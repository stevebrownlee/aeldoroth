defmodule LLMGateway.RouterTest do
  use ExUnit.Case, async: true
  alias LLMGateway.{Ctx, Request, Router}

  @scripted LLMGateway.Adapters.Scripted

  @schema %{type: :object, properties: %{verb: %{type: :string}}, required: [:verb]}
  @good ~s({"verb":"move","target":"north"})
  @also_good ~s({"verb":"move","target":"south"})
  @not_json "the goblin looks at you"

  defp cfg(scripts) do
    %{
      adapter: @scripted,
      model: "test-model",
      endpoint: nil,
      key_ref: nil,
      temperature: 0.1,
      max_tokens: 512,
      scripts: scripts
    }
  end

  defp ctx(scripts \\ nil, budget \\ %{cap: :inf, spent: 0}, breaker \\ %{}) do
    scripts = scripts || %{interpret: [@good, @also_good], narrate: ["story one", "story two"]}

    %Ctx{
      routing: %{interpret: cfg(scripts), narrate: cfg(scripts)},
      budget: budget,
      breaker: breaker
    }
  end

  defp req(class, opts \\ []) do
    struct!(Request, [class: class, system: "sys", user: "usr"] ++ opts)
  end

  test "happy path: route → adapter → schema ok → audit + spend + breaker reset" do
    {:ok, result, audit, ctx2} = Router.complete(ctx(), req(:interpret, schema: @schema))

    assert result.parsed == %{"verb" => "move", "target" => "north"}
    assert audit.ok and audit.parse_verdict == :ok
    assert audit.class == :interpret and audit.adapter == @scripted and audit.model == "test-model"

    cost = audit.tokens_in + audit.tokens_out
    assert cost > 0
    assert ctx2.budget.spent == cost
    assert ctx2.breaker == %{}
  end

  test "breaker count resets on success after prior failures" do
    ctx1 = ctx(nil, %{cap: :inf, spent: 0}, %{@scripted => 2})
    {:ok, _result, _audit, ctx2} = Router.complete(ctx1, req(:interpret, schema: @schema))
    assert ctx2.breaker == %{}
  end

  test "missing route errors with no audit, ctx unchanged" do
    ctx1 = %Ctx{routing: %{}} 
    assert {:error, :no_route, nil, %Ctx{}} = Router.complete(ctx1, req(:interpret))
  end

  test "parse failure retries once; second good script yields :retry_ok" do
    scripts = %{interpret: [@not_json, @good]}
    {:ok, _result, audit, _ctx2} = Router.complete(ctx(scripts), req(:interpret, schema: @schema))
    assert audit.parse_verdict == :retry_ok and audit.ok
  end

  test "both parse attempts failing → :failed audit, ok false, breaker bumps" do
    scripts = %{interpret: [@not_json, @not_json]}
    assert {:error, :schema_invalid, audit, ctx2} =
             Router.complete(ctx(scripts), req(:interpret, schema: @schema))

    assert audit.parse_verdict == :failed and audit.ok == false
    assert ctx2.breaker == %{@scripted => 1}
  end

  test "hard adapter error → :failed audit, breaker +1; three consecutive opens circuit" do
    empty = %{interpret: []}

    {:error, :script_exhausted, a1, ctx1} = Router.complete(ctx(empty), req(:interpret))
    assert a1.parse_verdict == :failed and a1.ok == false
    assert ctx1.breaker == %{@scripted => 1}

    {:error, :script_exhausted, _a2, ctx2} = Router.complete(ctx1, req(:interpret))
    {:error, :script_exhausted, _a3, ctx3} = Router.complete(ctx2, req(:interpret))
    assert ctx3.breaker == %{@scripted => 3}

    # circuit now open: no adapter call is attempted
    assert {:error, :circuit_open, audit4, ^ctx3} = Router.complete(ctx3, req(:interpret))
    assert audit4.parse_verdict == :skipped and audit4.ok == false
  end

  test "budget: narrate degrades above cap while interpret still allowed" do
    # prompt is 80 bytes → tokens_in 20; content "" → tokens_out 0; cost exactly 20
    scripts = %{narrate: [""], interpret: [@good]}
    req = struct!(Request, class: :narrate, system: String.duplicate("s", 40), user: String.duplicate("u", 40))

    ctx0 = ctx(scripts, %{cap: 100, spent: 90})
    {:ok, _r, audit, ctx1} = Router.complete(ctx0, req)
    assert audit.tokens_in + audit.tokens_out == 20
    assert ctx1.budget.spent == 110

    # narrate above cap → degraded; interpret's ceiling is 2× cap
    assert {:error, :budget_degraded, nil, ^ctx1} = Router.complete(ctx1, req)
    assert match?({:ok, _, _, _}, Router.complete(ctx1, req(:interpret, schema: @schema)))

    # interpret degrades above 2× cap
    ctx2 = %{ctx1 | budget: %{cap: 100, spent: 201}}
    assert {:error, :budget_degraded, nil, ^ctx2} = Router.complete(ctx2, req(:interpret))
  end
end
