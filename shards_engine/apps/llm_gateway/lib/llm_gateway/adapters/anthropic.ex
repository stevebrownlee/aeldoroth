defmodule LLMGateway.Adapters.Anthropic do
  @moduledoc """
  Anthropic /v1/messages adapter (config-only vendor, decision 36).

  Same purity split as `OpenAICompat`: `build_request/2` + `parse_response/2`
  pure and tested; `complete/2` the untested `:httpc` shell. Called only from
  `LLMGateway.Router`.
  """

  alias LLMGateway.{Adapter, Json, Request, Result}

  @behaviour Adapter

  @spec build_request(Request.t(), map()) :: {String.t(), [{String.t(), String.t()}], map()}
  def build_request(%Request{} = req, cfg) do
    key = resolve_key(cfg[:key_ref])

    body = %{
      "model" => cfg[:model],
      "system" => req.system,
      "messages" => [%{"role" => "user", "content" => req.user}],
      "temperature" => req.temperature,
      "max_tokens" => req.max_tokens
    }

    headers = [
      {"x-api-key", key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    {cfg[:endpoint], headers, body}
  end

  @spec parse_response(integer(), binary()) :: {:ok, Result.t()} | {:error, term()}
  def parse_response(200, body) do
    with {:ok, %{"content" => [%{"type" => "text", "text" => text} | _]} = decoded} <-
           Json.decode(body),
         {:ok, usage} <- usage(decoded) do
      {:ok, %Result{content: text, parsed: parse_json(text), usage: usage}}
    else
      _ -> {:error, {:bad_response, body}}
    end
  end

  def parse_response(401, _body), do: {:error, :unauthorized}
  def parse_response(429, _body), do: {:error, :rate_limited}
  def parse_response(_status, _body), do: {:error, :server_error}

  @impl Adapter
  def complete(%Request{} = req, cfg) do
    {url, headers, body} = build_request(req, cfg)

    case :httpc.request(:post, {~c"#{url}", headers, ~c"application/json", Json.encode!(body)}, ssl: [], timeout: 30_000) do
      {:ok, {{_, status, _}, _, resp_body}} ->
        parse_response(status, IO.iodata_to_binary(resp_body))

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  defp usage(%{"usage" => %{"input_tokens" => tin, "output_tokens" => tout}}),
    do: {:ok, %{tokens_in: tin, tokens_out: tout}}

  defp usage(_), do: {:error, :no_usage}

  defp parse_json(content) do
    case Json.decode(content) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> nil
    end
  end

  defp resolve_key(nil), do: ""
  defp resolve_key(key_ref), do: Application.get_env(:llm_gateway, :keys, %{})[key_ref] || ""
end
