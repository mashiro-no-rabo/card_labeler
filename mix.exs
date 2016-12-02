defmodule CardLabeler.Mixfile do
  use Mix.Project

  def project do
    [app: :card_labeler,
     version: "0.2.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger, :httpoison, :crypto, :sasl],
     mod: {CardLabeler, []}]
  end

  defp deps do
    [
      {:httpoison, "~> 0.10.0"},
      {:poison, "~> 3.0"},
    ]
  end
end
