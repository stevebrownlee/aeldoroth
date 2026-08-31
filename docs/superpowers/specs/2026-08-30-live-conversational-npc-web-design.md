# Live Conversational NPCs in Web Play Design

**Date:** 2026-08-30  
**Status:** Draft — awaiting user review  
**Topic:** Making web-play NPC speech organic (LLM-live) instead of canned rumor parroting: deterministic `.env` → routing activation, lobby hard requirement, GM live/offline badge, and an organic-derivation deliberation prompt.

---

## 1. Problem & Root Cause

Players in web seats receive canned responses — verbatim `rumors:` fragments from `ruined_tower.yaml` (e.g. "They headed toward the ruined tower on the hill") with no conversational context, no personal knowledge of the players, and no first-person story.

**Root cause (evidence):** the web boot path was never the problem. `Referee.Run.new/4` resolves gateway routing as
`opts[:routing] || Application.get_env(:llm_gateway, :routing)` (`apps/referee/lib/referee/run.ex:40`), and `config/runtime.exs` already populates that Application config with live Anthropic routing for **all five classes** (`deliberate`, `adopt`, `interpret`, `narrate`, `summarize`) — but *only if `ANTHROPIC_API_KEY` is in the server process environment at boot* (decision 69). The server script `scripts/web_server.exs` reads no env files, so a server started from a shell without the exported key boots fully offline; the lobby then creates offline runs whose brains can only parrot YAML lines on the deterministic heuristic path (decision 30/88). The `.env` file at `shards_engine/.env` exists but nothing sources it. (The previously logged "10s declare latency when key present" open question proves live mode *has* engaged before — from a shell that had the key.)

Three gaps follow:

1. **Env activation is fragile** — depends on the operator's shell, not the project.
2. **No guardrail** — the lobby silently creates offline runs (the "hard requirement" the user asked for is missing).
3. **The deliberation prompt under-briefs the model** — even live, the current prompt surfaces bare rumor strings and bare agent ids, so output trends toward parroting rather than personal, in-character speech.

## 2. Goals / Non-Goals

**Goals**
- G1: Web play uses the live LLM path whenever the project `.env` carries `ANTHROPIC_API_KEY`, with no shell-dependent steps.
- G2: Lobby **refuses** to create a run when the resolved routing is offline, with an actionable message (hard requirement).
- G3: GM console shows a persistent LIVE/OFFLINE badge for the server's routing state.
- G4: NPC replies are organic and personal: derived at prompt time from each agent's own beliefs, intent, goals, and capabilities; addressed to the specific player; first-person; may ask questions back. No hand-authored speech scripts (user choice: "organically derived from the beliefs, intent, goal and capabilities of each agent").
- G5: Offline deterministic behavior is untouched for TUI/scripts/tests.

**Non-Goals**
- No new LLM vendor or adapter; Anthropic config-only per decisions 36/69.
- No adventure-YAML speech authoring (user rejected hand-authored persona stories).
- No latency tuning of gateway timeouts in this change (see §6).
- No changes to ledger, perception, or directed-speech delivery (decision 88 stands).

## 3. Settled Decisions Honored

- **Decision 69** — automatic Anthropic routing from env; **kept as-is for all five classes**. *Note for review:* this is a superset of the earlier "live scope: deliberate + interpret" answer. `narrate`-live was already verified in the web-9 trial (attributed NPC dialogue in chronicles) and trimming classes now would re-litigate a settled decision for no observed benefit. If per-class trimming is genuinely wanted, it is a follow-up.
- **Decision 88** — directed speech is addressee-private; unaddressed NPCs hold. The prompt changes must not weaken these two behavioral rules.
- **Decision 36** — providers are config; keys are deployment config resolved via `key_ref`, never literals in code.

## 4. Design

### 4.1 Single-source routing builder (`LLMGateway.Config`)

New module `apps/llm_gateway/lib/llm_gateway/config.ex`:

- `routing_from_env/0` — exactly the current `runtime.exs` logic: read `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` (default `claude-haiku-4-5-20251001`), `ANTHROPIC_TIMEOUT` (default 10_000), `ANTHROPIC_ENDPOINT`; when key present return `{keys: %{anthropic_main: key}, routing: %{deliberate | adopt | interpret | narrate | summarize: cfg}}`; else empty maps.
- `apply_env_routing/0` — merge `routing_from_env/0` into `Application.put_env` (only fills, never clobbers scripted test config unless a key is genuinely present).
- `live?/0` — resolved `Application.get_env(:llm_gateway, :routing)` has `interpret` and `deliberate` entries whose `adapter` is not `LLMGateway.Adapters.Scripted`. This is the one definition of "live" used everywhere below.
- `model/0` — model name for display (badge/lobby hint).

`config/runtime.exs` shrinks to `LLMGateway.Config.routing_from_env() |> then(fn %{keys: k, routing: r} -> config(:llm_gateway, keys: k); config(:llm_gateway, routing: r) end)` — no logic drift between boot and re-apply.

### 4.2 `.env` activation in the web server

`scripts/web_server.exs`, before endpoint restart and before any session can be created:

1. Parse `shards_engine/.env` if present (plain `KEY=VALUE` lines, `#` comments, no quotes handling beyond stripping matching outer quotes; ~20 lines, no new dependency). `System.put_env` each var **that is not already set** (explicit shell env wins).
2. Call `LLMGateway.Config.apply_env_routing/0` — because `Run.new` reads Application config lazily **per run creation**, sessions created after this point go live with no server restart and no boot-order trap.
3. Log one line: `[web_server] llm routing: live (claude-haiku-4-5-20251001)` or `offline (set ANTHROPIC_API_KEY)`.

### 4.3 Lobby hard requirement (`ClientWeb.HomeLive`)

At run creation (currently `home_live.ex:52`): unless `LLMGateway.Config.live?/0`, do **not** call `Session.start_link` — flash: "LLM routing is offline. Set ANTHROPIC_API_KEY (see shards_engine/.env) and restart the server to enable live NPC brains." The roster form stays interactive; only the start action is gated. Test configuration injects a non-Scripted stub adapter so client_web tests exercise both branches.

### 4.4 GM badge (`ClientWeb.SpectateLive`)

Server assigns `live: LLMGateway.Config.live?()` and `model: LLMGateway.Config.model/0` at mount; render a static badge in the header: `LIVE · claude-haiku-4-5` or `OFFLINE`. Sessions already in flight keep their own `run.ctx` (truth per run); the badge describes what the *next* run will get — same source as the lobby gate, so the two can never disagree.

### 4.5 Organic deliberation prompt (`Agents.Prompt.deliberate/1`)

Rebuild the user block from the slice alone (organic derivation — no YAML speech authoring). Blocks:

1. **Persona** — name, one-line description, then `intent`, `goal`, `capabilities`, and dossier **history/motives** fields rendered as prose (never the literal word "rumors" for core persona material).
2. **People you can perceive** — from `believed_agents`: `{name, pc}` — players introduced by their character names ("Bramble is an adventurer here"), NPCs by name and role.
3. **Recent speech** — lines attributed by **name**; lines addressed to you rendered as `Mara says to YOU: "..."`; overheard lines explicitly framed as `You overhear ...` and marked "(hearsay — secondhand, may be wrong)".
4. **The moment** — "You were just asked, by <name>: '<their words>'" when addressed (drives answer-the-question instead of topic rotation).
5. **Response contract** — reply rules verbatim:
   - Answer the actual question you were asked, in first person, in your own voice; 1–4 sentences; you may ask a question back.
   - Speak only from your persona block, what you have perceived, and general common-sense life experience of your station. Never invent world facts (names, places, magic) beyond them.
   - If someone just addressed you: `verb "shout"`, **their** id as `target_id`, `message` = your spoken reply, aimed at that person alone.
   - If nobody addressed you and no active commitment demands speaking: `verb "wait"`. Do not volunteer speech unprompted. (decision 88)

System block keeps: JSON schema, capabilities list, tier-3 world honesty ("you act only on your beliefs"). Existing `deliberate_test.exs` contracts stay green; new contract tests in §5.

### 4.6 Offline path

Unchanged. Deterministic heuristic (decision 30/88) remains the fallback when a live call fails mid-run (per-stage fallbacks already exist: interpret→Grammar, deliberate→heuristic) and the only path for TUI/scripts with no key. The hard requirement (§4.3) applies only to the web lobby.

## 5. Acceptance Criteria

1. No key in env → lobby refuses run creation; flash names the remedy; `Session.start_link` not called. (home_live test, config forced offline)
2. Live-shaped routing in config → lobby creates the run; the started session's `run.ctx` routing adapter is live. (home_live test with stub adapter)
3. `web_server.exs` with `.env` present → env sourced (shell value wins), routing applied, boot log states live/offline. (script-level check during smoke)
4. Prompt contracts (prompt/deliberate tests): persona name present; when addressed, the asker's words appear in "You were just asked"; believed PC names rendered by name; hearsay lines labeled; both decision-88 speech rules present verbatim.
5. Full umbrella suite green (engine_core, referee, wire, client_tui, client_web) — decision-88 directed-speech suites unaffected.
6. **Live smoke vs real API** replaying the inn scene: Bram asks Erik about his flock → Erik answers first-person with personal stakes, addressed to Bram alone; Mara/Grevik/Anna stay silent; no verbatim YAML rumor line appears as the reply.

## 6. Risks & Open Questions

- **Declare latency:** the previously logged "10s declare latency" (adapter timeouts stacking behind grammar fallback) is unresolved. This change does not tune timeouts (`ANTHROPIC_TIMEOUT` stays an env knob); the badge + boot log make live state visible, and §5.6 smoke observes real latency. Tuning is follow-up work with measurements in hand.
- **Cadence LLM cost:** cadence deliberation bills every awake, due agent regardless of addressing: `scheduler.ex:188-196` selects all `attention == :alert` cadence-due agents, and `run.ex:315-318` turns each `cadence_tick` into a `Brain.deliberate` RPC — a live, billed `:deliberate` call (`brain.ex:23-27`) even when the likely answer is "hold". With the inn's 4 tier-3 NPCs and Haiku pricing this is small in dollars but adds several seconds to any advance tick where multiple cadences come due (sequential RPCs, adapter timeout + 5 s margin per brain, decision 85). Accepted as-is for this change: NPC self-initiation (approaching, offering, reacting to scene state without an addresser) is real organic behavior worth the cost. Follow-up candidate if it shows in play: an engine-side cheap pre-check — hold deterministically (decision-30 heuristic shape) when the agent has no addresser, no due commitment, and no scene pressure, skipping the LLM entirely; tradeoff is that it amputates exactly that self-initiation behavior in the skip branch.
- **Dossier coverage:** organic derivation leans on YAML persona fields (description, history, motives, intent, goal). Thin fields → thinner personas. The smoke test will show whether Erik's livestock stakes surface from existing YAML material or whether dossier *content* (not speech scripts) needs one authoring pass — flagged now as a possible follow-up, out of scope here.
- **Class trimming deviation:** §3 documents keeping all five classes live (decision 69 superset) against the earlier "deliberate + interpret only" answer; user review of this spec is the sign-off point.
