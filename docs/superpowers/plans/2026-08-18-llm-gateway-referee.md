# Agent Engine — Plan 3: LLM Gateway & Referee Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the engine its LLM chokepoint and the referee pipeline (spec §12.4 phase 5): every PC natural-language intent flows through propose → validate → resolve → apply → narrate against the deterministic `engine_core`; the referee preference stack (core < module < personal) is resolved, hashed into the ledger, and consulted; all LLM traffic flows through one `LLMGateway.Router` with configurable class routing, token budgets with the documented degradation order, and lossless per-call audit events. Headless, offline-testable, replay-deterministic with scripted adapters.

**Scope split (deliberate):** spec §12.4 phases 6–8 are NOT in this plan. Brains/envelopes/adoption → Plan 4. Phoenix channels + terminal client + dossiers + spectate → Plan 5. Acceptance harness/fork-diff/spend dashboards → Plan 6. Each phase lands headless before the next, per spec §12.4's own rule.

**Architecture:** Two new umbrella apps. `llm_gateway` (deps: `jason` only — no engine dependency; the audit record is plain data so the gateway stays engine-agnostic) owns routing, adapters, budgets, circuit breaker. `referee` (in_umbrella: `engine_core`, `llm_gateway`) owns the preference stack, the truth-barrier slice builder, the five pipeline stages, and `Referee.Run` — a pure run container (`world + rng + ledger + prefs + gateway ctx + rejection counters`) driven headlessly. No new processes: `Router.complete/2` is a pure function; the OTP supervision tree (World.Server, Endpoint, brains) arrives with Plans 4–5. The chokepoint (pattern 14) is structural: adapter modules are called only from inside `LLMGateway.Router`.

**Tech Stack:** Elixir ≥ 1.17 / OTP ≥ 27, Mix umbrella, ExUnit, `yaml_elixir` (engine_core), `jason` (llm_gateway — NEW dep, fetched from hex; network confirmed available).

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` — this plan implements §12.4 phase 5: "`llm_gateway` + referee stages (interpret/narrate live; templates swap out)", plus §7 (pipeline + truth barrier), §8 (preference stack), §10 (orchestration/routing/failure semantics/budgets), and the `llm` event class of §9.1.

**Engrams design record (do not re-litigate):** decisions 20 (LLM proposes, engine disposes), 26 (tiered routing by decision class; model identity logged with every record), 32 (ambiguity: clarify only on lethal ambiguity, else most-plausible parse with narrated assumption), 33 (preference stack precedence + unknown keys warn/drop + versioned into the ledger), 36 (config-only vendors, no default pinned, OpenAI-compatible + Anthropic adapters); patterns 14 (`llm-gateway-single-chokepoint`), 10 (`append-only-ledger`), 11 (`effects-via-referee-pipeline`). New session decision: Plan 3 scope = phase 5 only (phases 6–8 are Plans 4–6).

## Global Constraints

- `engine_core` changes are ADDITIVE ONLY: two new `Fold` payload kinds (`:agent_added`, `:belief_corrected`) + tests. No new deps, no wall-clock, existing tests stay green.
- `llm_gateway` deps: `jason` ONLY. NO in_umbrella engine dependency, no `yaml_elixir`.
- `referee` deps: `in_umbrella [:engine_core, :llm_gateway]`, nothing else.
- All tests run OFFLINE. HTTP adapters are tested against pure request-build/response-parse functions; no socket is opened in any test.
- **No wall-clock anywhere in the new apps' ledger-bound data**: `llm` audit events carry no timestamps/latency — tokens, model, class, verdict only. (Wall-clock may exist in adapter HTTP paths for timeouts, never in ledgered data.)
- Determinism: identical YAML + seed + PC script + scripted-adapter script ⇒ byte-identical ledger (`:erlang.term_to_binary/1` comparison, Task 10 golden test). Any list derived from maps is sorted before use.
- Routing is config: `config :llm_gateway, :routing` (test config pins every class to `Scripted`). No vendor is default; missing config for a class ⇒ that class fails with `{:error, :no_route}` and the stage's failure semantics apply.
- Failure semantics (spec §10): `interpret` failure ⇒ grammar fallback + clarification note; `narrate` failure ⇒ `EngineCore.Narrate` template fallback; one bounded LLM retry on parse failure; budget exhaustion degrades in order narrate → interpret (deliberate not present yet).
- Truth barrier: prompts are built ONLY from `Referee.Slice` output; `is_hidden` items and non-local agents never enter a prompt (Task 8 property test).
- Tests: ExUnit, offline. Run from `shards_engine/`: `mix test`.
- Commit style: conventional (`feat:`, `fix:`, `test:`, `chore:`, `refactor:`), one logical change per commit.

## File Structure

```
shards_engine/
├── apps/
│   ├── engine_core/lib/engine_core/fold.ex     # MODIFY: +:agent_added, +:belief_corrected clauses
│   ├── llm_gateway/                            # CREATE app
│   │   ├── mix.exs
│   │   ├── lib/llm_gateway.ex                  # @moduledoc: chokepoint contract
│   │   ├── lib/llm_gateway/types.ex            # Request, Result, Audit, Ctx
│   │   ├── lib/llm_gateway/adapter.ex          # behaviour + shared req/resp plumbing
│   │   ├── lib/llm_gateway/schema.ex           # minimal JSON-schema validator
│   │   ├── lib/llm_gateway/router.ex           # routing + budget + breaker + audit
│   │   ├── lib/llm_gateway/json.ex             # Jason one-liner module (single import point)
│   │   └── lib/llm_gateway/adapters/
│   │       ├── scripted.ex                     # queue-per-class, deterministic
│   │       ├── openai_compat.ex                # /chat/completions via :httpc
│   │       └── anthropic.ex                    # /v1/messages via :httpc
│   ├── referee/                                # CREATE app
│   │   ├── mix.exs
│   │   ├── lib/referee.ex
│   │   ├── lib/referee/preferences.ex          # core < module < personal, hash
│   │   ├── lib/referee/pc.ex                   # PC agent construction + injection events
│   │   ├── lib/referee/slice.ex                # truth-barrier actor-visible view
│   │   ├── lib/referee/interpret.ex            # LLM heavy + grammar fallback + ambiguity
│   │   ├── lib/referee/grammar.ex              # deterministic NL parser
│   │   ├── lib/referee/validate.ex             # capability/belief/edge gates, retry budget
│   │   ├── lib/referee/resolve.ex              # verb dispatch to engine_core rules
│   │   ├── lib/referee/narrate.ex              # light LLM + template fallback by prefs
│   │   ├── lib/referee/run.ex                  # pure run container + declare/advance
│   │   └── lib/referee/spend.ex                # ledger llm-event aggregation
│   └── (test/ trees mirror lib/ in both apps)
├── config/config.exs                           # CREATE: routing defaults (none pinned)
├── config/test.exs                             # CREATE: all classes → Scripted
the-ruined-tower/ruined_tower.yaml              # MODIFY: + preferences: block (module layer)
shards_engine/automated-run.sh                  # MODIFY: `referee` mode
```

## Shared Interfaces (tasks must match these exactly)

- `LLMGateway.Request` — `%Request{class: atom, agent_id: String.t() | nil, system: String.t(), user: String.t(), schema: map() | nil, temperature: float, max_tokens: pos_integer()}` (`@enforce_keys [:class, :system, :user]`).
- `LLMGateway.Result` — `%Result{content: String.t(), parsed: map() | nil, usage: %{tokens_in: non_neg_integer(), tokens_out: non_neg_integer()}}`.
- `LLMGateway.Audit` — `%Audit{class: atom, agent_id: nil | String.t(), adapter: atom, model: String.t() | nil, tokens_in: non_neg_integer(), tokens_out: non_neg_integer(), prompt_slice_ref: String.t() | nil, parse_verdict: :ok | :retry_ok | :failed | :fallback | :skipped, ok: boolean}`. Ledger payload form: `%{kind: :llm_call, class: ..., agent_id: ..., adapter: ..., model: ..., tokens_in: ..., tokens_out: ..., prompt_slice_ref: ..., parse_verdict: ..., ok: ...}` — atom/values only.
- `LLMGateway.Ctx` — `%Ctx{routing: %{atom => adapter_cfg}, budget: %{cap: non_neg_integer() | :inf, spent: non_neg_integer()}, breaker: %{atom => non_neg_integer()}}` where `adapter_cfg = %{adapter: module, model: String.t() | nil, endpoint: String.t() | nil, key_ref: atom | nil, temperature: float, max_tokens: pos_integer()}`. Built via `Ctx.from_config/1` reading `Application.get_env(:llm_gateway, :routing, %{})`.
- `LLMGateway.Adapter` behaviour — `@callback complete(Request.t(), adapter_cfg :: map()) :: {:ok, Result.t()} | {:error, term()}`. Callable only from `LLMGateway.Router` (chokepoint; enforced by convention + review).
- `LLMGateway.Router.complete(ctx, request) :: {:ok, Result.t(), Audit.t(), Ctx.t()} | {:error, term(), Audit.t() | nil, Ctx.t()}` — pure. Order of operations: route lookup → budget check (class degraded? → `{:error, :budget_degraded}`) → breaker check → adapter call → schema parse (one bounded retry inside) → audit + ctx update (spend += tokens, breaker resets/advances).
- `LLMGateway.Schema.validate(map(), schema :: map()) :: :ok | {:error, String.t()}` — supports `type: :object|:string|:integer|:number|:boolean`, `properties`, `required`, `enum`, `items` (for string arrays).
- Adapter modules: `Scripted.complete/2` takes `adapter_cfg.scripts :: %{class => [String.t()]}` (pops head per call, class-keyed; empty queue ⇒ `{:error, :script_exhausted}`); `OpenAICompat`/`Anthropic` expose `build_request(request, cfg) :: {url, headers, body_map}` and `parse_response(status, body_binary) :: {:ok, Result.t()} | {:error, term}` as PURE functions plus the behaviour `complete/2` that wires them through `:httpc` (untouched by tests).
- `Referee.Preferences.core/0 :: map()` · `resolve(module_map | nil, personal_map | nil) :: {resolved_map, [warning_strings]}` · `hash(resolved) :: binary()` (`:erlang.md5(:erlang.term_to_binary(sorted_resolved))`).
- `Referee.PC.build(pc_map) :: Types.Agent.t()` — `pc_map = %{id, name, int, ac, hd, hp, thac0, damage: "1d8"}`; tier 3, capabilities `[:move, :strike, :wait, :shout]`, cadence `nil`, attention `:alert`, `body.conditions: []`, beliefs `%{}`. `Referee.PC.join_events(world, pc) :: [Ledger.Event.t()]` — one `:world`/`%{kind: :agent_added, agent: pc, place_id: entry}` event.
- `Referee.Slice.for_actor(world, agent_id) :: %{agent: identity_map, place: place_map, believed: sorted_list, salient: sorted_list, summary: String.t()}` — `is_hidden` items and agents outside `agent.place_id` NEVER appear. `prompt_slice_ref` = `:erlang.md5(term_to_binary(slice)) |> Base.encode16(case: :lower)`.
- `Referee.Interpret.nl_to_action(ctx, world, pc_id, nl) :: {:ok, Types.Action.t(), [assumption_strings], Ctx.t(), Audit.t() | nil} | {:clarify, String.t(), Ctx.t(), Audit.t() | nil}` — LLM first (class `:interpret`, schema-constrained), grammar fallback on error/parse-fail. Lethal ambiguity ⇒ `{:clarify, ...}`; else most-plausible parse with assumption notes.
- `Referee.Validate.check(world, action) :: :ok | {:reject, String.t()}` — capability gate (verb ∈ capabilities), belief gate (:strike requires a belief about `target_id` in current place), edge gate (:move requires an unsealed edge matching target/direction).
- `Referee.Resolve.action(world, rng, action, opts) :: {:resolved, [events], world2, rng2} | {:diegetic_fail, [events], world2, rng2}` — dispatches `:move` → `Movement.traverse/5`, `:strike` → `Combat.attack/4` (stale belief: target not actually present ⇒ diegetic miss + `:belief_corrected`), `:shout` → `Signals.emit/6` (voices signal, intensity 6), `:wait` → `[]`.
- `Referee.Narrate.stage(ctx, world_before, events, pc_id, prefs) :: {text :: String.t(), Ctx.t(), Audit.t() | nil}` — renders the PC's share of `events` at fidelity; LLM class `:narrate` when budget allows, else `EngineCore.Narrate.render/3` templates; `narration_style` pref picks terse/rich template voice.
- `Referee.Run` — `%Run{world: World.t(), rng: :rand.state(), ledger: [Ledger.Event.t()], prefs: map(), ctx: LLMGateway.Ctx.t(), rejections: %{{actor_id, tick} => count}}`; `new(yaml_path, seed, opts \\ [])` (loads via `EngineCore.Loader`, resolves prefs, emits `meta/prefs_stack` + `:agent_added` per PC sorted by id), `declare(run, pc_id, nl)`, `advance(run) :: {:ok, %{pc_id => [texts]}, Run.t()}` (one `Scheduler.advance` + `Scheduler.react` pass + per-PC narrate of new belief events), `events(run)`, `spend_report(run)`.
- Engine `Fold` additions: `:agent_added` (put agent into `world.agents`), `:belief_corrected` (`%{agent_id, place_id, about}` — deletes `agent.beliefs[place_id][about]`).

## Task 1: Scaffold the two new umbrella apps

**Files:**
- Create: `shards_engine/apps/llm_gateway/mix.exs`, `.../lib/llm_gateway.ex`, `.../test/llm_gateway_test.exs`
- Create: `shards_engine/apps/referee/mix.exs`, `.../lib/referee.ex`, `.../test/referee_test.exs`
- Create: `shards_engine/config/config.exs`, `shards_engine/config/test.exs`
- Modify: root `shards_engine/mix.exs` only if umbrella defaults need it (they do not; apps auto-discovered)

- [ ] **Step 1:** `llm_gateway/mix.exs`: app `:llm_gateway`, version 0.1.0, deps `[{:jason, "~> 1.4"}]`, no applications.
- [ ] **Step 2:** `referee/mix.exs`: app `:referee`, deps `[{:engine_core, in_umbrella: true}, {:llm_gateway, in_umbrella: true}]`.
- [ ] **Step 3:** `config/config.exs`: `import_config "#{config_env()}.exs"` guarded by File.exists?; empty routing `%{}` (nothing pinned). `config/test.exs`: routing for `:interpret`, `:narrate` → `Scripted` with empty scripts (tests inject via Ctx directly or config).
- [ ] **Step 4:** Smoke modules with `@moduledoc` only; one trivial test per app asserting the module loads.
- [ ] **Step 5:** `mix deps.get && mix test` from `shards_engine/` — expect 91 passing (89 + 2 new). Commit `chore: scaffold llm_gateway + referee umbrella apps`.

## Task 2: engine_core additive — `:agent_added` / `:belief_corrected`

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/fold.ex`
- Test: `shards_engine/apps/engine_core/test/fold_test.exs`

- [ ] **Step 1 (failing test):** `:agent_added` event folds a new agent into `world.agents` (PC injection); `:belief_corrected` deletes `beliefs[place_id][about]` and is a no-op for missing keys.
- [ ] **Step 2:** Implement the two clauses next to existing ones (same style: `update_agent` for correction; direct map put for addition). Verify: `mix test apps/engine_core`. Commit `feat(engine_core): fold clauses for agent_added and belief_corrected`.

## Task 3: llm_gateway types, schema validator, scripted adapter

**Files:**
- Create: `lib/llm_gateway/types.ex`, `lib/llm_gateway/schema.ex`, `lib/llm_gateway/json.ex`, `lib/llm_gateway/adapter.ex`, `lib/llm_gateway/adapters/scripted.ex`
- Test: `test/schema_test.exs`, `test/scripted_test.exs`, `test/types_test.exs`

- [ ] **Step 1 (failing tests):** schema validator accepts a valid interpret-schema payload, rejects missing required key, wrong type, out-of-enum value, bad items entry. Scripted pops per-class queues in order, returns parsed `%Result{parsed: map}` when payload is JSON, errors on `:script_exhausted`. Struct defaults per Shared Interfaces.
- [ ] **Step 2:** Implement. `Json` wraps `Jason.encode/decode` (single import point). `Scripted` derives `usage` from byte sizes of prompt/response (deterministic token proxy: `div(byte_size, 4)`).
- [ ] **Step 3:** `mix test apps/llm_gateway`. Commit `feat(llm_gateway): request/result/audit types, schema validator, scripted adapter`.

## Task 4: llm_gateway Router — chokepoint, budgets, breaker

**Files:**
- Create: `lib/llm_gateway/router.ex`
- Test: `test/router_test.exs`

- [ ] **Step 1 (failing tests):**
  - happy path: routing entry → scripted response → audit `ok: true`, `parse_verdict: :ok`, ctx spend increased by usage, breaker reset.
  - missing route → `{:error, :no_route, nil, ctx}`; stage callers apply failure semantics.
  - parse failure then good script on retry → `parse_verdict: :retry_ok`.
  - hard adapter error → `parse_verdict: :failed`, `ok: false`, breaker count +1; 3 consecutive per adapter → `{:error, :circuit_open, audit, ctx}` on next call.
  - budget: `cap: 100`, spend at 90, call costs 20 → after call `spent == 110`; next `:narrate` call → `{:error, :budget_degraded}` while `:interpret` still allowed (degradation order is class-aware: narrate drops first).
- [ ] **Step 2:** Implement `Router.complete/2` exactly per Shared Interfaces. Budget check: `degraded?(class, budget)` — narrate degrades when `spent > cap`; interpret when `spent > cap * 2` (documented multiple; deliberate/adopt/summarize never degrade in this plan).
- [ ] **Step 3:** `mix test apps/llm_gateway`. Commit `feat(llm_gateway): router chokepoint with routing, budgets, circuit breaker, audits`.

## Task 5: HTTP adapters (OpenAI-compatible + Anthropic)

**Files:**
- Create: `lib/llm_gateway/adapters/openai_compat.ex`, `lib/llm_gateway/adapters/anthropic.ex`
- Test: `test/adapters/openai_compat_test.exs`, `test/adapters/anthropic_test.exs`

- [ ] **Step 1 (failing tests, pure only):** `build_request/2` produces correct URL/headers (authorization from `key_ref` resolved via `Application.get_env(:llm_gateway, :keys)[key_ref]` — never a literal), body map with model/messages/temperature/max_tokens (+ `response_format: %{type: "json_object"}` for OpenAI; system as top-level for Anthropic). `parse_response/2` decodes a canned 200 body into `%Result{parsed: ...}` (JSON content), maps 401/429/500 to `{:error, :unauthorized | :rate_limited | :server_error}`, and parses each vendor's usage block.
- [ ] **Step 2:** Implement `complete/2` wiring through `:httpc.request/4` (`ssl` enabled, 30s timeout) — no test coverage by design (offline constraint); keep `complete` a thin shell over the two pure functions.
- [ ] **Step 3:** `mix test apps/llm_gateway`. Commit `feat(llm_gateway): openai-compatible + anthropic adapters over httpc (config-only vendors)`.

## Task 6: Preference stack + module layer

**Files:**
- Create: `apps/referee/lib/referee/preferences.ex`
- Modify: `the-ruined-tower/ruined_tower.yaml` (add `preferences:` block)
- Test: `apps/referee/test/preferences_test.exs`

- [ ] **Step 1 (failing tests):** core defaults exist (`tone`, `narration_style: "terse"`, `lethality: "standard"`, `dice_visibility: "open"`, `xp: %{gold_per_xp: 1, creative_bonus: true}`); module overrides core; personal overrides module; unknown keys dropped with warnings; `hash/1` stable across calls and sensitive to any value change.
- [ ] **Step 2:** Implement (`resolve/2` deep-merges known-key trees). Add to the tower YAML (additive, near top):

```yaml
preferences:
  tone: "grim-but-heroic"
  narration_style: "terse"
  lethality: "standard"
  dice_visibility: "open"
  xp:
    gold_per_xp: 1
    creative_bonus: true
```

- [ ] **Step 3:** `mix test apps/referee`. Commit `feat(referee): preference stack (core < module < personal) + tower module layer`.

## Task 7: PC construction + truth-barrier slice

**Files:**
- Create: `apps/referee/lib/referee/pc.ex`, `apps/referee/lib/referee/slice.ex`
- Test: `apps/referee/test/pc_test.exs`, `apps/referee/test/slice_test.exs`

- [ ] **Step 1 (failing tests):** `PC.build/1` produces a valid tier-3 agent with the fixed capability list and empty beliefs; `PC.join_events/2` yields one `:agent_added` event that folds the PC in at the entry place. `Slice.for_actor/2`: contains actor identity, place summary, believed agents for the current place only; NEVER contains another room's agent ids, hidden item ids, or monster statblocks of unbelieved agents; lists sorted; `summary` renders `Narrate`-style place line.
- [ ] **Step 2:** Implement. Slice reads `agent.beliefs[place_id]` keys ∪ agents co-present (perceivable), place connections from edges; `prompt_slice_ref` per Shared Interfaces.
- [ ] **Step 3:** `mix test apps/referee`. Commit `feat(referee): pc construction + actor-visible slice (truth barrier)`.

## Task 8: Interpret — LLM + grammar fallback + ambiguity policy

**Files:**
- Create: `apps/referee/lib/referee/grammar.ex`, `apps/referee/lib/referee/interpret.ex`
- Test: `apps/referee/test/grammar_test.exs`, `apps/referee/test/interpret_test.exs`

- [ ] **Step 1 (failing tests, grammar):** deterministic parse of "go north" → `%Action{verb: :move, params: %{direction: "north"}}`; "attack the goblin guard" → `:strike` with target resolved by token match against believed agent names/ids; "shout 'the tower falls!'" → `:shout` with message; "wait" → `:wait`; unmatchable → `{:unclear, rest}` (caller turns into hesitant :wait + assumption). Strike with token matching ≥2 believed agents equally → `{:ambiguous, [ids]}` (lethal-ambiguity trigger).
- [ ] **Step 2 (failing tests, interpret):** scripted-adapter ctx: valid JSON action comes back as `{:ok, action, assumptions, ctx2, audit}` with audit class `:interpret`; adapter error → grammar result with `parse_verdict: :fallback` audit; grammar `:ambiguous` → `{:clarify, "...which one...", ...}`; truth-barrier property: for a world with an agent in another room + hidden item, the user prompt string contains neither id (grep the captured prompt from scripted scripts via debug capture of `request.user`).
- [ ] **Step 3:** Implement. LLM system prompt states role, output schema, and decision-32 policy verbatim ("clarify only on lethal ambiguity; otherwise choose the most plausible parse and list assumptions"). Grammar runs only on failure — LLM-first is the point of phase 5.
- [ ] **Step 4:** `mix test apps/referee`. Commit `feat(referee): interpret stage - llm-first with deterministic grammar fallback, lethal-ambiguity clarifications`.

## Task 9: Validate → Resolve → Apply → Narrate + `Referee.Run`

**Files:**
- Create: `apps/referee/lib/referee/validate.ex`, `apps/referee/lib/referee/resolve.ex`, `apps/referee/lib/referee/narrate.ex`, `apps/referee/lib/referee/run.ex`, `apps/referee/lib/referee/spend.ex`
- Test: `apps/referee/test/validate_test.exs`, `apps/referee/test/resolve_test.exs`, `apps/referee/test/narrate_test.exs`, `apps/referee/test/run_test.exs`

- [ ] **Step 1 (failing tests, validate):** verb ∉ capabilities ⇒ reject; `:strike` with no belief about target in place ⇒ diegetic reject ("You see no such creature"); `:move` through sealed edge ⇒ diegetic reject; valid move/strike/wait/shout ⇒ `:ok`. Retry budget: third rejection within one tick ⇒ `{:stall, ...}` surfaced by `Run.declare` as "the moment passes".
- [ ] **Step 2 (failing tests, resolve):** `:strike` with stale belief (target believed, actually elsewhere) ⇒ `{:diegetic_fail, [belief_corrected + miss event], ...}` and the belief is gone from the folded world; `:move` delegates to `Movement.traverse`; `:shout` emits a `:sound`/voices signal into the current place (assert `signal_emitted` event + `in_flight` arrival); `:wait` emits nothing.
- [ ] **Step 3 (failing tests, narrate):** with budget available and scripted narrate response → LLM text returned, audit appended; with `budget_degraded` ctx → `EngineCore.Narrate` template text, `parse_verdict: :fallback`; `narration_style: "rich"` vs `"terse"` changes template assembly.
- [ ] **Step 4 (failing tests, run):** `new/3` loads the tower, emits `meta/prefs_stack` first with the resolved hash, `:agent_added` per PC sorted; `declare` happy path (move north from entry) returns narration mentioning the destination and mutates `run.world` via `Fold` only; ledger order is exactly: llm audits intermixed with world events in call order; `advance` ticks the scheduler and returns per-PC narrations only for PCs with new beliefs; `spend_report` aggregates tokens by class and agent from `llm_call` events.
- [ ] **Step 5:** Implement. `Run.declare` pipeline: interpret → (clarify? return) → validate (rejection → narrated rejection, increment counter) → resolve → apply (`Fold.fold` + `Scheduler.react` for side-effect signals) → narrate → append audits + events (seq assigned in append order). NO wall-clock; no unsorted map iteration.
- [ ] **Step 6:** `mix test` (all apps). Commit `feat(referee): full propose-validate-resolve-apply-narrate pipeline over engine_core`.

## Task 10: CLI smoke + golden replay determinism

**Files:**
- Create: `shards_engine/scripts/referee_smoke.exs`
- Modify: `shards_engine/automated-run.sh` (add `referee` mode)
- Test: `apps/referee/test/golden_test.exs`

- [ ] **Step 1 (failing golden test):** build a Run twice from the same tower YAML + seed + 4-PC spec + scripted interpret/narrate scripts + an 8-intent declare script (moves, a stale-belief strike, a shout, a wait, an invalid verb, an ambiguous attack → clarify); assert `:erlang.term_to_binary(run2.ledger) == term_to_binary(run1.ledger)` and both runs' final `world.tick` match. Also assert a different seed changes the ledger (RNG-branch evidence).
- [ ] **Step 2:** `scripts/referee_smoke.exs`: headless playthrough printing each intent → narration, then `Spend.report` table; wire `automated-run.sh referee`.
- [ ] **Step 3:** `mix test` all green (expect 89 + ~35 new). Run `./automated-run.sh referee` and paste output in the task log. Commit `test(referee): golden byte-identical replay + cli smoke mode`.

## Plan 3 Acceptance (maps to spec §12.4 phase 5)

1. PC NL intents run the full pipeline headless against the real tower YAML — `./automated-run.sh referee` shows interpret→…→narrate for moves/strikes/shouts, a diegetic stale-belief miss, an ambiguity clarification, and a spend report.
2. Chokepoint: every LLM call in the codebase flows through `LLMGateway.Router.complete/2`; adapters appear nowhere else (grep-verified in review).
3. Budget degradation order (narrate → interpret) demonstrated by test; circuit breaker opens after 3 consecutive adapter failures.
4. Preference stack: module layer in the tower YAML, personal override, unknown-key warning, hash ledgered as the first `meta` event of the run.
5. Truth barrier: property test shows prompts contain no non-local agent ids, no hidden items, no unbelieved statblocks.
6. Determinism: golden test proves byte-identical ledgers for identical inputs; verbatim replay of scripted runs is exact.
7. Offline: full suite green with zero network (`mix test` at umbrella root).

## Next Plans

- **Plan 4** (spec §12.4 phase 6): tier-3 brain processes over the `:cadence_tick` plug-in point, salience gate, envelopes + order adoption with reliability rolls, `deliberation` event class.
- **Plan 5** (spec §12.4 phase 7): Phoenix channels (`run:<id>`), per-PC isolation at push, spectate console, terminal reference client over WS, PC dossiers (summarize class), OTP supervision tree (World.Server, Ledger.Writer promotion, Run.Session).
- **Plan 6** (spec §12.4 phase 8): scripted end-to-end playthroughs over channels, fork-diff emergence scenarios, spend dashboards, XP/treasure claim consumption of `prefs.xp`.
