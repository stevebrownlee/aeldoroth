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

    f =
      tier
      |> Kernel.-(if arrival.hops >= 1, do: 1, else: 0)
      |> Kernel.-(if agent.attention == :dormant, do: 2, else: 0)
      |> Kernel.+(if agent.statblock.int >= 16, do: 1, else: 0)
      |> Kernel.-(if agent.statblock.int <= 6, do: 1, else: 0)
      |> max(0)
      |> then(fn f -> if arrival.intensity >= 9, do: max(f, 3), else: f end)
      |> min(5)

    # Words aimed at this agent are not faint room noise: directed speech
    # floors at F4 in the room and F3 across a hop (spec 6.1). Only the
    # addressee is in the receiver set at all; this floor covers the
    # faint-signal d6 path so the addressee never misses the words.
    if addressed?(arrival, agent),
      do: max(f, if(arrival.hops >= 1, do: 3, else: 4)),
      else: f
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
      # Presence (footsteps) and speech (voices) are emitted BY their
      # subject: the mover/speaker never receives its own signal. Combat
      # noise is about its VICTIM, who must perceive it.
      |> Enum.reject(&(&1.id == arrival.about and emitter_subject?(arrival)))
      |> Enum.reject(&(&1.body.hp == 0 or :dead in (&1.body.conditions || [])))
      # Directed speech is a private exchange: only its addressee (the
      # content_core.to id) perceives it. Undirected shouts stay public to
      # everyone present, gated by fidelity as before.
      |> Enum.filter(fn a ->
        to = (arrival.content_core || %{})[:to]
        is_nil(to) or to == a.id
      end)
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
              salience: addressed_boost(salience(arrival, a, world), arrival, a),
              roll: roll,
              content_core: arrival.content_core,
              content_nl: arrival.content_nl
            }
          }

          {[ev], r2}
        end
      end)

    {:ok, events, Fold.fold(world, events), rng2}
  end

  defp addressed?(arrival, agent),
    do: (arrival.content_core || %{})[:to] == agent.id

  # Being addressed pins attention: +3 salience, capped like threat noise.
  defp addressed_boost(s, arrival, agent) when is_number(s) do
    if addressed?(arrival, agent), do: min(s + 3, 10), else: s
  end

  # Footsteps (presence) and voices (shout) are emitted by their subject;
  # combat noise is about its victim. Only the former self-exclude.
  defp emitter_subject?(arrival) do
    Map.get(arrival.content_core || %{}, :class) in [:footsteps, :voices]
  end
end
