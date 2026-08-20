---
identifier: active_context
title: Active Context
created: 2026-08-20T13:38:42Z
---
# Active Context

```json
{
  "content": {
    "current_focus": "Play surface & GM console UX redesign spec in user review (docs/superpowers/specs/2026-08-20-play-surface-ux-design.md)",
    "current_plan": "Plan 5 (protocol-live-runs) COMPLETE",
    "decisions": [
      47,
      48,
      49,
      50,
      55
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
    "next": "post-v1: client_web LiveView client (spec §11), then v2 campaign memory (decision 34) / platform seams (decision 35)",
    "next_session": "After spec approval: writing-plans for Phase A (player surface + lobby)",
    "next_steps": [
      "develop commercial marketplace storefront and billing features",
      "explore v2 cross-run campaign memory layer",
      "run live campaign play sessions of The Ruined Tower"
    ],
    "open_questions": [
      "Verb palette set — core ten vs campaign-specific (Pry, Listen at door)",
      "Advance-until-input cap (proposed 20 steps)",
      "GM flow board: show believed monster HP or keep referee-only",
      "Roster builder: canonical four seats vs arbitrary party size"
    ],
    "open_threads": [
      "referee suite had one transient port-race failure under parallel sweep — isolated runs green, watch for recurrence"
    ],
    "phase": "spec 12.4 phase 7 done",
    "progress_state": "All enemies alive, no treasure collected, session log empty (as of 2026-08-17)",
    "session_checklist": [
      "Update ruined_tower.yaml is_alive/is_collected after play",
      "Fill xp-reference session log + creative bonus tracker",
      "Tick treasure-checklist.md boxes",
      "Log session progress + decisions into engrams"
    ],
    "spec": "docs/superpowers/specs/agent-engine-spec.md",
    "tests": "232 green umbrella (engine_core 97, llm_gateway 38, agents 25, referee 72)",
    "v1_status": "all 8 spec phases complete (plans 1-6); acceptance harness green, exits 0",
    "watch": "Party's choice for the Shadow-Crystal (keep/sell/study/destroy) is the Act 1 pacing lever"
  },
  "name": "default",
  "updated_at": "2026-08-20T13:38:42Z",
  "version": 12
}
```
