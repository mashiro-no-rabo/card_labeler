defmodule CardLabeler.WorkerConfiger do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Enum.each(Application.get_env(:card_labeler, CardLabeler)[:worker_configs], fn config ->
      Supervisor.start_child(CardLabeler.WorkerSupervisor, [config])
    end)

    {:ok, :ok}
  end
end
