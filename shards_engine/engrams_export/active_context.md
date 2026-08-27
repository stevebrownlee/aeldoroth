---
identifier: active_context
title: Active Context
created: 2026-08-27T17:39:11Z
---
# Active Context

```json
{
  "content": {
    "current_focus": "4 full multi-seat rounds verified live across GM and 2 player sessions without errors or inconsistencies (decisions 80-81)",
    "current_plan": "Next: LLM-live mode (real API key) full-session trial; parley/hide/obey/flee resolvers",
    "decisions": [
      47,
      48,
      49,
      50,
      55,
      58,
      59,
      60,
      61,
      64,
      65,
      66,
      67,
      68,
      69,
      70,
      71,
      73
    ],
    "expanded": {
      "content": {
        "current_focus": "Plan 3 (spec phase 5) DONE: llm_gateway + referee pipeline landed headless, 185 tests green, golden replay determinism + referee CLI smoke proven",
        "next_session": "Plan 4 (spec §12.4 phase 6): tier-3 brains as supervised OTP actors on cadence_tick, salience gate, envelopes + autonomous adoption; plug into cadence_tick events Plan 2/3 emit",
        "open_questions": [
          "Live vendor routing config (config-only per decision 36) — scripted adapter is the only tested path",
          "PC signal reception during declare react produces no advance narrations in smoke — engine (Plan 2) cadence behavior, verify in Plan 4"
        ]
      }
    },
    "flaws_fixed": [
      "World.Server transient restart loop",
      "zero-timeout assert race",
      "caller-linked sessions"
    ],
    "last_session": {
      "date": "2026-08-26",
      "open": "Spec open questions for user: verb palette set, cap tuning, believed monster HP on GM board, roster scope",
      "work": "Fixed Erlang :httpc timeout placement in HTTPOptions for Anthropic and OpenAICompat adapters, added ANTHROPIC_TIMEOUT support, and verified seamless grammar fallback during Session.declare to avoid referee timeouts and synchronize GM flow board. All 408 tests green."
    },
    "last_task": "directed-speech-custom-responses",
    "next": "run Session 1 Thornhollow",
    "next_session": "After spec approval: writing-plans for Phase A (player surface + lobby)",
    "next_steps": [
      "develop commercial marketplace storefront and billing features",
      "explore v2 cross-run campaign memory layer",
      "run live campaign play sessions of The Ruined Tower"
    ],
    "open_questions": [
      "Unexplained 10s declare latency when ANTHROPIC_API_KEY present in server env (live adapter timeouts stack behind grammar fallback)",
      "dir_phrase says somewhere nearby for co-located speech — cosmetic"
    ],
    "open_threads": [],
    "phase": "spec 12.4 phase 7 done",
    "progress_state": "All enemies alive, no treasure collected, session log empty (as of 2026-08-17)",
    "session_checklist": [
      "Update ruined_tower.yaml is_alive/is_collected after play",
      "Fill xp-reference session log + creative bonus tracker",
      "Tick treasure-checklist.md boxes",
      "Log session progress + decisions into engrams"
    ],
    "spec": "docs/superpowers/specs/agent-engine-spec.md",
    "state": "done: 423/423 green, session-end protocol run",
    "tests": "408 green umbrella (engine_core 115, llm_gateway 41, agents 27, referee 142, wire 31, client_tui 14, client_web 38)",
    "v1_status": "all 8 spec phases complete (plans 1-6); acceptance harness green, exits 0",
    "watch": "Party's choice for the Shadow-Crystal (keep/sell/study/destroy) is the Act 1 pacing lever"
  },
  "name": "default",
  "updated_at": "2026-08-27T17:39:11Z",
  "version": 30
}
```
