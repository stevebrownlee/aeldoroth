defmodule EngineCore.Loader do
  @moduledoc "Adventure YAML → %World{}. Validates first; never mutates the file."

  alias EngineCore.{Types, Validator, World}

  # Cognition tiers keyed by monster id
  @tier3 ~w(grisk_the_snatcher grisk snaga skrit varg murg willem)
  @tier2 ~w(wolf_1 wolf_2 wolf_pair giant_rat_1 giant_rat_2 giant_rat_3 rat_pack_1 rat_pack_2)
  @tier0 ~w(shadow_touched_skeleton shadow_skeleton tripwire_trap_1 tripwire_trap_2)

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
          c <- extract_exits(r),
          do: %Types.Edge{
            id: :"#{r["id"]}__#{c.target}",
            from: r["id"],
            to: c.target,
            sealed: c.sealed
          }

    monsters = extract_elements(yaml, ["initial_enemies", "monsters"])
    agents = Map.new(monsters, fn m -> {m["id"], agent_from(m)} end)

    treasures = extract_elements(yaml, ["initial_treasure", "treasures"])
    items = Map.new(treasures, fn t -> {t["id"], item_from(t)} end)

    %World{places: places, edges: edges, agents: agents, items: items, tick: 0}
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
    |> Enum.map(& &1.target)
  end

  defp extract_exits(r) do
    cond do
      is_list(r["connections"]) ->
        Enum.map(r["connections"], fn target -> %{target: target, sealed: false} end)

      is_map(r["exits"]) ->
        Enum.map(r["exits"], fn
          {_dir, target} when is_binary(target) ->
            %{target: target, sealed: false}

          {_dir, %{"target_room_id" => target} = map} when is_binary(target) ->
            locked = map["is_locked"] == true or (not is_nil(map["password_required"]) and map["password_required"] != false)
            %{target: target, sealed: locked}

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
      capabilities: caps(tier)
    }
  end

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
      [_, d, s, p] -> %{dice: String.to_integer(d), sides: String.to_integer(s), plus: String.to_integer(p)}
      [_, d, s] -> %{dice: String.to_integer(d), sides: String.to_integer(s), plus: 0}
      _ -> %{dice: 1, sides: 4, plus: 0}
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

  defp caps(3), do: [:move, :strike, :wait, :shout, :hide, :parley, :obey, :flee]
  defp caps(2), do: [:move, :strike, :wait, :flee]
  defp caps(_), do: [:move, :strike, :wait]
end
