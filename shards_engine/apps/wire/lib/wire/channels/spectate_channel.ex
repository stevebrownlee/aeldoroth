defmodule Wire.SpectateChannel do
  @moduledoc """
  GM/observer surface (spec §11; plan 5 Task 8). Join snapshot carries the
  engine truth: tick, boundary states, LLM spend, and the raw ledger tail.
  Every writer tail streams unfiltered — spectators see all classes; dice
  visibility is the referee preference stack's call, not the wire's.
  `pause`/`resume`/`spend` map to `Run.Session` calls.
  """

  use Phoenix.Channel

  alias EngineCore.Ledger
  alias EngineCore.Ledger.Writer
  alias EngineCore.World.Server
  alias Referee.Run.Session
  alias Referee.Spend
  alias Wire.JSONSafe

  @tail_cap 50

  @impl true
  def join("spectate:" <> run_id, _params, %{assigns: assigns} = socket) do
    with %{run_id: ^run_id, role: :spectate} <- assigns,
         %{} = state <- Session.state(run_id),
         :ok <- Writer.subscribe(run_id) do
      awaiting = enrich_awaiting(run_id, Session.awaiting(run_id))

      snapshot = %{
        tick: state.tick,
        boundaries: JSONSafe.to_json(Server.boundaries(run_id)),
        dungeon: JSONSafe.to_json(Server.dungeon_overview(run_id)),
        spend: Spend.report(Writer.events(run_id)),
        tail: Writer.events(run_id) |> Enum.take(-@tail_cap) |> JSONSafe.to_json(),
        awaiting: awaiting
      }

      {:ok, snapshot, assign(socket, :last_awaiting, awaiting)}
    else
      _other -> {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_in("pause", _params, socket) do
    case Session.pause(run_id(socket)) do
      {:ok, %{dossiers: dossiers}} -> {:reply, {:ok, %{dossiers: dossiers}}, socket}
      {:error, :already_paused} -> {:reply, {:error, %{reason: "already_paused"}}, socket}
    end
  end

  def handle_in("resume", _params, socket) do
    case Session.resume(run_id(socket)) do
      # `resumed: true` distinguishes this ack from heartbeat acks ({}).
      :ok -> {:reply, {:ok, %{resumed: true}}, socket}
      {:error, :not_paused} -> {:reply, {:error, %{reason: "not_paused"}}, socket}
    end
  end

  def handle_in("spend", _params, socket) do
    {:reply, {:ok, %{spend: Spend.report(Writer.events(run_id(socket)))}}, socket}
  end

  def handle_in("gm_chat", %{"text" => text}, socket) do
    case Session.gm_chat(run_id(socket), text) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in(_event, _params, socket),
    do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  @impl true
  def handle_info({:ledger_events, _run_id, events}, socket) do
    :ok = push(socket, "ledger_tail", %{events: JSONSafe.to_json(events)})

    for %Ledger.Event{class: :ooc, payload: %{agent_id: id, text: text}} <- events do
      :ok = push(socket, "ooc", %{agent_id: id, text: text})
    end

    push_state_sync(socket)
    {:noreply, push_awaiting(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp push_state_sync(socket) do
    run_id = run_id(socket)

    :ok =
      push(socket, "state_sync", %{
        tick: tick_of(run_id),
        boundaries: JSONSafe.to_json(Server.boundaries(run_id)),
        dungeon: JSONSafe.to_json(Server.dungeon_overview(run_id))
      })
  end

  defp push_awaiting(socket) do
    run_id = run_id(socket)
    current = enrich_awaiting(run_id, Session.awaiting(run_id))
    last = Map.get(socket.assigns, :last_awaiting, [])

    if current != last do
      :ok = push(socket, "awaiting", %{pcs: current})
      assign(socket, :last_awaiting, current)
    else
      socket
    end
  end

  defp enrich_awaiting(run_id, {:ok, pcs}) do
    Enum.map(pcs, fn pc ->
      seated = Registry.lookup(Wire.ClaimsReg, {run_id, pc.id}) != []
      Map.put(pc, :seated, seated)
    end)
  end

  defp enrich_awaiting(_run_id, {:error, :no_run}), do: []

  defp tick_of(run_id) do
    case Session.state(run_id) do
      %{} = state -> state.tick
      nil -> 0
    end
  end

  defp run_id(socket), do: socket.assigns.run_id
end
