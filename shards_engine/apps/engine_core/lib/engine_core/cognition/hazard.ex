defmodule EngineCore.Cognition.Hazard do
  @moduledoc "Tier 0: decision patterns keyed on trigger conditions (spec 5.1)."
  alias EngineCore.{Dice, Fold, Ledger, Rules, Signals, Types, World}

  @spec check_move(World.t(), :rand.state(), map()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def check_move(world, rng, %{kind: :move, agent_id: id, from: from, to: to} = move) do
    careful = Map.get(move, :careful, false)
    crossed = edge_id_between(world, from, to)

    candidates =
      world.hazards
      |> Map.values()
      |> Enum.reject(& &1.triggered)
      |> Enum.filter(&(&1.edge_id == nil or &1.edge_id == crossed))
      |> Enum.filter(&(&1.place_id == from or &1.place_id == to))
      |> Enum.sort_by(& &1.id)

    {events, w2, r2} =
      Enum.reduce(candidates, {[], world, rng}, fn h, {evs, w, r} ->
        resolve(w, h, id, careful, evs, r)
      end)

    {:ok, events, w2, r2}
  end

  def check_move(world, rng, _), do: {:ok, [], world, rng}

  @spec check_presence(World.t(), :rand.state(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def check_presence(world, rng, agent_id) do
    case World.agent(world, agent_id) do
      nil ->
        {:ok, [], world, rng}

      agent ->
        if alive?(agent) do
          tier0_agents =
            world.agents
            |> Map.values()
            |> Enum.filter(fn a ->
              a.place_id == agent.place_id and
                a.tier == 0 and
                a.attention == :alert and
                :strike in (a.capabilities || [])
            end)
            |> Enum.filter(&alive?/1)
            |> Enum.sort_by(& &1.id)

          {events, w2, r2} =
            Enum.reduce(tier0_agents, {[], world, rng}, fn t0, {evs_acc, w_acc, r_acc} ->
              intruders =
                w_acc.agents
                |> Map.values()
                |> Enum.filter(fn a ->
                  a.place_id == agent.place_id and
                    a.id != t0.id and
                    (a.group != t0.group or a.group == nil or t0.group == nil)
                end)
                |> Enum.filter(&alive?/1)
                |> Enum.sort_by(& &1.id)

              case intruders do
                [intruder | _] ->
                  case Rules.Combat.attack(w_acc, r_acc, t0.id, intruder.id) do
                    {:ok, evs, w_next, r_next} ->
                      {evs_acc ++ evs, w_next, r_next}

                    _ ->
                      {evs_acc, w_acc, r_acc}
                  end

                [] ->
                  {evs_acc, w_acc, r_acc}
              end
            end)

          {:ok, events, w2, r2}
        else
          {:ok, [], world, rng}
        end
    end
  end

  defp resolve(world, h, id, true = _careful, evs, r) do
    ev = meta_event(world, %{kind: :hazard_avoided, id: h.id, agent_id: id, how: :careful})
    w2 = Fold.fold(world, [ev])
    {evs ++ [ev], w2, r}
  end

  defp resolve(world, h, id, false = _careful, evs, r) do
    {roll, r2} = Dice.roll(r, 20)

    if roll < h.dc do
      ev_trig = meta_event(world, %{kind: :hazard_triggered, id: h.id, agent_id: id})
      w1 = Fold.fold(world, [ev_trig])
      {:ok, effect_evs, w2, r3} = apply_effect(w1, h, id, r2)
      {evs ++ [ev_trig | effect_evs], w2, r3}
    else
      ev = meta_event(world, %{kind: :hazard_avoided, id: h.id, agent_id: id, roll: roll})
      w1 = Fold.fold(world, [ev])
      {evs ++ [ev], w1, r2}
    end
  end

  defp apply_effect(world, %Types.Hazard{kind: :alarm} = h, id, r) do
    content_nl = "a wild clattering of pots and pans"

    case Signals.emit(
           world,
           h.id,
           :sound,
           %{class: h.signal_class || :alarm, threat: true, about: id, count: 1},
           h.signal_intensity || 9,
           content_nl
         ) do
      {:ok, evs, w2} -> {:ok, evs, w2, r}
    end
  end

  defp apply_effect(world, %Types.Hazard{kind: :damage} = h, id, r) do
    {rolls, r2} = Dice.roll(r, h.damage.sides, h.damage.dice)
    amount = Enum.sum(rolls) + h.damage.plus

    ev_dice = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :dice,
      payload: %{
        purpose: :hazard_damage,
        hazard_id: h.id,
        sides: h.damage.sides,
        rolls: rolls,
        amount: amount,
        target_id: id
      }
    }

    ev_dmg = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :world,
      payload: %{kind: :damage, target_id: id, amount: amount}
    }

    target = World.agent(world, id)
    target_hp = (target && target.body && target.body.hp) || 1

    {dmg_events, w2} =
      if target_hp - amount > 0 do
        {[ev_dice, ev_dmg], Fold.fold(world, [ev_dice, ev_dmg])}
      else
        ev_death = %Ledger.Event{
          seq: 0,
          tick: world.tick,
          class: :world,
          payload: %{kind: :death, agent_id: id}
        }

        {[ev_dice, ev_dmg, ev_death], Fold.fold(world, [ev_dice, ev_dmg, ev_death])}
      end

    {:ok, sig_events, w3} =
      Signals.emit(
        w2,
        h.id,
        :sound,
        %{class: :combat, threat: true, about: id, count: 1},
        6,
        "a cry of pain"
      )

    {:ok, dmg_events ++ sig_events, w3, r2}
  end

  defp edge_id_between(world, from, to) do
    case Enum.find(world.edges, fn e ->
           (e.from == from and e.to == to) or (e.from == to and e.to == from)
         end) do
      %Types.Edge{id: id} -> id
      nil -> nil
    end
  end

  defp alive?(agent) do
    hp = (agent.body && agent.body.hp) || 0
    conds = (agent.body && agent.body.conditions) || []
    hp > 0 and :dead not in conds
  end

  defp meta_event(world, payload),
    do: %Ledger.Event{seq: 0, tick: world.tick, class: :meta, payload: payload}
end
