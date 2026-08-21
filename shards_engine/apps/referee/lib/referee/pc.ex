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
    struct!(
      Types.Agent,
      id: pc_map.id,
      name: pc_map.name,
      tier: 3,
      place_id: pc_map[:place_id] || "entry_hall",
      statblock: %{
        ac: pc_map[:ac] || 10,
        hd: pc_map[:hd] || 1,
        hp_max: pc_map[:hp] || 1,
        thac0: pc_map[:thac0] || 20,
        morale: 12,
        int: pc_map[:int] || 10,
        damage: parse_damage(Map.fetch!(pc_map, :damage)),
        class: pc_map[:class],
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
