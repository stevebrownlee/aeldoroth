defmodule ClientWeb.Application do
  @moduledoc """
  ClientWeb supervision (spec §12.1): PubSub for LiveView + the dual-socket
  endpoint (`/live` for the UI, `/socket` re-serving `Wire.Socket`). The
  endpoint runs `server: false` — tests and the serve script boot Bandit.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: ClientWeb.PubSub},
      ClientWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClientWeb.Supervisor)
  end
end
