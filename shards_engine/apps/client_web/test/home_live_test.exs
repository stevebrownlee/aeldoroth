defmodule ClientWeb.HomeLiveTest do
  @moduledoc """
  Home surface (spec §6): run creation + active-runs registry.
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

  test "renders scenario card with starting place, race/class selects, level/xp, inventory, and spell slots", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "The Ruined Tower"
    assert html =~ "Mara&#39;s Inn (Common Room), Thornhollow"
    assert html =~ "Assemble Your Party"
    assert html =~ "-- Race --"
    assert html =~ "-- Class --"
    assert html =~ "Fighter"
    assert html =~ "Level"
    assert html =~ "XP"
    assert html =~ "THAC0 (1E)"
    assert html =~ "Initial Inventory &amp; Supplies"
    assert html =~ "Enter The Ruined Tower"
    refute html =~ "Internal Character ID"
  end

  test "spells appear only for magic users and prayers only for divine casters", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    # Slot 0 (Fighter) and Slot 1 (Thief) do not have spellbook/prayers by default
    refute html =~ "Arcane Spellbook"
    refute html =~ "Divine Prayers"
    canon_html =
      view
      |> element("button", "Load Canonical Party")
      |> render_click()

    assert canon_html =~ "Arcane Spellbook"
    assert canon_html =~ "Divine Prayers"
    assert canon_html =~ "Add to Spellbook"
    assert canon_html =~ "Add Prayer"
    assert canon_html =~ "Color Spray"
    assert canon_html =~ "Cure Light Wounds"
  end

  test "auto-derives character ID from name when not provided", %{conn: conn} do
    slug = "home_autoid_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#new_run",
        run: %{run_id: slug, seed: "42", yaml: @yaml},
        seat: %{
          "0" => %{
            "name" => "Valerius the Bold",
            "race" => "Human",
            "class" => "Paladin",
            "hp" => "10",
            "ac" => "4",
            "damage" => "1d8",
            "int" => "14"
          },
          "1" => %{"name" => ""}
        }
      )
      |> render_submit()

    assert html =~ ~s|data-testid="seat-link-pc_valerius_the_bold"|
    assert %{status: :running} = Session.state(slug)
    assert [%{id: "pc_valerius_the_bold", name: "Valerius the Bold"}] = Session.roster(slug)
  end
  test "creates a run and shows seat links", %{conn: conn} do
    slug = "home_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#new_run", run: %{run_id: slug, seed: "42", roster: @roster})
      |> render_submit()

    assert html =~ slug
    assert html =~ ~s|data-testid="seat-link-pc_thistle"|
    assert html =~ ~s|data-testid="seat-link-pc_bramble"|
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
    assert html =~ "Tick"
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

  test "creates a run via seat row fields", %{conn: conn} do
    slug = "home_rows_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#new_run",
        run: %{run_id: slug, seed: "42", yaml: @yaml},
        seat: %{
          "0" => %{
            "name" => "Thistle",
            "race" => "Human",
            "class" => "Fighter",
            "int" => "13",
            "hp" => "12",
            "ac" => "5",
            "damage" => "1d8"
          },
          "1" => %{
            "name" => "Bramble",
            "race" => "Halfling",
            "class" => "Thief",
            "int" => "12",
            "hp" => "8",
            "ac" => "6",
            "damage" => "1d6"
          }
        }
      )
      |> render_submit()

    assert html =~ ~s|data-testid="seat-link-pc_thistle"|
    assert html =~ ~s|data-testid="seat-link-pc_bramble"|
    assert %{status: :running} = Session.state(slug)
    assert Session.roster(slug) == @seats
  end

  test "loads canonical 4-player party with full gear, spells, and prayers", %{conn: conn} do
    slug = "home_canon_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("button", "Load Canonical Party")
      |> render_click()

    assert html =~ "Mirage"
    assert html =~ "Sister Lyra"
    assert html =~ "Color Spray"
    assert html =~ "Cure Light Wounds"

    submit_html =
      view
      |> form("#new_run", run: %{run_id: slug, seed: "42", yaml: @yaml})
      |> render_submit()

    assert submit_html =~ ~s|data-testid="seat-link-pc_thistle"|
    assert submit_html =~ ~s|data-testid="seat-link-pc_bramble"|
    assert submit_html =~ ~s|data-testid="seat-link-pc_mirage"|
    assert submit_html =~ ~s|data-testid="seat-link-pc_sister_lyra"|
    assert %{status: :running} = Session.state(slug)
    roster = Session.roster(slug)
    assert length(roster) == 4
  end
end
