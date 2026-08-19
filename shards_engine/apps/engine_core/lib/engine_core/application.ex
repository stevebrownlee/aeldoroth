defmodule EngineCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EngineCore.Ledger.Ets,
      {Registry, keys: :unique, name: EngineCore.RunReg},
      {DynamicSupervisor, name: EngineCore.RunSup}
    ]

    opts = [strategy: :one_for_one, name: EngineCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
