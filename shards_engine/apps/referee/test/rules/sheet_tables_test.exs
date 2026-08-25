defmodule Referee.Rules.SheetTablesTest do
  use ExUnit.Case, async: true
  alias Referee.Rules.SheetTables

  test "calculates strength sub-stats including exceptional strength" do
    s17 = SheetTables.strength_substats(17, nil)
    assert s17.hit_adj == "+1"
    assert s17.dam_adj == "+1"
    assert s17.open_doors == "1-3"
    assert s17.bend_bars == "13%"

    s18_50 = SheetTables.strength_substats(18, 50)
    assert s18_50.hit_adj == "+1"
    assert s18_50.dam_adj == "+3"
    assert s18_50.bend_bars == "20%"
  end

  test "calculates 1E saving throws by class and level" do
    fighter_1 = SheetTables.saving_throws("Fighter", 1)
    assert fighter_1.poison == 14
    assert fighter_1.petrification == 15
    assert fighter_1.wand == 16
    assert fighter_1.breath == 17
    assert fighter_1.spell == 17

    cleric_1 = SheetTables.saving_throws("Cleric", 1)
    assert cleric_1.poison == 10
    assert cleric_1.petrification == 13
    assert cleric_1.wand == 14
    assert cleric_1.breath == 16
    assert cleric_1.spell == 15
  end

  test "calculates to-hit matrix for AC 10..2" do
    matrix = SheetTables.to_hit_matrix("Fighter", 1)
    assert matrix[10] == 10
    assert matrix[5] == 15
    assert matrix[2] == 18
  end

  test "calculates thief skills percentages" do
    thief_1 = SheetTables.thieving_skills("Thief", 1, "Human", 15)
    assert thief_1.pick_pockets == "30%"
    assert thief_1.open_locks == "25%"
    assert thief_1.find_traps == "20%"
    assert thief_1.move_silently == "15%"
    assert thief_1.hide_in_shadows == "10%"
    assert thief_1.hear_noise == "10%"
    assert thief_1.climb_walls == "85%"
    assert thief_1.read_languages == "—"
  end

  test "returns turning undead table for level 1 cleric" do
    turning = SheetTables.turning_table(1)
    assert turning.skeleton == "10"
    assert turning.zombie == "13"
    assert turning.ghoul == "16"
    assert turning.shadow == "19"
    assert turning.wight == "20"
    assert turning.ghast == "—"
  end
end
