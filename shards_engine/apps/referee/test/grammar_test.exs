defmodule Referee.GrammarTest do
  @moduledoc "Deterministic NL parser: the LLM-failure fallback (decision 32)."
  use ExUnit.Case, async: true
  alias EngineCore.Types
  alias EngineCore.World
  alias Referee.Grammar

  defp world do
    beliefs = %{
      "hall" => %{
        "goblin_guard_1" => %{count: 2, last_tick: 4, last_fidelity: 4, seen: true, salience: 0.8},
        "goblin_king" => %{count: 1, last_tick: 3, last_fidelity: 3, seen: true, salience: 0.7}
      }
    }

    pc =
      struct!(Types.Agent, id: "pc", name: "PC", tier: 3, place_id: "hall", beliefs: beliefs)

    named = fn id, name, place ->
      struct!(Types.Agent, id: id, name: name, tier: 3, place_id: place)
    end

    %World{
      places: %{"hall" => %Types.Place{id: "hall", name: "Room hall", kind: :room, connections: []}},
      edges: [],
      agents: %{
        "pc" => pc,
        "goblin_guard_1" => named.("goblin_guard_1", "Goblin Guard", "hall"),
        "goblin_king" => named.("goblin_king", "Goblin King", "hall"),
        "rat_1" => named.("rat_1", "Giant Rat", "crypt")
      }
    }
  end

  test "go <direction> parses to a move action" do
    assert %Types.Action{actor_id: "pc", verb: :move, target_id: nil, params: %{direction: "north"}} =
             Grammar.parse(world(), "pc", "go north")
  end

  test "attack resolves the target by token match against believed agent names" do
    assert %Types.Action{actor_id: "pc", verb: :strike, target_id: "goblin_guard_1"} =
             Grammar.parse(world(), "pc", "attack the goblin guard")
  end

  test "shout captures the quoted message" do
    assert %Types.Action{actor_id: "pc", verb: :shout, params: %{message: "the tower falls!"}} =
             Grammar.parse(world(), "pc", "shout 'the tower falls!'")
  end

  test "wait parses to a wait action" do
    assert %Types.Action{actor_id: "pc", verb: :wait} = Grammar.parse(world(), "pc", "wait")
  end

  test "strike matching two believed agents equally is lethal ambiguity" do
    assert {:ambiguous, ["goblin_guard_1", "goblin_king"]} =
             Grammar.parse(world(), "pc", "attack the goblin")
  end

  test "unmatchable input is unclear with the original rest" do
    assert {:unclear, "dance a jig"} = Grammar.parse(world(), "pc", "dance a jig")
  end

  test "strike with no believed match is unclear" do
    assert {:unclear, "attack the dragon"} = Grammar.parse(world(), "pc", "attack the dragon")
  end
end
