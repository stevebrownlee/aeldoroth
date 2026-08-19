defmodule ClientTUI.E2EWSysTest do
  @moduledoc """
  E2E determinism over real WebSockets (plan 5 Task 10): Bandit serves
  Wire.Endpoint; two real `ClientTUI.Conn` clients (scripted test players,
  spec §11) drive declares. The live ledger must equal the pure `Run` path
  byte-for-byte, wire perceptions must equal the pure path's narration
  texts, and pause + process-restart + restore must continue
  deterministically (modulo `:dossier`).
  """

  use ExUnit.Case, async: false

  alias ClientTUI.Conn
  alias EngineCore.{Ledger, RunSup}
  alias EngineCore.Ledger.Writer
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  @moves ["north", "north", "south", "south"]

  test "live WS path produces the byte-identical ledger of the pure path" do
    port = start_bandit!()
    id = "e2e_ws_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> Session.stop(id); RunSup.stop_run(id) end)

    # Run A: pure path. Run B: live session, declares through two WS conns.
    # Lockstep order: thistle north, bramble north, advance; repeat south.
    {:ok, a} = Run.new(@yaml, 42, @pcs, routing: routing())
    {:ok, _pid} = Session.start_link(id, @yaml, 42, @pcs, routing: routing())
    {:ok, t} = conn(port, id, "pc_thistle")
    {:ok, b} = conn(port, id, "pc_bramble")

    a = ws_declare(a, t, "pc_thistle", "I head north")
    a = ws_declare(a, b, "pc_bramble", "I head north")
    {:ok, _, a} = Run.advance(a)
    {:ok, _} = Session.advance(id)

    a = ws_declare(a, t, "pc_thistle", "I head south")
    a = ws_declare(a, b, "pc_bramble", "I head south")
    {:ok, _, a} = Run.advance(a)
    {:ok, _} = Session.advance(id)

    assert :erlang.term_to_binary(Run.events(a)) ==
             :erlang.term_to_binary(Writer.events(id))

    # Wire perceptions equal the pure path's narration texts per pc (order kept).
    for pc <- ["pc_thistle", "pc_bramble"] do
      pure =
        Run.events(a)
        |> Enum.filter(&match?(%Ledger.Event{class: :narration, payload: %{agent_id: ^pc}}, &1))
        |> Enum.map(& &1.payload[:text])

      assert pure != []
      assert perceptions(pc, length(pure)) == pure
    end
  after
    stop_conns()
  end

  test "pause/resume across process restart mid-run" do
    id = "e2e_restart_#{:erlang.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "e2e_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn ->
      Session.stop(id)
      RunSup.stop_run(id)
      File.rm_rf!(dir)
    end)

    # Uninterrupted reference on the pure path: same four declares.
    {:ok, ref_run} = Run.new(@yaml, 42, @pcs, routing: routing())

    ref =
      Enum.reduce(@moves, ref_run, fn move, acc ->
        {:ok, _, acc2} = Run.declare(acc, "pc_thistle", "go #{move}")
        acc2
      end)

    # Live leg: two declares, pause, kill session + per-run processes, restore.
    {:ok, _pid} = Session.start_link(id, @yaml, 42, @pcs, routing: routing(), data_dir: dir)

    {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go north")
    {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go north")
    {:ok, %{dossiers: dossiers}} = Session.pause(id)
    assert map_size(dossiers) == 2

    :ok = Session.stop(id)
    :ok = RunSup.stop_run(id)

    # Fresh scripted queue for the continued session (adapter queue position
    # is per-session runtime state — session_test lesson).
    {:ok, _pid2} = Session.restore(id, dir, routing: leg2_routing())

    {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go south")
    {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go south")

    # Pause inserted :dossier events; their seqs shift later rows, so compare
    # content triples rather than binaries (session_test convention).
    content = fn evs -> Enum.map(evs, &{&1.tick, &1.class, &1.payload}) end
    restored = Writer.events(id) |> Enum.reject(&(&1.class == :dossier))
    assert content.(Run.events(ref)) == content.(restored)
  after
    stop_conns()
  end

  ## Helpers

  # One declare on each leg in lockstep: WS cast first, its reply awaited,
  # then the pure-path declare. Advances stay direct Session calls (plan).
  defp ws_declare(run, ws_pid, pc_id, text) do
    :ok = Conn.send_event(ws_pid, "declare_intent", %{"text" => text})
    assert_receive {:chan_reply, ^pc_id, _ref, :ok, %{"reply" => _}}, 5_000
    {:ok, _, run2} = Run.declare(run, pc_id, text)
    run2
  end

  # Each conn runs under a collector Task that forwards every server message
  # to the test process tagged with the pc_id — both conns share one mailbox,
  # attribution must stay exact.
  defp conn(port, run_id, pc_id) do
    parent = self()

    {:ok, collector} =
      Task.start(fn ->
        {:ok, pid} =
          Conn.start_link("ws://127.0.0.1:#{port}",
            run_id: run_id,
            character_id: pc_id,
            heartbeat_every: 60_000
          )

        send(parent, {:conn_up, pc_id, pid})
        forward(pc_id, parent)
      end)

    assert_receive {:conn_up, ^pc_id, pid}, 5_000
    put_collector(pc_id, collector)
    assert_receive {:chan_reply, ^pc_id, _ref, :ok, %{"state" => _}}, 5_000
    {:ok, pid}
  end

  defp forward(pc_id, parent) do
    receive do
      {:chan, topic, event, payload} ->
        send(parent, {:chan, pc_id, topic, event, payload})
        forward(pc_id, parent)

      {:chan_reply, ref, status, payload} ->
        send(parent, {:chan_reply, pc_id, ref, status, payload})
        forward(pc_id, parent)

      :stop ->
        :ok
    end
  end

  defp perceptions(pc_id, expected) do
    texts =
      for _ <- 1..expected do
        assert_receive {:chan, ^pc_id, _topic, "perception", %{"text" => t}}, 5_000
        t
      end

    refute_received {:chan, ^pc_id, _topic, "perception", _}
    texts
  end

  defp put_collector(pc_id, pid), do: Process.put({:e2e_conn, pc_id}, pid)

  defp stop_conns do
    for {{:e2e_conn, _pc}, collector} <- Process.get() do
      send(collector, :stop)
    end

    :ok
  end

  defp start_bandit! do
    port = 20_000 + rem(:erlang.unique_integer([:positive]), 20_000)

    case Bandit.start_link(plug: Wire.Endpoint, scheme: :http, port: port) do
      {:ok, pid} ->
        on_exit(fn ->
          try do
            GenServer.stop(pid, :normal)
          catch
            :exit, _ -> :ok
          end
        end)
        port

      {:error, {:eaddrinuse, _}} ->
        start_bandit!()
    end
  end

  defp routing do
    scripts = %{
      interpret: Enum.map(@moves, &move_json/1),
      salt: System.unique_integer()
    }

    %{interpret: %{adapter: Scripted, scripts: scripts}}
  end

  defp leg2_routing do
    scripts = %{
      interpret: Enum.map(["south", "south"], &move_json/1),
      salt: System.unique_integer()
    }

    %{interpret: %{adapter: Scripted, scripts: scripts}}
  end

  defp move_json(direction),
    do: ~s({"verb":"move","target_id":null,"params":{"direction":"#{direction}"}})
end
