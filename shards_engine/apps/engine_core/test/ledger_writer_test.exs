defmodule EngineCore.LedgerWriterTest do
  @moduledoc """
  Per-run append writer (plan 5 Task 2): seq-continuity validation, ETS
  read replica that outlives the writer, ordered subscriber fanout with
  death-unsubscribe, durable journal with restart replay.
  """
  use ExUnit.Case, async: true
  alias EngineCore.Ledger
  alias EngineCore.Ledger.Writer
  alias EngineCore.RunSup

  defp run_id, do: "w#{:erlang.unique_integer([:positive, :monotonic])}"

  defp ev(seq), do: struct!(Ledger.Event, seq: seq, tick: seq, class: :world, payload: %{kind: :test, seq: seq})

  defp start_writer!(id, opts \\ []) do
    assert {:ok, _pid} = RunSup.ensure_writer(id, opts)
  end

  test "append assigns contiguous seq validation" do
    id = run_id()
    start_writer!(id)

    assert :ok = Writer.append(id, [ev(1), ev(2), ev(3)])
    assert {:error, {:seq_gap, 3, 5}} = Writer.append(id, [ev(5)])
    assert Writer.last_seq(id) == 3
  end

  test "events/tail read from ETS without the writer process" do
    id = run_id()
    start_writer!(id)
    :ok = Writer.append(id, [ev(1), ev(2), ev(3)])

    writer = EngineCore.whereis_writer(id)
    assert is_pid(writer)
    :ok = GenServer.stop(writer)
    # Registry name release is async to exit; wait for the cleanup.
    wait_until(fn -> assert EngineCore.whereis_writer(id) == nil end)

    assert [%Ledger.Event{} | _] = Writer.events(id)
    assert length(Writer.events(id)) == 3
    assert Writer.tail(id, 1) == [ev(2), ev(3)]
    assert Writer.last_seq(id) == 3
  end

  test "subscribers get tails in append order" do
    id = run_id()
    start_writer!(id)
    parent = self()

    sub =
      spawn_link(fn ->
        :ok = Writer.subscribe(id)
        send(parent, :subscribed)
        receive_all(id, parent)
      end)

    receive do
      :subscribed -> :ok
    after
      1000 -> flunk("subscriber never confirmed")
    end

    :ok = Writer.append(id, [ev(1)])
    :ok = Writer.append(id, [ev(2), ev(3)])

    assert_received {:sub_events, ^id, [e1]}
    assert e1.seq == 1
    assert_received {:sub_events, ^id, [e2, e3]}
    assert e2.seq == 2 and e3.seq == 3
    refute_received {:sub_events, _, _}
  end

  test "subscriber death unsubscribes" do
    id = run_id()
    start_writer!(id)
    parent = self()

    sub =
      spawn_link(fn ->
        :ok = Writer.subscribe(id)
        send(parent, :subscribed)
        Process.sleep(:infinity)
      end)

    receive do
      :subscribed -> :ok
    after
      1000 -> flunk("subscriber never confirmed")
    end

    Process.unlink(sub)
    Process.exit(sub, :kill)
    # let the DOWN reach the writer
    wait_until(fn -> assert Writer.append(id, [ev(1)]) == :ok end)
    assert Process.alive?(EngineCore.whereis_writer(id))
  end

  test "journal replay on restart" do
    id = run_id()
    dir = Path.join(System.tmp_dir!(), "writer_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    start_writer!(id, data_dir: dir)
    :ok = Writer.append(id, [ev(1), ev(2), ev(3)])
    :ok = GenServer.stop(EngineCore.whereis_writer(id))

    start_writer!(id, data_dir: dir)
    assert Writer.last_seq(id) == 3
    assert Writer.events(id) |> Enum.map(& &1.seq) == [1, 2, 3]

    # seq continuity continues from the replayed journal
    assert :ok = Writer.append(id, [ev(4)])
  end

  test "append is durable before reply" do
    id = run_id()
    dir = Path.join(System.tmp_dir!(), "writer_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    start_writer!(id, data_dir: dir)
    events = [ev(1), ev(2)]
    :ok = Writer.append(id, events)

    bin = File.read!(Path.join(dir, "#{id}.events"))
    Enum.each(events, fn e -> assert bin =~ :erlang.term_to_binary(e) end)
  end

  defp receive_all(id, parent) do
    receive do
      {:ledger_events, ^id, events} ->
        send(parent, {:sub_events, id, events})
        receive_all(id, parent)
    end
  end

  defp wait_until(fun) when is_function(fun, 0) do
    try do
      fun.()
    rescue
      _ -> Process.sleep(10) && wait_until(fun)
    end
  end
end
