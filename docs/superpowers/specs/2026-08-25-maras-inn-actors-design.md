# Mara's Inn Actors & BDI Cognition Design

**Date:** 2026-08-25  
**Status:** Approved  
**Topic:** Defining Mara, Mayor Grevik, and tavern patrons as first-class AD&D 1E Tier-3 agents with dynamic BDI goals, spatial boundaries, and conversational capabilities.

---

## 1. Overview & Objectives

In *The Shattered Kingdoms* starter adventure (*The Ruined Tower*), player characters start in the warm common room of Mara's Inn (`maras_inn`) in the village of Thornhollow.

This design adds 4 fully statted AD&D 1E actors to the common room, equips them with Tier-3 cognition (enabling `:parley`, `:shout`, `:order`, `:obey`, and social interaction), sets up their initial commitments, and extends the `shards_engine` loader/prompt pipeline to thread their personality dossiers and goals directly into LLM deliberation.

### Key Goals
1. **Interactive Quest Initiation:** Mayor Grevik initiates the adventure in-engine by proposing his 100 gp bounty to investigate livestock raids and strange lights at the ruined tower.
2. **Emotional Stakes & Secondary Quests:** Anna Mordale pleads for her missing husband Willem (captive in Room 4) with a 20 gp reward.
3. **Tactical Eyewitness Intelligence:** Erik the Shepherd provides tactical reconnaissance on goblin numbers, weapons, and movements.
4. **Tavern Hospitality & World Lore:** Mara tends the counter, serves warm mutton stew and spiced ale, and shares rumors of Vaelith the Mirage-Weaver's ghost.
5. **Engine-Level Support:** Enable adventure YAMLs to specify explicit cognition tiers (`tier: 3`) and rich `dossier` maps that pass through the truth barrier to prompt generation.

---

## 2. Adventure YAML Specifications (`the-ruined-tower/ruined_tower.yaml`)

### 2.1 Actor Statblocks & Dossiers (`initial_actors:`)

Four actors are placed in `current_room_id: "maras_inn"`:

```yaml
initial_actors:
  mara:
    id: "mara"
    name: "Mara"
    type: "human_innkeeper"
    description: "A warm, motherly woman who runs the village inn. Treats travelers like family, keeps everyone fed, and knows all the local gossip."
    strength: 10
    dexterity: 11
    constitution: 12
    intelligence: 12
    wisdom: 13
    charisma: 14
    hit_dice: "1d8"
    hit_points: 6
    max_hit_points: 6
    armor_class: 10
    thac0: 20
    attacks_per_round: 1
    damage_per_attack: ["1d4"]
    movement_rate: 120
    saving_throws:
      paralyzation_poison_death_magic: 14
      petrification_polymorph: 16
      rod_staff_wand: 15
      breath_weapon: 17
      spell: 16
    current_room_id: "maras_inn"
    morale: 8
    tier: 3
    is_alive: true
    dossier:
      role: "Innkeeper & Hostess"
      personality: "Warm, observant, nurturing, but protective of her tavern and neighbors."
      speech_style: "Colloquial, hospitable, pours ale while speaking."
      goals:
        - "Keep the hearth warm, serve hot mutton stew and spiced ale (3 sp)."
        - "Look out for frightened villagers and soothe tensions."
      rumors:
        - "Old Vaelith's tower was silent for thirty years until two weeks ago. Some say his ghost is angry."
        - "Willem's wife Anna has barely slept since he disappeared up the hill."

  mayor_grevik:
    id: "mayor_grevik"
    name: "Mayor Grevik"
    type: "human_leader"
    description: "A weathered man in his sixties with kind, sorrowful eyes and a heavy brow. He carries the weight of Thornhollow's safety."
    strength: 10
    dexterity: 9
    constitution: 10
    intelligence: 13
    wisdom: 14
    charisma: 13
    hit_dice: "1d8"
    hit_points: 5
    max_hit_points: 5
    armor_class: 10
    thac0: 20
    attacks_per_round: 1
    damage_per_attack: ["1d4"]
    movement_rate: 120
    saving_throws:
      paralyzation_poison_death_magic: 14
      petrification_polymorph: 16
      rod_staff_wand: 15
      breath_weapon: 17
      spell: 16
    current_room_id: "maras_inn"
    morale: 7
    tier: 3
    is_alive: true
    dossier:
      role: "Village Mayor & Quest Giver"
      personality: "Solemn, earnest, desperate for capable defenders, protective of the village."
      speech_style: "Measured, grave, authoritative yet pleading."
      goals:
        - "Recruit capable adventurers to investigate the Ruined Tower and end the raids."
        - "Offer a 100 gold piece bounty from the village coffers for stopping the threat."
      knowledge:
        - "Raids started 2 weeks ago; livestock slaughtered, houses breached on the perimeter."
        - "Greenish lights flicker in the ruins every night."

  erik_the_shepherd:
    id: "erik_the_shepherd"
    name: "Erik the Shepherd"
    type: "human_farmer"
    description: "A gruff, weathered shepherd in stained wool, nursing a pint of ale with trembling, calloused hands."
    strength: 13
    dexterity: 12
    constitution: 12
    intelligence: 9
    wisdom: 11
    charisma: 9
    hit_dice: "1d8"
    hit_points: 7
    max_hit_points: 7
    armor_class: 10
    thac0: 20
    attacks_per_round: 1
    damage_per_attack: ["1d6"]
    movement_rate: 120
    saving_throws:
      paralyzation_poison_death_magic: 14
      petrification_polymorph: 16
      rod_staff_wand: 15
      breath_weapon: 17
      spell: 16
    current_room_id: "maras_inn"
    morale: 6
    tier: 3
    is_alive: true
    dossier:
      role: "Eyewitness & Raid Victim"
      personality: "Bitter, angry, shaken by the loss of his livelihood."
      speech_style: "Blunt, agitated, gestures emphatically."
      goals:
        - "Demand justice for his slaughtered sheep."
        - "Warn adventurers about the raiders' numbers and appearance."
      knowledge:
        - "Saw yellowish-green skin, pointed teeth, and crude short swords carrying off sheep 2 nights ago."
        - "They fled directly toward the old trail leading to Vaelith's tower."

  anna_mordale:
    id: "anna_mordale"
    name: "Anna Mordale"
    type: "human_villager"
    description: "A young village woman with red, tear-stained eyes, clutching a hand-knitted scarf tightly against her chest."
    strength: 9
    dexterity: 10
    constitution: 10
    intelligence: 11
    wisdom: 12
    charisma: 11
    hit_dice: "1d8"
    hit_points: 4
    max_hit_points: 4
    armor_class: 10
    thac0: 20
    attacks_per_round: 1
    damage_per_attack: ["1d2"]
    movement_rate: 120
    saving_throws:
      paralyzation_poison_death_magic: 14
      petrification_polymorph: 16
      rod_staff_wand: 15
      breath_weapon: 17
      spell: 16
    current_room_id: "maras_inn"
    morale: 5
    tier: 3
    is_alive: true
    dossier:
      role: "Distraught Spouse & Secondary Quest Giver"
      personality: "Frantic, grieving, desperate for hope, holds onto any chance her husband is alive."
      speech_style: "Pleading, soft, breaks down into tears when discussing Willem."
      goals:
        - "Plead with adventurers to search for her husband Willem."
        - "Offer her life savings of 20 gold pieces for Willem's safe return."
      knowledge:
        - "Willem went up to the tower 3 days ago with a hunting bow after hearing commotion."
        - "He never returned; she fears he was dragged underground."
```

### 2.2 Spatial Boundary (`boundaries:`)

```yaml
  - id: "maras_inn_zone"
    place: "maras_inn"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 4
    sleep_after: 60
```

### 2.3 Initial Commitments (`initial_commitments:`)

```yaml
  - id: "grevik_quest_offer"
    debtor: "mayor_grevik"
    deed: "explain livestock raids and offer 100 gp bounty to investigate ruined tower"
    due: 1
    every: 25
    priority: 8

  - id: "anna_rescue_plea"
    debtor: "anna_mordale"
    deed: "plead for Willem's rescue and offer 20 gp reward"
    due: 2
    every: 30
    priority: 7

  - id: "erik_raid_warning"
    debtor: "erik_the_shepherd"
    deed: "recount goblin attack on sheep and describe green flickering lights"
    due: 3
    every: 35
    priority: 6

  - id: "mara_hospitality_and_rumors"
    debtor: "mara"
    deed: "welcome guests, offer hot stew and ale, and share rumors of Vaelith's ghost"
    due: 5
    every: 45
    priority: 4
```

---

## 3. Engine Architecture & Integration

### 3.1 Multi-Key Actor Ingestion (`EngineCore.Loader`)
- Update `extract_elements(yaml, keys)` to concatenate/merge items across all matching keys (`initial_actors`, `initial_enemies`, `monsters`) so both neutral NPCs and hostile monsters load simultaneously into `World.agents`.
- In `agent_from(m)`:
  - `tier = m["tier"] || m["cognition_tier"] || tier_of(m["id"])`
  - `capabilities: caps(tier)` (Tier 3 grants `[:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee, :order]`).
  - Store `dossier: m["dossier"] || %{}` on `%Types.Agent{}`.

### 3.2 Adventure Validator (`EngineCore.Validator`)
- Update `monster_errors/1` and `agent_ids/1` to inspect maps across both `initial_actors` and `initial_enemies`.
- Ensure all declared NPCs satisfy AD&D 1E required attributes (`id`, `name`, `hit_dice`, `hit_points`, `armor_class`, `thac0`, `morale`, `current_room_id`).

### 3.3 Context Slicing (`Referee.Slice`)
- In `Slice.for_actor/2`, extract the agent's `dossier`:
  ```elixir
  dossier: agent.dossier || %{}
  ```

### 3.4 In-Character Brain Prompting (`Agents.Prompt`)
- In `Agents.Prompt.deliberate/1`, format the `dossier` into the user prompt section when present:
  ```text
  Role: <role>
  Personality: <personality>
  Goals: <goals joined>
  Knowledge / Rumors: <rumors or knowledge joined>
  ```
- This ensures LLM agents adopt authentic tabletop character voices and prioritize their specified goals during BCD loops.

---

## 4. Verification & Testing Plan

1. **Loader & Validator Unit Tests (`engine_core`):**
   - Verify `ruined_tower.yaml` passes `Validator.check/1` with zero errors.
   - Verify `Loader.load/1` populates all 4 inn actors alongside existing dungeon enemies with `tier: 3` and non-empty `dossier` maps.
2. **Prompt Generation Tests (`agents`):**
   - Verify `Agents.Prompt.deliberate/1` includes role, personality, goals, and rumors in the prompt string when given an actor slice with a dossier.
3. **Full Umbrella Test Suite:**
   - Run `mix test` across umbrella apps (`engine_core`, `agents`, `referee`, `wire`, `client_web`) ensuring 100% pass rate.
