# Acceptance harness (plan 6, spec §13) — the self-verifying v1 proof artifact.
#
#   SEED=42 YAML=../the-ruined-tower/ruined_tower.yaml mix run scripts/acceptance_harness.exs
#
# Runs the scripted playthrough twice (byte-identical replay), the persona
# fork (aggressive vs cautious bodyguard), a prompt-capture audit, and a
# capped-budget replay; prints the evidence for each §13 criterion and exits
# 1 with a named reason on the first failure, 0 after ALL ACCEPTANCE
# CRITERIA PASS. Pure `Referee.Run` path — plan 5 already proved wire ≡ pure.

seed = String.to_integer(System.get_env("SEED") || "42")
yaml = Path.expand(System.get_env("YAML") || "../the-ruined-tower/ruined_tower.yaml")

unless File.exists?(yaml) do
  IO.puts("FAIL: yaml not found: #{yaml}")
  System.halt(1)
end

defmodule Harness do
  @moduledoc false
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run

  @interpret [
    ~s({"verb":"move","target_id":null,"params":{"direction":"east"},"assumptions":[]}),
    ~s({"verb":"move","target_id":null,"params":{"direction":"south"},"assumptions":[]})
  ]

  @adopt [
    %{agent_id: "goblin_bodyguard_1",
      content: ~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"})}
  ]

  @narrate_line "Dust sifts through the ruined shaft; the moment holds."

  @deliberate_strike [
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

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}
  ]

  def deliberate_strike, do: @deliberate_strike

  # Fork B: identical queue except the bodyguard's one deliberate reply —
  # a cautious persona that waits instead of striking (§13.3, §13.6).
  def deliberate_wait do
    Enum.map(@deliberate_strike, fn
      %{agent_id: "goblin_bodyguard_1"} = e ->
        %{e | content: ~s({"verb":"wait","target_id":null,"reason":"cautious persona"})}

      e ->
        e
    end)
  end

  # Two declares carry Thistle into the chief's room; 20 advances let
  # escalation → order → delivery → adoption → strike run. Returns
  # {run, %{captured, marks}} — with capture: true, `captured` pairs each
  # drained gateway request with its [pre, post] phase-world bracket and
  # the ledger at that boundary.
  def play(yaml, seed, salt, deliberate, opts \\ []) do
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

    {:ok, run} = Run.new(yaml, seed, @pcs, routing: routing)
    run = if cap, do: cap_ctx(run, cap), else: run

    steps = [{:declare, "pc_thistle", "go east"}, {:declare, "pc_thistle", "go south"}] ++
              List.duplicate(:advance, 20)
    Enum.reduce(steps, {run, %{captured: [], marks: []}}, fn
      {:declare, pc, text}, {pre, info} ->
        {:ok, _t, post} = Run.declare(pre, pc, text)
        close_phase(post, pre, info, capture?)

      :advance, {pre, info} ->
        {:ok, _n, post} = Run.advance(pre)
        close_phase(post, pre, info, capture?)
    end)
  end

  def pc_hp(run, pc_id) do
    case run.world.agents[pc_id] do
      nil -> :absent
      a -> a.body.hp
    end
  end

  def damage_count(events), do: Enum.count(events, &(&1.payload[:kind] == :damage))

  def llm_payloads(events),
    do: for(ev <- events, ev.class == :llm and ev.payload[:kind] == :llm_call, do: ev.payload)

  def row_sig(ev),
    do: %{tick: ev.tick, class: ev.class, kind: ev.payload[:kind], decision: ev.payload[:decision], verb: ev.payload[:verb]}

  defp cap_ctx(run, cap),
    do: %{run | ctx: %{run.ctx | budget: %{run.ctx.budget | cap: cap}}}

  defp close_phase(post, pre, info, capture?) do
    reqs = Scripted.take_requests()

    info =
      info
      |> Map.update!(:marks, &[post.seq | &1])
      |> maybe_capture(capture?, pre, post, reqs)

    {post, info}
  end

  # Brain LLM calls (deliberate/adopt) are served inside Brain processes —
  # their gateway requests never reach this process's Scripted capture. The
  # prompt builders are pure, so sweep them directly: one deliberate prompt
  # per tier-3 agent over the final world. Allowed sets grow monotonically
  # within a run (beliefs/envelopes only accumulate), so a name non-local in
  # the final world flags every earlier prompt class.
  def brain_prompt_sweep(run) do
    events = Run.events(run)

    for {_id, agent} <- run.world.agents, agent.tier == 3 do
      slice = Referee.Slice.for_actor(run.world, agent.id)
      {sys, usr, _schema} = Agents.Prompt.deliberate(slice)

      %{
        req: %{agent_id: agent.id, class: :deliberate, system: sys, user: usr},
        world: run.world,
        events: events
      }
    end
  end

  defp maybe_capture(info, false, _pre, _post, _reqs), do: info

  # Prompts are built mid-phase (interpret before the move lands, deliberate
  # between scheduler and resolve); requests drain only at boundaries, so
  # each capture carries the [pre, post] bracket — locality counts a leak
  # only against every bracket world.
  defp maybe_capture(info, true, pre, post, reqs) do
    evs = Run.events(post)
    added = Enum.map(Enum.reverse(reqs), &%{req: &1, world: [pre.world, post.world], events: evs})
    Map.update!(info, :captured, &(&1 ++ added))
  end
end

alias EngineCore.Loader
alias Referee.{Acceptance, Run}

fail_with = fn reason ->
  IO.puts("FAIL: #{reason}")
  System.halt(1)
end

pass = fn label -> IO.puts("PASS: #{label}") end

IO.puts("=== ACCEPTANCE HARNESS — seed #{seed}, #{Path.basename(yaml)} ===")

# --- 13.1/13.3: verbatim double-run ⇒ byte-identical ledger ----------------
{a, _} = Harness.play(yaml, seed, 1, Harness.deliberate_strike())
{b, _} = Harness.play(yaml, seed, 2, Harness.deliberate_strike())

unless :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(b)) do
  fail_with.("13.1/13.3 identical seed + scripts replayed to different ledgers")
end

pass.("13.1/13.3 identical seed + scripts ⇒ byte-identical ledger (#{length(Run.events(a))} rows)")

IO.puts("")
IO.puts("--- base run: PC perceptions (sample) ---")

Run.events(a)
|> Enum.filter(&(&1.class == :narration))
|> Enum.take(6)
|> Enum.each(fn ev -> IO.puts("  [seq #{ev.seq}] #{String.slice(ev.payload[:text] || "", 0..90)}") end)

# --- 13.2: emergence — grisk's order leaves a complete receipt chain --------
IO.puts("")
IO.puts("--- 13.2 emergence: order envelope receipt chain ---")

case Enum.find(Run.events(a), &(&1.payload[:kind] == :envelope_sent)) do
  nil ->
    fail_with.("13.2 no order envelope sent in the base run")

  %{payload: %{envelope: env}} ->
    case Acceptance.receipt_chain(Run.events(a), env.id) do
      {:ok, links} ->
        Enum.each(links, fn l -> IO.puts("  [seq #{l.seq}] #{l.kind}: #{l.summary}") end)

        seqs = Enum.map(links, & &1.seq)

        unless seqs == Enum.sort(seqs) and length(links) >= 5 do
          fail_with.("13.2 receipt chain links not seq-ordered or too short (#{length(links)})")
        end

        pass.("13.2 emergent order traceable end-to-end: #{length(links)} linked rows, no GM fiat")

      {:error, {:missing, kind, after_seq}} ->
        fail_with.("13.2 receipt chain broken: no #{kind} after seq #{after_seq}")
    end
end

# --- 13.3/13.6: persona fork ⇒ materially different histories ---------------
IO.puts("")
IO.puts("--- 13.3/13.6 persona fork: strike vs wait ---")

{fa, _} = Harness.play(yaml, seed, 3, Harness.deliberate_strike())
{fb, _} = Harness.play(yaml, seed, 4, Harness.deliberate_wait())

case Acceptance.first_divergence(Run.events(fa), Run.events(fb)) do
  :identical ->
    fail_with.("13.3 persona fork produced identical ledgers")

  %{index: i} ->
    IO.puts("  divergence index: #{i} (#{i} shared prefix rows)")

    IO.puts("  row A at fork: #{inspect(Harness.row_sig(Enum.at(Run.events(fa), i)))}")
    IO.puts("  row B at fork: #{inspect(Harness.row_sig(Enum.at(Run.events(fb), i)))}")

    unless Acceptance.llm_root?(Enum.at(Run.events(fa), i)) and
             Acceptance.llm_root?(Enum.at(Run.events(fb), i)) do
      fail_with.("13.3 fork root row is not LLM-sourced")
    end

    pass.("13.3 fork root is an LLM decision row")
end

dmg_a = Harness.damage_count(Run.events(fa))
dmg_b = Harness.damage_count(Run.events(fb))
hp_a = Harness.pc_hp(fa, "pc_thistle")
hp_b = Harness.pc_hp(fb, "pc_thistle")
IO.puts("  A(strike): #{dmg_a} damage rows, PC hp #{hp_a} | B(wait): #{dmg_b} damage rows, PC hp #{hp_b}")

unless dmg_a != dmg_b or hp_a != hp_b do
  fail_with.("13.6 persona fork did not diverge material state (damage #{dmg_a}=#{dmg_b}, hp #{hp_a}=#{hp_b})")
end

pass.("13.6 persona alone rewrote material history")

# --- 13.4: truth barrier over every prompt of the whole run -----------------
IO.puts("")
IO.puts("--- 13.4 truth barrier: prompt audit ---")

# Capture run: interpret/narrate prompts are served in this process and
# drained per phase; brain prompts (deliberate/adopt) live in Brain
# processes, so they are swept from the pure prompt builders over the base
# run's final world instead (monotone allowed sets make that sound).
{_aud, info} = Harness.play(yaml, seed, 5, Harness.deliberate_strike(), capture: true)

swept = Harness.brain_prompt_sweep(a)
captured = info.captured ++ swept

if captured == [] do
  fail_with.("13.4 no prompts captured or swept")
end

IO.puts("  prompts audited: #{length(captured)} (#{length(info.captured)} captured, #{length(swept)} swept brain prompts)")

case Acceptance.locality_violations(captured) do
  [] ->
    pass.("13.4 zero locality violations across #{length(captured)} prompts")

  leaks ->
    Enum.each(leaks, fn l -> IO.puts("  leak: #{inspect(l)}") end)
    fail_with.("13.4 locality violations — truth-barrier bug in the engine")
end

{:ok, loaded} = Loader.load(yaml)

case Acceptance.hidden_leaks(captured, loaded) do
  [] ->
    pass.("13.4 zero hidden-item leaks across every prompt")

  leaks ->
    Enum.each(leaks, fn l -> IO.puts("  hidden leak: #{inspect(l)}") end)
    fail_with.("13.4 hidden-item names reached prompts")
end

# --- 13.5: spend observability + capped degradation -------------------------
IO.puts("")
IO.puts("--- 13.5 spend observability ---")

r = Run.spend_report(a)
IO.puts("  total:    #{r.total.calls} calls, #{r.total.tokens_in} in / #{r.total.tokens_out} out")

for {class, s} <- r.by_class do
  IO.puts("  #{class}:  #{s.calls} calls, #{s.tokens_in} in / #{s.tokens_out} out")
end

case Acceptance.spend_invariants(r, Run.events(a)) do
  :ok -> pass.("13.5 spend report reconciles with its llm rows")
  {:error, msg} -> fail_with.("13.5 spend invariants: #{msg}")
end

# Cap: cumulative spend immediately before the uncapped run's LAST served
# narrate, minus one — that narrate falls past the cap; narrate degrades,
# interpret survives to 2×, brains never starve.
{befores, _} =
  Harness.llm_payloads(Run.events(a))
  |> Enum.map_reduce(0, fn p, acc -> {acc, acc + (p[:tokens_in] || 0) + (p[:tokens_out] || 0)} end)

narrate_befores =
  Harness.llm_payloads(Run.events(a))
  |> Enum.zip(befores)
  |> Enum.filter(fn {p, _} -> p[:class] == :narrate and p[:parse_verdict] == :ok end)
  |> Enum.map(fn {_, before} -> before end)

cap = Enum.max(narrate_befores) - 1
{capped, _} = Harness.play(yaml, seed, 6, Harness.deliberate_strike(), cap: cap)

IO.puts("  capped replay: cap #{cap} tokens")

case Acceptance.capped_consistency(Run.events(capped), cap) do
  :ok -> pass.("13.5 capped run: narrate degraded past cap, interpret intact to 2×, brains served")
  {:error, msg} -> fail_with.("13.5 capped consistency: #{msg}")
end

IO.puts("")
IO.puts("ALL ACCEPTANCE CRITERIA PASS")
