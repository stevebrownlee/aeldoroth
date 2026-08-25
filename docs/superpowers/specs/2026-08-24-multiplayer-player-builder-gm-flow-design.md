# Multiplayer Character Creation & GM Flow Redesign

**Date:** 2026-08-24  
**Status:** In Review  
**Domain:** `shards_engine` (`apps/client_web`, `apps/referee`, `apps/wire`, `apps/engine_core`)  
**Decisions Referenced:** Decision 20 (Referee Pipeline), Decision 29 (Hybrid Brain/Ledger Split), Decision 35 (Long-Term Platform Vision & Multi-Tenancy), Decision 52 (Trust Barrier Split), Decision 55 (Play Surface & Console UX), Decision 59 (Starting Place & Character Cards), Decision 60 (1E Race/Class & THAC0), Decision 61 (Level, XP, Spells & Prayers), Decision 62 (2nd-Level Spell Catalogs)

---

## 1. Executive Summary & Goal

Transform the character creation and game session flow from a single-screen 4-slot setup into a true distributed multiplayer tabletop RPG experience:

1. **Role Separation on Home (`/`)**:
   - The **Game Master** launches a session with campaign settings, run ID, and collapsible **Advanced Engine Options** (Seed, Adventure YAML path, Starting Place override, Roster override, rules prefs).
   - **Players** join the game via a direct link (`/runs/:run_id`) or by entering a Run ID in the Player portal.
2. **Dedicated Individual Character Builder (`/runs/:run_id`)**:
   - Each player connects from their own browser/device and builds or chooses their *own* single adventurer.
   - Features 1-click **Pre-gen Archetypes** (*Thistle*, *Bramble*, *Mirage*, *Sister Lyra*) and a complete **AD&D 1E Hero Builder** (Race, Class, Ability Scores, Vitals, Armor, Weapons, Supplies, Arcane Spellbook, Divine Prayers).
   - Existing party members in the session are displayed for context and 1-click rejoining.
   - Clicking **"Enter The Ruined Tower"** places the PC at the campaign starting location (*Mara's Inn in Thornhollow*) and connects the player directly to their live play surface at `/runs/:run_id/:pc_id`.
3. **Real-Time GM Station & Dynamic Spawning (`/runs/:run_id/gm`)**:
   - Game sessions can start immediately even with zero initial PCs.
   - The GM console displays a shareable **Player Join URL** with a 1-click copy affordance.
   - As players create characters, PCs are injected into the running world via `Referee.Run.Session.add_pc/2`, and the GM's Party Vitals rail and round loop update in real time over the spectate wire channel.

---

## 2. Architecture & Information Flow

```
                               ┌─────────────────────────────────────────────────────────────┐
                               │                    Home Page: / (HomeLive)                  │
                               │                                                             │
                               │   ┌───────────────────────────┐ ┌─────────────────────────┐ │
                               │   │     Game Master Panel     │ │    Adventurer Panel     │ │
                               │   │  • Campaign Scenario Info │ │  • Join Game by Run ID  │ │
                               │   │  • Run ID & Seed Setup    │ │  • Active Public Games  │ │
                               │   │  • Advanced Engine Options│ │                         │ │
                               │   │  • [Launch Game as GM]    │ │  • [Join Game]          │ │
                               │   └─────────────┬─────────────┘ └────────────┬────────────┘ │
                               └─────────────────┼────────────────────────────┼──────────────┘
                                                 │                            │
                                                 ▼                            ▼
                                  ┌────────────────────────────┐ ┌──────────────────────────┐
                                  │     GM Console / Screen    │ │   Player Hero Builder    │
                                  │      /runs/:run_id/gm      │ │       /runs/:run_id      │
                                  │                            │ │                          │
                                  │  • Shareable Join Link     │ │  • 1-Click Archetypes    │
                                  │  • Live Party Vitals       │ │  • 1E Custom PC Builder  │
                                  │  • Round Loop & Levers     │ │  • [Enter the Adventure] │
                                  │  • Dungeon Overview & Chat │ └────────────┬─────────────┘
                                  │  • Engine Diagnostics      │              │
                                  └──────────────▲─────────────┘              ▼
                                                 │               ┌──────────────────────────┐
                                                 │ :agent_added  │    Player Play Surface   │
                                                 │ push event    │   /runs/:run_id/:pc_id   │
                                                 │               │                          │
                                                 └───────────────┤  • Narrative Chronicle   │
                                                   (over wire)   │  • Believed Scene & Exits│
                                                                 │  • Action Compose & Wire │
                                                                 └──────────────────────────┘
```

---

## 3. Surface Specifications

### 3.1 Home Screen (`ClientWeb.HomeLive` — `/`)

The landing page provides two distinct cards:

#### A. Game Master Launch Desk
- **Scenario Badge**: Title ("The Ruined Tower"), introductory hook, and starting location ("Mara's Inn in Thornhollow").
- **Quick Launch Input**: Run ID (e.g. `run-7a1b`, auto-generated, customizable).
- **Advanced Engine Options Accordion** (`<details class="advanced">`):
  - **Seed**: Seeded RNG integer for reproducible die rolls (default `42`).
  - **Starting Place Override**: Starting place ID (defaults to `maras_inn`).
  - **Adventure YAML Path**: Path to module YAML (defaults to `the-ruined-tower/ruined_tower.yaml`).
  - **Roster Override**: Optional pipe-delimited raw string for headless test execution.
- **Action Button**: `[Launch Game as GM]` $\rightarrow$ initializes run session and navigates directly to `/runs/:run_id/gm`.

#### B. Adventurer Join Portal
- **Direct Join Form**:
  - Run ID text input.
  - `[Join Adventure]` button $\rightarrow$ navigates to `/runs/:run_id`.
- **Active Games Table**:
  - Lists running sessions with Run ID, Status, Current Tick, Player count, and quick join links (`Join as Player`, `GM Console`).

---

### 3.2 Individual Player Character Builder (`ClientWeb.RunLive` — `/runs/:run_id`)

When visited without a `:pc_id` parameter (or when `pc` is not yet selected):

#### A. Existing Party & Quick Rejoin
- If adventurers already exist in this run:
  - Header: *"Current Party in Thornhollow"*
  - Chips showing existing PCs (Name, Class, Level).
  - Clicking an existing PC seat resumes play as that character (`/runs/:run_id/:pc_id`).
- Button: *"Create New Character"*.

#### B. 1-Click Pre-Gen Archetypes
- Four prominent archetype buttons:
  - ⚔️ **Thistle** (Human Fighter 1 — HP 12, AC 5, Longsword, Chain mail & Shield)
  - 🗡️ **Bramble** (Halfling Thief 1 — HP 8, AC 6, Thieves' tools, Leather armor, Shortsword)
  - ✨ **Mirage** (Gnome Illusionist 1 — HP 4, AC 10, Robes, Spellbook: Color Spray, Phantasmal Force, Read Magic)
  - 🙏 **Sister Lyra** (Human Cleric 1 — HP 8, AC 5, Scale mail & Shield, Prayers: Cure Light Wounds, Bless, Purify Food and Drink)
- Clicking any button instantly populates the full builder form with authentic AD&D 1E starting stats.

#### C. Comprehensive 1E Custom Hero Sheet
- **Identity**:
  - Character Name.
  - 1E Race (`Human`, `Elf`, `Half-Elf`, `Dwarf`, `Gnome`, `Halfling`, `Half-Orc`).
  - 1E Class (`Fighter`, `Paladin`, `Ranger`, `Cleric`, `Druid`, `Magic-User`, `Illusionist`, `Thief`, `Assassin`, `Monk`).
  - Level (1..20) and XP (0..).
- **Combat Vitals & Stats**:
  - HP (max hit points), AC (descending AC 10..2), Damage dice (e.g. `1d8`), INT (1..18).
  - **Dynamic 1E THAC0**: Calculated automatically from Class + Level DMG attack matrices.
- **Equipment & Supplies**:
  - Armor Worn (e.g. `Chain mail & Shield`).
  - Weapons (e.g. `Longsword (1d8), Dagger (1d4)`).
  - Initial Inventory (e.g. `Backpack, 50ft rope, 3 torches, rations, waterskin, 12 gp`).
- **Arcane Spellbook** (*Magic-User & Illusionist only*):
  - Catalog of 1E 1st & 2nd level arcane spells filtered by level.
  - "Add to Spellbook" button and prepared spell chips with remove buttons.
- **Divine Prayers** (*Cleric & Druid only*):
  - Catalog of 1E 1st & 2nd level divine prayers filtered by level.
  - "Add Prayer" button and prepared prayer chips with remove buttons.

#### D. Submission & Launch
- Submit button: `[ Enter The Ruined Tower ]`.
- Slugifies/assigns character ID (e.g. `pc_thistle` or `pc_<name>`), injects PC via `Session.add_pc/2`, and redirects to `/runs/:run_id/:pc_id`.

---

### 3.3 GM Referee Screen (`ClientWeb.SpectateLive` — `/runs/:run_id/gm`)

- **Shareable Player Link Banner**:
  - Displays: `Game Active — Invite Players:` with URL `http://<host>/runs/<run_id>` and a copy button.
- **Dynamic Party Vitals Deck**:
  - Real-time list of connected and living PCs.
  - Displays Name, Race, Class, Level, HP / Max HP, AC, THAC0, Current Location, and Declared Intent for the round.
  - Automatically updates when a new player creates a character.
- **Round Loop Controls**:
  - `[ > END ROUND (Run World) ]` (badged with player readiness).
  - `[ >> Auto-Run until Choice ]` (20-step cruise control).
  - `[ || Pause & Recap ]` / `[ Resume Play ]`.
- **Omniscient Dungeon Overview**:
  - Rooms, monsters (with HP), traps (armed/triggered), secrets (doors/caches), items & treasure values.
- **Story Chronicle & GM Table Chat**:
  - Live narrative stream + GM message broadcast box.
- **Collapsible Diagnostics Drawer**:
  - Active Run Config (YAML path, Seed, Starting Place), LLM Spend report, raw ledger preview, and boundary activation states.

---

## 4. Engine & Wire Protocol Changes

### 4.1 Dynamic PC Addition (`Referee.Run.Session` & `Referee.Run`)
- `Referee.Run.add_pc/2`:
  - Receives `%Referee.Run{}` and `pc_map`.
  - Normalizes PC struct via `Referee.PC.build/1` (defaulting `place_id` to `world.starting_place`).
  - Emits an `:agent_added` world event:
    ```elixir
    %{kind: :agent_added, agent: pc}
    ```
  - Appends to ledger and reduces state via `EngineCore.Fold.fold/2`.
  - Appends `pc_map` to `run.pcs`.
- `Referee.Run.Session.add_pc/2`:
  - GenServer call `{:add_pc, pc_map}`.
  - Updates running state, holds and checkpoints ledger.
  - Returns `{:ok, pc_id}`.

### 4.2 Real-Time Broadcast via Wire Channels
- When `:agent_added` is ledgered:
  - `EngineCore.Ledger.Writer` publishes the event.
  - `Wire.SpectateChannel` receives the event and pushes an updated snapshot (`dungeon`, `awaiting`, `tick`) to `SpectateLive`.
  - GM console updates party vitals and player count immediately.

---

## 5. Verification Plan

1. **Unit & Integration Tests**:
   - `Referee.RunTest` / `Referee.Run.SessionTest`: Test `add_pc/2` on running sessions with empty initial PCs and verify `:agent_added` event ledgering and state fold.
   - `ClientWeb.HomeLiveTest`: Test GM launch with advanced options, player join form navigation, and active runs listing.
   - `ClientWeb.RunLiveTest`: Test single hero builder, 1-click pre-gens, spell/prayer addition/removal, PC submission, and redirect to `/runs/:run_id/:pc_id`.
   - `ClientWeb.SpectateLiveTest`: Test dynamic party card updates and player invite link rendering.
2. **Umbrella Test Suite**:
   - Run `mix test` across all apps (`engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`) ensuring 100% green tests.
3. **Interactive Browser Verification**:
   - Start Phoenix server.
   - Open GM browser window $\rightarrow$ Launch game from Home with Advanced Options $\rightarrow$ Verify redirect to `/runs/:run_id/gm`.
   - Copy player link $\rightarrow$ Open Player browser window $\rightarrow$ Select *Mirage* (Illusionist) pre-gen $\rightarrow$ Customize $\rightarrow$ Click *Enter The Ruined Tower*.
   - Verify player enters `/runs/:run_id/pc_mirage` with narrative chronicle and action compose box.
   - Verify GM window immediately reflects *Mirage* in party vitals with full HP, AC, THAC0, and Thornhollow starting location.
