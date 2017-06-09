defmodule CardLabeler.ReposSupervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children =
      Enum.map(
        Application.get_env(:card_labeler, __MODULE__)[:repo_configs],
        fn config ->
          supervisor(CardLabeler.RepoSup, [config])
        end
      )

    supervise(children, strategy: :one_for_one, name: __MODULE__)
  end
end
