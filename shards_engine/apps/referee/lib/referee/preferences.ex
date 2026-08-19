defmodule Referee.Preferences do
  @moduledoc """
  Referee preference stack: core 1E defaults < module (adventure) YAML < personal referee YAML.

  `resolve/2` deep-merges known-key trees only; unknown keys at any depth are
  dropped with a warning. The resolved tree is plain data — `hash/1` gives a
  stable, value-sensitive fingerprint for audit records.
  """

  require Logger

  @core %{
    tone: "neutral",
    narration_style: "terse",
    lethality: "standard",
    dice_visibility: "open",
    xp: %{gold_per_xp: 1, creative_bonus: true}
  }

  @spec core() :: map()
  def core, do: deep_copy(@core)

  @spec resolve(map(), map()) :: map()
  def resolve(module_prefs, personal_prefs)
      when is_map(module_prefs) and is_map(personal_prefs) do
    known(@core, module_prefs, []) |> known(personal_prefs, [])
  end

  @doc "Load a YAML layer; nil/missing path → empty map (layer absent)."
  @spec load(Path.t() | nil) :: map()
  def load(nil), do: %{}
  def load(path), do: YamlElixir.read_from_file(path) || %{}

  @spec hash(map()) :: integer()
  def hash(prefs), do: :erlang.phash2(sort_tree(prefs))

  # Deep-merge `over` onto `base`, keeping only keys known in `base`'s schema.
  # Nested maps recurse; scalars replace.
  defp known(base, over, path) do
    Enum.reduce(over, base, fn {k, v}, acc ->
      key = to_atom(k)

      case Map.get(base, key) do
        nil ->
          Logger.warning("preferences: dropping unknown key #{Enum.join(path ++ [key], ".")}")
          acc

        %{} = nested when is_map(v) ->
          Map.put(acc, key, known(nested, v, path ++ [key]))

        %{} = _nested ->
          Map.put(acc, key, v)

        _scalar ->
          Map.put(acc, key, v)
      end
    end)
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_existing_atom(k)

  # Canonical ordering so phash2 never distinguishes equal maps by key order.
  defp sort_tree(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, sort_tree(v)} end)
  defp sort_tree(v) when is_list(v), do: Enum.map(v, &sort_tree/1)
  defp sort_tree(v), do: v

  defp deep_copy(t), do: sort_tree(t)
end
