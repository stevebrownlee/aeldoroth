defmodule ClientWeb.SpectateLiveTest do
  @moduledoc """
  SpectateLive surface (plan 7 Task 5): GM console joins the spectate
  channel over a real wire connection; advance is labeled referee
  authority. async: false — start_bandit!/0 publishes a global :wire_url.
  """
  use ClientWeb.ConnCase, async: false

  alias ClientWeb.TestSupport
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  setup %{test: test} do
    TestSupport.start_bandit!()
    id = "run_#{test}_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Session.start_link(id, @yaml, 42, @pcs)
    on_exit(fn -> TestSupport.stop_run(id) end)
    %{run_id: id}
  end

  test "renders snapshot", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn -> render(view) =~ "seq-" end)
    html = render(view)
    assert html =~ "GM console"
    assert html =~ "Tick"
    assert html =~ "Boundaries"
    assert html =~ "LLM spend"
    assert html =~ "calls:"
  end

  test "advance grows the tail", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "seq-" end)

    before = render(view)
    view |> element("[data-testid=advance]") |> render_click()

    eventually(fn ->
      after_html = render(view)
      after_html != before and after_html =~ "seq-"
    end)

    # tick advanced via state_sync: seed-42 join is tick 0; one advance = tick 1
    eventually(fn -> render(view) =~ "Tick 1" end)
  end

  test "pause returns dossiers and resume re-enables advance", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "seq-" end)

    view |> element("[data-testid=pause]") |> render_click()
    eventually(fn -> render(view) =~ "Dossiers" end)
    assert render(view) =~ "Thistle"

    view |> element("[data-testid=resume]") |> render_click()
    eventually(fn -> render(view) =~ "run resumed" end)
  end

  test "spend lever fetches the report over the wire", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "seq-" end)

    view |> element("[data-testid=spend]") |> render_click()

    eventually(fn -> render(view) =~ "LLM spend" end)
    assert render(view) =~ "calls:"
  end

  test "unknown run shows an error without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/runs/nope/gm")

    eventually(fn -> render(view) =~ "unauthorized" end)
    assert render(view) =~ "nope"
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
