defmodule EngineCore.World.Server do
  @moduledoc """
  Authoritative world fold for one run (spec §12.1): a GenServer holding
  `fold(ledger)` and advancing it off ledger-writer tails. Reads are cheap
  `GenServer.call`s served from the cached snapshot — they never join the
  writer's append path (plan 5 Task 3).
  """

  alias EngineCore.{Fold, Ledger, World}
  alias EngineCore.Ledger.Writer

  use GenServer

  defstruct [:run_id, :world, :last_seq]

  @doc "Start under `EngineCore.RunSup`. `world` is the run's seed state."
  @spec start_link({String.t(), World.t()}) :: GenServer.on_start()
  def start_link({run_id, %World{} = world}) do
    GenServer.start_link(__MODULE__, {run_id, world},
      name: {:via, Registry, {EngineCore.RunReg, {:world, run_id}}}
    )
  end

  # :transient — teardown (GenServer.stop :normal) must not restart the
  # fold against a writer that is itself stopping (restart loops here can
  # take down the whole EngineCore supervision tree).
  def child_spec({run_id, _world} = arg) do
    %{id: {__MODULE__, run_id}, start: {__MODULE__, :start_link, [arg]}, restart: :transient}
  end

  @doc "Current world snapshot (cached fold)."
  @spec snapshot(String.t()) :: World.t()
  def snapshot(run_id) do
    GenServer.call(via(run_id), :snapshot)
  end

  @doc "Boundary states as `%{id => %{state, last_trigger_tick}}`."
  @spec boundaries(String.t()) :: %{String.t() => map()}
  def boundaries(run_id) do
    try do
      Map.new(snapshot(run_id).boundaries, fn {id, b} ->
        {id, %{state: b.state, last_trigger_tick: b.last_trigger_tick}}
      end)
    catch
      :exit, _ -> %{}
    end
  end

  @doc "Active non-PC agents for referee and spectate panels."
  @spec active_agents(String.t()) :: [map()]
  def active_agents(run_id) do
    try do
      world = snapshot(run_id)
    place_name_by_id = Map.new(world.places, fn {_id, p} -> {p.id, p.name} end)

    awake_boundaries =
      world.boundaries
      |> Map.values()
      |> Enum.filter(&(&1.state == :awake))

    by_agent_id =
      Enum.reduce(awake_boundaries, %{}, fn b, acc ->
        Enum.reduce(b.bound_agent_ids || [], acc, fn aid, acc2 ->
          Map.put_new(acc2, aid, b)
        end)
      end)

    by_place_id =
      Enum.reduce(awake_boundaries, %{}, fn b, acc ->
        if b.scope_place_id, do: Map.put_new(acc, b.scope_place_id, b), else: acc
      end)

    by_group =
      Enum.reduce(awake_boundaries, %{}, fn b, acc ->
        if b.scope_group, do: Map.put_new(acc, b.scope_group, b), else: acc
      end)

    world.agents
    |> Map.values()
    |> Enum.reject(&Map.get(&1, :pc, false))
    |> Enum.filter(fn a ->
      a.attention != :dormant or
        Map.has_key?(by_agent_id, a.id) or
        Map.has_key?(by_place_id, a.place_id) or
        Map.has_key?(by_group, a.group)
    end)
    |> Enum.map(fn a ->
      b = by_agent_id[a.id] || by_place_id[a.place_id] || by_group[a.group]
      body = a.body || %{}
      statblock = a.statblock || %{}

      %{
        id: a.id,
        name: a.name,
        tier: a.tier || 1,
        group: a.group,
        place_id: a.place_id,
        place_name: Map.get(place_name_by_id, a.place_id, a.place_id),
        boundary_id: b && b.id,
        wake_tick: b && b.last_trigger_tick,
        wake_reason: (b && b.last_trigger_reason) || "presence crossing",
        hp: body.hp || 1,
        hp_max: statblock.hp_max || 1,
        ac: statblock.ac || 10,
        thac0: statblock.thac0 || 20,
        morale: statblock.morale || 7,
        conditions: body.conditions || [],
        commitments:
          Enum.map(a.commitments || [], fn c ->
            %{
              id: c.id,
              debtor: c.debtor,
              creditor: c.creditor,
              deed: c.deed,
              due: c.due,
              priority: c.priority,
              status: c.status
            }
          end),
        last_intent: nil,
        dossier: a.dossier || %{}
      }
    end)
    catch
      :exit, _ -> []
    end
  end

  @doc "Full dungeon overview for referee console: all places, connections, resident agents, items, and hazards."
  @spec dungeon_overview(String.t()) :: map()
  def dungeon_overview(run_id) do
    try do
      world = snapshot(run_id)
    edge_by_pair = Map.new(world.edges, fn e -> {{e.from, e.to}, e} end)

    places =
      world.places
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn place ->
        connections =
          (place.connections || [])
          |> Enum.map(fn target ->
            edge = Map.get(edge_by_pair, {place.id, target})
            label = if edge, do: edge.label, else: nil
            sealed = if edge, do: Map.get(edge, :sealed, false), else: false
            %{to: target, label: label, direction: label, sealed: sealed}
          end)

        items =
          world.items
          |> Map.values()
          |> Enum.filter(&(&1.place_id == place.id))
          |> Enum.map(fn item ->
            %{
              id: item.id,
              name: item.name,
              value_gp: item.value_gp || 0,
              is_hidden: item.is_hidden || false,
              holder_id: item.holder_id
            }
          end)
          |> Enum.sort_by(& &1.id)

        hazards =
          world.hazards
          |> Map.values()
          |> Enum.filter(&(&1.place_id == place.id))
          |> Enum.map(fn h ->
            %{
              id: h.id,
              kind: h.kind,
              dc: h.dc || 12,
              triggered: h.triggered || false,
              damage: h.damage
            }
          end)
          |> Enum.sort_by(& &1.id)

        %{
          id: place.id,
          name: place.name || place.id,
          kind: place.kind,
          connections: connections,
          items: items,
          hazards: hazards,
          agents:
            World.agents_in(world, place.id)
            |> Enum.map(fn a ->
              body = Map.get(a, :body, %{}) || %{}
              statblock = Map.get(a, :statblock, %{}) || %{}

              %{
                id: a.id,
                name: a.name,
                pc: Map.get(a, :pc, false),
                hp: body[:hp],
                hp_max: statblock[:hp_max],
                conditions: body[:conditions] || []
              }
            end)
        }
      end)

      %{places: places}
    catch
      :exit, _ -> %{places: []}
    end
  end

  @doc """
  Cast: fold `events` into the snapshot (restore path). The first new
  event's seq must be `last_seq + 1`; a gap crashes the server — the
  ledger is the only truth and must never be spliced.
  """
  @spec adopt(String.t(), [Ledger.Event.t()]) :: :ok
  def adopt(run_id, events) do
    GenServer.cast(via(run_id), {:adopt, events})
  end

  @impl true
  def init({run_id, %World{} = world}) do
    # Catch up with anything already in the ledger, then follow the tail.
    existing = Writer.events(run_id)
    state = %__MODULE__{run_id: run_id, world: Fold.fold(world, existing), last_seq: 0}
    state = %{state | last_seq: last_seq(state.world, existing)}

    case Writer.subscribe(run_id) do
      :ok -> {:ok, state}
      # No writer means teardown is already underway; exit quietly rather
      # than crash-looping into the DynamicSupervisor's restart intensity.
      {:error, :no_writer} -> {:stop, :normal}
    end
  end

  @impl true
  def handle_info({:ledger_events, run_id, [%Ledger.Event{} | _] = events}, %__MODULE__{} = st)
      when run_id == st.run_id do
    new = Enum.reject(events, &(&1.seq <= st.last_seq))
    {:noreply, %{st | world: Fold.fold(st.world, new), last_seq: max_seq(st.last_seq, new)}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, st), do: {:noreply, st}

  @impl true
  def handle_call(:snapshot, _from, st), do: {:reply, st.world, st}

  @impl true
  def handle_cast({:adopt, events}, %__MODULE__{} = st) do
    new = Enum.reject(events, &(&1.seq <= st.last_seq))

    case new do
      [] ->
        {:noreply, st}

      [%Ledger.Event{seq: first} | _] when first == st.last_seq + 1 ->
        {:noreply, %{st | world: Fold.fold(st.world, new), last_seq: max_seq(st.last_seq, new)}}

      [%Ledger.Event{seq: got} | _] ->
        raise ArgumentError, "world adopt seq gap: expected #{st.last_seq + 1}, got #{got}"
    end
  end

  ## Internals

  defp via(run_id), do: {:via, Registry, {EngineCore.RunReg, {:world, run_id}}}

  defp last_seq(_world, []), do: 0
  defp last_seq(_world, events), do: events |> List.last() |> Map.fetch!(:seq)

  defp max_seq(prev, []), do: prev
  defp max_seq(prev, events), do: max(prev, events |> List.last() |> Map.fetch!(:seq))
end
