defmodule EngineCore.LedgerTest do
  use ExUnit.Case, async: true
  alias EngineCore.Ledger

  test "appends are ordered, seq monotonic, reads stable" do
    l = start_ledger!()
    e1 = Ledger.append(l, :world, 1, %{kind: :move, agent_id: "g1", to: "guard_room"})
    e2 = Ledger.append(l, :dice, 1, %{roll: 15, sides: 20})
    assert e1.seq == 1 and e2.seq == 2
    assert [%{seq: 1}, %{seq: 2}] = Ledger.events(l)
    Ledger.append(l, :meta, 2, %{kind: :mode, mode: :combat})
    assert [%{seq: 1}, %{seq: 2}, %{seq: 3}] = Ledger.events(l)
  end

  test "events carry no wall-clock fields" do
    l = start_ledger!()
    e = Ledger.append(l, :world, 0, %{kind: :noop})
    refute Map.has_key?(e, :timestamp)
    assert e.class == :world and e.tick == 0
  end

  test "two ledgers are independent; clear resets" do
    la = start_ledger!()
    lb = start_ledger!()
    Ledger.append(la, :meta, 0, %{a: 1})
    assert Ledger.events(lb) == []
    :ok = Ledger.clear(la)
    assert Ledger.events(la) == []
  end

  defp start_ledger! do
    name = :"ledger_#{:erlang.unique_integer([:positive])}"
    start_supervised!({Ledger, name: name}, id: name)
    name
  end
end
