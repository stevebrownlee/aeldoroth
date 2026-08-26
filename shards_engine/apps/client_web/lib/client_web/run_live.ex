defmodule ClientWeb.RunLive do
  @moduledoc """
  Player seat over the wire protocol:
  * `/runs/:run_id` with no PC renders the authentic AD&D 1E Player Character Record
    sheet with 1-click archetypes and full 6-zone layout.
  * `/runs/:run_id/:pc_id` renders the 3-panel live play surface with dedicated
    OOC table chat, action declaration box, and interactive full-sheet modal.
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.PC
  alias Referee.Rules.SheetTables
  alias Referee.Run.Session

  @races ["Human", "Elf", "Half-Elf", "Dwarf", "Halfling", "Gnome", "Half-Orc"]

  @classes [
    "Fighter",
    "Paladin",
    "Ranger",
    "Magic-User",
    "Illusionist",
    "Cleric",
    "Druid",
    "Thief",
    "Assassin",
    "Monk"
  ]

  @alignments [
    "Lawful Good",
    "Neutral Good",
    "Chaotic Good",
    "Lawful Neutral",
    "True Neutral",
    "Chaotic Neutral",
    "Lawful Evil",
    "Neutral Evil",
    "Chaotic Evil"
  ]

  @mu_spells_1 [
    "Charm Person", "Color Spray", "Detect Magic", "Enlarge", "Erase", "Feather Fall",
    "Find Familiar", "Friends", "Hold Portal", "Identify", "Light", "Magic Missile",
    "Protection from Evil", "Read Magic", "Shield", "Shocking Grasp", "Sleep",
    "Spider Climb", "Tenser's Floating Disc", "Unseen Servant", "Ventriloquism", "Write"
  ]

  @mu_spells_2 [
    "Audible Glamer", "Continual Light", "Detect Evil", "Detect Invisibility", "ESP",
    "Fools' Gold", "Forget", "Invisibility", "Knock", "Leomund's Trap", "Levitate",
    "Locate Object", "Magic Mouth", "Mirror Image", "Phantasmal Force", "Pyrotechnics",
    "Ray of Enfeeblement", "Rope Trick", "Scare", "Shatter", "Stinking Cloud", "Strength",
    "Web", "Wizard Lock"
  ]

  @illusionist_spells_1 [
    "Audible Glamer", "Change Self", "Color Spray", "Dancing Lights", "Darkness",
    "Detect Illusion", "Detect Magic", "Fog Cloud", "Gaze Reflection", "Hypnotism",
    "Light", "Phantasmal Force", "Wall of Fog"
  ]

  @illusionist_spells_2 [
    "Blindness", "Blur", "Deafness", "Detect Magic", "False Alignment", "Fool's Gold",
    "Hypnotic Pattern", "Improved Phantasmal Force", "Invisibility", "Magic Mouth",
    "Mirror Image", "Misdirection", "Paralysis", "Scare", "Spectral Force", "Summon Swarm", "Vertigo"
  ]

  @cleric_prayers_1 [
    "Bless", "Combine", "Command", "Create Water", "Cure Light Wounds", "Detect Evil",
    "Detect Magic", "Light", "Protection from Evil", "Purify Food and Drink",
    "Remove Fear", "Resist Cold", "Sanctuary"
  ]

  @cleric_prayers_2 [
    "Augury", "Chant", "Detect Curse", "Find Traps", "Hold Person", "Know Alignment",
    "Resist Fire", "Silence 15' Radius", "Slow Poison", "Snake Charm", "Spiritual Hammer", "Speak with Animals"
  ]

  @druid_prayers_1 [
    "Animal Friendship", "Detect Balance", "Detect Magic", "Detect Snares & Pits",
    "Entangle", "Faerie Fire", "Invisibility to Animals", "Locate Animals",
    "Pass without Trace", "Predict Weather", "Purify Water", "Shillelagh", "Speak with Animals"
  ]

  @druid_prayers_2 [
    "Barkskin", "Charm Person or Mammal", "Create Water", "Cure Light Wounds",
    "Feign Death", "Fire Trap", "Heat Metal", "Locate Plants", "Obscurement",
    "Produce Flame", "Reflecting Pool", "Slow Poison", "Trip", "Warp Wood"
  ]

  @archetypes %{
    "Thistle" => %{
      name: "Thistle",
      race: "Human",
      class: "Fighter",
      level: 1,
      xp: 0,
      alignment: "Neutral Good",
      patron_deity: "Saint Cuthbert",
      religion: "Orthodox",
      place_of_origin: "Mara's Inn, Thornhollow",
      move_base: "12\"",
      str: 17,
      int: 13,
      wis: 11,
      dex: 15,
      con: 16,
      cha: 12,
      com: 10,
      hp: 12,
      ac: 5,
      thac0: 20,
      damage: "1d8",
      armor: "Chain mail & Shield",
      weapons: "Longsword & Dagger",
      inventory: "Backpack, bedroll, tinderbox, waterskin, iron rations (5), torches (3), hemp rope (50 ft), flask of oil (2), mirror, 12 gp",
      spells: [],
      prayers: []
    },
    "Bramble" => %{
      name: "Bramble",
      race: "Halfling",
      class: "Thief",
      level: 1,
      xp: 0,
      alignment: "Neutral",
      patron_deity: "Brandobaris",
      religion: "Halfling Pantheon",
      place_of_origin: "Thornhollow Shire",
      move_base: "9\"",
      str: 11,
      int: 12,
      wis: 10,
      dex: 17,
      con: 14,
      cha: 13,
      com: 11,
      hp: 8,
      ac: 6,
      thac0: 19,
      damage: "1d6",
      armor: "Leather armor",
      weapons: "Shortsword & Shortbow",
      inventory: "Thieves' tools, lockpicks, bedroll, tinderbox, waterskin, iron rations (3), torches (2), rope (50 ft), chalk, silk gloves, 18 gp",
      spells: [],
      prayers: []
    },
    "Mirage" => %{
      name: "Mirage",
      race: "Gnome",
      class: "Illusionist",
      level: 1,
      xp: 0,
      alignment: "Chaotic Good",
      patron_deity: "Baravar Cloakshadow",
      religion: "Gnomish Mysteries",
      place_of_origin: "Underhearth enclave",
      move_base: "9\"",
      str: 8,
      int: 17,
      wis: 12,
      dex: 16,
      con: 13,
      cha: 14,
      com: 12,
      hp: 4,
      ac: 10,
      thac0: 20,
      damage: "1d4",
      armor: "Robes",
      weapons: "Staff & Darts",
      inventory: "Spellbook, ink & quills, parchment (5), bedroll, tinderbox, waterskin, iron rations (3), torches (2), component pouch, 8 gp",
      spells: ["Color Spray", "Phantasmal Force", "Read Magic"],
      prayers: []
    },
    "Sister Lyra" => %{
      name: "Sister Lyra",
      race: "Human",
      class: "Cleric",
      level: 1,
      xp: 0,
      alignment: "Lawful Good",
      patron_deity: "Saint Cuthbert",
      religion: "Church of the Sacred Flame",
      place_of_origin: "Thornhollow Abbey",
      move_base: "12\"",
      str: 14,
      int: 11,
      wis: 16,
      dex: 12,
      con: 15,
      cha: 14,
      com: 13,
      hp: 8,
      ac: 5,
      thac0: 20,
      damage: "1d6",
      armor: "Scale mail & Shield",
      weapons: "Warhammer & Mace",
      inventory: "Wooden holy symbol, holy water (2 vials), bedroll, tinderbox, waterskin, iron rations (5), torches (3), rope (50 ft), bandages, 15 gp",
      spells: [],
      prayers: ["Cure Light Wounds", "Bless", "Purify Food and Drink"]
    }
  }

  @verb_palette [
    {"Look", "look "},
    {"Search", "search the "},
    {"Listen", "listen "},
    {"Attack", "attack "},
    {"Talk", "say "},
    {"Take", "take "},
    {"Use", "use "},
    {"Ready", "ready "},
    {"Wait", "wait"}
  ]

  # Lifecycle ---------------------------------------------------------------

  @impl true
  def mount(%{"run_id" => run_id} = params, _session, socket) do
    raw_pc = params["pc_id"] || params["pc"]
    raw_pc = if is_binary(raw_pc) and String.trim(raw_pc) != "", do: String.trim(raw_pc), else: nil

    {pc, redirect_to} =
      if raw_pc do
        case ensure_pc_present(run_id, raw_pc) do
          {:ok, resolved_pc} -> {resolved_pc, nil}
          :not_found -> {nil, "/runs/#{run_id}"}
        end
      else
        {nil, nil}
      end

    if redirect_to do
      {:ok,
       socket
       |> put_flash(:error, "Character '#{raw_pc}' not found in this run. Create your hero below.")
       |> push_navigate(to: redirect_to)}
    else
      socket =
        assign(socket,
          run_id: run_id,
          pc: pc,
          roster: nil,
          hero: default_hero(),
          races: @races,
          classes: @classes,
          alignments: @alignments,
          archetypes: @archetypes,
          conn: nil,
          slice: nil,
          dossier: nil,
          prompt: nil,
          paused: false,
          tick: 0,
          compose: "",
          hint_shown: false,
          ooc_messages: [],
          action_status: :pending,
          last_declared_text: "",
          show_sheet_modal: false,
          error: nil
        )
        |> stream(:log, [])

      if connected?(socket) && pc && wire_url() do
        case Conn.start_link(wire_url(),
               run_id: run_id,
               character_id: pc,
               parent: self()
             ) do
          {:ok, pid} ->
            {:ok, monitor_conn(assign(socket, conn: pid))}

          {:error, reason} ->
            {:ok, put_flash(socket, :error, "wire connection failed: #{inspect(reason)}")}
        end
      else
        {:ok, assign(socket, roster: Session.roster(run_id))}
      end
    end
  end

  # Builder events ----------------------------------------------------------

  @impl true
  def handle_event("set_archetype", %{"name" => name}, socket) do
    hero =
      case Map.fetch(@archetypes, name) do
        {:ok, data} ->
          update_hero(socket.assigns.hero, Map.new(data, fn {k, v} -> {to_string(k), v} end))
          |> Map.put(:chosen_spell, first(spell_catalog(data.class)))
          |> Map.put(:chosen_prayer, first(prayer_catalog(data.class)))

        :error ->
          socket.assigns.hero
      end

    {:noreply, assign(socket, hero: hero)}
  end

  def handle_event("hero_change", %{"hero" => params}, socket) do
    {:noreply, assign(socket, hero: update_hero(socket.assigns.hero, params))}
  end

  def handle_event("add_spell", _params, socket) do
    {:noreply, assign(socket, hero: add_spell(socket.assigns.hero))}
  end

  def handle_event("remove_spell", %{"spell" => spell}, socket) do
    hero = update_in(socket.assigns.hero.spells, &List.delete(&1, spell))
    {:noreply, assign(socket, hero: hero)}
  end

  def handle_event("add_prayer", _params, socket) do
    {:noreply, assign(socket, hero: add_prayer(socket.assigns.hero))}
  end

  def handle_event("remove_prayer", %{"prayer" => prayer}, socket) do
    hero = update_in(socket.assigns.hero.prayers, &List.delete(&1, prayer))
    {:noreply, assign(socket, hero: hero)}
  end

  def handle_event("open_sheet_modal", _params, socket) do
    {:noreply, assign(socket, show_sheet_modal: true)}
  end

  def handle_event("close_sheet_modal", _params, socket) do
    {:noreply, assign(socket, show_sheet_modal: false)}
  end

  def handle_event("create_hero", %{"hero" => params}, socket) do
    hero = update_hero(socket.assigns.hero, params)

    case validate_hero(hero) do
      {:error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}

      :ok ->
        pc_id = slug_id(hero.name)

        pc_map = %{
          id: pc_id,
          name: hero.name,
          race: hero.race,
          class: hero.class,
          level: hero.level,
          xp: hero.xp,
          int: hero.int,
          hp: hero.hp,
          ac: hero.ac,
          thac0: hero.thac0,
          damage: hero.damage,
          armor: hero.armor,
          weapons: hero.weapons,
          inventory: hero.inventory,
          spells: Enum.join(hero.spells, ", "),
          prayers: Enum.join(hero.prayers, ", ")
        }

        case Session.add_pc(socket.assigns.run_id, pc_map) do
          {:ok, ^pc_id} ->
            {:noreply,
             push_navigate(socket, to: "/runs/#{socket.assigns.run_id}/#{pc_id}")}

          {:ok, other_id} ->
            {:noreply,
             push_navigate(socket, to: "/runs/#{socket.assigns.run_id}/#{other_id}")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "could not enter the world: #{inspect(reason)}")}
        end
    end
  end

  # Play surface events ----------------------------------------------------

  def handle_event("declare", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    event = if socket.assigns.prompt, do: "answer", else: "declare_intent"
    :ok = Conn.send_event(conn, event, %{"text" => text})

    {:noreply,
     assign(socket,
       prompt: nil,
       compose: "",
       hint_shown: true,
       action_status: :ready,
       last_declared_text: text
     )}
  end

  def handle_event("send_ooc", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    :ok = Conn.send_event(conn, "ooc", %{"text" => text})
    {:noreply, socket}
  end

  def handle_event("scaffold", %{"text" => add}, socket) do
    {:noreply, update(socket, :compose, &(&1 <> add))}
  end

  def handle_event("go", %{"dir" => dir}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and dir != "" do
    :ok = Conn.send_event(conn, "declare_intent", %{"text" => dir})
    {:noreply, assign(socket, compose: "", hint_shown: true, action_status: :ready, last_declared_text: dir)}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages ------------------------------------------------------------

  @impl true
  def handle_info({:chan_reply, _ref, :ok, %{"state" => slice} = reply}, socket) do
    {:noreply,
     assign(socket,
       slice: slice,
       dossier: reply["dossier"],
       roster: nil,
       paused: reply["paused"] == true
     )}
  end

  def handle_info({:chan_reply, _ref, :error, %{"reason" => "unauthorized"}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Character not found or not authorized in this run.")
     |> push_navigate(to: "/runs/#{socket.assigns.run_id}")}
  end

  def handle_info({:chan_reply, _ref, :error, %{"reason" => "character_already_claimed"}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "That character seat is already claimed by another player.")
     |> push_navigate(to: "/runs/#{socket.assigns.run_id}")}
  end

  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, put_flash(socket, :error, "referee: #{reason}")}
  end

  def handle_info({:chan, _topic, "perception", %{"text" => text, "tick" => tick}}, socket) do
    new_tick = max(tick, socket.assigns.tick)
    action_status = if new_tick > socket.assigns.tick, do: :pending, else: socket.assigns.action_status
    last_declared_text = if new_tick > socket.assigns.tick, do: "", else: socket.assigns.last_declared_text

    {:noreply,
     socket
     |> stream_insert(:log, log_row("perception", "[tick #{tick}] #{text}"))
     |> assign(tick: new_tick, action_status: action_status, last_declared_text: last_declared_text)}
  end

  def handle_info({:chan, _topic, "ooc", %{"author" => id, "text" => text}}, socket) do
    msg = %{
      id: "ooc-#{System.unique_integer([:positive])}",
      author: id,
      text: text,
      gm?: id == "GM"
    }

    {:noreply, update(socket, :ooc_messages, fn msgs -> msgs ++ [msg] end)}
  end

  def handle_info({:chan, _topic, "prompt", %{"question" => q}}, socket) do
    {:noreply, assign(socket, prompt: q)}
  end

  def handle_info({:chan, _topic, "state_sync", %{"slice" => slice}}, socket) do
    {:noreply, assign(socket, slice: slice)}
  end

  def handle_info({:chan, _topic, "paused", _payload}, socket) do
    {:noreply, assign(socket, paused: true)}
  end

  def handle_info({:chan, _topic, "resumed", _payload}, socket) do
    {:noreply, assign(socket, paused: false)}
  end

  def handle_info({:chan, _topic, "dossier", %{"text" => text}}, socket) do
    {:noreply, assign(socket, dossier: text)}
  end

  def handle_info({:chan, _topic, _event, _payload}, socket), do: {:noreply, socket}
  def handle_info({:chan_reply, _ref, _status, _payload}, socket), do: {:noreply, socket}

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    Process.send_after(self(), :rejoin, 500)
    {:noreply, assign(socket, conn: nil, error: "wire connection lost: #{inspect(reason)}")}
  end

  def handle_info(:rejoin, %{assigns: %{conn: nil, pc: pc, run_id: run_id}} = socket)
      when is_binary(pc) do
    case wire_url() do
      url when is_binary(url) and url != "" ->
        case Conn.start_link(url, run_id: run_id, character_id: pc, parent: self()) do
          {:ok, pid} -> {:noreply, monitor_conn(assign(socket, conn: pid, error: nil))}
          _ ->
            Process.send_after(self(), :rejoin, 1_000)
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end
  def handle_info(:rejoin, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Run <%= @run_id %></h1>

    <%!-- 1. Character Builder (when @pc == nil) --%>
    <div :if={@pc == nil} class="hero-builder panel" data-testid="hero-builder">
      <h2>Create your hero</h2>

      <div :if={@roster != nil && @roster != []} class="party-banner panel" data-testid="party-banner">
        <h3>Current Party in Thornhollow</h3>
        <div class="chip-row">
          <.link
            :for={pc <- @roster}
            navigate={"/runs/#{@run_id}/#{pc.id}"}
            class="chip"
            data-testid={"existing-pc-#{pc.id}"}
          ><%= pc.name %></.link>
        </div>
      </div>

      <div class="archetypes panel">
        <h3>1-Click Archetypes</h3>
        <button
          :for={name <- Map.keys(@archetypes)}
          type="button"
          phx-click="set_archetype"
          phx-value-name={name}
          class="btn-archetype"
          data-testid={"archetype-#{slug_for_testid(name)}"}
        ><%= name %></button>
      </div>

      <form id="hero_builder" phx-change="hero_change" phx-submit="create_hero">
        <%= render_1e_sheet(assigns, @hero, true) %>

        <div style="margin-top: 1rem;">
          <button type="submit" class="btn-start-run" data-testid="enter-world">
            Enter The Ruined Tower
          </button>
        </div>
      </form>
    </div>

    <%!-- 2. Live Play Surface (when @pc != nil) --%>
    <div :if={@pc != nil}>
      <p :if={@error} class="flash-error"><%= @error %></p>

      <div class="status-ribbon">
        <span class={"dot-" <> if(@conn, do: "ok", else: "bad")}>●</span>
        <span><%= if @conn, do: "connected", else: "reconnecting…" %></span>
        <span>·</span>
        <span>tick <%= @tick %></span>
        <span>·</span>
        <span><%= if @paused, do: "paused", else: "your move" %></span>
      </div>

      <h2><%= (@slice && @slice["agent"] && @slice["agent"]["name"]) || @pc %></h2>

      <div class="layout-seat tabletop">
        <%!-- Panel 1: Sensory Scene & Story Chronicle --%>
        <section class="panel scene-panel" data-testid="scene-panel">
          <div class="scene-card">
            <h3><%= (@slice && @slice["place"] && @slice["place"]["name"]) || "Awaiting location" %></h3>
            <p :if={@slice && @slice["place"] && @slice["place"]["description"]}>
              <%= @slice["place"]["description"] %>
            </p>

            <div :if={@slice && believed_agents(@slice) != []} class="believed-agents">
              <strong>Present:</strong>
              <span :for={name <- believed_agents(@slice)} class="chip chip-agent"><%= name %></span>
            </div>

            <p :if={@slice && @slice["place"]} class="exits">
              <strong>Exits:</strong>
              <button
                :for={e <- @slice["place"]["exits_labeled"] || []}
                :if={e["dir"] && !e["sealed"]}
                type="button"
                class="chip chip-exit"
                phx-click="go"
                phx-value-dir={e["dir"]}
              ><%= e["dir"] %></button>
              <span
                :for={e <- @slice["place"]["exits_labeled"] || []}
                :if={e["sealed"] or is_nil(e["dir"])}
                class="chip-static"
              ><%= e["dir"] || e["to"] %><%= if e["sealed"], do: " (sealed)" %></span>
            </p>
          </div>

          <div class="chronicle-card">
            <h3>Story Chronicle</h3>
            <ul id="log" class="log chronicle" phx-hook="ChronicleScroll" phx-update="stream">
              <li :for={{dom_id, row} <- @streams.log} id={dom_id} class={"kind-#{row.kind}"}>
                <%= row.text %>
              </li>
            </ul>
          </div>
        </section>

        <%!-- Panel 2: Live OOC Table Chat --%>
        <section class="panel ooc-panel" data-testid="ooc-panel">
          <h3>OOC Table Chat</h3>

          <ul class="ooc-messages" data-testid="ooc-messages">
            <li :for={msg <- @ooc_messages} class={"ooc-message #{if msg.gm?, do: "ooc-gm", else: "ooc-player"}"}>
              <span
                :if={msg.gm?}
                class="ooc-badge ooc-gm-badge"
                style="color: #d4af37; font-weight: bold;"
              >[GM]</span>
              <span :if={!msg.gm?} class="ooc-badge ooc-player-badge"><%= msg.author %></span>
              <span class="ooc-text"><%= msg.text %></span>
            </li>
          </ul>

          <form id="send_ooc" phx-submit="send_ooc" class="ooc-compose">
            <input name="text" placeholder="table talk" />
            <button type="submit">Send OOC</button>
          </form>
        </section>

        <%!-- Panel 3: Action Declaration & Character Sheet --%>
        <section class="panel action-panel" data-testid="action-panel">
          <div class="action-card">
            <h3>Declare Next Action</h3>

            <div class="verb-palette" data-testid="verb-palette">
              <button
                :for={{label, scaffold} <- verb_palette()}
                type="button"
                class="chip chip-verb"
                phx-click="scaffold"
                phx-value-text={scaffold}
              ><%= label %></button>
            </div>

            <form id="declare" phx-submit="declare">
              <input
                name="text"
                value={@compose}
                placeholder={if @prompt, do: "your answer", else: "declare your next action"}
                disabled={@paused}
              />
              <button type="submit" disabled={@paused}>[ Submit Action ]</button>
            </form>

            <p :if={@paused} class="hint">Paused by the GM — the referee will resume play.</p>
            <p :if={!@hint_shown && !@prompt} class="hint"><%= first_run_hint() %></p>

            <div class="action-status" data-testid="action-status">
              <%= if @action_status == :pending do %>
                <span class="status-pending">🟡 Pending: Please declare your action for Round <%= @tick + 1 %></span>
              <% else %>
                <span class="status-ready">🟢 Action Ready: "<%= @last_declared_text %>" — Waiting for GM to Start Round</span>
              <% end %>
            </div>
          </div>

          <div class="sheet-card">
            <%= if sh = @slice["sheet"] do %>
              <% hp_max = sh["hp_max"] || sh["hp"] %>
              <h3>Character<%= if sh["race"] || sh["class"], do: " • #{Enum.filter([sh["race"], sh["class"]], &(&1 && &1 != "")) |> Enum.join(" ")}" %></h3>

              <p class="hp">
                <strong>HP</strong>
                <span class="hp-numbers"><%= sh["hp"] %> / <%= hp_max %></span>
              </p>
              <div class="hp-bar">
                <div class="hp-fill" style={"width: #{hp_percent(sh)}%"}></div>
              </div>

              <dl class="stats">
                <div><dt>AC</dt><dd><%= sh["ac"] %></dd></div>
                <div><dt>THAC0</dt><dd><%= sh["thac0"] %></dd></div>
                <div :if={sh["int"]}><dt>INT</dt><dd><%= sh["int"] %></dd></div>
                <div><dt>Damage</dt><dd><%= sh["damage"] || "—" %></dd></div>
              </dl>

              <button type="button" class="btn-full-sheet" phx-click="open_sheet_modal" data-testid="open-full-sheet">
                📜 View Full 1E Character Sheet
              </button>
            <% end %>
          </div>

          <section class="dossier panel" :if={@dossier}>
            <h3>Dossier</h3>
            <p><%= @dossier %></p>
          </section>
        </section>
      </div>

      <%= if @show_sheet_modal do %>
        <div class="sheet-modal-backdrop" data-testid="sheet-modal">
          <div class="sheet-modal-content">
            <div class="sheet-modal-header">
              <h3>ADVANCED D&D ™ Player Character Record</h3>
              <button type="button" class="sheet-modal-close" phx-click="close_sheet_modal" data-testid="close-sheet-modal">✕ Close</button>
            </div>
            <%= render_1e_sheet(assigns, sheet_from_slice(@hero, @slice), false) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Authentic 1E Character Sheet Component (Zones 1-6) -----------------------

  defp render_1e_sheet(assigns, h, editable?) do
    assigns = assign(assigns, h: h, editable?: editable?)

    ~H"""
    <div class="sheet-1e-container">
      <input type="hidden" name="hero[spells]" value={Enum.join(@h.spells, ", ")} />
      <input type="hidden" name="hero[prayers]" value={Enum.join(@h.prayers, ", ")} />

      <%!-- Zone 1: Header --%>
      <div class="sheet-1e-header">
        <div>
          <strong>PLAYER NAME:</strong>
          <%= if @editable? do %>
            <input name="hero[player_name]" value={@h.player_name} placeholder="Player Name" style="display:inline-block; width:140px; padding:0.2rem 0.4rem;" />
          <% else %>
            <span><%= @h.player_name %></span>
          <% end %>
        </div>
        <div class="sheet-1e-title">ADVANCED D&D ™ Player Character Record</div>
        <div>
          <strong>CAMPAIGN:</strong>
          <%= if @editable? do %>
            <input name="hero[campaign_name]" value={@h.campaign_name} style="display:inline-block; width:130px; padding:0.2rem 0.4rem;" />
            <strong>#</strong>
            <input name="hero[campaign_num]" value={@h.campaign_num} style="display:inline-block; width:40px; padding:0.2rem 0.4rem;" />
          <% else %>
            <span><%= @h.campaign_name %> #<%= @h.campaign_num %></span>
          <% end %>
        </div>
      </div>

      <%!-- Zone 1: Character Identity & Movement --%>
      <div class="sheet-grid-2col">
        <div class="sheet-box">
          <div class="sheet-box-title">Character Identity</div>
          <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 0.4rem; margin-bottom: 0.4rem;">
            <div>
              <label>Character Name</label>
              <%= if @editable? do %>
                <input name="hero[name]" value={@h.name} placeholder="Character Name" data-testid="hero-name" style="font-weight:bold; font-size:1rem;" />
              <% else %>
                <strong style="font-size:1.1rem; color:#e8d9a8;"><%= @h.name %></strong>
              <% end %>
            </div>
            <div>
              <label>Level / XP</label>
              <%= if @editable? do %>
                <div style="display: flex; gap: 0.3rem;">
                  <input type="number" name="hero[level]" value={@h.level} min="1" style="width: 50px;" />
                  <input type="number" name="hero[xp]" value={@h.xp} min="0" placeholder="XP" />
                </div>
              <% else %>
                <span>Level <%= @h.level %> (XP: <%= @h.xp %>)</span>
              <% end %>
            </div>
          </div>

          <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0.4rem; margin-bottom: 0.4rem;">
            <div>
              <label>Class</label>
              <%= if @editable? do %>
                <select name="hero[class]">
                  <option :for={c <- @classes} value={c} selected={@h.class == c}><%= c %></option>
                </select>
              <% else %>
                <span><%= @h.class %></span>
              <% end %>
            </div>
            <div>
              <label>Race</label>
              <%= if @editable? do %>
                <select name="hero[race]">
                  <option :for={r <- @races} value={r} selected={@h.race == r}><%= r %></option>
                </select>
              <% else %>
                <span><%= @h.race %></span>
              <% end %>
            </div>
            <div>
              <label>Alignment</label>
              <%= if @editable? do %>
                <select name="hero[alignment]">
                  <option :for={al <- @alignments} value={al} selected={@h.alignment == al}><%= al %></option>
                </select>
              <% else %>
                <span><%= @h.alignment %></span>
              <% end %>
            </div>
          </div>

          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.4rem; margin-bottom: 0.4rem;">
            <div>
              <label>Patron Deity</label>
              <%= if @editable? do %>
                <input name="hero[patron_deity]" value={@h.patron_deity} />
              <% else %>
                <span><%= @h.patron_deity %></span>
              <% end %>
            </div>
            <div>
              <label>Religion</label>
              <%= if @editable? do %>
                <input name="hero[religion]" value={@h.religion} />
              <% else %>
                <span><%= @h.religion %></span>
              <% end %>
            </div>
          </div>

          <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 0.4rem;">
            <div>
              <label>Place of Origin</label>
              <%= if @editable? do %>
                <input name="hero[place_of_origin]" value={@h.place_of_origin} />
              <% else %>
                <span><%= @h.place_of_origin %></span>
              <% end %>
            </div>
            <div>
              <label>Move Base</label>
              <%= if @editable? do %>
                <input name="hero[move_base]" value={@h.move_base} />
              <% else %>
                <span><%= @h.move_base %></span>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Zone 3: Saving Throws & Defenses --%>
        <div class="sheet-box">
          <div class="sheet-box-title">Saving Throws (1E) &amp; Resistances</div>
          <table class="sheet-table-1e" style="margin-bottom: 0.6rem;">
            <thead>
              <tr>
                <th>Saving Throw Category</th>
                <th style="text-align: center; width: 60px;">Score</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Paralyzation / Poison / Death Magic</td>
                <td class="num"><span class="sheet-bubble"><%= @h.save_poison %></span></td>
              </tr>
              <tr>
                <td>Petrification / Polymorph</td>
                <td class="num"><span class="sheet-bubble"><%= @h.save_petrification %></span></td>
              </tr>
              <tr>
                <td>Rod, Staff, or Wand</td>
                <td class="num"><span class="sheet-bubble"><%= @h.save_wand %></span></td>
              </tr>
              <tr>
                <td>Breath Weapon</td>
                <td class="num"><span class="sheet-bubble"><%= @h.save_breath %></span></td>
              </tr>
              <tr>
                <td>Spells</td>
                <td class="num"><span class="sheet-bubble"><%= @h.save_spell %></span></td>
              </tr>
            </tbody>
          </table>

          <div style="font-size: 0.78rem;">
            <div><strong>Adjustments:</strong> <%= @h.save_adjustments %></div>
            <div><strong>Resistances:</strong> <%= @h.resistances %></div>
            <div><strong>Detection/Vision:</strong> <%= @h.detection %></div>
            <div><strong>Languages:</strong> <%= @h.languages %></div>
          </div>
        </div>
      </div>

      <%!-- Zone 2: Abilities Sub-Table Matrix --%>
      <div class="sheet-box" style="margin-bottom: 0.8rem;">
        <div class="sheet-box-title">Abilities &amp; Sub-Attributes Matrix</div>
        <table class="sheet-table-1e">
          <thead>
            <tr>
              <th style="width: 30px;">Abil</th>
              <th style="width: 50px; text-align: center;">Score</th>
              <th>Sub-Attributes &amp; Modifiers</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><strong>S</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[str]" value={@h.str} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.str %><%= if @h.str_percent, do: "/#{@h.str_percent}" %>
                <% end %>
              </td>
              <td>
                <span class="stat">Hit Adj: <b><%= @h.hit_adj %></b></span>
                <span class="stat">Dam Adj: <b><%= @h.dam_adj %></b></span>
                <span class="stat">Open Doors: <b><%= @h.open_doors %></b></span>
                <span class="stat">Bend Bars: <b><%= @h.bend_bars %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>I</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[int]" value={@h.int} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.int %>
                <% end %>
              </td>
              <td>
                <span class="stat">Add Lang: <b><%= @h.add_lang %></b></span>
                <span class="stat">% Know Spell: <b><%= @h.know_spell %></b></span>
                <span class="stat">Min Spells: <b><%= @h.min_spells %></b></span>
                <span class="stat">Max Spells: <b><%= @h.max_spells %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>W</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[wis]" value={@h.wis} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.wis %>
                <% end %>
              </td>
              <td>
                <span class="stat">Magical Atk Adj: <b><%= @h.mag_atk_adj %></b></span>
                <span class="stat">Spell Bonus: <b><%= @h.spell_bonus %></b></span>
                <span class="stat">% Spell Failure: <b><%= @h.spell_failure %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>D</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[dex]" value={@h.dex} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.dex %>
                <% end %>
              </td>
              <td>
                <span class="stat">Reaction Adj: <b><%= @h.react_adj %></b></span>
                <span class="stat">Missile Adj: <b><%= @h.missile_adj %></b></span>
                <span class="stat">Defense Adj: <b><%= @h.def_adj %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>C</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[con]" value={@h.con} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.con %>
                <% end %>
              </td>
              <td>
                <span class="stat">HP Adj: <b><%= @h.hp_adj %></b></span>
                <span class="stat">System Shock: <b><%= @h.system_shock %></b></span>
                <span class="stat">Resurrect Survival: <b><%= @h.resurrect_survival %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>CH</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[cha]" value={@h.cha} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.cha %>
                <% end %>
              </td>
              <td>
                <span class="stat">Max Henchmen: <b><%= @h.max_henchmen %></b></span>
                <span class="stat">Loyalty Base: <b><%= @h.loyalty_base %></b></span>
                <span class="stat">Reaction Adj: <b><%= @h.react_cha_adj %></b></span>
              </td>
            </tr>
            <tr>
              <td><strong>CM</strong></td>
              <td class="num">
                <%= if @editable? do %>
                  <input type="number" name="hero[com]" value={@h.com} min="3" max="18" style="width:45px; text-align:center; padding:0.1rem;" />
                <% else %>
                  <%= @h.com %>
                <% end %>
              </td>
              <td>
                <span class="stat">Reaction Response: <b><%= @h.com_response %></b></span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <%!-- Zone 4: Combat Vitals & Armor Class --%>
      <div class="sheet-grid-2col">
        <div class="sheet-box">
          <div class="sheet-box-title">Armor Class (AC)</div>
          <div style="display: flex; gap: 0.8rem; align-items: center;">
            <div class="sheet-shield">
              <div style="font-size: 0.7rem; color: #8fb7e8;">ARMOR CLASS</div>
              <%= if @editable? do %>
                <input type="number" name="hero[ac]" value={@h.ac} style="width: 72px; text-align: center; font-weight: bold; font-size: 1.25rem; padding: 0.2rem 0.3rem;" />
              <% else %>
                <div class="ac-val"><%= @h.ac %></div>
              <% end %>
            </div>
            <div style="font-size: 0.8rem; flex: 1;">
              <div>
                <strong>Armor Worn:</strong>
                <%= if @editable? do %>
                  <input name="hero[armor]" value={@h.armor} placeholder="e.g. Chain mail &amp; Shield" />
                <% else %>
                  <span><%= @h.armor %></span>
                <% end %>
              </div>
              <div style="margin-top: 0.3rem;">
                <span class="stat">Base: <b><%= @h.ac_base %></b></span>
                <span class="stat">Dex: <b><%= @h.dex_ac_adj %></b></span>
                <span class="stat">Shieldless: <b><%= @h.shieldless_ac %></b></span>
                <span class="stat">Rear: <b><%= @h.rear_ac %></b></span>
              </div>
            </div>
          </div>
        </div>

        <div class="sheet-box">
          <div class="sheet-box-title">Hit Points &amp; Combat Vitals</div>
          <div style="display: flex; gap: 0.8rem; align-items: center;">
            <div class="sheet-shield" style="border-color: #e88f8f; background: #2e1c1c;">
              <div style="font-size: 0.7rem; color: #e88f8f;">HIT POINTS</div>
              <%= if @editable? do %>
                <input type="number" name="hero[hp]" value={@h.hp} min="1" style="width: 72px; text-align: center; font-weight: bold; font-size: 1.25rem; color: #e88f8f; padding: 0.2rem 0.3rem;" />
              <% else %>
                <div class="ac-val" style="color: #e88f8f;"><%= @h.hp %></div>
              <% end %>
            </div>
            <div style="font-size: 0.8rem; flex: 1;">
              <div>
                <span class="stat">Max HP: <b><%= @h.hp_max %></b></span>
                <span class="stat">Hit Die: <b><%= @h.hit_die %></b></span>
                <span class="stat">Const Adj: <b><%= @h.hp_adj %></b></span>
              </div>
              <div style="margin-top: 0.3rem;">
                <span class="stat">Surprise: <b><%= @h.surprise_mod %></b></span>
                <span class="stat">Rear Atk: <b><%= @h.rear_attack_adj %></b></span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Zone 5: Weapons & To-Hit Matrix (AC 10..2) --%>
      <div class="sheet-box" style="margin-bottom: 0.8rem;">
        <div class="sheet-box-title">Weapons &amp; To-Hit Armor Class Matrix (DMG p. 74)</div>
        <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 0.5rem; margin-bottom: 0.5rem;">
          <div>
            <label>Weapons Carried</label>
            <%= if @editable? do %>
              <input name="hero[weapons]" value={@h.weapons} placeholder="e.g. Longsword (1d8), Dagger (1d4)" />
            <% else %>
              <span><%= @h.weapons %></span>
            <% end %>
          </div>
          <div>
            <label>Primary Damage (NdM[+K])</label>
            <%= if @editable? do %>
              <input name="hero[damage]" value={@h.damage} placeholder="1d8" />
            <% else %>
              <span><%= @h.damage %></span>
            <% end %>
          </div>
        </div>
        <table class="sheet-matrix-1e" style="margin-bottom: 0.6rem;">
          <thead>
            <tr>
              <th style="text-align: left;">WEAPON</th>
              <th>MAG</th>
              <th>RANGE / SPEED</th>
              <th :for={ac <- 10..2//-1}>AC <%= ac %></th>
              <th>DAM (S-M)</th>
              <th>DAM (L)</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="text-align: left; font-weight: bold;"><%= @h.weapon_in_hand %></td>
              <td>+0</td>
              <td><%= if @h.class == "Fighter", do: "4' / Spd 5", else: "3' / Spd 3" %></td>
              <td :for={ac <- 10..2//-1} style="font-weight: bold; color: #e8d9a8;"><%= @h.to_hit_matrix[ac] %></td>
              <td><%= @h.damage %></td>
              <td>1d12</td>
            </tr>
          </tbody>
        </table>

        <div style="font-size: 0.78rem; display: flex; gap: 0.8rem; flex-wrap: wrap;">
          <div><strong>Weaponless Combat:</strong></div>
          <span class="stat">Pummeling: Atk <b><%= @h.pummeling_atk %></b> / Dam <b><%= @h.pummeling_dam %></b></span>
          <span class="stat">Grappling: Atk <b><%= @h.grappling_atk %></b> / Dam <b><%= @h.grappling_dam %></b></span>
          <span class="stat">Overbearing: Atk <b><%= @h.overbearing_atk %></b> / Dam <b><%= @h.overbearing_dam %></b></span>
        </div>
      </div>

      <%!-- Zone 6: Dynamic Class-Specific Bottom Zones --%>
      <%= case @h.class do %>
        <% c when c in ["Cleric", "Druid"] -> %>
          <div class="sheet-box">
            <div class="sheet-box-title">Cleric / Druid Record &amp; Turning Undead</div>
            <div style="display: flex; gap: 0.6rem; margin-bottom: 0.5rem; font-size: 0.8rem;">
              <span class="stat">Status: <b><%= @h.church_status %></b></span>
              <span class="stat">Parish: <b><%= @h.parish %></b></span>
              <span class="stat">Holy Symbol: <b><%= @h.holy_symbol %></b></span>
            </div>

            <div style="margin-bottom: 0.5rem;">
              <div style="font-size: 0.75rem; color: #a8c8e8; margin-bottom: 0.2rem;">TURNING UNDEAD TABLE (1E DMG p. 65):</div>
              <table class="sheet-matrix-1e">
                <thead>
                  <tr>
                    <th>Skel</th><th>Zomb</th><th>Ghoul</th><th>Shadow</th><th>Wight</th><th>Ghast</th><th>Wraith</th><th>Mummy</th><th>Spec</th><th>Vamp</th><th>Ghost</th><th>Lich</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><%= @h.turning_table.skeleton %></td>
                    <td><%= @h.turning_table.zombie %></td>
                    <td><%= @h.turning_table.ghoul %></td>
                    <td><%= @h.turning_table.shadow %></td>
                    <td><%= @h.turning_table.wight %></td>
                    <td><%= @h.turning_table.ghast %></td>
                    <td><%= @h.turning_table.wraith %></td>
                    <td><%= @h.turning_table.mummy %></td>
                    <td><%= @h.turning_table.spectre %></td>
                    <td><%= @h.turning_table.vampire %></td>
                    <td><%= @h.turning_table.ghost %></td>
                    <td><%= @h.turning_table.lich %></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div :if={prayer_catalog(@h.class) != []}>
              <div style="font-size: 0.75rem; color: #a8c8e8; margin-bottom: 0.2rem;">DIVINE PRAYERS PREPARED:</div>
              <div :if={@editable?} class="picker-row" style="margin-bottom: 0.4rem;">
                <select name="hero[chosen_prayer]">
                  <option value="">-- choose prayer --</option>
                  <option :for={pr <- prayer_catalog(@h.class)} value={pr} selected={@h.chosen_prayer == pr}><%= pr %></option>
                </select>
                <button type="button" phx-click="add_prayer" class="chip">Add Prayer</button>
              </div>
              <ul class="chosen-list" :if={@h.prayers != []}>
                <li :for={pr <- @h.prayers}>
                  🙏 <%= pr %>
                  <button :if={@editable?} type="button" phx-click="remove_prayer" phx-value-prayer={pr} class="chip-small">Remove</button>
                </li>
              </ul>
            </div>
          </div>

        <% c when c in ["Thief", "Assassin", "Monk"] -> %>
          <div class="sheet-box">
            <div class="sheet-box-title">Rogue Record &amp; Thieving Skills (1E PHB p. 28)</div>
            <div style="display: flex; gap: 0.6rem; margin-bottom: 0.5rem; font-size: 0.8rem;">
              <span class="stat">Guild: <b><%= @h.guild_order %></b></span>
              <span class="stat">Rank: <b><%= @h.guild_rank %></b></span>
              <span class="stat">Superior: <b><%= @h.superior %></b></span>
              <span class="stat">Contacts: <b><%= @h.contacts %></b></span>
            </div>

            <div>
              <table class="sheet-matrix-1e">
                <thead>
                  <tr>
                    <th>PICK POCKETS</th><th>OPEN LOCKS</th><th>FIND TRAPS</th><th>MOVE SILENT</th><th>HIDE SHADOWS</th><th>HEAR NOISE</th><th>CLIMB WALLS</th><th>READ LANG</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td class="num"><%= @h.thieving_skills.pick_pockets %></td>
                    <td class="num"><%= @h.thieving_skills.open_locks %></td>
                    <td class="num"><%= @h.thieving_skills.find_traps %></td>
                    <td class="num"><%= @h.thieving_skills.move_silently %></td>
                    <td class="num"><%= @h.thieving_skills.hide_in_shadows %></td>
                    <td class="num"><%= @h.thieving_skills.hear_noise %></td>
                    <td class="num"><%= @h.thieving_skills.climb_walls %></td>
                    <td class="num"><%= @h.thieving_skills.read_languages %></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

        <% c when c in ["Magic-User", "Illusionist"] -> %>
          <div class="sheet-box">
            <div class="sheet-box-title">Arcane Spellbook &amp; Memorization Record</div>
            <div style="display: flex; gap: 0.6rem; margin-bottom: 0.5rem; font-size: 0.8rem;">
              <span class="stat">Master: <b><%= @h.master %></b></span>
              <span class="stat">School: <b><%= @h.school %></b></span>
              <span class="stat">Familiar: <b><%= @h.familiar %></b></span>
            </div>

            <div :if={spell_catalog(@h.class) != []}>
              <div :if={@editable?} class="picker-row" style="margin-bottom: 0.4rem;">
                <select name="hero[chosen_spell]">
                  <option value="">-- choose spell --</option>
                  <option :for={sp <- spell_catalog(@h.class)} value={sp} selected={@h.chosen_spell == sp}><%= sp %></option>
                </select>
                <button type="button" phx-click="add_spell" class="chip">Add Spell</button>
              </div>
              <ul class="chosen-list" :if={@h.spells != []}>
                <li :for={sp <- @h.spells}>
                  ✨ <%= sp %>
                  <button :if={@editable?} type="button" phx-click="remove_spell" phx-value-spell={sp} class="chip-small">Remove</button>
                </li>
              </ul>
            </div>
          </div>

        <% _ -> %>
          <div class="sheet-box">
            <div class="sheet-box-title">Warrior Record &amp; Mount / Companions</div>
            <div style="display: flex; gap: 0.6rem; margin-bottom: 0.5rem; font-size: 0.8rem;">
              <span class="stat"># Attacks: <b><%= @h.num_attacks %></b></span>
              <span class="stat">Morale Mod: <b><%= @h.morale_modifier %></b></span>
              <span class="stat">Patron: <b><%= @h.patron %></b></span>
              <span class="stat">Special: <b><%= @h.special_abilities %></b></span>
            </div>
            <div style="font-size: 0.8rem;">
              <strong>MOUNT:</strong> <%= @h.mount_name %> (<%= @h.mount_type %>) — HD <%= @h.mount_hd %>, AC <%= @h.mount_ac %>, HP <%= @h.mount_hp %>, Damage <%= @h.mount_damage %>
            </div>
          </div>
      <% end %>

      <%!-- Equipment & Inventory Textarea (for custom notes) --%>
      <div style="margin-top: 0.8rem;">
        <label>Initial Inventory &amp; Backpack Supplies</label>
        <%= if @editable? do %>
          <textarea name="hero[inventory]" rows="2"><%= @h.inventory %></textarea>
        <% else %>
          <p style="font-size:0.85rem; color:#b9c2cf;"><%= @h.inventory %></p>
        <% end %>
      </div>
    </div>
    """
  end

  # Helpers -----------------------------------------------------------------

  defp default_hero do
    str = 16
    int = 13
    wis = 11
    dex = 15
    con = 15
    cha = 12
    com = 10
    class = "Fighter"
    level = 1
    race = "Human"

    s_sub = SheetTables.strength_substats(str)
    i_sub = SheetTables.intelligence_substats(int)
    w_sub = SheetTables.wisdom_substats(wis)
    d_sub = SheetTables.dexterity_substats(dex)
    c_sub = SheetTables.constitution_substats(con, class)
    ch_sub = SheetTables.charisma_substats(cha)
    cm_sub = SheetTables.comeliness_substats(com)
    saves = SheetTables.saving_throws(class, level)
    to_hit = SheetTables.to_hit_matrix(class, level)
    thief_skills = SheetTables.thieving_skills(class, level, race, dex)
    turning = SheetTables.turning_table(level)

    %{
      player_name: "",
      campaign_name: "The Shattered Kingdoms",
      campaign_num: "1",
      date_began: "2026-08-25",
      name: "",
      race: race,
      class: class,
      level: level,
      xp: 0,
      alignment: "Neutral Good",
      patron_deity: "Saint Cuthbert",
      religion: "Orthodox",
      place_of_origin: "Mara's Inn, Thornhollow",
      move_base: "12\"",
      movement_notes: "",
      str: str,
      str_percent: nil,
      hit_adj: s_sub.hit_adj,
      dam_adj: s_sub.dam_adj,
      open_doors: s_sub.open_doors,
      bend_bars: s_sub.bend_bars,
      int: int,
      add_lang: i_sub.add_lang,
      know_spell: i_sub.know_spell,
      min_spells: i_sub.min_spells,
      max_spells: i_sub.max_spells,
      wis: wis,
      mag_atk_adj: w_sub.mag_atk_adj,
      spell_bonus: w_sub.spell_bonus,
      spell_failure: w_sub.spell_failure,
      dex: dex,
      react_adj: d_sub.react_adj,
      missile_adj: d_sub.missile_adj,
      def_adj: d_sub.def_adj,
      con: con,
      hp_adj: c_sub.hp_adj,
      system_shock: c_sub.system_shock,
      resurrect_survival: c_sub.resurrect_survival,
      cha: cha,
      max_henchmen: ch_sub.max_henchmen,
      loyalty_base: ch_sub.loyalty_base,
      react_cha_adj: ch_sub.react_adj,
      com: com,
      com_response: cm_sub.response,
      save_poison: saves.poison,
      save_petrification: saves.petrification,
      save_wand: saves.wand,
      save_breath: saves.breath,
      save_spell: saves.spell,
      save_adjustments: "None",
      resistances: "None",
      detection: "Normal (60' infravision)",
      languages: "Common, Alignment",
      thac0: 20,
      ac: 4,
      ac_base: 5,
      armor: "Chain mail & Shield",
      dex_ac_adj: "-1",
      mag_ac_adj: "0",
      shieldless_ac: 5,
      rear_ac: 6,
      armor_condition: "Good",
      hp: 12,
      hp_max: 12,
      hit_die: "d10",
      wounds: 0,
      surprise_mod: "1-2 on d6",
      dex_surprise_adj: "0",
      rear_attack_adj: "-2",
      weapons_proficiency: "Longsword, Dagger, Shortbow",
      num_proficiencies: 3,
      non_prof_penalty: "-2",
      to_hit_adj_total: "+0",
      damage_adj_total: "+1",
      weapon_in_hand: "Longsword",
      weapons: "Longsword (1d8), Dagger (1d4), Shortbow (1d6)",
      damage: "1d8",
      to_hit_matrix: to_hit,
      pummeling_atk: "+0",
      pummeling_dam: "1d2",
      pummeling_def: "0",
      grappling_atk: "+0",
      grappling_dam: "1d1",
      grappling_def: "0",
      overbearing_atk: "+0",
      overbearing_dam: "None",
      overbearing_def: "0",
      inventory: "Backpack, 50ft rope, 3 torches, rations (7 days), waterskin, 12 gp",
      spells: [],
      prayers: [],
      chosen_spell: "",
      chosen_prayer: "",
      church_status: "Acolyte",
      church_influence: "Local",
      tithes_percent: "10%",
      parish: "Saint Cuthbert of Thornhollow",
      holy_symbol: "Wooden Sun Amulet",
      turning_table: turning,
      num_attacks: "1/1",
      morale_modifier: "+1",
      patron: "Mayor Grevik of Thornhollow",
      special_abilities: "Weapon Specialization",
      mount_name: "Brutus",
      mount_type: "Heavy Warhorse",
      mount_hd: "3+3",
      mount_ac: "7",
      mount_hp: "18",
      mount_damage: "1d8",
      master: "Vaelith the Mirage-Weaver",
      school: "Illusion / Phantasm",
      familiar: "None",
      magic_components: "Component pouch, ink, parchment",
      guild_order: "Thornhollow Shadow Ring",
      guild_rank: "Footpad",
      superior: "Black Jack",
      contacts: "Willem the Miller (Farmer)",
      disguises_tools: "Lockpicks, Grappling Hook",
      thieving_skills: thief_skills
    }
  end

  defp update_hero(hero, params) do
    parsed =
      Enum.reduce(params, hero, fn {key, value}, acc ->
        atom =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> String.to_atom(key)
          end

        value =
          case atom do
            a when a in [:level, :xp, :hp, :ac, :str, :int, :wis, :dex, :con, :cha, :com] ->
              parse_int(value, Map.get(acc, atom))

            :spells -> list_of_strings(value)
            :prayers -> list_of_strings(value)
            _ -> value
          end

        Map.put(acc, atom, value)
      end)

    # Recompute derived 1E stats
    s_sub = SheetTables.strength_substats(parsed[:str] || 10, parsed[:str_percent])
    i_sub = SheetTables.intelligence_substats(parsed[:int] || 10)
    w_sub = SheetTables.wisdom_substats(parsed[:wis] || 10)
    d_sub = SheetTables.dexterity_substats(parsed[:dex] || 10)
    c_sub = SheetTables.constitution_substats(parsed[:con] || 10, parsed.class)
    ch_sub = SheetTables.charisma_substats(parsed[:cha] || 10)
    cm_sub = SheetTables.comeliness_substats(parsed[:com] || 10)
    saves = SheetTables.saving_throws(parsed.class, parsed.level)
    to_hit = SheetTables.to_hit_matrix(parsed.class, parsed.level)
    thief_skills = SheetTables.thieving_skills(parsed.class, parsed.level, parsed.race, parsed[:dex] || 10)
    turning = SheetTables.turning_table(parsed.level)
    thac0 = PC.calculate_thac0(parsed.class, parsed.level)

    parsed
    |> Map.merge(%{
      thac0: thac0,
      hit_adj: s_sub.hit_adj,
      dam_adj: s_sub.dam_adj,
      open_doors: s_sub.open_doors,
      bend_bars: s_sub.bend_bars,
      add_lang: i_sub.add_lang,
      know_spell: i_sub.know_spell,
      min_spells: i_sub.min_spells,
      max_spells: i_sub.max_spells,
      mag_atk_adj: w_sub.mag_atk_adj,
      spell_bonus: w_sub.spell_bonus,
      spell_failure: w_sub.spell_failure,
      react_adj: d_sub.react_adj,
      missile_adj: d_sub.missile_adj,
      def_adj: d_sub.def_adj,
      hp_adj: c_sub.hp_adj,
      system_shock: c_sub.system_shock,
      resurrect_survival: c_sub.resurrect_survival,
      max_henchmen: ch_sub.max_henchmen,
      loyalty_base: ch_sub.loyalty_base,
      react_cha_adj: ch_sub.react_adj,
      com_response: cm_sub.response,
      save_poison: saves.poison,
      save_petrification: saves.petrification,
      save_wand: saves.wand,
      save_breath: saves.breath,
      save_spell: saves.spell,
      to_hit_matrix: to_hit,
      turning_table: turning,
      thieving_skills: thief_skills
    })
  end

  defp sheet_from_slice(hero, slice) do
    if slice && slice["sheet"] do
      sh = slice["sheet"]
      %{
        hero
        | name: (slice["agent"] && slice["agent"]["name"]) || hero.name,
          race: sh["race"] || hero.race,
          class: sh["class"] || hero.class,
          level: sh["level"] || hero.level,
          xp: sh["xp"] || hero.xp,
          hp: sh["hp"] || hero.hp,
          hp_max: sh["hp_max"] || hero.hp_max,
          ac: sh["ac"] || hero.ac,
          thac0: sh["thac0"] || hero.thac0,
          damage: sh["damage"] || hero.damage,
          armor: sh["armor"] || hero.armor,
          weapons: sh["weapons"] || hero.weapons,
          inventory: sh["inventory"] || hero.inventory,
          spells: list_or_text(sh["spells"] || hero.spells),
          prayers: list_or_text(sh["prayers"] || hero.prayers)
      }
    else
      hero
    end
  end

  defp parse_int(value, fallback) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> fallback
    end
  end

  defp parse_int(value, _fallback) when is_integer(value), do: value
  defp parse_int(_, fallback), do: fallback

  defp list_of_strings(values) when is_list(values) do
    values |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
  end

  defp list_of_strings(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp list_of_strings(_), do: []

  defp validate_hero(hero) do
    if String.trim(hero.name) == "" do
      {:error, "Name is required"}
    else
      :ok
    end
  end
  defp ensure_pc_present(run_id, pc) do
    case Session.pcs(run_id) do
      {:ok, pcs} ->
        if pc in pcs do
          {:ok, pc}
        else
          case find_archetype(pc) do
            {:ok, archetype} ->
              pc_id = slug_id(archetype.name)

              pc_map = %{
                id: pc_id,
                name: archetype.name,
                race: archetype.race,
                class: archetype.class,
                level: archetype.level,
                xp: archetype.xp,
                int: archetype.int,
                hp: archetype.hp,
                ac: archetype.ac,
                thac0: archetype.thac0,
                damage: archetype.damage,
                armor: archetype.armor,
                weapons: archetype.weapons,
                inventory: archetype.inventory,
                spells: Enum.join(archetype.spells, ", "),
                prayers: Enum.join(archetype.prayers, ", ")
              }

              case Session.add_pc(run_id, pc_map) do
                {:ok, created_id} -> {:ok, created_id}
                _ -> :not_found
              end

            :error ->
              :not_found
          end
        end

      _ ->
        {:ok, pc}
    end
  end

  defp find_archetype(pc) do
    Enum.find_value(@archetypes, :error, fn {name, data} ->
      if slug_id(name) == pc or String.downcase(name) == String.downcase(pc) do
        {:ok, data}
      end
    end)
  end


  defp slug_id(name) do
    base =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    if base == "", do: "pc_hero", else: "pc_" <> base
  end

  defp add_spell(hero) do
    spell = String.trim(hero.chosen_spell)
    if spell != "" and spell not in hero.spells do
      %{hero | spells: hero.spells ++ [spell]}
    else
      hero
    end
  end

  defp add_prayer(hero) do
    prayer = String.trim(hero.chosen_prayer)
    if prayer != "" and prayer not in hero.prayers do
      %{hero | prayers: hero.prayers ++ [prayer]}
    else
      hero
    end
  end

  defp spell_catalog(class) when class in ["Magic-User", "Illusionist"] do
    case class do
      "Magic-User" -> @mu_spells_1 ++ @mu_spells_2
      "Illusionist" -> @illusionist_spells_1 ++ @illusionist_spells_2
    end
  end

  defp spell_catalog(_), do: []

  defp prayer_catalog(class) when class in ["Cleric", "Druid"] do
    case class do
      "Cleric" -> @cleric_prayers_1 ++ @cleric_prayers_2
      "Druid" -> @druid_prayers_1 ++ @druid_prayers_2
    end
  end

  defp prayer_catalog(_), do: []

  defp first([h | _]), do: h
  defp first(_), do: ""

  defp slug_for_testid(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp verb_palette, do: @verb_palette

  defp first_run_hint do
    "Describe what you do — specifics beat dice. Try: \"search the crate\" or \"north\"."
  end

  defp log_row(kind, text) do
    %{
      id: "log-#{System.unique_integer([:positive])}",
      kind: kind,
      text: text
    }
  end

  defp believed_agents(slice) do
    (slice["believed_agents"] || slice["believed"] || [])
    |> Enum.map(fn
      %{"name" => name} -> name
      %{name: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp hp_percent(sh) when is_map(sh) do
    hp = sh["hp"] || sh[:hp] || 0
    max = sh["hp_max"] || sh[:hp_max] || hp
    if max > 0, do: min(100, max(0, trunc(hp / max * 100))), else: 0
  end

  defp hp_percent(_), do: 0

  defp list_or_text(list) when is_list(list), do: list
  defp list_or_text(text) when is_binary(text) do
    text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
  defp list_or_text(_), do: []

  defp wire_url do
    System.get_env("WIRE_URL") || Application.get_env(:client_web, :wire_url) || "ws://127.0.0.1:4000"
  end

  defp monitor_conn(socket) do
    if is_pid(socket.assigns.conn) do
      Process.monitor(socket.assigns.conn)
    end
    socket
  end
end
