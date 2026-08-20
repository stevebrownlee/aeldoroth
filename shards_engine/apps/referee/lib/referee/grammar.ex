defmodule Referee.Grammar do
  @moduledoc """
  Deterministic NL parser — the fallback when the LLM fails or misreturns
  (decision 32: grammar runs only on failure; LLM-first is the point).

  Ambiguity policy (decision 21): `{:ambiguous, candidates}` for lethal verbs
  (strike/shoot) when more than one believed agent matches the object token
  equally. `{:unclear, rest}` otherwise — the caller renders the hesitation.
  """

  alias EngineCore.{Types, World}

  @directions %{
    "north" => "north", "n" => "north",
    "south" => "south", "s" => "south",
    "east" => "east", "e" => "east",
    "west" => "west", "w" => "west",
    "up" => "up", "u" => "up",
    "down" => "down", "d" => "down",
    "northeast" => "northeast", "ne" => "northeast",
    "northwest" => "northwest", "nw" => "northwest",
    "southeast" => "southeast", "se" => "southeast",
    "southwest" => "southwest", "sw" => "southwest"
  }

  @verbs %{
    "go" => :move,
    "move" => :move,
    "walk" => :move,
    "head" => :move,
    "run" => :move,
    "travel" => :move,
    "enter" => :move,
    "step" => :move,
    "advance" => :move,
    "attack" => :strike,
    "strike" => :strike,
    "hit" => :strike,
    "stab" => :strike,
    "shoot" => :strike,
    "slash" => :strike,
    "kill" => :strike,
    "smite" => :strike,
    "bash" => :strike,
    "slay" => :strike,
    "fire" => :strike,
    "shout" => :shout,
    "yell" => :shout,
    "scream" => :shout,
    "call" => :shout,
    "say" => :shout,
    "speak" => :shout,
    "tell" => :shout,
    "wait" => :wait,
    "hold" => :wait,
    "look" => :wait,
    "examine" => :wait,
    "inspect" => :wait,
    "search" => :wait,
    "peer" => :wait,
    "watch" => :wait,
    "listen" => :wait,
    "rest" => :wait,
    "pause" => :wait,
    "scout" => :wait,
    "explore" => :wait
  }

  # Leading filler a player types before the verb: "I go north", "let's wait".
  @filler ~w(i we you lets let's let my please carefully cautiously quickly slowly)
  # Prepositions to strip during movement target parsing: "walk into the library".
  @prepositions ~w(to the into through toward towards in at over around for)

  @spec parse(World.t(), String.t(), String.t()) ::
          Types.Action.t() | {:ambiguous, [String.t()]} | {:unclear, String.t()}
  def parse(world, actor_id, utterance) do
    text = utterance |> String.trim() |> String.replace(~r/\s+/, " ")

    words =
      text
      |> String.split(" ", trim: true)
      |> Enum.drop_while(fn w -> String.downcase(w) in @filler end)

    case words do
      [verb | rest] ->
        verb_lower = String.downcase(verb)

        cond do
          # 1. Bare direction (e.g. "north", "east", "n", "down")
          Map.has_key?(@directions, verb_lower) ->
            canonical = Map.fetch!(@directions, verb_lower)
            struct!(Types.Action, actor_id: actor_id, verb: :move, params: %{direction: canonical})

          # 2. Bare room or exit name (e.g. "library", "guard_room")
          is_map_key(world.places, verb_lower) ->
            struct!(Types.Action, actor_id: actor_id, verb: :move, target_id: verb_lower)

          # 3. Known action verb
          action_verb = Map.get(@verbs, verb_lower) ->
            case action_verb do
              :move -> parse_move(world, actor_id, rest)
              :strike -> parse_strike(world, actor_id, text, rest)
              :shout -> parse_shout(actor_id, text)
              :wait -> struct!(Types.Action, actor_id: actor_id, verb: :wait)
            end

          true ->
            {:unclear, text}
        end

      [] ->
        {:unclear, text}
    end
  end

  defp parse_move(world, actor_id, rest) do
    filtered = Enum.drop_while(rest, fn w -> String.downcase(w) in @prepositions end)

    case filtered do
      [first | _] ->
        dir_candidate = String.downcase(first)

        case Map.get(@directions, dir_candidate) do
          canonical when is_binary(canonical) ->
            struct!(Types.Action,
              actor_id: actor_id,
              verb: :move,
              params: %{direction: canonical}
            )

          nil ->
            target_str = Enum.map_join(filtered, "_", &String.downcase/1)
            target_clean = String.downcase(first)

            cond do
              is_map_key(world.places, target_str) ->
                struct!(Types.Action, actor_id: actor_id, verb: :move, target_id: target_str)

              is_map_key(world.places, target_clean) ->
                struct!(Types.Action, actor_id: actor_id, verb: :move, target_id: target_clean)

              true ->
                struct!(Types.Action,
                  actor_id: actor_id,
                  verb: :move,
                  params: %{direction: dir_candidate}
                )
            end
        end

      [] ->
        {:unclear, "go"}
    end
  end

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

      matches ->
        sorted = Enum.sort_by(matches, fn {_id, score} -> score end, :desc)
        {_best_id, max_score} = hd(sorted)
        top = Enum.filter(sorted, fn {_id, score} -> score == max_score end)

        case top do
          [{id, _}] -> {:ok, id}
          ties -> {:ambiguous, Enum.map(ties, fn {id, _} -> id end)}
        end
    end
  end

  defp name_tokens(name) do
    name |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp overlap(object, tokens) do
    obj_tokens = name_tokens(object)
    Enum.count(obj_tokens, fn t -> t in tokens end)
  end
end
