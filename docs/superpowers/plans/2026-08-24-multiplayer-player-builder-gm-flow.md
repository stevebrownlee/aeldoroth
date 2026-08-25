# Multiplayer Character Creation & GM Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the character creation and game session flow into a distributed multiplayer experience where the GM starts runs with Advanced Engine Options, players connect individually to build/choose their own character, and the party spawns dynamically into the live world.

**Architecture:** Add dynamic PC injection (`add_pc/2`) to `Referee.Run` and `Referee.Run.Session` with `:agent_added` ledger events. Refactor `HomeLive` (`/`) into a split Game Master Launch Desk (with collapsible Advanced Engine Options) and Adventurer Join Portal. Redesign `RunLive` (`/runs/:run_id`) to host a dedicated single-character 1E Hero Builder with 1-click Pre-Gen Archetypes and dynamic joining. Enhance `SpectateLive` (`/runs/:run_id/gm`) with a shareable Player Invite link and real-time party updates.

**Tech Stack:** Elixir 1.18, Phoenix LiveView 1.0, OTP GenServer, Phoenix Channels (`Wire.SpectateChannel`, `Wire.RunChannel`), AD&D 1E Rules Matrices (DMG p. 74).

## Global Constraints

- Never break the pure hybrid brain/ledger architecture: LLM proposes, engine disposes; all authority state lives in the append-only ledger.
- The referee is the single authority for world mutation; player seats talk strictly over the wire protocol.
- All 1E character data (Race, Class, Level, XP, HP, AC, Damage, INT, THAC0, Armor, Weapons, Inventory, Arcane Spellbook, Divine Prayers) must match 1E canon.
- All existing tests across the 7 umbrella apps must remain green.

---

### Task 1: Engine Dynamic PC Spawning (`Referee.Run.add_pc/2` and `Referee.Run.Session.add_pc/2`)

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run.ex`
- Modify: `shards_engine/apps/referee/lib/referee/run/session.ex`
- Test: `shards_engine/apps/referee/test/run_test.exs`
- Test: `shards_engine/apps/referee/test/referee/run/session_test.exs`

**Interfaces:**
- Consumes: `Referee.PC.build/1`, `EngineCore.Fold.fold/2`, `EngineCore.Ledger.Writer`
- Produces: `Referee.Run.add_pc/2` returning `{:ok, pc, run}`, `Referee.Run.Session.add_pc/2` returning `{:ok, pc_id}`

- [ ] **Step 1: Write failing tests for `Run.add_pc/2` and `Session.add_pc/2`**

In `shards_engine/apps/referee/test/run_test.exs`, add:
```elixir
  test "add_pc dynamically injects a new PC with agent_added ledger event and updates world" do
    {:ok, run} = new_run()
    new_pc = %{
      id: "pc_lyra",
      name: "Sister Lyra",
      class: "Cleric",
      race: "Human",
      level: 1,
      hp: 8,
      ac: 5,
      thac0: 20,
      damage: "1d6"
    }

    assert {:ok, pc, run2} = Run.add_pc(run, new_pc)
    assert pc.id == "pc_lyra"
    assert run2.world.agents["pc_lyra"]
    assert run2.world.agents["pc_lyra"].name == "Sister Lyra"
    assert Enum.any?(run2.pcs, &(&1.id == "pc_lyra"))

    events = Run.events(run2)
    assert Enum.any?(events, fn e ->
      e.class == :world && e.payload[:kind] == :agent_added && e.payload[:agent].id == "pc_lyra"
    end)
  end
```

In `shards_engine/apps/referee/test/referee/run/session_test.exs`, add:
```elixir
  test "add_pc dynamically registers PC into live session" do
    {:ok, session} = Session.start_link(@run_id, @yaml, @seed, [])
    new_pc = %{
      id: "pc_bramble",
      name: "Bramble",
      class: "Thief",
      race: "Halfling",
      level: 1,
      hp: 8,
      ac: 6,
      thac0: 19,
      damage: "1d6"
    }

    assert {:ok, "pc_bramble"} = Session.add_pc(@run_id, new_pc)
    assert [%{id: "pc_bramble", name: "Bramble"}] = Session.roster(@run_id)
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/referee && mix test test/run_test.exs test/referee/run/session_test.exs`
Expected: FAIL with `undefined function add_pc/2`

- [ ] **Step 3: Implement `Referee.Run.add_pc/2` and `Referee.Run.Session.add_pc/2`**

In `shards_engine/apps/referee/lib/referee/run.ex`:
```elixir
  @doc """
  Inject a new PC into an existing run dynamically (e.g. when a player connects
  and completes character creation). Appends an `:agent_added` event to the ledger
  and reduces the world state.
  """
  @spec add_pc(t(), map()) :: {:ok, map(), t()}
  def add_pc(%__MODULE__{} = run, pc_map) do
    place_id = pc_map[:place_id] || pc_map["place_id"] || run.world.starting_place || "entry_hall"
    pc_map_normalized = Map.put(pc_map, :place_id, place_id)
    pc = PC.build(pc_map_normalized)

    run = push(run, :world, run.world.tick, %{kind: :agent_added, agent: pc})
    [event | _] = run.events
    world2 = Fold.fold(run.world, [event])
    pcs2 = (run.pcs || []) ++ [pc_map]

    {:ok, pc, %{run | world: world2, pcs: pcs2}}
  end
```

In `shards_engine/apps/referee/lib/referee/run/session.ex`:
```elixir
  @doc "Dynamically add a PC to the running session."
  @spec add_pc(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def add_pc(run_id, pc_map) do
    call(run_id, {:add_pc, pc_map})
  end
```

And in `handle_call` in `Session`:
```elixir
  def handle_call({:add_pc, pc_map}, _from, %{status: status} = st) when status in [:running, :paused] do
    case Run.add_pc(st.run, pc_map) do
      {:ok, pc, run2} ->
        st2 = hold(st, run2) |> checkpoint()
        {:reply, {:ok, pc.id}, st2}

      {:error, reason} ->
        {:reply, {:error, reason}, st}
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/referee && mix test test/run_test.exs test/referee/run/session_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/referee/lib/referee/run.ex shards_engine/apps/referee/lib/referee/run/session.ex shards_engine/apps/referee/test/run_test.exs shards_engine/apps/referee/test/referee/run/session_test.exs
git commit -m "feat(referee): add dynamic PC spawning via Run.add_pc/2 and Session.add_pc/2"
```

---

### Task 2: Home Page Redesign (`ClientWeb.HomeLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/home_live.ex`
- Test: `shards_engine/apps/client_web/test/home_live_test.exs`

**Interfaces:**
- Consumes: `Referee.Run.Session.start_link/5`, `EngineCore.Loader`
- Produces: Split landing screen: Game Master Launch Desk (with Advanced Engine Options) redirecting to `/runs/:run_id/gm`, and Adventurer Portal redirecting to `/runs/:run_id`

- [ ] **Step 1: Write failing tests for HomeLive split GM and Player flows**

In `shards_engine/apps/client_web/test/home_live_test.exs`:
```elixir
  test "renders split Game Master and Adventurer portals with advanced engine options", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "The Ruined Tower"
    assert html =~ "Game Master Launch Desk"
    assert html =~ "Launch Game as GM"
    assert html =~ "Advanced Engine Options"
    assert html =~ "Adventurer Portal"
    assert html =~ "Join Adventure"
    assert html =~ "Active runs"
  end

  test "GM launch creates run with advanced engine options and redirects to GM console", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#gm_launch", %{
               "run" => %{
                 "run_id" => "custom-gm-run",
                 "seed" => "1234",
                 "starting_place" => "entry_hall",
                 "yaml" => @yaml,
                 "roster" => ""
               }
             })
             |> render_submit()

    assert to == "/runs/custom-gm-run/gm"
    assert Session.whereis("custom-gm-run") != nil
    Session.stop("custom-gm-run")
  end

  test "Player join form navigates to /runs/:run_id", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#player_join", %{"join" => %{"run_id" => "web-test-join"}})
             |> render_submit()

    assert to == "/runs/web-test-join"
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: FAIL with missing forms or layout elements

- [ ] **Step 3: Implement `ClientWeb.HomeLive`**

Refactor `shards_engine/apps/client_web/lib/client_web/home_live.ex`:
- Update `mount/3` to initialize GM launch assigns (`run_id`, `seed`, `yaml`, `starting_place`, `roster`, `runs: list_runs()`).
- Handle event `"gm_launch", %{"run" => run_params}`:
  - Parses `seed`, `yaml`, `starting_place`, and optional `roster`.
  - Parses `pcs` from roster string if given, else `[]`.
  - Calls `Session.start_link(run_id, yaml, seed, pcs)`.
  - Calls `push_navigate(socket, to: "/runs/#{run_id}/gm")`.
- Handle event `"player_join", %{"join" => %{"run_id" => run_id}}`:
  - Calls `push_navigate(socket, to: "/runs/#{String.trim(run_id)}")`.
- Update `render/1` to display two clean columns:
  - Left: **Game Master Launch Desk** (Scenario card, Run ID, Advanced Engine Options accordion with Seed, YAML path, Starting Place, and Roster override, plus `[ Launch Game as GM ]` button).
  - Right: **Adventurer Portal & Active Games** (Join by Run ID form with `[ Join Adventure ]` button, and Active Runs table with `Join as Player` and `GM Console` links).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/home_live.ex shards_engine/apps/client_web/test/home_live_test.exs
git commit -m "feat(client_web): redesign home page with GM launch desk and player join portal"
```

---

### Task 3: Individual Player Character Builder (`ClientWeb.RunLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Test: `shards_engine/apps/client_web/test/run_live_test.exs`

**Interfaces:**
- Consumes: `Referee.Run.Session.add_pc/2`, `Referee.Run.Session.roster/1`, `Referee.Run.Session.whereis/1`
- Produces: Single-character 1E Hero Builder on `/runs/:run_id` with 1-click archetypes and dynamic PC creation

- [ ] **Step 1: Write failing tests for single-character hero builder in `RunLiveTest`**

In `shards_engine/apps/client_web/test/run_live_test.exs`:
```elixir
  test "renders single-hero character builder and 1-click archetypes when no seat chosen", %{
    conn: conn,
    run_id: id
  } do
    {:ok, _view, html} = live(conn, "/runs/#{id}")

    assert html =~ "Build Your Adventurer"
    assert html =~ "1-Click Archetypes"
    assert html =~ "Thistle (Fighter)"
    assert html =~ "Bramble (Thief)"
    assert html =~ "Mirage (Illusionist)"
    assert html =~ "Sister Lyra (Cleric)"
    assert html =~ "Enter The Ruined Tower"
    assert html =~ "Current Party in Thornhollow"
  end

  test "picking an archetype pre-populates hero sheet with authentic 1E stats and spells", %{
    conn: conn,
    run_id: id
  } do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    mirage_html =
      view
      |> element("button", "Mirage (Illusionist)")
      |> render_click()

    assert mirage_html =~ "value=\"Mirage\""
    assert mirage_html =~ "Gnome"
    assert mirage_html =~ "Illusionist"
    assert mirage_html =~ "Arcane Spellbook"
    assert mirage_html =~ "Color Spray"
  end

  test "submitting hero builder creates PC dynamically and redirects to /runs/:run_id/:pc_id", %{
    conn: conn,
    run_id: id
  } do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#hero_builder", %{
               "hero" => %{
                 "name" => "Valen",
                 "race" => "Elf",
                 "class" => "Fighter",
                 "level" => "1",
                 "xp" => "0",
                 "hp" => "10",
                 "ac" => "5",
                 "damage" => "1d8",
                 "int" => "14",
                 "armor" => "Chain mail",
                 "weapons" => "Longsword",
                 "inventory" => "Backpack, rope, torches",
                 "spells" => "",
                 "prayers" => ""
               }
             })
             |> render_submit()

    assert to =~ "/runs/#{id}/pc_valen"
    assert Enum.any?(Session.roster(id), &(&1.name == "Valen"))
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement single-character Hero Builder in `ClientWeb.RunLive`**

In `shards_engine/apps/client_web/lib/client_web/run_live.ex`:
- Define `@canonical_archetypes`, `@classes`, `@races`, spell and prayer catalogs, and `thac0_matrix`.
- In `mount/3`:
  - When `pc` is `nil` (or not present):
    - Check if run exists via `Session.whereis(run_id)`.
    - Fetch `@existing_pcs` from `Session.roster(run_id)`.
    - Assign default `@hero` struct:
      ```elixir
      %{
        name: "",
        race: "Human",
        class: "Fighter",
        level: "1",
        xp: "0",
        hp: "10",
        ac: "5",
        damage: "1d8",
        int: "10",
        armor: "Chain mail & Shield",
        weapons: "Longsword (1d8), Dagger (1d4)",
        inventory: "Backpack, 50ft rope, 3 torches, rations, waterskin, 10 gp",
        spells_list: [],
        prayers_list: [],
        chosen_spell: "",
        chosen_prayer: ""
      }
      ```
- Implement event handlers:
  - `"pick_archetype", %{"name" => name}`: loads archetype into `@hero`.
  - `"hero_change", %{"hero" => params}`: updates `@hero` fields.
  - `"add_spell"`, `"remove_spell"`, `"add_prayer"`, `"remove_prayer"`: updates spell/prayer lists.
  - `"create_hero", %{"hero" => params}`:
    - Normalizes PC map with unique ID `pc_<slug>`.
    - Calls `Session.add_pc(socket.assigns.run_id, pc_map)`.
    - Redirects with `push_navigate(socket, to: "/runs/#{socket.assigns.run_id}/#{pc_id}")`.
- Update `render/1`:
  - When `@pc == nil`: render Hero Builder template (Archetype buttons, 1E Hero Sheet, Spellbook / Prayers, Rejoin chips for `@existing_pcs`, Submit button).
  - When `@pc != nil`: render live play surface (scene, chronicle, action compose, party rail).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/run_live.ex shards_engine/apps/client_web/test/run_live_test.exs
git commit -m "feat(client_web): add single-character 1E Hero Builder with 1-click archetypes on RunLive"
```

---

### Task 4: GM Screen Enhancements (`ClientWeb.SpectateLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

**Interfaces:**
- Consumes: `Wire.SpectateChannel`, `Referee.Run.Session`
- Produces: Shareable Player Invite banner and live party vitals updating dynamically on `:agent_added` events

- [ ] **Step 1: Write failing tests for SpectateLive invite banner and live party updates**

In `shards_engine/apps/client_web/test/spectate_live_test.exs`:
```elixir
  test "renders shareable player invite link banner", %{conn: conn, run_id: id} do
    {:ok, _view, html} = live(conn, "/runs/#{id}/gm")
    assert html =~ "Invite Players:"
    assert html =~ "/runs/#{id}"
    assert html =~ "Copy Join Link"
  end

  test "dynamically updates party vitals when a new PC is added", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    new_pc = %{
      id: "pc_mirage",
      name: "Mirage",
      class: "Illusionist",
      race: "Gnome",
      level: 1,
      hp: 4,
      ac: 10,
      thac0: 20,
      damage: "1d4"
    }

    {:ok, "pc_mirage"} = Session.add_pc(id, new_pc)

    eventually(fn ->
      html = render(view)
      assert html =~ "Mirage"
      assert html =~ "Illusionist"
    end)
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement enhancements in `ClientWeb.SpectateLive`**

In `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`:
- In `render/1`:
  - Add top invite ribbon:
    ```heex
    <div class="player-invite-ribbon panel">
      <span>🎲 <strong>Table Active:</strong> Share player link:</span>
      <code class="invite-link-code">/runs/<%= @run_id %></code>
      <button type="button" class="btn-copy-link" onclick={"navigator.clipboard.writeText(window.location.origin + '/runs/#{@run_id}')"}>
        📋 Copy Join Link
      </button>
    </div>
    ```
  - Ensure the Party Vitals deck dynamically renders all PCs received in state sync and updates smoothly when new agents join.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/spectate_live.ex shards_engine/apps/client_web/test/spectate_live_test.exs
git commit -m "feat(client_web): add player invite ribbon and dynamic party vitals to GM console"
```

---

### Task 5: Full Umbrella Suite & Visual Browser Verification

**Files:**
- Test all: `mix test` across all 7 umbrella apps

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All 365+ tests green across all 7 apps (`engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`).

- [ ] **Step 2: Live interactive browser verification**

Start Phoenix server:
```bash
cd shards_engine/apps/client_web && iex -S mix phx.server
```
Perform visual verification:
1. Open GM browser at `http://localhost:4000/`.
2. Inspect Game Master Launch Desk, expand Advanced Engine Options, click **"Launch Game as GM"**.
3. Verify redirect to `/runs/<run_id>/gm`.
4. Copy the Player Invite link `/runs/<run_id>`.
5. Open Player browser window at `http://localhost:4000/runs/<run_id>`.
6. Click **"Mirage (Illusionist)"** pre-gen button. Verify sheet populates with 1E stats and Arcane Spellbook.
7. Click **"Enter The Ruined Tower"**. Verify player connects to `/runs/<run_id>/pc_mirage` with narrative chronicle and compose box.
8. Switch to GM window: verify *Mirage* appears immediately in Party Vitals with full stats and location.

- [ ] **Step 3: Final commit and status update**

Log session decision and progress to engrams:
```bash
engrams decision log --summary "Multiplayer Character Creation & GM Flow: separated GM launch desk with Advanced Engine Options from individual Player Hero Builder with 1-click archetypes and dynamic PC spawning" --rationale "Empowers each player to build their own hero from their own device while giving the GM full referee authority and shareable invite links." --tags ui,ux,multiplayer,gm-console,hero-builder,client-web --importance 9
engrams progress log --status Done --description "Multiplayer Character Creation & GM Flow complete & verified: GM launch desk with Advanced Engine Options, individual Player Hero Builder with 1-click archetypes on /runs/:run_id, and dynamic PC spawning via Session.add_pc/2. All tests green."
engrams export
```
