# client_tui — terminal reference client

The thin terminal client for the line-JSON WebSocket protocol
(`apps/wire/PROTOCOL.md` — decision 24/37). Untrusted: every input re-enters
the referee pipeline server-side.

## Modules

- `ClientTUI.Channel` — pure Phoenix Channels line-JSON codec
  (encode join/event/heartbeat, decode reply/push frames)
- `ClientTUI.Conn` — WebSockex connection: auto `phx_join` on connect,
  heartbeats every `heartbeat_every` ms, forwards server pushes to the
  parent as `{:chan, topic, event, payload}`
- `ClientTUI.CLI` — REPL

## Run

```sh
mix run -e "ClientTUI.CLI.main(System.argv)" -- \
  --url http://localhost:4000 --run my_run --character pc_thistle
# spectate:
mix run -e "ClientTUI.CLI.main(System.argv)" -- \
  --url http://localhost:4000 --run my_run --spectate
```

REPL: a plain line is a `declare_intent`; commands `/ooc text`, `/sheet`,
`/pause`, `/resume`, `/spend`, `/quit`. Pushes print prefixed
(`[perception]`, `[prompt]`, `[dice]`, `[state]`, `[ooc]`, `[ledger]`).
