defmodule Agents.Adopt do
  @moduledoc """
  Order adoption mechanics (spec 5.6, decision 30): a subordinate adopts an
  order into its own commitment only through its own decision. LLM-first at
  the brain; this module is the deterministic fallback — a reliability target
  from morale, INT, and engine-computed feasibility, against a d20 the
  coordinator rolled and ledgered.
  """
  alias EngineCore.{Types, World}

  @spec feasible?(World.t(), map()) :: boolean()
  def feasible?(world, env) do
    debtor = World.agent(world, env.to)
    creditor = World.agent(world, env.from)

    alive?(debtor) and :fleeing not in (debtor.body.conditions || []) and
      creditor_near?(debtor, creditor)
  end

  defp creditor_near?(_debtor, nil), do: true

  defp creditor_near?(debtor, creditor) do
    creditor.place_id == debtor.place_id or
      get_in(debtor.beliefs, [debtor.place_id, creditor.id]) != nil or
      get_in(debtor.beliefs, [creditor.place_id, creditor.id]) != nil
  end

  defp alive?(nil), do: false
  defp alive?(a), do: a.body.hp > 0 and :dead not in (a.body.conditions || [])

  @spec reliability(Types.Agent.t(), boolean()) :: integer()
  def reliability(debtor, feasible) do
    int = debtor.statblock.int

    debtor.statblock.morale + int_adjust(int) + if(feasible, do: 3, else: -4)
  end

  defp int_adjust(int) when int >= 12, do: 2
  defp int_adjust(int) when int <= 7, do: -2
  defp int_adjust(_), do: 0

  @spec decide(integer(), integer()) :: :adopt | :reject
  def decide(roll, target), do: if(roll <= target, do: :adopt, else: :reject)
end
