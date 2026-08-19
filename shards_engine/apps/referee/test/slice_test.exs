defmodule Referee.SliceTest do
  use ExUnit.Case, async: true
  alias EngineCore.Types
  alias EngineCore.World
  alias Referee.Slice

  defp world do
    mk = fn id, place ->
      struct!(Types.Agent,
        id: id,
        name: String.upcase(id),
        tier: 3,
        place_id: place,
        body: %{hp: 5, conditions: []}
      )
    end

    place = fn id -> %Types.Place{id: id, name: "Room #{id}", kind: :room, connections: []} end

    beliefs = %{
      "hall" => %{
        "goblin_guard_1" => %{count: 2, last_tick: 4, last_fidelity: 4, seen: true, salience: 0.8},
        "ghost" => %{count: 1, last_tick: 2, last_fidelity: 2, seen: false, salience: 0.3}
      },
      "crypt" => %{
        "rat_1" => %{count: 1, last_tick: 1, last_fidelity: 1, seen: true, salience: 0.9}
      }
    }

    %World{
      places: %{"hall" => place.("hall"), "crypt" => place.("crypt")},
      edges: [
        %Types.Edge{id: "e1", from: "hall", to: "crypt"},
        %Types.Edge{id: "e2", from: "crypt", to: "hall"}
      ],
      agents: %{
        "pc" => struct!(mk.("pc", "hall"), beliefs: beliefs),
        "goblin_guard_1" => mk.("goblin_guard_1", "hall"),
        "rat_1" => mk.("rat_1", "crypt")
      },
      items: %{
        "sword" => %Types.Item{id: "sword", name: "Sword", value_gp: 10, place_id: "hall"},
        "gem" => %Types.Item{id: "gem", name: "Gem", value_gp: 500, place_id: "hall", is_hidden: true}
      }
    }
  end

  test "for_actor returns identity, place with exits, and current-place beliefs only" do
    s = Slice.for_actor(world(), "pc")

    assert s.agent == %{id: "pc", name: "PC", place_id: "hall"}
    assert s.place.name == "Room hall"
    assert s.place.kind == :room
    assert s.place.exits == ["crypt"]

    # believed: abouts at the actor's current place, sorted; crypt belief must not leak
    assert s.believed == ["ghost", "goblin_guard_1"]
    refute "rat_1" in s.believed

    # salient: seen beliefs only, salience-descending
    assert s.salient == ["goblin_guard_1"]
  end

  test "hidden items never appear anywhere in the slice" do
    s = Slice.for_actor(world(), "pc")

    # direct: visible_items lists only the unconcealed item at the place
    assert s.place.visible_items == ["sword"]

    # whole-term: no field of the slice leaks the hidden gem — the slice is
    # the only world data a prompt may reference (acceptance criterion 5)
    refute inspect(s) =~ "gem"
    refute to_string(:erlang.term_to_binary(s)) =~ "gem"
  end

  test "prompt_slice_ref is a stable lowercase md5 hex, sensitive to content" do
    w = world()
    a = Slice.for_actor(w, "pc")
    b = Slice.for_actor(w, "pc")

    # same world content → identical slice and identical ref
    w2 = put_in(w.agents["pc"].beliefs["hall"]["goblin_guard_1"].count, 2)
    c = Slice.for_actor(w2, "pc")

    assert a == b
    assert Slice.prompt_slice_ref(a) == Slice.prompt_slice_ref(b)
    assert Slice.prompt_slice_ref(a) == Slice.prompt_slice_ref(c)
    assert String.match?(Slice.prompt_slice_ref(a), ~r/^[0-9a-f]{32}$/)

    # unseen→seen flips a prompt-visible fact: salient list changes
    w3 = put_in(w.agents["pc"].beliefs["hall"]["ghost"].seen, true)
    d = Slice.for_actor(w3, "pc")
    refute a == d
    refute Slice.prompt_slice_ref(a) == Slice.prompt_slice_ref(d)
  end

  test "summary mentions the place and believed agent names" do
    s = Slice.for_actor(world(), "pc")

    assert s.summary =~ "Room hall"
    assert s.summary =~ "GOBLIN_GUARD_1"
  end

end
