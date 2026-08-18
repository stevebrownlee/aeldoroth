defmodule EngineCore.FoldTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, Types, World}

  setup do
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall", body: %{hp: 5, conditions: []})
    {:ok, w: %World{places: %{}, edges: [], agents: %{"g1" => g}, items: %{}, tick: 0}}
  end

  test "move event relocates agent and advances tick", %{w: w} do
    ev = %Ledger.Event{seq: 1, tick: 3, class: :world,
                       payload: %{kind: :move, agent_id: "g1", to: "guard_room"}}
    w2 = Fold.apply(w, ev)
    assert %Types.Agent{place_id: "guard_room"} = World.agent(w2, "g1")
    assert w2.tick == 3
  end

  test "damage reduces hp; death empties capabilities; morale_break adds condition", %{w: w} do
    w1 = Fold.apply(w, ev(1, 1, %{kind: :damage, target_id: "g1", amount: 3}))
    assert %Types.Agent{body: %{hp: 2}} = World.agent(w1, "g1")

    w2 = Fold.apply(w1, ev(2, 2, %{kind: :damage, target_id: "g1", amount: 9}))
    w3 = Fold.apply(w2, ev(3, 2, %{kind: :death, agent_id: "g1"}))
    assert %Types.Agent{body: %{hp: 0}, capabilities: []} = World.agent(w3, "g1")

    w4 = Fold.apply(w, ev(4, 1, %{kind: :morale_break, agent_id: "g1"}))
    assert :fleeing in World.agent(w4, "g1").body.conditions
  end

  test "fold folds in order; empty fold is identity", %{w: w} do
    evs = [ev(1, 1, %{kind: :damage, target_id: "g1", amount: 1})]
    assert %World{tick: 1} = w2 = Fold.fold(w, evs)
    assert Fold.fold(w2, []) == w2
  end

  test "out-of-order events preserve tick monotonicity", %{w: w} do
    w1 = Fold.apply(w, ev(1, 3, %{kind: :damage, target_id: "g1", amount: 1}))
    w2 = Fold.apply(w1, ev(2, 1, %{kind: :damage, target_id: "g1", amount: 1}))
    assert w2.tick == 3
  end

  test "unknown payload kind raises" do
    assert_raise ArgumentError, ~r/unknown payload kind/, fn ->
      Fold.apply(%World{}, ev(1, 0, %{kind: :teleport}))
    end
  end

  defp ev(seq, tick, payload),
    do: %Ledger.Event{seq: seq, tick: tick, class: :world, payload: payload}
end
