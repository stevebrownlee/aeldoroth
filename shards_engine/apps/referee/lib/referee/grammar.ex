defmodule Referee.Grammar do
  @moduledoc """
  Deterministic NL parser — the fallback when the LLM fails or misreturns
  (decision 32: grammar runs only on failure; LLM-first is the point).

  Ambiguity policy (decision 21): `{:ambiguous, candidates}` for lethal verbs
  (strike/shoot) when more than one believed agent matches the object token
  equally. `{:unclear, rest}` otherwise — the caller renders the hesitation.
  """

  alias EngineCore.{Types, World}

  @verbs %{
    "go" => :move,
    "move" => :move,
    "walk" => :move,
    "head" => :move,
    "run" => :move,
    "attack" => :strike,
    "strike" => :strike,
    "hit" => :strike,
    "stab" => :strike,
    "shoot" => :strike,
    "slash" => :strike,
    "kill" => :strike,
    "shout" => :shout,
    "yell" => :shout,
    "scream" => :shout,
    "call" => :shout,
    "wait" => :wait,
    "hold" => :wait
  }

  @spec parse(World.t(), String.t(), String.t()) ::
          Types.Action.t() | {:ambiguous, [String.t()]} | {:unclear, String.t()}
  def parse(world, actor_id, utterance) do
    text = utterance |> String.trim() |> String.replace(~r/\s+/, " ")
    words = String.split(text, " ", trim: true)

    case words do
      [verb | rest] ->
        case Map.get(@verbs, String.downcase(verb)) do
          nil -> {:unclear, text}
          :move -> parse_move(actor_id, rest)
          :strike -> parse_strike(world, actor_id, text, rest)
          :shout -> parse_shout(actor_id, text)
          :wait -> struct!(Types.Action, actor_id: actor_id, verb: :wait)
        end

      [] ->
        {:unclear, text}
    end
  end

  defp parse_move(actor_id, [dir | _rest]) do
    struct!(Types.Action,
      actor_id: actor_id,
      verb: :move,
      params: %{direction: String.downcase(dir)}
    )
  end

  defp parse_move(_actor_id, []), do: {:unclear, "go"}

  defp parse_strike(world, actor_id, text, _rest) do
    object = object_phrase(text)

    case resolve_believed(world, actor_id, object) do
      {:ok, id} ->
        struct!(Types.Action, actor_id: actor_id, verb: :strike, target_id: id)

      {:ambiguous, ids} ->
        {:ambiguous, ids}

      :none ->
        {:unclear, text}
    end
  end

  defp parse_shout(actor_id, text) do
    message =
      case Regex.run(~r/['"](.*)['"]/, text) do
        [_, msg] -> msg
        nil -> String.trim(String.replace(text, ~r/^\S+\s*/, ""))
      end

    struct!(Types.Action, actor_id: actor_id, verb: :shout, params: %{message: message})
  end

  # "attack the goblin guard" -> "goblin guard"; strips articles and the verb.
  defp object_phrase(text) do
    text
    |> String.replace(~r/^\S+\s+(the\s+|a\s+|an\s+)?/i, "")
    |> String.trim()
  end

  # Token overlap against believed agent names in the actor's current place.
  # Exact single match wins; >1 match with equal (maximal) overlap on a
  # lethal verb is ambiguity; anything else is no match.
  defp resolve_believed(world, actor_id, object) do
    actor = world.agents[actor_id]
    believed = actor && Map.get(actor.beliefs, actor.place_id, %{})

    candidates =
      for {id, _belief} <- believed || %{},
          agent = world.agents[id],
          tokens = name_tokens(agent.name) ++ name_tokens(id),
          score = overlap(object, tokens),
          score > 0,
          do: {id, score}

    case candidates do
      [] ->
        :none

      [{id, _}] ->
        {:ok, id}

      many ->
        max_score = many |> Enum.map(fn {_, s} -> s end) |> Enum.max()

        case Enum.filter(many, fn {_, s} -> s == max_score end) do
          [{id, _}] -> {:ok, id}
          ties -> {:ambiguous, ties |> Enum.map(fn {id, _} -> id end) |> Enum.sort()}
        end
    end
  end

  defp name_tokens(name) do
    name |> String.downcase() |> String.split(~r/[^a-z0-9_]+/, trim: true)
  end

  defp overlap(object, tokens) do
    obj_tokens = name_tokens(object)
    Enum.count(obj_tokens, fn t -> t in tokens end)
  end
end
