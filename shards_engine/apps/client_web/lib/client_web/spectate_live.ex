defmodule ClientWeb.SpectateLive do
  @moduledoc """
  GM console (plan 7 Task 5): spectate-channel view over the wire (tail +
  state_sync) plus referee-authority levers — advance/pause/resume call
  `Referee.Run.Session` directly (trusted surface, plan's trust split: the
  advance lever is the referee, not a seat).
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.Run.Session

  @impl true
  def mount(%{"run_id" => run_id}, _session, socket) do
    socket =
      assign(socket,
        run_id: run_id,
        conn: nil,
        error: nil,
        tick: nil,
        tail: [],
        boundaries: nil,
        dossiers: nil,
        resumed: false,
        spend: nil
      )

    if connected?(socket) && wire_url() do
      case Conn.start_link(wire_url(), run_id: run_id, spectate: true, parent: self()) do
        {:ok, pid} ->
          {:ok, monitor_conn(socket, pid)}

        {:error, reason} ->
          {:ok, assign(socket, error: "wire connection failed: #{inspect(reason)}")}
      end
    else
      {:ok, socket}
    end
  end

  # Levers -------------------------------------------------------------------

  # Advance is referee authority: the engine console calls the session
  # directly (trusted surface), never the wire.
  @impl true
  def handle_event("advance", _params, socket) do
    case Session.advance(socket.assigns.run_id) do
      {:ok, _} -> {:noreply, assign(socket, resumed: false)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "advance: #{inspect(reason)}")}
    end
  end

  # Everything else is wire traffic (plan 5 Task 5): the spectate channel
  # owns pause/resume/spend; replies arrive as chan_reply messages below.
  def handle_event("pause", _params, %{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    :ok = Conn.send_event(conn, "pause", %{})
    {:noreply, socket}
  end

  def handle_event("resume", _params, %{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    :ok = Conn.send_event(conn, "resume", %{})
    {:noreply, socket}
  end

  def handle_event("spend", _params, %{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    :ok = Conn.send_event(conn, "spend", %{})
    {:noreply, socket}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages ---------------------------------------------------------

  # Spectate join reply: initial tail + tick + boundaries + spend.
  @impl true
  def handle_info({:chan_reply, _ref, :ok, %{"tail" => tail} = reply}, socket) do
    {:noreply, assign(socket, tick: reply["tick"], boundaries: reply["boundaries"], spend: reply["spend"], tail: tail)}
  end

  # Pause reply: one dossier per living PC.
  def handle_info({:chan_reply, _ref, :ok, %{"dossiers" => dossiers}}, socket) do
    {:noreply, assign(socket, dossiers: dossiers, resumed: false)}
  end

  # Spend reply: the report (total, by class, by agent).
  def handle_info({:chan_reply, _ref, :ok, %{"spend" => spend}}, socket) do
    {:noreply, assign(socket, spend: spend)}
  end

  # Resume reply: `{"resumed": true}` — distinctive so heartbeat acks ({}),
  # which share the transport, never masquerade as a resume.
  def handle_info({:chan_reply, _ref, :ok, %{"resumed" => true}}, socket) do
    {:noreply, assign(socket, dossiers: nil, resumed: true)}
  end

  # Heartbeat acks and future empty ok replies: nothing to show.
  def handle_info({:chan_reply, _ref, :ok, _payload}, socket), do: {:noreply, socket}

  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, assign(socket, error: reason)}
  end

  def handle_info({:chan, _topic, "state_sync", %{"tick" => tick} = push}, socket) do
    {:noreply, assign(socket, tick: tick, boundaries: push["boundaries"] || socket.assigns.boundaries)}
  end

  # Protocol growth never crashes the console.
  def handle_info({:chan, _topic, _event, _payload}, socket), do: {:noreply, socket}
  def handle_info({:chan_reply, _ref, _status, _payload}, socket), do: {:noreply, socket}

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply, assign(socket, conn: nil, error: "wire connection lost: #{inspect(reason)}")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <h1>GM console — run <%= @run_id %></h1>

    <p :if={@error} class="error">spectate: <%= @error %></p>

    <%= if @tick do %>
      <p>Tick <%= @tick %><span :if={@resumed}> — run resumed</span></p>

      <p>
        <button data-testid="advance" phx-click="advance">Advance</button>
        <button data-testid="pause" phx-click="pause">Pause &amp; dossier</button>
        <button data-testid="resume" phx-click="resume" :if={@dossiers}>Resume</button>
        <button data-testid="spend" phx-click="spend">LLM spend</button>
      </p>

      <%= if @boundaries do %>
        <section>
          <h2>Boundaries</h2>
          <table>
            <tbody>
              <tr :for={{place, state} <- Enum.sort(@boundaries)}>
                <td><%= place %></td>
                <td><%= state["state"] %> (last trigger: <%= state["last_trigger_tick"] %>)</td>
              </tr>
            </tbody>
          </table>
        </section>
      <% end %>

      <%= if @spend do %>
        <section>
          <h2>LLM spend</h2>
          <% t = @spend["total"] || @spend[:total] %>
          <p>calls: <%= t["calls"] || t[:calls] %> · tokens_in: <%= t["tokens_in"] || t[:tokens_in] %> · tokens_out: <%= t["tokens_out"] || t[:tokens_out] %></p>
        </section>
      <% end %>
    <% end %>

    <%= if @dossiers do %>
      <section>
        <h2>Dossiers</h2>
        <%= for {pc_id, text} <- Enum.sort(@dossiers) do %>
          <h3><%= pc_id %></h3>
          <pre><%= text %></pre>
        <% end %>
      </section>
    <% end %>

    <%= if @tail != [] do %>
      <section>
        <h2>Ledger tail</h2>
        <ul id="ledger">
          <li :for={ev <- @tail} id={"seq-#{ev["seq"]}"} class={ev["class"]}>
            seq <%= ev["seq"] %> · tick <%= ev["tick"] %> · <%= ev["class"] %>
          </li>
        </ul>
      </section>
    <% end %>
    """
  end

  ## Internals

  defp wire_url, do: Application.get_env(:client_web, :wire_url)

  defp monitor_conn(socket, pid) do
    Process.monitor(pid)
    assign(socket, conn: pid)
  end
end
