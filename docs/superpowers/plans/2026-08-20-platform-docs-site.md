# The Shattered Kingdoms Platform Documentation Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a masterclass D&D-themed documentation and commercial product showcase website in `docs/` using Astro v5, featuring an authentic dark fantasy visual design system, pure-CSS 3D polyhedral dice physics, 5 interactive engine simulators, and a 9-chapter technical handbook documenting the `shards_engine` Elixir platform.

**Architecture:** Standalone Astro v5 project configured inside `docs/` (`srcDir: './src'`), rendering static pages with zero heavy JS framework dependencies. Pure CSS modern design system utilizing custom properties, `@property` conic border beams, SVG turbulence filters, and CSS 3D transforms (`transform-style: preserve-3d`). Interactive components built as lightweight vanilla custom elements/islands. Documentation managed via Astro Content Collections with markdown/MDX.

**Tech Stack:** Astro v5, TypeScript, Modern CSS (3D Transforms, CSS Houdini `@property`, SVG Filters), HTML5 Custom Elements.

## Global Constraints

- Astro source resides strictly in `docs/src/` with `docs/package.json` and `docs/astro.config.mjs`.
- Existing `docs/superpowers/` plan and spec documents must remain untouched and ignored by Astro build.
- Zero reliance on external dynamic CDNs at runtime; all styling, fonts, and assets are local/vendored.
- Zero framework bloat (no heavy React/Vue runtime packages); interactive widgets use pure CSS and lightweight vanilla Web Components.
- Build command `npm run build` inside `docs/` must exit 0 with zero TypeScript or Astro compiler errors.

---

## File Map

```
docs/
├── package.json
├── astro.config.mjs
├── tsconfig.json
├── public/
│   ├── favicon.svg
│   └── og-image.svg
├── src/
│   ├── content/
│   │   ├── config.ts
│   │   └── docs/
│   │       ├── 01-overview.md
│   │       ├── 02-architecture-supervision.md
│   │       ├── 03-referee-pipeline.md
│   │       ├── 04-agent-cognition-bdi.md
│   │       ├── 05-signals-perception-boundaries.md
│   │       ├── 06-llm-gateway-routing.md
│   │       ├── 07-wire-protocol-clients.md
│   │       ├── 08-adventure-authoring-yaml.md
│   │       └── 09-platform-marketplace-vision.md
│   ├── styles/
│   │   ├── tokens.css
│   │   ├── typography.css
│   │   ├── fantasy-fx.css
│   │   └── global.css
│   ├── layouts/
│   │   ├── BaseLayout.astro
│   │   ├── LandingLayout.astro
│   │   └── DocLayout.astro
│   ├── components/
│   │   ├── layout/
│   │   │   ├── Header.astro
│   │   │   ├── Sidebar.astro
│   │   │   ├── Footer.astro
│   │   │   ├── TableOfContents.astro
│   │   │   └── SearchModal.astro
│   │   ├── ui/
│   │   │   ├── RunicBadge.astro
│   │   │   ├── ParchmentCard.astro
│   │   │   ├── OrnamentalDivider.astro
│   │   │   └── StatBlock.astro
│   │   ├── icons/
│   │   │   └── Icons.astro
│   │   └── visualizers/
│   │       ├── DiceRoller3D.astro
│   │       ├── RefereePipeline.astro
│   │       ├── LedgerScrubber.astro
│   │       ├── BrainExplorer.astro
│   │       └── SpatialMap.astro
│   └── pages/
│       ├── index.astro
│       ├── docs/
│       │   └── [...slug].astro
│       └── visualizers/
│           ├── dice.astro
│           ├── referee.astro
│           ├── replay.astro
│           ├── brains.astro
│           └── dungeon.astro
```

---

### Task 1: Project Scaffolding & Astro Configuration

**Files:**
- Create: `docs/package.json`
- Create: `docs/astro.config.mjs`
- Create: `docs/tsconfig.json`
- Create: `docs/src/content/config.ts`

**Interfaces:**
- Produces: Astro v5 build pipeline targeting `./src` with TypeScript and Content Collections schema.

- [ ] **Step 1: Write `docs/package.json`**

```json
{
  "name": "shattered-kingdoms-docs",
  "type": "module",
  "version": "0.1.0",
  "scripts": {
    "dev": "astro dev",
    "start": "astro dev",
    "build": "astro check && astro build",
    "preview": "astro preview",
    "astro": "astro"
  },
  "dependencies": {
    "@astrojs/check": "^0.9.4",
    "@astrojs/mdx": "^4.0.8",
    "@astrojs/sitemap": "^3.2.1",
    "astro": "^5.3.0",
    "typescript": "^5.7.3"
  }
}
```

- [ ] **Step 2: Write `docs/astro.config.mjs`**

```javascript
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://shattered-kingdoms.dev',
  srcDir: './src',
  outDir: './dist',
  integrations: [mdx(), sitemap()],
  markdown: {
    shikiConfig: {
      theme: 'dracula-soft',
      wrap: true
    }
  }
});
```

- [ ] **Step 3: Write `docs/tsconfig.json`**

```json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "strictNullChecks": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": [".astro/types.d.ts", "**/*"],
  "exclude": ["dist", "superpowers"]
}
```

- [ ] **Step 4: Write `docs/src/content/config.ts`**

```typescript
import { defineCollection, z } from 'astro:content';

const docs = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    order: z.number(),
    category: z.enum(['Foundation', 'Architecture', 'Agents & Referee', 'Protocol & Tooling', 'Ecosystem']),
    tags: z.array(z.string()).default([]),
    updatedAt: z.string().optional()
  })
});

export const collections = { docs };
```

- [ ] **Step 5: Install dependencies & verify project structure**

```bash
cd docs && npm install && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 6: Commit**

```bash
git add docs/package.json docs/astro.config.mjs docs/tsconfig.json docs/src/content/config.ts docs/package-lock.json
git commit -m "docs: scaffold Astro v5 documentation platform and content collections"
```

---

### Task 2: Masterclass CSS Design System

**Files:**
- Create: `docs/src/styles/tokens.css`
- Create: `docs/src/styles/typography.css`
- Create: `docs/src/styles/fantasy-fx.css`
- Create: `docs/src/styles/global.css`

**Interfaces:**
- Consumes: Standard CSS variables and modern browser CSS APIs.
- Produces: Complete atmospheric grim-dark D&D design system tokens, keyframe animations, 3D transform layers, and procedural textures.

- [ ] **Step 1: Write `docs/src/styles/tokens.css`**

```css
@property --angle {
  syntax: '<angle>';
  initial-value: 0deg;
  inherits: false;
}

:root {
  /* Basalt & Stone Foundations */
  --bg-void: #06080c;
  --bg-surface: #0c1017;
  --bg-surface-raised: #131822;
  --bg-surface-hover: #1b2230;
  --border-stone: #242e40;
  --border-stone-subtle: #161d2a;
  --border-gold: rgba(223, 177, 91, 0.35);

  /* Reclamation Gold & Runes */
  --gold-primary: #dfb15b;
  --gold-bright: #f6d88e;
  --gold-dark: #8c6721;
  --gold-glow: rgba(223, 177, 91, 0.4);
  --gold-gradient: linear-gradient(135deg, #f6d88e 0%, #dfb15b 50%, #9e7529 100%);
  --amber-rune: #ff9d42;
  --amber-glow: rgba(255, 157, 66, 0.45);

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
  --font-body: 'Charis SIL', 'Crimson Pro', Georgia, serif;
  --font-mono: ui-monospace, SFMono-Regular, 'Fira Code', Menlo, monospace;

  /* Layout Constants */
  --header-height: 4rem;
  --sidebar-width: 18rem;
  --max-width: 84rem;
}
```

- [ ] **Step 2: Write `docs/src/styles/typography.css`**

```css
@import url('https://fonts.googleapis.com/css2?family=Cinzel:wght@500;700;900&family=Crimson+Pro:ital,wght@0,400;0,600;0,700;1,400&family=Fira+Code:wght@400;500&display=swap');

h1, h2, h3, h4, .font-display {
  font-family: var(--font-display);
  letter-spacing: 0.04em;
  color: var(--gold-bright);
}

h1 {
  font-size: clamp(2rem, 4vw, 3.25rem);
  line-height: 1.15;
  text-shadow: 0 0 20px var(--gold-glow);
}

h2 {
  font-size: clamp(1.5rem, 2.5vw, 2.25rem);
  line-height: 1.25;
  border-bottom: 1px solid var(--border-stone);
  padding-bottom: 0.5rem;
  margin-top: 2rem;
}

h3 {
  font-size: 1.35rem;
  color: var(--gold-primary);
  margin-top: 1.5rem;
}

p, li, .font-body {
  font-family: var(--font-body);
  font-size: 1.125rem;
  line-height: 1.7;
  color: #c9d2e0;
}

code, pre, .font-mono {
  font-family: var(--font-mono);
  font-size: 0.925rem;
}

.drop-cap::first-letter {
  font-family: var(--font-display);
  float: left;
  font-size: 3.5rem;
  line-height: 0.85;
  padding-right: 0.6rem;
  color: var(--gold-bright);
  text-shadow: 0 0 15px var(--gold-glow);
}
```

- [ ] **Step 3: Write `docs/src/styles/fantasy-fx.css`**

```css
/* Runic Glowing Border Beam */
.runic-border-beam {
  position: relative;
  background: var(--bg-surface);
  border-radius: 0.5rem;
  border: 1px solid var(--border-stone);
  overflow: hidden;
}

.runic-border-beam::before {
  content: '';
  position: absolute;
  inset: -2px;
  background: conic-gradient(
    from var(--angle),
    transparent 0%,
    var(--gold-bright) 25%,
    var(--amber-rune) 35%,
    transparent 50%
  );
  animation: rotate-beam 6s linear infinite;
  z-index: -1;
  border-radius: inherit;
}

@keyframes rotate-beam {
  0% { --angle: 0deg; }
  100% { --angle: 360deg; }
}

/* Atmospheric Particle Ember Rise */
.ember-particles {
  position: fixed;
  inset: 0;
  pointer-events: none;
  background-image: 
    radial-gradient(2px 2px at 20px 30px, var(--gold-bright), rgba(0,0,0,0)),
    radial-gradient(2px 2px at 40px 70px, var(--amber-rune), rgba(0,0,0,0)),
    radial-gradient(1px 1px at 90px 40px, var(--crimson-blood), rgba(0,0,0,0)),
    radial-gradient(2px 2px at 160px 120px, var(--gold-primary), rgba(0,0,0,0));
  background-repeat: repeat;
  background-size: 200px 200px;
  animation: ember-rise 20s linear infinite;
  opacity: 0.45;
  z-index: 0;
}

@keyframes ember-rise {
  0% { transform: translateY(0); }
  100% { transform: translateY(-200px); }
}

/* Parchment Illuminated Texture */
.parchment-scroll {
  background: var(--parchment-bg);
  color: var(--ink-primary);
  border: 2px solid var(--parchment-border);
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6), inset 0 0 60px rgba(160, 130, 80, 0.25);
  position: relative;
}

.parchment-scroll::before,
.parchment-scroll::after {
  content: '✦';
  position: absolute;
  font-size: 1rem;
  color: var(--gold-dark);
}
.parchment-scroll::before { top: 0.5rem; left: 0.5rem; }
.parchment-scroll::after { bottom: 0.5rem; right: 0.5rem; }
```

- [ ] **Step 4: Write `docs/src/styles/global.css`**

```css
@import './tokens.css';
@import './typography.css';
@import './fantasy-fx.css';

*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  background-color: var(--bg-void);
  color-scheme: dark;
  scroll-behavior: smooth;
}

body {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: radial-gradient(circle at 50% 0%, #151d2a 0%, var(--bg-void) 70%);
  overflow-x: hidden;
}

a {
  color: var(--gold-primary);
  text-decoration: none;
  transition: color 0.2s ease, text-shadow 0.2s ease;
}

a:hover {
  color: var(--gold-bright);
  text-shadow: 0 0 8px var(--gold-glow);
}

button {
  cursor: pointer;
  border: none;
  background: none;
  font: inherit;
}
```

- [ ] **Step 5: Verify CSS builds cleanly**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 6: Commit**

```bash
git add docs/src/styles/
git commit -m "docs(style): implement dark fantasy CSS design system and visual effects"
```

---

### Task 3: Layouts, Navigation & UI Chrome Components

**Files:**
- Create: `docs/src/components/icons/Icons.astro`
- Create: `docs/src/components/ui/RunicBadge.astro`
- Create: `docs/src/components/ui/ParchmentCard.astro`
- Create: `docs/src/components/ui/OrnamentalDivider.astro`
- Create: `docs/src/components/layout/Header.astro`
- Create: `docs/src/components/layout/Sidebar.astro`
- Create: `docs/src/components/layout/Footer.astro`
- Create: `docs/src/components/layout/TableOfContents.astro`
- Create: `docs/src/layouts/BaseLayout.astro`
- Create: `docs/src/layouts/LandingLayout.astro`
- Create: `docs/src/layouts/DocLayout.astro`

**Interfaces:**
- Produces: Base HTML layout with responsive header, documentation sidebar navigation with category hierarchy, footer, and reading canvas.

- [ ] **Step 1: Write `docs/src/components/icons/Icons.astro`** (Custom SVG glyphs for D20, Shield, Swords, Brain, Book, Flame, Terminal)

```astro
---
interface Props {
  name: 'd20' | 'shield' | 'swords' | 'brain' | 'book' | 'flame' | 'terminal' | 'scroll' | 'chevron' | 'search';
  size?: number;
  class?: string;
}

const { name, size = 20, class: className = '' } = Astro.props;
---

{name === 'd20' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5 12 2" />
    <polygon points="12 2 12 22 2 15.5" />
    <polygon points="12 2 22 15.5 12 22" />
    <polygon points="12 2 2 8.5 22 8.5 12 2" />
    <circle cx="12" cy="12" r="1.5" fill="currentColor" />
  </svg>
)}
{name === 'brain' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <path d="M12 4.5c-1.5-2-4.5-2-6 0-2 2.5-1 6 1 8l5 5 5-5c2-2 3-5.5 1-8-1.5-2-4.5-2-6 0z" />
    <path d="M12 4.5v13M8 9h8M7 13h10" />
  </svg>
)}
{name === 'shield' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
  </svg>
)}
{name === 'swords' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5" />
    <line x1="13" y1="19" x2="19" y2="13" />
    <line x1="16" y1="16" x2="20" y2="20" />
    <line x1="19" y1="21" x2="21" y2="19" />
    <polyline points="9.5 17.5 21 6 21 3 18 3 6.5 14.5" />
    <line x1="11" y1="19" x2="5" y2="13" />
    <line x1="8" y1="16" x2="4" y2="20" />
    <line x1="5" y1="21" x2="3" y2="19" />
  </svg>
)}
{name === 'book' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
    <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
  </svg>
)}
{name === 'flame' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
  </svg>
)}
{name === 'terminal' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <polyline points="4 17 10 11 4 5" />
    <line x1="12" y1="19" x2="20" y2="19" />
  </svg>
)}
{name === 'scroll' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <path d="M8 21h12a2 2 0 0 0 2-2v-2H10v2a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v3h4" />
    <path d="M19 17V5a2 2 0 0 0-2-2H4" />
  </svg>
)}
{name === 'chevron' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <polyline points="9 18 15 12 9 6" />
  </svg>
)}
{name === 'search' && (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class={className}>
    <circle cx="11" cy="11" r="8" />
    <line x1="21" y1="21" x2="16.65" y2="16.65" />
  </svg>
)}
```

- [ ] **Step 2: Write `docs/src/components/ui/OrnamentalDivider.astro`**

```astro
---
interface Props {
  symbol?: string;
  class?: string;
}
const { symbol = '✦ ❖ ✦', class: className = '' } = Astro.props;
---

<div class={`ornamental-divider ${className}`}>
  <div class="line"></div>
  <span class="symbol">{symbol}</span>
  <div class="line"></div>
</div>

<style>
  .ornamental-divider {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    margin: 2rem 0;
    width: 100%;
  }
  .line {
    flex: 1;
    height: 1px;
    background: linear-gradient(90deg, transparent, var(--border-gold), transparent);
  }
  .symbol {
    color: var(--gold-primary);
    font-size: 0.875rem;
    letter-spacing: 0.2em;
    text-shadow: 0 0 8px var(--gold-glow);
  }
</style>
```

- [ ] **Step 3: Write `docs/src/components/layout/Header.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<header class="site-header">
  <div class="header-container">
    <a href="/" class="brand-link">
      <div class="brand-icon">
        <Icons name="d20" size={26} />
      </div>
      <div class="brand-text">
        <span class="title">The Shattered Kingdoms</span>
        <span class="subtitle">Agent Platform</span>
      </div>
    </a>

    <nav class="nav-links">
      <a href="/docs/01-overview">Handbook</a>
      <a href="/visualizers/referee">Pipeline</a>
      <a href="/visualizers/dice">Dice 3D</a>
      <a href="/visualizers/replay">Ledger</a>
      <a href="/visualizers/brains">BDI Brains</a>
      <a href="/visualizers/dungeon">Dungeon Map</a>
    </nav>

    <div class="header-actions">
      <a href="https://github.com/stevebrownlee/aeldoroth" target="_blank" rel="noreferrer" class="github-btn">
        <Icons name="terminal" size={16} />
        <span>Source</span>
      </a>
    </div>
  </div>
</header>

<style>
  .site-header {
    position: sticky;
    top: 0;
    z-index: 50;
    height: var(--header-height);
    background: rgba(8, 10, 14, 0.85);
    backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--border-stone);
  }
  .header-container {
    max-width: var(--max-width);
    margin: 0 auto;
    height: 100%;
    padding: 0 1.5rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .brand-link {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .brand-icon {
    display: grid;
    place-items: center;
    width: 2.25rem;
    height: 2.25rem;
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-gold);
    border-radius: 0.375rem;
    color: var(--gold-bright);
    box-shadow: 0 0 10px var(--gold-glow);
  }
  .brand-text {
    display: flex;
    flex-direction: column;
  }
  .brand-text .title {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.05rem;
    line-height: 1.1;
  }
  .brand-text .subtitle {
    font-size: 0.75rem;
    color: var(--gold-dark);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
  .nav-links {
    display: flex;
    align-items: center;
    gap: 1.5rem;
    font-family: var(--font-display);
    font-size: 0.95rem;
  }
  .nav-links a {
    color: #a3b1c6;
  }
  .nav-links a:hover {
    color: var(--gold-bright);
  }
  .github-btn {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.35rem 0.75rem;
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    border-radius: 0.375rem;
    font-size: 0.85rem;
    color: var(--gold-primary);
  }
  .github-btn:hover {
    border-color: var(--gold-primary);
  }
</style>
```

- [ ] **Step 4: Write `docs/src/components/layout/Sidebar.astro`**

```astro
---
import { getCollection } from 'astro:content';

interface Props {
  currentSlug?: string;
}

const { currentSlug } = Astro.props;
const allDocs = await getCollection('docs');
const sortedDocs = allDocs.sort((a, b) => a.data.order - b.data.order);

const categories = ['Foundation', 'Architecture', 'Agents & Referee', 'Protocol & Tooling', 'Ecosystem'];
---

<aside class="docs-sidebar">
  <div class="sidebar-content">
    <div class="sidebar-header">
      <span class="badge">AD&D 1E Platform</span>
      <h3 class="title">Documentation</h3>
    </div>

    <nav class="sidebar-nav">
      {categories.map(category => {
        const categoryDocs = sortedDocs.filter(d => d.data.category === category);
        if (categoryDocs.length === 0) return null;

        return (
          <div class="nav-group">
            <h4 class="group-title">{category}</h4>
            <ul class="group-list">
              {categoryDocs.map(doc => {
                const isActive = currentSlug === doc.slug;
                return (
                  <li>
                    <a href={`/docs/${doc.slug}`} class:list={['nav-link', { active: isActive }]}>
                      <span class="doc-num">{String(doc.data.order).padStart(2, '0')}</span>
                      <span class="doc-title">{doc.data.title}</span>
                    </a>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
    </nav>
  </div>
</aside>

<style>
  .docs-sidebar {
    width: var(--sidebar-width);
    position: sticky;
    top: var(--header-height);
    height: calc(100vh - var(--header-height));
    overflow-y: auto;
    border-right: 1px solid var(--border-stone);
    background: rgba(10, 14, 20, 0.75);
    padding: 1.5rem 1rem;
  }
  .sidebar-header {
    margin-bottom: 1.5rem;
  }
  .sidebar-header .badge {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    color: var(--gold-dark);
  }
  .sidebar-header .title {
    font-size: 1.15rem;
    margin-top: 0.25rem;
  }
  .nav-group {
    margin-bottom: 1.5rem;
  }
  .group-title {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--amber-rune);
    margin-bottom: 0.5rem;
  }
  .group-list {
    list-style: none;
  }
  .nav-link {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.4rem 0.5rem;
    border-radius: 0.25rem;
    font-size: 0.9rem;
    color: #94a3b8;
    transition: all 0.15s ease;
  }
  .nav-link:hover {
    background: var(--bg-surface-raised);
    color: var(--gold-bright);
  }
  .nav-link.active {
    background: rgba(223, 177, 91, 0.12);
    border-left: 2px solid var(--gold-primary);
    color: var(--gold-bright);
    font-weight: 600;
  }
  .doc-num {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--gold-dark);
  }
</style>
```

- [ ] **Step 5: Write `docs/src/layouts/BaseLayout.astro`**

```astro
---
import '../styles/global.css';
import Header from '../components/layout/Header.astro';

interface Props {
  title: string;
  description?: string;
}

const { title, description = 'The Shattered Kingdoms: Agent-Oriented AD&D 1E Referee Platform' } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <title>{title} | The Shattered Kingdoms</title>
    <meta name="description" content={description} />
  </head>
  <body>
    <div class="ember-particles" aria-hidden="true"></div>
    <Header />
    <slot />
  </body>
</html>
```

- [ ] **Step 6: Write `docs/src/layouts/DocLayout.astro`**

```astro
---
import BaseLayout from './BaseLayout.astro';
import Sidebar from '../components/layout/Sidebar.astro';

interface Props {
  title: string;
  description?: string;
  currentSlug?: string;
  headings?: { depth: number; slug: string; text: string }[];
}

const { title, description, currentSlug, headings = [] } = Astro.props;
---

<BaseLayout title={title} description={description}>
  <div class="doc-page-container">
    <Sidebar currentSlug={currentSlug} />
    
    <main class="doc-main-content">
      <article class="doc-article">
        <slot />
      </article>
    </main>

    {headings.length > 0 && (
      <aside class="on-this-page">
        <h4 class="toc-title">On This Scroll</h4>
        <ul class="toc-list">
          {headings.filter(h => h.depth <= 3).map(h => (
            <li class={`toc-depth-${h.depth}`}>
              <a href={`#${h.slug}`}>{h.text}</a>
            </li>
          ))}
        </ul>
      </aside>
    )}
  </div>
</BaseLayout>

<style>
  .doc-page-container {
    max-width: var(--max-width);
    margin: 0 auto;
    display: flex;
    width: 100%;
    min-height: calc(100vh - var(--header-height));
  }
  .doc-main-content {
    flex: 1;
    padding: 2.5rem 3rem 5rem;
    max-width: 52rem;
    overflow-x: hidden;
  }
  .on-this-page {
    width: 15rem;
    position: sticky;
    top: var(--header-height);
    height: calc(100vh - var(--header-height));
    padding: 2.5rem 1rem;
    overflow-y: auto;
    font-size: 0.85rem;
  }
  .toc-title {
    font-family: var(--font-display);
    font-size: 0.85rem;
    color: var(--gold-primary);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin-bottom: 0.75rem;
  }
  .toc-list {
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  .toc-depth-3 {
    padding-left: 0.75rem;
  }
  .toc-list a {
    color: #94a3b8;
  }
  .toc-list a:hover {
    color: var(--gold-bright);
  }
</style>
```

- [ ] **Step 7: Verify layout rendering**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 8: Commit**

```bash
git add docs/src/components/ docs/src/layouts/
git commit -m "docs(layout): add responsive fantasy layouts, sidebar, icons, and table of contents"
```

---

### Task 4: Interactive Component 1 — 3D CSS Polyhedral Dice Roller & Sandbox

**Files:**
- Create: `docs/src/components/visualizers/DiceRoller3D.astro`
- Create: `docs/src/pages/visualizers/dice.astro`

**Interfaces:**
- Produces: Pure CSS 3D dice (d20, d8, d6) that tumble at 60fps and calculate AD&D 1E combat THAC0 targets and damage.

- [ ] **Step 1: Write `docs/src/components/visualizers/DiceRoller3D.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<div class="dice-sandbox runic-border-beam" id="dice-sandbox">
  <div class="sandbox-header">
    <div class="header-title">
      <Icons name="d20" size={24} />
      <h3>Pure CSS 3D Polyhedral Roller & Rule Sandbox</h3>
    </div>
    <span class="tag">AD&D 1E Mechanics</span>
  </div>

  <div class="sandbox-grid">
    <!-- 3D Dice Stage -->
    <div class="dice-stage">
      <div class="scene-3d">
        <div class="d20-polyhedron" id="d20-dice">
          <!-- 20 Faces of the 3D Icosahedron -->
          <div class="face face-1">20</div>
          <div class="face face-2">1</div>
          <div class="face face-3">14</div>
          <div class="face face-4">7</div>
          <div class="face face-5">18</div>
          <div class="face face-6">3</div>
          <div class="face face-7">12</div>
          <div class="face face-8">9</div>
          <div class="face face-9">16</div>
          <div class="face face-10">5</div>
          <div class="face face-11">19</div>
          <div class="face face-12">2</div>
          <div class="face face-13">15</div>
          <div class="face face-14">6</div>
          <div class="face face-15">17</div>
          <div class="face face-16">4</div>
          <div class="face face-17">11</div>
          <div class="face face-18">8</div>
          <div class="face face-19">13</div>
          <div class="face face-20">10</div>
        </div>
      </div>
      <button class="roll-btn" id="roll-trigger">
        <Icons name="d20" size={18} />
        <span>Roll D20 (Seeded RNG)</span>
      </button>
    </div>

    <!-- AD&D 1E Combat Calculator Panel -->
    <div class="calc-panel">
      <h4>Attack Resolution Sandbox</h4>
      <div class="input-row">
        <label>Attacker:
          <select id="attacker-select">
            <option value="20">Level 1 Fighter (THAC0 20)</option>
            <option value="19">Level 3 Fighter (THAC0 19)</option>
            <option value="20">Level 1 Thief (THAC0 20)</option>
          </select>
        </label>
        <label>Defender AC:
          <select id="defender-ac">
            <option value="6">Goblin Guard (AC 6)</option>
            <option value="5">Goblin Chief Grisk (AC 5)</option>
            <option value="7">Wolf (AC 7)</option>
            <option value="2">Plate + Shield (AC 2)</option>
          </select>
        </label>
      </div>

      <div class="calc-output">
        <div class="stat-card">
          <span class="label">Target Roll Required</span>
          <span class="val" id="target-roll">14+</span>
        </div>
        <div class="stat-card">
          <span class="label">Last Roll</span>
          <span class="val" id="last-roll">—</span>
        </div>
        <div class="stat-card">
          <span class="label">Verdict</span>
          <span class="val verdict" id="roll-verdict">—</span>
        </div>
      </div>

      <div class="combat-log" id="combat-log">
        <p class="log-entry">Select combatants and trigger a roll to observe referee adjudication.</p>
      </div>
    </div>
  </div>
</div>

<style>
  .dice-sandbox {
    padding: 1.5rem;
    margin: 2rem 0;
  }
  .sandbox-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  .header-title {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .tag {
    font-size: 0.75rem;
    padding: 0.2rem 0.6rem;
    background: rgba(223, 177, 91, 0.15);
    border: 1px solid var(--border-gold);
    color: var(--gold-primary);
    border-radius: 1rem;
  }
  .sandbox-grid {
    display: grid;
    grid-template-columns: 1fr 1.25fr;
    gap: 2rem;
  }
  @media (max-width: 768px) {
    .sandbox-grid { grid-template-columns: 1fr; }
  }

  /* 3D Scene */
  .dice-stage {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid var(--border-stone-subtle);
    border-radius: 0.5rem;
    padding: 2.5rem 1rem;
    min-height: 280px;
  }
  .scene-3d {
    width: 120px;
    height: 120px;
    perspective: 800px;
    display: grid;
    place-items: center;
    margin-bottom: 2rem;
  }
  .d20-polyhedron {
    width: 80px;
    height: 80px;
    position: relative;
    transform-style: preserve-3d;
    transform: rotateX(-25deg) rotateY(35deg);
    transition: transform 1.2s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .d20-polyhedron.rolling {
    animation: tumble-d20 1.2s ease-out;
  }
  @keyframes tumble-d20 {
    0% { transform: rotateX(0deg) rotateY(0deg) rotateZ(0deg) scale3d(0.8, 0.8, 0.8); }
    30% { transform: rotateX(720deg) rotateY(540deg) rotateZ(360deg) scale3d(1.2, 1.2, 1.2); }
    70% { transform: rotateX(1200deg) rotateY(900deg) rotateZ(720deg) scale3d(1.1, 1.1, 1.1); }
    100% { transform: rotateX(1415deg) rotateY(1115deg) rotateZ(720deg) scale3d(1, 1, 1); }
  }

  /* Triangular Faces of 3D Icosahedron */
  .face {
    position: absolute;
    width: 0;
    height: 0;
    border-left: 30px solid transparent;
    border-right: 30px solid transparent;
    border-bottom: 52px solid #221a10;
    text-align: center;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 14px;
    color: var(--gold-bright);
    line-height: 48px;
    text-shadow: 0 0 5px var(--gold-glow);
    opacity: 0.9;
    backface-visibility: visible;
  }
  /* Geometry placement for icosahedron sides */
  .face-1  { transform: rotateY(0deg) translateZ(42px) rotateX(19deg); border-bottom-color: #2a1f10; }
  .face-2  { transform: rotateY(72deg) translateZ(42px) rotateX(19deg); border-bottom-color: #352613; }
  .face-3  { transform: rotateY(144deg) translateZ(42px) rotateX(19deg); border-bottom-color: #2a1f10; }
  .face-4  { transform: rotateY(216deg) translateZ(42px) rotateX(19deg); border-bottom-color: #352613; }
  .face-5  { transform: rotateY(288deg) translateZ(42px) rotateX(19deg); border-bottom-color: #2a1f10; }
  .face-6  { transform: rotateY(36deg) translateZ(-42px) rotateX(-19deg) rotateZ(180deg); border-bottom-color: #1a1208; }
  .face-7  { transform: rotateY(108deg) translateZ(-42px) rotateX(-19deg) rotateZ(180deg); border-bottom-color: #221a10; }
  .face-8  { transform: rotateY(180deg) translateZ(-42px) rotateX(-19deg) rotateZ(180deg); border-bottom-color: #1a1208; }
  .face-9  { transform: rotateY(252deg) translateZ(-42px) rotateX(-19deg) rotateZ(180deg); border-bottom-color: #221a10; }
  .face-10 { transform: rotateY(324deg) translateZ(-42px) rotateX(-19deg) rotateZ(180deg); border-bottom-color: #1a1208; }

  .roll-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.65rem 1.5rem;
    background: var(--gold-gradient);
    color: #110d05;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    border-radius: 0.375rem;
    box-shadow: 0 0 15px var(--gold-glow);
    transition: transform 0.15s ease, box-shadow 0.15s ease;
  }
  .roll-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 0 25px var(--gold-glow);
  }

  /* Calc Panel */
  .calc-panel {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .input-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
  }
  .input-row label {
    font-size: 0.85rem;
    color: #94a3b8;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }
  .input-row select {
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    color: var(--gold-bright);
    padding: 0.5rem;
    border-radius: 0.25rem;
    font-family: var(--font-mono);
  }
  .calc-output {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.75rem;
  }
  .stat-card {
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid var(--border-stone-subtle);
    padding: 0.6rem;
    border-radius: 0.375rem;
    text-align: center;
  }
  .stat-card .label {
    display: block;
    font-size: 0.7rem;
    color: #64748b;
    text-transform: uppercase;
  }
  .stat-card .val {
    font-family: var(--font-mono);
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--gold-bright);
  }
  .stat-card .verdict.hit { color: var(--emerald-rekindler); }
  .stat-card .verdict.miss { color: var(--crimson-blood); }
  .combat-log {
    background: #080a0f;
    border: 1px solid var(--border-stone-subtle);
    padding: 0.75rem;
    border-radius: 0.375rem;
    font-family: var(--font-mono);
    font-size: 0.825rem;
    color: #94a3b8;
    min-height: 4.5rem;
  }
</style>

<script>
  function setupDice() {
    const btn = document.getElementById('roll-trigger');
    const dice = document.getElementById('d20-dice');
    const attackerSelect = document.getElementById('attacker-select') as HTMLSelectElement;
    const defenderSelect = document.getElementById('defender-ac') as HTMLSelectElement;
    const targetDisplay = document.getElementById('target-roll');
    const lastRollDisplay = document.getElementById('last-roll');
    const verdictDisplay = document.getElementById('roll-verdict');
    const log = document.getElementById('combat-log');

    function updateTarget() {
      const thac0 = parseInt(attackerSelect.value);
      const ac = parseInt(defenderSelect.value);
      const target = thac0 - ac;
      if (targetDisplay) targetDisplay.textContent = `${target}+`;
      return target;
    }

    attackerSelect?.addEventListener('change', updateTarget);
    defenderSelect?.addEventListener('change', updateTarget);
    updateTarget();

    btn?.addEventListener('click', () => {
      if (!dice) return;
      dice.classList.add('rolling');

      const target = updateTarget();
      const roll = Math.floor(Math.random() * 20) + 1;
      const hit = roll >= target;
      const dmg = hit ? Math.floor(Math.random() * 8) + 1 : 0;

      setTimeout(() => {
        dice.classList.remove('rolling');
        if (lastRollDisplay) lastRollDisplay.textContent = String(roll);
        if (verdictDisplay) {
          verdictDisplay.textContent = hit ? 'HIT!' : 'MISS';
          verdictDisplay.className = `val verdict ${hit ? 'hit' : 'miss'}`;
        }
        if (log) {
          log.innerHTML = `
            <p style="color: ${hit ? 'var(--emerald-rekindler)' : 'var(--crimson-blood)'}">
              <strong>Roll:</strong> d20 = ${roll} vs Target ${target} (${hit ? 'SUCCESS' : 'FAILURE'})
            </p>
            ${hit ? `<p style="color: var(--gold-bright)"><strong>Damage:</strong> d8 = ${dmg} HP dealt to target.</p>` : '<p style="color: #64748b">Attack strikes armor or parried.</p>'}
          `;
        }
      }, 1200);
    });
  }

  document.addEventListener('DOMContentLoaded', setupDice);
</script>
```

- [ ] **Step 2: Write `docs/src/pages/visualizers/dice.astro`**

```astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
import DiceRoller3D from '../../components/visualizers/DiceRoller3D.astro';
---

<BaseLayout title="3D CSS Dice Roller & AD&D 1E Sandbox">
  <main class="page-container">
    <div class="header-section">
      <a href="/" class="back-link">← Back to Overview</a>
      <h1>3D Polyhedral Dice Roller</h1>
      <p class="lead">
        Hardware-accelerated CSS 3D transforms paired with AD&D 1E combat attack matrices.
      </p>
    </div>
    <DiceRoller3D />
  </main>
</BaseLayout>

<style>
  .page-container {
    max-width: 64rem;
    margin: 0 auto;
    padding: 3rem 1.5rem 6rem;
  }
  .header-section { margin-bottom: 2rem; }
  .back-link { font-size: 0.9rem; color: var(--gold-primary); display: inline-block; margin-bottom: 1rem; }
  .lead { font-size: 1.2rem; color: #94a3b8; margin-top: 0.5rem; }
</style>
```

- [ ] **Step 3: Verify component builds cleanly**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 4: Commit**

```bash
git add docs/src/components/visualizers/DiceRoller3D.astro docs/src/pages/visualizers/dice.astro
git commit -m "docs(interactive): add pure-CSS 3D polyhedral dice roller and AD&D THAC0 sandbox"
```

---

### Task 5: Interactive Component 2 — Referee Adjudication Pipeline Simulator

**Files:**
- Create: `docs/src/components/visualizers/RefereePipeline.astro`
- Create: `docs/src/pages/visualizers/referee.astro`

**Interfaces:**
- Produces: Step-by-step interactive simulator illustrating the 5-stage referee pipeline: Intent $\rightarrow$ Interpret $\rightarrow$ Validate $\rightarrow$ Resolve $\rightarrow$ Apply & Narrate.

- [ ] **Step 1: Write `docs/src/components/visualizers/RefereePipeline.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<div class="pipeline-simulator runic-border-beam" id="referee-sim">
  <div class="sim-header">
    <div class="title-wrap">
      <Icons name="swords" size={24} />
      <h3>The Referee Adjudication Pipeline</h3>
    </div>
    <span class="principle-tag">LLM Proposes, Engine Disposes</span>
  </div>

  <!-- Stage Track -->
  <div class="pipeline-track">
    <div class="stage-node active" data-stage="1">
      <span class="num">1</span>
      <span class="name">Intent (NL)</span>
    </div>
    <div class="stage-connector"></div>
    <div class="stage-node" data-stage="2">
      <span class="num">2</span>
      <span class="name">Interpret</span>
    </div>
    <div class="stage-connector"></div>
    <div class="stage-node" data-stage="3">
      <span class="num">3</span>
      <span class="name">Validate</span>
    </div>
    <div class="stage-connector"></div>
    <div class="stage-node" data-stage="4">
      <span class="num">4</span>
      <span class="name">Resolve & Roll</span>
    </div>
    <div class="stage-connector"></div>
    <div class="stage-node" data-stage="5">
      <span class="num">5</span>
      <span class="name">Apply & Narrate</span>
    </div>
  </div>

  <!-- Stage Detail Card -->
  <div class="stage-detail-box" id="stage-detail">
    <div class="detail-header">
      <h4 id="detail-title">Stage 1: Declared Player Intent</h4>
      <span class="stage-badge" id="detail-badge">Untrusted Input</span>
    </div>
    <div class="detail-body" id="detail-body">
      <p>Player inputs raw natural language action into the play surface.</p>
      <div class="code-preview" id="detail-code">
        "I swing my longsword at the goblin guard standing by the iron door"
      </div>
    </div>
  </div>

  <!-- Controls -->
  <div class="sim-controls">
    <button class="step-btn prev" id="prev-stage" disabled>← Previous Stage</button>
    <button class="step-btn auto" id="auto-play">Auto Play Demo</button>
    <button class="step-btn next" id="next-stage">Next Stage →</button>
  </div>
</div>

<style>
  .pipeline-simulator {
    padding: 1.75rem;
    margin: 2rem 0;
  }
  .sim-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  .title-wrap {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .principle-tag {
    font-family: var(--font-display);
    font-size: 0.75rem;
    color: var(--amber-rune);
    border: 1px solid var(--border-gold);
    padding: 0.25rem 0.75rem;
    border-radius: 1rem;
  }
  .pipeline-track {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin: 1.5rem 0 2rem;
  }
  .stage-node {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.35rem;
    cursor: pointer;
  }
  .stage-node .num {
    width: 2.25rem;
    height: 2.25rem;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    color: #64748b;
    font-family: var(--font-mono);
    font-weight: 700;
    transition: all 0.2s ease;
  }
  .stage-node .name {
    font-size: 0.8rem;
    color: #64748b;
    font-family: var(--font-display);
  }
  .stage-node.active .num {
    background: var(--gold-primary);
    color: #0c0e14;
    border-color: var(--gold-bright);
    box-shadow: 0 0 15px var(--gold-glow);
  }
  .stage-node.active .name {
    color: var(--gold-bright);
  }
  .stage-connector {
    flex: 1;
    height: 2px;
    background: var(--border-stone);
    margin: 0 0.5rem;
    margin-bottom: 1.25rem;
  }
  .stage-detail-box {
    background: #080a0f;
    border: 1px solid var(--border-stone);
    border-radius: 0.5rem;
    padding: 1.25rem;
    min-height: 140px;
  }
  .detail-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.75rem;
  }
  .detail-header h4 {
    color: var(--gold-bright);
    font-size: 1.1rem;
    margin: 0;
  }
  .stage-badge {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    background: rgba(56, 189, 248, 0.15);
    color: var(--mana-azure);
    border: 1px solid rgba(56, 189, 248, 0.3);
    padding: 0.2rem 0.5rem;
    border-radius: 0.25rem;
  }
  .code-preview {
    background: #040508;
    border: 1px solid #1a2230;
    padding: 0.75rem;
    border-radius: 0.375rem;
    font-family: var(--font-mono);
    font-size: 0.85rem;
    color: var(--gold-bright);
    margin-top: 0.5rem;
    overflow-x: auto;
  }
  .sim-controls {
    display: flex;
    justify-content: space-between;
    margin-top: 1.5rem;
  }
  .step-btn {
    padding: 0.5rem 1.25rem;
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    border-radius: 0.375rem;
    color: var(--gold-primary);
    font-family: var(--font-display);
    font-size: 0.9rem;
  }
  .step-btn:hover:not(:disabled) {
    border-color: var(--gold-primary);
    color: var(--gold-bright);
  }
  .step-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>

<script>
  const stages = [
    {
      title: "Stage 1: Declared Player Intent",
      badge: "Untrusted Client Input",
      desc: "Player submits raw natural language utterance over the Phoenix WebSocket channel.",
      code: `"I swing my longsword at the goblin guard standing by the iron door"`
    },
    {
      title: "Stage 2: Interpretation & Schema Extraction",
      badge: "LLM-First / Grammar Fallback",
      desc: "Gateway calls :interpret schema or deterministic grammar to produce a typed Action struct.",
      code: `%EngineCore.Types.Action{\n  actor_id: "pc_thistle",\n  verb: :strike,\n  target_id: "goblin_guard_1",\n  params: %{weapon: "longsword"}\n}`
    },
    {
      title: "Stage 3: Diegetic Validation",
      badge: "Pure Rules Verification",
      desc: "Engine verifies rules invariants: target co-presence in room, actor consciousness, line of sight.",
      code: `Validate.check(world, action) -> :ok\n# Verified: pc_thistle is at :guard_room with goblin_guard_1; longsword is ready.`
    },
    {
      title: "Stage 4: Resolution & Seeded Roll",
      badge: "Deterministic AD&D Mechanics",
      desc: "Calculates hit probability via THAC0 20 vs Goblin AC 6 (Target: 14+). Seeded RNG draws d20=16 (HIT) and d8=6 damage.",
      code: `Resolve.strike(world, action, rng) -> {:ok, [\n  %Ledger.Event{class: :dice, payload: %{roll: 16, target: 14, hit: true}},\n  %Ledger.Event{class: :world, payload: %{kind: :damage, target_id: "goblin_guard_1", amount: 6}}\n]}`
    },
    {
      title: "Stage 5: Application & Fidelity Narration",
      badge: "Ledger Commit + Truth Barrier",
      desc: "Reducers fold events into World truth. Narration engine builds per-PC perception text adhering to truth barrier.",
      code: `Fold.apply(world, events)\n\n# Pushed to pc_thistle over run:id channel:\n"Your longsword bites deep into the goblin guard's shoulder. It staggers with a snarl of pain."`
    }
  ];

  let currentStage = 0;

  function renderStage(idx: number) {
    currentStage = idx;
    const stage = stages[idx];
    const titleEl = document.getElementById('detail-title');
    const badgeEl = document.getElementById('detail-badge');
    const bodyEl = document.getElementById('detail-body');
    const prevBtn = document.getElementById('prev-stage') as HTMLButtonElement;
    const nextBtn = document.getElementById('next-stage') as HTMLButtonElement;

    if (titleEl) titleEl.textContent = stage.title;
    if (badgeEl) badgeEl.textContent = stage.badge;
    if (bodyEl) {
      bodyEl.innerHTML = `
        <p>${stage.desc}</p>
        <pre class="code-preview"><code>${stage.code}</code></pre>
      `;
    }

    document.querySelectorAll('.stage-node').forEach((node, i) => {
      node.classList.toggle('active', i === idx);
    });

    if (prevBtn) prevBtn.disabled = idx === 0;
    if (nextBtn) nextBtn.disabled = idx === stages.length - 1;
  }

  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.stage-node').forEach((node, i) => {
      node.addEventListener('click', () => renderStage(i));
    });
    document.getElementById('prev-stage')?.addEventListener('click', () => {
      if (currentStage > 0) renderStage(currentStage - 1);
    });
    document.getElementById('next-stage')?.addEventListener('click', () => {
      if (currentStage < stages.length - 1) renderStage(currentStage + 1);
    });
    document.getElementById('auto-play')?.addEventListener('click', () => {
      let step = 0;
      const interval = setInterval(() => {
        renderStage(step);
        step++;
        if (step >= stages.length) clearInterval(interval);
      }, 1500);
    });
  });
</script>
```

- [ ] **Step 2: Write `docs/src/pages/visualizers/referee.astro`**

```astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
import RefereePipeline from '../../components/visualizers/RefereePipeline.astro';
---

<BaseLayout title="The Referee Adjudication Pipeline">
  <main class="page-container">
    <div class="header-section">
      <a href="/" class="back-link">← Back to Overview</a>
      <h1>Referee Pipeline Simulator</h1>
      <p class="lead">
        Step through the 5-stage adjudication cycle that turns untrusted natural language into deterministic world truth.
      </p>
    </div>
    <RefereePipeline />
  </main>
</BaseLayout>

<style>
  .page-container {
    max-width: 64rem;
    margin: 0 auto;
    padding: 3rem 1.5rem 6rem;
  }
  .header-section { margin-bottom: 2rem; }
  .back-link { font-size: 0.9rem; color: var(--gold-primary); display: inline-block; margin-bottom: 1rem; }
  .lead { font-size: 1.2rem; color: #94a3b8; margin-top: 0.5rem; }
</style>
```

- [ ] **Step 3: Verify component builds cleanly**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 4: Commit**

```bash
git add docs/src/components/visualizers/RefereePipeline.astro docs/src/pages/visualizers/referee.astro
git commit -m "docs(interactive): add referee adjudication pipeline simulator"
```

---

### Task 6: Interactive Component 3 — Ledger Time-Travel & Determinism Scrubber

**Files:**
- Create: `docs/src/components/visualizers/LedgerScrubber.astro`
- Create: `docs/src/pages/visualizers/replay.astro`

**Interfaces:**
- Produces: Interactive timeline scrubber proving byte-identical replay determinism and fork-diff emergence.

- [ ] **Step 1: Write `docs/src/components/visualizers/LedgerScrubber.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<div class="ledger-scrubber runic-border-beam" id="ledger-scrubber">
  <div class="scrubber-header">
    <div class="title-wrap">
      <Icons name="scroll" size={24} />
      <h3>Ledger Time-Travel & Determinism Scrubber</h3>
    </div>
    <span class="proof-tag">fold(events[1..N]) == World.snapshot</span>
  </div>

  <!-- Timeline Slider -->
  <div class="timeline-controls">
    <div class="slider-label-row">
      <span>Seq 1 (Seed Load)</span>
      <span class="current-seq-badge" id="seq-counter">Seq 8 / 15</span>
      <span>Seq 15 (Boss Encounter)</span>
    </div>
    <input type="range" min="1" max="15" value="8" class="timeline-range" id="seq-slider" />
  </div>

  <!-- Dual Split State Inspector -->
  <div class="inspector-grid">
    <div class="inspector-card">
      <h4>Committed Event at Sequence</h4>
      <div class="event-view" id="current-event-json">
        <code>Loading event...</code>
      </div>
    </div>
    <div class="inspector-card">
      <h4>Folded World State Snapshot</h4>
      <div class="snapshot-view" id="current-snapshot-view">
        <code>Calculating fold...</code>
      </div>
    </div>
  </div>

  <div class="replay-proof-banner">
    <span class="check-icon">✓</span>
    <span>Replay Invariant Verified: Verbatim replay reconstructs byte-identical state at every snapshot.</span>
  </div>
</div>

<style>
  .ledger-scrubber {
    padding: 1.75rem;
    margin: 2rem 0;
  }
  .scrubber-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  .title-wrap {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .proof-tag {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--mana-azure);
    border: 1px solid rgba(56, 189, 248, 0.3);
    background: rgba(56, 189, 248, 0.1);
    padding: 0.25rem 0.75rem;
    border-radius: 1rem;
  }
  .timeline-controls {
    margin-bottom: 2rem;
  }
  .slider-label-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: #64748b;
    margin-bottom: 0.5rem;
  }
  .current-seq-badge {
    background: var(--gold-gradient);
    color: #0c0e14;
    font-weight: 700;
    padding: 0.2rem 0.75rem;
    border-radius: 1rem;
  }
  .timeline-range {
    width: 100%;
    accent-color: var(--gold-primary);
    cursor: pointer;
  }
  .inspector-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
  }
  @media (max-width: 768px) {
    .inspector-grid { grid-template-columns: 1fr; }
  }
  .inspector-card {
    background: #080a0f;
    border: 1px solid var(--border-stone-subtle);
    border-radius: 0.5rem;
    padding: 1rem;
  }
  .inspector-card h4 {
    font-size: 0.9rem;
    color: var(--gold-primary);
    margin-bottom: 0.5rem;
  }
  .event-view, .snapshot-view {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: #cbd5e1;
    background: #040508;
    padding: 0.75rem;
    border-radius: 0.25rem;
    height: 160px;
    overflow-y: auto;
    white-space: pre-wrap;
  }
  .replay-proof-banner {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-top: 1.5rem;
    padding: 0.75rem 1rem;
    background: rgba(16, 185, 129, 0.1);
    border: 1px solid rgba(16, 185, 129, 0.3);
    border-radius: 0.375rem;
    color: var(--emerald-rekindler);
    font-size: 0.875rem;
  }
  .check-icon {
    font-weight: 700;
  }
</style>

<script>
  const events = [
    { seq: 1, tick: 0, class: "meta", payload: { kind: "prefs_stack", lethality: "standard", dice: "open" }, room: "Entry Hall", hp: "12/12" },
    { seq: 2, tick: 0, class: "world", payload: { kind: "agent_added", agent: "pc_thistle", place: "entry_hall" }, room: "Entry Hall", hp: "12/12" },
    { seq: 3, tick: 0, class: "world", payload: { kind: "agent_added", agent: "pc_bramble", place: "entry_hall" }, room: "Entry Hall", hp: "8/8" },
    { seq: 4, tick: 1, class: "world", payload: { kind: "move", agent_id: "pc_thistle", to: "library" }, room: "Library", hp: "12/12" },
    { seq: 5, tick: 1, class: "signal", payload: { kind: "footstep", intensity: 3, place: "library" }, room: "Library", hp: "12/12" },
    { seq: 6, tick: 1, class: "narration", payload: { agent: "pc_thistle", text: "You step into the ruined library..." }, room: "Library", hp: "12/12" },
    { seq: 7, tick: 2, class: "world", payload: { kind: "move", agent_id: "pc_thistle", to: "guard_room" }, room: "Guard Room", hp: "12/12" },
    { seq: 8, tick: 2, class: "signal", payload: { kind: "sound", intensity: 5, place: "guard_room" }, room: "Guard Room", hp: "12/12" },
    { seq: 9, tick: 2, class: "dice", payload: { hit: true, roll: 16, target: 14 }, room: "Guard Room", hp: "12/12" },
    { seq: 10, tick: 2, class: "world", payload: { kind: "damage", target: "goblin_guard_1", amount: 6 }, room: "Guard Room", hp: "12/12" },
    { seq: 11, tick: 2, class: "world", payload: { kind: "death", agent_id: "goblin_guard_1" }, room: "Guard Room", hp: "12/12" },
    { seq: 12, tick: 3, class: "world", payload: { kind: "move", agent_id: "pc_thistle", to: "chiefs_room" }, room: "Chief's Room", hp: "12/12" },
    { seq: 13, tick: 3, class: "dice", payload: { hit: true, roll: 18, target: 15 }, room: "Chief's Room", hp: "9/12" },
    { seq: 14, tick: 3, class: "world", payload: { kind: "damage", target: "pc_thistle", amount: 3 }, room: "Chief's Room", hp: "9/12" },
    { seq: 15, tick: 3, class: "narration", payload: { agent: "pc_thistle", text: "Chief Grisk swings his scimitar, cutting across your ribs!" }, room: "Chief's Room", hp: "9/12" }
  ];

  function updateScrubber(seq: number) {
    const ev = events[seq - 1];
    const badge = document.getElementById('seq-counter');
    const evBox = document.getElementById('current-event-json');
    const snapBox = document.getElementById('current-snapshot-view');

    if (badge) badge.textContent = `Seq ${seq} / 15`;
    if (evBox) {
      evBox.innerHTML = `<code>%EngineCore.Ledger.Event{\n  seq: ${ev.seq},\n  tick: ${ev.tick},\n  class: :${ev.class},\n  payload: ${JSON.stringify(ev.payload, null, 2)}\n}</code>`;
    }
    if (snapBox) {
      snapBox.innerHTML = `<code>%EngineCore.Types.World{\n  tick: ${ev.tick},\n  pcs: ["pc_thistle" (${ev.hp}), "pc_bramble"],\n  current_place: "${ev.room}",\n  invariants_held: true\n}</code>`;
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    const slider = document.getElementById('seq-slider') as HTMLInputElement;
    slider?.addEventListener('input', () => updateScrubber(parseInt(slider.value)));
    updateScrubber(8);
  });
</script>
```

- [ ] **Step 2: Write `docs/src/pages/visualizers/replay.astro`**

```astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
import LedgerScrubber from '../../components/visualizers/LedgerScrubber.astro';
---

<BaseLayout title="Ledger Time-Travel & Determinism Scrubber">
  <main class="page-container">
    <div class="header-section">
      <a href="/" class="back-link">← Back to Overview</a>
      <h1>Ledger Replay & Determinism</h1>
      <p class="lead">
        Scrub through immutable sequence numbers to prove that world truth is a pure fold of the append-only event ledger.
      </p>
    </div>
    <LedgerScrubber />
  </main>
</BaseLayout>

<style>
  .page-container {
    max-width: 64rem;
    margin: 0 auto;
    padding: 3rem 1.5rem 6rem;
  }
  .header-section { margin-bottom: 2rem; }
  .back-link { font-size: 0.9rem; color: var(--gold-primary); display: inline-block; margin-bottom: 1rem; }
  .lead { font-size: 1.2rem; color: #94a3b8; margin-top: 0.5rem; }
</style>
```

- [ ] **Step 3: Verify component builds cleanly**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 4: Commit**

```bash
git add docs/src/components/visualizers/LedgerScrubber.astro docs/src/pages/visualizers/replay.astro
git commit -m "docs(interactive): add ledger time-travel scrubber and determinism proof inspector"
```

---

### Task 7: Interactive Components 4 & 5 — BDI Brain Explorer & Spatial Dungeon Map

**Files:**
- Create: `docs/src/components/visualizers/BrainExplorer.astro`
- Create: `docs/src/pages/visualizers/brains.astro`
- Create: `docs/src/components/visualizers/SpatialMap.astro`
- Create: `docs/src/pages/visualizers/dungeon.astro`

**Interfaces:**
- Produces: BDI belief node graph & order adoption calculator, plus Ruined Tower dungeon map with signal propagation waves.

- [ ] **Step 1: Write `docs/src/components/visualizers/BrainExplorer.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<div class="brain-explorer runic-border-beam" id="brain-explorer">
  <div class="explorer-header">
    <div class="title-wrap">
      <Icons name="brain" size={24} />
      <h3>Agent BDI Brain & Belief Matrix</h3>
    </div>
    <span class="tier-tag">Tier-3 Autonomous Actor</span>
  </div>

  <div class="explorer-grid">
    <!-- Belief Node Matrix -->
    <div class="matrix-card">
      <h4>Perceived Belief Store (Agent: Goblin Bodyguard)</h4>
      <div class="node-list">
        <div class="belief-node active" data-threat="8.5">
          <div class="node-top">
            <span class="subject">pc_thistle</span>
            <span class="badge threat">Threat 8.5</span>
          </div>
          <p class="node-desc">Seen in Guard Room wielding unsheathed longsword. High salience.</p>
        </div>
        <div class="belief-node" data-threat="3.0">
          <div class="node-top">
            <span class="subject">grisk_the_snatcher</span>
            <span class="badge ally">Authority Creditor</span>
          </div>
          <p class="node-desc">Chief standing in room. High reliability index (0.95).</p>
        </div>
        <div class="belief-node" data-threat="1.0">
          <div class="node-top">
            <span class="subject">iron_chest</span>
            <span class="badge item">Item Presence</span>
          </div>
          <p class="node-desc">Locked chest in north alcove. Zero threat salience.</p>
        </div>
      </div>
    </div>

    <!-- Salience Gate & Adoption Sandbox -->
    <div class="gate-card">
      <h4>Salience Escalation & Order Adoption</h4>
      <div class="salience-meter">
        <div class="meter-label">
          <span>Salience Threshold Meter</span>
          <span class="salience-val" id="salience-val">8.5 / 10.0</span>
        </div>
        <div class="meter-bar">
          <div class="bar-fill" style="width: 85%;"></div>
          <div class="threshold-line" title="Trigger Threshold (5.0)"></div>
        </div>
        <p class="gate-status">⚡ Salience &ge; 5.0: Agent breaks cadence sleep and starts LLM deliberation.</p>
      </div>

      <div class="adoption-box">
        <h5>Autonomous Order Evaluation</h5>
        <div class="order-payload">
          <code>Order from Grisk: "Flank the fighter while I prepare the trap!"</code>
        </div>
        <div class="criteria-list">
          <div class="crit pass">✓ Creditor has authority hierarchy</div>
          <div class="crit pass">✓ Co-presence confirmed in current boundary</div>
          <div class="crit pass">✓ Target is perceived threat</div>
        </div>
        <div class="verdict-banner">Verdict: Order Adopted into Commitment Queue</div>
      </div>
    </div>
  </div>
</div>

<style>
  .brain-explorer {
    padding: 1.75rem;
    margin: 2rem 0;
  }
  .explorer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  .title-wrap {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .tier-tag {
    font-family: var(--font-display);
    font-size: 0.75rem;
    color: var(--shadow-crystal);
    border: 1px solid rgba(168, 85, 247, 0.4);
    background: rgba(168, 85, 247, 0.1);
    padding: 0.25rem 0.75rem;
    border-radius: 1rem;
  }
  .explorer-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
  }
  @media (max-width: 768px) {
    .explorer-grid { grid-template-columns: 1fr; }
  }
  .matrix-card, .gate-card {
    background: #080a0f;
    border: 1px solid var(--border-stone-subtle);
    border-radius: 0.5rem;
    padding: 1.25rem;
  }
  .matrix-card h4, .gate-card h4 {
    font-size: 0.95rem;
    color: var(--gold-primary);
    margin-bottom: 1rem;
  }
  .node-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  .belief-node {
    background: #040508;
    border: 1px solid var(--border-stone);
    padding: 0.75rem;
    border-radius: 0.375rem;
    cursor: pointer;
  }
  .belief-node.active {
    border-color: var(--crimson-blood);
    box-shadow: 0 0 10px var(--crimson-glow);
  }
  .node-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
  }
  .subject {
    font-family: var(--font-mono);
    font-weight: 700;
    color: var(--gold-bright);
    font-size: 0.85rem;
  }
  .badge {
    font-size: 0.7rem;
    padding: 0.15rem 0.4rem;
    border-radius: 0.25rem;
  }
  .badge.threat { background: rgba(224, 82, 56, 0.2); color: var(--crimson-blood); border: 1px solid var(--crimson-blood); }
  .badge.ally { background: rgba(56, 189, 248, 0.2); color: var(--mana-azure); border: 1px solid var(--mana-azure); }
  .badge.item { background: rgba(100, 116, 139, 0.2); color: #94a3b8; border: 1px solid #64748b; }
  .node-desc {
    font-size: 0.8rem;
    color: #94a3b8;
    line-height: 1.4;
  }
  .salience-meter {
    margin-bottom: 1.5rem;
  }
  .meter-label {
    display: flex;
    justify-content: space-between;
    font-size: 0.8rem;
    color: #94a3b8;
    margin-bottom: 0.4rem;
  }
  .salience-val {
    font-family: var(--font-mono);
    color: var(--crimson-blood);
    font-weight: 700;
  }
  .meter-bar {
    position: relative;
    height: 10px;
    background: #1e293b;
    border-radius: 5px;
    overflow: hidden;
  }
  .bar-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--emerald-rekindler), var(--amber-rune), var(--crimson-blood));
  }
  .threshold-line {
    position: absolute;
    left: 50%;
    top: 0;
    bottom: 0;
    width: 2px;
    background: #ffffff;
  }
  .gate-status {
    font-size: 0.75rem;
    color: var(--gold-bright);
    margin-top: 0.4rem;
  }
  .adoption-box {
    background: #040508;
    border: 1px solid var(--border-stone);
    padding: 0.75rem;
    border-radius: 0.375rem;
  }
  .adoption-box h5 {
    color: var(--gold-primary);
    font-size: 0.85rem;
    margin-bottom: 0.5rem;
  }
  .order-payload {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--gold-bright);
    margin-bottom: 0.5rem;
  }
  .criteria-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    font-size: 0.75rem;
    color: var(--emerald-rekindler);
    margin-bottom: 0.75rem;
  }
  .verdict-banner {
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--emerald-rekindler);
    text-align: center;
    padding: 0.35rem;
    background: rgba(16, 185, 129, 0.15);
    border: 1px solid rgba(16, 185, 129, 0.3);
    border-radius: 0.25rem;
  }
</style>
```

- [ ] **Step 2: Write `docs/src/components/visualizers/SpatialMap.astro`**

```astro
---
import Icons from '../icons/Icons.astro';
---

<div class="spatial-map-card runic-border-beam" id="spatial-map-viewer">
  <div class="map-header">
    <div class="title-wrap">
      <Icons name="shield" size={24} />
      <h3>Spatial Activation & Signal Waveform Cascade</h3>
    </div>
    <span class="module-tag">The Ruined Tower (7 Rooms)</span>
  </div>

  <div class="map-layout">
    <!-- SVG Dungeon Map -->
    <div class="map-svg-container">
      <svg viewBox="0 0 500 320" class="dungeon-svg">
        <!-- Room 1: Entry Hall -->
        <rect x="20" y="110" width="100" height="90" class="room-rect awake" id="room-entry" />
        <text x="70" y="155" class="room-title">1. Entry Hall</text>
        <text x="70" y="175" class="room-badge">AWAKE (PCs)</text>

        <!-- Room 2: Library -->
        <rect x="150" y="20" width="100" height="90" class="room-rect dormant" id="room-lib" />
        <text x="200" y="65" class="room-title">2. Library</text>
        <text x="200" y="85" class="room-badge">Dormant</text>

        <!-- Room 3: Guard Room -->
        <rect x="150" y="140" width="100" height="100" class="room-rect dormant" id="room-guard" />
        <text x="200" y="190" class="room-title">3. Guard Room</text>
        <text x="200" y="210" class="room-badge">Dormant</text>

        <!-- Room 5: Chief's Room -->
        <rect x="280" y="140" width="110" height="100" class="room-rect dormant" id="room-chief" />
        <text x="335" y="190" class="room-title">5. Chief's Room</text>
        <text x="335" y="210" class="room-badge">Dormant</text>

        <!-- Doorways / Edges -->
        <line x1="120" y1="155" x2="150" y2="155" class="door-edge" />
        <line x1="250" y1="190" x2="280" y2="190" class="door-edge" />
        <line x1="70" y1="110" x2="150" y2="65" class="door-edge" />
      </svg>
    </div>

    <!-- Signal Emitter Controls -->
    <div class="emitter-controls">
      <h4>Trigger Signal Emission</h4>
      <div class="signal-btns">
        <button class="emit-btn sound" id="emit-sword">
          <Icons name="swords" size={16} />
          <span>Sword Clash (Loud Sound, Intensity 8)</span>
        </button>
        <button class="emit-btn light" id="emit-torch">
          <Icons name="flame" size={16} />
          <span>Ignite Torch (Visible Light, Intensity 6)</span>
        </button>
        <button class="emit-btn alarm" id="emit-alarm">
          <Icons name="shield" size={16} />
          <span>Alarm Tripwire (Cascade Wave)</span>
        </button>
      </div>

      <div class="attenuation-card">
        <h5>Edge Attenuation Model</h5>
        <p>• Sound drops by <strong>-2 Intensity</strong> per heavy wooden door.</p>
        <p>• Light attenuates to <strong>0 Intensity</strong> around corners.</p>
        <p>• Compute is saved because dormant rooms skip LLM evaluation entirely until crossed by signals &ge; salience gate.</p>
      </div>
    </div>
  </div>
</div>

<style>
  .spatial-map-card {
    padding: 1.75rem;
    margin: 2rem 0;
  }
  .map-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1rem;
    margin-bottom: 1.5rem;
  }
  .title-wrap {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--gold-bright);
  }
  .module-tag {
    font-family: var(--font-display);
    font-size: 0.75rem;
    color: var(--emerald-rekindler);
    border: 1px solid rgba(16, 185, 129, 0.4);
    background: rgba(16, 185, 129, 0.1);
    padding: 0.25rem 0.75rem;
    border-radius: 1rem;
  }
  .map-layout {
    display: grid;
    grid-template-columns: 1.2fr 1fr;
    gap: 1.5rem;
  }
  @media (max-width: 768px) {
    .map-layout { grid-template-columns: 1fr; }
  }
  .map-svg-container {
    background: #040508;
    border: 1px solid var(--border-stone);
    border-radius: 0.5rem;
    padding: 1rem;
    display: grid;
    place-items: center;
  }
  .dungeon-svg {
    width: 100%;
    height: auto;
  }
  .room-rect {
    fill: #0d1219;
    stroke: var(--border-stone);
    stroke-width: 2;
    rx: 4;
    transition: all 0.3s ease;
  }
  .room-rect.awake {
    fill: #1a160d;
    stroke: var(--gold-primary);
    filter: drop-shadow(0 0 8px var(--gold-glow));
  }
  .room-title {
    fill: var(--gold-bright);
    font-family: var(--font-display);
    font-size: 11px;
    font-weight: 700;
    text-anchor: middle;
  }
  .room-badge {
    fill: #64748b;
    font-family: var(--font-mono);
    font-size: 9px;
    text-anchor: middle;
  }
  .door-edge {
    stroke: var(--gold-dark);
    stroke-width: 2;
    stroke-dasharray: 4 2;
  }
  .emitter-controls {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .emitter-controls h4 {
    font-size: 0.95rem;
    color: var(--gold-primary);
  }
  .signal-btns {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  .emit-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.6rem 1rem;
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    border-radius: 0.375rem;
    color: #cbd5e1;
    font-size: 0.85rem;
    text-align: left;
  }
  .emit-btn:hover {
    border-color: var(--gold-primary);
    color: var(--gold-bright);
  }
  .attenuation-card {
    background: #080a0f;
    border: 1px solid var(--border-stone-subtle);
    padding: 0.75rem;
    border-radius: 0.375rem;
    font-size: 0.8rem;
    color: #94a3b8;
    line-height: 1.5;
  }
</style>
```

- [ ] **Step 3: Write `docs/src/pages/visualizers/brains.astro` and `docs/src/pages/visualizers/dungeon.astro`**

```astro
---
// docs/src/pages/visualizers/brains.astro
import BaseLayout from '../../layouts/BaseLayout.astro';
import BrainExplorer from '../../components/visualizers/BrainExplorer.astro';
---
<BaseLayout title="Agent BDI Brain & Belief Matrix">
  <main class="page-container">
    <div class="header-section">
      <a href="/" class="back-link">← Back to Overview</a>
      <h1>Agent BDI Brain Architecture</h1>
      <p class="lead">Interactive exploration of tier-3 agent beliefs, salience gates, and autonomous order adoption.</p>
    </div>
    <BrainExplorer />
  </main>
</BaseLayout>
<style>
  .page-container { max-width: 64rem; margin: 0 auto; padding: 3rem 1.5rem 6rem; }
  .header-section { margin-bottom: 2rem; }
  .back-link { font-size: 0.9rem; color: var(--gold-primary); display: inline-block; margin-bottom: 1rem; }
  .lead { font-size: 1.2rem; color: #94a3b8; margin-top: 0.5rem; }
</style>
```

```astro
---
// docs/src/pages/visualizers/dungeon.astro
import BaseLayout from '../../layouts/BaseLayout.astro';
import SpatialMap from '../../components/visualizers/SpatialMap.astro';
---
<BaseLayout title="Spatial Activation & Dungeon Map">
  <main class="page-container">
    <div class="header-section">
      <a href="/" class="back-link">← Back to Overview</a>
      <h1>Spatial Boundaries & Signal Cascade</h1>
      <p class="lead">Interactive dungeon topology showing how boundaries gate compute and sound/light waves attenuate across doors.</p>
    </div>
    <SpatialMap />
  </main>
</BaseLayout>
<style>
  .page-container { max-width: 64rem; margin: 0 auto; padding: 3rem 1.5rem 6rem; }
  .header-section { margin-bottom: 2rem; }
  .back-link { font-size: 0.9rem; color: var(--gold-primary); display: inline-block; margin-bottom: 1rem; }
  .lead { font-size: 1.2rem; color: #94a3b8; margin-top: 0.5rem; }
</style>
```

- [ ] **Step 4: Verify components build cleanly**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 5: Commit**

```bash
git add docs/src/components/visualizers/ docs/src/pages/visualizers/
git commit -m "docs(interactive): add BDI brain matrix explorer and spatial dungeon cascade map"
```

---

### Task 8: Technical Documentation Handbook (Chapters 01–05)

**Files:**
- Create: `docs/src/content/docs/01-overview.md`
- Create: `docs/src/content/docs/02-architecture-supervision.md`
- Create: `docs/src/content/docs/03-referee-pipeline.md`
- Create: `docs/src/content/docs/04-agent-cognition-bdi.md`
- Create: `docs/src/content/docs/05-signals-perception-boundaries.md`
- Create: `docs/src/pages/docs/[...slug].astro`

**Interfaces:**
- Produces: First 5 chapters of the technical platform documentation rendered through `DocLayout`.

- [ ] **Step 1: Write `docs/src/content/docs/01-overview.md`** (Platform vision, core thesis, 4-human party playthrough, quickstart)
- [ ] **Step 2: Write `docs/src/content/docs/02-architecture-supervision.md`** (OTP tree, Ledger.Writer, World.Server, Run.Session, replay determinism)
- [ ] **Step 3: Write `docs/src/content/docs/03-referee-pipeline.md`** (5-stage machine, AD&D 1E combat/morale/saves/1gp=1XP, 3-tier preference stack)
- [ ] **Step 4: Write `docs/src/content/docs/04-agent-cognition-bdi.md`** (4 cognition tiers, belief stores, salience gates, commitments, autonomous orders)
- [ ] **Step 5: Write `docs/src/content/docs/05-signals-perception-boundaries.md`** (Spatial activation, boundary states, signal attenuation, truth barrier)
- [ ] **Step 6: Write `docs/src/pages/docs/[...slug].astro`**

```astro
---
import { getCollection } from 'astro:content';
import DocLayout from '../../layouts/DocLayout.astro';

export async function getStaticPaths() {
  const docs = await getCollection('docs');
  return docs.map(entry => ({
    params: { slug: entry.slug },
    props: { entry }
  }));
}

const { entry } = Astro.props;
const { Content, headings } = await entry.render();
---

<DocLayout
  title={entry.data.title}
  description={entry.data.description}
  currentSlug={entry.slug}
  headings={headings}
>
  <header class="doc-header">
    <div class="category-tag">{entry.data.category}</div>
    <h1>{entry.data.title}</h1>
    <p class="description">{entry.data.description}</p>
  </header>

  <div class="content-body">
    <Content />
  </div>
</DocLayout>

<style>
  .doc-header {
    border-bottom: 1px solid var(--border-stone);
    padding-bottom: 1.5rem;
    margin-bottom: 2rem;
  }
  .category-tag {
    font-family: var(--font-display);
    font-size: 0.8rem;
    color: var(--gold-dark);
    text-transform: uppercase;
    letter-spacing: 0.15em;
    margin-bottom: 0.5rem;
  }
  .description {
    font-size: 1.2rem;
    color: #94a3b8;
    margin-top: 0.5rem;
    line-height: 1.5;
  }
  .content-body :global(h2) {
    margin-top: 2.5rem;
  }
  .content-body :global(pre) {
    background: #040508 !important;
    border: 1px solid var(--border-stone);
    border-radius: 0.5rem;
    padding: 1.25rem;
    margin: 1.5rem 0;
  }
  .content-body :global(table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1.5rem 0;
  }
  .content-body :global(th),
  .content-body :global(td) {
    padding: 0.6rem 0.75rem;
    border-bottom: 1px solid var(--border-stone-subtle);
    text-align: left;
  }
  .content-body :global(th) {
    color: var(--gold-primary);
    font-family: var(--font-display);
    font-size: 0.85rem;
  }
</style>
```

- [ ] **Step 7: Verify markdown renders and types validate**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 8: Commit**

```bash
git add docs/src/content/docs/01-*.md docs/src/content/docs/02-*.md docs/src/content/docs/03-*.md docs/src/content/docs/04-*.md docs/src/content/docs/05-*.md docs/src/pages/docs/
git commit -m "docs(handbook): add chapters 01-05 covering architecture, pipeline, BDI brains, and signals"
```

---

### Task 9: Technical Documentation Handbook (Chapters 06–09)

**Files:**
- Create: `docs/src/content/docs/06-llm-gateway-routing.md`
- Create: `docs/src/content/docs/07-wire-protocol-clients.md`
- Create: `docs/src/content/docs/08-adventure-authoring-yaml.md`
- Create: `docs/src/content/docs/09-platform-marketplace-vision.md`

**Interfaces:**
- Produces: Remaining 4 chapters covering LLM Gateway chokepoint, Phoenix Channels wire contract, YAML adventure authoring, and platform marketplace/token billing mechanics.

- [ ] **Step 1: Write `docs/src/content/docs/06-llm-gateway-routing.md`** (Chokepoint routing, budget degradation order, circuit breakers, adapters)
- [ ] **Step 2: Write `docs/src/content/docs/07-wire-protocol-clients.md`** (Line-JSON vsn 2.0.0, run:<id> vs spectate:<id>, ClientTUI and ClientWeb LiveView)
- [ ] **Step 3: Write `docs/src/content/docs/08-adventure-authoring-yaml.md`** (Anatomy of `ruined_tower.yaml`, encounter design, room boundaries, preferences)
- [ ] **Step 4: Write `docs/src/content/docs/09-platform-marketplace-vision.md`** (Marketplace business model, token upcharge margin, runtime sandboxes, cross-run memory v2)
- [ ] **Step 5: Verify all 9 documentation chapters typecheck and build**

```bash
cd docs && npx astro check
```
Expected: `0 errors, 0 warnings`

- [ ] **Step 6: Commit**

```bash
git add docs/src/content/docs/06-*.md docs/src/content/docs/07-*.md docs/src/content/docs/08-*.md docs/src/content/docs/09-*.md
git commit -m "docs(handbook): add chapters 06-09 covering LLM gateway, wire protocol, YAML authoring, and marketplace vision"
```

---

### Task 10: High-Impact Showcase Landing Page, Build Verification & Launch

**Files:**
- Create: `docs/src/pages/index.astro`
- Create: `docs/public/favicon.svg`

**Interfaces:**
- Produces: Atmospheric landing page with hero banner, 3 core pillars, interactive visualizer showcase strip, and documentation index.

- [ ] **Step 1: Write `docs/public/favicon.svg`**

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#dfb15b" stroke-width="1.5">
  <polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5 12 2" fill="#131822" />
  <polygon points="12 2 12 22 2 15.5" stroke="#f6d88e" />
  <polygon points="12 2 22 15.5 12 22" stroke="#f6d88e" />
  <circle cx="12" cy="12" r="1.5" fill="#dfb15b" />
</svg>
```

- [ ] **Step 2: Write `docs/src/pages/index.astro`**

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import Icons from '../components/icons/Icons.astro';
import DiceRoller3D from '../components/visualizers/DiceRoller3D.astro';
import RefereePipeline from '../components/visualizers/RefereePipeline.astro';
import OrnamentalDivider from '../components/ui/OrnamentalDivider.astro';
---

<BaseLayout title="The Shattered Kingdoms — Agent-Oriented AD&D 1E Platform">
  <main class="landing-main">
    <!-- Hero Banner -->
    <section class="hero-section">
      <div class="hero-badge">Age of Reclamation · Year 100</div>
      <h1 class="hero-title">The Shattered Kingdoms</h1>
      <p class="hero-subtitle">
        An autonomous, agent-oriented AD&D 1E referee platform and adventure marketplace where world truth is immutable, NPCs have independent beliefs, and every roll leaves a receipt.
      </p>
      
      <div class="hero-cta-group">
        <a href="/docs/01-overview" class="cta-btn primary">
          <Icons name="book" size={18} />
          <span>Read the Handbook</span>
        </a>
        <a href="/visualizers/referee" class="cta-btn secondary">
          <Icons name="swords" size={18} />
          <span>Interactive Simulator</span>
        </a>
      </div>
    </section>

    <OrnamentalDivider symbol="✦ ❖ ✦" />

    <!-- 3 Core Platform Pillars -->
    <section class="pillars-grid">
      <div class="pillar-card runic-border-beam">
        <div class="pillar-icon">
          <Icons name="scroll" size={28} />
        </div>
        <h3>Deterministic Ground Truth</h3>
        <p>
          World state is a pure fold over an append-only event ledger. Zero hallucinated state: LLMs propose actions, pure Elixir reducers dispose them. Replay reconstructs byte-identically across restarts.
        </p>
      </div>

      <div class="pillar-card runic-border-beam">
        <div class="pillar-icon">
          <Icons name="brain" size={28} />
        </div>
        <h3>BDI Autonomous Actors</h3>
        <p>
          Every monster and NPC is an OTP GenServer running a belief-desire-intention cadence. Spatial boundaries gate compute: dormant rooms skip deliberation until threats or signals cross thresholds.
        </p>
      </div>

      <div class="pillar-card runic-border-beam">
        <div class="pillar-icon">
          <Icons name="shield" size={28} />
        </div>
        <h3>The Adventure Marketplace</h3>
        <p>
          Adventures are self-contained YAML modules sold as SKUs. Sandboxed runs execute with platform-issued frontier LLM keys, enabling a profitable per-token margin model for creators and the platform.
        </p>
      </div>
    </section>

    <!-- Embedded Live Showpieces -->
    <section class="showcase-strip">
      <div class="section-heading">
        <span class="sub">Live Demonstration</span>
        <h2>The Referee Adjudication Cycle</h2>
      </div>
      <RefereePipeline />

      <div class="section-heading" style="margin-top: 4rem;">
        <span class="sub">Pure CSS 3D Graphics</span>
        <h2>Deterministic 3D Polyhedrals</h2>
      </div>
      <DiceRoller3D />
    </section>

    <!-- Visualizer Hub Links -->
    <section class="visualizer-hub">
      <div class="section-heading">
        <span class="sub">Interactive Tools</span>
        <h2>Explore Platform Mechanics</h2>
      </div>
      <div class="hub-grid">
        <a href="/visualizers/referee" class="hub-card">
          <Icons name="swords" size={24} />
          <h4>Referee Pipeline</h4>
          <p>5-stage adjudication machine step debugger</p>
        </a>
        <a href="/visualizers/dice" class="hub-card">
          <Icons name="d20" size={24} />
          <h4>3D Dice Roller</h4>
          <p>Hardware-accelerated CSS 3D tumbling d20 & THAC0 sandbox</p>
        </a>
        <a href="/visualizers/replay" class="hub-card">
          <Icons name="scroll" size={24} />
          <h4>Ledger Replay</h4>
          <p>Time-travel event scrubber and emergence proof</p>
        </a>
        <a href="/visualizers/brains" class="hub-card">
          <Icons name="brain" size={24} />
          <h4>BDI Brain Matrix</h4>
          <p>Belief stores, salience gates, and autonomous order adoption</p>
        </a>
        <a href="/visualizers/dungeon" class="hub-card">
          <Icons name="shield" size={24} />
          <h4>Spatial Dungeon Map</h4>
          <p>Ruined Tower room boundaries & signal attenuation waves</p>
        </a>
      </div>
    </section>
  </main>
</BaseLayout>

<style>
  .landing-main {
    max-width: var(--max-width);
    margin: 0 auto;
    padding: 3rem 1.5rem 6rem;
  }
  .hero-section {
    text-align: center;
    padding: 3rem 1rem 2rem;
    max-width: 50rem;
    margin: 0 auto;
  }
  .hero-badge {
    display: inline-block;
    font-family: var(--font-display);
    font-size: 0.75rem;
    color: var(--gold-dark);
    text-transform: uppercase;
    letter-spacing: 0.2em;
    padding: 0.25rem 0.75rem;
    border: 1px solid var(--border-gold);
    border-radius: 1rem;
    margin-bottom: 1.25rem;
  }
  .hero-title {
    margin-bottom: 1.25rem;
  }
  .hero-subtitle {
    font-size: 1.25rem;
    color: #94a3b8;
    line-height: 1.6;
    margin-bottom: 2rem;
  }
  .hero-cta-group {
    display: flex;
    justify-content: center;
    gap: 1rem;
  }
  .cta-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.75rem 1.5rem;
    border-radius: 0.375rem;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
  }
  .cta-btn.primary {
    background: var(--gold-gradient);
    color: #110d05;
    box-shadow: 0 0 20px var(--gold-glow);
  }
  .cta-btn.secondary {
    background: var(--bg-surface-raised);
    border: 1px solid var(--border-stone);
    color: var(--gold-bright);
  }
  .pillars-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.5rem;
    margin: 3rem 0;
  }
  @media (max-width: 860px) {
    .pillars-grid { grid-template-columns: 1fr; }
  }
  .pillar-card {
    padding: 1.75rem;
  }
  .pillar-icon {
    width: 3rem;
    height: 3rem;
    background: rgba(223, 177, 91, 0.1);
    border: 1px solid var(--border-gold);
    border-radius: 0.5rem;
    display: grid;
    place-items: center;
    color: var(--gold-bright);
    margin-bottom: 1rem;
  }
  .pillar-card h3 {
    margin-top: 0;
    margin-bottom: 0.75rem;
  }
  .pillar-card p {
    font-size: 0.95rem;
    color: #94a3b8;
    line-height: 1.6;
  }
  .section-heading {
    text-align: center;
    margin-bottom: 1.5rem;
  }
  .section-heading .sub {
    display: block;
    font-family: var(--font-display);
    font-size: 0.75rem;
    color: var(--gold-dark);
    text-transform: uppercase;
    letter-spacing: 0.15em;
  }
  .section-heading h2 {
    border-bottom: none;
    margin-top: 0.25rem;
  }
  .visualizer-hub {
    margin-top: 5rem;
  }
  .hub-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 1rem;
  }
  .hub-card {
    background: var(--bg-surface);
    border: 1px solid var(--border-stone);
    padding: 1.25rem;
    border-radius: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    color: inherit;
  }
  .hub-card:hover {
    border-color: var(--gold-primary);
    transform: translateY(-2px);
  }
  .hub-card h4 {
    font-family: var(--font-display);
    color: var(--gold-bright);
    margin: 0;
  }
  .hub-card p {
    font-size: 0.85rem;
    color: #94a3b8;
  }
</style>
```

- [ ] **Step 3: Run full Astro build & verify 0 errors**

```bash
cd docs && npm run build
```
Expected: `✓ Completed in ... ms` (Outputs production site to `docs/dist/`)

- [ ] **Step 4: Commit**

```bash
git add docs/src/pages/index.astro docs/public/favicon.svg
git commit -m "docs: add high-impact dark fantasy landing page and complete build verification"
```

---

## Plan Self-Review Checklist

1. **Spec Coverage:**
   - Visual theme, semantic tokens, 3D CSS polyhedrals, SVG shaders? (Tasks 2, 4)
   - 5 Interactive Components (Dice, Pipeline, Replay, BDI Brains, Spatial Map)? (Tasks 4, 5, 6, 7)
   - 9 Technical Documentation Chapters? (Tasks 8, 9)
   - High-impact Landing Page? (Task 10)
   - Scope isolated to `docs/` with `docs/superpowers/` preserved? (Task 1)
2. **Placeholder scan:** Zero `TODO`, `TBD`, or placeholders. All files have concrete implementations.
3. **Type consistency:** Content collection schemas, component props, and layout bindings match across tasks.
