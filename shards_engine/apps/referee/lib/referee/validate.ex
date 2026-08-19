defmodule Referee.Validate do
  @moduledoc """
  Stage 2 of the referee pipeline: diegetic validation against the actor's
  beliefs and the world's truth — but only what the character could perceive.

  A validation failure is a *diegetic rejection*: an in-fiction "that doesn't
  work" message, never a system error. Rejections are counted by the caller
  (Run) per actor/tick; three in one tick stall the moment.
  """

  alias EngineCore.{Types, World}
  alias Referee.Resolve

  @doc """
  Speech is not capability-gated: any living agent can shout. Physical verbs
  (`:move`, `:strike`, …) must appear in the actor's capabilities.
  """
  @universal ~w(shout)a

  @spec check(World.t(), Types.Action.t()) :: :ok | {:reject, String.t()}
  def check(world, %Types.Action{actor_id: actor_id, verb: verb} = action) do
    actor = World.agent(world, actor_id)

    cond do
      actor == nil ->
        {:reject, "You are no longer part of this scene."}

      :dead in actor.body.conditions ->
        {:reject, "You are no longer part of this scene."}

      verb not in @universal and verb not in actor.capabilities ->
        {:reject, "You have no way to do that."}

      verb == :move ->
        check_move(world, actor, action)

      verb == :strike ->
        check_strike(actor, action)

      verb == :order ->
        check_order(actor, action)

      true ->
        :ok
    end
  end

  defp check_move(world, actor, action) do
    case Resolve.destination(world, actor.place_id, action) do
      {:ok, _to} -> :ok
      {:error, :no_place} -> {:reject, "You know of no such place."}
      {:error, :sealed} -> {:reject, "The way is sealed shut."}
      {:error, :no_exit} -> {:reject, "There is no way through there."}
    end
  end

  defp check_strike(_actor, %Types.Action{target_id: nil}),
    do: {:reject, "You see nothing there to strike."}

  defp check_strike(actor, %Types.Action{target_id: target_id}) do
    if get_in(actor.beliefs, [actor.place_id, target_id]) != nil do
      :ok
    else
      {:reject, "You see no such creature here."}
    end
  end

  defp check_order(_actor, %Types.Action{target_id: nil}),
    do: {:reject, "You have no one to order."}

  defp check_order(actor, %Types.Action{target_id: target_id}) do
    if get_in(actor.beliefs, [actor.place_id, target_id]) != nil do
      :ok
    else
      {:reject, "You see no such creature here."}
    end
  end
end
