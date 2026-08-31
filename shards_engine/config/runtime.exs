import Config

# Live LLM routing activates from the environment (decision 69); the logic
# lives in LLMGateway.Config so boot and web_server re-apply cannot drift
# (spec 2026-08-30 §4.1).
if config_env() != :test do
  %{keys: keys, routing: routing} = LLMGateway.Config.routing_from_env()

  if map_size(keys) != 0 do
    config :llm_gateway, keys: keys
    config :llm_gateway, routing: routing
  end
end
# Channels-only endpoint (plan 5 Task 6): Bandit adapter boots only when a
# deployment explicitly turns the server on; tests and offline use run with
# server: false.
if config_env() == :prod do
  config :wire, Wire.Endpoint, server: true
end
