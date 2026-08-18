defmodule EngineCore.Rules.Morale do
  @moduledoc "1E-style morale: leader down or ≥50% casualties forces d20 vs morale. Break ⇒ :fleeing."
  alias EngineCore.{Dice, Ledger, World}

  @spec check(World.t(), :rand.state(), [String.t()]) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def check(world, rng, faction_ids) do
    faction = faction_ids |> Enum.map(&World.agent(world, &1)) |> Enum.reject(&is_nil/1)

    dead = Enum.count(faction, &(&1.body.hp == 0 or :dead in &1.body.conditions))
    leader_down = Enum.any?(faction, &(&1.body.hp == 0 and Map.get(&1.statblock, :hd, 1) >= 3))
    casualties_half = faction != [] and dead * 2 >= length(faction)

    if leader_down or casualties_half do
      living = Enum.reject(faction, &(&1.body.hp == 0 or :dead in &1.body.conditions))

      {events_rev, world2, rng2} =
        Enum.reduce(living, {[], world, rng}, fn a, {evs, w, r} ->
          {roll, r2} = Dice.roll(r, 20)
          morale_val = Map.get(a.statblock, :morale, 7)
          held = roll <= morale_val

          dice_ev = %Ledger.Event{
            seq: 0,
            tick: w.tick,
            class: :dice,
            payload: %{
              purpose: :morale,
              sides: 20,
              roll: roll,
              morale: morale_val,
              agent_id: a.id,
              held: held
            }
          }

          if held do
            {[dice_ev | evs], w, r2}
          else
            break_ev = %Ledger.Event{
              seq: 0,
              tick: w.tick,
              class: :world,
              payload: %{kind: :morale_break, agent_id: a.id}
            }

            w2 = add_condition(w, a.id, :fleeing)
            {[break_ev, dice_ev | evs], w2, r2}
          end
        end)

      {:ok, Enum.reverse(events_rev), world2, rng2}
    else
      {:ok, [], world, rng}
    end
  end

  defp add_condition(world, id, cond) do
    %{
      world
      | agents:
          Map.update!(world.agents, id, fn a ->
            %{a | body: %{a.body | conditions: Enum.uniq([cond | a.body.conditions])}}
          end)
    }
  end
end
