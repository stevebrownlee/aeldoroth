7cb03ce3 feat(gateway): single-source env routing builder (LLMGateway.Config)

 .../apps/llm_gateway/lib/llm_gateway/config.ex     | 82 +++++++++++++++++++
 .../apps/llm_gateway/test/config_test.exs          | 93 ++++++++++++++++++++++
 2 files changed, 175 insertions(+)

diff --git a/shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex b/shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex
new file mode 100644
index 00000000..34996e4d
--- /dev/null
+++ b/shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex
@@ -0,0 +1,82 @@
+defmodule LLMGateway.Config do
+  @moduledoc """
+  Single source of LLM routing activation from the environment (spec
+  2026-08-30, decision 69). `config/runtime.exs` boot and the web server's
+  re-apply both call `routing_from_env/0`/`apply_env_routing/0`, so the two
+  can never drift. `live?/0` is THE definition of "live" — the lobby gate
+  and the GM badge both read it.
+  """
+
+  @default_model "claude-haiku-4-5-20251001"
+  @default_endpoint "https://api.anthropic.com/v1/messages"
+  @default_timeout 10_000
+  @classes [:deliberate, :adopt, :interpret, :narrate, :summarize]
+
+  @doc "Live Anthropic routing for all five classes, or empty maps when no key."
+  @spec routing_from_env() :: %{keys: map(), routing: map()}
+  def routing_from_env do
+    case System.get_env("ANTHROPIC_API_KEY") do
+      key when is_binary(key) and key != "" ->
+        cfg = %{
+          adapter: LLMGateway.Adapters.Anthropic,
+          model: System.get_env("ANTHROPIC_MODEL", @default_model),
+          endpoint: System.get_env("ANTHROPIC_ENDPOINT", @default_endpoint),
+          key_ref: :anthropic_main,
+          temperature: 0.2,
+          max_tokens: 1024,
+          timeout: timeout_from_env()
+        }
+
+        %{keys: %{anthropic_main: key}, routing: Map.new(@classes, &{&1, cfg})}
+
+      _ ->
+        %{keys: %{}, routing: %{}}
+    end
+  end
+
+  @doc "Merge env routing into Application env. Only fills; a no-op without a key."
+  @spec apply_env_routing() :: :ok
+  def apply_env_routing do
+    %{keys: keys, routing: routing} = routing_from_env()
+
+    if map_size(keys) != 0 do
+      Application.put_env(:llm_gateway, :keys, keys)
+      Application.put_env(:llm_gateway, :routing, routing)
+    end
+
+    :ok
+  end
+
+  @doc """
+    The one definition of "live": deliberate AND interpret are configured
+    with an adapter that is not the offline Scripted adapter.
+  """
+  @spec live?() :: boolean()
+  def live? do
+    routing = Application.get_env(:llm_gateway, :routing, %{})
+
+    Enum.all?([:deliberate, :interpret], fn class ->
+      case routing[class] do
+        %{adapter: LLMGateway.Adapters.Scripted} -> false
+        %{adapter: a} when is_atom(a) -> true
+        _ -> false
+      end
+    end)
+  end
+
+  @doc "Model name for display (badge, lobby hint); nil when offline."
+  @spec model() :: String.t() | nil
+  def model do
+    case Application.get_env(:llm_gateway, :routing, %{})[:deliberate] do
+      %{model: m} -> m
+      _ -> nil
+    end
+  end
+
+  defp timeout_from_env do
+    case System.get_env("ANTHROPIC_TIMEOUT") do
+      nil -> @default_timeout
+      val -> String.to_integer(val)
+    end
+  end
+end
diff --git a/shards_engine/apps/llm_gateway/test/config_test.exs b/shards_engine/apps/llm_gateway/test/config_test.exs
new file mode 100644
index 00000000..5fa49f54
--- /dev/null
+++ b/shards_engine/apps/llm_gateway/test/config_test.exs
@@ -0,0 +1,93 @@
+defmodule LLMGateway.ConfigTest do
+  @moduledoc "Env → routing activation (spec 2026-08-30): one builder, one live? definition."
+  use ExUnit.Case, async: false
+
+  alias LLMGateway.Config
+
+  @env_vars ["ANTHROPIC_API_KEY", "ANTHROPIC_MODEL", "ANTHROPIC_ENDPOINT", "ANTHROPIC_TIMEOUT"]
+
+  setup do
+    Enum.each(@env_vars, &System.delete_env/1)
+
+    on_exit(fn ->
+      Enum.each(@env_vars, &System.delete_env/1)
+      Application.delete_env(:llm_gateway, :routing)
+      Application.delete_env(:llm_gateway, :keys)
+    end)
+
+    :ok
+  end
+
+  test "routing_from_env builds live routing for all five classes when a key is present" do
+    System.put_env("ANTHROPIC_API_KEY", "sk-test")
+    System.put_env("ANTHROPIC_MODEL", "test-model")
+
+    %{keys: keys, routing: routing} = Config.routing_from_env()
+
+    assert keys == %{anthropic_main: "sk-test"}
+
+    assert MapSet.new(Map.keys(routing)) ==
+             MapSet.new([:deliberate, :adopt, :interpret, :narrate, :summarize])
+
+    Enum.each(routing, fn {_class, cfg} ->
+      assert cfg.adapter == LLMGateway.Adapters.Anthropic
+      assert cfg.model == "test-model"
+      assert cfg.key_ref == :anthropic_main
+      assert cfg.timeout == 10_000
+      assert cfg.temperature == 0.2
+      assert cfg.max_tokens == 1024
+    end)
+  end
+
+  test "routing_from_env is empty without a key (nil or blank)" do
+    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
+    System.put_env("ANTHROPIC_API_KEY", "")
+    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
+  end
+
+  test "routing_from_env honors ANTHROPIC_TIMEOUT and ANTHROPIC_ENDPOINT" do
+    System.put_env("ANTHROPIC_API_KEY", "sk-test")
+    System.put_env("ANTHROPIC_TIMEOUT", "5000")
+    System.put_env("ANTHROPIC_ENDPOINT", "https://proxy.example/v1/messages")
+
+    %{routing: %{deliberate: cfg}} = Config.routing_from_env()
+
+    assert cfg.timeout == 5000
+    assert cfg.endpoint == "https://proxy.example/v1/messages"
+  end
+
+  test "live? is true only when deliberate and interpret are non-Scripted" do
+    live_cfg = %{adapter: LLMGateway.Adapters.Anthropic, model: "m"}
+
+    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg, interpret: live_cfg})
+    assert Config.live?()
+
+    scripted = %{adapter: LLMGateway.Adapters.Scripted, scripts: %{}}
+    Application.put_env(:llm_gateway, :routing, %{deliberate: scripted, interpret: scripted})
+    refute Config.live?()
+
+    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg})
+    refute Config.live?()
+
+    Application.delete_env(:llm_gateway, :routing)
+    refute Config.live?()
+  end
+
+  test "apply_env_routing fills app env when a key is present and is a no-op without" do
+    System.put_env("ANTHROPIC_API_KEY", "sk-test")
+    assert :ok = Config.apply_env_routing()
+
+    assert %{deliberate: %{adapter: LLMGateway.Adapters.Anthropic}} =
+             Application.get_env(:llm_gateway, :routing)
+
+    assert %{anthropic_main: "sk-test"} = Application.get_env(:llm_gateway, :keys)
+  end
+
+  test "model returns the deliberate model, nil offline" do
+    Application.put_env(:llm_gateway, :routing, %{deliberate: %{model: "stub-1"}})
+    assert Config.model() == "stub-1"
+
+    Application.delete_env(:llm_gateway, :routing)
+    assert Config.model() == nil
+  end
+end
