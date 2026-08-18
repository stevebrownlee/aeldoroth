defmodule EngineCore.Dice do
  @moduledoc "Pure seeded RNG. :rand.uniform_s threads state explicitly — no process seed."

  @spec new(integer) :: :rand.state()
  def new(seed_int) do
    :rand.seed_s(:exsss, {seed_int, seed_int + 0x9E37, seed_int + 0x7F4A})
  end

  @spec roll(:rand.state(), pos_integer) :: {pos_integer, :rand.state()}
  def roll(rng, sides), do: :rand.uniform_s(sides, rng)

  @spec roll(:rand.state(), pos_integer, pos_integer) :: {[pos_integer], :rand.state()}
  def roll(rng, sides, k), do: roll_n(rng, sides, k, [])

  defp roll_n(rng, _sides, 0, acc), do: {Enum.reverse(acc), rng}

  defp roll_n(rng, sides, k, acc) do
    {v, rng2} = :rand.uniform_s(sides, rng)
    roll_n(rng2, sides, k - 1, [v | acc])
  end
end
