# Task 5 Report: GM console LIVE/OFFLINE badge (`ClientWeb.SpectateLive`)

## Status

DONE

## Commit

`b175726983d5d1d425371c049884c2553a86289f` — `feat(web): GM console shows persistent LIVE/OFFLINE routing badge` (2 files changed, 39 insertions(+), 1 deletion(-))

Files committed (only the two named):
- `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- `shards_engine/apps/client_web/test/spectate_live_test.exs`

## TDD evidence

- RED: `mix test test/spectate_live_test.exs` → 16/18 passed, exactly the 2 new badge tests failed on `assert html =~ ~s(data-testid="llm-badge")` (badge not yet rendered).
- GREEN: same command after implementation → 18 passed, 0 failures, 1.2s.

## Test counts

`test/spectate_live_test.exs`: 18 tests total (16 pre-existing snapshot/ribbon/flow tests + 2 new badge tests), all passing.

## Contract verification (brief's STOP check)

`LLMGateway.Config.live?/0` (apps/llm_gateway/lib/llm_gateway/config.ex:55) requires only `:deliberate` and `:interpret` to carry a non-Scripted adapter — the test's partial routing (2 of 5 classes) is accepted. `Config.model/0` reads `:deliberate`'s model → `"stub-1"`. No STOP needed; test not widened.

## Deviations

None from the brief's specified test bodies, assigns, template snippet, or commit message. Mechanical fixes during application:

1. Added the trailing comma on `ooc_log: []` once `live:`/`model:` became the list tail (required for compilation; the brief's snippet shows the two new lines without restating the preceding comma).
2. Blank-line separation between the last pre-existing private helper and the first appended test (file convention: blank line between definitions).

## Environment hygiene

`engrams/` workspace churn (context.db, release_cache.json) was left unstaged — not committed.
