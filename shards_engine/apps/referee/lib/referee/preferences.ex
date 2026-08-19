defmodule Referee.Preferences do
  @moduledoc """
  Referee preference stack: core 1E defaults < module (adventure) YAML < personal referee YAML.

  `resolve/2` deep-merges known-key trees only; unknown keys at any depth are
  dropped and reported as warning strings. `hash/1` is a stable,
  value-sensitive md5 of the canonically ordered resolved tree.
  """

  @core %{
    tone: "neutral",
    narration_style: "terse",
    lethality: "standard",
    dice_visibility: "open",
    xp: %{gold_per_xp: 1, creative_bonus: true}
  }

  @spec core() :: map()
  def core, do: deep_copy(@core)

  @spec resolve(map() | nil, map() | nil) :: {map(), [String.t()]}
  def resolve(module_prefs, personal_prefs) do
    {m, w1} = known(@core, module_prefs || %{}, [])
    {p, w2} = known(m, personal_prefs || %{}, [])
    {p, w1 ++ w2}
  end

  @doc "Load a YAML layer; nil/missing path → empty map (layer absent)."
  @spec load(Path.t() | nil) :: map()
  def load(nil), do: %{}
  def load(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  @spec hash(map()) :: binary()
  def hash(prefs), do: :erlang.md5(:erlang.term_to_binary(sort_tree(prefs)))

  # Deep-merge `over` onto `base`, keeping only keys known in `base`'s schema.
  # Nested maps recurse; scalars replace. Returns {merged, warnings}.
  defp known(base, over, path) do
    Enum.reduce(over, {base, []}, fn {k, v}, {acc, warns} ->
      key = to_atom(k)

      case Map.get(base, key) do
        nil ->
          dotted = path ++ [key] |> Enum.join(".") |> maybe_quote(k)
          {acc, warns ++ ["unknown preference key: #{dotted}"]}

        %{} = nested when is_map(v) ->
          {inner, w} = known(nested, v, path ++ [key])
          {Map.put(acc, key, inner), warns ++ w}

        %{} = _nested ->
          {Map.put(acc, key, v), warns}

        _scalar ->
          {Map.put(acc, key, v), warns}
      end
    end)
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_existing_atom(k)

  defp maybe_quote(dotted, k) when is_binary(k), do: "'#{dotted}'"
  defp maybe_quote(dotted, _k), do: dotted

  # Canonical ordering so the hash never distinguishes equal maps by key order.
  defp sort_tree(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, sort_tree(v)} end)
  defp sort_tree(v) when is_list(v), do: Enum.map(v, &sort_tree/1)
  defp sort_tree(v), do: v

  defp deep_copy(t), do: sort_tree(t)
end
