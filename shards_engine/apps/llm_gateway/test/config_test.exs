defmodule LLMGateway.ConfigTest do
  @moduledoc "Env → routing activation (spec 2026-08-30): one builder, one live? definition."
  use ExUnit.Case, async: false

  alias LLMGateway.Config

  @env_vars ["ANTHROPIC_API_KEY", "ANTHROPIC_MODEL", "ANTHROPIC_ENDPOINT", "ANTHROPIC_TIMEOUT"]

  setup do
    Enum.each(@env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(@env_vars, &System.delete_env/1)
      Application.delete_env(:llm_gateway, :routing)
      Application.delete_env(:llm_gateway, :keys)
    end)

    :ok
  end

  test "routing_from_env builds live routing for all five classes when a key is present" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    System.put_env("ANTHROPIC_MODEL", "test-model")

    %{keys: keys, routing: routing} = Config.routing_from_env()

    assert keys == %{anthropic_main: "sk-test"}

    assert MapSet.new(Map.keys(routing)) ==
             MapSet.new([:deliberate, :adopt, :interpret, :narrate, :summarize])

    Enum.each(routing, fn {_class, cfg} ->
      assert cfg.adapter == LLMGateway.Adapters.Anthropic
      assert cfg.model == "test-model"
      assert cfg.key_ref == :anthropic_main
      assert cfg.timeout == 10_000
      assert cfg.temperature == 0.2
      assert cfg.max_tokens == 1024
    end)
  end

  test "routing_from_env is empty without a key (nil or blank)" do
    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
    System.put_env("ANTHROPIC_API_KEY", "")
    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
  end

  test "routing_from_env honors ANTHROPIC_TIMEOUT and ANTHROPIC_ENDPOINT" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    System.put_env("ANTHROPIC_TIMEOUT", "5000")
    System.put_env("ANTHROPIC_ENDPOINT", "https://proxy.example/v1/messages")

    %{routing: %{deliberate: cfg}} = Config.routing_from_env()

    assert cfg.timeout == 5000
    assert cfg.endpoint == "https://proxy.example/v1/messages"
  end

  test "live? is true only when deliberate and interpret are non-Scripted" do
    live_cfg = %{adapter: LLMGateway.Adapters.Anthropic, model: "m"}

    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg, interpret: live_cfg})
    assert Config.live?()

    scripted = %{adapter: LLMGateway.Adapters.Scripted, scripts: %{}}
    Application.put_env(:llm_gateway, :routing, %{deliberate: scripted, interpret: scripted})
    refute Config.live?()

    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg})
    refute Config.live?()

    Application.delete_env(:llm_gateway, :routing)
    refute Config.live?()
  end

  test "apply_env_routing fills app env when a key is present and is a no-op without" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    assert :ok = Config.apply_env_routing()

    assert %{deliberate: %{adapter: LLMGateway.Adapters.Anthropic}} =
             Application.get_env(:llm_gateway, :routing)

    assert %{anthropic_main: "sk-test"} = Application.get_env(:llm_gateway, :keys)
  end

  test "model returns the deliberate model, nil offline" do
    Application.put_env(:llm_gateway, :routing, %{deliberate: %{model: "stub-1"}})
    assert Config.model() == "stub-1"

    Application.delete_env(:llm_gateway, :routing)
    assert Config.model() == nil
  end
end
