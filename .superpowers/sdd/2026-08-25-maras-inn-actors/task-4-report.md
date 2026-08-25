# Task 4 Report: Add Mara's Inn Actors, Boundary & Commitments to ruined_tower.yaml

## Status
DONE

## Commits
- `feat(adventure): define Mara, Mayor Grevik, Erik, and Anna in ruined_tower.yaml` (HEAD of current branch)

## Test Summary
- `mix test apps/engine_core/test/loader_test.exs`: 8/8 passed
- `mix test apps/engine_core/test` (all engine_core tests): 109/109 passed
- `mix test` (umbrella): 388/388 passed
  - engine_core: 109
  - llm_gateway: 38
  - agents: 26
  - referee: 139
  - wire: 29
  - client_tui: 14
  - client_web: 33

## Changes
- Added `initial_actors:` section to `the-ruined-tower/ruined_tower.yaml` with four actors:
  - `mara` (human innkeeper, tier 3, hp 6, AC 9)
  - `mayor_grevik` (human official, tier 3, hp 8, AC 8)
  - `erik` (human farmer, tier 2, hp 7, AC 10)
  - `anna` (human healer, tier 2, hp 6, AC 9)
- Added `maras_inn_zone` boundary in `boundaries:` section for the settlement.
- Added three actor commitments for Mara and Mayor Grevik:
  - `mara_welcome_guests`
  - `mara_tend_bar`
  - `mayor_grevik_listen_concerns`
- Updated `shards_engine/apps/engine_core/test/loader_test.exs` boundary-key assertion to include `maras_inn_zone` so the suite remains green.

## Concerns
- The commit `e022411` includes unrelated untracked `.superpowers/sdd/2026-08-25-maras-inn-actors/task-{1,2,3}-*` files that were already present in the working tree; they were swept in by `git add -A`. If these should not be part of this commit, the commit should be rewritten to scope only `ruined_tower.yaml`, `loader_test.exs`, and `task-4-report.md`.
- The brief requested `mix test apps/engine_core`; at the umbrella root that path matches no tests, so `mix test apps/engine_core/test` was used instead to exercise the engine_core suite.
