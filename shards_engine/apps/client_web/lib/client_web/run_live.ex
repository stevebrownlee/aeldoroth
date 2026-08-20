defmodule ClientWeb.RunLive do
  @moduledoc """
  Player seat over the wire protocol (plan 7 Task 4): seat picker from
  `Session.roster` (pre-seat only — GM-console introspection), then a real
  `ClientTUI.Conn` per joined seat. Every play interaction is wire traffic;
  this module never touches the engine directly.
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.Run.Session

  @impl true
  def mount(%{"run_id" => run_id} = params, _session, socket) do
    socket =
      assign(socket,
        run_id: run_id,
        pc: params["pc"],
        roster: nil,
        conn: nil,
        slice: nil,
        dossier: nil,
        prompt: nil
      )
      |> stream(:log, [])

    if connected?(socket) && socket.assigns.pc && wire_url() do
      case Conn.start_link(wire_url(),
             run_id: run_id,
             character_id: socket.assigns.pc,
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
    {:noreply, assign(socket, prompt: nil)}
  end

  def handle_event("ooc", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    :ok = Conn.send_event(conn, "ooc", %{"text" => text})
    {:noreply, socket}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages -----------------------------------------------------------

  # Join reply: seat claimed, here is the truth-barrier slice.
  def handle_info({:chan_reply, _ref, :ok, %{"state" => slice} = reply}, socket) do
    {:noreply, assign(socket, slice: slice, dossier: reply["dossier"], roster: nil)}
  end

  # Error replies (unknown event, paused, no_run, claim races).
  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, put_flash(socket, :error, "referee: #{reason}")}
  end

  def handle_info({:chan, _topic, "perception", %{"text" => text, "tick" => tick}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("perception", "[tick #{tick}] #{text}"))}
  end

  def handle_info({:chan, _topic, "ooc", %{"agent_id" => id, "text" => text}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("ooc", "#{id}: #{text}"))}
  end

  def handle_info({:chan, _topic, "prompt", %{"question" => question}}, socket) do
    {:noreply, assign(socket, prompt: question)}
  end

  def handle_info({:chan, _topic, "dice", %{"event_payload" => payload}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("dice", inspect(payload)))}
  end

  def handle_info({:chan, _topic, "state_sync", %{"slice" => slice}}, socket) do
    {:noreply, assign(socket, slice: slice)}
  end

  # Protocol growth never crashes a seat.
  def handle_info({:chan, _topic, _event, _payload}, socket), do: {:noreply, socket}
  def handle_info({:chan_reply, _ref, _status, _payload}, socket), do: {:noreply, socket}

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "wire connection lost: #{inspect(reason)}")
     |> assign(conn: nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Render ------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <h1>Run <%= @run_id %></h1>

    <div :if={@roster} class="picker">
      <h2>Choose a seat</h2>
      <%= for pc <- @roster do %>
        <p><a href={"/runs/#{@run_id}?pc=#{pc.id}"}><%= pc.name %> (<%= pc.id %>)</a></p>
      <% end %>
    </div>

    <div :if={@slice} class="seat" data-testid="seat">
      <h2><%= @slice["agent"]["name"] %></h2>

      <div class="prompt" :if={@prompt}>
        <strong>Referee asks:</strong> <%= @prompt %>
      </div>

      <section class="slice">
        <h3><%= @slice["place"]["name"] %></h3>
        <p><%= @slice["summary"] %></p>
        <p>
          Exits: <%= Enum.map_join(@slice["place"]["exits"] || [], ", ", & &1) %>
        </p>
      </section>

      <section class="dossier" :if={@dossier}>
        <h3>Dossier</h3>
        <pre><%= @dossier["text"] || inspect(@dossier) %></pre>
      </section>

      <section class="log">
        <h3>Log</h3>
        <ul id="log" phx-update="stream">
          <li :for={{dom_id, row} <- @streams.log} id={dom_id} class={row.kind}>
            <%= row.text %>
          </li>
        </ul>
      </section>

      <form id="declare" phx-submit="declare">
        <input name="text" placeholder={if @prompt, do: "your answer", else: "declare intent"} />
        <button type="submit">Declare</button>
      </form>

      <form id="ooc" phx-submit="ooc">
        <input name="text" placeholder="table talk" />
        <button type="submit">OOC</button>
      </form>
    </div>
    """
  end

  ## Internals

  defp wire_url, do: Application.get_env(:client_web, :wire_url)

  defp monitor_conn(%{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    Process.monitor(conn)
    socket
  end

  defp log_row(kind, text), do: %{id: "row-#{kind}-#{System.unique_integer([:positive])}", kind: kind, text: text}
end
