defmodule Referee.PCTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, World}
  alias Referee.PC

  @pc_map %{
    id: "pc_thistle",
    name: "Thistle",
    place_id: "entry_hall",
    int: 13,
    ac: 5,
    hd: 1,
    hp: 7,
    thac0: 20,
    damage: "1d8"
  }

  test "build/1 constructs a tier-3 PC agent" do
    pc = PC.build(@pc_map)

    assert pc.id == "pc_thistle"
    assert pc.tier == 3
    assert pc.capabilities == [:move, :strike, :wait, :shout]
    assert pc.beliefs == %{}
    assert pc.cadence == nil
    assert pc.attention == :alert
    assert pc.body == %{hp: 7, conditions: []}

    assert pc.statblock.ac == 5
    assert pc.statblock.hd == 1
    assert pc.statblock.hp_max == 7
    assert pc.statblock.thac0 == 20
    assert pc.statblock.int == 13
    assert pc.statblock.damage == %{dice: 1, sides: 8, plus: 0}
  end

  test "build/1 parses damage with a plus term" do
    pc = PC.build(%{@pc_map | damage: "2d6+1"})

    assert pc.statblock.damage == %{dice: 2, sides: 6, plus: 1}
  end
  test "build/1 captures class, armor, weapons, inventory, spells, prayers" do
    pc =
      PC.build(
        Map.merge(@pc_map, %{
          class: "Magic-User",
          armor: "Robes",
          weapons: "Staff (1d6), Dagger (1d4)",
          inventory: "Spellbook, 3 torches, 10 gp",
          spells: "Magic Missile, Sleep",
          prayers: nil
        })
      )

    assert pc.statblock.class == "Magic-User"
    assert pc.statblock.armor == "Robes"
    assert pc.statblock.weapons == "Staff (1d6), Dagger (1d4)"
    assert pc.statblock.inventory == "Spellbook, 3 torches, 10 gp"
    assert pc.statblock.spells == "Magic Missile, Sleep"
    assert pc.statblock.prayers == nil
  end

  test "join_events yields one :agent_added event that folds the PC in at the entry place" do
    w = %World{places: %{"entry_hall" => %EngineCore.Types.Place{id: "entry_hall", name: "Entry Hall", kind: :room, connections: []}}, agents: %{}}
    pc = PC.build(@pc_map)
    [ev] = PC.join_events(w, pc)

    assert %Ledger.Event{class: :world, payload: %{kind: :agent_added, agent: agent, place_id: "entry_hall"}} = ev
    assert agent.id == "pc_thistle"

    w2 = Fold.fold(w, [ev])
    assert Map.has_key?(w2.agents, "pc_thistle")
    assert w2.agents["pc_thistle"].place_id == "entry_hall"
  end
end
