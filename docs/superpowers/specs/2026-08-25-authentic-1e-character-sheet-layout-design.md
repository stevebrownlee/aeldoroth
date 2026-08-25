# Authentic AD&D 1E Character Sheet Layout Design

**Date:** 2026-08-25  
**Status:** In Review  
**Domain:** `shards_engine` (`apps/client_web`, `apps/referee`)  
**Decisions Referenced:** Decision 20 (Referee Pipeline), Decision 52 (Trust Barrier), Decision 59 (Starting Place & Character Cards), Decision 60 (1E Race/Class & THAC0), Decision 61 (Level, XP, Spells & Prayers), Decision 62 (2nd-Level Spell Catalogs), Decision 64 (Two Portals, Dedicated OOC Chat & 1E Round Engine)

---

## 1. Executive Summary & Goal

Replicate the spatial layout, typography, sub-attributes, and combat matrices of the traditional TSR **AD&D 1E Player Character Record** sheets (from the official 1E character sheet folios) across the player experience:

1. **Character Creation (`/runs/:run_id`)**:
   - The single-hero character builder adopts the complete authentic 1E Player Character Record layout matching the provided reference sheets.
   - Includes Header, Identity & Movement, Abilities Sub-Table Matrix ($S, I, W, D, C, CH, CM$), Saving Throws, Combat & Armor Class block, Weapons & To-Hit Armor Class Matrix (AC 10..2), and class-specific tables.
2. **Live Play Surface (`/runs/:run_id/:pc_id`)**:
   - The right panel houses the live combat vitals and action declaration box, with a 1-click **"📜 View Full 1E Character Sheet"** button that opens the full authentic sheet with live HP, wounds, equipped gear, and prepared spells/prayers.
3. **Class-Specific Adaptation (Images 1–4)**:
   - **Cleric / Druid (Image #1)**: Divine Prayers grid (1st–7th level) + official **Turning Undead Table** (*Skeleton, Zombie, Ghoul, Shadow, Wight, Ghast, Wraith, Mummy, Spectre, Vampire, Ghost, Lich*).
   - **Fighter / Ranger / Paladin (Image #2)**: # Attacks, Morale, Mount stats (*Name, HD, AC, HP, Damage*), Special Abilities, Paladin Turning.
   - **Magic-User / Illusionist (Image #3)**: Arcane Spellbook grid (1st–9th level columns), Master, School, Familiar/Pet.
   - **Thief / Assassin / Monk (Image #4)**: Guild/Order, Rank, Contacts, and official **Thieving Skills % Table** (*Pick Pockets %, Open Locks %, Find/Remove Traps %, Move Silently %, Hide in Shadows %, Hear Noise %, Climb Walls %, Read Languages %*).
4. **Auto-Calculations with Manual Overrides**:
   - Ability scores, class, and level automatically populate sub-attributes (Open Doors, Bend Bars, % Know Spell, System Shock, Reaction Adj) and 1E Saving Throws, with full manual override support.

---

## 2. Layout Structure & Zone Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ZONE 1: HEADER & CHARACTER IDENTITY                                                             │
│ • Player Name, Campaign Name, Campaign #, Date Character Began                                  │
│ • Character Name Box, Class, Level, Race, Alignment, Patron Deity, Religion, Place of Origin    │
│ • Movement Base (Concealed, Climbing, Special Move, Secondary Skill, Vision, Listening)         │
├────────────────────────────────────────────────┬────────────────────────────────────────────────┤
│ ZONE 2: ABILITIES SUB-TABLE MATRIX (Left)      │ ZONE 3: SAVING THROWS & RESISTANCES (Right)    │
│ • Strength (Hit Adj, Dam Adj, Open D, Bend B)  │ • Paralyzation / Poison                        │
│ • Intelligence (Add Lang, % Know, Min/Max Sp)  │ • Petrification / Polymorph                    │
│ • Wisdom (Mag Atk Adj, Spell Bonus, % Fail)    │ • Rod, Staff, or Wand                          │
│ • Dexterity (Reaction, Missile, Defense Adj)   │ • Breath Weapon                                │
│ • Constitution (HP Adj, System Shock, Resurrec)│ • Spells                                       │
│ • Charisma (Max Henchmen, Loyalty, Reaction)   │ • Saving Throw Adjustments & Resistances       │
│ • Comeliness (Response)                        │ • Languages, Detection & Psionics              │
├────────────────────────────────────────────────┴────────────────────────────────────────────────┤
│ ZONE 4: COMBAT VITALS & ARMOR CLASS                                                             │
│ • Armor Class (AC Box, Armor Worn, AC Base, Dex Adj, Magic Adj, Shieldless AC, Rear AC)         │
│ • Hit Points (HP Box, Max HP, Const Adj, Hit Die, Wounds, Surprise & Rear Modifiers)            │
│ • Weapons of Proficiency & Total Combat Adjustments ("To Hit" Adj, Damage Adj)                  │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ZONE 5: WEAPONS & TO-HIT ARMOR CLASS MATRIX                                                     │
│ • Weapon in Hand                                                                                │
│ • Weapon Table: WEAPON | MAG ADJ | SPACE/RANGE | SPEED | AC 10 9 8 7 6 5 4 3 2 | DAMAGE S-M / L │
│ • Weaponless Combat (Pummeling, Grappling, Overbearing)                                         │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ZONE 6: DYNAMIC CLASS-SPECIFIC RECORD                                                           │
│ • Cleric / Druid: Church status, Parish, Holy Symbol, Prayers (1st-7th), Turning Undead Table   │
│ • Fighter / Ranger / Paladin: # Attacks, Patron, Mount stats, Paladin Turning                   │
│ • Magic-User / Illusionist: Master, School, Familiar, Spellbook & Memorization Grid (1st-9th)   │
│ • Thief / Assassin / Monk: Guild/Order, Rank, Contacts, Thieving Skills % Table (8 skills)     │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Zone Specifications

### 3.1 Zone 1: Header & Identity
- **Header Fields**:
  - `player_name`: Text input.
  - `campaign_name`: Text input (defaults to "The Shattered Kingdoms").
  - `campaign_num`: Text input (defaults to "1").
  - `date_began`: Text input (defaults to current date).
- **Identity Fields**:
  - `name`: Character Name (prominent decorative box).
  - `class`: 1E Class select (`Fighter`, `Paladin`, `Ranger`, `Cleric`, `Druid`, `Magic-User`, `Illusionist`, `Thief`, `Assassin`, `Monk`).
  - `level`: Number input (1..20).
  - `race`: 1E Race select (`Human`, `Elf`, `Half-Elf`, `Dwarf`, `Gnome`, `Halfling`, `Half-Orc`).
  - `alignment`: 1E Alignment select (`Lawful Good`, `Neutral Good`, `Chaotic Good`, `Lawful Neutral`, `True Neutral`, `Chaotic Neutral`, `Lawful Evil`, `Neutral Evil`, `Chaotic Evil`).
  - `patron_deity`: Text input.
  - `religion`: Text input.
  - `place_of_origin`: Text input (defaults to "Mara's Inn, Thornhollow").
  - `move_base`: Base movement (e.g. `12"` / `9"`).
  - `movement_notes`: Secondary skills (Concealed, Climbing, Special Move, Vision, Listening).

---

### 3.2 Zone 2: Abilities Sub-Table Matrix
Each ability row features the base score (3..18+) plus official 1E sub-fields:

1. **Strength (S)**:
   - Score (`str`: 3..18) & Exceptional Strength % (`str_percent`: 01..00 for 18 Fighter/Paladin/Ranger).
   - Hit Probability Adj (`hit_adj`: e.g. `0`, `+1`, `+2`).
   - Damage Adjustment (`dam_adj`: e.g. `0`, `+1`, `+2`, `+3`).
   - Open Doors (`open_doors`: e.g. `1-2 on d6`, `1-3`, `1-4`).
   - Bend Bars / Lift Gates (`bend_bars`: e.g. `1%`, `4%`, `7%`, `16%`).
2. **Intelligence (I)**:
   - Score (`int`: 3..18).
   - Additional Languages (`add_lang`: 0..7).
   - % Know Spell (`know_spell`: e.g. `45%`, `55%`, `65%`, `75%`).
   - Min # Spells Per Level (`min_spells`: 4..8).
   - Max # Spells Per Level (`max_spells`: 6..All).
3. **Wisdom (W)**:
   - Score (`wis`: 3..18).
   - Magical Attack Adjustment (`mag_atk_adj`: e.g. `-1`, `0`, `+1`, `+2`).
   - Clerical Spell Bonus (`spell_bonus`: e.g. `1st`, `1st+2nd`).
   - % Spell Failure (`spell_failure`: e.g. `20%`, `10%`, `0%`).
4. **Dexterity (D)**:
   - Score (`dex`: 3..18).
   - Reaction / Attacking Adjustment (`react_adj`: e.g. `-1`, `0`, `+1`, `+2`).
   - Missile Attack Adjustment (`missile_adj`: e.g. `-1`, `0`, `+1`, `+2`).
   - Defensive Adjustment to AC (`def_adj`: e.g. `+1`, `0`, `-1`, `-2`, `-3`, `-4`).
5. **Constitution (C)**:
   - Score (`con`: 3..18).
   - Hit Point Adjustment (`hp_adj`: e.g. `-1`, `0`, `+1`, `+2`, `+3` or `+4` for warriors).
   - System Shock Survival (`system_shock`: e.g. `70%`, `80%`, `90%`, `95%`).
   - Resurrection Survival (`resurrect_survival`: e.g. `75%`, `85%`, `95%`, `98%`).
6. **Charisma (CH)**:
   - Score (`cha`: 3..18).
   - Max # Henchmen (`max_henchmen`: 1..15).
   - Loyalty Base (`loyalty_base`: e.g. `-10%`, `0%`, `+15%`).
   - Reaction Adjustment (`react_cha_adj`: e.g. `-15%`, `0%`, `+20%`).
7. **Comeliness (CM)**:
   - Score (`com`: 3..18).
   - Reaction Response (`com_response`: e.g. `Repulsive`, `Normal`, `Fascinating`).

---

### 3.3 Zone 3: Saving Throws & Adjustments
- **5 Saving Throw Bubbles (1E DMG p. 79)**:
  1. `save_poison`: **Paralyzation, Poison, or Death Magic**
  2. `save_petrification`: **Petrification or Polymorph**
  3. `save_wand`: **Rod, Staff, or Wand**
  4. `save_breath`: **Breath Weapon**
  5. `save_spell`: **Spells**
- **Adjustments & Defenses**:
  - `save_adjustments`: +/- and Condition inputs (e.g. `+1 vs Poison (Dwarf/Halfling)`).
  - `resistances`: Racial / Magical resistances (e.g. `90% Resistance to Sleep/Charm (Elf)`).
  - `detection`: Vision & infravision notes (e.g. `Infravision 60'`).
  - `languages`: Known languages (e.g. `Common, Alignment, Elven, Gnoll`).
  - `psionics`: Attack/Defense modes, Attack Strength, Defense Strength, Major/Minor Disciplines.

---

### 3.4 Zone 4: Combat Vitals & Armor Class Block
- **Armor Class Shield**:
  - `ac`: Final effective AC (descending AC 10..-10).
  - `armor_worn`: Armor description (e.g. `Chain mail & Shield`).
  - `ac_base`: Base AC of armor (e.g. `5` for chain mail).
  - `dex_ac_adj`: Dexterity AC adjustment.
  - `mag_ac_adj`: Magical armor/shield bonus.
  - `shieldless_ac`: AC without shield.
  - `rear_ac`: AC against rear attacks (no Dex/shield).
  - `armor_condition`: Condition notes.
- **Hit Points**:
  - `hp_max`: Maximum Hit Points.
  - `hp_current`: Current Hit Points.
  - `hit_die`: Hit die type (`d10`, `d8`, `d6`, `d4`).
  - `con_hp_adj`: Constitution HP bonus.
  - `wounds`: Damage taken tracker.
- **Surprise & Tactical Adjustments**:
  - `surprise_mod`: Surprise roll modifier.
  - `dex_surprise_adj`: Dexterity surprise adjustment.
  - `rear_attack_adj`: Rear attack modifier.
- **Proficiencies & Combat Adjustments**:
  - `weapons_proficiency`: Weapons known (e.g. `Longsword, Dagger, Shortbow`).
  - `num_proficiencies`: Total slots.
  - `non_prof_penalty`: Non-proficiency to-hit penalty (`-2` warrior, `-3` priest/rogue, `-5` wizard).
  - `to_hit_adj_total`: Total to-hit bonus (Str/Dex + magical).
  - `damage_adj_total`: Total damage bonus (Str + magical).

---

### 3.5 Zone 5: Weapons & To-Hit Armor Class Matrix
- **Weapon in Hand**: Currently active weapon.
- **1E Weapons Matrix Table**:
  - Up to 4 weapon rows with columns:
    1. `WEAPON`: Weapon name.
    2. `MAG. ADJ.`: Magical bonus (`+0`, `+1`, etc.).
    3. `SPACE REQUIRED / RANGE`: Melee space or missile range brackets (`S/M/L`).
    4. `SPEED`: Weapon speed factor (1E DMG p. 66).
    5. `AC 10`: To-hit roll needed vs AC 10.
    6. `AC 9`: To-hit roll needed vs AC 9.
    7. `AC 8`: To-hit roll needed vs AC 8.
    8. `AC 7`: To-hit roll needed vs AC 7.
    9. `AC 6`: To-hit roll needed vs AC 6.
    10. `AC 5`: To-hit roll needed vs AC 5.
    11. `AC 4`: To-hit roll needed vs AC 4.
    12. `AC 3`: To-hit roll needed vs AC 3.
    13. `AC 2`: To-hit roll needed vs AC 2.
    14. `DAMAGE S-M`: Damage vs Small/Medium targets (e.g. `1d8`).
    15. `DAMAGE L`: Damage vs Large targets (e.g. `1d12`).
- **Weaponless Combat Sub-Box**:
  - Pummeling (`pummeling`: Atk Adj, Damage Adj, Def Adj).
  - Grappling (`grappling`: Atk Adj, Damage Adj, Def Adj).
  - Overbearing (`overbearing`: Atk Adj, Damage Adj, Def Adj).

---

### 3.6 Zone 6: Class-Specific Bottom Zones

#### A. Cleric / Druid (Image #1)
- `church_status`: Status in Church (e.g. `Acolyte`, `Curate`, `Bishop`).
- `church_influence`: Church's Influence.
- `tithes_percent`: % Tithes.
- `parish`: Parish name.
- `holy_symbol`: Holy symbol description.
- **Divine Prayers Table**:
  - Matrix with columns for 1st, 2nd, 3rd, 4th, 5th, 6th, 7th level prayers.
  - Prepared prayer slots with checkboxes.
- **Turning Undead Table (1E DMG p. 65)**:
  - Columns: `Skeleton`, `Zombie`, `Ghoul`, `Shadow`, `Wight`, `Ghast`, `Wraith`, `Mummy`, `Spectre`, `Vampire`, `Ghost`, `Lich`, `Special`.
  - Values: Target $1\text{d}20$ number (e.g. `10`, `13`, `16`, `20`, `T`, `D`).

#### B. Fighter / Ranger / Paladin (Image #2)
- `num_attacks`: # Attacks per round (e.g. `1/1`, `3/2` at Level 7+, `2/1` at Level 13+).
- `morale_modifier`: Morale Modifier.
- `patron`: Patron / Lord / Lady.
- `special_abilities`: Weapon Specialization, 1E Melee allowances.
- `mount`: Mount Name, Type (e.g. `Heavy Warhorse`), HD, AC, HP, #AT, Damage.
- `paladin_turning`: Paladin turning undead table (for Paladins Level 3+).

#### C. Magic-User / Illusionist (Image #3)
- `master`: Master name (e.g. `Vaelith the Mirage-Weaver`).
- `school`: Arcane School / Specialization (e.g. `Illusion / Phantasm`).
- `familiar`: Familiar / Pet description.
- `magic_components`: Material spell components pouch.
- **Arcane Spellbook Matrix**:
  - Columns for 1st, 2nd, 3rd, 4th, 5th, 6th, 7th, 8th, 9th level arcane spells.
  - Prepared spell chips with level indicators.

#### D. Thief / Assassin / Monk (Image #4)
- `guild_order`: Guild / Thieves' Guild / Monastic Order.
- `guild_rank`: Rank in Guild / Title.
- `superior`: Guild Master / Superior.
- `contacts`: Contacts list (Name or Pseudonym, Occupation).
- `disguises_tools`: Disguises and Special Tools (Lockpicks, Thieves' Tools, Grappling Hook).
- **Thieving Skills Table (1E PHB p. 28)**:
  - Columns with percentage boxes:
    - **Pick Pockets (%)**: `30%`
    - **Open Locks (%)**: `25%`
    - **Find / Remove Traps (%)**: `20%`
    - **Move Silently (%)**: `15%`
    - **Hide in Shadows (%)**: `10%`
    - **Hear Noise (%)**: `10%` (or `1-2 on d6`)
    - **Climb Walls (%)**: `85%`
    - **Read Languages (%)**: `—` (Level 4+)

---

## 4. In-Game Live Play Integration

In `ClientWeb.RunLive` (`/runs/:run_id/:pc_id`):
- **Right Panel**: Displays the quick combat vitals (HP, AC, THAC0, Weapons, Spells) + Action Declaration box.
- **Full Sheet Modal**: Clicking **"📜 View Full 1E Character Sheet"** opens an interactive full-screen modal displaying this complete authentic 1E Player Character Record with live HP, wounds, equipment, and spells.

---

## 5. Verification Plan

1. **Unit & Component Tests**:
   - `ClientWeb.RunLiveTest`: Test rendering of all 6 character sheet zones, 1E abilities sub-table, saving throws, weapons matrix, and dynamic class-specific sections (Cleric Turning, Fighter Mount, Magic-User Spells, Thief Skills %).
   - `Referee.PC`: Ensure all 1E sub-attributes (Open Doors, Bend Bars, System Shock, Saving Throws, Thieving skills %) are populated in PC data structures.
2. **Umbrella Suite**:
   - Run `mix test` across all 7 umbrella apps ensuring 100% green tests.
3. **Visual Verification**:
   - Verify that `/runs/:run_id` and the in-game character sheet modal accurately mirror the text and input field layouts of the 4 provided reference images.
