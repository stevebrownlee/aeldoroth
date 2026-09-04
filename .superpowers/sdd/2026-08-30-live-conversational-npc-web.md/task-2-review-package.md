fa6ddce1 refactor(gateway): runtime.exs delegates env routing to LLMGateway.Config

 shards_engine/config/runtime.exs | 36 +++++++-----------------------------
 1 file changed, 7 insertions(+), 29 deletions(-)

diff --git a/shards_engine/config/runtime.exs b/shards_engine/config/runtime.exs
index 1e87bdf5..9b7b9abb 100644
--- a/shards_engine/config/runtime.exs
+++ b/shards_engine/config/runtime.exs
@@ -1,41 +1,19 @@
 import Config
 
+# Live LLM routing activates from the environment (decision 69); the logic
+# lives in LLMGateway.Config so boot and web_server re-apply cannot drift
+# (spec 2026-08-30 §4.1).
 if config_env() != :test do
-  anthropic_key = System.get_env("ANTHROPIC_API_KEY")
-  anthropic_model = System.get_env("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
-  anthropic_timeout =
-    case System.get_env("ANTHROPIC_TIMEOUT") do
-      nil -> 10_000
-      val -> String.to_integer(val)
-    end
+  %{keys: keys, routing: routing} = LLMGateway.Config.routing_from_env()
 
-  if anthropic_key && anthropic_key != "" do
-    config :llm_gateway, keys: %{
-      anthropic_main: anthropic_key
-    }
-
-    haiku_cfg = %{
-      adapter: LLMGateway.Adapters.Anthropic,
-      model: anthropic_model,
-      endpoint: System.get_env("ANTHROPIC_ENDPOINT", "https://api.anthropic.com/v1/messages"),
-      key_ref: :anthropic_main,
-      temperature: 0.2,
-      max_tokens: 1024,
-      timeout: anthropic_timeout
-    }
-
-    config :llm_gateway, routing: %{
-      deliberate: haiku_cfg,
-      adopt: haiku_cfg,
-      interpret: haiku_cfg,
-      narrate: haiku_cfg,
-      summarize: haiku_cfg
-    }
+  if map_size(keys) != 0 do
+    config :llm_gateway, keys: keys
+    config :llm_gateway, routing: routing
   end
 end
 # Channels-only endpoint (plan 5 Task 6): Bandit adapter boots only when a
 # deployment explicitly turns the server on; tests and offline use run with
 # server: false.
 if config_env() == :prod do
   config :wire, Wire.Endpoint, server: true
 end
