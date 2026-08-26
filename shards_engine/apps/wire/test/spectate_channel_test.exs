defmodule Wire.SpectateChannelTest do
  @moduledoc """
  SpectateChannel (plan 5 Task 8): the GM/observer surface. Join snapshot
  carries tick/boundaries/spend/tail; tails stream as JSON-safe projections
  (Wire.JSONSafe — structs and opaque binaries never cross a real socket);
  pause/resume/spend map to Session calls.
  """
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest
  @endpoint Wire.Endpoint

  alias EngineCore.RunSup
  alias EngineCore.Ledger
  alias EngineCore.Ledger.Writer
  alias EngineCore.World.Server
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  setup ctx do
    id = "spec_#{ctx.test}_#{:erlang.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "spectate_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn ->
      File.rm_rf!(dir)
      RunSup.stop_run(id)
    end)
    {:ok, run_id: id}
  end

  test "join snapshot has tick, boundaries, spend, tail", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})

    assert {:ok, %{tick: tick, boundaries: boundaries, spend: spend, tail: tail, awaiting: awaiting, active_agents: active_agents}, _chan} =
             join(socket, "spectate:#{id}", %{}) 

    assert is_integer(tick)
    assert is_map(boundaries) and map_size(boundaries) > 0
    assert is_map(spend) and Map.has_key?(spend, :total)
    assert length(tail) <= 50
    assert active_agents == []

    assert length(awaiting) == 2
    assert Enum.all?(awaiting, &(&1.seated == false))
    assert %{
             "pc_thistle" => %{name: "Thistle"},
             "pc_bramble" => %{name: "Bramble"}
           } = Map.new(awaiting, fn pc -> {pc.id, pc} end)

    # Real sockets serialize to JSON (the crash this pins: agent_added's
    # Agent struct and the prefs md5 digest are not JSON-safe terms).
    assert {:ok, _} = Jason.encode(%{tick: tick, boundaries: boundaries, spend: spend, tail: tail, awaiting: awaiting, active_agents: active_agents})

    # Tail entries are JSON-shaped projections: string keys, plain maps.
    for ev <- tail do
      assert %{"seq" => seq, "tick" => _, "class" => _, "payload" => _} = ev
      assert is_integer(seq)
    end

    # The prefs-stack digest (opaque md5) projects to hex, not raw bytes.
    assert [%{"payload" => %{"hash" => hash}} | _] = Enum.filter(tail, &(&1["class"] == "meta"))
    assert hash == Base.encode16(Base.decode16!(hash))
  end

  test "spectate join refuses a socket holding a character", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_thistle"})
    assert {:error, %{reason: "unauthorized"}} = join(socket, "spectate:#{id}", %{})
  end

  test "ledger tails stream after join, all classes", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    seq0 = Writer.last_seq(id)
    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")

    assert_push "ledger_tail", %{events: events}
    assert [%{"class" => _, "payload" => _, "seq" => _, "tick" => _} | _] = events
    assert Enum.all?(events, &is_map/1)
    assert Enum.all?(events, &(&1["seq"] > seq0))
    # All classes reach spectators (observability), JSON-shaped.
    assert Enum.any?(events, &(&1["class"] == "llm"))
    assert {:ok, _} = Jason.encode(events)
  end

  test "pause generates dossiers and resumes", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    {:ok, _, chan} = join(socket, "spectate:#{id}", %{})

    ref = push(chan, "pause", %{})
    assert_reply ref, :ok, %{dossiers: dossiers}
    assert Map.has_key?(dossiers, "pc_thistle")
    assert Map.has_key?(dossiers, "pc_bramble")
    assert is_binary(dossiers["pc_thistle"])

    assert %{status: :paused} = Session.state(id)

    # The reply carries `resumed: true` so clients can tell it apart from
    # heartbeat acks (additive — bare %{} matchers still match).
    ref2 = push(chan, "resume", %{})
    assert_reply ref2, :ok, %{resumed: true}
    assert %{status: :running} = Session.state(id)
  end

  test "spend replies with the report", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    {:ok, _, chan} = join(socket, "spectate:#{id}", %{})

    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")

    ref = push(chan, "spend", %{})
    assert_reply ref, :ok, %{spend: spend}
    assert spend.total.calls >= 1
  end

  test "gm_chat pushes ooc to the spectate socket", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    :ok = Session.gm_chat(id, "gm table talk")

    assert_push "ledger_tail", %{events: _}
    assert_push "ooc", %{"author" => "GM", "text" => "gm table talk"}
  end

  test "Session.ooc pushes ooc to the spectate socket", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    :ok = Session.ooc(id, "pc_thistle", "player table talk")

    assert_push "ledger_tail", %{events: _}
    assert_push "ooc", %{"author" => "pc_thistle", "text" => "player table talk"}
  end

  test "state_sync pushes tick, boundaries, and active_agents after world tails", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")

    assert_push "state_sync", %{tick: tick, boundaries: boundaries, active_agents: active_agents}
    assert is_integer(tick)
    assert is_map(boundaries)
    assert is_list(active_agents)
    assert {:ok, _} = Jason.encode(boundaries)
    assert {:ok, _} = Jason.encode(active_agents)
  end

  test "state_sync pushes active_agents after boundary wake", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    world = Server.snapshot(id)

    boundary =
      world.boundaries
      |> Map.values()
      |> Enum.find(fn b -> b.state == :dormant and b.bound_agent_ids != [] end)

    assert boundary, "expected at least one dormant boundary with bound agents"

    seq = Writer.last_seq(id) + 1
    tick = world.tick

    event = %Ledger.Event{
      seq: seq,
      tick: tick,
      class: :meta,
      payload: %{
        kind: :boundary_wake,
        id: boundary.id,
        tick: tick,
        reason: "test wake",
        bound_agent_ids: boundary.bound_agent_ids
      }
    }

    assert :ok = Writer.append(id, [event])

    assert_push "state_sync", %{tick: ^tick, active_agents: active_agents}
    awakened_ids = MapSet.new(boundary.bound_agent_ids)
    found_ids = MapSet.new(active_agents, & &1["id"])
    assert MapSet.subset?(awakened_ids, found_ids)
    assert {:ok, _} = Jason.encode(active_agents)
  end

  test "awaiting push fires after a joined PC seat declares", %{run_id: id} do
    {:ok, _pid} = start_run(id)

    {:ok, spec_socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _spec_chan} = join(spec_socket, "spectate:#{id}", %{})

    {:ok, pc_socket} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_thistle"})
    assert {:ok, _, _pc_chan} = join(pc_socket, "run:#{id}", %{})

    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")

    assert_push "awaiting", %{pcs: pcs}
    by_id = Map.new(pcs, fn pc -> {pc.id, pc} end)

    assert %{"pc_thistle" => thistle, "pc_bramble" => bramble} = by_id
    assert thistle.seated == true
    assert thistle.last_intent.text == "I head east"
    assert is_integer(thistle.last_intent.tick)
    assert bramble.seated == false
    assert bramble.last_intent == nil
  end

  test "awaiting push is suppressed when the list has not changed", %{run_id: id} do
    {:ok, _pid} = start_run(id)

    {:ok, spec_socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _spec_chan} = join(spec_socket, "spectate:#{id}", %{})

    {:ok, pc_socket} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_thistle"})
    assert {:ok, _, _pc_chan} = join(pc_socket, "run:#{id}", %{})

    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")
    assert_push "awaiting", %{pcs: _}

    # A meta ledger event (pause) does not change awaiting, so no push.
    assert {:ok, %{dossiers: _}} = Session.pause(id)
    refute_push "awaiting", %{}
  end

  test "spectate join succeeds without crashing when session is busy", %{run_id: id} do
    {:ok, session_pid} = start_run(id)

    # Suspend the session process to simulate a long synchronous LLM advance/deliberation call
    :sys.suspend(session_pid)

    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    # Join must succeed and return the snapshot from World.Server and Writer without crashing or timing out
    assert {:ok, snapshot, _chan} = join(socket, "spectate:#{id}", %{})
    assert is_integer(snapshot.tick)
    assert is_map(snapshot.boundaries)
    assert is_list(snapshot.awaiting)

    :sys.resume(session_pid)
  end

  defp start_run(id) do

    scripts = %{
      interpret: [
        ~s({"verb":"move","target_id":null,"params":{"direction":"east"}}),
        ~s({"verb":"move","target_id":null,"params":{"direction":"east"}})
      ],
      salt: System.unique_integer()
    }

    Session.start_link(id, @yaml, 42, @pcs,
      routing: %{interpret: %{adapter: Scripted, scripts: scripts}}
    )
  end
end
