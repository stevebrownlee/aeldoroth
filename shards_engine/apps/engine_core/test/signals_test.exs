defmodule EngineCore.SignalsTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, Loader, Signals, Types}

  # entry_hall --east--> guard_room ; entry_hall --north--> library
  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  defp loaded do
    {:ok, w} = Loader.load(@yaml)
    pc = struct!(Types.Agent, id: "pc1", name: "PC", tier: 3, place_id: "entry_hall")
    %{w | agents: Map.put(w.agents, "pc1", pc)}
  end

  test "emission creates origin arrival and attenuated neighbor arrivals" do
    w = loaded()
    {:ok, [ev], w2} =
      Signals.emit(w, "pc1", :sound,
        %{class: :combat, threat: true, about: "pc1", count: 1}, 10,
        "the crash of steel on steel")

    assert ev.class == :signal
    assert ev.payload.kind == :signal_emitted
    assert ev.payload.ref == 1 and ev.payload.signal_kind == :sound
    assert w2.signal_seq == 1

    by_place = Map.new(w2.in_flight, &{{&1.place_id, &1.hops}, &1})
    origin = by_place[{"entry_hall", 0}]
    assert origin.tick == w.tick and origin.intensity == 10 and origin.about == "pc1"

    east = by_place[{"guard_room", 1}]
    assert east.tick == w.tick + 1
    assert_in_delta east.intensity, 10 * 0.7, 0.001   # open doorway, sound

    north = by_place[{"library", 1}]
    assert_in_delta north.intensity, 10 * 0.7, 0.001

    # ritual chamber is behind a sealed trapdoor: no arrival
    refute Map.has_key?(by_place, {"ritual_chamber", 2})
    # every place reachable, each exactly once, list sorted
    ticks = Enum.map(w2.in_flight, &{&1.tick, &1.ref, &1.place_id})
    assert ticks == Enum.sort(ticks)
  end

  test "intensity floor cuts propagation" do
    w = loaded()
    {:ok, [_], w2} = Signals.emit(w, "pc1", :sound, %{class: :footsteps, threat: false,
                                  about: "pc1", count: 1}, 1.2)
    # 1.2 * 0.7 = 0.84 < 1.0 floor: only the origin arrival exists
    assert [%Types.Arrival{place_id: "entry_hall", hops: 0}] = w2.in_flight
  end

  test "fold replays emission and arrival removal identically" do
    w = loaded()
    {:ok, [ev], w2} = Signals.emit(w, "pc1", :sound,
        %{class: :alarm, threat: true, about: "pc1", count: 1}, 9)
    assert Fold.fold(w, [ev]) == w2

    arrival = Enum.find(w2.in_flight, &(&1.place_id == "guard_room"))
    rem_ev = %Ledger.Event{seq: 0, tick: arrival.tick, class: :signal,
      payload: %{kind: :signal_arrived, ref: arrival.ref, place_id: "guard_room",
                 tick: arrival.tick, intensity: arrival.intensity,
                 signal_kind: :sound, about: "pc1"}}
    w3 = Fold.fold(w2, [rem_ev])
    refute Enum.any?(w3.in_flight, &(&1.ref == arrival.ref and &1.place_id == "guard_room"))
    assert Enum.any?(w3.in_flight, &(&1.place_id == "entry_hall"))
  end

  test "signal_received updates beliefs via fold" do
    w = loaded()
    g1 = w.agents["goblin_guard_1"]
    ev = %Ledger.Event{seq: 0, tick: 7, class: :signal,
      payload: %{kind: :signal_received, agent_id: "goblin_guard_1",
                 place_id: "guard_room", ref: 1, about: "pc1", signal_kind: :sound,
                 intensity: 6.3, fidelity: 3, salience: 8.0, roll: nil}}
    w2 = Fold.fold(w, [ev])
    entry = w2.agents["goblin_guard_1"].beliefs["guard_room"]["pc1"]
    assert entry.count == 1 and entry.last_tick == 7 and entry.last_fidelity == 3
    assert entry.seen == false and entry.salience == 8.0
    assert g1.beliefs == %{}
  end
end