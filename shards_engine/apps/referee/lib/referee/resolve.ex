defmodule Referee.Resolve do
  @moduledoc """
  Stage 3 of the referee pipeline: action → engine rules → events + new world.

  Wraps the engine's pure rule modules (`Rules.Movement`, `Rules.Combat`,
  `Signals`) behind one contract. Rules return both the event list and the
  already-mutated world; the caller (Run) treats the events as the record and
  never re-folds them over the returned world (scenario.ex convention).

  `{:diegetic_fail, events, world, rng}` covers in-fiction misses: a stale
  belief corrected mid-swing still spends the moment and emits its events.
  """

  alias EngineCore.{Dice, Envelopes, Fold, Ledger, Rules, Signals, Types, World}

  @shout_intensity 7.0

  @doc """
  Where a `:move` action leads, from `from_place`. Target ids must name real
  adjacent places; directions match unsealed edge labels case-insensitively.
  """
  @spec destination(World.t(), String.t(), Types.Action.t()) ::
          {:ok, String.t()} | {:error, :no_exit | :no_place | :sealed}
  def destination(world, from_place, %Types.Action{verb: :move} = action) do
    cond do
      target = action.target_id ->
        cond do
          not is_map_key(world.places, target) -> {:error, :no_place}

          edge = find_edge(world, from_place, target, nil) ->
            if edge.sealed, do: {:error, :sealed}, else: {:ok, target}

          true ->
            {:error, :no_exit}
        end

      dir = action.params[:direction] ->
        edge = find_edge(world, from_place, nil, String.downcase(dir))

        cond do
          edge == nil -> {:error, :no_exit}
          edge.sealed -> {:error, :sealed}
          true -> {:ok, edge.to}
        end

      true ->
        {:error, :no_exit}
    end
  end

  @doc """
  Resolve one validated action through the engine rules. Shouts carry no dice;
  every path returns the world and rng to carry forward.
  """
  @spec act(World.t(), :rand.state(), Types.Action.t()) ::
          {:ok, [Ledger.Event.t()], World.t(), :rand.state()}
          | {:diegetic_fail, [Ledger.Event.t()], World.t(), :rand.state()}
  def act(world, rng, %Types.Action{verb: verb} = action) do
    case verb do
      :wait -> {:ok, [], world, rng}
      :move -> act_move(world, rng, action)
      :strike -> act_strike(world, rng, action)
      :shout -> act_shout(world, rng, action)
:order -> act_order(world, rng, action)
      # Capability-gated verbs without a resolver yet (:parley, :hide, :obey,
      # :flee are in tier-3 caps): the caller already ledgered the decision
      # row, so the moment is spent — never a crash into the owning Session.
      _other -> {:diegetic_fail, [], world, rng}
    end
  end

  defp act_move(world, rng, action) do
    case destination(world, place_of(world, action.actor_id), action) do
      {:ok, to} ->
        case Rules.Movement.traverse(world, rng, action.actor_id, to) do
          {:ok, event, w2, r2} -> {:ok, [event], w2, r2}
          {:error, _reason} -> {:diegetic_fail, [], world, rng}
        end

      {:error, _} ->
        {:diegetic_fail, [], world, rng}
    end
  end

  defp act_strike(world, rng, %Types.Action{actor_id: actor_id, target_id: target_id}) do
    target = World.agent(world, target_id)
    actor = World.agent(world, actor_id)

    stale? = target == nil or actor == nil or target.place_id != actor.place_id

    if stale? do
      # The believed target is gone: correct the belief, spend the swing.
      # The d20 roll is ledgered as RNG-branch evidence even though no
      # to-hit check happens — the swing still happened in the fiction.
      corrected =
        %Ledger.Event{
          seq: 0,
          tick: world.tick,
          class: :world,
          payload: %{kind: :belief_corrected, agent_id: actor_id, place_id: actor.place_id, about: target_id}
        }

      {roll, rng2} = Dice.roll(rng, 20)

      swing =
        %Ledger.Event{
          seq: 0,
          tick: world.tick,
          class: :dice,
          payload: %{purpose: :stale_swing, sides: 20, roll: roll, hit: false, agent_id: actor_id}
        }

      w2 = Fold.fold(world, [corrected])
      {:diegetic_fail, [corrected, swing], w2, rng2}
    else
      case Rules.Combat.attack(world, rng, actor_id, target_id) do
        {:ok, events, w2, r2} -> {:ok, events, w2, r2}
        {:error, _reason} -> {:diegetic_fail, [], world, rng}
      end
    end
  end

  defp act_shout(world, rng, %Types.Action{actor_id: actor_id, target_id: target_id, params: params}) do
    message = Map.get(params, :message, "")
    place = place_of(world, actor_id)

    # Directed speech names its addressee in the content core: perception
    # floors the addressee's fidelity and boosts salience off this field.
    core = %{class: :voices, about: actor_id, count: 1}
    core = if target_id, do: Map.put(core, :to, target_id), else: core

    {:ok, events, w2} =
      Signals.emit_at(
        world,
        actor_id,
        place,
        :sound,
        core,
        @shout_intensity,
        message
      )

    {:ok, events, w2, rng}
  end

  defp act_order(world, rng, %Types.Action{actor_id: actor_id, target_id: target_id, params: params}) do
    message = Map.get(params, :message, "")

    {:ok, events, w2} =
      Envelopes.send(world, actor_id, target_id, :order, message, truth: true)

    {:ok, events, w2, rng}
  end

  defp place_of(world, agent_id) do
    case World.agent(world, agent_id) do
      nil -> raise ArgumentError, "unknown actor #{inspect(agent_id)}"
      a -> a.place_id
    end
  end

  defp find_edge(world, from, to, label) do
    Enum.find(world.edges, fn e ->
      e.from == from and
        (to == nil or e.to == to) and
        (label == nil or e.label == label)
    end)
  end
end
