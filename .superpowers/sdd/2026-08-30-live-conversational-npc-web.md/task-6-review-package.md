# Task 6 review package — Organic deliberation prompt

Reviewer: verify spec compliance + code quality for commit `c5ab8b29` (parent `b1757269`).

**Read, in order:**
1. Brief: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-6-brief.md`
2. Implementer report: `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-6-report.md`
3. Diff: `git show c5ab8b29` (two files: `agents/lib/agents/prompt.ex`, `agents/test/deliberate_test.exs`)
4. Spec context: `docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md` §4.5 + decision-88 rules

**Adjudicate:**
- Prompt contract: system heredoc carries decision-88 rules as single unbroken lines; reply rules (first person, 1-4 sentences, ask back, Never invent world facts) present; schema untouched; `Summary:` still last.
- User assembly: persona opener, dossier, people_block (names + ids, PC vs NPC labels), speech_block (says-to-YOU vs hearsay), the_moment_block (last addresser), retained labels (`Commitments:`, `Salient here:`, `Role:`, `Personality:`, `Goals:`, `Knowledge / Rumors:`).
- Deviations from brief text: (a) one sigil delimiter change `~s(...)` → `~s{...}` on the hearsay line (claimed byte-identical rendered text — verify against the brief's expected assertion strings); (b) a stale speech_block comment replaced — read the new comment and confirm it is accurate, not scope creep; (c) formatter wrapping in test literals.
- Existing contracts: deliberate_test 14/14, agents suite 35/35 claimed — spot-check by running `cd shards_engine/apps/agents && mix test` (allowed).
- `adopt/1` and dossier helpers untouched; only two files committed; engrams untouched.

**Reply JSON:** `{"findings": [{"severity": "P1|P2|P3", "body": "..."}], "verdict": "approved|fix_required", "overall_correctness": "correct|concerns|incorrect", "confidence": 0.0-1.0, "explanation": "..."}`. Findings: only real defects or spec violations; style nits as P3 max.
