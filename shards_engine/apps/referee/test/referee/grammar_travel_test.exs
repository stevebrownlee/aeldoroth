defmodule Referee.GrammarTravelTest do
  @moduledoc """
  Regression: travel preambles ("I set out north...", "make my way to the
  library") must parse as :move, not fall to {:unclear} hesitate.
  """
  use ExUnit.Case, async: true

  alias EngineCore.World
  alias Referee.Grammar

  setup do
    world = %World{
      places: %{
        "maras_inn" => %{id: "maras_inn"},
        "library" => %{id: "library"}
      },
      agents: %{}
    }

    {:ok, world: world}
  end

  test "set out north parses as move north", %{world: world} do
    assert %EngineCore.Types.Action{verb: :move, params: %{direction: "north"}} =
             Grammar.parse(world, "pc_thistle", "I set out north from the inn toward the old tower road, watching for tracks.")
  end

  test "head off east parses as move east", %{world: world} do
    assert %EngineCore.Types.Action{verb: :move, params: %{direction: "east"}} =
             Grammar.parse(world, "pc_thistle", "head off east")
  end

  test "make my way to the library parses as move to library", %{world: world} do
    assert %EngineCore.Types.Action{verb: :move, target_id: "library"} =
             Grammar.parse(world, "pc_thistle", "make my way to the library")
  end

  test "bare go north still parses", %{world: world} do
    assert %EngineCore.Types.Action{verb: :move, params: %{direction: "north"}} =
             Grammar.parse(world, "pc_thistle", "go north")
  end

  test "follow a companion east parses as move east", %{world: world} do
    assert %EngineCore.Types.Action{verb: :move, params: %{direction: "east"}} =
             Grammar.parse(world, "pc_thistle", "I follow Bramble east and keep my sword ready.")
  end
end
