defmodule Referee.Spend do
  @moduledoc """
  LLM spend aggregation from `:llm` ledger events (spec §10 dashboards).

  Works on any event shaped like `%{class: _, payload: %{kind: :llm_call, ...}}`
  — `Ledger.Event` structs from a live run or plain maps from a replay.
  """

  @zero %{calls: 0, tokens_in: 0, tokens_out: 0}

  @spec report([map()]) :: %{
          total: map(),
          by_class: %{atom() => map()},
          by_agent: %{String.t() => map()}
        }
  def report(events) do
    payloads =
      events
      |> Enum.filter(&(Map.get(&1, :class) == :llm and llm_call?(&1)))
      |> Enum.map(& &1.payload)

    %{
      total: tally(payloads),
      by_class: by_facet(payloads, &Map.get(&1, :class)),
      by_agent: by_facet(payloads, &Map.get(&1, :agent_id))
    }
  end

  defp llm_call?(ev), do: Map.get(Map.get(ev, :payload) || %{}, :kind) == :llm_call

  defp by_facet(payloads, facet) do
    payloads
    |> Enum.group_by(facet)
    |> Map.new(fn {key, ps} -> {key, tally(ps)} end)
  end

  defp tally(payloads) do
    Enum.reduce(payloads, @zero, fn p, acc ->
      %{
        calls: acc.calls + 1,
        tokens_in: acc.tokens_in + (Map.get(p, :tokens_in) || 0),
        tokens_out: acc.tokens_out + (Map.get(p, :tokens_out) || 0)
      }
    end)
  end
end
