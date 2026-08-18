defmodule EngineCore.Boundaries do
  @moduledoc """
  Boundary activation (spec 4.2/4.3, decision 25). Boundaries are dormant
  until a trigger fires; wake starts bound agents' cadences; sustained
  quiet sleeps. Lazy catch-up: overdue commitments of bound agents fire at
  wake with lateness, audited with provenance.
  """
  alias EngineCore.{Commitments, Fold, Ledger, Types, World}

  @spec evaluate(World.t(), Ledger.Event.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def evaluate(world, event) do
    world.boundaries
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.flat_map_reduce(world, fn b, w ->
      case trigger_for(w, b, event) do
        nil ->
          {[], w}

        reason ->
          if b.state == :dormant do
            {:ok, evs, w2} = wake(w, b.id, event.tick, reason)
            {evs, w2}
          else
            ev = refresh_event(w, b.id, event.tick)
            {[ev], Fold.fold(w, [ev])}
          end
      end
    end)
    |> then(fn {events, w} -> {:ok, events, w} end)
  end

  @spec wake(World.t(), String.t(), integer(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def wake(world, id, tick, reason) do
    b = Map.fetch!(world.boundaries, id)
    wake_ev = wake_event(world, b, tick, reason)
    w2 = Fold.fold(world, [wake_ev])
    catchup(w2, id, wake_events: [wake_ev])
  end

  @spec catchup(World.t(), String.t(), Keyword.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def catchup(world, id, opts \\ []) do
    b = Map.fetch!(world.boundaries, id)
    tick = world.tick

    overdue =
      world.agents
      |> Map.values()
      |> Enum.filter(&(&1.id in b.bound_agent_ids))
      |> Enum.flat_map(& &1.commitments)
      |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
      |> Enum.sort_by(& &1.id)

    {due_events, w2} =
      Enum.flat_map_reduce(overdue, world, fn c, w ->
        {:ok, evs, w2} = Commitments.mark_due(w, c.id, tick - c.due)
        {evs, w2}
      end)

    audit =
      if overdue != [] do
        earliest = overdue |> Enum.map(& &1.due) |> Enum.min()

        [
          %Ledger.Event{
            seq: 0,
            tick: tick,
            class: :meta,
            payload: %{
              kind: :boundary_catchup,
              id: id,
              computed_at: tick,
              from_tick: earliest,
              to_tick: tick,
              note: "computed at wake, tick #{tick}"
            }
          }
        ]
      else
        []
      end

    w3 = Fold.fold(w2, audit)
    wake_events = Keyword.get(opts, :wake_events, [])
    {:ok, wake_events ++ due_events ++ audit, w3}
  end

  @spec sleep(World.t(), String.t()) :: {:ok, [Ledger.Event.t()], World.t()}
  def sleep(world, id) do
    b = Map.fetch!(world.boundaries, id)

    ev = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :meta,
      payload: %{kind: :boundary_sleep, id: id, bound_agent_ids: b.bound_agent_ids}
    }

    {:ok, [ev], Fold.fold(world, [ev])}
  end

  @spec sleep_ready?(World.t(), Types.Boundary.t()) :: boolean()
  def sleep_ready?(world, b) do
    b.state == :awake and b.last_trigger_tick != nil and
      world.tick - b.last_trigger_tick >= b.sleep_after and
      not pending_among?(world, b)
  end

  defp pending_among?(world, b) do
    world.agents
    |> Map.values()
    |> Enum.filter(&(&1.id in b.bound_agent_ids))
    |> Enum.any?(fn a ->
      Enum.any?(
        a.commitments,
        &(&1.status in [:pending, :due] and &1.due != nil and &1.due <= world.tick)
      )
    end)
  end

  defp trigger_for(world, b, %Ledger.Event{
         payload: %{kind: :move, agent_id: mover, to: to, from: from}
       }) do
    if :presence_crossing in b.triggers and mover not in b.bound_agent_ids and
         (place_in_scope?(world, b, to) or place_in_scope?(world, b, from)) do
      "presence_crossing by #{mover}"
    end
  end

  defp trigger_for(world, b, %Ledger.Event{
         payload: %{kind: :signal_arrived, place_id: p, intensity: i}
       }) do
    if :signal_arrived in b.triggers and i >= b.wake_on_intensity and
         place_in_scope?(world, b, p) do
      "signal_arrived intensity #{Float.round(i * 1.0, 2)}"
    end
  end

  defp trigger_for(_world, b, %Ledger.Event{payload: %{kind: :commitment_due, debtor: d}}) do
    if :commitment_due in b.triggers and d in b.bound_agent_ids do
      "commitment_due by #{d}"
    end
  end

  defp trigger_for(_world, _b, _event), do: nil

  defp place_in_scope?(world, b, place) do
    cond do
      b.scope_place_id != nil ->
        place == b.scope_place_id

      b.scope_group != nil ->
        world.agents
        |> Map.values()
        |> Enum.any?(fn a ->
          (a.group == b.scope_group or a.id in b.bound_agent_ids) and a.place_id == place
        end)

      true ->
        world.agents
        |> Map.values()
        |> Enum.any?(&(&1.id in b.bound_agent_ids and &1.place_id == place))
    end
  end

  defp wake_event(_world, b, tick, reason) do
    %Ledger.Event{
      seq: 0,
      tick: tick,
      class: :meta,
      payload: %{
        kind: :boundary_wake,
        id: b.id,
        tick: tick,
        reason: reason,
        bound_agent_ids: b.bound_agent_ids
      }
    }
  end

  defp refresh_event(_world, id, tick) do
    %Ledger.Event{
      seq: 0,
      tick: tick,
      class: :meta,
      payload: %{kind: :boundary_refresh, id: id, tick: tick}
    }
  end
end
