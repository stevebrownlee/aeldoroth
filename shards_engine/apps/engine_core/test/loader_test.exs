defmodule EngineCore.LoaderTest do
  use ExUnit.Case, async: true

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  @yaml if File.exists?(path), do: path, else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

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
    library_edge = Enum.find(w.edges, fn e -> e.from == "library" and e.to == "ritual_chamber" end)
    assert library_edge != nil
    assert library_edge.sealed == true
  end
end
