defmodule Referee.Narrate do
  @moduledoc """
  Stage 5 of the referee pipeline: outcome → prose. Action outcomes are
  LLM-first through the `:narrate` class, with the engine's deterministic
  templates (decision 31) catching every failure. Received-speech delivery
  is template-only (see `received/4`). Facts never come from the LLM; only
  phrasing does.

  Narration style comes from the referee preference stack: `rich` appends the
  interpret stage's assumptions; `terse` (core default) stays lean.
  """

  alias EngineCore.{Ledger, Narrate, Types}
  alias LLMGateway.{Audit, Ctx, Request, Router}

  @fallback_audit %Audit{class: :narrate, adapter: :template, parse_verdict: :fallback, ok: false}

  @doc """
  Narrate one action's resolution. `resolution` is `{:ok, events}` |
  `{:diegetic_fail, events}` | `{:rejected, reason}`. `opts` may carry
  `assumptions:` (from Interpret) for rich-style rendering.
  """
  @spec action(Ctx.t(), map(), String.t(), Types.Action.t(), tuple(), keyword()) ::
          {String.t(), Ctx.t(), Audit.t()}
  def action(ctx, prefs, actor_id, action, resolution, opts \\ []) do
    case resolution do
      {:rejected, reason} ->
        {reason, ctx, @fallback_audit}

      _ ->
        maybe_llm(ctx, prefs, actor_id, action, resolution, opts)
    end
  end

  @doc """
  Narrate what one PC newly perceived this tick (`:signal_received` payloads).
  Deterministic by design: the words are already organic output of the
  speaking brain's deliberation, so delivery is pure formatting — fidelity-
  gated verbatim quotes through the engine template (decision 31). Never an
  LLM call: re-narration only drops attribution and mangles person.
  """
  @spec received(Ctx.t(), map(), String.t(), [map()]) :: {String.t(), Ctx.t(), Audit.t()}
  def received(ctx, _prefs, pc_id, payloads) do
    lines =
      payloads
      |> Enum.map(&template_line(&1, pc_id))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))

    {Enum.join(lines, " "), ctx,
     %Audit{class: :narrate, adapter: :template, parse_verdict: :skipped, ok: true, agent_id: pc_id}}
  end

  ## LLM path

  defp maybe_llm(ctx, prefs, actor_id, action, resolution, opts) do
    req = %Request{
      class: :narrate,
      agent_id: actor_id,
      system: system_prompt(prefs),
      user: user_prompt(actor_id, action, resolution, opts)
    }

    case Router.complete(ctx, req) do
      {:ok, res, audit, ctx2} ->
        {res.content, ctx2, audit}

      {:error, _reason, _audit, ctx2} ->
        text = template(action, resolution, opts) |> append_assumptions(prefs, opts)
        {text, ctx2, %{@fallback_audit | agent_id: actor_id}}
    end
  end

  defp system_prompt(prefs) do
    """
    You are the referee of a grim fantasy tabletop game. Tone: #{prefs.tone}.
    Narration style: #{prefs.narration_style}. Recount the outcome in at most
    two sentences of second-person prose. Use only the facts given; never
    invent rooms, creatures, items, or numbers beyond those stated.
    """
  end

  defp user_prompt(actor_id, action, resolution, opts) do
    assumptions = Keyword.get(opts, :assumptions, [])
    events = elem(resolution, 1)

    """
    Actor: #{actor_id}
    Action: #{describe(action, opts)}
    Outcome: #{outcome_word(resolution)}
    Events: #{inspect(Enum.map(events, & &1.payload))}
    Assumptions: #{inspect(assumptions)}
    """
  end


  ## Deterministic templates (decision 31)

  defp template(%Types.Action{verb: :wait, params: %{hesitant: true}}, _resolution, _opts),
    do: "You hesitate, unsure, and the moment passes."

  defp template(%Types.Action{verb: :wait}, _resolution, _opts),
    do: "You hold your ground and wait."

  defp template(%Types.Action{verb: :move}, {:diegetic_fail, _events}, _opts),
    do: "You find no way through there."

  defp template(%Types.Action{verb: :move, params: params}, _resolution, _opts),
    do: "You go #{Map.get(params, :direction, "on")}."

  defp template(%Types.Action{verb: :shout, target_id: tid} = action, _resolution, opts)
       when is_binary(tid) do
    who = Keyword.get(opts, :target_name, tid)

    case Map.get(action.params, :message, "") do
      "" -> "You address #{who}."
      msg -> "You say to #{who}: \"#{msg}\""
    end
  end

  defp template(%Types.Action{verb: :shout, params: params}, _resolution, _opts),
    do: "You shout: \"#{Map.get(params, :message, "")}\""

  defp template(%Types.Action{verb: :strike}, {:diegetic_fail, events}, _opts) do
    if Enum.any?(events, &(&1.payload[:kind] == :belief_corrected)) do
      "You swing — but there is nothing there. What you believed was already gone."
    else
      "Your strike finds no mark."
    end
  end

  defp template(%Types.Action{verb: :strike}, {:ok, events}, _opts) do
    damage = Enum.find(events, &(&1.payload[:kind] == :damage))
    death = Enum.find(events, &(&1.payload[:kind] == :death))

    cond do
      death != nil -> "#{hit_phrase(damage)} #{death.payload[:agent_id]} falls."
      damage != nil -> hit_phrase(damage)
      true -> "You strike, but the blow glances away."
    end
  end

  defp template(_action, _resolution, _opts),
    do: "The moment passes."

  defp describe(%Types.Action{verb: verb, target_id: target, params: params}, opts) do
    base = to_string(verb)

    base =
      if target,
        do: base <> " at #{target}" <> name_note(opts),
        else: base

    if params != [], do: base <> " #{inspect(params)}", else: base
  end

  defp name_note(opts) do
    case Keyword.get(opts, :target_name) do
      nil -> ""
      name -> " (#{name})"
    end
  end


  defp hit_phrase(nil), do: "You land a blow."
  defp hit_phrase(%Ledger.Event{payload: %{amount: amount, target_id: target}}),
    do: "You strike #{target} for #{amount} damage."

  defp template_line(p, pc_id) do
    view = %{
      kind: p[:signal_kind],
      intensity: p[:intensity],
      content_core: p[:content_core] || %{class: :voices},
      about: p[:about],
      content_nl: p[:content_nl],
      speaker: p[:speaker_name] || p[:about],
      addressed: get_in(p, [:content_core, :to]) == pc_id
    }

    Narrate.render(view, p[:fidelity] || 1, nil)
  end

  ## Rich-style assumption appending

  defp append_assumptions(text, prefs, opts) do
    case {rich?(prefs), Keyword.get(opts, :assumptions, [])} do
      {true, [_ | _] = as} -> text <> " (assuming: " <> Enum.join(as, "; ") <> ")"
      _ -> text
    end
  end

  defp rich?(prefs), do: prefs[:narration_style] == "rich"


  defp outcome_word({:ok, _}), do: "succeeds"
  defp outcome_word({:diegetic_fail, _}), do: "fails in the fiction"
  defp outcome_word(other), do: inspect(other)
end
