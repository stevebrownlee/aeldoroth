# Task 4 Report: ClientWeb SpectateLive & RunLive UI Redesign & Styling

## Status

**DONE**

## Summary

Implemented the redesigned GM console (`ClientWeb.SpectateLive`) as the 2-column tabletop referee screen, updated player-seat styling parity in `ClientWeb.RunLive`, extended the root layout CSS, and added/updated tests. All `client_web` tests pass.

## Changes

### `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`

- Re-architected the GM console into a clear round-loop view:
  - **Status ribbon**: tick, derived round number, run status (paused/resumed/active), and party readiness counter.
  - **Prominent "End Round" lever**: the primary `advance` button is now styled as the round-advance action.
  - **Flow board**: intent cards now show a seat-dot, PC name, last declared intent or pending prompt, plus HP/max-HP vitals.
  - **Dungeon overview**: new omniscient grid of room cards with resident agents (PC badges / monster badges) and exits.
  - **Right-hand rail**: live story chronicle, GM-to-table chat form, and pause-time dossiers.
  - **Collapsible diagnostics drawer**: LLM spend, boundary-state table, and ledger preview.
- Added wire handling for the new `dungeon` snapshot payload and `state_sync` dungeon push.
- Added `handle_event("gm_chat", ...)` that calls `Referee.Run.Session.gm_chat/2` to ledger a table-wide OOC event from the GM.
- Added helpers: `round_of/1`, `readiness/1`, `card_class/1`, `hp_of/1`, `max_hp_of/1`, `dungeon_places/1`, `status_badge/3`.
- Updated module docs to describe the new layout.

### `shards_engine/apps/client_web/lib/client_web/run_live.ex`

- Updated OOC rendering so messages from `"GM"` are labeled `[GM] <text>` in player chat logs, matching the new GM chat feature.
- Added pause/resume system rows (`The GM pauses the world.`, `The GM resumes play.`) and connection/rejoin system rows for clearer player feedback.

### `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`

- Added Task-4-specific CSS:
  - `.lever-row`, `.status-ribbon .badge`, `.flow-list`, `.flow-card-outer` with `needs/ready/idle` border states, `.seat-dot`, `.pc-name`, `.intent`, `.prompt`, `.vitals`.
  - `.dungeon-grid`, `.room-card`, resident badges (`pc`/`monster`), `.exits`.
  - `.gm-rail .chronicle`, `.compose` chat form.
  - `details.diagnostics`, `.diagnostics-grid`, `.boundary-table`, `.boundary.state-active/inactive`.
- Updated mobile breakpoint to collapse `.diagnostics-grid` to a single column.

### `shards_engine/apps/client_web/test/spectate_live_test.exs`

- Added test: **gm chat form submits a table-wide message** — fills the GM chat form, submits, and asserts the rendered chronicle includes `"Party, hold position."` and `"GM"`.
- Added test: **dungeon overview shows rooms and resident monsters** — mounts the GM console and asserts `"Entry Hall"`, `"Guard Room"`, and `"giant rat"` appear in the dungeon overview.
- Existing tests continue to cover snapshot render, flow board intent display, pause/resume dossiers, and unknown-run error handling.

## Test Results

```
cd shards_engine && mix test apps/client_web/test
==> client_web
Finished in 1.2 seconds (0.1s async, 1.0s sync)
Result: 21 passed
```

Target file:

```
cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs
==> client_web
Finished in 0.6 seconds (0.00s async, 0.6s sync)
Result: 9 passed
```

## Commit

```
69ef0d1 feat(client_web): redesign GM console with clear round loop, dungeon overview, and GM chat
 4 files changed, 237 insertions(+), 47 deletions(-)
```

## Notes

- The `dungeon` payload is delivered by `Wire.SpectateChannel` via the existing `Session.state/1` + `EngineCore.World.Server.dungeon_overview/1` path; no additional backend changes were required.
---

# Task 4 Review Fix Report

## Status

**DONE**

## Summary

Addressed the Task 4 review findings in `ClientWeb.SpectateLive` and `root.html.heex`. GM chat now uses the wire when connected; levers carry the requested labels, subtitles, and readiness badge; party status cards expose location, HP bar, AC/THAC0, and explicit intent badges; `readiness/1` no longer counts PCs waiting on input. All `client_web` tests pass.

## Changes

### `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`

- **GM Chat wire event**: `handle_event("gm_chat", ...)` now tries the wire first when `conn` is a PID, calling `Conn.send_event(conn, "gm_chat", %{"text" => trimmed})`, and falls back to `Session.gm_chat/2` when the connection is nil.
- **Primary lever**: button label changed to `End Round (Run World)`, with subtitle *"Executes declared player actions & NPC AI deliberation for 1 round."* and a readiness badge showing `<ready>/<total> ready`.
- **Secondary lever**: button label changed to `Auto-Run until Choice`, with subtitle *"Steps rounds until a player decision is required."*
- **Pause/Resume levers**: pause button now reads `Pause & Recap`; resume button reads `Resume Play`.
- **Party status cards**:
  - Show character location via `place_name_of/1`.
  - Render an HP bar (`<div class="hpbar">`) and `HP <hp>/<hp_max>` text.
  - Render `AC <ac> | THAC0 <thac0>`.
  - Explicit intent badges:
    - Prompt present: `<span class="badge badge-prompt">NEEDS INPUT</span>` followed by the prompt.
    - Intent present: `<span class="badge badge-ready">READY</span>` followed by the intent text.
    - Neither: `<span class="badge badge-thinking">THINKING</span>` followed by *Waiting for player action...*
- **`readiness/1`**: now counts only PCs with `last_intent != nil && prompt == nil`.
- Added helpers: `place_name_of/1`, `ac_of/1`, `thac0_of/1`, `hp_percent/1`, `to_num/1`.

### `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`

- Added `.lever`, `.lever-subtitle`, and `.lever .badge.readiness` styles.
- Added flow-card badge styles (`.badge-prompt`, `.badge-ready`, `.badge-thinking`), `.location`, `.hpbar`, and `.vitals .stat`.

### `shards_engine/apps/client_web/test/spectate_live_test.exs`

- Updated the intent-display test to assert `READY`, location `Entry Hall`, `HP 12/12`, `AC 5`, `THAC0 20`, and `data-testid="hpbar"`.
- Updated the clarify test to assert `NEEDS INPUT` instead of the old lowercase label.
- Updated the advance test to assert new lever labels and subtitles after the view connects.
- Updated the pause/resume test to assert `Pause & Recap`, `Resume Play`, and `End Round (Run World)`.
- Added a new test verifying the `THINKING` badge and `Waiting for player action...` text before any intent is declared, and the transition to `READY` after declaring.

## Test Results

```
cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs
Running ExUnit with seed: 239844, max_cases: 32
Finished in 0.7 seconds (0.00s async, 0.7s sync)
Result: 10 passed
```

```
cd shards_engine/apps/client_web && mix test
Running ExUnit with seed: 445621, max_cases: 32
Finished in 1.2 seconds (0.1s async, 1.1s sync)
Result: 22 passed
```

## Commit

```
90222e0 Task 4: GM console levers, intent badges, vitals, gm_chat wire event
 3 files changed, 127 insertions(+), 17 deletions(-)
```

---

# Task 4 Exit Keys Fix Report

## Status

**DONE**

## Summary

Fixed the dungeon overview exit rendering in `ClientWeb.SpectateLive`. Exits now display the correct directional label (e.g. `north`, `east`) and target place (e.g. `library`, `guard_room`) by consuming the connection map provided by `EngineCore.World.Server.dungeon_overview/1`, which now includes both `to` and `direction` keys. Added test assertions covering the rendered exits.

## Changes

### `shards_engine/apps/engine_core/lib/engine_core/world/server.ex`

- `dungeon_overview/1` now derives the human-readable edge label from `world.edges` keyed by `{from, to}`.
- Each place's `connections` list emits maps with both `to` (target place id) and `direction` (edge label), and `label` as a fallback alias, so callers no longer need to guess which key names to render.

### `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`

- Replaced the broken `conn["direction"] → conn["target_id"]` template with `<%= exit_label(conn) %> → <%= exit_to(conn) %>`.
- Added `exit_label/1` and `exit_to/1` helpers that accept string or atom keys (`:label`/`"label"`, `:direction`/ `"direction"`, `:to`/`:target_id`/string equivalents) and return safe defaults (`"exit"` / `"?"`).

### `shards_engine/apps/client_web/test/spectate_live_test.exs`

- Extended **"dungeon overview shows rooms and resident monsters"** with assertions:
  - `html =~ "north → library"`
  - `html =~ "east → guard_room"`
  - `html =~ "west → entry_hall"`

## Test Results

```
cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs
==> client_web
Result: 10 passed
```

```
cd shards_engine && mix test apps/engine_core/test/engine_core/world/server_test.exs
==> engine_core
Result: 1 passed
```

## Commit

```
d3341c3 fix(client_web): correct connection keys in dungeon overview exits
 3 files changed, 30 insertions(+), 8 deletions(-)
```
