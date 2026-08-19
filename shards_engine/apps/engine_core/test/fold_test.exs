defmodule EngineCore.FoldTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Fold, Ledger, Types, World}

  setup do
    g = struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "entry_hall", body: %{hp: 5, conditions: []})
    {:ok, w: %World{places: %{}, edges: [], agents: %{"g1" => g}, items: %{}, tick: 0}}
  end

  test "move event relocates agent and advances tick", %{w: w} do
    ev = %Ledger.Event{seq: 1, tick: 3, class: :world,
                       payload: %{kind: :move, agent_id: "g1", to: "guard_room"}}
    w2 = Fold.apply(w, ev)
    assert %Types.Agent{place_id: "guard_room"} = World.agent(w2, "g1")
    assert w2.tick == 3
  end

  test "damage reduces hp; death empties capabilities; morale_break adds condition", %{w: w} do
    w1 = Fold.apply(w, ev(1, 1, %{kind: :damage, target_id: "g1", amount: 3}))
    assert %Types.Agent{body: %{hp: 2}} = World.agent(w1, "g1")

    w2 = Fold.apply(w1, ev(2, 2, %{kind: :damage, target_id: "g1", amount: 9}))
    w3 = Fold.apply(w2, ev(3, 2, %{kind: :death, agent_id: "g1"}))
    assert %Types.Agent{body: %{hp: 0}, capabilities: []} = World.agent(w3, "g1")

    w4 = Fold.apply(w, ev(4, 1, %{kind: :morale_break, agent_id: "g1"}))
    assert :fleeing in World.agent(w4, "g1").body.conditions
  end

  test "fold folds in order; empty fold is identity", %{w: w} do
    evs = [ev(1, 1, %{kind: :damage, target_id: "g1", amount: 1})]
    assert %World{tick: 1} = w2 = Fold.fold(w, evs)
    assert Fold.fold(w2, []) == w2
  end

  test "out-of-order events preserve tick monotonicity", %{w: w} do
    w1 = Fold.apply(w, ev(1, 3, %{kind: :damage, target_id: "g1", amount: 1}))
    w2 = Fold.apply(w1, ev(2, 1, %{kind: :damage, target_id: "g1", amount: 1}))
    assert w2.tick == 3
  end

  test "unknown payload kind raises" do
    assert_raise ArgumentError, ~r/unknown payload kind/, fn ->
      Fold.apply(%World{}, ev(1, 0, %{kind: :teleport}))
    end
  end

  test "agent_added folds a new agent into the world (PC injection)", %{w: w} do
    pc = %{
      id: "pc_torvald",
      name: "Torvald",
      tier: 3,
      place_id: "entry_hall",
      body: %{hp: 9, conditions: []},
      capabilities: [:move, :strike, :shout, :wait]
    }

    w2 = Fold.apply(w, ev(1, 0, %{kind: :agent_added, agent: pc}))
    assert %Types.Agent{id: "pc_torvald", place_id: "entry_hall"} = World.agent(w2, "pc_torvald")
  end

  test "belief_corrected drops the belief; no-op for missing keys", %{w: w} do
    believed =
      Fold.apply(w, ev(1, 1, %{kind: :signal_received, agent_id: "g1", place_id: "entry_hall",
                             about: "pc_torvald", fidelity: 3, salience: 5.0, signal_kind: :sound}))

    assert get_in(World.agent(believed, "g1").beliefs, ["entry_hall", "pc_torvald"]).count == 1

    corrected =
      Fold.apply(believed, ev(2, 2, %{kind: :belief_corrected, agent_id: "g1",
                                      place_id: "entry_hall", about: "pc_torvald"}))

    assert get_in(World.agent(corrected, "g1").beliefs, ["entry_hall", "pc_torvald"]) == nil
    assert get_in(World.agent(corrected, "g1").beliefs, ["entry_hall"]) == %{}

    # missing key is a no-op, not a crash
    noop =
      Fold.apply(corrected, ev(3, 3, %{kind: :belief_corrected, agent_id: "g1",
                                        place_id: "entry_hall", about: "never_was"}))

    assert World.agent(noop, "g1").beliefs == corrected |> World.agent("g1") |> Map.get(:beliefs)
  end

  test "envelope_adopted and envelope_rejected mutate envelope status", %{w: w} do
    env = struct!(Types.Envelope,
      id: "env-0-1", from: "g1", to: "pc1", type: :order, payload_nl: "go",
      sent_tick: 0, delivery_place: "entry_hall", signal_ref: 7
    )
    w = %{w | envelopes: [env]}

    adopted =
      Fold.apply(w, ev(1, 1, %{kind: :envelope_adopted, id: "env-0-1", roll: 15, adopted: true}))

    assert hd(adopted.envelopes).adopted == true
    assert hd(adopted.envelopes).status == :adopted

    rejected =
      Fold.apply(w, ev(2, 2, %{kind: :envelope_rejected, id: "env-0-1", reason: "cowardice"}))

    assert hd(rejected.envelopes).adopted == false
    assert hd(rejected.envelopes).status == :rejected
  end

  defp ev(seq, tick, payload),
    do: %Ledger.Event{seq: seq, tick: tick, class: :world, payload: payload}
end
