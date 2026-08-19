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
