# Agent Engine — Plan 5: Phoenix Protocol, Live Sessions, Dossiers & Spectate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement plan task-by-task. Steps use checkbox (`- [ ]`) syntax tracking.

**Goal:** Spec §12.4 phase 7 — promote the pure engine to supervised live runs (`Ledger.Writer`, `World.Server`, `Referee.Run.Session` per spec §12.1), expose the WS protocol surface over Phoenix Channels (spec §11: per-PC `run:<run_id>` channel + GM `spectate:<run_id>` channel), PC dossiers via the `:summarize` LLM class, and a terminal reference client. Ends with a determinism proof: the same scripted scenario driven through the live WS path produces a byte-identical ledger to the pure `Referee.Run` path, and pause/resume (including process restart) changes nothing but `:dossier` events.

**Scope split (deliberate):** Plan 6 (acceptance harness, fork-diff emergence scenarios, full-playthrough report) NOT in plan. Auth/multi-tenant/spectate keys remain out (spec §14). No LiveView web client — channels + TUI only (decision 37).

**Architecture:** `Referee.Run` stays the pure pipeline (golden tests keep calling it directly). New process topology per run:

- `EngineCore.Ledger.Writer` — the single append writer for one run (spec §12.1): validates seq continuity, writes an optional disk journal, mirrors into one public ETS read-replica table (`engine_core_ledger`), and notifies subscribers (`{:ledger_events, run_id, events}`) in append order. Append-only, never rewritten (pattern 10).
- `EngineCore.World.Server` — the authoritative fold for one run: subscribes to the Writer, folds every tail through pure `Fold`, serves cheap `snapshot/1` + `boundaries/1` reads. Client reads never queue behind LLM deliberation — that is *why* it is separate from the Session. `fold(writer_events) == snapshot` is test-enforced (spec §12.3).
- `Referee.Run.Session` — GenServer owning the `Run` struct (world/rng/ctx included) — the only process that executes pipeline steps (`declare`, `advance`). After each step it drains new events to `Writer.append`, which fans out to `World.Server` + channels. When `data_dir` is set, checkpoints `term_to_binary(run)` after every step (decision 28: cheap state snapshots) and pauses build PC dossiers (`:summarize`) ledgered as `:dossier` events.
- `apps/protocol` (new) — Phoenix Endpoint (Bandit, channels-only, `server: false` by default), `Protocol.Socket` (connect params carry `run_id` + `character_id` or `role: "spectate"`), `RunChannel` (one claimed character per connection via `Protocol.Claims` registry; pushes only slice-visible data — truth barrier at channel push, spec §11), `SpectateChannel` (ledger tail, spend dashboard, boundary state, pause/resume — observability only).
- `apps/client_tui` (new) — thin terminal reference client: WebSockex + a ~100-line Phoenix-Channels line-JSON codec (decision 24: protocol is the public contract, documented in `apps/protocol/PROTOCOL.md`).

**Narrations enter the ledger (contract change):** today `declare/advance` return narration texts to the caller without ledgering them; verbatim replay therefore cannot reconstruct what PCs were told. Plan 5 pushes `:narration` events (`%{kind: :narration, agent_id, text}`) and `:clarify` events (`%{kind: :clarify, agent_id, question}`) inside `Referee.Run`; the returned texts map is derived from those events. Existing golden tests assert determinism by running twice in-process (no stored fixtures), so they absorb the new event kinds without regeneration.

**Tech Stack:** Elixir 1.17 / OTP 27, Phoenix 1.8 (channels + PubSub only), Bandit, Websockex, ExUnit.

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` §11 (protocol), §12.1 (supervision), §12.3 (determinism), §12.4 phase 7; §10 (`summarize` class).

**Engrams (settled — do not re-litigate):** 17 (custom Elixir/Phoenix codebase), 23 (save = flush log, load = replay), 24 + 37 (thin terminal client, line-JSON WS protocol, protocol doc is the contract), 28 (BEAM, brain fault isolation, cheap state snapshots), 34 (session memory isolated, no cross-run feedback). Patterns: 9 (`brains-hold-no-authority-state`), 10 (`append-only-ledger`), 11 (`effects-via-referee-pipeline`), 14 (`llm-gateway-single-chokepoint`).

## Context & Constraints

- Pure path unchanged in behavior: `Referee.Run.new/declare/advance` signatures and semantics stay; only new event kinds are added inside. Every existing test stays green (kind-level assertions unaffected; narration events are additive).
- All LLM traffic still flows through `LLMGateway.Router` (pattern 14). `Dossier` uses class `:summarize`, scriptable via `Scripted` exactly like other classes. Dossier prompts are built ONLY from the PC's belief store + PC-visible narration events (truth barrier; no world truth).
- Determinism: Session is a single serialized process; Writer validates seq continuity; World.Server folds Writer tails in order. No wall-clock, no `System.unique_integer`, no `make_ref` inside ledgered payloads. `:dossier` texts are LLM output ledgered verbatim (same rule as narration) — replay reads them from the ledger, never re-calls.
- Scripted-adapter process-affinity: per-process script queues mean the Session process (interpret/narrate/summarize) and brain processes (deliberate/adopt) each pop their own copy in the same order as the pure path — golden equality holds. Tests keep the `salt:` convention.
- Claims are local-node only (v1, spec §14): `Protocol.Claims` is a unique Registry `{run_id, pc_id}`; channel `terminate/2` releases. No reconnect tokens.
- Dice visibility (spec §11): module preference default open. `RunChannel` pushes `:dice`-class events for the PC's own declared actions when prefs allow; SpectateChannel always sees them.
- Files under `shards_engine/runs/` (journals, checkpoints) are gitignored; tests pass explicit tmp `data_dir`s.
- No Phoenix HTML/JSON views, no router, no controllers — channels-only endpoint. `server: false` in dev/test config; smoke script flips it on.

## File Map

```
shards_engine/
├── apps/
│   ├── engine_core/lib/engine_core/
│   │   ├── application.ex        # MODIFY: +RunReg Registry, +RunSup DynamicSupervisor
│   │   ├── ledger/writer.ex      # CREATE: per-run append writer + ETS replica + journal + subscribers
│   │   ├── world/server.ex       # CREATE: per-run authoritative fold, snapshot/boundaries reads
│   │   └── run_sup.ex            # CREATE: ensure_run/stop_run helpers over RunSup
│   ├── referee/lib/referee/
│   │   ├── run.ex                # MODIFY: ledger :narration + :clarify events; texts derived
│   │   ├── dossier.ex            # CREATE: :summarize dossier build (LLM + template fallback)
│   │   ├── session.ex            # CREATE: Referee.Run.Session GenServer + restore/2
│   │   └── application.ex        # MODIFY: +SessionReg Registry, +SessionSup DynamicSupervisor
│   ├── protocol/                 # CREATE app (deps: phoenix, bandit, jason, referee in_umbrella)
│   │   ├── mix.exs · lib/protocol.ex
│   │   ├── lib/protocol/application.ex   # PubSub + Endpoint (server: false)
│   │   ├── lib/protocol/endpoint.ex      # socket "/socket" only
│   │   ├── lib/protocol/socket.ex        # connect/2: run_id + character_id | role: spectate
│   │   ├── lib/protocol/claims.ex        # unique Registry claim/release
│   │   ├── lib/protocol/channels/run_channel.ex
│   │   ├── lib/protocol/channels/spectate_channel.ex
│   │   ├── PROTOCOL.md                   # the wire contract (decision 24/37)
│   │   └── test/{socket_test,run_channel_test,spectate_channel_test}.exs
│   └── client_tui/               # CREATE app (deps: websockex, jason, protocol+referee in_umbrella)
│       ├── mix.exs · lib/client_tui.ex
│       ├── lib/client_tui/channel.ex     # phx line-JSON codec (join/event/heartbeat/decode)
│       ├── lib/client_tui/conn.ex        # WebSockex client → {:chan, event, payload} messages
│       ├── lib/client_tui/cli.ex         # REPL: input → declare_intent/answer/ooc/sheet
│       └── test/{channel_test,conn_test,e2e_ws_test}.exs
├── config/config.exs             # MODIFY: protocol endpoint config
├── scripts/protocol_smoke.exs    # CREATE: live server + scripted player smoke
└── .gitignore                    # MODIFY: +runs/
```

## Shared Interfaces (tasks must match these exactly)

- `EngineCore.Ledger.Writer.start_link(run_id :: String.t(), opts :: keyword()) :: GenServer.on_start()` — named `{:via, Registry, {EngineCore.RunReg, {:writer, run_id}}}`. `opts`: `data_dir: nil | Path.t()` (nil = no journal). Restarts replay the journal into ETS.
- `EngineCore.Ledger.Writer.append(run_id, [Ledger.Event.t()]) :: :ok | {:error, {:seq_gap, last :: integer(), got :: integer()}}` — first append must start at seq 1; events must be seq-contiguous ascending. On success: journal append (if `data_dir`), ETS insert, ordered subscriber notify.
- `EngineCore.Ledger.Writer.events(run_id) :: [Ledger.Event.t()]` · `tail(run_id, after_seq) :: [Ledger.Event.t()]` · `last_seq(run_id) :: integer()` — ETS reads, no GenServer hop.
- `EngineCore.Ledger.Writer.subscribe(run_id) :: :ok` — caller is monitored; receives `{:ledger_events, run_id, [Ledger.Event.t()]}` casts in append order. `unsubscribe/1` on DOWN.
- `EngineCore.World.Server.start_link(run_id, seed :: World.t()) :: GenServer.on_start()` — via `{:writer, run_id}`'s RunReg key `{:world, run_id}`; subscribes to Writer at init.
- `EngineCore.World.Server.snapshot(run_id) :: World.t()` · `boundaries(run_id) :: %{String.t() => %{state: :awake | :dormant, reason: String.t() | nil}}` — synchronous reads.
- `EngineCore.ensure_run(run_id, seed_world) :: :ok | {:error, term()}` — idempotently starts Writer + World.Server under `EngineCore.RunSup`. `EngineCore.stop_run(run_id) :: :ok` — test teardown.
- `Referee.Run.Session.start_link(run_id, yaml_path, seed, pcs, opts \\ []) :: GenServer.on_start()` — via `Referee.SessionReg`. `opts` passed through to `Run.new/4` plus `data_dir: nil | Path.t()`. Init: `EngineCore.ensure_run`, `Run.new`, append initial events, checkpoint.
- `Session.declare(run_id, pc_id, text) :: {:ok, %{reply: String.t() | nil}} | {:error, :paused | :no_run}` · `Session.advance(run_id) :: {:ok, map()} | {:error, :paused | :no_run}` — replies mirror the pure path's return payloads.
- `Session.pause(run_id) :: {:ok, %{dossiers: %{String.t() => String.t()}}} | {:error, :already_paused}` — builds + ledgers one `:dossier` event per living PC, checkpoints, sets `:paused`.
- `Session.resume(run_id) :: :ok | {:error, :not_paused}` · `Session.state(run_id) :: %{status: :running | :paused, tick: integer(), seq: integer(), run_id: String.t()} | nil`.
- `Session.restore(run_id, data_dir) :: {:ok, pid()} | {:error, term()}` — restart from checkpoint + journal (assert checkpoint seq == journal last_seq).
- `Referee.Dossier.build(ctx :: Ctx.t(), pc :: map(), events :: [Ledger.Event.t()]) :: {String.t(), Ctx.t(), Audit.t() | nil}` — class `:summarize`; prompt inputs: PC belief store + `:narration` events for that PC ONLY; template fallback lists the PC's current beliefs (never fails).
- Ledger events added: `%{kind: :narration, agent_id: pc_id, text: String.t()}` (class `:narration`), `%{kind: :clarify, agent_id: pc_id, question: String.t()}` (class `:clarify`), `%{kind: :dossier, pc_id, text}` (class `:dossier`).
- `Protocol.Socket.connect/2` params: `%{"run_id" => id, "character_id" => pc_id}` (PC) or `%{"run_id" => id, "role" => "spectate"}`; assigns `%{run_id, character_id | nil, role: :pc | :spectate}`; `id/1` → `"#{run_id}:#{character_id || "spectate"}"`.
- `RunChannel` topic `run:<run_id>` — join reply `%{state: slice, dossier: String.t() | nil}`; in: `declare_intent` `%{"text" => s}` → `Session.declare`; `answer` `%{"text" => s}` → same path; `ooc` `%{"text" => s}` → ledger `:ooc` event (class `:ooc`, `%{kind: :ooc, agent_id, text}`) + `{:ok, %{ack: true}}`; `sheet` `%{"update" => map}` → `{:ok, %{state: slice}}` (v1: read-only sync). Out pushes from Writer tails: `perception` `%{text, tick}` (own `:narration` events), `prompt` `%{question}` (own `:clarify`), `dice` `%{event_payload}` (own-action `:dice` events, prefs-gated default open), `state_sync` `%{slice}` (re-slice after any `:world`-class tail).
- `SpectateChannel` topic `spectate:<run_id>` — join reply `%{tick, boundaries, spend, tail: last 50}`; in: `pause`, `resume`, `spend`; out: `ledger_tail` `%{events}` (all classes, observability), `state_sync` `%{tick, boundaries}`.
- `ClientTUI.Channel` — `join(topic, payload) :: {binary, ref}` · `event(topic, event, payload) :: {binary, ref}` · `heartbeat() :: binary` · `decode(binary) :: {:event, topic, event, payload, ref} | {:reply, ref, status, payload} | :heartbeat_ack | {:error, :malformed}`.
- `ClientTUI.Conn.start_link(url, opts) :: GenServer.on_start()` — opts `[character_id, run_id, heartbeat_every: 30_000]`; parent receives `{:chan, topic, event, payload}`; `Conn.send_event(pid, event, payload) :: :ok`.
- Phoenix message envelope (vsn 2.0.0): `{"topic": t, "event": e, "payload": p, "ref": r}` — documented verbatim in `apps/protocol/PROTOCOL.md`.

---

### Task 1: Ledger narrations and clarify prompts (pure path)

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run.ex`
- Test: `shards_engine/apps/referee/test/run_test.exs` (extend), `shards_engine/apps/referee/test/narrate_test.exs` (if affected)

**Interfaces:**
- Produces: `:narration` events (`%{kind: :narration, agent_id, text}`) and `:clarify` events (`%{kind: :clarify, agent_id, question}`) inside `Run.declare`'s paths (clarify branch, resolved branch narration, rejected branch) and `Run.advance`'s `narrate_new_receipts/2`. `advance` still returns `{:ok, texts, run}` — texts now derived from the new events (filter `agent_id`).

- [ ] **Step 1 (failing tests):** in `run_test.exs` add:
  - "declare clarification is ledgered as a clarify event" — garbage/ambiguous utterance → `Run.declare` → assert one `:clarify` event with the pc's id and the returned question text; `Run.events` contains it in seq order.
  - "declare resolution narration is ledgered" — valid move → assert a `:narration` event for the pc whose text equals the returned reply.
  - "advance narrations are ledgered per PC" — two PCs, scripted receipts → assert one `:narration` event per receiving PC and `advance`'s texts map equals the map derived from those events.
  - "no narration events when nothing was received" — advance with no receipts → no new `:narration` events.
- [ ] **Step 2:** implement — `push` narration in the clarify branch of `declare` (before returning `{:ok, question, run}`), in `resolved` (after `Narrate.action`), in `rejected` (template refusal is already a reply text — ledger it), and in `narrate_new_receipts` per PC. Keep payload keys exactly `%{kind: :narration | :clarify, agent_id, text | question}`.
- [ ] **Step 3:** `mix test apps/referee` — all green including goldens (they run twice in-process; new kinds are additive).
- [ ] **Step 4:** commit `referee: ledger narrations and clarify prompts (pure path)`.

### Task 2: `EngineCore.Ledger.Writer` — append writer, ETS replica, journal

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/ledger/writer.ex`, `lib/engine_core/run_sup.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/application.ex`
- Test: `shards_engine/apps/engine_core/test/ledger_writer_test.exs`

**Interfaces:** as in Shared Interfaces. ETS: one named public `:ordered_set` table `EngineCore.Ledger.Ets`, key `{run_id, seq}`, value `Ledger.Event.t()` — created by the FIRST writer (owner process dies with table? No: table is owned by a tiny `EngineCore.Ledger.Ets` owner process started under Application; writers write via `:ets.insert` — table `public`, `read_concurrency: true`). Journal format: 4-byte big-endian length + `term_to_binary(event)` per record, file `data_dir/<run_id>.events`.

- [ ] **Step 1 (failing tests):**
  - "append assigns contiguous seq validation" — append events seq 1..3 → `:ok`; append seq 5 → `{:error, {:seq_gap, 3, 5}}`; `last_seq` == 3.
  - "events/tail read from ETS without the writer process" — stop the writer GenServer (Registry lookup, GenServer.stop), then `Writer.events(run_id)` still returns all 3 (read path survives writer restart).
  - "subscribers get tails in append order" — spawn a monitor'd subscriber, append twice, assert two `{:ledger_events, run_id, events}` messages arrive in order with correct payloads.
  - "subscriber death unsubscribes" — kill subscriber, append, writer does not crash (assert writer alive).
  - "journal replay on restart" — `data_dir` tmp path, append 1..3, stop writer, start new writer same run_id → `events` returns all 3, `last_seq` == 3.
  - "append is durable before reply" — after `append` returns `:ok`, journal file on disk contains the records (read back bytes).
- [ ] **Step 2:** implement `Ledger.Writer` GenServer + ETS owner + `RunSup.ensure_run`-adjacent helpers. `EngineCore.Application` children: ETS owner, `RunReg` Registry, `RunSup` DynamicSupervisor. `ensure_run/2` starts `{Ledger.Writer, {run_id, opts}}` and `{World.Server, ...}` (Task 3) idempotently via Registry.
- [ ] **Step 3:** `mix test apps/engine_core` green.
- [ ] **Step 4:** commit `engine_core: per-run Ledger.Writer with ETS replica, journal, subscribers`.

### Task 3: `EngineCore.World.Server` — authoritative fold + cheap reads

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/world/server.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/run_sup.ex` (ensure_run starts it)
- Test: `shards_engine/apps/engine_core/test/world_server_test.exs`

**Interfaces:** as in Shared Interfaces. Init: `{run_id, seed_world}` → subscribe to Writer → fold nothing yet. On `{:ledger_events, run_id, events}` → `Fold.fold` (assert first event seq == last folded + 1 — Writer already guarantees). `snapshot/1`, `boundaries/1` GenServer calls. `stop_run/1` terminates both.

- [ ] **Step 1 (failing tests):**
  - "folds writer tails into snapshots" — seed world from tower YAML, ensure_run, append `agent_added` PC event (seq 1) via Writer → `World.Server.snapshot` shows the agent; `boundaries` returns every boundary with `:dormant`/`:awake` states from the YAML.
  - "fold of writer events equals snapshot (spec 12.3)" — append a scripted `move` event chain, then `Fold.fold(seed_plus_pcs, Writer.events(run_id)) == World.Server.snapshot(run_id)` (compare `agents`, `tick`, `boundaries`).
  - "reads are cheap while writer busy" — not a perf test; assert `snapshot` answers while a subscriber (fake slow folder) is draining — i.e., World.Server is a separate process (assert `whereis writer != whereis world`).
- [ ] **Step 2:** implement. `boundaries/1` maps `world.boundaries` to `%{id => %{state: b.state, reason: b.reason}}` (use actual Boundary struct fields).
- [ ] **Step 3:** `mix test apps/engine_core` green. Commit `engine_core: World.Server authoritative fold with snapshot reads`.

> **Known rare intermittent (deferred):** full-suite runs occasionally fail `LedgerWriterTest` with `(EXIT) shutdown` on a writer mid-call (~2 in 10 before Task 3 landed). Never reproduces in isolation, paired files, or a 400-pass concurrent reproducer. No `Application.stop`/supervisor-killer exists in the suite. Revisit at Task 10's full-suite determinism proof; do not re-litigate mid-task.

### Task 4: `Referee.Dossier` — `:summarize` class, template fallback

**Files:**
- Create: `shards_engine/apps/referee/lib/referee/dossier.ex`
- Test: `shards_engine/apps/referee/test/dossier_test.exs`

**Interfaces:** `build/3` as in Shared Interfaces. Prompt: system = dossier writer role; user = PC name + belief list (`place_id` → believed agents/items) + that PC's `:narration` texts (chronological, capped 20). Response schema: `{"dossier": string}` (`required: [:dossier]`), one bounded retry via Router, then template fallback: "Thistle recalls: <belief summaries; narrations elided>". Audit ledgered by caller. Truth barrier test: prompt user text must NOT contain any agent/item not present in the PC's beliefs or narrations (assert against full world agent list).

- [ ] **Step 1 (failing tests):**
  - "routes through gateway as :summarize and returns dossier text" — scripted `summarize` queue with `{"dossier":"..."}` → returns text, audit class `:summarize`.
  - "template fallback on garbage" — two garbage entries (bounded retry) → fallback text contains the PC's believed agents; audit `parse_verdict: :fallback`, `ok: false`.
  - "truth barrier: prompt only carries PC-visible data" — capture `request.user` from the scripted adapter's request log; build a world where an agent exists elsewhere; assert that agent's id absent from prompt; assert PC's believed agent id present.
- [ ] **Step 2:** implement (mirror `Narrate`'s Ctx-passing shape: `{text, ctx2, audit}`).
- [ ] **Step 3:** `mix test apps/referee` green. Commit `referee: PC dossiers via :summarize with template fallback`.

### Task 5: `Referee.Run.Session` — live run owner, pause/resume, checkpoint/restore

**Files:**
- Create: `shards_engine/apps/referee/lib/referee/session.ex`
- Modify: `shards_engine/apps/referee/lib/referee/application.ex` (+SessionReg Registry, +SessionSup DynamicSupervisor)
- Test: `shards_engine/apps/referee/test/session_test.exs`

**Interfaces:** as in Shared Interfaces. State: `%{run_id, run: Run.t(), status, last_flushed: integer(), data_dir: nil | Path.t()}`. After every pipeline step: `new_events = Run.events(run) |> Enum.drop(last_flushed)` → `Writer.append(run_id, new_events)` → `last_flushed = run.seq` → checkpoint if `data_dir`. Checkpoint file: `data_dir/<run_id>.snapshot` (`term_to_binary(run)`); write via tmp+rename (atomic). `pause`: status guard → dossiers per living PC (from `run.pcs` + `dead?` logic — reuse Run's `dead?/1` semantics by re-implementing locally against `run.world`) → push `:dossier` events → append+checkpoint → reply texts. `restore`: read snapshot binary → run struct; `Writer` journal replay must agree (`last_seq == run.seq`); ensure World.Server folds — simplest: stop world server, restart with `seed = run.world`... NO: world must fold from journal; restart World.Server with seed loaded from YAML then let Writer... Writer only notifies NEW events. Correct restore: start Writer (journal replay), World.Server with seed = the LOADED yaml seed + `PC.build` injection (mirror `Run.new`'s pre-events world), then explicitly feed `Writer.events` through a one-shot `World.Server.adopt(run_id, events)` internal call (add `:adopt` handle_cast — test-covered). Then start Session with the restored run struct, `last_flushed = run.seq`.

- [ ] **Step 1 (failing tests):** each test uses a tmp `data_dir` and `EngineCore.stop_run` teardown; scripts follow `advance_test.exs` conventions (salt-keyed):
  - "declare through session mirrors the pure path byte-identically" — run A pure (`Run.new` + same declares), run B via Session; assert `term_to_binary(Run.events(A)) == term_to_binary(Writer.events(B))` and `Session.declare` reply text equals A's return text.
  - "advance through session mirrors the pure path" — same pattern with `advance` + `Session.advance`.
  - "pause blocks pipeline and ledgers dossiers" — pause → `declare`/`advance` return `{:error, :paused}`; one `:dossier` event per living PC; `Session.state` shows `:paused`; resume → declare works again.
  - "checkpoint restore continues deterministically" — scripted 4 declares; after 2, pause, `GenServer.stop` session + `EngineCore.stop_run`; `Session.restore(run_id, data_dir)`; continue remaining declares; final `Writer.events` equals uninterrupted run's events minus nothing (dossier events from the pause excluded — assert equality after filtering `:dossier`).
  - "pause twice errors" — `{:error, :already_paused}`.
- [ ] **Step 2:** implement Session + `World.Server.adopt/2` (cast, folds given events, seq-continuity assert).
- [ ] **Step 3:** `mix test apps/referee apps/engine_core` green.
- [ ] **Step 4:** commit `referee: Run.Session live owner — writer fanout, pause/resume dossiers, checkpoint restore`.

### Task 6: `apps/protocol` scaffold — endpoint, socket, claims

**Files:**
- Create: `shards_engine/apps/protocol/mix.exs`, `lib/protocol.ex`, `lib/protocol/application.ex`, `lib/protocol/endpoint.ex`, `lib/protocol/socket.ex`, `lib/protocol/claims.ex`, `test/test_helper.exs`, `test/socket_test.exs`
- Modify: `shards_engine/mix.exs` (no change — umbrella auto), `shards_engine/config/config.exs` (endpoint config), root `.formatter.exs` if app list exists
- Test: `shards_engine/apps/protocol/test/socket_test.exs`

**Interfaces:** Endpoint `use Phoenix.Endpoint, otp_app: :protocol`; `socket "/socket", Protocol.Socket, websocket: [timeout: 45_000]`; config `server: false`, adapter Bandit in `config/runtime.exs` only when `server: true`. Application: `Protocol.PubSub` + Endpoint. Claims: unique Registry; `claim(run_id, pc_id) :: :ok | {:error, {:already_claimed, pid()}}` · `release(run_id, pc_id) :: :ok` · idempotent release.

- [ ] **Step 1 (failing tests):** `Phoenix.ChannelTest` with `@endpoint Protocol.Endpoint`:
  - "connect with character params assigns pc role" — `socket("/socket", %{"run_id" => "r1", "character_id" => "pc_thistle"})` → `connect` → assigns.
  - "connect with spectate role" — role assign `:spectate`.
  - "connect rejects missing run_id" — `{:error, _}`.
  - "claims are exclusive and released on demand" — claim twice → error; release → claim ok.
- [ ] **Step 2:** implement; `mix deps.get` at umbrella root (phoenix ~1.8, bandit ~1.x pinned); config entries.
- [ ] **Step 3:** `mix test apps/protocol` green. Commit `protocol: channels-only Phoenix endpoint, socket, claims registry`.

### Task 7: `RunChannel` — per-PC protocol surface

**Files:**
- Create: `shards_engine/apps/protocol/lib/protocol/channels/run_channel.ex`
- Test: `shards_engine/apps/protocol/test/run_channel_test.exs`

**Interfaces:** as in Shared Interfaces. Join: `Session` must exist (whereis `Referee.SessionReg`) AND `character_id` in run's pcs (query `Session.state` + a new `Session.pcs(run_id)` — add tiny reader) AND `Claims.claim` succeeds; reply `%{state: slice, dossier: last dossier event text or nil}`; subscribe `Writer.subscribe`. `handle_in` per Shared Interfaces (ooc ledgered via `Session.ooc(run_id, pc_id, text)` — add to Session: pushes `:ooc` event, appends, no pipeline). Tail handling (`handle_info {:ledger_events, ...}`): fan out per Shared Interfaces; `state_sync` only when tail contains `:world`-class events; slice from `World.Server.snapshot` + `Referee.Slice.for_actor`. `terminate/2`: `Claims.release`.

- [ ] **Step 1 (failing tests):** channel tests with a live Session (scripted adapters, real Writer/World under test — reuse Task 5 harness helpers; module `async: false` for registry hygiene):
  - "join claims character and returns slice + dossier" — reply slice contains pc id; second socket same pc → `{:error, %{reason: "character_already_claimed"}}`.
  - "declare_intent pushes perception" — `push "declare_intent"` → `assert_push "perception", %{text: t}` with t non-empty; reply `:ok`.
  - "prompt push on clarify" — garbage utterance → `prompt` push with question.
  - "per-PC isolation: other PCs' narrations never pushed" — two PCs joined; narration event for pc_b → pc_a's socket gets NO perception push; pc_b's does. Also assert pc_a receives no `state_sync` referencing agents not in its slice (barrier).
  - "ooc is ledgered and acked" — `ooc` event in Writer tail; reply ack.
  - "sheet returns current slice" — reply `:ok`, payload has `state`.
- [ ] **Step 2:** implement. Add `Session.pcs/1` + `Session.ooc/3` (TDD one test each in session_test).
- [ ] **Step 3:** `mix test apps/protocol apps/referee` green. Commit `protocol: RunChannel — per-PC claim, isolation, perception/prompt/dice/state_sync pushes`.

### Task 8: `SpectateChannel` + `PROTOCOL.md`

**Files:**
- Create: `shards_engine/apps/protocol/lib/protocol/channels/spectate_channel.ex`, `shards_engine/apps/protocol/PROTOCOL.md`
- Test: `shards_engine/apps/protocol/test/spectate_channel_test.exs`

**Interfaces:** as in Shared Interfaces. Join reply built from `Session.state`, `World.Server.boundaries`, `Run.spend_report`-equivalent via `Referee.Spend.report(Writer.events(run_id))`, `Writer.tail(run_id, max(0, last_seq - 50))`. Tail pushes: every `{:ledger_events}` → `ledger_tail` with raw events. `pause`/`resume` in-events → Session calls, reply with dossier map / `:ok`. `spend` in-event → reply report.

- [ ] **Step 1 (failing tests):**
  - "join snapshot has tick, boundaries, spend, tail" — all keys present; tail capped at 50.
  - "ledger tails stream after join" — declare via Session after join → `ledger_tail` push arrives.
  - "pause generates dossiers and resumes" — `push "pause"` → reply has dossier map per PC; subsequent push "resume" replies `:ok`; Session.state flips.
- [ ] **Step 2:** implement + write `PROTOCOL.md`: transport (WS `/socket/websocket?vsn=2.0.0`), envelope, both channels' events with exact payload shapes, join/reply semantics, claim rules, dice visibility note, never-sent list (spec §11 verbatim). This doc is the client contract (decision 24/37).
- [ ] **Step 3:** `mix test apps/protocol` green. Commit `protocol: SpectateChannel + wire contract doc`.

### Task 9: `apps/client_tui` — codec, connection, CLI

**Files:**
- Create: `shards_engine/apps/client_tui/mix.exs`, `lib/client_tui.ex`, `lib/client_tui/channel.ex`, `lib/client_tui/conn.ex`, `lib/client_tui/cli.ex`, `test/test_helper.exs`, `test/channel_test.exs`, `test/conn_test.exs`
- Modify: `shards_engine/config/config.exs` if needed

**Interfaces:** as in Shared Interfaces. `Conn` uses WebSockex; `handle_frame({:text, json})` → decode → parent message `{:chan, topic, event, payload}` (replies surfaced as `{:chan_reply, ref, status, payload}`); auto-heartbeat `phx_heartbeat` every `heartbeat_every` ms; auto `phx_join` on connect for the configured topic. `CLI.main(args)` — opts `--url --run --character [--spectate]`; REPL: plain line → `declare_intent`; `/ooc text`, `/sheet`, `/pause`, `/resume`, `/spend`, `/quit`; prints pushes prefixed `[perception]` etc. `mix run -e "ClientTUI.CLI.main(System.argv)"` documented in app README.

- [ ] **Step 1 (failing tests):** codec: envelope round-trips, malformed JSON → `{:error, :malformed}`, heartbeat decode. Conn: against a local echo/fake WS? No network in unit tests — test Conn's pure frame handlers via `handle_cast/2`/`handle_info/2` directly (WebSockex callbacks are public overridable — call them with state tuples): join on connect builds phx_join with correct topic/payload; text frame routes to parent; heartbeat timer message emits heartbeat frame.
- [ ] **Step 2:** implement; deps `websockex ~> 0.4`, `jason`, in_umbrella `protocol`, `referee` (for e2e only).
- [ ] **Step 3:** `mix test apps/client_tui` green. Commit `client_tui: terminal reference client — codec, conn, CLI`.

### Task 10: E2E determinism proof + smoke script

**Files:**
- Create: `shards_engine/apps/client_tui/test/e2e_ws_test.exs`, `shards_engine/scripts/protocol_smoke.exs`
- Modify: `shards_engine/.gitignore` (+`runs/`)

**Interfaces:** e2e test starts `Bandit` (`plug: Protocol.Endpoint`, fixed test port with `:eaddrinuse` retry) + a scripted Session; connects TWO real `ClientTUI.Conn` WebSockex clients (scripted test players — spec §11); drives declares.

- [ ] **Step 1 (failing test):**
  - "live WS path produces the byte-identical ledger of the pure path" — Run A pure with N declares + M advances; Run B same via two WS clients issuing the same declares in the same order (advance driven via spectate `resume`-style calls or direct Session.advance between declares — choose direct Session.advance, deterministic); assert `term_to_binary(Run.events(A)) == term_to_binary(Writer.events(B))`.
  - "perception texts over the wire equal the pure path's returned texts" — collect `perception` pushes per pc; assert equality with Run A's narration texts per pc (same order).
  - "pause/resume across process restart mid-run" — pause at step k, stop session+run processes, restore, finish; final ledger (minus `:dossier`) byte-identical to uninterrupted.
- [ ] **Step 2:** `scripts/protocol_smoke.exs`: boots endpoint (server: true, port 4000 or arg), starts a Session from tower YAML with template-only routing (no keys), one scripted PC client prints perceptions; `mix run scripts/protocol_smoke.exs` documented. Run it once; paste output into commit message body (proof).
- [ ] **Step 3:** full suite `mix test` at umbrella root — all apps green. Commit `e2e: WS determinism proof + protocol smoke`.

### Task 11: Session end — engrams + final verification

- [ ] Full umbrella `mix test` + `mix compile --warnings-as-errors` green; `engrams check --staged` clean.
- [ ] `engrams decision log` for: (a) narrations/clarify/dossier events enter the ledger (replay reconstructs PC-perceived surface); (b) Session-as-pipeline-owner + Writer/World read split (client reads never queue behind LLM calls); (c) checkpoint = term_to_binary(Run) after each step (cheap snapshots, decision 28); (d) protocol contract doc location. Link `implements`/`part_of` to spec + prior decisions 23/24/28/37.
- [ ] `engrams progress log --status Done`, `active-context update`, `engrams export`, commit & push per Session End Protocol.

---

## Verification (plan-level)

1. `mix test` umbrella green — pure path unchanged, new surfaces covered.
2. Byte-identical ledger proof: live WS + Session path ≡ pure `Referee.Run` path (Task 10), pause/restore ≡ uninterrupted modulo `:dossier`.
3. Truth barrier over the wire: isolation test (Task 7) + prompt-level (Task 4).
4. `scripts/protocol_smoke.exs` output pasted as proof.
