defmodule ClientWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :client_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {ClientWeb.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:client_tui, in_umbrella: true},
      {:referee, in_umbrella: true},
      {:wire, in_umbrella: true},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
