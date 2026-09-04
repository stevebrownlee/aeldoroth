# Task 6: Organic deliberation prompt (`Agents.Prompt.deliberate/1`)

Implementer for plan `docs/superpowers/plans/2026-08-30-live-conversational-npc-web.md` Task 6. TDD strictly. Work in `/Users/chortlehoort/Campaigns/the-shattered-kingdoms`. Current HEAD: `b1757269` (Tasks 1–5 landed). Commit only the two named files.

Purpose: the deliberation prompt must make NPCs conversational — persona first, players addressed by name, "you were just asked" answering instead of dossier rotation, hearsay explicitly doubted (spec §4.5). This is prompt-contract work only; no engine or heuristic changes.

**Files:**
- Modify: `shards_engine/apps/agents/lib/agents/prompt.ex` — replace `deliberate/1` (lines 9–56), replace `speech_block/1` (lines 60–73), add `people_block/1` + `the_moment_block/1`; leave `adopt/1` and dossier helpers untouched
- Test: `shards_engine/apps/agents/test/deliberate_test.exs` (append new contract tests)

**Interfaces:**
- Produces: same `{system, user, schema}` triple; existing `deliberate_test.exs` contracts stay green (labels `Commitments:`, `Salient here:`, `Role:`, `Personality:`, `Goals:`, `Knowledge / Rumors:`, `Summary:` retained; `Summary:` last).

## Step 1 — Failing contract tests

Append before the final `end` of `shards_engine/apps/agents/test/deliberate_test.exs` (read the file's existing `slice/2` helper first — the tests below use it as-is; if the helper's shape differs, adapt call sites, NOT assertions):

```elixir
  test "prompt introduces perceived people by name with ids and marks PCs" do
    slice =
      slice("mara", %{
        agent: %{id: "mara", name: "Mara", place_id: "chiefs_room"},
        believed_agents: [
          %{id: "pc_thistle", name: "Thistle", pc: true, salience: 0.4},
          %{id: "npc_grevik", name: "Mayor Grevik", pc: false, salience: 0.2}
        ]
      })

    {_system, user, _schema} = Agents.Prompt.deliberate(slice)

    assert user =~ "Mara (mara) in Chief's Room"
    assert user =~ "Thistle (pc_thistle) — an adventurer here"
    assert user =~ "Mayor Grevik (npc_grevik) — someone here"
  end

  test "prompt renders addressed ask, hearsay overheard, and the moment" do
    slice =
      slice("mara", %{
        recent_speech: [
          %{from_id: "pc_bramble", from_name: "Bramble", words: "pass the ale", addressed: false, tick: 2},
          %{from_id: "pc_thistle", from_name: "Thistle", words: "how is your flock?", addressed: true, tick: 3}
        ]
      })

    {_system, user, _schema} = Agents.Prompt.deliberate(slice)

    assert user =~ ~s(Thistle says to YOU: "how is your flock?")
    assert user =~ "You overhear Bramble: \"pass the ale\" (hearsay"
    assert user =~ "secondhand, may be wrong"
    assert user =~ ~s(you were just asked, by Thistle: "how is your flock?")
  end

  test "system prompt carries the organic reply rules and decision-88 contract verbatim" do
    {system, _user, _schema} = Agents.Prompt.deliberate(slice("mara"))

    assert system =~
             ~s(If someone just addressed you: verb "shout", their id as target_id, message = your spoken reply, aimed at that person alone.)

    assert system =~
             "If nobody addressed you and no active commitment demands speaking: verb \"wait\". Do not volunteer speech unprompted."

    assert system =~ "first person"
    assert system =~ "1-4 sentences"
    assert system =~ "you may ask a question back"
    assert system =~ "Never invent world facts"
  end
```

Caveat: the place name in the first assertion is `slice.place.name` — the helper's default slice must yield `Chief's Room` for `place_id: "chiefs_room"`; check the helper and keep the assertion truthful to what the helper provides. If the helper's default place differs, adapt the `place_id` in the test input so the assertion holds against the helper's own name mapping.

## Step 2 — RED

`cd shards_engine/apps/agents && mix test test/deliberate_test.exs`
Expected: exactly the 3 new tests FAIL; all existing tests PASS.

## Step 3 — Implement

In `shards_engine/apps/agents/lib/agents/prompt.ex`:

(a) Replace `deliberate/1` (lines 9–56) — keep the schema exactly as-is, replace system and user assembly:

```elixir
  def deliberate(slice) do
    schema = %{
      type: :object,
      properties: %{
        verb: %{type: :string},
        target_id: %{type: :string, nullable: true},
        direction: %{type: :string, nullable: true},
        message: %{type: :string, nullable: true},
        reason: %{type: :string}
      },
      required: [:verb, :reason]
    }

    system = """
    You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
    tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
    Choose exactly one action for this moment. Respond ONLY with a JSON object:
    {"verb": string, "target_id": string | null, "direction": string | null,
    "message": string | null, "reason": string}.
    verb must be one of your capabilities. target_id must come from your believed
    list — never invent one. Ordering a subordinate uses verb "order", the
    subordinate's id as target_id, and the spoken order as message.
    Reply rules:
    - Answer the actual question you were asked, in first person, in your own
      voice; 1-4 sentences; you may ask a question back.
    - Speak only from your persona, what you have perceived, and general
      common-sense life experience of your station. Never invent world facts
      (names, places, magic) beyond them.
    - If someone just addressed you: verb "shout", their id as target_id, message = your spoken reply, aimed at that person alone.
    - If nobody addressed you and no active commitment demands speaking: verb "wait". Do not volunteer speech unprompted.
    """

    dossier = format_dossier(slice[:dossier])
    speech = speech_block(slice)
    the_moment = the_moment_block(Map.get(slice, :recent_speech, []))

    user =
      [
        "You are #{slice.agent.name} (#{slice.agent.id}) in #{slice.place.name}.",
        dossier,
        people_block(Map.get(slice, :believed_agents, [])),
        speech,
        the_moment,
        "Commitments: #{commitment_lines(slice.commitments)}",
        "Salient here: #{Enum.join(slice.salient, ", ")}",
        "Believed here: #{Enum.join(slice.believed, ", ")}",
        "Exits: #{Enum.join(slice.place.exits, ", ")}",
        "Capabilities: #{Enum.join(slice.capabilities, ", ")}",
        "",
        "Summary: #{slice.summary}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    {system, user, schema}
  end
```

(b) Replace `speech_block/1` (lines 60–73) and add the two new private helpers:

```elixir
  # What has been said in earshot. Addressed lines are first-class and name
  # the speaker; overheard lines are explicitly hearsay the brain may doubt.
  defp speech_block(slice) do
    case Map.get(slice, :recent_speech, []) do
      [] ->
        nil

      lines ->
        "Recent speech:\n" <>
          Enum.map_join(lines, "\n", fn l ->
            if l[:addressed] do
              ~s(  #{l[:from_name]} says to YOU: "#{l[:words]}")
            else
              ~s(  You overhear #{l[:from_name]}: "#{l[:words]}" (hearsay — secondhand, may be wrong))
            end
          end)
    end
  end

  # Names make the conversation personal; ids keep target_id legal. PCs are
  # labelled adventurers; beliefs carry no role for other agents.
  defp people_block([]), do: nil

  defp people_block(agents) do
    "People you can perceive:\n" <>
      Enum.map_join(agents, "\n", fn a ->
        role = if a[:pc], do: "an adventurer here", else: "someone here"
        "  #{a[:name]} (#{a[:id]}) — #{role}"
      end)
  end

  # The last person to address the brain drives answer-the-question instead
  # of topic rotation.
  defp the_moment_block(recent_speech) do
    case Enum.find(Enum.reverse(recent_speech), & &1[:addressed]) do
      nil ->
        nil

      line ->
        ~s(The moment: you were just asked, by #{line[:from_name]}: "#{line[:words]}")
    end
  end
```

Note: the two decision-88 rule lines are deliberately single (long) lines in the heredoc — the contract test matches them as continuous substrings. `mix format` will not rewrap heredocs; do not hand-reformat them.

## Step 4 — Full agents suite

`cd shards_engine/apps/agents && mix test`
Expected: PASS — new tests green; existing contracts green (`Summary:` last; dossier, heuristic, brain suites untouched).

## Step 5 — Commit

```bash
git add shards_engine/apps/agents/lib/agents/prompt.ex shards_engine/apps/agents/test/deliberate_test.exs
git commit -m "feat(agents): organic-derivation deliberation prompt (persona, named listeners, answer-the-question)"
```

## Report

Write `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-6-report.md`: commit sha, deviations (justified), test counts. Final reply: status (DONE / DONE_WITH_CONCERNS / FAILED), commit sha, test summary, concerns, report path. Never commit `.env` or `engrams/` artifacts.
