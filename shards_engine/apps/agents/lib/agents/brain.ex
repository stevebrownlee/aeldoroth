defmodule Agents.Brain do
  @moduledoc """
  One tier-3 brain: a disposable, stateless OTP actor (decision 29, pattern 9).
  State is the agent id and nothing else — all authority lives in the ledger.
  Kill/restart is a hesitation at the coordinator (spec 10). Deliberation and
  adoption handlers arrive with Tasks 5-6.
  """
  use GenServer, restart: :temporary

  def child_spec(agent_id) do
    %{id: {:brain, agent_id}, start: {__MODULE__, :start_link, [agent_id]}, restart: :temporary}
  end

  def start_link(agent_id) do
    GenServer.start_link(__MODULE__, agent_id,
      name: {:via, Registry, {Agents.Registry, agent_id}}
    )
  end

  @impl true
  def init(agent_id), do: {:ok, agent_id}
end
