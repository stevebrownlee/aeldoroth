---
title: "Agent Cognition: BDI and the Four Tiers"
description: "How The Shattered Kingdoms models NPC agency through four cognitive tiers, from static hazards to autonomous BDI actors driven by beliefs, desires, intentions, and LLM deliberation."
order: 4
category: "Agents & Referee"
tags: ["agents", "bdi", "cognition", "salience", "commitments", "llm"]
updatedAt: "2026-08-20"
---

# Agent Cognition: BDI and the Four Tiers

Not every inhabitant of The Shattered Kingdoms needs a soul. Some need only a tripwire; others need a reason to betray you. The engine therefore partitions agency into **four cognition tiers**, each with a distinct execution model, cost profile, and audit contract. A single world may contain all four tiers simultaneously, and an agent's tier is immutable after creation.

| Tier | Kind | Decision authority | Typical examples | Compute cost |
|------|------|--------------------|------------------|--------------|
| 0 | Static item / prop | None (reactive trigger) | Traps, alarm bells, tripwires | Zero until triggered |
| 1 | Deterministic rule table | Hard-coded condition → action | Rats, zombies, mindless vermin | One rules pass |
| 2 | Scripted statechart / FSM | State machine transition | Wolf pack, guard patrol, swarm | One state transition |
| 3 | Autonomous BDI + LLM actor | Belief-driven deliberation | Lieutenants, named villains, PCs under autopilot | LLM call on pressure |

This chapter explains the tiers, the belief store that feeds Tier 3, the salience gate that prevents runaway LLM usage, and the commitment system through which Tier-3 actors adopt, schedule, and break obligations.

## 1. The four cognition tiers

The tier lives on the agent struct and is respected by `EngineCore.Scheduler` when it selects a decision strategy for each cadence tick.

```elixir
defmodule EngineCore.Types.Agent do
  defstruct [
    :id,
    :name,
    :tier,            # 0 | 1 | 2 | 3
    :place_id,
    statblock: %{...},
    body: %{hp: 1, conditions: []},
    capabilities: [:move, :strike, :wait],
    beliefs: %{},     # place_id => about => belief map
    commitments: [],
    cadence: nil,
    attention: :alert,
    group: nil
  ]
end
```

### 1.1 Tier 0: Static items and props

Tier-0 entities are not agents in the usual sense. They are `EngineCore.Types.Hazard` records keyed to a place or an edge, and they fire when the world state matches a trigger condition.

```elixir
defmodule EngineCore.Types.Hazard do
  defstruct [
    :id,
    :kind,              # :alarm | :damage
    :place_id,
    edge_id: nil,
    dc: 12,
    triggered: false,
    damage: %{dice: 1, sides: 4, plus: 0},
    signal_intensity: 9,
    signal_class: :alarm
  ]
end
```

`EngineCore.Cognition.Hazard.check_move/3` evaluates every movement event against hazards whose `place_id` or `edge_id` intersects the move. A damage hazard emits a `signal_emitted` event with `signal_class: :alarm`; an alarm hazard emits a signal without direct damage. Once triggered, `triggered: true` prevents re-firing. Tier 0 is pure, deterministic, and requires no dice of its own beyond the save rolled by the moving agent.

### 1.2 Tier 1: Deterministic rule tables

Tier-1 agents implement the classic "stimulus → response" pattern. `EngineCore.Cognition.Reflex.decide/3` inspects a small number of hard-coded variables and returns an action immediately.

```elixir
cond do
  hp <= hp_max * 0.25 ->
    flee(world, rng, agent)

  intruder = find_nearest_intruder(world, agent) ->
    Rules.Combat.attack(world, rng, agent.id, intruder.id)

  has_loud_belief?(world, agent) ->
    seek_source_of_noise(world, rng, agent)

  true ->
    {:ok, [], world, rng}
end
```

The rule table has no hidden state, no plan, and no memory beyond the agent's belief map. It is appropriate for creatures whose tactical depth can be exhausted in a `cond` block. Because the rule set is code, it is also easy to unit-test with hand-crafted worlds.

### 1.3 Tier 2: Scripted statecharts / finite state machines

Tier 2 lifts Tier 1's tables into explicit state. The canonical example is `EngineCore.Cognition.Pack`, which models wolf-pack coordination through a small number of states (patrol, hunt, flee, regroup). State transitions are driven by hit points, group proximity, and perceived intruders.

```elixir
cond do
  hp <= hp_max * 0.40 ->
    flee(world, rng, agent)

  intruder = find_nearest_intruder(world, agent) ->
    Rules.Combat.attack(world, rng, agent.id, intruder.id)

  true ->
    {:ok, [], world, rng}
end
```

Statecharts are deterministic and cheap, but they can still produce emergent behavior when many Tier-2 agents share the same state transition table and react to shared signals. A pack of wolves individually runs the same code; the pack appears coordinated because they all perceive the same blood scent and flee threshold.

### 1.4 Tier 3: Autonomous BDI + LLM actors

Tier 3 is where agency becomes expensive. Each Tier-3 agent owns an `Agents.Brain` GenServer that is **stateless and disposable**: the process holds only the agent id, while all authority lives in the world ledger.

```elixir
defmodule Agents.Brain do
  use GenServer, restart: :temporary

  def handle_call({:deliberate, %{slice: slice, ctx: ctx}}, _from, agent_id) do
    {system, user, schema} = Agents.Prompt.deliberate(slice)

    req = %LLMGateway.Request{
      class: :deliberate,
      agent_id: agent_id,
      system: system,
      user: user,
      schema: schema
    }

    # LLM proposes; engine disposes.
    case LLMGateway.Router.complete(ctx, req) do
      {:ok, %LLMGateway.Result{parsed: parsed}, audit, ctx2} ->
        ...

      {:error, _reason, audit, ctx2} ->
        {:hesitate, %{reason: "deliberation unavailable", ...}}
    end
  end
end
```

The brain receives a **slice** from `Referee.Slice.for_actor/2` rather than the whole world. The slice contains only what the agent believes and perceives; hidden truth never enters the prompt. The LLM returns a JSON object constrained by a schema, and the engine validates the proposed verb against the agent's capability set. If the LLM proposes an impossible verb, the agent hesitates and the event is audited.

## 2. Belief store representation

Beliefs are the "B" in BDI. They are not truth; they are a localized, per-agent, perceptual model of the world.

### 2.1 Perceived entity matrix

Each agent carries a nested map:

```elixir
%{
  place_id => %{
    about => %{
      seen: boolean,
      last_tick: integer,
      last_fidelity: 1..5,
      salience: float,
      snapshot: %{class: atom, threat: boolean, count: integer}
    }
  }
}
```

- `place_id` scopes the belief to a location. An agent may hold beliefs about many places, but only beliefs at `agent.place_id` are visible in the prompt slice.
- `about` is usually an agent id, item id, or signal class.
- `seen` marks whether the agent has direct sensory confirmation.
- `last_tick` is the world tick at which the belief was last refreshed.
- `last_fidelity` records signal clarity from `EngineCore.Perception`.
- `salience` is the computed threat/novelty score.
- `snapshot` holds the `content_core` of the original signal (class, threat flag, count).

The matrix is updated only by `signal_received` and `arrival` events folded into the world. No code writes to an agent's beliefs directly except through the ledger fold.

### 2.2 Threat salience calculation

`EngineCore.Perception.salience/3` converts a raw signal arrival into a scalar that the salience gate can compare against a threshold.

```elixir
def salience(arrival, agent, _world) do
  novel = get_in(agent.beliefs, [arrival.place_id, arrival.about]) == nil
  same  = agent.place_id == arrival.place_id
  threat = arrival.content_core[:threat] == true

  (arrival.intensity
    + if(same, do: 2, else: 1)
    + if(novel, do: 2, else: 0)
    + if(threat, do: 3, else: 0))
  |> min(10)
  |> Kernel.*(1.0)
  |> Float.round(1)
end
```

The formula rewards:

- **Intensity**: loud or bright signals naturally draw attention.
- **Co-location**: signals in the same place are twice as salient as distant rumors.
- **Novelty**: first impressions count; a previously unknown entity adds `2.0`.
- **Threat flag**: content tagged as threatening adds `3.0`.

Salience is capped at `10.0` and rounded to one decimal place.

### 2.3 Temporal decay

Beliefs are not forgotten, but they become less useful over time. The slice only surfaces beliefs whose `seen` flag is true, and the prompt itself is anchored at the current place. Older beliefs remain in the matrix for future reference (e.g., "I heard fighting in the courtyard three ticks ago"), but they do not by themselves wake the agent from cadence sleep.

Decay is currently implicit: a belief that is not refreshed will eventually fall out of the salient set because its `last_tick` lags the current tick and no new signal raises its salience. Future work may add explicit per-belief half-life decay, but the data model already supports it through `last_tick` and `last_fidelity`.

## 3. Salience escalation gate

Tier-3 agents do not deliberate on every cadence tick. They deliberate only under **pressure**. `Agents.Salience.escalate?/2` is the guard.

```elixir
defmodule Agents.Salience do
  @salience_threshold 7.0

  def escalate?(%Types.Agent{} = agent, _tick) do
    pressured?(agent) or salient?(agent)
  end

  defp pressured?(agent) do
    Enum.any?(agent.commitments, &(&1.status in [:pending, :due]))
  end

  defp salient?(agent) do
    agent.beliefs
    |> Map.get(agent.place_id, %{})
    |> Enum.any?(fn {_about, b} -> b[:salience] >= @salience_threshold end)
  end
end
```

Two conditions wake a Tier-3 brain:

1. **Commitment pressure**: any pending or due commitment means the agent has unfinished business.
2. **Salient novelty**: any belief at the agent's current place with salience ≥ `7.0`.

If neither is true, the cadence tick is skipped and logged as a no-op. This keeps LLM costs bounded: a sleeping guard in an empty room costs nothing; the same guard hearing a salient noise pays exactly one deliberation call.

> **Threshold contract**: The salience gate fires when any belief at the agent's current place reaches salience ≥ `5.0`. The runtime module `Agents.Salience` currently hard-codes `@salience_threshold 7.0`, which acts as a stricter safety margin. Content authors should design signals so that genuinely threatening or novel events cross `5.0`; operators may lower the runtime constant to `5.0` to match the documented contract. Signals in the `5.0`–`7.0` range are still recorded in the belief store and may influence later deliberation.

## 4. Commitments and autonomous order adoption

Tier-3 agents do not merely react; they hold **commitments** — the "intention" layer of BDI. A commitment is an obligation owed by a debtor to an optional creditor, with a due tick, a priority, and a lifecycle status.

```elixir
defmodule EngineCore.Types.Commitment do
  defstruct [
    :id,
    :debtor,
    :creditor,       # optional
    :deed,           # natural-language description
    due: nil,
    every: nil,      # recurring interval
    priority: 5,      # lower number = more urgent
    status: :pending # pending | due | kept | violated
  ]
end
```

`EngineCore.Commitments` provides the lifecycle:

| Function | Event emitted | Resulting status |
|----------|---------------|------------------|
| `create/2` | `:commitment_created` | `:pending` |
| `mark_due/3` | `:commitment_due` | `:due` |
| `keep/2` | `:commitment_kept` | `:kept` (or rearmed to `:pending`) |
| `violate/2` | `:commitment_violated` | `:violated` |
| `renegotiate/3` | `:commitment_renegotiated` | `:pending` with new due |

### 4.1 Creditor hierarchy

When an agent receives an order, the engine must decide whether the order becomes a binding commitment. The decision is influenced by the **creditor hierarchy** encoded in the agent's `dossier` and group membership. In general:

1. A command from a superior in the same chain of command is likely to be adopted.
2. A command from a peer may be adopted if the deed is feasible and aligns with existing commitments.
3. A command from an outsider or enemy is likely to be rejected or accepted deceptively.

The exact hierarchy is part of the scenario data and is supplied to the brain prompt through the `summary` field of the slice.

### 4.2 Co-location verification

An order cannot be adopted unless the creditor is plausibly able to give it. `Agents.Adopt.feasible?/2` checks co-location or recent perception:

```elixir
def feasible?(world, env) do
  debtor = World.agent(world, env.to)
  creditor = World.agent(world, env.from)

  alive?(debtor) and
    :fleeing not in (debtor.body.conditions || []) and
    creditor_near?(debtor, creditor)
end

 defp creditor_near?(debtor, creditor) do
  creditor.place_id == debtor.place_id or
    get_in(debtor.beliefs, [debtor.place_id, creditor.id]) != nil or
    get_in(debtor.beliefs, [creditor.place_id, creditor.id]) != nil
end
```

A debtor can adopt an order if the creditor is in the same place **or** if the debtor currently believes the creditor is nearby. This prevents an agent from obeying orders telepathically broadcast from across the map.

### 4.3 Reliability heuristic scoring

When the LLM is unavailable or the brain is operating in deterministic fallback mode, `Agents.Adopt` computes a reliability target from the debtor's statblock and the feasibility of the order:

```elixir
def reliability(debtor, feasible) do
  int = debtor.statblock.int

  debtor.statblock.morale +
    int_adjust(int) +
    if(feasible, do: 3, else: -4)
end

 defp int_adjust(int) when int >= 12, do: 2
 defp int_adjust(int) when int <= 7, do: -2
 defp int_adjust(_), do: 0

def decide(roll, target) do
  if(roll <= target, do: :adopt, else: :reject)
end
```

- **Morale** is the base willingness to follow orders.
- **Intelligence adjustment** rewards INT ≥ 12 with `+2` and penalizes INT ≤ 7 with `-2`.
- **Feasibility bonus** adds `+3` if the deed looks doable, or `-4` if it does not.

The coordinator rolls `1d20` against this target. A roll ≤ target means adoption; otherwise the agent rejects the order.

### 4.4 Deception detection

Tier-3 agents can lie about adoption. The LLM adoption prompt explicitly permits pretense:

```json
{
  "adopted": true,
  "deed": "I will guard the gate.",
  "deceive": true,
  "inform": "Yes, captain. The gate is secure.",
  "reason": "I will pretend to obey so I can warn the rebels."
}
```

When `deceive: true`, the engine emits a `signal_emitted` event containing `inform` as natural-language speech. The creditor (and anyone else who hears it) receives a belief that the order was accepted, while the debtor's actual commitment may differ or be absent. Detecting the lie is left to other agents through normal perception: does the debtor's subsequent behavior match the claimed deed? There is no omniscient "deception check"; truth is social.

### 4.5 Commitment scheduling

Commitments may have a `due` tick. The scheduler evaluates `EngineCore.Commitments.due/2` each tick to surface obligations that have matured:

```elixir
def due(world, tick) do
  world.agents
  |> Map.values()
  |> Enum.flat_map(& &1.commitments)
  |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
  |> Enum.sort_by(&{-&1.priority, &1.debtor, &1.id})
end
```

Overdue commitments are marked `:due` and create salient pressure, which wakes the agent for deliberation. Recurring commitments (`every: n`) are rearmed with a new due tick when kept. This is how patrol routes, guard shifts, and feeding schedules become durable intentions.

## 5. Audit and the truth barrier

Every Tier-3 decision is auditable. The prompt slice, the LLM request, the parsed response, the final action, and any fallback heuristic are written to the ledger. Because the brain is stateless, killing or restarting a brain process is equivalent to a momentary hesitation: the next tick simply starts a fresh GenServer with the same agent id and reconstructs the slice from the world.

The truth barrier is enforced upstream in `Referee.Slice.for_actor/2` (see Chapter 5), but the brain module reinforces it by construction: it never imports `EngineCore.World` and has no API to request hidden state.

## 6. Summary

- **Tier 0** hazards fire on triggers; **Tier 1** reflexes use `cond`; **Tier 2** packs use scripted statecharts; **Tier 3** actors use LLM deliberation over a belief store.
- The **belief matrix** is place-keyed and stores salience, fidelity, and snapshots.
- **Salience** combines intensity, co-location, novelty, and threat, capped at `10.0`.
- The **salience gate** wakes Tier-3 agents only under pressure (pending commitments) or salient novelty (≥ `7.0` at current place).
- **Commitments** formalize intentions with creditor, debtor, due tick, priority, and lifecycle status.
- **Order adoption** checks co-location, computes reliability from morale + INT + feasibility, and supports deception through the `deceive` flag.
- All Tier-3 output is validated, ledgered, and slice-bounded.
