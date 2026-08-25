# Two Portals, Dedicated OOC Chat & AD&D 1E Round Mechanics Design

**Date:** 2026-08-24  
**Status:** In Review  
**Domain:** `shards_engine` (`apps/client_web`, `apps/referee`, `apps/wire`, `apps/engine_core`)  
**Decisions Referenced:** Decision 20 (Referee Pipeline), Decision 29 (Hybrid Brain/Ledger Split), Decision 35 (Platform Seams & Multi-Tenancy), Decision 52 (Trust Barrier Split), Decision 55 (Play Surface & Console UX), Decision 60 (1E Race/Class & THAC0), Decision 61 (Level, XP, Spells & Prayers), Decision 63 (Multiplayer Character Creation & GM Flow)

---

## 1. Executive Summary & Goal

Establish a true tabletop RPG environment with two dedicated portals, a persistent 3-panel player play surface with dedicated OOC chat and action inputs, and authentic AD&D 1E round adjudication:

1. **Two Separate Portals**:
   - **Portal 1 — Game Master Portal (`/` & `/runs/:run_id/gm`)**: For the Dungeon Master to configure campaign scenarios, set engine options, monitor active games, talk with the table in real-time, and adjudicate rounds.
   - **Portal 2 — Player Portal (`/runs/:run_id` & `/runs/:run_id/:pc_id`)**: The direct link given to players. Players load the link into their browser, build their 1E character (with 1-click archetypes or custom sheet), click `[ Ready to Join ]`, and enter their individualized in-game station.
2. **Dedicated 3-Panel Player In-Game Station**:
   - **Panel 1 — Sensory Scene & Chronicle**: Perceived room description, monsters present in room, exits, and narrative log.
   - **Panel 2 — Dedicated Live OOC Table Chat Window**: Real-time table communication between all connected players and the GM, with gold GM tags and player badges.
   - **Panel 3 — Action Declaration & Character Sheet**: Dedicated *"Declare Next Action"* input box with clear readiness states (`Pending` vs `Action Ready — Waiting for GM to Start Round`), plus live HP, AC, THAC0, gear, and spells/prayers.
3. **Tabletop Round Adjudication & Official AD&D 1E Mechanics**:
   - GM sees all declared player actions in real time on the Party Flow Board.
   - GM can use the shared OOC chat to ask questions, clarify intents, or provide storytelling context before triggering the round.
   - GM clicks **`[ Start Round ]`**.
   - Engine executes authentic AD&D 1E round mechanics:
     - Initiative roll ($1\text{d}6$ Party vs $1\text{d}6$ Monsters, DMG p. 62).
     - Segment-based action ordering, spellcasting duration checks, and disruption risks (DMG p. 61, 65).
     - Attack rolls ($1\text{d}20$ vs Target AC via class/level THAC0 matrices, DMG p. 74) and weapon damage dice.
     - Saving throws (DMG p. 79) for spells and hazards.
     - Authoritative world state update and chronicle broadcast to all screens.

---

## 2. Architecture & Surface Separation

```
  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
  │                               PORTAL 1: GAME MASTER PORTAL                                  │
  │                                                                                             │
  │   1. GM Setup Hub: / (HomeLive)                                                             │
  │      • Scenario summary & Starting location                                                 │
  │      • Run ID input (e.g. web-101)                                                          │
  │      • Collapsible Advanced Engine Options (Seed, YAML Path, Starting Place override)       │
  │      • [ Launch Game as GM ] ────────────────────────────────┐                              │
  │      • Active games monitor                                  │                              │
  │                                                              ▼                              │
  │   2. GM Referee Console: /runs/:run_id/gm (SpectateLive)                                    │
  │      • Shareable Player Invite Link: http://<host>/runs/<run_id> [ 📋 Copy Join Link ]       │
  │      • ⚡ [ START ROUND ] (Badged: 4/4 Players Ready)                                       │
  │      • Party Action Flow Board & Live Vitals                                                │
  │      • 💬 Dedicated Live OOC Table Chat Panel (Broadcasts to all players)                   │
  │      • 🏰 Omniscient Dungeon Overview (monsters with HP, traps, secret doors, treasure)     │
  │      • 📜 Story Chronicle & Diagnostics Drawer (LLM token spend, raw ledger preview)        │
  └─────────────────────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                PORTAL 2: PLAYER PORTAL                                      │
  │                                                                                             │
  │   1. Player Invite Link: /runs/:run_id (RunLive - Character Builder Mode)                   │
  │      • 1-Click Pre-Gen Archetypes (Thistle, Bramble, Mirage, Sister Lyra)                   │
  │      • Complete 1E Hero Sheet (Race, Class, Level, XP, Combat Vitals, Gear, Spells/Prayers)  │
  │      • "Current Party in Thornhollow" chips for 1-click rejoin                              │
  │      • [ Ready to Join (Enter Game) ] ───────────────────────┐                              │
  │                                                              ▼                              │
  │   2. Player In-Game Station: /runs/:run_id/:pc_id (RunLive - Live Play Mode)                │
  │      ┌────────────────────────┬────────────────────────────┬─────────────────────────────┐  │
  │      │ Panel 1: Senses & Story│ Panel 2: Live OOC Chat     │ Panel 3: Action & Character │  │
  │      │ • Perceived Room & Host│ • Dedicated table chat     │ • ⚔️ Declare Next Action    │  │
  │      │ • Direction Exits      │ • GM messages in gold      │ • Status: [ Action Ready ]  │  │
  │      │ • Narrative Chronicle  │ • Player chat input        │ • HP, AC, THAC0, Spells     │  │
  │      └────────────────────────┴────────────────────────────┴─────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Surface Specifications

### 3.1 Portal 1: Game Master Portal

#### A. GM Setup Desk (`ClientWeb.HomeLive` — `/`)
- Dedicated to the Game Master.
- **Scenario Header**: Campaign title (*The Ruined Tower*), hook, and starting location (*Mara's Inn in Thornhollow*).
- **Run ID**: Editable field, auto-generated unique ID (e.g. `web-101`).
- **Advanced Engine Options Accordion** (`<details class="advanced">`):
  - **Seed**: Integer for seeded deterministic die rolls (default `42`).
  - **Starting Place Override**: Place ID string (default `maras_inn`).
  - **Adventure YAML Path**: Path to module YAML.
  - **Roster Override**: Optional pipe-delimited raw PC string for automated setups.
- **`[ Launch Game as GM ]` Button**: Boots the world session and redirects directly to `/runs/:run_id/gm`.
- **Active Games Monitor**: Displays active sessions with current tick, status, and direct GM console links.

#### B. GM Referee Console (`ClientWeb.SpectateLive` — `/runs/:run_id/gm`)
- **Player Invite Ribbon**:
  - Banner: `🎲 Table Active — Invite Players:` with URL `http://<host>/runs/<run_id>` and a 1-click `[ 📋 Copy Join Link ]` button.
- **Party Action & Readiness Flow Board**:
  - Displays each connected player: Character Name, Race, Class, Level, HP / Max HP, AC, THAC0, and Current Room.
  - Shows declared action with state:
    - 🟡 `THINKING: Waiting for player action...`
    - 🟢 `READY: "I draw my longsword and strike goblin #1"`
- **Live OOC Table Chat Panel**:
  - Shared chat window allowing the GM to message all players simultaneously.
  - Styled with distinct `[GM (Dungeon Master)]` badges.
- **`[ START ROUND ]` Execution Button**:
  - High-visibility primary action button badged with readiness count: `[ 3/3 Players Ready ]` (green) or `[ 2/3 Players Ready ]` (amber).
  - Triggers AD&D 1E round resolution across all actors.
- **Omniscient Dungeon Overview**:
  - All rooms, resident monsters with exact HP, armed/triggered traps with DCs, secret doors, and treasure values.

---

### 3.2 Portal 2: Player Portal

#### A. Player Join & Character Builder (`ClientWeb.RunLive` — `/runs/:run_id`)
- Rendered when a player visits `/runs/:run_id` without a character selected.
- **1-Click Pre-Gen Archetypes**:
  - ⚔️ **Thistle** (Human Fighter — HP 12, AC 5, Longsword, Chain mail & Shield)
  - 🗡️ **Bramble** (Halfling Thief — HP 8, AC 6, Thieves' tools, Leather armor, Shortsword)
  - ✨ **Mirage** (Gnome Illusionist — HP 4, AC 10, Robes, Spellbook: Color Spray, Phantasmal Force, Read Magic)
  - 🙏 **Sister Lyra** (Human Cleric — HP 8, AC 5, Scale mail & Shield, Prayers: Cure Light Wounds, Bless, Purify Food and Drink)
- **1E Custom Hero Sheet**:
  - Character Name, 1E Race, 1E Class, Level, XP.
  - HP, Descending AC (10..2), INT, Damage Dice (e.g. `1d8`), Dynamic 1E THAC0 badge.
  - Armor Worn, Weapons, Initial Inventory & Supplies.
  - Arcane Spellbook (Magic-Users & Illusionists) / Divine Prayers (Clerics & Druids) with 1E spell catalog dropdowns and prepared spell chips.
- **`[ Ready to Join (Enter Game) ]` Button**:
  - Registers PC into the active session via `Referee.Run.Session.add_pc/2`.
  - Spawns character at Mara's Inn and smoothly transitions to `/runs/:run_id/:pc_id`.

#### B. Player In-Game 3-Panel Tabletop Station (`ClientWeb.RunLive` — `/runs/:run_id/:pc_id`)
- **Panel 1 — Sensory Scene & Story Chronicle (Left Panel)**:
  - Current location title & atmospheric description.
  - Believed agents present in the room (excludes monsters in other rooms).
  - Direction exit chips (`north`, `south`, `tower`, etc.) that populate or trigger movement.
  - Typed Story Chronicle streaming narrative descriptions, dice rolls, and round outcomes.
- **Panel 2 — Dedicated Live OOC Table Chat Window (Center Panel)**:
  - Persistent chat window showing out-of-character conversation between all players and the GM.
  - Messages display author name, timestamp, and styling (e.g. gold border for GM messages).
  - Chat input box + `[ Send OOC ]` (with <kbd>Enter</kbd> submit).
- **Panel 3 — Action Declaration & Individual Hero Sheet (Right Panel)**:
  - **Declare Next Action Input**:
    - High-contrast text input: *"What does your character do this round?"*
    - `[ Submit Action ]` button.
    - Status indicator:
      - 🟡 `Pending: Please declare your action for Round N`
      - 🟢 `Action Submitted: "I fire shortbow at goblin #2" — Waiting for GM to Start Round`
  - **Individual Character Sheet**:
    - Live HP bar and vitals (HP, Max HP, AC, THAC0, INT, Damage).
    - Equipped Weapons & Armor.
    - Prepared Spells / Prayers list with spell descriptions.
    - Inventory backpack items.

---

## 4. AD&D 1E Round Mechanics Engine Integration

When the GM clicks **`[ Start Round ]`**, the engine orchestrates the round according to authentic 1E rules (DMG pp. 61–75):

```
                       ┌────────────────────────────────────────┐
                       │ GM Clicks [ START ROUND ] (/runs/gm)   │
                       └───────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌────────────────────────────────────────┐
                       │ 1. Initiative Check (DMG p. 62)        │
                       │    Roll 1d6 (Party) vs 1d6 (Monsters)  │
                       │    Higher roll acts first; tie = simul │
                       └───────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌────────────────────────────────────────┐
                       │ 2. Segment & Action Ordering (DMG p.61)│
                       │    • Missiles fire at segment start    │
                       │    • Spells check casting times        │
                       │    • Disruption if caster takes damage │
                       │    • Melee / Movement in init order    │
                       └───────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌────────────────────────────────────────┐
                       │ 3. Attack & Damage Resolution (DMG p74)│
                       │    • 1d20 >= THAC0 - Target AC         │
                       │    • Roll weapon damage dice (e.g. 1d8)│
                       │    • Saving throws for spells/hazards  │
                       └───────────────────┬────────────────────┘
                                           │
                                           ▼
                       ┌────────────────────────────────────────┐
                       │ 4. Authoritative Ledger & Broadcast    │
                       │    • World state reduces (HP, spells)  │
                       │    • Chronicle receives narrative log  │
                       │    • Player action inputs reset to     │
                       │      Pending for Round N+1             │
                       └────────────────────────────────────────┘
```

### 4.1 Detailed Mechanics Breakdown:
1. **Initiative ($1\text{d}6$ vs $1\text{d}6$)**:
   - `Referee.Combat.initiative/2` rolls $1\text{d}6$ for Party and $1\text{d}6$ for Monsters using the run's seeded RNG.
   - Winner determines order of execution. Ties mean simultaneous resolution.
2. **Spell Casting Segments & Disruption (DMG p. 65)**:
   - Spells declare casting time in segments (e.g. *Magic Missile* = 1 segment, *Sleep* = 1 segment, *Color Spray* = 1 segment).
   - If a spellcaster takes damage before their segment resolves, the spell is disrupted and lost from memory for that round.
3. **Attack Rolls & Damage (DMG p. 74)**:
   - Attacker rolls $1\text{d}20$. Target number is determined by attacker's 1E Class/Level THAC0 minus defender's AC.
   - Natural 20 always hits; natural 1 always misses.
   - Damage dice rolled according to weapon type vs size (e.g. Longsword: $1\text{d}8$ vs S/M).
4. **Saving Throws (DMG p. 79)**:
   - Spells, poison, breath weapons, and traps roll $1\text{d}20$ against class/level saving throw targets (`Referee.Rules.Saves`).
5. **State Update & Round Reset**:
   - World state reduces HP and marks dead/incapacitated actors.
   - Chronicle broadcasts formatted narrative to all players and GM.
   - Action inputs on all player stations reset to empty with `Pending` status for Round $N+1$.

---

## 5. Verification Plan

1. **Unit & Integration Tests**:
   - `Referee.RunTest` & `Referee.Run.SessionTest`: Test round advance with 1E initiative rolls, THAC0 combat resolution, spellcasting, and saving throws.
   - `ClientWeb.HomeLiveTest`: Test GM setup desk and advanced options.
   - `ClientWeb.RunLiveTest`: Test 3-panel player layout, OOC chat messaging, action declaration submission with status badge, and character sheet display.
   - `ClientWeb.SpectateLiveTest`: Test GM console with player action flow board, live OOC chat broadcast, and `Start Round` button.
2. **Umbrella Test Suite**:
   - Run `mix test` across all 7 umbrella apps (`engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`) ensuring 100% green tests.
3. **Interactive Browser Live Verification**:
   - Open GM station on port 4000 $\rightarrow$ Launch game $\rightarrow$ Verify Player Invite Link banner.
   - Open 2 separate Player browser windows on player join URL $\rightarrow$ Player 1 creates *Thistle (Fighter)*, Player 2 creates *Mirage (Illusionist)*.
   - Test live OOC chat: Player 1, Player 2, and GM send messages in OOC chat; verify messages appear in real time across all 3 screens.
   - Test Action declaration: Player 1 declares attack, Player 2 declares spell; verify GM screen updates to `2/2 Players Ready`.
   - GM clicks `[ Start Round ]`: verify 1E initiative roll, combat resolution, chronicle story update, HP changes, and action inputs reset for Round 2.
