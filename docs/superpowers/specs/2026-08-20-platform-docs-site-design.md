# The Shattered Kingdoms — Platform Documentation & Interactive Showcase Design

**Date:** 2026-08-20  
**Status:** Approved  
**Topic:** D&D-Themed Astro Documentation Platform & Interactive Engine Showcase  
**Target:** `docs/`  

---

## 1. Executive Summary & Vision

This specification defines the architecture, visual design system, interactive simulator components, and technical documentation handbook for **The Shattered Kingdoms Platform** (`shards_engine`).

The platform is a dual-purpose product:
1. **The Adventure Marketplace (Ecosystem):** A two-sided marketplace where tabletop adventure modules are authored in clean YAML, published, and sold with platform revenue share.
2. **The Autonomous Referee Engine (Runtime):** A deterministic, agent-oriented Elixir/OTP platform where every NPC and monster is an autonomous BDI agent, the referee is an automated preference-driven adjudicator, and world truth is immutably preserved in an append-only ledger.

The documentation site serves as both the flagship technical reference manual and the commercial product showcase, built in Astro v5 with an authentic AD&D dark-fantasy aesthetic, masterclass pure-CSS animations/3D polyhedral graphics, and rich interactive engine simulations.

---

## 2. Directory Layout & Astro Architecture

The documentation site resides directly in `docs/`, configured so that `srcDir` is scoped to `./src` and coexists peacefully with the existing `docs/superpowers/` plan/spec hierarchy.

```
docs/
├── package.json               # Astro v5, TypeScript, Lucide icons
├── astro.config.mjs           # Astro configuration (srcDir: './src')
├── tsconfig.json              # Strict TypeScript config
├── public/                    # Static assets, favicon, social cards
├── src/
│   ├── components/
│   │   ├── layout/            # Header, Sidebar, Footer, Navigation, SearchModal, TOC
│   │   ├── visualizers/       # 5 Interactive D&D / Engine Showpieces
│   │   │   ├── RefereePipeline.astro    # Step-by-step referee flow simulator
│   │   │   ├── LedgerScrubber.astro     # Deterministic replay & event timeline
│   │   │   ├── BrainExplorer.astro      # BDI belief graph & salience sliders
│   │   │   ├── DiceRoller3D.astro       # Pure CSS 3D d20/d8/d6 roller + THAC0
│   │   │   └── SpatialMap.astro         # Dungeon boundaries & signal propagation
│   │   ├── ui/                # Fantasy UI primitives: RunicBadge, ParchmentCard, etc.
│   │   └── icons/             # Custom SVG fantasy & tech glyphs (Runes, D20, Swords, Shield)
│   ├── content/
│   │   ├── config.ts          # Content Collections schema (zod validation)
│   │   └── docs/              # 9 Technical & Architectural handbook chapters
│   │       ├── 01-overview.md
│   │       ├── 02-architecture-supervision.md
│   │       ├── 03-referee-pipeline.md
│   │       ├── 04-agent-cognition-bdi.md
│   │       ├── 05-signals-perception-boundaries.md
│   │       ├── 06-llm-gateway-routing.md
│   │       ├── 07-wire-protocol-clients.md
│   │       ├── 08-adventure-authoring-yaml.md
│   │       └── 09-platform-marketplace-vision.md
│   ├── layouts/
│   │   ├── BaseLayout.astro   # HTML shell, metadata, CSS tokens, atmospheric backdrop
│   │   ├── LandingLayout.astro# Full-width hero showcase layout
│   │   └── DocLayout.astro    # Reading layout with sticky sidebar & on-this-page TOC
│   ├── pages/
│   │   ├── index.astro        # High-impact Product Showcase & Live Interactive Hub
│   │   ├── visualizers/       # Dedicated standalone full-screen pages for each tool
│   │   │   ├── referee.astro
│   │   │   ├── replay.astro
│   │   │   ├── brains.astro
│   │   │   ├── dice.astro
│   │   │   └── dungeon.astro
│   │   └── docs/
│   │       └── [...slug].astro# Dynamic content collection router
│   └── styles/
│       ├── tokens.css         # Colors, typography, spacing, shadows, runic glow variables
│       ├── typography.css     # Uncial/Cinzel/Medieval headers, clean monospace code
│       ├── fantasy-fx.css     # CSS 3D transforms, glowing border beams, parchment textures
│       └── global.css         # CSS reset & base element styling
```

---

## 3. Visual Theme & Masterclass CSS Design System

### 3.1 Design Tokens (`styles/tokens.css`)

```css
:root {
  /* Basalt & Stone Foundations */
  --bg-void: #07090d;
  --bg-surface: #0e1219;
  --bg-surface-raised: #151a24;
  --bg-surface-hover: #1c222e;
  --border-stone: #242c3b;
  --border-stone-subtle: #181f2a;
  --border-gold: rgba(223, 177, 91, 0.35);

  /* Reclamation Gold & Runes */
  --gold-primary: #dfb15b;
  --gold-bright: #f3cf7a;
  --gold-dark: #8c6721;
  --gold-glow: rgba(223, 177, 91, 0.45);
  --gold-gradient: linear-gradient(135deg, #f3cf7a 0%, #dfb15b 50%, #9e7529 100%);
  --amber-rune: #ff9d42;
  --amber-glow: rgba(255, 157, 66, 0.4);

  /* Arcane & Health */
  --crimson-blood: #e05238;
  --crimson-glow: rgba(224, 82, 56, 0.4);
  --mana-azure: #38bdf8;
  --mana-glow: rgba(56, 189, 248, 0.4);
  --shadow-crystal: #a855f7;
  --shadow-glow: rgba(168, 85, 247, 0.4);
  --emerald-rekindler: #10b981;

  /* Parchment Overlay & Ink */
  --parchment-bg: #f5eedb;
  --parchment-border: #d8c8a6;
  --ink-primary: #1f1a14;
  --ink-muted: #574e41;

  /* Typography Stack */
  --font-display: 'Cinzel', 'Trajan Pro', Georgia, serif;
  --font-body: 'Charis SIL', 'Crimson Pro', Garamond, Georgia, serif;
  --font-mono: ui-monospace, SFMono-Regular, 'Fira Code', Menlo, monospace;
}
```

### 3.2 Key Visual Techniques

1. **Runic Border-Beam Animations (`@property --angle`):**
   * Uses CSS Custom Property angle interpolation (`@property --angle { syntax: '<angle>'; initial-value: 0deg; inherits: false; }`) with continuous rotational `conic-gradient` tracking along container boundaries.
2. **Procedural Noise Textures:**
   * Embedded inline SVG `<filter id="noise">` data URIs simulating chiseled granite, aged iron plate, and coarse parchment paper fibers without external image dependencies.
3. **Pure CSS 3D Polyhedrals (d20, d8, d6):**
   * True CSS 3D geometric polyhedrals built using `transform-style: preserve-3d`, `perspective: 1000px`, and `@keyframes roll-tumble` that land on deterministic face rotations.
4. **Atmospheric Backdrop:**
   * Layered radial gradients with ambient upward floating particle embers (`@keyframes ember-rise`) and rune constellation lines.

---

## 4. Interactive Components Specification

### 4.1 Referee Pipeline Simulator (`RefereePipeline.astro`)
* **Core Principle:** Demonstrates *LLM proposes, engine disposes*.
* **5 Interactive Stages:**
  1. *Intent Input:* Editable natural language prompt or selectable presets (`"I strike the goblin with my longsword"`, `"I search the library wall for hidden runes"`).
  2. *Interpretation:* Shows JSON-schema extraction (`verb: :strike, target: "goblin_1"`) with toggles between LLM-first parsing and Grammar fallback.
  3. *Validation:* Displays diegetic engine rule evaluations (line-of-sight, weapon readiness, target co-presence).
  4. *Resolution & Roll:* Displays seeded d20 to-hit vs THAC0 table, computing hit/miss and damage without side effects.
  5. *Apply & Narrate:* Shows ledger event commits (`:damage`, `:death`) and generated PC-perceived narration text.
* **Controls:** Step Forward, Step Back, Auto-play, Branch Mutation toggles (e.g. simulate invalid target).

### 4.2 Ledger Time-Travel & Determinism Scrubber (`LedgerScrubber.astro`)
* **Core Principle:** Proves `fold(ledger) == World.snapshot` at any point in history.
* **Interface:**
  * Interactive range slider scrubbing from `seq 1` to `seq 50+`.
  * Live-updating World State inspector (Room actors, HP bars, item locations).
  * Dual-branch fork-diff viewer comparing Run A vs Run B starting from seed 42 and highlighting the exact emergence divergence point.

### 4.3 Agent BDI Brain & Belief Map Explorer (`BrainExplorer.astro`)
* **Core Principle:** Supervised deliberation actors holding no authority state.
* **Interface:**
  * Interactive SVG node graph showing agent beliefs (locations, observed creatures, threat level).
  * Salience meter ($0.0 - 10.0$) with trigger thresholds ($\ge 5.0$ wakes agent).
  * Autonomous Order Adoption simulator (evaluates creditor authority, co-location, and reliability heuristics before adding to commitment queue).

### 4.4 3D CSS Polyhedral Dice Roller & Sandbox (`DiceRoller3D.astro`)
* **Core Principle:** Deterministic seeded dice generation rendered in pure 3D CSS.
* **Interface:**
  * Interactive 3D d20, d8, d6 dice with authentic 60fps tumbling physics.
  * Interactive AD&D 1E combat calculator (Select Attacker Class/Level, Defender Armor Class $\rightarrow$ computes target to-hit number, executes 3D roll, and resolves damage).

### 4.5 Spatial Boundaries & Signal Cascade Map (`SpatialMap.astro`)
* **Core Principle:** Spatial activation gates compute; signals attenuate through dungeon topology.
* **Interface:**
  * Interactive SVG floorplan of *The Ruined Tower* (Rooms 1-7).
  * Sound/light wave ripple animation triggered by room actions (e.g., sword strike in Guard Room attenuates through closed wooden door).
  * Visual room dormancy indicators (Awake vs Dormant).

---

## 5. Technical Documentation Handbook Chapters

The documentation covers 9 comprehensive chapters managed via Astro Content Collections:

| Chapter | Title | Key Coverage |
|---|---|---|
| `01-overview.md` | System Overview & Philosophy | Engine/content split, deterministic simulation, 4-human party playthrough, quickstart commands |
| `02-architecture-supervision.md` | Engine Architecture & OTP Topology | Hybrid Brain/Ledger split, `Ledger.Writer`, `World.Server`, `Run.Session`, Replay determinism contract |
| `03-referee-pipeline.md` | The Referee Adjudication Pipeline | 5-stage pipeline, AD&D 1E rules (combat rounds, segments, THAC0, saves, 1gp=1XP), 3-tier preference stack |
| `04-agent-cognition-bdi.md` | Agent Cognition & BDI Brains | 4 cognition tiers, belief stores, salience escalation gates, commitments, autonomous order adoption |
| `05-signals-perception-boundaries.md` | Spatial Activation, Boundaries & Signals | Agent-defined boundaries, trigger types, signal emission & edge attenuation, per-PC truth barrier |
| `06-llm-gateway-routing.md` | LLM Gateway & Orchestration | `LLMGateway.Router` chokepoint, adapters (Scripted, Claude, OpenAI), budget degradation, circuit breakers |
| `07-wire-protocol-clients.md` | Wire Protocol & Client Architecture | Phoenix Channels line-JSON (vsn 2.0.0), `run:<id>` vs `spectate:<id>`, Reference TUI & LiveView clients |
| `08-adventure-authoring-yaml.md` | Adventure Authoring & YAML Schema | Seed YAML specification (`ruined_tower.yaml`), dungeon mapping, encounter design, module preferences |
| `09-platform-marketplace-vision.md` | Platform Vision & Marketplace Business | Adventures as SKUs, runtime sandboxes, per-token margin metering, cross-run memory (v2 roadmap) |

---

## 6. Verification & Acceptance Criteria

1. **Build & Typecheck:** `npm run build` exits 0 with zero TypeScript or Astro compiler errors.
2. **Interactive 60fps Physics:** All 5 interactive visualizers render smoothly across modern desktop and mobile browsers.
3. **Pure CSS Craftsmanship:** 3D polyhedrals, glowing borders, and procedural textures operate without heavy external 3D libraries.
4. **Content Completeness:** All 9 technical documentation chapters are authored with accurate architectural diagrams, code snippets, and deep platform references.
5. **Offline Ready:** Zero reliance on dynamic external CDNs for core styles or scripts.
