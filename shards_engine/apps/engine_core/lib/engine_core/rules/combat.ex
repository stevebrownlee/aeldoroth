defmodule EngineCore.Rules.Combat do
  @moduledoc "1E to-hit and damage resolution. Segment scheduling arrives with the Scheduler (Plan 2)."
  alias EngineCore.{Dice, Ledger, World}

  @spec initiative(:rand.state(), [String.t()]) :: {[String.t()], :rand.state()}
  def initiative(rng, ids) do
    {scored, rng2} =
      Enum.map_reduce(ids, rng, fn id, r ->
        {v, r2} = Dice.roll(r, 6)
        {{v, id}, r2}
      end)

    order = scored |> Enum.sort_by(&{-elem(&1, 0), elem(&1, 1)}) |> Enum.map(&elem(&1, 1))
    {order, rng2}
  end

  @spec attack(World.t(), :rand.state(), String.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()} | {:error, atom()}
  def attack(world, rng, attacker_id, target_id) do
    a = World.agent(world, attacker_id)
    t = World.agent(world, target_id)

    cond do
      a == nil or t == nil -> {:error, :no_agent}
      a.place_id != t.place_id -> {:error, :not_engaged}
      :strike not in a.capabilities -> {:error, :no_capability}
      true ->
        {roll, rng2} = Dice.roll(rng, 20)
        hit = roll >= a.statblock.thac0 - t.statblock.ac
        resolve(hit, world, rng2, a, t, roll)
    end
  end

  defp resolve(false, world, rng, _a, t, roll) do
    ev = dice_event(world.tick, %{purpose: :to_hit, sides: 20, roll: roll,
                                  target_ac: t.statblock.ac, hit: false})
    {:ok, [ev], world, rng}
  end

  defp resolve(true, world, rng, a, t, roll) do
    cfg = a.statblock.damage
    {rolls, rng2} = Dice.roll(rng, cfg.sides, cfg.dice)
    amount = Enum.sum(rolls) + cfg.plus

    ev_dice =
      dice_event(world.tick, %{purpose: :to_hit, sides: 20, roll: roll,
                               target_ac: t.statblock.ac, hit: true,
                               dmg_rolls: rolls, amount: amount})

    ev_dmg = %Ledger.Event{seq: 0, tick: world.tick, class: :world,
                           payload: %{kind: :damage, target_id: t.id, amount: amount}}

    w2 = %{
      world
      | agents:
          Map.update!(world.agents, t.id, fn ag ->
            %{ag | body: %{ag.body | hp: max(0, ag.body.hp - amount)}}
          end)
    }

    target_after = World.agent(w2, t.id)

    if target_after.body.hp == 0 do
      ev_death = %Ledger.Event{
        seq: 0,
        tick: world.tick,
        class: :world,
        payload: %{kind: :death, agent_id: t.id}
      }

      w3 = %{
        w2
        | agents:
            Map.update!(w2.agents, t.id, fn ag ->
              %{ag | capabilities: [], body: %{ag.body | conditions: Enum.uniq([:dead | ag.body.conditions])}}
            end)
      }

      {:ok, [ev_dice, ev_dmg, ev_death], w3, rng2}
    else
      {:ok, [ev_dice, ev_dmg], w2, rng2}
    end
  end

  defp dice_event(tick, payload),
    do: %Ledger.Event{seq: 0, tick: tick, class: :dice, payload: payload}
end
