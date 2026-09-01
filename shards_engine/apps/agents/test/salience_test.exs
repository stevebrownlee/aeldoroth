defmodule Agents.SalienceTest do
  @moduledoc "Cadence escalation gate: commitments or salient novelty buy deliberation."
  use ExUnit.Case, async: true
  alias Agents.Salience
  alias EngineCore.Types

  test "due commitments and adopted orders escalate; scheduled pending ones do not" do
    due = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :due}]}
    assert Salience.escalate?(due, 5, world())

    # Adopted orders have no scheduled due tick: they demand action at once.
    adopted = %Types.Agent{id: "a", name: "A", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c2", debtor: "a", deed: "slay", status: :pending}]}
    assert Salience.escalate?(adopted, 5, world())

    # A scheduled commitment whose due tick has not arrived is context,
    # not pressure: the every-window, not the cadence, sets its rhythm.
    scheduled = %Types.Agent{id: "s", name: "S", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c3", debtor: "s", deed: "plead", status: :pending, due: 30}]}
    refute Salience.escalate?(scheduled, 5, world())
    refute Salience.escalate?(scheduled, 29, world())
    assert Salience.escalate?(scheduled, 30, world())
  end

  test "kept or violated commitments do not escalate alone" do
    agent = %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", commitments: [
      %Types.Commitment{id: "c1", debtor: "g", deed: "watch", status: :kept}]}
    refute Salience.escalate?(agent, 5, world())
  end

  test "a salient belief escalates; quiet agents do not" do
    quiet = %Types.Agent{id: "q", name: "Q", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"noise" => %{salience: 4.0}}}}
    refute Salience.escalate?(quiet, 5, world())

    scared = %Types.Agent{id: "s", name: "S", tier: 3, place_id: "r",
      beliefs: %{"r" => %{"pc_thistle" => %{salience: 7.0}}}}
    assert Salience.escalate?(scared, 5, world())
  end

  test "beliefs in other places do not escalate" do
    far = %Types.Agent{id: "f", name: "F", tier: 3, place_id: "r1",
      beliefs: %{"r2" => %{"pc" => %{salience: 9.0}}}}
    refute Salience.escalate?(far, 5, world())
  end

  test "a brain that has perceived a present player escalates; an unfelt one does not" do
    felt =
      %Types.Agent{id: "g", name: "G", tier: 3, place_id: "r", pc: false,
        beliefs: %{"r" => %{"pc_thistle" => %{salience: 1.0}}}, commitments: []}

    pc_here = %Types.Agent{id: "pc_thistle", name: "T", tier: 3, place_id: "r", pc: true}
    pc_gone = %Types.Agent{id: "pc_x", name: "X", tier: 3, place_id: "elsewhere", pc: true}
    world = %EngineCore.World{agents: %{"g" => felt, "pc_thistle" => pc_here, "pc_x" => pc_gone}}

    # Low salience, not due, no commitment pressure — only the player's
    # perceived presence buys this deliberation.
    assert Salience.escalate?(felt, 5, world)

    # A hidden player (no belief ever formed) triggers nothing: the gate
    # reads beliefs, not bare world truth.
    unfelt = %{felt | beliefs: %{}}
    refute Salience.escalate?(unfelt, 5, %EngineCore.World{agents: %{"g" => unfelt, "pc_thistle" => pc_here}})
  end

  defp world, do: %EngineCore.World{agents: %{}}
end
