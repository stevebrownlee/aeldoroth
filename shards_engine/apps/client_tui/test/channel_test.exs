defmodule ClientTUI.ChannelTest do
  @moduledoc """
  Line-JSON codec (plan 5 Task 9): Phoenix vsn 2.0.0 array envelope on the
  wire — [join_ref, ref, topic, event, payload] — decoded into plain tuples.
  """
  use ExUnit.Case, async: true
  alias ClientTUI.Channel

  test "encode produces the vsn 2.0.0 array envelope" do
    json = Channel.encode("run:r1", "declare_intent", %{"text" => "go east"}, "1")

    assert {:ok, [nil, "1", "run:r1", "declare_intent", %{"text" => "go east"}]} =
             Jason.decode(json)
  end

  test "decode routes phx_reply to a reply tuple with atom status" do
    wire = Jason.encode!([nil, "7", "run:r1", "phx_reply", %{"status" => "ok", "response" => %{"reply" => "T1"}}])

    assert {:ok, {:reply, "7", :ok, %{"reply" => "T1"}}} = Channel.decode(wire)
  end

  test "decode routes pushes with topic, event, payload" do
    wire = Jason.encode!([nil, nil, "run:r1", "perception", %{"text" => "You go east.", "tick" => 1}])

    assert {:ok, {:push, "run:r1", "perception", %{"text" => "You go east.", "tick" => 1}}} =
             Channel.decode(wire)
  end

  test "decode joins the phx_reply for the initial join like any reply" do
    wire = Jason.encode!([nil, "1", "run:r1", "phx_reply", %{"status" => "ok", "response" => %{"state" => %{}}}])

    assert {:ok, {:reply, "1", :ok, %{"state" => %{}}}} = Channel.decode(wire)
  end

  test "malformed JSON is {:error, :malformed}" do
    assert {:error, :malformed} = Channel.decode("{not json")
    assert {:error, :malformed} = Channel.decode("")
  end

  test "non-array envelope is malformed (we only speak 2.0.0 arrays)" do
    assert {:error, :malformed} = Channel.decode(Jason.encode!(%{"topic" => "t"}))
  end
end
