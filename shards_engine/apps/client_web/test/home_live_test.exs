defmodule ClientWeb.HomeLiveTest do
  @moduledoc """
  Home surface: split GM launch desk + adventurer portal + active-runs registry.
  """

  use ClientWeb.ConnCase, async: true

  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @roster """
  pc_thistle|Thistle|entry_hall|13|12|5|20|1d8
  pc_bramble|Bramble|entry_hall|12|8|6|19|1d6
  """

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, hd: 1, hp: 12, ac: 5, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, hd: 1, hp: 8, ac: 6, thac0: 19, damage: "1d6"}
  ]

  test "renders split GM and Player portals with scenario info and advanced options", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "The Ruined Tower"
    assert html =~ "Mara&#39;s Inn (Common Room), Thornhollow"
    assert html =~ "Game Master Launch Desk"
    assert html =~ "Adventurer Portal &amp; Active Games"
    assert html =~ "Advanced Engine Options"
    assert html =~ ~s|<form id="gm_launch"|
    assert html =~ ~s|<form id="player_join"|
    assert html =~ ~s|name="run[run_id]"|
    assert html =~ ~s|name="run[seed]"|
    assert html =~ ~s|name="run[starting_place]"|
    assert html =~ ~s|name="run[yaml]"|
    assert html =~ ~s|name="run[roster]"|
    assert html =~ ~s|name="join[run_id]"|
    assert html =~ ~s|<button type="submit" class="btn-start-run">Launch Game as GM</button>|
    assert html =~ ~s|<button type="submit" class="btn-join-run">Join Adventure</button>|
  end

  test "GM launch creates a run and redirects to the GM console", %{conn: conn} do
    slug = "web-#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#gm_launch", run: %{run_id: slug, seed: "42", yaml: @yaml})
    |> render_submit()

    assert_redirect(view, "/runs/#{slug}/gm")
    assert %{status: :running} = Session.state(slug)
  end

  test "GM launch with roster override creates a run and redirects to the GM console", %{conn: conn} do
    slug = "web-roster_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#gm_launch", run: %{run_id: slug, seed: "42", yaml: @yaml, roster: @roster})
    |> render_submit()

    assert_redirect(view, "/runs/#{slug}/gm")
    assert %{status: :running} = Session.state(slug)
    assert Session.roster(slug) == [%{id: "pc_thistle", name: "Thistle"}, %{id: "pc_bramble", name: "Bramble"}]
  end

  test "Player join form navigates to /runs/:run_id", %{conn: conn} do
    slug = "web-join_#{:erlang.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#player_join", join: %{run_id: slug})
    |> render_submit()

    assert_redirect(view, "/runs/#{slug}")
  end

  test "lists active runs", %{conn: conn} do
    slug = "web-list_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, _pid} = Session.start_link(slug, @yaml, 42, @pcs)

    {:ok, _view, html} = live(conn, "/")
    assert html =~ slug
    assert html =~ "running"
    assert html =~ "Tick"
    assert html =~ ~s|href="/runs/#{slug}"|
    assert html =~ ~s|href="/runs/#{slug}/gm"|
  end
end
