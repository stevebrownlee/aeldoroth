---
title: "Adventure Authoring YAML"
description: "Immutable seed state format for The Shattered Kingdoms adventures, with a complete anatomy of ruined_tower.yaml and the Loader that turns it into a World."
order: 8
category: "Protocol & Tooling"
tags: ["adventure", "yaml", "loader", "world", "seed", "content-authoring"]
---

# Adventure Authoring YAML

The Shattered Kingdoms separates *content* from *engine*. The engine is an Elixir umbrella of pure functions, GenServers, and wire channels; the content is a single YAML file that describes an adventure's geography, inhabitants, treasures, traps, and referee defaults. The engine never mutates that file. Instead, `EngineCore.Loader` validates it once and builds an immutable `%EngineCore.World{}` that becomes the seed for every run.

This chapter walks through `the-ruined-tower/ruined_tower.yaml` field by field and shows how each section maps to the structs in `EngineCore.Types`.

## Content / engine split

| Concern | Owned by YAML | Owned by engine |
| ------- | ------------- | --------------- |
| Rooms, exits, traps, treasure, NPC statblocks | yes | no |
| Cognition tier, capability caps, cadence | inferred from YAML id / type | yes |
| Activation rules, boundaries, commitments | declared in YAML | evaluated by engine |
| XP style, tone, lethality defaults | declared in YAML preferences | merged with core + personal referee YAML |
| Dice rolls, saves, morale checks, initiative | no | yes |
| LLM prompts and routing | no | yes |

A module author writes content. The engine supplies the physics of AD&D 1E and the LLM referee.

## Top-level adventure metadata

```yaml
name: "The Ruined Tower"
description: "A collapsed wizard's tower infested by goblins who have been raiding the nearby village of Thornhollow. The tower hides secrets of shadow magic and failed rituals from 30 years ago. Recommended for 4 level 1 characters."
recommended_level: "1"
difficulty_level: "balanced"
starting_room: "entry_hall"
opening_narrative: "You stand in the warm common room of Mara's inn in Thornhollow..."
```

The Loader carries `starting_room` into `%World{starting_place_id: "entry_hall"}` so the run session knows where to position newly created PCs. The `recommended_level` and `difficulty_level` are opaque metadata surfaced to the web home page; the engine ignores them for balance because 1E balance is determined by the actual statblocks and coin values placed in the module.

## Places and edges

### `rooms:` place graph

A room becomes a `EngineCore.Types.Place`:

```elixir
defmodule EngineCore.Types.Place do
  @enforce_keys [:id, :name, :kind, :connections]
  defstruct [:id, :name, :kind, :connections]
end
```

Example from `ruined_tower.yaml`:

```yaml
rooms:
  entry_hall:
    id: "entry_hall"
    name: "Entry Hall"
    description: "A stone-floored hall..."
    terrain: "stone floor"
    lighting: "dim torchlight"
    structures: ["collapsed stairwell", "statue of Vaelith"]
    exits:
      north: "guard_room"
      east: "library"
```

The Loader builds the connections map from `exits`:

```elixir
%{"north" => %{target: "guard_room", sealed: false},
  "east"  => %{target: "library", sealed: false}}
```

### Edge extraction and door state

For every exit the Loader emits a `Types.Edge`:

```elixir
defmodule EngineCore.Types.Edge do
  @enforce_keys [:id, :from, :to]
  defstruct [
    :id, :from, :to,
    sealed: false,
    label: nil,
    permeability: %{sight: :open, sound: :open}
  ]
end
```

The id is deterministic: `:"#{from}__#{to}"`. A sealed edge blocks movement. A locked door is represented by the richer exit form:

```yaml
exits:
  south:
    target_room_id: "hidden_chamber"
    is_locked: true
    password_required: "Lux Memoriae"
```

`extract_exits/1` treats `is_locked: true` or a non-empty `password_required` as `sealed: true`. The Referee or an agent can later unlock it by an action that produces an `unseal` event.

### Permeability and line of sight

The YAML does not explicitly tag every edge. The engine derives default permeability from `sealed`: a sealed edge is closed to both sight and sound; an open edge is open to both. Future modules may override this with `permeability: {sight: open, sound: muffled}`.

## Agents: statblocks and cognition tiers

### The `initial_enemies:` map

`ruined_tower.yaml` stores every NPC and monster under `initial_enemies` keyed by id. A representative goblin guard:

```yaml
goblin_guard_1:
  id: "goblin_guard_1"
  name: "Goblin Guard"
  type: "goblin"
  description: "A wiry goblin in scavenged leather armor..."
  strength: 8
  dexterity: 14
  constitution: 9
  intelligence: 8
  wisdom: 10
  charisma: 6
  hit_dice: "1d8-1"
  hit_points: 4
  max_hit_points: 4
  armor_class: 6
  thac0: 20
  attacks_per_round: 1
  damage_per_attack: ["1d6"]
  movement_rate: 60
  special_abilities:
    - "Surprise on 1-3 in dim light"
    - "Speak goblin and broken common"
  saving_throws:
    paralyzation_poison_death_magic: 14
    petrification_polymorph: 16
    rod_staff_wand: 15
    breath_weapon: 17
    spell: 16
  treasure_type: "Individual (10 gp)"
  current_room_id: "guard_room"
  morale: 7
  is_alive: true
```

The Loader turns this into a `Types.Agent` with a `statblock`, `body`, `capabilities`, and `cadence`.

### `agent_from/1`

```elixir
defp agent_from(m) do
  tier = tier_of(m["id"])
  hp = m["hit_points"] || m["hp"] || 1

  %Types.Agent{
    id: m["id"],
    name: m["name"] || m["id"],
    tier: tier,
    place_id: m["current_room_id"] || m["room_id"] || m["location_room_id"],
    statblock: %{
      ac: m["armor_class"] || m["ac"] || 10,
      hd: parse_hd(m["hit_dice"] || m["hd"]),
      hp_max: hp,
      thac0: m["thac0"] || 20,
      morale: m["morale"] || 7,
      int: m["intelligence"] || m["int"] || 8,
      damage: parse_damage(m)
    },
    body: %{hp: hp, conditions: []},
    capabilities: caps(tier),
    group: m["type"],
    cadence: cadence_for(tier)
  }
end
```

### Tier mapping

Cognition tier is not declared in the YAML. It is inferred by id so that authors cannot accidentally give a giant rat tier-3 deliberation. The Loader keeps three hard-coded lists:

```elixir
@tier3 ~w(grisk_the_snatcher grisk snaga skrit varg murg willem
          goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4
          goblin_bodyguard_1 goblin_bodyguard_2)
@tier2 ~w(wolf_1 wolf_2 wolf_pair rat_pack_1 rat_pack_2)
@tier0 ~w(shadow_touched_skeleton shadow_skeleton tripwire_trap_1 tripwire_trap_2)
```

`tier_of/1` returns `3`, `2`, `0`, or `1` as the default. That maps to:

| Tier | Capabilities | Cadence |
| ---- | ------------ | ------- |
| 0 | `[:move, :strike, :wait]` | every 2 ticks |
| 1 | `[:move, :strike, :wait]` | none (reactive) |
| 2 | `[:move, :strike, :wait, :flee]` | every 5 ticks |
| 3 | full set including `parley`, `hide`, `obey`, `order` | every 10 ticks |

Tier 0 is for traps, environmental hazards, and mindless undead. Tier 3 is for named villains and tactically interesting enemies who deliberate with the LLM.

## Items and treasure

Items live in `initial_treasure`, but the Loader also accepts the alias `treasures`:

```yaml
initial_treasure:
  healing_potion:
    id: "healing_potion"
    name: "Potion of Healing"
    description: "A small glass vial containing a red liquid..."
    value: 50
    type: "potion"
    effect: "Restores 1d8 hit points"
    location_room_id: "entry_hall"
    weight: 0.5
    is_hidden: false
    is_magical: true
```

```elixir
defp item_from(t) do
  %Types.Item{
    id: t["id"],
    name: t["name"] || t["id"],
    value_gp: t["value"] || t["value_gp"] || 0,
    place_id: t["location_room_id"] || t["place_id"],
    holder_id: t["holder_id"],
    is_hidden: t["is_hidden"] == true
  }
end
```

`Types.Item` keeps only the fields the engine needs: id, name, value in gp, place or holder, and hiddenness. Descriptive fields such as `effect`, `weight`, and `is_magical` are passed through to the YAML and may be surfaced by the Referee's narration LLM, but the engine does not model them directly.

Treasure caches are a special case. `ruined_tower.yaml` uses `contains:` to nest items inside one another, which prevents double-counting the global value:

```yaml
vaeliths_hidden_wall_cache:
  id: "vaeliths_hidden_wall_cache"
  value: 250
  coins:
    pp: 50
  contains: ["three_gems"]
```

## Boundaries: waking the dungeon

`boundaries` declare when dormant agents should activate. The canonical example guards the entry hall and corridor:

```yaml
boundaries:
  - id: "guard_room_zone"
    place: "guard_room"
    triggers: ["presence_crossing", "signal_arrived"]
    bound_agent_ids:
      - "goblin_guard_1"
      - "goblin_guard_2"
    sleep_after: 40
    wake_on_intensity: 4
  - id: "east_passage_patrol"
    group: "goblin_patrol"
    triggers: ["coarse_tick"]
```

`EngineCore.Boundaries.evaluate/2` matches a boundary when an event of a listed class crosses its scope. A boundary can be scoped by `place`, by `group`, or explicitly by `bound_agent_ids`. The Loader resolves `group` membership by `agent.group` and `place` membership by `agent.place_id`.

```elixir
defmodule EngineCore.Types.Boundary do
  @enforce_keys [:id, :bound_agent_ids, :triggers]
  defstruct [
    :id,
    :scope_place_id,
    :scope_group,
    :bound_agent_ids,
    :triggers,
    state: :dormant,
    last_trigger_tick: nil,
    wake_on_intensity: 4,
    sleep_after: 40
  ]
end
```

Valid trigger atoms are `presence_crossing`, `signal_arrived`, `commitment_due`, and `coarse_tick`. Anything else is rejected as `:invalid` by `put_boundaries/2` and will fail validation.

## Hazards: traps and alarms

Hazards are room-scoped traps. They are declared under `rooms.<room>.traps`:

```yaml
rooms:
  chiefs_room:
    traps:
      - id: "pit_trap"
        type: "pit_trap"
        difficulty_class: 14
        bound_exit: "south"
        damage_dice: 1
        damage_sides: 6
        damage_plus: 0
```

The Loader converts every trap into a `Types.Hazard`:

```elixir
defmodule EngineCore.Types.Hazard do
  @enforce_keys [:id, :kind, :place_id]
  defstruct [
    :id, :kind, :place_id,
    edge_id: nil,
    dc: 12,
    triggered: false,
    damage: %{dice: 1, sides: 4, plus: 0},
    signal_intensity: 9,
    signal_class: :alarm
  ]
end
```

`hazard_kind/1` classifies `type: "alarm"` as `:alarm` and everything else as `:damage`. Alarm hazards broadcast a signal with intensity `9`; damage hazards emit a combat signal with intensity `6`. The optional `bound_exit` lets a hazard know which edge it protects via `edge_id_for/3`.

## Initial commitments

Commitments seed agent obligations before any LLM runs:

```yaml
initial_commitments:
  - id: "guard_watch_rotation"
    debtor: "goblin_guard_1"
    deed: "keep_watch"
    due: 30
    every: 30
    priority: 5
  - id: "east_passage_patrol"
    debtor: "goblin_guard_3"
    deed: "patrol_east_passage"
    due: 45
    every: 45
    priority: 4
  - id: "grisk_relocation_deadline"
    debtor: "grisk_the_snatcher"
    deed: "relocate_treasure_if_alarmed"
    due: 120
    priority: 8
```

`put_commitments/2` converts each entry into a `Types.Commitment` and appends it to the debtor agent's `commitments` list. A commitment with `every:` repeats after it is kept; without it the commitment fires once.

```elixir
%Types.Commitment{
  id: "guard_watch_rotation",
  debtor: "goblin_guard_1",
  creditor: nil,
  deed: "keep_watch",
  due: 30,
  every: 30,
  priority: 5,
  status: :pending
}
```

## Module preference layer

The YAML declares how the Referee should interpret rulings for this module:

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

`Referee.Preferences.resolve/2` deep-merges three layers:

1. **Core defaults** hard-coded in `Referee.Preferences`.
2. **Module preferences** from the adventure YAML.
3. **Personal referee preferences** from a separate YAML supplied at session start.

The merge keeps only known keys; unknown keys are dropped with a warning. This prevents a third-party module from silently changing fields that should belong to the engine. `hash/1` produces a stable md5 of the resolved tree so two runs with the same module and same personal preferences hash to the same value.

## Loading and validation pipeline

A run starts with a single call:

```elixir
EngineCore.Loader.load("content/adventures/the-ruined-tower/ruined_tower.yaml")
```

Steps:

1. `YamlElixir.read_from_file/1` parses the file.
2. `EngineCore.Validator.check/1` runs structural checks:
   - required monster fields (`id`, `name`, `hit_dice`, `hit_points`, `armor_class`, `thac0`, `morale`, `current_room_id`);
   - exit targets point to declared rooms;
   - boundary debtors reference declared agents;
   - `coarse_tick` cannot be used on a group-scoped boundary.
3. `Loader.build/1` constructs `World` with nested `Place`, `Edge`, `Agent`, `Item`, `Boundary`, `Hazard`, and seed beliefs.
4. `apply_dormancy/1` sets `attention: :dormant` on every agent bound by a dormant boundary.

The resulting `%EngineCore.World{}` is frozen. The `Referee.Run.Session` seeds per-run processes from it, and checkpoints preserve the original seed alongside the live journal so that restore can replay from the same immutable starting point.

## Summary

The adventure YAML is the contract between author and engine. It stays small enough to read in one sitting and structured enough that the Loader can turn it into typed Elixir structs without creative interpretation. By keeping the content in data and the engine in code, The Shattered Kingdoms lets module authors write new dungeons without changing the runtime and lets engine maintainers improve AI reasoning without touching existing adventures.
