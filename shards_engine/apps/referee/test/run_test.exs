defmodule Referee.RunTest do
  @moduledoc "Referee.Run — full pipeline against the real tower YAML (plan Task 9)."
  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.Scripted
  alias Referee.{Preferences, Run}

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"}
  ]

  defp interpret_json(verb, extra) do
    Jason.encode!(Map.merge(%{"verb" => verb, "target_id" => nil, "assumptions" => []}, extra))
  end

  defp new_run(interpret \\ [], narrate \\ []) do
    scripts = %{interpret: interpret, narrate: narrate, salt: System.unique_integer()}
    Run.new(@yaml, 42, @pcs, routing: %{interpret: %{adapter: Scripted, scripts: scripts},
                                        narrate: %{adapter: Scripted, scripts: scripts}})
  end

  test "new loads the tower, resolves prefs from the module layer, injects PCs in order" do
    {:ok, run} = new_run()

    assert run.world.agents["pc_thistle"]
    assert run.world.agents["pc_thistle"].place_id == "entry_hall"

    [meta | rest] = Run.events(run)
    assert meta.class == :meta
    assert meta.payload.kind == :prefs_stack
    assert meta.payload.resolved.tone == "grim-but-heroic"
    assert is_binary(meta.payload.hash) and byte_size(meta.payload.hash) == 16
    assert meta.payload.hash == Preferences.hash(meta.payload.resolved)

    assert [%{payload: %{kind: :agent_added, agent: %{id: "pc_thistle"}}}] = rest
  end

  test "declare runs interpret → validate → resolve → react → narrate and ledgers every step" do
    {:ok, run} =
      new_run(
        [interpret_json("move", %{"params" => %{"direction" => "north"}})],
        ["You push north into the library."]
      )

    assert {:ok, text, run2} = Run.declare(run, "pc_thistle", "I head north")
    assert text == "You push north into the library."
    assert run2.world.agents["pc_thistle"].place_id == "library"

    classes = Run.events(run2) |> Enum.map(& &1.class)
    assert :llm in classes and :world in classes

    payloads = Run.events(run2) |> Enum.map(& &1.payload[:kind])
    assert :llm_call in payloads
    assert :move in payloads

    # seq is strictly monotonic across the whole ledger
    seqs = Run.events(run2) |> Enum.map(& &1.seq)
    assert seqs == Enum.sort(seqs) and length(Enum.uniq(seqs)) == length(seqs)
  end

  test "rejected intents diegetically bounce; third same-tick rejection stalls" do
    {:ok, run} = new_run([interpret_json("move", %{"params" => %{"direction" => "up"}})], [])

    {:ok, t1, run2} = Run.declare(run, "pc_thistle", "I go up")
    assert t1 =~ "no way through"

    {:ok, t2, run3} = Run.declare(run2, "pc_thistle", "I go up again")
    assert t2 =~ "no way through"

    assert {:stall, msg, _run4} = Run.declare(run3, "pc_thistle", "I go up once more")
    assert msg =~ "moment passes"
  end

  test "grammar fallback still completes the pipeline when the LLM misreturns" do
    # invalid JSON → router marks parse failure → grammar parses "I head north"
    {:ok, run} = new_run(["{not json"], [])
    assert {:ok, text, run2} = Run.declare(run, "pc_thistle", "I head north")

    assert is_binary(text) and text =~ "north"
    assert run2.world.agents["pc_thistle"].place_id == "library"
  end

  test "advance runs world time and reports per-PC received-signal narrations" do
    # one shout to seed a signal at entry_hall
    {:ok, run} = new_run([interpret_json("shout", %{"params" => %{"message" => "HELLO"}})], [])

    {:ok, _text, run2} = Run.declare(run, "pc_thistle", "I shout HELLO")
    assert {:ok, narrations, run3} = Run.advance(run2)

    assert is_map(narrations)
    assert Run.events(run3) |> length() > Run.events(run2) |> length()
  end

  test "spend_report totals by class and agent" do
    {:ok, run} =
      new_run(
        [interpret_json("move", %{"params" => %{"direction" => "north"}})],
        ["You push north into the library."]
      )

    {:ok, _text, run2} = Run.declare(run, "pc_thistle", "I head north")
    report = Run.spend_report(run2)

    assert report.total.calls == 2
    assert report.by_class.interpret.calls == 1
    assert report.by_class.narrate.calls == 1
    assert report.by_agent["pc_thistle"].calls == 2
  end

  test "identical seeds and scripts replay to an identical ledger (golden determinism)" do
    {:ok, run_a} = new_run([interpret_json("move", %{"params" => %{"direction" => "north"}})], ["north text"])
    {:ok, run_b} = new_run([interpret_json("move", %{"params" => %{"direction" => "north"}})], ["north text"])

    {:ok, _, a} = Run.declare(run_a, "pc_thistle", "I head north")
    {:ok, _, b} = Run.declare(run_b, "pc_thistle", "I head north")

    {:ok, _, a2} = Run.advance(a)
    {:ok, _, b2} = Run.advance(b)

    assert :erlang.term_to_binary(Run.events(a2)) == :erlang.term_to_binary(Run.events(b2))
  end
end
