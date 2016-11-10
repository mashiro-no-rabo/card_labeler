defmodule CardLabeler.Worker do
  use GenServer

  @interval Application.get_env(:card_labeler, CardLabeler.Worker)[:interval] * 1000

  defmodule State do
    defstruct [:repo, :project_id, :default_column_id, :close_column_id
               :last_update, :issues_table]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init({repo, project_id, default_column_id, close_column_id}) do
    issues_table = :etc.new(:issues, [:private])

    schedule_next_update()

    state = %State{repo: repo,
                   project_id: project_id,
                   default_column_id: default_column_id,
                   close_column_id: close_column_id,
                   issues_table: issues_table}
    {:ok, state}
  end

  def handle_info(:update, state) do
    this_update_time = DateTime.utc_now() |> DateTime.to_iso8601()

    # Step 1: Fetch all issues, since last update if available
    issues_resp = build_issues_url(state.repo, state.last_update) |> GitHub.get!()

    # Step 2: Fetch Project columns, save ids -> names

    # Step 3: Fetch each column's cards, filter out issues

    # Step 4: Assign correct labels

    schedule_next_update()
    {:noreply, %State{ state | last_update: this_update_time }}
  end
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_next_update() do
    Process.send_after(self(), :update, @interval)
  end

  defp build_issues_url(repo, nil), do: "/repos/#{state.repo}/issues?per_page=100"
  defp build_issues_url(repo, last_update), do: "/repos/#{state.repo}/issues?per_page=100&since=#{last_update}"
end
