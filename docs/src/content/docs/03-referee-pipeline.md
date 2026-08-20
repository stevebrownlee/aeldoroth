---
title: "Referee Pipeline"
description: "The five-stage adjudication pipeline, AD&D 1E mechanics, and the three-tier referee preference stack."
order: 3
category: "Architecture"
tags: ["referee", "pipeline", "adnd", "mechanics", "preferences"]
---

# Referee Pipeline

The referee is the single path through which the world changes. Its pipeline has five stages:

```text
Intent ──▶ Interpret ──▶ Validate ──▶ Resolve ──▶ Apply ──▶ Narrate
           (propose)      (pure)     (dice)     (reducer)  (render)
```

Every actor—PC or NPC—enters through this pipeline. The only difference is the shape of stage 1:

- A **PC** declares natural-language intent; the referee must first `interpret` it into a typed action.
- A **tier-3 brain** already emits a typed `Action{verb, target, manner, params}`; interpretation is a no-op.
- Lower-tier agents emit verbs directly from stimulus tables or pack heuristics.

No stage except Apply mutates world state; no stage except Resolve touches dice.

---

## Stage 1: Propose / Interpret

### PC natural-language interpretation

PC input arrives over the wire as natural language:

```json
{
  "event": "declare_intent",
  "payload": {
    "text": "I draw my sword and charge the goblin chief."
  }
}
```

`Referee.Interpret` turns this into one or more typed proposals. The output schema is fixed:

```elixir
%Referee.Action{
  verb: :strike,
  actor: "aelfric",
  target: "grisk",
  manner: "charge_with_longsword",
  params: %{weapon: "longsword", distance: 10}
}
```

### Ambiguity policy

The engine does not ask clarifying questions for every ambiguity. It asks only on **lethal ambiguity**—situations where the wrong target or object would cause unavoidable death, such as:

- "I throw the vial" — which vial?
- "I fire into the melee" — who is shielded?
- "I drink the potion" — which one?

Otherwise the interpreter picks the most plausible parse and records the assumption. The assumption is then narrated, giving the player a chance to correct it on the next tick.

### Agent proposals

Tier-3 brains already emit typed actions. The proposal still passes through the same validation machinery so that a lieutenant cannot propose `parley` if its capability set lacks it, and a terrified goblin cannot propose `guard` while routing.

---

## Stage 2: Validate

Validate is **pure, total Elixir**. It asks four questions in order:

1. **Capability** — does the actor have the verb?
2. **Plausibility vs. beliefs** — is the action consistent with what the actor believes?
3. **Resources** — movement, ammo, spell components, encumbrance.
4. **Preconditions** — door state, engagement range, surprise, line of sight.

A failure at any step returns a rejection, which itself becomes perception: the actor learns *that* the action could not be taken, but not *why* in terms of hidden truth. For example, attempting to open a door that is secretly locked fails diegetically—"the door will not budge"—and updates the actor's belief store with that fact. The hidden trap behind the door is never revealed.

```elixir
# apps/referee/lib/referee/validate.ex (conceptual)
def validate(%Run{} = run, %Action{} = action) do
  with :ok <- capability_check(run, action),
       :ok <- belief_check(run, action),
       :ok <- resource_check(run, action),
       :ok <- precondition_check(run, action) do
    {:ok, action}
  end
end
```

Rejection does not consume a turn. The actor has a retry budget of 3 per tick; if exhausted, the tick passes and is itself narratable.

---

## Stage 3: Resolve

Resolve is the **only place dice exist**. All randomness flows from `EngineCore.Dice` with an explicit RNG state. The same seed always produces the same sequence, which is why verbatim replay is exact.

### Time model

Time is measured in segments, rounds, turns, and watches:

```text
1 segment   = 6 seconds
1 round     = 10 segments = 60 seconds
1 turn      = 10 minutes
1 watch     = 4 hours
```

- **Exploration mode** jumps event-to-event: next PC declaration, next commitment due, next signal arrival, next cadence tick.
- **Combat mode** advances segment-by-segment. Combat engages automatically on confirmed mutual hostility and is ledgered as a `meta` event.

### Initiative and segment order

At combat start:

1. Roll surprise on `1d6` for each side.
2. Each combatant rolls initiative: `1d6` ± Dexterity reaction adjustment.
3. Segment order is fixed for the round.
4. Missile fire and spell casting with casting times occupy specific segments.

```text
Round 1, segment 4
───────────────────────────────────────
seg 1  archer (missile)
seg 2  mage   (magic missile, 1 seg)
seg 3  cleric (initiative 3)
seg 4  goblin (initiative 4)  ──▶ strike vs aelfric
seg 5  fighter (initiative 5)
...
seg 10 end of round; morale checks if threshold met
```

### THAC0 and armor class

The AD&D 1E to-hit matrix is central to melee and missile resolution:

```text
THAC0 = the roll needed to hit AC 0
needed roll = THAC0 - target_AC
```

For example, a fighter with `THAC0 19` attacking a goblin with `AC 7` needs:

```text
19 - 7 = 12+ on 1d20
```

A natural 20 is always a hit; a natural 1 is always a miss. Shields, Dexterity, magic, and rear/flank modifiers are applied before the roll is evaluated.

The goblin chief Grisk in the seed YAML:

```yaml
thac0: 17
armor_class: 6
hit_dice: 1d8+1
hit_points: 8
max_hit_points: 8
morale: 10
```

### Saving throws

When a trap, spell, or poison demands a save, the target rolls on its class-appropriate table. The engine records:

```elixir
%dice{
  type: :saving_throw,
  save: :poison,
  target: 13,
  roll: 11,
  result: :fail
}
```

Failure applies the listed effect: falling into a pit, paralysis, death poison, etc.

### Morale

Monsters roll morale when:

- their leader falls,
- they lose 50% or more of their group,
- they are surprised and outnumbered,
- a special trigger in the YAML fires.

A failed morale check sends the creature or group into flight or surrender, depending on `Intelligence` and corneredness. Morale is a `2d6` roll against the creature's morale score; roll higher than morale = break.

### Damage and death

Damage subtracts from `body.hp`. At 0 hp, the actor is `dying`; at negative hp equal to `-level`, death. Monster removal grants XP according to the preference stack, described below.

---

## Stage 4: Apply

Apply is a single-writer reducer. `EngineCore.World.Server` serializes all applies.

```elixir
# apps/engine_core/lib/engine_core/fold.ex (conceptual)
def apply(%Event{class: :world, type: :strike} = ev, %World{} = world) do
  world
  |> update_actor_body(ev.actor, &damage(&1, ev.payload.damage))
  |> maybe_kill(ev.payload.target)
  |> emit_signal({:sound, :melee, ev.place_id, ev.payload.loudness})
  |> maybe_wake_boundaries(ev.place_id)
end
```

Applied actions emit **side-effect signals**: a torch is visible, melee is audible, a broken glass vial smells of vinegar. These signals enter the perception economy and become the only way other agents learn what happened.

---

## Stage 5: Narrate

Narrate is a **light** LLM call (or template fallback under budget pressure). It renders the perceivable signal set for each receiving actor at that actor's fidelity tier.

The prompt is constrained by the truth barrier: it receives only what the actor can perceive. It chooses words, not facts. A low-Intelligence fighter might receive:

```text
You hear a clash of steel somewhere to the north—faint, perhaps beyond the passage.
```

A high-Intelligence elf in the same room might receive:

```text
You hear two weapons meeting in the corridor north of here; the rhythm suggests a longsword parrying a crude blade.
```

The same event produces different text, but the underlying signals are identical.

---

## AD&D 1E Mechanics Reference

The engine implements a deterministic subset of AD&D 1E core procedures.

### Combat sequence

1. Declare intent (before rolls).
2. Check surprise (`1d6`, modified by Dexterity, alertness, and situation).
3. Determine engagement and range.
4. Roll initiative per side or per combatant (`1d6`).
5. Resolve actions in segment order.
6. Apply damage and check death/dying.
7. At round end, check morale if threshold met.

### THAC0 matrix (simplified)

| Attacker THAC0 | Hit AC 10 | Hit AC 7 | Hit AC 5 | Hit AC 2 | Hit AC 0 |
|----------------|-----------|----------|----------|----------|----------|
| 20             | 10+       | 13+      | 15+      | 18+      | 20+      |
| 19             | 9+        | 12+      | 14+      | 17+      | 19+      |
| 17             | 7+        | 10+      | 12+      | 15+      | 17+      |
| 15             | 5+        | 8+       | 10+      | 13+      | 15+      |

Dexterity reaction adjustment, shields, magic, rear/flank, and called-shot penalties are applied before comparing to needed roll.

### Armor class calculation

```text
AC = 10
     - armor bonus
     - shield bonus
     - Dexterity reaction adjustment
     - magical bonus
     + encumbrance / surprise / rear penalty
```

Lower is better. AC can be negative.

### Saving throw categories

The engine tracks the classic categories:

- Paralysis / Petrification / Polymorph
- Poison / Death magic
- Rod / Staff / Wand
- Breath weapon
- Spell

The target number comes from the actor's class/level table and is modified by race, magic, and situation.

### Morale break checks

```elixir
# roll > morale_score → break
roll = :rand.uniform(6) + :rand.uniform(6)  # 2d6
if roll > morale_score do
  :break
else
  :hold
end
```

Grisk has morale 10: he holds on 10 or less, breaks on 11–12. A leaderless goblin with morale 7 breaks on 8–12.

### 1 gp = 1 XP reward loop

The Ruined Tower ships with the classic campaign convention:

```yaml
preferences:
  xp:
    gold_per_xp: 1          # 1 gp recovered = 1 XP
    creative_bonus: true     # clever monster removal grants bonus XP
```

When a monster is removed, XP is awarded based on hit dice and special abilities. When treasure is recovered, each gp adds one XP. When a player finds a clever, non-combat way to remove a threat—luring wolves into a pit, tricking goblins into fleeing, collapsing the ceiling on the skeleton—a `creative_bonus` event is logged and XP is awarded with rationale.

```elixir
%Event{
  class: :world,
  type: :xp_award,
  payload: %{
    base: 75,              # monster HD value
    gp: 42,                # recovered coin
    creative: 25,          # bonus for luring wolves into the pit
    reason: "Wolves lured into the collapsed lab pit; no direct combat"
  }
}
```

---

## The Three-Tier Preference Stack

Adjudication is never fully hard-coded. Preferences layer on top of core rules and resolve per-key, with higher tiers overriding lower ones.

```text
core 1E rules  ⊂  module preferences  ⊂  personal referee YAML
 (engine)         (ships with adventure)   (human referee's)
```

### Core rules

The engine ships with deterministic interpretations of AD&D 1E procedures: segment/round/turn time, THAC0, saves, morale, and the standard XP tables.

### Module preferences

The adventure YAML can override core defaults:

```yaml
preferences:
  tone: "grim-but-heroic"
  narration_style: "terse"
  lethality: "standard"
  dice_visibility: "open"
  xp:
    gold_per_xp: 1
    creative_bonus: true
```

The Ruined Tower uses this layer to establish the `1 gp = 1 XP` house rule and creative-action bonuses.

### Personal referee YAML

The human running the game may supply their own `referee_defaults.yaml`:

```yaml
lethality: "hardcore"
dice_visibility: "hidden"
narration_style: "florid"
xp:
  creative_bonus: false
```

Per-key resolution: highest-defined wins. Unknown keys warn and fall back to the next lower tier. The resolved stack is hashed into a `meta` event at run start, so replays adjudicate identically.

```elixir
%Event{
  class: :meta,
  type: :preferences_resolved,
  tick: 0,
  payload: %{
    hash: "sha256:...",
    sources: [
      "core/rules.yaml",
      "the-ruined-tower/ruined_tower.yaml",
      "~/.shattered-kingdoms/referee_defaults.yaml"
    ]
  }
}
```

---

## Truth Barrier

Referee prompts never contain world truth. The slice builder constructs each actor's view from:

- its own belief store,
- signals that have arrived at its current place,
- its own body, inventory, and commitments,
- publicly visible place state (doors the actor knows are open).

Hidden items, other rooms, other PCs' private prompts, and preference internals are excluded. The `slice` event class records what went into each LLM prompt, enabling the oracle-leak audit.

This barrier is what makes fork-diff emergence meaningful: two runs diverge not because some agent learned hidden truth, but because the same perceivable slice produced different deliberations.
