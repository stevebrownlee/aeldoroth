defmodule ClientWeb.SpectateLive do
  @moduledoc """
  GM console (UX spec §6, Phase C): 2-column tabletop referee screen.

  Left column: round loop + party intent cards with vitals, and an
  omniscient dungeon overview. Right column: live story chronicle,
  GM-to-table chat, and pause-time character dossiers. Bottom: collapsible
  diagnostics drawer (LLM spend, ledger preview, boundary states).

  The spectate channel feeds tick, state_sync, dungeon, awaiting, and
  ledger_tail pushes. Referee levers (advance, advance-until-input,
  pause/resume, spend) call `Referee.Run.Session` directly — trusted
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
        dungeon: nil,
        awaiting: [],
        dossiers: nil,
        resumed: false,
        spend: nil,
        auto_note: nil,
        gm_chat_draft: ""
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

  # GM table-wide chat: prefer the wire (spectate channel) when connected,
  # fall back to a direct Session call for offline/testing surfaces.
  def handle_event("gm_chat", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_binary(text) and is_pid(conn) do
    trimmed = String.trim(text)

    if trimmed != "" do
      :ok = Conn.send_event(conn, "gm_chat", %{"text" => trimmed})
      {:noreply, assign(socket, gm_chat_draft: "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("gm_chat", %{"text" => text}, socket) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed != "" do
      case Session.gm_chat(socket.assigns.run_id, trimmed) do
        :ok -> {:noreply, assign(socket, gm_chat_draft: "")}
        {:error, :no_run} -> {:noreply, assign(socket, error: "run not found")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages -------------------------------------------------------------

  # Spectate join reply: initial snapshot (tail + tick + boundaries + spend
  # + dungeon + the flow board).
  @impl true
  def handle_info({:chan_reply, _ref, :ok, %{"tail" => tail} = reply}, socket) do
    {:noreply,
     assign(socket,
       tick: reply["tick"],
       boundaries: reply["boundaries"],
       dungeon: reply["dungeon"],
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
     assign(socket,
       tick: tick,
       boundaries: push["boundaries"] || socket.assigns.boundaries,
       dungeon: push["dungeon"] || socket.assigns.dungeon
     )}
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
      <header class="status-ribbon">
        <span class="badge"><b>Tick <%= @tick %></b></span>
        <span class="badge">Round <%= round_of(@tick) %></span>
        <span class="badge">Status: <%= status_badge(@resumed, @dossiers) %></span>
        <span class="badge" data-testid="party-readiness">
          Party readiness: <%= readiness(@awaiting) %>/<%= length(@awaiting) %>
        </span>
      </header>

      <section class="lever-row" data-testid="levers">
        <div class="lever">
          <button data-testid="advance" phx-click="advance">End Round (Run World)</button>
          <p class="lever-subtitle">Executes declared player actions &amp; NPC AI deliberation for 1 round.</p>
          <span class="badge readiness" data-testid="readiness-badge"><%= readiness(@awaiting) %>/<%= length(@awaiting) %> ready</span>
        </div>
        <div class="lever">
          <button data-testid="advance_until_input" phx-click="advance_until_input">Auto-Run until Choice</button>
          <p class="lever-subtitle">Steps rounds until a player decision is required.</p>
        </div>
        <%= if @dossiers do %>
          <div class="lever">
            <button data-testid="resume" phx-click="resume">Resume Play</button>
          </div>
        <% else %>
          <div class="lever">
            <button data-testid="pause" phx-click="pause">Pause &amp; Recap</button>
          </div>
        <% end %>
        <div class="lever">
          <button data-testid="spend" phx-click="spend">LLM spend</button>
        </div>
      </section>
      <p :if={@auto_note} class="hint"><%= @auto_note %></p>
      <p :if={@resumed && !@auto_note} class="hint">run resumed</p>

      <div class="layout-gm">
        <div class="gm-main">
          <section class="panel" data-testid="flow-board">
            <h2>Flow board</h2>
            <p class="hint">Who the table is waiting on.</p>
            <ul class="flow-list">
              <li :for={row <- @awaiting} class={card_class(row)}>
                <span class="seat-dot" data-seated={seated?(row)}></span>
                <div class="flow-card">
                  <strong class="pc-name"><%= name_of(row) %></strong>
                  <div class="location"><%= place_name_of(row) %></div>
                  <%= if prompt = prompt_of(row) do %>
                    <span class="badge badge-prompt">NEEDS INPUT</span>
                    <em class="prompt"><%= prompt %></em>
                  <% else %>
                    <%= if intent = last_intent_of(row) do %>
                      <span class="badge badge-ready">READY</span>
                      <span class="intent"><%= intent %></span>
                    <% else %>
                      <span class="badge badge-thinking">THINKING</span>
                      <span class="intent">Waiting for player action...</span>
                    <% end %>
                  <% end %>
                  <div class="hpbar" data-testid="hpbar">
                    <div style={"width: #{hp_percent(row)}%;"}></div>
                  </div>
                  <div class="vitals">
                    HP <%= hp_of(row) %>/<%= max_hp_of(row) %>
                    <span class="stat">AC <%= ac_of(row) %></span>
                    <span class="stat">THAC0 <%= thac0_of(row) %></span>
                  </div>
                </div>
              </li>
            </ul>
          </section>

          <section class="panel" data-testid="dungeon-overview">
            <h2>Dungeon overview</h2>
            <p class="hint">Omniscient view of places and resident agents.</p>
            <div class="dungeon-grid">
              <article :for={place <- dungeon_places(@dungeon)} class="room-card" data-room-id={place["id"]}>
                <h3><%= place["name"] %></h3>
                <p class="hint"><%= place["id"] %> · <%= place["kind"] %></p>
                <ul class="residents">
                  <li :for={agent <- place["agents"] || []}>
                    <span :if={agent["pc"]} class="badge pc"><%= agent["name"] %></span>
                    <span :if={!agent["pc"]} class="badge monster"><%= agent["name"] %></span>
                    <%= if hp = agent["hp"] do %>
                      <span class="dim">HP <%= hp %>/<%= agent["hp_max"] || "?" %></span>
                    <% end %>
                  </li>
                </ul>
                <ul :if={(place["items"] || []) != []} class="items">
                  <li :for={item <- place["items"] || []}>
                    <span class="badge treasure">TREASURE</span>
                    <%= item["name"] %>
                    <span class="dim"><%= item["value_gp"] || 0 %> gp</span>
                    <span :if={item["is_hidden"]} class="badge hidden">HIDDEN</span>
                    <span :if={item["holder_id"]} class="badge carried">CARRIED</span>
                  </li>
                </ul>
                <ul :if={(place["hazards"] || []) != []} class="hazards">
                  <li :for={hazard <- place["hazards"] || []}>
                    <span class="badge hazard">HAZARD</span>
                    <%= hazard["kind"] %>
                    <span class="dim">DC <%= hazard["dc"] %></span>
                    <span class={"badge " <> if(hazard["triggered"], do: "triggered", else: "armed")}>
                      <%= if hazard["triggered"], do: "TRIGGERED", else: "ARMED" %>
                    </span>
                  </li>
                </ul>
                <ul :if={place["connections"] != []} class="exits">
                  <li :for={conn <- place["connections"] || []}>
                    <%= exit_label(conn) %> → <%= exit_to(conn) %>
                    <span :if={conn["sealed"]} class="badge sealed">SECRET / SEALED</span>
                  </li>
                </ul>
              </article>
            </div>
          </section>
        </div>

        <aside class="gm-rail">
          <section class="panel" data-testid="chronicle">
            <h2>Story chronicle</h2>
            <ul class="chronicle log" id="chronicle" phx-hook="ChronicleScroll">
              <li :for={ev <- @tail} class={"kind-#{ev["class"]}"}>
                <%= render_event(ev) %>
              </li>
            </ul>
          </section>

          <section class="panel">
            <h2>GM chat</h2>
            <form phx-submit="gm_chat" data-testid="gm-chat-form" class="compose">
              <input name="text" type="text" placeholder="Message the table…" required />
              <button type="submit">Send to table</button>
            </form>
          </section>

          <%= if @dossiers do %>
            <section class="panel" data-testid="dossiers">
              <h2>Dossiers</h2>
              <%= for {pc_id, text} <- Enum.sort(@dossiers) do %>
                <h3><%= pc_id %></h3>
                <pre><%= text %></pre>
              <% end %>
            </section>
          <% end %>
        </aside>
      </div>

      <details class="diagnostics" data-testid="diagnostics">
        <summary>Diagnostics</summary>
        <div class="diagnostics-grid">
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
      </details>
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

  defp round_of(tick) when is_integer(tick), do: div(tick, 10) + 1

  defp status_badge(true, _), do: "running"
  defp status_badge(_, nil), do: "running"
  defp status_badge(_, _), do: "paused — dossier review"

  defp readiness(rows) do
    Enum.count(rows, fn row ->
      last_intent_of(row) != nil && prompt_of(row) == nil
    end)
  end

  defp dungeon_places(nil), do: []

  defp dungeon_places(dungeon) when is_map(dungeon) do
    dungeon["places"] || dungeon[:places] || []
  end

  # Awaiting rows arrive JSON-decoded (string keys) from the wire; direct
  # session reads hand back atom keys. Accessor helpers accept both.
  # `prompt` arrives as `%{"question" => ..., "tick" => ...}` (or atom keys
  # from direct session reads); render its question, never the map.
  defp prompt_of(row) when is_map(row) do
    case Map.get(row, "prompt") || Map.get(row, :prompt) do
      %{question: q} -> q
      %{"question" => q} -> q
      q when is_binary(q) -> q
      _ -> nil
    end
  end

  defp prompt_of(_), do: nil

  # `last_intent` is a map (`%{"text" => ..., "tick" => ...}`) or nil —
  # render its text, never the raw map (Phoenix.HTML.Safe has no Map).
  defp last_intent_of(row) when is_map(row) do
    case Map.get(row, "last_intent") || Map.get(row, :last_intent) do
      %{text: text} -> text
      %{"text" => text} -> text
      _ -> nil
    end
  end

  defp last_intent_of(_), do: nil

  defp hp_of(row) when is_map(row) do
    Map.get(row, "hp") || Map.get(row, :hp) || "?"
  end

  defp max_hp_of(row) when is_map(row) do
    Map.get(row, "hp_max") || Map.get(row, :hp_max) || "?"
  end

  defp card_class(row) do
    base = "flow-card-outer"

    cond do
      prompt_of(row) -> "#{base} needs"
      last_intent_of(row) -> "#{base} ready"
      true -> "#{base} idle"
    end
  end

  defp name_of(row) when is_map(row) do
    Map.get(row, "name") || Map.get(row, :name) || Map.get(row, "id") || Map.get(row, :id)
  end

  defp seated?(row) when is_map(row) do
    Map.get(row, "seated") || Map.get(row, :seated) || false
  end

  defp place_name_of(row) when is_map(row) do
    Map.get(row, "place_name") || Map.get(row, :place_name) || "?"
  end

  defp ac_of(row) when is_map(row) do
    Map.get(row, "ac") || Map.get(row, :ac) || "?"
  end

  defp thac0_of(row) when is_map(row) do
    Map.get(row, "thac0") || Map.get(row, :thac0) || "?"
  end

  # Dungeon overview exit connections may arrive with string or atom keys.
  defp exit_label(conn) when is_map(conn) do
    Map.get(conn, "label") ||
      Map.get(conn, :label) ||
      Map.get(conn, "direction") ||
      Map.get(conn, :direction) ||
      "exit"
  end

  defp exit_to(conn) when is_map(conn) do
    Map.get(conn, "to") ||
      Map.get(conn, :to) ||
      Map.get(conn, "target_id") ||
      Map.get(conn, :target_id) ||
      "?"
  end

  defp hp_percent(row) do
    hp = to_num(hp_of(row))
    max = to_num(max_hp_of(row))

    if max > 0 do
      trunc(hp / max * 100)
    else
      0
    end
  end

  defp to_num(n) when is_integer(n), do: n
  defp to_num(_), do: 0

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
