defmodule EngineCore.Signals do
  @moduledoc """
  Signal emission and edge-attenuated propagation (spec 6.1, decision 21).
  Pure: no dice. Arrival facts live in world.in_flight; the scheduler
  converts them to :signal_arrived events at their tick.
  """
  alias EngineCore.{Fold, Ledger, Types, World}

  @attenuation %{
    open: %{sight: 0.5, sound: 0.7, smell: 0.4, tremor: 0.8},
    muffled: %{sight: 0.1, sound: 0.3, smell: 0.1, tremor: 0.4}
  }
  @intensity_floor 1.0
  @hop_delay 1

  @spec emit(World.t(), String.t(), atom, map, number, String.t() | nil) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def emit(world, emitted_by, kind, content_core, intensity, content_nl \\ nil) do
    origin = origin_place(world, emitted_by)
    emit_at(world, emitted_by, origin, kind, content_core, intensity, content_nl)
  end

  @spec emit_at(World.t(), String.t(), String.t(), atom, map, number, String.t() | nil) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def emit_at(world, emitted_by, origin, kind, content_core, intensity, content_nl \\ nil) do
    ref = world.signal_seq + 1
    about = Map.get(content_core, :about, :unknown)

    facts = propagate(world, origin, kind, intensity)

    arrivals =
      for f <- facts do
        %Types.Arrival{
          ref: ref,
          place_id: f.place_id,
          tick: f.tick,
          kind: kind,
          intensity: f.intensity,
          about: about,
          hops: f.hops,
          origin_place_id: origin,
          content_core: content_core,
          content_nl: content_nl
        }
      end

    ev = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :signal,
      payload: %{
        kind: :signal_emitted,
        ref: ref,
        emitted_by: emitted_by,
        origin_place_id: origin,
        signal_kind: kind,
        intensity: intensity,
        content_core: content_core,
        content_nl: content_nl,
        arrivals: Enum.map(arrivals, &arrival_payload/1)
      }
    }

    {:ok, [ev], Fold.fold(world, [ev])}
  end

  def arrival_payload(%Types.Arrival{} = a) do
    Map.take(a, [
      :ref,
      :place_id,
      :tick,
      :kind,
      :intensity,
      :about,
      :hops,
      :origin_place_id,
      :content_core,
      :content_nl
    ])
  end

  defp origin_place(world, emitted_by) do
    case World.agent(world, emitted_by) do
      %Types.Agent{place_id: p} ->
        p

      nil ->
        (world.hazards[emitted_by] || raise ArgumentError, "unknown emitter #{emitted_by}").place_id
    end
  end

  # Level-ordered BFS. Each frontier expansion is sorted by {place_id, edge_id};
  # first (earliest) arrival per place wins.
  defp propagate(world, origin, kind, intensity) do
    frontier = [{origin, intensity, 0}]
    visited = MapSet.new([origin])
    acc = [%{place_id: origin, tick: world.tick, intensity: intensity * 1.0, hops: 0}]

    {acc, _visited} =
      expand_levels(world, kind, frontier, visited, acc, world.tick)

    acc
  end

  defp expand_levels(_world, _kind, [], visited, acc, _t), do: {acc, visited}

  defp expand_levels(world, kind, frontier, visited, acc, t) do
    next_tick = t + @hop_delay
    hops = div(next_tick - world.tick, @hop_delay)

    next =
      frontier
      |> Enum.flat_map(fn
        {place, intensity, _hops} ->
          place
          |> neighbors(world, kind)
          |> Enum.map(fn {n_place, att, _edge_id} -> {n_place, intensity * att, hops} end)

        {place, intensity} ->
          place
          |> neighbors(world, kind)
          |> Enum.map(fn {n_place, att, _edge_id} -> {n_place, intensity * att, hops} end)
      end)
      |> Enum.filter(fn {_p, i, _h} -> i >= @intensity_floor end)
      |> Enum.sort_by(fn {p, _i, _h} -> p end)
      |> Enum.uniq_by(fn {p, _i, _h} -> p end)
      |> Enum.reject(fn {p, _i, _h} -> MapSet.member?(visited, p) end)

    next_acc =
      acc ++
        for {p, i, h} <- next,
            do: %{
              place_id: p,
              tick: next_tick,
              intensity: i,
              hops: h
            }

    expand_levels(
      world,
      kind,
      next,
      MapSet.union(visited, MapSet.new(Enum.map(next, &elem(&1, 0)))),
      next_acc,
      next_tick
    )
  end

  defp neighbors(place, world, kind) do
    world.edges
    |> Enum.filter(fn e -> e.from == place and not e.sealed end)
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn e ->
      perm = permeability_for(e, kind)
      {e.to, attenuation(perm, kind), e.id}
    end)
    |> Enum.reject(fn {_p, att, _e} -> att == nil end)
  end

  defp permeability_for(edge, kind) do
    Map.get(edge.permeability || %{}, kind, :muffled)
  end

  defp attenuation(:blocked, _kind), do: nil
  defp attenuation(perm, kind), do: get_in(@attenuation, [perm, kind])
end