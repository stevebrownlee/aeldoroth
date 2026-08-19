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

  alias EngineCore.{Fold, Ledger, Loader, Scheduler}
  alias LLMGateway.{Audit, Ctx}
  alias Referee.{Interpret, Narrate, PC, Preferences, Resolve, Spend, Validate}

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
  Run one tick of autonomous world time; narrate what each PC newly perceived.
  """
  @spec advance(t()) :: {:ok, %{String.t() => String.t()}, t()}
  def advance(run) do
    {:ok, events, w2, r2} = Scheduler.advance(run.world, run.rng)
    {:ok, reaction, w3, r3} = Scheduler.react(w2, r2, events)

    all = events ++ reaction

    run =
      run
      |> Map.put(:world, w3)
      |> Map.put(:rng, r3)
      |> append_world(all)

    received = Enum.filter(all, &(&1.payload[:kind] == :signal_received))

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
