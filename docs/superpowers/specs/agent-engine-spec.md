# The Shattered Kingdoms Agent Engine — Design Specification

**Codename:** Shards Engine *(placeholder; umbrella app names below are stable)*
**Seed adventure:** The Ruined Tower (`the-ruined-tower/ruined_tower.yaml`)
**Status:** Approved design — all sections reviewed interactively, 2026-08-17/18
**Decision record:** engrams DB, decisions 16–37, patterns 8–14, links 233–256. Every section below cites its decision IDs.

---

## 1. Vision

Every character in an adventure — goblin chieftain, giant rat, imprisoned shepherd, human PC — is an agent with its own beliefs, capabilities, commitments, and cadence, acting on what *it* can perceive rather than world truth. Emergent events per run are the product, not a hope: the same YAML seed must produce different, defensible histories. The engine is AD&D 1E-mechanical, LLM-cognitive, replayable to the dice roll, and observable to the token.

Long-term context (not v1 scope): this engine is the runtime half of a platform — an adventure marketplace plus per-adventure sandboxes with platform-issued LLM keys and metered token upcharge. v1 deliberately builds the seams that vision needs (engine/content split, run isolation, gateway chokepoint, per-call metering) and none of the business logic. [decision 35]

## 2. Locked Design Axes (interview outcomes)

| # | Axis | Decision | engrams |
|---|------|----------|---------|
| 1 | Runtime | Custom Elixir/Phoenix engine; YAML loads as initial state | 17 |
| 2 | Humans | 1 human = 1 PC, individually modeled; client is the PC's intent channel | 16 |
| 3 | Time | Event-driven turns; one game clock; one ordered event log | 18 |
| 4 | Agency | Tiered by cognition: sapients full BCD, animals reflex, hazards decision patterns | 19 |
| 5 | Adjudication | LLM proposes, engine disposes — every actor through one pipeline | 20 |
| 6 | Perception | Room + signal routing; no world truth in any brain | 21 |
| 7 | Agent-to-agent comms | Typed envelope + natural-language payload | 22 |
| 8 | Persistence | YAML reset per run + full run persistence | 23 |
| 9 | Client | Thin terminal client + WS protocol (LiveView immediately post-POC) | 24, 37 |
| 10 | Off-screen sim | Trigger-activated zones (boundaries), not global simulation | 25 |
| 11 | LLM economics | Tiered routing by call class; every call ledgered | 26 |
| 12 | v1 acceptance | Emergence demonstrable + full playthrough | 27 |
| 13 | Stack | Elixir/Phoenix, BEAM process per deliberating brain | 28, 29 |

Refinements: agent-defined boundaries at arbitrary granularity [25]; autonomous order adoption — no hive puppeting [30]; raw signal metadata surfaced to players at per-PC fidelity (INT, race, skills) [31]; referee ambiguity policy [32]; referee preference stack [33]; memory isolation per run in v1, cross-run learning is a v2 BHAG [34]; config-only LLM vendors, no default [36].

## 3. Architecture (selected: "C — Ledger-centric actors")

Authority lives in **one append-only event ledger**; the current world state is a deterministic fold of it. Deliberating brains are supervised OTP actors that *read* a slice and *propose*; a single-writer referee path *validates and applies*. LLM outputs are proposals everywhere, never events. Every LLM call is a supervised, budgeted, ledgered operation through one gateway.

Rejected alternatives: A (BEAM-native, state-in-processes — replay/determinism painful), B (pure reducer simulation — loses fault isolation and per-brain supervision). C keeps "every character is a killable, restartable process" *and* byte-exact replay.

## 4. World Model & Spatial Activation

### 4.1 Places and edges
Places are typed bounded containers (region → zone → town/building/dungeon → room; the tower's 7 rooms are leaves). Edges connect places and carry propagation facts: permeability per signal kind (sound passes a curtain, sight doesn't), attenuation, traversal cost, sealed/unsealed state. A closed iron door is a sealed edge for sight/sound until opened.

### 4.2 Boundaries are first-class and agent-defined [25]
Every bounded place declares its own activation triggers, and **agents/groups declare their own boundaries at whatever granularity fits them** — one rat pack scoped to a city, another to a single building. A boundary is an object: `{id, scope: place_ref or custom geometry, bound_agent_ids, triggers}`.

### 4.3 Activation and dormancy
A boundary is **dormant** until a trigger fires. Triggers: `presence_crossing` (any agent of interest enters/exits), `signal_arrived` (loud signal crosses the boundary), `commitment_due` (a bound agent owes action), `coarse_tick` (dawn/dusk/calendar — **reserved for place boundaries only**; custom agent boundaries may use only the first three). On wake, bound agents begin their cadences; on sustained quiet, boundary sleeps. **Lazy catch-up:** on wake, the world computes "what plausibly moved while dormant" once, from the ledger, and writes the results back as derived events with provenance (`computed at wake, tick 340`). Dormant ≠ nonexistent: reflex agents keep listening for their triggers even while their boundary sleeps (the boundary decides where their triggers listen).

## 5. Agents

### 5.1 One anatomy, four cognition tiers [19]
```
Agent {
  id, name, tier, spawn_place,
  statblock,        # from YAML: AC, HD, hp, thac0, saves, morale, INT
  body,             # hp, conditions (fear, webbed, poisoned)
  beliefs,          # per-agent: what it thinks is where/who
  capabilities,     # verbs available to its tier
  commitments,      # outstanding obligations (self- or order-imposed)
  cadence,          # deliberation frequency + interrupt sensitivity
  dossier,          # (PCs and named NPCs) accumulated models of others
}
```
- **Tier 3 — sapients** (Grisk, the goblin sub-chiefs, Willem, PCs): full Beliefs–Commitments–Decisions loop, OTP process each, LLM deliberation.
- **Tier 2 — pack animals** (wolves, rats as packs): shared mental state per pack, reactive drives (hunger, territory, fear), heuristic decision function. No process of their own — pure rules over world state.
- **Tier 1 — vermin/reflex** (individual rats): stimulus→action tables. Signal in, action out.
- **Tier 0 — hazards** (the Shadow-Touched Skeleton, traps): decision patterns keyed on trigger conditions. The skeleton is a hazard with a *pattern*, not a brain.

### 5.2 Beliefs
Each agent's world model: per-place entity beliefs with recency/confidence; heard-but-unseen entries; false beliefs persist until corrected by perception. Beliefs are the *only* view of the world any brain ever gets. Bounded: recent-N + salient-M entries, compressed by the `summarize` LLM class.

### 5.3 Salience and cadence
Not everything perceived merits deliberation. Salience scores (novelty, proximity, threat, goal-relevance) gate what enters belief updates and whether a cadence tick escalates to full deliberation. Cadences: Grisk checks his commitments every ~10 ticks or on interrupt; a bored sentry's cadence lengthens when nothing salient happens. Unobserved sapients at long cadence cost near nothing.

### 5.4 Commitments
Structured obligations: `{id, debtor, creditor, deed, due, priority, status}` with statuses `pending/due/kept/violated/renegotiated`. Sources: self-imposed plans, orders from superiors, accepted requests. **An LLM saying "I will" is not a commitment until the engine records it.** Violation is an event the agent's own morale/relationship machinery sees — commitment drift becomes observable and testable. Commitments drive scheduling: `due` fires wake-ups.

### 5.5 Capabilities as verbs
Tier-gated verb sets (move, strike, guard, shout, hide, parley, obey, flee…). Reflex tiers emit verbs directly; tier-3 brains propose them. The referee validates against the *same* verb table for every actor — rats can't parley, PCs can't bite (usually).

### 5.6 Orders and autonomous adoption [30]
When Grisk barks an order, the subordinate's `adopt` decision (mid-weight LLM class) weighs reliability: morale, fear, INT, relationship, perceived feasibility. Adoption → commitment created; rejection → logged envelope event, possibly with deception (`inform` the boss it's done — a lie the engine can track as a false belief in Grisk's store). No hive puppeting: the warband's behavior under stress is emergent from each goblin's own adoption decisions. This is where per-run emergent events come from.

## 6. Perception & Communication

### 6.1 Signals
Nothing enters a belief store except via a **signal**: `{emitted_by, place, tick, kind: sight|sound|smell|tremor, content_core, content_nl, intensity, fidelity}`. Traps are signal broadcasters (tripwires are goblin communication infrastructure). Signal propagation: emitted into a place, routed along edges by permeability/attenuation with per-edge arrival ticks — sound arrives later down a long corridor. Reception: per-agent filters (senses, INT-derived acuity, attention state). **Uniform physics**: PCs receive signals through the identical filter machinery as NPCs.

### 6.2 Per-PC fidelity [31]
What a human client sees is their PC's perception rendered at that PC's fidelity: raw signal metadata emerges ("you hear something metallic, north, faint" — direction ±90°/±45°/exact by INT, detail level, false negatives on low rolls). Depends on INT, race (elf secret-door sensitivity, dwarf stonework, gnome/halfling hearing — per AD&D 1E racial traits), and any skill/trait affecting awareness. The structured core stays engine-side; players get fidelity-limited renderings — including honest omissions and direction errors.

### 6.3 Envelopes [22]
Agent-to-agent messages: typed envelopes, natural-language payload:
```
Envelope { from, to, type: order|inform|request|plead|warn,
           payload_nl, sent_tick, delivery_place,
           truth: true|false|unverified,   # engine-known, never leaked
           adopted: bool|nil }
```
Deception is emergent: a terrified guard's `inform` can be wrong; Grisk's `adopt`-class reasoning decides whether to believe him. The engine tracks ground truth of payload accuracy without exposing it to any brain.

### 6.4 Referee-derived side-effect signals
Applied actions emit signals: melee is loud, torches are visible, broken glass smells. The bridge from actions back into the perception economy (§7 stage 4).

## 7. The Referee: Propose → Validate → Resolve → Apply → Narrate [20]

```
Intent ──▶ 1 INTERPRET ──▶ 2 VALIDATE ──▶ 3 RESOLVE ──▶ 4 APPLY ──▶ 5 NARRATE
          (LLM, heavy)    (pure Elixir)  (dice, pure)  (reducer)  (LLM, light)
```

**1 Interpret** (only NL-touching stage): PC NL → normalized `Action{verb, target, manner, params}`; agent brains emit typed proposals directly. Ambiguity policy [32]: clarifying question only on *lethal* ambiguity (which vial? who is shielded?); otherwise most-plausible parse with the assumption narrated in the result.

**2 Validate** (pure, total): capability (verb ∈ tier set) · plausibility-vs-beliefs with diegetic failure (acting on a false belief fails *in the fiction*, correcting the belief — never leaks truth through rejections) · resources (movement, ammo, components, encumbrance) · preconditions (door state, engagement, surprise). Rejections return to the proposer as perception; retry budget 3/tick, then the tick passes — itself narratable.

**3 Resolve** (the only place dice exist): 1E to-hit/saves/surprise (d6)/initiative (d6+Dex)/segment ordering for missile & spell/casting times; morale checks (leader down, 50% losses). House conventions active by default from the module: trap-detection procedure, 1gp=1XP valuation, creative-action adjudication with logged rationale. Seeded RNG per run; every roll ledgered with seed.

**4 Apply** (single-writer reducer): emits ledger events and side-effect signals; serialized through one World process, one transaction per action.

**5 Narrate** (light LLM, constrained): renders each perceiving PC's signal subset at their fidelity tier; the model chooses words, never facts. Same renderer feeds NPC belief stores.

**Truth barrier**: referee prompts contain actor-visible slice only (belief store + place-local truth). `is_hidden` stays hidden until a find/search resolution flips it. Which slice entered every call is ledgered (oracle-leak audit).

### 7.1 Time lives here
One monotonic clock in **segments** (6s); round = 10 segments, turn = 10 min, watch = 4h. Combat mode: segment-ordered resolution, engages automatically on confirmed mutual hostility. Exploration mode: event-driven jumps to next scheduled item (PC declaration, commitment due, signal arrival, cadence tick). Mode transitions are ledgered `meta` events. Grisk's relocation deadline ticks in round-time during combat and turn-time during exploration — the pressure the adventure wants.

## 8. Referee Preference Stack [33]

```
core 1E rules  ⊂  module preferences  ⊂  referee personal YAML
 (engine)         (ships with adventure)   (the human referee's)
```

- **Module layer** (`preferences:` block or sibling `referee_defaults.yaml`): XP award policy (Ruined Tower ships 1gp=1XP + creative-action bonus), tone, lethality, active house conventions, narration style, `dice_visibility`.
- **Personal layer**: human referee overrides any module key.
- Resolution: highest-defined wins per key; unknown keys warn and drop; resolved stack hashed into the run's ledger at start so replays adjudicate identically. The referee *roles* are fixed; the stack modulates Resolve judgments and Narrate voice.

## 9. Ledger, Persistence, Replay

### 9.1 Event classes
`world` (applied actions) · `signal` (emission, propagation, reception) · `envelope` (send/deliver/adopt/reject) · `commitment` (create/due/keep/violate/renegotiate) · `deliberation` (agent decision summaries — audit trail for emergence) · `dice` (roll+seed+result) · `llm` (agent, role, model, prompt-slice ref, latency, cost, parse verdict) · `meta` (mode, snapshots, boundary wake/sleep). **World state = fold(ledger); snapshots are cached folds, never truth.**

### 9.2 Runs
`ruined_tower.yaml` is the immutable seed; loading instantiates places/edges/agents/items/boundaries/initial commitments; it never mutates mid-run. A run = `runs/<run-id>/` (ledger, snapshot, RNG position, per-PC dossiers). Pause = stop; resume = snapshot + replay tail. New run = fresh YAML load — infinite replayability is structural.

### 9.3 Replay and the emergence lab
Verbatim replay reconstructs byte-identically from recorded LLM outputs. Resimulated replay re-calls deliberation only (temperature pinned per role); dice replay verbatim. **Fork-diff**: `fork(run_id, tick)` = copy prefix + new RNG branch; ledger diff shows exactly where runs branch — the documented emergent event, with receipts; doubles as the test harness ("does the warband ever parley?").

### 9.4 Memory isolation [34]
Session memory is unique per play. No feedback loop from runs into world/campaign/adventure design in v1. Chronicle export on run completion is a GM artifact, never engine input. Cross-run learning that shapes design is a v2 BHAG.

## 10. LLM Orchestration & Routing [26, 36]

| Class | Fires when | Weight |
|---|---|---|
| `deliberate` | tier-3 cadence tick / interrupt wake | heavy |
| `interpret` | PC NL → action graph | heavy |
| `narrate` | PC-perceivable signals at fidelity | light |
| `summarize` | belief compression, dossiers, chronicle | light |
| `adopt` | order-envelope adoption | mid |

Routing is config: `class → {model, endpoint, key_ref, temperature, max_tokens, budget}`; OpenAI-compatible + Anthropic adapters; **no default vendor in v1** (no platform yet — keys are deployment config). Prompt discipline: truth barrier at slice-build; fixed schema; identity/commitments/salient signals head, state summary last (*Lost in the Middle*); JSON-schema-constrained output; one bounded retry then failure semantics. Failure semantics: `deliberate` → diegetic no-op hesitation; `interpret` → clarify (PC) / conservative default (NPC); `narrate` → template fallback; budget exhaustion → cadence degradation, logged. Brains are disposable actors — kill/restart = hesitation [pattern: brains-hold-no-authority-state].

**Gateway chokepoint [pattern 14]**: all LLM traffic flows through `LLM.Router`; adapters callable only from inside the gateway module. Platform metering (decision 35) depends on the `llm` event stream being lossless; any bypass path is silent revenue loss.

Cost envelope: worst-case combat round with warband fully active ≈ 12–15 calls (3 heavy); exploration turn in one active room ≈ 2–4 light + 1 heavy. Suppressors: salience gate, dormancy, bounded beliefs. Configurable session spend cap with degradation order narrate → deliberate → interpret.

## 11. Protocol & Clients [24, 37]

One WS surface (Phoenix Channels), `run:<run_id>`, one claimed character per connection. Client is untrusted and holds zero authority — every input re-enters the referee pipeline.

Server→client: `perception` (fidelity-tiered narration — the only world window) · `state_sync` (own body/sheet/inventory + *believed* surroundings) · `prompt` (referee clarification / initiative slot) · `dice` (visibility per preference stack, module default open).
Client→server: `declare_intent` (NL) · `answer` · `ooc` (to referee agent) · `sheet` (ready item, torch, marching-order proposal).
Never sent: world truth, hidden items, other rooms, monster stats (only perceivable state), other PCs' prompts, preference internals. Per-PC isolation enforced at channel push.
GM `spectate` channel: ledger tail, spend dashboard, boundary state, pause/resume — observability only.

**Reference client: terminal first**; scripted test players drive the same protocol for headless testing. **LiveView web client is the first post-POC-validation work item** — same channels, no protocol change.

## 12. Topology, Determinism, Build Order

### 12.1 Supervision tree
```
Engine.App
├── Ledger.Writer        # single append writer; :ets read replicas
├── World.Server         # authoritative fold; one apply-transaction at a time
├── Scheduler            # clock, modes, cadence ticks, commitment due-fires,
│                        #   signal propagation, boundary wake/sleep
├── Boundary.Sup         # one Boundary.Server per bounded place/group
├── Agents.DynamicSup    # one process per TIER-3 brain (kill/restart = hesitation)
│                        #   tiers 0–2: pure rules over World state — no process
├── Referee.Sup          # interpret/narrate task supervisors, preference stack
├── LLM.Router           # routing table, budgets, circuit breakers, telemetry
└── Endpoint (Phoenix)   # channels, session registry, spectate console
```

### 12.2 Umbrella layout
`engine_core` (ledger, fold, scheduler, rules — **zero LLM deps, deterministic, CI-testable offline**) · `agents` (brains, prompts, salience) · `referee` (pipeline, preferences) · `llm_gateway` (router + adapters, chokepoint) · `dungeon` (tower module: YAML load, signal/edge defs, module preferences, scenarios) · `client_tui` / `client_web`. The tower is content, proving the engine/content split.

### 12.3 Determinism contract (test-enforced)
`fold(ledger) == snapshot` at every snapshot point · no signal crosses a sealed edge · no prompt contains non-local truth (slice-builder property tests) · dice only from seeded stream · capability gates hold on every proposal · fork-diff: resimulated runs diverge only at `deliberation`/`interpret` events.

### 12.4 v1 build order (each phase headless before the next)
1. `engine_core`: YAML → world, ledger, fold — CLI smoke
2. Rules: movement, combat rounds, dice, morale, saves — scripted party vs. goblins, golden-ledger tests
3. Signals: emission, edge attenuation, reception filters, template narration at fidelity tiers
4. Scheduler: cadences, commitments, boundary wake/sleep, lazy catch-up
5. `llm_gateway` + referee stages (interpret/narrate live; templates swap out)
6. Brains: deliberation + salience gate; envelopes, order adoption, reliability
7. Phoenix channels + terminal reference client; PC dossiers; spectate console
8. Acceptance harness: scripted end-to-end playthroughs, fork-diff emergence scenarios, spend report

## 13. v1 Acceptance Criteria [27]

1. **Full playthrough**: 4 connected human PCs complete the adventure arc (or TPK — both are completions) from YAML reset via the terminal client, across ≥2 real sessions with pause/resume.
2. **Emergence, with receipts**: at least one documented emergent event (behavior not scripted in the YAML — e.g., goblin parley, subordinate deception, alarm cascade, wolf-pack flanking) reproduced via fork-diff from ledger evidence.
3. **Replay determinism**: verbatim replay of any run reconstructs byte-identically; resimulated replay diverges only at deliberation/interpret events.
4. **Truth barrier holds**: property tests + a full-run audit show no prompt received non-local truth.
5. **Cost observability**: per-class, per-agent spend report for a full run; session cap degrades gracefully in the documented order.
6. **Reset reproducibility**: two fresh runs from the same YAML produce materially different histories (the replayability claim, evidenced).

## 14. Out of Scope (v1) — platform seams only [35]

Auth, payments, key issuance/revocation, quotas, storefront, module signing/curation, multi-tenant hosting. The seams v1 provides: adventure-as-packageable-module (engine/content split), run sandbox isolation, config-keyed LLM routing, lossless per-call metering through the gateway chokepoint. Cross-run campaign memory: v2 BHAG [34].

## 15. Anchors

- AD&D 1E core procedures (segment/round/turn structure, morale, surprise/initiative d6)
- Campaign house rules: trap-detection procedure, 1gp=1XP, creative-action rewards (module preferences)
- Research basis (user-provided): BDI/LLM hybrid agents; commitment-driven coordination (AOP); envelope-based agent communication; *Lost in the Middle* context shaping; tiered-cognition cost control; replayable seeded simulation
- Engrams: decisions 16–37; patterns 8–14 (`llm-proposes-engine-disposes`, `brains-hold-no-authority-state`, `append-only-ledger`, `effects-via-referee-pipeline`, `activation-gated-deliberation`, `commitments-in-ledger`, `llm-gateway-single-chokepoint`), links 233–256
