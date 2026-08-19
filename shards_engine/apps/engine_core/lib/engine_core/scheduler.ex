defmodule EngineCore.Scheduler do
  @moduledoc """
  Pure per-tick world motion (spec 7.1): arrivals, receptions, reflex,
  commitment dues, cadences, boundary sleep. The OTP Scheduler process
  and brains arrive in Plan 3; this module is the deterministic core.
  """
  alias EngineCore.{
    Boundaries,
    Cognition,
    Commitments,
    Fold,
    Ledger,
    Perception,
    Signals,
    Types,
    World
  }

  @reflex_fidelity 3
  @reflex_salience 6

  @spec advance(World.t(), :rand.state()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def advance(world, rng) do
    t = world.tick + 1
    tick_ev = tick_event(t)
    world = Fold.fold(world, [tick_ev])

    {a_events, world, rng} = arrivals_phase(world, rng, t)
    {c_events, world, rng} = commitments_phase(world, rng, t)
    {k_events, world, rng} = cadence_phase(world, rng, t)
    {s_events, world} = sleep_phase(world)

    {:ok, [tick_ev] ++ a_events ++ c_events ++ k_events ++ s_events, world, rng}
  end

  @doc """
  The 6.4 bridge: applied actions emit signals; hazards arm on crossing;
  boundaries re-evaluate. Call after any action batch leaves the rules
  modules. One pass, no recursion.
  """
  @spec react(World.t(), :rand.state(), [Ledger.Event.t()]) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def react(world, rng, events) do
    moves = Enum.filter(events, &(Map.get(&1.payload, :kind) == :move))
    damages = Enum.filter(events, &(Map.get(&1.payload, :kind) == :damage))

    {h_events, world, rng} = hazard_phase(world, rng, moves)
    {s_events, world} = side_effect_phase(world, moves, damages)
    {b_events, world} = boundary_phase(world, events)
    {a_events, world, rng} = due_arrivals_phase(world, rng)

    {:ok, h_events ++ s_events ++ b_events ++ a_events, world, rng}
  end

  defp hazard_phase(world, rng, moves) do
    Enum.reduce(moves, {[], world, rng}, fn mv, {evs, w, r} ->
      {:ok, e, w2, r2} = Cognition.Hazard.check_move(w, r, mv.payload)
      {:ok, e3, w3, r3} = Cognition.Hazard.check_presence(w2, r2, mv.payload.agent_id)
      {evs ++ e ++ e3, w3, r3}
    end)
  end

  defp side_effect_phase(world, moves, damages) do
    emissions =
      Enum.map(moves, fn mv ->
        {:footsteps, mv.payload.to, mv.payload.agent_id, 3, "soft footsteps"}
      end) ++
        Enum.map(damages, fn dm ->
          about = Map.get(dm.payload, :attacker_id, dm.payload.target_id)
          target_place = place_of_agent(world, dm.payload.target_id)
          {:combat, target_place, about, 7, "the sounds of violent blows"}
        end)

    Enum.reduce(emissions, {[], world}, fn
      {_class, nil, _about, _intensity, _nl}, {evs, w} ->
        {evs, w}

      {class, place, about, intensity, nl}, {evs, w} ->
        emit_at(w, place, about, class, intensity, nl, evs)
    end)
  end

  defp emit_at(w, place, about, class, intensity, nl, evs) do
    {:ok, e, w2} =
      Signals.emit_at(
        w,
        about,
        place,
        :sound,
        %{class: class, threat: class == :combat, about: about, count: 1},
        intensity,
        nl
      )

    {evs ++ e, w2}
  end

  defp place_of_agent(world, agent_id) do
    case World.agent(world, agent_id) do
      %Types.Agent{place_id: p} -> p
      nil -> nil
    end
  end

  defp boundary_phase(world, events) do
    Enum.reduce(events, {[], world}, fn ev, {evs, w} ->
      {:ok, e, w2} = Boundaries.evaluate(w, ev)
      {evs ++ e, w2}
    end)
  end

  defp due_arrivals_phase(world, rng) do
    due =
      world.in_flight
      |> Enum.filter(&(&1.tick <= world.tick))
      |> Enum.sort_by(&{&1.ref, &1.place_id})

    Enum.reduce(due, {[], world, rng}, fn arrival, {evs, w, r} ->
      {arr_evs, w2, r2} = process_arrival(w, r, arrival)
      {evs ++ arr_evs, w2, r2}
    end)
  end

  defp arrivals_phase(world, rng, t) do
    due = world.in_flight |> Enum.filter(&(&1.tick == t)) |> Enum.sort_by(&{&1.ref, &1.place_id})

    Enum.reduce(due, {[], world, rng}, fn arrival, {evs, w, r} ->
      {arr_evs, w2, r2} = process_arrival(w, r, arrival)
      {reflex_evs, w3, r3} = reflex_phase(w2, r2, arrival)

      {evs ++ arr_evs ++ reflex_evs, w3, r3}
    end)
  end

  defp process_arrival(world, rng, arrival) do
    ev = arrival_event(arrival)
    w1 = Fold.fold(world, [ev])
    {:ok, recv_evs, w2, r2} = Perception.receive_arrival(w1, rng, arrival)
    {:ok, b_evs, w3} = Boundaries.evaluate(w2, ev)
    {[ev] ++ recv_evs ++ b_evs, w3, r2}
  end

  defp arrival_event(arrival) do
    %Ledger.Event{
      seq: 0,
      tick: arrival.tick,
      class: :signal,
      payload: %{
        kind: :signal_arrived,
        ref: arrival.ref,
        place_id: arrival.place_id,
        tick: arrival.tick,
        intensity: arrival.intensity,
        signal_kind: arrival.kind,
        about: arrival.about
      }
    }
  end

  defp reflex_phase(world, rng, arrival) do
    stimulated =
      world.agents
      |> Map.values()
      |> Enum.filter(&(&1.tier == 1 and &1.place_id == arrival.place_id))
      |> Enum.filter(fn a ->
        entry = get_in(a.beliefs, [arrival.place_id, arrival.about])

        entry != nil and entry.last_tick == world.tick and
          entry.last_fidelity >= @reflex_fidelity and entry.salience >= @reflex_salience
      end)
      |> Enum.sort_by(& &1.id)

    Enum.reduce(stimulated, {[], world, rng}, fn rat, {evs, w, r} ->
      {:ok, e, w2, r2} = Cognition.Reflex.decide(w, r, rat)
      {evs ++ e, w2, r2}
    end)
  end

  defp commitments_phase(world, rng, t) do
    Enum.reduce(Commitments.due(world, t), {[], world, rng}, fn c, {evs, w, r} ->
      {:ok, e, w2} = Commitments.mark_due(w, c.id)
      {:ok, b_evs, w3} = Boundaries.evaluate(w2, hd(e))
      {evs ++ e ++ b_evs, w3, r}
    end)
  end

  defp cadence_phase(world, rng, t) do
    due =
      world.agents
      |> Map.values()
      |> Enum.filter(
        &(&1.attention == :alert and &1.cadence != nil and
            &1.cadence.next_due != nil and &1.cadence.next_due <= t)
      )
      |> Enum.sort_by(& &1.id)

    Enum.reduce(due, {[], world, rng}, fn a, {evs, w, r} ->
      case a.tier do
        0 ->
          ev = %Ledger.Event{
            seq: 0,
            tick: t,
            class: :meta,
            payload: %{kind: :cadence_tick, agent_id: a.id, due: t, next_due: t + a.cadence.every}
          }

          w_armed = fold_cadence(w, ev)

          # One strike pattern per place per tick: only the first due tier-0 agent runs it.
          first_t0 = Enum.find(due, fn d -> d.tier == 0 and d.place_id == a.place_id end)

          if first_t0.id == a.id do
            intruder =
              w_armed.agents
              |> Map.values()
              |> Enum.filter(&(&1.place_id == a.place_id and &1.tier != 0 and alive?(&1)))
              |> Enum.sort_by(& &1.id)
              |> List.first()

            if intruder do
              {:ok, e2, w3, r2} = Cognition.Hazard.check_presence(w_armed, r, intruder.id)
              {evs ++ [ev] ++ e2, w3, r2}
            else
              {evs ++ [ev], w_armed, r}
            end
          else
            {evs ++ [ev], w_armed, r}
          end

        2 ->
          {:ok, e, w2, r2} = Cognition.Pack.decide(w, r, a)
          {evs ++ e, w2, r2}

        _ ->
          ev = %Ledger.Event{
            seq: 0,
            tick: t,
            class: :meta,
            payload: %{kind: :cadence_tick, agent_id: a.id, due: t, next_due: t + a.cadence.every}
          }

          {evs ++ [ev], fold_cadence(w, ev), r}
      end
    end)
  end

  defp fold_cadence(world, ev) do
    Fold.update_agent(world, ev.payload.agent_id, fn a ->
      %{a | cadence: %{a.cadence | next_due: ev.payload.next_due}}
    end)
  end

  defp alive?(%Types.Agent{body: body}) do
    hp = (body && body.hp) || 0
    conds = (body && body.conditions) || []
    hp > 0 and :dead not in conds
  end

  defp sleep_phase(world) do
    world.boundaries
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.filter(&Boundaries.sleep_ready?(world, &1))
    |> Enum.reduce({[], world}, fn b, {evs, w} ->
      {:ok, e, w2} = Boundaries.sleep(w, b.id)
      {evs ++ e, w2}
    end)
  end

  defp tick_event(t),
    do: %Ledger.Event{seq: 0, tick: t, class: :meta, payload: %{kind: :tick_advance, to: t}}
end
