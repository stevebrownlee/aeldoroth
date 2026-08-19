defmodule Referee.BrainsGoldenTest do
  @moduledoc """
  Golden replay determinism including brains/envelopes (plan Task 9):
  identical tower YAML + seed + PC spec + scripted LLM queues (identical
  content, distinct process-dict salts) ⇒ byte-identical ledgers across
  deliberation, envelopes, adoption dice, and llm rows. A different seed
  diverges (RNG-branch evidence).
  """

  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}
  ]

  @interpret [
    ~s({"verb":"move","target_id":null,"params":{"direction":"east"},"assumptions":[]}),
    ~s({"verb":"move","target_id":null,"params":{"direction":"south"},"assumptions":[]})
  ]

  # Identical content in every run; only the salt differs (queue identity).
  @deliberate [
    %{agent_id: "goblin_bodyguard_1",
      content: ~s({"verb":"strike","target_id":"pc_thistle","reason":"obeying orders"})},
    %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"guarding the chief"})},
    %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"still guarding"})},
    %{agent_id: "grisk_the_snatcher",
      content: ~s({"verb":"order","target_id":"goblin_bodyguard_1","message":"Kill the intruder!","reason":"intruders in my hall"})},
    %{agent_id: "grisk_the_snatcher", content: ~s({"verb":"wait","reason":"my will is done"})},
    %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"still on watch"})},
    %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"on watch"})},
    %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"still on watch"})}
  ]

  @adopt [
    %{agent_id: "goblin_bodyguard_1",
      content: ~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"})}
  ]

  test "identical seed + scripts replay to a byte-identical ledger, brains included" do
    {:ok, a} = play(salt: 1, seed: 42)
    {:ok, b} = play(salt: 2, seed: 42)

    assert :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(b))
    assert a.world.tick == b.world.tick

    # Phase markers present in BOTH ledgers.
    for run <- [a, b] do
      evs = Run.events(run)

      assert Enum.any?(evs, fn ev ->
               ev.payload[:kind] == :envelope_sent and
                 ev.payload.envelope.to == "goblin_bodyguard_1"
             end)

      assert Enum.any?(evs, &(&1.payload[:kind] == :envelope_delivered))
      assert Enum.any?(evs, &(&1.payload[:kind] == :envelope_adopted))
      assert Enum.any?(evs, fn ev ->
               ev.payload[:kind] == :commitment_created and
                 String.starts_with?(ev.payload.commitment.id, "adopted:")
             end)

      assert Enum.any?(evs, fn ev ->
               ev.class == :deliberation and ev.payload[:decision] == :proposed
             end)
    end
  end

  test "a different seed diverges the ledger" do
    {:ok, a} = play(salt: 3, seed: 42)
    {:ok, c} = play(salt: 4, seed: 43)

    refute :erlang.term_to_binary(Run.events(a)) == :erlang.term_to_binary(Run.events(c))
  end

  defp play(salt: salt, seed: seed) do
    scripts = %{interpret: @interpret, narrate: [], deliberate: @deliberate, adopt: @adopt, salt: salt}
    cfg = %{adapter: Scripted, scripts: scripts}
    routing = %{interpret: cfg, narrate: cfg, deliberate: cfg, adopt: cfg}

    {:ok, run} = Run.new(@yaml, seed, @pcs, routing: routing)

    {:ok, _, run} = Run.declare(run, "pc_thistle", "go east")
    {:ok, _, run} = Run.declare(run, "pc_thistle", "go south")

    run =
      Enum.reduce(1..20, run, fn _i, acc ->
        {:ok, _texts, acc2} = Run.advance(acc)
        acc2
      end)

    {:ok, run}
  end
end
