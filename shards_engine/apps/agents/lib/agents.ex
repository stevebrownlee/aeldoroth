defmodule Agents do
  @moduledoc "Façade over the brain pool. The only module the referee calls."

  @spec ensure_brain(String.t()) :: :ok | {:error, term()}
  def ensure_brain(agent_id), do: ensure_brain(agent_id, 50)

  defp ensure_brain(_agent_id, 0), do: {:error, :brain_unavailable}

  defp ensure_brain(agent_id, tries) do
    case whereis(agent_id) do
      nil -> start_brain(agent_id, tries)
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :ok, else: start_brain(agent_id, tries)
    end
  end

  # Registry key cleanup of a dead holder lags by a scheduler beat; retry
  # briefly until the partition frees the key.
  defp start_brain(agent_id, tries) do
    case DynamicSupervisor.start_child(Agents.DynamicSup, {Agents.Brain, agent_id}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, pid}} when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok
        else
          Process.sleep(1)
          ensure_brain(agent_id, tries - 1)
        end

      error ->
        error
    end
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(agent_id) do
    case Registry.lookup(Agents.Registry, agent_id) do
      [{pid, _}] when is_pid(pid) -> pid
      [] -> nil
    end
  end

  @doc "Kill a brain now: synchronously drop the registry key, then exit the process."
  @spec kill_brain(String.t()) :: :ok
  def kill_brain(agent_id) do
    case whereis(agent_id) do
      nil -> :ok
      pid ->
        Registry.unregister(Agents.Registry, agent_id)
        Process.exit(pid, :kill)
        :ok
    end
  end

  @doc """
  Deliberate through one agent's brain: LLM-first, schema-bound. `{:ok, d}`
  carries the typed action; `{:hesitate, h}` is the ledgered no-decision
  (brain dead, router failure, or out-of-capability proposal).
  """
  @spec deliberate(String.t(), %{slice: map(), ctx: LLMGateway.Ctx.t()}) ::
          {:ok, map()} | {:hesitate, map()} | {:error, :brain_unavailable}
  def deliberate(agent_id, msg) do
    case ensure_brain(agent_id) do
      :ok -> call_brain(agent_id, :deliberate, msg)
      {:error, _reason} -> {:error, :brain_unavailable}
    end
  end

  @doc """
  GenServer call budget for a brain RPC of `class`: the route's adapter
  timeout plus margin. A hardcoded 5s call fires mid-request on live LLM
  calls (haiku deliberation alone can exceed it), turning every live round
  into "brain unavailable" while the brain is still working. Offline paths
  (scripted adapters, no-route heuristics) return instantly either way.
  """
  @default_call_timeout 30_000
  @call_margin 5_000
  @spec call_timeout(:deliberate | :adopt, LLMGateway.Ctx.t()) :: pos_integer()
  def call_timeout(class, %LLMGateway.Ctx{} = ctx) do
    case ctx.routing do
      %{^class => %{timeout: t}} when is_integer(t) and t > 0 -> t + @call_margin
      _ -> @default_call_timeout
    end
  end

  defp call_brain(agent_id, class, msg) do
    case whereis(agent_id) do
      nil ->
        {:error, :brain_unavailable}

      pid ->
        try do
          GenServer.call(pid, {class, msg}, call_timeout(class, msg.ctx))
        catch
          :exit, _ -> {:error, :brain_unavailable}
        end
    end
  end

  @doc """
  Adopt an order through one agent's brain: LLM-first with a deterministic
  heuristic fallback (morale/INT/feasibility vs. the coordinator's ledgered
  d20). `{:ok, d}` is always a decision — flat `%{adopted, deed, deceive,
  inform, reason, request, ctx, audit}`.
  """
  @spec adopt(String.t(), map()) :: {:ok, map()} | {:error, :brain_unavailable}
  def adopt(agent_id, msg) do
    case ensure_brain(agent_id) do
      :ok -> call_brain(agent_id, :adopt, msg)
      {:error, _reason} -> {:error, :brain_unavailable}
    end
  end
end
