defmodule ClientWeb.TestSupport do
  @moduledoc """
  Test + console plumbing (plan 7): Bandit boot on an ephemeral port for
  wire-socket tests and the serve script, plus run teardown. Deliberately
  in `lib/` (not `test/support/`) so `scripts/serve.exs` reuses it; it is
  not part of any player surface.
  """

  alias EngineCore.RunSup
  alias Referee.Run.Session

  @doc """
  Boot Bandit on `ClientWeb.Endpoint` at an ephemeral port and publish it
  as `Application.get_env(:client_web, :wire_url)` (`ws://127.0.0.1:PORT`)
  for LiveViews that open real wire connections. Under ExUnit, kills the
  server and clears the env on test exit; outside tests (serve script) the
  server simply stays up.
  """
  @spec start_bandit!() :: pos_integer()
  def start_bandit! do
    {:ok, pid} = Bandit.start_link(plug: ClientWeb.Endpoint, scheme: :http, port: 0)
    {:ok, {_listen_addr, port}} = ThousandIsland.listener_info(pid)
    Application.put_env(:client_web, :wire_url, "ws://127.0.0.1:#{port}")

    if Process.whereis(ExUnit.Server) do
      ExUnit.Callbacks.on_exit(fn ->
        Application.delete_env(:client_web, :wire_url)

        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
      end)
    end

    port
  end

  @doc "Stop a run session + its engine run (tolerates absent ids)."
  @spec stop_run(String.t()) :: :ok
  def stop_run(run_id) do
    try do
      Session.stop(run_id)
    catch
      :exit, _ -> :ok
    end

    RunSup.stop_run(run_id)
  end
end

defmodule ClientWeb.TestSupport.StubAdapter do
  @moduledoc """
  Non-Scripted adapter stand-in: enough for `LLMGateway.Config.live?/0` to
  see live-shaped routing in tests. Never called — tests that configure it
  never drive an LLM round.
  """

  def complete(_request, _cfg), do: {:error, :stub, %LLMGateway.Audit{}, nil}
end
