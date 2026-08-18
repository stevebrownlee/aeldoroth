defmodule EngineCore.TypesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Types, World}

  test "agent requires id, name, tier, place_id" do
    assert_raise ArgumentError, fn ->
      struct!(Types.Agent, name: "Grisk", tier: 3, place_id: "guard_room")
    end
  end

  test "edge and place defaults" do
    e = struct!(Types.Edge, id: :e1, from: "a", to: "b")
    assert e.sealed == false and e.permeability == %{sight: :open, sound: :open}
    p = struct!(Types.Place, id: "entry_hall", name: "Hall", kind: :room, connections: [])
    assert p.kind == :room
  end

  test "world query: agents_in returns agents at a place" do
    a1 = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall")
    a2 = %{a1 | id: "g2", place_id: "guard_room"}
    w = %World{places: %{}, edges: [], agents: %{"g1" => a1, "g2" => a2}, items: %{}, tick: 0}
    assert [%Types.Agent{id: "g1"}] = World.agents_in(w, "entry_hall")
    assert %Types.Agent{id: "g2"} = World.agent(w, "g2")
    assert World.agent(w, "nope") == nil
    assert World.place(w, "nope") == nil
  end
end
