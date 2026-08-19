defmodule Wire.RunChannel do
  @moduledoc """
  Per-PC protocol surface (spec §11; plan 5 Task 7 — wire contract verbatim).

  Join claims the socket's character exclusively and replies with the PC's
  truth-barrier slice plus the last dossier text. Ledger tails fan out as
  typed pushes: `perception` (own narrations), `prompt` (own clarifies),
  `dice` (own dice, prefs-gated), and `state_sync` (fresh slice after any
  world-class event). `terminate/2` releases the claim.
  """

  use Phoenix.Channel

  alias EngineCore.Ledger
  alias EngineCore.Ledger.Writer
  alias EngineCore.World.Server
  alias Referee.{Run.Session, Slice}
  alias Wire.Claims

  @impl true
  def join("run:" <> run_id, _params, %{assigns: assigns} = socket) do
    with %{run_id: ^run_id, role: :pc, character_id: pc_id} <- assigns,
         {:ok, pcs} <- Session.pcs(run_id),
         true <- pc_id in pcs || :not_a_pc,
         :ok <- Claims.claim(run_id, pc_id),
         :ok <- Writer.subscribe(run_id) do
      {:ok, %{state: slice(run_id, pc_id), dossier: last_dossier(run_id, pc_id)}, socket}
    else
      {:error, {:already_claimed, _pid}} -> {:error, %{reason: "character_already_claimed"}}
      _other -> {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_in("declare_intent", %{"text" => text}, socket),
    do: handle_declare(text, socket)

  def handle_in("answer", %{"text" => text}, socket),
    do: handle_declare(text, socket)

  def handle_in("ooc", %{"text" => text}, socket) do
    :ok = Session.ooc(run_id(socket), pc_id(socket), text)
    {:reply, {:ok, %{ack: true}}, socket}
  end

  # v1: read-only sync — `update` is accepted but ignored (plan Task 7).
  def handle_in("sheet", %{"update" => _update}, socket) do
    {:reply, {:ok, %{state: slice(run_id(socket), pc_id(socket))}}, socket}
  end

  def handle_in(_event, _params, socket), do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  @impl true
  def handle_info({:ledger_events, _run_id, events}, socket) do
    pc = pc_id(socket)
    open_dice? = dice_visibility(socket) == "open"

    Enum.each(events, fn ev -> push_one(ev, pc, open_dice?, socket) end)

    if Enum.any?(events, &(&1.class == :world)) do
      push(socket, "state_sync", %{slice: slice(run_id(socket), pc)})
    end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    Claims.release(run_id(socket), pc_id(socket))
    :ok
  end

  ## Internals

  defp handle_declare(text, socket) do
    case Session.declare(run_id(socket), pc_id(socket), text) do
      {:ok, %{reply: reply}} -> {:reply, {:ok, %{reply: reply}}, socket}
      {:error, :paused} -> {:reply, {:error, %{reason: :paused}}, socket}
      {:error, :no_run} -> {:reply, {:error, %{reason: :no_run}}, socket}
    end
  end

  defp push_one(%Ledger.Event{class: :narration, tick: tick, payload: %{agent_id: id, text: text}}, pc, _open?, socket) when id == pc,
    do: push(socket, "perception", %{text: text, tick: tick})

  defp push_one(%Ledger.Event{class: :clarify, payload: %{agent_id: id, question: q}}, pc, _open?, socket) when id == pc,
    do: push(socket, "prompt", %{question: q})

  defp push_one(%Ledger.Event{class: :dice, payload: payload}, pc, true = _open?, socket)
       when is_map(payload) and :erlang.map_get(:agent_id, payload) == pc,
       do: push(socket, "dice", %{event_payload: payload})

  defp push_one(_ev, _pc, _open?, _socket), do: :ok

  defp slice(run_id, pc_id), do: Slice.for_actor(Server.snapshot(run_id), pc_id)

  defp dice_visibility(socket) do
    case Session.prefs(run_id(socket)) do
      {:ok, prefs} -> Map.get(prefs, :dice_visibility, "open")
      _ -> "open"
    end
  end

  defp last_dossier(run_id, pc_id) do
    run_id
    |> Writer.events()
    |> Enum.filter(&match?(%Ledger.Event{class: :dossier, payload: %{pc_id: ^pc_id}}, &1))
    |> List.last()
    |> case do
      nil -> nil
      ev -> ev.payload[:text]
    end
  end

  defp run_id(socket), do: socket.assigns.run_id
  defp pc_id(socket), do: socket.assigns.character_id
end
