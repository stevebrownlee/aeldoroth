defmodule Agents.DeliberateTest do
  @moduledoc "Brain deliberation: LLM-first, schema-bound, hesitation on failure."
  use ExUnit.Case, async: true
  alias Agents
  alias EngineCore.Types
  alias LLMGateway.{Adapters.Scripted, Ctx, Request}

  @caps [:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee, :order]

  defp slice(agent_id, over \\ %{}) do
    Map.merge(%{
      agent: %{id: agent_id, name: "Grisk", place_id: "chiefs_room"},
      place: %{id: "chiefs_room", name: "Chief's Room", kind: "room",
               exits: ["guard_room"], visible_items: []},
      believed: ["pc_thistle"], salient: ["pc_thistle"],
      commitments: [%{id: "c1", deed: "relocate_treasure_if_alarmed", status: :pending,
                      priority: 8, creditor: nil}],
      capabilities: @caps,
      summary: "Chief's Room. You believe here: a thief."
    }, over)
  end

  defp ctx(entries) do
    %Ctx{routing: %{deliberate: %{adapter: Scripted, model: nil, endpoint: nil,
      key_ref: nil, temperature: 0.1, max_tokens: 512,
      scripts: %{deliberate: entries, salt: System.unique_integer()}}}}
  end

  test "valid proposal parses into a typed action" do
    entry = ~s({"verb":"strike","target_id":"pc_thistle","reason":"intruder in my hall"})
    {:ok, d} = Agents.deliberate("grisk_the_snatcher", %{slice: slice("grisk_the_snatcher"), ctx: ctx([entry])})

    assert d.action == struct!(Types.Action, actor_id: "grisk_the_snatcher",
      verb: :strike, target_id: "pc_thistle")
    assert d.reason == "intruder in my hall"
    assert %Request{class: :deliberate, agent_id: "grisk_the_snatcher"} = d.request
    assert d.audit.ok
  end

  test "verb outside capabilities hesitates (engine double-guards the enum)" do
    entry = ~s({"verb":"fireball","reason":"burn it all"})
    {:hesitate, h} = Agents.deliberate("goblin_bodyguard_1",
      %{slice: slice("goblin_bodyguard_1", %{capabilities: [:move, :wait]}), ctx: ctx([entry])})
    assert h.reason =~ "capability"
  end

  test "router failure (script exhausted) hesitates with failed audit" do
    {:hesitate, h} = Agents.deliberate("grisk_the_snatcher",
      %{slice: slice("grisk_the_snatcher"), ctx: ctx([])})
    assert h.reason == "deliberation unavailable"
    assert h.audit.parse_verdict == :failed
  end

  test "kill then deliberate restarts a fresh brain and still works" do
    Agents.ensure_brain("snaga")
    Agents.kill_brain("snaga")
    entry = ~s({"verb":"wait","reason":"huddle"})
    assert {:ok, _} = Agents.deliberate("snaga",
      %{slice: slice("snaga", %{believed: [], salient: [], commitments: [],
        capabilities: [:move, :wait]}), ctx: ctx([entry])})
  end

  test "prompt carries identity, commitments, salient belief — and no hidden truth" do
    entry = ~s({"verb":"wait","reason":"biding"})
    {:ok, d} = Agents.deliberate("grisk_the_snatcher", %{slice: slice("grisk_the_snatcher"), ctx: ctx([entry])})

    assert d.request.user =~ "pc_thistle"
    assert d.request.user =~ "relocate_treasure_if_alarmed"
    assert d.request.user =~ "Chief's Room"
    refute d.request.user =~ "shadow_touched_skeleton"   # never in the slice
    refute d.request.user =~ "ritual_chamber"
  end

  test "prompt shape: commitments/salient head, state summary last" do
    entry = ~s({"verb":"wait","reason":"biding"})
    {:ok, d} = Agents.deliberate("grisk_the_snatcher", %{slice: slice("grisk_the_snatcher"), ctx: ctx([entry])})
    [head, _summary] = String.split(d.request.user, "Summary:", parts: 2)
    assert head =~ "Commitments:"
    assert head =~ "Salient here:"
  end

  test "prompt includes formatted dossier lines" do
    dossier = %{
      role: "bandit chief",
      personality: "gruff and suspicious",
      goals: ["protect the treasure", "drive off intruders"],
      knowledge: ["pc_thistle is a thief", "the back exit leads east"]
    }
    entry = ~s({"verb":"wait","reason":"biding"})
    {:ok, d} = Agents.deliberate("grisk_the_snatcher",
      %{slice: slice("grisk_the_snatcher", %{dossier: dossier}), ctx: ctx([entry])})

    assert d.request.user =~ "Role: bandit chief"
    assert d.request.user =~ "Personality: gruff and suspicious"
    assert d.request.user =~ "Goals: protect the treasure; drive off intruders"
    assert d.request.user =~ "Knowledge / Rumors: pc_thistle is a thief; the back exit leads east"
  end

  test "prompt formats string-keyed dossier with empty knowledge falling back to rumors" do
    dossier = %{
      "role" => "Innkeeper",
      "personality" => "Warm",
      "goals" => ["Serve ale"],
      "knowledge" => [],
      "rumors" => ["Vaelith's ghost haunts the tower"]
    }
    entry = ~s({"verb":"wait","reason":"biding"})
    {:ok, d} = Agents.deliberate("grisk_the_snatcher",
      %{slice: slice("grisk_the_snatcher", %{dossier: dossier}), ctx: ctx([entry])})

    assert d.request.user =~ "Role: Innkeeper"
    assert d.request.user =~ "Personality: Warm"
    assert d.request.user =~ "Goals: Serve ale"
    assert d.request.user =~ "Knowledge / Rumors: Vaelith's ghost haunts the tower"
  end
  test "no-route deliberation replies to the last addresser with a dossier line" do
    slice =
      slice("mara", %{
        tick: 1,
        dossier: %{"rumors" => ["Green lights flicker from the tower."]},
        recent_speech: [
          %{from_id: "pc_thistle", from_name: "Thistle", words: "any news?", addressed: true, tick: 2}
        ]
      })

    assert {:ok, d} = Agents.deliberate("mara", %{slice: slice, ctx: %Ctx{routing: %{}}})

    assert %Types.Action{verb: :shout, target_id: "pc_thistle"} = d.action
    assert d.action.params.message =~ "Green lights"
    assert d.reason =~ "Thistle"
    assert d.audit.parse_verdict == :fallback and d.audit.adapter == :heuristic
  end

  test "no-route deliberation without an addresser addresses the most salient PC" do
    slice =
      slice("mara", %{
        tick: 1,
        dossier: %{"rumors" => ["Green lights flicker from the tower."]},
        recent_speech: [],
        salient: ["pc_bramble", "pc_thistle"],
        believed_agents: [
          %{id: "pc_thistle", name: "Thistle", pc: true, salience: 0.4},
          %{id: "pc_bramble", name: "Bramble", pc: true, salience: 0.9}
        ]
      })

    assert {:ok, d} = Agents.deliberate("mara", %{slice: slice, ctx: %Ctx{routing: %{}}})

    assert %Types.Action{verb: :shout, target_id: "pc_bramble"} = d.action
  end

  test "prompt carries overheard and addressed speech lines" do
    slice =
      slice("mara", %{
        recent_speech: [
          %{from_id: "pc_thistle", from_name: "Thistle", words: "any news?", addressed: true, tick: 3},
          %{from_id: "pc_bramble", from_name: "Bramble", words: "pass the ale", addressed: false, tick: 2}
        ]
      })

    entry = ~s({"verb":"wait","reason":"biding"})
    {:ok, d} = Agents.deliberate("mara", %{slice: slice, ctx: ctx([entry])})

    assert d.request.user =~ "any news?"
    assert d.request.user =~ "pass the ale"
  end
end
