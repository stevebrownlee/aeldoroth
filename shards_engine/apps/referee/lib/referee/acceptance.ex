defmodule Referee.Acceptance do
  @moduledoc """
  v1 acceptance proofs as pure functions over a finished run's ledger and
  captured gateway requests (spec §13, plan 6). The harness observes runs;
  it never mutates the pipeline.

  Criteria → functions:
    13.2 emergence      `receipt_chain/2`
    13.3 divergence     `first_divergence/2`, `llm_root?/1`
    13.4 truth barrier  `locality_violations/1`, `hidden_leaks/2`
    13.5 cost control   `spend_invariants/2`, `capped_consistency/2`
  """

  alias EngineCore.{Ledger, World}
  alias Referee.Slice

  @type link :: %{kind: atom(), seq: pos_integer(), summary: String.t()}

  ## 13.3 — fork divergence

  @doc """
  First index at which two ledgers differ. Rows are compared on
  `{tick, class, payload}` — `seq` renumbers per run and is never compared.
  `:identical` only when both ledgers have equal length and equal rows;
  a length difference reports at the shorter ledger's tail.
  """
  @spec first_divergence([Ledger.Event.t()], [Ledger.Event.t()]) ::
          %{index: non_neg_integer(), a: map(), b: map()} | :identical
  def first_divergence(a, b) do
    max = max(length(a), length(b))

    case Enum.find_index(0..max(0, max - 1), fn i -> sig_at(a, i) != sig_at(b, i) end) do
      nil -> :identical
      idx -> %{index: idx, a: row(a, idx), b: row(b, idx)}
    end
  end

  @doc """
  Is this divergence row LLM-sourced — i.e. the fork root traces to model
  output entering the ledger (`:llm` audit, a brain's `:proposed` decision,
  or a `:clarify` question) rather than to engine nondeterminism?
  """
  @spec llm_root?(nil | map()) :: boolean()
  def llm_root?(nil), do: false
  def llm_root?(%{class: :llm}), do: true
  def llm_root?(%{class: :clarify}), do: true
  def llm_root?(%{class: :deliberation, decision: :proposed}), do: true
  def llm_root?(_row), do: false

  ## 13.2 — emergence: one order envelope's receipt chain

  @doc """
  The ordered proof links for one order envelope's emergent cascade:

      envelope_sent → signal_received → envelope_delivered → adopt audit
      → adoption dice → envelope_adopted|rejected → commitment_created
      → proposed deliberation by the adopter → attack dice → damage

  Every present link must strictly increase in `seq`. `{:error,
  {:missing, kind, after_seq}}` names the first absent link so failures are
  diagnosable. `:damage` is reported when present but not required — a
  missed swing is still a complete emergent attack.
  """
  @spec receipt_chain([Ledger.Event.t()], String.t()) ::
          {:ok, [link()]} | {:error, {:missing, atom(), pos_integer() | 0}}
  def receipt_chain(events, envelope_id) do
    with {:envelope_sent, %{seq: s1} = sent} <- find_sent(events, envelope_id),
         {:signal_received, %{seq: s2} = _rcpt} <-
           find_after(events, s1, :signal_received, &(&1.payload[:kind] == :signal_received and &1.payload[:agent_id] == sent.to and &1.payload[:ref] == sent.signal_ref)),
         {:envelope_delivered, %{seq: s3} = _dlvd} <-
           find_after(events, s2, :envelope_delivered, &(&1.payload[:kind] == :envelope_delivered and &1.payload[:id] == envelope_id)),
         {:adopt_audit, %{seq: s4} = audit} <-
           find_after(events, s3, :adopt_audit, &(&1.class == :llm and &1.payload[:class] == :adopt and &1.payload[:agent_id] == sent.to)),
         {:adoption_dice, %{seq: s5} = dice} <-
           find_after(events, s4, :adoption_dice, &(&1.class == :dice and &1.payload[:purpose] == :adoption and &1.payload[:agent_id] == sent.to)),
         {:verdict, %{seq: s6, kind: vk}} <-
           find_verdict(events, s5, envelope_id) do
      base = [
        link(:envelope_sent, s1, "#{sent.from} → #{sent.to} (#{sent.type}): \"#{sent.payload_nl}\""),
        link(:signal_received, s2, "#{sent.to} heard the voicing signal #{short(sent.signal_ref)}"),
        link(:envelope_delivered, s3, "envelope #{envelope_id} delivered"),
        link(:adopt_audit, s4, "adopt brain call (#{audit.payload[:adapter]})"),
        link(:adoption_dice, s5,
          "d20 #{dice.payload[:roll]} vs reliability #{dice.payload[:target]}: " <>
            if(dice.payload[:adopted], do: "adopted", else: "not adopted")),
        link(vk, s6, "envelope #{envelope_id} #{if(vk == :envelope_adopted, do: "adopted", else: "rejected")}")
      ]

      case vk do
        :envelope_rejected ->
          {:ok, base}

        :envelope_adopted ->
          adopted_chain(events, sent, envelope_id, s6, base)
      end
    else
      {:error, e} -> {:error, e}
    end
  end

  defp adopted_chain(events, sent, envelope_id, s6, base) do
    with {:commitment_created, %{seq: s7}} <-
           maybe_commitment(events, s6, envelope_id, sent.to),
         {:proposed, %{seq: s8} = dec} <-
           find_after(events, s7, :proposed, &(&1.class == :deliberation and &1.payload[:agent_id] == sent.to and &1.payload[:decision] == :proposed)),
         {:attack, %{seq: s9, payload: roll_payload}} <-
           find_after(events, s8, :attack, &(&1.class == :dice and &1.payload[:purpose] == :attack and &1.payload[:agent_id] == sent.to)) do
      damage =
        Enum.find(events, fn ev ->
          Map.get(ev, :seq, 0) > s9 and ev.class == :world and ev.payload[:kind] == :damage and ev.payload[:target_id] != sent.to
        end)

      links =
        base ++
          [
            link(:commitment_created, s7, "commitment adopted:#{envelope_id} for #{sent.to}"),
            link(:proposed, s8, "#{sent.to} proposed #{inspect(dec.payload[:verb])}"),
            link(:attack, s9, "#{sent.to} attacked (attack roll #{roll_payload[:roll]})")
          ]

      links =
        case damage do
          nil -> links
          d -> links ++ [link(:damage, Map.get(d, :seq, 0), "damage #{d.payload[:amount]} to #{d.payload[:target_id]}")]
        end

      {:ok, links}
    else
      {:error, e} -> {:error, e}
    end
  end

  defp find_sent(events, envelope_id) do
    case Enum.find(events, &(&1.payload[:kind] == :envelope_sent and &1.payload[:envelope].id == envelope_id)) do
      nil -> {:error, {:missing, :envelope_sent, 0}}
      %{payload: %{envelope: env}, seq: seq} -> {:envelope_sent, Map.put(env, :seq, seq)}
    end
  end
  defp find_after(events, after_seq, kind, pred) do
    case Enum.find(events, &(ev_seq(&1) > after_seq and pred.(&1))) do
      nil -> {:error, {:missing, kind, after_seq}}
      ev -> {kind, ev}
    end
  end

  defp find_verdict(events, after_seq, envelope_id) do
    pred = &(&1.payload[:kind] in [:envelope_adopted, :envelope_rejected] and &1.payload[:id] == envelope_id)

    case Enum.find(events, &(ev_seq(&1) > after_seq and pred.(&1))) do
      nil -> {:error, {:missing, :envelope_adopted, after_seq}}
      %{payload: %{kind: kind}, seq: seq} -> {:verdict, %{seq: seq, kind: kind}}
    end
  end

  # An adopted order must create the debtor's commitment before the adopter
  # acts on it.
  defp maybe_commitment(events, after_seq, envelope_id, to) do
    pred = &(&1.payload[:kind] == :commitment_created and &1.payload[:commitment][:id] == "adopted:#{envelope_id}" and &1.payload[:commitment][:debtor] == to)

    case Enum.find(events, &(ev_seq(&1) > after_seq and pred.(&1))) do
      nil -> {:error, {:missing, :commitment_created, after_seq}}
      %{seq: seq} -> {:commitment_created, %{seq: seq}}
    end
  end

  defp ev_seq(ev), do: Map.get(ev, :seq, 0)

  ## 13.4 — truth barrier over captured prompts

  @doc """
  Collect every binary from a term — structs walked as maps, atoms skipped
  (ids never appear in prompts; display strings do).
  """
  @spec deep_strings(term()) :: [String.t()]
  def deep_strings(term), do: term |> walk([]) |> Enum.reverse()

  defp walk(binary, acc) when is_binary(binary), do: [binary | acc]
  defp walk(%{__struct__: _} = s, acc), do: walk(Map.from_struct(s), acc)
  defp walk(%{} = map, acc), do: Enum.reduce(map, acc, fn {_k, v}, a -> walk(v, a) end)
  defp walk(list, acc) when is_list(list), do: Enum.reduce(list, acc, &walk/2)
  defp walk(_other, acc), do: acc

  @doc """
  Every display name (agent, place) appearing in a captured prompt must be
  reconstructible from that actor's own information set: its slice, the NL
  of signals it received, and its envelopes. `captured` entries pair one
  drained gateway request with the ledger at capture time plus a world —
  a single world, or a `[pre, post]` bracket list: requests are drained at
  phase boundaries, and a prompt built mid-phase may legitimately reference
  either boundary's information set, so a name is a leak only when it is
  non-local in *every* bracket world.

  Violations are `%{req_index, agent_id, class, leaked}` — a leak is a
  truth-barrier bug in the engine, never an allowlist candidate.
  """
  @spec locality_violations([
          %{
            req: %{agent_id: nil | String.t(), class: atom(), system: String.t(), user: String.t()},
            world: World.t() | [World.t()],
            events: [Ledger.Event.t()]
          }
        ]) :: [%{req_index: non_neg_integer(), agent_id: String.t(), class: atom(), leaked: String.t()}]
  def locality_violations(captured) do
    captured
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, i} ->
      req = entry.req
      worlds = List.wrap(entry.world)
      actor_id = req.agent_id

      own_name =
        Enum.find_value(worlds, fn w ->
          case World.agent(w, actor_id) do
            nil -> nil
            a -> a.name
          end
        end)

      if is_nil(actor_id) or is_nil(own_name) do
        []
      else
        allowed = Enum.map_join(worlds, " \n ", &allowed_blob(&1, entry.events, actor_id))
        prompt = req.system <> " " <> req.user

        candidate_names(hd(worlds))
        |> Enum.reject(&(&1 == own_name))
        |> Enum.filter(&String.contains?(prompt, &1))
        |> Enum.reject(&String.contains?(allowed, &1))
        |> Enum.map(&%{req_index: i, agent_id: actor_id, class: req.class, leaked: &1})
      end
    end)
  end

  @doc """
  Hidden-item names must appear in no prompt, ever, regardless of actor.
  Pass the *loaded* world: discovery flips `is_hidden` during play, but the
  ban is authored truth.
  """
  @spec hidden_leaks([%{req: map()}], World.t()) :: [
          %{req_index: non_neg_integer(), class: atom(), leaked: String.t()}
        ]
  def hidden_leaks(captured, %World{} = loaded) do
    hidden =
      loaded.items
      |> Map.values()
      |> Enum.filter(& &1.is_hidden)
      |> Map.new(&{&1.name, true})

    captured
    |> Enum.with_index()
    |> Enum.flat_map(fn {%{req: req}, i} ->
      prompt = req.system <> " " <> req.user

      hidden
      |> Map.keys()
      |> Enum.filter(&String.contains?(prompt, &1))
      |> Enum.map(&%{req_index: i, class: req.class, leaked: &1})
    end)
  end

  defp allowed_blob(world, events, actor_id) do
    received_refs =
      events
      |> Enum.filter(&(&1.payload[:kind] == :signal_received and &1.payload[:agent_id] == actor_id))
      |> Enum.map(& &1.payload[:ref])
      |> MapSet.new()

    heard_nl =
      events
      |> Enum.filter(&(&1.payload[:kind] == :signal_emitted and &1.payload[:ref] in received_refs))
      |> Enum.map(& &1.payload[:content_nl])

    envelopes =
      events
      |> Enum.filter(&(&1.payload[:kind] == :envelope_sent))
      |> Enum.map(& &1.payload[:envelope])
      |> Enum.filter(&(&1.to == actor_id or &1.from == actor_id))
      |> Enum.flat_map(fn env ->
        peers = [env.to, env.from] |> Enum.map(&name_of(world, &1))
        [env.payload_nl | peers]
      end)

    slice = Slice.for_actor(world, actor_id)

    Enum.join(heard_nl ++ envelopes ++ deep_strings(slice) ++ [name_of(world, actor_id)], " \n ")
  end

  defp name_of(world, id) do
    case World.agent(world, id) do
      nil -> id
      a -> a.name
    end
  end

  defp candidate_names(world) do
    agents = world.agents |> Map.values() |> Enum.map(& &1.name)
    places = world.places |> Map.values() |> Enum.map(& &1.name)
    Enum.uniq(agents ++ places)
  end

  ## 13.5 — spend observability and capped degradation

  @doc """
  The spend report must reconcile with the `:llm` rows it was computed
  from: call counts, token totals, and both facet breakdowns summing to
  the total.
  """
  @spec spend_invariants(map(), [Ledger.Event.t()]) :: :ok | {:error, String.t()}
  def spend_invariants(report, events) do
    llm_rows = for ev <- events, ev.class == :llm, ev.payload[:kind] == :llm_call, do: ev.payload

    total_calls = length(llm_rows)
    tokens_in = Enum.sum_by(llm_rows, &(&1[:tokens_in] || 0))
    tokens_out = Enum.sum_by(llm_rows, &(&1[:tokens_out] || 0))

    class_calls = report.by_class |> Map.values() |> Enum.sum_by(& &1.calls)
    agent_calls = report.by_agent |> Map.values() |> Enum.sum_by(& &1.calls)

    conds = [
      {report.total.calls == total_calls, "total.calls #{report.total.calls} != #{total_calls} llm rows"},
      {report.total.tokens_in == tokens_in, "total.tokens_in #{report.total.tokens_in} != #{tokens_in}"},
      {report.total.tokens_out == tokens_out, "total.tokens_out #{report.total.tokens_out} != #{tokens_out}"},
      {class_calls == total_calls, "by_class calls sum #{class_calls} != #{total_calls}"},
      {agent_calls == total_calls, "by_agent calls sum #{agent_calls} != #{total_calls}"}
    ]

    case Enum.find(conds, fn {ok?, _} -> not ok? end) do
      nil -> :ok
      {_, msg} -> {:error, msg}
    end
  end

  @doc """
  Class-aware degradation under a token cap (spec §10): every LLM-served
  `:narrate` row sits at cumulative spend ≤ cap, at least one narrate
  fallback row sits past the cap (budget engaged, not script exhaustion),
  every `:interpret` row survived the 2× window with verdict `:ok`, and no
  `:deliberate`/`:adopt` row was ever degraded (they never are). Cumulative
  spend is reconstructed from the rows — exact here because every scripted
  call succeeds.
  """
  @spec capped_consistency([Ledger.Event.t()], non_neg_integer()) :: :ok | {:error, String.t()}
  def capped_consistency(events, cap) do
    llm =
      events
      |> Enum.filter(&(&1.class == :llm and &1.payload[:kind] == :llm_call))
      |> Enum.map(& &1.payload)

    {rows, _spend} =
      Enum.map_reduce(llm, 0, fn p, acc ->
        {%{payload: p, before: acc}, acc + (p[:tokens_in] || 0) + (p[:tokens_out] || 0)}
      end)

    narrate_ok = for r <- rows, r.payload[:class] == :narrate and r.payload[:parse_verdict] == :ok, do: r
    narrate_fb = for r <- rows, r.payload[:class] == :narrate and r.payload[:parse_verdict] == :fallback, do: r
    interpret = for r <- rows, r.payload[:class] == :interpret, do: r
    brains = for r <- rows, r.payload[:class] in [:deliberate, :adopt], do: r

    late_ok? = Enum.any?(narrate_ok, &(&1.before > cap))
    engaged? = Enum.any?(narrate_fb, &(&1.before > cap))
    interpret_ok? = interpret != [] and Enum.all?(interpret, &(&1.payload[:parse_verdict] == :ok and &1.before <= 2 * cap))
    brains_ok? = Enum.all?(brains, &(&1.payload[:parse_verdict] in [:ok, :retry_ok]))

    conds = [
      {not late_ok?, "an :ok narrate row was served past the cap (#{cap})"},
      {engaged?, "no budget-degraded narrate fallback past the cap (#{cap})"},
      {interpret_ok?, "interpret degraded or starved inside the 2× window"},
      {brains_ok?, "a deliberate/adopt row shows degradation — brains must never starve"}
    ]

    case Enum.find(conds, fn {ok?, _} -> not ok? end) do
      nil -> :ok
      {_, msg} -> {:error, msg}
    end
  end

  ## shared

  defp sig_at(events, i) do
    case Enum.at(events, i) do
      nil -> nil
      ev -> {ev.tick, ev.class, ev.payload}
    end
  end

  defp row(events, i) do
    case Enum.at(events, i) do
      nil -> :absent
      ev -> %{class: ev.class, tick: ev.tick, payload: ev.payload}
    end
  end

  defp link(kind, seq, summary), do: %{kind: kind, seq: seq, summary: summary}

  defp short(ref), do: String.slice(to_string(ref), 0..11)
end
