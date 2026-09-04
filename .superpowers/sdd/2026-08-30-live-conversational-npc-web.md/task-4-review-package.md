# Task 4 review package — Lobby hard-requirement gate

Reviewer: verify spec compliance + code quality for commit `bb1e9466` (parent `bfaba97e`).

**Read, in order:**
1. Brief: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-4-brief.md`
2. Implementer report: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-4-report.md`
3. Diff: `git show bb1e9466` (three files: `home_live.ex`, `test_support.ex`, `home_live_test.exs`)
4. Spec context: `docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md` §4.3, §5.2

**Adjudicate:**
- Gate placement in the `with` chain (after roster, before start) and the `{:live, false}` else branch — flash text names `ANTHROPIC_API_KEY` (spec hard requirement wording), no session created offline.
- `Config.live?/0` consumed, not Application env read directly.
- `StubAdapter` builds a valid `%LLMGateway.Audit{}` and satisfies the adapter contract enough for `live?/0` (never called in these tests).
- async: false + setup/restore of `:llm_gateway` app env — correct save/restore, no leakage to other tests (full client_web suite 40/40 claimed — spot-check by running `cd shards_engine/apps/client_web && mix test` if in doubt; do NOT run other apps' suites).
- No unrelated changes; `.env`/engrams not committed.

**Reply JSON:** `{"findings": [{"severity": "P1|P2|P3", "body": "..."}], "verdict": "approved|fix_required", "overall_correctness": "correct|concerns|incorrect", "confidence": 0.0-1.0, "explanation": "..."}`. Findings: only real defects or spec violations; style nits as P3 max.
