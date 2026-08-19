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
    """

    user = """
    You are #{slice.agent.name} in #{slice.place.name}.
    Commitments: #{commitment_lines(slice.commitments)}
    Salient here: #{Enum.join(slice.salient, ", ")}
    Believed here: #{Enum.join(slice.believed, ", ")}
    Exits: #{Enum.join(slice.place.exits, ", ")}
    Capabilities: #{Enum.join(slice.capabilities, ", ")}

    Summary: #{slice.summary}
    """

    {system, user, schema}
  end

  defp commitment_lines([]), do: "none"
  defp commitment_lines(cs) do
    Enum.map_join(cs, "; ", &"#{&1.deed} (#{&1.status}, priority #{&1.priority})")
  end
end
