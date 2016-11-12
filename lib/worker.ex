defmodule CardLabeler.Worker do
  use GenServer
  alias CardLabeler.GitHub

  @interval Application.get_env(:card_labeler, CardLabeler.Worker)[:interval] * 1000

  defmodule State do
    defstruct [:repo, :project_id, :default_column_id, :close_column_id,
               :last_update, :issues_table]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init({repo, project_id, default_column_id, close_column_id}) do
    GitHub.start

    issues_table = :ets.new(:issues, [])

    schedule_next_update(5)

    state = %State{repo: repo,
                   project_id: project_id,
                   default_column_id: default_column_id,
                   close_column_id: close_column_id,
                   issues_table: issues_table}
    {:ok, state}
  end

  def handle_info(:update, state) do
    this_update_time = DateTime.utc_now() |> DateTime.to_iso8601()

    # Step 1: Fetch all Issues, since last update if available
    # Be ware issue["id"] is not the number in URI you normally see, that's issue["number"]
    issues_resp = build_issues_url(state.repo, state.last_update) |> GitHub.get!()

    Enum.each(issues_resp.body, &(save_issue_labels(state.issues_table, &1)))
    # only care about open issues
    updated_issue_ids = Enum.filter_map(issues_resp.body, fn issue -> issue["state"] == "open" end, fn issue -> issue["number"] end)

    # Step 2: Fetch Project columns, then fetch all cards for each column
    columns_resp = GitHub.get!("/projects/#{state.project_id}/columns")
    column_name_to_ids = Enum.map(columns_resp.body, fn column -> {column["name"], column["id"]} end) |> Enum.into(%{})

    # Step 3: Fetch each column's cards, filter out Issues, save issue_id -> column_name
    issues_columns =
      Enum.flat_map(columns_resp.body, &get_column_cards/1)
      |> Enum.into(%{})

    # Step 4: Move new Issues into correct column or the default column
    # Do this first, because if there's a new Issue with 2 labels in column_names
    # We pick up whatever comes first and add it into that column
    # Then rely on next step to fix it
    updated_issue_ids
    |> Enum.filter( fn issue_id ->
      not Map.has_key?(issues_columns, issue_id)
    end)
    |> Enum.each( fn issue_id ->
      {_, issue_labels} = :ets.lookup(state.issues_table, issue_id) |> List.first
      add_to_found_column_or_default(issue_id, state.default_column_id, issue_labels, nil, column_name_to_ids)
    end)

    # Step 4.5: Fetch each column's cards again
    issues_columns =
      Enum.flat_map(columns_resp.body, &get_column_cards/1)
      |> Enum.into(%{})

    # Step 5: Assign correct labels
    Enum.each(issues_columns, fn {issue_id, column_name} ->
      # Remove labels if this issue has a label same as another column's name
      remove_wrong_labels(state.issues_table, state.repo, issue_id, Map.delete(column_name_to_ids, column_name) |> Map.to_list)

      # Set correct label if not already present
      unless issue_has_label?(state.issues_table, issue_id, column_name) do
        GitHub.post!("/repos/#{state.repo}/issues/#{issue_id}/labels", "[\"#{column_name}\"]")
      end
    end)

    # Step 6: Close Issues in closed_column
    issues_columns
    |> Enum.each( fn {issue_id, column_name} ->
      if column_name_to_ids[column_name] == state.close_column_id do
        GitHub.patch!("/repos/#{state.repo}/issues/#{issue_id}", "{\"state\":\"closed\"}")
      end
    end)

    schedule_next_update()
    {:noreply, %State{ state | last_update: this_update_time }}
  end
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_next_update(time \\ @interval) do
    Process.send_after(self(), :update, time)
  end

  defp build_issues_url(repo, nil), do: "/repos/#{repo}/issues?per_page=100&state=all"
  defp build_issues_url(repo, last_update), do: "/repos/#{repo}/issues?per_page=100&state=all&since=#{last_update}"

  defp save_issue_labels(table_id, issue) do
    issue_id = issue["number"]
    label_names = Enum.map(issue["labels"], fn label -> label["name"] end)
    :ets.insert(table_id, {issue_id, label_names})
  end

  # Returns [{id, name}, {id, name}, ...]
  defp get_column_cards(column) do
    cards_resp = GitHub.get!("/projects/columns/#{column["id"]}/cards")

    Enum.filter_map(cards_resp.body,
      fn card ->
        Map.has_key?(card, "content_url") and String.contains?(card["content_url"], "/issues/")
      end,
      fn card ->
        issue_id = card["content_url"] |> String.split("/") |> List.last |> String.to_integer
        {issue_id, column["name"]}
      end)
  end

  defp issue_has_label?(table_id, issue_id, label_name) do
    {_, issue_labels} = :ets.lookup(table_id, issue_id) |> List.first
    Enum.member?(issue_labels, label_name)
  end

  defp remove_wrong_labels(_table_id, _repo, _issue_id, []), do: nil
  defp remove_wrong_labels(table_id, repo, issue_id, [{label_name, _label_id} | rest]) do
    if issue_has_label?(table_id, issue_id, label_name) do
      GitHub.delete!("/repos/#{repo}/issues/#{issue_id}/labels/#{label_name}")
    end
    remove_wrong_labels(table_id, repo, issue_id, rest)
  end

  # issue_id, default_column_id, issue_labels, found_label, column_name_to_ids
  defp add_to_found_column_or_default(issue_id, default_column_id, [], nil, _) do
    GitHub.post!("/projects/columns/#{default_column_id}/cards", "{\"content_id\":#{issue_id},\"content_type\":\"Issue\"}")
  end
  defp add_to_found_column_or_default(issue_id, default_column_id, [label_name | rest], _, column_name_to_ids) do
    if Map.has_key?(column_name_to_ids, label_name) do
      column_id = column_name_to_ids[label_name]
      GitHub.post!("/projects/columns/#{column_id}/cards", "{\"content_id\":#{issue_id},\"content_type\":\"Issue\"}")
    else
      add_to_found_column_or_default(issue_id, default_column_id, rest, nil, column_name_to_ids)
    end
  end
end
