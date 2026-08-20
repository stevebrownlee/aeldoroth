defmodule ClientWeb.HomeLiveTest do
  @moduledoc """
  Home surface (plan 7 Task 3): run creation + registry listing.
  """

  use ClientWeb.ConnCase, async: true

  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @roster """
  pc_thistle|Thistle|entry_hall|13|12|5|20|1d8
  pc_bramble|Bramble|entry_hall|12|8|6|19|1d6
  """

  @seats [%{id: "pc_thistle", name: "Thistle"}, %{id: "pc_bramble", name: "Bramble"}]

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, hd: 1, hp: 12, ac: 5, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, hd: 1, hp: 8, ac: 6, thac0: 19, damage: "1d6"}
  ]

  test "creates a run and redirects", %{conn: conn} do
    slug = "home_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#new_run", run: %{run_id: slug, seed: "42", roster: @roster})
    |> render_submit()

    assert_redirect(view, "/runs/#{slug}")
    assert %{status: :running} = Session.state(slug)
    assert Session.roster(slug) == @seats
  end

  test "lists active runs", %{conn: conn} do
    slug = "home_list_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, _pid} = Session.start_link(slug, @yaml, 42, @pcs)

    {:ok, _view, html} = live(conn, "/")
    assert html =~ slug
    assert html =~ "running"
  end

  test "rejects a malformed roster line", %{conn: conn} do
    slug = "home_bad_#{:erlang.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#new_run", run: %{run_id: slug, roster: "pc_x|NoPlace"})
      |> render_submit()

    assert html =~ "pc_x|NoPlace"
    assert Session.state(slug) == nil
  end
end
