9bc85e2 feat(agents): format agent dossier role, goals, and knowledge in deliberate prompt

--- STAT ---

 shards_engine/apps/agents/lib/agents/prompt.ex     | 54 ++++++++++++++++++----
 shards_engine/apps/agents/test/deliberate_test.exs | 17 +++++++
 2 files changed, 61 insertions(+), 10 deletions(-)

--- DIFF ---

diff --git a/shards_engine/apps/agents/lib/agents/prompt.ex b/shards_engine/apps/agents/lib/agents/prompt.ex
index 0f11c26..57644bb 100644
--- a/shards_engine/apps/agents/lib/agents/prompt.ex
+++ b/shards_engine/apps/agents/lib/agents/prompt.ex
@@ -23,33 +23,67 @@ defmodule Agents.Prompt do
     You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
     tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
     Choose exactly one action for this moment. Respond ONLY with a JSON object:
     {"verb": string, "target_id": string | null, "direction": string | null,
     "message": string | null, "reason": string}.
     verb must be one of your capabilities. target_id must come from your believed
     list — never invent one. Ordering a subordinate uses verb "order", the
     subordinate's id as target_id, and the spoken order as message.
     """
 
-    user = """
-    You are #{slice.agent.name} in #{slice.place.name}.
-    Commitments: #{commitment_lines(slice.commitments)}
-    Salient here: #{Enum.join(slice.salient, ", ")}
-    Believed here: #{Enum.join(slice.believed, ", ")}
-    Exits: #{Enum.join(slice.place.exits, ", ")}
-    Capabilities: #{Enum.join(slice.capabilities, ", ")}
+    dossier = format_dossier(slice[:dossier])
 
-    Summary: #{slice.summary}
-    """
+    user =
+      [
+        "You are #{slice.agent.name} in #{slice.place.name}.",
+        dossier,
+        "Commitments: #{commitment_lines(slice.commitments)}",
+        "Salient here: #{Enum.join(slice.salient, ", ")}",
+        "Believed here: #{Enum.join(slice.believed, ", ")}",
+        "Exits: #{Enum.join(slice.place.exits, ", ")}",
+        "Capabilities: #{Enum.join(slice.capabilities, ", ")}",
+        "",
+        "Summary: #{slice.summary}"
+      ]
+      |> Enum.reject(&is_nil/1)
+      |> Enum.join("\n")
 
     {system, user, schema}
-end
+  end
+
+  defp format_dossier(nil), do: nil
+  defp format_dossier(%{} = d) when map_size(d) == 0, do: nil
+  defp format_dossier(dossier) do
+    lines =
+      []
+      |> maybe_dossier_line("Role", dossier_field(dossier, :role))
+      |> maybe_dossier_line("Personality", dossier_field(dossier, :personality))
+      |> maybe_dossier_line("Goals", dossier_field(dossier, :goals))
+      |> maybe_dossier_line("Knowledge / Rumors",
+           dossier_field(dossier, :knowledge) || dossier_field(dossier, :rumors))
+
+    if Enum.empty?(lines), do: nil, else: Enum.join(lines, "\n")
+  end
+
+  defp dossier_field(dossier, key) do
+    dossier[key] || dossier[Atom.to_string(key)]
+  end
+
+  defp maybe_dossier_line(lines, _label, nil), do: lines
+  defp maybe_dossier_line(lines, _label, []), do: lines
+  defp maybe_dossier_line(lines, _label, ""), do: lines
+  defp maybe_dossier_line(lines, label, value) when is_list(value) do
+    lines ++ ["#{label}: #{Enum.join(value, "; ")}"]
+  end
+  defp maybe_dossier_line(lines, label, value) do
+    lines ++ ["#{label}: #{value}"]
+  end
 
   @doc """
   Adoption prompt. The envelope is stripped to its deniable face — id, from,
   to, type, spoken text, tick — so `truth` never reaches the LLM (truth
   barrier; llm-proposes-engine-disposes).
   """
   @spec adopt(map(), map()) :: {String.t(), String.t(), map()}
   def adopt(slice, envelope) do
     schema = %{
       type: :object,
diff --git a/shards_engine/apps/agents/test/deliberate_test.exs b/shards_engine/apps/agents/test/deliberate_test.exs
index c88490f..c3d2211 100644
--- a/shards_engine/apps/agents/test/deliberate_test.exs
+++ b/shards_engine/apps/agents/test/deliberate_test.exs
@@ -71,11 +71,28 @@ defmodule Agents.DeliberateTest do
     refute d.request.user =~ "ritual_chamber"
   end
 
   test "prompt shape: commitments/salient head, state summary last" do
     entry = ~s({"verb":"wait","reason":"biding"})
     {:ok, d} = Agents.deliberate("grisk_the_snatcher", %{slice: slice("grisk_the_snatcher"), ctx: ctx([entry])})
     [head, _summary] = String.split(d.request.user, "Summary:", parts: 2)
     assert head =~ "Commitments:"
     assert head =~ "Salient here:"
   end
+
+  test "prompt includes formatted dossier lines" do
+    dossier = %{
+      role: "bandit chief",
+      personality: "gruff and suspicious",
+      goals: ["protect the treasure", "drive off intruders"],
+      knowledge: ["pc_thistle is a thief", "the back exit leads east"]
+    }
+    entry = ~s({"verb":"wait","reason":"biding"})
+    {:ok, d} = Agents.deliberate("grisk_the_snatcher",
+      %{slice: slice("grisk_the_snatcher", %{dossier: dossier}), ctx: ctx([entry])})
+
+    assert d.request.user =~ "Role: bandit chief"
+    assert d.request.user =~ "Personality: gruff and suspicious"
+    assert d.request.user =~ "Goals: protect the treasure; drive off intruders"
+    assert d.request.user =~ "Knowledge / Rumors: pc_thistle is a thief; the back exit leads east"
+  end
 end
