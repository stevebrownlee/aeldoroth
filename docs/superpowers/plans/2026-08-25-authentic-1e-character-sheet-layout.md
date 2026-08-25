# Authentic AD&D 1E Character Sheet Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replicate the spatial layout, typography, sub-attributes, and combat matrices of the traditional TSR AD&D 1E Player Character Record sheets (from the 4 provided reference images) across the single-hero character builder and live play sheet modal.

**Architecture:** Create `Referee.Rules.SheetTables` providing official 1E sub-ability matrices ($S, I, W, D, C, CH, CM$), Saving Throw tables, THAC0 attack matrices (AC 10..2), Turning Undead tables, and Thieving Skills % tables. Render the complete authentic 1E Character Sheet layout in `ClientWeb.RunLive` (both on `/runs/:run_id` character creation and inside a 1-click modal during live play `/runs/:run_id/:pc_id`), with dynamic class-specific bottom sections (Cleric Turning, Fighter Mount, Magic-User Spells, Thief Skills %).

**Tech Stack:** Elixir 1.18, Phoenix LiveView 1.0, CSS Grid / Flexbox, AD&D 1E Rules (PHB pp. 9–30, DMG pp. 61–79).

## Global Constraints

- Keep the pure hybrid brain/ledger architecture: LLM proposes, engine disposes; all authority state in append-only ledger.
- All 1E tables (Abilities, Saves, THAC0 matrix, Turning Undead, Thieving Skills) must match authentic TSR AD&D 1E canon.
- The player character sheet layout must faithfully reflect the spatial structure and fields of the 4 reference images.
- All existing tests across the 7 umbrella apps must remain green.

---

### Task 1: 1E Sub-Attributes, Saving Throws & Matrices Rules Module (`Referee.Rules.SheetTables`)

**Files:**
- Create: `shards_engine/apps/referee/lib/referee/rules/sheet_tables.ex`
- Test: `shards_engine/apps/referee/test/rules/sheet_tables_test.exs`

**Interfaces:**
- Produces:
  - `SheetTables.ability_substats(ability, score, class)` returning map of sub-stats
  - `SheetTables.saving_throws(class, level)` returning `%{poison: n, petrification: n, wand: n, breath: n, spell: n}`
  - `SheetTables.to_hit_matrix(class, level)` returning map `%{10 => n, 9 => n, ..., 2 => n}`
  - `SheetTables.turning_table(level)` returning map of undead types to target rolls
  - `SheetTables.thieving_skills(class, level, race, dex)` returning map of 8 thieving skill percentages

- [ ] **Step 1: Write failing tests for `SheetTables` in `sheet_tables_test.exs`**

In `shards_engine/apps/referee/test/rules/sheet_tables_test.exs`:
```elixir
defmodule Referee.Rules.SheetTablesTest do
  use ExUnit.Case, async: true
  alias Referee.Rules.SheetTables

  test "calculates strength sub-stats including exceptional strength" do
    s17 = SheetTables.strength_substats(17, nil)
    assert s17.hit_adj == "+1"
    assert s17.dam_adj == "+1"
    assert s17.open_doors == "1-3"
    assert s17.bend_bars == "13%"

    s18_50 = SheetTables.strength_substats(18, 50)
    assert s18_50.hit_adj == "+1"
    assert s18_50.dam_adj == "+3"
    assert s18_50.bend_bars == "20%"
  end

  test "calculates 1E saving throws by class and level" do
    fighter_1 = SheetTables.saving_throws("Fighter", 1)
    assert fighter_1.poison == 14
    assert fighter_1.petrification == 15
    assert fighter_1.wand == 16
    assert fighter_1.breath == 17
    assert fighter_1.spell == 17

    cleric_1 = SheetTables.saving_throws("Cleric", 1)
    assert cleric_1.poison == 10
    assert cleric_1.petrification == 13
    assert cleric_1.wand == 14
    assert cleric_1.breath == 16
    assert cleric_1.spell == 15
  end

  test "calculates to-hit matrix for AC 10..2" do
    matrix = SheetTables.to_hit_matrix("Fighter", 1)
    assert matrix[10] == 10
    assert matrix[5] == 15
    assert matrix[2] == 18
  end

  test "calculates thief skills percentages" do
    thief_1 = SheetTables.thieving_skills("Thief", 1, "Human", 15)
    assert thief_1.pick_pockets == "30%"
    assert thief_1.open_locks == "25%"
    assert thief_1.find_traps == "20%"
    assert thief_1.move_silently == "15%"
    assert thief_1.hide_in_shadows == "10%"
    assert thief_1.hear_noise == "10%"
    assert thief_1.climb_walls == "85%"
    assert thief_1.read_languages == "—"
  end

  test "returns turning undead table for level 1 cleric" do
    turning = SheetTables.turning_table(1)
    assert turning.skeleton == "10"
    assert turning.zombie == "13"
    assert turning.ghoul == "16"
    assert turning.shadow == "19"
    assert turning.wight == "20"
    assert turning.ghast == "—"
  end
end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/referee && mix test test/rules/sheet_tables_test.exs`
Expected: FAIL with `undefined module Referee.Rules.SheetTables`

- [ ] **Step 3: Implement `Referee.Rules.SheetTables`**

Create `shards_engine/apps/referee/lib/referee/rules/sheet_tables.ex` with full AD&D 1E tables:
- `strength_substats/2` (PHB p. 9)
- `intelligence_substats/1` (PHB p. 10)
- `wisdom_substats/1` (PHB p. 11)
- `dexterity_substats/1` (PHB p. 11)
- `constitution_substats/2` (PHB p. 12)
- `charisma_substats/1` (PHB p. 13)
- `comeliness_substats/1` (Unearthed Arcana p. 6)
- `saving_throws/2` (DMG p. 79)
- `to_hit_matrix/2` (DMG p. 74)
- `turning_table/1` (DMG p. 65)
- `thieving_skills/4` (PHB p. 28)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/referee && mix test test/rules/sheet_tables_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/referee/lib/referee/rules/sheet_tables.ex shards_engine/apps/referee/test/rules/sheet_tables_test.exs
git commit -m "feat(referee): implement authentic 1E ability sub-stats, saving throws, THAC0 matrix, turning, and thief skill tables"
```

---

### Task 2: Authentic 1E Character Sheet Layout in `ClientWeb.RunLive`

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Test: `shards_engine/apps/client_web/test/run_live_test.exs`

**Interfaces:**
- Consumes: `Referee.Rules.SheetTables`
- Produces: Complete authentic 1E Player Character Record sheet with Zones 1–6 rendered on `/runs/:run_id`

- [ ] **Step 1: Write failing tests in `run_live_test.exs` for authentic 1E sheet structure**

In `shards_engine/apps/client_web/test/run_live_test.exs`:
```elixir
  test "character builder renders authentic 1E Player Character Record layout", %{conn: conn, run_id: id} do
    {:ok, _view, html} = live(conn, "/runs/#{id}")

    # Zone 1: Header & Identity
    assert html =~ "Player Character Record"
    assert html =~ "PATRON DEITY"
    assert html =~ "PLACE OF ORIGIN"
    assert html =~ "MOVE BASE"

    # Zone 2: Abilities Sub-Table Matrix
    assert html =~ "Hit Adj"
    assert html =~ "Open Doors"
    assert html =~ "Bend Bars"
    assert html =~ "% Know"
    assert html =~ "System Shock"

    # Zone 3: Saving Throws (5 bubbles)
    assert html =~ "Paralyzation"
    assert html =~ "Petrification"
    assert html =~ "Rod, Staff"
    assert html =~ "Breath Weapon"
    assert html =~ "Spells"

    # Zone 4: Combat Vitals & AC
    assert html =~ "Shieldless AC"
    assert html =~ "Rear AC"
    assert html =~ "Weapons of Proficiency"

    # Zone 5: Weapons To-Hit Matrix Table
    assert html =~ "ADJUSTED TO HIT ARMOR CLASS"
    assert html =~ "DAMAGE VS SIZE"
    assert html =~ "PUMMELING"
    assert html =~ "GRAPPLING"
  end

  test "renders dynamic class-specific bottom section based on selected class", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    # Fighter selected by default -> Warrior Record (Mount, # Attacks)
    html = render(view)
    assert html =~ "WARRIOR RECORD"
    assert html =~ "MOUNT"

    # Select Thief -> Rogue Record & Thieving Skills % Table
    thief_html =
      view
      |> form("#hero_builder", %{"hero" => %{"class" => "Thief", "race" => "Halfling", "level" => "1"}})
      |> render_change()

    assert thief_html =~ "ROGUE RECORD"
    assert thief_html =~ "PICK POCKETS"
    assert thief_html =~ "OPEN LOCKS"
    assert thief_html =~ "CLIMB WALLS"

    # Select Cleric -> Cleric Record & Turning Undead Table
    cleric_html =
      view
      |> form("#hero_builder", %{"hero" => %{"class" => "Cleric", "race" => "Human", "level" => "1"}})
      |> render_change()

    assert cleric_html =~ "CLERIC / DRUID RECORD"
    assert cleric_html =~ "TURNING UNDEAD"
    assert cleric_html =~ "Skeleton"
    assert cleric_html =~ "Zombie"
    assert cleric_html =~ "Ghoul"
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: FAIL on missing layout zones

- [ ] **Step 3: Implement authentic 1E character sheet layout in `ClientWeb.RunLive`**

In `shards_engine/apps/client_web/lib/client_web/run_live.ex`:
- Update `@hero` default state with all 1E sub-fields:
  - Header: `player_name`, `campaign_name`, `campaign_num`, `date_began`, `patron_deity`, `religion`, `place_of_origin`, `move_base`, `alignment`.
  - Sub-abilities: `str_percent`, `hit_adj`, `dam_adj`, `open_doors`, `bend_bars`, `add_lang`, `know_spell`, `min_spells`, `max_spells`, `mag_atk_adj`, `spell_bonus`, `spell_failure`, `react_adj`, `missile_adj`, `def_adj`, `hp_adj`, `system_shock`, `resurrect_survival`, `max_henchmen`, `loyalty_base`, `react_cha_adj`, `com`, `com_response`.
  - Combat: `ac_base`, `shieldless_ac`, `rear_ac`, `condition_armor`, `hit_die`, `wounds`, `surprise_mod`, `dex_surprise_adj`, `rear_attack_adj`, `weapons_proficiency`, `num_proficiencies`, `non_prof_penalty`, `to_hit_adj_total`, `damage_adj_total`.
  - Weapons: list of weapon rows with name, mag_adj, range, speed, to-hit AC 10..2 scores, and damage S-M/L.
  - Class-specific: `church_status`, `holy_symbol`, `parish`, `turning_table`, `thieving_skills`, `mount_name`, `mount_hd`, `mount_hp`, `guild_order`, `guild_rank`, `contacts`.
- In `update_hero/2` and `hero_change` event:
  - Compute sub-stats and saving throws using `Referee.Rules.SheetTables` when Ability scores, Class, Race, or Level change.
- In `render/1` when `@pc == nil`:
  - Render the authentic 1E Player Character Record sheet with Zones 1–6 matching the reference images.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/run_live.ex shards_engine/apps/client_web/test/run_live_test.exs
git commit -m "feat(client_web): render authentic AD&D 1E Player Character Record layout with all 6 zones and class sections"
```

---

### Task 3: In-Game Full Sheet Modal (`ClientWeb.RunLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Test: `shards_engine/apps/client_web/test/run_live_test.exs`

**Interfaces:**
- Consumes: `ClientWeb.RunLive` live play surface
- Produces: 1-click **"📜 View Full 1E Character Sheet"** modal during live play

- [ ] **Step 1: Write failing tests for in-game sheet modal in `run_live_test.exs`**

In `shards_engine/apps/client_web/test/run_live_test.exs`:
```elixir
  test "in-game seat has View Full 1E Character Sheet button and modal toggle", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    html = render(view)
    assert html =~ "View Full 1E Character Sheet"

    # Click to open modal
    modal_html =
      view
      |> element("button", "View Full 1E Character Sheet")
      |> render_click()

    assert modal_html =~ "ADVANCED D&D"
    assert modal_html =~ "Player Character Record"
    assert modal_html =~ "SAVING THROWS (1E)"
    assert modal_html =~ "ADJUSTED TO HIT ARMOR CLASS"
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: FAIL

- [ ] **Step 3: Implement sheet modal in `ClientWeb.RunLive`**

In `shards_engine/apps/client_web/lib/client_web/run_live.ex`:
- Assign `:show_sheet_modal` (default `false`).
- Add event handlers `"open_sheet_modal"` and `"close_sheet_modal"`.
- Add `"View Full 1E Character Sheet"` button to Panel 3 in live play mode.
- Render the full 1E Player Character Record inside a modal overlay when `@show_sheet_modal == true`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/run_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/run_live.ex shards_engine/apps/client_web/test/run_live_test.exs
git commit -m "feat(client_web): add interactive full 1E character sheet modal to in-game player station"
```

---

### Task 4: Full Umbrella Verification & Engrams Export

**Files:**
- Test all: `mix test` across all 7 umbrella apps

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: All tests pass green across `engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`.

- [ ] **Step 2: Interactive visual verification in browser**

1. Launch server: `cd shards_engine && PORT=4000 mix run --no-halt scripts/web_server.exs`.
2. Open Player Link `http://localhost:4000/runs/<run_id>`.
3. Verify visual layout of all 6 zones:
   - Header, Identity & Movement.
   - Abilities Sub-Table Matrix with all sub-stats.
   - Saving Throws (5 bubbles) & Resistances.
   - Combat Vitals & AC Shield block.
   - Weapons & To-Hit Matrix (AC 10..2).
   - Dynamic class bottom sections (switch between Fighter, Thief, Magic-User, Cleric).
4. Click "Enter The Ruined Tower".
5. In live play station, click `"📜 View Full 1E Character Sheet"` and verify full sheet modal opens with live stats.

- [ ] **Step 3: Engrams logging and export**

```bash
engrams decision log --summary "Authentic AD&D 1E Character Sheet Layout: implemented spatial layout, abilities sub-table matrix, saving throws, weapons AC 10..2 matrix, and dynamic class-specific bottom sections matching TSR 1E Player Character Record sheets" --rationale "Faithfully reflects the official 1E printed character record sheets across character builder and live play modal." --tags ui,ux,1e-character-sheet,adnd,character-record,client-web --importance 9
engrams progress log --status Done --description "Authentic AD&D 1E Character Sheet Layout complete & verified: all 6 zones, ability sub-stats, saving throws, weapons matrix, and class-specific tables (Cleric Turning, Fighter Mount, Magic-User Spells, Thief Skills %) implemented and verified."
engrams export
```
