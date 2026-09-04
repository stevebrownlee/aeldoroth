# Task 6 Report: Organic deliberation prompt (`Agents.Prompt.deliberate/1`)

- **Status:** DONE_WITH_CONCERNS (one syntactic micro-deviation, output text identical to spec)
- **Commit:** `c5ab8b29` — `feat(agents): organic-derivation deliberation prompt (persona, named listeners, answer-the-question)`
- **Files committed:** `shards_engine/apps/agents/lib/agents/prompt.ex`, `shards_engine/apps/agents/test/deliberate_test.exs` (only these two; `engrams/` artifacts left uncommitted)

## TDD flow (strict order)
1. **RED:** Appended the brief's 3 contract tests verbatim → `mix test test/deliberate_test.exs` → exactly 3 failures (new tests), 11 existing passed.
2. **GREEN:** Replaced `deliberate/1` and `speech_block/1`; added `people_block/1` and `the_moment_block/1` per brief → 14/14 passed.
3. Scoped `mix format` on the two touched files only (formatter reflowed the verbatim long maps in one new test; no semantic change; heredocs untouched). Re-ran tests after format.

## Test counts
- `test/deliberate_test.exs`: 14 passed (11 pre-existing + 3 new), 0 failures.
- Full `apps/agents` suite: 35 passed, 0 failures.
- Umbrella-wide test suite not run (out of scope for this task per protocol).

## Deviations (justified)
1. **Sigil delimiter on the hearsay line:** the brief's line
   `~s(  You overhear #{l[:from_name]}: "#{l[:words]}" (hearsay — secondhand, may be wrong))`
   does not compile: Elixir sigils do not nest their delimiter, so the literal `(hearsay …)` parens close the `~s(...)` sigil early (`MismatchedDelimiterError`). Changed to `~s{...}` for that one line. **Rendered prompt text is byte-identical to the brief's intent**, and the contract test asserting `"You overhear Bramble: \"pass the ale\" (hearsay"` and `"secondhand, may be wrong"` passes.
2. **Stale comment replaced with `speech_block/1`:** the brief's replacement code includes its own new comment; the old `addressed lines first-class` comment above the function was replaced in the same edit rather than left contradicting the new code.
3. **Formatter reflow** of two long map literals in the new test (verbatim-from-brief text, line-wrapping only).

## Concerns
- The one-line deviation above is the only divergence from the brief's literal text; all asserted prompt substrings match the contract tests.
- `engrams/context.db` / `engrams/release_cache.json` show as modified in `git status` (runtime churn) — intentionally NOT staged.
