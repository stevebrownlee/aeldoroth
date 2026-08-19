import Config

# Channels-only endpoint (plan 5 Task 6): Bandit adapter boots only when a
# deployment explicitly turns the server on; tests and offline use run with
# server: false.
if config_env() == :prod do
  config :wire, Wire.Endpoint, server: true
end
