defmodule EngineCore.BoundariesTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Boundaries, Fold, Ledger, Types}

  defp agent(id, place, opts \\ []) do
    struct!(Types.Agent, id: id, name: id, tier: opts[:tier] || 3, place_id: place)
    |> Map.put(:attention, Keyword.get(opts, :attention, :dormant))
    |> Map.put(:cadence, Keyword.get(opts, :cadence))
    |> Map.put(:commitments, Keyword.get(opts, :commitments, []))
  end

  defp world(boundaries, agents) do
    %EngineCore.World{
      agents: Map.new(agents, &{&1.id, &1}),
      boundaries: Map.new(boundaries, &{&1.id, &1}),
      places: %{"guard_room" => %{}, "entry_hall" => %{}},
      tick: 20
    }
  end

  defp guard_zone(opts \\ []) do
    struct!(Types.Boundary,
      id: "gz",
      scope_place_id: "guard_room",
      bound_agent_ids: ["g1"],
      triggers: [:presence_crossing, :signal_arrived]
    )
    |> Map.merge(Map.new(opts))
  end

  defp move_event(to),
    do: %Ledger.Event{
      seq: 1,
      tick: 20,
      class: :world,
      payload: %{kind: :move, agent_id: "pc1", from: "entry_hall", to: to, careful: false}
    }

  test "presence crossing wakes the zone and its agents" do
    g1 = agent("g1", "guard_room", cadence: %{every: 10, next_due: nil})
    w = world([guard_zone()], [g1, agent("pc1", "entry_hall", attention: :alert)])

    {:ok, events, w2} = Boundaries.evaluate(w, move_event("guard_room"))
    [wake] = Enum.filter(events, &(&1.payload.kind == :boundary_wake))
    assert wake.payload.id == "gz"
    assert wake.payload.reason == "presence_crossing by pc1"
    assert w2.boundaries["gz"].state == :awake
    assert w2.boundaries["gz"].last_trigger_tick == 20
    assert w2.agents["g1"].attention == :alert
    assert w2.agents["g1"].cadence.next_due == 21
    assert Fold.fold(w, events) == w2
  end

  test "signal arrival below intensity does not wake; at or above it does" do
    w = world([guard_zone(wake_on_intensity: 4)], [agent("g1", "guard_room")])

    weak = %Ledger.Event{
      seq: 1,
      tick: 20,
      class: :signal,
      payload: %{
        kind: :signal_arrived,
        ref: 1,
        place_id: "guard_room",
        tick: 20,
        intensity: 3.0,
        signal_kind: :sound,
        about: "pc1"
      }
    }

    {:ok, [], w2} = Boundaries.evaluate(w, weak)
    assert w2.boundaries["gz"].state == :dormant

    loud = %Ledger.Event{
      seq: 2,
      tick: 20,
      class: :signal,
      payload: %{
        kind: :signal_arrived,
        ref: 2,
        place_id: "guard_room",
        tick: 20,
        intensity: 6.3,
        signal_kind: :sound,
        about: "pc1"
      }
    }

    {:ok, events, _} = Boundaries.evaluate(w2, loud)
    assert Enum.any?(events, &(&1.payload.kind == :boundary_wake))
  end

  test "awake zones refresh instead of waking; movement by bound agents does not trigger" do
    awake = guard_zone(state: :awake, last_trigger_tick: 10)
    w = world([awake], [agent("g1", "guard_room")])
    {:ok, [refresh], _} = Boundaries.evaluate(w, move_event("guard_room"))
    assert refresh.payload.kind == :boundary_refresh

    {:ok, events2, _} =
      Boundaries.evaluate(
        w,
        %Ledger.Event{
          seq: 3,
          tick: 20,
          class: :world,
          payload: %{
            kind: :move,
            agent_id: "g1",
            from: "guard_room",
            to: "entry_hall",
            careful: false
          }
        }
      )

    assert events2 == []
  end

  test "group-scoped boundary wakes when a mover enters a member's place" do
    wolf_zone =
      struct!(Types.Boundary,
        id: "wz",
        scope_group: "wolf",
        bound_agent_ids: ["wolf_1"],
        triggers: [:presence_crossing]
      )

    w1 = agent("wolf_1", "beast_pen", tier: 2, group: "wolf")
    w = world([wolf_zone], [w1, agent("pc1", "entry_hall", attention: :alert)])

    ev = %Ledger.Event{
      seq: 1,
      tick: 20,
      class: :world,
      payload: %{
        kind: :move,
        agent_id: "pc1",
        from: "guard_room",
        to: "beast_pen",
        careful: false
      }
    }

    {:ok, events, w2} = Boundaries.evaluate(w, ev)
    assert Enum.any?(events, &(&1.payload.kind == :boundary_wake and &1.payload.id == "wz"))
    assert w2.agents["wolf_1"].attention == :alert
  end

  test "catchup fires overdue commitments with lateness, audited with provenance" do
    c = %Types.Commitment{id: "watch", debtor: "g1", deed: "keep_watch", due: 12}
    g1 = agent("g1", "guard_room", commitments: [c])
    w = world([guard_zone()], [g1]) |> Map.put(:tick, 20)

    {:ok, events, w2} = Boundaries.catchup(w, "gz")
    due_ev = Enum.find(events, &(&1.payload.kind == :commitment_due))
    assert due_ev.payload.late_by == 8
    audit = Enum.find(events, &(&1.payload.kind == :boundary_catchup))
    assert audit.payload.computed_at == 20
    assert audit.payload.note == "computed at wake, tick 20"
    assert w2.agents["g1"].commitments == [%{c | status: :due}]
    assert Fold.fold(w, events) == w2
  end

  test "sleep after sustained quiet; pending commitments hold sleep" do
    g1 = agent("g1", "guard_room")
    b = guard_zone(state: :awake, last_trigger_tick: 5, sleep_after: 40)
    w = world([b], [g1]) |> Map.put(:tick, 50)
    assert Boundaries.sleep_ready?(w, b) == true
    {:ok, [ev], w2} = Boundaries.sleep(w, "gz")
    assert ev.payload.kind == :boundary_sleep
    assert w2.boundaries["gz"].state == :dormant
    assert w2.agents["g1"].attention == :dormant

    busy =
      agent("g1", "guard_room",
        commitments: [%Types.Commitment{id: "c", debtor: "g1", deed: "x", due: 45}]
      )

    refute Boundaries.sleep_ready?(%{w | agents: %{"g1" => busy}}, b)
  end
end
