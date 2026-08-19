defmodule Agents.Application do
  @moduledoc "One Registry + one DynamicSupervisor for tier-3 brains (spec 12.1)."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Agents.Registry},
      {DynamicSupervisor, name: Agents.DynamicSup}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: Agents.Supervisor)
  end
end
