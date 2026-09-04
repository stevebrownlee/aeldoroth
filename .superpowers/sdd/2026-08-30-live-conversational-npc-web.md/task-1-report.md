# Task 1 Report: `LLMGateway.Config` — single-source routing builder

## Status: DONE

## What was done
Followed the brief's TDD order exactly, transcribing its test and implementation code verbatim:

1. **Step 1 — failing test**: Created `shards_engine/apps/llm_gateway/test/config_test.exs` (verbatim from brief).
2. **Step 2 — red**: Ran `mix test test/config_test.exs` → failed as expected: all 6 tests with `UndefinedFunctionError ... LLMGateway.Config is not available` (compile warnings for each of the 4 functions). Matches brief's expected failure mode.
3. **Step 3 — implementation**: Created `shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex` (verbatim from brief). Decision 69 defaults hard-coded: model `claude-haiku-4-5-20251001`, endpoint `https://api.anthropic.com/v1/messages`, temperature `0.2`, max_tokens `1024`, `ANTHROPIC_TIMEOUT` default `10_000`.
4. **Step 4 — green**:
   - `cd shards_engine/apps/llm_gateway && mix test test/config_test.exs` → `Result: 6 passed` (0 failures, no warnings).
   - `cd shards_engine/apps/llm_gateway && mix test` (full app suite, collateral check) → `Result: 47 passed`.
5. **Step 5 — commit**:
   ```
   git add shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex shards_engine/apps/llm_gateway/test/config_test.exs
   git commit -m "feat(gateway): single-source env routing builder (LLMGateway.Config)"
   ```
   → commit `7cb03ce3` on `main`: "2 files changed, 175 insertions(+)", both files created.

## Test path convention
Checked before writing: existing tests live flat in `shards_engine/apps/llm_gateway/test/` (`router_test.exs`, `schema_test.exs`, …) with an `adapters/` subdir. The brief's path `test/config_test.exs` matches convention — **no adaptation needed**.

## Deviations
None. No other files touched (runtime.exs, web_server.exs, etc. untouched per non-goals). No new dependencies.

## Notes for later tasks
- `routing_from_env/0` shape: `%{keys: %{anthropic_main: key}, routing: %{class => cfg}}` where cfg = `%{adapter: LLMGateway.Adapters.Anthropic, model, endpoint, key_ref: :anthropic_main, temperature: 0.2, max_tokens: 1024, timeout}`.
- `live?/0` requires BOTH `:deliberate` and `:interpret` present with a non-`Scripted` atom adapter.
- `apply_env_routing/0` is a strict no-op (returns `:ok`, writes nothing) when `ANTHROPIC_API_KEY` is nil/blank.
