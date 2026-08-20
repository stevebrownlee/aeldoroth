defmodule ClientWeb.SpectateLive do
  @moduledoc """
  GM console (UX spec §6, Phase C): flow board (who the table waits on),
  referee levers (advance, advance-until-input, pause/resume, spend), the
  dungeon boundary panel, always-visible LLM spend header, and a readable
  ledger preview. Views ride the spectate channel (tail + state_sync +
  awaiting); advance levers call `Referee.Run.Session` directly — trusted
  surface, the advance lever is the referee, not a seat.
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.Run.Session

  @until_input_cap 20

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
        awaiting: [],
        dossiers: nil,
        resumed: false,
        spend: nil,
        auto_note: nil
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
      {:ok, _} -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  # Advance until a seat needs input (clarify prompt) or the cap hits —
  # the GM's cruise control (UX spec §6). Direct session calls: referee
  # authority, same trust as advance.
  def handle_event("advance_until_input", _params, socket) do
    {steps, result} = advance_until_input(socket.assigns.run_id, 0, nil)

    note =
      case result do
        :needs_input -> "stopped after #{steps} step(s) — a seat needs input"
        :cap -> "stopped at the #{@until_input_cap}-step cap"
        {:error, reason} -> "stopped after #{steps} step(s): #{inspect(reason)}"
      end

    {:noreply, assign(socket, auto_note: note)}
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

  # Spectate join reply: initial snapshot (tail + tick + boundaries + spend
  # + the flow board).
  @impl true
  def handle_info({:chan_reply, _ref, :ok, %{"tail" => tail} = reply}, socket) do
    {:noreply,
     assign(socket,
       tick: reply["tick"],
       boundaries: reply["boundaries"],
       spend: reply["spend"],
       awaiting: reply["awaiting"] || [],
       tail: tail
     )}
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

  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, assign(socket, error: reason)}
  end

  def handle_info({:chan, _topic, "state_sync", %{"tick" => tick} = push}, socket) do
    {:noreply,
     assign(socket, tick: tick, boundaries: push["boundaries"] || socket.assigns.boundaries)}
  end

  # Flow board refresh (UX spec §6): awaiting rows pushed on change.
  def handle_info({:chan, _topic, "awaiting", %{"pcs" => rows}}, socket) do
    {:noreply, assign(socket, awaiting: rows)}
  end

  # New ledger events append to the preview.
  def handle_info({:chan, _topic, "ledger_tail", %{"events" => events}}, socket) do
    {:noreply, update(socket, :tail, &(&1 ++ events))}
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
      <p class="status-ribbon">Tick <%= @tick %></p>
      <div class="layout-gm">
        <div class="gm-main">
          <section class="panel" data-testid="flow-board">
            <h2>Flow board</h2>
            <p class="hint">Who the table is waiting on.</p>
            <ul class="flow-list">
              <li :for={row <- @awaiting} class={if prompt_of(row), do: "flow-row needs", else: "flow-row"}>
                <span class="seat-dot" data-seated={seated?(row)}></span>
                <strong><%= name_of(row) %></strong>
                <%= if prompt = prompt_of(row) do %>
                  <em class="prompt">needs input: <%= prompt %></em>
                <% else %>
                  <span class="intent"><%= last_intent_of(row) || "waiting for intent" %></span>
                <% end %>
              </li>
            </ul>
          </section>

          <section class="panel">
            <h2>Levers</h2>
            <div class="lever-row">
              <button data-testid="advance" phx-click="advance">Advance</button>
              <button data-testid="advance_until_input" phx-click="advance_until_input">Advance until input</button>
              <button data-testid="pause" phx-click="pause">Pause &amp; dossier</button>
              <button data-testid="resume" phx-click="resume" :if={@dossiers}>Resume</button>
              <button data-testid="spend" phx-click="spend">LLM spend</button>
            </div>
            <p :if={@auto_note} class="hint"><%= @auto_note %></p>
            <p :if={@resumed && !@auto_note} class="hint">run resumed</p>
          </section>

          <section class="panel">
            <h2>Ledger</h2>
            <ul class="ledger-preview" id="ledger">
              <li :for={ev <- @tail} id={"seq-#{ev["seq"]}"} class={ev["class"]}>
                <span class="seq"><%= ev["seq"] %></span>
                <%= render_event(ev) %>
              </li>
            </ul>
          </section>
        </div>

        <aside class="gm-rail">
          <%= if @spend do %>
            <section class="panel">
              <h2>LLM spend</h2>
              <% t = @spend["total"] || @spend[:total] %>
              <p>calls: <%= get_num(t, "calls") %> · tokens_in: <%= get_num(t, "tokens_in") %> · tokens_out: <%= get_num(t, "tokens_out") %></p>
            </section>
          <% end %>

          <%= if @boundaries do %>
            <section class="panel">
              <h2>Boundaries</h2>
              <table class="boundary-table">
                <tbody>
                  <tr :for={{place, state} <- Enum.sort(@boundaries)}>
                    <td><%= place %></td>
                    <td>
                      <span class={"boundary state-#{state_value(state)}"}><%= state_value(state) %></span>
                      <span class="hint">since <%= get_num(state, "last_trigger_tick") %></span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </section>
          <% end %>

          <%= if @dossiers do %>
            <section class="panel">
              <h2>Dossiers</h2>
              <%= for {pc_id, text} <- Enum.sort(@dossiers) do %>
                <h3><%= pc_id %></h3>
                <pre><%= text %></pre>
              <% end %>
            </section>
          <% end %>
        </aside>
      </div>
    <% end %>
    """
  end

  ## Internals

  defp wire_url, do: Application.get_env(:client_web, :wire_url)

  defp monitor_conn(socket, pid) do
    Process.monitor(pid)
    assign(socket, conn: pid)
  end

  # advance_until_input: step until a clarify prompt appears, the cap hits,
  # or the session errors. Returns {steps, :needs_input | :cap | {:error, reason}}.
  defp advance_until_input(_run_id, steps, result)
       when steps >= @until_input_cap or result != nil,
       do: {steps, result || :cap}

  defp advance_until_input(run_id, steps, nil) do
    case Session.advance(run_id) do
      {:ok, _} ->
        if awaiting_input?(run_id),
          do: {steps + 1, :needs_input},
          else: advance_until_input(run_id, steps + 1, nil)

      {:error, reason} ->
        {steps, {:error, reason}}
    end
  end

  defp awaiting_input?(run_id) do
    case Session.awaiting(run_id) do
      {:ok, rows} -> Enum.any?(rows, &prompt_of(&1))
      {:error, _} -> false
    end
  end

  # Awaiting rows arrive JSON-decoded (string keys) from the wire; direct
  # session reads hand back atom keys. Accessor helpers accept both.
  defp prompt_of(row) when is_map(row) do
    Map.get(row, "prompt") || Map.get(row, :prompt)
  end

  defp last_intent_of(row) when is_map(row) do
    Map.get(row, "last_intent") || Map.get(row, :last_intent)
  end

  defp name_of(row) when is_map(row) do
    Map.get(row, "name") || Map.get(row, :name) || Map.get(row, "id") || Map.get(row, :id)
  end

  defp seated?(row) when is_map(row) do
    Map.get(row, "seated") || Map.get(row, :seated) || false
  end

  defp state_value(state) when is_map(state),
    do: Map.get(state, "state") || Map.get(state, :state) || "?"

  defp state_value(other), do: other

  defp get_num(nil, _key), do: 0

  defp get_num(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, safe_atom(key)) || 0

  defp get_num(_other, _key), do: 0

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # One readable line per ledger event (UX spec §6) — previews, not raw JSON.
  defp render_event(%{"class" => "narration", "payload" => %{"agent_id" => who, "text" => text}}),
    do: "narration → #{who}: #{text}"

  defp render_event(%{"class" => "signal", "payload" => p}) do
    about = p["about"] || "?"
    kind = p["signal_kind"] || p["kind"]

    case p["fidelity"] do
      nil -> "signal: #{kind} about #{about}"
      f -> "signal: #{kind} about #{about} · fidelity #{f}"
    end
  end

  defp render_event(%{"class" => "dice", "payload" => p}) do
    base =
      case p do
        %{"sides" => s, "roll" => r} -> "dice: #{p["purpose"]} d#{s} → #{r}"
        _ -> "dice: #{p["purpose"]}"
      end

    case p do
      %{"hit" => true} -> base <> " — hit"
      %{"hit" => false} -> base <> " — miss"
      %{"amount" => a} -> base <> " — #{a} dmg"
      _ -> base
    end
  end

  defp render_event(%{"class" => "ooc", "payload" => %{"agent_id" => who, "text" => text}}),
    do: "ooc · #{who}: #{text}"

  defp render_event(%{"class" => "clarify", "payload" => %{"question" => q}}),
    do: "clarify: #{q}"

  defp render_event(%{"class" => "llm", "payload" => p}),
    do:
      "llm: #{p["class"]} · #{p["agent_id"]} · #{p["tokens_in"] || 0}→#{p["tokens_out"] || 0} tok"

  defp render_event(%{"class" => "dossier", "payload" => %{"pc_id" => pc}}),
    do: "dossier: #{pc}"

  defp render_event(%{"class" => "meta", "payload" => %{"kind" => kind}}),
    do: "meta: #{kind}"

  defp render_event(%{"class" => "world", "payload" => %{"kind" => kind}}),
    do: "world: #{kind}"

  defp render_event(%{"class" => "deliberation", "payload" => p}),
    do: "deliberation: #{p["decision"]} · #{p["agent_id"]}"

  defp render_event(%{"class" => class, "payload" => %{"kind" => kind}}),
    do: "#{class}: #{kind}"

  defp render_event(%{"class" => class}), do: class
  defp render_event(other), do: inspect(other)
end
