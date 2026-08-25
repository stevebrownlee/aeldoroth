# GM Console — Active NPC Agents Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real-time "Active NPC Agents" section to the GM console (`ClientWeb.SpectateLive`) that displays tactical vitals, activation trigger context, BDI cognition, and roleplay dossiers for all NPCs awakened by player boundary crossings.

**Architecture:** 
1. `EngineCore.Types.Boundary` and `EngineCore.Fold` track and persist `last_trigger_reason` across `:boundary_wake` events into the authoritative world state.
2. `EngineCore.World.Server.active_agents/1` inspects the cached world snapshot, identifies non-PC agents belonging to awake boundaries or in an alert attention state, and enriches them with waking boundary triggers (`wake_reason`, `wake_tick`), 1E vitals, commitments, and dossier metadata.
3. `Wire.SpectateChannel` broadcasts `active_agents` in the initial join snapshot and on every `state_sync` push.
4. `ClientWeb.SpectateLive` renders a dedicated panel between the Party Flow Board and Dungeon Overview with responsive empty-state banners, animated active-agent pulse chips, combat vitals, pending commitments, and collapsible roleplay dossiers.

**Tech Stack:** Elixir 1.18+, Phoenix LiveView, Phoenix Channels, ExUnit, AD&D 1E rules engine.

## Global Constraints

- **Single Append-Only Ledger**: World state mutations occur strictly via pure reducers (`Fold.fold/2`); queries in `Server` operate on read-only snapshots.
- **Truth Barrier**: Non-PC agents are marked `pc: false`; player sheets and NPC views are cleanly segregated.
- **Dossier Schema**: Uses authored keys `:role`, `:personality`, `:goals`, `:knowledge`, `:rumors` matching `the-ruined-tower/ruined_tower.yaml` and `Agents.Prompt`.
- **JSON Safety**: All wire payloads project through `Wire.JSONSafe` before transmission.
- **Zero Warnings / 100% Green**: All umbrella test suites must pass cleanly with 0 failures.

---

### Task 1: Boundary Trigger Reason Persistence & `Server.active_agents/1`

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/types.ex:85-99`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/fold.ex:120-147`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/world/server.ex:37-44`
- Test: `shards_engine/apps/engine_core/test/world_server_test.exs`
- Test: `shards_engine/apps/engine_core/test/fold_test.exs`

**Interfaces:**
- Consumes: `Types.Boundary`, `Fold.fold(world, events)`, `Server.snapshot(run_id)`
- Produces: `b.last_trigger_reason`, `Server.active_agents(run_id) -> [map()]`

- [ ] **Step 1: Write the failing tests**

Add to `shards_engine/apps/engine_core/test/world_server_test.exs`:

```elixir
  test "active_agents returns enriched maps for awake boundary agents and empty list when dormant", %{id: id, world: world} do
    {:ok, _} = RunSup.ensure_run(id, world)

    # Initial state: all boundaries are dormant
    assert Server.active_agents(id) == []

    # Wake the guard_room_zone boundary with specific reason
    gz = world.boundaries["guard_room_zone"]
    wake_ev = %Ledger.Event{
      seq: 1,
      tick: 5,
      class: :world,
      payload: %{
        kind: :boundary_wake,
        id: "guard_room_zone",
        tick: 5,
        reason: "presence_crossing by pc_thistle",
        bound_agent_ids: gz.bound_agent_ids
      }
    }
    :ok = Writer.append(id, [wake_ev])

    wait_until(fn ->
      active = Server.active_agents(id)
      assert length(active) == 4
      [g1 | _] = Enum.filter(active, &(&1.id == "goblin_guard_1"))
      assert g1.name == "Goblin Guard 1"
      assert g1.tier == 2
      assert g1.place_id == "guard_room"
      assert g1.place_name == "Guard Room"
      assert g1.boundary_id == "guard_room_zone"
      assert g1.wake_tick == 5
      assert g1.wake_reason == "presence_crossing by pc_thistle"
      assert g1.hp == 4
      assert g1.hp_max == 4
      assert g1.ac == 6
      assert g1.thac0 == 20
      assert g1.morale == 7
    end)
  end
```

Add to `shards_engine/apps/engine_core/test/fold_test.exs`:

```elixir
  test "boundary_wake persists last_trigger_reason on boundary struct" do
    b = struct!(Types.Boundary, id: "b1", bound_agent_ids: ["a1"], triggers: [:presence_crossing])
    w = %World{boundaries: %{"b1" => b}, agents: %{"a1" => %Types.Agent{id: "a1", name: "A1", tier: 1, place_id: "p1"}}}
    ev = %Ledger.Event{seq: 1, tick: 10, class: :world, payload: %{kind: :boundary_wake, id: "b1", tick: 10, reason: "noise from p2"}}
    w2 = Fold.fold(w, [ev])
    assert w2.boundaries["b1"].state == :awake
    assert w2.boundaries["b1"].last_trigger_tick == 10
    assert w2.boundaries["b1"].last_trigger_reason == "noise from p2"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine/apps/engine_core && mix test test/world_server_test.exs test/fold_test.exs`
Expected: FAIL with `UndefinedFunctionError` or missing `last_trigger_reason`

- [ ] **Step 3: Implement `last_trigger_reason` in `types.ex`, `fold.ex`, and `server.ex`**

1. In `shards_engine/apps/engine_core/lib/engine_core/types.ex`:
Add `last_trigger_reason: nil` to `Types.Boundary` struct:
```elixir
  defmodule Boundary do
    @moduledoc "Activation boundary: place-scoped or group-scoped (decision 25)."
    @enforce_keys [:id, :bound_agent_ids, :triggers]
    defstruct [
      :id,
      :scope_place_id,
      :scope_group,
      :bound_agent_ids,
      :triggers,
      state: :dormant,
      last_trigger_tick: nil,
      last_trigger_reason: nil,
      wake_on_intensity: 4,
      sleep_after: 40
    ]
  end
```

2. In `shards_engine/apps/engine_core/lib/engine_core/fold.ex`:
Update `:boundary_wake` in `Fold.fold_event/2`:
```elixir
      :boundary_wake ->
        %{
          world
          | boundaries:
              Map.update!(world.boundaries, p.id, fn b ->
                %{b | state: :awake, last_trigger_tick: p.tick, last_trigger_reason: Map.get(p, :reason)}
              end)
        }
        |> wake_agents(p)
```

3. In `shards_engine/apps/engine_core/lib/engine_core/world/server.ex`:
Implement `active_agents/1`:
```elixir
  @doc """
  Active non-PC agents enriched with boundary trigger context, combat vitals,
  commitments, and roleplay dossiers.
  """
  @spec active_agents(String.t()) :: [map()]
  def active_agents(run_id) do
    world = snapshot(run_id)

    awake_boundaries =
      world.boundaries
      |> Map.values()
      |> Enum.filter(&(&1.state == :awake))

    awake_boundary_by_agent_id =
      awake_boundaries
      |> Enum.flat_map(fn b ->
        Enum.map(b.bound_agent_ids || [], fn aid -> {aid, b} end)
      end)
      |> Map.new()

    awake_boundary_by_place_id =
      awake_boundaries
      |> Enum.filter(&(&1.scope_place_id != nil))
      |> Map.new(fn b -> {b.scope_place_id, b} end)

    awake_boundary_by_group =
      awake_boundaries
      |> Enum.filter(&(&1.scope_group != nil))
      |> Map.new(fn b -> {b.scope_group, b} end)

    place_name_by_id =
      Map.new(world.places, fn {pid, p} -> {pid, p.name || pid} end)

    world.agents
    |> Map.values()
    |> Enum.reject(&Map.get(&1, :pc, false))
    |> Enum.filter(fn agent ->
      agent.attention != :dormant or
        Map.has_key?(awake_boundary_by_agent_id, agent.id) or
        (agent.place_id != nil and Map.has_key?(awake_boundary_by_place_id, agent.place_id)) or
        (agent.group != nil and Map.has_key?(awake_boundary_by_group, agent.group))
    end)
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn agent ->
      b =
        awake_boundary_by_agent_id[agent.id] ||
          awake_boundary_by_place_id[agent.place_id] ||
          awake_boundary_by_group[agent.group]

      boundary_id = if b, do: b.id, else: nil
      wake_tick = if b, do: b.last_trigger_tick, else: nil
      wake_reason = if b, do: b.last_trigger_reason || "presence crossing", else: "alert"

      commitments =
        (agent.commitments || [])
        |> Enum.map(fn c ->
          %{
            id: c.id,
            debtor: c.debtor,
            creditor: c.creditor,
            deed: c.deed,
            due: c.due,
            priority: c.priority,
            status: c.status
          }
        end)

      %{
        id: agent.id,
        name: agent.name,
        tier: agent.tier || 1,
        group: agent.group,
        place_id: agent.place_id,
        place_name: Map.get(place_name_by_id, agent.place_id, agent.place_id),
        boundary_id: boundary_id,
        wake_tick: wake_tick,
        wake_reason: wake_reason,
        hp: (agent.body && agent.body.hp) || 1,
        hp_max: (agent.statblock && agent.statblock.hp_max) || 1,
        ac: (agent.statblock && agent.statblock.ac) || 10,
        thac0: (agent.statblock && agent.statblock.thac0) || 20,
        morale: (agent.statblock && agent.statblock.morale) || 7,
        conditions: (agent.body && agent.body.conditions) || [],
        commitments: commitments,
        last_intent: nil,
        dossier: agent.dossier || %{}
      }
    end)
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine/apps/engine_core && mix test test/world_server_test.exs test/fold_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/types.ex shards_engine/apps/engine_core/lib/engine_core/fold.ex shards_engine/apps/engine_core/lib/engine_core/world/server.ex shards_engine/apps/engine_core/test/world_server_test.exs shards_engine/apps/engine_core/test/fold_test.exs
git commit -m "feat(engine_core): persist boundary wake reason and add Server.active_agents/1 query"
```

---

### Task 2: `Wire.SpectateChannel` Active Agents Integration

**Files:**
- Modify: `shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex`
- Test: `shards_engine/apps/wire/test/spectate_channel_test.exs`

**Interfaces:**
- Consumes: `EngineCore.World.Server.active_agents/1`
- Produces: `active_agents` in join snapshot reply and in `"state_sync"` channel push.

- [ ] **Step 1: Write the failing test**

Add to `shards_engine/apps/wire/test/spectate_channel_test.exs`:

```elixir
  test "join snapshot and state_sync include active_agents", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})

    assert {:ok, %{active_agents: active_agents}, _chan} =
             join(socket, "spectate:#{id}", %{})

    assert is_list(active_agents)
    assert active_agents == []

    # Wake Mara's Inn boundary by appending boundary_wake event
    ev = %EngineCore.Ledger.Event{
      seq: 100,
      tick: 1,
      class: :world,
      payload: %{
        kind: :boundary_wake,
        id: "maras_inn_zone",
        tick: 1,
        reason: "presence_crossing by pc_thistle",
        bound_agent_ids: ["mara", "mayor_grevik", "erik_the_shepherd", "anna_mordale"]
      }
    }
    :ok = Writer.append(id, [ev])

    assert_push "state_sync", %{active_agents: synced_active}
    assert length(synced_active) >= 4
    assert Enum.any?(synced_active, &(&1["id"] == "mara" or &1[:id] == "mara"))
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine/apps/wire && mix test test/spectate_channel_test.exs`
Expected: FAIL with `KeyError: key :active_agents not found in pattern`

- [ ] **Step 3: Update `Wire.SpectateChannel`**

Edit `shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex`:
1. In `join/3`: Add `active_agents: JSONSafe.to_json(Server.active_agents(run_id))` to the snapshot map.
2. In `push_state_sync/1`: Add `active_agents: JSONSafe.to_json(Server.active_agents(run_id))` to the payload map.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine/apps/wire && mix test test/spectate_channel_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex shards_engine/apps/wire/test/spectate_channel_test.exs
git commit -m "feat(wire): broadcast active_agents in spectate channel snapshot and state_sync"
```

---

### Task 3: `ClientWeb.SpectateLive` Active NPC Panel UI and CSS

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Modify: `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

**Interfaces:**
- Consumes: `@active_agents` assign from wire channel.
- Produces: `section[data-testid="active-npcs-panel"]` with `.npc-card`, `.empty-state-banner`, vitals, triggers, and roleplay dossier drawer.

- [ ] **Step 1: Write the failing test**

Add to `shards_engine/apps/client_web/test/spectate_live_test.exs`:

```elixir
  test "renders active npcs panel with empty state when dormant and cards when awake", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn -> render(view) =~ "Active NPC Agents" end)
    html = render(view)
    assert html =~ ~s(data-testid="active-npcs-panel")
    assert html =~ ~s(data-testid="active-npcs-empty")
    assert html =~ "All NPC zones dormant"

    # Wake guard room zone
    ev = %EngineCore.Ledger.Event{
      seq: 101,
      tick: 2,
      class: :world,
      payload: %{
        kind: :boundary_wake,
        id: "guard_room_zone",
        tick: 2,
        reason: "presence_crossing by pc_thistle",
        bound_agent_ids: ["goblin_guard_1", "goblin_guard_2", "goblin_guard_3", "goblin_guard_4"]
      }
    }
    :ok = EngineCore.Ledger.Writer.append(id, [ev])

    eventually(fn -> render(view) =~ "Goblin Guard 1" end)
    awake_html = render(view)
    assert awake_html =~ ~s(data-testid="active-npcs-grid")
    assert awake_html =~ "Goblin Guard 1"
    assert awake_html =~ "Tier 2"
    assert awake_html =~ "Guard Room"
    assert awake_html =~ "HP 4/4"
    assert awake_html =~ "AC 6"
    assert awake_html =~ "THAC0 20"
    assert awake_html =~ "presence_crossing by pc_thistle"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: FAIL with missing `"Active NPC Agents"`

- [ ] **Step 3: Update `SpectateLive` assigns, event handlers, template, and CSS**

1. In `SpectateLive.mount/3`: Assign `active_agents: []`.
2. In `SpectateLive.handle_info({:chan_reply, _, :ok, reply}, socket)`: Assign `active_agents: reply["active_agents"] || []`.
3. In `SpectateLive.handle_info({:chan, _, "state_sync", push}, socket)`: Assign `active_agents: push["active_agents"] || socket.assigns.active_agents`.
4. In `SpectateLive.render/1`: Insert `<section class="panel" data-testid="active-npcs-panel">` in `.gm-main` between `flow-board` and `dungeon-overview`.
5. Add helper functions in `SpectateLive`:
   - `tier_label/1`: Maps `1 -> "Reflex"`, `2 -> "Scripted"`, `3 -> "Cognitive"`, `_ -> "Actor"`.
   - `has_dossier?/1`: Checks if dossier map has non-empty role, personality, goals, knowledge, or rumors.
   - `knowledge_or_rumors/1`: Combines knowledge and rumors lists.
6. In `shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex`: Add CSS styles for `.npc-grid`, `.npc-card`, `.activation-strip`, `.pulse-dot`, `.tier-badge`, `.empty-state-banner`, and `.npc-dossier-drawer`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/spectate_live.ex shards_engine/apps/client_web/lib/client_web/layouts/root.html.heex shards_engine/apps/client_web/test/spectate_live_test.exs
git commit -m "feat(client_web): render Active NPC Agents panel in GM console"
```

---

### Task 4: Integration Verification and Full Test Suite

**Files:**
- Test: All apps across the umbrella.

- [ ] **Step 1: Run complete umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All 390+ tests pass with 0 failures and 0 warnings.

- [ ] **Step 2: Commit any final test adjustments**

```bash
git add .
git commit -m "test: verify all umbrella tests pass with GM console active NPC agents"
```
