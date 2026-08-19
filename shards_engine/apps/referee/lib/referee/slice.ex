defmodule Referee.Slice do
  @moduledoc """
  Truth-barrier actor-visible view (spec §9; pattern: llm-proposes-engine-disposes).

  `for_actor/2` derives everything an LLM prompt may reference for one agent:
  identity, current place + exits, believed agents *at that place*, salient
  (seen) beliefs by salience, and a summary line. Hidden items and agents in
  other places never appear — the slice is the only world data that reaches
  a prompt.
  """

  alias EngineCore.World

  @spec for_actor(World.t(), String.t()) :: %{
          agent: map(),
          place: map(),
          believed: [String.t()],
          salient: [String.t()],
          summary: String.t()
        }
  def for_actor(%World{} = world, agent_id) do
    agent = World.agent(world, agent_id)
    place = World.place(world, agent.place_id)

    believed =
      agent.beliefs
      |> Map.get(agent.place_id, %{})
      |> Map.keys()
      |> Enum.sort()

    salient =
      agent.beliefs
      |> Map.get(agent.place_id, %{})
      |> Enum.filter(fn {_about, b} -> b[:seen] end)
      |> Enum.sort_by(fn {about, b} -> {-b[:salience], about} end)
      |> Enum.map(&elem(&1, 0))

    %{
      agent: %{id: agent.id, name: agent.name, place_id: agent.place_id},
      place: %{
        id: place.id,
        name: place.name,
        kind: place.kind,
        exits: exits(world, agent.place_id),
        visible_items: visible_items(world, agent.place_id)
      },
      believed: believed,
      salient: salient,
      summary: summarize(place, believed, world)
    }
  end

  @doc "Stable content reference for audit rows: lowercase md5 hex of the slice term."
  @spec prompt_slice_ref(map()) :: String.t()
  def prompt_slice_ref(slice) do
    :erlang.md5(:erlang.term_to_binary(slice)) |> Base.encode16(case: :lower)
  end

  defp exits(world, place_id) do
    world.edges
    |> Enum.filter(&(&1.from == place_id))
    |> Enum.map(& &1.to)
    |> Enum.sort()
  end

  defp visible_items(world, place_id) do
    world.items
    |> Map.values()
    |> Enum.filter(&(&1.place_id == place_id and not Map.get(&1, :is_hidden, false)))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp summarize(place, believed, world) do
    names =
      believed
      |> Enum.map(fn about ->
        case World.agent(world, about) do
          nil -> about
          a -> a.name
        end
      end)

    case names do
      [] -> "#{place.name}."
      _ -> "#{place.name}. You believe here: #{Enum.join(names, ", ")}."
    end
  end
end
