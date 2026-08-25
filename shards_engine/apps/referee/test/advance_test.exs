defmodule Referee.AdvanceTest do
  @moduledoc """
  Task 8 chain: cadence → salience gate → deliberation → order envelope →
  receipt-keyed delivery → dice-checked adoption → commitment — plus the
  gate invariant and deception, all against the real tower YAML.
  """
  use ExUnit.Case, async: true
  alias Agents.{Adopt, Salience}
  alias EngineCore.{Fold, Loader, World}
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 20, hd: 1, hp: 50, thac0: 20, damage: "1d8"}
  ]

  defp scripts(over) do
    Map.merge(
      %{
        interpret: [
          ~s({"verb":"move","target_id":null,"params":{"direction":"east"}}),
          ~s({"verb":"move","params":{"direction":"south"}}),
          ~s({"verb":"wait"})
        ],
        narrate: [],
        # bodyguard_1's first escalated tick (t=13, via the adopted
        # commitment) must strike; the other tier-3s only ever wait.
        deliberate: [
          %{agent_id: "goblin_bodyguard_1",
            content: ~s({"verb":"strike","target_id":"pc_thistle","reason":"obeying orders"})},
          %{agent_id: "goblin_bodyguard_2",
            content: ~s({"verb":"wait","reason":"guarding the chief"})},
          %{agent_id: "goblin_bodyguard_2",
            content: ~s({"verb":"wait","reason":"still guarding"})},
          %{agent_id: "grisk_the_snatcher",
            content: ~s({"verb":"order","target_id":"goblin_bodyguard_1","message":"Kill the intruder!","reason":"intruders in my hall"})},
          %{agent_id: "grisk_the_snatcher",
            content: ~s({"verb":"wait","reason":"my will is done"})},
          %{agent_id: "goblin_guard_1",
            content: ~s({"verb":"wait","reason":"on watch"})},
          %{agent_id: "goblin_guard_1",
            content: ~s({"verb":"wait","reason":"still on watch"})},
          %{agent_id: "goblin_guard_2",
            content: ~s({"verb":"wait","reason":"on watch"})},
          %{agent_id: "goblin_guard_2",
            content: ~s({"verb":"wait","reason":"still on watch"})},
          %{agent_id: "goblin_guard_3",
            content: ~s({"verb":"wait","reason":"on watch"})},
          %{agent_id: "goblin_guard_3",
            content: ~s({"verb":"wait","reason":"still on watch"})},
          %{agent_id: "goblin_guard_4",
            content: ~s({"verb":"wait","reason":"on watch"})},
          %{agent_id: "goblin_guard_4",
            content: ~s({"verb":"wait","reason":"still on watch"})}
        ],
        adopt: [
          %{agent_id: "goblin_bodyguard_1",
            content: ~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"})}
        ],
        salt: System.unique_integer()
      },
      over
    )
  end

  defp new_run(over \\ %{}) do
    {:ok, run} = Run.new(@yaml, 42, @pcs, routing: routing(scripts(over)))
    run
  end

  defp routing(s) do
    cfg = %{adapter: Scripted, scripts: s}
    %{interpret: cfg, narrate: cfg, deliberate: cfg, adopt: cfg}
  end

  defp advance_until(run, pred, n) do
    Enum.reduce_while(1..n, {run, []}, fn _i, {acc, all} ->
      {:ok, texts, acc2} = Run.advance(acc)
      if pred.(acc2), do: {:halt, {acc2, [texts | all]}}, else: {:cont, {acc2, [texts | all]}}
    end)
  end

  defp enter_chiefs_room(run) do
    {:ok, _, run} = Run.declare(run, "pc_thistle", "go east")
    {:ok, _, run} = Run.advance(run)
    {:ok, _, run} = Run.declare(run, "pc_thistle", "go south")
    {:ok, _, run} = Run.advance(run)
    run
  end

  defp deliberations(run),
    do: Run.events(run) |> Enum.filter(&(&1.class == :deliberation))

  defp rows(run, agent_id),
    do: deliberations(run) |> Enum.filter(&(&1.payload[:agent_id] == agent_id))

  defp events_of(run, kind),
    do: Run.events(run) |> Enum.filter(&(&1.payload[:kind] == kind))

  defp order_sent?(run) do
    events_of(run, :envelope_sent)
    |> Enum.any?(&(&1.payload.envelope.to == "goblin_bodyguard_1"))
  end

  test "the PC's arrival escalates Grisk: he orders his bodyguard" do
    {run, _} = new_run() |> enter_chiefs_room() |> advance_until(&order_sent?/1, 15)

    assert Enum.any?(rows(run, "grisk_the_snatcher"), fn row ->
             row.payload[:decision] == :proposed and row.payload[:verb] == :order
           end)

    env =
      events_of(run, :envelope_sent)
      |> Enum.find(&(&1.payload.envelope.to == "goblin_bodyguard_1"))
      |> Map.fetch!(:payload)
      |> Map.fetch!(:envelope)

    assert env.from == "grisk_the_snatcher"
    assert env.type == :order
    assert env.payload_nl == "Kill the intruder!"
  end

  test "the order is delivered, dice-checked, and adopted into a commitment" do
    {run0, _} = new_run() |> enter_chiefs_room() |> advance_until(&order_sent?/1, 15)

    env =
      events_of(run0, :envelope_sent)
      |> Enum.find(&(&1.payload.envelope.to == "goblin_bodyguard_1"))
      |> Map.fetch!(:payload)
      |> Map.fetch!(:envelope)

    {run, _} =
      advance_until(run0, fn r -> events_of(r, :envelope_adopted) != [] end, 3)

    evs = Run.events(run)

    i_del =
      Enum.find_index(evs, &(&1.payload[:kind] == :envelope_delivered and &1.payload[:id] == env.id))

    {dice, i_dice} =
      evs
      |> Enum.with_index()
      |> Enum.find(fn {ev, i} ->
        i > i_del and ev.class == :dice and ev.payload[:purpose] == :adoption
      end)

    i_adopt =
      Enum.find_index(evs, &(&1.payload[:kind] == :envelope_adopted and &1.payload[:id] == env.id))

    i_commit =
      Enum.find_index(
        evs,
        &(&1.payload[:kind] == :commitment_created and
            &1.payload.commitment.id == "adopted:#{env.id}")
      )

    assert i_del != nil and i_dice != nil and i_adopt != nil and i_commit != nil
    assert i_del < i_dice and i_dice < i_adopt and i_adopt < i_commit

    assert dice.payload[:sides] == 20 and is_integer(dice.payload[:roll])

    bodyguard = World.agent(run.world, "goblin_bodyguard_1")
    assert dice.payload[:target] == Adopt.reliability(bodyguard, true)
    assert dice.payload[:adopted] == true

    c = Enum.find(bodyguard.commitments, &(&1.id == "adopted:#{env.id}"))
    assert c.debtor == "goblin_bodyguard_1"
    assert c.creditor == "grisk_the_snatcher"
    assert c.status == :pending
  end

  test "the bodyguard strikes the PC on a later cadence; the PC is narrated to" do
    {run0, _} = new_run() |> enter_chiefs_room() |> advance_until(&order_sent?/1, 15)

    {run1, _} =
      advance_until(run0, fn r -> events_of(r, :envelope_adopted) != [] end, 3)

    {run, all_texts} =
      advance_until(run1, fn r -> strike?(r) end, 12)

    evs = Run.events(run)

    {_strike_ev, i_strike} =
      Enum.with_index(evs)
      |> Enum.find(fn {ev, _} ->
        ev.class == :deliberation and ev.payload[:agent_id] == "goblin_bodyguard_1" and
          ev.payload[:decision] == :proposed and ev.payload[:verb] == :strike
      end)

    {attack_ev, i_attack} =
      Enum.with_index(evs)
      |> Enum.find(fn {ev, i} ->
        i > i_strike and ev.class == :dice and ev.payload[:purpose] == :attack and
          ev.payload[:agent_id] == "goblin_bodyguard_1"
      end)

    assert i_strike != nil and i_attack != nil and i_attack > i_strike,
           "strike=#{i_strike} attack=#{i_attack}"

    assert attack_ev.payload[:thac0] != nil
    assert attack_ev.payload[:target_ac] != nil
    assert attack_ev.payload[:hit] == (attack_ev.payload[:roll] >= attack_ev.payload[:thac0] - attack_ev.payload[:target_ac])

    assert Enum.any?(all_texts, fn texts -> texts["pc_thistle"] not in [nil, ""] end)
  end

  defp strike?(run) do
    Enum.any?(rows(run, "goblin_bodyguard_1"), fn row ->
      row.payload[:decision] == :proposed and row.payload[:verb] == :strike
    end)
  end

  test "gate invariant: every living tier-3 cadence tick leaves a row; skipped ticks spend nothing" do
    {run0, _} = new_run() |> enter_chiefs_room() |> advance_until(&order_sent?/1, 15)
    {run1, _} = advance_until(run0, fn r -> events_of(r, :envelope_adopted) != [] end, 3)

    {run, _} =
      advance_until(run1, fn r -> strike?(r) end, 12)

    evs = Run.events(run)
    {:ok, base} = Loader.load(@yaml)
    # only engine-mutating classes replay through Fold
    foldable = Enum.filter(evs, &(&1.class in [:world, :signal, :commitment, :envelope]))
    ticks = Enum.filter(evs, &(&1.payload[:kind] == :cadence_tick))
    for ct <- ticks do
      world_at = base |> Fold.fold(Enum.take_while(foldable, &(&1.seq < ct.seq)))
      agent = World.agent(world_at, ct.payload.agent_id)

      if agent != nil and agent.tier == 3 and alive?(agent) do
        row =
          deliberations(run)
          |> Enum.find(&(&1.payload[:agent_id] == ct.payload.agent_id and &1.tick == ct.tick))

        assert row != nil, "no deliberation row for #{ct.payload.agent_id} at #{ct.tick}"
        assert row.payload[:decision] in [:proposed, :hesitated, :rejected, :skipped]

        next_ct =
          Enum.find(ticks, fn t ->
            t.payload[:agent_id] == ct.payload.agent_id and t.seq > ct.seq
          end)

        llm_between =
          Enum.filter(evs, fn ev ->
            ev.class == :llm and ev.payload[:agent_id] == ct.payload.agent_id and
              ev.payload[:class] == :deliberate and
              ev.seq > ct.seq and (next_ct == nil or ev.seq < next_ct.seq)
          end)

        if Salience.escalate?(agent, ct.tick) do
          assert row.payload[:decision] in [:proposed, :hesitated, :rejected]
        else
          assert row.payload[:decision] == :skipped,
                 "#{ct.payload.agent_id} tick #{ct.tick} expected skipped"
          assert llm_between == [],
                 "#{ct.payload.agent_id} tick #{ct.tick} skipped but spent #{length(llm_between)} llm rows: #{inspect(Enum.map(llm_between, &{&1.seq, &1.payload[:class]}))}"
        end
      end
    end
  end

  defp alive?(agent) do
    hp = (agent.body && agent.body.hp) || 0
    hp > 0 and :dead not in ((agent.body && agent.body.conditions) || [])
  end

  test "an empty deliberate queue is a ledgered hesitation; the run survives" do
    run = new_run(%{deliberate: []}) |> enter_chiefs_room()

    {run, _} =
      advance_until(run, fn r -> rows(r, "grisk_the_snatcher") != [] end, 15)

    first = hd(rows(run, "grisk_the_snatcher"))
    assert first.payload[:decision] == :hesitated
    assert first.payload[:reason] =~ "deliberation unavailable"

    assert {:ok, _, _} = Run.declare(run, "pc_thistle", "I wait, listening.")
  end

  test "deception: a rejected adoption informs the creditor with a false envelope" do
    # quiet defaults for the whole tier-3 roster; only the adopt outcome differs
    run = new_run(%{adopt: [
      %{agent_id: "goblin_bodyguard_1",
        content: ~s({"adopted":false,"deceive":true,"inform":"Done, boss.","reason":"cowardice"})}
    ]})

    {run0, _} = enter_chiefs_room(run) |> advance_until(&order_sent?/1, 15)

    {run1, _} =
      advance_until(run0, fn r -> events_of(r, :envelope_rejected) != [] end, 4)

    inform =
      events_of(run1, :envelope_sent)
      |> Enum.find(&(&1.payload.envelope.type == :inform))

    assert inform != nil
    assert inform.payload.envelope.truth == false
    assert inform.payload.envelope.to == "grisk_the_snatcher"
    assert inform.payload.envelope.payload_nl == "Done, boss."

    inform_id = inform.payload.envelope.id

    {run, _} =
      advance_until(run1, fn r ->
        events_of(r, :envelope_delivered)
        |> Enum.any?(&(&1.payload[:id] == inform_id))
      end, 3)

    grisk = World.agent(run.world, "grisk_the_snatcher")

    assert grisk.beliefs["chiefs_room"]
           |> Map.keys()
           |> Enum.any?(&String.starts_with?(&1, "inform:"))

    llm_rows = Enum.filter(Run.events(run), &(&1.class == :llm))
    refute Enum.any?(llm_rows, &is_map_key(&1.payload, :truth))
  end
end
