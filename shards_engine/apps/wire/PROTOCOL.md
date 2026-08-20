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

Reply: `{:ok, %{state: state, dossier: dossier, paused: boolean}}`

- `state` — the PC's actor slice (`Referee.Slice.for_actor/2`): identity, sheet
  (hp/hp_max/ac/thac0/damage/conditions), current place + labeled exits,
  believed agents (with `pc` flags for party-vs-monster), visible items,
  salient beliefs, summary. This is the truth barrier: nothing outside the
  PC's beliefs or perceptions ever appears.
- `dossier` — the most recent pause dossier for this PC, or `null`.
- `paused` — whether the run is currently paused (a seat that joins mid-pause
  learns it from the reply, not from a missed push).

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
| `paused` | `{}` | the GM paused the run (declarations are refused until resume) |
| `resumed` | `{}` | the GM resumed the run |

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

Reply:

```json
{
  "tick": n,
  "boundaries": {"<boundary_id>": {"state": "dormant|awake", "last_trigger_tick": n|null}},
  "dungeon": {
    "places": [
      {
        "id": "place_id",
        "name": "Place Name",
        "tags": [...],
        "connections": [
          {"to": "...", "label": "...", "sealed": false}
        ],
        "items": [
          {"id": "healing_potion", "name": "Potion of Healing", "value_gp": 50, "is_hidden": true, "holder_id": null}
        ],
        "hazards": [
          {"id": "alarm_tripwire", "kind": "alarm", "dc": 12, "triggered": false, "damage": "0"}
        ],
        "agents": [
          {
            "id": "agent_id",
            "name": "Agent Name",
            "kind": "pc|monster|npc",
            "hp": n,
            "hp_max": n,
            "conditions": [...]
          }
        ]
      }
    ]
  },
  "spend": {"by_class": {...}, "by_agent": {...}},
  "tail": [Ledger.Event.t],   // last 50, raw — all classes
  "awaiting": [
    {
      "id": "pc_thistle", "name": "Thistle", "seated": true,
      "last_intent": {"text": "go east", "tick": 3},   // or null
      "prompt": {"question": "which one do you mean?", "tick": 3}  // or null
    }
  ]
}

`dungeon` is the referee console view: every place, its labeled exits (with
`sealed` true for locked/password-blocked passages), the items and hazards
present, and all resident agents with identity, HP, and conditions. It is
derived from the same world snapshot as `boundaries`.
```

`awaiting` is the flow board: one row per living PC — who holds the floor
(`last_intent`), who owes the table an answer (`prompt` is an outstanding
clarification with no newer narration for that PC), and whether their seat is
connected (`seated`).

### Client → server

| Event | Payload | Reply |
|---|---|---|
| `pause` | | `{:ok, %{"dossiers": {pc_id: text}}}` · `{:error, %{"reason": "already_paused"}}` |
| `resume` | | `{:ok, %{"resumed": true}}` (distinct from heartbeat acks `{}`) · `{:error, %{"reason": "not_paused"}}` |
| `spend` | | `{:ok, %{"spend": report}}` |
| `gm_chat` | `{"text": "..."}` | `:ok` — ledgered as `:ooc`, broadcast to `spectate:*` and `run:*` topics |

### Server → client

| Event | Payload |
|---|---|
| `ledger_tail` | `{"events": [Ledger.Event.t]}` — every writer tail, unfiltered |
| `state_sync` | `{"tick": n, "boundaries": {...}, "dungeon": {...}}` |
| `ooc` | `{"agent_id": "...", "text": "..."}` — any OOC talk on the run, including GM chat |
| `awaiting` | `{"pcs": [rows]}` — same rows as the join snapshot; pushed only when a row changes (intent declared, prompt raised/answered, seat claimed/released) |

Spectators see all event classes (including `:llm` audits) — observability is
the point; dice visibility is the preference stack's call, not the wire's.

## Determinism note

Everything a client receives is derived from the append-only ledger
(`seq`-ordered). The same YAML + seed + LLM scripts produce byte-identical
ledgers whether play flows through a live session or the pure pipeline — the
wire is a view, never a source of truth.
