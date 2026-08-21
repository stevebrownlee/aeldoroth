defmodule ClientWeb.SpectateLiveTest do
  @moduledoc """
  SpectateLive surface (plan 7 Task 5): GM console joins the spectate
  channel over a real wire connection; advance is labeled referee
  authority. async: false — start_bandit!/0 publishes a global :wire_url.
  """
  use ClientWeb.ConnCase, async: false

  alias ClientWeb.TestSupport
  alias LLMGateway.Adapters.Scripted
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

  test "flow board shows a seated player's declared intent as text", %{conn: conn, run_id: id} do
    # A declare before the console joins: last_intent is a map on the wire
    # (%{"text", "tick"}) — the board must render its text, never the map
    # (regression: raw map crashed Phoenix.HTML.Safe).
    assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")

    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn -> render(view) =~ "go east" end)
    refute render(view) =~ ~s(%{"text" =>)

    html = render(view)
    assert html =~ "READY"
    assert html =~ "Entry Hall"
    assert html =~ "HP 12/12"
    assert html =~ "AC 5"
    assert html =~ "THAC0 20"
    assert html =~ ~s(data-testid="hpbar")
  end

  test "flow board shows an outstanding clarify as text", %{conn: conn} do
    # Real ambiguity: east into the guard room, both identically-named
    # guards shout (beliefs form), garbage interpret forces the grammar,
    # "attack the goblin" is a lethal-verb tie -> clarify. `prompt` is a
    # map on the wire (%{"question", "tick"}) — the board must render its
    # question text, never the map (regression: raw map crashed
    # Phoenix.HTML.Safe on the first clarify).
    scripts = %{
      interpret: [move_east_json(), "{garbage", "{garbage", "{garbage"],
      deliberate: [guard_shout("goblin_guard_1"), guard_shout("goblin_guard_2")],
      salt: System.unique_integer()
    }

    routing =
      for {class, _} <- scripts, class != :salt, into: %{} do
        {class, %{adapter: Scripted, scripts: scripts}}
      end

    id = "run_clarify_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Session.start_link(id, @yaml, 42, @pcs, routing: routing)
    on_exit(fn -> TestSupport.stop_run(id) end)

    assert {:ok, _} = Session.declare(id, "pc_thistle", "I head east")
    advance_until_believed(id, "goblin_guard_1")
    advance_until_believed(id, "goblin_guard_2")

    assert {:ok, %{reply: q}} = Session.declare(id, "pc_thistle", "attack the goblin")
    assert q =~ "which one"

    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn -> render(view) =~ "NEEDS INPUT" end)
    html = render(view)
    assert html =~ "which one"
    refute html =~ ~s(%{"question" =>)
  end

  test "advance grows the tail", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn ->
      html = render(view)

      html =~ "End Round (Run World)" and
        html =~ "Auto-Run until Choice"
    end)

    assert render(view) =~
             "Executes declared player actions &amp; NPC AI deliberation for 1 round."

    assert render(view) =~ "Steps rounds until a player decision is required."

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
    eventually(fn -> render(view) =~ "Pause &amp; Recap" end)
    eventually(fn -> render(view) =~ "seq-" end)

    view |> element("[data-testid=pause]") |> render_click()
    eventually(fn -> render(view) =~ "Dossiers" end)
    assert render(view) =~ "Thistle"

    view |> element("[data-testid=resume]") |> render_click()
    eventually(fn -> render(view) =~ "Resume Play" end)
    eventually(fn -> render(view) =~ "End Round (Run World)" end)
  end

  test "flow board shows a thinking badge while waiting for action", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")

    eventually(fn ->
      html = render(view)
      html =~ "THINKING" and html =~ "Waiting for player action..."
    end)

    assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")

    eventually(fn ->
      html = render(view)
      html =~ "READY" and html =~ "go east"
    end)
  end

  test "spend lever fetches the report over the wire", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "seq-" end)

    view |> element("[data-testid=spend]") |> render_click()

    eventually(fn -> render(view) =~ "LLM spend" end)
    assert render(view) =~ "calls:"
  end

  test "gm chat form submits a table-wide message", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ "seq-" end)

    view
    |> form("[data-testid=gm-chat-form]", %{text: "Party, hold position."})
    |> render_submit()

    eventually(fn -> render(view) =~ "Party, hold position." end)
    assert render(view) =~ "GM"
  end

  test "dungeon overview shows rooms, residents, treasure, hazards, and sealed exits", %{conn: conn, run_id: id} do
    {:ok, view, _html} = live(conn, "/runs/#{id}/gm")
    eventually(fn -> render(view) =~ ~s(data-testid="dungeon-overview") end)
    html = render(view)

    assert html =~ "Entry Hall"
    assert html =~ "Guard Room"
    assert html =~ ~r/giant rat/i
    assert html =~ "north → library"
    assert html =~ "east → guard_room"
    assert html =~ "west → entry_hall"

    entry_hall = room_html(html, "entry_hall")
    assert entry_hall =~ "TRAP"
    assert entry_hall =~ "alarm"
    assert entry_hall =~ "DC 12"
    assert entry_hall =~ "ARMED"
    assert entry_hall =~ "class=\"badge trap\""
    assert entry_hall =~ "class=\"badge armed-tag\""

    library = room_html(html, "library")
    assert library =~ "Potion of Healing"
    assert library =~ "50 gp"
    assert library =~ "HIDDEN"
    assert library =~ "Spellbook"
    assert library =~ "500 gp"
    assert library =~ "SEALED"
    assert library =~ "down"
    assert library =~ "class=\"badge item\""
    assert library =~ "class=\"badge hidden-tag\""
    assert library =~ "class=\"badge sealed-tag\""
  end

  test "unknown run shows an error without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/runs/nope/gm")

    eventually(fn -> render(view) =~ "unauthorized" end)
    assert render(view) =~ "nope"
  end

  # Ambiguity staging (run_channel_test convention): one scripted move,
  # then garbage interpret scripts so every later declare falls through
  # to the deterministic grammar.
  defp move_east_json,
    do: ~s({"verb":"move","target_id":null,"params":{"direction":"east"}})

  defp guard_shout(guard_id),
    do: %{
      agent_id: guard_id,
      content:
        ~s({"verb":"shout","target_id":null,"params":{"message":"Intruders!"},"reason":"raise the alarm"})
    }

  defp room_html(html, room_id) do
    regex = ~r/<article[^>]*data-room-id="#{room_id}"[^>]*>.*?<\/article>/s
    [[match] | _] = Regex.scan(regex, html)
    match
  end

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
