defmodule Referee.MixProject do
  use Mix.Project

  def project do
    [
      app: :referee,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:engine_core, in_umbrella: true},
        {:llm_gateway, in_umbrella: true}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
