defmodule Agents do
  @moduledoc "Façade over the brain pool. The only module the referee calls."

  @spec ensure_brain(String.t()) :: :ok | {:error, term()}
  def ensure_brain(agent_id) do
    case whereis(agent_id) do
      nil ->
        case DynamicSupervisor.start_child(Agents.DynamicSup, {Agents.Brain, agent_id}) do
          {:ok, _pid} -> :ok
          {:error, :already_started, _pid} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(agent_id) do
    case Registry.lookup(Agents.Registry, agent_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @spec kill_brain(String.t()) :: :ok
  def kill_brain(agent_id) do
    case whereis(agent_id) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end

    :ok
  end
end
