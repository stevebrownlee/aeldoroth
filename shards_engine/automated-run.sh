#!/usr/bin/env bash
# automated-run.sh — run the scripted Ruined Tower crawl without typing Elixir.
#
# Usage (from anywhere; the script finds its own way home):
#   ./automated-run.sh                 # same as: fight 1234
#   ./automated-run.sh fight [seed]    # full battle report for one dice seed
#   ./automated-run.sh cascade [seed]  # alarm cascade scenario + signals/scheduler
#   ./automated-run.sh survey          # 10 different seeds, one-line outcome each
#   ./automated-run.sh referee [seed]   # full referee pipeline: interpret->validate->resolve->narrate
#   ./automated-run.sh inventory       # rooms / monsters / treasure loaded from the YAML
#   ./automated-run.sh all             # everything, in order
#
# Different adventure file?   YAML=path/to/file.yaml ./automated-run.sh fight
set -euo pipefail

cd "$(dirname "$0")"
YAML="${YAML:-../the-ruined-tower/ruined_tower.yaml}"
SEED="${2:-${SEED:-1234}}"
export YAML SEED

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

elixir() {  # reads an Elixir program on stdin, runs it, cleans up
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/automated-run.XXXXXX")
  cat >"$tmp"
  mix run "$tmp"
  rm -f "$tmp"
}

fight() { elixir <<'ELIXIR'
seed = String.to_integer(System.get_env("SEED"))
yaml = System.get_env("YAML")
r = EngineCore.Scenario.party_vs_warband(yaml, seed)
names = Map.new(r.final_world.agents, fn {id, a} -> {id, a.name} end)
rooms = Map.new(r.final_world.places, fn {id, p} -> {id, p.name} end)
nm = fn id -> Map.get(names, id, to_string(id)) end
IO.puts("=== THE RUINED TOWER — scripted crawl, dice seed #{seed} ===")
for e <- r.ledger, e.class == :world do
  case e.payload do
    %{kind: :move, agent_id: a, to: room} -> IO.puts("[t#{e.tick}] #{nm.(a)} moves to #{Map.get(rooms, room, room)}")
    %{kind: :damage, target_id: t, amount: n} -> IO.puts("[t#{e.tick}] #{nm.(t)} takes #{n} damage")
    %{kind: :death, agent_id: a} -> IO.puts("[t#{e.tick}] #{nm.(a)} DIES")
    _ -> :ok
  end
end
agents = Map.values(r.final_world.agents)
{pcs, mons} = Enum.split_with(agents, &String.starts_with?(&1.id, "pc"))
IO.puts("=== OUTCOME ===")
IO.puts("Party: #{Enum.count(pcs, & &1.body.hp > 0)}/4 survived" <> (for a <- pcs, a.body.hp > 0, do: " (#{a.name} #{a.body.hp}hp in #{Map.get(rooms, a.place_id)})", into: ""))
for m <- mons, m.body.hp > 0, do: IO.puts("Still standing: #{m.name} (#{m.body.hp}hp) in #{Map.get(rooms, m.place_id)}")
IO.puts("Total casualties: #{Enum.count(agents, & &1.body.hp <= 0)}")
ELIXIR
}

cascade() { elixir <<'ELIXIR'
seed = String.to_integer(System.get_env("SEED"))
yaml = System.get_env("YAML")
r = EngineCore.Scenario.alarm_cascade(yaml, seed)
kinds = Enum.frequencies(Enum.map(r.ledger, &Map.get(&1.payload, :kind)))
IO.puts("=== ALARM CASCADE — seed #{seed} ===")
IO.inspect(kinds, label: "event kinds")
IO.puts("final tick: #{r.final_world.tick}")
IO.puts("guard zone: #{r.final_world.boundaries["guard_room_zone"].state}")
IO.puts("wolf pack:  #{r.final_world.boundaries["wolf_pack"].state} (dormancy proof)")
ELIXIR
}

survey() { elixir <<'ELIXIR'
yaml = System.get_env("YAML")
IO.puts("=== DIFFICULTY SURVEY — same dungeon, 10 different dice seeds ===")
for seed <- [1, 7, 42, 99, 123, 555, 1234, 2026, 31337, 77777] do
  r = EngineCore.Scenario.party_vs_warband(yaml, seed)
  agents = Map.values(r.final_world.agents)
  {pcs, monsters} = Enum.split_with(agents, &String.starts_with?(&1.id, "pc"))
  p_alive = Enum.count(pcs, & &1.body.hp > 0)
  m_alive = Enum.count(monsters, & &1.body.hp > 0)
  hp_left = pcs |> Enum.filter(&(&1.body.hp > 0)) |> Enum.map(& &1.body.hp) |> Enum.join("/")
  verdict = cond do
    p_alive == 0 -> "TOTAL PARTY KILL"
    p_alive < 4 and m_alive > 0 -> "PYRRHIC — fight unfinished"
    m_alive == 0 -> "TOWER CLEARED"
    true -> "party withdrew?"
  end
  IO.puts("seed #{seed}: party #{p_alive}/4 alive (hp #{hp_left}), monsters #{m_alive}/12 alive  ->  #{verdict}")
end
ELIXIR
}

inventory() { elixir <<'ELIXIR'
yaml = System.get_env("YAML")
{:ok, w} = EngineCore.Loader.load(yaml)
IO.puts("== ROOMS (#{map_size(w.places)}) ==")
w.places |> Enum.sort() |> Enum.each(fn {id, p} -> IO.puts("  #{p.name}  [#{id}]") end)
IO.puts("== MONSTERS & NPCs (#{map_size(w.agents)}) ==")
w.agents |> Enum.sort_by(fn {_, a} -> a.place_id end) |> Enum.each(fn {_, a} ->
  IO.puts("  #{a.name} — #{a.body.hp} hp, in #{a.place_id}") end)
IO.puts("== TREASURE (#{map_size(w.items)}) ==")
w.items |> Enum.sort() |> Enum.each(fn {_, i} -> IO.puts("  #{i.name} (#{i.value_gp} gp)") end)
ELIXIR
}

referee() { elixir <<'ELIXIR'
seed = String.to_integer(System.get_env("SEED"))
yaml = System.get_env("YAML")
alias LLMGateway.Adapters.Scripted
alias Referee.Run

interpret = [
  ~s({"verb":"shout","target_id":null,"params":{"message":"HELLO?"},"assumptions":[]}),
  # garbage x2: "attack the goblin guard" falls back to grammar -> ambiguity ->
  # clarify question (no narrate consumption on a clarify)
  "garbage {",
  "garbage {",
  # garbage x2: "strike goblin guard 1" falls back to grammar -> unique match ->
  # stale belief corrected, swing spent
  "garbage {",
  "garbage {",
  ~s({"verb":"move","target_id":null,"params":{"direction":"north"},"assumptions":[]}),
  ~s({"verb":"wait","target_id":null,"params":{},"assumptions":[]})
]
# One narrate response only: the shout is LLM-narrated; the queue then runs
# dry and later action narration falls back to engine templates (diegetic).
scripts = %{interpret: interpret, narrate: ["You cup your hands and bellow \"HELLO?\" into the gloom; somewhere in the dark, claws go still."], salt: 99}
pcs = [
  %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall", int: 13, ac: 5, hd: 1, hp: 7, thac0: 20, damage: "1d8"},
  %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall", int: 9, ac: 6, hd: 1, hp: 6, thac0: 20, damage: "1d6"}
]
{:ok, run} = Run.new(yaml, seed, pcs, routing: %{interpret: %{adapter: Scripted, scripts: scripts}, narrate: %{adapter: Scripted, scripts: scripts}})

# Seed two stale beliefs (both guards actually stand in guard_room): "attack
# the goblin guard" ties -> clarify; "strike goblin guard 1" resolves uniquely.
belief = %{count: 1, last_tick: 0, last_fidelity: 3, seen: false, salience: 0.7}
run =
  Enum.reduce(["goblin_guard_1", "goblin_guard_2"], run, fn gid, acc ->
    pc = acc.world.agents["pc_thistle"]
    here = Map.put(pc.beliefs["entry_hall"] || %{}, gid, belief)
    pc2 = %{pc | beliefs: Map.put(pc.beliefs, "entry_hall", here)}
    %{acc | world: %{acc.world | agents: Map.put(acc.world.agents, "pc_thistle", pc2)}}
  end)

IO.puts("=== REFEREE PIPELINE — tower YAML, seed #{seed}, scripted LLM queues ===")
run =
  Enum.reduce(["I shout HELLO?", "I attack the goblin guard", "I strike goblin guard 1", "I head north", "I wait"], run, fn utterance, run ->
    case Run.declare(run, "pc_thistle", utterance) do
      {:ok, text, run2} -> IO.puts("  > #{utterance}\n    #{text}"); run2
      {:stall, msg, run2} -> IO.puts("  > #{utterance}\n    [#{msg}]"); run2
    end
  end)

{:ok, narrations, run} = Run.advance(run)
IO.puts("=== WORLD TIME PASSES (tick #{run.world.tick}) ===")
narrations |> Enum.each(fn {pc_id, text} -> IO.puts("  #{pc_id} perceives: #{text}") end)

IO.puts("=== SPEND REPORT ===")
r = Run.spend_report(run)
IO.puts("  total:    #{r.total.calls} calls, #{r.total.tokens_in} in / #{r.total.tokens_out} out")
for {class, s} <- r.by_class, do: IO.puts("  #{class}:  #{s.calls} calls, #{s.tokens_in} in / #{s.tokens_out} out")
for {agent, s} <- r.by_agent, do: IO.puts("  #{agent}: #{s.calls} calls, #{s.tokens_in} in / #{s.tokens_out} out")
ELIXIR
}

case "${1:-fight}" in
  fight)     fight ;;
  cascade)   cascade ;;
  referee)   referee ;;
  survey)    survey ;;
  inventory) inventory ;;
  all)       inventory; echo; fight; echo; cascade; echo; referee; echo; survey ;;
  help|-h|--help) usage ;;
  *)         echo "Unknown command: $1"; echo; usage ;;
esac
