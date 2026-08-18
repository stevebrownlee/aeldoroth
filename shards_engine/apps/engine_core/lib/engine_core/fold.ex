defmodule EngineCore.Fold do
  @moduledoc "Deterministic state derivation: world = fold(ledger). Snapshots are cached folds."
  import Kernel, except: [apply: 2]
  alias EngineCore.{Ledger, World}

  @spec fold(World.t(), [Ledger.Event.t()]) :: World.t()
  def fold(world, events), do: Enum.reduce(events, world, fn ev, w -> apply(w, ev) end)

  @spec apply(World.t(), Ledger.Event.t()) :: World.t()
  def apply(world, %Ledger.Event{tick: tick, payload: %{kind: kind} = p}) do
    world = %{world | tick: tick}

    case kind do
      :move ->
        update_agent(world, p.agent_id, &%{&1 | place_id: p.to})

      :damage ->
        update_agent(world, p.target_id, fn a ->
          %{a | body: %{a.body | hp: max(0, a.body.hp - p.amount)}}
        end)

      :death ->
        update_agent(world, p.agent_id, &%{&1 | capabilities: []})

      :morale_break ->
        update_agent(world, p.agent_id, fn a ->
          %{a | body: %{a.body | conditions: Enum.uniq([:fleeing | a.body.conditions])}}
        end)

      :tick_advance ->
        %{world | tick: max(world.tick, p.to)}

      other ->
        raise ArgumentError, "unknown payload kind: #{inspect(other)}"
    end
  end

  defp update_agent(world, id, fun) do
    case World.agent(world, id) do
      nil -> world
      a -> %{world | agents: Map.put(world.agents, id, fun.(a))}
    end
  end
end
