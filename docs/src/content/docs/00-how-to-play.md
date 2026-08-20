---
title: "How to Play"
description: "A complete step-by-step player and referee guide to playing adventures in The Shattered Kingdoms."
order: 0
category: "Foundation"
tags: ["how-to-play", "player-guide", "tutorial", "starter-adventure", "gameplay"]
---

# How to Play The Shattered Kingdoms

Welcome to **The Shattered Kingdoms**—an autonomous-agent tabletop roleplaying platform set in the realm of Aeldoroth during the Age of Reclamation.

Unlike traditional computer RPGs with rigid dialogue trees or button-press actions, The Shattered Kingdoms lets you **type natural English actions** just like you would describe them to a live Game Master at a physical tabletop. The engine's automated referee interprets your intent, diegetically validates your surroundings, rolls authentic AD&D 1E dice, and delivers personalized sensory narrations to your screen.

---

## 1. Quick Start: Launching a Game

You can play via the **Web Console** in any modern web browser or via the **Terminal Client**.

### Option A: The Web Console (Recommended)

Start the local web server from the project directory:

```bash
cd shards_engine
MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Open your browser to:
```
http://localhost:4000/
```

1. **Create a Run:** The home page prefills a new run using the starter adventure `the-ruined-tower/ruined_tower.yaml` and a 2-character party (Thistle the Fighter and Bramble the Thief). Click **Start Run**.
2. **Claim a Seat:** You will land on `/runs/<run_id>`. Click a character name (e.g. **Thistle**) to claim that character's seat.
3. **Open Multiple Players:** In a separate browser tab or window, navigate to `/runs/<run_id>` and claim **Bramble** to play with multiple party members!
4. **Open the GM Console:** Open `/runs/<run_id>/gm` in another tab to observe the live dungeon state and advance game time.

### Option B: The Terminal Client (`client_tui`)

If you prefer an authentic retro ASCII terminal experience:

```bash
cd shards_engine
mix run -e "ClientTUI.CLI.main(System.argv)" -- --url http://localhost:4000 --run my_run --character pc_thistle
```

---

## 2. Choosing Your Character Seat

In the starter adventure, *The Ruined Tower*, players pilot members of an adventuring party investigating a collapsed wizard's tower infested by raiding goblins:

| Character | Class | Level | HP | AC | THAC0 | Weapon & Damage | Role & Strengths |
|---|---|---|---|---|---|---|---|
| **Thistle** | Fighter | 1 | 12 | 5 (Chain) | 20 | Longsword (1d8) | Frontline melee powerhouse; high survivability and steady blade work. |
| **Bramble** | Thief | 1 | 8 | 6 (Leather) | 19 | Shortsword (1d6) | Stealth, trap detection, lockpicking, and backstab ambush damage. |

When you select a character, the **Truth Barrier** activates: your screen receives only the sensory information (sight, sound, smell) that your specific character can perceive from their current room.

---

## 3. Taking Your Turn: Declaring Intent

To act, simply type what you want your character to do into the **Declare** box and press Enter or click **Declare**.

### How to Declare Actions

The platform supports two interpretation modes: **Deterministic Local Mode** (default, 100% offline with zero API keys) and **Frontier LLM Mode** (when connected to a live model gateway).

#### 1. Exploration & Movement
To move between rooms in the ruins:
* **Bare Directions:** `"north"`, `"south"`, `"east"`, `"west"`, `"up"`, `"down"` (or shorthand `"n"`, `"s"`, `"e"`, `"w"`)
* **Natural Movement:** `"I head north"`, `"go to the library"`, `"walk east"`, `"step into the guard room"`
* **Room Names:** `"library"`, `"guard_room"`, `"enter library"`

#### 2. Observation & Scouting
To pause, listen, or search your surroundings:
* `"look around"` or `"examine room"`
* `"search"` or `"search for traps"`
* `"listen"` or `"listen at the doorway"`
* `"wait"` or `"hold"` (spends the moment observing quietly)

#### 3. Combat & Attacks
When hostile creatures are present in your character's room:
* `"attack the goblin guard"` or `"strike the sentry with my longsword"`
* `"shoot the goblin"` or `"stab the guard"`
*(Note: If you declare an attack in an empty room where no enemies are believed to be present, the referee will indicate there is nothing to strike.)*

#### 4. Speech & Communication
* **In-World Speech:** `"shout 'To me, Bramble!'"` or `"call 'Who is in there?'"` (can be heard by nearby rooms depending on sound attenuation).
* **Out-of-Character Table Talk:** Type in the **OOC** box below the declare box to coordinate tactics with your fellow players without taking an in-world action.
---

## 4. The 5-Stage Referee Adjudication Cycle

Every action you submit flows through a deterministic 5-stage referee pipeline:

```
[ Your Natural Intent ]
         │
         ▼
  1. INTERPRET    ───► Extracts structured action (%Action{verb: :strike, target: "goblin_1"})
         │
         ▼
  2. VALIDATE     ───► Checks line-of-sight, weapon readiness, and spatial reach
         │
         ▼
  3. RESOLVE      ───► Rolls seeded AD&D 1E dice (THAC0 vs Armor Class)
         │
         ▼
  4. APPLY        ───► Pure reducers commit events to the append-only ledger
         │
         ▼
  5. NARRATE      ───► Generates vivid sensory perception delivered to your screen
```

1. **Interpret:** The engine parses your natural language into a typed Action. If the LLM gateway is offline or unconfigured, the engine automatically uses deterministic grammar parsing.
2. **Validate:** The referee checks real physical invariants: Are you in the same room as the target? Is your weapon drawn? Are you conscious?
3. **Resolve:** If an attack or check is needed, the engine draws from a seeded random stream to roll the dice.
4. **Apply:** Pure state reducers update world truth (reducing HP, opening doors, transferring items) and append the record to an immutable ledger.
5. **Narrate:** The referee generates an in-character perception text describing what you see, hear, and feel.

---

## 5. Combat & Rules (AD&D 1E Mechanics)

The referee engine natively runs official **Advanced Dungeons & Dragons 1st Edition** rules:

### How Attacks Work (THAC0)
* **THAC0** stands for *"To Hit Armor Class 0"*.
* To calculate the target number you need to roll on a **d20**:
  $$\text{Target Roll} = \text{Attacker THAC0} - \text{Defender AC}$$
* **Example:** Thistle (THAC0 20) strikes a Goblin Guard wearing studded leather (AC 6):
  $$\text{Target} = 20 - 6 = 14+$$
* If Thistle rolls **14 or higher** on the d20, the strike hits! The engine then rolls weapon damage (e.g. `1d8` for a longsword) and subtracts it from the goblin's HP.

### Monster Morale & Surrender
Monsters in The Shattered Kingdoms are not mindless combat automata. When a warband loses its leader or suffers heavy casualties, the engine triggers a **Morale Check**. If morale breaks, surviving goblins will surrender, plead for their lives, or scatter into dark corridors.

### Experience Points (XP)
* **1 Gold Piece (gp) = 1 XP:** Recovering lost treasures from the ruins is the primary way characters level up.
* **Creative Encounter Resolution:** You receive full XP for outsmarting, bribing, or sneaking past monsters—slaughter is never mandatory.

---

## 6. Responding to Referee Prompts (Clarifications)

If your declared action is ambiguous, the referee will pause and display a golden prompt box:

```
┌───────────────────────────────────────────────────────────┐
│ ❓ Referee asks: "There are two iron chests—one by the    │
│    altar and one hidden behind the bookcase. Which one    │
│    do you search?"                                        │
└───────────────────────────────────────────────────────────┘
```

When a prompt appears, simply type your clarification into the input box and click **Declare** (e.g. `"The one behind the bookcase"`). The referee immediately resumes the action.

---

## 7. Out-of-Character Table Talk (`/ooc`)

Sometimes you want to discuss strategy with your party members without having your character say it out loud in the dungeon:

* **In the Web UI:** Type your message into the **OOC** box and click **OOC**.
* **In the Terminal Client:** Prefix your line with `/ooc <message>`.

OOC table talk is broadcast to all active player seats with an *italicized purple tag* (e.g. `[OOC] Thistle: Let's coordinate our attacks on the chief!`), but **does not advance game time** and cannot be overheard by dungeon monsters.

---

## 8. The Truth Barrier

In tabletop RPGs, players often accidentally act on metagame knowledge their characters wouldn't know. The Shattered Kingdoms enforces the **Truth Barrier** at the architectural level:

* If Thistle is in the *Entry Hall* and Bramble is scouting the *Library*, Thistle **cannot see** what is inside the Library.
* Loud sounds (such as a battle or alarm bell) **attenuate across doors and walls**, so Thistle might receive a muffled sound perception:
  > *"[tick 2] You hear the sharp ring of clashing steel echoing from the east doorway."*
* Hidden traps, monster stats, and secret DM notes never cross the network wire to player browsers.

---

## 9. The Game Master (GM) Console

If you are running the session as the Referee / Game Master, the **GM Console** at `/runs/<run_id>/gm` gives you complete oversight:

* **Advance Time:** Click **Advance** to progress world time (advancing monster deliberations and patrol routes).
* **Pause & Secret Dossiers:** Click **Pause & dossier** to freeze the session and generate private summary dossiers detailing what each character remembers and secretly suspects.
* **Resume:** Click **Resume** to reopen player declarations.
* **Inspect Spatial Boundaries:** See in real-time which dungeon rooms are `AWAKE` (consuming compute) versus `DORMANT` (sleeping until disturbed).
* **Live Ledger Tail:** Watch raw immutable game events (`:world`, `:dice`, `:signal`, `:narration`) stream in sequence.

---

## 10. Example Gameplay Transcript

Here is an authentic snippet of a two-player turn inside *The Ruined Tower*:

```text
[Thistle enters the seat at Entry Hall]
Perception: You stand in the vaulted Entry Hall of the Ruined Tower. Broken flagstones 
are littered with old goblin bones and soot. Arched doorways lead North to the Library 
and East to the Guard Room.

> Thistle declares: "I ready my shield and cautiously open the east door."

[Referee validates movement; door opens; Guard Room boundary wakes up]
Perception: The heavy timber door groans open. In the torchlit Guard Room beyond, a goblin 
sentry jumps up from a stool with a snarl, raising a notched scimitar!

> Bramble declares: "I slip into the shadows behind Thistle and aim my shortbow."

[Referee resolves initiative and attacks]
Dice: d20 roll = 17 vs Target 14 (HIT!)
Perception: Bramble's arrow whistles past Thistle's shoulder, piercing the goblin sentry's 
arm for 5 damage. The goblin shrieks an alarm!

[Signal cascade: Sound wave intensity 8 travels west back to Entry Hall]
Perception: The goblin drops its weapon and cowers against the wall, raising its hands 
in surrender.
```

---

## Next Steps

* **Try the Interactive Simulators:** Test the [3D Dice Roller](/visualizers/dice) or step through the [Referee Pipeline Simulator](/visualizers/referee).
* **Explore the Architecture:** Read [Chapter 02: Engine Architecture & OTP Topology](/docs/02-architecture-supervision) to learn how the Elixir backend guarantees deterministic truth.
* **Author an Adventure:** Read [Chapter 08: Adventure Authoring YAML](/docs/08-adventure-authoring-yaml) to learn how to write your own modules.
