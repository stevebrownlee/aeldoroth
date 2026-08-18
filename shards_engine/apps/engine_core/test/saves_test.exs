defmodule EngineCore.SavesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Saves, Types, World}

  test "monster-as-fighter save targets" do
    assert Saves.target(1, :death) == 14
    assert Saves.target(3, :death) == 12
    assert Saves.target(1, :spells) == 17
    assert Saves.target(10, :death) == 10
  end

  test "check emits a dice event with a boolean verdict" do
    a =
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
        }
      )

    w = %World{places: %{}, edges: [], agents: %{"g1" => a}, items: %{}, tick: 6}
    {:ok, [ev], _w2, _} = Saves.check(w, EngineCore.Dice.new(11), "g1", :death)
    assert ev.class == :dice and ev.tick == 6
    assert ev.payload.purpose == :save and ev.payload.category == :death
    assert is_integer(ev.payload.roll) and is_boolean(ev.payload.saved)
    assert ev.payload.target == 14
    assert {:error, :no_agent} = Saves.check(w, EngineCore.Dice.new(11), "nope", :death)
  end
end
