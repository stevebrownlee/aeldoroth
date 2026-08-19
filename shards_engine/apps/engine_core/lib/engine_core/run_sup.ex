defmodule EngineCore.RunSup do
  @moduledoc """
  Per-run supervision helpers over the `EngineCore.RunSup`
  DynamicSupervisor (spec §12.1). Starts are idempotent via the
  `EngineCore.RunReg` Registry: writer first, then the world fold.
  """

  alias EngineCore.Ledger.Writer

  @doc """
  Idempotently start the ledger writer for `run_id`. Registry name release
  is asynchronous to process exit, so a just-stopped writer may still be
  registered — we poll until the entry is gone or a live pid emerges.
  """
  @spec ensure_writer(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_writer(run_id, opts \\ []) do
    case EngineCore.whereis_writer(run_id) do
      nil ->
        case DynamicSupervisor.start_child(EngineCore.RunSup, {Writer, {run_id, opts}}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, {:already_registered, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          Process.sleep(1)
          ensure_writer(run_id, opts)
        end
    end
  end

  @doc "Stop every per-run process (writer; world server once Task 3 adds it). Test teardown."
  @spec stop_run(String.t()) :: :ok
  def stop_run(run_id) do
    Enum.each([:world, :writer], fn kind ->
      case Registry.lookup(EngineCore.RunReg, {kind, run_id}) do
        [{pid, _}] ->
          Process.unlink(pid)
          GenServer.stop(pid, :normal)

        [] ->
          :ok
      end
    end)

    :ok
  end
end
