# Task 4 Report: Lobby hard-requirement gate (`ClientWeb.HomeLive`)

**Status:** DONE
**Commit:** `bb1e94662d4412d3c59c54cac34368cb3d3f2085` — `feat(web): lobby refuses to create runs while LLM routing is offline`
**Files committed (only these three):**
- `shards_engine/apps/client_web/lib/client_web/home_live.ex`
- `shards_engine/apps/client_web/lib/client_web/test_support.ex`
- `shards_engine/apps/client_web/test/home_live_test.exs`

## TDD evidence
- **RED** (after Step 1–2, before Step 4): `mix test test/home_live_test.exs` → 6/7 passed, 1 failed. The new "GM launch is refused while LLM routing is offline" failed as predicted: launch redirected to `/runs/web-offline_260/gm` (no gate existed), so `assert html =~ "LLM routing is offline"` hit a live_redirect tuple instead of the flash. All pre-existing tests plus the new live-shaped-launch test passed.
- **GREEN** (after Step 4): `mix test test/home_live_test.exs` → **7 passed**.
- **Full app suite** (Step 6): `mix test` in `client_web` → **40 passed**, 0 failures. Cross-file app-env bleed confirmed behaviorally harmless (plan §Task 4 Step 6) — no hack needed.

## Implementation notes
- Stub adapter appended to `lib/client_web/test_support.ex` exactly per brief; `%LLMGateway.Audit{}` verified to build empty (all fields defaulted in `llm_gateway/lib/llm_gateway/types.ex`), so no field-for-field adaptation was needed. `client_web` reaches `llm_gateway` transitively (`client_web → referee → llm_gateway`, both `in_umbrella`), so the struct expansion and `Config.live?/0` call compile and dispatch fine.
- Gate: `{:live, true} <- {:live, Config.live?()}` inserted between the `{:roster, ...}` and `{:start, ...}` steps of the launch `with`; `{:live, false}` else-branch flashes the ANTHROPIC_API_KEY guidance and starts no session.
- Test file flipped to `async: false` with the brief's comment; setup installs live-shaped StubAdapter routing + stub key and restores prior env in `on_exit`.

## Deviations
None from the brief's intent or content. One mechanical note: the `home_live.ex` else-branch edit triggered the edit tool's boundary auto-repair (a duplicate `{:roster, false}` row outside the range was dropped); the final file was re-read and verified — the else chain is exactly brief-shaped.

## Not committed (intentionally)
`engrams/context.db`, `engrams/release_cache.json` (modified by other processes — never commit per brief), plan/spec docs, and `.superpowers/` working files remain uncommitted.
