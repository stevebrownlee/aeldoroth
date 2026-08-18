defmodule EngineCore.PerceptionTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Dice, Fold, Perception, Types}

  defp arrival(intensity, opts \\ []) do
    struct!(Types.Arrival,
      ref: 1,
      place_id: "guard_room",
      tick: 5,
      kind: :sound,
      intensity: intensity,
      about: "pc1",
      hops: Keyword.get(opts, :hops, 0),
      origin_place_id: "entry_hall",
      content_core: %{class: :combat, threat: true, about: "pc1", count: 1}
    )
  end

  defp agent(int, attention \\ :alert) do
    struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "guard_room")
    |> Map.put(:statblock, %{
      ac: 6,
      hd: 1,
      hp_max: 5,
      thac0: 20,
      morale: 7,
      int: int,
      damage: %{dice: 1, sides: 6, plus: 0}
    })
    |> Map.put(:attention, attention)
  end

  test "base fidelity ladder and adjustments" do
    assert Perception.base_fidelity(arrival(9.5), agent(10)) == 5
    assert Perception.base_fidelity(arrival(7), agent(10)) == 4
    assert Perception.base_fidelity(arrival(5), agent(10)) == 3
    assert Perception.base_fidelity(arrival(3), agent(10)) == 2
    assert Perception.base_fidelity(arrival(1.5), agent(10)) == 1
    # adjacent room: -1
    assert Perception.base_fidelity(arrival(7, hops: 1), agent(10)) == 3
    # dormant guard: -2
    assert Perception.base_fidelity(arrival(7), agent(10, :dormant)) == 2
    # dim rat (int 1): -1
    assert Perception.base_fidelity(arrival(7), agent(1)) == 3
    # auto-high: deafening alarm is at least F3 for everyone
    assert Perception.base_fidelity(arrival(10, hops: 1), agent(1, :dormant)) == 3
    # ceiling: int 17 bonus cannot exceed F5
    assert Perception.base_fidelity(arrival(9.5), agent(17)) == 5
  end

  test "marginal signals resolve by d6 awareness" do
    a = arrival(1.5)
    g = agent(10)
    rng = Dice.new(42)
    {f1, roll1, rng2} = Perception.resolve_fidelity(Perception.base_fidelity(a, g), a, rng)
    {f2, _roll2, _} = Perception.resolve_fidelity(Perception.base_fidelity(a, g), a, rng2)
    assert is_nil(roll1) == false
    assert f1 in 0..1 and f2 in 0..1
    # strong signal: no roll, direct
    {f3, roll3, _} = Perception.resolve_fidelity(4, arrival(8), Dice.new(1))
    assert f3 == 4 and roll3 == nil
  end

  test "salience scoring" do
    g = agent(10)
    w = %EngineCore.World{agents: %{"g1" => g}}
    a = arrival(7)
    # 7 + 2 (same place) + 2 (novel) + 3 (threat) = 14 -> cap 10
    assert Perception.salience(a, g, w) == 10
  end

  test "receive_arrival emits per-agent events, updates beliefs via fold" do
    g1 = agent(10)
    g2 = agent(10) |> Map.put(:id, "g2") |> Map.put(:attention, :dormant)
    dead = agent(10) |> Map.put(:id, "g3") |> Map.update!(:body, &%{&1 | hp: 0})

    w = %EngineCore.World{
      agents: %{"g1" => g1, "g2" => g2, "g3" => dead},
      places: %{"guard_room" => %{}},
      tick: 5
    }

    {:ok, events, w2, _rng} = Perception.receive_arrival(w, Dice.new(7), arrival(8))
    receivers = events |> Enum.map(& &1.payload.agent_id)
    assert receivers == Enum.sort(receivers)
    assert "g1" in receivers and "g2" in receivers and "g3" not in receivers
    assert Enum.all?(events, &(&1.class == :signal and &1.payload.kind == :signal_received))
    assert Fold.fold(w, events) == w2
    assert w2.agents["g1"].beliefs["guard_room"]["pc1"].count == 1
  end
end
