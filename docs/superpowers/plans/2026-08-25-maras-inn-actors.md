# Mara's Inn Actors & BDI Cognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mara, Mayor Grevik, Erik the Shepherd, and Anna Mordale as Tier-3 BDI actors in `ruined_tower.yaml` with spatial boundaries, initial commitments, and engine-level dossier prompt formatting.

**Architecture:** Extend `EngineCore.Loader` and `EngineCore.Validator` to ingest actors across multiple keys (`initial_actors`, `initial_enemies`, `monsters`), parse explicit `tier` attributes, and store `dossier` maps on `Types.Agent`. Expose `dossier` through `Referee.Slice` and format it in `Agents.Prompt.deliberate/1` so LLM-driven agents adopt their authentic tabletop persona, goals, and local knowledge.

**Tech Stack:** Elixir (OTP, ExUnit), YAML (`YamlElixir`), AD&D 1E rules engine (`shards_engine`).

## Global Constraints

- Truth barrier preservation: LLM prompts receive only the agent's slice, beliefs, commitments, and dossier; hidden world truth never leaks into prompts.
- Deterministic append-only ledger: World mutations only occur via pure reducers in `World.Server` / `Fold` after referee validation.
- Backwards compatibility: Existing adventures using `initial_enemies` or `monsters` must continue to load identically.
- 100% test pass rate across all umbrella apps (`engine_core`, `llm_gateway`, `agents`, `referee`, `wire`, `client_tui`, `client_web`).

---

### Task 1: Multi-Key Actor Ingestion, Tier Parsing & Dossier Support in `EngineCore.Loader` & `EngineCore.Validator`

**Files:**
- Modify: `shards_engine/apps/engine_core/lib/engine_core/loader.ex:70-200`
- Modify: `shards_engine/apps/engine_core/lib/engine_core/validator.ex:40-185`
- Test: `shards_engine/apps/engine_core/test/loader_test.exs`
- Test: `shards_engine/apps/engine_core/test/validator_test.exs`

**Interfaces:**
- Consumes: Adventure YAML parsed map with optional `initial_actors`, `initial_enemies`, `tier`, and `dossier`.
- Produces: `%EngineCore.Types.Agent{..., tier: integer(), capabilities: [atom()], dossier: map()}`.

- [ ] **Step 1: Write failing unit tests in `loader_test.exs` and `validator_test.exs`**

Add tests to `shards_engine/apps/engine_core/test/loader_test.exs`:
```elixir
  test "loads initial_actors alongside initial_enemies with explicit tier and dossier" do
    raw = %{
      "rooms" => [
        %{"id" => "inn", "name" => "Inn", "kind" => "settlement", "exits" => %{"north" => "hall"}},
        %{"id" => "hall", "name" => "Hall", "kind" => "dungeon", "exits" => %{"south" => "inn"}}
      ],
      "initial_actors" => %{
        "innkeeper" => %{
          "id" => "innkeeper",
          "name" => "Innkeeper",
          "hit_dice" => 1,
          "hit_points" => 6,
          "armor_class" => 10,
          "thac0" => 20,
          "morale" => 8,
          "current_room_id" => "inn",
          "tier" => 3,
          "dossier" => %{
            "role" => "Host",
            "personality" => "Warm",
            "goals" => ["Serve ale", "Share rumors"]
          }
        }
      },
      "initial_enemies" => %{
        "goblin" => %{
          "id" => "goblin_guard_1",
          "name" => "Goblin",
          "hit_dice" => 1,
          "hit_points" => 4,
          "armor_class" => 6,
          "thac0" => 20,
          "morale" => 7,
          "current_room_id" => "hall"
        }
      }
    }

    w = EngineCore.Loader.build(raw)
    assert Map.has_key?(w.agents, "innkeeper")
    assert Map.has_key?(w.agents, "goblin_guard_1")

    innkeeper = w.agents["innkeeper"]
    assert innkeeper.tier == 3
    assert :parley in innkeeper.capabilities
    assert innkeeper.dossier["role"] == "Host"
    assert innkeeper.dossier["goals"] == ["Serve ale", "Share rumors"]
  end
```

Add test to `shards_engine/apps/engine_core/test/validator_test.exs`:
```elixir
  test "accepts initial_actors with standard monster attributes" do
    raw = %{
      "rooms" => %{"inn" => %{"id" => "inn", "exits" => %{"north" => "hall"}}, "hall" => %{"id" => "hall", "exits" => %{"south" => "inn"}}},
      "starting_place" => "inn",
      "initial_actors" => %{
        "mara" => %{
          "id" => "mara",
          "name" => "Mara",
          "hit_dice" => 1,
          "hit_points" => 6,
          "armor_class" => 10,
          "thac0" => 20,
          "morale" => 8,
          "current_room_id" => "inn"
        }
      },
      "initial_enemies" => %{
        "goblin" => %{
          "id" => "goblin",
          "name" => "Goblin",
          "hit_dice" => 1,
          "hit_points" => 4,
          "armor_class" => 6,
          "thac0" => 20,
          "morale" => 7,
          "current_room_id" => "hall"
        }
      }
    }

    assert :ok = EngineCore.Validator.check(raw)
  end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `mix test apps/engine_core/test/loader_test.exs apps/engine_core/test/validator_test.exs`  
Expected: FAIL (`innkeeper` missing from agents because `extract_elements` only took first key).

- [ ] **Step 3: Implement multi-key extraction, tier parsing & dossier population**

In `shards_engine/apps/engine_core/lib/engine_core/loader.ex`:
```elixir
  def build(yaml) when is_map(yaml) do
    rooms = extract_elements(yaml, ["rooms", "places"])

    places =
      Map.new(rooms, fn r ->
        id = r["id"]

        place = %Types.Place{
          id: id,
          name: r["name"] || id,
          kind: parse_kind(r["kind"] || r["type"]),
          connections: extract_connections(r)
        }

        {id, place}
      end)

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

    monsters = extract_elements(yaml, ["initial_actors", "initial_npcs", "initial_enemies", "monsters"])
    agents = Map.new(monsters, fn m -> {m["id"], agent_from(m)} end)

    treasures = extract_elements(yaml, ["initial_treasure", "treasures"])
    items = Map.new(treasures, fn t -> {t["id"], item_from(t)} end)

    starting_place = yaml["starting_place"] || yaml["starting_room"] || "entry_hall"
    world = %World{places: places, edges: edges, agents: agents, items: items, tick: 0, starting_place: starting_place}

    world
    |> put_boundaries(yaml)
    |> put_hazards(yaml)
    |> put_commitments(yaml)
    |> apply_dormancy()
    |> seed_presence_beliefs()
  end

  defp extract_elements(yaml, keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Map.get(yaml, key) do
        nil -> []
        map when is_map(map) -> Map.values(map)
        list when is_list(list) -> list
        _ -> []
      end
    end)
  end

  defp agent_from(m) do
    tier = parse_tier(m)
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
      cadence: cadence_for(tier),
      dossier: m["dossier"] || %{}
    }
  end

  defp parse_tier(m) do
    cond do
      is_integer(m["tier"]) -> m["tier"]
      is_integer(m["cognition_tier"]) -> m["cognition_tier"]
      true -> tier_of(m["id"])
    end
  end
```

In `shards_engine/apps/engine_core/lib/engine_core/validator.ex`:
```elixir
  defp monster_errors(yaml) when is_map(yaml) do
    all_agents =
      ["initial_actors", "initial_npcs", "initial_enemies", "monsters"]
      |> Enum.flat_map(fn key ->
        case Map.get(yaml, key) do
          nil -> []
          map when is_map(map) -> Map.values(map)
          list when is_list(list) -> list
          _ -> []
        end
      end)

    if all_agents == [] do
      ["initial_enemies or initial_actors: key absent"]
    else
      Enum.flat_map(all_agents, fn m ->
        if is_map(m) do
          id = m["id"] || "?"

          Enum.flat_map(@monster_req, fn k ->
            if Map.has_key?(m, k) do
              []
            else
              ["monster #{id}: missing #{k}"]
            end
          end)
        else
          []
        end
      end)
    end
  end

  defp agent_ids(yaml) do
    ["initial_actors", "initial_npcs", "initial_enemies", "monsters"]
    |> Enum.flat_map(fn key ->
      case Map.get(yaml, key) do
        map when is_map(map) ->
          Enum.flat_map(map, fn {k, m} ->
            id = if is_map(m), do: m["id"], else: nil
            [k, id]
          end)

        list when is_list(list) ->
          Enum.map(list, fn m -> if is_map(m), do: m["id"], else: nil end)

        _ ->
          []
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end
```

- [ ] **Step 4: Run tests to verify it passes**

Run: `mix test apps/engine_core`  
Expected: PASS (all tests green).

- [ ] **Step 5: Commit**

```bash
git add apps/engine_core/lib/engine_core/loader.ex apps/engine_core/lib/engine_core/validator.ex apps/engine_core/test/loader_test.exs apps/engine_core/test/validator_test.exs
git commit -m "feat(engine_core): support initial_actors, explicit tier parsing, and agent dossiers"
```

---

### Task 2: Dossier Context Slicing in `Referee.Slice`

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/slice.ex:60-100`
- Test: `shards_engine/apps/referee/test/slice_test.exs`

**Interfaces:**
- Consumes: `%World{}` and `agent_id`.
- Produces: `%{agent: ..., dossier: map(), ...}` slice.

- [ ] **Step 1: Write failing test in `slice_test.exs`**

Add to `shards_engine/apps/referee/test/slice_test.exs`:
```elixir
  test "for_actor includes the agent's dossier map", %{world: world} do
    mara = %Types.Agent{
      id: "mara",
      name: "Mara",
      tier: 3,
      place_id: "entry_hall",
      dossier: %{"role" => "Innkeeper", "personality" => "Warm"}
    }

    world = World.put_agent(world, mara)
    slice = Referee.Slice.for_actor(world, "mara")

    assert slice.dossier == %{"role" => "Innkeeper", "personality" => "Warm"}
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/referee/test/slice_test.exs`  
Expected: FAIL with `KeyError: key :dossier not found in %{...}`.

- [ ] **Step 3: Include `dossier` in `Slice.for_actor/2`**

In `shards_engine/apps/referee/lib/referee/slice.ex`:
```elixir
    %{
      agent: %{id: agent.id, name: agent.name, place_id: agent.place_id},
      dossier: Map.get(agent, :dossier) || %{},
      sheet: sheet(agent),
      place: %{
        id: place.id,
        name: place.name,
        kind: place.kind,
        exits: exits(world, agent.place_id),
        exits_labeled: exits_labeled(world, agent.place_id),
        visible_items: visible_items(world, agent.place_id),
        items: place_items(world, agent.place_id)
      },
      believed: believed,
      believed_agents: believed_agents(world, believed),
      salient: salient,
      commitments: commitments(agent),
      capabilities: agent.capabilities,
      summary: summarize(place, believed, world, agent.id)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/referee/test/slice_test.exs`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/referee/lib/referee/slice.ex apps/referee/test/slice_test.exs
git commit -m "feat(referee): expose agent dossier in slice for deliberation"
```

---

### Task 3: In-Character Dossier Prompt Formatting in `Agents.Prompt`

**Files:**
- Modify: `shards_engine/apps/agents/lib/agents/prompt.ex:1-50`
- Test: `shards_engine/apps/agents/test/deliberate_test.exs`

**Interfaces:**
- Consumes: Slice with `:dossier`.
- Produces: `{system, user, schema}` prompt with formatted persona and goals.

- [ ] **Step 1: Write failing test in `deliberate_test.exs`**

Add to `shards_engine/apps/agents/test/deliberate_test.exs`:
```elixir
  test "deliberation prompt renders dossier role, personality, goals, and rumors" do
    slice = %{
      agent: %{id: "mayor_grevik", name: "Mayor Grevik"},
      place: %{id: "inn", name: "Mara's Inn", exits: ["trail"]},
      commitments: [%{deed: "offer bounty", status: :pending, priority: 8}],
      salient: ["pc_thistle"],
      believed: ["pc_thistle"],
      capabilities: [:move, :wait, :parley, :shout],
      summary: "Mara's Inn. You believe here: Thistle.",
      dossier: %{
        "role" => "Village Mayor",
        "personality" => "Solemn, earnest",
        "goals" => ["Offer 100 gp bounty for investigating tower"],
        "knowledge" => ["Livestock killed 2 nights ago"]
      }
    }

    {_system, user, _schema} = Agents.Prompt.deliberate(slice)

    assert user =~ "Role: Village Mayor"
    assert user =~ "Personality: Solemn, earnest"
    assert user =~ "Goals: Offer 100 gp bounty for investigating tower"
    assert user =~ "Knowledge / Rumors: Livestock killed 2 nights ago"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/agents/test/deliberate_test.exs`  
Expected: FAIL (missing "Role: Village Mayor").

- [ ] **Step 3: Implement `format_dossier/1` in `Agents.Prompt`**

In `shards_engine/apps/agents/lib/agents/prompt.ex`:
```elixir
  @spec deliberate(map()) :: {String.t(), String.t(), map()}
  def deliberate(slice) do
    schema = %{
      type: :object,
      properties: %{
        verb: %{type: :string},
        target_id: %{type: :string, nullable: true},
        direction: %{type: :string, nullable: true},
        message: %{type: :string, nullable: true},
        reason: %{type: :string}
      },
      required: [:verb, :reason]
    }

    system = """
    You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
    tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
    Choose exactly one action for this moment. Respond ONLY with a JSON object:
    {"verb": string, "target_id": string | null, "direction": string | null,
    "message": string | null, "reason": string}.
    verb must be one of your capabilities. target_id must come from your believed
    list — never invent one. Ordering a subordinate uses verb "order", the
    subordinate's id as target_id, and the spoken order as message.
    """

    user = """
    You are #{slice.agent.name} in #{slice.place.name}.
    #{format_dossier(slice[:dossier])}Commitments: #{commitment_lines(slice.commitments)}
    Salient here: #{Enum.join(slice.salient, ", ")}
    Believed here: #{Enum.join(slice.believed, ", ")}
    Exits: #{Enum.join(slice.place.exits, ", ")}
    Capabilities: #{Enum.join(slice.capabilities, ", ")}

    Summary: #{slice.summary}
    """

    {system, user, schema}
  end

  defp format_dossier(nil), do: ""
  defp format_dossier(dossier) when is_map(dossier) and map_size(dossier) == 0, do: ""
  defp format_dossier(dossier) when is_map(dossier) do
    lines =
      []
      |> maybe_add_dossier_line("Role", dossier["role"] || dossier[:role])
      |> maybe_add_dossier_line("Personality", dossier["personality"] || dossier[:personality])
      |> maybe_add_dossier_list("Goals", dossier["goals"] || dossier[:goals])
      |> maybe_add_dossier_list(
        "Knowledge / Rumors",
        dossier["knowledge"] || dossier[:knowledge] || dossier["rumors"] || dossier[:rumors]
      )

    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n") <> "\n"
    end
  end
  defp format_dossier(_), do: ""

  defp maybe_add_dossier_line(acc, _label, nil), do: acc
  defp maybe_add_dossier_line(acc, _label, ""), do: acc
  defp maybe_add_dossier_line(acc, label, val), do: acc ++ ["#{label}: #{val}"]

  defp maybe_add_dossier_list(acc, _label, nil), do: acc
  defp maybe_add_dossier_list(acc, _label, []), do: acc
  defp maybe_add_dossier_list(acc, label, list) when is_list(list),
    do: acc ++ ["#{label}: #{Enum.join(list, "; ")}"]
  defp maybe_add_dossier_list(acc, label, val), do: acc ++ ["#{label}: #{val}"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/agents/test/deliberate_test.exs`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/agents/lib/agents/prompt.ex apps/agents/test/deliberate_test.exs
git commit -m "feat(agents): format agent dossier role, goals, and knowledge in deliberate prompt"
```

---

### Task 4: Add Mara's Inn Actors, Boundary & Commitments to `the-ruined-tower/ruined_tower.yaml`

**Files:**
- Modify: `the-ruined-tower/ruined_tower.yaml`

**Interfaces:**
- Consumes: Spec section 2 definitions.
- Produces: Validated adventure YAML with `mara`, `mayor_grevik`, `erik_the_shepherd`, and `anna_mordale`.

- [ ] **Step 1: Update `the-ruined-tower/ruined_tower.yaml`**

Add `initial_actors:`, the `maras_inn_zone` boundary, and the 4 initial commitments to `ruined_tower.yaml`:
- Actors: `mara`, `mayor_grevik`, `erik_the_shepherd`, `anna_mordale` with full stats, `tier: 3`, `current_room_id: "maras_inn"`, and `dossier` blocks.
- Boundary:
  ```yaml
  - id: "maras_inn_zone"
    place: "maras_inn"
    triggers: ["presence_crossing", "signal_arrived"]
    wake_on_intensity: 4
    sleep_after: 60
  ```
- Commitments:
  - `grevik_quest_offer`: debtor `mayor_grevik`, priority 8, due 1, every 25
  - `anna_rescue_plea`: debtor `anna_mordale`, priority 7, due 2, every 30
  - `erik_raid_warning`: debtor `erik_the_shepherd`, priority 6, due 3, every 35
  - `mara_hospitality_and_rumors`: debtor `mara`, priority 4, due 5, every 45

- [ ] **Step 2: Verify `ruined_tower.yaml` passes loader and validator tests**

Run: `mix test apps/engine_core/test/loader_test.exs`  
Expected: PASS (8 places, all 4 inn actors + dungeon monsters loaded, starting place `maras_inn`).

- [ ] **Step 3: Commit**

```bash
git add the-ruined-tower/ruined_tower.yaml
git commit -m "feat(adventure): define Mara, Mayor Grevik, Erik, and Anna in ruined_tower.yaml"
```

---

### Task 5: End-to-end Integration Verification & Full Umbrella Test Suite

**Files:**
- Test: All umbrella test suites

- [ ] **Step 1: Run full umbrella test suite**

Run: `mix test` in `shards_engine`  
Expected: All tests green across all umbrella apps.

- [ ] **Step 2: Commit any final test cleanups and log engrams progress**

```bash
engrams progress log --status Done --description "Mara's Inn Actors & BDI Cognition implemented and verified"
engrams export
git add engrams/ engrams_export/
git commit -m "chore: log engrams progress and export"
```
