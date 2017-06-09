defmodule CardLabeler.RepoSup do
  use Supervisor
  alias CardLabeler.Repo.AgentStorage
  alias CardLabeler.Repo.Tracker

  def start_link(repo_config) do
    Supervisor.start_link(__MODULE__, repo_config, [])
  end

  def init(repo_config) do
    children = [
      worker(AgentStorage, [repo_config]),
      worker(Tracker, [repo_config]),
    ]

    supervise(children, strategy: :one_for_all)
  end
end
