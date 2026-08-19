defmodule Wire.Application do
  @moduledoc """
  Wire supervision (spec §12.1): PubSub for channel fanout, the claims
  registry, and the channels-only Phoenix endpoint (`server: false` by
  default — the endpoint boots for tests and embedded use).
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Wire.PubSub},
      {Registry, keys: :unique, name: Wire.ClaimsReg},
      Wire.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Wire.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Wire.Endpoint.config_change(changed, removed)
    :ok
  end
end
