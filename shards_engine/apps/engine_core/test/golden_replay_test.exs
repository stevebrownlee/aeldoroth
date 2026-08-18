defmodule EngineCore.GoldenReplayTest do
  use ExUnit.Case, async: false
  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "same yaml + seed + script = byte-identical ledger" do
    r1 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    r2 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    assert :erlang.term_to_binary(r1.ledger) == :erlang.term_to_binary(r2.ledger)
  end

  test "different seed diverges" do
    r1 = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    r2 = EngineCore.Scenario.party_vs_warband(@yaml, 5678)
    assert :erlang.term_to_binary(r1.ledger) != :erlang.term_to_binary(r2.ledger)
  end

  test "fold of ledger equals scenario's final world" do
    r = EngineCore.Scenario.party_vs_warband(@yaml, 1234)
    {:ok, base} = EngineCore.Loader.load(@yaml)
    refolded = EngineCore.Fold.fold(EngineCore.Scenario.add_party(base), r.ledger)
    assert refolded.tick == r.final_world.tick
    assert refolded.agents == r.final_world.agents
  end
end
