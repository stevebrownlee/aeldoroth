# Dungeon Overview Enrichment: Treasure, Traps & Secret Doors

**Date:** 2026-08-20  
**Status:** In Review  
**Domain:** `shards_engine` (`apps/client_web`, `apps/engine_core`, `apps/wire`)  
**Decisions Referenced:** Decision 20 (Referee Pipeline), Decision 52 (Trust Barrier), Decision 57 (GM Console Redesign)

---

## 1. Goal

Expand the Dungeon Overview panel in the GM Console (`ClientWeb.SpectateLive`) to provide the referee with a comprehensive, omniscient DM view of each room:
1. **Treasure & Valuable Items:** Gold hoards, potions, magic items, spellbooks, clues/notes, gold piece values, and `[HIDDEN]` / `[CARRIED]` status.
2. **Traps & Hazards:** Pit traps, alarm tripwires, poison needle traps, caltrops, detection/disarm DCs, damage, and trigger status (`[ARMED]` vs `[TRIGGERED]`).
3. **Secret & Sealed Doors:** Secret passages (e.g. library to secret ritual chamber with password "Lux Memoriae"), locked doors, direction labels, and sealed status.
4. **Resident Monsters & PCs:** Retain resident PCs and monsters with live HP bars and condition tags.

---

## 2. Omniscient Referee View vs Sensory Player Isolation

- **GM Console (`SpectateLive` / `Wire.SpectateChannel`):**
  - Receives complete `dungeon` overview containing all places, items, hazards, and edges.
  - Gives the DM immediate answers when players search a room, detect traps, or inspect walls.
- **Player Seat (`RunLive` / `Wire.RunChannel`):**
  - Retains strict truth-barrier sensory isolation (Decision 52).
  - Players only see items in their slice that are unhidden or discovered; hidden caches, armed traps, and secret doors remain invisible to players until revealed through referee adjudication.

---

## 3. Data Model & Projections (`EngineCore.World.Server.dungeon_overview/1`)

In `EngineCore.World.Server.dungeon_overview(run_id)`:
For each place in `world.places`:
1. **`items`:** List of items located in this place (`item.place_id == place.id`):
   - `id`: item ID
   - `name`: item name
   - `value_gp`: value in gold pieces
   - `is_hidden`: boolean
   - `holder_id`: agent ID if carried, or nil
2. **`hazards`:** List of hazards/traps located in this place (`hazard.place_id == place.id`):
   - `id`: hazard ID
   - `kind`: hazard kind (e.g. `:alarm`, `:damage`, `:pit`, `:tripwire`)
   - `dc`: difficulty class for detection/avoidance
   - `triggered`: boolean
   - `damage`: damage dice description (e.g. `1d4`, `2d6`)
3. **`connections`:** List of exits from this place with `Edge` metadata:
   - `to`: target room ID
   - `label`: direction (e.g. `north`, `down`)
   - `sealed`: boolean (true for locked doors or secret passages)
4. **`agents`:** List of resident agents (PCs and monsters with HP, HP max, conditions, and PC flag).

---

## 4. UI Design & Visual Badges (`ClientWeb.SpectateLive`)

Inside the `.room-card` element:
- **Header:** Room Name + ID + Kind (`Room 2: Vaelith's Library · library · room`) + `[PARTY IS HERE]` badge if PCs present.
- **Monsters Section:** Green badge for PCs, red badge for monsters with HP values.
- **Treasure Section:**
  - Item name + gold value (`Potion of Healing · 50 gp`).
  - Amber badge `[HIDDEN]` if hidden in a wall cache/compartment.
  - Blue badge `[CARRIED by <Agent>]` if carried by an NPC/monster.
- **Traps Section:**
  - Trap name / kind (`Concealed Pit Trap · DC 14 · 2d6 dmg`).
  - Red badge `[ARMED]` or grey badge `[TRIGGERED]`.
- **Exits & Secret Doors Section:**
  - Standard exit: `north → guard_room`.
  - Secret / Sealed door: `down → ritual_chamber [SECRET DOOR / SEALED]`.

---

## 5. Verification Plan

1. **Unit Tests:** `Server.dungeon_overview/1` in `engine_core_test` verifies extraction of items, hazards, and sealed edges.
2. **Wire Tests:** `WireTest` asserts spectate join snapshot contains `items`, `hazards`, and `connections` with `sealed` boolean.
3. **LiveView Tests:** `SpectateLiveTest` asserts rendering of treasure, traps, and secret door badges on room cards.
4. **Browser Smoke:** Verify visual display in live browser.
