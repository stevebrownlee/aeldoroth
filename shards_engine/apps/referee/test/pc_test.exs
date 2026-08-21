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
  test "build/1 captures class, race, armor, weapons, inventory, spells, prayers and calculates THAC0" do
    pc =
      PC.build(
        Map.merge(Map.delete(@pc_map, :thac0), %{
          race: "Elf",
          class: "Magic-User",
          level: 1,
          armor: "Robes",
          weapons: "Staff (1d6), Dagger (1d4)",
          inventory: "Spellbook, 3 torches, 10 gp",
          spells: "Magic Missile, Sleep",
          prayers: nil
        })
      )

    assert pc.statblock.race == "Elf"
    assert pc.statblock.class == "Magic-User"
    assert pc.statblock.thac0 == 20
    assert pc.statblock.armor == "Robes"
    assert pc.statblock.weapons == "Staff (1d6), Dagger (1d4)"
    assert pc.statblock.inventory == "Spellbook, 3 torches, 10 gp"
    assert pc.statblock.spells == "Magic Missile, Sleep"
    assert pc.statblock.prayers == nil
  end

  test "calculate_thac0/2 computes AD&D 1E attack matrices across levels" do
    # Fighter: 1-2 is 20, 3-4 is 18, 5-6 is 16, 7-8 is 14
    assert PC.calculate_thac0("Fighter", 1) == 20
    assert PC.calculate_thac0("Paladin", 3) == 18
    assert PC.calculate_thac0("Ranger", 5) == 16
    assert PC.calculate_thac0("Fighter", 9) == 12

    # Cleric: 1-3 is 20, 4-6 is 18, 7-9 is 16
    assert PC.calculate_thac0("Cleric", 1) == 20
    assert PC.calculate_thac0("Druid", 4) == 18
    assert PC.calculate_thac0("Cleric", 7) == 16

    # Thief: 1-4 is 20, 5-8 is 19, 9-12 is 16
    assert PC.calculate_thac0("Thief", 1) == 20
    assert PC.calculate_thac0("Thief", 5) == 19
    assert PC.calculate_thac0("Assassin", 9) == 16

    # Magic-User: 1-5 is 20, 6-10 is 19, 11-15 is 16
    assert PC.calculate_thac0("Magic-User", 1) == 20
    assert PC.calculate_thac0("Illusionist", 6) == 19
    assert PC.calculate_thac0("Magic-User", 11) == 16
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
