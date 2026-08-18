# EngineCore

Deterministic engine core for the Shards agent engine (Plan 1). Loads adventure
YAML into `%World{}`, applies rules (movement, combat, morale, saves) as pure
functions that emit append-only ledger events, and replays any event stream
through `EngineCore.Fold` to reconstruct identical world state.

Acceptance proof: `EngineCore.Scenario.party_vs_warband/2` runs scripted
party-vs-warband combat on `the-ruined-tower.yaml`; the golden replay test
pins byte-identical reruns and `fold(events, w0) == final_world`.

```elixir
{:ok, world} = EngineCore.Loader.load("path/to/adventure.yaml")
```

Run the suite from the umbrella root:

```sh
cd shards_engine && mix test
```
