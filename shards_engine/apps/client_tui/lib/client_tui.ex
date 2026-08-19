defmodule ClientTUI do
  @moduledoc """
  Terminal reference client (spec §11; decision 24): a thin WebSockex line
  speaking the documented wire protocol (`apps/wire/PROTOCOL.md`). Zero
  authority — every input re-enters the referee pipeline server-side.
  """
end
