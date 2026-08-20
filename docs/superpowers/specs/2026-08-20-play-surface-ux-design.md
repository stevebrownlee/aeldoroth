# Play Surface & GM Console — UI/UX Redesign

**Date:** 2026-08-20 · **Status:** For review · **Scope:** `shards_engine/apps/client_web` (HomeLive, RunLive, SpectateLive) + additive wire events

**Author's stance:** written from the table, not the codebase. Thirty years of running AD&D says a play UI lives or dies on one thing: at every moment, every person at the table must be able to answer the questions the GM answers verbally at a physical table. This document diagnoses why the current UI fails that test and lays out the redesign.

---

## 1. Diagnosis — why the current UI fails

The current UI is a transport inspector, not a game. It exposes the wire protocol (declares, OOC events, ticks, ledger seqs) instead of the fiction (what you see, what you can do, what just happened). Concretely:

### HomeLive (`/`) — the front door is an engine form
- The first screen a human sees is titled **"Referee console — trusted surface"** and asks for a **server filesystem path** to a YAML file and a roster in pipe-delimited text (`id|name|place|int|hp|ac|thac0|damage`). A player landing here has no idea what to do; a GM must know server paths by heart.
- No scenario concept, no party concept, no seat links. Starting "tonight's game" is a data-entry chore.

### RunLive (`/runs/:id`) — the player surface answers nothing
A player at a real table constantly asks three questions. The surface answers none well:

- **"What do I see?"** — The scene is one `summary` line plus an exits string (`Exits: north, down`). The slice already carries `believed` (who/what is here) and `salient` (what caught your eye) — **neither is rendered**. Exits are text, not actions.
- **"What can I do?"** — A bare input with placeholder `declare intent`. Nothing teaches the grammar the parser actually understands (bare directions, room names, look/search/listen verbs — decision 54). A new player will type nothing, or type something the referee must clarify, and bounce off. The campaign philosophy is *player skill over character stats* — but player skill needs to know the moves exist.
- **"What just happened?"** — The log mixes narration, OOC, and dice rows where **dice are `inspect(payload)` — raw Elixir term dumps**. The single most dramatic moment in D&D (the roll) is rendered as debug output.
- **Turn state is invisible.** Is the referee resolving? Is it waiting on *me*? Are we paused? The only prompt signal is a placeholder swap in the same input box. Paused runs produce a flash error *after* you submit.
- **No character sheet.** HP, AC, THAC0, inventory — all in the slice's agent body, none rendered. A D&D player without a visible sheet is not playing D&D.
- **No party.** Other PCs believed present never appear. The party — the social core of the game — is absent from the screen.

### SpectateLive (`/runs/:id/gm`) — the GM console is a firewall log
The GM's loop is *advance → watch → intervene*. The console supports none of it:

- **"Is anyone waiting on me?" is unanswerable.** Pending player intents and unanswered clarification prompts are not visible. The GM presses Advance blind.
- **"Advance" is unlabeled.** Advance what — a tick? Until someone must act? The single most important lever has no stated semantics.
- **The ledger tail is metadata-only**: `seq 41 · tick 3 · dice`. No payload preview, no filtering. The promised observability (spec §11) exists on the wire and is thrown away in the render.
- **Boundaries are a two-column table**, not the dungeon. Spend is hidden behind a button instead of always-on. Dossiers appear only on pause, with no on-demand path.

### Systemic
- No onboarding anywhere: nothing explains what this game is, how a turn works, or what to type.
- One flat monospace column for every surface; no information hierarchy. (The dark theme in `root.html.heex` is fine as chrome — the problem is structure, not palette.)

---

## 2. North star — the five table questions

At a physical table the GM keeps five questions answered at all times. The UI must answer them continuously, in screen space proportional to how often they're asked:

| # | Question | Whose | Surface region |
|---|----------|-------|----------------|
| 1 | What do I see? | Player | Scene panel (center) |
| 2 | What can I do? | Player | Action bar (bottom, always reachable) |
| 3 | What just happened? | Player | Chronicle (center, below scene) |
| 4 | Who is waiting on me / what needs input? | GM | Flow board (top, primary) |
| 5 | What is the world doing / about to do? | GM | World panel + ledger tail (below flow board) |

Supporting rails: the player's **character sheet** and **party** are persistent side rails (always visible, never scrolled away); the GM's **spend**, **tick**, and **run state** are a persistent header.

---

## 3. Design principles

1. **Two products, one wire.** Player surface and GM console are different products with different mental models. Share chrome and components; never share layout.
2. **Show, then scaffold, never block.** Freeform declaration stays primary — it's the campaign's soul (player skill > stats). Every UI affordance composes *text into the declare box*; nothing replaces the box. Buttons teach the grammar by writing it.
3. **State is a first-class citizen.** "Whose move is it" is rendered as status, not implied by placeholder text. The UI always shows one of: `your action`, `answer needed`, `referee resolving`, `waiting on others`, `paused by GM`, `disconnected`.
4. **Dice are theater.** Rolls render as rolls: who, what, die, result, outcome. Open visibility is the module default — lean into it.
5. **The truth barrier is a feature, not a limit.** Everything rendered on the player surface is already in `Referee.Slice` (place, exits, believed, salient, agent body) or per-PC pushes. We render what exists; we do not add player-facing data.
6. **Additive protocol only.** The wire grows new optional events/fields; existing ones never change shape. Both LiveViews already ignore unknown events ("protocol growth never crashes a seat/console").
7. **Every screen answers: what do I do next?** If a screen needs a manual, it failed.

---

## 4. Player surface (RunLive redesign)

Layout (desktop; collapses vertically on narrow screens):

```
┌──────────────────────────────────────────────────────────────┐
│ Thistle · The Ruined Tower        ● connected · tick 12      │  header: identity + status
├────────────┬─────────────────────────────────┬───────────────┤
│ CHARACTER  │  SCENE                          │  PARTY        │
│  HP ▓▓▓▓░  │  Entry Hall                     │  Bramble      │
│  AC 5      │  narration text…                │  (believed    │
│  THAC0 20  │  ─────────────                  │   present;    │
│  dmg 1d8   │  Here: a crate, 3 giant rats    │   from slice) │
│  Ready: —  │  (believed + salient)           │               │
│            │  ─────────────                  ├───────────────┤
│            │  CHRONICLE (stream)             │  EXITS        │
│            │  [tick 11] You push north…      │  [north]      │
│            │  🎲 Bramble hits rat — 4 dmg    │  [down]       │
│            │  ooc: brb 30 sec                │  (chips →     │
│            │                                 │   declare)    │
├────────────┴─────────────────────────────────┴───────────────┤
│ ⚠ REFEREE ASKS: "The corridor forks — left or right?"        │  prompt banner (when set)
│ [Look][Search][Listen][Attack][Talk][Take][Use][Ready][Wait] │  verb palette
│ > go n|_______________________________________ [Declare]     │  compose box
│ 💬 table talk…                                  [OOC]        │  ooc (secondary, collapsed by default)
└──────────────────────────────────────────────────────────────┘
```

### Components

- **Scene panel** — place name, latest narration, "Here:" list from `believed` + `salient` (chips; clicking a chip inserts its name into the compose box — "attack " + chip → "attack giant rat"). This is the answer to *what do I see*.
- **Exits** — chips, one per exit; clicking declares the bare direction (`north`). Teaches decision-54 grammar by using it.
- **Chronicle** — the existing stream, typed: narration rows (prose), dice rows (rendered, see below), OOC rows (italic, dim), system rows (pause/resume notices). Newest at bottom, auto-scroll unless the player scrolled up.
- **Dice tray rendering** — dice event payloads carry the roll; render `🎲 <who> <what>: <die> <result> → <outcome>`. Fallback for unknown payload shapes: a generic "the referee rolls…" row, never `inspect(payload)`.
- **Character rail** — from the slice agent body: HP (bar + numbers), AC, THAC0, damage, ready item, plus level/XP when content provides them (levels "arrive with content, not forms" — rail shows what exists, no fabrication). Read-only, matching v1 `sheet` semantics.
- **Party rail** — other PCs from `believed`, name + perceived state only. Truth-barrier-safe by construction.
- **Prompt banner** — when a `prompt` push arrives: pinned banner quoting the question, compose box switches to answer mode (sends `answer`), banner clears on send. Today this is a placeholder swap; it becomes unmistakable.
- **Status ribbon** — one line, always visible: `connected · tick n · your move` / `answer needed` / `resolving…` / `paused by GM` / `reconnecting…`. Derived from conn liveness + prompt + pause flashes (pause currently only surfaces as a submit error — we surface it as state; see §7).
- **Verb palette** — `Look · Move · Search · Listen · Attack · Talk · Take · Use · Ready · Wait`. Each inserts a scaffold into the compose box (e.g. Search → `search the `; Attack → `attack `). Pure client-side; sends ordinary `declare_intent`. First-run hint under the box: "Describe what you do — specifics beat dice. Try: *search the crate* or *north*."

### States handled explicitly
- **Pre-seat**: seat picker becomes a small lobby — PC name + one-line concept + "claim" buttons; claimed PCs show as taken (claim failure is already a join error — render it inline on the picker, not a flash).
- **Disconnected**: banner + auto-reconnect (LiveView reconnects; the wire conn must re-join the seat — claim survives re-join because disconnect releases it).
- **Paused**: status ribbon + compose box disabled with "Paused by the GM" affordance instead of submit-and-error.

---

## 5. GM console (SpectateLive redesign)

Layout:

```
┌──────────────────────────────────────────────────────────────┐
│ GM — The Ruined Tower · run web-42 · tick 12 · ● live        │
│ spend: 31 calls · 48k in / 9k out        [details ▾]         │  always-on header
├──────────────────────────────────────────────────────────────┤
│ NEEDS INPUT                                                  │  FLOW BOARD — question #4
│  ⚠ Thistle — referee asked: "left or right?" (2 ticks)       │
│  … Bramble — declared "search the crate", not yet resolved   │
│  ✓ 2 PCs seated · 0 idle                                     │
│ [▶ Advance]  [⏭ Advance until input needed]  [⏸ Pause & dossier] [▶ Resume]
├──────────────────────────────┬───────────────────────────────┤
│ THE DUNGEON                  │  LEDGER (filtered)            │
│  entry_hall   ● awake t11    │  [all][narration][dice][llm]  │
│  library      ○ dormant —    │  seq 41 · 🎲 attack: hit, 4   │
│  guard_room   ● awake t9     │  seq 40 · 📖 "You push…"      │
│  (place list from            │  seq 39 · 🧠 grisk deliberates│
│   boundaries; awake/dormant) │  (payload previews, not       │
│                              │   metadata-only)              │
├──────────────────────────────┴───────────────────────────────┤
│ DOSSIERS (on pause, or "view latest" anytime)                │
└──────────────────────────────────────────────────────────────┘
```

### Components & levers

- **Flow board (primary).** Per PC: seated?, last declared intent + tick, outstanding clarification (question text + age), HP if living. Sorted: needs-input first. This is the console's reason to exist.
- **Advance, labeled honestly.** `Advance` = one pipeline step (current `Session.advance/1` semantics — label it "step"). New **`Advance until input needed`**: console-side loop calling advance until any PC has an outstanding prompt/intent or a step cap (suggest 20) is hit — the button every GM actually wants. No engine change; document the cap.
- **The Dungeon panel** — boundaries rendered as the place list with awake/dormant and last-trigger tick. This is "what the world is doing" at a glance. (Stretch, phase C+: node-and-exit graph from module YAML edges — the data exists; a real map. Optional.)
- **Ledger tail with previews** — per class icon + one-line payload summary (narration: first 80 chars; dice: rendered roll; llm: agent + class + tokens; signal/commitment: name + parties). Class filter chips. The wire already streams full events — this is pure render work.
- **Spend header** — totals always visible from join reply; `[details ▾]` expands by-class/by-agent (the current `spend` reply). No button-press for the number a GM checks constantly.
- **Dossiers** — still generated on pause; add "view latest dossiers" when paused state exists. Rendering unchanged (pre-wrap text), plus per-PC framing.

---

## 6. Lobby (HomeLive redesign) — the session flow

Replace the engine form with tonight's-game flow:

1. **Scenario card(s).** Detect bundled modules (The Ruined Tower at the configured path); card shows name, hook ("Livestock disappearing…"), party size/level (4 × level 1), tone. GM clicks **Start this adventure**. YAML path field survives only behind an "advanced" disclosure.
2. **Roster builder.** Four canonical seats prebuilt (Fighter / Cleric / Illusionist / Thief per product context; names editable, stats via fields, not pipe text). Pipe-delimited textarea moves behind "advanced". Validation inline per row.
3. **After create → the sharing screen.** One copyable seat link per PC (`/runs/:id?pc=…` — already works) + "Open GM console" + "Open a seat". This is the entire onboarding: *GM starts run → sends links → players click.*
4. **Active runs** table stays, gains status + tick + a resume hint; seed field gets a one-line "same seed + same script = same world" tooltip.

First-run help: a three-line "How this plays" box on the seat picker (you declare in prose, the referee resolves, dice are open).

---

## 7. Wire & engine implications (all additive)

| # | Addition | Why | Shape |
|---|----------|-----|-------|
| W1 | Spectate join reply + push: `awaiting` — per PC `{seated, last_intent: text+tick, prompt_outstanding: question+tick}` | Flow board (question #4). Source: `Referee.Run.Session` state — prompts are already tracked pipeline-side | New key in join reply; new optional `awaiting` push on change. Unknown-event/field tolerance already in both clients |
| W2 | Run channel: `paused` / `resumed` push to seats | Status ribbon without submit-and-error | New optional events; clients ignoring them see no change |
| W3 | Nothing else for players | Scene/party/sheet all exist in `Referee.Slice`; dice payloads already pushed | — |
| W4 | Ledger tail: **no change** — full events already stream; previews are render-side | GM observability | — |

Non-goals (unchanged v1 semantics): sheet stays read-only; no player map (place-graph is GM stretch); no auth; advance semantics unchanged.

---

## 8. Phasing — each phase ships independently

**Phase A — "Make it a game" (player surface + lobby)**
Lobby flow (scenario card, roster builder, seat links) · RunLive layout: scene panel with believed/salient, exit chips, verb palette, typed chronicle with rendered dice, character rail, party rail, prompt banner, status ribbon.
*Acceptance:* a brand-new player, given only a seat link, can orient (what do I see), act (exit chip / verb / freeform), and read the fight (dice rendered) — with zero instructions. Browser-verified: full seat flow + a scripted combat beat.

**Phase B — "Teach the grammar" (depth + polish)**
Contextual suggestions (combat verbs when believed hostiles present; prompt-aware framing), chip-to-compose for entities, pause/disconnect states end-to-end (W2), reconnect re-claim, chronicle ergonomics (auto-scroll pinning, kind filters), narrow-screen collapse, first-run hints.
*Acceptance:* pause mid-fight → every seat shows `paused by GM` without a failed submit; disconnect/reconnect keeps seat and chronicle; a new player produces a parseable declaration within 2 tries.

**Phase C — "GM flow board" (console)**
W1 `awaiting` event + flow board · advance-until-input lever (capped console loop) · dungeon place panel · ledger previews + class filters · spend header · dossiers on demand.
*Acceptance:* GM can answer "who is waiting on me and why" without pressing anything; advance-until-input stops at the first prompt; every ledger class renders a one-line preview.

---

## 9. Decisions I made (push back if you disagree)

1. **Scaffold over sandbox.** Verb palette and chips compose text; the freeform box stays primary. A pure-menu UI would betray the player-skill philosophy; a bare box keeps failing new players. This is the middle that teaches.
2. **Advance-until-input lives in the console, not the engine.** It's a UX loop over `Session.advance/1` with a cap. Engine semantics stay pure; GM gets the lever they actually want.
3. **No player-facing map in v1.** The engine's space is a place-graph; the scene panel + exit chips carry navigation. A graph map is GM-console stretch only.
4. **Dice theater, open table.** Module default is open visibility — we render all PC rolls. If a module hides dice, the tray shows "the referee rolls…" — never debug output.
5. **W1/W2 are the only protocol growth.** Everything else is render-side on data the wire already carries. Both LiveViews tolerate unknown events by design.

## 10. Open questions for your review

1. Verb palette set — is `Look · Move · Search · Listen · Attack · Talk · Take · Use · Ready · Wait` the right ten, or do you want campaign-specific verbs (e.g. `Pry`, `Listen at door`) reflecting the trap-detection procedure?
2. Advance-until-input cap of 20 steps — right order of magnitude for the tower's cadence?
3. Should the GM flow board show *believed* HP/status of monsters (awake boundaries only), or keep monster internals referee-only as today?
4. Roster builder: lock to the canonical four seats for the Tower, or allow arbitrary party size now?

---

*Next step after your approval: implementation plan via the writing-plans skill, Phase A first.*
