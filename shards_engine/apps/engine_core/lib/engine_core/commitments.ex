defmodule EngineCore.Commitments do
  @moduledoc """
  Commitment lifecycle (spec 5.4, decision 30): an obligation exists only
  when the engine records it. Statuses: pending/due/kept/violated.
  """
  alias EngineCore.{Fold, Ledger, Types, World}

  @spec create(World.t(), keyword() | map()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_debtor}
  def create(world, attrs) do
    attrs = Map.new(attrs)
    debtor = attrs.debtor

    if World.agent(world, debtor) == nil,
      do: {:error, :no_debtor},
      else:
        {:ok, [created_event(world.tick, attrs)],
         Fold.fold(world, [created_event(world.tick, attrs)])}
  end

  @spec due(World.t(), integer()) :: [Types.Commitment.t()]
  def due(world, tick) do
    world.agents
    |> Map.values()
    |> Enum.flat_map(& &1.commitments)
    |> Enum.filter(&(&1.status == :pending and &1.due != nil and &1.due <= tick))
    |> Enum.sort_by(&{-&1.priority, &1.debtor, &1.id})
  end

  @spec mark_due(World.t(), String.t(), integer()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def mark_due(world, id, late_by \\ 0) do
    with {:ok, c} <- find(world, id) do
      ev =
        event(world.tick, %{
          kind: :commitment_due,
          id: id,
          debtor: c.debtor,
          late_by: late_by
        })

      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec keep(World.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def keep(world, id) do
    with {:ok, c} <- find(world, id) do
      rearm = if c.every, do: world.tick + c.every

      ev =
        event(world.tick, %{
          kind: :commitment_kept,
          id: id,
          debtor: c.debtor,
          rearm_due: rearm
        })

      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec violate(World.t(), String.t()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def violate(world, id) do
    with {:ok, c} <- find(world, id) do
      ev = event(world.tick, %{kind: :commitment_violated, id: id, debtor: c.debtor})
      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  @spec renegotiate(World.t(), String.t(), integer()) ::
          {:ok, [Ledger.Event.t()], World.t()} | {:error, :no_commitment}
  def renegotiate(world, id, new_due) do
    with {:ok, c} <- find(world, id) do
      ev =
        event(world.tick, %{
          kind: :commitment_renegotiated,
          id: id,
          debtor: c.debtor,
          due: new_due
        })

      {:ok, [ev], Fold.fold(world, [ev])}
    end
  end

  defp find(world, id) do
    world.agents
    |> Map.values()
    |> Enum.find_value(nil, fn a -> Enum.find(a.commitments, &(&1.id == id)) end)
    |> case do
      nil -> {:error, :no_commitment}
      c -> {:ok, c}
    end
  end

  defp created_event(tick, attrs) do
    event(
      tick,
      %{
        kind: :commitment_created,
        commitment: %{
          id: attrs.id,
          debtor: attrs.debtor,
          creditor: attrs[:creditor],
          deed: attrs.deed,
          due: attrs[:due],
          every: attrs[:every],
          priority: Map.get(attrs, :priority, 5)
        }
      }
    )
  end

  defp event(tick, payload),
    do: %Ledger.Event{seq: 0, tick: tick, class: :commitment, payload: payload}
end
