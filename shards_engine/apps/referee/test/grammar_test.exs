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

  defp inn_world do
    beliefs = %{
      "common_room" => %{
        "mara" => %{count: 1, last_tick: 2, last_fidelity: 4, seen: true, salience: 0.5},
        "patron_erik" => %{count: 3, last_tick: 2, last_fidelity: 3, seen: true, salience: 0.9}
      }
    }

    pc =
      struct!(Types.Agent, id: "pc", name: "PC", tier: 3, place_id: "common_room", beliefs: beliefs)

    mk = fn id, name, role ->
      a = struct!(Types.Agent, id: id, name: name, tier: 3, place_id: "common_room")
      if role, do: Map.put(a, :dossier, %{"role" => role}), else: a
    end

    %World{
      places: %{
        "common_room" => %Types.Place{id: "common_room", name: "Common Room", kind: :room, connections: []}
      },
      edges: [],
      agents: %{
        "pc" => pc,
        "mara" => mk.("mara", "Mara", "innkeeper"),
        "patron_erik" => mk.("patron_erik", "Erik the Shepherd", "patron")
      }
    }
  end

  test "go <direction> parses to a move action" do
    assert %Types.Action{actor_id: "pc", verb: :move, target_id: nil, params: %{direction: "north"}} =
             Grammar.parse(world(), "pc", "go north")
  end

  test "bare directions and abbreviations parse to move actions" do
    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "north"}} =
             Grammar.parse(world(), "pc", "north")
    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "east"}} =
             Grammar.parse(world(), "pc", "e")
    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "down"}} =
             Grammar.parse(world(), "pc", "down")
  end

  test "movement with natural prepositions parses cleanly" do
    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "north"}} =
             Grammar.parse(world(), "pc", "I walk to the north")
    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "east"}} =
             Grammar.parse(world(), "pc", "head into the east")
  end

  test "observation and search verbs parse to observant wait actions" do
    assert %Types.Action{actor_id: "pc", verb: :wait} = Grammar.parse(world(), "pc", "look around")
    assert %Types.Action{actor_id: "pc", verb: :wait} = Grammar.parse(world(), "pc", "search for traps")
    assert %Types.Action{actor_id: "pc", verb: :wait} = Grammar.parse(world(), "pc", "examine the room")
    assert %Types.Action{actor_id: "pc", verb: :wait} = Grammar.parse(world(), "pc", "listen carefully")
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

  test "talk/ask/say to an addressee parse to directed shouts" do
    assert %Types.Action{actor_id: "pc", verb: :shout, target_id: "goblin_king", params: %{message: ""}} =
             Grammar.parse(world(), "pc", "talk to goblin king")

    assert %Types.Action{actor_id: "pc", verb: :shout, target_id: "goblin_king", params: %{message: "about the tower"}} =
             Grammar.parse(world(), "pc", "ask goblin king about the tower")

    # quoted speech without an addressee stays ambient broadcast
    assert %Types.Action{actor_id: "pc", verb: :shout, target_id: nil, params: %{message: "hello there"}} =
             Grammar.parse(world(), "pc", ~s(say "hello there"))
  end

  test "buy addresses the room's service provider, never a guess" do
    assert %Types.Action{actor_id: "pc", verb: :shout, target_id: "mara", params: %{message: "a drink"}} =
             Grammar.parse(inn_world(), "pc", "buy a drink")

    assert %Types.Action{actor_id: "pc", verb: :shout, target_id: "mara", params: %{message: "an ale"}} =
             Grammar.parse(inn_world(), "pc", "buy an ale from mara")

    # no believed provider in the room is unclear, not a salience pick
    assert {:unclear, "buy a drink"} = Grammar.parse(world(), "pc", "buy a drink")
  end
end
