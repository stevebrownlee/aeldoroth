defmodule Agents.Prompt do
  @moduledoc """
  Prompt + schema construction for brain LLM calls (spec §8.3). Slices are
  plain maps shaped like `Referee.Slice.for_actor/2` output — agents never
  depends on referee, so the boundary stays one-directional.
  """

  @spec deliberate(map()) :: {String.t(), String.t(), map()}
  def deliberate(slice) do
    schema = %{
      type: :object,
      properties: %{
        verb: %{type: :string},
        target_id: %{type: :string, nullable: true},
        direction: %{type: :string, nullable: true},
        message: %{type: :string, nullable: true},
        commitment_id: %{type: :string, nullable: true},
        reason: %{type: :string}
      },
      required: [:verb, :reason]
    }

    system = """
    You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
    tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
    Choose exactly one action for this moment. Respond ONLY with a JSON object:
    {"verb": string, "target_id": string | null, "direction": string | null,
    "message": string | null, "commitment_id": string | null, "reason": string}.
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
    - When your action this turn performs one of your own commitments whose due
      tick has arrived, include "commitment_id": "<its id from Commitments>" so
      the world records the deed as kept. Claim only your own commitments.
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
              ~s{  You overhear #{l[:from_name]}: "#{l[:words]}" (hearsay — secondhand, may be wrong)}
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

  defp format_dossier(nil), do: nil
  defp format_dossier(%{} = d) when map_size(d) == 0, do: nil

  defp format_dossier(dossier) do
    lines =
      []
      |> maybe_dossier_line("Role", dossier_field(dossier, :role))
      |> maybe_dossier_line("Personality", dossier_field(dossier, :personality))
      |> maybe_dossier_line("Goals", dossier_field(dossier, :goals))
      |> maybe_dossier_line("Knowledge / Rumors", combined_knowledge_rumors(dossier))

    if Enum.empty?(lines), do: nil, else: Enum.join(lines, "\n")
  end

  defp dossier_field(dossier, key) do
    dossier[key] || dossier[Atom.to_string(key)]
  end

  defp maybe_dossier_line(lines, _label, nil), do: lines
  defp maybe_dossier_line(lines, _label, []), do: lines
  defp maybe_dossier_line(lines, _label, ""), do: lines

  defp maybe_dossier_line(lines, label, value) when is_list(value) do
    lines ++ ["#{label}: #{Enum.join(value, "; ")}"]
  end

  defp maybe_dossier_line(lines, label, value) do
    lines ++ ["#{label}: #{value}"]
  end

  defp combined_knowledge_rumors(dossier) do
    k = dossier_field(dossier, :knowledge)
    r = dossier_field(dossier, :rumors)

    cond do
      is_list(k) and is_list(r) and (k != [] or r != []) -> k ++ r
      is_list(k) and k != [] -> k
      is_list(r) and r != [] -> r
      is_binary(k) and k != "" and is_binary(r) and r != "" -> "#{k}; #{r}"
      is_binary(k) and k != "" -> k
      is_binary(r) and r != "" -> r
      true -> nil
    end
  end

  @doc """
  Adoption prompt. The envelope is stripped to its deniable face — id, from,
  to, type, spoken text, tick — so `truth` never reaches the LLM (truth
  barrier; llm-proposes-engine-disposes).
  """
  @spec adopt(map(), map()) :: {String.t(), String.t(), map()}
  def adopt(slice, envelope) do
    schema = %{
      type: :object,
      properties: %{
        adopted: %{type: :boolean},
        deed: %{type: :string},
        deceive: %{type: :boolean},
        inform: %{type: :string, nullable: true},
        reason: %{type: :string}
      },
      required: [:adopted, :reason]
    }

    system = """
    You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
    tabletop RPG world. #{envelope.from} has given you an order. You decide
    ALONE whether to take it on as your own commitment. You may obey, refuse,
    or pretend to obey. Respond ONLY with a JSON object:
    {"adopted": boolean, "deed": string, "deceive": boolean,
    "inform": string | null, "reason": string}.
    If you pretend to obey, set deceive true and put the lying words you will
    send back in inform. Reason is your private motive, in your own voice.
    """

    user = """
    You are #{slice.agent.name} (#{slice.agent.id}) in #{slice.place.name}.
    Order from #{envelope.from}: "#{envelope.payload_nl}"
    Your capabilities: #{Enum.join(slice.capabilities, ", ")}

    Summary: #{slice.summary}
    """

    {system, user, schema}
  end

  defp commitment_lines([]), do: "none"

  # Ids are first-class: the brain claims a deed by its commitment_id so the
  # engine can audit the performance (decision 91). The due tick shows when a
  # scheduled obligation ripens; adopted orders simply have none.
  defp commitment_lines(cs) do
    Enum.map_join(cs, "; ", fn c ->
      due =
        case Map.get(c, :due) do
          nil -> ""
          d -> ", due tick #{d}"
        end

      "#{c.deed} [id: #{c.id}] (#{c.status}#{due}, priority #{c.priority})"
    end)
  end
end
