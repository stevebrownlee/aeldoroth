defmodule Wire.JSONSafe do
  @moduledoc """
  Wire-boundary JSON projection (spec §11): the ledger's raw tail carries
  engine terms — structs (agent_added's `Agent`, replay data for Fold) and
  opaque binaries (the prefs-stack md5 digest). Those are correct in the
  engine and unencodable on a real socket. The wire owns JSON safety:
  structs project to plain maps, non-UTF-8 binaries project to hex.

  The ledger itself is never rewritten — this is a view, applied only at
  push time (determinism contract untouched).
  """

  @spec to_json(term()) :: term()
  def to_json(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> to_json()
  end

  def to_json(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_json(k), to_json(v)} end)
  end

  def to_json(list) when is_list(list), do: Enum.map(list, &to_json/1)

  def to_json(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> to_json()

  def to_json(binary) when is_binary(binary) do
    if String.valid?(binary), do: binary, else: Base.encode16(binary)
  end

  def to_json(atom) when is_nil(atom) or is_boolean(atom), do: atom
  def to_json(atom) when is_atom(atom), do: Atom.to_string(atom)
  def to_json(number) when is_integer(number) or is_float(number), do: number
end
