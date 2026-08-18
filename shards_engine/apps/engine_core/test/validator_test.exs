defmodule EngineCore.ValidatorTest do
  use ExUnit.Case, async: true

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "the real tower YAML is structurally intact" do
    assert :ok = EngineCore.Validator.check_file(@yaml)
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
end
