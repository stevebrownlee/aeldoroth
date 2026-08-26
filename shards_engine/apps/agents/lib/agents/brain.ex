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
  def handle_call({:deliberate, %{slice: slice, ctx: ctx} = msg}, _from, agent_id) do
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
          deliberate_heuristic(slice, agent_id, Map.get(msg, :tick, 0), req, audit, ctx2)

        # No route configured (pure offline mode): the world must still
        # react — deterministic heuristic (decision 30 pattern). Real
        # adapter failures below still hesitate: unknown failures must
        # not fabricate speech.
        {:error, :no_route, audit, ctx2} ->
          deliberate_heuristic(slice, agent_id, Map.get(msg, :tick, 0), req, audit, ctx2)

        {:error, _reason, audit, ctx2} ->
          {:hesitate, %{reason: "deliberation unavailable", request: req, ctx: ctx2, audit: audit}}
      end

    {:reply, reply, agent_id}
  end

  @impl true
  def handle_call({:adopt, msg}, _from, agent_id) do
    %{envelope: envelope, slice: slice, ctx: ctx} = msg

    {system, user, schema} = Agents.Prompt.adopt(slice, envelope)

    req = %LLMGateway.Request{class: :adopt, agent_id: agent_id,
      system: system, user: user, schema: schema}

    reply =
      case LLMGateway.Router.complete(ctx, req) do
        {:ok, %LLMGateway.Result{parsed: %{} = parsed}, audit, ctx2} ->
          {:ok, %{adopted: bool(parsed["adopted"]),
                  deed: parsed["deed"], deceive: bool(parsed["deceive"]),
                  inform: parsed["inform"], reason: parsed["reason"],
                  request: req, ctx: ctx2, audit: audit}}

        {_ok_or_error, _reason, audit, ctx2} ->
          {:ok, heuristic_reply(msg, req, audit, ctx2)}
      end

    {:reply, reply, agent_id}
  end

  # Deterministic fallback (decision 30): LLM proposes, engine disposes —
  # and when the LLM cannot propose at all, morale + INT + feasibility
  # against the ledgered roll decides. Audit mirrors Interpret's fallback.
  defp heuristic_reply(%{roll: roll, debtor: debtor, feasible: feasible} = msg, req, audit, ctx2) do
    target = Agents.Adopt.reliability(debtor, feasible)

    case Agents.Adopt.decide(roll, target) do
      :adopt ->
        %{adopted: true, deed: msg.envelope.payload_nl, deceive: false,
          inform: nil, reason: "heuristic adoption: reliability #{target} held at roll #{roll}",
          request: req, ctx: ctx2, audit: fallback_audit(audit)}

      :reject ->
        %{adopted: false, deed: nil, deceive: false,
          inform: nil, reason: "heuristic rejection: reliability #{target} failed at roll #{roll}",
          request: req, ctx: ctx2, audit: fallback_audit(audit)}
    end
  end
  defp fallback_audit(nil),
    do: %LLMGateway.Audit{class: :adopt, adapter: :heuristic, parse_verdict: :fallback, ok: true}

  defp fallback_audit(%LLMGateway.Audit{} = a),
    do: %LLMGateway.Audit{a | class: :adopt, adapter: :heuristic, parse_verdict: :fallback, ok: true}

  # Deterministic deliberate fallback (decision 30 pattern): with no LLM
  # route the world must still react. Restricted to verbs Resolve.act
  # actually implements. An NPC who can speak addresses the most salient
  # PC in the room with a dossier line (rumors/knowledge, rotated by tick);
  # otherwise it holds. Facts stay engine-side — only phrasing is local.
  defp deliberate_heuristic(slice, agent_id, tick, req, audit, ctx2) do
    pc = most_salient_pc(slice)

    if pc != nil and :shout in Map.get(slice, :capabilities, []) do
      line = fallback_line(slice, pc, tick)

      {:ok, %{
        action: struct!(EngineCore.Types.Action, actor_id: agent_id, verb: :shout, params: %{message: line}),
        reason: "offline heuristic: addresses #{pc[:name]}",
        request: req, ctx: ctx2,
        audit: deliberate_fallback_audit(audit)
      }}
    else
      {:ok, %{
        action: struct!(EngineCore.Types.Action, actor_id: agent_id, verb: :wait, params: %{}),
        reason: "offline heuristic: holds and watches",
        request: req, ctx: ctx2,
        audit: deliberate_fallback_audit(audit)
      }}
    end
  end

  defp deliberate_fallback_audit(nil),
    do: %LLMGateway.Audit{class: :deliberate, adapter: :heuristic, parse_verdict: :fallback, ok: true}

  defp deliberate_fallback_audit(%LLMGateway.Audit{} = a),
    do: %LLMGateway.Audit{a | class: :deliberate, adapter: :heuristic, parse_verdict: :fallback, ok: true}

  defp most_salient_pc(slice) do
    pcs =
      slice
      |> Map.get(:believed_agents, [])
      |> Enum.filter(& &1[:pc])
      |> Map.new(&{&1[:id], &1})

    Enum.find_value(Map.get(slice, :salient, []), fn id -> pcs[id] end) ||
      Enum.at(Map.values(pcs), 0)
  end

  # Dossier comes straight from YAML: string keys.
  defp fallback_line(slice, pc, tick) do
    dossier = Map.get(slice, :dossier, %{})
    lines = List.wrap(dossier["rumors"] || dossier["knowledge"] || [])
    if lines != [] do
      "“#{Enum.at(lines, rem(tick, length(lines)))}”"
    else
      "#{slice.agent[:name]} nods to #{pc[:name]} and keeps watching the room."
    end
  end

  defp bool(true), do: true
  defp bool(_), do: false

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
