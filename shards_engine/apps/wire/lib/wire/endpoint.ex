defmodule Wire.Endpoint do
  @moduledoc """
  Channels-only Phoenix endpoint (decision 24: the line-JSON WS protocol is
  the public contract). No router, no plugs, no HTML.
  """

  use Phoenix.Endpoint, otp_app: :wire

  # check_origin: false — the reference client is a terminal, not a browser;
  # the protocol is the contract (auth arrives per-run in connect params).
  socket "/socket", Wire.Socket,
    websocket: [timeout: 45_000, check_origin: false],
    longpoll: false
end
