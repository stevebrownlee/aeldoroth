defmodule Referee.Run do
  @moduledoc """
  One headless play session: propose → validate → resolve → react → narrate
  (spec §7). Pure data — no processes, no wall-clock. Save/resume is ledger
  replay elsewhere; `events/1` is the run's record.

  The Run threads the deterministic engine (world + seeded RNG), the resolved
  preference stack, and the gateway `Ctx` (budget/breaker/routing) through
  every stage. Rejections are diegetic and counted per {tick, actor}; the
  third rejection in one tick stalls the moment (plan Task 9).
  """

  alias Agents
  alias Agents.{Adopt, Salience}
  alias EngineCore.{Commitments, Dice, Envelopes, Fold, Ledger, Loader, Scheduler, World}
  alias LLMGateway.{Audit, Ctx}
  alias Referee.{Interpret, Narrate, PC, Preferences, Resolve, Slice, Spend, Validate}

  defstruct [:world, :prefs, :ctx, :rng, :pcs, events: [], seq: 0, rejections: %{}]

  @type t :: %__MODULE__{}

  @stall_limit 3

  @doc """
  Load an adventure YAML, resolve the preference stack (core < module < personal),
  and inject the PCs as tier-3 agents at their declared places. `opts`:
  `:routing` (gateway routing map), `:personal_prefs` (path to referee YAML).
  """
  @spec new(Path.t(), integer(), [map()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(yaml_path, seed, pcs, opts \\ []) do
    with {:ok, world} <- Loader.load(yaml_path),
         {:ok, raw} <- YamlElixir.read_from_file(yaml_path) do
      module_layer = Map.get(raw, "preferences") || %{}
      {prefs, _warnings} = Preferences.resolve(module_layer, Preferences.load(opts[:personal_prefs]))

      run = %__MODULE__{
        world: world,
        prefs: prefs,
        ctx: Ctx.from_config(opts[:routing]),
        rng: :rand.seed_s(:exsss, seed),
        pcs: pcs,
        events: [],
        seq: 0,
        rejections: %{}
      }

      run
      |> push(:meta, 0, %{kind: :prefs_stack, resolved: prefs, hash: Preferences.hash(prefs)})
      |> inject_pcs(pcs)
      |> then(&{:ok, &1})
    end
  end

  defp inject_pcs(run, pcs) do
    Enum.reduce(pcs, run, fn pc_map, acc ->
      pc = PC.build(pc_map)
      acc = push(acc, :world, acc.world.tick, %{kind: :agent_added, agent: pc})
      [event | _] = acc.events
      %{acc | world: Fold.fold(acc.world, [event])}
    end)
  end

  @doc """
  One PC's declared NL intent through the full pipeline.
  `{:ok, narration, run}` | `{:stall, message, run}`.
  """
  @spec declare(t(), String.t(), String.t()) ::
          {:ok, String.t(), t()} | {:stall, String.t(), t()}
  def declare(run, pc_id, utterance) do
    case Interpret.nl_to_action(run.ctx, run.world, pc_id, utterance) do
      {:clarify, question, ctx2, _audit} ->
        {:ok, question, %{run | ctx: ctx2}}

      {:ok, action, assumptions, ctx2, audit} ->
        run
        |> Map.put(:ctx, ctx2)
        |> append_audit(audit)
        |> continue(pc_id, action, assumptions)
    end
  end

  defp continue(run, pc_id, action, assumptions) do
    case Validate.check(run.world, action) do
      :ok -> resolved(run, pc_id, action, assumptions)
      {:reject, reason} -> rejected(run, pc_id, reason)
    end
  end

  @doc """
  Advance the world one tick: scheduler arrivals, commitments, cadence,
  sleep — then envelope delivery, order adoption, tier-3 deliberation, and
  narration of what each PC newly perceived.
  """
  @spec advance(t()) :: {:ok, %{String.t() => String.t()}, t()}
  def advance(run) do
    seq0 = run.seq

    {:ok, events, w2, r2} = Scheduler.advance(run.world, run.rng)
    {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, events)
    all = events ++ reaction

    run =
      run
      |> Map.put(:world, w3)
      |> Map.put(:rng, r3)
      |> append_world(all)

    {run, delivered} = deliver_phase(run)
    {run, _} = adoption_phase(run, delivered)
    run = deliberation_phase(run, all)

    narrate_new_receipts(run, seq0)
  end

  # Envelopes deliver when their target holds a receipt for the voicing
  # signal: agent id + signal ref must match (spec 8). Idempotent — a
  # pending-check gates re-delivery.
  defp deliver_phase(run) do
    receipts =
      events(run)
      |> Enum.map(& &1.payload)
      |> Enum.filter(&(&1[:kind] == :signal_received))

    pre = run.world.envelopes

    {:ok, delivered_events, w2} = Envelopes.deliver_due(run.world, receipts)
    run = %{run | world: w2} |> append_world(delivered_events)

    delivered_ids = MapSet.new(delivered_events, & &1.payload[:id])

    delivered =
      pre
      |> Enum.filter(&(&1.type == :order and &1.id in delivered_ids))
      |> Enum.sort_by(& &1.id)

    {run, delivered}
  end

  # A delivered order becomes the subordinate's own commitment only through
  # the subordinate's decision: one d20 (rolled here, in Run) against a
  # reliability target from morale, INT, and engine feasibility. The dice row
  # lands after the brain replies, recording decision and roll atomically.
  defp adoption_phase(run, delivered) do
    Enum.reduce(delivered, {run, []}, fn env, {acc, _} ->
      {roll, rng2} = Dice.roll(acc.rng, 20)
      acc = %{acc | rng: rng2}

      feasible = Adopt.feasible?(acc.world, env)
      slice = Slice.for_actor(acc.world, env.to)
      debtor = World.agent(acc.world, env.to)

      case Agents.adopt(env.to, %{
             envelope: Map.from_struct(env),
             slice: slice,
             ctx: acc.ctx,
             roll: roll,
             debtor: debtor,
             feasible: feasible
           }) do
        {:ok, d} ->
          acc =
            acc
            |> Map.put(:ctx, d.ctx)
            |> append_audit(d.audit)
            |> push(:dice, acc.world.tick, %{
              purpose: :adoption,
              sides: 20,
              roll: roll,
              target: Adopt.reliability(debtor, feasible),
              adopted: d.adopted
            })

          {:ok, acc} =
            if d.adopted do
              acc = adopt_commitment(acc, env, d)
              {:ok, acc}
            else
              {:ok, reject_or_deceive(acc, env, d)}
            end

          {acc, []}

        {:error, _brain_unavailable} ->
          {acc, []}
      end
    end)
  end

  defp adopt_commitment(run, env, d) do
    adopted = [%Ledger.Event{seq: 0, tick: run.world.tick, class: :envelope,
      payload: %{kind: :envelope_adopted, id: env.id}}]

    run =
      run
      |> Map.put(:world, Fold.fold(run.world, adopted))
      |> append_world(adopted)


    {:ok, created, w2} =
      Commitments.create(run.world, %{
        id: "adopted:#{env.id}",
        debtor: env.to,
        creditor: env.from,
        deed: d.deed,
        due: nil,
        every: nil,
        priority: 7
      })

    %{run | world: w2} |> append_world(created)
  end

  defp reject_or_deceive(run, env, d) do
    rejected = [%Ledger.Event{seq: 0, tick: run.world.tick, class: :envelope,
      payload: %{kind: :envelope_rejected, id: env.id}}]

    run =
      run
      |> Map.put(:world, Fold.fold(run.world, rejected))
      |> append_world(rejected)

    if d.deceive and is_binary(d.inform) and d.inform != "" do
      {:ok, inform_events, w2} =
        Envelopes.send(run.world, env.to, env.from, :inform, d.inform, truth: false)

      %{run | world: w2} |> append_world(inform_events)
    else
      run
    end
  end

  # Tier-3 cadence ticks: the salience gate buys LLM deliberation only under
  # pressure; closed gates skip with a row and zero spend. Every path leaves
  # a decision row — the ledger records what each brain chose or could not.
  defp deliberation_phase(run, scheduler_events) do
    ticks = Enum.filter(scheduler_events, &(&1.payload[:kind] == :cadence_tick))

    Enum.reduce(ticks, run, fn ev, acc ->
      agent = World.agent(acc.world, ev.payload.agent_id)

      if agent == nil or agent.tier != 3 or dead?(agent) do
        acc
      else
        unless Salience.escalate?(agent, acc.world.tick) do
          push(acc, :deliberation, acc.world.tick, %{
            agent_id: ev.payload.agent_id,
            decision: :skipped,
            verb: nil,
            reason: "salience below threshold"
          })
        else
          deliberate_one(acc, agent)
        end
      end
    end)
  end

  defp deliberate_one(run, agent) do
    slice = Slice.for_actor(run.world, agent.id)

    case Agents.deliberate(agent.id, %{slice: slice, ctx: run.ctx}) do
      {:ok, d} ->
        run =
          run
          |> Map.put(:ctx, d.ctx)
          |> append_audit(d.audit)

        case Validate.check(run.world, d.action) do
          {:reject, reason} ->
            push(run, :deliberation, run.world.tick, %{
              agent_id: agent.id,
              decision: :rejected,
              verb: d.action.verb,
              reason: reason
            })

          :ok ->
            run
            |> push(:deliberation, run.world.tick, %{
              agent_id: agent.id,
              decision: :proposed,
              verb: d.action.verb,
              reason: d.reason
            })
            |> resolve_action(d.action)
        end

      {:hesitate, h} ->
        run
        |> Map.put(:ctx, h.ctx)
        |> append_audit(h.audit)
        |> push(:deliberation, run.world.tick, %{
          agent_id: agent.id,
          decision: :hesitated,
          verb: nil,
          reason: h.reason
        })

      {:error, _brain_unavailable} ->
        push(run, :deliberation, run.world.tick, %{
          agent_id: agent.id,
          decision: :hesitated,
          verb: nil,
          reason: "brain unavailable"
        })
    end
  end

  # One validated action through the engine rules, world + rng carried
  # forward. Called only after the decision row is ledgered, so effects
  # always follow their decision in seq order.
  defp resolve_action(run, action) do
    case Resolve.act(run.world, run.rng, action) do
      {verdict, world_events, w2, r2} when verdict in [:ok, :diegetic_fail] ->
        {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, world_events)

        run
        |> Map.put(:world, w3)
        |> Map.put(:rng, r3)
        |> append_world(world_events ++ reaction)
    end
  end

  defp narrate_new_receipts(run, seq0) do
    received =
      events(run)
      |> Enum.filter(&(&1.seq > seq0 and &1.payload[:kind] == :signal_received))

    {narrations, run} =
      Enum.reduce(run.pcs, {%{}, run}, fn pc_map, {texts, acc} ->
        mine = Enum.filter(received, &(&1.payload[:agent_id] == pc_map.id))

        if mine == [] do
          {texts, acc}
        else
          {text, ctx2, _audit} =
            Narrate.received(acc.ctx, acc.prefs, pc_map.id, Enum.map(mine, & &1.payload))

          {Map.put(texts, pc_map.id, text), %{acc | ctx: ctx2}}
        end
      end)

    {:ok, narrations, run}
  end

  defp dead?(agent) do
    hp = (agent.body && agent.body.hp) || 0
    hp <= 0 or :dead in ((agent.body && agent.body.conditions) || [])
  end

  @doc "Ledger events of this run, in seq order."
  @spec events(t()) :: [Ledger.Event.t()]
  def events(run), do: Enum.reverse(run.events)

  @doc "LLM spend report from this run's ledger."
  @spec spend_report(t()) :: map()
  def spend_report(run), do: Spend.report(events(run))

  ## Internals

  defp resolved(run, pc_id, action, assumptions) do
    case Resolve.act(run.world, run.rng, action) do
      {verdict, world_events, w2, r2} when verdict in [:ok, :diegetic_fail] ->
        {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, world_events)

        {text, ctx2, naudit} =
          Narrate.action(run.ctx, run.prefs, pc_id, action, {verdict, world_events},
            assumptions: assumptions
          )

        run =
          run
          |> Map.put(:world, w3)
          |> Map.put(:rng, r3)
          |> Map.put(:ctx, ctx2)
          |> append_world(world_events ++ reaction)
          |> append_audit(naudit)

        {:ok, text, run}
    end
  end

  defp rejected(run, pc_id, reason) do
    key = {run.world.tick, pc_id}
    count = Map.get(run.rejections, key, 0) + 1
    run = %{run | rejections: Map.put(run.rejections, key, count)}

    if count >= @stall_limit do
      {:stall, "The moment passes — you cannot gather yourself to act again.", run}
    else
      {:ok, reason, run}
    end
  end

  ## Ledger helpers (events stored reversed; seq strictly monotonic)

  defp push(run, class, tick, payload) do
    event = struct!(Ledger.Event, seq: run.seq + 1, tick: tick, class: class, payload: payload)
    %{run | events: [event | run.events], seq: run.seq + 1}
  end

  defp append_world(run, world_events) do
    Enum.reduce(world_events, run, fn ev, acc ->
      push(acc, ev.class, ev.tick, ev.payload)
    end)
  end

  defp append_audit(run, nil), do: run

  defp append_audit(run, audit), do: push(run, :llm, run.world.tick, Audit.to_ledger(audit))
end
