defmodule ClientTUI.ConnTest do
  @moduledoc """
  Conn frame handlers (plan 5 Task 9): no network here — WebSockex callbacks
  are public overridable, so each is exercised with a bare state tuple.
  """
  use ExUnit.Case, async: true
  alias ClientTUI.Channel
  alias ClientTUI.Conn

  defp state(over \\ []) do
    struct!(%Conn{parent: self(), topic: "run:r1", heartbeat_every: 30_000, next_ref: 1},
      over
    )
  end

  test "connect arms the heartbeat; the join goes out on the first self-message" do
    assert {:ok, st} = Conn.handle_connect(nil, state())
    assert is_reference(st.hb_ref)

    assert {:reply, {:text, join}, _st} = Conn.handle_info(:send_join, st)
    assert {:ok, {:push, "run:r1", "phx_join", %{}}} = Channel.decode(join)
  end

  test "text frames route pushes to the parent as {:chan, topic, event, payload}" do
    wire = Jason.encode!([nil, nil, "run:r1", "perception", %{"text" => "T1", "tick" => 2}])

    assert {:ok, _st} = Conn.handle_frame({:text, wire}, state())
    assert_receive {:chan, "run:r1", "perception", %{"text" => "T1", "tick" => 2}}
  end

  test "text frames surface replies to the parent as {:chan_reply, ref, status, payload}" do
    wire = Jason.encode!([nil, "4", "run:r1", "phx_reply", %{"status" => "ok", "response" => %{"reply" => "T1"}}])

    assert {:ok, _st} = Conn.handle_frame({:text, wire}, state())
    assert_receive {:chan_reply, "4", :ok, %{"reply" => "T1"}}
  end

  test "malformed frames are dropped without crashing" do
    assert {:ok, _st} = Conn.handle_frame({:text, "{garbage"}, state())
    refute_received {:chan, _, _, _}
  end

  test "the heartbeat timer emits a heartbeat frame to phoenix and re-arms" do
    assert {:reply, {:text, hb}, st} = Conn.handle_info(:heartbeat, state(heartbeat_every: 5))

    assert {:ok, {:push, "phoenix", "heartbeat", %{}}} = Channel.decode(hb)
    assert is_reference(st.hb_ref)
  end

  test "send_event frames carry a fresh ref and the channel topic" do
    assert {:reply, {:text, out}, _st} =
             Conn.handle_cast({:send_event, "declare_intent", %{"text" => "go east"}}, state())

    assert {:ok, {:push, "run:r1", "declare_intent", %{"text" => "go east"}}} = Channel.decode(out)
  end
end
