# Shards Wire Protocol — v1 (line-JSON over Phoenix Channels)

The public client contract (spec §11; decisions 24/37). The terminal client is
the reference implementation; a web client later ports onto these same channels
with no protocol change.

## Transport

WebSocket at `/socket/websocket?vsn=2.0.0` (Phoenix Channels, JSON serializer).

Message envelope (vsn 2.0.0) — a JSON **array**, topic before event:

```json
[<join_ref>, <ref>, "<topic>", "<event>", <payload>]
```

- `join_ref` is null on this client's frames; the server echoes its own value.
- Client→server joins and pushes carry a unique `ref`; server replies reuse it.
- Heartbeat: clients send `phx_heartbeat` on topic `phoenix` every ~30s.

## Connect params

```
%{"run_id" => run_id}                      # spectate role
%{"run_id" => run_id, "character_id" => pc_id}  # PC role
```

- Missing/blank `run_id` → connect refused.
- `character_id` must name a PC the run owns (checked at `run:*` join, not
  connect).

## Topics

| Topic | Who | Purpose |
|---|---|---|
| `run:<run_id>` | one connection per claimed PC | the play surface |
| `spectate:<run_id>` | GM / observers | observability only |

Claims are exclusive per `{run_id, pc_id}`: the channel process holds the
claim; the second join for a claimed character is refused with
`{"reason": "character_already_claimed"}`, and disconnect releases it.

---

## `run:<run_id>` — the per-PC surface

### Join

Reply: `{:ok, %{state: state, dossier: dossier}}`

- `state` — the PC's actor slice (`Referee.Slice.for_actor/2`): identity, body,
  current place + exits, believed agents at that place, salient beliefs,
  summary. This is the truth barrier: nothing outside the PC's beliefs or
  perceptions ever appears.
- `dossier` — the most recent pause dossier for this PC, or `null`.

Errors: `{"reason": "unauthorized"}` (no character on socket, character not in
run, session absent) · `{"reason": "character_already_claimed"}`.

### Client → server

| Event | Payload | Reply |
|---|---|---|
| `declare_intent` | `{"text": "..."}` | `{:ok, %{reply: text}}` · `{:error, %{"reason": "paused"}}` |
| `answer` | `{"text": "..."}` | same as `declare_intent` (clarification answer) |
| `ooc` | `{"text": "..."}` | `{:ok, %{"ack": true}}` — ledgered as `:ooc`, broadcast to run topic |
| `sheet` | `{"update": {...}}` | `{:ok, %{"state": slice}}` — v1 read-only; `update` accepted but ignored |

Unknown events reply `{"reason": "unknown_event"}`.

### Server → client

| Event | Payload | Fires when |
|---|---|---|
| `perception` | `{"text": "...", "tick": n}` | a narration for this PC (the only world window) |
| `prompt` | `{"question": "..."}` | referee clarification for this PC |
| `dice` | `{"event_payload": {...}}` | a dice event whose `agent_id` is this PC — only when `dice_visibility` is `"open"` in the referee preference stack |
| `state_sync` | `{"state": slice}` | after each pipeline step |
| `ooc` | `{"agent_id": "...", "text": "..."}` | any OOC talk on the run |

Per-PC isolation is enforced at push: other PCs' narrations, prompts, and dice
never arrive on this channel.

### Never sent on `run:*`

World truth, hidden items, other rooms, monster stats (only perceivable
state), other PCs' prompts, preference internals (spec §11 verbatim).

---

## `spectate:<run_id>` — the GM/observer surface

Join is refused for sockets carrying a `character_id`
(`{"reason": "unauthorized"}`).

### Join

Reply: `{:ok, snapshot}` with

```json
{
  "tick": n,
  "boundaries": {"<boundary_id>": {"state": "dormant|awake", "last_trigger_tick": n|null}},
  "spend": {"by_class": {...}, "by_agent": {...}},
  "tail": [Ledger.Event.t]   // last 50, raw — all classes
}
```

### Client → server

| Event | Reply |
|---|---|
| `pause` | `{:ok, %{"dossiers": {pc_id: text}}}` · `{:error, %{"reason": "already_paused"}}` |
| `resume` | `{:ok, %{"resumed": true}}` (distinct from heartbeat acks `{}`) · `{:error, %{"reason": "not_paused"}}` |
| `spend` | `{:ok, %{"spend": report}}` |

### Server → client

| Event | Payload |
|---|---|
| `ledger_tail` | `{"events": [Ledger.Event.t]}` — every writer tail, unfiltered |
| `state_sync` | `{"tick": n, "boundaries": {...}}` |

Spectators see all event classes (including `:llm` audits) — observability is
the point; dice visibility is the preference stack's call, not the wire's.

## Determinism note

Everything a client receives is derived from the append-only ledger
(`seq`-ordered). The same YAML + seed + LLM scripts produce byte-identical
ledgers whether play flows through a live session or the pure pipeline — the
wire is a view, never a source of truth.
