defmodule EngineCore.Envelopes do
  @moduledoc """
  Typed envelopes: an NL payload voiced as a sound signal at the sender's
  place, plus a durable envelope keyed to that signal's ref (spec 8).

  Delivery is receipt-keyed: an envelope is delivered only when its target
  agent has a :signal_received receipt for the envelope's signal_ref.
  """

  alias EngineCore.{Fold, Ledger, Signals, Types, World}

  @doc """
  Sends `payload_nl` from agent `from` to agent `to` as an envelope of
  `type` (e.g. :order). Emits the voicing signal event and the envelope
  event; returns both plus the folded world. `truth` is engine-known only
  and defaults to :unverified — it never reaches the receiving brain.
  """
  @spec send(World.t(), String.t(), String.t(), atom, String.t(), keyword) ::
          {:ok, [Ledger.Event.t()], World.t()}
  def send(world, from, to, type, payload_nl, opts \\ []) do
    place = World.agent(world, from).place_id

    {:ok, sig_events, w1} =
      Signals.emit_at(world, from, place, :sound, %{class: :voices, about: from, count: 1}, 6.0, payload_nl)

    sig_ev = Enum.find(sig_events, &(&1.payload.kind == :signal_emitted))
    ref = sig_ev.payload.ref

    n = Enum.count(w1.envelopes, &(&1.sent_tick == world.tick)) + 1

    env = %Types.Envelope{
      id: "env-#{world.tick}-#{n}",
      from: from,
      to: to,
      type: type,
      payload_nl: payload_nl,
      sent_tick: world.tick,
      delivery_place: place,
      signal_ref: ref,
      truth: Keyword.get(opts, :truth, :unverified)
    }

    env_ev = %Ledger.Event{
      seq: 0,
      tick: world.tick,
      class: :envelope,
      payload: %{kind: :envelope_sent, envelope: env}
    }

    {:ok, sig_events ++ [env_ev], Fold.fold(w1, [env_ev])}
  end

  @doc """
  Delivers pending envelopes whose target agent holds a matching
  :signal_received receipt (same agent id, same signal ref). Emits and
  folds each delivery immediately so later envelopes see prior state.
  """
  @spec deliver_due(World.t(), [map]) :: {:ok, [Ledger.Event.t()], World.t()}
  def deliver_due(world, receipts) do
    {events, world} =
      Enum.reduce(world.envelopes, {[], world}, fn env, {acc, w} ->
        receipt =
          Enum.find(receipts, fn r ->
            r[:kind] == :signal_received and r[:agent_id] == env.to and r[:ref] == env.signal_ref
          end)

        if env.status == :pending and receipt do
          ev = %Ledger.Event{
            seq: 0,
            tick: w.tick,
            class: :envelope,
            payload: %{kind: :envelope_delivered, id: env.id, place_id: receipt[:place_id]}
          }

          {[ev | acc], Fold.fold(w, [ev])}
        else
          {acc, w}
        end
      end)

    {:ok, Enum.reverse(events), world}
  end
end
