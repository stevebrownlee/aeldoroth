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
end
