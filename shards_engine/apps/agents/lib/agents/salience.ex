defmodule Agents.Salience do
  @moduledoc """
  Cadence escalation gate (spec 5.3): an agent's cadence tick buys full
  deliberation only under pressure — a commitment that demands action now
  (engine-marked :due, or an unscheduled adopted order), salient novelty
  (threat/intruder beliefs), or a perceived player in the agent's own
  place. Otherwise the tick is skipped and logged: no LLM call. A
  scheduled commitment whose due tick has not arrived is context, not
  pressure — its every-window sets the rhythm, not the cadence.
  """
  alias EngineCore.{Types, World}

  @salience_threshold 7.0

  @spec escalate?(Types.Agent.t(), integer(), World.t()) :: boolean()
  def escalate?(%Types.Agent{} = agent, tick, world),
    do: pressured?(agent, tick) or salient?(agent) or player_present?(agent, world)

  defp pressured?(agent, tick) do
    Enum.any?(agent.commitments, fn c ->
      c.status == :due or (c.status == :pending and (is_nil(c.due) or c.due <= tick))
    end)
  end

  defp salient?(agent) do
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Enum.any?(fn {_about, b} -> b[:salience] >= @salience_threshold end)
  end

  # A brain that has perceived a player in its own place always has a
  # decision worth making — adventurers are what every NPC reacts to (the
  # AD&D premise). Gated on the belief, never bare world truth: a hidden
  # player whose presence was never perceived triggers nothing.
  # Cadence-bounded by construction: this buys one deliberation per
  # cadence window, not a busy loop.
  defp player_present?(agent, world) do
    agent.pc == false and
      world.agents
      |> Map.values()
      |> Enum.any?(fn p ->
        p.pc and p.place_id == agent.place_id and
          get_in(agent.beliefs, [agent.place_id, p.id]) != nil
      end)
  end
end
