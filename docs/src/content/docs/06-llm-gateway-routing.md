---
title: "LLM Gateway Routing"
description: "The single-chokepoint LLM gateway: adapters, budget-aware degradation, circuit breakers, and deterministic fallbacks."
order: 6
category: "Architecture"
tags: ["llm-gateway", "routing", "circuit-breaker", "budget", "adapters"]
---

# LLM Gateway Routing

All LLM traffic in The Shattered Kingdoms flows through one module: `LLMGateway.Router` in `apps/llm_gateway`. That module is the **single chokepoint** for every generative call in the engine, whether it is narration, interpretation, deliberation, adoption, or summarization. By centralizing the path we get exactly one place to meter spend, enforce a class-aware degradation order, trip circuit breakers, and audit every request. Adapters are intentionally callable only from this router; nothing else in the umbrella is allowed to talk to a vendor or script queue directly.

This chapter explains the router's pipeline, the three adapter implementations, the budget degradation rules, and the circuit-breaker fallback path.

## Single choke-point architecture

```text
                 ┌─────────────────────────────────────────────┐
                 │           LLMGateway.Router                 │
                 │  (single chokepoint: metering + audit)      │
                 └──────────────┬──────────────────┬───────────┘
                                │                  │
        ┌───────────────────────┼──────────────────┼───────────────┐
        │                       │                  │               │
   ┌────▼────┐          ┌───────▼─────┐     ┌──────▼──────┐  ┌──────▼──────┐
   │ Scripted│          │  Anthropic  │     │ OpenAICompat│  │  Fallback   │
   │ (test/  │          │   Claude    │     │  chat.compl.│  │grammar/templ│
   │ replay) │          │  /v1/messages│     │ /v1/chat/   │  │             │
   └─────────┘          └─────────────┘     └─────────────┘  └─────────────┘
```

The router's public API is a single pure function:

```elixir
@type complete_ok :: {:ok, Result.t(), Audit.t(), Ctx.t()}
@type complete_err :: {:error, term(), Audit.t() | nil, Ctx.t()}

@spec complete(Ctx.t(), Request.t()) :: complete_ok() | complete_err()
def complete(%Ctx{} = ctx, %Request{} = req)
```

`Ctx` carries routing configuration, the current budget, and the per-adapter failure counters (circuit-breaker state). `Request` is the payload that describes what class of call is being made, the prompt, and the expected JSON schema. `Result` is the raw text plus a parsed JSON map when decoding succeeds. `Audit` is the immutable record written to the ledger, capturing spend and verdict.

The pipeline order is hard-coded in `complete/2` and in the module docstring:

1. **Route lookup** — pick the adapter config for the request class.
2. **Budget gate** — decide if this request class is degraded.
3. **Circuit breaker** — check consecutive failure count.
4. **Adapter call** — invoke the selected adapter.
5. **Schema parse + one bounded retry** — validate JSON against the expected schema.
6. **Audit + context update** — record spend and update breaker state.

Because the router is pure, the caller threads the updated `Ctx` back into the next call. There is no hidden mutable gateway process; the Referee run process holds the context and passes it forward.

## Request, result, and context shapes

```elixir
# LLMGateway.Request
%LLMGateway.Request{
  class: :narrate | :interpret | :deliberate | :adopt | :summarize,
  system: String.t(),
  user: String.t(),
  schema: map() | nil,
  agent_id: String.t() | nil,
  temperature: 0.1,
  max_tokens: 512
}

# LLMGateway.Result
%LLMGateway.Result{
  content: String.t(),
  parsed: map() | nil,
  usage: %{tokens_in: non_neg_integer(), tokens_out: non_neg_integer()}
}

# LLMGateway.Ctx
%LLMGateway.Ctx{
  routing: %{class => adapter_cfg},
  budget: %{cap: :inf | non_neg_integer(), spent: non_neg_integer()},
  breaker: %{adapter_name => failure_count}
}
```

`class` is the routing key. The router looks it up in `ctx.routing` and falls through to the configured adapter. `schema` is optional; when present the router validates that the parsed JSON matches it and performs one bounded retry if it does not.

## Gateway adapters

All adapters implement the `LLMGateway.Adapter` behaviour:

```elixir
defmodule LLMGateway.Adapter do
  @callback complete(Request.t(), adapter_cfg :: map()) ::
              {:ok, Result.t()} | {:error, term()}
end
```

Only `LLMGateway.Router.complete/2` may call `LLMGateway.Adapter.complete/2`. This is not enforced by the type system, but it is the documented architectural invariant (`pattern: llm-gateway-single-chokepoint`).

### Scripted adapter

`LLMGateway.Adapters.Scripted` is the deterministic replay adapter. It is used in tests and for golden-path reproductions. Instead of calling a network endpoint it pops queued strings from a process-dictionary map keyed by class and, optionally, `agent_id`.

```elixir
# Test setup
scripts = %{
  narrate: [
    %{agent_id: "glimmer", content: "The torch gutters."},
    "A rat scurries across the stone."
  ]
}

# The adapter records every request so tests can assert on prompt content.
requests = LLMGateway.Adapters.Scripted.take_requests()
```

Because the queue lives in the process dictionary, each test process starts empty and pops are fully deterministic. The adapter returns `:script_exhausted` if the queue for the requested class is empty. It also computes synthetic usage from prompt and response byte sizes.

### Anthropic Claude adapter

`LLMGateway.Adapters.Anthropic` calls `POST /v1/messages`. The adapter separates pure request construction and response parsing from the untested `:httpc` shell.

```elixir
{url, headers, body} = LLMGateway.Adapters.Anthropic.build_request(req, cfg)

# headers include:
#   x-api-key
#   anthropic-version: 2023-06-01
#   content-type: application/json
```

Response parsing extracts the first text block and the `input_tokens`/`output_tokens` usage map. Errors map HTTP status to domain reasons:

- `401` → `:unauthorized`
- `429` → `:rate_limited`
- other non-200 → `:server_error`
- malformed body → `{:bad_response, body}`

### OpenAI-compatible adapter

`LLMGateway.Adapters.OpenAICompat` calls `POST /v1/chat/completions`. It is designed to work with any endpoint that exposes the OpenAI chat-completions shape. Like the Anthropic adapter, `build_request/2` and `parse_response/2` are pure and unit-tested; `complete/2` is the `:httpc` transport shell.

```elixir
body = %{
  "model" => cfg[:model],
  "messages" => [
    %{"role" => "system", "content" => req.system},
    %{"role" => "user", "content" => req.user}
  ],
  "temperature" => req.temperature,
  "max_tokens" => req.max_tokens,
  "response_format" => %{"type" => "json_object"}
}
```

Usage is read from `usage.prompt_tokens` and `usage.completion_tokens`. Error mapping is identical to Anthropic: `401` unauthorized, `429` rate-limited, everything else a server error.

## Budget degradation order

The gateway degrades gracefully when a run spends more than its configured token cap. Degradation is class-aware, not uniform. The rule is implemented in `LLMGateway.Router.degraded?/2`:

```elixir
@interpret_cap_multiple 2

defp degraded?(_class, %{cap: :inf}), do: false
defp degraded?(:narrate, %{cap: cap, spent: spent}), do: spent > cap
defp degraded?(:interpret, %{cap: cap, spent: spent}), do: spent > cap * @interpret_cap_multiple
defp degraded?(_class, _budget), do: false
```

| Class          | Degradation threshold | Behavior |
| -------------- | --------------------- | -------- |
| `narrate`      | `spent > cap`         | Request is skipped; narration drops at the cap. |
| `interpret`    | `spent > 2 * cap`     | Request is skipped; interpretation drops at twice the cap. |
| `deliberate`   | never in v1           | Always allowed. |
| `adopt`        | never in v1           | Always allowed. |
| `summarize`    | never in v1           | Always allowed. |

A cap of `:inf` disables the gate entirely. The design choice is that cheap or safety-critical classes continue to function after narration has gone silent; the richest text generation is throttled first.

When a request is degraded, the router returns an audit record with verdict `:skipped` and the result is empty. The caller still receives an updated `Ctx` so the ledger can record the skip.

## Circuit breakers and fallback

Each adapter has a per-run failure counter in `Ctx.breaker`. The breaker trips after **three consecutive failures** for the same adapter:

```elixir
@breaker_threshold 3

defp open?(breaker, adapter),
  do: Map.get(breaker, adapter, 0) >= @breaker_threshold
```

A failure is any adapter return of `{:error, _}` or any schema-validation failure that exhausts the one bounded retry. On success the counter is reset to zero. On failure it is incremented:

```elixir
defp bump(%Ctx{} = ctx, adapter),
  do: %Ctx{ctx | breaker: Map.update(ctx.breaker, adapter, 1, &(&1 + 1))}
```

When the breaker is open the router bypasses the network adapter and falls back to deterministic resolution:

- **Grammar-based resolvers** for structured output classes (adoption tables, condition mappings).
- **Template resolvers** for narration and clarification prompts.

The fallback returns a `Result` with `parsed` populated and usage zero, so downstream code continues to receive the expected shape. The audit record carries verdict `:fallback`, preserving a complete trace of when and why the engine stopped calling the vendor.

The bounded retry is worth emphasizing: the router makes at most two attempts for any non-degraded request. If the adapter returns an error, or the response does not parse, or the parsed JSON fails schema validation, the router tries once more. After the second failure it either trips the breaker or returns `{:error, reason, audit, ctx}` if the breaker was already closed.

```elixir
defp check_schema(%Result{parsed: nil}, _schema), do: {:error, :not_json}
defp check_schema(%Result{parsed: parsed}, schema), do: Schema.validate(parsed, schema)
```

## Audit and ledger integration

Every router call produces an `LLMGateway.Audit` record. The verdict is one of:

```elixir
@type verdict :: :ok | :retry_ok | :failed | :fallback | :skipped
```

`Audit.to_ledger/1` converts the record into a map suitable for `EngineCore.Ledger.Writer.append/2`, which writes it into the run's event stream. Because the ledger is the source of truth, the audit trail is durable and can be replayed to reconstruct exact spend per run, per class, and per agent.

## Summary

- `LLMGateway.Router` is the only caller of any adapter. No other module makes LLM requests.
- Three adapters are provided: `Scripted` (deterministic replay), `Anthropic` (Claude), and `OpenAICompat` (OpenAI-compatible).
- Budget degradation is class-aware: `narrate` drops at the cap, `interpret` drops at `2×` cap, `deliberate`/`adopt`/`summarize` never drop in v1.
- Three consecutive failures open the circuit breaker for that adapter; subsequent calls fall back to grammar/template resolvers.
- One bounded retry is allowed per request for transient parse or schema failures.
