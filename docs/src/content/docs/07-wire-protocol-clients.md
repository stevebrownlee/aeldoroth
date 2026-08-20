---
title: "Wire Protocol & Clients"
description: "The public Phoenix Channels wire protocol, topic semantics, and the TUI and Web client architectures."
order: 7
category: "Protocol & Tooling"
tags: ["wire", "phoenix-channels", "client-tui", "client-web", "websocket"]
---

# Wire Protocol & Clients

The `wire` application in `apps/wire` is the public boundary of The Shattered Kingdoms engine. Everything a player, GM, or spectator sees travels over a single protocol: **Phoenix Channels vsn 2.0.0 line-JSON** over a WebSocket at `/socket/websocket`. The engine itself does not expose an HTTP API for run actions; the wire is the contract.

This chapter documents the protocol envelope, the two channel topics (`run:<id>` and `spectate:<id>`), the two reference client implementations, and the determinism rule that separates the wire from the engine's source of truth.

## Public wire contract

### Endpoint

```elixir
# apps/wire/lib/wire/endpoint.ex
socket "/socket", Wire.Socket,
  websocket: [timeout: 45_000, check_origin: false],
  longpoll: false
```

The wire endpoint is deliberately minimal: one WebSocket path, no router, no plugs, no HTML. `check_origin: false` is intentional; the reference client is a terminal application, not a browser, and authentication is per-run via connect parameters.

### Phoenix Channels vsn 2.0.0 line-JSON envelope

Every message on the wire is a single line of JSON representing the Phoenix V2 array envelope:

```json
[join_ref, ref, topic, event, payload]
```

The topic appears before the event; this matches `Phoenix.Socket.V2.JSONSerializer`. Client code decodes it as follows (from `apps/client_tui/lib/client_tui/channel.ex`):

```elixir
@spec decode(String.t()) ::
          {:ok, {:reply, String.t(), :ok | :error, map()}}
          | {:ok, {:push, String.t(), String.t(), map()}}
          | {:error, :malformed}

def decode(text) when is_binary(text) do
  with {:ok, [_, ref, _topic, "phx_reply", body]} when is_map(body) <- Jason.decode(text),
       {:ok, status} <- status(body["status"]),
       {:ok, response} when is_map(response) <- ok(body["response"]) do
    {:ok, {:reply, ref, status, response}}
  else
    {:ok, [_, _ref, topic, event, payload]} when is_map(payload) and event != "phx_reply" ->
      {:ok, {:push, topic, event, payload}}

    _ ->
      {:ok, {:error, :malformed}}
  end
end
```

Notes:

- `join_ref` is unused in the current client; it is encoded as `nil` for outbound pushes.
- `ref` is a client-generated string used to correlate `phx_reply` frames with the original push.
- `phx_reply` is treated as a reply tuple; every other event is an unsolicited server push.
- Malformed frames are silently dropped by the TUI decoder.

A typical player interaction looks like this on the wire:

```json
// client → server: join run:castle-dracolich as character "glimmer"
[null, "1", "run:castle-dracolich", "phx_join", {"character_id": "glimmer"}]

// server → client: join reply with the truth-barrier slice
[null, "1", "run:castle-dracolich", "phx_reply",
  {"status": "ok", "response": {"state": {...}, "dossier": {...}}}]

// client → server: declare intent
[null, "2", "run:castle-dracolich", "declare_intent", {"text": "I inspect the altar."}]

// server → client: narration pushed only to the acting PC
[null, null, "run:castle-dracolich", "perception",
  {"text": "The altar is warm to the touch.", "tick": 17}]
```

## Channel topics

The wire exposes two channel patterns from `apps/wire/lib/wire/socket.ex`:

```elixir
channel "run:*", Wire.RunChannel
channel "spectate:*", Wire.SpectateChannel
```

Connection parameters are:

- `run_id` (required) — the run scope.
- `character_id` (optional) — if present, the socket assumes role `:pc`; otherwise `:spectate`.

```elixir
def connect(%{"run_id" => run_id} = params, socket, _connect_info)
    when is_binary(run_id) and run_id != "" do
  character_id =
    case params["character_id"] do
      char_id when is_binary(char_id) and char_id != "" -> char_id
      _ -> nil
    end

  role = if character_id, do: :pc, else: :spectate
  {:ok, assign(socket, run_id: run_id, character_id: character_id, role: role)}
end
```

### `run:<id>` — per-PC exclusive claim surface

`Wire.RunChannel` is the player seat. It enforces two rules at join time:

1. The socket must have role `:pc`.
2. The requested `character_id` must not already be claimed for that run.

Claims are managed by `Wire.Claims`, which uses a `Registry` keyed by `{run_id, pc_id}`. The claim is owned by the channel process, so disconnect, crash, or explicit channel termination releases it. Release is idempotent.

```elixir
@registry Wire.ClaimsReg

def claim(run_id, pc_id) do
  case Registry.register(@registry, {run_id, pc_id}, self()) do
    {:ok, _owner} -> :ok
    {:error, {:already_registered, pid}} -> {:error, {:already_claimed, pid}}
  end
end
```

A successful join replies with the per-PC **truth barrier slice**: only information the character is allowed to see, produced by `Referee.Slice.for_actor/2`. The player cannot observe the full world state; the wire enforces the barrier at the channel boundary.

Player events handled by `run:*`:

| Event           | Payload                | Semantics |
| --------------- | ---------------------- | --------- |
| `declare_intent`| `{"text": "..."}`      | Player action for the referee. |
| `answer`        | `{"text": "..."}`      | Alias for `declare_intent` (clarification response). |
| `ooc`           | `{"text": "..."}`      | Out-of-character table talk; broadcast to all seats. |
| `sheet`         | `{"update": {...}}`    | v1: accepted but ignored; replies with current slice. |

Server pushes to a player:

| Event        | Payload                                      | Semantics |
| ------------ | -------------------------------------------- | --------- |
| `perception` | `{"text": "...", "tick": n}`                 | Narration for this PC only. |
| `prompt`     | `{"question": "..."}`                        | Interpreter clarification request. |
| `dice`       | `{"event_payload": {...}}`                   | Dice task for this PC (if visibility is open). |
| `ooc`        | `{"agent_id": "...", "text": "..."}`        | OOC message from another seat. |
| `state_sync` | `{"slice": {...}}`                           | Updated truth-barrier slice. |

### `spectate:<id>` — GM observability

`Wire.SpectateChannel` is the trusted observer seat. It requires role `:spectate` and replies with a full snapshot of engine truth:

```elixir
snapshot = %{
  tick: state.tick,
  boundaries: JSONSafe.to_json(Server.boundaries(run_id)),
  spend: Spend.report(Writer.events(run_id)),
  tail: Writer.events(run_id) |> Enum.take(-@tail_cap) |> JSONSafe.to_json()
}
```

The tail is unfiltered: spectators see all ledger event classes. Dice visibility is the referee's preference-stack decision, not the wire's; the spectate channel simply streams whatever the engine emits.

Spectator events:

| Event    | Payload | Semantics |
| -------- | ------- | --------- |
| `pause`  | `{}`    | Pauses the run; reply carries dossiers. |
| `resume` | `{}`    | Resumes the run; reply is `{"resumed": true}`. |
| `spend`  | `{}`    | Returns the current spend report. |

The `resumed: true` field is deliberately distinctive so that empty heartbeat acks (`{}`) never masquerade as a resume confirmation.

Server pushes to a spectator:

| Event         | Payload                            | Semantics |
| ------------- | ---------------------------------- | --------- |
| `ledger_tail` | `{"events": [...]}`                | New ledger events appended to the tail. |
| `state_sync`  | `{"tick": n, "boundaries": [...]}` | Current tick and boundary states. |

## Client architectures

### `client_tui`: WebSockex terminal REPL

`apps/client_tui` is the reference terminal client. It uses `WebSockex` to open a single WebSocket to the wire endpoint and speaks the Phoenix Channels line-JSON protocol directly. The module `ClientTUI.Conn` owns the connection lifecycle, heartbeat, ref generation, and auto-join.

```elixir
defmodule ClientTUI.Conn do
  use WebSockex

  defstruct [:parent, :topic, :character_id, :heartbeat_every, :hb_ref, next_ref: 0]

  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(url, opts) do
    WebSockex.start_link(url, __MODULE__, struct!(__MODULE__, opts))
  end
end
```

Key design points:

- `handle_connect/2` does not send the join immediately; it schedules a `:send_join` self-message. This works around WebSockex 0.4's rule that frames can only be sent from frame/info/cast callbacks.
- A periodic `:heartbeat` keeps the Phoenix connection alive.
- `send_event/3` casts to the connection process and encodes via `ClientTUI.Channel.encode/4`.
- The `join_payload` is `{}` for spectators and `{"character_id" => id}` for PCs.

The TUI demonstrates that no Phoenix client-side library is required; the protocol is the contract.

### `client_web`: Phoenix LiveView 1.2 dual-socket endpoint

`apps/client_web` is the web client. It uses Phoenix LiveView 1.2 and exposes **two sockets on one endpoint**, each with a different trust zone:

```elixir
# apps/client_web/lib/client_web/endpoint.ex
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [session: @session_options]]

socket "/socket", Wire.Socket,
  websocket: [timeout: 45_000, check_origin: false],
  longpoll: false
```

- `/live` is the LiveView socket for UI surfaces. It carries browser sessions and cookies.
- `/socket` re-serves `Wire.Socket` verbatim, so player LiveViews connect to the engine wire through a loopback WebSocket client (`ClientTUI.Conn`).

This means the same endpoint serves both the visual UI and the engine wire protocol. Player LiveViews never call engine modules directly; they send events over the wire and receive pushes back.

LiveViews dispatch wire traffic through `ClientTUI.Conn.send_event/3`:

```elixir
def handle_event("declare", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
    when is_pid(conn) and text != "" do
  ClientTUI.Conn.send_event(conn, "declare_intent", %{"text" => text})
  {:noreply, socket}
end
```

Incoming wire pushes arrive as `{:chan, topic, event, payload}` messages, while replies arrive as `{:chan_reply, ref, status, payload}`. Each LiveView handles the subset of events relevant to its surface:

- `ClientWeb.RunLive` handles player-seat pushes: `perception`, `prompt`, `dice`, `ooc`, `state_sync`.
- `ClientWeb.SpectateLive` handles GM-console pushes: `ledger_tail`, `state_sync`, plus replies for `pause`, `resume`, and `spend`.

## Determinism note: wire is a view, never a source of truth

The wire carries **views** of engine state, not authoritative state. The source of truth is always the ledger in `EngineCore.Ledger.Writer` and the referee run session in `Referee.Run.Session`. The wire:

- subscribes to ledger events,
- slices world state for the requesting actor,
- forwards GM commands to the referee,
- and never invents ticks, boundaries, or spend figures on its own.

If a client reconnects, the join reply rebuilds the view from the current engine state; any messages missed during the disconnect are simply absent from that client's local log, not lost from the run. Replaying the ledger reconstructs the full, canonical history.

This separation has two practical consequences:

1. **Multiple clients can coexist.** A player can use the TUI while another uses the web seat, because both receive the same truth-barrier slice derived from the same engine state.
2. **GM authority remains on the engine side.** `advance` is not a wire event; it is called directly by `ClientWeb.SpectateLive` into `Referee.Run.Session` because the GM console is a trusted engine surface, not a player surface.

## Summary

- The wire protocol is **Phoenix Channels vsn 2.0.0 line-JSON** over `/socket/websocket`.
- The envelope is `[join_ref, ref, topic, event, payload]`.
- `run:<id>` is the per-PC exclusive-claim surface with a truth barrier.
- `spectate:<id>` is the unfiltered GM observability surface with pause/resume/spend controls.
- `client_tui` is a WebSockex terminal REPL speaking the protocol directly.
- `client_web` is a Phoenix LiveView 1.2 endpoint with two sockets: `/live` for UI and `/socket` for the loopback wire client.
- The wire is a **view**; the ledger and referee session remain the sole source of truth.
