defmodule LLMGateway.Adapters.AnthropicTest do
  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.Anthropic
  alias LLMGateway.Request

  @cfg %{
    adapter: Anthropic,
    model: "claude-test",
    endpoint: "https://api.anthropic.com/v1/messages",
    key_ref: :anthropic_main,
    temperature: 0.4,
    max_tokens: 128
  }

  @req struct!(Request,
    class: :interpret,
    system: "be the referee",
    user: "go north",
    temperature: 0.4,
    max_tokens: 128
  )

  test "build_request: x-api-key + anthropic-version headers, system top-level, no response_format" do
    {url, headers, body} = Anthropic.build_request(@req, @cfg)

    assert url == "https://api.anthropic.com/v1/messages"
    assert {"x-api-key", "ak-test-5678"} in headers
    assert {"anthropic-version", "2023-06-01"} in headers
    assert {"content-type", "application/json"} in headers

    assert body["model"] == "claude-test"
    assert body["system"] == "be the referee"
    assert body["temperature"] == 0.4
    assert body["max_tokens"] == 128
    assert body["response_format"] == nil
    assert [%{"role" => "user", "content" => "go north"}] = body["messages"]
  end

  test "parse_response decodes 200 content blocks + usage" do
    body =
      Jason.encode!(%{
        "content" => [%{"type" => "text", "text" => ~s({"verb":"wait"})}],
        "usage" => %{"input_tokens" => 13, "output_tokens" => 4}
      })

    assert {:ok, result} = Anthropic.parse_response(200, body)
    assert result.content == ~s({"verb":"wait"})
    assert result.parsed == %{"verb" => "wait"}
    assert result.usage == %{tokens_in: 13, tokens_out: 4}
  end

  test "parse_response decodes markdown-fenced json" do
    body =
      Jason.encode!(%{
        "content" => [%{"type" => "text", "text" => "```json\n{\"verb\":\"speak\",\"message\":\"welcome\"}\n```"}],
        "usage" => %{"input_tokens" => 20, "output_tokens" => 8}
      })

    assert {:ok, result} = Anthropic.parse_response(200, body)
    assert result.parsed == %{"verb" => "speak", "message" => "welcome"}
  end

  test "parse_response maps vendor error statuses" do
    assert {:error, :unauthorized} = Anthropic.parse_response(401, ~s({}))
    assert {:error, :rate_limited} = Anthropic.parse_response(429, ~s({}))
    assert {:error, :server_error} = Anthropic.parse_response(500, "")
  end

  test "parse_response rejects empty content blocks" do
    assert {:error, {:bad_response, _}} = Anthropic.parse_response(200, ~s({"content": []}))
  end
end
