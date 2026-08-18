defmodule EngineCore.CascadeReplayTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Loader, Scenario}

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @tag :golden
  test "same seed replays byte-identically; different seeds diverge" do
    a = Scenario.alarm_cascade(@yaml, 1234)
    b = Scenario.alarm_cascade(@yaml, 1234)
    c = Scenario.alarm_cascade(@yaml, 99)

    assert :erlang.term_to_binary(a.ledger) == :erlang.term_to_binary(b.ledger)
    assert :erlang.term_to_binary(a.ledger) != :erlang.term_to_binary(c.ledger)
  end

  @tag :golden
  test "fold reconstructs the final world from the ledger alone" do
    {:ok, seed} = Loader.load(@yaml)
    r = Scenario.alarm_cascade(@yaml, 1234)
    rebuilt = Fold.fold(Scenario.add_party(seed), Enum.map(r.ledger, &drop_seq/1))
    assert rebuilt.tick == r.final_world.tick
    assert rebuilt.agents == r.final_world.agents
    assert rebuilt.boundaries == r.final_world.boundaries
    assert rebuilt.in_flight == r.final_world.in_flight
  end

  test "the cascade machinery fires and dormancy holds where nothing happened" do
    r = Scenario.alarm_cascade(@yaml, 1234)
    kinds = r.ledger |> Enum.map(&Map.get(&1.payload, :kind))

    triggered = :hazard_triggered in kinds

    if triggered do
      assert :signal_emitted in kinds and :signal_arrived in kinds and
               :signal_received in kinds

      assert :boundary_wake in kinds
      # the guard zone woke because of the alarm or the intrusion
      gz = r.final_world.boundaries["guard_room_zone"]
      assert gz.state == :awake or gz.last_trigger_tick != nil
    else
      assert :hazard_avoided in kinds
    end

    # wolves and skeleton stay dormant: the party never went there
    assert r.final_world.boundaries["wolf_pack"].state == :dormant
    assert r.final_world.boundaries["skeleton_sentinel"].state == :dormant
    assert r.final_world.agents["wolf_1"].attention == :dormant
  end

  defp drop_seq(ev), do: %{ev | seq: 0}
end
