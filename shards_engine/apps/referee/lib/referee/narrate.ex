defmodule Referee.Narrate do
  @moduledoc """
  Stage 5 of the referee pipeline: outcome → prose. LLM-first through the
  `:narrate` class; the engine's deterministic templates (decision 31) catch
  every failure — no route, budget-degraded narrate, circuit open, adapter
  error. Facts never come from the LLM; only phrasing does.

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
  Template fallback renders through the engine's fidelity ladder.
  """
  @spec received(Ctx.t(), map(), String.t(), [map()]) :: {String.t(), Ctx.t(), Audit.t()}
  def received(ctx, prefs, pc_id, payloads) do
    req = %Request{
      class: :narrate,
      agent_id: pc_id,
      system: system_prompt(prefs),
      user: received_prompt(payloads)
    }

    case Router.complete(ctx, req) do
      {:ok, res, audit, ctx2} ->
        {res.content, ctx2, audit}

      {:error, _reason, _audit, ctx2} ->
        lines =
          payloads
          |> Enum.map(&template_line/1)
          |> Enum.reject(&(&1 == ""))

        {Enum.join(lines, " "), ctx2, %{@fallback_audit | agent_id: pc_id}}
    end
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
    Action: #{describe(action)}
    Outcome: #{outcome_word(resolution)}
    Events: #{inspect(Enum.map(events, & &1.payload))}
    Assumptions: #{inspect(assumptions)}
    """
  end

  defp received_prompt(payloads) do
    Enum.map_join(payloads, "\n", fn p ->
      "perceived: kind=#{p[:signal_kind]} intensity=#{p[:intensity]} fidelity=#{p[:fidelity]} about=#{p[:about]}"
    end)
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

  defp hit_phrase(nil), do: "You land a blow."

  defp hit_phrase(%Ledger.Event{payload: %{amount: amount, target_id: target}}),
    do: "You strike #{target} for #{amount} damage."

  defp template_line(p) do
    view = %{
      kind: p[:signal_kind],
      intensity: p[:intensity],
      content_core: %{class: :voices},
      about: p[:about],
      content_nl: nil
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

  defp describe(%Types.Action{verb: verb, target_id: target, params: params}) do
    base = to_string(verb)
    base = if target, do: base <> " at #{target}", else: base
    if params != [], do: base <> " #{inspect(params)}", else: base
  end

  defp outcome_word({:ok, _}), do: "succeeds"
  defp outcome_word({:diegetic_fail, _}), do: "fails in the fiction"
  defp outcome_word(other), do: inspect(other)
end
