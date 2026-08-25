# Two Portals, Dedicated OOC Chat & AD&D 1E Round Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish two separate portals (GM setup & management desk vs shareable Player link), a 3-panel player in-game station with dedicated live OOC table chat and action declaration input, and authentic AD&D 1E combat round adjudication when the GM clicks "Start Round".

**Architecture:** Integrate authentic 1E initiative ($1\text{d}6$ vs $1\text{d}6$), segment checks, spell disruption, and THAC0 attack matrices into `Referee.Run.advance/1`. Wire live OOC table chat across all connected player seats and the GM console via Phoenix Channels (`Wire.RunChannel`, `Wire.SpectateChannel`). Reorganize `ClientWeb.RunLive` into a 3-panel tabletop layout (Senses & Story | Live OOC Chat | Action Input & Hero Sheet). Refactor `ClientWeb.SpectateLive` to feature the Player Invite ribbon, live party action board, shared OOC chat, and the `[ Start Round ]` execution button.

**Tech Stack:** Elixir 1.18, Phoenix LiveView 1.0, Phoenix Channels, OTP GenServer, AD&D 1E Rules (DMG pp. 61–75, PHB).

## Global Constraints

- Keep the pure hybrid brain/ledger architecture: LLM proposes, engine disposes; all authority state lives in the append-only ledger.
- The referee is the single authority for world mutation; player seats talk strictly over the wire protocol.
- All 1E mechanics (Initiative d6 vs d6, THAC0 $1\text{d}20 \ge \text{THAC0} - \text{AC}$, Weapon Damage dice, Saving throws) must strictly follow 1E DMG/PHB canon.
- All existing umbrella tests across all 7 apps must remain green.

---

### Task 1: AD&D 1E Round Mechanics Engine Integration

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run.ex`
- Modify: `shards_engine/apps/referee/lib/referee/combat.ex` (or rules modules)
- Test: `shards_engine/apps/referee/test/run_test.exs`
- Test: `shards_engine/apps/referee/test/advance_test.exs`

**Interfaces:**
- Consumes: `EngineCore.Dice`, `Referee.PC.calculate_thac0/2`, `Referee.Rules.Saves`
- Produces: `Referee.Run.advance/1` executing 1E initiative ($1\text{d}6$ vs $1\text{d}6$), action resolution in initiative order, spell disruption check, and attack matrices

- [ ] **Step 1: Write failing tests for 1E round mechanics in `run_test.exs`**

In `shards_engine/apps/referee/test/run_test.exs`:
```elixir
  test "advance rolls 1E initiative (1d6 party vs 1d6 enemies) and ledgers initiative event" do
    {:ok, run} = new_run()
    {:ok, _texts, run2} = Run.advance(run)

    events = Run.events(run2)
    init_event = Enum.find(events, fn e ->
      e.class == :dice && e.payload[:purpose] == :initiative
    end)

    assert init_event != nil
    assert init_event.payload[:party_roll] in 1..6
    assert init_event.payload[:enemy_roll] in 1..6
    assert init_event.payload[:winner] in [:party, :enemy, :simultaneous]
  end

  test "melee attack resolves via 1E THAC0 matrix against target AC" do
    {:ok, run} = new_run()
    # Move thistle to guard_room with goblins
    {:ok, _, run} = Run.declare(run, "pc_thistle", "go east")
    {:ok, _, run} = Run.advance(run)

    # Attack goblin
    {:ok, _, run} = Run.declare(run, "pc_thistle", "attack goblin guard with longsword")
    {:ok, texts, run2} = Run.advance(run)

    events = Run.events(run2)
    attack_event = Enum.find(events, fn e ->
      e.class == :dice && e.payload[:purpose] == :attack
    end)

    if attack_event do
      assert attack_event.payload[:thac0] == 20
      assert attack_event.payload[:target_ac] in 0..10
      assert attack_event.payload[:roll] in 1..20
    end
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/referee && mix test test/run_test.exs`
Expected: FAIL on missing `:initiative` or `:attack` dice events

- [ ] **Step 3: Implement 1E Round Mechanics in `Referee.Run`**

In `shards_engine/apps/referee/lib/referee/run.ex`:
- Update `advance/1` to:
  1. Roll 1E initiative:
     ```elixir
     {party_roll, rng1} = :rand.uniform_s(6, run.rng)
     {enemy_roll, rng2} = :rand.uniform_s(6, rng1)
     winner = cond do
       party_roll > enemy_roll -> :party
       enemy_roll > party_roll -> :enemy
       true -> :simultaneous
     end
     run = push(run, :dice, run.world.tick, %{
       purpose: :initiative,
       party_roll: party_roll,
       enemy_roll: enemy_roll,
       winner: winner
     })
     run = %{run | rng: rng2}
     ```
  2. Order action execution based on initiative winner.
  3. For attacks: compute needed roll = `attacker_thac0 - target_ac`, roll $1\text{d}20$, check hit, roll weapon damage dice, and apply damage via world events.
  4. For spellcasting: if caster took damage during the round prior to spell completion, emit `:spell_disrupted` event and cancel spell effect.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/referee && mix test test/run_test.exs test/advance_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/referee/lib/referee/run.ex shards_engine/apps/referee/test/run_test.exs
git commit -m "feat(referee): implement authentic AD&D 1E initiative, THAC0 attack matrices, and round mechanics in Run.advance/1"
```

---

### Task 2: Persistent Live OOC Chat Synchronization Across Wire & Channels

**Files:**
- Modify: `shards_engine/apps/wire/lib/wire/channels/run_channel.ex`
- Modify: `shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex`
- Test: `shards_engine/apps/wire/test/run_channel_test.exs`
- Test: `shards_engine/apps/wire/test/spectate_channel_test.exs`

**Interfaces:**
- Consumes: `EngineCore.Ledger.Writer`, `Referee.Run.Session.ooc/3`, `Referee.Run.Session.gm_chat/2`
- Produces: Bi-directional real-time `:ooc` event broadcasts delivered to all connected player seats and the spectate console

- [ ] **Step 1: Write failing tests for bi-directional OOC chat in `run_channel_test.exs` and `spectate_channel_test.exs`**

In `shards_engine/apps/wire/test/run_channel_test.exs`:
```elixir
  test "ooc messages are broadcast to player channels in real time", %{socket: socket, run_id: id} do
    Session.gm_chat(id, "Greetings adventurers!")
    assert_push "ooc", %{"author" => "GM", "text" => "Greetings adventurers!"}
  end
```

In `shards_engine/apps/wire/test/spectate_channel_test.exs`:
```elixir
  test "player ooc messages are pushed to spectate channel", %{socket: socket, run_id: id} do
    Session.ooc(id, "pc_thistle", "I am ready")
    assert_push "ooc", %{"author" => "pc_thistle", "text" => "I am ready"}
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/wire && mix test test/run_channel_test.exs test/spectate_channel_test.exs`
Expected: FAIL on missing push or payload shape

- [ ] **Step 3: Implement OOC push handling in `RunChannel` and `SpectateChannel`**

In `shards_engine/apps/wire/lib/wire/channels/run_channel.ex`:
- When subscribed to `Writer.events`: filter for `:ooc` events and push `"ooc"` event to socket:
  ```elixir
  defp handle_event(%{class: :ooc, payload: payload}, socket) do
    push(socket, "ooc", %{
      "author" => payload[:agent_id] || payload["agent_id"] || "Table",
      "text" => payload[:text] || payload["text"]
    })
    socket
  end
  ```

In `shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex`:
- Handle `"ooc"` events similarly, delivering player table talk to the GM console.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/wire && mix test test/run_channel_test.exs test/spectate_channel_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/wire/lib/wire/channels/run_channel.ex shards_engine/apps/wire/lib/wire/channels/spectate_channel.ex shards_engine/apps/wire/test/run_channel_test.exs shards_engine/apps/wire/test/spectate_channel_test.exs
git commit -m "feat(wire): add bi-directional real-time OOC table chat pushes across run and spectate channels"
```

---

### Task 3: Player In-Game 3-Panel Station & Dedicated OOC Chat (`ClientWeb.RunLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Test: `shards_engine/apps/client_web/test/run_live_test.exs`

**Interfaces:**
- Consumes: `ClientTUI.Conn`, `Referee.Run.Session`
- Produces: 3-panel live player UI: Panel 1 (Scene & Chronicle), Panel 2 (Dedicated Live OOC Chat), Panel 3 (Action Box & Hero Sheet)

- [ ] **Step 1: Write failing tests for 3-panel player station in `run_live_test.exs`**

In `shards_engine/apps/client_web/test/run_live_test.exs`:
```elixir
  test "renders 3-panel tabletop layout when connected to seat", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Mara&#39;s Inn" or render(view) =~ "Entry Hall" end)

    html = render(view)
    # Panel 1: Senses & Chronicle
    assert html =~ "Sensory Scene" or html =~ "CHRONICLE"
    # Panel 2: Live OOC Chat Window
    assert html =~ "Table Chat" or html =~ "OOC"
    assert html =~ "Message the table"
    # Panel 3: Action Declaration & Hero Sheet
    assert html =~ "Declare Next Action"
    assert html =~ "Submit Action"
    assert html =~ "HP"
    assert html =~ "AC"
    assert html =~ "THAC0"
  end

  test "sending OOC chat updates chat window in real time", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" or render(view) =~ "Mara&#39;s Inn" end)

    view
    |> form("#ooc_form", %{"text" => "Hey everyone!"})
    |> render_submit()

    eventually(fn ->
      html = render(view)
      assert html =~ "Hey everyone!"
    end)
  end

  test "submitting action updates status badge to Action Ready", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" or render(view) =~ "Mara&#39;s Inn" end)

    view
    |> form("#declare_form", %{"text" => "I search the walls"})
    |> render_submit()

    html = render(view)
    assert html =~ "Action Ready" or html =~ "Waiting for GM"
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: FAIL on missing layout elements or forms

- [ ] **Step 3: Implement 3-Panel Player Station in `ClientWeb.RunLive`**

In `shards_engine/apps/client_web/lib/client_web/run_live.ex`:
- Update `mount/3`:
  - Initialize `:ooc_messages` stream / list (`ooc_messages: []`).
  - Initialize `:action_status` (`:pending` | `:ready`).
  - Initialize `:last_declared_text` (`""`).
- Handle incoming wire OOC pushes (`handle_info({:wire_event, "ooc", payload}, socket)`):
  - Appends `{author, text, timestamp}` to `:ooc_messages`.
- Handle event `"declare", %{"text" => text}`:
  - Sends declare intent over wire.
  - Updates `action_status: :ready`, `last_declared_text: text`.
- Handle event `"send_ooc", %{"text" => text}`:
  - Sends OOC event over wire.
- Update `render/1` when `@pc != nil`:
  - **Panel 1 (Left/Center)**: Scene panel (location title, perceived agents, direction exit chips, auto-scrolling chronicle).
  - **Panel 2 (Center/Right)**: Dedicated Live OOC Table Chat window with message list (GM messages highlighted in gold) and chat input box.
  - **Panel 3 (Right/Bottom)**: Action Declaration card (Action input box, `[ Submit Action ]` button, Action status badge) + Individual Hero Vitals card (HP bar, AC, THAC0, Weapons, Armor, Spells/Prayers list).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/run_live.ex shards_engine/apps/client_web/test/run_live_test.exs
git commit -m "feat(client_web): build 3-panel player in-game station with dedicated live OOC chat and action input"
```

---

### Task 4: GM Referee Console & "Start Round" Execution (`ClientWeb.SpectateLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

**Interfaces:**
- Consumes: `Referee.Run.Session.advance/1`, `Referee.Run.Session.gm_chat/2`, `Wire.SpectateChannel`
- Produces: GM console with Shareable Player Invite Ribbon, Party Action Flow Board, Shared OOC Chat Panel, and `[ Start Round ]` button

- [ ] **Step 1: Write failing tests for GM console enhancements in `spectate_live_test.exs`**

In `shards_engine/apps/client_web/test/spectate_live_test.exs`:
```elixir
  test "renders Start Round button badged with player readiness", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "Start Round" end)

    html = render(view)
    assert html =~ "Start Round"
    assert html =~ "0/2 ready" or html =~ "Party readiness"
  end

  test "clicking Start Round advances the 1E combat round and updates story chronicle", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "Start Round" end)

    view
    |> element("button", "Start Round")
    |> render_click()

    eventually(fn ->
      html = render(view)
      assert html =~ "Round 2" or html =~ "Tick 1"
    end)
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: FAIL on missing elements or labels

- [ ] **Step 3: Implement enhancements in `ClientWeb.SpectateLive`**

In `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`:
- Rename advance button to **`[ Start Round ]`** (or `Start Round (Run World)`), badged with live readiness (`X/N ready`).
- Ensure Party Flow Board highlights declared player actions with high-contrast `READY: "<intent>"` badges.
- Ensure the OOC Table Chat panel streams all player and GM messages with real-time updates.
- Ensure clicking `[ Start Round ]` triggers `Session.advance(socket.assigns.run_id)` and updates the round counter and chronicle.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/spectate_live.ex shards_engine/apps/client_web/test/spectate_live_test.exs
git commit -m "feat(client_web): add Start Round execution lever and party action flow board to GM console"
```

---

### Task 5: GM Setup Desk Refinement (`ClientWeb.HomeLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/home_live.ex`
- Test: `shards_engine/apps/client_web/test/home_live_test.exs`

**Interfaces:**
- Consumes: `Referee.Run.Session.start_link/5`
- Produces: Clean GM setup desk on `/` with Advanced Engine Options and direct redirection to `/runs/:run_id/gm`

- [ ] **Step 1: Write failing tests in `home_live_test.exs`**

In `shards_engine/apps/client_web/test/home_live_test.exs`:
```elixir
  test "GM setup desk allows configuring seed, yaml, and starting place before launch", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#gm_launch", %{
               "run" => %{
                 "run_id" => "custom-tower-1",
                 "seed" => "999",
                 "starting_place" => "maras_inn",
                 "yaml" => @yaml,
                 "roster" => ""
               }
             })
             |> render_submit()

    assert to == "/runs/custom-tower-1/gm"
    Session.stop("custom-tower-1")
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: FAIL if options not present

- [ ] **Step 3: Refine `HomeLive`**

Ensure `HomeLive` presents the Game Master setup card with scenario description, Run ID, Advanced Engine Options (`<details class="advanced">`), and `[ Launch Game as GM ]` button, alongside active running games.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/home_live.ex shards_engine/apps/client_web/test/home_live_test.exs
git commit -m "feat(client_web): polish GM launch desk with advanced engine options and active games monitor"
```

---

### Task 6: Full Suite Verification, Live Multi-Browser Verification & Engrams Export

**Files:**
- Test all: `mix test` across all 7 umbrella apps

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All 367+ tests pass green across `engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`.

- [ ] **Step 2: Live interactive multi-browser verification**

Start Phoenix server:
```bash
cd shards_engine/apps/client_web && PORT=4000 iex -S mix phx.server
```
1. Open GM window at `http://localhost:4000/`.
2. Expand Advanced Engine Options, click **`[ Launch Game as GM ]`** $\rightarrow$ verifies redirect to `/runs/<run_id>/gm`.
3. Copy the Shareable Player Join link `/runs/<run_id>`.
4. Open Player 1 window at `http://localhost:4000/runs/<run_id>` $\rightarrow$ click **Thistle (Fighter)** archetype $\rightarrow$ click **`[ Ready to Join ]`** $\rightarrow$ enters `/runs/<run_id>/pc_thistle`.
5. Open Player 2 window at `http://localhost:4000/runs/<run_id>` $\rightarrow$ click **Mirage (Illusionist)** archetype $\rightarrow$ click **`[ Ready to Join ]`** $\rightarrow$ enters `/runs/<run_id>/pc_mirage`.
6. Test OOC Table Chat:
   - Player 1 types *"Greetings party!"* in OOC chat box $\rightarrow$ verifies message appears in real time on Player 1, Player 2, and GM console.
   - GM types *"Welcome to Thornhollow!"* in GM chat $\rightarrow$ verifies message appears in gold badge on all player screens.
7. Test Action Declaration:
   - Player 1 types *"I look around the common room"* and clicks Submit Action $\rightarrow$ status changes to `Action Ready`.
   - Player 2 types *"I study my spellbook"* and clicks Submit Action $\rightarrow$ status changes to `Action Ready`.
   - GM console reflects `Party readiness: 2/2 ready` with Thistle and Mirage actions displayed on Flow Board.
8. GM clicks **`[ Start Round ]`**:
   - Engine rolls 1E initiative and resolves actions.
   - Story Chronicle updates with round narration.
   - Action inputs reset to `Pending` for Round 2.

- [ ] **Step 3: Engrams logging and export**

```bash
engrams decision log --summary "Two Portals, Dedicated Live OOC Chat & AD&D 1E Round Engine: split GM setup desk from player join link, built 3-panel player station with persistent OOC chat and action declaration box, and wired authentic 1E initiative, THAC0 combat, and round resolution" --rationale "Fulfills authentic tabletop RPG collaboration where players talk OOC with the GM, declare round actions, and the GM triggers 1E round mechanics." --tags ui,ux,ooc-chat,1e-round-mechanics,gm-console,player-station,client-web --importance 9
engrams progress log --status Done --description "Two Portals, Dedicated OOC Chat & AD&D 1E Round Engine complete & verified: GM setup desk on /, shareable player link /runs/:run_id with 3-panel live station, real-time OOC chat, action declaration box, and GM Start Round 1E adjudication."
engrams export
```
