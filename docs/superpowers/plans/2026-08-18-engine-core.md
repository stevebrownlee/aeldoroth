# Agent Engine — Plan 1: Deterministic Engine Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `engine_core`, the zero-LLM deterministic heart of the Shards agent engine: load The Ruined Tower from YAML, run an append-only event ledger, derive world state by folding, and resolve scripted AD&D 1E movement/combat/morale/saves headlessly with byte-identical replay.

**Architecture:** One umbrella app (`engine_core`) under `shards_engine/`. World state = deterministic `fold(ledger)`; every mutation is a data event; dice come only from a seeded RNG passed explicitly through call chains. No process holds authority state except the single Ledger GenServer; no wall-clock anywhere.

**Tech Stack:** Elixir ≥ 1.17 / OTP ≥ 27, Mix umbrella, ExUnit, `yaml_elixir` (only allowed dep).

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` — this plan implements §12.4 phases 1–2.

## Global Constraints

- Engine lives at `shards_engine/` (umbrella); core app at `shards_engine/apps/engine_core/`.
- `engine_core` dependencies: `yaml_elixir` ONLY. Phoenix, HTTP clients, LLM clients, Jason: FORBIDDEN in `engine_core`.
- No wall-clock: `DateTime`, `NaiveDateTime`, `:os.time`, `System.time` FORBIDDEN in `engine_core` lib. Ticks are monotonically increasing integers.
- All events are pure data (maps/structs of scalars, lists, atoms) — serializable via `:erlang.term_to_binary/1`.
- Dice rolls only via `EngineCore.Dice` with explicit RNG state threaded through (`{value, new_rng}` return convention).
- Determinism: same YAML + same seed + same action script ⇒ byte-identical ledger. Enforced by Task 11's golden test.
- Tests: ExUnit, offline, no network. Run from `shards_engine/`: `mix test`.
- Commit style: conventional (`feat:`, `fix:`, `test:`, `chore:`, `refactor:`), one logical change per commit.
- Engrams patterns to honor: `append-only-ledger` (10), `llm-proposes-engine-disposes` (8, as "no LLM here yet — verbs only"), `brains-hold-no-authority-state` (9).

## File Structure

```
shards_engine/                          # Mix umbrella
├── mix.exs
└── apps/
    └── engine_core/
        ├── mix.exs
        └── lib/
            ├── engine_core.ex              # defmodule + moduledoc only
            ├── types.ex                    # Place, Edge, Agent, Item, Action structs
            ├── world.ex                    # World struct + query helpers
            ├── validator.ex                # YAML integrity validator (Task 3)
            ├── loader.ex                   # YAML → World (Task 4)
            ├── ledger.ex                   # Event struct + append-only GenServer (Task 5)
            ├── fold.ex                     # event → state reducer (Task 6)
            ├── dice.ex                     # seeded pure RNG (Task 7)
            ├── scenario.ex                 # scripted combat + replay proof (Task 11)
            └── rules/
                ├── movement.ex             # edge traversal (Task 8)
                ├── combat.ex               # initiative, to-hit, damage (Task 9)
                ├── morale.ex               # morale checks (Task 10)
                └── saves.ex                # 1E save resolution (Task 10)
        └── test/
            ├── types_test.exs
            ├── validator_test.exs
            ├── loader_test.exs
            ├── ledger_test.exs
            ├── fold_test.exs
            ├── dice_test.exs
            ├── movement_test.exs
            ├── combat_test.exs
            ├── morale_test.exs
            ├── saves_test.exs
            └── golden_replay_test.exs      # Task 11
the-ruined-tower/ruined_tower.yaml      # repaired in place (Task 3)
```

Shared type signatures (tasks reference these; "Interfaces" blocks restate what matters):

- `EngineCore.Types` — nested structs: `%Types.Place{id, name, kind, connections}`, `%Types.Edge{id, from, to, sealed, permeability}`, `%Types.Agent{id, name, tier, place_id, statblock, body, capabilities, beliefs, commitments, cadence, dossier}`, `%Types.Item{id, name, value_gp, place_id, holder_id, is_hidden}`, `%Types.Action{actor_id, verb, target_id, params}`
- `EngineCore.World` — `%World{places: %{id => Place}, edges: [Edge], agents: %{id => Agent}, items: %{id => Item}, tick: integer}`; queries `agents_in/2`, `agent/2`, `place/2`
- `EngineCore.Ledger.start_link(opts)` · `append(ledger, class, tick, payload) :: Event` · `events(ledger) :: [Event]` · `clear(ledger)` — `ledger` is the registered name (any term) or pid
- `EngineCore.Fold.apply(World.t(), Event.t()) :: World.t()` · `Fold.fold(World.t(), [Event.t()]) :: World.t()`
- `EngineCore.Dice.new(seed :: integer) :: :rand.state()` · `Dice.roll(rng, sides) :: {1..sides, rng2}` · `Dice.roll(rng, sides, k) :: {[integer], rng2}`
- Rule modules: pure `(world, rng, args) :: {:ok, events, world2, rng2} | {:error, atom}`
- Statblock (plain map): `%{ac, hd, hp_max, thac0, morale, int, damage: %{dice, sides, plus}}`; body: `%{hp, conditions: [atom]}`

---

### Task 1: Umbrella scaffold

**Files:**
- Create: `shards_engine/mix.exs`, `shards_engine/apps/engine_core/mix.exs`, `shards_engine/apps/engine_core/lib/engine_core.ex`, `shards_engine/.gitignore`

**Interfaces:**
- Produces: runnable umbrella; `mix test` exits 0; app `:engine_core` v0.1.0, elixir "~> 1.17", dep `{:yaml_elixir, "~> 2.11"}`.

- [ ] **Step 1: Create umbrella**

```bash
mkdir -p shards_engine/apps
cd shards_engine
mix new apps/engine_core --sup
```

Replace `shards_engine/mix.exs` with:

```elixir
defmodule ShardsEngine.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  defp deps, do: []
end
```

Replace `shards_engine/apps/engine_core/mix.exs` with:

```elixir
defmodule EngineCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :engine_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [{:yaml_elixir, "~> 2.11"}]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {EngineCore.Application, []}]
end
```

Write `shards_engine/.gitignore`:

```
_build/
deps/
.mix_tasks
```

Trim `lib/engine_core/application.ex` `start/2` to a no-op supervisor (children: `[]`). Delete the generated `hello/0` from `lib/engine_core.ex` and the generated sample test, leaving only the `@moduledoc`.

- [ ] **Step 2: Verify compile and test run**

Run: `cd shards_engine && mix deps.get && mix compile && mix test`
Expected: deps fetch succeeds, compile clean, `There are no tests to run` exits 0.

- [ ] **Step 3: Commit**

```bash
git add shards_engine
git commit -m "chore: scaffold shards_engine umbrella with engine_core app"
```

---

### Task 2: Core type structs

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/types.ex`
- Create: `shards_engine/apps/engine_core/lib/engine_core/world.ex`
- Test: `shards_engine/apps/engine_core/test/types_test.exs`

**Interfaces:**
- Produces: `EngineCore.Types` (nested `Place`, `Edge`, `Agent`, `Item`, `Action`) and `EngineCore.World` with `agents_in/2`, `agent/2`, `place/2`. Defaults per File Structure above.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.TypesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Types, World}

  test "agent requires id, name, tier, place_id" do
    assert_raise ArgumentError, fn ->
      struct!(Types.Agent, name: "Grisk", tier: 3, place_id: "guard_room")
    end
  end

  test "edge and place defaults" do
    e = struct!(Types.Edge, id: :e1, from: "a", to: "b")
    assert e.sealed == false and e.permeability == %{sight: :open, sound: :open}
    p = struct!(Types.Place, id: "entry_hall", name: "Hall", kind: :room, connections: [])
    assert p.kind == :room
  end

  test "world query: agents_in returns agents at a place" do
    a1 = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall")
    a2 = %{a1 | id: "g2", place_id: "guard_room"}
    w = %World{places: %{}, edges: [], agents: %{"g1" => a1, "g2" => a2}, items: %{}, tick: 0}
    assert [%Types.Agent{id: "g1"}] = World.agents_in(w, "entry_hall")
    assert %Types.Agent{id: "g2"} = World.agent(w, "g2")
    assert World.agent(w, "nope") == nil
    assert World.place(w, "nope") == nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/types_test.exs`
Expected: FAIL — `EngineCore.Types` is not defined.

- [ ] **Step 3: Write the implementation**

`lib/engine_core/types.ex`:

```elixir
defmodule EngineCore.Types do
  @moduledoc "Pure data structs shared across the engine. No behavior."

  defmodule Place do
    @enforce_keys [:id, :name, :kind, :connections]
    defstruct [:id, :name, :kind, :connections]
  end

  defmodule Edge do
    @enforce_keys [:id, :from, :to]
    defstruct [:id, :from, :to, sealed: false, permeability: %{sight: :open, sound: :open}]
  end

  defmodule Agent do
    @enforce_keys [:id, :name, :tier, :place_id]
    defstruct [:id, :name, :tier, :place_id,
               statblock: %{ac: 10, hd: 1, hp_max: 1, thac0: 20, morale: 7, int: 10,
                            damage: %{dice: 1, sides: 6, plus: 0}},
               body: %{hp: 1, conditions: []},
               capabilities: [:move, :strike, :wait],
               beliefs: %{}, commitments: [], cadence: nil, dossier: %{}]
  end

  defmodule Item do
    @enforce_keys [:id, :name, :value_gp]
    defstruct [:id, :name, :value_gp, place_id: nil, holder_id: nil, is_hidden: false]
  end

  defmodule Action do
    @enforce_keys [:actor_id, :verb]
    defstruct [:actor_id, :verb, target_id: nil, params: %{}]
  end
end
```

`lib/engine_core/world.ex`:

```elixir
defmodule EngineCore.World do
  @moduledoc "World container + query helpers. State is data."
  defstruct places: %{}, edges: [], agents: %{}, items: %{}, tick: 0
  @type t :: %__MODULE__{}

  def agents_in(%__MODULE__{agents: agents}, place_id),
    do: agents |> Map.values() |> Enum.filter(&(&1.place_id == place_id))

  def agent(%__MODULE__{agents: agents}, id), do: agents[id]
  def place(%__MODULE__{places: places}, id), do: places[id]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/types_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib shards_engine/apps/engine_core/test
git commit -m "feat: core type structs and world container"
```

---

### Task 3: YAML integrity validator + repair of degraded YAML

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/validator.ex`
- Test: `shards_engine/apps/engine_core/test/validator_test.exs`
- Modify: `the-ruined-tower/ruined_tower.yaml` (repair in place)

**Interfaces:**
- Produces: `EngineCore.Validator.check(map) :: :ok | {:error, [String.t()]}` and `check_file(path) :: :ok | {:error, [String.t()] | term}`.

Known degradation (engrams decision 15): dropped words and orphaned fragments in text fields, e.g. `hand (3 (7`; orphan stat numbers. Repair source of truth: `the-ruined-tower/README.md` stat blocks.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.ValidatorTest do
  use ExUnit.Case, async: true
  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "the real tower YAML is structurally intact" do
    assert :ok = EngineCore.Validator.check_file(@yaml)
  end

  test "detects orphan-fragment text" do
    bad = %{"monsters" => [%{"id" => "m1", "name" => "goblin",
                             "description" => "claw hand (3 (7"}]}
    assert {:error, [e | _]} = EngineCore.Validator.check(bad)
    assert e =~ "orphan fragment"
  end

  test "detects missing required monster fields" do
    bad = %{"monsters" => [%{"id" => "m1", "name" => "goblin"}]}
    assert {:error, errors} = EngineCore.Validator.check(bad)
    assert Enum.any?(errors, &(&1 =~ "missing"))
  end

  test "detects connections to unknown rooms" do
    bad = %{"rooms" => [%{"id" => "r1", "name" => "R", "connections" => ["ghost_room"]}],
            "monsters" => []}
    assert {:error, errors} = EngineCore.Validator.check(bad)
    assert Enum.any?(errors, &(&1 =~ "unknown room"))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/validator_test.exs`
Expected: FAIL — `EngineCore.Validator` not defined.

- [ ] **Step 3: Implement the validator**

```elixir
defmodule EngineCore.Validator do
  @moduledoc "Structural integrity checks for adventure YAML. Pure, no state."

  @monster_req ~w(id name hd hp ac thac0 morale)
  @orphan_fragment ~r/\(\d+ \(\d/

  def check_file(path) do
    with {:ok, parsed} <- YamlElixir.read_from_file(path), do: check(parsed)
  end

  def check(yaml) do
    errors =
      (monster_errors(yaml) ++ text_errors(yaml) ++ room_errors(yaml))
      |> Enum.reject(&is_nil(&1))

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp monster_errors(%{"monsters" => monsters}) do
    Enum.flat_map(monsters || [], fn m ->
      Enum.map(@monster_req, fn k ->
        unless Map.has_key?(m, k), do: "monster #{m["id"] || "?"}: missing #{k}"
      end)
    end)
  end

  defp monster_errors(_), do: ["monsters: key absent"]

  defp text_errors(yaml) do
    yaml
    |> walk_strings()
    |> Enum.filter(&Regex.match?(@orphan_fragment, &1.elem))
    |> Enum.map(&"#{&1.path}: orphan fragment #{inspect(&1.elem)}")
  end

  defp room_errors(%{"rooms" => rooms}) do
    ids = MapSet.new(rooms |> Enum.map(& &1["id"]))
    Enum.flat_map(rooms, fn r ->
      Enum.map(r["connections"] || [], fn c ->
        unless MapSet.member?(ids, c), do: "room #{r["id"]}: connection to unknown room #{c}"
      end)
    end)
  end

  defp room_errors(_), do: []

  defp walk_strings(term, path \\ "$")
  defp walk_strings(m, path) when is_map(m),
    do: Enum.flat_map(m, fn {k, v} -> walk_strings(v, "#{path}.#{k}") end)
  defp walk_strings(l, path) when is_list(l),
    do: Enum.with_index(l) |> Enum.flat_map(fn {v, i} -> walk_strings(v, "#{path}[#{i}]") end)
  defp walk_strings(s, path) when is_binary(s), do: [%{path: path, elem: s}]
  defp walk_strings(_, _), do: []
end
```

- [ ] **Step 4: Repair the YAML until the real-YAML test passes**

Run: `cd shards_engine && mix test apps/engine_core/test/validator_test.exs`
Expected: the `real tower YAML` test FAILS with orphan-fragment/missing-field errors; the other three PASS.

Repair procedure, iterating until the test passes:
1. Each reported path (e.g. `$.monsters[4].attacks`) — open `the-ruined-tower/ruined_tower.yaml` at that node, open the matching stat block in `the-ruined-tower/README.md`, restore the field's full text/numbers from the README.
2. Each reported missing field — copy the value from the README stat block (e.g. `morale: 7` for goblins).
3. Do NOT rename keys, add keys, or restructure — text/value repair only, so loader expectations stay stable.
4. Re-run the test after each node repair.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/validator.ex \
        shards_engine/apps/engine_core/test/validator_test.exs \
        the-ruined-tower/ruined_tower.yaml
git commit -m "fix: repair degraded YAML text; add structural validator"
```

---

### Task 4: YAML loader

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/loader.ex`
- Test: `shards_engine/apps/engine_core/test/loader_test.exs`

**Interfaces:**
- Consumes: `Validator.check/1`, Task 2 structs.
- Produces: `EngineCore.Loader.load(path) :: {:ok, World.t()} | {:error, term}`. Tier assignment: the cognition map below — Plan 3 gives tier-3 agents brains.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.LoaderTest do
  use ExUnit.Case, async: true
  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "loads the tower into a coherent world" do
    {:ok, w} = EngineCore.Loader.load(@yaml)
    assert map_size(w.places) == 7
    assert w.tick == 0
    tiers = w.agents |> Map.values() |> Map.new(&{&1.tier, true})
    assert tiers[3] and tiers[2] and tiers[0] and tiers[1]
    assert Enum.all?(w.agents |> Map.values(), &(&1.place_id != nil))
  end

  test "refuses to load a file failing validation" do
    tmp = Path.join(System.tmp_dir!(), "bad_adventure_#{:erlang.unique_integer()}.yaml")
    File.write!(tmp, "monsters:\n- id: m1\n  name: x\n  description: bad (3 (7\n")
    on_exit(fn -> File.rm!(tmp) end)
    assert {:error, _} = EngineCore.Loader.load(tmp)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/loader_test.exs`
Expected: FAIL — `EngineCore.Loader` not defined.

- [ ] **Step 3: Implement the loader**

First confirm the real monster ids: `grep -A1 "^monsters:" -n the-ruined-tower/ruined_tower.yaml` and list every monster `id:`. Then write, adjusting the three tier lists to those ids (behavior contract: tiers 3/2/1/0 all present; the test enforces presence, the lists encode which):

```elixir
defmodule EngineCore.Loader do
  @moduledoc "Adventure YAML → %World{}. Validates first; never mutates the file."

  alias EngineCore.{Types, Validator, World}

  # Cognition tiers keyed by monster id (spec §5.1) — ADJUST to real YAML ids.
  @tier3 ~w(grisk snaga skrit varg murg willem)
  @tier2 ~w(wolf_pair rat_pack_1 rat_pack_2)
  @tier0 ~w(shadow_skeleton tripwire_trap_1 tripwire_trap_2)

  def load(path) do
    with {:ok, parsed} <- YamlElixir.read_from_file(path),
         :ok <- Validator.check(parsed) do
      {:ok, build(parsed)}
    end
  end

  def build(yaml) do
    places =
      Map.new(yaml["rooms"] || [], fn r ->
        {r["id"], %Types.Place{id: r["id"], name: r["name"], kind: :room,
                               connections: r["connections"] || []}}
      end)

    edges =
      for r <- yaml["rooms"] || [], c <- r["connections"] || [],
          do: %Types.Edge{id: :"#{r["id"]}__#{c}", from: r["id"], to: c}

    agents = Map.new(yaml["monsters"] || [], fn m -> {m["id"], agent_from(m)} end)

    items =
      Map.new(yaml["treasures"] || [], fn t ->
        {t["id"], %Types.Item{id: t["id"], name: t["name"], value_gp: t["value"] || 0,
                              place_id: t["location_room_id"], is_hidden: t["is_hidden"] == true}}
      end)

    %World{places: places, edges: edges, agents: agents, items: items, tick: 0}
  end

  defp agent_from(m) do
    tier = tier_of(m["id"])

    %Types.Agent{
      id: m["id"],
      name: m["name"],
      tier: tier,
      place_id: m["current_room_id"] || m["room_id"],
      statblock: %{ac: m["ac"], hd: m["hd"], hp_max: m["hp"], thac0: m["thac0"],
                   morale: m["morale"], int: m["int"] || 8, damage: dmg(m)},
      body: %{hp: m["hp"], conditions: []},
      capabilities: caps(tier)
    }
  end

  defp tier_of(id) when id in @tier3, do: 3
  defp tier_of(id) when id in @tier2, do: 2
  defp tier_of(id) when id in @tier0, do: 0
  defp tier_of(_), do: 1

  defp dmg(%{"damage_dice" => d, "damage_sides" => s} = m),
    do: %{dice: d, sides: s, plus: m["damage_plus"] || 0}

  defp dmg(_), do: %{dice: 1, sides: 4, plus: 0}

  defp caps(3), do: [:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee]
  defp caps(2), do: [:move, :strike, :wait, :flee]
  defp caps(_), do: [:move, :strike, :wait]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/loader_test.exs`
Expected: PASS (2 tests). If an id mismatch fails it, fix the tier lists, not the test.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/loader.ex \
        shards_engine/apps/engine_core/test/loader_test.exs
git commit -m "feat: adventure YAML loader with cognition tier assignment"
```

---

### Task 5: Append-only event ledger

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/ledger.ex`
- Test: `shards_engine/apps/engine_core/test/ledger_test.exs`

**Interfaces:**
- Produces: `%EngineCore.Ledger.Event{seq, tick, class, payload}`; `EngineCore.Ledger` GenServer: `start_link/1` (opt `name:`, any term), `append(ledger, class, tick, payload) :: Event`, `events(ledger) :: [Event]`, `clear(ledger) :: :ok` — `ledger` is name or pid. Classes this plan: `:world`, `:dice`, `:meta`. Plan 2 adds `:signal`, `:envelope`, `:commitment`; Plan 3 adds `:deliberation`, `:llm`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.LedgerTest do
  use ExUnit.Case, async: true
  alias EngineCore.Ledger

  test "appends are ordered, seq monotonic, reads stable" do
    l = start_ledger!()
    e1 = Ledger.append(l, :world, 1, %{kind: :move, agent_id: "g1", to: "guard_room"})
    e2 = Ledger.append(l, :dice, 1, %{roll: 15, sides: 20})
    assert e1.seq == 1 and e2.seq == 2
    assert [%{seq: 1}, %{seq: 2}] = Ledger.events(l)
    Ledger.append(l, :meta, 2, %{kind: :mode, mode: :combat})
    assert [%{seq: 1}, %{seq: 2}, %{seq: 3}] = Ledger.events(l)
  end

  test "events carry no wall-clock fields" do
    l = start_ledger!()
    e = Ledger.append(l, :world, 0, %{kind: :noop})
    refute Map.has_key?(e, :timestamp)
    assert e.class == :world and e.tick == 0
  end

  test "two ledgers are independent; clear resets" do
    la = start_ledger!()
    lb = start_ledger!()
    Ledger.append(la, :meta, 0, %{a: 1})
    assert Ledger.events(lb) == []
    :ok = Ledger.clear(la)
    assert Ledger.events(la) == []
  end

  defp start_ledger! do
    ref = make_ref()
    start_supervised!({Ledger, name: ref})
    ref
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/ledger_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement the ledger**

```elixir
defmodule EngineCore.Ledger.Event do
  @enforce_keys [:seq, :tick, :class, :payload]
  defstruct [:seq, :tick, :class, :payload]
  @type t :: %__MODULE__{}
end

defmodule EngineCore.Ledger do
  @moduledoc """
  Append-only event ledger (engrams pattern 10). Single writer process.
  Events are pure data: seq (monotonic), tick (game clock), class, payload.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def append(ledger, class, tick, payload),
    do: GenServer.call(ledger, {:append, class, tick, payload})

  def events(ledger), do: GenServer.call(ledger, :events)
  def clear(ledger), do: GenServer.call(ledger, :clear)

  @impl true
  def init(:ok), do: {:ok, %{events: [], seq: 0}}

  @impl true
  def handle_call({:append, class, tick, payload}, _from, %{events: ev, seq: s} = st) do
    event = struct!(EngineCore.Ledger.Event, seq: s + 1, tick: tick, class: class, payload: payload)
    {:reply, event, %{st | events: [event | ev], seq: s + 1}}
  end

  def handle_call(:events, _from, %{events: ev} = st), do: {:reply, Enum.reverse(ev), st}
  def handle_call(:clear, _from, st), do: {:reply, :ok, %{st | events: [], seq: 0}}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/ledger_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/ledger.ex \
        shards_engine/apps/engine_core/test/ledger_test.exs
git commit -m "feat: append-only event ledger with monotonic seq"
```

---

### Task 6: Fold — events to world state

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/fold.ex`
- Test: `shards_engine/apps/engine_core/test/fold_test.exs`

**Interfaces:**
- Consumes: `Ledger.Event`, `World`, `Types.Agent`.
- Produces: `Fold.apply/2`, `Fold.fold/2`. Handled payload kinds here: `:move` (`%{agent_id, to}`), `:damage` (`%{target_id, amount}`), `:death` (`%{agent_id}`), `:morale_break` (`%{agent_id}`), `:tick_advance` (`%{to}`). Unknown kinds raise `ArgumentError` (fail loud — no silent drift).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.FoldTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, Types, World}

  setup do
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall")
    {:ok, w: %World{places: %{}, edges: [], agents: %{"g1" => g}, items: %{}, tick: 0}}
  end

  test "move event relocates agent and advances tick", %{w: w} do
    ev = %Ledger.Event{seq: 1, tick: 3, class: :world,
                       payload: %{kind: :move, agent_id: "g1", to: "guard_room"}}
    w2 = Fold.apply(w, ev)
    assert %Types.Agent{place_id: "guard_room"} = World.agent(w2, "g1")
    assert w2.tick == 3
  end

  test "damage reduces hp; death empties capabilities; morale_break adds condition", %{w: w} do
    w1 = Fold.apply(w, ev(1, 1, %{kind: :damage, target_id: "g1", amount: 3}))
    assert %Types.Agent{body: %{hp: 2}} = World.agent(w1, "g1")

    w2 = Fold.apply(w1, ev(2, 2, %{kind: :damage, target_id: "g1", amount: 9}))
    w3 = Fold.apply(w2, ev(3, 2, %{kind: :death, agent_id: "g1"}))
    assert %Types.Agent{body: %{hp: 0}, capabilities: []} = World.agent(w3, "g1")

    w4 = Fold.apply(w, ev(4, 1, %{kind: :morale_break, agent_id: "g1"}))
    assert :fleeing in World.agent(w4, "g1").body.conditions
  end

  test "fold folds in order; empty fold is identity", %{w: w} do
    evs = [ev(1, 1, %{kind: :damage, target_id: "g1", amount: 1})]
    assert %World{tick: 1} = w2 = Fold.fold(w, evs)
    assert Fold.fold(w2, []) == w2
  end

  test "unknown payload kind raises" do
    assert_raise ArgumentError, ~r/unknown payload kind/, fn ->
      Fold.apply(%World{}, ev(1, 0, %{kind: :teleport}))
    end
  end

  defp ev(seq, tick, payload),
    do: %Ledger.Event{seq: seq, tick: tick, class: :world, payload: payload}
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/fold_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement the fold**

```elixir
defmodule EngineCore.Fold do
  @moduledoc "Deterministic state derivation: world = fold(ledger). Snapshots are cached folds."
  alias EngineCore.{Ledger, World}

  @spec fold(World.t(), [Ledger.Event.t()]) :: World.t()
  def fold(world, events), do: Enum.reduce(events, world, &apply/2)

  @spec apply(World.t(), Ledger.Event.t()) :: World.t()
  def apply(world, %Ledger.Event{tick: tick, payload: %{kind: kind} = p}) do
    world = %{world | tick: tick}

    case kind do
      :move ->
        update_agent(world, p.agent_id, &%{&1 | place_id: p.to})

      :damage ->
        update_agent(world, p.target_id, fn a ->
          %{a | body: %{a.body | hp: max(0, a.body.hp - p.amount)}}
        end)

      :death ->
        update_agent(world, p.agent_id, &%{&1 | capabilities: []})

      :morale_break ->
        update_agent(world, p.agent_id, fn a ->
          %{a | body: %{a.body | conditions: Enum.uniq([:fleeing | a.body.conditions])}}
        end)

      :tick_advance ->
        %{world | tick: max(world.tick, p.to)}

      other ->
        raise ArgumentError, "unknown payload kind: #{inspect(other)}"
    end
  end

  defp update_agent(world, id, fun) do
    case World.agent(world, id) do
      nil -> world
      a -> %{world | agents: Map.put(world.agents, id, fun.(a))}
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/fold_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/fold.ex \
        shards_engine/apps/engine_core/test/fold_test.exs
git commit -m "feat: deterministic ledger fold to world state"
```

---

### Task 7: Seeded dice

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/dice.ex`
- Test: `shards_engine/apps/engine_core/test/dice_test.exs`

**Interfaces:**
- Produces: `Dice.new/1`, `Dice.roll/2`, `Dice.roll/3` (signatures in File Structure). Every roll site in Tasks 8–11 uses this and ONLY this.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.DiceTest do
  use ExUnit.Case, async: true

  test "same seed, same sequence" do
    r1 = EngineCore.Dice.new(42)
    r2 = EngineCore.Dice.new(42)
    {a, r1} = EngineCore.Dice.roll(r1, 20)
    {b, r2} = EngineCore.Dice.roll(r2, 20)
    assert a == b
    {[c1, c2], _} = EngineCore.Dice.roll(r1, 6, 2)
    {[d1, d2], _} = EngineCore.Dice.roll(r2, 6, 2)
    assert {c1, c2} == {d1, d2}
  end

  test "different seeds diverge" do
    rolls = for s <- 1..50 do
      {v, _} = EngineCore.Dice.new(s) |> EngineCore.Dice.roll(20)
      v
    end
    assert length(Enum.uniq(rolls)) > 1
  end

  test "results within bounds" do
    {v, _} = EngineCore.Dice.new(7) |> EngineCore.Dice.roll(6)
    assert v in 1..6
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/dice_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement dice**

```elixir
defmodule EngineCore.Dice do
  @moduledoc "Pure seeded RNG. :rand.uniform_s threads state explicitly — no process seed."

  @spec new(integer) :: :rand.state()
  def new(seed_int) do
    :rand.seed_s(:exsss, {seed_int, seed_int + 0x9E37, seed_int + 0x7F4A})
  end

  @spec roll(:rand.state(), pos_integer) :: {pos_integer, :rand.state()}
  def roll(rng, sides), do: :rand.uniform_s(sides, rng)

  @spec roll(:rand.state(), pos_integer, pos_integer) :: {[pos_integer], :rand.state()}
  def roll(rng, sides, k), do: roll_n(rng, sides, k, [])

  defp roll_n(rng, _sides, 0, acc), do: {Enum.reverse(acc), rng}

  defp roll_n(rng, sides, k, acc) do
    {v, rng2} = :rand.uniform_s(sides, rng)
    roll_n(rng2, sides, k - 1, [v | acc])
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/dice_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/dice.ex \
        shards_engine/apps/engine_core/test/dice_test.exs
git commit -m "feat: pure seeded dice stream"
```

---

### Task 8: Movement rule

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/rules/movement.ex`
- Test: `shards_engine/apps/engine_core/test/movement_test.exs`

**Interfaces:**
- Consumes: `World`, `Types`, `Ledger.Event`.
- Produces: `Movement.traverse(world, rng, agent_id, to_place_id) :: {:ok, Event, World, rng} | {:error, :no_agent | :no_place | :not_adjacent | :sealed_edge}`. Event payload `%{kind: :move, agent_id, from, to}` at tick `world.tick + 1` (one segment per move). Event `seq: 0` — the Ledger stamps authoritative seq on append.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.MovementTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Movement, Types, World}

  setup do
    hall = %Types.Place{id: "entry_hall", name: "Hall", kind: :room, connections: ["guard_room"]}
    guard = %Types.Place{id: "guard_room", name: "Guard", kind: :room, connections: ["entry_hall"]}
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall")
    w = %World{places: %{"entry_hall" => hall, "guard_room" => guard},
               edges: [%Types.Edge{id: :e1, from: "entry_hall", to: "guard_room"}],
               agents: %{"g1" => g}, items: %{}, tick: 10}
    {:ok, w: w}
  end

  test "traverse emits move event and relocates", %{w: w} do
    rng = EngineCore.Dice.new(1)
    {:ok, ev, w2, _} = Movement.traverse(w, rng, "g1", "guard_room")
    assert ev.payload == %{kind: :move, agent_id: "g1", from: "entry_hall", to: "guard_room"}
    assert ev.tick == 11
    assert %Types.Agent{place_id: "guard_room"} = World.agent(w2, "g1")
  end

  test "no edge means not_adjacent", %{w: w} do
    w = put_in(w.places["entry_hall"].connections, [])
    assert {:error, :not_adjacent} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "guard_room")
  end

  test "sealed edge blocks", %{w: w} do
    w = %{w | edges: [%Types.Edge{id: :e1, from: "entry_hall", to: "guard_room", sealed: true}]}
    assert {:error, :sealed_edge} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "guard_room")
  end

  test "unknown agent and unknown destination error", %{w: w} do
    assert {:error, :no_agent} = Movement.traverse(w, EngineCore.Dice.new(1), "nope", "guard_room")
    assert {:error, :no_place} = Movement.traverse(w, EngineCore.Dice.new(1), "g1", "nowhere")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/movement_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement movement**

```elixir
defmodule EngineCore.Rules.Movement do
  @moduledoc "Room-to-room traversal along edges. Sealed edges block; permeability routing is Plan 2."
  alias EngineCore.{Ledger, Types, World}

  @spec traverse(World.t(), :rand.state(), String.t(), String.t()) ::
          {:ok, Ledger.Event.t(), World.t(), :rand.state()} | {:error, atom()}
  def traverse(world, rng, agent_id, to) do
    with {:ok, agent} <- fetch_agent(world, agent_id),
         {:ok, _place} <- fetch_place(world, to),
         :ok <- check_edge(world, agent.place_id, to) do
      tick = world.tick + 1

      ev = %Ledger.Event{seq: 0, tick: tick, class: :world,
                         payload: %{kind: :move, agent_id: agent_id, from: agent.place_id, to: to}}

      w2 = %{
        world
        | agents: Map.update!(world.agents, agent_id, &%{&1 | place_id: to}),
          tick: tick
      }

      {:ok, ev, w2, rng}
    end
  end

  defp fetch_agent(world, id),
    do: if(a = World.agent(world, id), do: {:ok, a}, else: {:error, :no_agent})

  defp fetch_place(world, id),
    do: if(p = World.place(world, id), do: {:ok, p}, else: {:error, :no_place})

  defp check_edge(world, from, to) do
    case Enum.find(world.edges, &(&1.from == from and &1.to == to)) do
      nil -> {:error, :not_adjacent}
      %Types.Edge{sealed: true} -> {:error, :sealed_edge}
      _edge -> :ok
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/movement_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/rules/movement.ex \
        shards_engine/apps/engine_core/test/movement_test.exs
git commit -m "feat: edge-based movement rule with sealed-edge blocking"
```

---

### Task 9: Combat rule (initiative, to-hit, damage)

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/rules/combat.ex`
- Test: `shards_engine/apps/engine_core/test/combat_test.exs`

**Interfaces:**
- Consumes: `World`, `Dice`, `Ledger.Event`.
- Produces: `Combat.initiative(rng, ids) :: {[id], rng2}` (per-agent d6, highest first, id tiebreak — deterministic); `Combat.attack(world, rng, attacker_id, target_id) :: {:ok, [Event], World, rng} | {:error, :no_agent | :not_engaged | :no_capability}`. Events on hit: `:dice` `%{purpose: :to_hit, sides: 20, roll, target_ac, hit, dmg_rolls, amount}` + `:world` `%{kind: :damage, target_id, amount}`; on miss: `:dice` `%{..., hit: false}` only. 1E to-hit: `roll >= thac0 - target_ac` (AC descending).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.CombatTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Combat, Types, World}

  defp world do
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "r",
      statblock: %{ac: 6, hd: 1, hp_max: 5, thac0: 19, morale: 7, int: 8,
                   damage: %{dice: 1, sides: 4, plus: 0}})
    f = struct!(Types.Agent, id: "pc1", name: "Fighter", tier: 3, place_id: "r",
      statblock: %{ac: 5, hd: 3, hp_max: 18, thac0: 18, morale: 12, int: 10,
                   damage: %{dice: 1, sides: 8, plus: 0}})
    %World{places: %{"r" => %Types.Place{id: "r", name: "R", kind: :room, connections: []}},
           edges: [], agents: %{"g1" => g, "pc1" => f}, items: %{}, tick: 4}
  end

  test "attack emits events and reduces hp or misses cleanly" do
    {:ok, events, w2, _} = Combat.attack(world(), EngineCore.Dice.new(99), "g1", "pc1")

    case events do
      [%{class: :dice, payload: %{hit: true}}, %{class: :world, payload: %{kind: :damage, target_id: "pc1"}}] ->
        assert World.agent(w2, "pc1").body.hp < 18
      [%{class: :dice, payload: %{hit: false}}] ->
        assert World.agent(w2, "pc1").body.hp == 18
    end
  end

  test "attack on different-room agent errors :not_engaged" do
    w = put_in(world().agents["pc1"].place_id, "elsewhere")
    assert {:error, :not_engaged} = Combat.attack(w, EngineCore.Dice.new(1), "g1", "pc1")
  end

  test "dead agents (no capabilities) cannot attack" do
    w = world() |> put_in([:agents, "g1", :capabilities], [])
    assert {:error, :no_capability} = Combat.attack(w, EngineCore.Dice.new(1), "g1", "pc1")
  end

  test "initiative is a permutation, deterministic per seed" do
    rng = EngineCore.Dice.new(5)
    {o1, _} = Combat.initiative(rng, ["g1", "pc1"])
    {o2, _} = Combat.initiative(rng, ["g1", "pc1"])
    assert Enum.sort(o1) == ["g1", "pc1"] and o1 == o2
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/combat_test.exs`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement combat**

```elixir
defmodule EngineCore.Rules.Combat do
  @moduledoc "1E to-hit and damage resolution. Segment scheduling arrives with the Scheduler (Plan 2)."
  alias EngineCore.{Dice, Ledger, World}

  @spec initiative(:rand.state(), [String.t()]) :: {[String.t()], :rand.state()}
  def initiative(rng, ids) do
    {scored, rng2} =
      Enum.map_reduce(ids, rng, fn id, r ->
        {v, r2} = Dice.roll(r, 6)
        {{v, id}, r2}
      end)

    order = scored |> Enum.sort_by(&{-elem(&1, 0), elem(&1, 1)}) |> Enum.map(&elem(&1, 1))
    {order, rng2}
  end

  @spec attack(World.t(), :rand.state(), String.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()} | {:error, atom()}
  def attack(world, rng, attacker_id, target_id) do
    a = World.agent(world, attacker_id)
    t = World.agent(world, target_id)

    cond do
      a == nil or t == nil -> {:error, :no_agent}
      a.place_id != t.place_id -> {:error, :not_engaged}
      :strike not in a.capabilities -> {:error, :no_capability}
      true ->
        {roll, rng2} = Dice.roll(rng, 20)
        hit = roll >= a.statblock.thac0 - t.statblock.ac
        resolve(hit, world, rng2, a, t, roll)
    end
  end

  defp resolve(false, world, rng, _a, t, roll) do
    ev = dice_event(world.tick, %{purpose: :to_hit, sides: 20, roll: roll,
                                  target_ac: t.statblock.ac, hit: false})
    {:ok, [ev], world, rng}
  end

  defp resolve(true, world, rng, a, t, roll) do
    cfg = a.statblock.damage
    {rolls, rng2} = Dice.roll(rng, cfg.sides, cfg.dice)
    amount = Enum.sum(rolls) + cfg.plus

    ev_dice =
      dice_event(world.tick, %{purpose: :to_hit, sides: 20, roll: roll,
                               target_ac: t.statblock.ac, hit: true,
                               dmg_rolls: rolls, amount: amount})

    ev_dmg = %Ledger.Event{seq: 0, tick: world.tick, class: :world,
                           payload: %{kind: :damage, target_id: t.id, amount: amount}}

    w2 = %{
      world
      | agents:
          Map.update!(world.agents, t.id, fn ag ->
            %{ag | body: %{ag.body | hp: max(0, ag.body.hp - amount)}}
          end)
    }

    {:ok, [ev_dice, ev_dmg], w2, rng2}
  end

  defp dice_event(tick, payload),
    do: %Ledger.Event{seq: 0, tick: tick, class: :dice, payload: payload}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine && mix test apps/engine_core/test/combat_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/rules/combat.ex \
        shards_engine/apps/engine_core/test/combat_test.exs
git commit -m "feat: 1E to-hit/damage resolution with dice ledger events"
```

---

### Task 10: Morale & saves rules

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/rules/morale.ex`
- Create: `shards_engine/apps/engine_core/lib/engine_core/rules/saves.ex`
- Test: `shards_engine/apps/engine_core/test/morale_test.exs`, `shards_engine/apps/engine_core/test/saves_test.exs`

**Interfaces:**
- Consumes: `World`, `Dice`, `Ledger.Event`.
- Produces: `Morale.check(world, rng, faction_ids) :: {:ok, [Event], World, rng}` — triggers: leader down (an hp-0 faction member with `hd >= 3`) or ≥50% casualties; each living member rolls d20, `roll <= morale` holds, else `:morale_break` world event + `:fleeing` condition. `Saves.target(hd, category) :: pos_integer` and `Saves.check(world, rng, agent_id, category) :: {:ok, [Event], World, rng} | {:error, :no_agent}` — categories `:death | :petrification | :wands | :spells`; monster-as-fighter formula `max(10, 15 - hd) + offset` with offsets `%{death: 0, petrification: 1, wands: 2, spells: 3}`; d20 `>= target` saves. Saves emit `:dice` events `%{purpose: :save, category, sides: 20, roll, target, agent_id, saved}` (Plan 2's shadow-whispers consumes this).

- [ ] **Step 1: Write the failing tests**

`test/morale_test.exs`:

```elixir
defmodule EngineCore.MoraleTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Morale, Types, World}

  defp gob(id, opts \\ []) do
    struct!(Types.Agent, id: id, name: id, tier: 3, place_id: "r",
      statblock: %{ac: 6, hd: Keyword.get(opts, :hd, 1), hp_max: 5, thac0: 19,
                   morale: Keyword.get(opts, :morale, 7), int: 8,
                   damage: %{dice: 1, sides: 4, plus: 0}},
      body: %{hp: Keyword.get(opts, :hp, 5), conditions: Keyword.get(opts, :conditions, [])})
  end

  test "leader down triggers morale dice for the living; outcome is consistent" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1")}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    {:ok, events, w2, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])

    assert Enum.any?(events, &(&1.class == :dice and &1.payload.purpose == :morale))
    g1 = World.agent(w2, "g1")
    assert g1.body.conditions == [] or :fleeing in g1.body.conditions
    assert Enum.all?(events, &(&1.payload[:agent_id] != "l")), "dead do not roll"
  end

  test "50% casualties trigger" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1"), "g2" => gob("g2", hp: 0)}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    {:ok, events, _, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1", "g2"])
    assert Enum.any?(events, &(&1.payload[:purpose] == :morale))
  end

  test "healthy faction triggers nothing" do
    agents = %{"l" => gob("l", hd: 3), "g1" => gob("g1")}
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 0}
    assert {:ok, [], ^w, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])
  end

  test "morale_break event matches Fold behavior" do
    agents = %{"l" => gob("l", hd: 3, hp: 0), "g1" => gob("g1", morale: 0)}
    # morale 0: any roll 1..20 breaks
    w = %World{places: %{}, edges: [], agents: agents, items: %{}, tick: 2}
    {:ok, events, w2, _} = Morale.check(w, EngineCore.Dice.new(3), ["l", "g1"])
    break_ev = Enum.find(events, &(&1.payload[:kind] == :morale_break))
    assert break_ev.tick == 2
    assert :fleeing in World.agent(w2, "g1").body.conditions
  end
end
```

`test/saves_test.exs`:

```elixir
defmodule EngineCore.SavesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Rules.Saves, Types, World}

  test "monster-as-fighter save targets" do
    assert Saves.target(1, :death) == 14
    assert Saves.target(3, :death) == 12
    assert Saves.target(1, :spells) == 17
    assert Saves.target(10, :death) == 10
  end

  test "check emits a dice event with a boolean verdict" do
    a = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "r",
      statblock: %{ac: 6, hd: 1, hp_max: 5, thac0: 19, morale: 7, int: 8,
                   damage: %{dice: 1, sides: 4, plus: 0}})
    w = %World{places: %{}, edges: [], agents: %{"g1" => a}, items: %{}, tick: 6}
    {:ok, [ev], _w2, _} = Saves.check(w, EngineCore.Dice.new(11), "g1", :death)
    assert ev.class == :dice and ev.tick == 6
    assert ev.payload.purpose == :save and ev.payload.category == :death
    assert is_integer(ev.payload.roll) and is_boolean(ev.payload.saved)
    assert ev.payload.target == 14
    assert {:error, :no_agent} = Saves.check(w, EngineCore.Dice.new(11), "nope", :death)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd shards_engine && mix test apps/engine_core/test/morale_test.exs apps/engine_core/test/saves_test.exs`
Expected: FAIL — modules not defined.

- [ ] **Step 3: Implement morale and saves**

`lib/engine_core/rules/morale.ex`:

```elixir
defmodule EngineCore.Rules.Morale do
  @moduledoc "1E-style morale: leader down or ≥50% casualties forces d20 vs morale. Break ⇒ :fleeing."
  alias EngineCore.{Dice, Ledger, World}

  @spec check(World.t(), :rand.state(), [String.t()]) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def check(world, rng, faction_ids) do
    faction = faction_ids |> Enum.map(&World.agent(world, &1)) |> Enum.reject(&is_nil/1)

    dead = Enum.count(faction, &(&1.body.hp == 0 or :dead in &1.body.conditions))
    leader_down = Enum.any?(faction, &(&1.body.hp == 0 and (&1.statblock.hd || 1) >= 3))
    casualties_half = faction != [] and dead * 2 >= length(faction)

    if leader_down or casualties_half do
      living = Enum.reject(faction, &(&1.body.hp == 0))

      {events_rev, world2, rng2} =
        Enum.reduce(living, {[], world, rng}, fn a, {evs, w, r} ->
          {roll, r2} = Dice.roll(r, 20)
          held = roll <= a.statblock.morale

          dice_ev = %Ledger.Event{seq: 0, tick: w.tick, class: :dice,
            payload: %{purpose: :morale, sides: 20, roll: roll,
                       morale: a.statblock.morale, agent_id: a.id, held: held}}

          if held do
            {[dice_ev | evs], w, r2}
          else
            break_ev = %Ledger.Event{seq: 0, tick: w.tick, class: :world,
              payload: %{kind: :morale_break, agent_id: a.id}}

            w2 = add_condition(w, a.id, :fleeing)
            {[break_ev, dice_ev | evs], w2, r2}
          end
        end)

      {:ok, Enum.reverse(events_rev), world2, rng2}
    else
      {:ok, [], world, rng}
    end
  end

  defp add_condition(world, id, cond) do
    %{world | agents: Map.update!(world.agents, id, fn a ->
      %{a | body: %{a.body | conditions: Enum.uniq([cond | a.body.conditions])}}
    end)}
  end
end
```

`lib/engine_core/rules/saves.ex`:

```elixir
defmodule EngineCore.Rules.Saves do
  @moduledoc "1E-style saves. Monsters save as fighters by HD: target = max(10, 15 - hd) + category offset."
  alias EngineCore.{Dice, Ledger, World}

  @offset %{death: 0, petrification: 1, wands: 2, spells: 3}

  @spec target(pos_integer, atom) :: pos_integer
  def target(hd, category), do: max(10, 15 - hd) + Map.fetch!(@offset, category)

  @spec check(World.t(), :rand.state(), String.t(), atom) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()} | {:error, :no_agent}
  def check(world, rng, agent_id, category) do
    case World.agent(world, agent_id) do
      nil ->
        {:error, :no_agent}

      a ->
        t = target(a.statblock.hd, category)
        {roll, rng2} = Dice.roll(rng, 20)
        saved = roll >= t

        ev = %Ledger.Event{seq: 0, tick: world.tick, class: :dice,
          payload: %{purpose: :save, category: category, sides: 20, roll: roll,
                     target: t, agent_id: agent_id, saved: saved}}

        {:ok, [ev], world, rng2}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine && mix test apps/engine_core/test/morale_test.exs apps/engine_core/test/saves_test.exs`
Expected: PASS (4 + 2 tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/rules/morale.ex \
        shards_engine/apps/engine_core/lib/engine_core/rules/saves.ex \
        shards_engine/apps/engine_core/test/morale_test.exs \
        shards_engine/apps/engine_core/test/saves_test.exs
git commit -m "feat: morale checks and 1E save resolution"
```

---

### Task 11: Golden-ledger scripted combat + replay determinism

**Files:**
- Create: `shards_engine/apps/engine_core/lib/engine_core/scenario.ex`
- Test: `shards_engine/apps/engine_core/test/golden_replay_test.exs`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: `Scenario.party_vs_warband(yaml_path, seed) :: %{ledger: [Event.t()], final_world: World.t()}` — 4 hardcoded PCs enter entry_hall, advance one connection per round when no foes are present, trade attacks with same-room goblins; loop ends when one side is dead. Plan 1's acceptance smoke and Plan 3's headless test-player substrate.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EngineCore.GoldenReplayTest do
  use ExUnit.Case, async: false
  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "same yaml + seed + script = byte-identical ledger" do
    r1 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    r2 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    assert :erlang.term_to_binary(r1.ledger) == :erlang.term_to_binary(r2.ledger)
  end

  test "different seed diverges" do
    r1 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    r2 = EngineCore.Scenario.party_vs_warband(@yaml, 5678)
    assert :erlang.term_to_binary(r1.ledger) != :erlang.term_to_binary(r2.ledger)
  end

  test "fold of ledger equals scenario's final world" do
    r = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    {:ok, base} = EngineCore.Loader.load(@yaml)
    refolded = EngineCore.Fold.fold(EngineCore.Scenario.add_party(base), r.ledger)
    assert refolded.tick == r.final_world.tick
    assert refolded.agents == r.final_world.agents
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine && mix test apps/engine_core/test/golden_replay_test.exs`
Expected: FAIL — `EngineCore.Scenario` not defined.

- [ ] **Step 3: Implement the scenario runner**

```elixir
defmodule EngineCore.Scenario do
  @moduledoc """
  Deterministic scripted combat — Plan-1 acceptance proof (replay determinism + fold = state).
  """
  alias EngineCore.{Dice, Fold, Ledger, Loader, Rules.Combat, Rules.Movement, Types, World}

  def party_vs_warband(yaml_path, seed) do
    {:ok, world} = Loader.load(yaml_path)
    rng = Dice.new(seed)
    ledger = start_ledger!()
    world = add_party(world)
    {world, rng} = loop(world, rng, ledger, 100)

    %{ledger: Ledger.events(ledger), final_world: world}
  end

  def add_party(world) do
    pcs =
      for i <- 1..4, into: %{} do
        id = "pc#{i}"

        {id,
         struct!(Types.Agent, id: id, name: "PC#{i}", tier: 3, place_id: "entry_hall",
           statblock: %{ac: 5, hd: 3, hp_max: 16, thac0: 18, morale: 12, int: 10,
                        damage: %{dice: 1, sides: 8, plus: 0}},
           body: %{hp: 16, conditions: []},
           capabilities: [:move, :strike, :wait])}
      end

    %{world | agents: Map.merge(world.agents, pcs)}
  end

  defp start_ledger! do
    ref = make_ref()
    {:ok, _pid} = Ledger.start_link(name: ref)
    ref
  end

  defp loop(world, rng, _ledger, 0), do: {world, rng}

  defp loop(world, rng, ledger, n) do
    {order, rng} = Combat.initiative(rng, alive(world))

    {world, rng} =
      Enum.reduce(order, {world, rng}, fn id, {w, r} -> act(w, r, ledger, id) end)

    if battle_over?(world) do
      {world, rng}
    else
      loop(world, rng, ledger, n - 1)
    end
  end

  defp act(world, rng, ledger, id) do
    case World.agent(world, id) do
      nil -> {world, rng}
      %{body: %{hp: 0}} -> {world, rng}
      a -> choose_action(world, rng, ledger, a)
    end
  end

  defp choose_action(world, rng, ledger, a) do
    foes =
      world
      |> World.agents_in(a.place_id)
      |> Enum.reject(&(&1.id == a.id))
      |> Enum.reject(&(&1.body.hp == 0))

    case foes do
      [] ->
        dest = world.places[a.place_id].connections |> List.first()
        move_or_wait(world, rng, ledger, a, dest)

      [foe | _] ->
        case Combat.attack(world, rng, a.id, foe.id) do
          {:ok, events, w2, r2} ->
            Enum.each(events, &Ledger.append(ledger, &1.class, &1.tick, &1.payload))
            {mark_deaths(w2, ledger, foe.id), r2}

          {:error, _} ->
            {world, rng}
        end
    end
  end

  defp move_or_wait(world, rng, _ledger, _a, nil), do: {world, rng}

  defp move_or_wait(world, rng, ledger, a, dest) do
    case Movement.traverse(world, rng, a.id, dest) do
      {:ok, ev, w2, r2} ->
        Ledger.append(ledger, ev.class, ev.tick, ev.payload)
        {w2, r2}

      {:error, _} ->
        {world, rng}
    end
  end

  defp mark_deaths(world, ledger, target_id) do
    a = World.agent(world, target_id)

    if a && a.body.hp == 0 and :dead not in a.body.conditions do
      Ledger.append(ledger, :world, world.tick, %{kind: :death, agent_id: target_id})

      %{world | agents: Map.update!(world.agents, target_id, fn ag ->
        %{ag | body: %{ag.body | conditions: Enum.uniq([:dead | ag.body.conditions])}}
      end)}
    else
      world
    end
  end

  defp alive(world),
    do: world.agents |> Map.values() |> Enum.filter(&(&1.body.hp > 0)) |> Enum.map(& &1.id)

  defp battle_over?(world) do
    living = alive(world)
    pcs = Enum.filter(living, &String.starts_with?(&1, "pc"))
    (living -- pcs) == [] or pcs == []
  end
end
```

Notes for the implementer:

- `Movement.traverse/4` moves one agent per call; `Enum.reduce` over initiative order gives per-agent movement. Agents with no alive same-room foes and no outgoing connection simply wait (no event) — acceptable for this script.
- The scenario must terminate: 100-round cap plus `battle_over?/1`.
- [ ] **Step 4: Run test to verify it passes; full suite green**

Run: `cd shards_engine && mix test apps/engine_core/test/golden_replay_test.exs && mix test`
Expected: golden tests PASS (3), full suite PASS.

- [ ] **Step 5: CLI smoke (spec §12.4 phase 1 gate)**

Run:

```bash
cd shards_engine && mix run -e '
{:ok, w} = EngineCore.Loader.load("../the-ruined-tower/ruined_tower.yaml")
IO.puts("rooms=#{map_size(w.places)} agents=#{map_size(w.agents)} items=#{map_size(w.items)}")
r = EngineCore.Scenario.party_vs_warband("../the-ruined-tower/ruined_tower.yaml", 1234)
IO.puts("events=#{length(r.ledger)} tick=#{r.final_world.tick}")
'
```

Expected: prints `rooms=7 agents=<tower+4>` and a non-zero event count; exit 0. No wall-clock in output.

- [ ] **Step 6: Commit**

```bash
git add shards_engine/apps/engine_core/lib/engine_core/scenario.ex \
        shards_engine/apps/engine_core/test/golden_replay_test.exs
git commit -m "feat: golden-ledger scripted combat proving replay determinism"
```

---

## Plan 1 Acceptance (maps to spec §12.4 phases 1–2)

- `mix test` green across all 11 test files, offline.
- Real tower YAML passes validation (Task 3) and loads into a coherent 7-room world (Task 4).
- Two identical `Scenario.party_vs_warband/2` calls produce byte-identical ledgers; different seeds diverge; `Fold.fold` reconstructs the final world (Task 11).
- CLI smoke prints world + scenario stats (Task 11 Step 5).
- `grep -rn "DateTime\|NaiveDateTime\|System.time\|:os.time" shards_engine/apps/engine_core/lib` returns nothing.

## Next Plans

- **Plan 2** (spec §12.4 phases 3–4): signals (emission/edge attenuation/reception filters), scheduler (cadences, commitment due-fires, boundary wake/sleep, lazy catch-up), tier-2 pack heuristics, tier-0/1 reflex tables.
- **Plan 3** (spec §12.4 phases 5–8): `llm_gateway` chokepoint, referee pipeline stages, tier-3 brains + salience gate, envelopes/adoption, Phoenix channels + terminal client, acceptance harness with fork-diff.
