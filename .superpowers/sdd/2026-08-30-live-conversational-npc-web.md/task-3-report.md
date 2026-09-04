# Task 3 report — `.env` activation in the web server script

**Status:** complete. **Commit:** `5cf1e831` — `feat(web): source .env and activate live routing at web server boot` (1 file, 73 insertions).

## Change (`shards_engine/scripts/web_server.exs` only)

After the `port = ...` line, before endpoint/app config and any session creation:

1. `.env` parser as three bindings: `strip_quotes`, `put_env_line`, `source_env_file` (bodies transcribed from the brief verbatim, except as noted below). Plain `KEY=VALUE`, optional `export ` prefix, `#` comments, outer matching quotes stripped; a variable already present in the process environment is never overwritten (presence check `is_nil(System.get_env(key))` — empty string counts as present).
2. `source_env_file.(Path.expand("../.env", __DIR__))` then `LLMGateway.Config.apply_env_routing()`.
3. `routing_state` computed from `LLMGateway.Config.live?/0` + `model/0`; boot banner now prints `[web_server] llm routing: #{routing_state}` as its first line — `live (<model>)` or `offline (set ANTHROPIC_API_KEY)`.

## Deviations from the brief's literal code (both forced, both verified)

- **`defp` → closures.** Top-level `defp` in a `.exs` raises `cannot invoke defp/2 outside module` (reproduced on this repo's Elixir 1.20.2/OTP 29 before editing — the script would not boot at all). Same bodies as closures, defined immediately before the single call site (closures must be bound before use, so the helpers sit above the sourcing call instead of at file end).
- **Path: `.env` → `../.env`** (`Path.expand("../.env", __DIR__)`). The brief's literal `Path.expand(".env", __DIR__)` resolves to `shards_engine/scripts/.env`, which contradicts the brief's own prose ("source shards_engine/.env", Step 4, lobby error text "see shards_engine/.env") and matches no existing file. `__DIR__` is anchored on the script's directory, so the documented `cd shards_engine && mix run scripts/web_server.exs` sources `shards_engine/.env` regardless of invoking cwd.

## Verification (4 real boots, `MIX_ENV=dev mix run --no-halt scripts/web_server.exs`, banner + `GET /`)

Throwaway `shards_engine/.env` created with FAKE values in repo `export KEY=VALUE` convention (comments, quoted model value, extra quoted/plain vars); deleted after the runs; the real repo-root `.env` was never read or loaded. Banner expectations in the log exclude shell `ANTHROPIC_*` contamination (sanitized env per boot).

| Boot | Setup | Banner | HTTP |
|---|---|---|---|
| A | no key anywhere, no `.env` | `offline (set ANTHROPIC_API_KEY)` | 200 |
| B | fake key only in throwaway `shards_engine/.env` (`ANTHROPIC_MODEL="claude-haiku-4-5-20251001"` quoted) | `live (claude-haiku-4-5-20251001)` — no quotes in value ⇒ quote-stripping + `export ` prefix parsed | 200 |
| C | shell fake key + `ANTHROPIC_MODEL=shell-model-value` vs different file model | `live (shell-model-value)` ⇒ per-var shell precedence, never-overwrite (positive) | 200 |
| D | shell `ANTHROPIC_API_KEY=""` + file fake key | `offline (set ANTHROPIC_API_KEY)` ⇒ empty is present, not overwritten (brief Step 4) | 200 |

Offline boot serves on `PORT` (A, D: HTTP 200) — the `live?/0` log line is informational only, as required. Boot B's banner model can only come from the file, so the file→process-env round trip is proven end-to-end through the real script.

## Notes / concerns

- `.env` is **not** gitignored (root and `shards_engine/.gitignore` checked). I did not touch `.gitignore` (non-goal: this task edits `web_server.exs` only); the real repo-root `.env` is currently untracked — recommend the plan owner gitignore it or keep it out of any `git add -A`.
- No Config/runtime.exs changes; no commits by siblings touched.
