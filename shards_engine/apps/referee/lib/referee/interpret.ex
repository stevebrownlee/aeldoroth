defmodule Referee.Interpret do
  @moduledoc """
  Stage 1 of the referee pipeline: NL intent → `Types.Action` (decision 20).

  LLM-first: one `:interpret` class call whose schema pins verb/target/params.
  On failure — no route, circuit open, unparseable JSON, schema-invalid —
  the deterministic `Grammar` runs (decision 32). Grammar ambiguity on a
  lethal verb yields `{:clarify, question}` — never a guess (decision 21).
  """

  alias EngineCore.{Types, World}
  alias LLMGateway.{Audit, Ctx, Request, Result, Router}
  alias Referee.{Grammar, Slice}

  @schema %{
    type: :object,
    properties: %{
      verb: %{type: :string, enum: ~w(move strike shout wait)},
      target_id: %{type: :string, nullable: true},
      params: %{type: :object},
      assumptions: %{type: :array, items: %{type: :string}}
    },
    required: [:verb]
  }

  @spec nl_to_action(Ctx.t(), World.t(), String.t(), String.t()) ::
          {:ok, Types.Action.t(), [String.t()], Ctx.t(), Audit.t() | nil}
          | {:clarify, String.t(), Ctx.t(), Audit.t() | nil}
  def nl_to_action(ctx, world, actor_id, utterance) do
    slice = Slice.for_actor(world, actor_id)

    req = %Request{
      class: :interpret,
      agent_id: actor_id,
      system: system_prompt(),
      user: user_prompt(slice, utterance),
      schema: @schema
    }

    case Router.complete(ctx, req) do
      {:ok, %Result{parsed: %{} = parsed}, audit, ctx2} ->
        {:ok, to_action(parsed, actor_id), Map.get(parsed, "assumptions", []), ctx2, audit}

      {:ok, _result, audit, ctx2} ->
        fallback(ctx2, world, actor_id, utterance, audit)

      {:error, _reason, audit, ctx2} ->
        fallback(ctx2, world, actor_id, utterance, audit)
    end
  end

  # Grammar runs only on LLM failure (decision 32): LLM-first is the point.
  defp fallback(ctx, world, actor_id, utterance, audit) do
    case Grammar.parse(world, actor_id, utterance) do
      %Types.Action{} = action ->
        {:ok, action, ["grammar fallback used"], ctx, fallback_audit(audit)}

      {:ambiguous, ids} ->
        names = ids |> Enum.map(&World.agent(world, &1).name) |> Enum.join(", ")
        {:clarify, "which one do you mean — #{names}?", ctx, fallback_audit(audit)}

      {:unclear, rest} ->
        action = struct!(Types.Action, actor_id: actor_id, verb: :wait, params: %{hesitant: true})
        {:ok, action, ["could not parse \"#{rest}\"; you hold"], ctx, fallback_audit(audit)}
    end
  end

  # The interpretation stage succeeded via grammar; the audit records the
  # fallback verdict while keeping any tokens the failed LLM attempt spent.
  defp fallback_audit(nil), do: %Audit{class: :interpret, adapter: :grammar, parse_verdict: :fallback, ok: true}
  defp fallback_audit(%Audit{} = a), do: %Audit{a | parse_verdict: :fallback, ok: true}

  defp to_action(parsed, actor_id) do
    verb = String.to_existing_atom(Map.fetch!(parsed, "verb"))

    params =
      %{}
      |> maybe_put(:direction, get_in(parsed, ["params", "direction"]))
      |> maybe_put(:message, get_in(parsed, ["params", "message"]))

    struct!(Types.Action,
      actor_id: actor_id,
      verb: verb,
      target_id: parsed["target_id"],
      params: params
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp system_prompt do
    """
    You are the referee's intent interpreter for a tabletop RPG. Convert the
    player's utterance into one action. Respond ONLY with a JSON object:
    {"verb": "move" | "strike" | "shout" | "wait", "target_id": string | null,
    "params": {"direction": string | null, "message": string | null},
    "assumptions": [string]}.
    Verbs:
    - "move": moving, walking, exploring in a direction (params.direction: "north", "south", "east", "west", "up", "down", etc.) or heading toward an exit/room
    - "strike": attacking, fighting, or striking a target (target_id must be from believed list)
    - "shout": speaking, saying, asking, talking, calling out, greeting, questioning, or addressing someone (params.message: the spoken text or inquiry, target_id: target agent id if addressing someone specific, or null)
    - "wait": waiting, pausing, resting, examining, searching, or looking around (params: {})
    target_id must be an id from the believed list you are given — never invent one.
    """
  end

  defp user_prompt(slice, utterance) do
    believed_list =
      Enum.map_join(slice[:believed_agents] || slice.believed_agents || [], ", ", fn a ->
        "#{a[:name] || a.name} (#{a[:id] || a.id})"
      end)

    """
    Scene: #{slice.summary}
    Believed here: #{believed_list}
    Exits: #{Enum.join(slice.place.exits, ", ")}

    Player says: "#{utterance}"
    """
  end
end
