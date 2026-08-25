defmodule EngineCore.WorldServerTest do
  @moduledoc """
  World.Server (plan 5 Task 3): authoritative world fold living in its own
  process, fed by writer tails, exposing cheap snapshot reads.
  """
  use ExUnit.Case, async: true

  alias EngineCore.{Fold, Ledger, Loader, RunSup, World}
  alias EngineCore.Ledger.Writer
  alias EngineCore.World.Server

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pc %EngineCore.Types.Agent{
    id: "pc_thistle",
    name: "Thistle",
    tier: 3,
    place_id: "entry_hall"
  }

  setup do
    id = "ws#{:erlang.unique_integer([:positive])}"
    {:ok, world} = Loader.load(@yaml)
    on_exit(fn -> RunSup.stop_run(id) end)
    %{id: id, world: world}
  end

  test "folds writer tails into snapshots", %{id: id, world: world} do
    {:ok, _} = RunSup.ensure_run(id, world)

    ev = %Ledger.Event{seq: 1, tick: 0, class: :world, payload: %{kind: :agent_added, agent: @pc}}
    :ok = Writer.append(id, [ev])

    wait_until(fn ->
      snap = Server.snapshot(id)
      assert World.agent(snap, "pc_thistle") != nil
    end)

    boundaries = Server.boundaries(id)
    assert map_size(boundaries) > 0

    for {_bid, b} <- boundaries do
      assert %{state: state} = b
      assert state in [:dormant, :awake]
    end
    assert Map.keys(boundaries) |> MapSet.new() ==
             world.boundaries |> Map.keys() |> MapSet.new()
  end

  test "fold of writer events equals snapshot (spec 12.3)", %{id: id, world: world} do
    {:ok, _} = RunSup.ensure_run(id, world)

    events = [
      %Ledger.Event{seq: 1, tick: 0, class: :world, payload: %{kind: :agent_added, agent: @pc}},
      %Ledger.Event{
        seq: 2,
        tick: 1,
        class: :world,
        payload: %{kind: :move, agent_id: "pc_thistle", to: "guard_room"}
      }
    ]

    :ok = Writer.append(id, events)

    wait_until(fn ->
      snap = Server.snapshot(id)
      refolded = Fold.fold(world, events)
      assert snap.tick == refolded.tick
      assert snap.agents == refolded.agents
      assert snap.boundaries == refolded.boundaries
    end)
  end

  test "reads are cheap while writer busy: server is its own process", %{id: id, world: world} do
    {:ok, server} = RunSup.ensure_run(id, world)
    assert is_pid(server)

    writer = EngineCore.whereis_writer(id)
    assert is_pid(writer)
    assert server != writer

    # snapshot answers without joining the writer's append path
    assert %World{} = Server.snapshot(id)
  end

  test "active_agents returns empty list when no boundaries are awake", %{id: id, world: world} do
    {:ok, _} = RunSup.ensure_run(id, world)
    assert Server.active_agents(id) == []
  end

  test "active_agents returns enriched agents when boundary is awake", %{id: id, world: world} do
    {:ok, _} = RunSup.ensure_run(id, world)

    reason = "presence_crossing by pc_thistle"

    ev = %Ledger.Event{
      seq: 1,
      tick: 7,
      class: :meta,
      payload: %{
        kind: :boundary_wake,
        id: "guard_room_zone",
        tick: 7,
        reason: reason,
        bound_agent_ids: Map.fetch!(world.boundaries, "guard_room_zone").bound_agent_ids
      }
    }

    :ok = Writer.append(id, [ev])

    wait_until(fn ->
      assert Server.boundaries(id)["guard_room_zone"].state == :awake
    end)

    agents = Server.active_agents(id)
    assert length(agents) == 4

    for a <- agents do
      assert a.boundary_id == "guard_room_zone"
      assert a.wake_tick == 7
      assert a.wake_reason == reason
      assert a.group == "goblin"
      assert a.place_id == "guard_room"
      assert is_binary(a.place_name)
      assert a.tier == 3
      assert map_size(a.dossier) == 0

      for key <- [
            :id,
            :name,
            :tier,
            :group,
            :place_id,
            :place_name,
            :boundary_id,
            :wake_tick,
            :wake_reason,
            :hp,
            :hp_max,
            :ac,
            :thac0,
            :morale,
            :conditions,
            :commitments,
            :dossier
          ] do
        assert Map.has_key?(a, key), "missing #{key}"
      end
    end

    ids = Enum.map(agents, & &1.id) |> Enum.sort()
    assert ids == ["goblin_guard_1", "goblin_guard_2", "goblin_guard_3", "goblin_guard_4"]
  end

  defp wait_until(fun) when is_function(fun, 0) do
    try do
      fun.() || (Process.sleep(10) && wait_until(fun))
    rescue
      _ -> Process.sleep(10) && wait_until(fun)
    end
  end
end
