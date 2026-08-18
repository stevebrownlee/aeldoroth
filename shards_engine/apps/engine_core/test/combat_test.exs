defmodule EngineCore.CombatTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Rules.Combat, Types, World}

  defp world do
    g =
      struct!(Types.Agent,
        id: "g1",
        name: "Gob",
        tier: 3,
        place_id: "r",
        statblock: %{
          ac: 6,
          hd: 1,
          hp_max: 5,
          thac0: 19,
          morale: 7,
          int: 8,
          damage: %{dice: 1, sides: 4, plus: 0}
        },
        body: %{hp: 5, conditions: []}
      )

    f =
      struct!(Types.Agent,
        id: "pc1",
        name: "Fighter",
        tier: 3,
        place_id: "r",
        statblock: %{
          ac: 5,
          hd: 3,
          hp_max: 18,
          thac0: 18,
          morale: 12,
          int: 10,
          damage: %{dice: 1, sides: 8, plus: 0}
        },
        body: %{hp: 18, conditions: []}
      )

    %World{
      places: %{"r" => %Types.Place{id: "r", name: "R", kind: :room, connections: []}},
      edges: [],
      agents: %{"g1" => g, "pc1" => f},
      items: %{},
      tick: 4
    }
  end

  test "attack emits events and reduces hp or misses cleanly" do
    {:ok, events, w2, _} = Combat.attack(world(), EngineCore.Dice.new(99), "g1", "pc1")

    case events do
      [
        %{class: :dice, payload: %{hit: true}},
        %{class: :world, payload: %{kind: :damage, target_id: "pc1"}}
      ] ->
        assert World.agent(w2, "pc1").body.hp < 18

      [%{class: :dice, payload: %{hit: false}}] ->
        assert World.agent(w2, "pc1").body.hp == 18
    end
  end

  test "attack on different-room agent errors :not_engaged" do
    w = put_in(world().agents["pc1"].place_id, "elsewhere")
    assert {:error, :not_engaged} = Combat.attack(w, EngineCore.Dice.new(1), "g1", "pc1")
  end

  test "dead agents (no capabilities) cannot attack" do
    w = put_in(world().agents["g1"].capabilities, [])
    assert {:error, :no_capability} = Combat.attack(w, EngineCore.Dice.new(1), "g1", "pc1")
  end

  test "initiative is a permutation, deterministic per seed" do
    rng = EngineCore.Dice.new(5)
    {o1, _} = Combat.initiative(rng, ["g1", "pc1"])
    {o2, _} = Combat.initiative(rng, ["g1", "pc1"])
    assert Enum.sort(o1) == ["g1", "pc1"] and o1 == o2
  end

  test "lethal attack emits death event, clears capabilities, adds :dead condition, and matches fold invariant" do
    w0 = put_in(world().agents["g1"].body.hp, 1)

    {events, w_result} =
      Enum.find_value(1..100, fn seed ->
        case Combat.attack(w0, EngineCore.Dice.new(seed), "pc1", "g1") do
          {:ok, [_, %{payload: %{kind: :damage}}, %{payload: %{kind: :death}}] = evs, w_out, _} ->
            {evs, w_out}

          _ ->
            nil
        end
      end)

    assert [
             %{class: :dice, payload: %{hit: true}},
             %{class: :world, payload: %{kind: :damage, target_id: "g1"}},
             %{class: :world, payload: %{kind: :death, agent_id: "g1"}}
           ] = events

    g_dead = World.agent(w_result, "g1")
    assert g_dead.body.hp == 0
    assert g_dead.capabilities == []
    assert :dead in g_dead.body.conditions

    assert Fold.fold(w0, events) == w_result
  end
end
