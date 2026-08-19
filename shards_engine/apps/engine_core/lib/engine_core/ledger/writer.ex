defmodule EngineCore.Ledger.Writer do
  @moduledoc """
  The single append writer for one run (spec §12.1; pattern:
  append-only-ledger). The journal and ETS mirror are written only here.

  `append/2` validates seq continuity (first event seq 1, then contiguous
  ascending), journals to `data_dir/<run_id>.events` (4-byte big-endian
  length + `term_to_binary/1` per record, synced before reply), mirrors
  into the shared ETS replica, then notifies subscribers with
  `{:ledger_events, run_id, events}` in append order. Reads (`events/1`,
  `tail/2`, `last_seq/1`) hit ETS directly — no GenServer hop, so they
  survive writer restarts. Restart replays the journal into ETS.
  """

  use GenServer

  alias EngineCore.Ledger
  alias EngineCore.Ledger.Ets

  def child_spec({run_id, opts}) do
    %{id: {:writer, run_id}, start: {__MODULE__, :start_link, [run_id, opts]}, restart: :transient}
  end

  ## Client API

  @doc "Start the writer for `run_id`, named via `EngineCore.RunReg`."
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(run_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {run_id, opts},
      name: {:via, Registry, {EngineCore.RunReg, {:writer, run_id}}}
    )
  end

  @doc """
  Append events. First append must start at seq 1; events must be
  seq-contiguous ascending. `{:error, {:seq_gap, last, got}}` otherwise.
  """
  @spec append(String.t(), [Ledger.Event.t()]) ::
          :ok | {:error, {:seq_gap, integer(), integer()}} | {:error, :no_writer}
  def append(run_id, events) do
    case EngineCore.whereis_writer(run_id) do
      nil -> {:error, :no_writer}
      pid -> GenServer.call(pid, {:append, events})
    end
  end

  @doc "All events for `run_id` in seq order (ETS read; works without a live writer)."
  @spec events(String.t()) :: [Ledger.Event.t()]
  def events(run_id), do: read_range(run_id, 1, last_seq(run_id))

  @doc "Events with seq > `after_seq` (ETS read)."
  @spec tail(String.t(), integer()) :: [Ledger.Event.t()]
  def tail(run_id, after_seq), do: read_range(run_id, after_seq + 1, last_seq(run_id))

  @doc "Highest appended seq for `run_id` (0 when the ledger is empty)."
  @spec last_seq(String.t()) :: integer()
  def last_seq(run_id), do: :ets.lookup_element(Ets.table(), {run_id, Ets.sentinel()}, 2, 0)

  @doc "Monitor the caller; it receives `{:ledger_events, run_id, [event]}` casts in append order."
  @spec subscribe(String.t()) :: :ok | {:error, :no_writer}
  def subscribe(run_id) do
    case EngineCore.whereis_writer(run_id) do
      nil -> {:error, :no_writer}
      pid -> GenServer.call(pid, {:subscribe, self()})
    end
  end

  ## Server

  @impl true
  def init({run_id, opts}) do
    :ok = Ets.ensure()

    # Stale replica rows for this run (writer crash/restart) are replaced
    # by the journal replay below; the replica is never authoritative.
    :ets.select_delete(Ets.table(), [{{{run_id, :_}, :_}, [], [true]}])

    data_dir = Keyword.get(opts, :data_dir)
    {events, dev, path} = open_journal(run_id, data_dir)
    Enum.each(events, fn ev -> :ets.insert(Ets.table(), {{run_id, ev.seq}, ev}) end)

    last_seq = events |> List.last() |> Kernel.||(%{}) |> Map.get(:seq, 0)
    :ets.insert(Ets.table(), {{run_id, Ets.sentinel()}, last_seq})

    {:ok, %{run_id: run_id, last_seq: last_seq, subs: %{}, dev: dev, path: path}}
  end

  @impl true
  def handle_call({:append, []}, _from, st), do: {:reply, :ok, st}

  def handle_call({:append, events}, _from, st) do
    case validate(st.last_seq, events) do
      :ok ->
        journal!(events, st)

        Enum.each(events, fn ev ->
          :ets.insert(Ets.table(), {{st.run_id, ev.seq}, ev})
        end)

        last = events |> List.last() |> Map.fetch!(:seq)
        :ets.insert(Ets.table(), {{st.run_id, Ets.sentinel()}, last})

        Enum.each(st.subs, fn {_ref, pid} -> send(pid, {:ledger_events, st.run_id, events}) end)

        {:reply, :ok, %{st | last_seq: last}}

      {:error, _reason} = err ->
        {:reply, err, st}
    end
  end

  def handle_call({:subscribe, pid}, _from, st) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{st | subs: Map.put(st.subs, ref, pid)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, st),
    do: {:noreply, %{st | subs: Map.delete(st.subs, ref)}}

  @impl true
  def terminate(_reason, %{dev: dev}) when not is_nil(dev), do: File.close(dev)
  def terminate(_reason, _st), do: :ok

  ## Internals

  defp validate(last, [%Ledger.Event{seq: seq} | rest]) when seq == last + 1,
    do: validate(seq, rest)

  defp validate(last, [%Ledger.Event{seq: seq} | _]), do: {:error, {:seq_gap, last, seq}}

  defp validate(_last, []), do: :ok

  defp open_journal(_run_id, nil), do: {[], nil, nil}

  defp open_journal(run_id, data_dir) do
    File.mkdir_p!(data_dir)
    path = Path.join(data_dir, "#{run_id}.events")
    events = read_records(path)
    {:ok, dev} = File.open(path, [:append, :binary])
    {events, dev, path}
  end

  defp read_records(path) do
    case File.read(path) do
      {:ok, bin} -> decode_records(bin, [])
      _ -> []
    end
  end

  defp decode_records(<<len::big-integer-32, rest::binary>>, acc) when byte_size(rest) >= len do
    <<record::binary-size(^len), rest::binary>> = rest
    decode_records(rest, [:erlang.binary_to_term(record) | acc])
  end

  # Trailing partial record (crash mid-write) is dropped.
  defp decode_records(_bin, acc), do: Enum.reverse(acc)

  defp journal!(_events, %{dev: nil}), do: :ok

  defp journal!(events, %{dev: dev}) do
    bin =
      Enum.map_join(events, fn ev ->
        record = :erlang.term_to_binary(ev)
        <<byte_size(record)::big-integer-32, record::binary>>
      end)

    :ok = IO.binwrite(dev, bin)
    :ok = :file.sync(dev)
    :ok
  end

  defp read_range(_run_id, from, to) when from > to, do: []

  defp read_range(run_id, from, to) do
    # Seqs are validated contiguous, so per-seq lookup is exhaustive.
    Enum.flat_map(from..to//1, fn seq ->
      case :ets.lookup(Ets.table(), {run_id, seq}) do
        [{_key, event}] -> [event]
        [] -> []
      end
    end)
  end
end
