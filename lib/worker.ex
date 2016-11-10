defmodule CardLabeler.Worker do
  use GenServer

  @interval Application.get_env(:card_labeler, CardLabeler.Worker)[:interval] * 1000

  defmodule State do
    defstruct [:repo, :project_id, :default_column_id, :last_update]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init({repo, project_id, default_column_id}) do
    schedule_next_update()

    state = %State{repo: repo, project_id: project_id, default_column_id: default_column_id}
    {:ok, state}
  end

  def handle_info(:update, state) do
    current_time = DateTime.utc_now() |> DateTime.to_iso8601()

    # Step 1: Fetch all issues, since last update if available


    # Step 2: Fetch Project columns, save ids -> names

    schedule_next_update()
  end

  def handle_info(_, state), do: {:noreply, state}


  defp schedule_next_update() do
    Process.send_after(self(), :update, @interval)
  end
end
