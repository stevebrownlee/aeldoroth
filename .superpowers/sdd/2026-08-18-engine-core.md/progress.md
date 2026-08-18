# SDD Progress — 2026-08-18-engine-core.md

## Status
- [X] Task 1: Umbrella scaffold — commit bbff0b1
- [X] Task 2: Core type structs + world — Wave A, commit 64bdb70
- [X] Task 5: Append-only event ledger — Wave A, commit 64bdb70
- [X] Task 7: Seeded dice — Wave A, commit 64bdb70
- [X] Task 3: YAML validator — Wave A, commit 64bdb70 (YAML repair no-op: file intact; validator adapted to real schema)
- [X] Task 4: YAML loader — Wave B, commit b5b792d; fix-round commit bd5b6e6
- [X] Task 6: Fold — Wave B, commit b5b792d; fix-round (tick monotonicity) bd5b6e6
- [X] Task 8: Movement — Wave B, commit b5b792d; fix-round (dead-agent guard) bd5b6e6; directionality fix 8d7a714
- [X] Task 9: Combat — Wave B, commit b5b792d; fix-round (:death emission + fold mirror) bd5b6e6
- [X] Task 10: Morale & saves — Wave B, commit b5b792d; fix-round (leader check, string hit_dice parse) bd5b6e6
- [X] Task 11: Scenario + golden replay — commit bd5b6e6 (fold pass-through clause for audit events)
- [X] Full gates: 43/43 tests, zero warnings, wall-clock grep clean, plan-verbatim CLI smoke `events=259 tick=90`
- [ ] Final whole-branch review — FinalReview dispatched

## Review history
- WaveBReviewer (post-Wave-B): 8 findings, overall incorrect — 2 crashers (Fold vs dice events [pre-T11, already fixed], Saves vs string hit_dice), morale always-true, sealed-edge lock-drop, missing :death emission, dead-agent movement, tick rewind, weak test pins.
- Fix round: 5 parallel owner-scoped dispatches (T6FoldFix, T4LoaderFix, T8MovementFix, T9CombatFix, T10MoraleSavesFix) + inline scenario mark_deaths removal (dead code post-T9Fix). Gate 42/42.
- ReReviewer: all 8 verified closed; 1 new P2 — Movement.check_edge matched edges in either direction (sealed one-way exit shadowed unsealed reverse). Fixed 8d7a714 + pinning test; gate 43/43.

## Deviations from plan (flagged for overrule)
- Parallel implementer waves (orchestration contract) override SDD serial-implementer rule; subagents edit-only, no commits; orchestrator gates per wave.
- Validator/loader adapted to real YAML schema (rooms map + exits map, initial_enemies/initial_treasure, string hit_dice/damage_per_attack) vs plan's assumed shape; plan test semantics preserved.
- Scenario drops plan's mark_deaths step: Combat now owns :death emission; golden replay (byte-identical rerun + fold==world) proves the invariant.
- Scenario smoke numbers differ from plan sketch (plan pins none): events=259 tick=90 at seed 1234.
