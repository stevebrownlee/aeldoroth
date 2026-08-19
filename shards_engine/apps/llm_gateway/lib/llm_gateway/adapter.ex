defmodule LLMGateway.Adapter do
  @moduledoc """
  Adapter behaviour. Implementations are callable ONLY from `LLMGateway.Router` —
  the single chokepoint for all LLM traffic (pattern: llm-gateway-single-chokepoint).
  """

  @callback complete(LLMGateway.Request.t(), adapter_cfg :: map()) ::
              {:ok, LLMGateway.Result.t()} | {:error, term()}
end
