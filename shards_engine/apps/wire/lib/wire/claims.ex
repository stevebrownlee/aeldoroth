defmodule Wire.Claims do
  @moduledoc """
  Exclusive per-PC claims for one run (spec §11): a character connection
  holds its PC until it releases (disconnect terminates the claim).

  The claim is owned by the calling process — channels claim from `join/3`,
  so channel death (socket close, crash) releases the character. Release is
  idempotent.
  """

  @registry Wire.ClaimsReg

  @spec claim(String.t(), String.t()) :: :ok | {:error, {:already_claimed, pid()}}
  def claim(run_id, pc_id) do
    case Registry.register(@registry, {run_id, pc_id}, self()) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, pid}} -> {:error, {:already_claimed, pid}}
    end
  end

  @spec release(String.t(), String.t()) :: :ok
  def release(run_id, pc_id) do
    Registry.unregister(@registry, {run_id, pc_id})
    :ok
  end
end
