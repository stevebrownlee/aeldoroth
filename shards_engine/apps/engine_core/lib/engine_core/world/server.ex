defmodule EngineCore.World.Server do
  @moduledoc """
  Authoritative world fold for one run (spec §12.1): a GenServer holding
  `fold(ledger)` and advancing it off ledger-writer tails. Reads are cheap
  `GenServer.call`s served from the cached snapshot — they never join the
  writer's append path (plan 5 Task 3).
  """

  alias EngineCore.{Fold, Ledger, World}
  alias EngineCore.Ledger.Writer

  use GenServer

  defstruct [:run_id, :world, :last_seq]

  @doc "Start under `EngineCore.RunSup`. `world` is the run's seed state."
  @spec start_link({String.t(), World.t()}) :: GenServer.on_start()
  def start_link({run_id, %World{} = world}) do
    GenServer.start_link(__MODULE__, {run_id, world},
      name: {:via, Registry, {EngineCore.RunReg, {:world, run_id}}}
    )
  end

  @doc "Current world snapshot (cached fold)."
  @spec snapshot(String.t()) :: World.t()
  def snapshot(run_id) do
    GenServer.call(via(run_id), :snapshot)
  end

  @doc "Boundary states as `%{id => %{state, last_trigger_tick}}`."
  @spec boundaries(String.t()) :: %{String.t() => map()}
  def boundaries(run_id) do
    Map.new(snapshot(run_id).boundaries, fn {id, b} ->
      {id, %{state: b.state, last_trigger_tick: b.last_trigger_tick}}
    end)
  end

  @impl true
  def init({run_id, %World{} = world}) do
    # Catch up with anything already in the ledger, then follow the tail.
    existing = Writer.events(run_id)
    state = %__MODULE__{run_id: run_id, world: Fold.fold(world, existing), last_seq: 0}
    state = %{state | last_seq: last_seq(state.world, existing)}
    :ok = Writer.subscribe(run_id)
    {:ok, state}
  end

  @impl true
  def handle_info({:ledger_events, run_id, [%Ledger.Event{} | _] = events}, %__MODULE__{} = st)
      when run_id == st.run_id do
    new = Enum.reject(events, &(&1.seq <= st.last_seq))
    {:noreply, %{st | world: Fold.fold(st.world, new), last_seq: max_seq(st.last_seq, new)}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, st), do: {:noreply, st}

  def handle_info(_other, st), do: {:noreply, st}

  @impl true
  def handle_call(:snapshot, _from, st), do: {:reply, st.world, st}

  ## Internals

  defp via(run_id), do: {:via, Registry, {EngineCore.RunReg, {:world, run_id}}}

  defp last_seq(_world, []), do: 0
  defp last_seq(_world, events), do: events |> List.last() |> Map.fetch!(:seq)

  defp max_seq(prev, []), do: prev
  defp max_seq(prev, events), do: max(prev, events |> List.last() |> Map.fetch!(:seq))
end
