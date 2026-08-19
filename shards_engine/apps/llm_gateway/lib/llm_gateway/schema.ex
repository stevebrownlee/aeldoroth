defmodule LLMGateway.Schema do
  @moduledoc """
  Minimal JSON-schema subset validator for constraining LLM output.

  Supports `type` (:object | :string | :integer | :number | :boolean | :array),
  `properties`, `required`, `enum`, and `items` (subschema applied per element).
  Payload keys may be atoms or strings — both are normalized.
  """

  @spec validate(term(), map()) :: :ok | {:error, String.t()}
  def validate(value, schema) do
    case check(value, schema, "$") do
      :ok -> :ok
      {:error, path, reason} -> {:error, "#{reason} at #{path}"}
    end
  end

  defp check(value, %{type: :object} = schema, path) do
    with :ok <- type_check(value, :object, path) do
      sv = stringify(value)
      req = schema |> Map.get(:required, []) |> Enum.map(&to_string/1)
      props = stringify(Map.get(schema, :properties, %{}))

      missing = Enum.find(req, fn k -> not Map.has_key?(sv, k) end)

      cond do
        missing ->
          {:error, path, "missing required key '#{missing}'"}

        true ->
          Enum.reduce_while(sv, :ok, fn {k, v}, acc ->
            case Map.fetch(props, k) do
              {:ok, sub} ->
                case check(v, sub, "#{path}.#{k}") do
                  :ok -> {:cont, acc}
                  {:error, _, _} = err -> {:halt, err}
                end

              :error ->
                {:cont, acc}
            end
          end)
      end
    end
  end

  defp check(value, %{type: :array} = schema, path) do
    with :ok <- type_check(value, :array, path),
         :ok <- enum_check(value, schema, path) do
      items = Map.get(schema, :items, %{type: :string})

      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {v, i}, acc ->
        case check(v, items, "#{path}[#{i}]") do
          :ok -> {:cont, acc}
          {:error, _, _} = err -> {:halt, err}
        end
      end)
    end
  end

  defp check(value, schema, path) do
    with :ok <- type_check(value, Map.get(schema, :type), path) do
      enum_check(value, schema, path)
    end
  end

  defp type_check(value, type, path) do
    ok =
      case type do
        nil -> true
        :object -> is_map(value)
        :array -> is_list(value)
        :string -> is_binary(value)
        :integer -> is_integer(value)
        :number -> is_number(value)
        :boolean -> is_boolean(value)
      end

    if ok,
      do: :ok,
      else: {:error, path, "expected #{inspect(type)}, got #{typename(value)}"}
  end

  defp enum_check(value, schema, path) do
    case Map.get(schema, :enum) do
      nil ->
        :ok

      allowed ->
        if value in allowed,
          do: :ok,
          else: {:error, path, "value #{inspect(value)} not in enum"}
    end
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp typename(v) when is_map(v), do: "object"
  defp typename(v) when is_list(v), do: "array"
  defp typename(v) when is_binary(v), do: "string"
  defp typename(v) when is_integer(v), do: "integer"
  defp typename(v) when is_float(v), do: "float"
  defp typename(v) when is_boolean(v), do: "boolean"
  defp typename(_), do: inspect("unknown")
end
