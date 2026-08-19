# Agent Engine — Plan 2: Signals, Perception, Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `engine_core` its perception economy and autonomous clock: typed signals emitted by actions, attenuated across edges, received at per-agent fidelity into beliefs; boundaries that wake and sleep; commitments that fire on the clock; a deterministic scheduler that advances world time and reacts to applied actions — all offline, all replayable to the byte.

**Architecture:** Everything stays pure data + pure functions, per Plan 1. New world truth (beliefs, boundaries, commitments, hazards, in-flight signal arrivals) is derived state maintained only by `EngineCore.Fold`; every rule module generates ledger events and applies them **via `Fold.fold`** (single reducer truth — stronger than Plan 1's hand-applied mutations; do not touch existing modules' style). Dice only through the threaded RNG. The scheduler is a pure function per tick, not a process — the OTP Scheduler process arrives with brains (Plan 3).

**Tech Stack:** Elixir ≥ 1.17 / OTP ≥ 27, Mix umbrella, ExUnit, `yaml_elixir` (only allowed dep).

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` — this plan implements §12.4 phases 3–4: "Signals: emission, edge attenuation, reception filters, template narration at fidelity tiers" and "Scheduler: cadences, commitments, boundary wake/sleep, lazy catch-up", plus tier-0/1/2 cognition (spec §5.1) as deterministic rules.

**Engrams design record (do not re-litigate):** decisions 18 (event-driven time), 19 (cognition tiers), 21 (room-occlusion + signal routing; traps are signal broadcasters), 25 (boundaries first-class, agent-defined; `coarse_tick` reserved for place boundaries ONLY), 31 (fidelity tiers F0–F5, marginal signals resolved by d6 awareness), 30 (commitments recorded by engine — LLM "I will" is not a commitment); patterns 10 (`append-only-ledger`), 11 (`effects-via-referee-pipeline` — here: no state mutation outside rule modules + Fold), 12 (`activation-gated-deliberation`).

## Global Constraints

- Engine lives at `shards_engine/` (umbrella); core app at `shards_engine/apps/engine_core/`.
- `engine_core` dependencies: `yaml_elixir` ONLY. Phoenix, HTTP/LLM clients, Jason: FORBIDDEN in `engine_core`.
- No wall-clock: `DateTime`, `NaiveDateTime`, `:os.time`, `System.time` FORBIDDEN in `engine_core` lib. Ticks are monotonically increasing integers.
- All events are pure data (maps/structs of scalars, lists, atoms) — serializable via `:erlang.term_to_binary/1`.
- Dice rolls only via `EngineCore.Dice`, RNG threaded explicitly (`{value, new_rng}` convention). Propagation math itself uses NO dice.
- Determinism: same YAML + same seed + same action script ⇒ byte-identical ledger (Task 11 golden test enforces).
- **Deterministic iteration:** any code that generates events from map/list data MUST sort first (`Enum.sort_by(&1.id)`, `sort_by({tick, ref, place_id})`, etc.). Unsorted `Map.values/1` into event generation is a bug.
- **Reducer unity:** every new module applies its events with `Fold.fold(world, events)`. Never hand-mutate beliefs/boundaries/commitments outside `Fold`.
- Event classes used: existing `:world`, `:dice`; new `:signal`, `:commitment`, `:meta`. New payload kinds are additive — existing fold clauses and tests must stay green.
- Template narration only — no LLM anywhere (LLM `narrate` swaps templates in Plan 3).
- Tests: ExUnit, offline. Run from `shards_engine/`: `mix test`.
- Commit style: conventional (`feat:`, `fix:`, `test:`, `chore:`, `refactor:`), one logical change per commit.

## File Structure

```
shards_engine/apps/engine_core/
├── lib/engine_core/
│   ├── types.ex                # MODIFY: +Signal, Arrival, Boundary, Commitment, Hazard;
│   │                           #   Edge.label, Agent.attention/group, World fields
│   ├── world.ex                # MODIFY: new struct fields
│   ├── loader.ex               # MODIFY: boundaries, commitments, hazards, groups,
│   │                           #   cadences, edge labels, rat tier fix
│   ├── validator.ex            # MODIFY: boundary/commitment/hazard checks
│   ├── fold.ex                 # MODIFY: clauses for all new payload kinds
│   ├── signals.ex              # CREATE: emission + edge attenuation propagation
│   ├── perception.ex           # CREATE: reception filters, fidelity, salience
│   ├── narrate.ex              # CREATE: F0–F5 template rendering
│   ├── commitments.ex          # CREATE: commitment lifecycle transitions
│   ├── boundaries.ex           # CREATE: trigger evaluation, wake/sleep, catch-up
│   ├── scheduler.ex            # CREATE: advance/1 tick loop + react/3 bridge
│   ├── scenario.ex             # MODIFY: alarm_cascade/2 scenario
│   └── cognition/
│       ├── hazard.ex           # CREATE: tier 0 — traps + skeleton pattern
│       ├── reflex.ex           # CREATE: tier 1 — rat stimulus→action table
│       └── pack.ex             # CREATE: tier 2 — wolf pack drives
└── test/
    ├── types_test.exs          # MODIFY
    ├── loader_test.exs         # MODIFY
    ├── validator_test.exs      # MODIFY
    ├── fold_test.exs           # MODIFY
    ├── signals_test.exs        # CREATE
    ├── perception_test.exs     # CREATE
    ├── narrate_test.exs        # CREATE
    ├── commitments_test.exs    # CREATE
    ├── boundaries_test.exs     # CREATE
    ├── cognition_test.exs      # CREATE
    ├── scheduler_test.exs      # CREATE
    └── cascade_replay_test.exs # CREATE (Task 11)
the-ruined-tower/ruined_tower.yaml  # MODIFY (Task 2): boundaries, initial_commitments,
                                    #   alarm bound_exit — additive keys only
shards_engine/automated-run.sh      # MODIFY (Task 11): `cascade` mode
```

## Shared Interfaces (tasks must match these exactly)

- `Types.Signal` — `%Signal{emitted_by, place_id, tick, kind, content_core, intensity, content_nl}`; `kind ∈ :sight | :sound | :smell | :tremor`; `content_core ≈ %{class: atom, threat: bool, about: agent_id | :unknown, count: pos_integer}`.
- `Types.Arrival` — `%Arrival{ref, place_id, tick, kind, intensity, about, hops, origin_place_id, content_core, content_nl}` (`@enforce_keys` the first eight). `ref` is a positive integer from `world.signal_seq`.
- `Types.Boundary` — `%Boundary{id, scope_place_id, scope_group, bound_agent_ids, triggers, state, last_trigger_tick, wake_on_intensity, sleep_after}`; `state ∈ :dormant | :awake`; `triggers ⊆ [:presence_crossing, :signal_arrived, :commitment_due, :coarse_tick]`.
- `Types.Commitment` — `%Commitment{id, debtor, creditor, deed, due, every, priority, status}`; `status ∈ :pending | :due | :kept | :violated`; `deed` is a string, `due/every` integers or nil.
- `Types.Hazard` — `%Hazard{id, kind, place_id, edge_id, dc, triggered, damage, signal_intensity, signal_class}`; `kind ∈ :alarm | :damage`.
- `Types.Edge` — gains `label: nil` (direction string, e.g. `"north"`).
- `Types.Agent` — gains `attention: :alert` (`:alert | :dormant`) and `group: nil` (string). `cadence` is `nil` or `%{every: pos_integer, next_due: integer | nil}`.
- `World` — gains `boundaries: %{id => Boundary}`, `in_flight: [Arrival]` (sorted by `{tick, ref, place_id}`), `hazards: %{id => Hazard}`, `signal_seq: 0`.
- `Fold.update_agent(world, id, fun) :: World.t()` — made PUBLIC in Task 3 (was private).
- `Signals.emit(world, emitted_by, kind, content_core, intensity, content_nl \\ nil) :: {:ok, [Ledger.Event.t()], World.t()}` — emits at `world.tick`, BFS-propagates, returns `[:signal_emitted]` events (arrival facts live in `world.in_flight`, consumed by the scheduler).
- `Perception.base_fidelity(arrival, agent) :: integer` (pure, may go ≤ 0) · `Perception.resolve_fidelity(base, arrival, rng) :: {0..5, roll | nil, rng2}` (d6 marginal) · `Perception.salience(arrival, agent, world) :: float` · `Perception.receive_arrival(world, rng, arrival) :: {:ok, [Event], World, rng2}`.
- `Narrate.render(view, fidelity, direction \\ nil) :: String.t()` (view = Arrival or map with `kind`, `intensity`, `content_core`, `content_nl`) · `Narrate.direction(world, from_place_id, to_place_id) :: String.t()`.
- `Commitments.create(world, attrs) :: {:ok, [Event], World} | {:error, :no_debtor}` · `due(world, tick) :: [Commitment]` · `mark_due(world, id, late_by \\ 0)` · `keep(world, id)` · `violate(world, id)` · `renegotiate(world, id, new_due)` — all `{:ok, [Event], World}`.
- `Boundaries.evaluate(world, event) :: {:ok, [Event], World}` · `wake(world, id, tick, reason)` · `sleep(world, id)` · `catchup(world, id)` · `sleep_ready?(world, boundary) :: boolean`.
- `Scheduler.advance(world, rng) :: {:ok, [Event], World, rng2}` — one tick of autonomous time (arrivals → receptions → reflex → commitment dues → cadences → boundary sleep).
- `Scheduler.react(world, rng, [Event]) :: {:ok, [Event], World, rng2}` — §6.4 bridge after an applied action batch: hazard triggers, side-effect signals, boundary refresh, same-tick arrival processing.
- `Cognition.Hazard.check_move(world, rng, move_payload) :: {:ok, [Event], World, rng2}` · `Cognition.Hazard.check_presence(world, rng, agent_id) :: {:ok, [Event], World, rng2}` · `Cognition.Reflex.decide(world, rng, agent) :: {:ok, [Event], World, rng2}` · `Cognition.Pack.decide(world, rng, agent) :: {:ok, [Event], World, rng2}`.
- `Movement.traverse(world, rng, agent_id, to, opts \\ [])` — opts `[careful: boolean]`; move payload gains `careful: boolean` (default `false`).
- `Scenario.alarm_cascade(yaml_path, seed) :: %{ledger: [Event], final_world: World}`.

Event payload kinds added to `Fold` (class in parens): `:signal_emitted`, `:signal_arrived`, `:signal_received` (`:signal`); `:commitment_created`, `:commitment_due`, `:commitment_kept`, `:commitment_violated`, `:commitment_renegotiated` (`:commitment`); `:boundary_wake`, `:boundary_refresh`, `:boundary_sleep`, `:boundary_catchup`, `:cadence_tick`, `:hazard_triggered`, `:hazard_avoided` (`:meta`); `:damage` reuse for hazard damage (`:world`).

Attenuation constants (`EngineCore.Signals`): `open ≈ %{sight: 0.5, sound: 0.7, smell: 0.4, tremor: 0.8}`, `muffled ≈ %{sight: 0.1, sound: 0.3, smell: 0.1, tremor: 0.4}`; a kind missing from an edge's permeability map defaults to `:muffled`; `sealed` edge or `:blocked` permeability ⇒ no propagation. Intensity floor `1.0` — arrivals below it don't exist. Hop delay: 1 tick per edge.

---

### Task 1: Types & World extensions

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/types.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/world.ex`
- Test: `shards_engine/apps/engine_core/test/types_test.exs`

**Interfaces:**
- Consumes: existing structs (unchanged behavior — all additions have defaults).
- Produces: `Types.Signal`, `Types.Arrival`, `Types.Boundary`, `Types.Commitment`, `Types.Hazard`; `Edge.label`; `Agent.attention`, `Agent.group`; `World.boundaries/in_flight/hazards/signal_seq`. Exact defaults per Shared Interfaces.

- [ ] **Step 1: Write the failing tests** — append to `test/types_test.exs`:

```elixir
  test "signal and arrival defaults" do
    s = struct!(Types.Signal, emitted_by: "pc1", place_id: "entry_hall", tick: 3,
                kind: :sound, content_core: %{class: :combat, threat: true}, intensity: 7)
    assert s.content_nl == nil
    a = struct!(Types.Arrival, ref: 1, place_id: "library", tick: 4, kind: :sound,
                intensity: 4.9, about: "pc1", hops: 1, origin_place_id: "entry_hall")
    assert a.content_core == nil and a.content_nl == nil
  end

  test "boundary, commitment, hazard defaults" do
    b = struct!(Types.Boundary, id: "guard_room_zone", bound_agent_ids: ["g1"],
                triggers: [:presence_crossing, :signal_arrived])
    assert b.state == :dormant and b.wake_on_intensity == 4 and b.sleep_after == 40
    assert b.scope_place_id == nil and b.scope_group == nil
    c = struct!(Types.Commitment, id: "watch", debtor: "g1", deed: "keep_watch")
    assert c.status == :pending and c.priority == 5 and c.due == nil and c.every == nil
    h = struct!(Types.Hazard, id: "alarm_tripwire", kind: :alarm, place_id: "entry_hall")
    assert h.triggered == false and h.dc == 12 and h.edge_id == nil
    assert h.damage == %{dice: 1, sides: 4, plus: 0} and h.signal_intensity == 9
    assert h.signal_class == :alarm
  end

  test "edge label, agent attention and group, world defaults" do
    e = struct!(Types.Edge, id: :e1, from: "a", to: "b")
    assert e.label == nil
    a = struct!(Types.Agent, id: "w1", name: "Wolf", tier: 2, place_id: "beast_pen")
    assert a.attention == :alert and a.group == nil
    w = %World{}
    assert w.boundaries == %{} and w.in_flight == [] and w.hazards == %{}
    assert w.signal_seq == 0
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/types_test.exs`
Expected: FAIL — `Types.Signal` is not defined.

- [ ] **Step 3: Implement** — in `types.ex`, extend the existing modules and add new ones:

```elixir
  defmodule Edge do
    @enforce_keys [:id, :from, :to]
    defstruct [:id, :from, :to, sealed: false, label: nil,
               permeability: %{sight: :open, sound: :open}]
  end

  defmodule Agent do
    @enforce_keys [:id, :name, :tier, :place_id]
    defstruct [
      :id,
      :name,
      :tier,
      :place_id,
      statblock: %{
        ac: 10, hd: 1, hp_max: 1, thac0: 20, morale: 7, int: 10,
        damage: %{dice: 1, sides: 6, plus: 0}
      },
      body: %{hp: 1, conditions: []},
      capabilities: [:move, :strike, :wait],
      beliefs: %{}, commitments: [], cadence: nil, dossier: %{},
      attention: :alert, group: nil
    ]
  end

  defmodule Signal do
    @moduledoc "One emission into a place. content_core: %{class, threat, about, count}."
    @enforce_keys [:emitted_by, :place_id, :tick, :kind, :content_core, :intensity]
    defstruct [:emitted_by, :place_id, :tick, :kind, :content_core, :intensity, content_nl: nil]
  end

  defmodule Arrival do
    @moduledoc "A signal instance pending reception at a place/tick, post-attenuation."
    @enforce_keys [:ref, :place_id, :tick, :kind, :intensity, :about, :hops, :origin_place_id]
    defstruct [:ref, :place_id, :tick, :kind, :intensity, :about, :hops,
               :origin_place_id, :content_core, :content_nl]
  end

  defmodule Boundary do
    @moduledoc "Activation boundary: place-scoped or group-scoped (decision 25)."
    @enforce_keys [:id, :bound_agent_ids, :triggers]
    defstruct [:id, :scope_place_id, :scope_group, :bound_agent_ids, :triggers,
               state: :dormant, last_trigger_tick: nil,
               wake_on_intensity: 4, sleep_after: 40]
  end

  defmodule Commitment do
    @moduledoc "Structured obligation (spec 5.4). Status: pending/due/kept/violated."
    @enforce_keys [:id, :debtor, :deed]
    defstruct [:id, :debtor, :creditor, :deed, due: nil, every: nil,
               priority: 5, status: :pending]
  end

  defmodule Hazard do
    @moduledoc "Tier-0 pattern: alarm hazards broadcast, damage hazards bite (decision 21)."
    @enforce_keys [:id, :kind, :place_id]
    defstruct [:id, :kind, :place_id, edge_id: nil, dc: 12, triggered: false,
               damage: %{dice: 1, sides: 4, plus: 0},
               signal_intensity: 9, signal_class: :alarm]
  end
```

In `world.ex`, extend the struct:

```elixir
  defstruct places: %{}, edges: [], agents: %{}, items: %{}, tick: 0,
            boundaries: %{}, in_flight: [], hazards: %{}, signal_seq: 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/types_test.exs`
Expected: PASS (all tests in file).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/types.ex \
        shards_engine/apps/engine_core/lib/engine_core/world.ex \
        shards_engine/apps/engine_core/test/types_test.exs
git commit -m "feat: signal, boundary, commitment, hazard types; world containers"
```

---

### Task 2: YAML seed data + Loader + Validator

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml` (additive keys only)
- Modify: `shards_engine/apps/engine_core/lib/engine_core/loader.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/validator.ex`
- Test: `shards_engine/apps/engine_core/test/loader_test.exs`, `test/validator_test.exs`

**Interfaces:**
- Consumes: Task 1 structs.
- Produces: `Loader.load/1` returning a World with `boundaries` (5), `hazards` (5), agent `group`/`attention`/`cadence`/`commitments` set, edge `label`s, and giant rats at tier 1 (spec §5.1: individual rats are vermin/reflex, tier 1 — the Plan-1 loader wrongly listed them tier 2). `Validator.check/1` rejecting bad boundary/commitment/hazard data.

- [ ] **Step 1: Add seed data to the YAML.** Append these top-level blocks at the end of `the-ruined-tower/ruined_tower.yaml` (after `initial_treasure`), and add one `bound_exit` key inside the existing `alarm_tripwire` trap map:

```yaml
# --- Agent engine seed data (spec sections 4.2, 5.4; decisions 25, 30) ---
boundaries:
  - id: "guard_room_zone"
    place: "guard_room"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 4
    sleep_after: 60
  - id: "chiefs_room_zone"
    place: "chiefs_room"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 5
    sleep_after: 80
  - id: "library_zone"
    place: "library"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 6
    sleep_after: 40
  - id: "wolf_pack"
    group: "wolf"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 6
    sleep_after: 30
  - id: "skeleton_sentinel"
    place: "ritual_chamber"
    triggers: ["presence_crossing"]

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

Inside `rooms.entry_hall.traps`, add to the `alarm_tripwire` map: `bound_exit: "east"` (binds the tripwire to the entry_hall→guard_room passage).

- [ ] **Step 2: Write the failing tests** — append to `loader_test.exs`:

```elixir
  test "loads boundaries, hazards, commitments, groups, cadences" do
    {:ok, w} = EngineCore.Loader.load(@yaml)

    assert MapSet.new(Map.keys(w.boundaries)) == MapSet.new([
             "guard_room_zone", "chiefs_room_zone", "library_zone",
             "wolf_pack", "skeleton_sentinel"])

    gz = w.boundaries["guard_room_zone"]
    assert gz.scope_place_id == "guard_room" and gz.state == :dormant
    assert gz.triggers == [:presence_crossing, :signal_arrived]
    assert gz.wake_on_intensity == 4 and gz.sleep_after == 60
    assert MapSet.new(gz.bound_agent_ids) ==
           MapSet.new(~w(goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4))

    wp = w.boundaries["wolf_pack"]
    assert wp.scope_group == "wolf"
    assert MapSet.new(wp.bound_agent_ids) == MapSet.new(~w(wolf_1 wolf_2))

    assert MapSet.new(Map.keys(w.hazards)) ==
           MapSet.new(~w(alarm_tripwire caltrops bell_tripwire pit_trap false_cache_needle))
    assert w.hazards["alarm_tripwire"].kind == :alarm
    assert w.hazards["alarm_tripwire"].edge_id == :"entry_hall__guard_room"
    assert w.hazards["caltrops"].kind == :damage
    assert w.hazards["pit_trap"].damage == %{dice: 1, sides: 6, plus: 0}

    guards = w.agents["goblin_guard_1"]
    assert guards.attention == :dormant
    assert guards.cadence == %{every: 10, next_due: nil}
    assert [%EngineCore.Types.Commitment{id: "guard_watch_rotation", status: :pending,
             due: 30, every: 30}] = guards.commitments

    grisk = w.agents["grisk_the_snatcher"]
    assert [%EngineCore.Types.Commitment{id: "grisk_relocation_deadline", priority: 8}] =
             grisk.commitments

    assert w.agents["giant_rat_1"].tier == 1
    assert w.agents["wolf_1"].tier == 2 and w.agents["wolf_1"].group == "wolf"
    assert w.agents["wolf_1"].cadence == %{every: 5, next_due: nil}
    assert w.agents["shadow_touched_skeleton"].attention == :dormant

    assert Enum.find(w.edges, &(&1.id == :"entry_hall__guard_room")).label == "east"
  end
```

and to `validator_test.exs`:

```elixir
  test "boundary validation: unknown place, bad trigger, coarse_tick on group scope" do
    base = %{"rooms" => %{}, "initial_enemies" => %{}}
    assert {:error, errs} = EngineCore.Validator.check(
      Map.put(base, "boundaries", [%{"id" => "b1", "place" => "nowhere",
                                     "triggers" => ["presence_crossing"]}]))
    assert "boundary b1: unknown place nowhere" in errs

    assert {:error, errs2} = EngineCore.Validator.check(
      Map.put(base, "boundaries", [%{"id" => "b1", "place" => "r1",
                                     "triggers" => ["nonsense"]}]))
    assert "boundary b1: invalid trigger nonsense" in errs2

    assert {:error, errs3} = EngineCore.Validator.check(
      Map.put(base, "boundaries", [%{"id" => "b1", "group" => "wolf",
                                     "triggers" => ["coarse_tick"]}]))
    assert "boundary b1: coarse_tick is reserved for place boundaries" in errs3

    assert {:error, errs4} = EngineCore.Validator.check(
      Map.merge(base, %{"boundaries" => [%{"id" => "b1", "place" => "r1",
                                           "triggers" => ["presence_crossing"]}],
                        "rooms" => %{"r1" => %{"id" => "r1"}},
                        "initial_enemies" => %{"g1" => %{"id" => "g1"}},
                        "initial_commitments" => [%{"id" => "c1", "debtor" => "ghost",
                                                     "deed" => "x", "due" => 5}]}))
    assert "commitment c1: unknown debtor ghost" in errs4
  end
```

(If `loader_test.exs` lacks an `@yaml` path variable, add at module top:
`@yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)`.)

- [ ] **Step 3: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/loader_test.exs apps/engine_core/test/validator_test.exs`
Expected: FAIL — no boundaries loaded; validator accepts bad boundaries.

- [ ] **Step 4: Implement loader changes** (in `loader.ex`):

```elixir
  # tier lists: individual rats are tier 1 vermin (spec 5.1); wolves are the pack tier
  @tier3 ~w(grisk_the_snatcher grisk snaga skrit varg murg willem
            goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4
            goblin_bodyguard_1 goblin_bodyguard_2)
  @tier2 ~w(wolf_1 wolf_2 wolf_pair rat_pack_1 rat_pack_2)

  @trigger_atoms %{"presence_crossing" => :presence_crossing,
                   "signal_arrived" => :signal_arrived,
                   "commitment_due" => :commitment_due,
                   "coarse_tick" => :coarse_tick}

  def build(yaml) when is_map(yaml) do
    ...existing rooms/edges/agents/items building unchanged, except:
    # edges carry direction labels:
    edges =
      for r <- rooms,
          {dir, c} <- extract_exits(r),
          do: %Types.Edge{
            id: :"#{r["id"]}__#{c.target}",
            from: r["id"],
            to: c.target,
            sealed: c.sealed,
            label: dir
          }
    # (extract_exits returns {dir, %{target, sealed}} pairs — see below)

    world = %World{places: places, edges: edges, agents: agents, items: items, tick: 0}
    world
    |> put_boundaries(yaml)
    |> put_hazards(yaml)
    |> put_commitments(yaml)
    |> apply_dormancy()
  end
```

`extract_exits/1` becomes `extract_exits(r) :: [{direction, %{target: id, sealed: bool}}]` — keep every existing parsing branch, tagging each result with the map key; `extract_connections/1` then maps over `Enum.map(extract_exits(r), fn {_d, c} -> c.target end)`.

New private functions:

```elixir
  defp put_boundaries(world, yaml) do
    default_place_boundary = fn {place_id, _} -> place_id end

    boundaries =
      yaml
      |> Map.get("boundaries", [])
      |> Enum.map(fn b ->
        id = b["id"]
        triggers = b["triggers"] |> Enum.map(&Map.get(@trigger_atoms, &1, :invalid))

        bound =
          cond do
            b["agents"] -> b["agents"]
            b["group"] -> world.agents
                        |> Map.values()
                        |> Enum.filter(&(&1.group == b["group"]))
                        |> Enum.map(& &1.id)
                        true ->
              world.agents
              |> Map.values()
              |> Enum.filter(&(&1.place_id == b["place"]))
              |> Enum.map(& &1.id)
          end
          |> Enum.sort()

        struct!(Types.Boundary,
          id: id,
          scope_place_id: b["place"],
          scope_group: b["group"],
          bound_agent_ids: bound,
          triggers: triggers,
          wake_on_intensity: b["wake_on_intensity"] || 4,
          sleep_after: b["sleep_after"] || 40
        )
      end)

    %{world | boundaries: Map.new(boundaries, &{&1.id, &1})}
  end

  defp put_hazards(world, yaml) do
    hazards =
      for {room_id, r} <- Map.get(yaml, "rooms", %{}),
          t <- List.wrap(r["traps"]),
          do: {t["id"], hazard_from(t, room_id, world)}

    %{world | hazards: Map.new(hazards)}
  end

  defp hazard_from(t, room_id, world) do
    kind = hazard_kind(t["type"])
    edge_id = edge_id_for(room_id, t["bound_exit"], world)
    struct!(Types.Hazard,
      id: t["id"], kind: kind, place_id: room_id, edge_id: edge_id,
      dc: t["difficulty_class"] || 12,
      damage: parse_damage(t),
      signal_intensity: (kind == :alarm && 9) || 6,
      signal_class: (kind == :alarm && :alarm) || :combat)
  end

  defp hazard_kind("alarm"), do: :alarm
  defp hazard_kind(_), do: :damage

  defp edge_id_for(room_id, nil, _world), do: nil
  defp edge_id_for(room_id, exit_dir, world) do
    world.edges
    |> Enum.find(%{id: nil}, fn e ->
      e.from == room_id and e.label == exit_dir
    end).id
  end

  defp put_commitments(world, yaml) do
    commits =
      yaml
      |> Map.get("initial_commitments", [])
      |> Enum.map(fn c ->
        %Types.Commitment{
          id: c["id"], debtor: c["debtor"], creditor: c["creditor"],
          deed: c["deed"], due: c["due"], every: c["every"],
          priority: c["priority"] || 5
        }
      end)

    agents =
      Enum.reduce(commits, world.agents, fn cm, acc ->
        case Map.get(acc, cm.debtor) do
          nil -> acc
          agent -> Map.put(acc, cm.debtor, %{agent | commitments: agent.commitments ++ [cm]})
        end
      end)

    %{world | agents: agents}
  end

  defp apply_dormancy(world) do
    dormant_ids =
      world.boundaries
      |> Map.values()
      |> Enum.filter(&(&1.state == :dormant))
      |> Enum.flat_map(& &1.bound_agent_ids)
      |> MapSet.new()

    agents =
      Map.new(world.agents, fn {id, a} ->
        {id, if(MapSet.member?(dormant_ids, id), do: %{a | attention: :dormant}, else: a)}
      end)

    %{world | agents: agents}
  end
```

Delete the erroneous placeholder `Enum.reduce` shown first in `put_commitments` — final code contains only the second reduce plus cadence assignment: in `agent_from/2` add `group: m["type"]` and after tier resolution set `cadence: cadence_for(tier)` where:

```elixir
  defp cadence_for(3), do: %{every: 10, next_due: nil}
  defp cadence_for(2), do: %{every: 5, next_due: nil}
  defp cadence_for(_), do: nil
```

- [ ] **Step 5: Implement validator additions** (in `validator.ex`):

```elixir
  @valid_triggers MapSet.new(~w(presence_crossing signal_arrived commitment_due coarse_tick))

  # call as boundary_errors(yaml, room_ids); commits as commitment_errors(yaml, agent_ids)
  defp boundary_errors(%{"boundaries" => bs}, room_ids) when is_list(bs) do
    Enum.flat_map(bs, fn b ->
      id = b["id"] || "?"

      cond do
        b["place"] == nil and b["group"] == nil ->
          ["boundary #{id}: needs place or group scope"]

        b["place"] != nil and b["group"] != nil ->
          ["boundary #{id}: place and group are mutually exclusive"]

        true ->
          []
      end ++
      trigger_errors(id, b) ++ scope_errors(id, b, room_ids)
    end)
  end

  defp boundary_errors(_, _), do: []

  defp trigger_errors(id, b) do
    b |> Map.get("triggers", []) |> Enum.flat_map(fn t ->
      if MapSet.member?(@valid_triggers, t), do: [], else: ["boundary #{id}: invalid trigger #{t}"]
    end)
  end

  defp scope_errors(id, b, room_ids) do
    place = b["place"]

    unknown_place =
      if place != nil and not MapSet.member?(room_ids, place),
        do: ["boundary #{id}: unknown place #{place}"],
        else: []

    coarse_on_group =
      if b["group"] != nil and "coarse_tick" in (b["triggers"] || []),
        do: ["boundary #{id}: coarse_tick is reserved for place boundaries"],
        else: []

    unknown_place ++ coarse_on_group
  end

  defp commitment_errors(%{"initial_commitments" => cs}, agent_ids)
       when is_list(cs) do
    Enum.flat_map(cs, fn c ->
      id = c["id"] || "?"
      if c["debtor"] in agent_ids, do: [], else: ["commitment #{id}: unknown debtor #{c["debtor"]}"]
    end)
  end

  defp commitment_errors(_, _), do: []
```

Wire them into `check/1`: derive `room_ids` exactly as `room_errors` does, `agent_ids` from `initial_enemies` values' `"id"` keys, and append `boundary_errors(yaml, room_ids) ++ commitment_errors(yaml, agent_ids)` to the existing error list.


- [ ] **Step 6: Run tests to verify they pass; full suite green**

Run: `cd shards_engine && mix test apps/engine_core/test/loader_test.exs apps/engine_core/test/validator_test.exs && mix test`
Expected: new tests PASS; full suite PASS (existing loader tests still green — all YAML changes additive).

- [ ] **Step 7: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml \
        shards_engine/apps/engine_core/lib/engine_core/loader.ex \
        shards_engine/apps/engine_core/lib/engine_core/validator.ex \
        shards_engine/apps/engine_core/test/loader_test.exs \
        shards_engine/apps/engine_core/test/validator_test.exs
git commit -m "feat: boundaries, commitments, hazards seed data; loader and validator support"
```

---

### Task 3: Signals — emission, edge attenuation, in-flight arrivals

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/signals.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/fold.ex` (new clauses + public `update_agent/3`)
- Test: `shards_engine/apps/engine_core/test/signals_test.exs`, modify `test/fold_test.exs`

**Interfaces:**
- Consumes: Task 1 structs, existing `Ledger.Event`.
- Produces: `Signals.emit/6`; fold clauses `:signal_emitted` / `:signal_arrived` / `:signal_received`; `Fold.update_agent/3` public; `World.in_flight` sorted by `{tick, ref, place_id}`.

- [ ] **Step 1: Write the failing test** — `test/signals_test.exs`:

```elixir
defmodule EngineCore.SignalsTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, Loader, Signals, Types, World}

  # entry_hall --east--> guard_room ; entry_hall --north--> library
  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  defp loaded, do: elem(Loader.load(@yaml), 1)

  test "emission creates origin arrival and attenuated neighbor arrivals" do
    w = loaded()
    {:ok, [ev], w2} =
      Signals.emit(w, "pc1", :sound,
        %{class: :combat, threat: true, about: "pc1", count: 1}, 10,
        "the crash of steel on steel")

    assert ev.class == :signal
    assert ev.payload.kind == :signal_emitted
    assert ev.payload.ref == 1 and ev.payload.signal_kind == :sound
    assert w2.signal_seq == 1

    by_place = Map.new(w2.in_flight, &{{&1.place_id, &1.hops}, &1})
    origin = by_place[{"entry_hall", 0}]
    assert origin.tick == w.tick and origin.intensity == 10 and origin.about == "pc1"

    east = by_place[{"guard_room", 1}]
    assert east.tick == w.tick + 1
    assert_in_delta east.intensity, 10 * 0.7, 0.001   # open doorway, sound

    north = by_place[{"library", 1}]
    assert_in_delta north.intensity, 10 * 0.7, 0.001

    # ritual chamber is behind a sealed trapdoor: no arrival
    refute Map.has_key?(by_place, {"ritual_chamber", 2})
    # every place reachable, each exactly once, list sorted
    ticks = Enum.map(w2.in_flight, &{&1.tick, &1.ref, &1.place_id})
    assert ticks == Enum.sort(ticks)
  end

  test "intensity floor cuts propagation" do
    w = loaded()
    {:ok, [_], w2} = Signals.emit(w, "pc1", :sound, %{class: :footsteps, threat: false,
                                  about: "pc1", count: 1}, 1.2)
    # 1.2 * 0.7 = 0.84 < 1.0 floor: only the origin arrival exists
    assert [%Types.Arrival{place_id: "entry_hall", hops: 0}] = w2.in_flight
  end

  test "fold replays emission and arrival removal identically" do
    w = loaded()
    {:ok, [ev], w2} = Signals.emit(w, "pc1", :sound,
        %{class: :alarm, threat: true, about: "pc1", count: 1}, 9)
    assert Fold.fold(w, [ev]) == w2

    arrival = Enum.find(w2.in_flight, &(&1.place_id == "guard_room"))
    rem_ev = %Ledger.Event{seq: 0, tick: arrival.tick, class: :signal,
      payload: %{kind: :signal_arrived, ref: arrival.ref, place_id: "guard_room",
                 tick: arrival.tick, intensity: arrival.intensity,
                 signal_kind: :sound, about: "pc1"}}
    w3 = Fold.fold(w2, [rem_ev])
    refute Enum.any?(w3.in_flight, &(&1.ref == arrival.ref and &1.place_id == "guard_room"))
    assert Enum.any?(w3.in_flight, &(&1.place_id == "entry_hall"))
  end

  test "signal_received updates beliefs via fold" do
    w = loaded()
    g1 = w.agents["goblin_guard_1"]
    ev = %Ledger.Event{seq: 0, tick: 7, class: :signal,
      payload: %{kind: :signal_received, agent_id: "goblin_guard_1",
                 place_id: "guard_room", ref: 1, about: "pc1", signal_kind: :sound,
                 intensity: 6.3, fidelity: 3, salience: 8.0, roll: nil}}
    w2 = Fold.fold(w, [ev])
    entry = w2.agents["goblin_guard_1"].beliefs["guard_room"]["pc1"]
    assert entry.count == 1 and entry.last_tick == 7 and entry.last_fidelity == 3
    assert entry.seen == false and entry.salience == 8.0
    assert g1.beliefs == %{}
  end
end
```

Append to `fold_test.exs` equivalent minimal checks (one emission clause test, one unknown-kind raise still holds).

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/signals_test.exs`
Expected: FAIL — `EngineCore.Signals` is not defined.

- [ ] **Step 3: Implement `lib/engine_core/signals.ex`:**

```elixir
defmodule EngineCore.Signals do
  @moduledoc """
  Signal emission and edge-attenuated propagation (spec 6.1, decision 21).
  Pure: no dice. Arrival facts live in world.in_flight; the scheduler
  converts them to :signal_arrived events at their tick.
  """
  alias EngineCore.{Fold, Ledger, Types, World}

  @attenuation %{
    open: %{sight: 0.5, sound: 0.7, smell: 0.4, tremor: 0.8},
    muffled: %{sight: 0.1, sound: 0.3, smell: 0.1, tremor: 0.4}
  }
  @intensity_floor 1.0
  @hop_delay 1

  @spec emit(World.t(), String.t(), atom, map, number, String.t() | nil) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def emit(world, emitted_by, kind, content_core, intensity, content_nl \\ nil) do
    ref = world.signal_seq + 1
    origin = origin_place(world, emitted_by)
    about = Map.get(content_core, :about, :unknown)

    facts = propagate(world, origin, kind, intensity)

    arrivals =
      for f <- facts do
        %Types.Arrival{ref: ref, place_id: f.place_id, tick: f.tick, kind: kind,
                       intensity: f.intensity, about: about, hops: f.hops,
                       origin_place_id: origin, content_core: content_core,
                       content_nl: content_nl}
      end

    ev = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :signal,
      payload: %{
        kind: :signal_emitted,
        ref: ref,
        emitted_by: emitted_by,
        origin_place_id: origin,
        signal_kind: kind,
        intensity: intensity,
        content_core: content_core,
        content_nl: content_nl,
        arrivals: Enum.map(arrivals, &arrival_payload/1)
      }
    }

    {:ok, [ev], Fold.fold(world, [ev])}
  end

  def arrival_payload(%Types.Arrival{} = a) do
    Map.take(a, [:ref, :place_id, :tick, :kind, :intensity, :about, :hops,
                 :origin_place_id, :content_core, :content_nl])
  end

  defp origin_place(world, emitted_by) do
    case World.agent(world, emitted_by) do
      %Types.Agent{place_id: p} -> p
      nil -> (world.hazards[emitted_by] || raise ArgumentError, "unknown emitter #{emitted_by}").place_id
    end
  end

  # Level-ordered BFS. Each frontier expansion is sorted by {place_id, edge_id};
  # first (earliest) arrival per place wins.
  defp propagate(world, origin, kind, intensity) do
    frontier = [{origin, intensity, 0}]
    visited = MapSet.new([origin])
    acc = [%{place_id: origin, tick: world.tick, intensity: intensity * 1.0, hops: 0}]

    {acc, _visited} =
      expand_levels(world, kind, frontier, visited, acc, world.tick)

    acc
  end

  defp expand_levels(_world, _kind, [], visited, acc, _t), do: {acc, visited}

  defp expand_levels(world, kind, frontier, visited, acc, t) do
    next_tick = t + @hop_delay

    next =
      frontier
      |> Enum.flat_map(fn {place, intensity, _hops} ->
        place
        |> neighbors(world, kind)
        |> Enum.map(fn {n_place, att, _edge_id} -> {n_place, intensity * att} end)
      end)
      |> Enum.filter(fn {_p, i} -> i >= @intensity_floor end)
      |> Enum.sort_by(fn {p, _i} -> p end)
      |> Enum.uniq_by(fn {p, _i} -> p end)
      |> Enum.reject(fn {p, _i} -> MapSet.member?(visited, p) end)

    next_acc =
      acc ++ (for {p, i} <- next, do: %{place_id: p, tick: next_tick, intensity: i,
                                        hops: div(next_tick - world.tick, @hop_delay)})

    expand_levels(world, kind, next, MapSet.union(visited, MapSet.new(Enum.map(next, &elem(&1, 0)))), next_acc, next_tick)
  end

  defp neighbors(place, world, kind) do
    world.edges
    |> Enum.filter(fn e -> (e.from == place or e.to == place) and not e.sealed end)
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn e ->
      other = if e.from == place, do: e.to, else: e.from
      perm = permeability_for(e, kind)
      {other, attenuation(perm, kind), e.id}
    end)
    |> Enum.reject(fn {_p, att, _e} -> att == nil end)
  end

  defp permeability_for(edge, kind) do
    Map.get(edge.permeability || %{}, kind, :muffled)
  end

  defp attenuation(:blocked, _kind), do: nil
  defp attenuation(perm, kind), do: get_in(@attenuation, [perm, kind])
end
```

In `fold.ex`: make `update_agent/3` public (`@spec update_agent(World.t(), String.t(), function()) :: World.t()`), and extend the `case kind do` block:

```elixir
      :signal_emitted ->
        arrivals =
          for a <- p.arrivals do
            struct!(EngineCore.Types.Arrival,
              ref: a.ref, place_id: a.place_id, tick: a.tick, kind: a.kind,
              intensity: a.intensity, about: a.about, hops: a.hops,
              origin_place_id: a.origin_place_id, content_core: a.content_core,
              content_nl: a.content_nl)
          end

        %{world |
          signal_seq: max(world.signal_seq, p.ref),
          in_flight: Enum.sort_by(world.in_flight ++ arrivals, &{&1.tick, &1.ref, &1.place_id})}

      :signal_arrived ->
        %{world |
          in_flight: Enum.reject(world.in_flight, fn a ->
            a.ref == p.ref and a.place_id == p.place_id
          end)}

      :signal_received ->
        entry = %{count: 0, last_tick: 0, last_fidelity: 0, seen: false, salience: 0.0}

        update_agent(world, p.agent_id, fn a ->
          current = get_in(a.beliefs, [p.place_id, p.about])
          merged =
            case current do
              nil -> %{entry | count: 1}
              c -> %{c | count: c.count + 1}
            end
          |> Map.merge(%{last_tick: p.tick, last_fidelity: p.fidelity,
                         salience: p.salience,
                         seen: (current && current.seen) || p.signal_kind == :sight})

          place_map = Map.put(a.beliefs[p.place_id] || %{}, p.about, merged)
          %{a | beliefs: Map.put(a.beliefs, p.place_id, place_map)}
        end)
```


- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/signals_test.exs apps/engine_core/test/fold_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/signals.ex \
        shards_engine/apps/engine_core/lib/engine_core/fold.ex \
        shards_engine/apps/engine_core/test/signals_test.exs \
        shards_engine/apps/engine_core/test/fold_test.exs
git commit -m "feat: signal emission with edge attenuation and in-flight arrival tracking"
```

---

### Task 4: Perception — fidelity ladder, salience, reception

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/perception.ex`
- Test: `shards_engine/apps/engine_core/test/perception_test.exs`

**Interfaces:**
- Consumes: `Types.Arrival`, `Types.Agent`, `Fold`, `Dice`.
- Produces: `base_fidelity/2`, `resolve_fidelity/3`, `salience/3`, `receive_arrival/3` — signatures per Shared Interfaces. Reception events: class `:signal`, payload `%{kind: :signal_received, agent_id, place_id, ref, about, signal_kind, intensity, fidelity, salience, roll}`.

Fidelity rules (decision 31): intensity ≥ 9 → tier 5; ≥ 7 → 4; ≥ 5 → 3; ≥ 3 → 2; else 1. Adjust: `hops ≥ 1` → −1; attention `:dormant` → −2; `int ≥ 16` → +1; `int ≤ 6` → −1. Clamp ≥ 0. Auto-high: intensity ≥ 9 → at least 3. Marginal (result ≤ 0, or result == 1 with intensity ≤ 3): d6 awareness — roll ≤ 2 → fidelity 1, else 0 (F0: honest nothing; no event). Salience: `intensity + (same_place ? 2 : 1) + (novel ? 2 : 0) + (threat ? 3 : 0)`, capped 10.

- [ ] **Step 1: Write the failing test:**

```elixir
defmodule EngineCore.PerceptionTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Dice, Fold, Perception, Types}

  defp arrival(intensity, opts \\ []) do
    struct!(Types.Arrival,
      ref: 1, place_id: "guard_room", tick: 5, kind: :sound,
      intensity: intensity, about: "pc1",
      hops: Keyword.get(opts, :hops, 0),
      origin_place_id: "entry_hall",
      content_core: %{class: :combat, threat: true, about: "pc1", count: 1})
  end

  defp agent(int, attention \\ :alert) do
    struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "guard_room")
    |> Map.put(:statblock, %{ac: 6, hd: 1, hp_max: 5, thac0: 20, morale: 7, int: int,
                             damage: %{dice: 1, sides: 6, plus: 0}})
    |> Map.put(:attention, attention)
  end

  test "base fidelity ladder and adjustments" do
    assert Perception.base_fidelity(arrival(9.5), agent(10)) == 5
    assert Perception.base_fidelity(arrival(7), agent(10)) == 4
    assert Perception.base_fidelity(arrival(5), agent(10)) == 3
    assert Perception.base_fidelity(arrival(3), agent(10)) == 2
    assert Perception.base_fidelity(arrival(1.5), agent(10)) == 1
    # adjacent room: -1
    assert Perception.base_fidelity(arrival(7, hops: 1), agent(10)) == 3
    # dormant guard: -2
    assert Perception.base_fidelity(arrival(7), agent(10, :dormant)) == 2
    # dim rat (int 1): -1
    assert Perception.base_fidelity(arrival(7), agent(1)) == 3
    # auto-high: deafening alarm is at least F3 for everyone
    assert Perception.base_fidelity(arrival(10, hops: 1), agent(1, :dormant)) == 3
  end

  test "marginal signals resolve by d6 awareness" do
    a = arrival(1.5)                       # base 1, marginal because intensity <= 3
    g = agent(10)
    rng = Dice.new(42)
    {f1, roll1, rng2} = Perception.resolve_fidelity(Perception.base_fidelity(a, g), a, rng)
    {f2, roll2, _} = Perception.resolve_fidelity(Perception.base_fidelity(a, g), a, rng2)
    assert is_nil(roll1) == false          # marginal: a roll happened
    assert f1 in 0..1 and f2 in 0..1
    # strong signal: no roll, direct
    {f3, roll3, _} = Perception.resolve_fidelity(4, arrival(8), Dice.new(1))
    assert f3 == 4 and roll3 == nil
  end

  test "salience scoring" do
    g = agent(10)
    w = %EngineCore.World{agents: %{"g1" => g}}
    a = arrival(7)
    # 7 + 2 (same place) + 2 (novel) + 3 (threat) = 14 -> cap 10
    assert Perception.salience(a, g, w) == 10
  end

  test "receive_arrival emits per-agent events, updates beliefs via fold" do
    g1 = agent(10)
    g2 = agent(10) |> Map.put(:id, "g2") |> Map.put(:attention, :dormant)
    dead = agent(10) |> Map.put(:id, "g3") |> Map.update!(:body, &%{&1 | hp: 0})
    w = %EngineCore.World{agents: %{"g1" => g1, "g2" => g2, "g3" => dead},
                          places: %{"guard_room" => %{}}, tick: 5}

    {:ok, events, w2, _rng} = Perception.receive_arrival(w, Dice.new(7), arrival(8))
    receivers = events |> Enum.map(& &1.payload.agent_id)
    assert receivers == Enum.sort(receivers)
    assert "g1" in receivers and "g2" in receivers and "g3" not in receivers
    assert Enum.all?(events, &(&1.class == :signal and &1.payload.kind == :signal_received))
    assert Fold.fold(w, events) == w2
    assert w2.agents["g1"].beliefs["guard_room"]["pc1"].count == 1
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/perception_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement `lib/engine_core/perception.ex`:**

```elixir
defmodule EngineCore.Perception do
  @moduledoc """
  Reception filters and belief formation (spec 6.1/6.2, decision 31).
  F0 is an honest omission: no event is emitted at all.
  """
  alias EngineCore.{Dice, Fold, Ledger, Types, World}

  @spec base_fidelity(Types.Arrival.t(), Types.Agent.t()) :: non_neg_integer()
  def base_fidelity(arrival, agent) do
    tier = cond do
      arrival.intensity >= 9 -> 5
      arrival.intensity >= 7 -> 4
      arrival.intensity >= 5 -> 3
      arrival.intensity >= 3 -> 2
      true -> 1
    end

    tier
    |> Kernel.-(if arrival.hops >= 1, do: 1, else: 0)
    |> Kernel.-(if agent.attention == :dormant, do: 2, else: 0)
    |> Kernel.+(if agent.statblock.int >= 16, do: 1, else: 0)
    |> Kernel.-(if agent.statblock.int <= 6, do: 1, else: 0)
    |> max(0)
    |> then(fn f -> if arrival.intensity >= 9, do: max(f, 3), else: f end)
  end

  @spec resolve_fidelity(non_neg_integer(), Types.Arrival.t(), :rand.state()) ::
          {non_neg_integer(), non_neg_integer() | nil, :rand.state()}
  def resolve_fidelity(base, arrival, rng) do
    if base <= 0 or (base == 1 and arrival.intensity <= 3) do
      {roll, rng2} = Dice.roll(rng, 6)
      {if(roll <= 2, do: 1, else: 0), roll, rng2}
    else
      {base, nil, rng}
    end
  end

  @spec salience(Types.Arrival.t(), Types.Agent.t(), World.t()) :: float()
  def salience(arrival, agent, world) do
    novel = get_in(agent.beliefs, [arrival.place_id, arrival.about]) == nil
    same = agent.place_id == arrival.place_id
    threat = arrival.content_core[:threat] == true

    (arrival.intensity + if(same, do: 2, else: 1) + if(novel, do: 2, else: 0) +
       if(threat, do: 3, else: 0))
    |> min(10)
    |> Float.round(1)
  end

  @spec receive_arrival(World.t(), :rand.state(), Types.Arrival.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def receive_arrival(world, rng, arrival) do
    receivers =
      world
      |> World.agents_in(arrival.place_id)
      |> Enum.reject(&(&1.body.hp == 0 or :dead in (&1.body.conditions || [])))
      |> Enum.sort_by(& &1.id)

    {events, rng2} =
      Enum.flat_map_reduce(receivers, rng, fn a, r ->
        base = base_fidelity(arrival, a)
        {f, roll, r2} = resolve_fidelity(base, arrival, r)

        if f <= 0 do
          {[], r2}
        else
          ev = %Ledger.Event{
            seq: 0, tick: arrival.tick, class: :signal,
            payload: %{
              kind: :signal_received, agent_id: a.id, place_id: arrival.place_id,
              ref: arrival.ref, about: arrival.about, signal_kind: arrival.kind,
              intensity: Float.round(arrival.intensity, 4), fidelity: f,
              salience: salience(arrival, a, world), roll: roll
            }
          }
          {[ev], r2}
        end
      end)

    {:ok, events, Fold.fold(world, events), rng2}
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/perception_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/perception.ex \
        shards_engine/apps/engine_core/test/perception_test.exs
git commit -m "feat: perception filters, fidelity ladder with d6 marginal, salience, beliefs"
```

---

### Task 5: Narrate — template rendering at fidelity tiers

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/narrate.ex`
- Test: `shards_engine/apps/engine_core/test/narrate_test.exs`

**Interfaces:**
- Consumes: `World` (edges with labels), Arrival-shaped maps.
- Produces: `render/3`, `direction/3` per Shared Interfaces. Pure; no ledger writes.

- [ ] **Step 1: Write the failing test:**

```elixir
defmodule EngineCore.NarrateTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Loader, Narrate}

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  defp view(kind, class, intensity, nl), do:
    %{kind: kind, intensity: intensity, content_nl: nl,
      content_core: %{class: class, threat: class == :combat, about: "pc1", count: 1}}

  test "fidelity tier ladder for sound" do
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 0, "east") == ""
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 1, nil) ==
           "You hear something."
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 2, nil) ==
           "You hear a sounds-of-fighting noise."
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 3, "east") ==
           "You hear a loud sounds-of-fighting noise to the east."
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 4, "east") ==
           "You hear the crash of steel to the east."
    out = Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 5, "east")
    assert String.starts_with?(out, "You hear the crash of steel to the east.")
    assert String.contains?(out, "something is wrong")
  end

  test "intensity words and unknown direction" do
    assert String.contains?(
             Narrate.render(view(:sound, :footsteps, 2, nil), 3, nil),
             "faint scraping-of-feet noise somewhere nearby")
    assert String.contains?(
             Narrate.render(view(:sound, :alarm, 10, "pots and pans crashing"), 3, nil),
             "deafening")
  end

  test "sight, smell, tremor openers" do
    assert Narrate.render(view(:sight, :movement, 5, nil), 1, nil) == "You glimpse movement."
    assert Narrate.render(view(:smell, :musk, 4, nil), 1, nil) == "You catch an odor."
    assert Narrate.render(view(:tremor, :footfall, 6, nil), 1, nil) == "You feel a vibration."
    assert Narrate.render(view(:sight, :movement, 6, "four small figures"), 4, "north") ==
           "You see four small figures to the north."
  end

  test "direction from edges over the real tower" do
    {:ok, w} = Loader.load(@yaml)
    assert Narrate.direction(w, "entry_hall", "guard_room") == "east"
    assert Narrate.direction(w, "guard_room", "entry_hall") == "west"
    assert Narrate.direction(w, "entry_hall", "chiefs_room") == "somewhere nearby"
    assert Narrate.direction(w, "entry_hall", "entry_hall") == "very close"
  end
end
```

(Check the guard_room→entry_hall exit label in the YAML — if the reverse exit key differs, e.g. `"west"`, pin the actual value; the test must reflect the real file.)

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/narrate_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/engine_core/narrate.ex`:**

```elixir
defmodule EngineCore.Narrate do
  @moduledoc """
  Template narration at fidelity tiers (decision 31). The LLM narrate class
  (Plan 3) swaps these templates out; facts stay engine-side.
  """

  @class_words %{
    sound: %{alarm: "clattering", combat: "sounds-of-fighting", footsteps: "scraping-of-feet",
             voices: "murmur-of-voices", metallic: "metallic-clinking"},
    sight: %{movement: "movement", figures: "figures"},
    smell: %{musk: "rank", smoke: "smoke", blood: "blood"},
    tremor: %{footfall: "heavy", collapse: "rumbling"}
  }

  @openers %{
    sound: {"You hear something.", "You hear"},
    sight: {"You glimpse movement.", "You see"},
    smell: {"You catch an odor.", "You smell"},
    tremor: {"You feel a vibration.", "You feel"}
  }

  @inferences %{
    combat: "something is wrong",
    alarm: "a trap has been sprung",
    stealth: "something is trying to be quiet"
  }

  @spec render(map, 0..5, String.t() | nil) :: String.t()
  def render(_view, 0, _dir), do: ""

  def render(view, fidelity, direction) do
    kind = view.kind
    dir = dir_phrase(direction)
    iw = intensity_word(view.intensity)
    cw = class_word(kind, view.content_core)
    {bare, verb} = @openers[kind]

    case fidelity do
      1 -> bare
      2 -> "#{verb} a #{cw} #{noun(kind)}."
      3 -> "#{verb} a #{iw} #{cw} #{noun(kind)} #{dir}."
      4 -> rich(view, verb, iw, cw, dir)
      5 -> rich(view, verb, iw, cw, dir) <> " — " <> inference(view)
    end
  end

  # F4: prefer the emitter's natural-language payload; fall back to the
  # class-word template when the arrival carried no prose.
  defp rich(%{content_nl: nil} = view, verb, iw, cw, _dir) do
    "#{verb} a #{iw} #{cw} #{noun(view.kind)}."
  end

  defp rich(view, verb, _iw, _cw, dir), do: "#{verb} #{view.content_nl} #{dir}."


  defp noun(:sound), do: "noise"
  defp noun(:sight), do: "movement"
  defp noun(:smell), do: "smell"
  defp noun(:tremor), do: "tremor"

  defp class_word(kind, cc) do
    Map.get(@class_words[kind] || %{}, Map.get(cc || %{}, :class, :unknown), "strange")
  end

  defp intensity_word(i) when i >= 9, do: "deafening"
  defp intensity_word(i) when i >= 7, do: "loud"
  defp intensity_word(i) when i >= 4, do: "distinct"
  defp intensity_word(_), do: "faint"

  defp dir_phrase(nil), do: "somewhere nearby"
  defp dir_phrase("very close"), do: "very close"
  defp dir_phrase(d), do: "to the #{d}"

  defp inference(view) do
    cc = view.content_core || %{}
    cond do
      Map.get(cc, :stealth) == true -> @inferences.stealth
      true -> Map.get(@inferences, Map.get(cc, :class, :none), @inferences.combat)
    end
  end

  @spec direction(EngineCore.World.t(), String.t(), String.t()) :: String.t()
  def direction(world, from, to) when from == to, do: "very close"

  def direction(world, from, to) do
    case Enum.find(world.edges, &(&1.from == from and &1.to == to and &1.label)) do
      %EngineCore.Types.Edge{label: label} -> label
      nil -> "somewhere nearby"
    end
  end
end
```


- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/narrate_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/narrate.ex \
        shards_engine/apps/engine_core/test/narrate_test.exs
git commit -m "feat: template narration at fidelity tiers F0-F5"
```

---

### Task 6: Commitments lifecycle

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/commitments.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/fold.ex`
- Test: `shards_engine/apps/engine_core/test/commitments_test.exs`

**Interfaces:**
- Consumes: Task 1 `Types.Commitment`, `Fold.update_agent/3`.
- Produces: `create/2`, `due/2`, `mark_due/3`, `keep/2`, `violate/2`, `renegotiate/3`; fold clauses for the five payload kinds.

- [ ] **Step 1: Write the failing test:**

```elixir
defmodule EngineCore.CommitmentsTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Commitments, Fold, Types}

  defp world_with(commitment) do
    a = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "guard_room")
    |> Map.put(:commitments, [commitment])
    %EngineCore.World{agents: %{"g1" => a}, tick: 10}
  end

  test "create adds a commitment through the ledger" do
    w = %EngineCore.World{tick: 5}
    {:ok, [ev], w2} =
      Commitments.create(w, id: "c1", debtor: "g1", deed: "keep_watch",
                         due: 30, every: 30, priority: 6)
    assert ev.class == :commitment and ev.payload.kind == :commitment_created
    assert [%Types.Commitment{id: "c1", status: :pending, priority: 6}] =
           w2.agents["g1"].commitments
    assert Fold.fold(w, [ev]) == w2
  end

  test "create with unknown debtor errors" do
    assert {:error, :no_debtor} =
           Commitments.create(%EngineCore.World{}, id: "x", debtor: "ghost", deed: "y")
  end

  test "due query returns pending commitments past the tick, priority-sorted" do
    w =
      world_with(%Types.Commitment{id: "low", debtor: "g1", deed: "a", due: 5, priority: 1})
      |> put_agent_commitment("g1", %Types.Commitment{id: "high", debtor: "g1", deed: "b",
                                                      due: 8, priority: 9})
      |> put_agent_commitment("g1", %Types.Commitment{id: "future", debtor: "g1", deed: "c",
                                                      due: 40, priority: 9})

    assert Enum.map(Commitments.due(w, 10), & &1.id) == ["high", "low"]
  end

  test "mark_due, keep re-arms recurring, violate" do
    w = world_with(%Types.Commitment{id: "c", debtor: "g1", deed: "a", due: 30, every: 30})
    {:ok, [ev_due], w2} = Commitments.mark_due(w, "c")
    assert ev_due.payload == %{kind: :commitment_due, id: "c", debtor: "g1", late_by: 0}
    assert w2.agents["g1"].commitments == [%Types.Commitment{id: "c", debtor: "g1",
      deed: "a", due: 30, every: 30, priority: 5, status: :due}]

    {:ok, [ev_keep], w3} = Commitments.keep(w2, "c")
    assert ev_keep.payload.rearm_due == 40   # world.tick 10 + every 30
    assert %{status: :pending, due: 40} = hd(w3.agents["g1"].commitments)

    {:ok, [_], w4} = Commitments.mark_due(w3, "c", late_by: 2)
    {:ok, [_], w5} = Commitments.violate(w4, "c")
    assert hd(w5.agents["g1"].commitments).status == :violated
    # every fold round-trips
    assert Fold.fold(w2, [ev_keep]) == w3
  end

  test "renegotiate moves the due date" do
    w = world_with(%Types.Commitment{id: "c", debtor: "g1", deed: "a", due: 30})
    {:ok, [ev], w2} = Commitments.renegotiate(w, "c", 99)
    assert ev.payload.kind == :commitment_renegotiated
    assert hd(w2.agents["g1"].commitments).due == 99
    assert hd(w2.agents["g1"].commitments).status == :pending
  end

  defp put_agent_commitment(w, id, c) do
    %{w | agents: Map.update!(w.agents, id, fn a -> %{a | commitments: a.commitments ++ [c]} end)}
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/commitments_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/engine_core/commitments.ex`:**

```elixir
defmodule EngineCore.Commitments do
  @moduledoc """
  Commitment lifecycle (spec 5.4, decision 30): an obligation exists only
  when the engine records it. Statuses: pending/due/kept/violated.
  """
  alias EngineCore.{Fold, Ledger, Types, World}

  @spec create(World.t(), keyword() | map()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_debtor}
  def create(world, attrs) do
    attrs = Map.new(attrs)
    debtor = attrs.debtor

    if World.agent(world, debtor) == nil,
      do: {:error, :no_debtor},
      else: {:ok, [created_event(world.tick, attrs)], Fold.fold(world, [created_event(world.tick, attrs)])}
  end

  @spec due(World.t(), integer()) :: [Types.Commitment.t()]
  def due(world, tick) do
    world.agents
    |> Map.values()
    |> Enum.flat_map(& &1.commitments)
    |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
    |> Enum.sort_by(&{-&1.priority, &1.debtor, &1.id})
  end

  @spec mark_due(World.t(), String.t(), integer()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def mark_due(world, id, late_by \\ 0) do
    with {:ok, c} <- find(world, id) do
      ev = event(world.tick, %{kind: :commitment_due, id: id, debtor: c.debtor,
                               late_by: late_by})
      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec keep(World.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def keep(world, id) do
    with {:ok, c} <- find(world, id) do
      rearm = if c.every, do: world.tick + c.every
      ev = event(world.tick, %{kind: :commitment_kept, id: id, debtor: c.debtor,
                               rearm_due: rearm})
      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec violate(World.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def violate(world, id) do
    with {:ok, c} <- find(world, id) do
      ev = event(world.tick, %{kind: :commitment_violated, id: id, debtor: c.debtor})
      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec renegotiate(World.t(), String.t(), integer()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def renegotiate(world, id, new_due) do
    with {:ok, c} <- find(world, id) do
      ev = event(world.tick, %{kind: :commitment_renegotiated, id: id, debtor: c.debtor,
                               due: new_due})
      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  defp find(world, id) do
    world.agents
    |> Map.values()
    |> Enum.find_value(nil, fn a -> Enum.find(a.commitments, &(&1.id == id)) end)
    |> case do
      nil -> {:error, :no_commitment}
      c -> {:ok, c}
    end
  end

  defp created_event(tick, attrs) do
    event(tick, %{kind: :commitment_created,
                  commitment: %{id: attrs.id, debtor: attrs.debtor,
                                creditor: attrs[:creditor], deed: attrs.deed,
                                due: attrs[:due], every: attrs[:every],
                                priority: Map.get(attrs, :priority, 5)}})
  end

  defp event(tick, payload),
    do: %Ledger.Event{seq: 0, tick: tick, class: :commitment, payload: payload}
end
```

Fold clauses (append to the case in `Fold.apply/2`):

```elixir
      :commitment_created ->
        c = struct!(EngineCore.Types.Commitment, Map.to_list(p.commitment))
        update_agent(world, p.commitment.debtor, fn a ->
          %{a | commitments: a.commitments ++ [c]}
        end)

      :commitment_due ->
        update_commitment(world, p.id, &%{&1 | status: :due})

      :commitment_kept ->
        update_commitment(world, p.id, fn c ->
          if p.rearm_due,
            do: %{c | status: :pending, due: p.rearm_due},
            else: %{c | status: :kept}
        end)

      :commitment_violated ->
        update_commitment(world, p.id, &%{&1 | status: :violated})

      :commitment_renegotiated ->
        update_commitment(world, p.id, &%{&1 | due: p.due, status: :pending})
```

with a private helper next to `update_agent`:

```elixir
  defp update_commitment(world, id, fun) do
    %{world | agents:
      Map.new(world.agents, fn {aid, a} ->
        {aid,
         %{a | commitments: Enum.map(a.commitments, fn c ->
           if c.id == id, do: fun.(c), else: c
         end)}}
      end)}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/commitments_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/commitments.ex \
        shards_engine/apps/engine_core/lib/engine_core/fold.ex \
        shards_engine/apps/engine_core/test/commitments_test.exs
git commit -m "feat: commitment lifecycle with recurring re-arm and ledger events"
```

---

### Task 7: Boundaries — triggers, wake/sleep, lazy catch-up

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/boundaries.ex`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/fold.ex`
- Test: `shards_engine/apps/engine_core/test/boundaries_test.exs`

**Interfaces:**
- Consumes: Task 1 `Types.Boundary`, `Fold`, `Commitments.mark_due/3` (catch-up).
- Produces: `evaluate/2` (input: one already-applied ledger event), `wake/4`, `sleep/2`, `catchup/2`, `sleep_ready?/2`; fold clauses `:boundary_wake` (state awake, `last_trigger_tick`, bound agents `attention: :alert` and `cadence.next_due = tick + 1` when cadence set), `:boundary_refresh` (`last_trigger_tick` only), `:boundary_sleep` (state dormant, bound agents `attention: :dormant`), `:boundary_catchup` (audit only).

Trigger semantics: `presence_crossing` — a `:move` event whose `to` or `from` is the scope place (place scope), or whose `to` is a place containing a bound member (group scope), mover not itself bound. `signal_arrived` — arrival event at the scope place (place scope) or at a place containing a bound member (group scope), with `intensity ≥ wake_on_intensity`. `commitment_due` — debtor ∈ bound agents. Triggers only matter while dormant for wake; while awake, matching triggers emit `:boundary_refresh`.

- [ ] **Step 1: Write the failing test:**

```elixir
defmodule EngineCore.BoundariesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Boundaries, Commitments, Fold, Ledger, Types}

  defp agent(id, place, opts \\ []) do
    struct!(Types.Agent, id: id, name: id, tier: opts[:tier] || 3, place_id: place)
    |> Map.put(:attention, Keyword.get(opts, :attention, :dormant))
    |> Map.put(:cadence, Keyword.get(opts, :cadence))
    |> Map.put(:commitments, Keyword.get(opts, :commitments, []))
  end

  defp world(boundaries, agents) do
    %EngineCore.World{agents: Map.new(agents, &{&1.id, &1}),
                      boundaries: Map.new(boundaries, &{&1.id, &1}),
                      places: %{"guard_room" => %{}, "entry_hall" => %{}}, tick: 20}
  end

  defp guard_zone(opts \\ []) do
    struct!(Types.Boundary, id: "gz", scope_place_id: "guard_room",
            bound_agent_ids: ["g1"], triggers: [:presence_crossing, :signal_arrived])
    |> Map.merge(Map.new(opts))
  end

  defp move_event(to), do:
    %Ledger.Event{seq: 1, tick: 20, class: :world,
                  payload: %{kind: :move, agent_id: "pc1", from: "entry_hall", to: to,
                             careful: false}}

  test "presence crossing wakes the zone and its agents" do
    g1 = agent("g1", "guard_room", cadence: %{every: 10, next_due: nil})
    w = world([guard_zone()], [g1, agent("pc1", "entry_hall", attention: :alert)])

    {:ok, events, w2} = Boundaries.evaluate(w, move_event("guard_room"))
    [wake] = Enum.filter(events, &(&1.payload.kind == :boundary_wake))
    assert wake.payload.id == "gz"
    assert wake.payload.reason == "presence_crossing by pc1"
    assert w2.boundaries["gz"].state == :awake
    assert w2.boundaries["gz"].last_trigger_tick == 20
    assert w2.agents["g1"].attention == :alert
    assert w2.agents["g1"].cadence.next_due == 21
    assert Fold.fold(w, events) == w2
  end

  test "signal arrival below intensity does not wake; at or above it does" do
    w = world([guard_zone(wake_on_intensity: 4)], [agent("g1", "guard_room")])
    weak = %Ledger.Event{seq: 1, tick: 20, class: :signal,
      payload: %{kind: :signal_arrived, ref: 1, place_id: "guard_room", tick: 20,
                 intensity: 3.0, signal_kind: :sound, about: "pc1"}}
    {:ok, [], w2} = Boundaries.evaluate(w, weak)
    assert w2.boundaries["gz"].state == :dormant

    loud = %Ledger.Event{seq: 2, tick: 20, class: :signal,
      payload: %{kind: :signal_arrived, ref: 2, place_id: "guard_room", tick: 20,
                 intensity: 6.3, signal_kind: :sound, about: "pc1"}}
    {:ok, events, _} = Boundaries.evaluate(w2, loud)
    assert Enum.any?(events, &(&1.payload.kind == :boundary_wake))
  end

  test "awake zones refresh instead of waking; movement by bound agents does not trigger" do
    awake = guard_zone(state: :awake, last_trigger_tick: 10)
    w = world([awake], [agent("g1", "guard_room")])
    {:ok, [refresh], _} = Boundaries.evaluate(w, move_event("guard_room"))
    assert refresh.payload.kind == :boundary_refresh

    {:ok, events2, _} =
      Boundaries.evaluate(w, %Ledger.Event{seq: 3, tick: 20, class: :world,
        payload: %{kind: :move, agent_id: "g1", from: "guard_room", to: "entry_hall",
                   careful: false}})
    assert events2 == []
  end

  test "group-scoped boundary wakes when a mover enters a member's place" do
    wolf_zone = struct!(Types.Boundary, id: "wz", scope_group: "wolf",
                        bound_agent_ids: ["wolf_1"], triggers: [:presence_crossing])
    w1 = agent("wolf_1", "beast_pen", tier: 2)
    w = world([wolf_zone], [w1, agent("pc1", "entry_hall", attention: :alert)])
    ev = %Ledger.Event{seq: 1, tick: 20, class: :world,
      payload: %{kind: :move, agent_id: "pc1", from: "guard_room", to: "beast_pen",
                 careful: false}}
    {:ok, events, w2} = Boundaries.evaluate(w, ev)
    assert Enum.any?(events, &(&1.payload.kind == :boundary_wake and &1.payload.id == "wz"))
    assert w2.agents["wolf_1"].attention == :alert
  end

  test "catchup fires overdue commitments with lateness, audited with provenance" do
    c = %Types.Commitment{id: "watch", debtor: "g1", deed: "keep_watch", due: 12}
    g1 = agent("g1", "guard_room", commitments: [c])
    w = world([guard_zone()], [g1]) |> Map.put(:tick, 20)

    {:ok, events, w2} = Boundaries.catchup(w, "gz")
    due_ev = Enum.find(events, &(&1.payload.kind == :commitment_due))
    assert due_ev.payload.late_by == 8
    audit = Enum.find(events, &(&1.payload.kind == :boundary_catchup))
    assert audit.payload.computed_at == 20
    assert audit.payload.note == "computed at wake, tick 20"
    assert w2.agents["g1"].commitments == [%{c | status: :due}]
    assert Fold.fold(w, events) == w2
  end

  test "sleep after sustained quiet; pending commitments hold sleep" do
    g1 = agent("g1", "guard_room")
    b = guard_zone(state: :awake, last_trigger_tick: 5, sleep_after: 40)
    w = world([b], [g1]) |> Map.put(:tick, 50)
    assert Boundaries.sleep_ready?(w, b) == true
    {:ok, [ev], w2} = Boundaries.sleep(w, "gz")
    assert ev.payload.kind == :boundary_sleep
    assert w2.boundaries["gz"].state == :dormant
    assert w2.agents["g1"].attention == :dormant

    busy = agent("g1", "guard_room",
                 commitments: [%Types.Commitment{id: "c", debtor: "g1", deed: "x", due: 45}])
    refute Boundaries.sleep_ready?(%{w | agents: %{"g1" => busy}}, b)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/boundaries_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/engine_core/boundaries.ex`:**

```elixir
defmodule EngineCore.Boundaries do
  @moduledoc """
  Boundary activation (spec 4.2/4.3, decision 25). Boundaries are dormant
  until a trigger fires; wake starts bound agents' cadences; sustained
  quiet sleeps. Lazy catch-up: overdue commitments of bound agents fire at
  wake with lateness, audited with provenance.
  """
  alias EngineCore.{Commitments, Fold, Ledger, Types, World}

  @spec evaluate(World.t(), Ledger.Event.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def evaluate(world, event) do
    world.boundaries
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.flat_map_reduce(world, fn b, w ->
      case trigger_for(w, b, event) do
        nil -> {[], w}
        reason ->
          if b.state == :dormant do
            {:ok, evs, w2} = wake(w, b.id, event.tick, reason)
            {evs, w2}
          else
            ev = refresh_event(w, b.id, event.tick)
            {[ev], Fold.fold(w, [ev])}
          end
      end
    end)
    |> then(fn {events, w} -> {:ok, events, w} end)
  end

  @spec wake(World.t(), String.t(), integer(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def wake(world, id, tick, reason) do
    b = Map.fetch!(world.boundaries, id)
    evs = [wake_event(world, b, tick, reason)]

    {:ok, evs, w2} =
      try do
        {:ok, evs, Fold.fold(world, evs)}
      rescue
        _ -> {:ok, evs, world}
      end

    catchup(w2, id, wake_events: evs)
  end

  @spec catchup(World.t(), String.t(), Keyword.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def catchup(world, id, opts \\ []) do
    b = Map.fetch!(world.boundaries, id)
    tick = world.tick

    overdue =
      world.agents
      |> Map.values()
      |> Enum.filter(&(&1.id in b.bound_agent_ids))
      |> Enum.flat_map(& &1.commitments)
      |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
      |> Enum.sort_by(& &1.id)

    {due_events, w2} =
      Enum.flat_map_reduce(overdue, world, fn c, w ->
        {:ok, evs, w2} = Commitments.mark_due(w, c.id, tick - c.due)
        {evs, w2}
      end)

    audit =
      if overdue != [] do
        earliest = overdue |> Enum.map(& &1.due) |> Enum.min()
        [%Ledger.Event{seq: 0, tick: tick, class: :meta,
          payload: %{kind: :boundary_catchup, id: id, computed_at: tick,
                     from_tick: earliest, to_tick: tick,
                     note: "computed at wake, tick #{tick}"}}]
      else
        []
      end

    {:ok, Keyword.get(opts, :wake_events, []) ++ due_events ++ audit, Fold.fold(w2, audit)}
  end

  @spec sleep(World.t(), String.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def sleep(world, id) do
    ev = %Ledger.Event{seq: 0, tick: world.tick, class: :meta,
      payload: %{kind: :boundary_sleep, id: id}}
    {:ok, [ev], Fold.fold(world, [ev])}
  end

  @spec sleep_ready?(World.t(), Types.Boundary.t()) :: boolean()
  def sleep_ready?(world, b) do
    b.state == :awake and b.last_trigger_tick != nil and
      world.tick - b.last_trigger_tick >= b.sleep_after and
      not pending_among?(world, b)
  end

  defp pending_among?(world, b) do
    world.agents
    |> Map.values()
    |> Enum.filter(&(&1.id in b.bound_agent_ids))
    |> Enum.any?(fn a ->
      Enum.any?(a.commitments, &(&1.status in [:pending, :due] and &1.due != nil and &1.due <= world.tick))
    end)
  end

  defp trigger_for(_world, b, %Ledger.Event{payload: %{kind: :move, agent_id: mover,
                                                       to: to, from: from}}) do
    if :presence_crossing in b.triggers and mover not in b.bound_agent_ids and
         place_in_scope?(b, to) or place_in_scope?(b, from) do
      "presence_crossing by #{mover}"
    end
  end

  defp trigger_for(world, b, %Ledger.Event{payload: %{kind: :signal_arrived,
                                                      place_id: p, intensity: i}}) do
    if :signal_arrived in b.triggers and i >= b.wake_on_intensity and
         place_in_scope?(world, b, p) do
      "signal_arrived intensity #{Float.round(i * 1.0, 2)}"
    end
  end

  defp trigger_for(_world, b, %Ledger.Event{payload: %{kind: :commitment_due, debtor: d}}) do
    if :commitment_due in b.triggers and d in b.bound_agent_ids,
      do: "commitment_due by #{d}"
  end

  defp trigger_for(_world, _b, _event), do: nil

  defp place_in_scope?(b, place) when is_map(b) and b.scope_place_id != nil,
    do: place == b.scope_place_id

  defp place_in_scope?(world, b, place) do
    cond do
      b.scope_place_id != nil -> place == b.scope_place_id
      true ->
        world.agents
        |> Map.values()
        |> Enum.any?(&(&1.id in b.bound_agent_ids and &1.place_id == place))
    end
  end

  defp wake_event(world, b, tick, reason) do
    %Ledger.Event{seq: 0, tick: tick, class: :meta,
      payload: %{kind: :boundary_wake, id: b.id, tick: tick, reason: reason,
                 bound_agent_ids: b.bound_agent_ids}}
  end

  defp refresh_event(_world, id, tick) do
    %Ledger.Event{seq: 0, tick: tick, class: :meta,
      payload: %{kind: :boundary_refresh, id: id, tick: tick}}
  end
end
```

Note on the sketch above — clean it while implementing (these are correctness requirements, not style): (1) `trigger_for/3`'s move clause must parenthesize the boolean: `(place_in_scope?(b, to) or place_in_scope?(b, from))` and the group-scope variant needs the `world` argument — unify to `place_in_scope?(world, b, place)` for both branches; (2) `wake/4` must NOT rescue — call `Fold.fold` directly and then `catchup(w2, id, wake_events: evs)`; (3) `catchup/3` returns `wake_events ++ due_events ++ audit` applied over `w2` — but the wake events must be applied to the ORIGINAL world before catchup runs; since `wake` already folded them into `w2`, `catchup` receives that state, so its return's world must equal `Fold.fold(original_world, all_events)`; the test asserts exactly that round-trip. Fold clauses:

```elixir
      :boundary_wake ->
        %{world | boundaries: Map.update!(world.boundaries, p.id, fn b ->
          %{b | state: :awake, last_trigger_tick: p.tick}
        end)}
        |> wake_agents(p)

      :boundary_refresh ->
        %{world | boundaries: Map.update!(world.boundaries, p.id, fn b ->
          %{b | last_trigger_tick: p.tick}
        end)}

      :boundary_sleep ->
        %{world | boundaries: Map.update!(world.boundaries, p.id, fn b ->
          %{b | state: :dormant}
        end)}
        |> sleep_agents(p)

      :boundary_catchup ->
        world
```

with private helpers in `fold.ex`:

```elixir
  defp wake_agents(world, p) do
    Enum.reduce(p.bound_agent_ids, world, fn id, w ->
      update_agent(w, id, fn a ->
        cadence =
          case a.cadence do
            %{every: _} = c -> %{c | next_due: max(a_last_next(c), p.tick + 1)}
            nil -> nil
          end
        %{a | attention: :alert, cadence: cadence}
      end)
    end)
  end

  defp a_last_next(%{next_due: nil}), do: 0
  defp a_last_next(%{next_due: n}) when is_integer(n), do: n

  defp sleep_agents(world, p) do
    Enum.reduce(p.bound_agent_ids, world, fn id, w ->
      update_agent(w, id, fn a -> %{a | attention: :dormant} end)
    end)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/boundaries_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/boundaries.ex \
        shards_engine/apps/engine_core/lib/engine_core/fold.ex \
        shards_engine/apps/engine_core/test/boundaries_test.exs
git commit -m "feat: boundary triggers, wake/sleep, lazy catch-up with provenance"
```

---

### Task 8: Cognition — tier 0 hazards, tier 1 reflex, tier 2 pack

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/cognition/hazard.ex`
- Create: `shards_engine/apps/engine_core/lib/engine_core/cognition/reflex.ex`
- Create: `shards_engine/apps/engine_core/lib/engine_core/cognition/pack.ex`
- Test: `shards_engine/apps/engine_core/test/cognition_test.exs`

**Interfaces:**
- Consumes: `Signals`, `Saves`, `Dice`, `Movement`, `Combat`, `Fold`, `World`.
- Produces:
  - `Cognition.Hazard.check_move(world, rng, move_payload) :: {:ok, [Event], World, rng2}` — for a `%{kind: :move, agent_id, from, to, careful}` payload: untriggered hazards bound to the crossed edge (`edge_id` matching the from→to edge) or to `from`/`to` places (only when the mover crosses in/out — a hazard on place `to` arms on arrival, one on `from` arms on departure). `careful: true` ⇒ `:hazard_avoided` event, no roll. Otherwise d20 `roll < dc` ⇒ trigger (`:hazard_triggered`): `:alarm` kind ⇒ `Signals.emit` at `signal_intensity` with `content_core: %{class: signal_class, threat: true, about: agent_id, count: 1}` and `content_nl` from the YAML trap description; `:damage` kind ⇒ dice damage on the mover (`:damage` + possible `:death` via the same rules as `Rules.Combat`) plus a `:combat`-class sound at intensity 6. `roll ≥ dc` ⇒ `:hazard_avoided`. Every path ledgered.
  - `Cognition.Hazard.check_presence(world, rng, agent_id)` — the skeleton pattern: when `agent_id` enters a place containing an awake tier-0 agent with `:strike`, that agent strikes the nearest intruder (sorted by id). Unaware/dormant ⇒ `{:ok, [], world, rng}`.
  - `Cognition.Reflex.decide(world, rng, agent) :: {:ok, [Event], World, rng2}` — rat table, in order: (1) `hp ≤ half hp_max` ⇒ flee (first sorted unsealed connection via `Movement.traverse`); (2) loud recent signal in beliefs (`last_tick == world.tick`, `last_fidelity ≥ 3`, salience ≥ 6) ⇒ flee; (3) intruder in same place (different `group`, alive) ⇒ `Combat.attack` nearest by id; (4) otherwise no events.
  - `Cognition.Pack.decide(world, rng, agent) :: {:ok, [Event], World, rng2}` — wolf drives, in order: (1) fear: `hp ≤ 40% of hp_max` ⇒ flee; (2) territory: intruders (alive, different group or `group == nil`, not `:dead`) in the agent's place ⇒ pack strike — attack nearest intruder by id; a packmate's fresh kill this tick does not double-swing (one attack per cadence tick per wolf); (3) otherwise no events.

- [ ] **Step 1: Write the failing test** (`test/cognition_test.exs`) covering: alarm trap triggers on careless crossing of the bound edge and emits a `:signal_emitted` with class `:alarm`; careful crossing avoids; d20-pinned trigger/no-trigger; damage trap deals dice damage with a ledgered roll; skeleton strikes an intruder entering its chamber; rat flees on loud belief; rat attacks intruder in place; wolf pack strikes intruders; wounded wolf flees. Use hand-built worlds modeled on the loader output (structs from Task 1) plus `Loader.load(@yaml)` where convenient. At minimum these cases:

```elixir
defmodule EngineCore.CognitionTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Cognition.Hazard, Cognition.Pack, Cognition.Reflex, Dice, Loader, Types}

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  defp move(from, to, careful), do:
    %{kind: :move, agent_id: "pc1", from: from, to: to, careful: careful}

  test "alarm tripwire on the bound edge: careless crossing triggers and broadcasts" do
    {:ok, w} = Loader.load(@yaml)
    w = put_pc(w, "entry_hall")
    {:ok, events, w2, _} = Hazard.check_move(w, Dice.new(3), move("entry_hall", "guard_room", false))

    if Enum.any?(events, &(&1.payload.kind == :hazard_triggered)) do
      assert Enum.any?(events, &(&1.payload.id == :alarm_tripwire or &1.payload.id == "alarm_tripwire"))
      emit = Enum.find(events, &(&1.payload.kind == :signal_emitted))
      assert emit.payload.content_core.class == :alarm
      assert Enum.any?(w2.in_flight, &(&1.place_id == "guard_room"))
      assert w2.hazards["alarm_tripwire"].triggered == true
    else
      assert Enum.any?(events, &(&1.payload.kind == :hazard_avoided))
    end
  end

  test "careful crossing always avoids" do
    {:ok, w} = Loader.load(@yaml)
    w = put_pc(w, "entry_hall")
    {:ok, events, _, _} = Hazard.check_move(w, Dice.new(3), move("entry_hall", "guard_room", true))
    assert Enum.all?(events, &(&1.payload.kind == :hazard_avoided))
  end

  test "skeleton pattern strikes intruders entering its chamber" do
    {:ok, w} = Loader.load(@yaml)
    w = w |> put_pc("library") |> wake_boundary("skeleton_sentinel")
    {:ok, events, _w2, _} = Hazard.check_presence(w, Dice.new(11), "pc1")
    # pc1 is in library, skeleton in ritual_chamber: no strike
    assert events == []

    w3 = w |> put_pc("ritual_chamber")
    {:ok, events3, _, _} = Hazard.check_presence(w3, Dice.new(11), "pc1")
    assert Enum.any?(events3, &(&1.payload.kind == :damage and &1.payload.target_id == "pc1"))
  end

  test "rat reflex: loud belief flees, intruder strikes" do
    {:ok, w} = Loader.load(@yaml)
    rat = w.agents["giant_rat_1"]
    loud_w = put_belief(w, "giant_rat_1", "library", "pc1",
                        %{count: 1, last_tick: w.tick, last_fidelity: 4, seen: false,
                          salience: 8.0})
    {:ok, events, _, _} = Reflex.decide(loud_w, Dice.new(5), rat)
    assert Enum.any?(events, &(&1.payload.kind == :move and &1.payload.agent_id == "giant_rat_1"))

    intruder_w = put_pc(w, "library")
    {:ok, events2, _, _} = Reflex.decide(intruder_w, Dice.new(5), rat)
    assert Enum.any?(events2, &(&1.payload.kind in [:damage] or
                                (&1.payload.kind == :to_hit)))
  end

  test "wolf pack strikes intruders in the pen; wounded wolf flees" do
    {:ok, w} = Loader.load(@yaml)
    wolf = w.agents["wolf_1"]
    pen_w = put_pc(w, "beast_pen")
    {:ok, events, _, _} = Pack.decide(pen_w, Dice.new(9), wolf)
    assert Enum.any?(events, &match?(%{kind: :to_hit, purpose: :to_hit}, &1.payload) or
                    Enum.any?(events, &(&1.payload.kind == :damage)))

    hurt = update_agent(w, "wolf_1", fn a ->
      %{a | body: %{a.body | hp: 2}}   # hp_max 16 -> 12.5% : fear
    end)
    {:ok, events2, _, _} = Pack.decide(hurt, Dice.new(9), hurt.agents["wolf_1"])
    assert Enum.any?(events2, &(&1.payload.kind == :move))
  end

  defp put_pc(w, place) do
    pc = struct!(Types.Agent, id: "pc1", name: "PC", tier: 3, place_id: place)
    %{w | agents: Map.put(w.agents, "pc1", pc)}
  end

  defp wake_boundary(w, id),
    do: %{w | boundaries: Map.update!(w.boundaries, id, &%{&1 | state: :awake})}

  defp put_belief(w, id, place, about, entry) do
    update_agent(w, id, fn a ->
      %{a | beliefs: Map.put(a.beliefs, place, %{about => entry})}
    end)
  end

  defp update_agent(w, id, fun),
    do: %{w | agents: Map.update!(w.agents, id, fun)}
end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/cognition_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the three modules.**

`cognition/hazard.ex`:

```elixir
defmodule EngineCore.Cognition.Hazard do
  @moduledoc "Tier 0: decision patterns keyed on trigger conditions (spec 5.1)."
  alias EngineCore.{Dice, Fold, Ledger, Rules, Signals, Types, World}

  @spec check_move(Types World.t(), :rand.state(), map()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def check_move(world, rng, %{kind: :move, agent_id: id, from: from, to: to,
                               careful: careful}) do
    crossed_edge = edge_id_between(world, from, to)

    candidates =
      world.hazards
      |> Map.values()
      |> Enum.filter(&(!&1.triggered))
      |> Enum.filter(&(&1.edge_id == nil or &1.edge_id == crossed_edge))
      |> Enum.filter(&(&1.place_id in [from, to]))
      |> Enum.sort_by(& &1.id)

    Enum.flat_map_reduce(candidates, rng, fn h, r ->
      if careful do
        ev = avoided_event(world, h)
        {[ev], Fold.fold(world, [ev]) |> elem(0) |> then(fn _ -> nil end) |> then(fn _ -> nil end)}
      else
        resolve_hazard(world, h, id, r)
      end
    end)
    # NOTE: the reduce above must accumulate {events, world, rng} — implement it as a
    # three-tuple reduce; the sketch shows shape only.
  end

  def check_move(world, rng, _), do: {:ok, [], world, rng}
```

The sketch above is intentionally corrected here — implement `check_move` as:

```elixir
  def check_move(world, rng, move) do
    crossed = edge_id_between(world, move.from, move.to)

    candidates =
      world.hazards
      |> Map.values()
      |> Enum.reject(& &1.triggered)
      |> Enum.filter(&(&1.edge_id == nil or &1.edge_id == crossed))
      |> Enum.filter(&(&1.place_id == move.from or &1.place_id == move.to))
      |> Enum.sort_by(& &1.id)

    {events, w2, r2} =
      Enum.reduce(candidates, {[], world, rng}, fn h, {evs, w, r} ->
        resolve(w, h, move, evs, r)
      end)

    {:ok, events, w2, r2}
  end

  defp resolve(world, h, %{careful: true, agent_id: id}, evs, r) do
    ev = meta_event(world, %{kind: :hazard_avoided, id: h.id, agent_id: id, how: :careful})
    {evs ++ [ev], Fold.fold(world, [ev]), r}
  end

  defp resolve(world, h, %{agent_id: id}, evs, r) do
    {roll, r2} = Dice.roll(r, 20)

    if roll < h.dc do
      ev_trig = meta_event(world, %{kind: :hazard_triggered, id: h.id, agent_id: id})
      w1 = Fold.fold(world, [ev_trig])
      {:ok, effect_evs, w2, r3} = apply_effect(w1, h, id, r2)
      {evs ++ [ev_trig | effect_evs], w2, r3}
    else
      ev = meta_event(world, %{kind: :hazard_avoided, id: h.id, agent_id: id, roll: roll})
      {evs ++ [ev], Fold.fold(world, [ev]), r2}
    end
  end

  defp apply_effect(world, %Types.Hazard{kind: :alarm} = h, id, r) do
    Signals.emit(world, h.id, :sound,
      %{class: h.signal_class, threat: true, about: id, count: 1},
      h.signal_intensity,
      "a wild clattering of pots and pans")
    |> then(fn {:ok, evs, w2} -> {:ok, evs, w2, r} end)
  end

  defp apply_effect(world, %Types.Hazard{kind: :damage} = h, id, r) do
    {rolls, r2} = Dice.roll(r, h.damage.sides, h.damage.dice)
    amount = Enum.sum(rolls) + h.damage.plus

    ev_dice = %Ledger.Event{seq: 0, tick: world.tick, class: :dice,
      payload: %{purpose: :hazard_damage, hazard_id: h.id, sides: h.damage.sides,
                 rolls: rolls, amount: amount, target_id: id}}

    ev_dmg = %Ledger.Event{seq: 0, tick: world.tick, class: :world,
      payload: %{kind: :damage, target_id: id, amount: amount}}

    {events, w2} =
      case World.agent(world, id) do
        %{body: %{hp: hp}} when hp - amount > 0 ->
          {[ev_dice, ev_dmg], Fold.fold(world, [ev_dice, ev_dmg])}
        _ ->
          ev_death = %Ledger.Event{seq: 0, tick: world.tick, class: :world,
            payload: %{kind: :death, agent_id: id}}
          {[ev_dice, ev_dmg, ev_death], Fold.fold(world, [ev_dice, ev_dmg, ev_death])}
      end

    {:ok, sig_events, w3} =
      Signals.emit(w2, h.id, :sound,
        %{class: :combat, threat: true, about: id, count: 1}, 6, "a cry of pain")

    {:ok, events ++ sig_events, w3, r2}
  end

  defp edge_id_between(world, from, to) do
    case Enum.find(world.edges, &(&1.from == from and &1.to == to)) do
      %Types.Edge{id: id} -> id
      nil -> nil
    end
  end

  defp meta_event(world, payload),
    do: %Ledger.Event{seq: 0, tick: world.tick, class: :meta, payload: payload}
end
```

`check_presence/3`: if the mover's `to` place hosts an awake tier-0 agent with `:strike` in capabilities and the mover is alive and not that agent, the hazard-agent strikes the nearest alive intruder (sorted by id) via `Rules.Combat.attack/4`; otherwise no events. On the loaded tower this is the skeleton (give it `:strike` — its capability list comes from `caps(0)` = `[:move, :strike, :wait]`, already true).

`cognition/reflex.ex` and `cognition/pack.ex` per the interface bullet: both return `{:ok, events, world, rng}` with events applied through `Fold.fold`; `Movement.traverse/4` provides flee moves (first sorted connection whose edge is unsealed); `Rules.Combat.attack/4` provides strikes.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/cognition_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/cognition \
        shards_engine/apps/engine_core/test/cognition_test.exs
git commit -m "feat: tier 0/1/2 cognition - hazard patterns, rat reflex, wolf pack drives"
```

---

### Task 9: Scheduler.advance — one tick of autonomous world time

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/scheduler.ex`
- Test: `shards_engine/apps/engine_core/test/scheduler_test.exs`

**Interfaces:**
- Consumes: Tasks 3–8 (`in_flight`, `Perception`, `Boundaries`, `Commitments`, `Cognition.*`).
- Produces: `advance/2` per Shared Interfaces. Within one tick, in fixed order: (1) `:tick_advance` to t+1; (2) arrivals due at t (sorted `{ref, place_id}`): each becomes a `:signal_arrived` event, then `Perception.receive_arrival`, then `Boundaries.evaluate` on the arrival event (wake may fire catch-up); then tier-1 reflex for receivers whose new belief entry has `last_fidelity ≥ 3` and `salience ≥ 6` (sorted by agent id); (3) commitments due (priority-sorted): `Commitments.mark_due` events + boundary evaluation; (4) cadences: alert agents with `cadence.next_due ≤ t`, sorted by id — tier 3 emits `:cadence_tick` `%{agent_id, due, next_due: due + every}`; tier 2 runs `Cognition.Pack.decide`; (5) boundaries where `sleep_ready?/2` emit `:boundary_sleep` (sorted by id). All events applied through `Fold.fold` once, in generation order. Every branch sorted — no map-order leakage.

- [ ] **Step 1: Write the failing test:**

```elixir
defmodule EngineCore.SchedulerTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Boundaries, Dice, Fold, Ledger, Loader, Perception, Scheduler,
                     Signals, Types}

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "advance processes due arrivals into receptions and wakes boundaries" do
    {:ok, w} = Loader.load(@yaml)
    # a deafening alarm lands in guard_room at tick 1
    {:ok, [emit], w1} =
      Signals.emit(%{w | tick: 0}, "alarm_tripwire", :sound,
        %{class: :alarm, threat: true, about: "pc1", count: 1}, 9,
        "pots and pans crashing")

    {:ok, events, w2, _rng} = Scheduler.advance(w1, Dice.new(21))

    assert Enum.any?(events, &(&1.payload.kind == :tick_advance))
    arrived = Enum.filter(events, &(&1.payload.kind == :signal_arrived))
    refute arrived == []

    gz_arrival = Enum.find(arrived, &(&1.payload.place_id == "guard_room"))
    if gz_arrival do
      assert Enum.any?(events, &(&1.payload.kind == :boundary_wake and
                                 &1.payload.id == "guard_room_zone"))
      assert w2.agents["goblin_guard_1"].attention == :alert
      assert w2.agents["goblin_guard_1"].cadence.next_due == 2
    end

    received = Enum.filter(events, &(&1.payload.kind == :signal_received))
    assert received != []
    assert Enum.all?(received, &(&1.payload.fidelity >= 1))
    assert Fold.fold(w1, events) == w2
  end

  test "advance fires due commitments and then sleeps quiet boundaries" do
    {:ok, w} = Loader.load(@yaml)
    # force the watch commitment due now and the zone awake but long-quiet
    w =
      %{w | tick: 130}
      |> Map.update!(:agents, fn agents ->
        Map.update!(agents, "goblin_guard_1", fn a ->
          %{a | commitments: [%Types.Commitment{id: "guard_watch_rotation",
            debtor: "goblin_guard_1", deed: "keep_watch", due: 30, every: 30,
            priority: 5}]}
        end)
      end)

    w2 = Map.update!(w.boundaries, "guard_room_zone", fn b ->
      %{b | state: :awake, last_trigger_tick: 10}
    end) |> then(&%{w | boundaries: &1, tick: 130})

    {:ok, events, w3, _} = Scheduler.advance(w2, Dice.new(2))
    assert Enum.any?(events, &(&1.payload.kind == :commitment_due and
                               &1.payload.id == "guard_watch_rotation"))
    # a still-due commitment holds sleep (pending_among? includes :due)
    assert w3.agents["goblin_guard_1"].commitments
           |> Enum.any?(&(&1.id == "guard_watch_rotation" and &1.status == :due))
  end

  test "advance runs wolf pack cadence against intruders" do
    {:ok, w} = Loader.load(@yaml)
    w = w
        |> Map.update!(:agents, fn a -> Map.put(a, "pc1",
            struct!(Types.Agent, id: "pc1", name: "PC", tier: 3, place_id: "beast_pen")) end)
        |> Map.update!(:boundaries, fn b ->
            Map.update!(b, "wolf_pack", fn z -> %{z | state: :awake} end) end)
        |> Map.update!(:agents, fn a ->
            Map.update!(a, "wolf_1", fn wolf ->
              %{wolf | attention: :alert, cadence: %{every: 5, next_due: 1}} end) end)

    {:ok, events, _w2, _} = Scheduler.advance(%{w | tick: 0}, Dice.new(4))
    assert Enum.any?(events, &(&1.payload.kind == :to_hit or &1.payload.kind == :damage))
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/scheduler_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/engine_core/scheduler.ex`** (advance only in this task; `react/3` lands in Task 10 — stub it as `def react(world, rng, _events), do: advance-noop` is FORBIDDEN; instead define only `advance/2` here and add `react/3` in Task 10):

```elixir
defmodule EngineCore.Scheduler do
  @moduledoc """
  Pure per-tick world motion (spec 7.1): arrivals, receptions, reflex,
  commitment dues, cadences, boundary sleep. The OTP Scheduler process
  and brains arrive in Plan 3; this module is the deterministic core.
  """
  alias EngineCore.{Boundaries, Cognition, Commitments, Fold, Ledger, Perception, Types, World}

  @reflex_fidelity 3
  @reflex_salience 6

  @spec advance(World.t(), :rand.state()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def advance(world, rng) do
    t = world.tick + 1
    tick_ev = tick_event(t)
    world = Fold.fold(world, [tick_ev])

    {a_events, world, rng} = arrivals_phase(world, rng, t)
    {c_events, world, rng} = commitments_phase(world, rng, t)
    {k_events, world, rng} = cadence_phase(world, rng, t)
    {s_events, world} = sleep_phase(world)

    {:ok, [tick_ev] ++ a_events ++ c_events ++ k_events ++ s_events, world, rng}
  end

  defp arrivals_phase(world, rng, t) do
    due = world.in_flight |> Enum.filter(&(&1.tick == t)) |> Enum.sort_by(&{&1.ref, &1.place_id})

    Enum.reduce(due, {[], world, rng}, fn arrival, {evs, w, r} ->
      ev = %Ledger.Event{seq: 0, tick: t, class: :signal,
        payload: %{kind: :signal_arrived, ref: arrival.ref, place_id: arrival.place_id,
                   tick: t, intensity: arrival.intensity, signal_kind: arrival.kind,
                   about: arrival.about}}
      w1 = Fold.fold(w, [ev])

      {:ok, recv_evs, w2, r2} = Perception.receive_arrival(w1, r, arrival)
      {:ok, b_evs, w3} = Boundaries.evaluate(w2, ev)
      {:ok, reflex_evs, w4, r3} = reflex_phase(w3, r2, arrival)

      {evs ++ [ev] ++ recv_evs ++ b_evs ++ reflex_evs, w4, r3}
    end)
  end

  defp reflex_phase(world, rng, arrival) do
    stimulated =
      world.agents
      |> Map.values()
      |> Enum.filter(&(&1.tier == 1 and &1.place_id == arrival.place_id))
      |> Enum.filter(fn a ->
        entry = get_in(a.beliefs, [arrival.place_id, arrival.about])
        entry != nil and entry.last_tick == world.tick and
          entry.last_fidelity >= @reflex_fidelity and entry.salience >= @reflex_salience
      end)
      |> Enum.sort_by(& &1.id)

    Enum.reduce(stimulated, {[], world, rng}, fn rat, {evs, w, r} ->
      {:ok, e, w2, r2} = Cognition.Reflex.decide(w, r, rat)
      {evs ++ e, w2, r2}
    end)
  end

  defp commitments_phase(world, rng, t) do
    Enum.reduce(Commitments.due(world, t), {[], world, rng}, fn c, {evs, w, r} ->
      {:ok, e, w2} = Commitments.mark_due(w, c.id)
      {:ok, b_evs, w3} = Boundaries.evaluate(w2, hd(e))
      {evs ++ e ++ b_evs, w3, r}
    end)
  end

  defp cadence_phase(world, rng, t) do
    due =
      world.agents
      |> Map.values()
      |> Enum.filter(&(&1.attention == :alert and &1.cadence != nil and
                       &1.cadence.next_due != nil and &1.cadence.next_due <= t))
      |> Enum.sort_by(& &1.id)

    Enum.reduce(due, {[], world, rng}, fn a, {evs, w, r} ->
      case a.tier do
        2 ->
          {:ok, e, w2, r2} = Cognition.Pack.decide(w, r, a)
          {evs ++ e, w2, r2}

        _ ->
          ev = %Ledger.Event{seq: 0, tick: t, class: :meta,
            payload: %{kind: :cadence_tick, agent_id: a.id, due: t,
                       next_due: t + a.cadence.every}}
          {evs ++ [ev], fold_cadence(w, ev), r}
      end
    end)
  end

  defp fold_cadence(world, ev) do
    Fold.update_agent(world, ev.payload.agent_id, fn a ->
      %{a | cadence: %{a.cadence | next_due: ev.payload.next_due}}
    end)
  end

  defp sleep_phase(world) do
    world.boundaries
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.filter(&Boundaries.sleep_ready?(world, &1))
    |> Enum.reduce({[], world}, fn b, {evs, w} ->
      {:ok, e, w2} = Boundaries.sleep(w, b.id)
      {evs ++ e, w2}
    end)
  end

  defp tick_event(t),
    do: %Ledger.Event{seq: 0, tick: t, class: :meta, payload: %{kind: :tick_advance, to: t}}
end
```

The cadence fold uses `Fold.update_agent` directly — also ADD a `:cadence_tick` fold clause performing the identical update so ledger replay reconstructs cadence state; keep both paths identical.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/scheduler_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/scheduler.ex \
        shards_engine/apps/engine_core/test/scheduler_test.exs \
        shards_engine/apps/engine_core/lib/engine_core/fold.ex
git commit -m "feat: deterministic scheduler tick - arrivals, dues, cadences, boundary sleep"
```

---

### Task 10: Scheduler.react — action side-effects bridge

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/scheduler.ex` (add `react/3`)
- Modify: `shards_engine/apps/engine_core/lib/engine_core/rules/movement.ex` (careful flag)
- Test: `shards_engine/apps/engine_core/test/scheduler_test.exs` (append), `test/movement_test.exs` (append)

**Interfaces:**
- Consumes: `Cognition.Hazard.check_move/3`, `Signals.emit/6`, `Boundaries.evaluate/2`, `Perception.receive_arrival/3`.
- Produces: `Movement.traverse/5` with opts `[careful: boolean]` (event payload gains `careful:`; default `false`; existing 4-arity callers compile via default arg); `Scheduler.react/3` per Shared Interfaces: (1) hazard checks for every `:move` event in the batch (in order); (2) side-effect signals — for each `:move`: `:footsteps` sound intensity 3 at destination; for each `:damage`: `:combat` sound intensity 7 at the target's place (`about` = attacker if known else target); (3) `Boundaries.evaluate` over each input event in order; (4) process arrivals now due (`tick ≤ world.tick`, sorted) through `Perception.receive_arrival` + boundary evaluation (this catches same-tick origin arrivals of just-emitted signals); no reflex here (cadence/reflex stay in `advance`). No recursion — a single react pass; generated `:signal_emitted` arrivals at future ticks wait for `advance`.

- [ ] **Step 1: Write the failing tests** — append to `scheduler_test.exs`:

```elixir
  test "react turns moves and damage into side-effect signals and boundary wakes" do
    {:ok, w} = Loader.load(@yaml)
    w = put_in(w.agents["pc1"], struct!(Types.Agent, id: "pc1", name: "PC", tier: 3,
                                        place_id: "library"))

    moves = [%Ledger.Event{seq: 1, tick: 0, class: :world,
      payload: %{kind: :move, agent_id: "pc1", from: "entry_hall", to: "library",
                 careful: false}}]
    w1 = Fold.fold(w, moves)

    {:ok, events, w2, _} = Scheduler.react(w1, Dice.new(17), moves)

    emits = Enum.filter(events, &(&1.payload.kind == :signal_emitted))
    assert Enum.any?(emits, &(&1.payload.signal_kind == :sound and
                              &1.payload.content_core.class == :footsteps))
    # rats in the library hear the arrival this tick
    assert Enum.any?(events, &(&1.payload.kind == :signal_received and
                               &1.payload.agent_id in ~w(giant_rat_1 giant_rat_2 giant_rat_3)))
    assert Fold.fold(w1, events) == w2
  end

  test "react runs hazard checks on careless moves" do
    {:ok, w} = Loader.load(@yaml)
    w = put_in(w.agents["pc1"], struct!(Types.Agent, id: "pc1", name: "PC", tier: 3,
                                        place_id: "entry_hall"))
    moves = [%Ledger.Event{seq: 1, tick: 0, class: :world,
      payload: %{kind: :move, agent_id: "pc1", from: "entry_hall", to: "guard_room",
                 careful: false}}]
    w1 = Fold.fold(w, moves)

    {:ok, events, _w2, _} = Scheduler.react(w1, Dice.new(17), moves)
    assert Enum.any?(events, &(&1.payload.kind in [:hazard_triggered, :hazard_avoided]))
  end
```

and to `movement_test.exs`:

```elixir
  test "careful flag rides the move event; default is false" do
    {:ok, w} = EngineCore.Loader.load(@yaml)
    {:ok, ev, _w2, _r} = EngineCore.Rules.Movement.traverse(w, EngineCore.Dice.new(1),
                                                            "goblin_guard_1", "entry_hall")
    assert ev.payload.careful == false
    {:ok, ev2, _w3, _r2} = EngineCore.Rules.Movement.traverse(w, EngineCore.Dice.new(1),
                                                              "goblin_guard_1", "entry_hall",
                                                              careful: true)
    assert ev2.payload.careful == true
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/scheduler_test.exs apps/engine_core/test/movement_test.exs`
Expected: FAIL — `Scheduler.react/3` undefined; move payload has no `careful`.

- [ ] **Step 3: Implement.** `rules/movement.ex`: change the signature to `traverse(world, rng, agent_id, to, opts \\ [])`, read `careful = Keyword.get(opts, :careful, false)`, and add `careful: careful` to the move payload (nothing else changes). In `scheduler.ex` add:

```elixir
  @doc """
  The 6.4 bridge: applied actions emit signals; hazards arm on crossing;
  boundaries re-evaluate. Call after any action batch leaves the rules
  modules. One pass, no recursion.
  """
  @spec react(World.t(), :rand.state(), [Ledger.Event.t()]) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def react(world, rng, events) do
    moves = Enum.filter(events, &(&1.payload.kind == :move))
    damages = Enum.filter(events, &(&1.payload.kind == :damage))

    {h_events, world, rng} = hazard_phase(world, rng, moves)
    {s_events, world} = side_effect_phase(world, moves, damages)
    {b_events, world} = boundary_phase(world, events)
    {a_events, world, rng} = due_arrivals_phase(world, rng)

    {:ok, h_events ++ s_events ++ b_events ++ a_events, world, rng}
  end

  defp hazard_phase(world, rng, moves) do
    Enum.reduce(moves, {[], world, rng}, fn mv, {evs, w, r} ->
      {:ok, e, w2, r2} = Cognition.Hazard.check_move(w, r, mv.payload)
      {evs ++ e, w2, r2}
    end)
  end

  defp side_effect_phase(world, moves, damages) do
    emissions =
      Enum.map(moves, fn mv ->
        {:footsteps, mv.payload.to, mv.payload.agent_id, 3, "soft footsteps"}
      end) ++
      Enum.map(damages, fn dm ->
        {:combat, place_of_agent(world, dm.payload.target_id), dm.payload.target_id, 7,
         "the sounds of violent blows"}
      end)

    Enum.reduce(emissions, {[], world}, fn {class, place, about, intensity, nl}, {evs, w} ->
      emit_at(w, place, about, class, intensity, nl, evs)
    end)
  end

  defp emit_at(w, place, about, class, intensity, nl, evs) do
    # Signals.emit resolves place from an agent id; for place-based emission
    # use a helper that seeds a temporary agent lookup — implement
    # Signals.emit_at/6 in signals.ex: same as emit/6 but takes the origin
    # place directly. Keep both public.
    {:ok, e, w2} = Signals.emit_at(w, place, about, :sound,
      %{class: class, threat: class == :combat, about: about, count: 1}, intensity, nl)
    {evs ++ e, w2}
  end

  defp boundary_phase(world, events) do
    Enum.reduce(events, {[], world}, fn ev, {evs, w} ->
      {:ok, e, w2} = Boundaries.evaluate(w, ev)
      {evs ++ e, w2}
    end)
  end

  defp due_arrivals_phase(world, rng) do
    due =
      world.in_flight
      |> Enum.filter(&(&1.tick <= world.tick))
      |> Enum.sort_by(&{&1.ref, &1.place_id})

    Enum.reduce(due, {[], world, rng}, fn arrival, {evs, w, r} ->
      ev = arrival_event(arrival)
      w1 = Fold.fold(w, [ev])
      {:ok, recv_evs, w2, r2} = Perception.receive_arrival(w1, r, arrival)
      {:ok, b_evs, w3} = Boundaries.evaluate(w2, ev)
      {evs ++ [ev] ++ recv_evs ++ b_evs, w3, r2}
    end)
  end
```

Refactor note: `Scheduler.advance`'s arrivals phase and this `due_arrivals_phase` share logic — extract `process_arrival(world, rng, arrival, tick)` used by both; `advance` uses `arrival.tick == t`, `react` uses `arrival.tick <= world.tick`. Add `Signals.emit_at/7` to `signals.ex` (origin place explicit; `emit/6` becomes a thin wrapper resolving the emitter's place then calling `emit_at`).

- [ ] **Step 4: Run tests to verify they pass; full suite green**

Run: `cd shards_engine && mix test apps/engine_core/test/scheduler_test.exs apps/engine_core/test/movement_test.exs && mix test`
Expected: PASS, full suite PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/scheduler.ex \
        shards_engine/apps/engine_core/lib/engine_core/signals.ex \
        shards_engine/apps/engine_core/lib/engine_core/rules/movement.ex \
        shards_engine/apps/engine_core/test/scheduler_test.exs \
        shards_engine/apps/engine_core/test/movement_test.exs
git commit -m "feat: scheduler react bridge - action side-effect signals and hazard triggers"
```

---

### Task 11: Alarm-cascade scenario + golden replay + CLI smoke

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/scenario.ex`
- Test: `shards_engine/apps/engine_core/test/cascade_replay_test.exs`
- Modify: `shards_engine/automated-run.sh` (add `cascade` mode)

**Interfaces:**
- Consumes: everything above.
- Produces: `Scenario.alarm_cascade/2` per Shared Interfaces.

Scenario script (deterministic, seed-driven): load tower; add the Plan-1 party at `entry_hall`; **beat 1** — pc1 crosses east to guard_room carelessly (`Movement.traverse` + `Scheduler.react`): the alarm tripwire may trigger (d20 vs dc 12); **beat 2** — run `Scheduler.advance` until 6 ticks pass or no events fire twice in a row (alarm propagates, guard zone wakes, cadences start); **beat 3** — scripted tier-3 stand-in (brains are Plan 3): alert, alive goblin guards walk the sorted BFS path from guard_room to the alarm origin and strike the party there (`Movement.traverse` + `Combat.attack`, with `Scheduler.react` after each batch); **beat 4** — up to 12 more `advance` ticks (melee noise propagates; `chiefs_room_zone` may wake two hops away — the full cascade). Wolves and skeleton must remain untouched by this script (dormancy proof). Helper `quiet_advance/3` stops early when `advance` returns `[]` twice consecutively.

- [ ] **Step 1: Write the failing test** — `test/cascade_replay_test.exs`:

```elixir
defmodule EngineCore.CascadeReplayTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Loader, Scenario}

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @tag :golden
  test "same seed replays byte-identically; different seeds diverge" do
    a = Scenario.alarm_cascade(@yaml, 1234)
    b = Scenario.alarm_cascade(@yaml, 1234)
    c = Scenario.alarm_cascade(@yaml, 99)

    assert :erlang.term_to_binary(a.ledger) == :erlang.term_to_binary(b.ledger)
    assert :erlang.term_to_binary(a.ledger) != :erlang.term_to_binary(c.ledger)
  end

  @tag :golden
  test "fold reconstructs the final world from the ledger alone" do
    {:ok, seed} = Loader.load(@yaml)
    r = Scenario.alarm_cascade(@yaml, 1234)
    rebuilt = Fold.fold(Scenario.add_party(seed), Enum.map(r.ledger, &drop_seq/1))
    assert rebuilt.tick == r.final_world.tick
    assert rebuilt.agents == r.final_world.agents
    assert rebuilt.boundaries == r.final_world.boundaries
    assert rebuilt.in_flight == r.final_world.in_flight
  end

  test "the cascade machinery fires and dormancy holds where nothing happened" do
    r = Scenario.alarm_cascade(@yaml, 1234)
    kinds = r.ledger |> Enum.map(& &1.payload.kind)

    triggered = :hazard_triggered in kinds

    if triggered do
      assert :signal_emitted in kinds and :signal_arrived in kinds and
             :signal_received in kinds
      assert :boundary_wake in kinds
      # the guard zone woke because of the alarm or the intrusion
      gz = r.final_world.boundaries["guard_room_zone"]
      assert gz.state == :awake or gz.last_trigger_tick != nil
    else
      assert :hazard_avoided in kinds
    end

    # wolves and skeleton stay dormant: the party never went there
    assert r.final_world.boundaries["wolf_pack"].state == :dormant
    assert r.final_world.boundaries["skeleton_sentinel"].state == :dormant
    assert r.final_world.agents["wolf_1"].attention == :dormant
  end

  defp drop_seq(ev), do: %{ev | seq: 0}
end
```

(The ledger's `seq` values are assigned at append time and replay folds ignore them; dropping them makes the reconstruct assertion robust. If `Scenario.alarm_cascade` returns ledgers whose `seq` starts at 1, `drop_seq/1` normalizes.)

- [ ] **Step 2: Run to verify failure**

Run: `cd shards_engine && mix test apps/engine_core/test/cascade_replay_test.exs`
Expected: FAIL — `Scenario.alarm_cascade/2` undefined.

- [ ] **Step 3: Implement in `scenario.ex`:**

```elixir
  @doc """
  The alarm cascade (spec 12.4 phases 3-4 gate): party trips the entry-hall
  alarm; signals propagate; the guard zone wakes; scripted guards respond
  (tier-3 stand-in until Plan-3 brains); melee noise wakes deeper zones.
  Wolves and skeleton stay dormant — dormancy is load-bearing.
  """
  def alarm_cascade(yaml_path, seed) do
    {:ok, world} = Loader.load(yaml_path)
    rng = Dice.new(seed)
    ledger = start_ledger!()
    world = add_party(world)

    # Beat 1: pc1 crosses the trapped east passage carelessly.
    {world, rng} = step(world, rng, ledger, Movement.traverse(world, rng, "pc1", "guard_room"))

    # Beat 2: the world reacts on its own clock.
    {world, rng} = quiet_advance(world, rng, ledger, 6)

    # Beat 3: scripted guard response (brains arrive in Plan 3).
    {world, rng} = guards_investigate(world, rng, ledger)

    # Beat 4: let the aftermath propagate (chiefs_room may wake).
    {world, rng} = quiet_advance(world, rng, ledger, 12)

    %{ledger: Ledger.events(ledger), final_world: world}
  end

  defp step(world, rng, _ledger, {:ok, events, w2, r2}) when is_list(events),
    do: apply_and_react(world, w2, r2, events)
  defp step(world, rng, _ledger, {:ok, event, w2, r2}),
    do: apply_and_react(world, w2, r2, [event])
  defp step(world, rng, _ledger, _), do: {world, rng}

  defp apply_and_react(_world_before, w2, r2, events) do
    w2 = w2  # events already applied by the rule module
    {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, events)
    {w3, r3, reaction}
  end

  # quiet_advance/4: advance up to n ticks; stop after two consecutive
  # event-less ticks. Appends every event to the ledger.
  defp quiet_advance(world, rng, _ledger, 0), do: {world, rng}

  defp quiet_advance(world, rng, ledger, n) do
    {:ok, events, w2, r2} = Scheduler.advance(world, rng)
    Enum.each(events, &Ledger.append(ledger, &1.class, &1.tick, &1.payload))

    if events == [] do
      {world2, rng2} = quiet_advance(w2, r2, ledger, n - 1, :quiet)
      {world2, rng2}
    else
      quiet_advance(w2, r2, ledger, n - 1)
    end
  end

  defp quiet_advance(world, rng, _ledger, n, :quiet) when n <= 1, do: {world, rng}

  defp quiet_advance(world, rng, ledger, n, :quiet) do
    {:ok, events, w2, r2} = Scheduler.advance(world, rng)
    Enum.each(events, &Ledger.append(ledger, &1.class, &1.tick, &1.payload))

    if events == [] do
      {world, rng}
    else
      quiet_advance(w2, r2, ledger, n - 1)
    end
  end

  # guards_investigate/3: every alert, alive guard_room goblin walks the
  # sorted BFS path toward the alarm origin (entry_hall) and fights.
  defp guards_investigate(world, rng, ledger) do
    guards =
      world.agents
      |> Map.values()
      |> Enum.filter(&String.starts_with?(&1.id, "goblin_guard_"))
      |> Enum.filter(&(&1.attention == :alert and &1.body.hp > 0))
      |> Enum.sort_by(& &1.id)

    Enum.reduce(guards, {world, rng}, fn g, {w, r} ->
      w = maybe_walk(w, r, g) |> elem(0)
      fight(w, r, ledger, g.id)
    end)
  end

  defp maybe_walk(world, rng, g) do
    if g.place_id != "entry_hall" do
      case path_to(world, g.place_id, "entry_hall") do
        [next | _] ->
          case Movement.traverse(world, rng, g.id, next) do
            {:ok, ev, w2, r2} ->
              {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, [ev])
              {w3, r3, [ev] ++ reaction}
            _ -> {world, rng, []}
          end
        [] -> {world, rng, []}
      end
    else
      {world, rng, []}
    end
  end

  defp fight(world, rng, _ledger, guard_id) do
    # up to 3 swings at the nearest alive pc in the same place
    fight_loop(world, rng, guard_id, 3)
  end

  defp fight_loop(world, rng, _id, 0), do: {world, rng}

  defp fight_loop(world, rng, id, n) do
    g = World.agent(world, id)

    pcs =
      world
      |> World.agents_in(g.place_id)
      |> Enum.filter(&String.starts_with?(&1.id, "pc"))
      |> Enum.filter(&(&1.body.hp > 0))
      |> Enum.sort_by(& &1.id)

    case pcs do
      [] ->
        {world, rng}

      [target | _] ->
        case Combat.attack(world, rng, id, target.id) do
          {:ok, events, w2, r2} ->
            {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, events)
            fight_loop(w3, r3, id, n - 1)
          {:error, _} -> {world, rng}
        end
    end
  end

  defp path_to(world, from, to) do
    # sorted BFS over unsealed connections; returns the place sequence
    bfs([{from, []}], world, MapSet.new([from]), to)
  end

  defp bfs([{place, path} | _], _world, _seen, to) when place == to,
    do: Enum.reverse([place | path])

  defp bfs([{place, path} | rest], world, seen, to) do
    nexts =
      (World.place(world, place).connections || [])
      |> Enum.sort()
      |> Enum.reject(&MapSet.member?(seen, &1))

    bfs(rest ++ Enum.map(nexts, &{&1, [place | path]}), world,
        MapSet.union(seen, MapSet.new(nexts)), to)
  end

  defp bfs([], _world, _seen, _to), do: []
end
```

Every event the scenario generates must also be appended to the ledger (mirror `apply_and_react`'s reaction events and quiet_advance's appends; pass the ledger through `guards_investigate`'s walk/fight helpers and append there too). The golden test is the proof: if an event mutated the world but missed the ledger, `fold reconstruct` fails. Simplify the sketch freely — but every world-mutating event MUST be appended.

- [ ] **Step 4: Run tests to verify they pass; full suite green**

Run: `cd shards_engine && mix test apps/engine_core/test/cascade_replay_test.exs && mix test`
Expected: golden tests PASS (byte-identical replay, divergence on seed change, fold reconstruction), dormancy assertions PASS, full suite PASS.

- [ ] **Step 5: CLI smoke (spec §12.4 phase 3–4 gate)**

Run:

```bash
cd shards_engine && mix run -e '
{:ok, w} = EngineCore.Loader.load("../the-ruined-tower/ruined_tower.yaml")
IO.puts("boundaries=#{map_size(w.boundaries)} hazards=#{map_size(w.hazards)}")
r = EngineCore.Scenario.alarm_cascade("../the-ruined-tower/ruined_tower.yaml", 1234)
kinds = Enum.frequencies(Enum.map(r.ledger, & &1.payload.kind))
IO.inspect(kinds, label: "event kinds")
IO.puts("ticks=#{r.final_world.tick} wolves=#{r.final_world.agents["wolf_1"].attention}")
'
```

Expected: prints boundary/hazard counts, a kind frequency map including signal/boundary machinery (or `hazard_avoided` for this seed), and `wolves=dormant`; exit 0.

- [ ] **Step 6: Add `cascade` mode to `automated-run.sh`** following the existing `fight()` pattern:

```bash
cascade() { elixir <<'ELIXIR'
seed = String.to_integer(System.get_env("SEED"))
yaml = System.get_env("YAML")
r = EngineCore.Scenario.alarm_cascade(yaml, seed)
kinds = Enum.frequencies(Enum.map(r.ledger, & &1.payload.kind))
IO.puts("=== ALARM CASCADE — seed #{seed} ===")
IO.inspect(kinds, label: "event kinds")
IO.puts("final tick: #{r.final_world.tick}")
IO.puts("guard zone: #{r.final_world.boundaries["guard_room_zone"].state}")
IO.puts("wolf pack:  #{r.final_world.boundaries["wolf_pack"].state} (dormancy proof)")
ELIXIR
}
```

Wire `cascade` into the usage text, the argument dispatch, and the `all` mode. Verify: `cd shards_engine && ./automated-run.sh cascade 1234` exits 0.

- [ ] **Step 7: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/scenario.ex \
        shards_engine/apps/engine_core/test/cascade_replay_test.exs \
        shards_engine/automated-run.sh
git commit -m "feat: alarm-cascade scenario proving signal/scheduler/boundary machinery end-to-end"
```

---

## Plan 2 Acceptance (maps to spec §12.4 phases 3–4)

- `mix test` green across all test files, offline.
- Signals: emission → attenuated edge propagation → per-agent fidelity reception → beliefs — all visible as `:signal` events in the ledger; `Narrate.render` covers F0–F5.
- Boundaries: place- and group-scoped zones wake on presence/signal/commitment triggers (never `coarse_tick` on groups), refresh on activity, sleep after sustained quiet; catch-up fires overdue commitments with lateness and provenance.
- Scheduler: `advance/2` moves the world one tick autonomously; `react/3` converts applied actions into side-effect signals and hazard triggers.
- Cognition: tier-0 hazards (alarm + damage + skeleton pattern), tier-1 rat reflex, tier-2 wolf pack — all deterministic, all through rules modules.
- Golden proof: `Scenario.alarm_cascade/2` — same seed byte-identical ledger, different seed diverges, `Fold.fold` reconstructs the final world from the ledger alone, untouched zones stay dormant.
- `grep -rn "DateTime\|NaiveDateTime\|System.time\|:os.time" shards_engine/apps/engine_core/lib` returns nothing.

## Next Plans

- **Plan 3** (spec §12.4 phases 5–8): `llm_gateway` chokepoint, referee pipeline stages, tier-3 brains + salience gate, envelopes/adoption, Phoenix channels + terminal client, acceptance harness with fork-diff. The `:cadence_tick` events this plan emits are the plug-in point for deliberation.
