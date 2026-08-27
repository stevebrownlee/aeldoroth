# Thornhollow Town Expansion & Comprehensive Settlement Design

**Date:** 2026-08-26  
**Status:** Draft / Review  
**Topic:** Expanding the village of Thornhollow in `the-ruined-tower/ruined_tower.yaml` with a central Village Green, full commercial services, civic and faith institutions, residential investigative sites with tangible evidence, and Tier-3 BDI NPC cognition.

---

## 1. Overview & Setting Canon

In *The Shattered Kingdoms* campaign series (Age of Reclamation), Thornhollow is a resilient farming community of approximately 150 souls nestled in the Western Lands near the Thornwood forest. While previously only Mara's Inn (`maras_inn`) had an active in-engine boundary and presence, this expansion establishes Thornhollow as a living, fully interactive AD&D 1E settlement.

### Design Principles & Canon Alignment
1. **Hub-and-Spoke Village Green:** A central commons (`village_green`) connects Mara's Inn, five commercial craft shops, the temple, civic administration, and four residential investigative sites.
2. **Faith & Lore Consistency:** The village temple is dedicated to **Thyra the Green Mother** (nature, harvest, life) with reverent devotion to **Solara the Daystar** (sun, light, anti-shadow), matching Aeldoroth canon. The blacksmith honors **Korvath the Iron Lord** (warriors and smiths), and the herbalist studies the mysteries of **Mystara the Weaver** (arcane weave and reagents).
3. **Authentic 1E Provisioning & Arcane Reagents:** Complete gear inventories with 1E pricing, discrete copper-value currency rules (pp=500, gp=100, ep=50, sp=10, cp=1), essential dungeon tools (10-ft poles, iron spikes, crowbars), and spell components (bat guano, sulfur, silver dust, belladonna).
4. **Tangible Evidence & Investigation:** Residential houses contain examinable evidence items that provide evocative clues (tracks, claw marks, wolf behavior, ancient masonry) without spoiling dungeon puzzle solutions.
5. **Tier-3 BDI NPC Agency:** All major townspeople are fully statted Tier-3 actors with combat stats, rich personality dossiers (role, personality, goals, knowledge, rumors), spatial presence boundaries, and initial commitments.
6. **Engine & Golden Replay Determinism:** All additions adhere strictly to `EngineCore.Validator` and `EngineCore.Loader` schemas, maintaining 100% test compatibility.

---

## 2. Spatial Map & Room Definitions

### 2.1 Navigation Topology

```
                         [entry_hall] (Ruined Tower)
                              │
                            north
                              │
 [mordale_cottage] ──northwest  │  northeast── [eriks_farm]
 [trappers_cabin] ───west     │     east───── [elders_study]
                              │
                    ┌──────────────────┐
 [maras_inn] ───────┤  village_green   ├─────── [temple_of_thyra]
 (Start Room)       └─┬───┬───┬───┬───┬┘
                      │   │   │   │   │
     ┌────────────────┘   │   │   │   └────────────────┐
     ▼                    ▼   ▼   ▼                    ▼
[blacksmith_shop]  [general_store]  [herbalist_shop]  [butchers_shop]  [pawn_shop]
                          │
                      southwest
                          │
                     [town_hall]
                     ├── [town_jail]
                     └── [town_treasury]
```

### 2.2 Room Specifications

#### 1. `village_green` — **Thornhollow Village Green**
- **Kind:** `settlement`
- **Description:** "The open village green of Thornhollow, surrounded by timber-and-stone cottages and shops with thatched roofs. A weathered stone well stands at the center beneath a spreading golden oak tree. To the west, the warm lights of Mara's Inn beckon. Paths lead north toward the ruined tower hill, east toward the stone chapel, southwest to the council hall, and south along the row of craftsman shops."
- **Terrain:** "beaten earth paths, autumn grass, fallen golden leaves"
- **Lighting:** "bright (daylight / lantern-lit paths)"
- **Structures:** ["ancient stone well", "spreading golden oak", "village notice board", "timber signposts"]
- **Atmosphere:** "Crisp autumn air carrying the scent of woodsmoke, roasted barley, and damp earth. Anxious murmurs from passing villagers."
- **Exits:**
  - `west`: `"maras_inn"`
  - `north`: `"entry_hall"` (tower trail)
  - `tower`: `"entry_hall"` (alias)
  - `east`: `"temple_of_thyra"`
  - `southwest`: `"town_hall"`
  - `provisions`: `"general_store"`
  - `forge`: `"blacksmith_shop"`
  - `apothecary`: `"herbalist_shop"`
  - `butcher`: `"butchers_shop"`
  - `curio`: `"pawn_shop"`
  - `farm`: `"eriks_farm"`
  - `cottage`: `"mordale_cottage"`
  - `trapper`: `"trappers_cabin"`
  - `study`: `"elders_study"`

#### 2. `maras_inn` — **Mara's Inn (Common Room)** *(Starting Place)*
- **Kind:** `settlement`
- **Description:** "The cozy common room of Mara's inn in Thornhollow. A hearth crackles warmly against the autumn chill. Mayor Grevik sits at the head table with a furrowed brow, while Mara tends the counter and worried villagers murmur nearby. Through the front door, the village green opens out toward the town and the hill path."
- **Terrain:** "warm wooden floorboards"
- **Lighting:** "bright (hearth and lanterns)"
- **Structures:** ["stone hearth", "heavy oak tables", "innkeeper's counter", "door to village green"]
- **Atmosphere:** "Warm, bustling with anxious tavern folk, smell of hearty stew and spiced ale."
- **Exits:**
  - `east`: `"village_green"`
  - `green`: `"village_green"`
  - `north`: `"entry_hall"`
  - `tower`: `"entry_hall"`

#### 3. `blacksmith_shop` — **The Ironhand Forge**
- **Kind:** `settlement`
- **Description:** "A soot-stained stone smithy ringing with the rhythmic strike of hammer on iron. Master Torvald works beside a roaring forge, surrounded by weapon racks, barrels of tempering brine, and rows of sharpened farm tools and blades. An iron anvil bearing the hammer-and-anvil rune of Korvath stands prominently in the center."
- **Structures:** ["roaring charcoal forge", "stone chimney", "Korvath-inscribed anvil", "weapon racks", "tempering brine barrel"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`

#### 4. `general_store` — **Jorren's Provisions**
- **Kind:** `settlement`
- **Description:** "A dry, crowded general store packed to the rafters with adventuring essentials, farm supplies, and household wares. Coils of hemp rope and iron chains hang from ceiling beams alongside smoked hams and bundles of torches. Old Jorren keeps tally at a sturdy counter."
- **Structures:** ["wooden display counters", "heavy shelving units", "hanging rope and torch racks", "ledger desk"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`

#### 5. `herbalist_shop` — **Greenweft Apothecary**
- **Kind:** `settlement`
- **Description:** "A fragrant, sunlit shop filled with the earthy aroma of drying herbs, crushed petals, and pungent tinctures. Bundles of lavender, sage, and belladonna hang from exposed cedar rafters. Glass alembics, mortar stones, and jars of arcane mineral powders line the polished wooden shelves."
- **Structures:** ["cedar drying rafters", "alchemical workbench", "glass distillation apparatus", "specimen cabinets"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`

#### 6. `butchers_shop` — **Hael's Cleaver**
- **Kind:** `settlement`
- **Description:** "A clean, cool stone butchery with sawdust-covered floors and hanging game. Large wooden chopping blocks bear the marks of decades of cleaver work. Hael the butcher trims cuts of fresh venison and salted mutton with practiced ease."
- **Structures:** ["heavy maple butcher blocks", "iron meat hooks", "smokehouse door", "salting bins"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`

#### 7. `pawn_shop` — **The Silver Trinket & Curios**
- **Kind:** `settlement`
- **Description:** "A quiet, dimly lit shop filled with antique curiosities, estate oddities, and salvaged relics. Glass display cases hold silver brooches, pocket lenses, strange coins, and carved wooden figurines. Silas Vance peers through a jeweler's loupe behind the velvet-lined counter."
- **Structures:** ["locked glass display cabinets", "velvet appraisal counter", "iron strongbox", "curio display shelves"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`

#### 8. `temple_of_thyra` — **Sanctuary of the Green Mother & Solara**
- **Kind:** `settlement`
- **Description:** "A serene fieldstone chapel with arched windows that let in radiant autumn sunlight. A carved wooden altar draped in living ivy and golden sheaves of wheat honors Thyra the Green Mother, flanked by sunburst mosaics of Solara the Daystar. A consecrated stone basin of pure spring water rests near the entrance, and the scent of sweet incense fills the air."
- **Structures:** ["living ivy altar of Thyra", "Solara sunburst mosaic", "consecrated holy water font", "prayer benches", "votive candle stands"]
- **Exits:**
  - `west`: `"village_green"`
  - `green`: `"village_green"`

#### 9. `town_hall` — **Thornhollow Council Hall**
- **Kind:** `settlement`
- **Description:** "The civic meeting hall of Thornhollow, built with heavy oak timbers and fieldstone. A long council table sits beneath banners of the Western Lands. Parchment archives and regional land maps line the walls. An iron-reinforced door leads east to the watch post and jail, while a heavy padlocked trapdoor in the corner leads down into the stone vault."
- **Structures:** ["oak council table", "magistrate's high-backed chair", "parchment archive shelves", "iron-reinforced jail door", "banded treasury trapdoor"]
- **Exits:**
  - `north`: `"village_green"`
  - `green`: `"village_green"`
  - `east`: `"town_jail"`
  - `jail`: `"town_jail"`
  - `down`: `"town_treasury"`
  - `vault`: `"town_treasury"`

#### 10. `town_jail` — **Village Lockup & Watch Post**
- **Kind:** `settlement`
- **Description:** "A stark stone holding room and militia watch post. Two iron-barred cells occupy the southern wall, fitted with heavy deadbolts and straw bunks. A sturdy desk holds the night watch roster, patrol incident logs, and iron keys. A weapons rack holds militia spears and light crossbows."
- **Structures:** ["two iron-barred cells with heavy locks", "watch commander's desk", "militia weapon rack", "iron key ring on peg"]
- **Exits:**
  - `west`: `"town_hall"`
  - `hall`: `"town_hall"`

#### 11. `town_treasury` — **Municipal Vault**
- **Kind:** `settlement`
- **Description:** "A cool, windowless stone cellar beneath the council hall. The masonry is reinforced with iron braces. In the center sits a heavy iron-banded chest secured with dual dwarven-forged locks. Sacks of municipal tax coinage and the village emergency bounty reserve are kept here under strict lock and guard."
- **Structures:** ["iron-braced masonry walls", "heavy iron-banded chest with dual locks", "coin tally ledger", "torch sconce"]
- **Exits:**
  - `up`: `"town_hall"`
  - `hall`: `"town_hall"`

#### 12. `eriks_farm` — **Erik's Sheep Farm**
- **Kind:** `settlement`
- **Description:** "A modest sheep farm on the northeast outskirts of the village. The wooden split-rail paddock shows recent violent damage, with several fence rails splintered and smashed. A thatched farmhouse and hay barn sit beside the muddy pasture where the remaining sheep huddle nervously."
- **Structures:** ["thatched farmhouse", "timber hay barn", "splintered sheepfold fencing", "muddy feeding paddock"]
- **Exits:**
  - `southwest`: `"village_green"`
  - `green`: `"village_green"`

#### 13. `mordale_cottage` — **Willem & Anna's Cottage**
- **Kind:** `settlement`
- **Description:** "A tidy fieldstone cottage surrounded by a quiet vegetable garden. Inside, simple wooden furnishings and a warm hearth reflect years of quiet farming life. On a writing desk in the corner lie Willem's crop notes and recent scouting sketches."
- **Structures:** ["stone hearth", "simple dining table", "farmer's writing desk", "small pantry cupboard"]
- **Exits:**
  - `southeast`: `"village_green"`
  - `green`: `"village_green"`

#### 14. `trappers_cabin` — **Kaelen's Woodsman Cabin**
- **Kind:** `settlement`
- **Description:** "A rugged log cabin situated on the western fringe where the village meets the Thornwood. Cured animal pelts hang on wooden drying frames against the exterior walls. Inside, hunting bows, snaring wire, and tracking tools are neatly organized along the cedar walls."
- **Structures:** ["log hearth", "pelt drying racks", "bowyer's workbench", "snare and trap rack"]
- **Exits:**
  - `east`: `"village_green"`
  - `green`: `"village_green"`

#### 15. `elders_study` — **Elder Corvus's Cottage**
- **Kind:** `settlement`
- **Description:** "A warm, cluttered cottage filled with tall cedar bookshelves, rolled parchment maps, and curious instruments of brass and glass. Elder Corvus sits in a comfortable high-backed armchair beside a crackling hearth, surrounded by five decades of compiled histories and regional lore."
- **Structures:** ["floor-to-ceiling cedar bookshelves", "brass astrolabe", "scholar's reading desk", "high-backed armchair"]
- **Exits:**
  - `west`: `"village_green"`
  - `green`: `"village_green"`

---

## 3. Commercial Inventories & Services

### 3.1 Blacksmith (`blacksmith_shop` — Torvald Ironhand)
- **Weapons:** Dagger (2 gp), Hand Axe (3 gp), Short Sword (7 gp), Spear (1 gp), Mace (5 gp), Club (3 sp).
- **Armor & Protection:** Shield (10 gp), Leather Armor (5 gp), Iron Helm (10 gp).
- **Hardware & Tools:** Iron spikes $\times 12$ (1 gp), Crowbar (2 gp), Hammer (5 sp).
- **Special Services:** Weapon silvering (50 gp + blade), armor mending (1–5 sp).

### 3.2 Provisions (`general_store` — Old Jorren)
- **Delving Tools:** 10-foot pole (1 gp), Hemp rope 50ft (1 gp), Torches $\times 10$ (1 gp), Lantern (9 gp), Flask of Oil (1 gp), Waterskin (1 gp), Chalk $\times 10$ (1 sp), Sacks (small 2 sp, large 1 gp), Backpack (2 gp), Thieves' tools (30 gp).
- **Provisions:** Standard rations 7-day (3 gp), Iron preserved rations 7-day (5 gp).
- **Trade In:** Buys dungeon salvage and trade items at 70% listed value.

### 3.3 Apothecary (`herbalist_shop` — Thessia Brightmix)
- **Arcane Spell Components:**
  - Bat guano & sulfur (flame/arcane reagent): 5 gp
  - Pinch of fine sand & rose petals (Sleep spell reagent): 5 sp
  - Powdered silver & iron filings (Protection/warding reagent): 10 gp
  - Dried wolfsbane & belladonna sprigs: 2 gp
  - Glass vials & stoppered flasks: 1 gp
- **Herbal Remedies:**
  - *Herbal Poultice* (stops bleeding, accelerates rest healing): 5 gp
  - *Antivenom Draught* (+2 on saves vs poison for 1 hour): 15 gp
  - *Healing Tincture* (mild draught restoring 1d4 HP, limit 1/day): 25 gp

### 3.4 Butcher (`butchers_shop` — Hael Bloodwood)
- **Meats & Trail Food:** Fresh meat rations 3-day (6 sp), Smoked mutton strips 7-day (2 gp).
- **Tactical Bait:** Fresh offal and scent bait (3 sp) — *can distract or lure wolves in Room 6*.
- **Tools:** Heavy butcher's cleaver (treat as hand axe, 2 gp).

### 3.5 Pawn Shop & Curios (`pawn_shop` — Silas Vance)
- **Curios & Tools:** Brass pocket mirror (peek around corners): 5 gp; Magnifying glass: 25 gp; Scroll case: 1 gp; Ancient Titan-era silver coin: 10 gp.
- **Services:** Gem & jewelry appraisal (1 gp fee), bullion and ancient coin exchange.

---

## 4. Faith, Civic & Divine Services

### 4.1 Sanctuary of Thyra & Solara (`temple_of_thyra` — Sister Aldara)
- **Healing:** Tends wounds and binds fractures (donation-based / free for needy).
- **Holy Water:** Consecrated water vials (25 gp each) — deals 2d4 damage to undead (e.g. Talven's skeleton in Room 7).
- **Harvest & Dawn Blessing:** Praying at the altar with a 10+ gp donation confers a **+1 bonus to saving throws vs. Fear and Poison** for the upcoming delve.
- **Divine Communion:** Sister Aldara channels omens from the gods: *"Beneath the dry leaves of forgotten books, cold bones sit in violet chains, awaiting release from an unkept oath."*

### 4.2 Council Hall, Jail & Treasury (`town_hall`, `town_jail`, `town_treasury`)
- **Bounty:** 100 gp bounty for stopping raids, authorized by Mayor Grevik.
- **Watch Records:** Incident logs showing raids occur on moonless/foggy nights between midnight and second watch (confirming goblin daylight sensitivity).
- **Treasury Vault:** Secure reserve of 120 gp, 350 sp, 1,200 cp plus the 100 gp adventurer reward bag in a locked dwarven-banded chest.

---

## 5. Residential Tangible Clues & Investigation Items

| Item ID | Location | Type | Description & Value |
|---|---|---|---|
| `mutilated_sheep_fleece` | `eriks_farm` | `clue_item` | Slashed fleece showing savage bite wounds and blackened bruising from trained wolf beasts (0 gp). |
| `goblin_javelin_scrap` | `eriks_farm` | `clue_item` | Crude javelin head bound with sinew, coated in grey hill clay (0 gp). |
| `willems_scouting_sketch` | `mordale_cottage` | `quest_item` | Willem's charcoal sketch: *"The arch stones look weak and ready to crumble if shouted near... saw goblins stringing tripwires across doorways in the dark."* (0 gp). |
| `violet_crystal_shard` | `mordale_cottage` | `quest_item` | Unnaturally cold purple crystal fragment pulsing faintly in shadows (10 gp). |
| `goblin_wolf_collar` | `trappers_cabin` | `clue_item` | Iron-and-leather collar with crude beast-runes salvaged from a snared scout wolf (1 gp). |
| `trappers_beast_notes` | `trappers_cabin` | `clue_item` | Kaelen's notes: *"Ruins wolves are chained and starved. They fear open fire intensely, and fresh meat distracts them immediately."* (0 gp). |
| `vaeliths_chronicle_excerpt` | `elders_study` | `clue_item` | Account of the 30-year-old disaster: *"A purple blast shook the valley as the tower fell. Vaelith raved that Talven was trapped in the unsealed circle."* (5 gp). |
| `archival_estate_receipt` | `elders_study` | `clue_item` | 40-year-old masonry order for Vaelith's private storeroom: *"Double-walled hollow stonecraft ordered for master storage room."* (5 gp). |

---

## 6. NPC Roster (Tier-3 BDI Actors)

All actors are defined under `initial_actors:` with full AD&D 1E combat stats, `tier: 3`, `is_alive: true`, and rich `dossier:` blocks:

1. **`mara`** (`maras_inn`): Innkeeper, warm, observant, gossipy.
2. **`mayor_grevik`** (`maras_inn`): Village leader, solemn, protective, manages 100 gp bounty.
3. **`erik_the_shepherd`** (`maras_inn`): Shepherd, gruff, worried, tracked tracks to the hill.
4. **`anna_mordale`** (`maras_inn`): Willem's wife, desperate, offers 20 gp reward for his rescue.
5. **`torvald_ironhand`** (`blacksmith_shop`): Blacksmith, devotee of Korvath, stalwart, complains of stolen tools.
6. **`jorren`** (`general_store`): Shopkeeper, practical, cautious, recommends 10-ft poles.
7. **`thessia_brightmix`** (`herbalist_shop`): Herbalist, student of Mystara, observant of purple plant blight.
8. **`hael_bloodwood`** (`butchers_shop`): Butcher, sharp-eyed, analyzes wolf bite marks and provides bait.
9. **`silas_vance`** (`pawn_shop`): Broker and appraiser, warns against shadow crystals and bad dreams.
10. **`sister_aldara`** (`temple_of_thyra`): Cleric of Thyra and Solara, provides healing, holy water, and omens.
11. **`captain_gareth`** (`town_jail`): Watch captain, veteran soldier, details goblin night-raid habits.
12. **`kaelen_the_trapper`** (`trappers_cabin`): Woodsman, keen tracker, knows wolf fire-weakness.
13. **`elder_corvus`** (`elders_study`): Village scholar, knows Vaelith's history and hollow stonework lore.

---

## 7. Spatial Boundaries & Initial Commitments

### 7.1 Boundaries
Every town location is given an explicit place boundary with `triggers: ["presence_crossing", "signal_arrived"]`, `wake_on_intensity: 4`, and `sleep_after: 60`:
- `maras_inn_zone` (`place: "maras_inn"`)
- `town_green_zone` (`place: "village_green"`)
- `blacksmith_zone` (`place: "blacksmith_shop"`)
- `general_store_zone` (`place: "general_store"`)
- `apothecary_zone` (`place: "herbalist_shop"`)
- `butcher_zone` (`place: "butchers_shop"`)
- `pawn_shop_zone` (`place: "pawn_shop"`)
- `temple_zone` (`place: "temple_of_thyra"`)
- `town_hall_zone` (`place: "town_hall"`)
- `town_jail_zone` (`place: "town_jail"`)
- `town_treasury_zone` (`place: "town_treasury"`)
- `eriks_farm_zone` (`place: "eriks_farm"`)
- `mordale_cottage_zone` (`place: "mordale_cottage"`)
- `trappers_cabin_zone` (`place: "trappers_cabin"`)
- `elders_study_zone` (`place: "elders_study"`)

### 7.2 Initial Commitments
- `grevik_quest_offer`: Grevik explains livestock raids and offers 100 gp bounty (priority 8).
- `anna_rescue_plea`: Anna pleads for Willem's rescue with 20 gp reward (priority 7).
- `erik_raid_warning`: Erik recounts goblin attack and tracks (priority 6).
- `mara_hospitality_and_rumors`: Mara offers hot stew and shares tower rumors (priority 4).
- `torvald_forge_work`: Torvald tends forge, offering sturdy arms and repairs (priority 5).
- `jorren_stock_gear`: Jorren equips delve expeditions with poles and rope (priority 5).
- `thessia_alchemical_care`: Thessia prepares antivenom and measures spell reagents (priority 5).
- `aldara_sacred_communion`: Sister Aldara tends temple font and offers blessings (priority 6).
- `gareth_militia_watch`: Captain Gareth reviews night watch incident logs (priority 6).
- `silas_appraisal_desk`: Silas examines curious relics and exchanges coin (priority 4).
- `kaelen_scout_prep`: Kaelen repairs wolf traps and recounts beast behavior (priority 5).
- `corvus_chronicle_study`: Elder Corvus archives tower history and estate blueprints (priority 5).

---

## 8. Verification & Test Plan

1. **Schema Validation:** Run `EngineCore.Validator.check_file/1` on `ruined_tower.yaml` to ensure zero unknown rooms, missing actor fields, invalid boundary triggers, or debtor mismatches.
2. **World Loader Build:** Load world via `EngineCore.Loader.load/1` and assert all 15 places, 13 town actors, 8 clue/quest items, 15 place boundaries, and commitments construct a coherent `%World{}`.
3. **Boundary Activation on Starting Place:** Assert `run_test.exs` starting place wake test passes for `maras_inn_zone` waking `mara`, `mayor_grevik`, `erik_the_shepherd`, and `anna_mordale`.
4. **Full Test Suite:** Run `mix test` across all 7 umbrella applications (`engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`) ensuring 100% pass rate.
