defmodule LLMGatewayTest do
  use ExUnit.Case, async: true

  test "module loads and documents the chokepoint" do
    assert Code.ensure_loaded?(LLMGateway)
  end
end
