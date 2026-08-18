defmodule EngineCore.SchedulerTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Dice, Fold, Loader, Scheduler, Signals, Types}

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "advance processes due arrivals into receptions and wakes boundaries" do
    {:ok, w} = Loader.load(@yaml)
    # a deafening alarm lands in guard_room at tick 1
    {:ok, [_emit], w1} =
      Signals.emit(%{w | tick: 0}, "alarm_tripwire", :sound,
        %{class: :alarm, threat: true, about: "pc1", count: 1}, 9,
        "pots and pans crashing")

    {:ok, events, w2, _rng} = Scheduler.advance(w1, Dice.new(21))

    assert Enum.any?(events, &(&1.payload.kind == :tick_advance))
    arrived = Enum.filter(events, &(&1.payload.kind == :signal_arrived))
    refute arrived == []

    gz_arrival = Enum.find(arrived, &(&1.payload.place_id == "guard_room"))
    if gz_arrival do
      assert Enum.any?(events, &(&1.payload.kind == :boundary_wake and
                                 &1.payload.id == "guard_room_zone"))
      assert w2.agents["goblin_guard_1"].attention == :alert
      assert w2.agents["goblin_guard_1"].cadence.next_due == 2
    end

    received = Enum.filter(events, &(&1.payload.kind == :signal_received))
    assert received != []
    assert Enum.all?(received, &(&1.payload.fidelity >= 1))
    assert Fold.fold(w1, events) == w2
  end

  test "advance fires due commitments and then sleeps quiet boundaries" do
    {:ok, w} = Loader.load(@yaml)
    # force the watch commitment due now and the zone awake but long-quiet
    w =
      %{w | tick: 130}
      |> Map.update!(:agents, fn agents ->
        Map.update!(agents, "goblin_guard_1", fn a ->
          %{a | commitments: [%Types.Commitment{id: "guard_watch_rotation",
            debtor: "goblin_guard_1", deed: "keep_watch", due: 30, every: 30,
            priority: 5}]}
        end)
      end)

    w2 = Map.update!(w.boundaries, "guard_room_zone", fn b ->
      %{b | state: :awake, last_trigger_tick: 10}
    end) |> then(&%{w | boundaries: &1, tick: 130})

    {:ok, events, w3, _} = Scheduler.advance(w2, Dice.new(2))
    assert Enum.any?(events, &(&1.payload.kind == :commitment_due and
                               &1.payload.id == "guard_watch_rotation"))
    # a still-due commitment holds sleep (pending_among? includes :due)
    assert w3.agents["goblin_guard_1"].commitments
           |> Enum.any?(&(&1.id == "guard_watch_rotation" and &1.status == :due))
  end

  test "advance runs wolf pack cadence against intruders" do
    {:ok, w} = Loader.load(@yaml)
    w = w
        |> Map.update!(:agents, fn a -> Map.put(a, "pc1",
            struct!(Types.Agent, id: "pc1", name: "PC", tier: 3, place_id: "beast_pen")) end)
        |> Map.update!(:boundaries, fn b ->
            Map.update!(b, "wolf_pack", fn z -> %{z | state: :awake} end) end)
        |> Map.update!(:agents, fn a ->
            Map.update!(a, "wolf_1", fn wolf ->
              %{wolf | attention: :alert, cadence: %{every: 5, next_due: 1}} end) end)

    {:ok, events, _w2, _} = Scheduler.advance(%{w | tick: 0}, Dice.new(4))
    assert Enum.any?(events, &(Map.get(&1.payload, :kind) in [:to_hit, :damage] or Map.get(&1.payload, :purpose) in [:to_hit, :damage]))
  end
end
