import Config

# LLM class routing (spec §10, decision 36): config-only vendors, nothing
# pinned by default. adapter_cfg shape:
#   %{adapter: module, model: String.t(), endpoint: String.t() | nil,
#     key_ref: atom | nil, temperature: float, max_tokens: pos_integer,
#     scripts: %{class => [response]}   # Scripted adapter only}
config :llm_gateway, routing: %{}
config :llm_gateway, keys: %{}

if config_env() == :test do
  import_config "test.exs"
end

# Channels-only endpoint (plan 5 Task 6): never boots a listener unless a
# deployment explicitly turns it on; Bandit adapter is wired in runtime.exs.
config :wire, Wire.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  server: false,
  pubsub_server: Wire.PubSub

# Web client endpoint (plan 7): LiveView socket + re-served wire socket.
# server: false always — the serve script (Task 6) flips it on at boot;
# tests boot their own Bandit on port 0.
config :client_web, ClientWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "clientweb_dev_secret_key_base_not_for_production_0123456789abcdef",
  server: false,
  pubsub_server: ClientWeb.PubSub,
  live_view: [signing_salt: "clientweb_lv_salt"],
  render_errors: [formats: [html: ClientWeb.ErrorView], layout: false]
