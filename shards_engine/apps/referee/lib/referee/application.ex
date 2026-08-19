defmodule Referee.Application do
  @moduledoc """
  Referee supervision (spec §12.1): one Registry + one DynamicSupervisor
  under which live `Run.Session` processes are started. The pure pipeline
  modules start nothing.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Referee.SessionReg},
      {DynamicSupervisor, name: Referee.SessionSup}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Referee.Supervisor)
  end
end
