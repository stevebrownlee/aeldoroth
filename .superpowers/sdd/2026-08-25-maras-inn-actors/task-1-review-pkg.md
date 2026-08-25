6505945 feat(engine_core): support initial_actors, explicit tier parsing, and agent dossiers

--- STAT ---

 .../2026-08-25-maras-inn-actors/task-1-report.md   | 34 ++++++++
 .../apps/engine_core/lib/engine_core/loader.ex     | 22 ++++--
 .../apps/engine_core/lib/engine_core/validator.ex  | 91 +++++++++++++---------
 .../apps/engine_core/test/loader_test.exs          | 41 ++++++++++
 .../apps/engine_core/test/validator_test.exs       | 22 ++++++
 5 files changed, 165 insertions(+), 45 deletions(-)

--- DIFF ---

diff --git a/.superpowers/sdd/2026-08-25-maras-inn-actors/task-1-report.md b/.superpowers/sdd/2026-08-25-maras-inn-actors/task-1-report.md
new file mode 100644
index 0000000..be2e23c
--- /dev/null
+++ b/.superpowers/sdd/2026-08-25-maras-inn-actors/task-1-report.md
@@ -0,0 +1,34 @@
+# Task 1 Report: Multi-Key Actor Ingestion, Tier Parsing & Dossier Support
+
+## Status
+DONE
+
+## Summary
+Implemented support for multiple actor source keys, explicit tier parsing, and agent dossiers in `EngineCore.Loader` and `EngineCore.Validator`, with accompanying tests.
+
+## Commits
+- `feat(engine_core): support initial_actors, explicit tier parsing, and agent dossiers`
+
+## Changes Made
+- `shards_engine/apps/engine_core/lib/engine_core/loader.ex`
+  - `extract_elements/2` now merges entries from `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters`.
+  - `agent_from/1` uses new `parse_tier/1` helper: prefers explicit `tier` or `cognition_tier` integer, falling back to ID-based `tier_of/1`.
+  - `agent_from/1` sets `capabilities: caps(tier)` and `dossier: m["dossier"] || %{}`.
+- `shards_engine/apps/engine_core/lib/engine_core/validator.ex`
+  - Added `@actor_keys` module attribute.
+  - `monster_errors/1` now validates required attributes across all actor keys.
+  - `agent_ids/1` collects IDs from `initial_actors`, `initial_npcs`, `initial_enemies`, and `monsters` (maps or lists).
+- `shards_engine/apps/engine_core/test/loader_test.exs`
+  - Added test verifying merge of `initial_actors` and `initial_enemies`, explicit tier parsing (`tier` and `cognition_tier`), tier-3 `:parley` capability, and dossier loading.
+- `shards_engine/apps/engine_core/test/validator_test.exs`
+  - Added test verifying validation accepts a valid `initial_actors` map.
+
+## Test Results
+```
+$ cd shards_engine/apps/engine_core && mix test
+Running ExUnit with seed: 734222, max_cases: 32
+Result: 109 passed
+```
+
+## Concerns
+None.
diff --git a/shards_engine/apps/engine_core/lib/engine_core/loader.ex b/shards_engine/apps/engine_core/lib/engine_core/loader.ex
index 33872cf..9e97150 100644
--- a/shards_engine/apps/engine_core/lib/engine_core/loader.ex
+++ b/shards_engine/apps/engine_core/lib/engine_core/loader.ex
@@ -64,22 +64,23 @@ defmodule EngineCore.Loader do
       for r <- rooms,
           {dir, c} <- extract_exits(r),
           do: %Types.Edge{
             id: :"#{r["id"]}__#{c.target}",
             from: r["id"],
             to: c.target,
             sealed: c.sealed,
             label: dir
           }
 
-    monsters = extract_elements(yaml, ["initial_enemies", "monsters"])
-    agents = Map.new(monsters, fn m -> {m["id"], agent_from(m)} end)
+    agents =
+      extract_elements(yaml, ["initial_actors", "initial_npcs", "initial_enemies", "monsters"])
+      |> Map.new(fn m -> {m["id"], agent_from(m)} end)
 
     treasures = extract_elements(yaml, ["initial_treasure", "treasures"])
     items = Map.new(treasures, fn t -> {t["id"], item_from(t)} end)
 
     starting_place = yaml["starting_place"] || yaml["starting_room"] || "entry_hall"
     world = %World{places: places, edges: edges, agents: agents, items: items, tick: 0, starting_place: starting_place}
 
     world
     |> put_boundaries(yaml)
     |> put_hazards(yaml)
@@ -104,27 +105,26 @@ defmodule EngineCore.Loader do
 
         {id, %{a | beliefs: Map.put(a.beliefs, a.place_id, others)}}
       end)
 
     %{world | agents: agents}
    end
 
   defp extract_elements(yaml, keys) do
     keys
     |> Enum.map(&Map.get(yaml, &1))
-    |> Enum.find(& &1)
-    |> case do
-      nil -> []
+    |> Enum.reject(&is_nil/1)
+    |> Enum.flat_map(fn
       map when is_map(map) -> Map.values(map)
       list when is_list(list) -> list
       _ -> []
-    end
+    end)
   end
 
   defp extract_connections(r) do
     r
     |> extract_exits()
     |> Enum.map(fn {_dir, c} -> c.target end)
   end
 
   defp extract_exits(r) do
     cond do
@@ -147,44 +147,50 @@ defmodule EngineCore.Loader do
             nil
         end)
         |> Enum.reject(&is_nil/1)
 
       true ->
         []
     end
   end
 
   defp agent_from(m) do
-    tier = tier_of(m["id"])
+    tier = parse_tier(m)
     hp = m["hit_points"] || m["hp"] || 1
 
     %Types.Agent{
       id: m["id"],
       name: m["name"] || m["id"],
       tier: tier,
       place_id: m["current_room_id"] || m["room_id"] || m["location_room_id"],
       statblock: %{
         ac: m["armor_class"] || m["ac"] || 10,
         hd: parse_hd(m["hit_dice"] || m["hd"]),
         hp_max: hp,
         thac0: m["thac0"] || 20,
         morale: m["morale"] || 7,
         int: m["intelligence"] || m["int"] || 8,
         damage: parse_damage(m)
       },
       body: %{hp: hp, conditions: []},
       capabilities: caps(tier),
       group: m["type"],
-      cadence: cadence_for(tier)
+      cadence: cadence_for(tier),
+      dossier: m["dossier"] || %{}
     }
   end
 
+  defp parse_tier(%{"tier" => tier}) when is_integer(tier), do: tier
+  defp parse_tier(%{"cognition_tier" => tier}) when is_integer(tier), do: tier
+  defp parse_tier(%{"id" => id}), do: tier_of(id)
+  defp parse_tier(_), do: 1
+
   defp cadence_for(0), do: %{every: 2, next_due: nil}
   defp cadence_for(3), do: %{every: 10, next_due: nil}
   defp cadence_for(2), do: %{every: 5, next_due: nil}
   defp cadence_for(_), do: nil
 
   defp tier_of(id) when id in @tier3, do: 3
   defp tier_of(id) when id in @tier2, do: 2
   defp tier_of(id) when id in @tier0, do: 0
   defp tier_of(_), do: 1
   defp parse_hd(val) when is_integer(val), do: val
diff --git a/shards_engine/apps/engine_core/lib/engine_core/validator.ex b/shards_engine/apps/engine_core/lib/engine_core/validator.ex
index c81cf3f..f3a056e 100644
--- a/shards_engine/apps/engine_core/lib/engine_core/validator.ex
+++ b/shards_engine/apps/engine_core/lib/engine_core/validator.ex
@@ -32,39 +32,59 @@ defmodule EngineCore.Validator do
         commitment_errors(yaml, agents_set)
     if errors == [] do
       :ok
     else
       {:error, errors}
     end
   end
 
   def check(_), do: {:error, ["invalid YAML document: expected a map"]}
 
-  defp monster_errors(%{"initial_enemies" => enemies}) when is_map(enemies) do
-    Enum.flat_map(Map.values(enemies), fn m ->
-      if is_map(m) do
-        id = m["id"] || "?"
-
-        Enum.flat_map(@monster_req, fn k ->
-          if Map.has_key?(m, k) do
-            []
-          else
-            ["monster #{id}: missing #{k}"]
-          end
-        end)
-      else
-        []
+  @actor_keys ["initial_actors", "initial_npcs", "initial_enemies", "monsters"]
+
+  defp monster_errors(yaml) when is_map(yaml) do
+    @actor_keys
+    |> Enum.flat_map(fn key ->
+      case yaml[key] do
+        enemies when is_map(enemies) ->
+          Enum.flat_map(Map.values(enemies), fn m ->
+            if is_map(m) do
+              id = m["id"] || "?"
+
+              Enum.flat_map(@monster_req, fn k ->
+                if Map.has_key?(m, k) do
+                  []
+                else
+                  ["monster #{id}: missing #{k}"]
+                end
+              end)
+            else
+              []
+            end
+          end)
+
+        _ ->
+          []
       end
     end)
-  end
+    |> case do
+      [] ->
+        if Enum.any?(@actor_keys, &Map.has_key?(yaml, &1)) do
+          []
+        else
+          ["initial_enemies: key absent"]
+        end
 
-  defp monster_errors(_), do: ["initial_enemies: key absent"]
+      errors ->
+        errors
+    end
+  end
 
   defp text_errors(yaml) do
     yaml
     |> walk_strings()
     |> Enum.filter(&Regex.match?(@orphan_fragment, &1.elem))
     |> Enum.map(&"#{&1.path}: orphan fragment #{inspect(&1.elem)}")
   end
 
   defp room_errors(yaml) when is_map(yaml) do
     rooms_map = extract_places_map(yaml)
@@ -154,41 +174,38 @@ defmodule EngineCore.Validator do
       |> Enum.map(fn r -> if is_map(r), do: r["id"], else: nil end)
       |> Enum.filter(&is_binary/1)
       |> MapSet.new()
 
     MapSet.union(set1, list_elems)
   end
 
   defp as_list(l) when is_list(l), do: l
   defp as_list(_), do: []
   defp agent_ids(yaml) do
-    enemies = yaml["initial_enemies"] || yaml["monsters"]
-
-    cond do
-      is_map(enemies) ->
-        enemies
-        |> Enum.flat_map(fn {k, m} ->
-          id = if is_map(m), do: m["id"], else: nil
-          [k, id]
-        end)
-        |> Enum.filter(&is_binary/1)
-        |> MapSet.new()
-
-      is_list(enemies) ->
-        enemies
-        |> Enum.map(fn m -> if is_map(m), do: m["id"], else: nil end)
-        |> Enum.filter(&is_binary/1)
-        |> MapSet.new()
-
-      true ->
-        MapSet.new()
-    end
+    @actor_keys
+    |> Enum.flat_map(fn key ->
+      case yaml[key] do
+        enemies when is_map(enemies) ->
+          Enum.flat_map(enemies, fn {k, m} ->
+            id = if is_map(m), do: m["id"], else: nil
+            [k, id]
+          end)
+
+        enemies when is_list(enemies) ->
+          Enum.map(enemies, fn m -> if is_map(m), do: m["id"], else: nil end)
+
+        _ ->
+          []
+      end
+    end)
+    |> Enum.filter(&is_binary/1)
+    |> MapSet.new()
   end
 
   defp boundary_errors(%{"boundaries" => bs}, room_ids) when is_list(bs) do
     Enum.flat_map(bs, fn b ->
       id = b["id"] || "?"
 
       cond do
         b["place"] == nil and b["group"] == nil ->
           ["boundary #{id}: needs place or group scope"]
 
diff --git a/shards_engine/apps/engine_core/test/loader_test.exs b/shards_engine/apps/engine_core/test/loader_test.exs
index 6268846..369fbfe 100644
--- a/shards_engine/apps/engine_core/test/loader_test.exs
+++ b/shards_engine/apps/engine_core/test/loader_test.exs
@@ -43,20 +43,61 @@ defmodule EngineCore.LoaderTest do
     assert w.agents["m3"].statblock.hd == 2
     assert w.agents["m4"].statblock.hd == 3
 
     {:ok, tower_world} = EngineCore.Loader.load(@yaml)
 
     for {_id, agent} <- tower_world.agents do
       assert is_integer(agent.statblock.hd)
     end
   end
 
+  test "merges initial_actors and initial_enemies, parses tier, capabilities, and dossier" do
+    raw = %{
+      "places" => %{
+        "maras_inn" => %{"id" => "maras_inn", "name" => "Mara's Inn"}
+      },
+      "starting_place" => "maras_inn",
+      "initial_actors" => %{
+        "bartender" => %{
+          "id" => "bartender",
+          "name" => "Bartender",
+          "tier" => 3,
+          "current_room_id" => "maras_inn",
+          "dossier" => %{"occupation" => "innkeeper"}
+        }
+      },
+      "initial_enemies" => %{
+        "goblin" => %{
+          "id" => "goblin",
+          "name" => "Goblin",
+          "cognition_tier" => 2,
+          "current_room_id" => "maras_inn",
+          "hit_dice" => "1d8",
+          "hit_points" => 4,
+          "armor_class" => 7,
+          "thac0" => 19,
+          "morale" => 6
+        }
+      }
+    }
+
+    w = EngineCore.Loader.build(raw)
+
+    assert map_size(w.agents) == 2
+    assert w.agents["bartender"].tier == 3
+    assert :parley in w.agents["bartender"].capabilities
+    assert w.agents["bartender"].dossier == %{"occupation" => "innkeeper"}
+    assert w.agents["goblin"].tier == 2
+    assert :parley not in w.agents["goblin"].capabilities
+    assert :move in w.agents["goblin"].capabilities
+  end
+
   test "sets sealed: true on edge when exit is locked" do
     {:ok, w} = EngineCore.Loader.load(@yaml)
 
     library_edge =
       Enum.find(w.edges, fn e -> e.from == "library" and e.to == "ritual_chamber" end)
 
     assert library_edge != nil
     assert library_edge.sealed == true
   end
 
diff --git a/shards_engine/apps/engine_core/test/validator_test.exs b/shards_engine/apps/engine_core/test/validator_test.exs
index 0efcdd1..0c9d302 100644
--- a/shards_engine/apps/engine_core/test/validator_test.exs
+++ b/shards_engine/apps/engine_core/test/validator_test.exs
@@ -1,19 +1,41 @@
 defmodule EngineCore.ValidatorTest do
   use ExUnit.Case, async: true
 
   @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
 
   test "the real tower YAML is structurally intact" do
     assert :ok = EngineCore.Validator.check_file(@yaml)
   end
 
+  test "accepts valid initial_actors maps" do
+    base = %{
+      "rooms" => %{
+        "r1" => %{"id" => "r1", "name" => "R1"}
+      },
+      "initial_actors" => %{
+        "a1" => %{
+          "id" => "a1",
+          "name" => "Hero",
+          "hit_dice" => "1d8",
+          "hit_points" => 8,
+          "armor_class" => 10,
+          "thac0" => 20,
+          "morale" => 7,
+          "current_room_id" => "r1"
+        }
+      }
+    }
+
+    assert :ok = EngineCore.Validator.check(base)
+  end
+
   test "detects orphan-fragment text" do
     bad = %{
       "initial_enemies" => %{
         "m1" => %{
           "id" => "m1",
           "name" => "goblin",
           "hit_dice" => "1d8",
           "hit_points" => 4,
           "armor_class" => 7,
           "thac0" => 19,
