defmodule EngineCore.CommitmentsTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Commitments, Fold, Types}

  defp world_with(commitment) do
    a =
      struct!(Types.Agent, id: "g1", name: "Gob", tier: 3, place_id: "guard_room")
      |> Map.put(:commitments, if(commitment, do: [commitment], else: []))

    %EngineCore.World{agents: %{"g1" => a}, tick: 10}
  end

  test "create adds a commitment through the ledger" do
    w = world_with(nil) |> Map.put(:tick, 5)

    {:ok, [ev], w2} =
      Commitments.create(w,
        id: "c1",
        debtor: "g1",
        deed: "keep_watch",
        due: 30,
        every: 30,
        priority: 6
      )

    assert ev.class == :commitment and ev.payload.kind == :commitment_created

    assert [%Types.Commitment{id: "c1", status: :pending, priority: 6}] =
             w2.agents["g1"].commitments

    assert Fold.fold(w, [ev]) == w2
  end

  test "create with unknown debtor errors" do
    assert {:error, :no_debtor} =
             Commitments.create(%EngineCore.World{}, id: "x", debtor: "ghost", deed: "y")
  end

  test "due query returns pending commitments past the tick, priority-sorted" do
    w =
      world_with(%Types.Commitment{id: "low", debtor: "g1", deed: "a", due: 5, priority: 1})
      |> put_agent_commitment("g1", %Types.Commitment{
        id: "high",
        debtor: "g1",
        deed: "b",
        due: 8,
        priority: 9
      })
      |> put_agent_commitment("g1", %Types.Commitment{
        id: "future",
        debtor: "g1",
        deed: "c",
        due: 40,
        priority: 9
      })

    assert Enum.map(Commitments.due(w, 10), & &1.id) == ["high", "low"]
  end

  test "mark_due, keep re-arms recurring, violate" do
    w = world_with(%Types.Commitment{id: "c", debtor: "g1", deed: "a", due: 30, every: 30})
    {:ok, [ev_due], w2} = Commitments.mark_due(w, "c")
    assert ev_due.payload == %{kind: :commitment_due, id: "c", debtor: "g1", late_by: 0}

    assert w2.agents["g1"].commitments == [
             %Types.Commitment{
               id: "c",
               debtor: "g1",
               deed: "a",
               due: 30,
               every: 30,
               priority: 5,
               status: :due
             }
           ]

    {:ok, [ev_keep], w3} = Commitments.keep(w2, "c")
    # world.tick 10 + every 30
    assert ev_keep.payload.rearm_due == 40
    assert %{status: :pending, due: 40} = hd(w3.agents["g1"].commitments)

    {:ok, [ev_due], w4} = Commitments.mark_due(w3, "c", 2)
    assert ev_due.payload.late_by == 2
    {:ok, [_], w5} = Commitments.violate(w4, "c")
    assert hd(w5.agents["g1"].commitments).status == :violated
    # every fold round-trips
    assert Fold.fold(w2, [ev_keep]) == w3
  end

  test "renegotiate moves the due date" do
    w = world_with(%Types.Commitment{id: "c", debtor: "g1", deed: "a", due: 30})
    {:ok, [ev], w2} = Commitments.renegotiate(w, "c", 99)
    assert ev.payload.kind == :commitment_renegotiated
    assert hd(w2.agents["g1"].commitments).due == 99
    assert hd(w2.agents["g1"].commitments).status == :pending
  end

  defp put_agent_commitment(w, id, c) do
    %{w | agents: Map.update!(w.agents, id, fn a -> %{a | commitments: a.commitments ++ [c]} end)}
  end
end
