defmodule EngineCore.DiceTest do
  use ExUnit.Case, async: true

  test "same seed, same sequence" do
    r1 = EngineCore.Dice.new(42)
    r2 = EngineCore.Dice.new(42)
    {a, r1} = EngineCore.Dice.roll(r1, 20)
    {b, r2} = EngineCore.Dice.roll(r2, 20)
    assert a == b
    {[c1, c2], _} = EngineCore.Dice.roll(r1, 6, 2)
    {[d1, d2], _} = EngineCore.Dice.roll(r2, 6, 2)
    assert {c1, c2} == {d1, d2}
  end

  test "different seeds diverge" do
    rolls = for s <- 1..50 do
      {v, _} = EngineCore.Dice.new(s) |> EngineCore.Dice.roll(20)
      v
    end
    assert length(Enum.uniq(rolls)) > 1
  end

  test "results within bounds" do
    {v, _} = EngineCore.Dice.new(7) |> EngineCore.Dice.roll(6)
    assert v in 1..6
  end
end
