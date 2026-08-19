defmodule LLMGateway.SchemaTest do
  use ExUnit.Case, async: true
  alias LLMGateway.Schema

  # Shape mirrors the interpret-stage schema from Shared Interfaces.
  @schema %{
    type: :object,
    required: [:verb, :target],
    properties: %{
      verb: %{type: :string, enum: ["move", "strike", "shout", "wait"]},
      target: %{type: :string},
      direction: %{type: :string},
      assumptions: %{type: :array, items: %{type: :string}}
    }
  }

  test "accepts a valid interpret payload" do
    payload = %{
      "verb" => "move",
      "target" => "north door",
      "assumptions" => ["door is unlocked"]
    }

    assert Schema.validate(payload, @schema) == :ok
  end

  test "accepts atom-keyed payloads too" do
    assert Schema.validate(%{verb: "wait", target: "x"}, @schema) == :ok
  end

  test "rejects missing required key" do
    assert {:error, msg} = Schema.validate(%{"target" => "x"}, @schema)
    assert msg =~ "verb"
  end

  test "rejects wrong type" do
    assert {:error, msg} = Schema.validate(%{"verb" => 42, "target" => "x"}, @schema)
    assert msg =~ "verb" and msg =~ "string"
  end

  test "rejects out-of-enum value" do
    assert {:error, msg} = Schema.validate(%{"verb" => "dance", "target" => "x"}, @schema)
    assert msg =~ "verb"
  end

  test "rejects bad items entry in array" do
    payload = %{"verb" => "wait", "target" => "x", "assumptions" => ["fine", 7]}
    assert {:error, msg} = Schema.validate(payload, @schema)
    assert msg =~ "assumptions"
  end

  test "rejects non-object at root when object required" do
    assert {:error, _} = Schema.validate(["nope"], @schema)
  end
end
