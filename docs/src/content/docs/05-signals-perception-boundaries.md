---
title: "Signals, Perception, and Boundaries"
description: "How The Shattered Kingdoms gates compute through spatial activation boundaries, propagates signals across places with edge attenuation, and enforces the truth barrier so that prompts contain only locally visible information."
order: 5
category: "Agents & Referee"
tags: ["signals", "perception", "boundaries", "truth-barrier", "referee", "spatial"]
updatedAt: "2026-08-20"
---

# Signals, Perception, and Boundaries

A living world is not a single global chat room. Sound dies in thick walls; light does not turn corners; and a sleeping village should not deliberate while the players are a day's march away. This chapter explains the three systems that enforce locality:

1. **Spatial activation boundaries** — which regions of the world are "awake" enough to compute.
2. **Signal propagation economy** — how emissions travel, attenuate, and are received.
3. **Truth barrier** — how `Referee.Slice.for_actor/2` proves that a prompt contains only what the actor could locally know.

```
Emitter
   │ sound / light / scent / tremor
   │ intensity I₀
   ▼
Place A ──edge(open/muffled/blocked)──▶ Place B ──edge──▶ Place C
   │                                         │
   │ same-place reception                    │ delayed, attenuated arrival
   ▼                                         ▼
Agent α (awake)                       Boundary γ wakes; agents δ, ε sleep
```

## 1. Spatial activation boundaries

A **boundary** is a compute gate. It defines a set of agents and a triggering condition. While the boundary is dormant, its bound agents do not cadence-deliberate; when it wakes, they catch up on overdue commitments and resume normal perception.

### 1.1 Boundary data model

```elixir
defmodule EngineCore.Types.Boundary do
  defstruct [
    :id,
    :scope_place_id,       # exact place id
    :scope_group,           # or a group of agents
    :bound_agent_ids,
    :triggers,              # [:presence_crossing, :signal_arrived, :commitment_due]
    state: :dormant,
    last_trigger_tick: nil,
    wake_on_intensity: 4,
    sleep_after: 40
  ]
end
```

Boundaries are resolved in precedence order:

- `scope_place_id` — the boundary covers one concrete place (a room, a clearing, a street).
- `scope_group` — the boundary covers every agent in a named group, regardless of where they are.
- Default — the boundary covers only `bound_agent_ids`, and is active wherever they happen to be.

A single world may mix all three kinds. For example, a town square might have a place-scoped boundary, while the villain's personal guard might be tracked by a group-scoped boundary.

### 1.2 Triggers

`EngineCore.Boundaries.evaluate/2` inspects every ledger event and decides whether a boundary should wake, refresh, or stay dormant.

```elixir
 defp trigger_for(world, b, %Ledger.Event{
       payload: %{kind: :move, agent_id: mover, to: to, from: from}
     }) do
  if :presence_crossing in b.triggers and
     mover not in b.bound_agent_ids and
     (place_in_scope?(world, b, to) or place_in_scope?(world, b, from)) do
    "presence_crossing by #{mover}"
  end
end
```

Supported triggers:

| Trigger | Condition | Typical use |
|---------|-----------|-------------|
| `:presence_crossing` | A non-bound agent enters or leaves the scoped place | Town gates, guard posts |
| `:signal_arrived` | A signal arrives in scope with intensity ≥ `wake_on_intensity` | Alarm bells, battle sounds |
| `:commitment_due` | A bound agent's commitment becomes due | Patrols, scheduled duties |

When a trigger fires and the boundary is dormant, `wake/4` is called. If it is already awake, a `:boundary_refresh` event is emitted instead, which resets the sleep countdown.

### 1.3 Dormant skip and lazy catch-up

While dormant, a boundary's bound agents are essentially frozen: they do not cadence-deliberate and they do not accrue per-tick perception costs. However, the world clock keeps running, so commitments with due ticks may become overdue. This is intentional: we do not want to pay for a hundred sleeping rooms every tick, but we also do not want to silently forget that a guard was supposed to relieve his watch two hours ago.

`EngineCore.Boundaries.catchup/3` runs at wake time:

```elixir
def catchup(world, id, opts \\ []) do
  b = Map.fetch!(world.boundaries, id)
  tick = world.tick

  overdue =
    world.agents
    |> Map.values()
    |> Enum.filter(&(&1.id in b.bound_agent_ids))
    |> Enum.flat_map(& &1.commitments)
    |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
    |> Enum.sort_by(& &1.id)

  {due_events, w2} =
    Enum.flat_map_reduce(overdue, world, fn c, w ->
      {:ok, evs, w2} = Commitments.mark_due(w, c.id, tick - c.due)
      {evs, w2}
    end)

  audit =
    if overdue != [] do
      earliest = overdue |> Enum.map(& &1.due) |> Enum.min()

      [%Ledger.Event{
        seq: 0,
        tick: tick,
        class: :meta,
        payload: %{
          kind: :boundary_catchup,
          id: id,
          computed_at: tick,
          from_tick: earliest,
          to_tick: tick,
          note: "computed at wake, tick #{tick}"
        }
      }]
    else
      []
    end

  {:ok, wake_events ++ due_events ++ audit, w3}
end
```

The catch-up emits three classes of facts:

1. The original `wake_event`.
2. One `:commitment_due` event per overdue commitment, carrying `late_by: current_tick - c.due`.
3. A single `:boundary_catchup` audit event summarizing the range of ticks that were compressed.

This is **lazy catch-up**: no work is done for dormant boundaries, but no work is lost either. The audit trail preserves the exact tick at which the commitment became due, even though the deliberation happened later.

### 1.4 Returning to sleep

A boundary returns to sleep when it has been quiet long enough and no bound agent has pressing business. `sleep_ready?/2` encodes the rule:

```elixir
def sleep_ready?(world, b) do
  b.state == :awake and
    b.last_trigger_tick != nil and
    world.tick - b.last_trigger_tick >= b.sleep_after and
    not pending_among?(world, b)
end
```

A boundary with pending or due commitments refuses to sleep. This ensures that once an alarm wakes a dungeon, the dungeon stays awake until the players leave or the situation is resolved.

## 2. Signal propagation economy

Signals are the currency of perception. Every action that makes noise, light, smell, or vibration emits one or more signals, and those signals propagate outward through place edges until they fall below the intensity floor.

### 2.1 Emission kinds

```elixir
defmodule EngineCore.Types.Signal do
  defstruct [
    :emitted_by,
    :place_id,
    :tick,
    :kind,              # :sound | :light | :scent | :tremor
    :content_core,     # %{class: atom, threat: boolean, about: term, count: integer}
    :intensity,
    content_nl: nil    # optional natural-language description
  ]
end
```

The `kind` determines which edges permit passage and how much the signal weakens per hop.

| Kind | Travels through | Typical source |
|------|-----------------|----------------|
| `:sound` | Most edges, muffled by walls | Combat, shouting, alarms, footsteps |
| `:light` | Open edges and sight lines | Torches, spells, explosions |
| `:scent` | Open edges, some weather edges | Blood, perfume, monsters, smoke |
| `:tremor` | Ground-connected edges | Collapse, large creature movement, siege |

### 2.2 Edge attenuation

Each `EngineCore.Types.Edge` carries a `permeability` map that classifies the edge for each signal kind:

```elixir
@attenuation %{
  open:     %{sight: 0.5, sound: 0.7, smell: 0.4, tremor: 0.8},
  muffled:  %{sight: 0.1, sound: 0.3, smell: 0.1, tremor: 0.4}
}

@intensity_floor 1.0
@hop_delay 1
```

An edge can be:

- `:open` — a doorway, window, or open arch.
- `:muffled` — a thick door, curtain, or dense foliage.
- `:blocked` — a solid wall or sealed barrier; signal attenuation is `nil` and propagation stops.

The propagation algorithm is a level-ordered BFS starting at the emitter's place. Each hop multiplies intensity by the attenuation factor and delays the arrival by `hop_delay` ticks. The first arrival at each place wins; later arrivals at the same place are discarded.

```
Place A (I₀ = 10.0 sound)
   │ open edge, sound attenuation 0.7
   ▼
Place B  I₁ = 7.0, arrives tick t+1
   │ muffled edge, sound attenuation 0.3
   ▼
Place C  I₂ = 2.1, arrives tick t+2
   │ muffled edge
   ▼
Place D  I₃ = 0.63  < 1.0 floor → dropped
```

The BFS is deterministic: neighbors are sorted by place id, and `Enum.uniq_by/2` keeps the first path to each place. This means propagation is reproducible across runs with the same world state.

### 2.3 Arrival facts and in-flight signals

Propagation produces `EngineCore.Types.Arrival` records:

```elixir
defmodule EngineCore.Types.Arrival do
  defstruct [
    :ref,              # signal reference id
    :place_id,
    :tick,             # arrival tick
    :kind,
    :intensity,        # post-attenuation
    :about,            # what the signal is about
    :hops,             # distance from origin
    :origin_place_id,
    :content_core,
    :content_nl
  ]
end
```

Arrivals are stored in `world.in_flight`. The scheduler converts them into `:signal_arrived` ledger events when their `tick` matches the world tick. This delay models the travel time of sound and light across the map and gives the engine a natural window for "did anyone hear that before it mattered?" questions.

### 2.4 Per-agent reception filters

Not every agent who could receive a signal does receive it. `EngineCore.Perception.receive_arrival/3` applies per-receiver filters:

```elixir
def base_fidelity(arrival, agent) do
  tier =
    cond do
      arrival.intensity >= 9 -> 5
      arrival.intensity >= 7 -> 4
      arrival.intensity >= 5 -> 3
      arrival.intensity >= 3 -> 2
      true -> 1
    end

  tier
  |> Kernel.-(if arrival.hops >= 1, do: 1, else: 0)
  |> Kernel.-(if agent.attention == :dormant, do: 2, else: 0)
  |> Kernel.+(if agent.statblock.int >= 16, do: 1, else: 0)
  |> Kernel.-(if agent.statblock.int <= 6, do: -1, else: 0)
  |> max(0)
  |> then(fn f -> if arrival.intensity >= 9, do: max(f, 3), else: f end)
  |> min(5)
end
```

Base fidelity is a 0–5 scalar:

- **Intensity tier**: the louder or brighter the signal, the higher the base fidelity.
- **Distance penalty**: signals that have hopped lose one tier of fidelity.
- **Attention penalty**: dormant agents lose two tiers.
- **Intelligence modifiers**: INT ≥ 16 adds one tier; INT ≤ 6 subtracts one tier.
- **High-intensity floor**: any signal with intensity ≥ 9 is at least fidelity 3.

For weak signals (`base <= 0` or `base == 1` with intensity ≤ 3), a d6 is rolled. A result of 1–2 means the agent receives the signal anyway; otherwise it is omitted. This is the honest "maybe you heard a mouse, maybe you didn't" layer. Importantly, a fidelity of 0 produces **no event at all**, not an explicit "I heard nothing" event.

### 2.5 From arrival to belief

When an agent receives a signal, the fold updates its belief matrix:

```elixir
%{
  place_id => %{
    about => %{
      seen: true,
      last_tick: tick,
      last_fidelity: fidelity,
      salience: salience,
      snapshot: content_core
    }
  }
}
```

The `seen` flag marks the belief as salient enough to surface in the prompt slice. The `salience` value is computed by `EngineCore.Perception.salience/3` (see Chapter 4). A high-fidelity, high-intensity, same-place, threatening signal produces the highest salience and is the most likely to wake a Tier-3 agent.

## 3. Truth barrier: `Referee.Slice.for_actor/2`

The truth barrier is the guarantee that an LLM prompt sees only what the actor could plausibly perceive. It is enforced by `Referee.Slice.for_actor/2`, which builds a prompt-local view from the world.

### 3.1 What the slice contains

```elixir
def for_actor(%World{} = world, agent_id) do
  agent = World.agent(world, agent_id)
  place = World.place(world, agent.place_id)

  believed =
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Map.keys()
    |> Enum.sort()

  salient =
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Enum.filter(fn {_about, b} -> b[:seen] end)
    |> Enum.sort_by(fn {about, b} -> {-b[:salience], about} end)
    |> Enum.map(&elem(&1, 0))

  %{
    agent: %{id: agent.id, name: agent.name, place_id: agent.place_id},
    place: %{
      id: place.id,
      name: place.name,
      kind: place.kind,
      exits: exits(world, agent.place_id),
      visible_items: visible_items(world, agent.place_id)
    },
    believed: believed,
    salient: salient,
    commitments: commitments(agent),
    capabilities: agent.capabilities,
    summary: summarize(place, believed, world)
  }
end
```

The slice exposes only:

- The actor's identity and current place.
- The current place's name, kind, exits, and visible (non-hidden) items.
- Agent and item ids that the actor believes are at the current place.
- Salient beliefs, sorted by descending salience.
- The actor's own commitments.
- The actor's capability list.
- A one-line natural-language summary.

It does **not** expose:

- Agents or items in other places.
- Hidden items, even in the same place.
- True HP, conditions, or statblocks of other entities.
- Events the actor did not personally receive.
- The full world graph beyond the names of exits.

### 3.2 Zero hidden information leakage

The slice is constructed from the agent's own `beliefs` map, not from `world.agents`. This is the critical invariant. Consider a hidden assassin in the same room:

```elixir
# Truth (in world.agents)
%{id: "assassin_01", place_id: "throne_room", is_hidden: true}

# Actor's beliefs about throne_room
%{"throne_room" => %{}}
```

Because the actor has no belief about `assassin_01`, `believed` will not contain it, and the prompt will not mention it. The hidden assassin can still act in the engine; the actor simply does not know it is there.

Similarly, `visible_items/2` filters by `not is_hidden`:

```elixir
 defp visible_items(world, place_id) do
  world.items
  |> Map.values()
  |> Enum.filter(&(&1.place_id == place_id and not Map.get(&1, :is_hidden, false)))
  |> Enum.map(& &1.id)
  |> Enum.sort()
end
```

### 3.3 Stable prompt reference

Every slice gets a stable content hash:

```elixir
def prompt_slice_ref(slice) do
  :erlang.md5(:erlang.term_to_binary(slice)) |> Base.encode16(case: :lower)
end
```

This hash is stored in the LLM audit row. If a player or developer later disputes an agent's behavior, the audit can replay the exact prompt context that produced it. The hash also collapses duplicate prompts: two agents with identical slices would hash to the same value, though they are still prompted separately.

### 3.4 PC dossiers extend the barrier

The same truth-barrier logic applies to PC dossiers in `Referee.Dossier.build/3`. A dossier is built from only two sources:

1. The PC's own belief store.
2. The PC's own `:narration` events.

No other player's knowledge, no referee-only truth, and no hidden scenario notes enter the summary. If the LLM summarizer fails, a template fallback lists the beliefs verbatim, which still cannot leak hidden information because the input was already filtered.

## 4. Interaction diagram

```
Action emitted (e.g., combat strike)
        │
        ▼
EngineCore.Signals.emit ──▶ propagate BFS
        │
        ▼
Arrival facts in world.in_flight
        │
        ▼
Scheduler fires :signal_arrived at arrival.tick
        │
        ├─▶ EngineCore.Boundaries.evaluate (may wake a boundary)
        │
        └─▶ EngineCore.Perception.receive_arrival
                │
                ▼
        Per-agent fidelity filter
                │
                ▼
        :signal_received events folded into agent beliefs
                │
                ▼
        Referee.Slice.for_actor/2 builds prompt-local view
                │
                ▼
        Agents.Brain.deliberate (LLM or heuristic)
```

## 5. Summary

- **Boundaries** gate compute by place or group. Dormant boundaries skip deliberation; wake triggers lazy catch-up of overdue commitments.
- **Signals** propagate as `:sound`, `:light`, `:scent`, and `:tremor`, attenuated by edge permeability (`:open`, `:muffled`, `:blocked`).
- **Perception** applies fidelity filters per agent, modified by intensity, distance, attention, and intelligence.
- **Beliefs** are formed only from successful receptions and stored in a place-keyed matrix.
- **Truth barrier** means prompts are built from the actor's beliefs, not from world truth. Hidden entities, off-place entities, and unreceived events never leak.
- All propagation, perception, and slicing is deterministic and auditable through ledger events.
