# Task 1 Brief: Multi-Key Actor Ingestion, Tier Parsing & Dossier Support in EngineCore.Loader and EngineCore.Validator

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/loader.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/validator.ex`
- Test: `shards_engine/apps/engine_core/test/loader_test.exs`
- Test: `shards_engine/apps/engine_core/test/validator_test.exs`

**Requirements:**
1. In `EngineCore.Loader`:
   - Update `extract_elements(yaml, keys)` to `flat_map` across all matching keys so that elements from both `initial_actors` (or `initial_npcs`) and `initial_enemies` (or `monsters`) are extracted and merged into `World.agents`.
   - Update `agent_from(m)`:
     - Parse `tier` using `parse_tier(m)` which checks integer `m["tier"]` or `m["cognition_tier"]` first, falling back to `tier_of(m["id"])`.
     - Assign `capabilities: caps(tier)`.
     - Assign `dossier: m["dossier"] || %{}`.
2. In `EngineCore.Validator`:
   - Update `monster_errors(yaml)` to inspect all agent entries across `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters`. Ensure required attributes (`id`, `name`, `hit_dice`, `hit_points`, `armor_class`, `thac0`, `morale`, `current_room_id`) are checked.
   - Update `agent_ids(yaml)` to include agent IDs from `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters`.
3. Tests:
   - Add unit test in `loader_test.exs` verifying loading a world with both `initial_actors` and `initial_enemies`, checking tier 3 capabilities (`:parley`), and checking the loaded `dossier`.
   - Add unit test in `validator_test.exs` verifying validation accepts valid `initial_actors` maps.
4. TDD cycle:
   - Add failing tests.
   - Run tests to confirm failure.
   - Implement minimal changes.
   - Run tests to confirm pass.
   - Commit with message: `feat(engine_core): support initial_actors, explicit tier parsing, and agent dossiers`.
