defmodule Referee.ValidateTest do
  @moduledoc "Diegetic validation (plan Task 9)."
  use ExUnit.Case, async: true
  alias EngineCore.{Types, World}
  alias Referee.Validate

  defp world do
    pc =
      struct!(Types.Agent,
        id: "pc",
        name: "PC",
        tier: 3,
        place_id: "hall",
        body: %{hp: 5, conditions: []},
        beliefs: %{"hall" => %{"gob" => %{count: 1, last_tick: 1, last_fidelity: 4, seen: true, salience: 0.8}}}
      )

    gob =
      struct!(Types.Agent, id: "gob", name: "Gob", tier: 1, place_id: "hall", body: %{hp: 3, conditions: []})

    %World{
      places: %{
        "hall" => %Types.Place{id: "hall", name: "Room hall", kind: :room, connections: ["crypt", "vault"]},
        "crypt" => %Types.Place{id: "crypt", name: "Crypt", kind: :room, connections: ["hall"]}
      },
      edges: [
        struct!(Types.Edge, id: "e1", from: "hall", to: "crypt", label: "north"),
        struct!(Types.Edge, id: "e2", from: "hall", to: "vault", label: "east", sealed: true)
      ],
      agents: %{"pc" => pc, "gob" => gob}
    }
  end

  test "verb outside capabilities is rejected" do
    w = world()
    a = struct!(Types.Action, actor_id: "pc", verb: :cast_fireball)

    assert {:reject, msg} = Validate.check(w, a)
    assert is_binary(msg)
  end

  test "strike with no belief about the target in place is diegetically rejected" do
    a = struct!(Types.Action, actor_id: "pc", verb: :strike, target_id: "rat_1")

    assert {:reject, msg} = Validate.check(world(), a)
    assert msg =~ "no such creature"
  end

  test "strike on a believed target passes" do
    a = struct!(Types.Action, actor_id: "pc", verb: :strike, target_id: "gob")
    assert :ok = Validate.check(world(), a)
  end

  test "move with no resolvable exit is diegetically rejected" do
    a = struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "up"})
    assert {:reject, msg} = Validate.check(world(), a)
    assert msg =~ "no way through"
  end

  test "move through a sealed edge is diegetically rejected" do
    a = struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "east"})
    assert {:reject, msg} = Validate.check(world(), a)
    assert msg =~ "sealed"
  end

  test "move by direction label and by target id both pass; wait and shout pass" do
    w = world()

    assert :ok = Validate.check(w, struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "north"}))
    assert :ok = Validate.check(w, struct!(Types.Action, actor_id: "pc", verb: :move, target_id: "crypt"))
    assert :ok = Validate.check(w, struct!(Types.Action, actor_id: "pc", verb: :wait))
    assert :ok = Validate.check(w, struct!(Types.Action, actor_id: "pc", verb: :shout, params: %{message: "hello"}))
  end

  test "move to a real place that is not adjacent is rejected" do
    # crypt is real but the pc is already in hall's neighbor set; use vault (sealed) covered above —
    # a non-adjacent real place:
    w = %World{world() | places: Map.put(world().places, "far", %Types.Place{id: "far", name: "Far", kind: :room, connections: []})}
    a = struct!(Types.Action, actor_id: "pc", verb: :move, target_id: "far")

    assert {:reject, _} = Validate.check(w, a)
  end
end
