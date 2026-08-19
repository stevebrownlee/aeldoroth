defmodule Agents.SalienceTest do
  @moduledoc "Cadence escalation gate: commitments or salient novelty buy deliberation."
  use ExUnit.Case, async: true
  alias Agents.Salience
  alias EngineCore.Types

  test "pending or due commitments escalate (cadence = commitment check)" do
    agent = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :pending}]}
    assert Salience.escalate?(agent, 5)
  end

  test "kept or violated commitments do not escalate alone" do
    agent = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :kept}]}
    refute Salience.escalate?(agent, 5)
  end

  test "a salient belief escalates; quiet agents do not" do
    quiet = %Types.Agent{id: "q", name: "Q", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"noise" => %{salience: 4.0}}}}
    refute Salience.escalate?(quiet, 5)

    scared = %Types.Agent{id: "s", name: "S", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"pc_thistle" => %{salience: 7.0}}}}
    assert Salience.escalate?(scared, 5)
  end

  test "beliefs in other places do not escalate" do
    far = %Types.Agent{id: "f", name: "F", tier: 3, place_id: "r1",
      beliefs: %{"r2" => %{"pc" => %{salience: 9.0}}}}
    refute Salience.escalate?(far, 5)
  end
end
