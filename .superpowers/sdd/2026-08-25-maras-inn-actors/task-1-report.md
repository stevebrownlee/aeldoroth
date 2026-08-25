# Task 1 Report: Multi-Key Actor Ingestion, Tier Parsing & Dossier Support

## Status
DONE

## Summary
Implemented support for multiple actor source keys, explicit tier parsing, and agent dossiers in `EngineCore.Loader` and `EngineCore.Validator`, with accompanying tests.

## Commits
- `feat(engine_core): support initial_actors, explicit tier parsing, and agent dossiers`

## Changes Made
- `shards_engine/apps/engine_core/lib/engine_core/loader.ex`
  - `extract_elements/2` now merges entries from `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters`.
  - `agent_from/1` uses new `parse_tier/1` helper: prefers explicit `tier` or `cognition_tier` integer, falling back to ID-based `tier_of/1`.
  - `agent_from/1` sets `capabilities: caps(tier)` and `dossier: m["dossier"] || %{}`.
- `shards_engine/apps/engine_core/lib/engine_core/validator.ex`
  - Added `@actor_keys` module attribute.
  - `monster_errors/1` now validates required attributes across all actor keys.
  - `agent_ids/1` collects IDs from `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters` (maps or lists).
- `shards_engine/apps/engine_core/test/loader_test.exs`
  - Added test verifying merge of `initial_actors` and `initial_enemies`, explicit tier parsing (`tier` and `cognition_tier`), tier-3 `:parley` capability, and dossier loading.
- `shards_engine/apps/engine_core/test/validator_test.exs`
  - Added test verifying validation accepts a valid `initial_actors` map.

## Test Results
```
$ cd shards_engine/apps/engine_core && mix test
Running ExUnit with seed: 734222, max_cases: 32
Result: 109 passed
```

## Concerns
None.
