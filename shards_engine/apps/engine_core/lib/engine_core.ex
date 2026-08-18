defmodule EngineCore do
  @moduledoc """
  Deterministic, zero-LLM heart of the Shards agent engine.

  World state is `fold(ledger)`; every mutation is a data event; dice come
  only from `EngineCore.Dice` with RNG state threaded explicitly. No
  wall-clock anywhere — ticks are monotonically increasing integers.
  """
end
