# Task 2 Brief: Dossier Context Slicing in Referee.Slice

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/slice.ex`
- Test: `shards_engine/apps/referee/test/slice_test.exs`

**Requirements:**
1. In `Referee.Slice.for_actor/2`:
   - Include the agent's `dossier` in the returned slice map:
     `dossier: Map.get(agent, :dossier) || %{}`
   - Ensure the `@spec for_actor(World.t(), String.t()) :: map()` or return type includes `dossier: map()` if typed.
2. In `shards_engine/apps/referee/test/slice_test.exs`:
   - Add a unit test verifying `for_actor` includes the agent's `dossier` map when present on the `%Types.Agent{}`.
3. TDD Cycle:
   - Add failing test in `slice_test.exs`.
   - Verify test fails.
   - Implement `dossier` in `Referee.Slice.for_actor/2`.
   - Run tests (`mix test apps/referee/test/slice_test.exs` and `mix test apps/referee`) to verify all pass.
   - Commit with message: `feat(referee): expose agent dossier in slice for deliberation`.
