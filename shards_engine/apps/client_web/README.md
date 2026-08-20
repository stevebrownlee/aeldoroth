# ClientWeb — web play surface

Phoenix LiveView 1.2 app serving the browser play experience for Shards Engine
adventures. Vendored assets only — no esbuild, no Node toolchain.

## Surfaces

| Route | Surface | Trust |
|---|---|---|
| `/` | **HomeLive** — lobby: scenario card, four-seat roster builder, seed/YAML advanced disclosure, active-runs table | Trusted (calls `Referee.Run.Session` to create runs) |
| `/runs/:run_id/:pc_id` | **RunLive** — player seat: scene panel, exit chips, verb palette, chronicle, character rail, declare/OOC boxes | Untrusted wire client (`run:<id>` channel, exclusive PC claim) |
| `/runs/:run_id/gm` | **SpectateLive** — GM console: flow board, advance / advance-until-input / pause / resume / spend levers, boundary states, live ledger preview | Trusted for advance levers (direct `Session` calls); views ride the `spectate:<id>` channel |

The trust split is deliberate: seats hold zero authority — every declaration
re-enters the referee pipeline over the wire (`apps/wire`, see
`apps/wire/PROTOCOL.md`) — while the console and lobby are referee surfaces.

## Running

```sh
cd shards_engine
MIX_ENV=dev mix run --no-halt scripts/web_server.exs   # http://localhost:4000
```

Default roster prefills Thistle and Bramble from *The Ruined Tower*; blank seat
rows drop on submit. Player seats auto-rejoin after a dropped connection.

## Tests

```sh
cd shards_engine/apps/client_web
mix test
```

Surface tests boot a real Bandit endpoint and drive each LiveView through a
real `ClientTUI.Conn` wire connection (`async: false` — the endpoint publishes
a global `:wire_url`).
