defmodule EngineCore.Ledger.Ets do
  @moduledoc """
  Owner process for the shared ETS read replica of the ledger.

  One named public `:ordered_set` table (`EngineCore.Ledger.Ets`) for every
  run; writers insert, anyone reads. Key `{run_id, seq}`, value
  `Ledger.Event.t()`, plus a `{run_id, :"$last_seq"}` sentinel row. The table
  outlives any single writer, so reads survive writer restarts.
  """

  use GenServer

  @table __MODULE__
  @sentinel :"$last_seq"

  def table, do: @table
  def sentinel, do: @sentinel

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Create the replica table if it does not exist (race-safe; writers call this defensively)."
  @spec ensure() :: :ok
  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :ordered_set, :public, read_concurrency: true])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  @impl true
  def init(:ok) do
    ensure()
    {:ok, :ok}
  end
end
