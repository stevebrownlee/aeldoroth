# The Shattered Kingdoms

## What this project is

This is **The Shattered Kingdoms**, an **AD&D 1E campaign world** — a campaign series set in the realm of Aeldoroth during the Age of Reclamation, roughly a century after the Darkening. Canon and play materials:

- `Aeldoroth/` — campaign-series canon: world guide (authoritative for world lore), Shadow Weaver Cult campaign arc, regions map spec, AD&D 1E gameplay reference
- `the-ruined-tower/` — starter adventure (README is authoritative for adventure details; `ruined_tower.yaml` is the game state)
- `shards-of-dimwood/` — Act 3 seed fragments
- `engrams/` — the project's persistent memory database (see the engrams section below)

Campaign status: authored and ready to play; The Ruined Tower has not yet been run.

## Newest work: shards_engine — an agent-oriented platform

The newest work is `shards_engine/` (Elixir umbrella app, `apps/engine_core`): an **agent-oriented platform** where **each major actor is its own agent with beliefs, capabilities, and decisions** — every NPC, monster, group, and the referee itself. Agents run a cadence of gathering beliefs, applying capabilities, and deciding, while the engine keeps world truth deterministic and auditable.

Settled architecture (check engrams decisions before re-litigating):

- **Hybrid brain/ledger split** — agent brains are supervised OTP actors doing deliberation only; all authority state lives in one append-only ledger mutated only by pure reducers in a single World process. Beliefs are derived, rebuildable views.
- **LLM proposes, engine disposes** — every effect, human or agent, flows through one referee pipeline: propose → validate → roll → apply. LLM output never becomes world state directly.
- **Single LLM gateway** — all LLM traffic routes through one gateway module; adapters are callable only from inside it.
- **Immutable per-run seed** — adventures load from YAML as per-run seed state; save/resume is ledger replay only; the event log is append-only and never rewritten.
- **Agent-defined boundaries** — bounded places and agents/groups declare their own boundaries that gate activation; dormant boundaries skip deliberation entirely.
- **The referee is an agent too** — a YAML preference stack drives adjudication: module preference YAML provides defaults, a personal referee YAML overrides them, core 1E rules sit beneath both.

## Engrams — Memory & Active Code Advisor

This project uses the `engrams` CLI (local SQLite) to persist decisions, patterns, progress, knowledge-graph links, and custom data between sessions. All output is **JSON**. Treat engrams as an **active advisor**: consult it before acting, log decisions as you make them, and check code against registered patterns before committing.

### When to Consult Engrams

- **Session start:** `engrams prime` — load context (mandatory before any other step).
- **Before editing files:** `engrams advise <paths>` — get only actionable constraints and violations for those files (compact; `--staged` for `git add`ed). For full context with scores, use `engrams relevant <paths>`.
- **Before designing or fixing:** `engrams query "<topic>"` · `engrams decision search "<term>" --snippets` — find prior decisions and patterns so you don't re-litigate settled choices.
- **When you make a design choice:** `engrams decision log --summary "..." --rationale "..." --tags a,b --anchor <path> --importance 8` — log immediately. Set importance (0–10) to influence retrieval ranking. A contradiction gate blocks near-duplicate active decisions and suggests `supersedes`/`conflicts_with`; resolve inline with `--supersedes <id>` / `--conflicts-with <id>` (or `--force` to bypass). To supersede after the fact: `engrams decision supersede <old-id> --by <new-id>`.
- **When you spot a recurring convention:** `engrams pattern log --name "..." --check-kind regex --check '<expr>' --severity error --anchor <path>` — make it machine-enforceable, not just prose.
- **Before committing:** `engrams check --staged` — scan staged files for violations against registered patterns (exits 1 on violations).
- **Install enforceable rules for omp sessions:** `engrams install --harness omp` (writes `.omp/rules/`). Add `--hooks` to also install a git pre-commit hook running `engrams check --staged`.

### Other Commands

| Goal | Command |
|---|---|
| Relate items (graph) | `engrams link add --source-type <t> --source-id <n> --target-type <t> --target-id <n> --rel <canonical>` |
| Log task progress | `engrams progress log --status <Status> --description "..."` |
| Hand off context | `engrams active-context update --patch '<json>'` (merge) · `--content` (replace) |
| List patterns | `engrams pattern list [--tags a,b]` |
| Attach file anchors | `engrams anchor add --type <decision|progress-entry|system-pattern> --id <n> --path <path>` |
| Attach PR reference | `engrams pr add --type <decision|system-pattern> --id <n> --pr <n_or_url>` |
| Promote repeated progress into patterns | `engrams consolidate [--apply]` — propose by default; `--apply` inserts with evidence links + confidence |
| Causal chain ("why"/impact) | `engrams graph why --node decision:7 [--down]` |
| Bulk operations | `engrams batch --type <decision|progress|pattern|custom-data> --items <json_or_->` |
| Export to Markdown | `engrams export [--path <dir>]` |
| Export rules (no install) | `engrams rules export --harness omp [--out <DIR>]` |
| Health check | `engrams doctor` |
| Prune decayed records | `engrams prune [--dry-run] [--threshold 0.1]` |
| Schema migration | `engrams migrate` |

Notes: `--status` ∈ `Todo, InProgress, InReview, Blocked, Done, Dropped`. Valid `--rel`: `relates_to`, `depends_on`, `part_of`, `implements`, `refines`, `supersedes`, `conflicts_with` (custom labels allowed; ontology at `https://engrams.sh`). Add `--compact` to any command; `--fields <list>` to project specific keys.

### Core Rules

- **CLI-First:** query all history/context through the `engrams` CLI. Never read `engrams_export/` (Git-tracked human export — token-inefficient, misses database-only state). Never improvise.
- **Accuracy:** verify any command/flag against `--help`. Decision logs describe intent, not implementation.
- **Entity types use hyphens:** `decision`, `progress-entry`, `system-pattern`, `custom-data`.

### Session End Protocol

Before declaring done: (1) `decision log` each design choice → (2) `link add` new items (`implements`/`depends_on`/`supersedes`) → (3) `progress log --status Done` → (4) `active-context update --patch '<json>'` → (5) `engrams export` → (6) commit & push `engrams_export/`.

For the full reference (Store/Link/Retrieve tables, `graph` queries, relationship ontology, status vocabularies) see `https://engrams.sh`.
