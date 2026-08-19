defmodule ClientTUI.Channel do
  @moduledoc """
  Phoenix Channels vsn 2.0.0 line-JSON codec (`apps/wire/PROTOCOL.md`).

  On the wire every message is the array envelope `[join_ref, ref, topic,
  event, payload]` (topic before event — see Phoenix.Socket.V2.JSONSerializer).
  `phx_reply` frames become reply tuples; everything else is a push.
  """

  @spec encode(String.t(), String.t(), map(), String.t()) :: String.t()
  def encode(topic, event, payload, ref) do
    Jason.encode!([nil, ref, topic, event, payload])
  end

  @spec decode(String.t()) ::
          {:ok, {:reply, String.t(), :ok | :error, map()}}
          | {:ok, {:push, String.t(), String.t(), map()}}
          | {:error, :malformed}
  def decode(text) when is_binary(text) do
    with {:ok, [_, ref, _topic, "phx_reply", body]} when is_map(body) <- Jason.decode(text),
         {:ok, status} <- status(body["status"]),
         {:ok, response} when is_map(response) <- ok(body["response"]) do
      {:ok, {:reply, ref, status, response}}
    else
      {:ok, [_, _ref, topic, event, payload]} when is_map(payload) and event != "phx_reply" ->
        {:ok, {:push, topic, event, payload}}

      _ ->
        {:error, :malformed}
    end
  end

  defp status("ok"), do: {:ok, :ok}
  defp status("error"), do: {:ok, :error}
  defp status(_), do: {:error, :malformed}

  defp ok(response) when is_map(response), do: {:ok, response}
  defp ok(_), do: {:error, :malformed}
end
