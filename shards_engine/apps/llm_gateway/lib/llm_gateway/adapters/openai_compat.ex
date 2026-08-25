defmodule LLMGateway.Adapters.OpenAICompat do
  @moduledoc """
  OpenAI-compatible chat-completions adapter (config-only vendor, decision 36).

  `build_request/2` and `parse_response/2` are pure and unit-tested offline;
  `complete/2` is a thin `:httpc` shell with no test coverage by design
  (offline constraint). Called only from `LLMGateway.Router`.
  """

  alias LLMGateway.{Adapter, Json, Request, Result}

  @behaviour Adapter

  @spec build_request(Request.t(), map()) :: {String.t(), [{String.t(), String.t()}], map()}
  def build_request(%Request{} = req, cfg) do
    key = resolve_key(cfg[:key_ref])

    body = %{
      "model" => cfg[:model],
      "messages" => [
        %{"role" => "system", "content" => req.system},
        %{"role" => "user", "content" => req.user}
      ],
      "temperature" => req.temperature,
      "max_tokens" => req.max_tokens,
      "response_format" => %{"type" => "json_object"}
    }

    headers = [
      {"authorization", "Bearer " <> key},
      {"content-type", "application/json"}
    ]

    {cfg[:endpoint], headers, body}
  end

  @spec parse_response(integer(), binary()) :: {:ok, Result.t()} | {:error, term()}
  def parse_response(200, body) do
    with {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]} = decoded} <-
           Json.decode(body),
         {:ok, usage} <- usage(decoded) do
      {:ok, %Result{content: content, parsed: parse_json(content), usage: usage}}
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

    charlist_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))} end)

    ssl_opts = ssl_opts()

    json_body = Json.encode!(body)

    case :httpc.request(
           :post,
           {~c"#{url}", charlist_headers, ~c"application/json", String.to_charlist(json_body)},
           [ssl: ssl_opts],
           timeout: 30_000
         ) do
      {:ok, {{_, status, _}, _, resp_body}} ->
        parse_response(status, IO.iodata_to_binary(resp_body))

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  defp usage(%{"usage" => %{"prompt_tokens" => tin, "completion_tokens" => tout}}),
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

  defp ssl_opts do
    try do
      case :public_key.cacerts_get() do
        cacerts when is_list(cacerts) and cacerts != [] ->
          [verify: :verify_peer, cacerts: cacerts]

        _ ->
          [verify: :verify_none]
      end
    rescue
      _ -> [verify: :verify_none]
    catch
      _, _ -> [verify: :verify_none]
    end
  end
end
