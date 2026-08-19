defmodule LLMGateway do
  @moduledoc """
  Single LLM chokepoint (engrams pattern 14).

  ALL LLM traffic in the engine flows through `LLMGateway.Router.complete/2`.
  Adapter modules (`LLMGateway.Adapters.*`) are callable ONLY from inside
  `LLMGateway.Router` — no other module in any app may call an adapter
  directly. Every call returns an `LLMGateway.Audit`; callers persist audits
  as `llm_call` events so platform metering stays lossless.

  Pure by design: `Router.complete/2` is a function over `%LLMGateway.Ctx{}`,
  not a process — determinism is testable and the run container owns state.
  Routing is config (`config :llm_gateway, :routing`); no vendor is pinned
  by default (decision 36). Keys are deployment config, resolved via
  `key_ref` against `config :llm_gateway, :keys` — never literals here.
  """
end
