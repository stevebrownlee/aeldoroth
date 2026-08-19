# Agent Engine — Plan 6: Acceptance Harness (v1 Closure)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement plan task-by-task. Steps use checkbox (`- [ ]`) syntax tracking.

**Goal:** Spec §12.4 phase 8 — an acceptance harness that proves the §13 v1 criteria machine-checkably on the real adventure YAML, closing the v1 build order (decision 41: Plans 3–6).

**Scope:** analysis lib + tests + a self-verifying script. **No engine behavior changes** — the harness observes runs; it never mutates the pipeline. If a criterion cannot be met without engine changes, that is a finding, not a harness patch.

## Criteria → proof mapping (spec §13)

| Criterion | Proof |
|---|---|
| 13.2 emergence: ≥1 emergent event per run traceable in the event log to agent decisions | `receipt_chain/2`: one envelope's full ordered trace — signal_received → envelope_sent → envelope_delivered → llm/dice adoption → commitment_created → adopter's `:proposed` deliberation → attack rows — every link present, seqs increasing |
| 13.3 second run demonstrably diverges | fork-diff: identical seed + scripts except **one** brain reply; assert byte-identical prefix, first-divergence root is an LLM-sourced row (`:llm` audit or `:deliberation :proposed`), and material divergence follows (damage present vs absent) |
| 13.4 no prompt contains non-local truth | full-run prompt audit over captured `Scripted.take_requests/0`, paired with per-phase pre-call world snapshots: every display name (agent/place) appearing in a prompt must be reconstructible from that actor's slice ∪ its received signals ∪ its envelopes; hidden-item names must appear in **no** prompt ever |
| 13.5 tiered-cognition cost control observable | `Run.spend_report/1` invariants (totals == `:llm` row count; by_class/by_agent sum to total); capped-budget run shows class-aware degradation: narrate falls back to template audits while interpret (2× cap) and deliberate (never) continue |
| 13.6 same YAML+seed, different persona → different history | two runs differing only in the bodyguard's persona (aggressive strike vs cautious wait): assert divergent material outcomes, not just byte-inequality (damage-row counts and/or PC final hp differ) |
| (13.1 replay) | reaffirmed at harness scale: verbatim double-run → `term_to_binary` identical ledgers |

## Key facts (interfaces the harness builds against)

- `Run.new(yaml, seed, pcs, routing: %{class: %{adapter: Scripted, scripts: %{class: [entry...]}}})`; `Run.declare/3`; `Run.advance/1`; `Run.events/1`; `Run.spend_report/1`. Pure, single-process — process-dict Scripted queues stay deterministic.
- Scripted entry: binary or `%{agent_id: id, content: json}`; per-agent FIFO per class; `take_requests/0` drains captured `Request`s (newest first) with `system`/`user`/`agent_id`/`class` intact. Tokens = `byte_size/4`, so differing reply content ⇒ differing `:llm` audit rows ⇒ the fork root is observable.
- Ledger row order in `deliberate_one`: `:llm` audit row **before** the `:deliberation` decision row, then effects. Divergence root for a brain-content fork is therefore class `:llm` (or `:deliberation` with `decision: :proposed` if audits tie).
- Envelope lifecycle rows: kinds `:envelope_sent`, `:signal_received`, `:envelope_delivered`, `:envelope_adopted` (`%{adopted: bool}` on a `:dice` purpose `:adoption` row), `:commitment_created`; adopter action = `:deliberation` row `decision: :proposed`; attacks = `:damage`-class rows (or combat events in Resolve output).
- Budget: `%LLMGateway.Ctx{budget: %{cap: n | :inf, spent: k}}` — harness sets it via struct update after `Run.new` (Run is pure data; no API change).
- `Referee.Slice.for_actor(world, agent_id)` — the locality oracle: deep-collect strings; allowed-set = slice strings ∪ signal `content_nl` received by that agent (from ledger rows so far) ∪ envelope sender/payload for `:adopt` reqs.
- Tier-3 caps include `wait` (Loader `caps(3)`) — the cautious persona is a legal action.
- World truth for the ban-set: `world.agents` names, `world.places` names, `world.items` (`is_hidden: true` names banned unconditionally).

## Scenario (reuses the proven brains-smoke path)

PC Thistle: two declares (`go east`, `go south`) carry her into the chief's room; 20 advances. Grisk's cadence escalates on arrival → he orders `goblin_bodyguard_1` → envelope delivers on signal receipt → bodyguard adopts (d20) → strikes Thistle. This is the §13.2 emergent cascade.

Fork B persona: bodyguard's first scripted `deliberate` reply becomes `{"verb":"wait","reason":"cautious persona"}` instead of the strike.

## Tasks

### Task 1 — `Referee.Acceptance` analysis lib
`apps/referee/lib/referee/acceptance.ex` — pure functions, no new deps:

- [x] `first_divergence(events_a, events_b) :: %{index: non_neg_integer, class: atom} | :identical` — compare `{tick, class, payload}` pairwise (seq renumbers across runs; never compared).
- [x] `llm_root?(nil | map) :: boolean` — root row is LLM-sourced: class `:llm`; class `:deliberation` with `decision: :proposed`; or class `:clarify`.
- [x] `receipt_chain(events, envelope_id) :: {:ok, [link]} | {:error, missing}` — ordered proof links for one order envelope; each link `%{kind: atom, seq: pos_integer, summary: String.t()}`; returns error naming the first missing kind so failures are diagnosable.
- [x] `deep_strings(term) :: [String.t()]` — collect binaries from structs/maps/lists recursively.
- [x] `locality_violations(captured) :: [violation]` where `captured = [%{req: Request.t(), world: World.t(), events_before: [Event]}]`; violation = `%{req_index, agent_id, class, leaked: name}`. Display names (agents/places) substring-matched against `req.system <> " " <> req.user` must be substring-present in the allowed set (slice ∪ received signal nl ∪ own envelopes). Case-sensitive exact-name substrings; names are proper display strings.
- [x] `hidden_leaks(captured, world_final) :: [violation]` — `is_hidden` item names must not appear in any prompt, unconditionally.
- [x] `spend_invariants(report, events) :: :ok | {:error, msg}` — total.calls == count of `:llm` rows; class/agent tallies sum to total.

Unit tests co-located (`acceptance_test.exs` setup section): divergence detection on synthetic rows; `llm_root?` truth table; `receipt_chain` on synthetic complete/partial chains; `deep_strings` on nested structs; `locality_violations` flags a planted leak and passes a slice-sourced name.

### Task 2 — `apps/referee/test/acceptance_test.exs` (the six proofs)
Shared scripted playthrough helper (mirrors `brains_golden_test` conventions: distinct salts per replay, `Scripted.reset()` in setup):

- [x] `verbatim double-run ⇒ byte-identical ledgers` — same seed, distinct salts, `:erlang.term_to_binary/1` equality (13.3 pre-req + 13.1).
- [x] `fork-diff: prefix identical, root is LLM, outcomes diverge materially` — A strike vs B wait; `first_divergence.index > 0`; `llm_root?`; A has `:damage` rows targeting the PC, B none in horizon; B's bodyguard deliberation row shows `verb: :wait` (13.3, 13.6).
- [x] `emergence: grisk's order leaves a complete receipt chain` — find the first `:envelope_sent` order envelope; `receipt_chain` returns every link in increasing seq (13.2).
- [x] `truth barrier holds across the whole run` — world-snapshot-per-phase capture (`take_requests/0` drained after each declare/advance, paired with `run.world` at that point); `locality_violations == []`; `hidden_leaks == []` (13.4).
- [x] `spend observability + degradation under cap` — invariants on the uncapped run; capped run (`cap` ≈ the uncapped interpret+narrate spend of the first advance): later narrate calls produce `:llm` rows with `parse_verdict: :fallback, adapter: :template` while interpret rows keep `verdict: :ok` (cap < spend ≤ 2×cap) and deliberate rows are unaffected (13.5).
- [x] `persona reset ⇒ different history` — A vs B from the fork test, asserted on material state (PC hp and/or damage-row counts differ), not byte-inequality alone (13.6).

### Task 3 — `scripts/acceptance_harness.exs` (self-verifying proof artifact)
Convention per `protocol_smoke.exs` / `brains_smoke.exs` (`SEED`/`YAML` env, defaults to adventure):

- [x] Runs the playthrough + fork + audits; prints narration lines, the receipt chain, fork summary (prefix length, root class, both sides' next rows), truth-audit verdict, spend report.
- [x] Exits `System.halt(1)` on any criterion failure with a named reason; prints `ALL ACCEPTANCE CRITERIA PASS` otherwise.
- [x] Header comment documents usage.

## Non-goals
- No engine/gateway/referee behavior changes; no new apps.
- No live-WS or Session coverage (plan 5 already proves pipeline ≡ wire).
- No cross-run memory, multi-adventure, or platform seams (decision 34/35 — post-v1).

## Acceptance (plan-level)
1. `mix test` umbrella green; the six proofs present and passing on the real YAML.
2. `mix run scripts/acceptance_harness.exs` prints the full evidence block and exits 0.
3. Zero `locality_violations`/`hidden_leaks` on the real adventure — if a violation fires, it is a truth-barrier bug to fix in the engine, not to allowlist here.
