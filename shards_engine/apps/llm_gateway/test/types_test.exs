defmodule LLMGateway.TypesTest do
  use ExUnit.Case, async: true
  alias LLMGateway.{Audit, Ctx, Request}

  test "Request enforces class/system/user, defaults the rest" do
    assert_raise ArgumentError, fn ->
      struct!(Request, system: "s", user: "u")
    end

    r = struct!(Request, class: :interpret, system: "s", user: "u")
    assert is_float(r.temperature) and r.max_tokens > 0
    assert r.schema == nil and r.agent_id == nil
  end

  test "Audit defaults track a successful call" do
    a = struct!(Audit, class: :interpret, adapter: LLMGateway.Adapters.Scripted)
    assert a.parse_verdict == :ok and a.ok == true
    assert a.tokens_in == 0 and a.tokens_out == 0
    assert a.model == nil and a.prompt_slice_ref == nil and a.agent_id == nil
  end

  test "Audit.to_ledger yields the atom/value payload" do
    a = struct!(Audit, class: :interpret, adapter: LLMGateway.Adapters.Scripted, tokens_in: 3, tokens_out: 5)
    assert Audit.to_ledger(a) == %{kind: :llm_call, class: :interpret, agent_id: nil, adapter: LLMGateway.Adapters.Scripted, model: nil, tokens_in: 3, tokens_out: 5, prompt_slice_ref: nil, parse_verdict: :ok, ok: true}
  end

  test "Ctx.from_config normalizes routing and defaults budget/breaker" do
    ctx =
      Ctx.from_config(%{
        interpret: %{adapter: LLMGateway.Adapters.Scripted, model: "m"}
      })

    cfg = ctx.routing[:interpret]
    assert cfg.adapter == LLMGateway.Adapters.Scripted
    assert cfg.model == "m" and cfg.endpoint == nil and cfg.key_ref == nil
    assert is_float(cfg.temperature) and is_integer(cfg.max_tokens) and cfg.max_tokens > 0

    assert ctx.budget == %{cap: :inf, spent: 0}
    assert ctx.breaker == %{}
  end

  test "Ctx.from_config defaults to env routing" do
    # config/test.exs routes every class to Scripted
    ctx = Ctx.from_config(nil)
    assert cfg = ctx.routing[:interpret]
    assert cfg.adapter == LLMGateway.Adapters.Scripted
  end
end
