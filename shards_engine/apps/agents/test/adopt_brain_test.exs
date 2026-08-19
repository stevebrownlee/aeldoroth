defmodule Agents.AdoptBrainTest do
  @moduledoc "Adoption through the brain: LLM-first, heuristic fallback, truth barrier."
  use ExUnit.Case, async: true
  alias Agents
  alias LLMGateway.{Adapters.Scripted, Ctx, Request}

  @env %{id: "env-0-1", from: "grisk_the_snatcher", to: "goblin_bodyguard_1",
         type: :order, payload_nl: "Kill the intruder!", sent_tick: 3,
         delivery_place: "chiefs_room", signal_ref: 1, truth: :unverified,
         adopted: nil, status: :delivered}

  defp slice do
    %{
      agent: %{id: "goblin_bodyguard_1", name: "Goblin Bodyguard", place_id: "chiefs_room"},
      place: %{id: "chiefs_room", name: "Chief's Room", kind: "room",
               exits: ["guard_room"], visible_items: []},
      believed: ["grisk_the_snatcher"], salient: ["grisk_the_snatcher"],
      commitments: [],
      capabilities: [:move, :strike, :wait, :shout, :obey, :flee],
      summary: "Chief's Room. You believe here: Grisk."
    }
  end

  defp ctx(entries) do
    %Ctx{routing: %{adopt: %{adapter: Scripted, model: nil, endpoint: nil,
      key_ref: nil, temperature: 0.1, max_tokens: 512,
      scripts: %{adopt: entries, salt: System.unique_integer()}}}}
  end

  defp entry(content), do: %{agent_id: "goblin_bodyguard_1", content: content}

  defp msg(over \\ %{}) do
    Map.merge(%{envelope: @env, slice: slice(), ctx: ctx([]), roll: 5,
                feasible: true, debtor: %{statblock: %{morale: 8, int: 10}}}, over)
  end

  test "LLM adopt: typed decision with audit" do
    script = entry(~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of Grisk"}))
    {:ok, d} = Agents.adopt("goblin_bodyguard_1", msg(%{ctx: ctx([script])}))

    assert d.adopted == true
    assert d.deed == "slay the intruder"
    assert d.deceive == false and d.inform == nil
    assert d.reason == "fear of Grisk"
    assert %Request{class: :adopt, agent_id: "goblin_bodyguard_1"} = d.request
    assert d.audit.ok and d.audit.parse_verdict == :ok
  end

  test "LLM adopt: deception passes through" do
    script = entry(~s({"adopted":false,"deceive":true,"inform":"Done, boss.","reason":"too scared"}))
    {:ok, d} = Agents.adopt("goblin_bodyguard_1", msg(%{ctx: ctx([script])}))

    assert d.adopted == false
    assert d.deceive == true
    assert d.inform == "Done, boss."
    assert d.reason == "too scared"
  end

  test "router failure falls back to the heuristic: roll under target adopts" do
    {:ok, d} = Agents.adopt("goblin_bodyguard_1", msg(%{roll: 5}))

    assert d.adopted
    assert d.deed == @env.payload_nl
    assert d.deceive == false and d.inform == nil
    assert d.reason =~ "heuristic"
    assert d.audit.adapter == :heuristic
    assert d.audit.parse_verdict == :fallback and d.audit.ok
  end

  test "heuristic fallback: roll over target rejects" do
    {:ok, d} = Agents.adopt("goblin_bodyguard_1", msg(%{roll: 20}))

    refute d.adopted
    assert d.audit.parse_verdict == :fallback
  end

  test "truth barrier: the prompt carries the order and debtor identity, never truth" do
    script = entry(~s({"adopted":true,"deed":"slay","deceive":false,"reason":"fear"}))
    {:ok, d} = Agents.adopt("goblin_bodyguard_1", msg(%{ctx: ctx([script])}))

    assert d.request.user =~ "Kill the intruder!"
    assert d.request.user =~ "grisk_the_snatcher"
    assert d.request.user =~ "goblin_bodyguard_1"
    refute d.request.user =~ ":unverified"
    refute inspect(d.request) =~ "truth"
    refute Map.has_key?(d.request.schema.properties, :truth)
  end
end
