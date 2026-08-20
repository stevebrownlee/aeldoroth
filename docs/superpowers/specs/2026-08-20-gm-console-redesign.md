# GM Console & Tabletop Round Loop Redesign

**Date:** 2026-08-20  
**Status:** In Review  
**Domain:** `shards_engine` (`apps/client_web`, `apps/wire`, `apps/referee`, `apps/engine_core`)  
**Decisions Referenced:** Decision 20 (Referee Pipeline), Decision 29 (Hybrid Brain/Ledger Split), Decision 52 (Trust Barrier), Decision 55 (Play Surface & Console UX)

---

## 1. Executive Summary & Goal

Transform the GM Console (`ClientWeb.SpectateLive`) from a developer-focused telemetry viewer into an intuitive, role-grounded Tabletop Dungeon Master Station for running AD&D 1E adventures.

The core gameplay cadence is centered around a clear 4-step round loop:
1. **Players Declare:** Players input what they want their characters to do for the current round.
2. **GM Inspects & Communicates:** The GM sees all declared player intents in real time and can chat with players (OOC / table announcements).
3. **GM Clicks "End Round":** The GM clicks a single, prominent **`End Round`** (or **`Run Round`**) button.
4. **Engine Resolves & Updates:** All actor agents (monsters, NPCs, PCs) run their deliberation based on their current beliefs and capabilities; the referee pipeline validates and applies the actions; the authoritative world state updates; and the resulting state is broadcast asymmetrically (omniscient full state to the GM, sensory/position-only slice to each player).

---

## 2. Information Architecture & State Visibility Split

### 2.1 The GM View (Omniscient / Full World State)
The referee screen has complete visibility over the simulation:
- **Party Status & Intents:** Every PC's name, class, current HP / max HP, current dungeon room location, active WebSocket connection status, and declared intent for the round.
- **Dungeon & Threat Overview:** Every room in the dungeon, which party members are present, which monsters/NPCs are present (including monster names, HP, and alert status), and connected exits.
- **Story Chronicle:** Formatted narrative log of all room descriptions, player actions, dice rolls (with roll values, targets, and damage), and table talk.
- **GM Table Chat:** An input box allowing the GM to send table messages and announcements directly to all player screens.
- **Diagnostics Drawer (Collapsible):** Engine-level telemetry (LLM token spend, raw ledger event sequence) tucked into a collapsible drawer so it never clutters gameplay.

### 2.2 The Player View (Strict Sensory Isolation / Position & Senses)
Player seats (`ClientWeb.RunLive` over `Wire.RunChannel`) retain strict truth-barrier isolation (Decision 52):
- Only see their current room and perceived exits/items.
- Only see agents currently perceived in their presence (believed agents).
- Only see their own character sheet and vitals.
- Receive GM table chat and public chronicle narrations, but zero hidden dungeon state, unperceived rooms, or monster stats.

---

## 3. The GM Round Workflow & Controls

```
+---------------------------------------------------------------------------------------------------------+
| THE RUINED TOWER — RUN: run-7a1b                     [ GAME ACTIVE ]               [ ROUND / TICK: 3 ]  |
| Active Combat: Room 3 (Guard Room)                   Party: 2/2 Seated (2/2 Declared)                   |
+---------------------------------------------------------------------------------------------------------+
| [ > END ROUND (Run World) ]      [ >> Auto-Run until Choice ]      [ || Pause & Recap ]      [ Dev v ]  |
| * Executes all declared intents  * Steps rounds until a player     * Freezes actions and     * Show raw |
|   and NPC AI for 1 round           decision prompt occurs            generates AI recaps       ledger   |
+---------------------------------------------------------------------------------------------------------+
```

### 3.1 Referee Controls
1. **`End Round (Run World)` [Primary Action]**:
   - **Visuals:** Large, high-contrast primary button.
   - **Subtext:** *"Executes declared player actions & NPC AI deliberation for 1 round."*
   - **Readiness State:** Badged with `[ 2/2 Players Ready ]` (green) or `[ Waiting on 1 Player ]` (amber). Clicking still allows the GM to force-advance even if an idle player has not declared.
2. **`Auto-Run until Choice` [Secondary Action]**:
   - **What it does:** Runs rounds continuously (up to a 20-round safety cap) until a player receives a clarification prompt (e.g. choosing between targets) or an error occurs.
   - **Subtext:** *"Runs rounds until player input or prompt is required."*
3. **`Pause & Recap` / `Resume Play`**:
   - **When Active:** Pauses player input and generates AI character summary dossiers for table review.
   - **When Paused:** Displays a prominent amber banner: `GAME PAUSED — Player input frozen` and converts button to `Resume Play`.
4. **`Diagnostics Drawer` [Collapsible Toggle]**:
   - Collapses LLM token spend breakdown and raw sequence events (`seq-1..seq-N`) out of the main view.

---

## 4. GM Console Screen Layout

```
+---------------------------------------------------+----------------------------------------------------+
| LEFT COLUMN: Party & Dungeon Overview             | RIGHT COLUMN: Story Chronicle & Table Chat         |
+---------------------------------------------------+----------------------------------------------------+
| 1. PLAYER INTENTS & VITALS                        | 3. STORY CHRONICLE (Narrations, Rolls, Dialogue)   |
|                                                   |                                                    |
| [●] Thistle (Fighter 1)       Loc: Guard Room     | [Tick 3] You push open the heavy oak door. Four    |
| HP: [========--] 9/12 (75%)   AC: 4 | THAC0: 20   | goblins look up from their dice game, drawing      |
| Intent: [ READY ] "Attack nearest goblin"         | rusty shortswords with shrill shrieks!             |
|                                                   |                                                    |
| [●] Bramble (Thief 1)         Loc: Guard Room     | [Combat] Thistle attacks Goblin Guard:             |
| HP: [==========] 6/6 (100%)   AC: 7 | THAC0: 20   | D20 Roll (14 + 1 = 15) vs AC 6 -> HIT! 5 damage.   |
| Intent: [ READY ] "Slip into the shadows"         |                                                    |
|                                                   | [OOC - Bramble]: "I'll try to flank the chief!"    |
| [○] Mirage (Illusionist 1)    (Unclaimed Seat)    |                                                    |
| HP: 4/4 | Intent: [ WAITING FOR PLAYER ]          |                                                    |
+---------------------------------------------------+----------------------------------------------------+
| 2. DUNGEON OVERVIEW (All Rooms & Threats)         | 4. GM TABLE CHAT / ANNOUNCEMENTS                   |
|                                                   |                                                    |
| ▼ Guard Room (Room 3)         [ PARTY IS HERE ]   | [ GM Broadcast / OOC Input Box                   ] |
|   - Status: Active / In Combat                    | [ Send Message to All Players                    ] |
|   - Monsters: 4x Goblin Guard (HP: 4, 3, 5, 4)    |                                                    |
|   - Exits: North (Chief Room), West (Entry Hall)  +----------------------------------------------------+
|                                                   | 5. CHARACTER DOSSIERS (when generated on pause)    |
| ▶ Entry Hall (Room 1)         [ Explored ]        | (Expandable AI character narrative summaries)      |
|   - Status: Calm (No monsters)                    |                                                    |
|                                                   |                                                    |
| ▶ Library (Room 2)            [ Unexplored ]      |                                                    |
|   - Status: Dormant (3x Giant Rats)               |                                                    |
+---------------------------------------------------+----------------------------------------------------+
| 6. COLLAPSIBLE ENGINE DIAGNOSTICS (Spend, Raw Ledger Tails, Boundary Triggers)                         |
+---------------------------------------------------------------------------------------------------------+
```

---

## 5. Technical Implementation & Data Flow

### 5.1 Backend Query & Aggregation
1. **`EngineCore.World.Server`**:
   - Add query `Server.dungeon_overview(run_id)` extracting from the cached `World` fold:
     - Places list with `id`, `name`, `connections` (with labels/directions), and list of resident agent summaries (`%{id, name, pc: bool, hp, hp_max, conditions}`).
2. **`Referee.Run.Session`**:
   - Add `Session.gm_chat(run_id, message)` which ledgers an `:ooc` event with `pc_id: "GM"` and broadcasts to the run's event stream.
   - Retain `Session.advance/1`, `Session.pause/1`, `Session.resume/1`, `Session.awaiting/1`.

### 5.2 Wire Protocol Additions (`apps/wire`)
1. **`Wire.SpectateChannel`**:
   - Join snapshot and state updates include:
     - `dungeon`: structured room and threat overview from `Server.dungeon_overview(run_id)`.
     - `awaiting`: enriched PC list with vitals (`hp`, `hp_max`, `ac`, `place_name`, `seated`, `last_intent`, `prompt`).
   - Channel incoming event: `"gm_chat"` with payload `%{"text" => string}` $\rightarrow$ routes to `Session.gm_chat`.
2. **`Wire.RunChannel`**:
   - Pushes `:ooc` events from the GM down to all player seats as `{:chan, "run:<id>", "ooc", %{"agent_id" => "GM", "text" => message}}`.

### 5.3 Frontend LiveView Updates (`apps/client_web`)
1. **`ClientWeb.SpectateLive`**:
   - Redesign template into two primary columns (Party + Dungeon on left, Story Chronicle + GM Chat on right).
   - Prominent **End Round** button with readiness badge and explanatory subtext.
   - Form for GM Table Chat sending `"gm_chat"` over the channel.
   - Collapsible drawer for LLM spend and raw ledger events.
2. **`ClientWeb.RunLive`**:
   - Displays GM messages in the chronicle with distinctive GM badge (`[GM]: ...`).

---

## 6. Verification & Test Plan

1. **Unit & Integration Tests (`apps/client_web/test/spectate_live_test.exs` & `apps/wire/test/wire_test.exs`)**:
   - Verify spectate channel join snapshot includes `dungeon` overview and enriched PC vitals.
   - Verify clicking `End Round` triggers `Session.advance/1` and updates round counter and room state.
   - Verify sending GM chat broadcasts an `:ooc` event received by both Spectate and Run channels.
   - Verify player seats receive GM messages while maintaining 100% sensory isolation from unperceived dungeon state.
2. **Browser E2E Verification**:
   - Launch server on port 4100.
   - Join GM Console in Tab 1 and Player Seat (Thistle) in Tab 2.
   - Player enters declare ("Look around room").
   - GM console reflects intent under Thistle's card in real-time.
   - GM sends chat ("Watch out for the floor trap") $\rightarrow$ Player sees `[GM]: Watch out for the floor trap`.
   - GM clicks `End Round` $\rightarrow$ Round advances, narrative unfolds, HP and locations update on both screens.
