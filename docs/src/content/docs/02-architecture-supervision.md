---
title: "Architecture & Supervision"
description: "The hybrid brain/ledger split, core OTP supervision topology, and the determinism contract that makes replay possible."
order: 2
category: "Architecture"
tags: ["architecture", "otp", "supervision", "ledger", "determinism"]
---

# Architecture & Supervision

The Shattered Kingdoms engine is a hybrid: **agent brains are supervised, deliberating OTP processes**, while **world truth is a single append-only ledger folded by pure reducers**. This split lets us keep the classic Elixir promise of isolated, restartable actors *and* get byte-exact replay, auditability, and deterministic adjudication.

---

## The Brain/Ledger Split

### What lives in a brain

A tier-3 sapient agent runs as its own OTP process under `Agents.DynamicSup`. It holds only *deliberation state*:

- a bounded belief store (what the agent thinks it knows),
- a dossier of other agents it has interacted with,
- outstanding commitments and their priorities,
- salience weights that decide whether to deliberate now.

```elixir
# apps/agents/lib/agents/brain.ex (conceptual)
%Agents.Brain{
  id: "grisk",
  run_id: "rt-001",
  beliefs: [...],       # belief entries, not world truth
  commitments: [...],   # pending/due/kept/violated
  dossier: %{...},      # models of other agents
  cadence: %{tick: 10, interrupt: :salient}
}
```

A brain **holds zero authority state**. It cannot change hit points, move an agent, or open a door. It can only *propose* an action to the referee. If the process crashes and restarts, the worst outcome is a moment of in-character hesitation; the world itself is untouched.

### What lives in the ledger

The ledger is the authority. It is an append-only sequence of typed events, one per run:

```elixir
# apps/engine_core/lib/engine_core/ledger/event.ex
%EngineCore.Ledger.Event{
  seq: 42,
  tick: 128,
  class: :world,
  type: :move,
  actor: "grisk",
  payload: %{from: "guard_room", to: "entry_hall"},
  provenance: %{...},
  hash: "..."
}
```

Event classes include:

- `world` — applied actions (move, strike, pick up, open, etc.)
- `signal` — emission, propagation, and reception
- `envelope` — agent-to-agent messages and adoption/rejection
- `commitment` — create, due, keep, violate, renegotiate
- `deliberation` — decision summaries for audit and emergence
- `dice` — roll, seed, result
- `llm` — model, tokens, latency, cost, prompt-slice ref
- `meta` — mode changes, snapshots, boundary wake/sleep

The current world is `fold(ledger)`. Nothing else is truth.

### The single-writer rule

Only one process applies world events: `EngineCore.World.Server`. Every other process reads snapshots or the ledger tail and proposes. This is the guarantee that makes validation total, ordering unambiguous, and replay byte-identical.

```
┌─────────────────────────────────────────────────────────┐
│                      Per-run topology                    │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐    propose    ┌──────────────────┐   │
│  │ Agent brains │──────────────▶│ Referee pipeline │   │
│  │  (GenServer) │               │                  │   │
│  └──────────────┘               │  1. interpret    │   │
│          │                      │  2. validate     │   │
│          │ subscribe to         │  3. resolve        │   │
│          │ perceivable slice   │  4. apply          │   │
│          ▼                      │  5. narrate      │   │
│  ┌──────────────┐               └────────┬─────────┘   │
│  │ EngineCore.  │                        │             │
│  │ World.Server │◀───────────────────────┘             │
│  │  (single     │                                       │
│  │   writer)    │                                       │
│  └──────┬───────┘                                       │
│         │ append                                        │
│         ▼                                               │
│  ┌──────────────────┐                                   │
│  │ EngineCore.      │                                   │
│  │ Ledger.Writer    │                                   │
│  │ (journal + ETS   │                                   │
│  │  read replica)   │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

---

## Core OTP Supervision Topology

`EngineCore.Application` and `Referee.Application` form the root supervision trees. Per-run processes live under a shared `DynamicSupervisor`, `EngineCore.RunSup`.

### Root supervision

```
EngineCore.Application
├── EngineCore.RunReg (Registry)
├── EngineCore.RunSup (DynamicSupervisor)
│   ├── EngineCore.Ledger.Writer per run
│   └── EngineCore.World.Server per run
├── EngineCore.Ledger.Ets (ETS read replica)
└── ...

Referee.Application
├── Referee.SessionSup (DynamicSupervisor)
│   └── Referee.Run.Session per run
├── Referee.GatewaySup
└── ...
```

### Key processes

| Process | Module | Responsibility | Restart |
|---------|--------|--------------|---------|
| Ledger writer | `EngineCore.Ledger.Writer` | Append events, journal to disk, serve tail reads | `:transient` |
| World server | `EngineCore.World.Server` | Fold ledger, hold cached snapshot, serialize applies | `:transient` |
| Run supervisor | `EngineCore.RunSup` | Idempotent `ensure_run/3` and `stop_run/1` | `:permanent` |
| Run registry | `EngineCore.RunReg` | `{kind, run_id}` → pid lookup | `:permanent` |
| Session | `Referee.Run.Session` | Pipeline owner, PC intent intake, brain orchestration | `:transient` |
| Session supervisor | `Referee.SessionSup` | One session per run | `:permanent` |

### `EngineCore.RunSup` idempotency

A run is booted with `ensure_run/3`. Writer starts first; world fold starts second, seeded from the loaded YAML. Both are `:transient` so a clean shutdown does not restart them.

```elixir
alias EngineCore.RunSup

{:ok, _pid} = RunSup.ensure_run(
  "rt-001",
  world,
  data_dir: "runs/rt-001"
)
```

The writer child spec is keyed by `{:writer, run_id}`; the world child spec by `{EngineCore.World.Server, run_id}`.

### `EngineCore.World.Server` fold loop

The world server subscribes to the writer. On every batch of ledger events, it folds them through `EngineCore.Fold` and caches the result.

```elixir
# apps/engine_core/lib/engine_core/world/server.ex (excerpt)
def handle_info({:ledger_events, run_id, events}, %{run_id: run_id} = st) do
  world = Enum.reduce(events, st.world, &EngineCore.Fold.apply/2)
  {:noreply, %{st | world: world, last_seq: max_seq(st.last_seq, events)}}
end
```

Because all applications flow through this one process, "apply" is naturally serialized. There are no lost updates, no interleaving of simultaneous melee strikes, and no race conditions between a door opening and a trap resolving.

---

## Determinism Contract

The engine enforces determinism at multiple layers. The contract is simple and test-enforced:

```text
fold(ledger) == snapshot at every snapshot point
```

### What makes it hold

1. **Append-only ledger.**  
   Events are never deleted or rewritten. A snapshot is the cached fold of a prefix.

2. **Seeded RNG.**  
   All dice come from `EngineCore.Dice` with an explicit RNG state. The seed is recorded in the run record.

3. **Pure reducers.**  
   `EngineCore.Fold` is a pure function `event × state → state`. No wall clock, no randomness, no external I/O.

4. **Deterministic scheduling.**  
   The scheduler advances a monotonic tick integer. Segment/round/turn durations are fixed; the next event is the next scheduled event, not a wall-clock poll.

5. **Reproducible inputs.**  
   Brains receive a *slice* built from their belief store and perceivable signals. The slice builder is deterministic given the same ledger.

### Replay modes

| Mode | What changes | Use |
|------|--------------|-----|
| **Verbatim replay** | Nothing. LLM outputs and dice are read from ledger. | Audit, resume, regression test. |
| **Resimulated replay** | `deliberation` and `interpret` events re-call the LLM at fixed temperature. | Emergence exploration, fork-diff. |
| **Dice replay** | Dice rolls verbatim; only sapient choices vary. | Controlled divergence. |

### Golden byte-identical replay proof

The acceptance suite contains golden-ledger tests. A full run is recorded; verbatim replay produces the same snapshot digest.

```elixir
# apps/engine_core/test/cascade_replay_test.exs (excerpt)
test "verbatim replay reconstructs snapshot" do
  run_id = "golden-replay"
  :ok = EngineCore.Fold.seed_world(run_id, world_seed())
  # run all scripted inputs...
  snap = EngineCore.World.Server.snapshot(run_id)
  replayed = EngineCore.Replay.reconstruct(run_id, mode: :verbatim)
  assert :erlang.term_to_binary(snap) == :erlang.term_to_binary(replayed)
end
```

This is not a soft guarantee. It is a CI gate: if any non-determinism leaks into the fold, the test fails and the build is blocked.

### Fork-diff as evidence

A fork is a copy of a run prefix plus a branched RNG stream:

```elixir
Referee.Run.fork("rt-001", tick: 340, branch_seed: :crypto.strong_rand_bytes(32))
```

The resulting ledger diff highlights exactly where the two histories diverge—usually at a `deliberation` or `interpret` event. That event is the **receipt** for emergent behavior: it is logged, auditable, and reproducible on demand.

---

## Failure Isolation

Because authority is centralized in the ledger and world server, brains can be killed and restarted without corrupting state. A crashed brain emits a `:DOWN` message that the session handles as a momentary hesitation; the next tick wakes it with a fresh belief summary. A crashed world server or writer, however, is treated as a run-ending fault: the run is paused, the journal is inspected, and resume replays from the last committed event.

This asymmetry is intentional. Brains are cheap, disposable, and safe. Truth is expensive, durable, and singular.
