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
      places: %{"hall" => place.("hall"), "crypt" => place.("crypt"), "vault" => place.("vault")},
      edges: [
        %Types.Edge{id: "e1", from: "hall", to: "crypt", label: "north"},
        %Types.Edge{id: "e2", from: "crypt", to: "hall"},
        %Types.Edge{id: "e3", from: "hall", to: "vault", label: "iron door", sealed: true}
      ],
      agents: %{
        "pc" =>
        struct!(mk.("pc", "hall"), beliefs: beliefs, statblock: %{
          ac: 12,
          hd: 1,
          hp_max: 10,
          thac0: 18,
          morale: 7,
          int: 8,
          damage: %{dice: 1, sides: 8, plus: 2}
        }),
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
    assert s.place.exits == ["crypt", "vault"]

    # believed: abouts at the actor's current place, sorted; crypt belief must not leak
    assert s.believed == ["ghost", "goblin_guard_1"]
    refute "rat_1" in s.believed

    # salient: seen beliefs only, salience-descending
    assert s.salient == ["goblin_guard_1"]
  end

  test "exits_labeled carries direction, destination, and seal for one-click moves" do
    s = Slice.for_actor(world(), "pc")

    assert s.place.exits_labeled == [
             %{dir: "north", to: "crypt", sealed: false},
             %{dir: "iron door", to: "vault", sealed: true}
           ]
  end

  test "hidden items never appear anywhere in the slice" do
    s = Slice.for_actor(world(), "pc")

    # direct: visible_items lists only the unconcealed item at the place
    assert s.place.visible_items == ["sword"]

    # whole-term: no field of the slice leaks the hidden gem — the slice is
    # the only world data a prompt may reference (acceptance criterion 5).
    # inspect/1 is the whole-term check: term_to_binary is unusable here
    # because raw encoding bytes forge substrings across field boundaries
    # (e.g. the :damage atom's trailing bytes plus the next value's string
    # tag encode "gem" without any gem anywhere in the slice).
    refute inspect(s) =~ "gem"
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

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "slice carries commitments (5-field maps, id-sorted) and capabilities" do
    {:ok, w} = EngineCore.Loader.load(@yaml)

    grisk = EngineCore.World.agent(w, "grisk_the_snatcher")
    s = Slice.for_actor(w, "grisk_the_snatcher")
    assert s.commitments ==
             Enum.sort_by(
               Enum.map(grisk.commitments, fn c ->
                 %{id: c.id, deed: c.deed, status: c.status, priority: c.priority, creditor: c.creditor}
               end),
               & &1.id
             )
    assert "grisk_relocation_deadline" in Enum.map(s.commitments, & &1.id)

    for c <- s.commitments do
      assert Map.keys(c) |> Enum.sort() == [:creditor, :deed, :id, :priority, :status]
    end

    assert s.capabilities == grisk.capabilities

    pc = struct!(Types.Agent, id: "pc_x", name: "X", tier: 3, place_id: "entry_hall")
    w2 = %{w | agents: Map.put(w.agents, "pc_x", pc)}
    assert Slice.for_actor(w2, "pc_x").commitments == []
  end

  test "summary mentions the place and believed agent names" do
    s = Slice.for_actor(world(), "pc")

    assert s.summary =~ "Room hall"
    assert s.summary =~ "GOBLIN_GUARD_1"
  end

  test "for_actor adds the actor sheet, believed agent names, and visible item details" do
    s = Slice.for_actor(world(), "pc")

    assert s.sheet == %{
             hp: 5,
             hp_max: 10,
             ac: 12,
             thac0: 18,
             damage: "1d8+2",
             conditions: [],
             morale: 7,
             int: 8,
             hd: 1
           }

    assert s.believed_agents == [
             %{id: "ghost", name: "ghost"},
             %{id: "goblin_guard_1", name: "GOBLIN_GUARD_1"}
           ]

    assert s.place.items == [%{id: "sword", name: "Sword"}]
  end

end
