# Thornhollow Town Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the village of Thornhollow in `the-ruined-tower/ruined_tower.yaml` with a central Village Green, 14 interconnected town locations, full commercial services, faith and civic administration, residential investigative sites with tangible evidence items, Tier-3 BDI NPC agency, and spatial presence boundaries.

**Architecture:** Update `the-ruined-tower/ruined_tower.yaml` with structured YAML sections (`home_base`, `rooms`, `initial_treasure`, `initial_actors`, `boundaries`, `initial_commitments`). Validate that the resulting world builds cleanly through `EngineCore.Validator`, loads into `%World{}` via `EngineCore.Loader`, and passes all ExUnit tests across the 7 umbrella applications without regressions.

**Tech Stack:** Elixir 1.18 / OTP 27, YAML (yaml_elixir), ExUnit, Engrams CLI.

## Global Constraints

- **File Integrity:** `the-ruined-tower/ruined_tower.yaml` is the machine-readable immutable per-run adventure seed; edits must preserve exact schema requirements.
- **Starting Room Continuity:** `starting_place: "maras_inn"` and `starting_room: "maras_inn"` must remain intact so existing player spawn routines and tests (`run_test.exs`) work seamlessly.
- **Single Current Room:** Every actor in `initial_actors` must have exactly one valid `current_room_id`.
- **1E Coinage Legend:** Treasure and coin values must adhere to discrete copper-value rules (`pp: 500, gp: 100, ep: 50, sp: 10, cp: 1`).
- **Pantheon Canon:** Temple dedicated to *Thyra the Green Mother* and *Solara the Daystar*; Blacksmith dedicated to *Korvath the Iron Lord*; Apothecary aligned with *Mystara the Weaver*.
- **No Placeholders:** Every room, actor, item, boundary, and commitment must be fully defined with concrete stats, descriptions, and exits.

---

### Task 1: Add Town Rooms & Exits to `the-ruined-tower/ruined_tower.yaml`

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml:20-125` (update `home_base` and `rooms:`)
- Test: `shards_engine/apps/engine_core/test/validator_test.exs`

**Interfaces:**
- Consumes: Existing `ruined_tower.yaml` room declarations (`maras_inn`, `entry_hall`, `library`, etc.).
- Produces: 14 interconnected town rooms under `rooms:` with bidirectional single-word exits and `kind: "settlement"`.

- [ ] **Step 1: Update `home_base` metadata in `the-ruined-tower/ruined_tower.yaml`**

Update `home_base.key_locations`, `home_base.notable_npcs`, and `home_base.available_services` to enumerate all 14 town buildings, new shopkeepers, civic officials, and residential figures.

- [ ] **Step 2: Add all 14 town room definitions to `rooms:` in `the-ruined-tower/ruined_tower.yaml`**

Add `village_green`, `blacksmith_shop`, `general_store`, `herbalist_shop`, `butchers_shop`, `pawn_shop`, `temple_of_thyra`, `town_hall`, `town_jail`, `town_treasury`, `eriks_farm`, `mordale_cottage`, `trappers_cabin`, and `elders_study` with complete `kind: "settlement"`, sensory descriptions, structures, atmosphere, and bidirectional exits. Update `maras_inn` exits to include `east: "village_green"` and `green: "village_green"`.

- [ ] **Step 3: Run validator test to verify syntax**

Run: `cd shards_engine && mix test apps/engine_core/test/validator_test.exs`
Expected: PASS (or identify missing rooms/connections)

- [ ] **Step 4: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml
git commit -m "feat(adventure): add town room definitions and navigation topology"
```

---

### Task 2: Add Commercial Inventories, Clues & Quest Items to `the-ruined-tower/ruined_tower.yaml`

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml` (`initial_treasure:` section)
- Test: `shards_engine/apps/engine_core/test/loader_test.exs`

**Interfaces:**
- Consumes: Room IDs from Task 1 (`eriks_farm`, `mordale_cottage`, `trappers_cabin`, `elders_study`, `town_treasury`).
- Produces: Examinable evidence items, quest items, and treasury contents under `initial_treasure:`.

- [ ] **Step 1: Add residential tangible clues and quest items**

Add the following items under `initial_treasure:`:
- `mutilated_sheep_fleece` (`location_room_id: "eriks_farm"`)
- `goblin_javelin_scrap` (`location_room_id: "eriks_farm"`)
- `willems_scouting_sketch` (`location_room_id: "mordale_cottage"`)
- `violet_crystal_shard` (`location_room_id: "mordale_cottage"`)
- `goblin_wolf_collar` (`location_room_id: "trappers_cabin"`)
- `trappers_beast_notes` (`location_room_id: "trappers_cabin"`)
- `vaeliths_chronicle_excerpt` (`location_room_id: "elders_study"`)
- `archival_estate_receipt` (`location_room_id: "elders_study"`)
- `town_treasury_vault` (`location_room_id: "town_treasury"`, coins: 120 gp, 350 sp, 1200 cp)

- [ ] **Step 2: Run loader test to verify items loaded**

Run: `cd shards_engine && mix test apps/engine_core/test/loader_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml
git commit -m "feat(adventure): add tangible evidence and quest items to town"
```

---

### Task 3: Add Tier-3 BDI Town Actors with 1E Statblocks & Dossiers to `the-ruined-tower/ruined_tower.yaml`

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml` (`initial_actors:` section)
- Test: `shards_engine/apps/engine_core/test/validator_test.exs`

**Interfaces:**
- Consumes: Room IDs and Actor schemas.
- Produces: 13 fully defined Tier-3 BDI actors with 1E stats, `tier: 3`, `is_alive: true`, and rich `dossier:` blocks.

- [ ] **Step 1: Add new town actors under `initial_actors:`**

Add complete statblocks and dossiers for:
- `torvald_ironhand` (`current_room_id: "blacksmith_shop"`)
- `jorren` (`current_room_id: "general_store"`)
- `thessia_brightmix` (`current_room_id: "herbalist_shop"`)
- `hael_bloodwood` (`current_room_id: "butchers_shop"`)
- `silas_vance` (`current_room_id: "pawn_shop"`)
- `sister_aldara` (`current_room_id: "temple_of_thyra"`)
- `captain_gareth` (`current_room_id: "town_jail"`)
- `kaelen_the_trapper` (`current_room_id: "trappers_cabin"`)
- `elder_corvus` (`current_room_id: "elders_study"`)

Ensure existing actors (`mara`, `mayor_grevik`, `erik_the_shepherd`, `anna_mordale`) remain at `current_room_id: "maras_inn"` with their approved statblocks and dossiers.

- [ ] **Step 2: Run validator test**

Run: `cd shards_engine && mix test apps/engine_core/test/validator_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml
git commit -m "feat(adventure): add Tier-3 BDI town actors with 1E statblocks and dossiers"
```

---

### Task 4: Add Spatial Boundaries & Initial Commitments to `the-ruined-tower/ruined_tower.yaml`

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml` (`boundaries:` and `initial_commitments:` sections)
- Test: `shards_engine/apps/referee/test/run_test.exs`

**Interfaces:**
- Consumes: Room IDs from Task 1 and Actor IDs from Task 3.
- Produces: 15 place boundaries with `presence_crossing` / `signal_arrived` triggers and 12 initial commitments.

- [ ] **Step 1: Add town place boundaries under `boundaries:`**

Add:
- `town_green_zone` (`place: "village_green"`)
- `blacksmith_zone` (`place: "blacksmith_shop"`)
- `general_store_zone` (`place: "general_store"`)
- `apothecary_zone` (`place: "herbalist_shop"`)
- `butcher_zone` (`place: "butchers_shop"`)
- `pawn_shop_zone` (`place: "pawn_shop"`)
- `temple_zone` (`place: "temple_of_thyra"`)
- `town_hall_zone` (`place: "town_hall"`)
- `town_jail_zone` (`place: "town_jail"`)
- `town_treasury_zone` (`place: "town_treasury"`)
- `eriks_farm_zone` (`place: "eriks_farm"`)
- `mordale_cottage_zone` (`place: "mordale_cottage"`)
- `trappers_cabin_zone` (`place: "trappers_cabin"`)
- `elders_study_zone` (`place: "elders_study"`)

- [ ] **Step 2: Add initial commitments under `initial_commitments:`**

Add commitments for `torvald_ironhand`, `jorren`, `thessia_brightmix`, `sister_aldara`, `captain_gareth`, `silas_vance`, `kaelen_the_trapper`, and `elder_corvus`.

- [ ] **Step 3: Run referee run tests**

Run: `cd shards_engine && mix test apps/referee/test/run_test.exs`
Expected: PASS (including `new wakes starting_place boundary when PCs are injected at maras_inn`)

- [ ] **Step 4: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml
git commit -m "feat(adventure): add spatial boundaries and initial commitments for town"
```

---

### Task 5: Run Full Test Suite & Validation

**Files:**
- Test: All 7 umbrella apps in `shards_engine`

- [ ] **Step 1: Run full umbrella test suite**

Run: `cd shards_engine && mix test`
Expected: 100% PASS across all apps (engine_core, llm_gateway, agents, referee, wire, client_tui, client_web)

- [ ] **Step 2: Verify `Engrams` pre-commit checks**

Run: `engrams check --staged` or `engrams check`
Expected: 0 violations

---

### Task 6: Session Logging with Engrams & Final Review

**Files:**
- Modify: `engrams/` database via CLI
- Export: `engrams export`

- [ ] **Step 1: Log design decision in Engrams**

```bash
engrams decision log \
  --summary "Thornhollow Comprehensive Settlement & Tangible Clues Expansion" \
  --rationale "Expanded Thornhollow from a single inn boundary into a full hub-and-spoke settlement with 14 interconnected locations, 5 shops with 1E gear and spell components, Temple of Thyra/Solara, civic administration with jail/treasury, and 4 residential houses with tangible clues and Tier-3 BDI NPC actors." \
  --tags "adventure,thornhollow,settlement,npcs,bdi,yaml,clues" \
  --anchor "the-ruined-tower/ruined_tower.yaml" \
  --importance 9
```

- [ ] **Step 2: Log progress entry**

```bash
engrams progress log --status Done --description "Thornhollow comprehensive town expansion implemented in ruined_tower.yaml with 14 locations, Tier-3 BDI actors, and spatial boundaries"
```

- [ ] **Step 3: Export engrams and commit**

```bash
engrams export
git add engrams/ engrams_export/
git commit -m "chore: log engrams decision, progress, and export"
```
