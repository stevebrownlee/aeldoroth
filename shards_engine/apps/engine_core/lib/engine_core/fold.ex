defmodule EngineCore.Fold do
  @moduledoc "Deterministic state derivation: world = fold(ledger). Snapshots are cached folds."
  import Kernel, except: [apply: 2]
  alias EngineCore.{Ledger, World}

  @spec fold(World.t(), [Ledger.Event.t()]) :: World.t()
  def fold(world, events), do: Enum.reduce(events, world, fn ev, w -> apply(w, ev) end)

  @spec apply(World.t(), Ledger.Event.t()) :: World.t()
  def apply(world, %Ledger.Event{tick: tick, payload: %{kind: kind} = p}) do
    world = %{world | tick: max(world.tick, tick)}

    case kind do
      :move ->
        update_agent(world, p.agent_id, &%{&1 | place_id: p.to})

      :damage ->
        update_agent(world, p.target_id, fn a ->
          %{a | body: %{a.body | hp: max(0, a.body.hp - p.amount)}}
        end)

      :death ->
        update_agent(world, p.agent_id, fn a ->
          %{
            a
            | capabilities: [],
              body: %{a.body | conditions: Enum.uniq([:dead | a.body.conditions])}
          }
        end)

      :morale_break ->
        update_agent(world, p.agent_id, fn a ->
          %{a | body: %{a.body | conditions: Enum.uniq([:fleeing | a.body.conditions])}}
        end)

      :tick_advance ->
        %{world | tick: max(world.tick, p.to)}

      :signal_emitted ->
        arrivals =
          for a <- p.arrivals do
            struct!(EngineCore.Types.Arrival,
              ref: a.ref,
              place_id: a.place_id,
              tick: a.tick,
              kind: a.kind,
              intensity: a.intensity,
              about: a.about,
              hops: a.hops,
              origin_place_id: a.origin_place_id,
              content_core: a.content_core,
              content_nl: a.content_nl
            )
          end

        %{
          world
          | signal_seq: max(world.signal_seq, p.ref),
            in_flight:
              Enum.sort_by(
                world.in_flight ++ arrivals,
                &{&1.tick, &1.ref, &1.place_id}
              )
        }

      :signal_arrived ->
        %{
          world
          | in_flight:
              Enum.reject(world.in_flight, fn a ->
                a.ref == p.ref and a.place_id == p.place_id
              end)
        }

      :signal_received ->
        entry = %{count: 0, last_tick: 0, last_fidelity: 0, seen: false, salience: 0.0}

        update_agent(world, p.agent_id, fn a ->
          current = get_in(a.beliefs, [p.place_id, p.about])

          merged =
            case current do
              nil -> %{entry | count: 1}
              c -> %{c | count: c.count + 1}
            end
            |> Map.merge(%{
              last_tick: tick,
              last_fidelity: p.fidelity,
              salience: p.salience,
              seen: (current && current.seen) || p.signal_kind == :sight
            })

          # Clear voiced words (fidelity >= 4) and being-addressed become
          # belief facts, so slices and brains can answer who said what —
          # beliefs are rebuildable views; this stays derived state.
          words =
            if p.fidelity >= 4 and p.signal_kind == :sound and
                 get_in(p, [:content_core, :class]) == :voices,
               do: p.content_nl

          merged = if is_binary(words), do: Map.put(merged, :words, words), else: merged

          merged =
            if get_in(p, [:content_core, :to]) == p.agent_id,
              do: Map.put(merged, :addressed_tick, tick),
              else: merged

          place_map = Map.put(a.beliefs[p.place_id] || %{}, p.about, merged)
          %{a | beliefs: Map.put(a.beliefs, p.place_id, place_map)}
        end)

      :commitment_created ->
        c = struct!(EngineCore.Types.Commitment, Map.to_list(p.commitment))

        update_agent(world, p.commitment.debtor, fn a ->
          %{a | commitments: a.commitments ++ [c]}
        end)

      :commitment_due ->
        update_commitment(world, p.id, &%{&1 | status: :due})

      :commitment_kept ->
        update_commitment(world, p.id, fn c ->
          if p.rearm_due,
            do: %{c | status: :pending, due: p.rearm_due},
            else: %{c | status: :kept}
        end)

      :commitment_violated ->
        update_commitment(world, p.id, &%{&1 | status: :violated})

      :commitment_renegotiated ->
        update_commitment(world, p.id, &%{&1 | due: p.due, status: :pending})

      :boundary_wake ->
        %{
          world
          | boundaries:
              Map.update!(world.boundaries, p.id, fn b ->
                %{b | state: :awake, last_trigger_tick: p.tick, last_trigger_reason: Map.get(p, :reason)}
              end)
        }
        |> wake_agents(p)

      :boundary_refresh ->
        %{
          world
          | boundaries:
              Map.update!(world.boundaries, p.id, fn b ->
                %{b | last_trigger_tick: p.tick}
              end)
        }

      :boundary_sleep ->
        %{
          world
          | boundaries:
              Map.update!(world.boundaries, p.id, fn b ->
                %{b | state: :dormant}
              end)
        }
        |> sleep_agents(p)

      :boundary_catchup ->
        world

      :hazard_triggered ->
        id = p.id

        cond do
          Map.has_key?(world.hazards, id) ->
            %{world | hazards: Map.update!(world.hazards, id, &%{&1 | triggered: true})}

          Map.has_key?(world.hazards, to_string(id)) ->
            %{
              world
              | hazards: Map.update!(world.hazards, to_string(id), &%{&1 | triggered: true})
            }

          true ->
            world
        end

      :hazard_avoided ->
        world

      :cadence_tick ->
        update_agent(world, p.agent_id, fn a ->
          %{a | cadence: %{a.cadence | next_due: p.next_due}}
        end)

      :agent_added ->
        a = struct!(EngineCore.Types.Agent, Map.to_list(p.agent))

        # Mutual presence sweep (mirrors Loader's boot-time seeding): an
        # agent appearing mid-run — an injected PC, a summoned ally — is
        # immediately visible to co-located agents and vice versa. Without
        # this, NPCs never believe a PC standing in their room.
        neighbors =
          world.agents
          |> Map.values()
          |> Enum.reject(&(&1.place_id != a.place_id or &1.body.hp == 0))

        seen = %{count: 1, last_tick: tick, last_fidelity: 3, salience: 6.0, seen: true}

        agents =
          world.agents
          |> Map.put(a.id, %{
            a
            | beliefs:
                Map.put(
                  a.beliefs,
                  a.place_id,
                  Map.new(neighbors, &{&1.id, seen})
                )
          })
          |> Map.new(fn {id, w} ->
            if id != a.id and w.place_id == a.place_id and w.body.hp != 0 do
              place_map = Map.put(w.beliefs[a.place_id] || %{}, a.id, seen)
              {id, %{w | beliefs: Map.put(w.beliefs, a.place_id, place_map)}}
            else
              {id, w}
            end
          end)

        %{world | agents: agents}

      :belief_corrected ->
        update_agent(world, p.agent_id, fn a ->
          place_map = Map.delete(a.beliefs[p.place_id] || %{}, p.about)
          %{a | beliefs: Map.put(a.beliefs, p.place_id, place_map)}
        end)

      :envelope_sent ->
        %{world | envelopes: world.envelopes ++ [struct!(EngineCore.Types.Envelope, Map.to_list(p.envelope))]}

      :envelope_delivered ->
        env = envelope_by_id(world, p.id)

        world
        |> update_envelope(p.id, fn e -> %{e | status: :delivered} end)
        |> update_agent(env.to, fn a ->
          entry = %{count: 1, last_tick: tick, last_fidelity: 3, salience: 6.0, seen: false}
          place_map = Map.put(a.beliefs[p.place_id] || %{}, "#{env.type}:#{env.id}", entry)
          %{a | beliefs: Map.put(a.beliefs, p.place_id, place_map)}
        end)

      :envelope_adopted -> update_envelope(world, p.id, &%{&1 | status: :adopted, adopted: true})
      :envelope_rejected -> update_envelope(world, p.id, &%{&1 | status: :rejected, adopted: false})

      # Non-mutating record kinds (spec §12.3: world = fold(whole ledger);
      # these classes document, they never change world state).
      :prefs_stack -> world
      :clarify -> world
      :narration -> world
      :llm_call -> world
      :dossier -> world
      :paused -> world
      :resumed -> world
      :ooc -> world
      :intent_declared -> world
      other ->
        raise ArgumentError, "unknown payload kind: #{inspect(other)}"
    end
  end

  def apply(world, %Ledger.Event{}), do: world

  @spec update_agent(World.t(), String.t(), (EngineCore.Types.Agent.t() ->
                                               EngineCore.Types.Agent.t())) :: World.t()
  def update_agent(world, id, fun) do
    case World.agent(world, id) do
      nil -> world
      a -> %{world | agents: Map.put(world.agents, id, fun.(a))}
    end
  end

  @spec envelope_by_id(World.t(), String.t()) :: EngineCore.Types.Envelope.t() | nil
  def envelope_by_id(world, id), do: Enum.find(world.envelopes, &(&1.id == id))

  @spec update_envelope(World.t(), String.t(), (EngineCore.Types.Envelope.t() ->
                                                EngineCore.Types.Envelope.t())) :: World.t()
  def update_envelope(world, id, fun) do
    case envelope_by_id(world, id) do
      nil ->
        world

      _env ->
        %{world | envelopes: Enum.map(world.envelopes, fn e -> if e.id == id, do: fun.(e), else: e end)}
    end
  end

  defp update_commitment(world, id, fun) do
    %{
      world
      | agents:
          Map.new(world.agents, fn {aid, a} ->
            {aid,
             %{
               a
               | commitments:
                   Enum.map(a.commitments, fn c ->
                     if c.id == id, do: fun.(c), else: c
                   end)
             }}
          end)
    }
  end

  defp wake_agents(world, p) do
    Enum.reduce(p.bound_agent_ids, world, fn id, w ->
      update_agent(w, id, fn a ->
        cadence =
          case a.cadence do
            %{every: _} = c -> %{c | next_due: max(a_last_next(c), p.tick + 1)}
            nil -> nil
          end

        %{a | attention: :alert, cadence: cadence}
      end)
    end)
  end

  defp a_last_next(%{next_due: nil}), do: 0
  defp a_last_next(%{next_due: n}) when is_integer(n), do: n

  defp sleep_agents(world, p) do
    bound_ids =
      Map.get(p, :bound_agent_ids) ||
        (world.boundaries[p.id] && world.boundaries[p.id].bound_agent_ids) || []

    Enum.reduce(bound_ids, world, fn id, w ->
      update_agent(w, id, fn a -> %{a | attention: :dormant} end)
    end)
  end
end
