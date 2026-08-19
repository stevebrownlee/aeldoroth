defmodule LLMGateway.Adapters.Scripted do
  @moduledoc """
  Deterministic queue-per-class adapter for tests and golden replay.

  Queue state lives in the process dictionary keyed by the `:scripts` map;
  replays run single-process, so pops are deterministic. Each test process
  starts with empty state, and a fresh scripts map starts a fresh set of
  queues. Requests are captured so tests can assert on prompt content.
  """

  @behaviour LLMGateway.Adapter
  alias LLMGateway.{Json, Request, Result}

  @spec reset() :: :ok
  def reset do
    Process.delete(__MODULE__)
    Process.delete({__MODULE__, :requests})
    :ok
  end

  @doc """
  Drains captured requests (newest first) so tests can assert on prompt
  content — the truth-barrier property in particular.
  """
  @spec take_requests() :: [Request.t()]
  def take_requests do
    Process.delete({__MODULE__, :requests}) || []
  end

  @impl true
  def complete(%Request{} = req, %{scripts: scripts}) do
    Process.put({__MODULE__, :requests}, [req | Process.get({__MODULE__, :requests}) || []])

    case remaining(scripts) |> Map.get(req.class, []) do
      [] ->
        {:error, :script_exhausted}

      [content | rest] ->
        put_remaining(scripts, Map.put(remaining(scripts), req.class, rest))

        {:ok,
         %Result{
           content: content,
           parsed: parse(content),
           usage: %{
             tokens_in: div(byte_size(req.system) + byte_size(req.user), 4),
             tokens_out: div(byte_size(content), 4)
           }
         }}
    end
  end

  def complete(_req, _cfg), do: {:error, :missing_scripts}

  defp remaining(scripts) do
    case Process.get(__MODULE__) do
      %{^scripts => rem} -> rem
      _ -> scripts
    end
  end

  defp put_remaining(scripts, rem), do: Process.put(__MODULE__, %{scripts => rem})

  defp parse(content) do
    case Json.decode(content) do
      {:ok, %{} = map} -> map
      _ -> nil
    end
  end
end
