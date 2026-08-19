defmodule Referee.Dossier do
  @moduledoc """
  PC dossier (plan 5 Task 4): a handoff summary of what one PC knows.

  One `:summarize` class call whose ONLY inputs are the PC's belief store
  and that PC's `:narration` events (spec §9 truth barrier). Template
  fallback lists the beliefs verbatim and never fails.

  The LLM proposes prose; the engine supplied every fact in it. The caller
  ledgers the returned audit.
  """

  alias EngineCore.Ledger
  alias LLMGateway.{Audit, Ctx, Request, Result, Router}

  @fallback_audit %Audit{class: :summarize, adapter: :template, parse_verdict: :fallback, ok: false}
  @narration_cap 20

  @schema %{
    type: :object,
    properties: %{"dossier" => %{type: :string}},
    required: ["dossier"]
  }

  @doc """
  Build one PC's dossier. `{text, ctx, audit | nil}`; the template path
  makes failure impossible.
  """
  @spec build(Ctx.t(), map(), [Ledger.Event.t()]) :: {String.t(), Ctx.t(), Audit.t() | nil}
  def build(ctx, pc, events) do
    req = %Request{
      class: :summarize,
      agent_id: pc.id,
      system: system_prompt(),
      user: prompt_text(pc, events),
      schema: @schema
    }

    case Router.complete(ctx, req) do
      {:ok, %Result{parsed: %{"dossier" => text}}, audit, ctx2} ->
        {text, ctx2, audit}

      {:error, _reason, nil, ctx2} ->
        {template(pc), ctx2, nil}

      {:error, _reason, _audit, ctx2} ->
        {template(pc), ctx2, %{@fallback_audit | agent_id: pc.id}}
    end
  end

  @doc """
  Truth barrier (spec §9): every fact an LLM prompt may reference — the
  PC's belief lines and this PC's narrations only, narrations capped at
  the most recent #{@narration_cap}.
  """
  @spec prompt_text(map(), [Ledger.Event.t()]) :: String.t()
  def prompt_text(pc, events) do
    """
    PC: #{pc.name} (#{pc.id})
    Beliefs:
    #{belief_block(pc)}
    Narrations:
    #{narration_block(pc, events)}
    """
  end

  defp system_prompt do
    """
    You are the chronicler of a tabletop campaign. Write the named PC's
    dossier: what they currently believe about their surroundings and what
    has just happened to them, in at most four sentences. Use ONLY the
    beliefs and narrations given; never invent rooms, creatures, items, or
    numbers beyond those stated.
    """
  end

  defp belief_block(pc) do
    lines =
      for {place, abouts} <- Enum.sort(pc.beliefs),
          about <- Map.keys(abouts) |> Enum.sort() do
        "- #{place} — #{about}"
      end

    case lines do
      [] -> "- (nothing believed)"
      _ -> Enum.join(lines, "\n")
    end
  end

  defp narration_block(pc, events) do
    texts =
      events
      |> Enum.filter(&(&1.class == :narration and &1.payload[:agent_id] == pc.id))
      |> Enum.map(& &1.payload[:text])
      |> Enum.take(-@narration_cap)

    case texts do
      [] -> "- (none)"
      _ -> Enum.map_join(texts, "\n", &"- #{&1}")
    end
  end

  defp template(pc) do
    lines =
      for {place, abouts} <- Enum.sort(pc.beliefs) do
        abouts = Map.keys(abouts) |> Enum.sort()
        "#{place} — #{Enum.join(abouts, ", ")}"
      end

    case lines do
      [] -> "#{pc.name} recalls little. (narrations elided)"
      _ -> "#{pc.name} recalls: #{Enum.join(lines, "; ")}. (narrations elided)"
    end
  end
end
