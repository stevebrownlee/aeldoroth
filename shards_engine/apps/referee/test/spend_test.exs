defmodule Referee.SpendTest do
  @moduledoc "Spend aggregation from llm_call ledger events (plan Task 9)."
  use ExUnit.Case, async: true
  alias Referee.Spend

  defp llm(class, agent, tin, tout) do
    %{kind: :llm_call, class: class, agent_id: agent, adapter: :scripted, model: nil,
      tokens_in: tin, tokens_out: tout, prompt_slice_ref: "abc", parse_verdict: :ok, ok: true}
  end

  test "empty ledger reports zero" do
    r = Spend.report([])

    assert r.total == %{calls: 0, tokens_in: 0, tokens_out: 0}
    assert r.by_class == %{}
    assert r.by_agent == %{}
  end

  test "aggregates calls, tokens by class and agent" do
    events = [
      %{class: :llm, tick: 0, payload: llm(:interpret, "pc1", 100, 20)},
      %{class: :llm, tick: 0, payload: llm(:narrate, "pc1", 50, 80)},
      %{class: :llm, tick: 1, payload: llm(:interpret, "pc2", 30, 10)},
      # non-llm events are ignored
      %{class: :world, tick: 1, payload: %{kind: :move, agent_id: "pc1", to: "crypt"}}
    ]

    r = Spend.report(events)

    assert r.total == %{calls: 3, tokens_in: 180, tokens_out: 110}
    assert r.by_class == %{interpret: %{calls: 2, tokens_in: 130, tokens_out: 30}, narrate: %{calls: 1, tokens_in: 50, tokens_out: 80}}
    assert r.by_agent == %{"pc1" => %{calls: 2, tokens_in: 150, tokens_out: 100}, "pc2" => %{calls: 1, tokens_in: 30, tokens_out: 10}}
  end
end
