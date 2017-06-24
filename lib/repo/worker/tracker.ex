defmodule CardLabeler.Repo.Tracker do
  @behaviour :gen_statem

  alias CardLabeler.Names
  alias CardLabeler.GitHubV3, as: GitHub
  alias CardLabeler.Repo.AgentStorage, as: Storage
  alias CardLabeler.Models.IssueCard

  require Logger

  @interval :timer.seconds(Application.get_env(:card_labeler, CardLabeler.Worker)[:interval])

  defmodule Data do
    defstruct [
      :repo, :project_id, :new_col, :close_col,
      :last_update,
      :columns, :wrong_labels_for_column,
    ]
  end

  ## APIs
  def start_link({repo, _, _, _} = config) do
    :gen_statem.start_link(Names.repo_tracker(repo), __MODULE__, config, [])
  end

  def callback_mode, do: [:state_functions, :state_enter]

  ## Callbacks
  def init({repo, project_id, new_col, close_col}) do
    data = %Data{
      repo: repo,
      project_id: project_id,
      new_col: new_col,
      close_col: close_col,
    }

    {:ok, :preparing, data}
  end

  ## States

  @doc """
  Assuming columns are static, get a column_id -> name map before starting real work.
  """
  def preparing(:enter, _, data) do
    Logger.debug("preparing..")
    columns = GitHub.get_columns(data.project_id)

    unless Map.has_key?(columns, data.new_col),
      do: raise("#{data.new_col} is not a column of project #{data.project_id} of repo #{data.repo}")

    unless Map.has_key?(columns, data.close_col),
      do: raise("#{data.close_col} is not a column of project #{data.project_id} of repo #{data.repo}")

    wrong_labels_for_column =
      Enum.map(columns, fn {id, name} ->
        {id, Map.values(columns) |> List.delete(name)}
      end)
      |> Enum.into(%{})

    Logger.debug("prepared")
    Process.send(self(), :prepared, [])
    {:keep_state, %Data{ data | columns: columns, wrong_labels_for_column: wrong_labels_for_column }}
  end
  def preparing(:info, :prepared, data), do: {:next_state, :resting, data}

  @doc """
  Trigger an immediate update if entering from `:preparing` state, or schedule it if
  entering from `:updating`.
  """
  def resting(:enter, :preparing, data) do
    Logger.debug("preparing -> resting")
    schedule_next_track(5)
    {:keep_state, data}
  end
  def resting(:enter, :updating, data) do
    Logger.debug("updating -> resting")
    schedule_next_track()
    {:keep_state, data}
  end
  def resting(:info, :track, data), do: {:next_state, :tracking, data}

  @doc """
  Fetch updated issues and card movements, and compute how to update them.
  """
  def tracking(:enter, :resting, data) do
    Logger.debug("resting -> tracking")
    this_update_time = DateTime.utc_now() |> DateTime.to_iso8601()

    # Fetch all Issues, since last_update if applicable
    updated_issues = GitHub.get_issues(data.repo, data.last_update)
    Logger.debug("updated_issues fetched: #{length(updated_issues)}")

    Enum.each(updated_issues, fn issue ->
      label_names = Enum.map(issue["labels"], fn label -> label["name"] end)

      Storage.update(data.repo, issue["number"],
        %IssueCard{id: issue["id"], state: issue["state"], labels: label_names },
        fn issue_card ->
          %IssueCard{ issue_card | state: issue["state"], labels: label_names }
        end)
    end)

    # Update each column's issues
    Enum.each(data.columns, fn {col_id, _name} ->
      GitHub.get_cards(col_id)
      |> Enum.each(fn card ->
        issue_num = card["content_url"] |> String.split("/") |> List.last |> String.to_integer

        Storage.update(data.repo, issue_num,
          %IssueCard{ column: col_id, card_id: card["id"] },
          fn issue_card ->
            %IssueCard{ issue_card | column: col_id, card_id: card["id"]}
          end)
      end)
    end)
    Logger.debug("cards fetched")

    # Move closed issues to close_col, add new issues as cards
    updated_issues
    |> Enum.map(fn issue -> issue["number"] end)
    |> Enum.each(fn issue_num ->
      issue_card = Storage.get(data.repo, issue_num)

      if issue_card.state == "closed" do
        if issue_card.card_id != nil and issue_card.column != data.close_col do
          GitHub.move_card(
            issue_card.card_id,
            data.close_col
          )

          Storage.update!(data.repo, issue_num,
            fn issue_card -> %IssueCard{ issue_card | column: data.close_col } end
          )
        end
      else
        if issue_card.card_id == nil do
          {col_id, _name} = Enum.find(data.columns,
            {data.new_col, nil},
            fn {_col_id, name} -> Enum.member?(issue_card.labels, name) end
          )
          card_id = GitHub.add_card(col_id, issue_card.id)

          Storage.update!(data.repo, issue_num,
            fn issue_card -> %IssueCard{ issue_card | card_id: card_id, column: col_id } end
          )
        end
      end
    end)
    Logger.debug("move/add card done")

    # Maintain correct labels
    Storage.get_all(data.repo)
    |> Enum.each(fn {issue_num, issue_card} ->
      if issue_card.column != nil do
        wrong_labels =
          Enum.filter(issue_card.labels, fn label_name ->
            Map.get(data.wrong_labels_for_column, issue_card.column)
            |> Enum.member?(label_name)
          end)

        Enum.each(wrong_labels, &(GitHub.remove_label(data.repo, issue_num, &1)))

        Storage.update!(data.repo, issue_num,
          fn issue_card -> %IssueCard{ issue_card | labels: issue_card.labels -- wrong_labels } end
        )

        correct_label = Map.get(data.columns, issue_card.column)
        unless Enum.member?(issue_card.labels, correct_label) do
          GitHub.add_label(data.repo, issue_num, correct_label)

          Storage.update!(data.repo, issue_num,
            fn issue_card -> %IssueCard{ issue_card | labels: [correct_label | issue_card.labels] } end
          )
        end
      end
    end)
    Logger.debug("labels corrected")

    Logger.debug("tracked")
    Process.send(self(), :tracked, [])
    {:keep_state, %Data{ data | last_update: this_update_time }}
  end
  def tracking(:info, :tracked, data), do: {:next_state, :updating, data}

  @doc """
  Spawn tasks to update issues and cards, then go back to `:resting` state.
  """
  def updating(:enter, :tracking, data) do
    Logger.debug("tracking -> updating")
    # Close any open issue in close_col
    Storage.get_all(data.repo)
    |> Enum.each(fn {issue_num, issue_card} ->
      if issue_card.column == data.close_col and issue_card.state == "open" do
        GitHub.close_issue(data.repo, issue_num)
      end
    end)

    Logger.debug("updated")
    Process.send(self(), :updated, [])
    {:keep_state, data}
  end
  def updating(:info, :updated, data), do: {:next_state, :resting, data}

  def terminate(_, _, _), do: :void
  def code_change(_, state, data, _), do: {:ok, state, data}

  ## Private Functions
  defp schedule_next_track(time \\ @interval) do
    Process.send_after(self(), :track, time)
  end

end
