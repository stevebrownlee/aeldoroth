defmodule EngineCore.Validator do
  @moduledoc """
  Structural integrity checks for adventure YAML. Pure, no state.
  """

  @monster_req ~w(id name hit_dice hit_points armor_class thac0 morale current_room_id)
  @orphan_fragment ~r/\(\d+ \(\d/
  @valid_triggers MapSet.new(~w(presence_crossing signal_arrived commitment_due coarse_tick))

  @doc """
  Reads YAML from file and runs structural checks.
  """
  def check_file(path) do
    with {:ok, parsed} <- YamlElixir.read_from_file(path) do
      check(parsed)
    end
  end

  @doc """
  Runs structural checks on parsed YAML map.
  """
  def check(yaml) when is_map(yaml) do
    rooms_set = room_ids(yaml)
    agents_set = agent_ids(yaml)

    errors =
      monster_errors(yaml) ++
        text_errors(yaml) ++
        room_errors(yaml) ++
        boundary_errors(yaml, rooms_set) ++
        commitment_errors(yaml, agents_set)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  def check(_), do: {:error, ["invalid YAML document: expected a map"]}

  defp monster_errors(%{"initial_enemies" => enemies}) when is_map(enemies) do
    Enum.flat_map(Map.values(enemies), fn m ->
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

  defp monster_errors(_), do: ["initial_enemies: key absent"]

  defp text_errors(yaml) do
    yaml
    |> walk_strings()
    |> Enum.filter(&Regex.match?(@orphan_fragment, &1.elem))
    |> Enum.map(&"#{&1.path}: orphan fragment #{inspect(&1.elem)}")
  end

  defp room_errors(%{"rooms" => rooms}) when is_map(rooms) do
    room_ids =
      rooms
      |> Enum.flat_map(fn {k, r} ->
        id = if is_map(r), do: r["id"], else: nil
        [k, id]
      end)
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    Enum.flat_map(Map.values(rooms), fn r ->
      if is_map(r) do
        room_id = r["id"] || "?"
        exits = r["exits"]

        if is_map(exits) do
          Enum.flat_map(exits, fn {_dir, exit_val} ->
            target =
              cond do
                is_binary(exit_val) -> exit_val
                is_map(exit_val) -> exit_val["target_room_id"]
                true -> nil
              end

            if is_binary(target) and not MapSet.member?(room_ids, target) do
              ["room #{room_id}: connection to unknown room #{target}"]
            else
              []
            end
          end)
        else
          []
        end
      else
        []
      end
    end)
  end

  defp room_errors(_), do: []

  defp walk_strings(term, path \\ "$")

  defp walk_strings(m, path) when is_map(m) do
    Enum.flat_map(m, fn {k, v} ->
      walk_strings(v, "#{path}.#{k}")
    end)
  end

  defp walk_strings(l, path) when is_list(l) do
    l
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} ->
      walk_strings(v, "#{path}[#{i}]")
    end)
  end

  defp walk_strings(s, path) when is_binary(s), do: [%{path: path, elem: s}]
  defp walk_strings(_, _), do: []

  defp room_ids(%{"rooms" => rooms}) when is_map(rooms) do
    rooms
    |> Enum.flat_map(fn {k, r} ->
      id = if is_map(r), do: r["id"], else: nil
      [k, id]
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp room_ids(%{"rooms" => rooms}) when is_list(rooms) do
    rooms
    |> Enum.map(fn r -> if is_map(r), do: r["id"], else: nil end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp room_ids(_), do: MapSet.new()

  defp agent_ids(yaml) do
    enemies = yaml["initial_enemies"] || yaml["monsters"]

    cond do
      is_map(enemies) ->
        enemies
        |> Enum.flat_map(fn {k, m} ->
          id = if is_map(m), do: m["id"], else: nil
          [k, id]
        end)
        |> Enum.filter(&is_binary/1)
        |> MapSet.new()

      is_list(enemies) ->
        enemies
        |> Enum.map(fn m -> if is_map(m), do: m["id"], else: nil end)
        |> Enum.filter(&is_binary/1)
        |> MapSet.new()

      true ->
        MapSet.new()
    end
  end

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
    b
    |> Map.get("triggers", [])
    |> Enum.flat_map(fn t ->
      if MapSet.member?(@valid_triggers, t),
        do: [],
        else: ["boundary #{id}: invalid trigger #{t}"]
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

      if c["debtor"] in agent_ids,
        do: [],
        else: ["commitment #{id}: unknown debtor #{c["debtor"]}"]
    end)
  end

  defp commitment_errors(_, _), do: []
end
