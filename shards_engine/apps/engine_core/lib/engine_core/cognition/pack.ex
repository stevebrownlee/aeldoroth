defmodule EngineCore.Cognition.Pack do
  @moduledoc "Tier 2: wolf pack drives (spec 5.1)."
  alias EngineCore.{Fold, Ledger, Rules, Types, World}

  @spec decide(World.t(), :rand.state(), Types.Agent.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
  def decide(world, rng, %Types.Agent{} = agent) do
    current_agent = World.agent(world, agent.id) || agent

    if alive?(current_agent) do
      do_decide(world, rng, current_agent)
    else
      {:ok, [], world, rng}
    end
  end

  defp do_decide(world, rng, agent) do
    hp = (agent.body && agent.body.hp) || 0
    hp_max = (agent.statblock && agent.statblock.hp_max) || 1

    cond do
      hp <= hp_max * 0.40 ->
        flee(world, rng, agent)

      intruder = find_nearest_intruder(world, agent) ->
        case Rules.Combat.attack(world, rng, agent.id, intruder.id) do
          {:ok, events, w2, rng2} -> {:ok, events, w2, rng2}
          {:error, _} -> {:ok, [], world, rng}
        end

      true ->
        {:ok, [], world, rng}
    end
  end

  defp flee(world, rng, agent) do
    case first_unsealed_connection(world, agent) do
      nil ->
        {:ok, [], world, rng}

      dest ->
        case Rules.Movement.traverse(world, rng, agent.id, dest) do
          {:ok, ev, _w2, r2} ->
            w3 = Fold.fold(world, [ev])
            {:ok, [ev], w3, r2}

          {:error, _} ->
            {:ok, [], world, rng}
        end
    end
  end

  defp find_nearest_intruder(world, agent) do
    world.agents
    |> Map.values()
    |> Enum.filter(fn a ->
      a.place_id == agent.place_id and
        a.id != agent.id and
        alive?(a) and
        (a.group != agent.group or a.group == nil or agent.group == nil)
    end)
    |> Enum.sort_by(& &1.id)
    |> List.first()
  end

  defp first_unsealed_connection(world, agent) do
    place = World.place(world, agent.place_id)
    conns = (place && place.connections) || []

    conns
    |> Enum.sort()
    |> Enum.find(fn dest ->
      case Enum.find(world.edges, fn e ->
             (e.from == agent.place_id and e.to == dest) or
               (e.from == dest and e.to == agent.place_id)
           end) do
        %Types.Edge{sealed: true} -> false
        _ -> true
      end
    end)
  end

  defp alive?(agent) do
    hp = (agent.body && agent.body.hp) || 0
    conds = (agent.body && agent.body.conditions) || []
    hp > 0 and :dead not in conds
  end
end
