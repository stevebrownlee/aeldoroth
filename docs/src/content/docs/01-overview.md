---
title: "Overview"
description: "The Shattered Kingdoms engine thesis, marketplace vision, acceptance criteria, and quickstart."
order: 1
category: "Foundation"
tags: ["overview", "vision", "quickstart", "acceptance"]
---

# The Shattered Kingdoms Engine

The Shattered Kingdoms is an autonomous-agent roleplaying runtime written in Elixir. Every actor in an adventure—player characters, goblin chiefs, giant rats, imprisoned farmers, even traps and hazards—is modeled as an **agent** with its own beliefs, capabilities, commitments, and cadence. The engine does not puppet characters from a single god-view; it lets each actor act on what *it* can perceive, then adjudicates the collisions.

> **LLM proposes. Engine disposes.**  
> Every non-trivial decision passes through a single referee pipeline. Large language models render perception, deliberate intent, and narration, but they never mutate world truth directly. Truth lives in one immutable, deterministic ledger.

This chapter states the system thesis, sketches the long-term platform vision, defines the v1 acceptance bar, and gets a live session running in two commands.

---

## System Thesis

The engine is built on four axioms that shape every module:

1. **Every actor is an agent.**  
   PCs, monsters, and NPCs share the same anatomy: beliefs, capabilities, commitments, cadence, and (for sapients) a supervised brain process. A goblin chief deliberates with the same machinery as a human player.

2. **LLM proposes, engine disposes.**  
   Brains emit *proposals* (`Action{verb, target, manner, params}`). The referee validates, resolves dice, applies changes through a pure reducer, and narrates back. LLMs never write events.

3. **World truth is immutable and deterministic.**  
   State is `fold(ledger)`. The ledger is append-only; every mutation is an event; every roll is seeded and recorded. Snapshots are caches, not authority.

4. **Emergence is reproducible.**  
   The same YAML seed produces different histories because sapient decisions are stochastic. Each divergence is ledgered with a *fork-diff receipt*: the exact event at which runs branch.

These axioms make the engine suitable both as a live play experience and as a test harness for emergent-agent behavior.

---

## The Two-Sided Marketplace Vision

v1 builds the runtime half of a platform. The eventual marketplace has two sides:

- **Adventure authors** package adventures as self-contained YAML modules. A module declares places, edges, agents, items, traps, boundaries, and referee preferences. It does not ship code.
- **Players and referees** run adventures inside isolated sandboxes. The platform issues frontier LLM keys, meters every call, and applies a per-token margin.

The seams needed by that vision are already present:

| Seam | Where it lives |
|------|----------------|
| Engine/content split | `shards_engine/apps/engine_core` (runtime) vs `the-ruined-tower/ruined_tower.yaml` (content) |
| Run sandbox isolation | One `run_id` → one `EngineCore.RunSup` subtree + one ledger |
| Gateway chokepoint | `LLM.Router` in `apps/llm_gateway` is the only allowed LLM caller |
| Per-call metering | Every LLM call writes an `llm` event with model, tokens, latency, and cost |

v1 deliberately avoids auth, payments, storefront, or multi-tenant hosting. It proves the runtime economics first: a full adventure can be played with observable cost and verifiable determinism.

---

## The 4-Human Party Acceptance Criteria

The Ruined Tower (`the-ruined-tower/ruined_tower.yaml`) is the v1 seed adventure. Acceptance is not a unit-test greenlight; it is a live, multi-session playthrough.

### 1. Full Playthrough
Four connected human PCs complete the adventure arc (or achieve a TPK) from YAML reset via `client_tui`, across two or more real sessions with pause and resume.

```bash
cd shards_engine
mix run --no-halt -e 'ClientTUI.CLI.main(["--run", "rt-001", "--pc", "aelfric"])'
```

During pause, the run stops; on resume, the engine replays from the last snapshot plus the event tail.

### 2. Emergent Behavior, With Receipts
At least one behavior not scripted in the YAML must be reproduced from ledger evidence. Examples:

- A goblin subordinate lies to Grisk about completing an order.
- A wolf pack flanks through an unexpected boundary wake.
- A parley is initiated by a non-PC agent.

The evidence is a **fork-diff**: a copy of the run prefix plus a new RNG branch. The diff pinpoints the event where history diverged.

### 3. Truth Barrier
No prompt fed to any LLM may contain world truth invisible to the actor. Property tests and a full-run audit scan `llm` events for leaked `is_hidden` fields, other-room state, or other PCs' private prompts.

### 4. Save/Resume and Replay
Verbatim replay reconstructs the run byte-identically. Resimulated replay changes only at `deliberation` and `interpret` events. Cost observability is complete: a per-class, per-agent spend report is generated for the full playthrough.

---

## Quickstart

### Terminal client (`client_tui`)

The terminal client is the reference PC seat. It speaks the WebSocket protocol defined in `apps/wire` and holds zero authority.

```bash
cd shards_engine
# start the umbrella in dev (or use scripts/web_server.exs below)
mix run --no-halt -e 'ClientTUI.CLI.main(["--run", "rt-001", "--pc", "aelfric"])'
```

Available slash commands inside the REPL:

```text
/ooc <text>   out-of-character message to the referee agent
/sheet        request a state sync of your PC
/pause        pause the run
/resume       resume the run
/spend        print current LLM spend for this run
/quit         disconnect
```

Every non-command line is a declared intent; it enters the referee pipeline as a natural-language proposal.

### LiveView web console (`scripts/web_server.exs`)

For a browser-based session, start the web console:

```bash
cd shards_engine
MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Then open:

```text
http://0.0.0.0:4000
```

The script exposes three routes:

```text
/                      home / referee console
/runs/<run_id>?pc=<id> player seat (LiveView)
/runs/<run_id>/gm      GM spectate console (ledger tail + spend)
```

The web console uses the same Phoenix Channels as the terminal client; no protocol change is required between CLI and browser play.

---

## Reading the Handbook

The next chapters descend from architecture to mechanics:

1. **Overview** — this chapter.
2. **Architecture & Supervision** — the brain/ledger split and OTP supervision tree.
3. **Referee Pipeline** — propose → validate → resolve → apply → narrate.
4. **Agent Cognition & BDI** — beliefs, commitments, decisions, and cadence.
5. **Signals, Perception, and Boundaries** — how agents learn what is true.
6. **LLM Gateway & Routing** — call classes, budgets, adapters, and telemetry.
7. **Wire Protocol & Clients** — WebSocket protocol and channel semantics.
8. **Adventure Authoring in YAML** — writing modules like The Ruined Tower.
9. **Platform Marketplace Vision** — from runtime to hosted marketplace.
