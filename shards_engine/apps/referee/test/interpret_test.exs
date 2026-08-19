defmodule Referee.InterpretTest do
  @moduledoc "LLM-first interpretation with grammar fallback (plan Task 8)."
  use ExUnit.Case, async: true
  alias EngineCore.Types
  alias EngineCore.World
  alias LLMGateway.{Ctx, Adapters.Scripted}
  alias Referee.Interpret

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
      },
      items: %{
        "gem" => %Types.Item{id: "gem", name: "Gem", value_gp: 500, place_id: "hall", is_hidden: true}
      }
    }
  end

  defp ctx(scripts \\ %{}),
    do: Ctx.from_config(%{interpret: %{adapter: Scripted, scripts: scripts}})

  test "valid LLM JSON action returns ok with audit class interpret" do
    json =
      Jason.encode!(%{
        "verb" => "move",
        "target_id" => nil,
        "params" => %{"direction" => "north"},
        "assumptions" => ["taking 'north' as the entry-hall exit"]
      })

    {:ok, action, assumptions, ctx2, audit} =
      Interpret.nl_to_action(ctx(%{interpret: [json]}), world(), "pc", "I head north")

    assert %Types.Action{actor_id: "pc", verb: :move, params: %{direction: "north"}} = action
    assert assumptions == ["taking 'north' as the entry-hall exit"]
    assert audit.class == :interpret
    assert audit.parse_verdict == :ok
    assert ctx2.budget.spent > 0
  end

  test "adapter error falls back to grammar with parse_verdict fallback" do
    {:ok, action, assumptions, _ctx2, audit} =
      Interpret.nl_to_action(ctx(), world(), "pc", "go south")

    assert %Types.Action{verb: :move, params: %{direction: "south"}} = action
    assert assumptions == ["grammar fallback used"]
    assert audit.parse_verdict == :fallback
    assert audit.ok
  end

  test "grammar ambiguity becomes a lethal-ambiguity clarification" do
    {:clarify, msg, _ctx2, audit} = Interpret.nl_to_action(ctx(), world(), "pc", "attack the goblin")

    assert msg =~ "which one"
    assert msg =~ "Goblin Guard"
    assert msg =~ "Goblin King"
    assert audit.parse_verdict == :fallback
  end

  test "unparseable input becomes a hesitant wait with an assumption" do
    {:ok, action, assumptions, _ctx2, audit} =
      Interpret.nl_to_action(ctx(), world(), "pc", "dance a jig")

    assert %Types.Action{verb: :wait, params: %{hesitant: true}} = action
    assert assumptions == ["could not parse \"dance a jig\"; you hold"]
    assert audit.parse_verdict == :fallback
  end

  test "truth barrier: the prompt carries no other-room agent or hidden item" do
    json = Jason.encode!(%{"verb" => "wait", "assumptions" => []})

    {:ok, _action, _assumptions, _ctx2, _audit} =
      Interpret.nl_to_action(ctx(%{interpret: [json]}), world(), "pc", "I stand still")

    [prompt | _] = Scripted.take_requests() |> Enum.map(& &1.user)

    # other-room agent and hidden item must never reach the model
    refute prompt =~ "rat_1"
    refute prompt =~ "gem"
    # believed agent is present (the barrier hides, it does not blind)
    assert prompt =~ "goblin"
  end
end
