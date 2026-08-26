defmodule LLMGateway.Adapters.OpenAICompatTest do
  use ExUnit.Case, async: true
  alias LLMGateway.Adapters.OpenAICompat
  alias LLMGateway.Request

  @cfg %{
    adapter: OpenAICompat,
    model: "gpt-test",
    endpoint: "https://api.example.com/v1/chat/completions",
    key_ref: :openai_main,
    temperature: 0.2,
    max_tokens: 256
  }

  @req struct!(Request,
    class: :interpret,
    system: "be the referee",
    user: "go north",
    temperature: 0.9,
    max_tokens: 99
  )

  test "build_request uses endpoint, bearer auth from key_ref, cfg model/temperature/max_tokens" do
    {url, headers, body} = OpenAICompat.build_request(@req, @cfg)

    assert url == "https://api.example.com/v1/chat/completions"
    assert {"authorization", "Bearer sk-test-1234"} in headers
    assert {"content-type", "application/json"} in headers


    # model/endpoint/key come from route cfg; temperature/max_tokens travel on the
    # request (Router merges class-level routing before dispatch)
    assert body["temperature"] == 0.9
    assert body["max_tokens"] == 99

    # system prompt leads the message list
    assert [%{"role" => "system", "content" => "be the referee"}, %{"role" => "user", "content" => "go north"}] =
             body["messages"]
  end

  test "request body carries no key material (key resolves from env only for headers)" do
    {_url, _headers, body} = OpenAICompat.build_request(@req, @cfg)
    refute Jason.encode!(body) =~ "sk-test-1234"
  end

  test "parse_response decodes 200 with JSON content + usage" do
    body =
      Jason.encode!(%{
        "choices" => [%{"message" => %{"content" => ~s({"verb":"move","target":"north"})}}],
        "usage" => %{"prompt_tokens" => 31, "completion_tokens" => 7}
      })

    assert {:ok, result} = OpenAICompat.parse_response(200, body)
    assert result.content == ~s({"verb":"move","target":"north"})
    assert result.parsed == %{"verb" => "move", "target" => "north"}
    assert result.usage == %{tokens_in: 31, tokens_out: 7}
  end

  test "parse_response maps vendor error statuses" do
    assert {:error, :unauthorized} = OpenAICompat.parse_response(401, ~s({"error": {}}))
    assert {:error, :rate_limited} = OpenAICompat.parse_response(429, ~s({"error": {}}))
    assert {:error, :server_error} = OpenAICompat.parse_response(500, "")
  end

  test "parse_response rejects non-JSON 200 and empty choices" do
    assert {:error, {:bad_response, _}} = OpenAICompat.parse_response(200, "no json here")
    assert {:error, {:bad_response, _}} = OpenAICompat.parse_response(200, ~s({"choices": []}))
  end

  test "complete respects bounded timeout and returns transport error" do
    cfg = Map.merge(@cfg, %{endpoint: "http://192.0.2.1:81", timeout: 50, connect_timeout: 50})
    start_time = System.monotonic_time(:millisecond)
    res = OpenAICompat.complete(@req, cfg)
    duration = System.monotonic_time(:millisecond) - start_time

    assert {:error, {:transport, _}} = res
    assert duration < 500
  end
end
