# Dungeon Overview Enrichment: Treasure, Traps & Secret Doors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the Dungeon Overview panel on the GM Console (`ClientWeb.SpectateLive`) to display treasure (with gold values and hidden status), traps/hazards (with DCs and armed/triggered status), and secret/sealed doors alongside enemies and PCs.

**Architecture:**
- `EngineCore.World.Server.dungeon_overview/1` enriches each place with resident `items` (from `world.items`), resident `hazards` (from `world.hazards`), and `connections` with their `sealed` status (from `world.edges`).
- `Wire.SpectateChannel` serializes the enriched dungeon map via `JSONSafe.to_json/1` in join snapshots and `state_sync` pushes.
- `ClientWeb.SpectateLive` renders room cards with dedicated sections and styled badges for Treasure, Traps, Secret Doors, and Monsters.

**Tech Stack:** Elixir 1.18, Phoenix LiveView 1.0, ExUnit.

## Global Constraints
- Preserve decision 52 trust split: player seats remain sensory-isolated (`Slice`), GM console is trusted/omniscient.
- Wire protocol changes are additive only.
- All tests must pass wait-free via `cd shards_engine && mix test`.

---

### Task 1: Backend Dungeon Overview Enrichment (`apps/engine_core`)

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/world/server.ex`
- Test: `shards_engine/apps/engine_core/test/engine_core/world/server_test.exs`

**Interfaces:**
- Produces: `EngineCore.World.Server.dungeon_overview(run_id)` returning:
  ```elixir
  %{
    places: [
      %{
        id: String.t(),
        name: String.t(),
        kind: atom() | String.t(),
        connections: [%{to: String.t(), label: String.t() | nil, sealed: boolean()}],
        agents: [%{id: String.t(), name: String.t(), pc: boolean(), hp: integer(), hp_max: integer(), conditions: list()}],
        items: [%{id: String.t(), name: String.t(), value_gp: integer(), is_hidden: boolean(), holder_id: String.t() | nil}],
        hazards: [%{id: String.t(), kind: atom() | String.t(), dc: integer(), triggered: boolean(), damage: map() | String.t()}]
      }
    ]
  }
  ```

- [ ] **Step 1: Write failing test in `server_test.exs`**

Assert that `dungeon_overview(run_id)` contains `items`, `hazards`, and `connections` with `sealed: true` for secret/sealed doors.

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/engine_core/world/server_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement enrichment in `EngineCore.World.Server.dungeon_overview/1`**

Extract `items` for each place from `world.items`, `hazards` from `world.hazards`, and look up `edge.sealed` in `world.edges`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/engine_core/world/server_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core
git commit -m "feat(engine_core): enrich dungeon_overview with items, hazards, and sealed edges"
```

---

### Task 2: Wire Protocol Documentation & Regression Tests (`apps/wire`)

**Files:**
- Modify: `apps/wire/PROTOCOL.md`
- Test: `shards_engine/apps/wire/test/wire_test.exs`

- [ ] **Step 1: Update `apps/wire/PROTOCOL.md`**

Document the enriched fields (`items`, `hazards`, `sealed` on connections) in the Spectate join reply snapshot.

- [ ] **Step 2: Add test in `wire_test.exs`**

Assert that spectate channel snapshot contains `items`, `hazards`, and `sealed` connections.

- [ ] **Step 3: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/wire/test/wire_test.exs`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add apps/wire/PROTOCOL.md shards_engine/apps/wire/test/wire_test.exs
git commit -m "docs(wire): document enriched dungeon fields in PROTOCOL.md"
```

---

### Task 3: ClientWeb Room Cards UI & Badges (`apps/client_web`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Modify: `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

- [ ] **Step 1: Write failing tests in `spectate_live_test.exs`**

Assert that room cards render items with gold value and `[HIDDEN]` badge, hazards with DC and `[ARMED]` status, and secret/sealed exits with `[SECRET / SEALED]` badge.

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement room card template updates and CSS**

- Render `Treasure` section with `.badge.item` and `.badge.hidden`.
- Render `Traps` section with `.badge.trap` (`[ARMED]` / `[TRIGGERED]`).
- Render `Exits` with `.badge.sealed` for secret/sealed doors.
- Add CSS in `root.html.heex`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web
git commit -m "feat(client_web): render treasure, traps, and secret doors in dungeon overview"
```

---

### Task 4: Umbrella Suite Verification & Browser Smoke

**Files:**
- None (verification phase)

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All tests pass (358+ tests, 0 failures).

- [ ] **Step 2: Browser smoke test on port 4100**

- Start server: `PORT=4100 MIX_ENV=dev mix run --no-halt scripts/web_server.exs`
- Open GM console in browser $\rightarrow$ observe room cards showing treasure (e.g. `Potion of Healing (50 gp)`, `[HIDDEN] Illusionist's Spellbook`), traps (e.g. `[ARMED] Alarm Tripwire`), and secret door to ritual chamber.

- [ ] **Step 3: Log engrams progress and export**

- `engrams decision log ...`
- `engrams progress log --status Done ...`
- `engrams export`
- Commit engrams changes.
