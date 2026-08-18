defmodule EngineCore.Rules.Movement do
  @moduledoc "Room-to-room traversal along edges. Sealed edges block; permeability routing is Plan 2."
  alias EngineCore.{Ledger, Types, World}

  @spec traverse(World.t(), :rand.state(), String.t(), String.t(), keyword()) ::
          {:ok, Ledger.Event.t(), World.t(), :rand.state()} | {:error, atom()}
  def traverse(world, rng, agent_id, to, opts \\ []) do
    with {:ok, agent} <- fetch_agent(world, agent_id),
         :ok <- check_alive(agent),
         {:ok, _place} <- fetch_place(world, to),
         :ok <- check_edge(world, agent.place_id, to) do
      tick = world.tick + 1
      careful = Keyword.get(opts, :careful, false)

      ev = %Ledger.Event{
        seq: 0,
        tick: tick,
        class: :world,
        payload: %{
          kind: :move,
          agent_id: agent_id,
          from: agent.place_id,
          to: to,
          careful: careful
        }
      }

      w2 = %{
        world
        | agents: Map.update!(world.agents, agent_id, &%{&1 | place_id: to}),
          tick: tick
      }

      {:ok, ev, w2, rng}
    end
  end

  defp fetch_agent(world, id),
    do: if(a = World.agent(world, id), do: {:ok, a}, else: {:error, :no_agent})

  defp check_alive(agent) do
    body = agent.body || %{hp: 1, conditions: []}

    if body.hp == 0 or :dead in (body.conditions || []) do
      {:error, :dead}
    else
      :ok
    end
  end

  defp fetch_place(world, id),
    do: if(p = World.place(world, id), do: {:ok, p}, else: {:error, :no_place})

  defp check_edge(world, from, to) do
    from_place = World.place(world, from)

    if from_place && to in (from_place.connections || []) do
      case Enum.find(world.edges, fn e -> e.from == from and e.to == to end) do
        %Types.Edge{sealed: true} -> {:error, :sealed_edge}
        _ -> :ok
      end
    else
      {:error, :not_adjacent}
    end
  end
end
