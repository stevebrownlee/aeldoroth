defmodule EngineCore.MoraleTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Morale, Types, World}

  defp gob(id, opts \\ []) do
    struct!(Types.Agent,
      id: id,
      name: id,
      tier: 3,
      place_id: "r",
      statblock: %{
        ac: 6,
        hd: Keyword.get(opts, :hd, 1),
        hp_max: 5,
        thac0: 19,
        morale: Keyword.get(opts, :morale, 7),
        int: 8,
        damage: %{dice: 1, sides: 4, plus: 0}
      },
      body: %{hp: Keyword.get(opts, :hp, 5), conditions: Keyword.get(opts, :conditions, [])}
    )
  end

  test "leader down triggers morale dice for the living; outcome is consistent" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1")}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    {:ok, events, w2, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])

    assert Enum.any?(events, &(&1.class == :dice and &1.payload.purpose == :morale))
    g1 = World.agent(w2, "g1")
    assert g1.body.conditions == [] or :fleeing in g1.body.conditions
    assert Enum.all?(events, &(&1.payload[:agent_id] != "l")), "dead do not roll"

    dice_ev = Enum.find(events, &(&1.class == :dice and &1.payload[:purpose] == :morale and &1.payload[:agent_id] == "g1"))
    has_break = Enum.any?(events, &(&1.payload[:kind] == :morale_break and &1.payload[:agent_id] == "g1"))

    if :fleeing in g1.body.conditions do
      assert has_break
      assert dice_ev != nil and dice_ev.payload.held == false
    else
      assert not has_break
      if dice_ev, do: assert dice_ev.payload.held == true
    end
  end

  test "50% casualties trigger" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1"), "g2" => gob("g2", hp: 0)}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    {:ok, events, _, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1", "g2"])
    assert Enum.any?(events, &(&1.payload[:purpose] == :morale))
  end

  test "healthy faction triggers nothing" do
    agents = %{"l" => gob("l", hd: 3), "g1" => gob("g1")}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    assert {:ok, [], ^w, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])
  end

  test "morale_break event matches Fold behavior" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1", morale: 0)}
    # morale 0: any roll 1..20 breaks
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 2}
    {:ok, events, w2, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])
    break_ev = Enum.find(events, &(&1.payload[:kind] == :morale_break))
    assert break_ev.tick == 2
    assert :fleeing in World.agent(w2, "g1").body.conditions
  end

  test "dead 1-HD agent does not trigger leader down" do
    agents = %{
      "g1" => gob("g1", hd: 1, hp: 0),
      "g2" => gob("g2", hd: 1, hp: 5),
      "g3" => gob("g3", hd: 1, hp: 5)
    }

    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    assert {:ok, [], ^w, _} = Morale.check(w, EngineCore.Dice.new(3), ["g1", "g2", "g3"])
  end
end
