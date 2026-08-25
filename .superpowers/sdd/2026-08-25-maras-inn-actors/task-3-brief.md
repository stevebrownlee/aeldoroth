# Task 3 Brief: In-Character Dossier Prompt Formatting in Agents.Prompt

**Files:**
- Modify: `shards_engine/apps/agents/lib/agents/prompt.ex`
- Test: `shards_engine/apps/agents/test/deliberate_test.exs`

**Requirements:**
1. In `Agents.Prompt.deliberate/1`:
   - Include formatted dossier lines when `slice[:dossier]` or `slice.dossier` is present and non-empty.
   - Format:
     - `Role: <role>` (from `dossier["role"]` or `dossier[:role]`)
     - `Personality: <personality>` (from `dossier["personality"]` or `dossier[:personality]`)
     - `Goals: <item1>; <item2>` or `<item>` (from `dossier["goals"]` or `dossier[:goals]`)
     - `Knowledge / Rumors: <item1>; <item2>` or `<item>` (from `dossier["knowledge"]`, `dossier["rumors"]`, etc.)
   - If `dossier` is nil or empty, omit dossier lines without adding blank lines.
2. In `shards_engine/apps/agents/test/deliberate_test.exs`:
   - Add a unit test verifying that `Agents.Prompt.deliberate/1` renders role, personality, goals, and knowledge/rumors into the user prompt string when provided with a dossier map.
3. TDD Cycle:
   - Add failing test in `deliberate_test.exs`.
   - Verify test fails.
   - Implement `format_dossier/1` and helper functions in `Agents.Prompt`.
   - Run tests (`mix test apps/agents/test/deliberate_test.exs` and `mix test apps/agents`) to verify all pass.
   - Commit with message: `feat(agents): format agent dossier role, goals, and knowledge in deliberate prompt`.
