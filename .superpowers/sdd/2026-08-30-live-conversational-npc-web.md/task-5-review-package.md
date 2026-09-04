# Task 5 review package — GM console LIVE/OFFLINE badge

Reviewer: verify spec compliance + code quality for commit `b1757269` (parent `0360202f`).

**Read, in order:**
1. Brief: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-5-brief.md`
2. Implementer report: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-5-report.md`
3. Diff: `git show b1757269` (two files: `spectate_live.ex`, `spectate_live_test.exs`)
4. Spec context: `docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md` §4.4, §5.3

**Adjudicate:**
- Assigns read `Config.live?()` / `Config.model()` at mount — same Application-env source as the lobby gate (spec: describes what the *next* run gets).
- Badge renders in the template exactly once, `data-testid="llm-badge"`, `LIVE · <model>` vs `OFFLINE`; no crash when `model/0` is `nil` offline.
- New tests save/restore `:llm_gateway` `:routing` via on_exit; do they poison concurrent async tests in this file (spectate suite is `async` — check the module attribute) by deleting/setting global env mid-run? If the file is async: true, reason carefully about ExUnit scheduling: the OFFLINE test's env deletion races other tests' mounts. If you find a real race (a test that would read routing concurrently), raise it P2 with the failing scenario; if no other test in the file reads routing, P3 note max.
- No unrelated changes; only two files committed; engrams untouched.

**Reply JSON:** `{"findings": [{"severity": "P1|P2|P3", "body": "..."}], "verdict": "approved|fix_required", "overall_correctness": "correct|concerns|incorrect", "confidence": 0.0-1.0, "explanation": "..."}`. Findings: only real defects or spec violations; style nits as P3 max.
