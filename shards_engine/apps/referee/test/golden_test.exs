defmodule Referee.GoldenTest do
  @moduledoc """
  Golden replay determinism (plan Task 10): identical tower YAML + seed +
  PC spec + scripted LLM queues ⇒ byte-identical ledgers. A different seed
  must diverge (RNG-branch evidence).

  The intent script is linear — every LLM response is valid JSON for its
  intent, and exactly one garbage response forces the grammar fallback that
  exercises the stale-belief strike path. Ambiguity/clarify mechanics and
  their queue effects live in grammar_test/interpret_test; this test proves
  replay determinism only.
  """

  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall", int: 9, ac: 6, hd: 1, hp: 6, thac0: 20, damage: "1d6"}
  ]

  # One response per Router ATTEMPT, in order. The Router retries once on
  # schema-invalid output, so forcing a grammar fallback needs TWO garbage
  # items (attempt 0 and the bounded retry both fail). Intent 2 then falls
  # back to grammar, resolves against the seeded (stale) belief, and
  # corrects it. The guard actually stands in guard_room, so the belief IS
  # stale from tick 0.
  @interpret [
    ~s({"verb":"shout","target_id":null,"params":{"message":"HELLO"},"assumptions":[]}),
    "garbage {",
    "garbage {",
    ~s({"verb":"move","target_id":null,"params":{"direction":"north"},"assumptions":[]}),
    ~s({"verb":"wait","target_id":null,"params":{},"assumptions":[]})
  ]

  @intents ["I shout HELLO", "I strike goblin guard 1", "I head north", "I wait"]

  test "identical seed + scripts replay to a byte-identical ledger" do
    {:ok, a} = play(salt: 1, seed: 42)
    {:ok, b} = play(salt: 2, seed: 42)

    # salt changes only the scripts-map identity (process-dict key), not the
    # responses; the ledgers must match byte-for-byte.
    assert :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(b))
    assert Run.events(a) == Run.events(b)

    kinds = Run.events(a) |> Enum.map(& &1.payload[:kind])

    # the stale-belief strike corrected the seeded belief and spent a swing
    assert :belief_corrected in kinds
    assert Enum.any?(Run.events(a), &(&1.class == :dice and &1.payload[:purpose] == :stale_swing))
    # the linear move succeeded
    assert :move in kinds
    # first event is the resolved preference stack (run provenance)
    assert hd(Run.events(a)).payload[:kind] == :prefs_stack
  end

  test "a different seed diverges the ledger" do
    {:ok, a} = play(salt: 3, seed: 42)
    {:ok, c} = play(salt: 4, seed: 43)

    refute :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(c))
  end

  defp play(salt: salt, seed: seed) do
    scripts = %{interpret: @interpret, narrate: Enum.map(1..6, &"narrated #{&1}"), salt: salt}

    {:ok, run} =
      Run.new(@yaml, seed, @pcs,
        routing: %{interpret: %{adapter: Scripted, scripts: scripts}, narrate: %{adapter: Scripted, scripts: scripts}}
      )

    # Seed one stale belief: the PC believes goblin_guard_1 is in entry_hall.
    # (The guard actually stands in guard_room.)
    belief = %{count: 1, last_tick: 0, last_fidelity: 3, seen: false, salience: 0.7}
    pc = run.world.agents["pc_thistle"]
    here = Map.put(pc.beliefs["entry_hall"] || %{}, "goblin_guard_1", belief)
    pc2 = %{pc | beliefs: Map.put(pc.beliefs, "entry_hall", here)}
    run = %{run | world: %{run.world | agents: Map.put(run.world.agents, "pc_thistle", pc2)}}

    run =
      Enum.reduce(@intents, run, fn utterance, acc ->
        {:ok, _text, run2} = Run.declare(acc, "pc_thistle", utterance)
        run2
      end)

    {:ok, _narrations, run} = Run.advance(run)
    {:ok, run}
  end
end
