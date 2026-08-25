b9c1bd5 feat(referee): expose agent dossier in slice for deliberation

--- STAT ---

 shards_engine/apps/referee/lib/referee/slice.ex | 4 +++-
 shards_engine/apps/referee/test/slice_test.exs  | 7 +++++++
 2 files changed, 10 insertions(+), 1 deletion(-)

--- DIFF ---

diff --git a/shards_engine/apps/referee/lib/referee/slice.ex b/shards_engine/apps/referee/lib/referee/slice.ex
index d81cf91..719be47 100644
--- a/shards_engine/apps/referee/lib/referee/slice.ex
+++ b/shards_engine/apps/referee/lib/referee/slice.ex
@@ -5,21 +5,21 @@ defmodule Referee.Slice do
   `for_actor/2` derives everything an LLM prompt may reference for one agent.
   Returned keys:
     * `:agent` — identity (`id`, `name`, `place_id`)
     * `:sheet` — the actor's own body (`hp`, `hp_max`, `ac`, `thac0`, `damage`,
       `conditions`, `morale`, `int`, `hd`); truth-barrier safe
     * `:place` — current place (`id`, `name`, `kind`, `exits`, `visible_items`,
       `items` with `id` and `name`)
     * `:believed` — ids of believed agents at this place
     * `:believed_agents` — the same ids resolved to `%{id: ..., name: ...}`
     * `:salient` — seen beliefs, sorted by salience
-    * `:commitments`, `:capabilities`, `:summary`
+    * `:commitments`, `:capabilities`, `:dossier`, `:summary`
 
   Hidden items and agents in other places never appear — the slice is the only
   world data that reaches a prompt, and the sheet is the actor's own body,
   so it is truth-barrier safe.
   """
 
   alias EngineCore.World
 
   @spec for_actor(World.t(), String.t()) :: %{
           agent: map(),
@@ -50,20 +50,21 @@ defmodule Referee.Slice do
             exits: [String.t()],
             exits_labeled: [%{dir: String.t() | nil, to: String.t(), sealed: boolean()}],
             visible_items: [String.t()],
             items: [%{id: String.t(), name: String.t()}]
           },
           believed: [String.t()],
           believed_agents: [%{id: String.t(), name: String.t(), pc: boolean()}],
           salient: [String.t()],
           commitments: [map()],
           capabilities: [atom()],
+          dossier: map(),
           summary: String.t()
         }
   def for_actor(%World{} = world, agent_id) do
     agent = World.agent(world, agent_id)
     place = World.place(world, agent.place_id)
 
     believed =
       agent.beliefs
       |> Map.get(agent.place_id, %{})
       |> Map.keys()
@@ -86,20 +87,21 @@ defmodule Referee.Slice do
         exits: exits(world, agent.place_id),
         exits_labeled: exits_labeled(world, agent.place_id),
         visible_items: visible_items(world, agent.place_id),
         items: place_items(world, agent.place_id)
       },
       believed: believed,
       believed_agents: believed_agents(world, believed),
       salient: salient,
       commitments: commitments(agent),
       capabilities: agent.capabilities,
+      dossier: Map.get(agent, :dossier) || %{},
       summary: summarize(place, believed, world, agent.id)
     }
   end
 
   defp sheet(agent) do
     body = agent.body
     st = Map.get(agent, :statblock) || %{}
 
     %{
       hp: body.hp,
diff --git a/shards_engine/apps/referee/test/slice_test.exs b/shards_engine/apps/referee/test/slice_test.exs
index 85058a0..a496a0a 100644
--- a/shards_engine/apps/referee/test/slice_test.exs
+++ b/shards_engine/apps/referee/test/slice_test.exs
@@ -48,20 +48,27 @@ defmodule Referee.SliceTest do
         "goblin_guard_1" => mk.("goblin_guard_1", "hall"),
         "rat_1" => mk.("rat_1", "crypt")
       },
       items: %{
         "sword" => %Types.Item{id: "sword", name: "Sword", value_gp: 10, place_id: "hall"},
         "gem" => %Types.Item{id: "gem", name: "Gem", value_gp: 500, place_id: "hall", is_hidden: true}
       }
     }
   end
 
+  test "for_actor includes the actor's dossier map" do
+    w = put_in(world().agents["pc"].dossier, %{"occupation" => "adventurer", "goal" => "find the gem"})
+    s = Slice.for_actor(w, "pc")
+
+    assert s.dossier == %{"occupation" => "adventurer", "goal" => "find the gem"}
+  end
+
   test "for_actor returns identity, place with exits, and current-place beliefs only" do
     s = Slice.for_actor(world(), "pc")
 
     assert s.agent == %{id: "pc", name: "PC", place_id: "hall"}
     assert s.place.name == "Room hall"
     assert s.place.kind == :room
     assert s.place.exits == ["crypt", "vault"]
 
     # believed: abouts at the actor's current place, sorted; crypt belief must not leak
     assert s.believed == ["ghost", "goblin_guard_1"]
