defmodule Referee.Run.Session do
  @moduledoc """
  Live run owner (spec §11): one GenServer per run holding the pure
  `Referee.Run` and flushing every new ledger event to the per-run
  `EngineCore.Ledger.Writer`. The pure pipeline stays untouched — this
  process only sequences it and gates it behind pause/resume.

  Pause (plan 5 Task 5): builds one dossier per living PC via
  `Referee.Dossier` (`:summarize` class), ledgers each as a `:dossier`
  event, checkpoints, and refuses pipeline ops until `resume/1`.

  Persistence: `checkpoint/1` writes the run **and its seed world** (the
  Loader state the journal folds from) to `data_dir/<run_id>.snapshot`
  (tmp + rename, atomic); `restore/3` restarts the writer (journal replay),
  re-folds the world server from the seed, asserts the fold agrees with the
  checkpoint byte-for-byte (spec §12.3), and reattaches routing — adapter
  queues/ctx are per-session runtime state, not world truth, so restore
  takes fresh `routing:` for the continued session.
  """

  use GenServer
  alias EngineCore.{Loader, RunSup, World}
  alias EngineCore.Ledger.Writer
  alias LLMGateway.{Audit, Ctx}
  alias Referee.{Dossier, Run}

  defstruct [:run_id, :run, :seed, :status, :last_flushed, :data_dir, last_intents: %{}]

  @registry Referee.SessionReg

  ## Client API

  @doc """
  Start a new live session for `run_id`: loads the adventure, seeds the
  per-run engine processes (writer first, then world server), appends the
  run's initial events, checkpoints. `opts` go to `Run.new/4` plus
  `data_dir: nil | Path.t()` (nil = no checkpoint/journal).
  """
  @spec start_link(String.t(), Path.t(), integer(), [map()], keyword()) :: GenServer.on_start()
  # Supervision entry: the child tuple carries one init_arg; the run_id in it
  # is also the Registry name. The 5-arity form is the human-facing wrapper.
  def start_link({:new, run_id, _, _, _, _} = init_arg),
    do: GenServer.start_link(__MODULE__, init_arg, name: via(run_id))

  def start_link({:restore, run_id, _, _, _} = init_arg),
    do: GenServer.start_link(__MODULE__, init_arg, name: via(run_id))

  def start_link(run_id, yaml_path, seed, pcs, opts \\ []) do
    start_named(run_id, {:new, run_id, yaml_path, seed, pcs, opts})
  end

  @doc "One PC's declared intent. `{:ok, %{reply: text}}` | `{:error, :paused | :no_run}`."
  @spec declare(String.t(), String.t(), String.t()) ::
          {:ok, %{reply: String.t() | nil}} | {:error, :paused | :no_run}
  def declare(run_id, pc_id, text) do
    call(run_id, {:declare, pc_id, text})
  end

  @doc "Advance one tick. `{:ok, texts}` mirroring the pure path | `{:error, :paused | :no_run}`."
  @spec advance(String.t()) :: {:ok, map()} | {:error, :paused | :no_run}
  def advance(run_id), do: call(run_id, :advance)

  @doc """
  Pause: dossiers per living PC (`:dossier` events), checkpoint, gate the
  pipeline. `{:error, :already_paused}` on repeat.
  """
  @spec pause(String.t()) :: {:ok, %{dossiers: %{String.t() => String.t()}}} | {:error, term()}
  def pause(run_id), do: call(run_id, :pause)

  @doc "Resume a paused session."
  @spec resume(String.t()) :: :ok | {:error, :not_paused | :no_run}
  def resume(run_id), do: call(run_id, :resume)

  @doc "Out-of-character table talk: ledgers an `:ooc` event, touches no pipeline."
  @spec ooc(String.t(), String.t(), String.t()) :: :ok | {:error, :no_run}
  def ooc(run_id, pc_id, text), do: call(run_id, {:ooc, pc_id, text})

  @doc "GM table-wide announcement, ledgered as an `:ooc` event from the GM."
  @spec gm_chat(String.t(), String.t()) :: :ok | {:error, :no_run}
  def gm_chat(run_id, text), do: call(run_id, {:gm_chat, text})

  @doc "This run's PC ids (from the immutable seed spec)."
  @spec pcs(String.t()) :: {:ok, [String.t()]} | {:error, :no_run}
  def pcs(run_id), do: call(run_id, :pcs)

  @doc "Resolved preference stack for this run's ruleset."
  @spec prefs(String.t()) :: {:ok, map()} | {:error, :no_run}
  def prefs(run_id), do: call(run_id, :prefs)
  @doc "Dynamically add a PC to the running session."
  @spec add_pc(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def add_pc(run_id, pc_map) do
    call(run_id, {:add_pc, pc_map})
  end


  @doc "Stop the session process (engine per-run processes stay up; see `EngineCore.RunSup.stop_run/1`)."
  @spec stop(String.t()) :: :ok | {:error, :no_run}
  def stop(run_id) do
    case whereis(run_id) do
      nil ->
        {:error, :no_run}

      pid ->
        # Tolerate a concurrent exit (supervisor teardown races with this
        # call): any exit reason achieves the stop.
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc "Session status: `%{status, tick, seq, run_id}` or nil when absent."
  @spec state(String.t()) :: map() | nil
  def state(run_id) do
    case whereis(run_id) do
      nil -> nil
      pid -> GenServer.call(pid, :state)
    end
  end

  @doc """
  Seat list `[%{id, name}]` for the web picker (GM-console introspection,
  not on the wire). `nil` when the run doesn't exist.
  """
  @spec roster(String.t()) :: [%{id: String.t(), name: String.t()}] | nil
  def roster(run_id) do
    case whereis(run_id) do
      nil -> nil
      pid -> GenServer.call(pid, :roster)
    end
  end

  @doc """
  Who the table is waiting on (GM-console introspection, same family as
  `roster/1` — not on the seat wire): one row per PC with their current
  vitals, place name, most recent declared intent (ephemeral session
  state, not ledgered) and any outstanding clarify prompt — a clarify
  ledger event newer than that PC's latest narration.
  """
  @spec awaiting(String.t()) ::
          {:ok,
           [
             %{
               id: String.t(),
               name: String.t(),
               hp: integer() | nil,
               hp_max: integer() | nil,
               ac: integer() | nil,
               thac0: integer() | nil,
               place_id: String.t() | nil,
               place_name: String.t() | nil,
               last_intent: %{text: String.t(), tick: integer()} | nil,
               prompt: %{question: String.t(), tick: integer()} | nil
             }
           ]}
          | {:error, :no_run}
  def awaiting(run_id), do: call(run_id, :awaiting)

  @doc """
  Restart `run_id` from its checkpoint + journal (both under `data_dir`).
  The writer replays the journal first; a checkpoint that disagrees with
  the journal's last seq, or a seed-fold that disagrees with the
  checkpointed world, is refused. `opts`: `:routing` — fresh gateway
  routing for the continued session (real adapters are stateless; scripted
  queues are consumed per-session and cannot resume mid-list).
  """
  @spec restore(String.t(), Path.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def restore(run_id, data_dir, opts \\ []) do
    with {:ok, run, seed} <- read_snapshot(run_id, data_dir),
         {:ok, _world_server} <- RunSup.ensure_run(run_id, seed, data_dir: data_dir),
         :ok <- fold_check(run_id, run),
         :ok <- seq_check(run_id, run) do
      start_named(run_id, {:restore, run_id, run, Keyword.get(opts, :routing), data_dir})
    else
      {:error, reason} ->
        RunSup.stop_run(run_id)
        {:error, reason}
    end
  end

  ## GenServer callbacks

  @impl true
  def init({:new, run_id, yaml_path, seed, pcs, opts}) do
    data_dir = Keyword.get(opts, :data_dir)

    with {:ok, seed_world} <- Loader.load(yaml_path),
         {:ok, _ws} <- RunSup.ensure_run(run_id, seed_world, data_dir: data_dir),
         {:ok, run} <- Run.new(yaml_path, seed, pcs, opts) do
      st =
        %__MODULE__{
          run_id: run_id,
          run: run,
          seed: seed_world,
          status: :running,
          last_flushed: 0,
          data_dir: data_dir
        }
        |> flush()
        |> checkpoint()

      {:ok, st}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def init({:restore, run_id, %Run{} = run, routing, data_dir}) do
    run =
      if routing do
        %{run | ctx: %{run.ctx | routing: Ctx.from_config(routing).routing}}
      else
        run
      end

    st = %__MODULE__{
      run_id: run_id,
      run: run,
      seed: nil,
      status: :running,
      last_flushed: run.seq,
      data_dir: data_dir
    }

    {:ok, st}
  end

  @impl true
  def handle_call({:add_pc, pc_map}, _from, %{status: status} = st) when status in [:running, :paused] do
    {:ok, pc, run2} = Run.add_pc(st.run, pc_map)
    st2 = hold(st, run2) |> checkpoint()
    {:reply, {:ok, pc.id}, st2}
  end

  def handle_call({:declare, pc_id, text}, _from, %{status: :running} = st) do
    case Run.declare(st.run, pc_id, text) do
      {tag, reply, run2} when tag in [:ok, :stall] ->
        st = %{
          st
          | last_intents: Map.put(st.last_intents, pc_id, %{text: text, tick: st.run.world.tick})
        }

        {:reply, {:ok, %{reply: reply}}, hold(st, run2)}
    end
  end

  def handle_call({:declare, _pc_id, _text}, _from, %{status: :paused} = st),
    do: {:reply, {:error, :paused}, st}

  def handle_call(:advance, _from, %{status: :running} = st) do
    {:ok, texts, run2} = Run.advance(st.run)
    {:reply, {:ok, texts}, hold(st, run2)}
  end

  def handle_call(:advance, _from, %{status: :paused} = st), do: {:reply, {:error, :paused}, st}

  def handle_call(:pause, _from, %{status: :running} = st) do
    {dossiers, st2} =
      Enum.reduce(st.run.pcs, {%{}, st}, fn pc_map, {texts, acc} ->
        agent = World.agent(acc.run.world, pc_map.id)

        if alive?(agent) do
          {text, ctx2, audit} = Dossier.build(acc.run.ctx, agent, Run.events(acc.run))
          acc = %{acc | run: %{acc.run | ctx: ctx2}}
          acc = append_audit(acc, audit)

          acc =
            push(acc, :dossier, acc.run.world.tick, %{
              kind: :dossier,
              pc_id: pc_map.id,
              text: text
            })

          {Map.put(texts, pc_map.id, text), acc}
        else
          {texts, acc}
        end
      end)

    st3 = hold(st2, st2.run) |> checkpoint()
    # Meta event (W2): seats + spectate console learn the pause over the wire.
    st3 = push(st3, :meta, st3.run.world.tick, %{kind: :paused})
    st3 = hold(st3, st3.run)
    {:reply, {:ok, %{dossiers: dossiers}}, %{st3 | status: :paused}}
  end

  def handle_call(:pause, _from, %{status: :paused} = st),
    do: {:reply, {:error, :already_paused}, st}

  def handle_call(:resume, _from, %{status: :paused} = st) do
    st = push(st, :meta, st.run.world.tick, %{kind: :resumed})
    {:reply, :ok, hold(%{st | status: :running}, st.run)}
  end

  def handle_call(:resume, _from, %{status: :running} = st),
    do: {:reply, {:error, :not_paused}, st}

  def handle_call(:state, _from, st) do
    {:reply, %{run_id: st.run_id, status: st.status, tick: st.run.world.tick, seq: st.run.seq},
     st}
  end

  def handle_call(:roster, _from, st),
    do: {:reply, Enum.map(st.run.pcs, &%{id: &1.id, name: &1.name}), st}

  def handle_call(:awaiting, _from, st) do
    rows =
      Enum.map(st.run.pcs, fn pc ->
        agent = World.agent(st.run.world, pc.id)
        place_id = if agent, do: agent.place_id, else: nil
        place = if place_id, do: World.place(st.run.world, place_id), else: nil
        place_name = if place, do: place.name || place_id, else: nil
        body = if agent, do: Map.get(agent, :body, %{}) || %{}, else: %{}
        statblock = if agent, do: Map.get(agent, :statblock, %{}) || %{}, else: %{}

        %{
          id: pc.id,
          name: pc.name,
          hp: Map.get(body, :hp),
          hp_max: Map.get(statblock, :hp_max),
          ac: Map.get(statblock, :ac),
          thac0: Map.get(statblock, :thac0),
          place_id: place_id,
          place_name: place_name,
          last_intent: Map.get(st.last_intents, pc.id),
          prompt: outstanding_prompt(st.run, pc.id)
        }
      end)

    {:reply, {:ok, rows}, st}
  end

  # OOC works in every status: it is table talk, not a pipeline op.
  def handle_call({:ooc, pc_id, text}, _from, st),
    do: {:reply, :ok, hold(st, Run.ooc(st.run, pc_id, text))}

  def handle_call({:gm_chat, text}, _from, st),
    do: {:reply, :ok, hold(st, Run.ooc(st.run, "GM", text))}

  def handle_call(:pcs, _from, st),
    do: {:reply, {:ok, Enum.map(st.run.pcs, & &1.id)}, st}

  def handle_call(:prefs, _from, st),
    do: {:reply, {:ok, st.run.prefs}, st}

  ## Internals

  defp hold(st, run2) do
    %{st | run: run2} |> flush() |> checkpoint()
  end

  # Append everything past last_flushed; writer enforces seq continuity.
  defp flush(%__MODULE__{run: run, last_flushed: last} = st) do
    case Run.events(run) |> Enum.drop(last) do
      [] ->
        st

      new_events ->
        :ok = Writer.append(st.run_id, new_events)
        %{st | last_flushed: run.seq}
    end
  end

  defp checkpoint(%__MODULE__{data_dir: nil} = st), do: st

  defp checkpoint(%__MODULE__{} = st) do
    path = snapshot_path(st.run_id, st.data_dir)
    tmp = path <> ".#{:erlang.unique_integer([:positive])}.tmp"
    bin = :erlang.term_to_binary(%{run: st.run, seed: st.seed})
    :ok = File.write!(tmp, bin)
    :ok = File.rename(tmp, path)
    st
  end

  defp push(st, class, tick, payload) do
    # Reuse Run's private push by folding a fresh event onto the run's
    # reversed event list — identical to what Run.declare does internally.
    event =
      struct!(EngineCore.Ledger.Event,
        seq: st.run.seq + 1,
        tick: tick,
        class: class,
        payload: payload
      )

    %{st | run: %{st.run | events: [event | st.run.events], seq: st.run.seq + 1}}
  end

  defp append_audit(st, nil), do: st

  defp append_audit(st, %Audit{} = audit),
    do: push(st, :llm, st.run.world.tick, Audit.to_ledger(audit))

  # A clarify for this PC with no newer narration targeting them is still
  # outstanding — the table is waiting on that player's answer.
  defp outstanding_prompt(run, pc_id) do
    run.events
    |> Enum.find(fn
      %EngineCore.Ledger.Event{class: :narration, payload: %{agent_id: ^pc_id}} -> true
      %EngineCore.Ledger.Event{class: :clarify, payload: %{agent_id: ^pc_id}} -> true
      _ -> false
    end)
    |> case do
      %EngineCore.Ledger.Event{class: :clarify, tick: tick, payload: %{question: q}} ->
        %{question: q, tick: tick}

      _ ->
        nil
    end
  end

  defp alive?(nil), do: false

  defp alive?(agent) do
    hp = (agent.body && agent.body.hp) || 0
    hp > 0 and :dead not in ((agent.body && agent.body.conditions) || [])
  end

  defp snapshot_path(run_id, data_dir), do: Path.join(data_dir, "#{run_id}.snapshot")

  defp read_snapshot(run_id, data_dir) do
    path = snapshot_path(run_id, data_dir)

    with {:ok, bin} <- File.read(path),
         %{run: %Run{} = run, seed: %World{} = seed} <- :erlang.binary_to_term(bin) do
      {:ok, run, seed}
    else
      _ -> {:error, :no_checkpoint}
    end
  end

  # Spec §12.3 invariant: fold(seed, journal) == checkpointed world —
  # the snapshot and the journal are two records of the same history.
  defp fold_check(run_id, %Run{} = run) do
    folded = World.Server.snapshot(run_id)

    if :erlang.term_to_binary(folded) == :erlang.term_to_binary(run.world) do
      :ok
    else
      {:error, {:fold_divergence, journal_world: folded, checkpoint_world: run.world}}
    end
  end

  defp seq_check(run_id, run) do
    last = Writer.last_seq(run_id)

    if last == run.seq do
      :ok
    else
      {:error, {:checkpoint_mismatch, checkpoint: run.seq, journal: last}}
    end
  end

  defp call(run_id, msg) do
    case whereis(run_id) do
      nil -> {:error, :no_run}
      pid -> GenServer.call(pid, msg)
    end
  end

  defp whereis(run_id) do
    case Registry.lookup(@registry, {:session, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # Sessions live under `Referee.SessionSup` (spec §12.1), so they outlive
  # the process that started them (a test process, a channel, a script).
  # `:temporary` — a crashed session is recovered explicitly via
  # `restore/2`; auto-restart would replay {:new, ...} against a journal
  # that already holds those seqs.
  def child_spec(init_arg) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [init_arg]},
      restart: :temporary
    }
  end

  defp start_named(run_id, init_arg) do
    case Registry.lookup(@registry, {:session, run_id}) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:error, {:already_started, pid}}
        else
          # Registry name release is async to exit; poll for the cleanup.
          Process.sleep(5)
          start_named(run_id, init_arg)
        end

      [] ->
        case DynamicSupervisor.start_child(Referee.SessionSup, {__MODULE__, init_arg}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:error, {:already_started, pid}}
        end
    end
  end

  defp via(run_id), do: {:via, Registry, {@registry, {:session, run_id}}}
end
