defmodule Agents.AdoptTest do
  @moduledoc "Adoption mechanics: feasibility, reliability target, threshold (pure)."
  use ExUnit.Case, async: true
  alias Agents.Adopt
  alias EngineCore.{Loader, World}

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  setup do
    {:ok, w} = Loader.load(@yaml)
    %{w: w}
  end

  defp order(w, over \\ %{}) do
    Map.merge(%{id: "env-0-1", from: "grisk_the_snatcher", to: "goblin_bodyguard_1",
                type: :order, payload_nl: "Kill the intruder!", sent_tick: 3,
                delivery_place: "chiefs_room", signal_ref: 1}, over)
  end

  test "feasible when co-present and awake", %{w: w} do
    assert Adopt.feasible?(w, order(w))
  end

  test "infeasible when the debtor is fleeing", %{w: w} do
    bodyguard =
      w
      |> World.agent("goblin_bodyguard_1")
      |> put_in([Access.key!(:body), :conditions], [:fleeing])

    w = %{w | agents: Map.put(w.agents, "goblin_bodyguard_1", bodyguard)}
    refute Adopt.feasible?(w, order(w))
  end

  test "infeasible when the creditor is elsewhere and not believed", %{w: w} do
    grisk = %{World.agent(w, "grisk_the_snatcher") | place_id: "guard_room"}
    w = %{w | agents: Map.put(w.agents, "grisk_the_snatcher", grisk)}
    refute Adopt.feasible?(w, order(w))
  end

  test "feasible when the creditor is elsewhere but believed here", %{w: w} do
    grisk = %{World.agent(w, "grisk_the_snatcher") | place_id: "guard_room"}
    bodyguard = World.agent(w, "goblin_bodyguard_1")
    beliefs = Map.put(bodyguard.beliefs, "chiefs_room", %{"grisk_the_snatcher" => %{salience: 4.0}})
    bodyguard = %{bodyguard | beliefs: beliefs}
    w = %{w | agents: w.agents |> Map.put("grisk_the_snatcher", grisk) |> Map.put("goblin_bodyguard_1", bodyguard)}
    assert Adopt.feasible?(w, order(w))
  end

  defp guard(int), do: %{statblock: %{morale: 8, int: int}}

  test "reliability: morale + INT adjust + feasibility adjust" do
    assert Adopt.reliability(guard(10), true) == 11
    assert Adopt.reliability(guard(13), true) == 13
    assert Adopt.reliability(guard(6), true) == 9
    assert Adopt.reliability(guard(10), false) == 4
  end

  test "decide: roll at or under target adopts" do
    assert Adopt.decide(11, 11) == :adopt
    assert Adopt.decide(12, 11) == :reject
  end
end
