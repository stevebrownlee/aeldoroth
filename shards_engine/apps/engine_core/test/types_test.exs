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

  test "signal and arrival defaults" do
    s =
      struct!(Types.Signal,
        emitted_by: "pc1",
        place_id: "entry_hall",
        tick: 3,
        kind: :sound,
        content_core: %{class: :combat, threat: true},
        intensity: 7
      )

    assert s.content_nl == nil

    a =
      struct!(Types.Arrival,
        ref: 1,
        place_id: "library",
        tick: 4,
        kind: :sound,
        intensity: 4.9,
        about: "pc1",
        hops: 1,
        origin_place_id: "entry_hall"
      )

    assert a.content_core == nil and a.content_nl == nil
  end

  test "boundary, commitment, hazard defaults" do
    b =
      struct!(Types.Boundary,
        id: "guard_room_zone",
        bound_agent_ids: ["g1"],
        triggers: [:presence_crossing, :signal_arrived]
      )

    assert b.state == :dormant and b.wake_on_intensity == 4 and b.sleep_after == 40
    assert b.scope_place_id == nil and b.scope_group == nil
    c = struct!(Types.Commitment, id: "watch", debtor: "g1", deed: "keep_watch")
    assert c.status == :pending and c.priority == 5 and c.due == nil and c.every == nil
    h = struct!(Types.Hazard, id: "alarm_tripwire", kind: :alarm, place_id: "entry_hall")
    assert h.triggered == false and h.dc == 12 and h.edge_id == nil
    assert h.damage == %{dice: 1, sides: 4, plus: 0} and h.signal_intensity == 9
    assert h.signal_class == :alarm
  end

  test "edge label, agent attention and group, world defaults" do
    e = struct!(Types.Edge, id: :e1, from: "a", to: "b")
    assert e.label == nil
    a = struct!(Types.Agent, id: "w1", name: "Wolf", tier: 2, place_id: "beast_pen")
    assert a.attention == :alert and a.group == nil
    w = %World{}
    assert w.boundaries == %{} and w.in_flight == [] and w.hazards == %{}
    assert w.signal_seq == 0
  end
end
