# GM Console & Tabletop Round Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the GM Console (`ClientWeb.SpectateLive`) into an intuitive, role-grounded Tabletop Referee Screen featuring live player intent tracking, an omniscient dungeon overview, live GM-to-player chat, and a prominent "End Round" button that triggers agent deliberation and world state resolution.

**Architecture:** 
- `EngineCore.World.Server` exposes a cached `dungeon_overview/1` query detailing all rooms, exits, and resident agents (monsters and PCs with HP/conditions).
- `Referee.Run.Session` exposes `gm_chat/2` (ledgering an `:ooc` event with `pc_id: "GM"`) and enriches `awaiting/1` with PC sheet vitals and room names.
- `Wire.SpectateChannel` streams `dungeon` overview and enriched PC cards to the GM console; `Wire.RunChannel` ensures GM table chat broadcasts reach player seats.
- `ClientWeb.SpectateLive` presents a 2-column layout (Party + Dungeon on left, Story Chronicle + GM Chat on right), a primary `End Round` button with readiness badging, and a collapsible Diagnostics Drawer for LLM spend and raw ledger events.

**Tech Stack:** Elixir 1.18 / OTP 27, Phoenix LiveView 1.0, Phoenix Channels, ExUnit.

## Global Constraints
- Preserve decision 52 trust split: player seats are sensory-isolated clients (`Slice`), GM console is trusted/omniscient.
- Wire protocol changes are additive only (Decision 55, `apps/wire/PROTOCOL.md`).
- Ledger is append-only; GM chat uses standard `:ooc` ledger events.
- All tests must pass wait-free via `mix test`.

---

### Task 1: Backend World & Dungeon Overview Queries (`apps/engine_core`)

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/world/server.ex`
- Test: `shards_engine/apps/engine_core/test/engine_core/world/server_test.exs`

**Interfaces:**
- Produces: `EngineCore.World.Server.dungeon_overview(run_id)` returning a map:
  ```elixir
  %{
    places: [
      %{
        id: String.t(),
        name: String.t(),
        kind: atom() | String.t(),
        connections: [%{to: String.t(), label: String.t() | nil}],
        agents: [
          %{
            id: String.t(),
            name: String.t(),
            pc: boolean(),
            hp: integer() | nil,
            hp_max: integer() | nil,
            conditions: [String.t() | atom()]
          }
        ]
      }
    ]
  }
  ```

- [ ] **Step 1: Write the failing test for `dungeon_overview/1`**

In `shards_engine/apps/engine_core/test/engine_core/world/server_test.exs`, add:
```elixir
test "dungeon_overview/1 returns places with resident agents and connections", %{run_id: run_id} do
  overview = Server.dungeon_overview(run_id)
  assert is_list(overview.places)
  assert Enum.any?(overview.places, fn p -> p.id == "room_1" && is_list(p.agents) end)
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/engine_core/world/server_test.exs`
Expected: FAIL with `undefined function Server.dungeon_overview/1`

- [ ] **Step 3: Implement `dungeon_overview/1` in `EngineCore.World.Server`**

```elixir
@doc "Full dungeon overview for referee console: all places, connections, and resident agents."
@spec dungeon_overview(String.t()) :: map()
def dungeon_overview(run_id) do
  world = snapshot(run_id)
  places =
    Enum.map(world.places, fn {place_id, place} ->
      resident_agents =
        world.agents
        |> Map.values()
        |> Enum.filter(&(&1.place_id == place_id))
        |> Enum.map(fn a ->
          %{
            id: a.id,
            name: a.name,
            pc: Map.get(a, :pc, false),
            hp: a.hp,
            hp_max: a.hp_max,
            conditions: a.conditions || []
          }
        end)

      connections =
        Enum.map(place.connections || [], fn
          {to_id, label} -> %{to: to_id, label: label}
          to_id when is_binary(to_id) -> %{to: to_id, label: nil}
          other -> %{to: inspect(other), label: nil}
        end)

      %{
        id: place_id,
        name: place.name || place_id,
        kind: place.kind,
        connections: connections,
        agents: resident_agents
      }
    end)
    |> Enum.sort_by(& &1.id)

  %{places: places}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/engine_core/world/server_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core
git commit -m "feat(engine_core): add Server.dungeon_overview/1 for referee state"
```

---

### Task 2: Referee Session GM Chat & Enriched Awaiting Vitals (`apps/referee`)

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run/session.ex`
- Test: `shards_engine/apps/referee/test/referee/run/session_test.exs`

**Interfaces:**
- Produces:
  - `Referee.Run.Session.gm_chat(run_id, text)` $\rightarrow$ `:ok | {:error, term()}`
  - `Referee.Run.Session.awaiting(run_id)` returning PC maps enriched with `hp`, `hp_max`, `ac`, `thac0`, `place_id`, `place_name`.

- [ ] **Step 1: Write failing tests for `gm_chat/2` and enriched `awaiting/1`**

In `shards_engine/apps/referee/test/referee/run/session_test.exs`, add:
```elixir
test "gm_chat/2 appends an OOC event with agent_id GM", %{run_id: run_id} do
  assert :ok = Session.gm_chat(run_id, "Welcome to the dungeon, adventurers!")
  assert {:ok, rows} = Session.awaiting(run_id)
  first = hd(rows)
  assert Map.has_key?(first, :hp)
  assert Map.has_key?(first, :place_name)
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/referee/test/referee/run/session_test.exs`
Expected: FAIL with `undefined function Session.gm_chat/2`

- [ ] **Step 3: Implement `gm_chat/2` and enriched `awaiting/1` in `Session`**

In `shards_engine/apps/referee/lib/referee/run/session.ex`:
```elixir
@doc "GM table broadcast: ledgers an :ooc event with pc_id: 'GM'."
@spec gm_chat(String.t(), String.t()) :: :ok | {:error, :no_run}
def gm_chat(run_id, text), do: call(run_id, {:gm_chat, text})
```

In `handle_call`:
```elixir
def handle_call({:gm_chat, text}, _from, st) do
  st2 = push(st, :ooc, st.run.world.tick, %{kind: :ooc, pc_id: "GM", text: text})
  {:reply, :ok, flush(st2)}
end
```

In `awaiting_rows(st)`:
Enrich each PC map with `agent.hp`, `agent.hp_max`, `agent.ac`, `agent.thac0`, `agent.place_id`, and `place.name`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/referee/test/referee/run/session_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/referee
git commit -m "feat(referee): add Session.gm_chat/2 and enrich awaiting with PC vitals"
```

---

### Task 3: Wire Protocol Spectate & Run Channels Updates (`apps/wire`)

**Files:**
- Modify: `shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex`
- Modify: `shards_engine/apps/wire/lib/wire/channels/run_channel.ex`
- Modify: `apps/wire/PROTOCOL.md`
- Test: `shards_engine/apps/wire/test/wire_test.exs`

**Interfaces:**
- Consumes: `EngineCore.World.Server.dungeon_overview/1`, `Referee.Run.Session.gm_chat/2`
- Produces:
  - `SpectateChannel` join reply with `dungeon` key containing places and resident agents.
  - `SpectateChannel` handles incoming `"gm_chat"` event with `%{"text" => text}`.
  - `SpectateChannel` state pushes include `dungeon` overview.

- [ ] **Step 1: Write failing tests for wire spectate `dungeon` and `gm_chat`**

In `shards_engine/apps/wire/test/wire_test.exs`, add test asserting join snapshot contains `"dungeon"` and sending `"gm_chat"` broadcasts to spectate and run channels.

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/wire/test/wire_test.exs`
Expected: FAIL

- [ ] **Step 3: Update `SpectateChannel` and `RunChannel`**

In `SpectateChannel`:
- In `join/3`: include `dungeon: JSONSafe.to_json(Server.dungeon_overview(run_id))` in the join snapshot.
- In `handle_in("gm_chat", %{"text" => text}, socket)`: call `Session.gm_chat(run_id(socket), text)` and reply `{:reply, :ok, socket}`.
- In `push_state_sync/1`: push `dungeon: JSONSafe.to_json(Server.dungeon_overview(run_id))`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/wire/test/wire_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/wire apps/wire/PROTOCOL.md
git commit -m "feat(wire): add dungeon overview and gm_chat to spectate channel"
```

---

### Task 4: ClientWeb SpectateLive & RunLive UI Redesign & Styling (`apps/client_web`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Modify: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Modify: `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

- [ ] **Step 1: Write failing tests in `spectate_live_test.exs`**

Assert:
- End Round button has clear label and testid `data-testid="advance"`.
- GM Chat input form exists with `data-testid="gm-chat-form"`.
- Dungeon Overview panel renders room names and resident monsters with HP.
- Player cards render HP bars and declared intents.

- [ ] **Step 2: Run test to verify failure**

Run: `cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement `SpectateLive` Redesign and CSS in `root.html.heex`**

- Refactor template in `SpectateLive`:
  - **Top Bar:** Run ID, Session Status badge, Tick/Round badge.
  - **Control Bar:** Primary bold button `End Round (Run World)` with readiness badge (`[2/2 Ready]`) and subtext; secondary `Auto-Run until Choice`, `Pause & Recap` / `Resume Play`.
  - **Left Column:**
    - `Party Status & Intents`: PC cards with HP bar, location, AC, THAC0, and Intent badges (`[READY: "..."]`, `[NEEDS INPUT: "..."]`, `[THINKING]`).
    - `Dungeon Overview`: Room cards with resident PCs, active monsters with HP, alert status, and exits.
  - **Right Column:**
    - `Story Chronicle`: Immersive stream of narrations, combat rolls, dialogue.
    - `GM Table Chat Form`: Input box sending `"gm_chat"` to all players.
    - `Character Dossiers`: Expandable section when paused.
  - **Bottom Drawer:** Collapsible `<details>` for LLM Token Spend and Raw Ledger sequence events.
- Update `root.html.heex` CSS with `.btn-primary`, `.btn-secondary`, `.party-card`, `.dungeon-card`, `.badge-ready`, `.badge-needs`, `.gm-chat-box`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/client_web/test/spectate_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web
git commit -m "feat(client_web): redesign GM console with clear round loop, dungeon overview, and GM chat"
```

---

### Task 5: Umbrella Test Suite Verification & Browser E2E Smoke

**Files:**
- None (verification phase)

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All tests pass (349+ tests across all 7 apps, 0 failures).

- [ ] **Step 2: Browser Smoke Test on Port 4100**

- Start server: `cd shards_engine && PORT=4100 MIX_ENV=dev mix run --no-halt scripts/web_server.exs`
- Verify Lobby -> Create Run -> Spectate GM console -> Open Player Seat -> Declare Intent -> GM sees Intent -> GM sends Chat -> Player sees Chat -> GM clicks `End Round` -> World resolves.
- Terminate dev server.

- [ ] **Step 3: Log engrams decisions and progress**

- `engrams decision log --summary "Redesigned GM Console around 4-step round loop, omniscient dungeon overview, and GM table chat" ...`
- `engrams progress log --status Done --description "GM console redesign complete and browser-verified"`
- `engrams export`
- Commit engrams changes.
