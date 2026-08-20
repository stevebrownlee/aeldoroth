defmodule WireTest do
  @moduledoc """
  Protocol-level regression tests for the GM console wire updates
  (Task 3): spectate join snapshot carries `dungeon`, and `gm_chat`
  is acknowledged and broadcast as an `:ooc` push from the GM.
  """
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest
  @endpoint Wire.Endpoint

  alias EngineCore.RunSup
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  setup ctx do
    id = "wire_#{ctx.test}_#{:erlang.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "wire_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      RunSup.stop_run(id)
    end)

    {:ok, run_id: id}
  end

  test "spectate join snapshot includes dungeon overview", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})

    assert {:ok, %{dungeon: dungeon}, _chan} =
             join(socket, "spectate:#{id}", %{"role" => "spectate"})

    assert is_map(dungeon)
    places = dungeon["places"]
    assert is_list(places) and length(places) > 0

    assert Enum.any?(places, fn place ->
             is_map(place) and
               place["id"] == "entry_hall" and
               place["name"] == "Entry Hall" and
               is_list(place["connections"]) and
               is_list(place["agents"])
           end)

    # The GM-facing overview includes resident PC agents (Thistle starts here).
    entry_hall = Enum.find(places, & &1["id"] == "entry_hall")
    assert entry_hall
    assert Enum.any?(entry_hall["agents"], & &1["id"] == "pc_thistle")
  end

  test "gm_chat replies :ok and broadcasts an ooc push", %{run_id: id} do
    {:ok, _pid} = start_run(id)
    {:ok, socket} = connect(Wire.Socket, %{"run_id" => id})
    assert {:ok, _snapshot, chan} = join(socket, "spectate:#{id}", %{"role" => "spectate"})

    ref = push(chan, "gm_chat", %{"text" => "Welcome to the table"})
    assert_reply ref, :ok, %{}

    assert_push "ooc", %{agent_id: "GM", text: "Welcome to the table"}
  end

  defp start_run(id) do
    scripts = %{
      interpret: [
        ~s({"verb":"move","target_id":null,"params":{"direction":"east"}}),
        ~s({"verb":"move","target_id":null,"params":{"direction":"east"}})
      ],
      salt: System.unique_integer()
    }

    Session.start_link(id, @yaml, 42, @pcs,
      routing: %{interpret: %{adapter: Scripted, scripts: scripts}}
    )
  end
end
