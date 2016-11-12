defmodule CardLabeler do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(CardLabeler.Worker, [], restart: :transient)
    ]

    opts = [strategy: :simple_one_for_one, name: CardLabeler.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def work() do
    Enum.each(Application.get_env(:card_labeler, CardLabeler)[:worker_configs], fn config ->
      Supervisor.start_child(CardLabeler.Supervisor, [config])
    end)
  end
end
