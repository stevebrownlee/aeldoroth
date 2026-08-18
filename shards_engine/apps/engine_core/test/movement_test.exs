defmodule EngineCore.MovementTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Movement, Types, World}

  setup do
    hall = %Types.Place{id: "entry_hall", name: "Hall", kind: :room, connections: ["guard_room"]}
    guard = %Types.Place{id: "guard_room", name: "Guard", kind: :room, connections: ["entry_hall"]}
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall")

    w = %World{
      places: %{"entry_hall" => hall, "guard_room" => guard},
      edges: [%Types.Edge{id: :e1, from: "entry_hall", to: "guard_room"}],
      agents: %{"g1" => g},
      items: %{},
      tick: 10
    }

    {:ok, w: w}
  end

  test "traverse emits move event and relocates", %{w: w} do
    rng = EngineCore.Dice.new(1)
    {:ok, ev, w2, _} = Movement.traverse(w, rng, "g1", "guard_room")
    assert ev.payload == %{kind: :move, agent_id: "g1", from: "entry_hall", to: "guard_room"}
    assert ev.tick == 11
    assert %Types.Agent{place_id: "guard_room"} = World.agent(w2, "g1")
  end

  test "no edge means not_adjacent", %{w: w} do
    w = put_in(w.places["entry_hall"].connections, [])
    assert {:error, :not_adjacent} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "guard_room")
  end

  test "sealed edge blocks", %{w: w} do
    w = %{w | edges: [%Types.Edge{id: :e1, from: "entry_hall", to: "guard_room", sealed: true}]}
    assert {:error, :sealed_edge} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "guard_room")
  end

  test "unknown agent and unknown destination error", %{w: w} do
    assert {:error, :no_agent} = Movement.traverse(w, EngineCore.Dice.new(1), "nope", "guard_room")
    assert {:error, :no_place} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "nowhere")
  end

  test "dead agent cannot traverse", %{w: w} do
    w_hp0 = put_in(w.agents["g1"].body.hp, 0)
    assert {:error, :dead} = Movement.traverse(w_hp0, EngineCore.Dice.new(1), "g1", "guard_room")

    w_dead = put_in(w.agents["g1"].body.conditions, [:dead])
    assert {:error, :dead} = Movement.traverse(w_dead, EngineCore.Dice.new(1), "g1", "guard_room")
  end
end
