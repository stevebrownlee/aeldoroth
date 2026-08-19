defmodule EngineCore.Loader do
  @moduledoc "Adventure YAML → %World{}. Validates first; never mutates the file."

  alias EngineCore.{Types, Validator, World}

  # Cognition tiers keyed by monster id
  @tier3 ~w(grisk_the_snatcher grisk snaga skrit varg murg willem
            goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4
            goblin_bodyguard_1 goblin_bodyguard_2)
  @tier2 ~w(wolf_1 wolf_2 wolf_pair rat_pack_1 rat_pack_2)
  @tier0 ~w(shadow_touched_skeleton shadow_skeleton tripwire_trap_1 tripwire_trap_2)

  @trigger_atoms %{
    "presence_crossing" => :presence_crossing,
    "signal_arrived" => :signal_arrived,
    "commitment_due" => :commitment_due,
    "coarse_tick" => :coarse_tick
  }

  @doc """
  Loads an adventure YAML file from `path`, validates it with Validator.check/1,
  and builds an EngineCore.World struct.
  """
  def load(path) do
    with {:ok, parsed} <- YamlElixir.read_from_file(path),
         :ok <- Validator.check(parsed) do
      {:ok, build(parsed)}
    end
  end

  @doc """
  Builds an EngineCore.World struct from a parsed YAML map.
  """
  def build(yaml) when is_map(yaml) do
    rooms = extract_elements(yaml, ["rooms"])

    places =
      Map.new(rooms, fn r ->
        id = r["id"]

        place = %Types.Place{
          id: id,
          name: r["name"] || id,
          kind: :room,
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

    monsters = extract_elements(yaml, ["initial_enemies", "monsters"])
    agents = Map.new(monsters, fn m -> {m["id"], agent_from(m)} end)

    treasures = extract_elements(yaml, ["initial_treasure", "treasures"])
    items = Map.new(treasures, fn t -> {t["id"], item_from(t)} end)

    world = %World{places: places, edges: edges, agents: agents, items: items, tick: 0}

    world
    |> put_boundaries(yaml)
    |> put_hazards(yaml)
    |> put_commitments(yaml)
    |> apply_dormancy()
  end

  defp extract_elements(yaml, keys) do
    keys
    |> Enum.map(&Map.get(yaml, &1))
    |> Enum.find(& &1)
    |> case do
      nil -> []
      map when is_map(map) -> Map.values(map)
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp extract_connections(r) do
    r
    |> extract_exits()
    |> Enum.map(fn {_dir, c} -> c.target end)
  end

  defp extract_exits(r) do
    cond do
      is_list(r["connections"]) ->
        Enum.map(r["connections"], fn target -> {nil, %{target: target, sealed: false}} end)

      is_map(r["exits"]) ->
        Enum.map(r["exits"], fn
          {dir, target} when is_binary(target) ->
            {dir, %{target: target, sealed: false}}

          {dir, %{"target_room_id" => target} = map} when is_binary(target) ->
            locked =
              map["is_locked"] == true or
                (not is_nil(map["password_required"]) and map["password_required"] != false)

            {dir, %{target: target, sealed: locked}}

          _ ->
            nil
        end)
        |> Enum.reject(&is_nil/1)

      true ->
        []
    end
  end

  defp agent_from(m) do
    tier = tier_of(m["id"])
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
      cadence: cadence_for(tier)
    }
  end

  defp cadence_for(0), do: %{every: 2, next_due: nil}
  defp cadence_for(3), do: %{every: 10, next_due: nil}
  defp cadence_for(2), do: %{every: 5, next_due: nil}
  defp cadence_for(_), do: nil

  defp tier_of(id) when id in @tier3, do: 3
  defp tier_of(id) when id in @tier2, do: 2
  defp tier_of(id) when id in @tier0, do: 0
  defp tier_of(_), do: 1
  defp parse_hd(val) when is_integer(val), do: val

  defp parse_hd(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, _rest} -> n
      :error -> 1
    end
  end

  defp parse_hd(_), do: 1

  defp parse_damage(%{"damage_dice" => d, "damage_sides" => s} = m) do
    %{dice: d, sides: s, plus: m["damage_plus"] || 0}
  end

  defp parse_damage(%{"damage_per_attack" => [dmg_str | _]}) when is_binary(dmg_str) do
    parse_dmg_str(dmg_str)
  end

  defp parse_damage(%{"damage" => dmg_str}) when is_binary(dmg_str) do
    parse_dmg_str(dmg_str)
  end

  defp parse_damage(_), do: %{dice: 1, sides: 4, plus: 0}

  defp parse_dmg_str(str) do
    case Regex.run(~r/(\d+)d(\d+)(?:\s*\+\s*(\d+))?/, str) do
      [_, d, s, p] ->
        %{dice: String.to_integer(d), sides: String.to_integer(s), plus: String.to_integer(p)}

      [_, d, s] ->
        %{dice: String.to_integer(d), sides: String.to_integer(s), plus: 0}

      _ ->
        %{dice: 1, sides: 4, plus: 0}
    end
  end

  defp item_from(t) do
    %Types.Item{
      id: t["id"],
      name: t["name"] || t["id"],
      value_gp: t["value"] || t["value_gp"] || 0,
      place_id: t["location_room_id"] || t["place_id"],
      holder_id: t["holder_id"],
      is_hidden: t["is_hidden"] == true
    }
  end

  defp caps(3), do: [:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee, :order]
  defp caps(2), do: [:move, :strike, :wait, :flee]
  defp caps(_), do: [:move, :strike, :wait]

  defp put_boundaries(world, yaml) do
    boundaries =
      yaml
      |> Map.get("boundaries", [])
      |> Enum.map(fn b ->
        id = b["id"]
        triggers = b["triggers"] |> Enum.map(&Map.get(@trigger_atoms, &1, :invalid))

        bound =
          cond do
            b["agents"] ->
              b["agents"]

            b["group"] ->
              world.agents
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
      id: t["id"],
      kind: kind,
      place_id: room_id,
      edge_id: edge_id,
      dc: t["difficulty_class"] || 12,
      damage: parse_damage(t),
      signal_intensity: (kind == :alarm && 9) || 6,
      signal_class: (kind == :alarm && :alarm) || :combat
    )
  end

  defp hazard_kind("alarm"), do: :alarm
  defp hazard_kind(_), do: :damage

  defp edge_id_for(_room_id, nil, _world), do: nil

  defp edge_id_for(room_id, exit_dir, world) do
    case Enum.find(world.edges, fn e -> e.from == room_id and e.label == exit_dir end) do
      nil -> nil
      e -> e.id
    end
  end

  defp put_commitments(world, yaml) do
    commits =
      yaml
      |> Map.get("initial_commitments", [])
      |> Enum.map(fn c ->
        %Types.Commitment{
          id: c["id"],
          debtor: c["debtor"],
          creditor: c["creditor"],
          deed: c["deed"],
          due: c["due"],
          every: c["every"],
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
end
