# Task 2 Report: Dossier Context Slicing in Referee.Slice

## Status
DONE

## Commits
- `b9c1bd5` — feat(referee): expose agent dossier in slice for deliberation

## Changes
- `shards_engine/apps/referee/lib/referee/slice.ex`
  - Updated `@spec for_actor/2` to include `dossier: map()`.
  - Added `dossier: Map.get(agent, :dossier) || %{}` to the returned slice map.
  - Updated moduledoc to list `:dossier` as a returned key.
- `shards_engine/apps/referee/test/slice_test.exs`
  - Added test: `for_actor includes the actor's dossier map`.

## Test Summary
- `mix test apps/referee/test/slice_test.exs` — 8 passed
- `mix test apps/referee/test` — 139 passed
- `mix test apps/engine_core/test` — 109 passed

## Concerns
- A pre-existing type warning in `client_web` (`RunLive.handle_info/2` conditional on `url = wire_url()`) appears during compilation; it is unrelated to this task.
- `engrams/context.db` is dirty locally but was left unstaged; it appears to be tooling state, not part of this change.
