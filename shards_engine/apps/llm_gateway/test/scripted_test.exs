defmodule LLMGateway.ScriptedTest do
  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.Scripted
  alias LLMGateway.Request

  @cfg %{
    scripts: %{
      interpret: ["one", ~s({"verb":"move","target":"door"})],
      narrate: ["story"]
    }
  }

  test "pops per-class queues in order" do
    assert {:ok, %LLMGateway.Result{content: "one"}} = Scripted.complete(req(:interpret), @cfg)

    assert {:ok, %LLMGateway.Result{content: ~s({"verb":"move","target":"door"})}} =
             Scripted.complete(req(:interpret), @cfg)
  end

  test "parsed is a map when payload is JSON, nil otherwise; queue exhausts" do
    {:ok, %LLMGateway.Result{parsed: nil}} = Scripted.complete(req(:interpret), @cfg)

    {:ok, %LLMGateway.Result{parsed: %{"verb" => "move", "target" => "door"}}} =
      Scripted.complete(req(:interpret), @cfg)

    assert {:error, :script_exhausted} = Scripted.complete(req(:interpret), @cfg)
  end

  test "class-keyed queues are independent" do
    Scripted.complete(req(:interpret), @cfg)
    Scripted.complete(req(:interpret), @cfg)
    # interpret exhausted, narrate still has its own queue
    assert {:ok, %LLMGateway.Result{content: "story"}} = Scripted.complete(req(:narrate), @cfg)
  end

  test "usage is the byte-size/4 token proxy from prompt and response" do
    cfg = %{scripts: %{narrate: ["abcd"]}}
    req = req(:narrate, system: "sys!", user: "user!")
    {:ok, %LLMGateway.Result{content: "abcd", usage: usage}} = Scripted.complete(req, cfg)

    assert usage.tokens_in == div(byte_size("sys!") + byte_size("user!"), 4)
    assert usage.tokens_out == div(4, 4)
  end

  test "missing scripts config errors" do
    assert {:error, :missing_scripts} = Scripted.complete(req(:interpret), %{})
  end

  test "agent-keyed entries pop only for their agent, in order" do
    scripts = %{
      deliberate: [
        %{agent_id: "grisk", content: ~s({"verb":"wait","reason":"bored"})},
        %{agent_id: "goblin_bodyguard_1", content: ~s({"verb":"strike","reason":"orders"})},
        %{agent_id: "grisk", content: ~s({"verb":"shout","reason":"alarmed"})}
      ],
      salt: System.unique_integer()
    }

    cfg = %{scripts: scripts}

    assert {:ok, %LLMGateway.Result{content: ~s({"verb":"strike","reason":"orders"})}} =
             Scripted.complete(req(:deliberate, agent_id: "goblin_bodyguard_1"), cfg)

    assert {:ok, %LLMGateway.Result{content: ~s({"verb":"wait","reason":"bored"})}} =
             Scripted.complete(req(:deliberate, agent_id: "grisk"), cfg)

    assert {:ok, %LLMGateway.Result{content: ~s({"verb":"shout","reason":"alarmed"})}} =
             Scripted.complete(req(:deliberate, agent_id: "grisk"), cfg)

    assert {:error, :script_exhausted} = Scripted.complete(req(:deliberate, agent_id: "grisk"), cfg)
    assert {:error, :script_exhausted} = Scripted.complete(req(:deliberate, agent_id: "willem"), cfg)
  end

  test "binary entries still match any agent (back-compat)" do
    scripts = %{interpret: ["one", "two"], salt: System.unique_integer()}
    cfg = %{scripts: scripts}

    assert {:ok, %LLMGateway.Result{content: "one"}} =
             Scripted.complete(req(:interpret, agent_id: "anyone"), cfg)

    assert {:ok, %LLMGateway.Result{content: "two"}} =
             Scripted.complete(req(:interpret, agent_id: "anyone"), cfg)

    assert {:error, :script_exhausted} =
             Scripted.complete(req(:interpret, agent_id: "anyone"), cfg)
  end

  defp req(class, opts \\ []) do
    struct!(Request, [class: class, system: "sys", user: "usr"] ++ opts)
  end
end
