defmodule Agents.Brain do
  @moduledoc """
  One tier-3 brain: a disposable, stateless OTP actor (decision 29, pattern 9).
  State is the agent id and nothing else — all authority lives in the ledger.
  Kill/restart is a hesitation at the coordinator (spec 10).
  """
  use GenServer, restart: :temporary

  def child_spec(agent_id) do
    %{id: {:brain, agent_id}, start: {__MODULE__, :start_link, [agent_id]}, restart: :temporary}
  end

  def start_link(agent_id) do
    GenServer.start_link(__MODULE__, agent_id,
      name: {:via, Registry, {Agents.Registry, agent_id}}
    )
  end

  @impl true
  def init(agent_id), do: {:ok, agent_id}

  @impl true
  def handle_call({:deliberate, %{slice: slice, ctx: ctx}}, _from, agent_id) do
    {system, user, schema} = Agents.Prompt.deliberate(slice)

    req = %LLMGateway.Request{class: :deliberate, agent_id: agent_id,
      system: system, user: user, schema: schema}

    reply =
      case LLMGateway.Router.complete(ctx, req) do
        {:ok, %LLMGateway.Result{parsed: %{} = parsed}, audit, ctx2} ->
          case verb_from(parsed["verb"], slice.capabilities) do
            nil ->
              {:hesitate, %{reason: "proposed verb outside the capability set",
                            request: req, ctx: ctx2, audit: audit}}

            verb ->
              {:ok, %{action: action_of(parsed, agent_id, verb), reason: parsed["reason"],
                      request: req, ctx: ctx2, audit: audit}}
          end

        {:ok, _result, audit, ctx2} ->
          {:hesitate, %{reason: "deliberation unavailable", request: req, ctx: ctx2, audit: audit}}

        {:error, _reason, audit, ctx2} ->
          {:hesitate, %{reason: "deliberation unavailable", request: req, ctx: ctx2, audit: audit}}
      end

    {:reply, reply, agent_id}
  end

  defp verb_from(verb, caps) when is_binary(verb),
    do: Enum.find(caps, &(Atom.to_string(&1) == verb))
  defp verb_from(_verb, _caps), do: nil

  defp action_of(parsed, agent_id, verb) do
    params =
      %{}
      |> maybe_put(:direction, parsed["direction"])
      |> maybe_put(:message, parsed["message"])

    struct!(EngineCore.Types.Action,
      actor_id: agent_id, verb: verb, target_id: parsed["target_id"], params: params)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
