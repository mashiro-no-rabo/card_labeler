defmodule CardLabeler do
  use Application
  alias CardLabeler.ReposSupervisor

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Registry, [:unique, CardLabeler.Registry]),
      supervisor(ReposSupervisor, [])
    ]

    opts = [strategy: :rest_for_one, name: CardLabeler.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end
