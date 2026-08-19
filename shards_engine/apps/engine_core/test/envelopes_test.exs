defmodule EngineCore.EnvelopesTest do
  @moduledoc "Envelope send/deliver: sound voices signal + typed envelope, receipt-keyed delivery."
  use ExUnit.Case, async: true
  alias EngineCore.{Envelopes, Loader, Types, World}

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "send emits signal then envelope; ids deterministic per tick" do
    {:ok, w} = Loader.load(@yaml)

    assert {:ok, [sig_ev, env_ev], w2} =
             Envelopes.send(w, "grisk_the_snatcher", "goblin_bodyguard_1", :order, "Kill them!")

    assert sig_ev.payload.kind == :signal_emitted
    assert sig_ev.payload.signal_kind == :sound
    assert sig_ev.payload.content_core == %{class: :voices, about: "grisk_the_snatcher", count: 1}
    assert sig_ev.payload.intensity == 6.0
    assert sig_ev.payload.content_nl == "Kill them!"

    env = env_ev.payload.envelope
    assert env_ev.payload == %{kind: :envelope_sent, envelope: env}
    assert env_ev.class == :envelope
    assert %Types.Envelope{
             id: "env-0-1",
             from: "grisk_the_snatcher",
             to: "goblin_bodyguard_1",
             type: :order,
             payload_nl: "Kill them!",
             sent_tick: 0,
             delivery_place: "chiefs_room",
             signal_ref: ref,
             truth: :unverified,
             adopted: nil,
             status: :pending
           } = env
    assert ref == sig_ev.payload.ref

    assert {:ok, [_sig2, env_ev2], _w3} =
             Envelopes.send(w2, "grisk_the_snatcher", "goblin_bodyguard_2", :order, "You too.")

    assert env_ev2.payload.envelope.id == "env-0-2"
  end

  test "deliver_due marks delivered and plants the order belief" do
    {:ok, w} = Loader.load(@yaml)
    {:ok, [_sig_ev, _env_ev], w1} = Envelopes.send(w, "grisk_the_snatcher", "goblin_bodyguard_1", :order, "Kill them!")
    env = hd(w1.envelopes)

    receipt = %{kind: :signal_received, agent_id: "goblin_bodyguard_1", ref: env.signal_ref, place_id: "chiefs_room"}

    assert {:ok, [delivered_ev], w2} = Envelopes.deliver_due(w1, [receipt])
    assert delivered_ev.payload == %{kind: :envelope_delivered, id: env.id, place_id: "chiefs_room"}
    assert delivered_ev.class == :envelope

    assert hd(w2.envelopes).status == :delivered
    belief = World.agent(w2, "goblin_bodyguard_1").beliefs["chiefs_room"]["order:#{env.id}"]
    assert %{count: 1, last_tick: _, last_fidelity: 3, salience: 6.0, seen: false} = belief
  end

  test "no matching receipt leaves the envelope pending" do
    {:ok, w} = Loader.load(@yaml)
    {:ok, [_s, _e], w1} = Envelopes.send(w, "grisk_the_snatcher", "goblin_bodyguard_1", :order, "Kill them!")
    env = hd(w1.envelopes)

    wrong_agent = [%{kind: :signal_received, agent_id: "grisk_the_snatcher", ref: env.signal_ref, place_id: "chiefs_room"}]
    wrong_ref = [%{kind: :signal_received, agent_id: "goblin_bodyguard_1", ref: env.signal_ref + 99, place_id: "chiefs_room"}]

    for receipts <- [[], wrong_agent, wrong_ref] do
      assert {:ok, [], w} = Envelopes.deliver_due(w1, receipts)
      assert hd(w.envelopes).status == :pending
    end
  end
end
