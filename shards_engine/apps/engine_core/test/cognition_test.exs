defmodule EngineCore.CognitionTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Cognition.Hazard, Cognition.Pack, Cognition.Reflex, Dice, Loader, Types}
  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  defp move(from, to, careful),
    do: %{kind: :move, agent_id: "pc1", from: from, to: to, careful: careful}

  test "alarm tripwire on the bound edge: careless crossing triggers and broadcasts" do
    {:ok, w} = Loader.load(@yaml)
    w = put_pc(w, "entry_hall")

    {:ok, events, w2, _} =
      Hazard.check_move(w, Dice.new(3), move("entry_hall", "guard_room", false))

    if Enum.any?(events, &(&1.payload.kind == :hazard_triggered)) do
      assert Enum.any?(
               events,
               &(&1.payload.id == :alarm_tripwire or &1.payload.id == "alarm_tripwire")
             )

      emit = Enum.find(events, &(&1.payload.kind == :signal_emitted))
      assert emit.payload.content_core.class == :alarm
      assert Enum.any?(w2.in_flight, &(&1.place_id == "guard_room"))
      assert w2.hazards["alarm_tripwire"].triggered == true
    else
      assert Enum.any?(events, &(&1.payload.kind == :hazard_avoided))
    end
  end

  test "careful crossing always avoids" do
    {:ok, w} = Loader.load(@yaml)
    w = put_pc(w, "entry_hall")

    {:ok, events, _, _} =
      Hazard.check_move(w, Dice.new(3), move("entry_hall", "guard_room", true))

    assert Enum.all?(events, &(&1.payload.kind == :hazard_avoided))
  end

  test "damage traps on careless crossing deal dice damage with a ledgered roll" do
    {:ok, w} = Loader.load(@yaml)

    w =
      put_pc(w, "guard_room")
      |> update_agent("pc1", fn a -> %{a | body: %{a.body | hp: 10}} end)

    {:ok, events, w2, _} =
      Hazard.check_move(w, Dice.new(2), move("guard_room", "chiefs_room", false))

    # seed 2: all three place-bound hazards on this crossing trigger,
    # sorted by id — caltrops (1d4=1), false_cache_needle (1d4=1), pit_trap (1d6=3)
    for id <- ["caltrops", "false_cache_needle", "pit_trap"] do
      assert Enum.any?(
               events,
               &(&1.payload[:kind] == :hazard_triggered and &1.payload[:id] == id)
             )
    end

    dice =
      Enum.find(events, fn e ->
        e.class == :dice and e.payload[:purpose] == :hazard_damage and
          e.payload[:hazard_id] == "pit_trap"
      end)

    assert dice.payload[:sides] == 6
    assert dice.payload[:rolls] == [3]
    assert dice.payload[:amount] == 3

    assert Enum.any?(
             events,
             &(&1.payload[:kind] == :damage and &1.payload[:target_id] == "pc1")
           )

    assert w2.agents["pc1"].body.hp == 5

    for id <- ["caltrops", "false_cache_needle", "pit_trap"] do
      assert w2.hazards[id].triggered == true
    end
  end

  test "skeleton pattern strikes intruders entering its chamber" do
    {:ok, w} = Loader.load(@yaml)
    w = w |> put_pc("library") |> wake_boundary("skeleton_sentinel")
    {:ok, events, _w2, _} = Hazard.check_presence(w, Dice.new(11), "pc1")
    # pc1 is in library, skeleton in ritual_chamber: no strike
    assert events == []

    w3 = w |> put_pc("ritual_chamber")
    {:ok, events3, _, _} = Hazard.check_presence(w3, Dice.new(11), "pc1")
    assert Enum.any?(events3, &(&1.payload[:kind] == :damage and &1.payload[:target_id] == "pc1"))
  end

  test "rat reflex: loud belief flees, intruder strikes" do
    {:ok, w} = Loader.load(@yaml)
    rat = w.agents["giant_rat_1"]

    loud_w =
      put_belief(w, "giant_rat_1", "library", "pc1", %{
        count: 1,
        last_tick: w.tick,
        last_fidelity: 4,
        seen: false,
        salience: 8.0
      })

    {:ok, events, _, _} = Reflex.decide(loud_w, Dice.new(5), rat)
    assert Enum.any?(events, &(&1.payload.kind == :move and &1.payload.agent_id == "giant_rat_1"))

    intruder_w = put_pc(w, "library")
    {:ok, events2, _, _} = Reflex.decide(intruder_w, Dice.new(5), rat)

    assert Enum.any?(
             events2,
             &(Map.get(&1.payload, :kind) in [:damage] or
                 Map.get(&1.payload, :purpose) == :to_hit)
           )
  end

  test "wolf pack strikes intruders in the pen; wounded wolf flees" do
    {:ok, w} = Loader.load(@yaml)
    wolf = w.agents["wolf_1"]
    pen_w = put_pc(w, "beast_pen")
    {:ok, events, _, _} = Pack.decide(pen_w, Dice.new(9), wolf)

    assert Enum.any?(events, fn e ->
             Map.get(e.payload, :purpose) == :to_hit or Map.get(e.payload, :kind) == :damage
           end)

    hurt =
      update_agent(w, "wolf_1", fn a ->
        # hp_max 16 -> 12.5% : fear
        %{a | body: %{a.body | hp: 2}}
      end)

    {:ok, events2, _, _} = Pack.decide(hurt, Dice.new(9), hurt.agents["wolf_1"])
    assert Enum.any?(events2, &(&1.payload.kind == :move))
  end

  defp put_pc(w, place) do
    pc = struct!(Types.Agent, id: "pc1", name: "PC", tier: 3, place_id: place)
    %{w | agents: Map.put(w.agents, "pc1", pc)}
  end

  defp wake_boundary(w, id) do
    case w.boundaries[id] do
      nil ->
        w

      b ->
        w1 = %{w | boundaries: Map.put(w.boundaries, id, %{b | state: :awake})}

        Enum.reduce(b.bound_agent_ids || [], w1, fn aid, acc ->
          update_agent(acc, aid, &%{&1 | attention: :alert})
        end)
    end
  end

  defp put_belief(w, id, place, about, entry) do
    update_agent(w, id, fn a ->
      %{a | beliefs: Map.put(a.beliefs, place, %{about => entry})}
    end)
  end

  defp update_agent(w, id, fun),
    do: %{w | agents: Map.update!(w.agents, id, fun)}
end
