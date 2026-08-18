defmodule EngineCore.Types do
  @moduledoc "Pure data structs shared across the engine. No behavior."

  defmodule Place do
    @enforce_keys [:id, :name, :kind, :connections]
    defstruct [:id, :name, :kind, :connections]
  end

  defmodule Edge do
    @enforce_keys [:id, :from, :to]
    defstruct [:id, :from, :to, sealed: false, permeability: %{sight: :open, sound: :open}]
  end

  defmodule Agent do
    @enforce_keys [:id, :name, :tier, :place_id]
    defstruct [
      :id,
      :name,
      :tier,
      :place_id,
      statblock: %{
        ac: 10,
        hd: 1,
        hp_max: 1,
        thac0: 20,
        morale: 7,
        int: 10,
        damage: %{dice: 1, sides: 6, plus: 0}
      },
      body: %{hp: 1, conditions: []},
      capabilities: [:move, :strike, :wait],
      beliefs: %{},
      commitments: [],
      cadence: nil,
      dossier: %{}
    ]
  end

  defmodule Item do
    @enforce_keys [:id, :name, :value_gp]
    defstruct [:id, :name, :value_gp, place_id: nil, holder_id: nil, is_hidden: false]
  end

  defmodule Action do
    @enforce_keys [:actor_id, :verb]
    defstruct [:actor_id, :verb, target_id: nil, params: %{}]
  end
end
