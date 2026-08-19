defmodule EngineCore do
  @moduledoc """
  Deterministic, zero-LLM heart of the Shards agent engine.

  World state is `fold(ledger)`; every mutation is a data event; dice come
  only from `EngineCore.Dice` with RNG state threaded explicitly. No
  wall-clock anywhere — ticks are monotonically increasing integers.
  """
  # Convenience process lookups through the `EngineCore.RunReg` Registry.

  @doc "Pid of the ledger writer for `run_id`, or nil."
  @spec whereis_writer(String.t()) :: pid() | nil
  def whereis_writer(run_id) do
    case Registry.lookup(EngineCore.RunReg, {:writer, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
