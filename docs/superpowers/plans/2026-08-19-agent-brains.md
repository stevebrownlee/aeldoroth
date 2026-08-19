# Agent Engine — Plan 4: Tier-3 Brains, Salience Gate, Envelopes & Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give tier-3 agents their brains (spec §12.4 phase 6): supervised OTP actors that deliberate on `:cadence_tick` events behind a salience gate, and the envelope economy — orders sent as typed envelopes, autonomously adopted (or rejected, possibly with deception) into commitments. Headless, offline-testable, replay-deterministic with scripted adapters.

**Scope split (deliberate):** spec §12.4 phases 7–8 are NOT in this plan. Phoenix channels + terminal client + spectate → Plan 5. Acceptance harness/fork-diff → Plan 6.

**Architecture:** One new umbrella app `apps/agents` (deps: `engine_core`, `llm_gateway` — never `referee`, so `referee` may depend on it). `Agents.DynamicSup` supervises one temporary, stateless GenServer brain per tier-3 agent (state = agent_id only — pattern `brains-hold-no-authority-state`); a Registry names them. `Referee.Run.advance` is the single coordinator: it processes due envelopes and cadence ticks **sequentially in deterministic order** (sorted by id), calling each brain synchronously — concurrency exists for fault isolation (kill/restart = hesitation, spec §10), never for ordering. All LLM traffic still flows through `LLMGateway.Router` (pattern 14). Brain proposals re-enter the existing Validate → Resolve → react pipeline (pattern `effects-via-referee-pipeline`); LLM output never becomes world state. Envelopes are engine_core data: `:envelope_sent/delivered/adopted/rejected` fold clauses, delivery keyed off the voice signal the order rode on — a shout that is never received never delivers its order.

**Tech Stack:** Elixir ≥ 1.17 / OTP ≥ 27, Mix umbrella, ExUnit, `yaml_elixir` (engine_core), `jason` (llm_gateway).

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` §12.4 phase 6 ("Brains: deliberation + salience gate; envelopes, order adoption, reliability"), §5.1–5.6 (anatomy/tiers/beliefs/salience/commitments/capabilities/orders), §6.3 (envelopes), §9.1 (`envelope` + `deliberation` event classes), §10 (`deliberate` heavy / `adopt` mid classes, failure semantics: `deliberate` → diegetic no-op hesitation; brains are disposable actors).

**Engrams design record (do not re-litigate):** decisions 29 (hybrid: brains deliberate only, ledger holds authority), 30 (autonomous adoption — no hive puppeting), 26 (tiered LLM routing), 20/32 (LLM proposes, engine disposes; ambiguity policy), 41 (Plans 3–6 partition); patterns 14 (`llm-gateway-single-chokepoint`), 9 (`brains-hold-no-authority-state`), 11 (`effects-via-referee-pipeline`), 10 (`append-only-ledger`), 12 (`activation-gated-deliberation`).

## Global Constraints

- `engine_core` changes are ADDITIVE ONLY: `Types.Envelope`, `World.envelopes` field (default `[]`), four new `Fold` clauses, `EngineCore.Envelopes` module, `caps(3)` gains `:order`. Existing tests stay green; no new deps; no wall-clock.
- `apps/agents` deps: `in_umbrella [:engine_core, :llm_gateway]` ONLY. `referee` adds `{:agents, in_umbrella: true}`. No other dep changes.
- Brain processes hold NO authority state (pattern 9): `Agents.Brain` state is exactly the agent id. Dice never roll inside a brain — rolls happen in `Referee.Run` (seeded `run.rng`) and are passed in; brains are deterministic functions of their message.
- Determinism: `Run.advance` serializes every brain call (sorted by agent id / envelope id); identical YAML + seed + scripts ⇒ byte-identical ledger (`:erlang.term_to_binary/1`). Any list derived from maps is sorted before use. No wall-clock, no `System.unique_integer` in ledgered data.
- Scripted-adapter queue state is process-dictionary keyed by the scripts map — brain processes each hold their own copy. Therefore: tests give every run/test its own scripts map (existing `salt:` convention), and per-agent responses use agent-keyed entries (Task 2). Prompt-content assertions use the `request` carried in brain replies (NOT `Scripted.take_requests/0`, which only sees the calling process's pops).
- Chokepoint (pattern 14): brains call `LLMGateway.Router.complete/2` only; adapters appear nowhere new.
- Truth barrier: brain prompts are built ONLY from `Referee.Slice` output + the envelope itself (minus `truth`); `envelope.truth` NEVER enters any prompt. `is_hidden` items and non-local agents never enter a prompt.
- Failure semantics (spec §10): `deliberate` failure (no route, breaker, parse fail, schema-invalid, brain dead) ⇒ diegetic no-op **hesitation**, logged as a `:deliberation` event; `adopt` failure ⇒ deterministic reliability-heuristic fallback using the coordinator's roll. Router budget: `deliberate`/`adopt` never degrade (existing Router behavior).
- All tests offline, `async: true` permitted (salt-keyed scripts). Run per app: `cd shards_engine/apps/<app> && mix test`.
- Commit style: conventional (`feat:`, `fix:`, `test:`, `chore:`), one logical change per commit.

## File Structure

```
shards_engine/apps/
├── agents/                                   # CREATE app
│   ├── mix.exs
│   ├── lib/agents.ex                         # supervisor façade: ensure/whereis/kill/deliberate/adopt
│   ├── lib/agents/application.ex             # Registry + DynamicSupervisor
│   ├── lib/agents/brain.ex                   # stateless GenServer per tier-3 agent
│   ├── lib/agents/prompt.ex                  # deliberate + adopt prompt/schema assembly (pure)
│   ├── lib/agents/salience.ex                # cadence escalation gate (pure)
│   ├── lib/agents/adopt.ex                   # reliability heuristic + feasibility (pure)
│   └── test/  (brain_test.exs, salience_test.exs, adopt_test.exs, deliberate_test.exs, adopt_brain_test.exs)
├── engine_core/lib/engine_core/
│   ├── types.ex                              # MODIFY: +Types.Envelope
│   ├── world.ex                              # MODIFY: +envelopes: []
│   ├── fold.ex                               # MODIFY: +4 envelope clauses
│   ├── envelopes.ex                          # CREATE: send / deliver_due
│   └── loader.ex                             # MODIFY: caps(3) += :order
├── llm_gateway/lib/llm_gateway/adapters/scripted.ex   # MODIFY: agent-keyed entries
├── referee/
│   ├── mix.exs                               # MODIFY: +agents dep
│   ├── lib/referee/slice.ex                  # MODIFY: +commitments, +capabilities
│   ├── lib/referee/validate.ex               # MODIFY: +:order clause
│   ├── lib/referee/resolve.ex                # MODIFY: +:order clause
│   └── lib/referee/run.ex                    # MODIFY: advance phases (deliver/adopt/deliberate)
shards_engine/scripts/brains_smoke.exs        # CREATE
shards_engine/automated-run.sh                # MODIFY: `brains` mode
```

## Shared Interfaces (tasks must match these exactly)

- `EngineCore.Types.Envelope` — `@enforce_keys [:id, :from, :to, :type, :payload_nl, :sent_tick, :delivery_place, :signal_ref]`; `defstruct [:id, :from, :to, :type, :payload_nl, :sent_tick, :delivery_place, :signal_ref, truth: :unverified, adopted: nil, status: :pending]`. `type` ∈ `[:order, :inform, :request, :plead, :warn]`; `status` ∈ `[:pending, :delivered, :adopted, :rejected]`.
- `EngineCore.Envelopes.send(world, from, to, type, payload_nl, opts \\ []) :: {:ok, [Ledger.Event.t()], World.t()}` — emits a `:sound` voices signal (`%{class: :voices, about: from, count: 1}`, intensity 6.0, `content_nl: payload_nl`) then one `%{kind: :envelope_sent, envelope: %Types.Envelope{}}` event (class `:envelope`); `opts`: `truth: true | false | :unverified` (default `:unverified`). Envelope id: `"env-#{world.tick}-#{length(world.envelopes) + 1}"`; `signal_ref` = the emitted signal's ref; `delivery_place` = emitter's place.
- `EngineCore.Envelopes.deliver_due(world, received_payloads) :: {:ok, [Ledger.Event.t()], World.t()}` — for each pending envelope in list order, first receipt (from `received_payloads`, which are `%{kind: :signal_received, agent_id, ref, place_id, ...}` payloads in seq order) with `agent_id == env.to and ref == env.signal_ref` yields `%{kind: :envelope_delivered, id, place_id}` (class `:envelope`). None ⇒ `{:ok, [], world}`.
- Fold additions (class `:envelope` → state change):
  - `:envelope_sent` — append `struct!(Types.Envelope, Map.to_list(p.envelope))` to `world.envelopes`.
  - `:envelope_delivered` — set `status: :delivered` on that envelope; add recipient belief `beliefs[p.place_id]["#{env.type}:#{env.id}"] = %{count: 1, last_tick: tick, last_fidelity: 3, salience: 6.0, seen: false}`.
  - `:envelope_adopted` — `status: :adopted`, `adopted: true`.
  - `:envelope_rejected` — `status: :rejected`, `adopted: false`.
- `LLMGateway.Adapters.Scripted` entries: `String.t() | %{agent_id: String.t(), content: String.t()}`. Pop = first entry that is a binary or whose `agent_id` equals `req.agent_id`; no match ⇒ `{:error, :script_exhausted}`. Binary-only behavior unchanged.
- `Agents.ensure_brain(agent_id) :: :ok | {:error, term()}` · `Agents.whereis(agent_id) :: pid() | nil` · `Agents.kill_brain(agent_id) :: :ok`.
- `Agents.deliberate(agent_id, %{slice: map(), ctx: Ctx.t()}) :: {:ok, %{action: Types.Action.t(), reason: String.t(), request: Request.t(), ctx: Ctx.t(), audit: Audit.t() | nil}} | {:hesitate, %{reason: String.t(), request: Request.t() | nil, ctx: Ctx.t(), audit: Audit.t() | nil}} | {:error, :brain_unavailable}` — LLM class `:deliberate`, schema-constrained; verb must be one of `slice.capabilities` (else hesitation).
- `Agents.adopt(agent_id, %{envelope: map(), slice: map(), ctx: Ctx.t(), roll: pos_integer(), feasible: boolean(), debtor: Types.Agent.t()}) :: {:ok, %{adopted: boolean(), deed: String.t(), deceive: boolean(), inform: String.t() | nil, reason: String.t(), request: Request.t() | nil, ctx: Ctx.t(), audit: Audit.t() | nil}} | {:error, :brain_unavailable}` — LLM class `:adopt`; failure ⇒ heuristic fallback inside the brain (never errors).
- `Agents.Salience.escalate?(%Types.Agent{}, integer()) :: boolean()` — true iff any commitment has status `:pending`/`:due` OR any belief at the agent's current place has `salience >= 7.0`.
- `Agents.Adopt.feasible?(World.t(), %Types.Envelope{} | map()) :: boolean()` · `reliability(%Types.Agent{}, boolean()) :: integer()` (morale + INT adj [≥12 → +2, ≤7 → −2] + feasibility [+3 / −4]) · `decide(roll, target) :: :adopt | :reject` (`roll <= target`).
- `Agents.Prompt.deliberate(slice) :: {system :: String.t(), user :: String.t(), schema :: map()}` · `Agents.Prompt.adopt(slice, envelope) :: {system, user, schema}`.
- `Referee.Slice.for_actor/2` output gains `commitments: [%{id, deed, status, priority, creditor}]` (sorted by id) and `capabilities: [atom()]`.
- `Referee.Resolve.act/3` gains `:order` → `EngineCore.Envelopes.send(world, actor_id, target_id, :order, message, truth: true)` where `message = params[:message] || ""`; `Referee.Validate.check/2` gains an `:order` clause (target required + believed in current place, diegetic rejects otherwise).
- `Referee.Run.advance/1` (signature unchanged) phases, in order: scheduler `advance` + `react` (existing) → envelope delivery → order adoption (delivered `:order` envelopes, sorted by id) → tier-3 cadence deliberation (cadence ticks from the scheduler pass, sorted by agent id) → per-PC receipt narration over ALL `:signal_received` events appended during this call. New ledger rows: `:envelope` events, adoption `:dice` events (`%{purpose: :adoption, sides: 20, roll, target, adopted}` — no `:kind`, dice convention), `:commitment` rows from `Commitments.create` with id `"adopted:#{env.id}"`, `:deliberation` events (`%{agent_id, decision: :proposed | :hesitated | :rejected | :skipped, verb | nil, reason}` — no `:kind`, audit-only), `:llm` audits.
- Deliberate LLM output schema (string-keyed JSON, like interpret): `{"verb": string, "target_id": string|null, "direction": string|null, "message": string|null, "reason": string}`, `required: [:verb, :reason]`, `verb` enum = `slice.capabilities`. Adopt schema: `{"adopted": boolean, "deed": string, "deceive": boolean, "inform": string|null, "reason": string}`, `required: [:adopted, :reason]`.

---

### Task 1: Scaffold `apps/agents` — supervisor, registry, brain lifecycle

**Files:**
- Create: `shards_engine/apps/agents/mix.exs`, `lib/agents.ex`, `lib/agents/application.ex`, `lib/agents/brain.ex`, `test/agents_test.exs`, `test/brain_test.exs`, `test/test_helper.exs`
- Modify: `shards_engine/apps/referee/mix.exs` (add `{:agents, in_umbrella: true}`)

**Interfaces:**
- Consumes: nothing (pure OTP scaffolding).
- Produces: `Agents.ensure_brain/1`, `Agents.whereis/1`, `Agents.kill_brain/1`, `Agents.Brain` GenServer (state = agent id), started application tree (`Agents.Registry`, `Agents.DynamicSup`).

- [ ] **Step 1 (failing tests):** in `test/brain_test.exs`:

```elixir
defmodule Agents.BrainTest do
  @moduledoc "Brain lifecycle: one temporary process per tier-3 agent id."
  use ExUnit.Case, async: true

  test "ensure_brain starts a registered brain, idempotently" do
    assert :ok == Agents.ensure_brain("grisk_the_snatcher")
    pid = Agents.whereis("grisk_the_snatcher")
    assert is_pid(pid)
    assert :ok == Agents.ensure_brain("grisk_the_snatcher")
    assert pid == Agents.whereis("grisk_the_snatcher")
  end

  test "kill leaves no brain; ensure restarts a fresh one" do
    Agents.ensure_brain("willem")
    pid = Agents.whereis("willem")
    Agents.kill_brain("willem")
    :timer.sleep(10)
    assert nil == Agents.whereis("willem")
    assert :ok == Agents.ensure_brain("willem")
    refute pid == Agents.whereis("willem")
  end

  test "distinct agents get distinct brains" do
    Agents.ensure_brain("goblin_guard_1")
    Agents.ensure_brain("goblin_guard_2")
    refute Agents.whereis("goblin_guard_1") == Agents.whereis("goblin_guard_2")
  end
end
```

Also `test/agents_test.exs`: assert `Agents` module loads and exports `ensure_brain/1`.

- [ ] **Step 2:** Run `cd shards_engine/apps/agents && mix test` — expect compile failure (no app yet).
- [ ] **Step 3 (implement):**

`mix.exs` (mirror referee's): app `:agents`, version 0.1.0, `in_umbrella` deps `:engine_core`, `:llm_gateway`, `elixirc_paths` standard, `start_permanent` in dev/test envs, `preferred_cli_env` test: :test.

`lib/agents/application.ex`:
```elixir
defmodule Agents.Application do
  @moduledoc "One Registry + one DynamicSupervisor for tier-3 brains (spec 12.1)."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Agents.Registry},
      {DynamicSupervisor, name: Agents.DynamicSup}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: Agents.Supervisor)
  end
end
```

`lib/agents/brain.ex`:
```elixir
defmodule Agents.Brain do
  @moduledoc """
  One tier-3 brain: a disposable, stateless OTP actor (decision 29, pattern 9).
  State is the agent id and nothing else — all authority lives in the ledger.
  Kill/restart is a hesitation at the coordinator (spec 10). Deliberation and
  adoption handlers arrive with Tasks 5-6.
  """
  use GenServer, restart: :temporary

  def child_spec(agent_id) do
    %{id: {:brain, agent_id}, start: {__MODULE__, :start_link, [agent_id]}, restart: :temporary}
  end

  def start_link(agent_id) do
    GenServer.start_link(__MODULE__, agent_id,
      name: {:via, Registry, {Agents.Registry, agent_id}})
  end

  @impl true
  def init(agent_id), do: {:ok, agent_id}
end
```

`lib/agents.ex`:
```elixir
defmodule Agents do
  @moduledoc "Façade over the brain pool. The only module the referee calls."

  @spec ensure_brain(String.t()) :: :ok | {:error, term()}
  def ensure_brain(agent_id) do
    case whereis(agent_id) do
      nil ->
        case DynamicSupervisor.start_child(Agents.DynamicSup, {Agents.Brain, agent_id}) do
          {:ok, _pid} -> :ok
          {:error, :already_started, _pid} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(agent_id) do
    case Registry.lookup(Agents.Registry, agent_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @spec kill_brain(String.t()) :: :ok
  def kill_brain(agent_id) do
    case whereis(agent_id) do
      nil -> :ok
      pid -> Process.exit(pid, :kill); :ok
    end
  end
end
```

Add `{:agents, in_umbrella: true}` to referee deps. `test/test_helper.exs`: `ExUnit.start()`.

- [ ] **Step 4:** `mix test` in `apps/agents` (4 green) and `apps/referee` (still 58). Commit `chore: scaffold agents umbrella app - brain supervisor, registry, lifecycle`.

### Task 2: Scripted adapter — agent-keyed entries

**Files:**
- Modify: `shards_engine/apps/llm_gateway/lib/llm_gateway/adapters/scripted.ex`
- Test: `shards_engine/apps/llm_gateway/test/scripted_test.exs` (append cases; adapt to the existing file's helpers)

**Interfaces:**
- Consumes: `LLMGateway.Request.agent_id`.
- Produces: entries `%{agent_id: id, content: s}` pop-first-match semantics (Shared Interfaces) — relied on by every agents-app test and the golden test.

- [ ] **Step 1 (failing tests):** in the existing scripted test module, append:

```elixir
test "agent-keyed entries pop only for their agent, in order" do
  scripts = %{
    deliberate: [
      %{agent_id: "grisk", content: ~s({"verb":"wait","reason":"bored"})},
      %{agent_id: "goblin_bodyguard_1", content: ~s({"verb":"strike","reason":"orders"})},
      %{agent_id: "grisk", content: ~s({"verb":"shout","reason":"alarmed"})}
    ],
    salt: System.unique_integer()
  }

  cfg = %{adapter: Scripted, model: nil, endpoint: nil, key_ref: nil,
          temperature: 0.1, max_tokens: 512, scripts: scripts}

  req = fn id -> %Request{class: :deliberate, agent_id: id, system: "s", user: "u"} end

  assert {:ok, %Result{content: ~s({"verb":"strike","reason":"orders"})}} =
           Scripted.complete(req.("goblin_bodyguard_1"), cfg)

  assert {:ok, %Result{content: ~s({"verb":"wait","reason":"bored"})}} =
           Scripted.complete(req.("grisk"), cfg)

  assert {:ok, %Result{content: ~s({"verb":"shout","reason":"alarmed"})}} =
           Scripted.complete(req.("grisk"), cfg)

  assert {:error, :script_exhausted} = Scripted.complete(req.("grisk"), cfg)
  assert {:error, :script_exhausted} = Scripted.complete(req.("willem"), cfg)
end

test "binary entries still match any agent (back-compat)" do
  scripts = %{interpret: ["one", "two"], salt: System.unique_integer()}
  cfg = %{adapter: Scripted, model: nil, endpoint: nil, key_ref: nil,
          temperature: 0.1, max_tokens: 512, scripts: scripts}

  req = %Request{class: :interpret, agent_id: "anyone", system: "s", user: "u"}
  assert {:ok, %Result{content: "one"}} = Scripted.complete(req, cfg)
  assert {:ok, %Result{content: "two"}} = Scripted.complete(req, cfg)
  assert {:error, :script_exhausted} = Scripted.complete(req, cfg)
end
```

- [ ] **Step 2:** Run `cd apps/llm_gateway && mix test` — expect the agent-keyed test to fail (a `%{agent_id: _}` entry currently pops for anyone and JSON-parses as nil).
- [ ] **Step 3 (implement):** in `Scripted.complete/2`, replace the head-pop with a matching pop. The queue for class `c` pops the FIRST entry that is a binary or whose `:agent_id` equals `req.agent_id`; remaining preserves order minus that entry; no match ⇒ `{:error, :script_exhausted}`:

```elixir
defp pop_for([], _agent_id), do: :none

defp pop_for(entries, agent_id) do
  idx = Enum.find_index(entries, &(is_binary(&1) or &1[:agent_id] == agent_id))

  case idx do
    nil -> :none
    idx -> {:ok, entries |> Enum.at(idx) |> content_of(), List.delete_at(entries, idx)}
  end
end

defp content_of(%{content: c}), do: c
defp content_of(c) when is_binary(c), do: c
```

Keep pdict get/put, request capture, usage computation exactly as-is.
- [ ] **Step 4:** llm_gateway tests green (existing 36 + 2). Commit `feat(llm_gateway): agent-keyed scripted entries for per-brain queues`.

### Task 3: engine_core — envelope type, fold clauses, send/deliver

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/types.ex`, `world.ex`, `fold.ex`
- Create: `shards_engine/apps/engine_core/lib/engine_core/envelopes.ex`
- Test: `shards_engine/apps/engine_core/test/envelopes_test.exs`; append to `test/fold_test.exs`

**Interfaces:**
- Consumes: `Signals.emit_at/6`, `Fold.fold/2`, `World.agent/2`.
- Produces: `Types.Envelope`, `World.envelopes`, four fold clauses, `Envelopes.send/5`, `Envelopes.deliver_due/2` (exact shapes in Shared Interfaces).

- [ ] **Step 1 (failing tests, envelopes_test.exs):** load the tower YAML via `EngineCore.Loader.load/1`. Cases:
  1. `Envelopes.send(world, "grisk_the_snatcher", "goblin_bodyguard_1", :order, "Kill them!")` → `{:ok, [sig_ev, env_ev], w2}`: `sig_ev.payload.kind == :signal_emitted` (`signal_kind: :sound`, `content_core.class: :voices`, `intensity: 6.0`, `content_nl: "Kill them!"`); `env_ev.payload == %{kind: :envelope_sent, envelope: env}`, `env.signal_ref == sig_ev.payload.ref`, `env.status == :pending`, `env.delivery_place == "chiefs_room"`, `env.id == "env-0-1"` at tick 0 (deterministic: `"env-#{tick}-#{n}"`), `env.truth == :unverified` by default; folded `w2.envelopes == [env]`; a second send yields id `"env-0-2"`.
  2. `Envelopes.deliver_due/2` with receipt `%{kind: :signal_received, agent_id: "goblin_bodyguard_1", ref: env.signal_ref, place_id: "chiefs_room"}` emits `%{kind: :envelope_delivered, id: env.id, place_id: "chiefs_room"}`; folded world: envelope `status: :delivered`, bodyguard belief `beliefs["chiefs_room"]["order:#{env.id}"] == %{count: 1, last_tick: _, last_fidelity: 3, salience: 6.0, seen: false}`.
  3. No matching receipt (wrong agent, wrong ref, or none) ⇒ `{:ok, [], world}`, status stays `:pending`; a receipt for another pending envelope's ref does not deliver it.
  4. Fold clauses for adopted/rejected (fold_test.exs):

```elixir
test "envelope adopted/rejected fold onto status and adopted flag" do
  # w carries one pending envelope with id "env-0-1"
  w2 = Fold.fold(w, [%Ledger.Event{seq: 0, tick: 1, class: :envelope,
    payload: %{kind: :envelope_adopted, id: "env-0-1"}}])
  env = hd(w2.envelopes)
  assert env.status == :adopted and env.adopted == true

  w3 = Fold.fold(w, [%Ledger.Event{seq: 0, tick: 1, class: :envelope,
    payload: %{kind: :envelope_rejected, id: "env-0-1"}}])
  env3 = hd(w3.envelopes)
  assert env3.status == :rejected and env3.adopted == false
end
```

- [ ] **Step 2:** Run `cd apps/engine_core && mix test` — new tests fail.
- [ ] **Step 3 (implement):** `Types.Envelope` per Shared Interfaces; `World` gains `envelopes: []`; `Fold` clauses (helper `update_envelope(world, id, fun)` replaces-by-id preserving list order; `envelope_by_id/2` via `Enum.find`):

```elixir
:envelope_sent ->
  %{world | envelopes: world.envelopes ++ [struct!(EngineCore.Types.Envelope, Map.to_list(p.envelope))]}

:envelope_delivered ->
  env = envelope_by_id(world, p.id)

  world
  |> update_envelope(p.id, fn e -> %{e | status: :delivered} end)
  |> update_agent(env.to, fn a ->
    entry = %{count: 1, last_tick: tick, last_fidelity: 3, salience: 6.0, seen: false}
    place_map = Map.put(a.beliefs[p.place_id] || %{}, "#{env.type}:#{env.id}", entry)
    %{a | beliefs: Map.put(a.beliefs, p.place_id, place_map)}
  end)

:envelope_adopted -> update_envelope(world, p.id, &%{&1 | status: :adopted, adopted: true})
:envelope_rejected -> update_envelope(world, p.id, &%{&1 | status: :rejected, adopted: false})
```

`Envelopes.send/5`: `place = World.agent(world, from).place_id`; `Signals.emit_at(world, from, place, :sound, %{class: :voices, about: from, count: 1}, 6.0, payload_nl)`; `ref = sig_ev.payload.ref`; envelope event at tick `world.tick` with `truth: Keyword.get(opts, :truth, :unverified)`; fold both. `Envelopes.deliver_due/2`: scan `world.envelopes` (list order), for each `status: :pending` find `Enum.find(receipts, &(&1[:kind] == :signal_received and &1[:agent_id] == env.to and &1[:ref] == env.signal_ref))`; emit and fold immediately (later envelopes see prior state).
- [ ] **Step 4:** engine_core green (91 + ~5). Commit `feat(engine_core): envelopes - typed send, signal-keyed delivery, fold clauses`.

### Task 4: Salience gate + slice carries commitments/capabilities

**Files:**
- Create: `shards_engine/apps/agents/lib/agents/salience.ex`, `test/salience_test.exs`
- Modify: `shards_engine/apps/referee/lib/referee/slice.ex`; test: `apps/referee/test/slice_test.exs`

**Interfaces:**
- Consumes: `Types.Agent` (`beliefs`, `commitments`, `place_id`, `capabilities`).
- Produces: `Agents.Salience.escalate?/2`; slice keys `:commitments`, `:capabilities` (Task 5's prompts and Task 8's gate consume them).

- [ ] **Step 1 (failing tests, salience_test.exs):**

```elixir
defmodule Agents.SalienceTest do
  use ExUnit.Case, async: true
  alias Agents.Salience
  alias EngineCore.Types

  test "pending or due commitments escalate (cadence = commitment check)" do
    agent = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :pending}]}
    assert Salience.escalate?(agent, 5)
  end

  test "kept or violated commitments do not escalate alone" do
    agent = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :kept}]}
    refute Salience.escalate?(agent, 5)
  end

  test "a salient belief escalates; quiet agents do not" do
    quiet = %Types.Agent{id: "q", name: "Q", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"noise" => %{salience: 4.0}}}}
    refute Salience.escalate?(quiet, 5)

    scared = %Types.Agent{id: "s", name: "S", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"pc_thistle" => %{salience: 7.0}}}}
    assert Salience.escalate?(scared, 5)
  end

  test "beliefs in other places do not escalate" do
    far = %Types.Agent{id: "f", name: "F", tier: 3, place_id: "r1",
      beliefs: %{"r2" => %{"pc" => %{salience: 9.0}}}}
    refute Salience.escalate?(far, 5)
  end
end
```

Slice tests: tower-YAML world — an agent holding a commitment yields `slice.commitments == [%{id: _, deed: _, status: _, priority: _, creditor: _}]` (5-field maps, sorted by id) and `slice.capabilities == agent.capabilities`; a PC slice yields `commitments: []`.

- [ ] **Step 2:** Run agents + referee tests — new ones fail.
- [ ] **Step 3 (implement):**

```elixir
defmodule Agents.Salience do
  @moduledoc """
  Cadence escalation gate (spec 5.3): an agent's cadence tick buys full
  deliberation only under pressure — outstanding commitments (the cadence IS
  the commitment check) or salient novelty (threat/intruder beliefs).
  Otherwise the tick is skipped and logged: no LLM call.
  """
  alias EngineCore.Types

  @salience_threshold 7.0

  @spec escalate?(Types.Agent.t(), integer()) :: boolean()
  def escalate?(%Types.Agent{} = agent, _tick), do: pressured?(agent) or salient?(agent)

  defp pressured?(agent),
    do: Enum.any?(agent.commitments, &(&1.status in [:pending, :due]))

  defp salient?(agent) do
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Enum.any?(fn {_about, b} -> b[:salience] >= @salience_threshold end)
  end
end
```

Slice: add `commitments:` (map each to `%{id, deed, status, priority, creditor}`, sort by id) and `capabilities: agent.capabilities` to the returned map.
- [ ] **Step 4:** agents + referee green. Commit `feat(agents): salience escalation gate; slice exposes commitments and capabilities`.

### Task 5: Brain deliberation — prompt, schema, hesitation semantics

**Files:**
- Create: `shards_engine/apps/agents/lib/agents/prompt.ex`; Modify: `lib/agents/brain.ex`, `lib/agents.ex`
- Test: `apps/agents/test/deliberate_test.exs`

**Interfaces:**
- Consumes: slice-shaped maps (plain data — agents never depends on referee), `LLMGateway.{Request, Result, Audit, Ctx, Router}`, Scripted agent-keyed entries (Task 2), `Types.Action`.
- Produces: `Agents.Prompt.deliberate/1`, `Agents.deliberate/2` (shapes in Shared Interfaces — Task 8's coordinator consumes them).

- [ ] **Step 1 (failing tests):** hand-built slices (plain maps) + Scripted ctx:

```elixir
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
    Agents.kill_brain("willem")
    entry = ~s({"verb":"wait","reason":"huddle"})
    assert {:ok, _} = Agents.deliberate("willem",
      %{slice: slice("willem", %{believed: [], salient: [], commitments: [],
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

    {head, _summary} = String.split(d.request.user, "Summary:", parts: 2)
    assert head =~ "Commitments:"
    assert head =~ "Salient here:"
  end
end
```

- [ ] **Step 2:** Run `cd apps/agents && mix test` — fail (no Prompt/handler).
- [ ] **Step 3 (implement):**

`Agents.Prompt`:
```elixir
def deliberate(slice) do
  caps = slice.capabilities

  schema = %{
    type: :object,
    properties: %{
      verb: %{type: :string, enum: caps},
      target_id: %{type: :string, nullable: true},
      direction: %{type: :string, nullable: true},
      message: %{type: :string, nullable: true},
      reason: %{type: :string}
    },
    required: [:verb, :reason]
  }

  system = """
  You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
  tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
  Choose exactly one action for this moment. Respond ONLY with a JSON object:
  {"verb": string, "target_id": string | null, "direction": string | null,
  "message": string | null, "reason": string}.
  verb must be one of your capabilities. target_id must come from your believed
  list — never invent one. Ordering a subordinate uses verb "order", the
  subordinate's id as target_id, and the spoken order as message.
  """

  user = """
  You are #{slice.agent.name} in #{slice.place.name}.
  Commitments: #{commitment_lines(slice.commitments)}
  Salient here: #{Enum.join(slice.salient, ", ")}
  Believed here: #{Enum.join(slice.believed, ", ")}
  Exits: #{Enum.join(slice.place.exits, ", ")}
  Capabilities: #{Enum.join(slice.capabilities, ", ")}

  Summary: #{slice.summary}
  """

  {system, user, schema}
end

defp commitment_lines([]), do: "none"
defp commitment_lines(cs) do
  Enum.map_join(cs, "; ", &"#{&1.deed} (#{&1.status}, priority #{&1.priority})")
end
```

`Agents.Brain` gains:
```elixir
def handle_call({:deliberate, %{slice: slice, ctx: ctx}}, _from, agent_id) do
  {system, user, schema} = Agents.Prompt.deliberate(slice)

  req = %LLMGateway.Request{class: :deliberate, agent_id: agent_id,
    system: system, user: user, schema: schema}

  reply =
    case LLMGateway.Router.complete(ctx, req) do
      {:ok, %LLMGateway.Result{parsed: %{} = parsed}, audit, ctx2} ->
        case verb_from(parsed["verb"], slice.capabilities) do
          nil ->
            {:hesitate, %{reason: "proposed verb outside capabilities",
                          request: req, ctx: ctx2, audit: audit}}

          verb ->
            {:ok, %{action: action_of(parsed, agent_id, verb), reason: parsed["reason"],
                    request: req, ctx: ctx2, audit: audit}}
        end

      {:ok, _result, audit, ctx2} ->
        {:hesitate, %{reason: "deliberation unavailable", request: req, ctx: ctx2, audit: audit}}

      {:error, _reason, audit, ctx2} ->
        {:hesitate, %{reason: "deliberation unavailable", request: req, ctx: ctx2, audit: audit}}
    end

  {:reply, reply, agent_id}
end

defp verb_from(verb, caps) when is_binary(verb),
  do: Enum.find(caps, &(Atom.to_string(&1) == verb))
defp verb_from(_verb, _caps), do: nil

defp action_of(parsed, agent_id, verb) do
  params =
    %{}
    |> maybe_put(:direction, parsed["direction"])
    |> maybe_put(:message, parsed["message"])

  struct!(EngineCore.Types.Action,
    actor_id: agent_id, verb: verb, target_id: parsed["target_id"], params: params)
end

defp maybe_put(map, _key, nil), do: map
defp maybe_put(map, key, value), do: Map.put(map, key, value)
```

`Agents.deliberate/2`: `ensure_brain(agent_id)`; `whereis`; nil ⇒ `{:error, :brain_unavailable}`; else `try GenServer.call(pid, {:deliberate, msg}, 5000) catch :exit, _ -> {:error, :brain_unavailable} end`.

- [ ] **Step 4:** agents tests green (Task 1 + Task 4 + these 6). Commit `feat(agents): tier-3 brain deliberation - llm-first, schema-bound, hesitation on failure`.

### Task 6: Order adoption — heuristic reliability, LLM adopt class, deception

**Files:**
- Create: `shards_engine/apps/agents/lib/agents/adopt.ex`; Modify: `lib/agents/prompt.ex`, `lib/agents/brain.ex`, `lib/agents.ex`
- Test: `apps/agents/test/adopt_test.exs` (pure heuristic + feasibility), `apps/agents/test/adopt_brain_test.exs` (LLM path + fallback + truth barrier)

**Interfaces:**
- Consumes: `Types.Agent` (debtor statblock), envelope-shaped maps, `Router`, `Scripted`, `EngineCore.Loader` (tests build worlds).
- Produces: `Agents.Adopt.feasible?/2`, `reliability/2`, `decide/2`; `Agents.Prompt.adopt/2`; `Agents.adopt/2` (Shared Interfaces — Task 8 consumes).

- [ ] **Step 1 (failing tests, pure):** tower-YAML world via Loader:
  1. `Adopt.feasible?` is true for an order from `grisk_the_snatcher` to `goblin_bodyguard_1` (co-present, awake); false when the debtor's body has `:fleeing`; false when the creditor is in another place and not believed at the debtor's place.
  2. `Adopt.reliability`: goblin guard statblock (morale 8, int 10) + feasible ⇒ `11`; int 13 ⇒ `13` (+2); int 6 ⇒ `9` (−2); infeasible ⇒ `8 − 4 = 4`-shaped (morale + adj − 4).
  3. `Adopt.decide(11, 11) == :adopt`; `Adopt.decide(12, 11) == :reject`.
- [ ] **Step 2 (failing tests, brain):** envelope map `%{id: "env-0-1", from: "grisk_the_snatcher", to: "goblin_bodyguard_1", type: :order, payload_nl: "Kill the intruder!", sent_tick: 3, delivery_place: "chiefs_room", signal_ref: 1, truth: :unverified, adopted: nil, status: :delivered}`; slice = bodyguard slice with a grisk belief:
  1. Scripted `{"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of Grisk"}` → `{:ok, %{adopted: true, deed: "slay the intruder", deceive: false, inform: nil, reason: "fear of Grisk"}}` with `request.class == :adopt`, audit ok.
  2. Scripted `{"adopted":false,"deceive":true,"inform":"Done, boss.","reason":"too scared"}` → `adopted: false, deceive: true, inform: "Done, boss."`.
  3. Empty scripts + `roll: 5, feasible: true, debtor: guard` → heuristic adopt: `adopted: true`, `deed` = envelope `payload_nl`, `deceive: false`, `inform: nil`, audit `parse_verdict: :fallback, ok: true`.
  4. Empty scripts + `roll: 20` → `adopted: false` (heuristic reject, fallback audit).
  5. Truth barrier: `request.user` contains the order text and debtor identity; the prompt never contains a serialized `truth:` field of the envelope (prompt builder receives the envelope stripped to `[:id, :from, :to, :type, :payload_nl, :sent_tick]`).
- [ ] **Step 3 (implement):**

```elixir
defmodule Agents.Adopt do
  @moduledoc """
  Order adoption mechanics (spec 5.6, decision 30): a subordinate adopts an
  order into its own commitment only through its own decision. LLM-first at
  the brain; this module is the deterministic fallback — a reliability target
  from morale, INT, and engine-computed feasibility, against a d20 the
  coordinator rolled and ledgered.
  """
  alias EngineCore.{Types, World}

  @spec feasible?(World.t(), map()) :: boolean()
  def feasible?(world, env) do
    debtor = World.agent(world, env.to)
    creditor = World.agent(world, env.from)

    alive?(debtor) and :fleeing not in (debtor.body.conditions || []) and
      creditor_near?(world, debtor, creditor)
  end

  defp creditor_near?(_world, _debtor, nil), do: true

  defp creditor_near?(world, debtor, creditor) do
    creditor.place_id == debtor.place_id or
      get_in(debtor.beliefs, [debtor.place_id, creditor.id]) != nil or
      get_in(debtor.beliefs, [creditor.place_id, creditor.id]) != nil
  end

  defp alive?(nil), do: false
  defp alive?(a), do: a.body.hp > 0 and :dead not in (a.body.conditions || [])

  @spec reliability(Types.Agent.t(), boolean()) :: integer()
  def reliability(debtor, feasible) do
    int = debtor.statblock.int

    debtor.statblock.morale + int_adjust(int) + (if feasible, do: 3, else: -4)
  end

  defp int_adjust(int) when int >= 12, do: 2
  defp int_adjust(int) when int <= 7, do: -2
  defp int_adjust(_), do: 0

  @spec decide(integer(), integer()) :: :adopt | :reject
  def decide(roll, target), do: if(roll <= target, do: :adopt, else: :reject)
end
```

`Prompt.adopt(slice, envelope)`: envelope stripped via `Map.take(envelope, [:id, :from, :to, :type, :payload_nl, :sent_tick])`; system prompt: "You are {slice.agent.name}. {from} has ordered you: \"{payload_nl}\". Weigh your morale, fear, intelligence, loyalty, and whether you can do it. Respond ONLY with JSON: {\"adopted\": boolean, \"deed\": string, \"deceive\": boolean, \"inform\": string | null, \"reason\": string}. deceive=true means you will NOT do it but will claim it is done — inform is the lie you tell." user: envelope lines, commitments, salient/believed, summary LAST. Schema per Shared Interfaces (`required: [:adopted, :reason]`, `inform` nullable).

`Brain.handle_call({:adopt, msg})`: LLM-first exactly like deliberate; on failure ⇒ heuristic: `target = Adopt.reliability(msg.debtor, msg.feasible)`; `decision = Adopt.decide(msg.roll, target)`; reply `{:ok, %{adopted: decision == :adopt, deed: msg.envelope.payload_nl, deceive: false, inform: nil, reason: "heuristic fallback: roll #{msg.roll} vs target #{target}", request: req, ctx: ctx2, audit: fallback_audit(audit)}}` where `fallback_audit(nil)` builds `%Audit{class: :adopt, adapter: :heuristic, parse_verdict: :fallback, ok: true}` and `fallback_audit(a)` mirrors Interpret's. `Agents.adopt/2` wrapper with the same exit-catch as deliberate.

- [ ] **Step 4:** agents tests green. Commit `feat(agents): autonomous order adoption - reliability heuristic, llm adopt class, deception`.

### Task 7: `:order` verb in the referee pipeline

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/loader.ex` (`caps(3)` gains `:order`); `shards_engine/apps/referee/lib/referee/validate.ex`, `resolve.ex`
- Test: `apps/engine_core/test/loader_test.exs` (assertion), `apps/referee/test/validate_test.exs`, `apps/referee/test/resolve_test.exs`

**Interfaces:**
- Consumes: `Envelopes.send/5` (Task 3), existing belief/capability gates.
- Produces: `:order` as a validated + resolved verb — Task 5's deliberate enum lists it via capabilities; Task 8's grisk script uses it.

- [ ] **Step 1 (failing tests):**
  - validate: `:order` with nil target ⇒ `{:reject, _}`; targeting an agent the actor believes present ⇒ `:ok`; targeting an unbelieved id ⇒ diegetic reject; `:order` by an actor whose capabilities lack it ⇒ capability reject.
  - resolve: on the tower world, `Resolve.act(world, rng, %Action{actor_id: "grisk_the_snatcher", verb: :order, target_id: "goblin_bodyguard_1", params: %{message: "Kill them!"}})` → `{:ok, [sig_ev, env_ev], _w2, rng}` with envelope `type: :order`, `truth: true`, `signal_ref == sig_ev.payload.ref`; rng returned unchanged.
  - loader: goblin chief capabilities include `:order`; a rat's do not.
- [ ] **Step 2:** Run engine_core + referee — new tests fail.
- [ ] **Step 3 (implement):** `caps(3)` → `[:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee, :order]`. Validate: add to the cond — `verb == :order -> check_order(actor, action)` mirroring `check_strike` but first rejecting nil target with "You have no one to order." Resolve: `:order -> act_order(world, rng, action)`:

```elixir
defp act_order(world, rng, %Types.Action{actor_id: actor_id, target_id: target_id, params: params}) do
  {:ok, events, w2} =
    EngineCore.Envelopes.send(world, actor_id, target_id, :order,
      Map.get(params, :message, ""), truth: true)

  {:ok, events, w2, rng}
end
```

- [ ] **Step 4:** engine_core + referee green. Commit `feat(referee): :order verb - validation and envelope resolution for tier-3 commanders`.

### Task 8: `Run.advance` — delivery, adoption, deliberation phases

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run.ex`
- Test: `apps/referee/test/brains_run_test.exs`

**Interfaces:**
- Consumes: `Envelopes.deliver_due/2`, `Agents.deliberate/2`, `Agents.adopt/2`, `Agents.Salience.escalate?/2`, `Agents.Adopt.feasible?/2`, `Commitments.create/2`, `Slice.for_actor/2`, `Validate`, `Resolve`, `Scheduler.react/3`, `Dice.roll/2`.
- Produces: the phase-6 engine loop (`advance/1` signature unchanged); ledger rows per Shared Interfaces.

- [ ] **Step 1 (failing tests, scripted full chain over the tower YAML):** one PC `pc_thistle` at `entry_hall`; routing for interpret/narrate/deliberate/adopt → Scripted with a salted scripts map. Scripts: interpret — `{"verb":"move","target_id":null,"params":{"direction":"east"}}` then `{"verb":"move","params":{"direction":"south"}}`; deliberate agent-keyed — grisk `{"verb":"order","target_id":"goblin_bodyguard_1","message":"Kill the intruder!","reason":"intruders in my hall"}`, bodyguard_1 `{"verb":"strike","target_id":"pc_thistle","reason":"obeying orders"}`; adopt — `{"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"}`.

```elixir
defp advance_until(run, pred, n) do
  Enum.reduce_while(1..n, {run, %{}}, fn i, {acc, texts} ->
    {:ok, t, acc2} = Run.advance(acc)
    texts = Map.merge(texts, t)
    if pred.(acc2, texts), do: {:halt, {acc2, texts}}, else: {:cont, {acc2, texts}}
  end)
end
```

  1. Declare `go east` then `go south` (PC ends in `chiefs_room`); advancing ≤ 15 ticks yields a `:deliberation` row `%{agent_id: "grisk_the_snatcher", decision: :proposed, verb: :order}` and an `:envelope_sent` envelope with `to: "goblin_bodyguard_1"`, `type: :order`.
  2. Continuing ≤ 3 more advances yields, in order: `:envelope_delivered` (that envelope), a `:dice` row `%{purpose: :adoption, sides: 20}`, `:envelope_adopted`, and `:commitment_created` with `id == "adopted:#{env.id}"`, `debtor: "goblin_bodyguard_1"`, `creditor: "grisk_the_snatcher"` — and the bodyguard's folded `world.agent.commitments` contains it.
  3. Continuing ≤ 12 more advances yields bodyguard_1's `:deliberation` `%{decision: :proposed, verb: :strike}` followed by a `:damage` event with `target_id: "pc_thistle"`, and at least one `advance` returned a non-empty narration for `pc_thistle`.
  4. Gate invariant: for EVERY `%{kind: :cadence_tick}` event of a living tier-3 agent, the ledger contains a `:deliberation` row for that agent at that tick with decision ∈ `[:proposed, :hesitated, :rejected, :skipped]`; and agents whose gate is closed (no pending/due commitment, no belief ≥ 7.0 at their place at fold time — construct from the world fold at that tick) have `decision: :skipped` with no `:llm` audit row between that cadence tick and the next cadence tick of the same agent (skipped ticks spend nothing).
  5. Hesitation: same setup but deliberate queue has NO grisk entry → his first deliberation row is `decision: :hesitated`; subsequent `Run.declare` still works (run survives brain failure).
  6. Deception: adopt script `{"adopted":false,"deceive":true,"inform":"Done, boss.","reason":"cowardice"}` → after adoption, ledger has `:envelope_rejected` AND a second `:envelope_sent` with `type: :inform`, `truth: false`; after ≤ 3 more advances `:envelope_delivered` for it and grisk's folded beliefs include `"inform:..."` at `chiefs_room`. Truth barrier, concretely: `llm_rows = Enum.filter(events, &(&1.class == :llm))`; `refute Enum.any?(llm_rows, &is_map_key(&1.payload, :truth))`; and (agents-side, covered in Task 6) the adopt `request.user` contains the order text but not a serialized `truth:` field.

- [ ] **Step 2:** Run — fail (no phases in `advance`).
- [ ] **Step 3 (implement):** restructure `advance/1`:

```elixir
def advance(run) do
  seq0 = run.seq

  {:ok, events, w2, r2} = Scheduler.advance(run.world, run.rng)
  {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, events)

  run =
    run
    |> Map.put(:world, w3)
    |> Map.put(:rng, r3)
    |> append_world(events ++ reaction)

  run = deliver_phase(run)
  run = adoption_phase(run)
  run = deliberation_phase(run, events)

  narrate_new_receipts(run, seq0)
end
```

  - `adoption_phase(run, delivered)`: for each delivered order envelope (sorted by id): `{roll, rng2} = Dice.roll(run.rng, 20)`; `feasible = Agents.Adopt.feasible?(run.world, env)`; `slice = Slice.for_actor(run.world, env.to)`; `debtor = World.agent(run.world, env.to)`; `Agents.adopt(env.to, %{envelope: Map.from_struct(env), slice: slice, ctx: run.ctx, roll: roll, feasible: feasible, debtor: debtor})` → then push ONE dice row after the brain replies, carrying all keys at once: `%{purpose: :adoption, sides: 20, roll: roll, target: Agents.Adopt.reliability(debtor, feasible), adopted: <bool from decision>}` (class `:dice`, no `:kind` — dice convention):
    - `{:ok, d}`: adopted ⇒ `{:ok, [c_ev], _w} = Commitments.create(run.world, %{id: "adopted:#{env.id}", debtor: env.to, creditor: env.from, deed: d.deed, priority: 5})` + `envelope_adopted` event; fold + append + `append_audit(d.audit)` + ctx from `d.ctx`; rejected ⇒ `envelope_rejected` event; when `d.deceive and d.inform` also `Envelopes.send(run.world, env.to, env.from, :inform, d.inform, truth: false)` (fold + append + react).
    - `{:error, :brain_unavailable}`: `envelope_rejected` event; `push(:deliberation, %{agent_id: env.to, decision: :rejected, verb: nil, reason: "brain unavailable"})`.
    - After each envelope: `Scheduler.react(world, rng, new_events)` folded/appended (voice signals from deception informs).
  - `deliberation_phase(run, scheduler_events)`: `ticks = Enum.filter(scheduler_events, &(&1.payload[:kind] == :cadence_tick))` (already agent-id sorted). For each: `agent = World.agent(run.world, ev.payload.agent_id)`; skip if nil or tier != 3 or dead; unless `Agents.Salience.escalate?(agent, tick)` ⇒ `push(:deliberation, %{agent_id:, decision: :skipped, verb: nil, reason: "salience below threshold"})`; else `slice = Slice.for_actor`; `Agents.deliberate(agent.id, %{slice: slice, ctx: run.ctx})`:
    - `{:ok, d}` ⇒ `apply_action(run, d.action)` → on `:ok` push `%{decision: :proposed, verb: d.action.verb, reason: d.reason}`; on `{:reject, reason}` push `%{decision: :rejected, verb: d.action.verb, reason: reason}`; `append_audit(d.audit)`; ctx from `d.ctx`.
    - `{:hesitate, h}` ⇒ push `%{decision: :hesitated, verb: nil, reason: h.reason}` + audit.
    - `{:error, :brain_unavailable}` ⇒ push `%{decision: :hesitated, verb: nil, reason: "brain unavailable"}`.
    - Deliberation rows carry NO `:kind` key (dice convention — audit-only, no fold).
  - `apply_action(run, action)`: extract the validate→resolve→react→append body from `resolved/4` WITHOUT the narration (narration stays declare-only; PCs perceive NPC actions as signals); return `{:ok, run} | {:reject, reason, run}`.
  - `narrate_new_receipts(run, seq0)`: `new_receipts = events(run) |> Enum.filter(&(&1.seq > seq0 and &1.payload[:kind] == :signal_received))` then the existing per-PC `Narrate.received` reduction unchanged.
  - `resolved/4` (declare path) now calls `apply_action` + `Narrate.action` — behavior byte-identical to before (same event order).

- [ ] **Step 4:** `cd apps/referee && mix test` — all green (58 + new; run_test/golden_test semantics unchanged). Commit `feat(referee): advance orchestrates envelope delivery, adoption, and tier-3 deliberation`.

### Task 9: Golden determinism + CLI smoke

**Files:**
- Create: `shards_engine/apps/referee/test/brains_golden_test.exs`, `shards_engine/scripts/brains_smoke.exs`
- Modify: `shards_engine/automated-run.sh` (add `brains` mode)

**Interfaces:**
- Consumes: the full Plan 4 surface.
- Produces: byte-identical replay proof including brains/envelopes; `./automated-run.sh brains [seed]` printing the order → adoption → strike chain and a spend report with `deliberate`/`adopt` classes.

- [ ] **Step 1 (failing golden test):** two runs from the same YAML + seed + PC spec, each with its own fresh-salt scripts map of IDENTICAL content (interpret moves, agent-keyed deliberate entries for grisk + bodyguard_1, adopt entry), driven identically: declare `go east`, declare `go south`, then `advance` 20×. Assert:
  - `:erlang.term_to_binary(events(run2)) == :erlang.term_to_binary(events(run1))` (byte-identical ledger, brains included) and both final `world.tick` match.
  - Marker rows in BOTH: an `:envelope_sent` order to `goblin_bodyguard_1`, an `:envelope_adopted`, a `:commitment_created` with an `"adopted:"` id, at least one `:deliberation` `%{decision: :proposed}`.
  - A third run with seed `43` yields a different ledger binary (RNG-branch evidence).
- [ ] **Step 2:** `scripts/brains_smoke.exs`: tower YAML + seed arg (default 42) + one PC; the same scripted queues; drive the two declares then 20 advances; print each PC narration as it arrives and, at the end, the phase-marker ledger rows in seq order (envelope/adoption/commitment/deliberation/damage classes), then the `Run.spend_report/1` table. Wire `automated-run.sh` `brains [seed]` mode exactly like the `referee` mode (same `mix run` invocation pattern against `scripts/brains_smoke.exs`).
- [ ] **Step 3:** Full suite green in all four apps (`cd apps/<app> && mix test`). Run `./automated-run.sh brains` from `shards_engine/` and paste the output into the task log. Commit `test: brains golden determinism + cli smoke mode`.

## Plan 4 Acceptance (maps to spec §12.4 phase 6)

1. Tier-3 agents deliberate as supervised OTP actors on `:cadence_tick` events: proposals flow propose → validate → resolve → apply exactly like PC intents; kills/LLM failures degrade to ledgered hesitation, never crash the run.
2. Salience gate suppresses deliberation spend: cadence ticks without pressure (no pending/due commitment, no belief ≥ 7.0 salience) log `:skipped` and make no LLM call.
3. Orders are typed envelopes: `:order` resolves to a voices signal + `:envelope_sent`; delivery only on signal receipt (a shout that is never heard never delivers); adoption is the subordinate's own decision (LLM `adopt` with deterministic reliability-roll fallback) recorded as commitment or rejection — never puppeted.
4. Deception is tracked: a rejecting subordinate may `inform` falsely; the inform envelope carries engine-known `truth: false` that appears in no prompt and no audit row.
5. Truth barrier holds for brain prompts: slice + envelope-only content; no hidden items, no other-place agents, no envelope truth.
6. Determinism: golden test — identical YAML + seed + scripts ⇒ byte-identical ledgers including all `:deliberation`, `:envelope`, adoption dice, and llm rows; different seed diverges.
7. Offline: all four apps green with zero network; spend report now shows `deliberate`/`adopt` classes.

## Next Plans

- **Plan 5** (spec §12.4 phase 7): Phoenix channels (`run:<id>`), per-PC isolation at push, spectate console, terminal WS reference client, PC dossiers (summarize class), OTP supervision tree promotion (World.Server, Ledger.Writer, Run.Session).
- **Plan 6** (spec §12.4 phase 8): scripted end-to-end playthroughs over channels, fork-diff emergence scenarios, spend dashboards, XP/treasure claim consuming `prefs.xp`.
