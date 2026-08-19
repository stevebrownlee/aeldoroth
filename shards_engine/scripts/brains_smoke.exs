# Brains smoke: the Plan 4 chain end-to-end from the shell.
#
#   SEED=42 YAML=../the-ruined-tower/ruined_tower.yaml mix run scripts/brains_smoke.exs
#
# Drives the two PC declares (east, south) that carry Thistle into the
# chief's room, then 20 advances: grisk's cadence escalates on her arrival,
# he orders goblin_bodyguard_1, the envelope delivers on signal receipt, the
# bodyguard adopts it into his own commitment, and his next escalated tick
# strikes. Prints PC narrations, the phase-marker ledger rows in seq order,
# and the spend report.
seed = String.to_integer(System.get_env("SEED") || "42")
yaml = System.get_env("YAML") || "../the-ruined-tower/ruined_tower.yaml"

alias LLMGateway.Adapters.Scripted
alias Referee.Run

interpret = [
  ~s({"verb":"move","target_id":null,"params":{"direction":"east"},"assumptions":[]}),
  ~s({"verb":"move","target_id":null,"params":{"direction":"south"},"assumptions":[]})
]

deliberate = [
  %{agent_id: "goblin_bodyguard_1",
    content: ~s({"verb":"strike","target_id":"pc_thistle","reason":"obeying orders"})},
  %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"guarding the chief"})},
  %{agent_id: "goblin_bodyguard_2", content: ~s({"verb":"wait","reason":"still guarding"})},
  %{agent_id: "grisk_the_snatcher",
    content: ~s({"verb":"order","target_id":"goblin_bodyguard_1","message":"Kill the intruder!","reason":"intruders in my hall"})},
  %{agent_id: "grisk_the_snatcher", content: ~s({"verb":"wait","reason":"my will is done"})},
  %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"on watch"})},
  %{agent_id: "goblin_guard_1", content: ~s({"verb":"wait","reason":"still on watch"})},
  %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"on watch"})},
  %{agent_id: "goblin_guard_2", content: ~s({"verb":"wait","reason":"still on watch"})},
  %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"on watch"})},
  %{agent_id: "goblin_guard_3", content: ~s({"verb":"wait","reason":"still on watch"})},
  %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"on watch"})},
  %{agent_id: "goblin_guard_4", content: ~s({"verb":"wait","reason":"still on watch"})}
]

adopt = [
  %{agent_id: "goblin_bodyguard_1",
    content: ~s({"adopted":true,"deed":"slay the intruder","deceive":false,"reason":"fear of the chief"})}
]

scripts = %{interpret: interpret, narrate: [], deliberate: deliberate, adopt: adopt, salt: 99}
cfg = %{adapter: Scripted, scripts: scripts}
routing = %{interpret: cfg, narrate: cfg, deliberate: cfg, adopt: cfg}

pcs = [
  %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
    int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"}
]

{:ok, run} = Run.new(yaml, seed, pcs, routing: routing)

IO.puts("=== BRAINS — tower YAML, seed #{seed}, scripted LLM queues ===")

IO.puts("  > go east")
{:ok, text, run} = Run.declare(run, "pc_thistle", "go east")
IO.puts("    #{text}")

IO.puts("  > go south")
{:ok, text, run} = Run.declare(run, "pc_thistle", "go south")
IO.puts("    #{text}")

run =
  Enum.reduce(1..20, run, fn i, acc ->
    {:ok, narrations, acc2} = Run.advance(acc)

    narrations
    |> Enum.each(fn {pc_id, text} ->
      if text not in [nil, ""], do: IO.puts("  [t#{i}] #{pc_id} perceives: #{text}")
    end)

    acc2
  end)

IO.puts("=== WORLD AT TICK #{run.world.tick} ===")

IO.puts("=== PHASE MARKERS (seq order) ===")

Run.events(run)
|> Enum.filter(fn ev ->
  ev.class in [:envelope, :commitment, :deliberation, :dice] or
    (ev.class == :world and ev.payload[:kind] == :damage)
end)
|> Enum.each(fn ev ->
  IO.puts("  #{String.pad_leading(Integer.to_string(ev.seq), 4)} #{String.pad_trailing(to_string(ev.class), 12)} #{inspect(ev.payload, limit: 6)}")
end)

IO.puts("=== SPEND REPORT ===")
r = Run.spend_report(run)
IO.puts("  total:    #{r.total.calls} calls, #{r.total.tokens_in} in / #{r.total.tokens_out} out")
for {class, s} <- r.by_class, do: IO.puts("  #{class}:  #{s.calls} calls, #{s.tokens_in} in / #{s.tokens_out} out")
for {agent, s} <- r.by_agent, do: IO.puts("  #{agent}: #{s.calls} calls, #{s.tokens_in} in / #{s.tokens_out} out")
