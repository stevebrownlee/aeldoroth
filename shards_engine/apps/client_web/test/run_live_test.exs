defmodule ClientWeb.RunLiveTest do
  @moduledoc """
  RunLive surface (plan 7 Task 4): seat picker, wire seat join, declare/ooc
  flows, paused refusal. The play surface talks ONLY to the wire — a real
  Bandit endpoint plus a real ClientTUI.Conn per seat.

  async: false — start_bandit!/0 publishes a global :wire_url env var.
  """
  use ClientWeb.ConnCase, async: false

  alias ClientWeb.TestSupport
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

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

  setup %{test: test} do
    TestSupport.start_bandit!()
    id = "run_#{test}_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Session.start_link(id, @yaml, 42, @pcs)
    on_exit(fn -> TestSupport.stop_run(id) end)
    %{run_id: id}
  end

  test "picker lists PCs when no seat chosen", %{conn: conn, run_id: id} do
    {:ok, _view, html} = live(conn, "/runs/#{id}")

    assert html =~ "Thistle"
    assert html =~ "Bramble"
  end

  test "joining a seat renders the slice", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")

    eventually(fn -> render(view) =~ "Entry Hall" end)

    html = render(view)
    assert html =~ "Thistle"
  end

  test "declare flows and perceptions stream", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head north"})

    eventually(fn -> render(view) =~ "You go north." end)

    {:ok, _} = Session.advance(id)

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head south"})

    eventually(fn -> render(view) =~ "[tick 3] You go south." end)
  end

  test "paused run refuses declares", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    {:ok, %{dossiers: _}} = Session.pause(id)

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head north"})

    eventually(fn -> render(view) =~ "paused" end)
  end

  test "ooc renders for everyone", %{conn: conn, run_id: id} do
    {:ok, view_t, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view_t) =~ "Entry Hall" end)
    {:ok, view_b, _html} = live(conn, "/runs/#{id}?pc=pc_bramble")
    eventually(fn -> render(view_b) =~ "Entry Hall" end)

    view_t
    |> element("form#ooc")
    |> render_submit(%{"text" => "gm, what do I see?"})

    eventually(fn -> render(view_b) =~ "gm, what do I see?" end)
    assert render(view_t) =~ "gm, what do I see?"
  end

  test "status ribbon shows connection state and tick", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    assert render(view) =~ "connected"
    assert render(view) =~ "your move"
  end

  test "verb palette scaffolds the compose box", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    view
    |> element("[data-testid='verb-palette'] button", "Attack")
    |> render_click()

    assert render(view) =~ "value=\"attack \""
  end

  test "exit chip declares its direction through the wire", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    view
    |> element("button.chip-exit", "north")
    |> render_click()

    eventually(fn -> render(view) =~ "You go north." end)
  end

  defp eventually(fun, tries \\ 80) do
    if fun.() do
      :ok
    else
      if tries <= 1, do: flunk("condition not met within timeout")
      Process.sleep(25)
      eventually(fun, tries - 1)
    end
  end
end
