defmodule EngineCore.Ledger.Event do
  @enforce_keys [:seq, :tick, :class, :payload]
  defstruct [:seq, :tick, :class, :payload]
  @type t :: %__MODULE__{}
end

defmodule EngineCore.Ledger do
  @moduledoc """
  Append-only event ledger (engrams pattern 10). Single writer process.
  Events are pure data: seq (monotonic), tick (game clock), class, payload.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def append(ledger, class, tick, payload),
    do: GenServer.call(ledger, {:append, class, tick, payload})

  def events(ledger), do: GenServer.call(ledger, :events)
  def clear(ledger), do: GenServer.call(ledger, :clear)

  @impl true
  def init(:ok), do: {:ok, %{events: [], seq: 0}}

  @impl true
  def handle_call({:append, class, tick, payload}, _from, %{events: ev, seq: s} = st) do
    event = struct!(EngineCore.Ledger.Event, seq: s + 1, tick: tick, class: class, payload: payload)
    {:reply, event, %{st | events: [event | ev], seq: s + 1}}
  end

  def handle_call(:events, _from, %{events: ev} = st), do: {:reply, Enum.reverse(ev), st}
  def handle_call(:clear, _from, st), do: {:reply, :ok, %{st | events: [], seq: 0}}
end
