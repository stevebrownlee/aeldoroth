defmodule ClientWeb.Endpoint do
  @moduledoc """
  One endpoint, two sockets, two trust zones (plan 7):

  - `/live` — LiveView socket for the UI surfaces.
  - `/socket` — the wire app's `Wire.Socket`, re-served verbatim so player
    LiveViews connect through `ClientTUI.Conn` on loopback. One port,
    zero changes to `apps/wire`.

  Player surfaces never touch engine modules; host surfaces
  (Home/GM console) call `Referee.Run.Session` directly as the trusted
  engine console.
  """

  use Phoenix.Endpoint, otp_app: :client_web

  @session_options [
    store: :cookie,
    key: "_client_web_session",
    signing_salt: "clientweb_cookie_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  # Mirrors Wire.Endpoint exactly: the protocol is the contract.
  socket "/socket", Wire.Socket,
    websocket: [timeout: 45_000, check_origin: false],
    longpoll: false

  plug Plug.Static,
    at: "/assets",
    from: {:client_web, "static/assets"},
    gzip: false,
    only: ~w(phoenix.min.js phoenix_live_view.min.js)

  plug Plug.RequestId
  plug Plug.Session, @session_options
  plug ClientWeb.Router
end
