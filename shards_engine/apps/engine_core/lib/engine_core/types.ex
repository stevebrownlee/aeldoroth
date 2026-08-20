defmodule EngineCore.Types do
  @moduledoc "Pure data structs shared across the engine. No behavior."

  defmodule Place do
    @enforce_keys [:id, :name, :kind, :connections]
    defstruct [:id, :name, :kind, :connections]
  end

  defmodule Edge do
    @enforce_keys [:id, :from, :to]
    defstruct [
      :id,
      :from,
      :to,
      sealed: false,
      label: nil,
      permeability: %{sight: :open, sound: :open}
    ]
  end

  defmodule Agent do
    @enforce_keys [:id, :name, :tier, :place_id]
    defstruct [
      :id,
      :name,
      :tier,
      :place_id,
      statblock: %{
        ac: 10,
        hd: 1,
        hp_max: 1,
        thac0: 20,
        morale: 7,
        int: 10,
        damage: %{dice: 1, sides: 6, plus: 0}
      },
      body: %{hp: 1, conditions: []},
      capabilities: [:move, :strike, :wait],
      beliefs: %{},
      commitments: [],
      cadence: nil,
      dossier: %{},
      attention: :alert,
      group: nil,
      # PCs are player-owned tier-3 agents (UX spec §5: truth-barrier-safe
      # party membership for "believed hostiles"). Read via Map.get — old
      # binary snapshots predate the field.
      pc: false
    ]
  end

  defmodule Item do
    @enforce_keys [:id, :name, :value_gp]
    defstruct [:id, :name, :value_gp, place_id: nil, holder_id: nil, is_hidden: false]
  end

  defmodule Action do
    @enforce_keys [:actor_id, :verb]
    defstruct [:actor_id, :verb, target_id: nil, params: %{}]
  end

  defmodule Signal do
    @moduledoc "One emission into a place. content_core: %{class, threat, about, count}."
    @enforce_keys [:emitted_by, :place_id, :tick, :kind, :content_core, :intensity]
    defstruct [:emitted_by, :place_id, :tick, :kind, :content_core, :intensity, content_nl: nil]
  end

  defmodule Arrival do
    @moduledoc "A signal instance pending reception at a place/tick, post-attenuation."
    @enforce_keys [:ref, :place_id, :tick, :kind, :intensity, :about, :hops, :origin_place_id]
    defstruct [
      :ref,
      :place_id,
      :tick,
      :kind,
      :intensity,
      :about,
      :hops,
      :origin_place_id,
      :content_core,
      :content_nl
    ]
  end

  defmodule Boundary do
    @moduledoc "Activation boundary: place-scoped or group-scoped (decision 25)."
    @enforce_keys [:id, :bound_agent_ids, :triggers]
    defstruct [
      :id,
      :scope_place_id,
      :scope_group,
      :bound_agent_ids,
      :triggers,
      state: :dormant,
      last_trigger_tick: nil,
      wake_on_intensity: 4,
      sleep_after: 40
    ]
  end

  defmodule Commitment do
    @moduledoc "Structured obligation (spec 5.4). Status: pending/due/kept/violated."
    @enforce_keys [:id, :debtor, :deed]
    defstruct [
      :id,
      :debtor,
      :creditor,
      :deed,
      due: nil,
      every: nil,
      priority: 5,
      status: :pending
    ]
  end

  defmodule Envelope do
    @moduledoc """
    A typed agent-to-agent message (e.g. an order). Delivery is keyed to the
    sound signal it travelled with: `signal_ref` must be received by `to`
    at `delivery_place` before the envelope's contents become a belief.
    """
    @enforce_keys [:id, :from, :to, :type, :payload_nl, :sent_tick, :delivery_place, :signal_ref]
    defstruct [
      :id,
      :from,
      :to,
      :type,
      :payload_nl,
      :sent_tick,
      :delivery_place,
      :signal_ref,
      truth: :unverified,
      adopted: nil,
      status: :pending
    ]
  end

  defmodule Hazard do
    @moduledoc "Tier-0 pattern: alarm hazards broadcast, damage hazards bite (decision 21)."
    @enforce_keys [:id, :kind, :place_id]
    defstruct [
      :id,
      :kind,
      :place_id,
      edge_id: nil,
      dc: 12,
      triggered: false,
      damage: %{dice: 1, sides: 4, plus: 0},
      signal_intensity: 9,
      signal_class: :alarm
    ]
  end
end
