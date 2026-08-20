defmodule Referee.Run.SessionTest do
  @moduledoc "Task 2: Session.gm_chat/2 and enriched awaiting API."
  use ExUnit.Case, async: true
  alias EngineCore.RunSup
  alias EngineCore.Ledger.Writer
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run.Session

  @yaml Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{
      id: "pc_thistle",
      name: "Thistle",
      place_id: "entry_hall",
      int: 13,
      ac: 5,
      hd: 1,
      hp: 12,
      thac0: 20,
      damage: "1d8"
    },
    %{
      id: "pc_bramble",
      name: "Bramble",
      place_id: "entry_hall",
      int: 12,
      ac: 6,
      hd: 1,
      hp: 8,
      thac0: 19,
      damage: "1d6"
    }
  ]

  defp routing do
    scripts = %{
      interpret: [
        Jason.encode!(%{
          "verb" => "move",
          "target_id" => nil,
          "params" => %{"direction" => "east"}
        })
      ],
      salt: System.unique_integer()
    }

    %{interpret: %{adapter: Scripted, scripts: scripts}}
  end

  defp tmp_dir(tag) do
    dir =
      Path.join(System.tmp_dir!(), "run_session_#{tag}_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp with_session(tag, fun), do: with_session(tag, [], fun)

  defp with_session(tag, opts, fun) do
    id = "run_session_#{tag}_#{:erlang.unique_integer([:positive])}"
    dir = tmp_dir(tag)
    on_exit(fn -> File.rm_rf!(dir) end)

    pcs = Keyword.get(opts, :pcs, @pcs)
    opts = Keyword.delete(opts, :pcs)

    {:ok, pid} =
      Session.start_link(
        id,
        @yaml,
        42,
        pcs,
        Keyword.merge([routing: routing(), data_dir: dir], opts)
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      RunSup.stop_run(id)
    end)

    fun.(id, dir, pid)
  end

  test "gm_chat broadcasts a GM-authored :ooc event", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert :ok = Session.gm_chat(id, "hello table")

      ooc =
        Writer.events(id)
        |> Enum.filter(&(&1.class == :ooc))
        |> Enum.map(& &1.payload)

      assert [%{kind: :ooc, agent_id: "GM", text: "hello table"}] = ooc
    end)
  end

  test "awaiting enriches each PC row with vitals and place name", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, rows} = Session.awaiting(id)

      thistle = Enum.find(rows, &(&1.id == "pc_thistle"))
      assert thistle.name == "Thistle"
      assert thistle.hp == 12
      assert thistle.hp_max == 12
      assert thistle.ac == 5
      assert thistle.thac0 == 20
      assert thistle.place_id == "entry_hall"
      assert thistle.place_name == "Entry Hall"
      assert thistle.last_intent == nil
      assert thistle.prompt == nil

      bramble = Enum.find(rows, &(&1.id == "pc_bramble"))
      assert bramble.hp == 8
      assert bramble.hp_max == 8
      assert bramble.ac == 6
      assert bramble.thac0 == 19
      assert bramble.place_id == "entry_hall"
      assert bramble.place_name == "Entry Hall"
    end)
  end

  test "awaiting reflects live agent place_id and place_name after movement", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, _texts} = Session.advance(id)

      assert {:ok, rows} = Session.awaiting(id)
      thistle = Enum.find(rows, &(&1.id == "pc_thistle"))
      assert thistle.place_id == "guard_room"
      assert thistle.place_name == "Guard Room"

      bramble = Enum.find(rows, &(&1.id == "pc_bramble"))
      assert bramble.place_id == "entry_hall"
      assert bramble.place_name == "Entry Hall"
    end)
  end
end
