defmodule AgentsTest do
  @moduledoc "The Agents façade exists and exposes the brain-pool API."
  use ExUnit.Case, async: true

  test "exports ensure_brain/1" do
    {:module, Agents} = Code.ensure_loaded(Agents)
    assert function_exported?(Agents, :ensure_brain, 1)
  end
end
