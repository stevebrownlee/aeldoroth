defmodule ClientWeb.RunLiveTest do
  @moduledoc """
  RunLive surface (plan 7 Task 4): hero builder, seat join, declare/ooc
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

  test "builder renders with 1-click archetypes and existing party chips", %{conn: conn, run_id: id} do
    {:ok, _view, html} = live(conn, "/runs/#{id}")

    assert html =~ "Create your hero"
    assert html =~ "1-Click Archetypes"
    assert html =~ "Current Party in Thornhollow"
    assert html =~ "Thistle"
    assert html =~ "Bramble"
    assert html =~ "Enter The Ruined Tower"
  end

  test "clicking an archetype populates the 1E hero sheet", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    html =
      view
      |> element("button", "Mirage")
      |> render_click()

    assert html =~ "Illusionist"
    assert html =~ "Color Spray"
    assert html =~ "Phantasmal Force"
    assert html =~ "Read Magic"
    assert html =~ "Robes"
    assert html =~ "Staff"
    assert html =~ "Darts"
  end

  test "submitting the builder creates a PC and redirects to the seat", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    view
    |> form("#hero_builder", %{
      "hero" => %{
        "name" => "Valerius",
        "race" => "Human",
        "class" => "Fighter",
        "level" => "1",
        "xp" => "0",
        "int" => "14",
        "hp" => "10",
        "ac" => "4",
        "damage" => "1d8",
        "armor" => "Chain mail & Shield",
        "weapons" => "Longsword & Dagger",
        "inventory" => "Bedroll, waterskin, rations"
      }
    })
    |> render_submit()

    assert_redirect(view, "/runs/#{id}/pc_valerius")
    assert Enum.any?(Session.roster(id), &(&1.id == "pc_valerius"))
  end

  test "joining a seat renders the slice", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")

    eventually(fn -> render(view) =~ "Entry Hall" end)

    html = render(view)
    assert html =~ "Thistle"
  end

  test "declare flows and perceptions stream on round advance", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head north"})

    {:ok, _} = Session.advance(id)

    eventually(fn -> render(view) =~ "You go north." end)

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head south"})

    {:ok, _} = Session.advance(id)

    eventually(fn -> render(view) =~ "You go south." end)
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

  test "3-panel tabletop layout is rendered on the seat", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    html = render(view)
    assert html =~ ~s(<section class="panel scene-panel" data-testid="scene-panel">)
    assert html =~ ~s(<section class="panel ooc-panel" data-testid="ooc-panel">)
    assert html =~ ~s(<section class="panel action-panel" data-testid="action-panel">)
    assert html =~ "Declare Next Action"
    assert html =~ "OOC Table Chat"
    assert html =~ "Story Chronicle"
  end

  test "ooc chat sends and receives in the dedicated panel", %{conn: conn, run_id: id} do
    {:ok, view_t, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view_t) =~ "Entry Hall" end)
    {:ok, view_b, _html} = live(conn, "/runs/#{id}?pc=pc_bramble")
    eventually(fn -> render(view_b) =~ "Entry Hall" end)

    view_t
    |> element("form#send_ooc")
    |> render_submit(%{"text" => "gm, what do I see?"})

    eventually(fn -> render(view_b) =~ "gm, what do I see?" end)
    assert render(view_t) =~ "gm, what do I see?"
  end

  test "action declaration updates the status badge to Action Ready", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)
    action_status_html = view |> element("[data-testid='action-status']") |> render()
    assert action_status_html =~ "Pending: Please declare your action"
    refute action_status_html =~ "Action Ready"

    view
    |> element("form#declare")
    |> render_submit(%{"text" => "I head north"})

    action_status_after = view |> element("[data-testid='action-status']") |> render()
    assert action_status_after =~ "Action Ready"
    assert action_status_after =~ "I head north"
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

    {:ok, _} = Session.advance(id)

    eventually(fn -> render(view) =~ "You go north." end)
  end

  test "character builder renders authentic 1E Player Character Record layout", %{conn: conn, run_id: id} do
    {:ok, _view, html} = live(conn, "/runs/#{id}")

    # Zone 1: Header & Identity
    assert html =~ "Player Character Record"
    assert html =~ "Patron Deity"
    assert html =~ "Place of Origin"
    assert html =~ "Move Base"

    # Zone 2: Abilities Sub-Table Matrix
    assert html =~ "Hit Adj"
    assert html =~ "Open Doors"
    assert html =~ "Bend Bars"
    assert html =~ "% Know Spell"
    assert html =~ "System Shock"

    # Zone 3: Saving Throws (5 categories)
    assert html =~ "Paralyzation"
    assert html =~ "Petrification"
    assert html =~ "Rod, Staff"
    assert html =~ "Breath Weapon"
    assert html =~ "Spells"

    # Zone 4: Combat Vitals & AC
    assert html =~ "Shieldless"
    assert html =~ "Rear"
    assert html =~ "Surprise"

    # Zone 5: Weapons To-Hit Matrix Table
    assert html =~ "WEAPON"
    assert html =~ "MAG"
    assert html =~ "DAM (S-M)"
    assert html =~ "Pummeling"
    assert html =~ "Grappling"
  end

  test "renders dynamic class-specific bottom section based on selected class", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}")

    # Fighter selected by default -> Warrior Record (Mount, # Attacks)
    html = render(view)
    assert html =~ "Warrior Record"
    assert html =~ "MOUNT"

    # Select Thief -> Rogue Record & Thieving Skills Table
    thief_html =
      view
      |> form("#hero_builder", %{"hero" => %{"class" => "Thief", "race" => "Halfling", "level" => "1"}})
      |> render_change()

    assert thief_html =~ "Rogue Record"
    assert thief_html =~ "PICK POCKETS"
    assert thief_html =~ "OPEN LOCKS"
    assert thief_html =~ "CLIMB WALLS"

    # Select Cleric -> Cleric Record & Turning Undead Table
    cleric_html =
      view
      |> form("#hero_builder", %{"hero" => %{"class" => "Cleric", "race" => "Human", "level" => "1"}})
      |> render_change()

    assert cleric_html =~ "Cleric / Druid Record"
    assert cleric_html =~ "TURNING UNDEAD"
    assert cleric_html =~ "Skel"
    assert cleric_html =~ "Zomb"
    assert cleric_html =~ "Ghoul"
  end

  test "in-game seat has View Full 1E Character Sheet button and modal toggle", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}?pc=pc_thistle")
    eventually(fn -> render(view) =~ "Entry Hall" end)

    html = render(view)
    assert html =~ "View Full 1E Character Sheet"

    # Click to open modal
    view
    |> element("[data-testid=open-full-sheet]")
    |> render_click()

    modal_html = render(view)
    assert modal_html =~ "Player Character Record"
    assert modal_html =~ "Saving Throws (1E)"
    assert modal_html =~ "Weapons &amp; To-Hit Armor Class Matrix"

    # Click to close modal
    view
    |> element("[data-testid=close-sheet-modal]")
    |> render_click()

    closed_html = render(view)
    refute closed_html =~ "sheet-modal-backdrop"
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
