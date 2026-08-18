defmodule EngineCore.World do
  @moduledoc "World container + query helpers. State is data."
  defstruct places: %{}, edges: [], agents: %{}, items: %{}, tick: 0
  @type t :: %__MODULE__{}

  def agents_in(%__MODULE__{agents: agents}, place_id),
    do: agents |> Map.values() |> Enum.filter(&(&1.place_id == place_id))

  def agent(%__MODULE__{agents: agents}, id), do: agents[id]
  def place(%__MODULE__{places: places}, id), do: places[id]
end
