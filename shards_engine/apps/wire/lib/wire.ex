defmodule Wire do
  @moduledoc """
  The public wire surface of the Shards engine (spec §11, decision 24):
  a channels-only Phoenix endpoint speaking line-JSON over WebSocket.

  - `Wire.Socket` — run-scoped connect; PC vs spectate role
  - `Wire.Claims` — exclusive character claims per run
  - `Wire.Endpoint` — no router, no plugs; channels only
  """
end
