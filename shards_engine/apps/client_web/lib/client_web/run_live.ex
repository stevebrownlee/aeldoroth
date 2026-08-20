defmodule ClientWeb.RunLive do
  @moduledoc """
  Player seat over the wire protocol (UX spec §4): seat lobby when no PC is
  chosen, then a play surface built from the truth-barrier slice — scene
  panel (believed agents as chips, direction-labeled exits as one-click
  moves), typed chronicle with auto-scroll, character + party rail, status
  ribbon, verb palette, prompt-answer mode, and seat auto-rejoin. Every
  play interaction is wire traffic; this module never touches the engine.
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.Run.Session

  @verb_palette [
    {"Look", "look "},
    {"Search", "search the "},
    {"Listen", "listen "},
    {"Attack", "attack "},
    {"Talk", "say "},
    {"Take", "take "},
    {"Use", "use "},
    {"Ready", "ready "},
    {"Wait", "wait"}
  ]

  @impl true
  def mount(%{"run_id" => run_id} = params, _session, socket) do
    pc = params["pc_id"] || params["pc"]

    socket =
      assign(socket,
        run_id: run_id,
        pc: pc,
        roster: nil,
        conn: nil,
        slice: nil,
        dossier: nil,
        prompt: nil,
        paused: false,
        tick: 0,
        compose: "",
        hint_shown: false
      )
      |> stream(:log, [])

    if connected?(socket) && pc && wire_url() do
      case Conn.start_link(wire_url(),
             run_id: run_id,
             character_id: pc,
             parent: self()
           ) do
        {:ok, pid} ->
          {:ok, monitor_conn(assign(socket, conn: pid))}

        {:error, reason} ->
          {:ok, put_flash(socket, :error, "wire connection failed: #{inspect(reason)}")}
      end
    else
      {:ok, assign(socket, roster: Session.roster(run_id))}
    end
  end

  # Forms -------------------------------------------------------------------

  @impl true
  def handle_event("declare", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    event = if socket.assigns.prompt, do: "answer", else: "declare_intent"
    :ok = Conn.send_event(conn, event, %{"text" => text})
    {:noreply, assign(socket, prompt: nil, compose: "", hint_shown: true)}
  end

  def handle_event("ooc", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    :ok = Conn.send_event(conn, "ooc", %{"text" => text})
    {:noreply, socket}
  end

  # Verb palette / believed-agent chips scaffold into the compose box —
  # grammar teaching (spec §4): Attack chip + name chip = "attack giant rat".
  def handle_event("scaffold", %{"text" => add}, socket) do
    {:noreply, update(socket, :compose, &(&1 <> add))}
  end

  # Exit chips declare the bare direction label immediately.
  def handle_event("go", %{"dir" => dir}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and dir != "" do
    :ok = Conn.send_event(conn, "declare_intent", %{"text" => dir})
    {:noreply, assign(socket, compose: "", hint_shown: true)}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages -----------------------------------------------------------

  # Join reply: seat claimed, here is the truth-barrier slice.
  @impl true
  def handle_info({:chan_reply, _ref, :ok, %{"state" => slice} = reply}, socket) do
    {:noreply,
     assign(socket,
       slice: slice,
       dossier: reply["dossier"],
       roster: nil,
       paused: reply["paused"] == true
     )}
  end

  # Error replies (unknown event, paused, no_run, claim races).
  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, put_flash(socket, :error, "referee: #{reason}")}
  end

  def handle_info({:chan, _topic, "perception", %{"text" => text, "tick" => tick}}, socket) do
    {:noreply,
     socket
     |> stream_insert(:log, log_row("perception", "[tick #{tick}] #{text}"))
     |> assign(tick: max(tick, socket.assigns.tick))}
  end

  def handle_info({:chan, _topic, "ooc", %{"agent_id" => id, "text" => text}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("ooc", "#{id}: #{text}"))}
  end

  def handle_info({:chan, _topic, "prompt", %{"question" => question}}, socket) do
    {:noreply, assign(socket, prompt: question)}
  end

  def handle_info({:chan, _topic, "dice", %{"event_payload" => payload}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("dice", render_dice(payload)))}
  end

  def handle_info({:chan, _topic, "state_sync", %{"slice" => slice}}, socket) do
    {:noreply, assign(socket, slice: slice)}
  end

  def handle_info({:chan, _topic, "paused", _payload}, socket) do
    {:noreply, socket |> system_row("The GM pauses the world.") |> assign(paused: true)}
  end

  def handle_info({:chan, _topic, "resumed", _payload}, socket) do
    {:noreply, socket |> system_row("The GM resumes play.") |> assign(paused: false)}
  end

  # Protocol growth never crashes a seat.
  def handle_info({:chan, _topic, _event, _payload}, socket), do: {:noreply, socket}
  def handle_info({:chan_reply, _ref, _status, _payload}, socket), do: {:noreply, socket}

  # Seat auto-rejoin (UX spec §4): the claim is process-owned, so a dropped
  # conn releases it — a fresh Conn re-claims the same PC. The ribbon keeps
  # the disconnected state visible until the rejoin lands.
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %{assigns: %{pc: pc}} = socket)
      when is_binary(pc) do
    Process.send_after(self(), :rejoin, 1_000)
    {:noreply, socket |> system_row("Connection lost — rejoining the seat…") |> assign(conn: nil)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "wire connection lost: #{inspect(reason)}")
     |> assign(conn: nil)}
  end

  def handle_info(:rejoin, %{assigns: %{conn: nil, pc: pc, run_id: run_id}} = socket)
      when is_binary(pc) do
    if url = wire_url() do
      case Conn.start_link(url, run_id: run_id, character_id: pc, parent: self()) do
        {:ok, pid} ->
          {:noreply, monitor_conn(assign(socket, conn: pid)) |> system_row("Seat rejoined.")}

        {:error, _reason} ->
          Process.send_after(self(), :rejoin, 2_500)
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(:rejoin, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Run <%= @run_id %></h1>

    <div :if={@roster} class="picker panel" data-testid="seat-picker">
      <h2>Choose a seat</h2>
      <p class="hint">
        You declare in prose, the referee resolves, dice are open. One seat per player.
      </p>
      <ul class="seat-list">
        <li :for={pc <- @roster} class="seat-card">
          <.link href={"/runs/#{@run_id}/#{pc.id}"} class="seat-claim" data-testid={"claim-#{pc.id}"}>
            <strong><%= pc.name %></strong>
            <span class="hint"><%= pc.id %></span>
          </.link>
        </li>
      </ul>
    </div>

    <div :if={@slice} class="seat" data-testid="seat">
      <div class="ribbon" data-testid="status-ribbon">
        <%= status(@conn, @paused, @prompt, @tick) %>
      </div>

      <h2><%= @slice["agent"]["name"] %></h2>

      <div class="prompt" :if={@prompt} data-testid="prompt">
        <strong>Referee asks:</strong> <%= @prompt %>
      </div>

      <div class="play-grid">
        <div class="play-main">
          <section class="slice panel">
            <h3><%= @slice["place"]["name"] %></h3>
            <p><%= @slice["summary"] %></p>

            <p :if={others(@slice) != []} class="here">
              <strong>Here:</strong>
              <button
                :for={who <- others(@slice)}
                type="button"
                class="chip"
                phx-click="scaffold"
                phx-value-text={who["name"] <> " "}
              ><%= who["name"] %></button>
            </p>

            <p :if={party(@slice) != []} class="here">
              <strong>Party:</strong>
              <span :for={p <- party(@slice)} class="chip-static"><%= p["name"] %></span>
            </p>

            <p :if={@slice["place"]["items"] != []} class="here">
              <strong>Items:</strong>
              <span :for={it <- @slice["place"]["items"]} class="chip-static"><%= it["name"] %></span>
            </p>

            <p class="exits">
              <strong>Exits:</strong>
              <button
                :for={e <- @slice["place"]["exits_labeled"] || []}
                :if={e["dir"] && !e["sealed"]}
                type="button"
                class="chip chip-exit"
                phx-click="go"
                phx-value-dir={e["dir"]}
              ><%= e["dir"] %></button>
              <span
                :for={e <- @slice["place"]["exits_labeled"] || []}
                :if={e["sealed"] or is_nil(e["dir"])}
                class="chip-static"
              ><%= e["dir"] || e["to"] %><%= if e["sealed"], do: " (sealed)" %></span>
            </p>
          </section>

          <section class="log panel">
            <h3>Chronicle</h3>
            <ul id="log" class="log chronicle" phx-hook="ChronicleScroll" phx-update="stream">
              <li :for={{dom_id, row} <- @streams.log} id={dom_id} class={"kind-#{row.kind}"}>
                <%= row.text %>
              </li>
            </ul>
          </section>

          <section class="compose panel">
            <div class="verb-palette" data-testid="verb-palette">
              <button
                :for={{label, scaffold} <- verb_palette()}
                type="button"
                class="chip chip-verb"
                phx-click="scaffold"
                phx-value-text={scaffold}
              ><%= label %></button>
            </div>

            <form id="declare" phx-submit="declare">
              <input
                name="text"
                value={@compose}
                placeholder={if @prompt, do: "your answer", else: "declare intent"}
                disabled={@paused}
              />
              <button type="submit" disabled={@paused}>
                <%= if @prompt, do: "Answer", else: "Declare" %>
              </button>
            </form>

            <p :if={@paused} class="hint">Paused by the GM — the referee will resume play.</p>
            <p :if={!@hint_shown && !@prompt} class="hint"><%= first_run_hint() %></p>

            <form id="ooc" phx-submit="ooc">
              <input name="text" placeholder="table talk" />
              <button type="submit">OOC</button>
            </form>
          </section>
        </div>

        <aside class="rail">
          <section class="sheet panel">
            <h3>Character</h3>
            <%= if sh = @slice["sheet"] do %>
              <p class="hp">
                <strong>HP</strong>
                <span class="hp-numbers"><%= sh["hp"] %><%= if sh["hp_max"], do: " / #{sh["hp_max"]}" %></span>
              </p>
              <div class="hp-bar">
                <div class="hp-fill" style={"width: #{hp_percent(sh)}%"}></div>
              </div>
              <dl class="stats">
                <div><dt>AC</dt><dd><%= sh["ac"] %></dd></div>
                <div><dt>THAC0</dt><dd><%= sh["thac0"] %></dd></div>
                <div><dt>Damage</dt><dd><%= sh["damage"] || "—" %></dd></div>
              </dl>
              <p :if={sh["conditions"] != []} class="conditions">
                <span :for={c <- sh["conditions"]} class="chip-static"><%= c %></span>
              </p>
            <% end %>
          </section>

          <section class="dossier panel" :if={@dossier}>
            <h3>Dossier</h3>
            <pre><%= @dossier %></pre>
          </section>
        </aside>
      </div>
    </div>
    """
  end

  ## Internals

  defp wire_url, do: Application.get_env(:client_web, :wire_url)

  defp monitor_conn(%{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    Process.monitor(conn)
    socket
  end

  defp log_row(kind, text),
    do: %{id: "row-#{kind}-#{System.unique_integer([:positive])}", kind: kind, text: text}

  defp system_row(socket, text), do: stream_insert(socket, :log, log_row("system", text))

  # Other player-owned agents among the believed (truth-barrier-safe party
  # rail, UX spec §4): names only, own seat excluded.
  defp party(slice) do
    me = slice["agent"]["id"]

    slice["believed_agents"]
    |> Enum.filter(&(&1["pc"] == true and &1["id"] != me))
  end

  # Everything believed here except the seated player themselves — the
  # mover perceives their own arrival, but "Here:" reads as who else is here.
  defp others(slice) do
    me = slice["agent"]["id"]
    Enum.reject(slice["believed_agents"], &(&1["id"] == me))
  end

  defp verb_palette, do: @verb_palette

  defp first_run_hint,
    do: ~s(Describe what you do — specifics beat dice. Try: "search the crate" or "north".)

  defp status(nil, _paused?, _prompt?, _tick), do: "disconnected — reconnecting…"
  defp status(_conn, true, _prompt?, _tick), do: "paused by GM"
  defp status(_conn, _paused?, prompt, _tick) when is_binary(prompt), do: "answer needed"
  defp status(_conn, _paused?, _prompt?, tick), do: "connected · tick #{tick} · your move"

  defp hp_percent(%{"hp" => hp, "hp_max" => hp_max})
       when is_number(hp) and is_number(hp_max) and hp_max > 0,
       do: hp |> max(0) |> Kernel.min(hp_max) |> Kernel.*(100) |> Kernel.div(hp_max) |> min(100)

  defp hp_percent(_), do: 100

  # Dice tray rendering (UX spec §4): never inspect/1 at the player.
  defp render_dice(%{"purpose" => purpose} = p) when is_map(p) do
    base =
      case p do
        %{"sides" => sides, "roll" => roll} -> "🎲 #{purpose}: d#{sides} → #{roll}"
        _ -> "🎲 #{purpose}"
      end

    case p do
      %{"hit" => true} -> "#{base} — hit"
      %{"hit" => false} -> "#{base} — miss"
      %{"amount" => amount} -> "#{base} — #{amount} damage"
      _ -> base
    end
  end

  defp render_dice(_), do: "🎲 the referee rolls…"
end
