# Protocol smoke (plan 5 Task 10): boots the channels endpoint, starts a live
# Session from The Ruined Tower YAML with template-only routing (no LLM keys —
# interpret falls back to Grammar, narrate to templates), connects one
# reference terminal client over a real WebSocket, drives a declare + advance,
# and prints every server push and the resulting ledger tail.
#
# Run from apps/client_tui:
#
#     mix run ../../scripts/protocol_smoke.exs [--port 4000]
#
# Journals/checkpoints land in shards_engine/runs/ (gitignored).

alias ClientTUI.Conn
alias EngineCore.RunSup
alias EngineCore.Ledger.Writer
alias Referee.Run.Session

port =
  case System.argv() do
    ["--port", p | _] -> String.to_integer(p)
    _ -> 4000
  end

{:ok, _bandit} = Bandit.start_link(plug: Wire.Endpoint, scheme: :http, port: port)
pcs = [
  %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
    int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}
]
yaml = Path.expand("../../the-ruined-tower/ruined_tower.yaml", __DIR__)
runs_dir = Path.expand("../runs", __DIR__)
id = "smoke_#{System.system_time(:millisecond)}"

{:ok, _session} = Session.start_link(id, yaml, 42, pcs, data_dir: runs_dir)
{:ok, conn} = Conn.start_link("ws://127.0.0.1:#{port}", run_id: id, character_id: "pc_thistle")

# Wait for the channel join to be acked, then declare and advance one tick.
receive do
  {:chan_reply, _ref, :ok, %{"state" => _}} -> IO.puts("[join] ok")
after
  5_000 -> raise "join not acked"
end

:ok = Conn.send_event(conn, "declare_intent", %{"text" => "go east"})

receive do
  {:chan_reply, _ref, :ok, _} -> IO.puts("[declare] ok")
after
  5_000 -> raise "declare not acked"
end

defmodule Smoke do
  def collect_pushes(quiet_ms) do
    receive do
      {:chan, _topic, event, payload} ->
        IO.puts("[push:#{event}] #{inspect(payload, limit: :infinity)}")
        collect_pushes(quiet_ms)
    after
      quiet_ms -> :ok
    end
  end
end

{:ok, _} = Session.advance(id)

# Print every server push the client receives, then the ledger tail.
Smoke.collect_pushes(300)

events = Writer.events(id)
IO.puts("[ledger] #{length(events)} events; last 5:")
events |> Enum.take(-5) |> Enum.each(&IO.puts("  seq #{&1.seq} tick #{&1.tick} #{&1.class}"))

Session.stop(id)
RunSup.stop_run(id)
IO.puts("[smoke] done")
