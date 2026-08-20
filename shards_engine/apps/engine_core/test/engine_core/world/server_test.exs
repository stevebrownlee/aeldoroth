defmodule EngineCore.World.ServerTest do
  @moduledoc "Tests for EngineCore.World.Server GM-console queries."
  use ExUnit.Case, async: true

  alias EngineCore.{Loader, RunSup}
  alias EngineCore.World.Server

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  setup do
    id = "ws#{:erlang.unique_integer([:positive])}"
    {:ok, world} = Loader.load(@yaml)
    on_exit(fn -> RunSup.stop_run(id) end)
    %{id: id, world: world}
  end

  test "dungeon_overview returns all places, connections, and resident agents", %{
    id: id,
    world: world
  } do
    {:ok, _} = RunSup.ensure_run(id, world)

    overview = Server.dungeon_overview(id)
    assert %{places: places} = overview
    assert is_list(places)
    assert length(places) == map_size(world.places)

    # Places are sorted by id and contain expected keys.
    ids = Enum.map(places, & &1.id)
    assert ids == Enum.sort(ids)

    entry_hall = Enum.find(places, &(&1.id == "entry_hall"))
    assert entry_hall.name == "Entry Hall"
    assert entry_hall.kind == :room
    assert is_list(entry_hall.connections)

    assert Enum.any?(entry_hall.connections, fn c -> c.to == "library" end)

    assert Enum.any?(entry_hall.connections, fn c -> c.to == "guard_room" end)

    guard_room = Enum.find(places, &(&1.id == "guard_room"))
    assert guard_room.kind == :room

    # At least one agent is loaded into the seed world.
    assert Enum.any?(places, &(length(&1.agents) > 0))

    # --- Dungeon enrichment: hazards, items, sealed edges -------------------

    # entry_hall contains the alarm tripwire hazard.
    assert is_list(entry_hall.hazards)
    assert Enum.any?(entry_hall.hazards, fn h ->
      h.id == "alarm_tripwire" and h.kind == :alarm and h.dc == 12
    end)

    # Non-secret connections default to sealed == false.
    for c <- entry_hall.connections do
      assert c.sealed == false
    end

    # library contains treasure items and a sealed connection down.
    library = Enum.find(places, &(&1.id == "library"))
    assert library.items != nil
    assert Enum.any?(library.items, fn i ->
      i.name == "Potion of Healing" and i.value_gp == 50 and i.is_hidden == true
    end)

    library_down = Enum.find(library.connections, &(&1.to == "ritual_chamber"))
    assert library_down != nil
    assert library_down.sealed == true
    assert library_down.label == "down"

    for place <- places,
        agent <- place.agents do
      assert %{id: _, name: _, pc: _, hp: _, hp_max: _, conditions: _} = agent
      assert is_boolean(agent.pc)
      assert is_integer(agent.hp)
      assert is_integer(agent.hp_max)
      assert is_list(agent.conditions)
    end
  end
end
