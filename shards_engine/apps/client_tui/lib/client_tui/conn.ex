defmodule ClientTUI.Conn do
  @moduledoc """
  WebSockex client for one character/spectate connection (plan 5 Task 9).

  On connect it joins the configured topic automatically and arms a heartbeat
  to `phoenix` every `heartbeat_every` ms. Every decoded frame is forwarded to
  the parent as `{:chan, topic, event, payload}` (pushes) or `{:chan_reply,
  ref, status, payload}` (replies).
  """

  use WebSockex

  alias ClientTUI.Channel

  defstruct [:parent, :topic, :character_id, :heartbeat_every, :hb_ref, next_ref: 0]

  @doc """
  Start a connection to `url` (no trailing path). Opts: `run_id` (required),
  `character_id`, `heartbeat_every` (default 30s), `parent` (default `self()`).
  Topic is `run:<run_id>`, or `spectate:<run_id>` with `spectate: true`.
  """
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(url, opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    character_id = Keyword.get(opts, :character_id)
    spectate = Keyword.get(opts, :spectate, false)

    topic =
      cond do
        spectate -> "spectate:#{run_id}"
        true -> "run:#{run_id}"
      end

    st = %__MODULE__{
      parent: Keyword.get(opts, :parent, self()),
      topic: topic,
      character_id: character_id,
      heartbeat_every: Keyword.get(opts, :heartbeat_every, 30_000)
    }

    # Phoenix socket params ride the query string (as in phx.js): the
    # server's Socket.connect/3 reads run_id/character_id from there.
    query =
      [vsn: "2.0.0", run_id: run_id]
      |> Kernel.++(if character_id, do: [character_id: character_id], else: [])
      |> URI.encode_query()

    WebSockex.start_link("#{String.trim_trailing(url, "/")}/socket/websocket?#{query}", __MODULE__, st)
  end

  @doc "Push `event` with `payload` on this connection's topic."
  @spec send_event(pid(), String.t(), map()) :: :ok
  def send_event(pid, event, payload) when is_map(payload) do
    WebSockex.cast(pid, {:send_event, event, payload})
  end

  @doc "Join payload for the role (also what auto-join sends)."
  def join_payload(%__MODULE__{character_id: nil}), do: %{}
  def join_payload(%__MODULE__{character_id: id}), do: %{"character_id" => id}

  ## WebSockex callbacks

  # WebSockex 0.4: handle_connect must return {:ok, state} — frames can only
  # be sent as replies from frame/info/cast callbacks. The join goes out on
  # the first self-message after the upgrade.
  @impl true
  def handle_connect(_conn, %__MODULE__{} = st) do
    send(self(), :send_join)
    {:ok, arm_heartbeat(st)}
  end

  @impl true
  def handle_info(:send_join, %__MODULE__{} = st) do
    {ref, st} = fresh_ref(st)
    join = Channel.encode(st.topic, "phx_join", join_payload(st), ref)
    {:reply, {:text, join}, st}
  end

  def handle_info(:heartbeat, %__MODULE__{} = st) do
    {ref, st} = fresh_ref(st)
    hb = Channel.encode("phoenix", "heartbeat", %{}, ref)
    {:reply, {:text, hb}, arm_heartbeat(st)}
  end

  @impl true
  def handle_cast({:send_event, event, payload}, %__MODULE__{} = st) do
    {ref, st} = fresh_ref(st)
    frame = Channel.encode(st.topic, event, payload, ref)
    {:reply, {:text, frame}, st}
  end

  @impl true
  def handle_frame({:text, text}, %__MODULE__{} = st) do
    case Channel.decode(text) do
      {:ok, {:push, topic, event, payload}} ->
        send(st.parent, {:chan, topic, event, payload})
        {:ok, st}

      {:ok, {:reply, ref, status, payload}} ->
        send(st.parent, {:chan_reply, ref, status, payload})
        {:ok, st}

      {:error, :malformed} ->
        # One bad frame never takes the connection down.
        {:ok, st}
    end
  end

  ## Internals

  defp arm_heartbeat(%__MODULE__{heartbeat_every: ms} = st) do
    ref = Process.send_after(self(), :heartbeat, ms)
    %{st | hb_ref: ref}
  end

  defp fresh_ref(%__MODULE__{next_ref: n} = st) do
    {Integer.to_string(n + 1), %{st | next_ref: n + 1}}
  end
end
