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
  alias EngineCore.Ledger.Writer
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

    assert {:ok, %{tick: tick, boundaries: boundaries, spend: spend, tail: tail}, _chan} =
             join(socket, "spectate:#{id}", %{})

    assert is_integer(tick)
    assert is_map(boundaries) and map_size(boundaries) > 0
    assert is_map(spend) and Map.has_key?(spend, :total)
    assert length(tail) <= 50

    # Real sockets serialize to JSON (the crash this pins: agent_added's
    # Agent struct and the prefs md5 digest are not JSON-safe terms).
    assert {:ok, _} = Jason.encode(%{tick: tick, boundaries: boundaries, spend: spend, tail: tail})

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

  test "state_sync pushes tick and boundaries after world tails", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _, _chan} = join(socket, "spectate:#{id}", %{})

    assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "I head east")

    assert_push "state_sync", %{tick: tick, boundaries: boundaries}
    assert is_integer(tick)
    assert is_map(boundaries)
    assert {:ok, _} = Jason.encode(boundaries)
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
