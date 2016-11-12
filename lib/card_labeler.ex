defmodule CardLabeler do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(CardLabeler.WorkerSupervisor, []),
      worker(CardLabeler.WorkerConfiger, [])
    ]

    opts = [strategy: :rest_for_one, name: CardLabeler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
