defmodule EngineCore.LoaderTest do
  use ExUnit.Case, async: true

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "loads the tower into a coherent world" do
    {:ok, w} = EngineCore.Loader.load(@yaml)
    assert map_size(w.places) == 7
    assert w.tick == 0
    tiers = w.agents |> Map.values() |> Map.new(&{&1.tier, true})
    assert tiers[3] and tiers[2] and tiers[0] and tiers[1]
    assert Enum.all?(w.agents |> Map.values(), &(&1.place_id != nil))
  end

  test "refuses to load a file failing validation" do
    tmp = Path.join(System.tmp_dir!(), "bad_adventure_#{:erlang.unique_integer()}.yaml")
    File.write!(tmp, "monsters:\n- id: m1\n  name: x\n  description: bad (3 (7\n")
    on_exit(fn -> File.rm!(tmp) end)
    assert {:error, _} = EngineCore.Loader.load(tmp)
  end

  test "parses hit_dice into integer hd in statblock" do
    raw = %{
      "rooms" => [%{"id" => "r1", "name" => "R1"}],
      "initial_enemies" => [
        %{"id" => "m1", "hit_dice" => "1+2 (1d8+2)", "current_room_id" => "r1"},
        %{"id" => "m2", "hit_dice" => "1-1 (1d8-1)", "current_room_id" => "r1"},
        %{"id" => "m3", "hit_dice" => "2d8", "current_room_id" => "r1"},
        %{"id" => "m4", "hit_dice" => 3, "current_room_id" => "r1"}
      ]
    }

    w = EngineCore.Loader.build(raw)
    assert is_integer(w.agents["m1"].statblock.hd)
    assert w.agents["m1"].statblock.hd == 1
    assert w.agents["m2"].statblock.hd == 1
    assert w.agents["m3"].statblock.hd == 2
    assert w.agents["m4"].statblock.hd == 3

    {:ok, tower_world} = EngineCore.Loader.load(@yaml)

    for {_id, agent} <- tower_world.agents do
      assert is_integer(agent.statblock.hd)
    end
  end

  test "sets sealed: true on edge when exit is locked" do
    {:ok, w} = EngineCore.Loader.load(@yaml)

    library_edge =
      Enum.find(w.edges, fn e -> e.from == "library" and e.to == "ritual_chamber" end)

    assert library_edge != nil
    assert library_edge.sealed == true
  end

  test "tier-3 chiefs carry :order; vermin do not" do
    {:ok, w} = EngineCore.Loader.load(@yaml)
    assert :order in w.agents["grisk_the_snatcher"].capabilities
    assert :order in w.agents["goblin_bodyguard_1"].capabilities
    refute :order in w.agents["giant_rat_1"].capabilities
  end

  test "loads boundaries, hazards, commitments, groups, cadences" do
    {:ok, w} = EngineCore.Loader.load(@yaml)

    assert MapSet.new(Map.keys(w.boundaries)) ==
             MapSet.new([
               "guard_room_zone",
               "chiefs_room_zone",
               "library_zone",
               "wolf_pack",
               "skeleton_sentinel"
             ])

    gz = w.boundaries["guard_room_zone"]
    assert gz.scope_place_id == "guard_room" and gz.state == :dormant
    assert gz.triggers == [:presence_crossing, :signal_arrived]
    assert gz.wake_on_intensity == 4 and gz.sleep_after == 60

    assert MapSet.new(gz.bound_agent_ids) ==
             MapSet.new(~w(goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4))

    wp = w.boundaries["wolf_pack"]
    assert wp.scope_group == "wolf"
    assert MapSet.new(wp.bound_agent_ids) == MapSet.new(~w(wolf_1 wolf_2))

    assert MapSet.new(Map.keys(w.hazards)) ==
             MapSet.new(~w(alarm_tripwire caltrops bell_tripwire pit_trap false_cache_needle))

    assert w.hazards["alarm_tripwire"].kind == :alarm
    assert w.hazards["alarm_tripwire"].edge_id == :entry_hall__guard_room
    assert w.hazards["caltrops"].kind == :damage
    assert w.hazards["pit_trap"].damage == %{dice: 1, sides: 6, plus: 0}

    guards = w.agents["goblin_guard_1"]
    assert guards.attention == :dormant
    assert guards.cadence == %{every: 10, next_due: nil}

    assert [
             %EngineCore.Types.Commitment{
               id: "guard_watch_rotation",
               status: :pending,
               due: 30,
               every: 30
             }
           ] = guards.commitments

    grisk = w.agents["grisk_the_snatcher"]

    assert [%EngineCore.Types.Commitment{id: "grisk_relocation_deadline", priority: 8}] =
             grisk.commitments

    assert w.agents["giant_rat_1"].tier == 1
    assert w.agents["wolf_1"].tier == 2 and w.agents["wolf_1"].group == "wolf"
    assert w.agents["wolf_1"].cadence == %{every: 5, next_due: nil}
    assert w.agents["shadow_touched_skeleton"].attention == :dormant
    assert w.agents["shadow_touched_skeleton"].cadence == %{every: 2, next_due: nil}

    assert Enum.find(w.edges, &(&1.id == :entry_hall__guard_room)).label == "east"
  end
end
