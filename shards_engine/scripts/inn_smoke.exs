# Live-API inn smoke (spec docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md §5.6).
# Run from shards_engine/ with ANTHROPIC_API_KEY exported (or present in .env
# already sourced into your shell):
#   MIX_ENV=dev mix run scripts/inn_smoke.exs
#
# Boots one session on the real ruined_tower.yaml with live routing, has
# Thistle ask Erik about his sheep while Bramble only listens, then prints
# each PC's text and runs mechanical checks: Erik answers Thistle, the reply
# is private, no unaddressed NPC speaks, and no verbatim YAML knowledge line
# comes back as the reply.

LLMGateway.Config.apply_env_routing()

unless LLMGateway.Config.live?() do
  IO.puts("[inn_smoke] live routing unavailable — export ANTHROPIC_API_KEY and retry")
  System.halt(1)
end

run_id = "smoke_#{System.unique_integer([:positive])}"
yaml = Path.expand("../../the-ruined-tower/ruined_tower.yaml", __DIR__)

pcs = [
  %{id: "pc_thistle", name: "Thistle", place_id: "maras_inn",
    int: 13, hd: 1, hp: 12, ac: 5, thac0: 20, damage: "1d8"},
  %{id: "pc_bramble", name: "Bramble", place_id: "maras_inn",
    int: 12, hd: 1, hp: 8, ac: 6, thac0: 19, damage: "1d6"}
]

{:ok, _pid} = Referee.Run.Session.start_link(run_id, yaml, 42, pcs)

{:ok, %{reply: _}} =
  Referee.Run.Session.declare(run_id, "pc_thistle", "Erik, what happened to your sheep?")

IO.puts("[inn_smoke] live round: interpret + NPC deliberations + narrate (be patient)...")

# Long timeout: several billed Haiku calls run sequentially (spec §6 cadence risk).
{:ok, texts} = Referee.Run.Session.advance(run_id, 300_000)

IO.puts("\n=== pc_thistle (asked) ===\n#{texts["pc_thistle"]}")
IO.puts("\n=== pc_bramble (listened) ===\n#{texts["pc_bramble"] || "(nothing)"}")

both = (texts["pc_thistle"] || "") <> " " <> (texts["pc_bramble"] || "")

failures =
  []
  |> Kernel.++(
    if texts["pc_thistle"] =~ "Erik the Shepherd says to you",
      do: [],
      else: ["Erik never replied to Thistle"]
  )
  |> Kernel.++(
    if texts["pc_bramble"] && texts["pc_bramble"] =~ "says to you",
      do: ["Erik's reply leaked to the listener"],
      else: []
  )
  |> Kernel.++(
    if Regex.match?(~r/(Mara|Mayor Grevik|Anna Mordale) says to you/, both),
      do: ["an unaddressed NPC volunteered speech"],
      else: []
  )
  |> Kernel.++(
    if Enum.any?(
         [
           "Green-skinned creatures carried off three sheep two nights ago.",
           "They headed toward the ruined tower on the hill.",
           "Strange green lights have flickered from the tower for two weeks."
         ],
         &String.contains?(both, &1)
       ),
      do: ["verbatim YAML knowledge/rumor line surfaced as a reply"],
      else: []
  )

IO.puts(
  "\nmechanical checks: #{if failures == [], do: "PASS", else: "FAIL — #{inspect(failures)}"}"
)

Referee.Run.Session.stop(run_id)
System.halt(if(failures == [], do: 0, else: 1))
