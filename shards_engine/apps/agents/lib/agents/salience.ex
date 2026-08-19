defmodule Agents.Salience do
  @moduledoc """
  Cadence escalation gate (spec 5.3): an agent's cadence tick buys full
  deliberation only under pressure — outstanding commitments (the cadence IS
  the commitment check) or salient novelty (threat/intruder beliefs).
  Otherwise the tick is skipped and logged: no LLM call.
  """
  alias EngineCore.Types

  @salience_threshold 7.0

  @spec escalate?(Types.Agent.t(), integer()) :: boolean()
  def escalate?(%Types.Agent{} = agent, _tick), do: pressured?(agent) or salient?(agent)

  defp pressured?(agent),
    do: Enum.any?(agent.commitments, &(&1.status in [:pending, :due]))

  defp salient?(agent) do
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Enum.any?(fn {_about, b} -> b[:salience] >= @salience_threshold end)
  end
end
