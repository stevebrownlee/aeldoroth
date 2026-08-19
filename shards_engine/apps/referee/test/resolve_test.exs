defmodule Referee.ResolveTest do
  @moduledoc "Action resolution via engine rules (plan Task 9)."
  use ExUnit.Case, async: true
  alias EngineCore.{Ledger, Types, World}
  alias Referee.Resolve

  defp world do
    pc =
      struct!(Types.Agent,
        id: "pc",
        name: "PC",
        tier: 3,
        place_id: "hall",
        body: %{hp: 5, conditions: []},
        statblock: %{ac: 5, hd: 1, hp_max: 7, thac0: 20, morale: 8, int: 10, damage: %{dice: 1, sides: 8, plus: 0}},
        beliefs: %{"hall" => %{"gob" => %{count: 1, last_tick: 1, last_fidelity: 4, seen: true, salience: 0.8}}}
      )

    gob =
      struct!(Types.Agent,
        id: "gob",
        name: "Gob",
        tier: 1,
        place_id: "hall",
        body: %{hp: 3, conditions: []},
        statblock: %{ac: 6, hd: 1, hp_max: 3, thac0: 20, morale: 6, int: 8, damage: %{dice: 1, sides: 4, plus: 0}}
      )

    %World{
      places: %{
        "hall" => %Types.Place{id: "hall", name: "Room hall", kind: :room, connections: ["crypt"]},
        "crypt" => %Types.Place{id: "crypt", name: "Crypt", kind: :room, connections: ["hall"]}
      },
      edges: [struct!(Types.Edge, id: "e1", from: "hall", to: "crypt", label: "north")],
      agents: %{"pc" => pc, "gob" => gob}
    }
  end

  defp rng, do: :rand.seed_s(:exsss, 42)

  test "destination resolves direction labels case-insensitively and target ids directly" do
    w = world()

    assert {:ok, "crypt"} =
             Resolve.destination(w, "hall", struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "NORTH"}))

    assert {:ok, "crypt"} = Resolve.destination(w, "hall", struct!(Types.Action, actor_id: "pc", verb: :move, target_id: "crypt"))

    assert {:error, :no_exit} =
             Resolve.destination(w, "hall", struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "sideways"}))

    assert {:error, :no_place} = Resolve.destination(w, "hall", struct!(Types.Action, actor_id: "pc", verb: :move, target_id: "moon"))
  end

  test "move resolves through Movement.traverse and mutates place" do
    a = struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "north"})
    {:ok, events, w2, _r2} = Resolve.act(world(), rng(), a)

    assert [%Ledger.Event{class: :world, payload: %{kind: :move, to: "crypt"}}] = events
    assert w2.agents["pc"].place_id == "crypt"
  end

  test "unresolvable move is a diegetic fail with no world change" do
    a = struct!(Types.Action, actor_id: "pc", verb: :move, params: %{direction: "sideways"})
    assert {:diegetic_fail, [], w, _r} = Resolve.act(world(), rng(), a)
    assert w == world()
  end

  test "strike on an engaged target resolves through Combat with ledgered rolls" do
    a = struct!(Types.Action, actor_id: "pc", verb: :strike, target_id: "gob")
    {:ok, events, w2, _r2} = Resolve.act(world(), rng(), a)

    assert Enum.any?(events, &(&1.class == :dice and &1.payload[:purpose] == :to_hit))

    if damage = Enum.find(events, &(&1.payload[:kind] == :damage)) do
      assert damage.payload.target_id == "gob"
      assert w2.agents["gob"].body.hp <= 3
    end
  end

  test "strike on a stale belief corrects the belief and records a miss" do
    w = put_in(world().agents["gob"].place_id, "crypt")
    a = struct!(Types.Action, actor_id: "pc", verb: :strike, target_id: "gob")

    assert {:diegetic_fail, events, w2, _r2} = Resolve.act(w, rng(), a)

    corrected = Enum.find(events, &(&1.payload[:kind] == :belief_corrected))
    assert corrected.payload.agent_id == "pc"
    assert corrected.payload.place_id == "hall"
    assert corrected.payload.about == "gob"

    assert Enum.any?(events, &(&1.class == :dice and &1.payload[:purpose] == :stale_swing))

    # the returned world actually lost the stale belief (resolve folds its own events)
    refute get_in(w2.agents["pc"].beliefs, ["hall", "gob"])
  end

  test "shout emits a sound signal at the actor's place" do
    a = struct!(Types.Action, actor_id: "pc", verb: :shout, params: %{message: "HELLO"})
    {:ok, events, _w2, _r2} = Resolve.act(world(), rng(), a)

    assert Enum.any?(events, fn ev ->
             ev.payload[:kind] == :signal_emitted and ev.payload[:origin_place_id] == "hall"
           end)
  end

  test "wait resolves to no events, world unchanged" do
    a = struct!(Types.Action, actor_id: "pc", verb: :wait)
    assert {:ok, [], w, _r} = Resolve.act(world(), rng(), a)
    assert w == world()
  end

  test "strike is deterministic from the same seed" do
    a = struct!(Types.Action, actor_id: "pc", verb: :strike, target_id: "gob")
    {:ok, events, _w2, r2} = Resolve.act(world(), rng(), a)
    {:ok, events_b, _w3, r3} = Resolve.act(world(), rng(), a)
    assert events == events_b and r2 == r3
  end
end
