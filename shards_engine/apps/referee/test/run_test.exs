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

  defp new_run(interpret \\ [], narrate \\ [], deliberate \\ []) do
    scripts = %{interpret: interpret, narrate: narrate, deliberate: deliberate, salt: System.unique_integer()}
    routing =
      for class <- [:interpret, :narrate, :deliberate], into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    Run.new(@yaml, 42, @pcs, routing: routing)
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

  test "new wakes starting_place boundary when PCs are injected at maras_inn" do
    pcs = [%{id: "pc_thistle", name: "Thistle", place_id: "maras_inn", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"}]
    {:ok, run} = Run.new(@yaml, 42, pcs)

    assert run.world.boundaries["maras_inn_zone"].state == :awake
    assert run.world.agents["mara"].attention == :alert
    assert run.world.agents["mayor_grevik"].attention == :alert
    assert run.world.agents["erik_the_shepherd"].attention == :alert
    assert run.world.agents["anna_mordale"].attention == :alert

    events = Run.events(run)
    assert Enum.any?(events, &(&1.payload[:kind] == :boundary_wake && &1.payload[:id] == "maras_inn_zone"))
  end
  test "add_pc dynamically injects a new PC with agent_added ledger event and updates world" do
    {:ok, run} = new_run()
    new_pc = %{
      id: "pc_lyra",
      name: "Sister Lyra",
      class: "Cleric",
      race: "Human",
      level: 1,
      hp: 8,
      ac: 5,
      thac0: 20,
      damage: "1d6"
    }

    assert {:ok, pc, run2} = Run.add_pc(run, new_pc)
    assert pc.id == "pc_lyra"
    assert run2.world.agents["pc_lyra"]
    assert run2.world.agents["pc_lyra"].name == "Sister Lyra"
    assert Enum.any?(run2.pcs, &(&1.id == "pc_lyra" || &1[:id] == "pc_lyra"))

    events = Run.events(run2)
    assert Enum.any?(events, fn e ->
      e.class == :world && e.payload[:kind] == :agent_added && e.payload[:agent].id == "pc_lyra"
    end)
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


  test "declare clarification is ledgered as a clarify event" do
    # PC in the guard room believing two indistinguishable guards; the
    # scripted interpret garbage forces the grammar fallback, whose
    # lethal-verb ambiguity (decision 21) yields a clarify, not a guess.
    pcs = [%{id: "pc_thistle", name: "Thistle", place_id: "guard_room", int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}]
    scripts = %{interpret: ["{not json"], narrate: [], salt: System.unique_integer()}
    {:ok, run} = Run.new(@yaml, 42, pcs, routing: %{interpret: %{adapter: Scripted, scripts: scripts},
                                                    narrate: %{adapter: Scripted, scripts: scripts}})
    pc = run.world.agents["pc_thistle"]
    believed = Map.put(pc.beliefs, "guard_room", %{
      "goblin_guard_1" => %{count: 1, seen: true, last_fidelity: 5, last_tick: 0, salience: 6.0},
      "goblin_guard_2" => %{count: 1, seen: true, last_fidelity: 5, last_tick: 0, salience: 6.0}
    })
    run = %{run | world: %{run.world | agents: Map.put(run.world.agents, "pc_thistle", %{pc | beliefs: believed})}}

    assert {:ok, question, run2} = Run.declare(run, "pc_thistle", "attack the goblin")
    assert question =~ "which one"

    clarifies = Run.events(run2) |> Enum.filter(&(&1.class == :clarify))
    assert length(clarifies) == 1
    [ev] = clarifies
    assert ev.payload.kind == :clarify
    assert ev.payload.agent_id == "pc_thistle"
    assert ev.payload.question == question
  end

  test "declare resolution narration is ledgered" do
    {:ok, run} =
      new_run(
        [interpret_json("move", %{"params" => %{"direction" => "north"}})],
        ["You push north into the library."]
      )

    assert {:ok, text, run2} = Run.declare(run, "pc_thistle", "I head north")

    narrations = Run.events(run2) |> Enum.filter(&(&1.class == :narration))
    assert length(narrations) == 1
    [ev] = narrations
    assert ev.payload.kind == :narration
    assert ev.payload.agent_id == "pc_thistle"
    assert ev.payload.text == text
    # narration lands after the world events it describes
    move = Run.events(run2) |> Enum.find(&(&1.payload[:kind] == :move))
    assert ev.seq > move.seq
  end

  test "rejected declarations ledger their refusal narration" do
    {:ok, run} = new_run([interpret_json("move", %{"params" => %{"direction" => "up"}})], [])

    assert {:ok, reason, run2} = Run.declare(run, "pc_thistle", "I go up")

    narrations = Run.events(run2) |> Enum.filter(&(&1.class == :narration))
    assert length(narrations) == 1
    assert hd(narrations).payload.text == reason
  end

  test "advance narrations are ledgered per receiving PC and derive the texts map" do
    pcs = [
      %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall", int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
      %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall", int: 12, ac: 6, hd: 1, hp: 8, thac0: 20, damage: "1d6"}
    ]
    scripts = %{interpret: [], narrate: [], salt: System.unique_integer()}
    {:ok, run} = Run.new(@yaml, 99, pcs, routing: %{interpret: %{adapter: Scripted, scripts: scripts},
                                                    narrate: %{adapter: Scripted, scripts: scripts}})

    assert {:ok, texts, run2} = Run.advance(run)

    narrations = Run.events(run2) |> Enum.filter(&(&1.class == :narration))
    derived = Map.new(narrations, &{&1.payload.agent_id, &1.payload.text})
    assert derived == texts
  end

  test "advance with no receipts ledgers no narration events" do
    {:ok, run} = new_run([interpret_json("move", %{"params" => %{"direction" => "north"}})], ["north text"])
    {:ok, _, run2} = Run.declare(run, "pc_thistle", "I head north")
    {:ok, _, run3} = Run.advance(run2)
    seq0 = run3.seq

    # quiet tick: no new receipts ⇒ no new narration events
    {:ok, _, run4} = Run.advance(run3)
    quiet = Run.events(run4) |> Enum.filter(&(&1.seq > seq0 and &1.class == :narration))
    assert quiet == []
  end

  test "advance rolls 1E initiative and ledgers the initiative dice event" do
    {:ok, run} = new_run()
    {:ok, _texts, run2} = Run.advance(run)

    initiatives =
      Run.events(run2)
      |> Enum.filter(&(&1.class == :dice and &1.payload[:purpose] == :initiative))

    assert length(initiatives) == 1
    [ev] = initiatives
    assert ev.payload.party_roll in 1..6
    assert ev.payload.enemy_roll in 1..6
    assert ev.payload.sides == 6
    assert ev.payload.winner in [:party, :enemy, :simultaneous]
  end

  test "advance attack rolls include thac0 and target AC" do
    deliberate = [
      %{
        agent_id: "goblin_guard_1",
        content:
          ~s({"verb":"shout","target_id":null,"params":{"message":"Intruders!"},"reason":"raise the alarm"})
      }
    ]

    {:ok, run} =
      new_run(
        [
          interpret_json("move", %{"params" => %{"direction" => "east"}}),
          interpret_json("strike", %{"target_id" => "goblin_guard_1"})
        ],
        [],
        deliberate
      )

    assert {:ok, _text, run2} = Run.declare(run, "pc_thistle", "I head east")
    # advance into the guard room; the guard will detect and belief will form
    run3 = advance_until_believed(run2, "guard_room", "goblin_guard_1")
    # strike the guard
    assert {:ok, _text, run4} = Run.declare(run3, "pc_thistle", "I strike the guard")
    # attack resolution happens on the next advance
    assert {:ok, _texts, run5} = Run.advance(run4)

    attacks =
      Run.events(run5)
      |> Enum.filter(&(&1.class == :dice and &1.payload[:purpose] == :attack and &1.payload[:agent_id] == "pc_thistle"))

    assert length(attacks) == 1
    [ev] = attacks
    assert ev.payload.roll in 1..20
    assert ev.payload.sides == 20
    assert is_integer(ev.payload.thac0)
    assert is_integer(ev.payload.target_ac)
    assert ev.payload.hit == (ev.payload.roll >= ev.payload.thac0 - ev.payload.target_ac)
  end

  test "performing a due commitment keeps it: rearm to the every-window, no cadence re-demand" do
    grevik =
      ~s({"verb":"shout","target_id":null,"message":"A hundred gold pieces to whoever investigates the tower.","commitment_id":"grevik_quest_offer","reason":"my due offer"})

    waits = List.duplicate(~s({"verb":"wait","reason":"nothing due"}), 3)
    pcs = [%{id: "pc_thistle", name: "Thistle", place_id: "maras_inn", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"}]
    scripts = %{interpret: [], narrate: [], deliberate: [grevik | waits], salt: System.unique_integer()}

    routing =
      for class <- [:interpret, :narrate, :deliberate], into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    {:ok, run} = Run.new(@yaml, 42, pcs, routing: routing)

    # Tick 1: grevik_quest_offer is due; his brain claims and performs the deed.
    {:ok, _t1, run1} = Run.advance(run)

    assert %{status: :pending, due: 26} =
             Enum.find(run1.world.agents["mayor_grevik"].commitments, &(&1.id == "grevik_quest_offer"))

    assert Enum.any?(Run.events(run1), fn e ->
             e.class == :commitment and e.payload[:kind] == :commitment_kept and
               e.payload[:id] == "grevik_quest_offer" and e.payload[:rearm_due] == 26
           end)

    # Ticks 2-10: nobody's cadence is due (rearm moved grevik to 26).
    run_mid = Enum.reduce(2..10, run1, fn _t, acc ->
      {:ok, _texts, acc2} = Run.advance(acc)
      acc2
    end)

    # Tick 11: Thistle is still in the inn, so a perceived-player is
    # standing pressure — Grevik deliberates again (accepted per-window
    # cost, spec 2026-08-30 §6). The engine guarantee is different: his
    # rearmed commitment is context, not demand — the tick must NOT
    # re-perform the deed (no second keep, due still 26).
    {:ok, _t11, run11} = Run.advance(run_mid)

    at_tick = fn evs, tick -> Enum.filter(evs, &(&1.tick == tick)) end

    grevik_row =
      run11
      |> Run.events()
      |> then(&at_tick.(&1, 11))
      |> Enum.find(&(&1.class == :deliberation and &1.payload[:agent_id] == "mayor_grevik"))

    assert grevik_row.payload[:decision] in [:proposed, :hesitated, :rejected]

    assert %{status: :pending, due: 26} =
             Enum.find(run11.world.agents["mayor_grevik"].commitments, &(&1.id == "grevik_quest_offer"))

    anna_row =
      run11
      |> Run.events()
      |> then(&at_tick.(&1, 11))
      |> Enum.find(&(&1.class == :deliberation and &1.payload[:agent_id] == "anna_mordale"))

    assert anna_row.payload[:decision] == :proposed

    kept =
      Enum.count(Run.events(run11), &(&1.class == :commitment and &1.payload[:kind] == :commitment_kept and
                                         &1.payload[:id] == "grevik_quest_offer"))

    assert kept == 1
  end

  test "a brain cannot keep another agent's commitment by claiming its id" do
    bogus =
      ~s({"verb":"shout","target_id":null,"message":"Plea!","commitment_id":"anna_rescue_plea","reason":"foreign claim"})

    anna_wait = ~s({"verb":"wait","reason":"nothing due"})
    waits = List.duplicate(anna_wait, 3)

    pcs = [
      %{id: "pc_thistle", name: "Thistle", place_id: "maras_inn", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"}
    ]
    # Scripted queues are per-brain (each process pops from index 0): key
    # Anna's entry to her agent so a NON-debtor consumes the bogus claim.
    scripts = %{
      interpret: [],
      narrate: [],
      deliberate: [%{agent_id: "anna_mordale", content: anna_wait}, bogus | waits],
      salt: System.unique_integer()
    }

    routing =
      for class <- [:interpret, :narrate, :deliberate], into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    {:ok, run} = Run.new(@yaml, 42, pcs, routing: routing)
    {:ok, _t1, run1} = Run.advance(run)

    anna_c = Enum.find(run1.world.agents["anna_mordale"].commitments, &(&1.id == "anna_rescue_plea"))
    assert %{status: :pending, due: 2} = anna_c

    refute Enum.any?(Run.events(run1), &(&1.payload[:kind] == :commitment_kept))
  end

  test "a fresh address pulls the addressee's cadence: round 2 reply lands next tick" do
    # Round 1 works only because every inn hook is due at tick 1. Round 2 is
    # the real conversational contract: a player addresses the same NPC again
    # between cadence windows and the reply must still arrive one tick later.
    erik_r1 =
      %{agent_id: "erik_the_shepherd",
        content: ~s({"verb":"shout","target_id":"pc_thistle","message":"Aye, the flock's thin.","reason":"addressed"})}

    erik_r2 =
      %{agent_id: "erik_the_shepherd",
        content: ~s({"verb":"shout","target_id":"pc_thistle","message":"Three sheep gone to the green devils.","reason":"addressed again"})}

    others =
      for id <- ["anna_mordale", "mara", "mayor_grevik"] do
        %{agent_id: id, content: ~s({"verb":"wait","reason":"not addressed"})}
      end

    interpret = [
      ~s({"verb":"shout","target_id":"erik_the_shepherd","params":{"message":"how is your flock?"},"assumptions":[]}),
      ~s({"verb":"shout","target_id":"erik_the_shepherd","params":{"message":"how bad is it really?"},"assumptions":[]})
    ]

    pcs = [
      %{id: "pc_thistle", name: "Thistle", place_id: "maras_inn", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"}
    ]

    scripts = %{
      interpret: interpret,
      narrate: [],
      deliberate: [erik_r1, erik_r2 | others],
      salt: System.unique_integer()
    }

    routing =
      for class <- [:interpret, :narrate, :deliberate], into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    {:ok, run} = Run.new(@yaml, 42, pcs, routing: routing)
    {:ok, _reply, run1} = Run.declare(run, "pc_thistle", "Erik, how is your flock?")
    {:ok, _r1_texts, run2} = Run.advance(run1)

    # Round 2: address Erik again while every cadence is parked at its
    # rearmed window — the reply must still land one tick later.
    {:ok, _reply, run3} = Run.declare(run2, "pc_thistle", "Erik, how bad is it really?")
    {:ok, texts, run3} = Run.advance(run3)
    t = run3.world.tick

    row =
      Run.events(run3)
      |> Enum.find(&(&1.tick == t and &1.class == :deliberation and
                       &1.payload[:agent_id] == "erik_the_shepherd"))

    assert row.payload[:decision] == :proposed

    # Nobody else was addressed; their brains stay parked until their window.
    refute Enum.any?(Run.events(run3), fn ev ->
      ev.tick == t and ev.class == :deliberation and
        ev.payload[:agent_id] in ["anna_mordale", "mara", "mayor_grevik"]
    end)

    assert texts["pc_thistle"] =~ "Three sheep gone"
  end

  defp advance_until_believed(run, place, about, n \\ 20) do
    pc = run.world.agents["pc_thistle"]

    if get_in(pc.beliefs, [place, about]) != nil do
      run
    else
      n > 0 || flunk("belief in #{about} never formed")
      {:ok, _texts, run2} = Run.advance(run)
      advance_until_believed(run2, place, about, n - 1)
    end
  end
end
