defmodule Referee.AcceptanceTest do
  @moduledoc """
  Unit proofs for the acceptance analysis lib (plan 6 Task 1): each §13
  checker against hand-built ledger fixtures with known structure, so a
  harness failure later means the run changed, not the checker.
  """
  use ExUnit.Case, async: true

  alias EngineCore.Types
  alias EngineCore.World
  alias Referee.Acceptance
  alias Referee.Spend

  ## 13.3 — first_divergence / llm_root?

  test "first_divergence: equal ledgers are identical" do
    a = [row(1, :world, %{kind: :tick}), row(2, :dice, %{purpose: :to_hit})]
    assert Acceptance.first_divergence(a, a) == :identical
  end

  test "first_divergence: first differing index with both rows" do
    a = [row(1, :world, %{kind: :t}), row(2, :dice, %{purpose: :to_hit, roll: 5})]
    b = [row(1, :world, %{kind: :t}), row(2, :dice, %{purpose: :to_hit, roll: 12})]

    assert %{index: 1, a: a_row, b: b_row} = Acceptance.first_divergence(a, b)
    assert a_row.payload[:roll] == 5
    assert b_row.payload[:roll] == 12
  end

  test "first_divergence: seq renumbering never counts as divergence; length does" do
    a = [row(1, :world, %{kind: :t}), row(2, :world, %{kind: :t})]
    b = [row(7, :world, %{kind: :t}), row(9, :world, %{kind: :t}), row(10, :world, %{kind: :t})]

    assert %{index: 2, a: :absent} = Acceptance.first_divergence(a, b)
  end

  test "llm_root? classifies fork roots" do
    assert Acceptance.llm_root?(%{class: :llm})
    assert Acceptance.llm_root?(%{class: :clarify})
    assert Acceptance.llm_root?(%{class: :deliberation, decision: :proposed})
    refute Acceptance.llm_root?(%{class: :dice, purpose: :to_hit})
    refute Acceptance.llm_root?(nil)
  end

  ## 13.2 — receipt_chain

  defp chain_events do
    [
      row(1, :envelope, %{
        kind: :envelope_sent,
        envelope: %{
          id: "env-5-1",
          from: "grisk",
          to: "gob",
          type: :order,
          payload_nl: "slay the intruder",
          signal_ref: "sig-abc123",
          sent_tick: 5,
          delivery_place: "chiefs_room",
          truth: :unverified
        }
      }),
      row(2, :world, %{
        kind: :signal_received,
        agent_id: "gob",
        place_id: "chiefs_room",
        ref: "sig-abc123",
        about: "grisk",
        signal_kind: :sound,
        intensity: 6.0
      }),
      row(3, :envelope, %{kind: :envelope_delivered, id: "env-5-1"}),
      row(4, :llm, %{
        kind: :llm_call,
        class: :adopt,
        agent_id: "gob",
        adapter: :scripted,
        tokens_in: 10,
        tokens_out: 4,
        parse_verdict: :ok,
        ok: true
      }),
      row(5, :dice, %{
        purpose: :adoption,
        agent_id: "gob",
        sides: 20,
        roll: 14,
        target: 11,
        adopted: true
      }),
      row(6, :envelope, %{kind: :envelope_adopted, id: "env-5-1"}),
      row(7, :commitment, %{
        kind: :commitment_created,
        commitment: %{id: "adopted:env-5-1", debtor: "gob", deed: "slay", due: nil, priority: 7}
      }),
      row(8, :deliberation, %{
        kind: :decision,
        agent_id: "gob",
        decision: :proposed,
        verb: :strike,
        target_id: "pc_thistle"
      }),
      row(9, :dice, %{purpose: :to_hit, agent_id: "gob", sides: 20, roll: 18, hit: true}),
      row(10, :world, %{kind: :damage, target_id: "pc_thistle", amount: 4})
    ]
  end

  test "receipt_chain: full adopted cascade links in strictly increasing seq" do
    {:ok, links} = Acceptance.receipt_chain(chain_events(), "env-5-1")

    assert Enum.map(links, & &1.kind) ==
             [
               :envelope_sent,
               :signal_received,
               :envelope_delivered,
               :adopt_audit,
               :adoption_dice,
               :envelope_adopted,
               :commitment_created,
               :proposed,
               :to_hit,
               :damage
             ]

    seqs = Enum.map(links, & &1.seq)
    assert seqs == Enum.sort(seqs)
    assert Enum.dedup(seqs) == seqs

    sent = Enum.at(links, 0)
    assert sent.summary =~ "grisk → gob"
    assert sent.summary =~ "slay the intruder"

    damage = Enum.at(links, 9)
    assert damage.summary =~ "pc_thistle"
  end

  test "receipt_chain: a miss (damage absent) is still a complete emergent attack" do
    events = Enum.reject(chain_events(), &(&1.payload[:kind] == :damage))

    {:ok, links} = Acceptance.receipt_chain(events, "env-5-1")
    assert List.last(links).kind == :to_hit
  end

  test "receipt_chain: rejected verdict truncates cleanly after the verdict link" do
    events =
      chain_events()
      |> Enum.map(fn
        %{seq: 5, payload: %{adopted: true} = p} ->
          %{seq: 5, tick: 1, class: :dice, payload: %{p | adopted: false}}

        %{seq: 6, payload: %{kind: :envelope_adopted} = p} ->
          %{seq: 6, tick: 1, class: :envelope, payload: %{p | kind: :envelope_rejected}}

        ev ->
          ev
      end)
      |> Enum.reject(&(&1.seq > 6))

    {:ok, links} = Acceptance.receipt_chain(events, "env-5-1")
    assert List.last(links).kind == :envelope_rejected
  end

  test "receipt_chain: names the first missing link" do
    events = Enum.reject(chain_events(), &(&1.payload[:kind] == :envelope_delivered))

    assert {:error, {:missing, :envelope_delivered, 2}} =
             Acceptance.receipt_chain(events, "env-5-1")
  end

  test "receipt_chain: unknown envelope id" do
    assert {:error, {:missing, :envelope_sent, 0}} =
             Acceptance.receipt_chain(chain_events(), "env-9-9")
  end

  ## 13.4 — truth barrier

  defp barrier_world do
    near = struct!(Types.Place, id: "hall", name: "HALL", kind: :room, connections: [])
    far = struct!(Types.Place, id: "crypt", name: "CRYPT", kind: :room, connections: [])

    agent = fn id, name, place ->
      struct!(Types.Agent,
        id: id,
        name: name,
        tier: 3,
        place_id: place,
        body: %{hp: 5, conditions: []}
      )
    end

    struct!(
      World,
      places: %{"hall" => near, "crypt" => far},
      agents: %{
        "gob" => agent.("gob", "GOBLIN", "hall"),
        "thistle" => agent.("thistle", "THISTLE", "hall"),
        "wight" => agent.("wight", "BARROW-WIGHT", "crypt")
      }
    )
  end

  defp captured(world, prompt, actor_id, class \\ :deliberate) do
    [
      %{
        req: %{agent_id: actor_id, class: class, system: prompt, user: ""},
        world: world,
        events: []
      }
    ]
  end

  test "locality_violations: a distant agent's name in a prompt is a leak" do
    world = barrier_world()

    assert [%{req_index: 0, agent_id: "gob", class: :deliberate, leaked: "BARROW-WIGHT"}] =
             Acceptance.locality_violations(
               captured(world, "You sense BARROW-WIGHT stirring.", "gob")
             )
  end

  test "locality_violations: a believed same-place agent's name comes from the slice — allowed" do
    world = barrier_world()

    world =
      update_in(world.agents["gob"], fn gob ->
        %{gob | beliefs: %{"hall" => %{"thistle" => %{seen: true, salience: 0.9}}}}
      end)

    assert [] = Acceptance.locality_violations(captured(world, "THISTLE stands in HALL.", "gob"))
  end

  test "locality_violations: a same-place but never-perceived agent's name is still a leak" do
    world = barrier_world()

    assert [%{agent_id: "gob", leaked: "THISTLE"}] =
             Acceptance.locality_violations(captured(world, "THISTLE stands in HALL.", "gob"))
  end

  test "locality_violations: the actor's own name is never a leak" do
    world = barrier_world()
    assert [] = Acceptance.locality_violations(captured(world, "You are GOBLIN.", "gob"))
  end

  test "locality_violations: actorless requests (interpret) are skipped" do
    world = barrier_world()
    assert [] = Acceptance.locality_violations(captured(world, "BARROW-WIGHT", nil, :interpret))
  end

  test "locality_violations: NL of a received signal enters the allowed blob" do
    world = barrier_world()

    events = [
      row(1, :world, %{
        kind: :signal_emitted,
        ref: "sig-1",
        content_nl: "a voice cries BARROW-WIGHT"
      }),
      row(2, :world, %{kind: :signal_received, agent_id: "gob", ref: "sig-1", place_id: "hall"})
    ]

    captured = [
      %{
        req: %{
          agent_id: "gob",
          class: :deliberate,
          system: "You heard BARROW-WIGHT named.",
          user: ""
        },
        world: world,
        events: events
      }
    ]

    assert [] = Acceptance.locality_violations(captured)
  end

  test "hidden_leaks: hidden item names banned from every prompt regardless of actor" do
    world =
      struct!(
        barrier_world(),
        items: %{
          "ring" =>
            struct!(Types.Item,
              id: "ring",
              name: "Twin-Keyed Locket",
              value_gp: 250,
              is_hidden: true
            ),
          "potion" => struct!(Types.Item, id: "potion", name: "Healing Draught", value_gp: 50)
        }
      )

    captured = [
      %{
        req: %{agent_id: nil, class: :interpret, system: "open the Twin-Keyed Locket", user: ""},
        world: world,
        events: []
      },
      %{
        req: %{agent_id: "gob", class: :deliberate, system: "You see a Healing Draught", user: ""},
        world: world,
        events: []
      }
    ]

    assert [%{req_index: 0, class: :interpret, leaked: "Twin-Keyed Locket"}] =
             Acceptance.hidden_leaks(captured, world)
  end

  ## 13.5 — spend invariants and capped degradation

  defp llm_row(seq, class, verdict, tokens) do
    row(seq, :llm, %{
      kind: :llm_call,
      class: class,
      agent_id: "pc_thistle",
      adapter: :scripted,
      tokens_in: elem(tokens, 0),
      tokens_out: elem(tokens, 1),
      parse_verdict: verdict,
      ok: verdict in [:ok, :retry_ok]
    })
  end

  test "spend_invariants: report reconciles with its llm rows" do
    events = [
      llm_row(1, :interpret, :ok, {10, 5}),
      llm_row(2, :narrate, :ok, {20, 8}),
      llm_row(3, :deliberate, :ok, {30, 6})
    ]

    assert :ok = Acceptance.spend_invariants(Spend.report(events), events)
  end

  test "spend_invariants: a drifted report is named" do
    events = [llm_row(1, :interpret, :ok, {10, 5})]
    report = Spend.report(events)
    drifted = put_in(report, [:total, :tokens_in], 999)

    assert {:error, msg} = Acceptance.spend_invariants(drifted, events)
    assert msg =~ "tokens_in"
  end

  test "capped_consistency: narrate degrades at the cap, interpret survives to 2×" do
    # each successful call spends 15 tokens; cap 100
    events = [
      llm_row(1, :interpret, :ok, {10, 5}),
      llm_row(2, :narrate, :ok, {10, 5}),
      llm_row(3, :narrate, :ok, {10, 5}),
      llm_row(4, :deliberate, :ok, {10, 5}),
      llm_row(5, :narrate, :ok, {10, 5}),
      llm_row(6, :narrate, :ok, {10, 5}),
      llm_row(7, :narrate, :ok, {10, 5}),
      llm_row(8, :narrate, :fallback, {0, 0}),
      llm_row(9, :interpret, :ok, {10, 5}),
      llm_row(10, :narrate, :fallback, {0, 0})
    ]

    assert :ok = Acceptance.capped_consistency(events, 100)
  end

  test "capped_consistency: an :ok narrate served past the cap fails" do
    events = [
      llm_row(1, :narrate, :ok, {60, 50}),
      llm_row(2, :narrate, :ok, {10, 5})
    ]

    assert {:error, msg} = Acceptance.capped_consistency(events, 100)
    assert msg =~ "past the cap"
  end

  test "capped_consistency: no degradation evidence past the cap fails" do
    events = [llm_row(1, :narrate, :ok, {10, 5})]

    assert {:error, msg} = Acceptance.capped_consistency(events, 100)
    assert msg =~ "budget"
  end

  test "capped_consistency: degraded brains are an invariant failure" do
    # interpret survives the whole 2× window (before 0 ≤ 0) and its spend
    # pushes cumulative past the cap so the narrate fallback engages.
    events = [
      llm_row(1, :interpret, :ok, {10, 5}),
      llm_row(2, :narrate, :fallback, {0, 0}),
      llm_row(3, :deliberate, :fallback, {0, 0})
    ]

    assert {:error, msg} = Acceptance.capped_consistency(events, 0)
    assert msg =~ "brains must never starve"
  end

  ## fixture

  defp row(seq, class, payload), do: %{seq: seq, tick: 1, class: class, payload: payload}

  ###########################################################################
  # §13 proofs on the real adventure (plan 6 Task 2). The playthrough mirrors
  # brains_golden_test: two declares carry Thistle into the chief's room; 20
  # advances let grisk's escalation → order → delivery → adoption → strike
  # cascade play out under scripted LLM queues.
  ###########################################################################

  alias EngineCore.Loader
  alias LLMGateway.Adapters.Scripted
  alias Agents.Prompt
  alias Referee.{Run, Slice}

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}
  ]

  @interpret [
    ~s({"verb":"move","target_id":null,"params":{"direction":"east"},"assumptions":[]}),
    ~s({"verb":"move","target_id":null,"params":{"direction":"south"},"assumptions":[]})
  ]

  @deliberate [
    %{agent_id: "goblin_bodyguard_1",
      content: ~s({"verb":"strike","target_id":"pc_thistle","reason":"obeying orders"})},
    %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"guarding the chief"})},
    %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"still guarding"})},
    %{agent_id: "grisk_the_snatcher",
      content: ~s({"verb":"order","target_id":"goblin_bodyguard_1","message":"Kill the intruder!","reason":"intruders in my hall"})},
    %{agent_id: "grisk_the_snatcher", content: ~s({"verb":"wait","reason":"my will is done"})},
    %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"still on watch"})}
  ]

  @adopt [
    %{agent_id: "goblin_bodyguard_1",
      content: ~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"})}
  ]
  @narrate_line "Dust sifts through the ruined shaft; the moment holds."

  # Fork B: identical queue except the bodyguard's one deliberate reply —
  # a cautious persona that waits instead of striking (§13.3, §13.6).
  defp deliberate_wait do
    Enum.map(@deliberate, fn
      %{agent_id: "goblin_bodyguard_1"} = e ->
        %{e | content: ~s({"verb":"wait","target_id":null,"reason":"cautious persona"})}

      e ->
        e
    end)
  end

  # Runs the playthrough, returning {run, %{captured: [...], marks: [seqs]}}.
  # `captured` (only with capture: true) pairs every gateway request drained
  # after a phase with the post-phase world + ledger — beliefs only grow
  # within a phase, so post-phase snapshots are the permissive pairing.
  # `marks` is run.seq after each phase (declare×2, advance×20).
  defp play(opts) do
    salt = Keyword.fetch!(opts, :salt)
    seed = Keyword.fetch!(opts, :seed)
    deliberate = Keyword.get(opts, :deliberate, @deliberate)
    capture? = Keyword.get(opts, :capture, false)
    cap = Keyword.get(opts, :cap)

    scripts = %{
      interpret: @interpret,
      narrate: List.duplicate(@narrate_line, 64),
      deliberate: deliberate,
      adopt: @adopt,
      salt: salt
    }

    cfg = %{adapter: Scripted, scripts: scripts}
    routing = %{interpret: cfg, narrate: cfg, deliberate: cfg, adopt: cfg}

    {:ok, run} = Run.new(@yaml, seed, @pcs, routing: routing)
    run = if cap, do: cap_ctx(run, cap), else: run

    steps = [
      {:declare, "pc_thistle", "go east"},
      {:declare, "pc_thistle", "go south"}
      | List.duplicate(:advance, 20)
    ]

    Enum.reduce(steps, {run, %{captured: [], marks: []}}, fn
      {:declare, pc, text}, {pre, info} ->
        {:ok, _t, post} = Run.declare(pre, pc, text)
        close_phase(post, pre, info, capture?)

      :advance, {pre, info} ->
        {:ok, _n, post} = Run.advance(pre)
        close_phase(post, pre, info, capture?)
    end)
  end

  defp close_phase(post, pre, info, capture?) do
    reqs = Scripted.take_requests()

    info =
      info
      |> Map.update!(:marks, &[post.seq | &1])
      |> maybe_capture(capture?, pre, post, reqs)

    {post, info}
  end

  defp maybe_capture(info, false, _pre, _post, _reqs), do: info

  # Prompts are built mid-phase (interpret before the move lands, deliberate
  # between scheduler and resolve); we can only drain requests at boundaries,
  # so each capture carries the [pre, post] bracket — locality_violations
  # counts a leak only against every bracket world.
  defp maybe_capture(info, true, pre, post, reqs) do
    evs = Run.events(post)
    added = Enum.map(Enum.reverse(reqs), &%{req: &1, world: [pre.world, post.world], events: evs})
    Map.update!(info, :captured, &(&1 ++ added))
  end

  defp cap_ctx(run, cap),
    do: %{run | ctx: %{run.ctx | budget: %{run.ctx.budget | cap: cap}}}

  test "13.1/13.3: verbatim double-run replays to a byte-identical ledger" do
    {a, _} = play(salt: 1, seed: 42)
    {b, _} = play(salt: 2, seed: 42)

    assert :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(b))
    assert a.world.tick == b.world.tick
    assert a.world.agents == b.world.agents
  end

  test "13.3/13.6: persona fork — prefix identical, root is LLM, outcomes split" do
    {a, _} = play(salt: 3, seed: 42)
    {b, _} = play(salt: 4, seed: 42, deliberate: deliberate_wait())

    evs_a = Run.events(a)
    evs_b = Run.events(b)

    div = Acceptance.first_divergence(evs_a, evs_b)
    assert div.index > 0

    # The fork root is the bodyguard's adopt-free deliberate call itself: the
    # :llm audit row (token counts differ) lands before the decision row.
    assert Acceptance.llm_root?(div.a)
    assert Acceptance.llm_root?(div.b)
    assert div.a.class == :llm
    assert div.a.payload[:class] == :deliberate
    assert div.a.payload[:agent_id] == "goblin_bodyguard_1"

    dec_a = Enum.at(evs_a, div.index + 1)
    dec_b = Enum.at(evs_b, div.index + 1)
    assert dec_a.class == :deliberation
    assert dec_a.payload[:verb] == :strike
    assert dec_b.class == :deliberation
    assert dec_b.payload[:verb] == :wait
    assert dec_b.payload[:reason] == "cautious persona"

    # Material split: the attack (and its dice) exists only in A.
    assert attack_count(evs_a) == 1
    assert attack_count(evs_b) == 0
  end

  test "13.2: grisk's order leaves a complete, in-order receipt chain" do
    {a, _} = play(salt: 5, seed: 42)
    evs = Run.events(a)

    sent =
      Enum.find(evs, fn ev ->
        ev.payload[:kind] == :envelope_sent and ev.payload[:envelope].to == "goblin_bodyguard_1"
      end)

    refute sent == nil
    assert sent.payload[:envelope].from == "grisk_the_snatcher"

    assert {:ok, links} = Acceptance.receipt_chain(evs, sent.payload[:envelope].id)

    seqs = Enum.map(links, & &1.seq)
    assert seqs == Enum.sort(seqs)

    kinds = Enum.map(links, & &1.kind)

    assert kinds ==
             [
               :envelope_sent,
               :signal_received,
               :envelope_delivered,
               :adopt_audit,
               :adoption_dice,
               :envelope_adopted,
               :commitment_created,
               :proposed,
               :to_hit
             ] ++ damage_kinds(kinds)
  end

  test "13.4: truth barrier holds across every prompt of the whole run" do
    {a, captured} = play(salt: 6, seed: 42, capture: true)

    # Brain prompts are served inside Brain processes — their gateway
    # requests never reach this process's Scripted capture. The prompt
    # builders are pure: sweep one deliberate prompt per tier-3 agent over
    # the final world (allowed sets grow monotonically, so a name non-local
    # in the final world flags every earlier prompt class).
    swept =
      for {_id, agent} <- a.world.agents, agent.tier == 3 do
        slice = Slice.for_actor(a.world, agent.id)
        {sys, usr, _schema} = Prompt.deliberate(slice)


        %{req: %{agent_id: agent.id, class: :deliberate, system: sys, user: usr}, world: a.world, events: Run.events(a)}
      end

    assert length(captured.captured) > 0
    assert swept != []
    assert [] = Acceptance.locality_violations(captured.captured ++ swept)

    {:ok, loaded} = Loader.load(@yaml)
    assert [] = Acceptance.hidden_leaks(captured.captured ++ swept, loaded)
  end

  test "13.5: spend reconciles; a mid-run cap degrades narrate, spares interpret and brains" do
    {a, _} = play(salt: 7, seed: 42)

    # Uncapped run: the report reconciles with its own llm rows, every
    # narrate was LLM-served (queue never exhausted), none templated.
    assert :ok = Acceptance.spend_invariants(Run.spend_report(a), Run.events(a))
    assert narrate_served(Run.events(a)) > 1
    assert narrate_fallbacks(Run.events(a)) == 0

    # Cap: cumulative spend immediately before the uncapped run's LAST
    # served narrate, minus one — that narrate then falls past the cap and
    # every narrate after it degrades, while interpret (≤ 2× cap) and the
    # brains (never degraded) ride through. Narration text never feeds
    # state, so the earlier phases replay identically up to that point.
    before_by_row =
      Run.events(a)
      |> llm_payloads()
      |> Enum.map_reduce(0, fn p, acc ->
        {acc, acc + (p[:tokens_in] || 0) + (p[:tokens_out] || 0)}
      end)
      |> elem(0)

    narrate_befores =
      llm_payloads(Run.events(a))
      |> Enum.zip(before_by_row)
      |> Enum.filter(fn {p, _} -> p[:class] == :narrate and p[:parse_verdict] == :ok end)
      |> Enum.map(fn {_, before} -> before end)

    cap = Enum.max(narrate_befores) - 1
    assert cap > 0

    {c, _} = play(salt: 8, seed: 42, cap: cap)

    assert :ok = Acceptance.capped_consistency(Run.events(c), cap)
    assert narrate_served(Run.events(c)) > 0
    assert narrate_fallbacks(Run.events(c)) > 0

    # Interpret never degraded inside the 2× window; brains never starved.
    for p <- llm_payloads(Run.events(c)), p[:class] == :interpret do
      assert p[:parse_verdict] == :ok
    end

    for p <- llm_payloads(Run.events(c)), p[:class] in [:deliberate, :adopt] do
      assert p[:ok]
    end
  end

  test "13.6: persona reset alone rewrites history — material state, not bytes" do
    {a, _} = play(salt: 9, seed: 42)
    {b, _} = play(salt: 10, seed: 42, deliberate: deliberate_wait())

    refute :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(b))

    evs_a = Run.events(a)
    evs_b = Run.events(b)

    assert material_state(a, evs_a) != material_state(b, evs_b)
  end


  defp attack_count(evs),
    do:
      Enum.count(evs, fn ev ->
        ev.class == :dice and ev.payload[:purpose] == :to_hit and
          ev.payload[:agent_id] == "goblin_bodyguard_1"
      end)

  defp damage_kinds(kinds), do: if(:damage in kinds, do: [:damage], else: [])

  defp llm_payloads(evs),
    do: for(ev <- evs, ev.class == :llm and ev.payload[:kind] == :llm_call, do: ev.payload)

  defp narrate_served(evs),
    do: Enum.count(llm_payloads(evs), &(&1[:class] == :narrate and &1[:adapter] != :template))

  defp narrate_fallbacks(evs),
    do: Enum.count(llm_payloads(evs), &(&1[:class] == :narrate and &1[:adapter] == :template))

  defp material_state(run, evs) do
    hp = run.world.agents["pc_thistle"].body.hp
    dmg = Enum.count(evs, &(&1.payload[:kind] == :damage and &1.payload[:target_id] == "pc_thistle"))
    {hp, dmg, attack_count(evs)}
  end
end
