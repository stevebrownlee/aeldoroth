defmodule Wire.RunChannelTest do
  @moduledoc """
  RunChannel (plan 5 Task 7): the per-PC protocol surface, wire contract
  verbatim. Join claims exclusively and replies slice + last dossier;
  declare_intent/answer flow through Run.Session; tails fan out as typed
  pushes (perception/prompt/dice/state_sync) with strict per-PC isolation.
  """

  use ExUnit.Case, async: true
  import Phoenix.ChannelTest
  @endpoint Wire.Endpoint

  alias EngineCore.{Ledger, RunSup}
  alias EngineCore.Ledger.Writer
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run.Session
  alias Wire.Claims

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  setup ctx do
    id = "chan_#{ctx.test}_#{:erlang.unique_integer([:positive])}"

    on_exit(fn ->
      Session.stop(id)
      RunSup.stop_run(id)
    end)

    {:ok, %{run_id: id}}
  end

  test "join claims the character and replies with slice + dossier", %{run_id: id} do
    {:ok, _pid, socket} = start_run(id)

    assert {:ok, %{state: state, dossier: dossier}, _chan} = join(socket, "run:#{id}", %{})
    assert state.agent.id == "pc_thistle"
    assert state.agent.name == "Thistle"
    assert state.summary =~ "Entry Hall"
    assert is_nil(dossier)

    # exclusive: a second claim for the same PC is refused with the holder
    {:ok, socket2} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_thistle"})
    assert {:error, %{reason: "character_already_claimed"}} = join(socket2, "run:#{id}", %{})
  end

  test "join refuses a character the run does not own", %{run_id: id} do
    {:ok, _pid, _socket} = start_run(id)

    {:ok, stranger} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_stranger"})
    assert {:error, %{reason: "unauthorized"}} = join(stranger, "run:#{id}", %{})
  end

  test "declare_intent pushes perception and state_sync", %{run_id: id} do
    {:ok, _pid, socket} = start_run(id)
    {:ok, _, chan} = join(socket, "run:#{id}", %{})

    ref = push(chan, "declare_intent", %{"text" => "I head east"})
    assert_reply ref, :ok, %{reply: reply}
    assert is_binary(reply)

    assert_push "perception", %{text: text, tick: tick}
    assert is_binary(text) and text != ""
    assert is_integer(tick)

    assert_push "state_sync", %{slice: slice}
    assert slice.agent.place_id == "guard_room"
  end

  test "clarify pushes prompt with the question", %{run_id: id} do
    # east into the guard room; two guards shout (PC believes both); then
    # garbage interpret forces the grammar, whose "attack the goblin" is
    # lethal-but-ambiguous across the identically-named guards.
    {:ok, _pid, socket} =
      start_run(id,
        scripts: %{
          interpret: [move_east_json(), "{garbage", "{garbage", "{garbage"],
          deliberate: [guard_shout("goblin_guard_1"), guard_shout("goblin_guard_2")]
        }
      )

    {:ok, _, chan} = join(socket, "run:#{id}", %{})

    ref = push(chan, "declare_intent", %{"text" => "I head east"})
    assert_reply ref, :ok
    advance_until_believed(id, "goblin_guard_1")
    advance_until_believed(id, "goblin_guard_2")

    ref2 = push(chan, "declare_intent", %{"text" => "attack the goblin"})
    assert_reply ref2, :ok

    assert_push "prompt", %{question: question}
    assert question =~ "which one"
  end

  test "per-PC isolation: other PCs' narrations never pushed", %{run_id: id} do
    {:ok, _pid, socket_a} = start_run(id)
    {:ok, _, _chan_a} = join(socket_a, "run:#{id}", %{})

    {:ok, socket_b} = connect(Wire.Socket, %{"run_id" => id, "character_id" => "pc_bramble"})
    {:ok, _, _chan_b} = join(socket_b, "run:#{id}", %{})

    # Bramble acts: his narration is pushed exactly once (his channel);
    # a broken filter would also push it to Thistle's channel.
    {:ok, %{reply: _}} = Session.declare(id, "pc_bramble", "I head east")
    assert_push "perception", %{text: b_text}
    assert is_binary(b_text)
    refute_push "perception", %{}
  end

  test "ooc is ledgered and acked", %{run_id: id} do
    {:ok, _pid, socket} = start_run(id)
    {:ok, _, chan} = join(socket, "run:#{id}", %{})

    ref = push(chan, "ooc", %{"text" => "gm, what do I see?"})
    assert_reply ref, :ok, %{ack: true}

    assert [%Ledger.Event{class: :ooc, payload: %{kind: :ooc, agent_id: "pc_thistle"}} | _] =
             Writer.events(id) |> Enum.reverse() |> Enum.filter(&(&1.class == :ooc))
  end

  test "sheet replies with the current slice", %{run_id: id} do
    {:ok, _pid, socket} = start_run(id)
    {:ok, _, chan} = join(socket, "run:#{id}", %{})

    ref = push(chan, "sheet", %{"update" => %{}})
    assert_reply ref, :ok, %{state: state}
    assert state.agent.id == "pc_thistle"
  end

  test "own dice push as dice events (open visibility)", %{run_id: id} do
    # east into the guard room, the guard shouts on its first deliberation
    # (PC forms the belief), then the strike's to-hit roll is a :dice event
    # stamped with the actor.
    {:ok, _pid, socket} =
      start_run(id,
        scripts: %{
          interpret: [
            ~s({"verb":"move","target_id":null,"params":{"direction":"east"}}),
            ~s({"verb":"strike","target_id":"goblin_guard_1","params":{}})
          ],
          deliberate: [guard_shout("goblin_guard_1")]
        }
      )

    {:ok, _, chan} = join(socket, "run:#{id}", %{})
    ref = push(chan, "declare_intent", %{"text" => "I head east"})
    assert_reply ref, :ok

    advance_until_believed(id, "goblin_guard_1")

    ref2 = push(chan, "declare_intent", %{"text" => "I strike the guard"})
    assert_reply ref2, :ok

    assert_push "dice", %{event_payload: payload}
    assert payload.agent_id == "pc_thistle"
    assert payload.purpose == :to_hit
  end

  ## Helpers

  defp start_run(id, over \\ []) do
    scripts =
      over
      |> Keyword.get(:scripts, %{interpret: [move_east_json()]})
      |> Map.put(:salt, System.unique_integer())

    routing =
      for {class, _} <- scripts, class != :salt, into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    {:ok, pid} = Session.start_link(id, @yaml, 42, @pcs, routing: routing)
    {:ok, pid, socket_with_pc(id, "pc_thistle")}
  end

  defp move_east_json,
    do: ~s({"verb":"move","target_id":null,"params":{"direction":"east"}})

  defp guard_shout(guard_id),
    do: %{agent_id: guard_id, content: ~s({"verb":"shout","target_id":null,"params":{"message":"Intruders!"},"reason":"raise the alarm"})}

  defp advance_until_believed(id, about, n \\ 20) do
    pc = EngineCore.World.Server.snapshot(id).agents["pc_thistle"]

    if get_in(pc.beliefs, ["guard_room", about]) != nil do
      :ok
    else
      n > 0 || flunk("belief in #{about} never formed")
      {:ok, _} = Session.advance(id)
      advance_until_believed(id, about, n - 1)
    end
  end

  defp socket_with_pc(run_id, pc_id) do
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => run_id, "character_id" => pc_id})
    socket
  end
end
