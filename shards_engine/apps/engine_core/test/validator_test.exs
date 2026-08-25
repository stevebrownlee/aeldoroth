defmodule EngineCore.ValidatorTest do
  use ExUnit.Case, async: true

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "the real tower YAML is structurally intact" do
    assert :ok = EngineCore.Validator.check_file(@yaml)
  end

  test "accepts valid initial_actors maps" do
    base = %{
      "rooms" => %{
        "r1" => %{"id" => "r1", "name" => "R1"}
      },
      "initial_actors" => %{
        "a1" => %{
          "id" => "a1",
          "name" => "Hero",
          "hit_dice" => "1d8",
          "hit_points" => 8,
          "armor_class" => 10,
          "thac0" => 20,
          "morale" => 7,
          "current_room_id" => "r1"
        }
      }
    }

    assert :ok = EngineCore.Validator.check(base)
  end

  test "detects orphan-fragment text" do
    bad = %{
      "initial_enemies" => %{
        "m1" => %{
          "id" => "m1",
          "name" => "goblin",
          "hit_dice" => "1d8",
          "hit_points" => 4,
          "armor_class" => 7,
          "thac0" => 19,
          "morale" => 6,
          "current_room_id" => "r1",
          "description" => "claw hand (3 (7"
        }
      }
    }

    assert {:error, errors} = EngineCore.Validator.check(bad)
    assert Enum.any?(errors, &(&1 =~ "orphan fragment"))
  end

  test "detects missing required monster fields" do
    bad = %{
      "initial_enemies" => %{
        "m1" => %{
          "id" => "m1",
          "name" => "goblin"
        }
      }
    }

    assert {:error, errors} = EngineCore.Validator.check(bad)
    assert Enum.any?(errors, &(&1 =~ "missing"))
  end

  test "detects connections to unknown rooms" do
    bad = %{
      "rooms" => %{
        "r1" => %{
          "id" => "r1",
          "name" => "R",
          "exits" => %{
            "north" => "ghost_room"
          }
        }
      },
      "initial_enemies" => %{}
    }

    assert {:error, errors} = EngineCore.Validator.check(bad)
    assert Enum.any?(errors, &(&1 =~ "unknown room"))
  end

  test "boundary validation: unknown place, bad trigger, coarse_tick on group scope" do
    base = %{"rooms" => %{}, "initial_enemies" => %{}}

    assert {:error, errs} =
             EngineCore.Validator.check(
               Map.put(base, "boundaries", [
                 %{"id" => "b1", "place" => "nowhere", "triggers" => ["presence_crossing"]}
               ])
             )

    assert "boundary b1: unknown place nowhere" in errs

    assert {:error, errs2} =
             EngineCore.Validator.check(
               Map.put(base, "boundaries", [
                 %{"id" => "b1", "place" => "r1", "triggers" => ["nonsense"]}
               ])
             )

    assert "boundary b1: invalid trigger nonsense" in errs2

    assert {:error, errs3} =
             EngineCore.Validator.check(
               Map.put(base, "boundaries", [
                 %{"id" => "b1", "group" => "wolf", "triggers" => ["coarse_tick"]}
               ])
             )

    assert "boundary b1: coarse_tick is reserved for place boundaries" in errs3

    assert {:error, errs4} =
             EngineCore.Validator.check(
               Map.merge(base, %{
                 "boundaries" => [
                   %{"id" => "b1", "place" => "r1", "triggers" => ["presence_crossing"]}
                 ],
                 "rooms" => %{"r1" => %{"id" => "r1"}},
                 "initial_enemies" => %{"g1" => %{"id" => "g1"}},
                 "initial_commitments" => [
                   %{"id" => "c1", "debtor" => "ghost", "deed" => "x", "due" => 5}
                 ]
               })
             )

    assert "commitment c1: unknown debtor ghost" in errs4
  end

  test "validates required attributes on list-form initial_actors and catches missing fields" do
    raw = %{
      "rooms" => %{"r1" => %{"id" => "r1"}},
      "starting_place" => "r1",
      "initial_actors" => [
        %{"id" => "a1", "name" => "Actor 1"} # missing hit_dice, hit_points, armor_class, thac0, morale, current_room_id
      ]
    }

    assert {:error, errs} = EngineCore.Validator.check(raw)
    assert "monster a1: missing hit_dice" in errs
    assert "monster a1: missing hit_points" in errs
    assert "monster a1: missing current_room_id" in errs
  end

  test "detects duplicate agent IDs declared across actor keys" do
    raw = %{
      "rooms" => %{"r1" => %{"id" => "r1"}},
      "starting_place" => "r1",
      "initial_actors" => %{
        "mara" => %{
          "id" => "mara",
          "name" => "Mara",
          "hit_dice" => 1,
          "hit_points" => 6,
          "armor_class" => 10,
          "thac0" => 20,
          "morale" => 8,
          "current_room_id" => "r1"
        }
      },
      "initial_enemies" => %{
        "mara" => %{
          "id" => "mara",
          "name" => "Mara Evil Twin",
          "hit_dice" => 1,
          "hit_points" => 6,
          "armor_class" => 10,
          "thac0" => 20,
          "morale" => 8,
          "current_room_id" => "r1"
        }
      }
    }

    assert {:error, errs} = EngineCore.Validator.check(raw)
    assert "duplicate agent id: mara" in errs
  end
end
