defmodule CardLabeler.Worker do
  use GenServer
  alias CardLabeler.GitHub

  @interval Application.get_env(:card_labeler, CardLabeler.Worker)[:interval] * 1000

  defmodule State do
    defstruct [:repo, :project_id, :last_update,
               :columns,
               :new_col, :close_col]
  end

  defmodule Issue do
    # issue["number"] as key
    defstruct [:id, :state, :labels, :column, :card_id]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init({repo, project_id, new_col, close_col}) do
    GitHub.start

    # TODO: This does not work for multiple config
    Agent.start_link(&Map.new/0, name: :issues)

    # Assuming Project columns to be static
    columns =
      GitHub.get!("/projects/#{project_id}/columns")
      |> Map.get(:body)
      |> Enum.map(fn column -> {column["id"], column["name"]} end) # TODO: change to id->name, use Enum.find
      |> Enum.into(%{})

    state = %State{repo: repo,
                   project_id: project_id,
                   columns: columns,
                   new_col: new_col,
                   close_col: close_col,
                  }

    schedule_next_update(5)

    {:ok, state}
  end

  def handle_info(:update, state) do
    this_update_time = DateTime.utc_now() |> DateTime.to_iso8601()

    # Step 1: Fetch all Issues, since last_update if applicable
    updated_issues = fetch_updated_issues(state.repo, state.last_update, 1, [])

    # Step 2: Update each column's issues
    state.columns
    |> Enum.each(fn {id, _name} ->
      update_issues_in_column(id)
    end)

    # Step 3: Move closed issues to close_col, add new issues as cards
    updated_issues
    |> Enum.each(fn issue_num ->
      issue_data = Agent.get(:issues, &(Map.get(&1, issue_num)))
      if issue_data.state == "closed" do
        if issue_data.card_id != nil and issue_data.column != state.close_col do
          GitHub.post!("/projects/columns/cards/#{issue_data.card_id}/moves",
            "{\"position\": \"bottom\", \"column_id\": #{state.close_col}}")

          Agent.update(:issues, &(Map.update!(&1, issue_num, fn issue_data -> %Issue{ issue_data | column: state.close_col } end)))
        end
      else
        if issue_data.card_id == nil do
          {card_id, col} = add_issue_card(issue_data.id, issue_data.labels, state.columns, state.new_col)

          Agent.update(:issues, &(Map.update!(&1, issue_num, fn issue_data -> %Issue{ issue_data | card_id: card_id, column: col } end)))
        end
      end
    end)

    # Step 4: Assign correct label
    wrong_labels_for_column =
      Enum.map(state.columns, fn {id, name} ->
        wrong_labels =
          Map.keys(state.columns)
          |> List.delete(name)

        {id, wrong_labels}
      end)
      |> Enum.into(%{})

    Agent.get(:issues, &(&1))
    |> Enum.each(fn {issue_num, issue_data} ->
      if issue_data.column != nil do
        wrong_labels =
          Enum.filter(issue_data.labels, fn label_name ->
            Map.get(wrong_labels_for_column, issue_data.column)
            |> Enum.member?(label_name)
          end)

        Enum.each(wrong_labels, &(GitHub.delete!("/repos/#{state.repo}/issues/#{issue_num}/labels/#{&1}")))
        Agent.update(:issues, &(Map.update!(&1, issue_num, fn issue_data -> %Issue{ issue_data | labels: issue_data.labels -- wrong_labels } end)))
      end
    end)

    # Step 5: Close any open issue in close_col
    Agent.get(:issues, &(&1))
    |> Enum.each(fn {issue_num, issue_data} ->
      if issue_data.column == state.close_col and issue_data.state == "open" do
        GitHub.patch!("/repos/#{state.repo}/issues/#{issue_num}", "{\"state\":\"closed\"}")
      end
    end)

    schedule_next_update()
    {:noreply, %State{ state | last_update: this_update_time }}
  end
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_next_update(time \\ @interval) do
    Process.send_after(self(), :update, time)
  end

  defp build_issues_url(repo, nil, page), do: "/repos/#{repo}/issues?per_page=100&page=#{page}&state=all"
  defp build_issues_url(repo, last_update, page), do: "/repos/#{repo}/issues?per_page=100&page=#{page}&state=all&since=#{last_update}"

  defp has_next_page?(response), do: response.headers |> Map.get("Link", "") |> String.contains?("rel=\"next\"")

  defp fetch_updated_issues(repo, last_update, page, acc) do
    resp = build_issues_url(repo, last_update, page) |> GitHub.get!()

    Enum.each(resp.body, fn issue ->
      label_names = Enum.map(issue["labels"], fn label -> label["name"] end)

      Agent.update(:issues, fn issues ->
        Map.update(issues, issue["number"],
          %Issue{id: issue["id"], state: issue["state"], labels: label_names },
          fn issue_data ->
            %Issue{ issue_data | state: issue["state"], labels: label_names }
          end)
      end)
    end)

    updated_issues = Enum.map(resp.body, fn issue -> issue["number"] end)
    new_acc = acc ++ updated_issues

    if has_next_page?(resp) do
      fetch_updated_issues(repo, last_update, page + 1, new_acc)
    else
      new_acc
    end
  end

  defp update_issues_in_column(column_id) do
    GitHub.get!("/projects/columns/#{column_id}/cards")
    |> Map.get(:body)
    |> Enum.filter_map(
    fn card ->
      Map.has_key?(card, "content_url") and String.contains?(card["content_url"], "/issues/")
    end,
    fn card ->
      issue_num = card["content_url"] |> String.split("/") |> List.last |> String.to_integer
      Agent.update(:issues, fn issues ->
        Map.update(issues, issue_num, %Issue{}, fn issue_data ->
          %Issue{ issue_data | column: column_id, card_id: card["id"]}
        end)
      end)
    end)
  end

  defp add_issue_card(issue_id, [], _columns, new_col) do
    card_id =
      GitHub.post!("/projects/columns/#{new_col}/cards", "{\"content_id\":#{issue_id},\"content_type\":\"Issue\"}")
      |> Map.get(:body)
      |> Map.get("id")

    {card_id, new_col}
  end
  defp add_issue_card(issue_id, [label_name | rest_labels], columns, new_col) do
    {col, _name} = Enum.find(columns, {nil, nil}, fn {_id, name} -> name == label_name end)

    if col != nil do
      card_id =
        GitHub.post!("/projects/columns/#{col}/cards", "{\"content_id\":#{issue_id},\"content_type\":\"Issue\"}")
        |> Map.get(:body)
        |> Map.get("id")

      {card_id, col}
    else
      add_issue_card(issue_id, rest_labels, columns, new_col)
    end
  end
end
