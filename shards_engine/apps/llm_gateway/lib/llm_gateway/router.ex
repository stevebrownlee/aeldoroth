defmodule LLMGateway.Router do
  @moduledoc """
  The single chokepoint for all LLM traffic (pattern: llm-gateway-single-chokepoint).

  Pure: `complete/2` threads a `Ctx` through and returns the updated one.
  Order of operations (spec §10): route lookup → budget gate (class-aware
  degradation order: narrate drops first, interpret at 2× cap) → circuit
  breaker → adapter call → schema parse with ONE bounded retry → audit +
  ctx update.

  Adapters are callable ONLY from this module.
  """

  alias LLMGateway.{Audit, Ctx, Request, Result, Schema}

  @breaker_threshold 3
  @interpret_cap_multiple 2

  @type complete_ok :: {:ok, Result.t(), Audit.t(), Ctx.t()}
  @type complete_err :: {:error, term(), Audit.t() | nil, Ctx.t()}

  @spec complete(Ctx.t(), Request.t()) :: complete_ok() | complete_err()
  def complete(%Ctx{} = ctx, %Request{} = req) do
    case Map.fetch(ctx.routing, req.class) do
      :error ->
        {:error, :no_route, nil, ctx}

      {:ok, cfg} ->
        cond do
          degraded?(req.class, ctx.budget) ->
            {:error, :budget_degraded, nil, ctx}

          open?(ctx.breaker, cfg.adapter) ->
            {:error, :circuit_open, audit(req, cfg, 0, 0, :skipped, false), ctx}

          true ->
            call(ctx, req, cfg, 0)
        end
    end
  end

  ## Budget degradation order (documented multiple): narrate drops at the cap,
  ## interpret at twice it. deliberate/adopt/summarize never degrade in v1.
  defp degraded?(_class, %{cap: :inf}), do: false
  defp degraded?(:narrate, %{cap: cap, spent: spent}), do: spent > cap
  defp degraded?(:interpret, %{cap: cap, spent: spent}), do: spent > cap * @interpret_cap_multiple
  defp degraded?(_class, _budget), do: false

  defp open?(breaker, adapter), do: Map.get(breaker, adapter, 0) >= @breaker_threshold

  # attempt 0 = first try; attempt 1 = the single bounded retry
  defp call(ctx, req, cfg, attempt) when attempt < 2 do
    merged = %{req | temperature: cfg.temperature, max_tokens: cfg.max_tokens}

    case cfg.adapter.complete(merged, cfg) do
      {:ok, %Result{} = res} ->
        case check_schema(res, req.schema) do
          :ok ->
            verdict = if attempt == 0, do: :ok, else: :retry_ok
            succeed(ctx, req, cfg, res, verdict)

          {:error, _reason} ->
            call(ctx, req, cfg, attempt + 1)
        end

      {:error, reason} ->
        a = audit(req, cfg, 0, 0, :failed, false)
        {:error, reason, a, bump(ctx, cfg.adapter)}
    end
  end

  defp call(ctx, req, cfg, 2) do
    # both parse attempts failed — schema-invalid result, no usable output
    a = audit(req, cfg, 0, 0, :failed, false)
    {:error, :schema_invalid, a, bump(ctx, cfg.adapter)}
  end

  defp check_schema(_result, nil), do: :ok

  defp check_schema(%Result{parsed: nil}, _schema), do: {:error, :not_json}

  defp check_schema(%Result{parsed: parsed}, schema) do
    case Schema.validate(parsed, schema) do
      :ok -> :ok
      {:error, _path, msg} -> {:error, msg}
    end
  end

  defp succeed(%Ctx{} = ctx, req, cfg, %Result{} = res, verdict) do
    tokens_in = res.usage.tokens_in
    tokens_out = res.usage.tokens_out

    a = audit(req, cfg, tokens_in, tokens_out, verdict, true)

    ctx2 = %Ctx{
      ctx
      | budget: %{ctx.budget | spent: ctx.budget.spent + tokens_in + tokens_out},
        breaker: Map.delete(ctx.breaker, cfg.adapter)
    }

    {:ok, res, a, ctx2}
  end

  defp bump(%Ctx{} = ctx, adapter),
    do: %Ctx{ctx | breaker: Map.update(ctx.breaker, adapter, 1, &(&1 + 1))}

  defp audit(req, cfg, tokens_in, tokens_out, verdict, ok) do
    %Audit{
      class: req.class,
      agent_id: req.agent_id,
      adapter: cfg.adapter,
      model: Map.get(cfg, :model),
      tokens_in: tokens_in,
      tokens_out: tokens_out,
      prompt_slice_ref: nil,
      parse_verdict: verdict,
      ok: ok
    }
  end
end
