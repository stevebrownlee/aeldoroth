defmodule Referee.PC do
  @moduledoc """
  PC agent construction and injection events (spec §5; decision 16).

  PCs are tier-3 engine agents whose intent channel is the human client.
  `build/1` takes the pc_map from `Run` (which stamps `place_id` from the
  adventure's `starting_room`): `%{id, name, place_id, int, ac, hd, hp,
  thac0, damage: "1d8"}` with `damage` in `NdM[+K]` notation.
  """

  alias EngineCore.{Ledger, Types}

  @pc_capabilities [:move, :strike, :wait, :shout]

  @spec build(map()) :: Types.Agent.t()
  def build(pc_map) do
    level = pc_map[:level] || pc_map[:hd] || 1
    class = pc_map[:class]
    thac0 = pc_map[:thac0] || calculate_thac0(class, level)

    struct!(
      Types.Agent,
      id: pc_map.id,
      name: pc_map.name,
      tier: 3,
      place_id: pc_map[:place_id] || "entry_hall",
      statblock: %{
        ac: pc_map[:ac] || 10,
        hd: level,
        level: level,
        xp: pc_map[:xp] || 0,
        hp_max: pc_map[:hp] || 1,
        thac0: thac0,
        morale: 12,
        int: pc_map[:int] || 10,
        damage: parse_damage(Map.fetch!(pc_map, :damage)),
        class: class,
        race: pc_map[:race],
        armor: pc_map[:armor],
        weapons: pc_map[:weapons],
        inventory: pc_map[:inventory],
        spells: pc_map[:spells],
        prayers: pc_map[:prayers]
      },
      body: %{hp: pc_map[:hp] || 1, conditions: []},
      capabilities: @pc_capabilities,
      beliefs: %{},
      commitments: [],
      cadence: nil,
      attention: :alert,
      pc: true
    )
  end

  @doc """
  Calculates AD&D 1E base THAC0 based on class and character level (PHB / DMG p. 74).
  """
  @spec calculate_thac0(String.t() | nil, integer()) :: integer()
  def calculate_thac0(class, level \\ 1)

  def calculate_thac0(class, level) when is_integer(level) and level >= 1 do
    normalized = if is_binary(class), do: String.downcase(String.trim(class)), else: ""

    case normalized do
      f when f in ["fighter", "paladin", "ranger"] ->
        group = div(level - 1, 2)
        max(20 - group * 2, 4)

      c when c in ["cleric", "druid", "monk"] ->
        group = div(level - 1, 3)
        max(20 - group * 2, 9)

      t when t in ["thief", "assassin"] ->
        cond do
          level <= 4 -> 20
          level <= 8 -> 19
          level <= 12 -> 16
          level <= 16 -> 14
          level <= 20 -> 12
          true -> 10
        end

      m when m in ["magic-user", "magic user", "illusionist"] ->
        cond do
          level <= 5 -> 20
          level <= 10 -> 19
          level <= 15 -> 16
          level <= 20 -> 13
          true -> 11
        end

      _ ->
        20
    end
  end

  def calculate_thac0(_, _), do: 20

  @doc """
  One `:agent_added` event folding the PC in at `pc.place_id` (the entry place).
  `seq` is a placeholder — the ledger Writer stamps the real sequence number
  at append time; Fold only consumes tick + payload.
  """
  @spec join_events(EngineCore.World.t(), Types.Agent.t()) :: [Ledger.Event.t()]
  def join_events(%EngineCore.World{} = world, %Types.Agent{} = pc) do
    [
      %Ledger.Event{
        seq: 0,
        tick: world.tick,
        class: :world,
        payload: %{kind: :agent_added, agent: pc, place_id: pc.place_id}
      }
    ]
  end

  defp parse_damage(notation) when is_binary(notation) do
    case Regex.run(~r/^(\d+)d(\d+)(?:\+(\d+))?$/, notation) do
      [_, dice, sides, plus] ->
        %{
          dice: String.to_integer(dice),
          sides: String.to_integer(sides),
          plus: String.to_integer(plus)
        }

      [_, dice, sides] ->
        %{dice: String.to_integer(dice), sides: String.to_integer(sides), plus: 0}

      nil ->
        raise ArgumentError, "unparseable damage notation: #{inspect(notation)}"
    end
  end
end
