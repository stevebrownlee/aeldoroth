defmodule Wire.MixProject do
  use Mix.Project

  def project do
    [
      app: :wire,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:bandit, "~> 1.0"},
        {:jason, "~> 1.4"},
        {:phoenix, "~> 1.8"},
        {:engine_core, in_umbrella: true},
        {:referee, in_umbrella: true}
      ]
    ]
  end

  def application, do: [mod: {Wire.Application, []}]
end
