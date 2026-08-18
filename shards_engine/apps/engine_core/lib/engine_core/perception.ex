defmodule EngineCore.Perception do
  @moduledoc """
  Reception filters and belief formation (spec 6.1/6.2, decision 31).
  F0 is an honest omission: no event is emitted at all.
  """
  alias EngineCore.{Dice, Fold, Ledger, Types, World}

  @spec base_fidelity(Types.Arrival.t(), Types.Agent.t()) :: non_neg_integer()
  def base_fidelity(arrival, agent) do
    tier =
      cond do
        arrival.intensity >= 9 -> 5
        arrival.intensity >= 7 -> 4
        arrival.intensity >= 5 -> 3
        arrival.intensity >= 3 -> 2
        true -> 1
      end

    tier
    |> Kernel.-(if arrival.hops >= 1, do: 1, else: 0)
    |> Kernel.-(if agent.attention == :dormant, do: 2, else: 0)
    |> Kernel.+(if agent.statblock.int >= 16, do: 1, else: 0)
    |> Kernel.-(if agent.statblock.int <= 6, do: 1, else: 0)
    |> max(0)
    |> then(fn f -> if arrival.intensity >= 9, do: max(f, 3), else: f end)
    |> min(5)
  end

  @spec resolve_fidelity(non_neg_integer(), Types.Arrival.t(), :rand.state()) ::
          {non_neg_integer(), non_neg_integer() | nil, :rand.state()}
  def resolve_fidelity(base, arrival, rng) do
    if base <= 0 or (base == 1 and arrival.intensity <= 3) do
      {roll, rng2} = Dice.roll(rng, 6)
      {if(roll <= 2, do: 1, else: 0), roll, rng2}
    else
      {base, nil, rng}
    end
  end

  @spec salience(Types.Arrival.t(), Types.Agent.t(), World.t()) :: float()
  def salience(arrival, agent, _world) do
    novel = get_in(agent.beliefs, [arrival.place_id, arrival.about]) == nil
    same = agent.place_id == arrival.place_id
    threat = arrival.content_core[:threat] == true

    (arrival.intensity + if(same, do: 2, else: 1) + if(novel, do: 2, else: 0) +
       if(threat, do: 3, else: 0))
    |> min(10)
    |> Kernel.*(1.0)
    |> Float.round(1)
  end

  @spec receive_arrival(World.t(), :rand.state(), Types.Arrival.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def receive_arrival(world, rng, arrival) do
    receivers =
      world
      |> World.agents_in(arrival.place_id)
      |> Enum.reject(&(&1.body.hp == 0 or :dead in (&1.body.conditions || [])))
      |> Enum.sort_by(& &1.id)

    {events, rng2} =
      Enum.flat_map_reduce(receivers, rng, fn a, r ->
        base = base_fidelity(arrival, a)
        {f, roll, r2} = resolve_fidelity(base, arrival, r)

        if f <= 0 do
          {[], r2}
        else
          ev = %Ledger.Event{
            seq: 0,
            tick: arrival.tick,
            class: :signal,
            payload: %{
              kind: :signal_received,
              agent_id: a.id,
              place_id: arrival.place_id,
              ref: arrival.ref,
              about: arrival.about,
              signal_kind: arrival.kind,
              intensity: Float.round(arrival.intensity * 1.0, 4),
              fidelity: f,
              salience: salience(arrival, a, world),
              roll: roll
            }
          }

          {[ev], r2}
        end
      end)

    {:ok, events, Fold.fold(world, events), rng2}
  end
end
