defmodule EngineCore.Rules.Saves do
  @moduledoc "1E-style saves. Monsters save as fighters by HD: target = max(10, 15 - hd) + category offset."
  alias EngineCore.{Dice, Ledger, World}

  @offset %{death: 0, petrification: 1, wands: 2, spells: 3}

  @spec target(pos_integer, atom) :: pos_integer
  def target(hd, category), do: max(10, 15 - hd) + Map.fetch!(@offset, category)

  @spec check(World.t(), :rand.state(), String.t(), atom) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()} | {:error, :no_agent}
  def check(world, rng, agent_id, category) do
    case World.agent(world, agent_id) do
      nil ->
        {:error, :no_agent}

      a ->
        hd = Map.get(a.statblock, :hd, 1)
        t = target(hd, category)
        {roll, rng2} = Dice.roll(rng, 20)
        saved = roll >= t

        ev = %Ledger.Event{
          seq: 0,
          tick: world.tick,
          class: :dice,
          payload: %{
            purpose: :save,
            category: category,
            sides: 20,
            roll: roll,
            target: t,
            agent_id: agent_id,
            saved: saved
          }
        }

        {:ok, [ev], world, rng2}
    end
  end
end
