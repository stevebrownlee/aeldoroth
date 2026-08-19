import Config

# Offline CI: every class routes to the deterministic Scripted adapter.
# Tests inject per-class response queues via :scripts.
config :llm_gateway, routing: %{
  interpret: %{adapter: LLMGateway.Adapters.Scripted, temperature: 0.1, max_tokens: 512},
  narrate: %{adapter: LLMGateway.Adapters.Scripted, temperature: 0.4, max_tokens: 512}
}

config :logger, level: :warning
