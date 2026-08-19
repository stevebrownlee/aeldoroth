defmodule Wire.Endpoint do
  @moduledoc """
  Channels-only Phoenix endpoint (decision 24: the line-JSON WS protocol is
  the public contract). No router, no plugs, no HTML.
  """

  use Phoenix.Endpoint, otp_app: :wire

  socket "/socket", Wire.Socket,
    websocket: [timeout: 45_000],
    longpoll: false
end
