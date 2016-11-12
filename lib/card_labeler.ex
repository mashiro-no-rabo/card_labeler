defmodule CardLabeler do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children =
      Enum.map(Application.get_env(:card_labeler, CardLabeler)[:worker_configs], fn config ->
        worker(CardLabeler.Worker, [config], restart: :transient)
      end)

    opts = [strategy: :one_for_one, name: CardLabeler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
