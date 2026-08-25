# Task 4 Brief: Add Mara's Inn Actors, Boundary & Commitments to ruined_tower.yaml

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml`

**Requirements:**
1. In `the-ruined-tower/ruined_tower.yaml`:
   - Add `initial_actors:` section defining 4 actors:
     - `mara` (name: "Mara", type: "human_innkeeper", current_room_id: "maras_inn", tier: 3, hit_dice: "1d8", hit_points: 6, armor_class: 10, thac0: 20, morale: 8, is_alive: true, dossier with role, personality, goals, rumors).
     - `mayor_grevik` (name: "Mayor Grevik", type: "human_leader", current_room_id: "maras_inn", tier: 3, hit_dice: "1d8", hit_points: 5, armor_class: 10, thac0: 20, morale: 7, is_alive: true, dossier with role, personality, goals, knowledge).
     - `erik_the_shepherd` (name: "Erik the Shepherd", type: "human_farmer", current_room_id: "maras_inn", tier: 3, hit_dice: "1d8", hit_points: 7, armor_class: 10, thac0: 20, morale: 6, is_alive: true, dossier with role, personality, goals, knowledge).
     - `anna_mordale` (name: "Anna Mordale", type: "human_villager", current_room_id: "maras_inn", tier: 3, hit_dice: "1d8", hit_points: 4, armor_class: 10, thac0: 20, morale: 5, is_alive: true, dossier with role, personality, goals, knowledge).
   - Add spatial boundary under `boundaries:`:
     ```yaml
       - id: "maras_inn_zone"
         place: "maras_inn"
         triggers: ["presence_crossing", "signal_arrived"]
         wake_on_intensity: 4
         sleep_after: 60
     ```
   - Add initial commitments under `initial_commitments:`:
     - `grevik_quest_offer`: debtor: "mayor_grevik", deed: "explain livestock raids and offer 100 gp bounty to investigate ruined tower", due: 1, every: 25, priority: 8
     - `anna_rescue_plea`: debtor: "anna_mordale", deed: "plead for Willem's rescue and offer 20 gp reward", due: 2, every: 30, priority: 7
     - `erik_raid_warning`: debtor: "erik_the_shepherd", deed: "recount goblin attack on sheep and describe green flickering lights", due: 3, every: 35, priority: 6
     - `mara_hospitality_and_rumors`: debtor: "mara", deed: "welcome guests, offer hot stew and ale, and share rumors of Vaelith's ghost", due: 5, every: 45, priority: 4
2. Verification:
   - Run `mix test apps/engine_core/test/loader_test.exs` in `shards_engine`
   - Run `mix test apps/engine_core` to ensure `ruined_tower.yaml` passes validation and loads all actors properly.
3. Commit with message: `feat(adventure): define Mara, Mayor Grevik, Erik, and Anna in ruined_tower.yaml`.
