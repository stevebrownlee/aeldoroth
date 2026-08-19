defmodule Wire.SocketTest do
  @moduledoc """
  Socket connect (plan 5 Task 6): run-scoped claims from connect params.
  Character params grant a per-PC role; anything else spectates; no run_id,
  no socket.
  """
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest
  @endpoint Wire.Endpoint

  alias Wire.Claims

  test "connect with character params assigns pc role" do
    assert {:ok, socket} =
             connect(Wire.Socket, %{"run_id" => "r1", "character_id" => "pc_thistle"})

    assert socket.assigns.run_id == "r1"
    assert socket.assigns.role == {:pc, "pc_thistle"}
  end

  test "connect without character id assigns spectate role" do
    assert {:ok, socket} = connect(Wire.Socket, %{"run_id" => "r1"})
    assert socket.assigns.role == :spectate
  end

  test "connect rejects missing run_id" do
    assert {:error, _} = connect(Wire.Socket, %{"character_id" => "pc_thistle"})
  end

  test "claims are exclusive and released on demand" do
    assert :ok = Claims.claim("r1", "pc_thistle")

    # a second claimant (even the same process) is refused with the holder
    assert {:error, {:already_claimed, pid}} = Claims.claim("r1", "pc_thistle")
    assert is_pid(pid)

    assert :ok = Claims.release("r1", "pc_thistle")
    # release is idempotent
    assert :ok = Claims.release("r1", "pc_thistle")
    assert :ok = Claims.claim("r1", "pc_thistle")
  end
end
