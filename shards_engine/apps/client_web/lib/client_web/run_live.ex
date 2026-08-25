defmodule ClientWeb.RunLive do
  @moduledoc """
  Player seat over the wire protocol (UX spec §4):

  * `/runs/:run_id` with no PC renders an authentic AD&D 1E single-hero
    builder with 1-click archetypes. Submitting calls `Session.add_pc/2` and
    navigates to the new seat.
  * `/runs/:run_id/:pc_id` joins an existing PC to the live play surface
    through the wire — scene panel, exits, chronicle, compose, and party rail.
  """

  use ClientWeb, :live_view

  alias ClientTUI.Conn
  alias Referee.PC
  alias Referee.Run.Session

  @races ["Human", "Elf", "Half-Elf", "Dwarf", "Halfling", "Gnome"]

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

  @mu_spells_1 [
    "Charm Person",
    "Color Spray",
    "Detect Magic",
    "Enlarge",
    "Erase",
    "Feather Fall",
    "Find Familiar",
    "Friends",
    "Hold Portal",
    "Identify",
    "Light",
    "Magic Missile",
    "Protection from Evil",
    "Read Magic",
    "Shield",
    "Shocking Grasp",
    "Sleep",
    "Spider Climb",
    "Tenser's Floating Disc",
    "Unseen Servant",
    "Ventriloquism",
    "Write"
  ]

  @mu_spells_2 [
    "Audible Glamer",
    "Continual Light",
    "Detect Evil",
    "Detect Invisibility",
    "ESP",
    "Fools' Gold",
    "Forget",
    "Invisibility",
    "Knock",
    "Leomund's Trap",
    "Levitate",
    "Locate Object",
    "Magic Mouth",
    "Mirror Image",
    "Phantasmal Force",
    "Pyrotechnics",
    "Ray of Enfeeblement",
    "Rope Trick",
    "Scare",
    "Shatter",
    "Stinking Cloud",
    "Strength",
    "Web",
    "Wizard Lock"
  ]

  @illusionist_spells_1 [
    "Audible Glamer",
    "Change Self",
    "Color Spray",
    "Dancing Lights",
    "Darkness",
    "Detect Illusion",
    "Detect Magic",
    "Fog Cloud",
    "Gaze Reflection",
    "Hypnotism",
    "Light",
    "Phantasmal Force",
    "Wall of Fog"
  ]

  @illusionist_spells_2 [
    "Blindness",
    "Blur",
    "Deafness",
    "Detect Magic",
    "False Alignment",
    "Fool's Gold",
    "Hypnotic Pattern",
    "Improved Phantasmal Force",
    "Invisibility",
    "Magic Mouth",
    "Mirror Image",
    "Misdirection",
    "Paralysis",
    "Scare",
    "Spectral Force",
    "Summon Swarm",
    "Vertigo"
  ]

  @cleric_prayers_1 [
    "Bless",
    "Combine",
    "Command",
    "Create Water",
    "Cure Light Wounds",
    "Detect Evil",
    "Detect Magic",
    "Light",
    "Protection from Evil",
    "Purify Food and Drink",
    "Remove Fear",
    "Resist Cold",
    "Sanctuary"
  ]

  @cleric_prayers_2 [
    "Augury",
    "Chant",
    "Detect Curse",
    "Find Traps",
    "Hold Person",
    "Know Alignment",
    "Resist Fire",
    "Silence 15' Radius",
    "Slow Poison",
    "Snake Charm",
    "Spiritual Hammer",
    "Speak with Animals"
  ]

  @druid_prayers_1 [
    "Animal Friendship",
    "Detect Magic",
    "Detect Snares and Pits",
    "Entangle",
    "Faerie Fire",
    "Invisibility to Animals",
    "Locate Animals",
    "Pass without Trace",
    "Predict Weather",
    "Purify Water",
    "Shillelagh",
    "Speak with Animals"
  ]

  @druid_prayers_2 [
    "Barkskin",
    "Charm Person or Mammal",
    "Create Water",
    "Cure Light Wounds",
    "Feign Death",
    "Fire Trap",
    "Heat Metal",
    "Locate Plants",
    "Obscurement",
    "Produce Flame",
    "Trip",
    "Warp Wood"
  ]

  @archetypes %{
    "Thistle" => %{
      name: "Thistle",
      race: "Human",
      class: "Fighter",
      level: 1,
      xp: 0,
      int: 13,
      hp: 12,
      ac: 5,
      thac0: 20,
      damage: "1d8",
      armor: "Chain mail & Shield",
      weapons: "Longsword & Dagger",
      inventory: "Bedroll, tinderbox, waterskin, iron rations (5), torches (3), hemp rope (50 ft), flask of oil (2), mirror",
      spells: [],
      prayers: []
    },
    "Bramble" => %{
      name: "Bramble",
      race: "Halfling",
      class: "Thief",
      level: 1,
      xp: 0,
      int: 12,
      hp: 8,
      ac: 6,
      thac0: 19,
      damage: "1d6",
      armor: "Leather armor",
      weapons: "Shortsword & Shortbow",
      inventory: "Thieves' tools, bedroll, tinderbox, waterskin, iron rations (3), torches (2), rope (50 ft), chalk, silk gloves",
      spells: [],
      prayers: []
    },
    "Mirage" => %{
      name: "Mirage",
      race: "Gnome",
      class: "Illusionist",
      level: 1,
      xp: 0,
      int: 16,
      hp: 4,
      ac: 10,
      thac0: 20,
      damage: "1d4",
      armor: "Robes",
      weapons: "Staff & Darts",
      inventory: "Spellbook, ink & quills, parchment (5), bedroll, tinderbox, waterskin, iron rations (3), torches (2)",
      spells: ["Color Spray", "Phantasmal Force", "Read Magic"],
      prayers: []
    },
    "Sister Lyra" => %{
      name: "Sister Lyra",
      race: "Human",
      class: "Cleric",
      level: 1,
      xp: 0,
      int: 14,
      hp: 8,
      ac: 5,
      thac0: 20,
      damage: "1d6",
      armor: "Scale mail & Shield",
      weapons: "Warhammer & Mace",
      inventory: "Holy symbol, bedroll, tinderbox, waterskin, iron rations (5), torches (3), rope (50 ft), bandages",
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
    pc = params["pc_id"] || params["pc"]

    socket =
      assign(socket,
        run_id: run_id,
        pc: pc,
        roster: nil,
        hero: default_hero(),
        races: @races,
        classes: @classes,
        archetypes: @archetypes,
        conn: nil,
        slice: nil,
        dossier: nil,
        prompt: nil,
        paused: false,
        tick: 0,
        compose: "",
        hint_shown: false
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

  # Builder events ----------------------------------------------------------

  @impl true
  def handle_event("set_archetype", %{"name" => name}, socket) do
    hero =
      case Map.fetch(@archetypes, name) do
        {:ok, data} ->
          data
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
          spells: hero.spells,
          prayers: hero.prayers
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
    {:noreply, assign(socket, prompt: nil, compose: "", hint_shown: true)}
  end

  def handle_event("ooc", %{"text" => text}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and text != "" do
    :ok = Conn.send_event(conn, "ooc", %{"text" => text})
    {:noreply, socket}
  end

  # Verb palette / believed-agent chips scaffold into the compose box —
  # grammar teaching (spec §4): Attack chip + name chip = "attack giant rat".
  def handle_event("scaffold", %{"text" => add}, socket) do
    {:noreply, update(socket, :compose, &(&1 <> add))}
  end

  # Exit chips declare the bare direction label immediately.
  def handle_event("go", %{"dir" => dir}, %{assigns: %{conn: conn}} = socket)
      when is_pid(conn) and dir != "" do
    :ok = Conn.send_event(conn, "declare_intent", %{"text" => dir})
    {:noreply, assign(socket, compose: "", hint_shown: true)}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # Wire messages ------------------------------------------------------------

  # Join reply: seat claimed, here is the truth-barrier slice.
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

  # Error replies (unknown event, paused, no_run, claim races).
  def handle_info({:chan_reply, _ref, :error, %{"reason" => reason}}, socket) do
    {:noreply, put_flash(socket, :error, "referee: #{reason}")}
  end

  def handle_info({:chan, _topic, "perception", %{"text" => text, "tick" => tick}}, socket) do
    {:noreply,
     socket
     |> stream_insert(:log, log_row("perception", "[tick #{tick}] #{text}"))
     |> assign(tick: max(tick, socket.assigns.tick))}
  end

  def handle_info({:chan, _topic, "ooc", %{"agent_id" => id, "text" => text}}, socket) do
    label = if id == "GM", do: "[GM] #{text}", else: "#{id}: #{text}"
    {:noreply, stream_insert(socket, :log, log_row("ooc", label))}
  end

  def handle_info({:chan, _topic, "prompt", %{"question" => question}}, socket) do
    {:noreply, assign(socket, prompt: question)}
  end

  def handle_info({:chan, _topic, "dice", %{"event_payload" => payload}}, socket) do
    {:noreply, stream_insert(socket, :log, log_row("dice", render_dice(payload)))}
  end

  def handle_info({:chan, _topic, "state_sync", %{"slice" => slice}}, socket) do
    {:noreply, assign(socket, slice: slice)}
  end

  def handle_info({:chan, _topic, "paused", _payload}, socket) do
    {:noreply, socket |> system_row("The GM pauses the world.") |> assign(paused: true)}
  end

  def handle_info({:chan, _topic, "resumed", _payload}, socket) do
    {:noreply, socket |> system_row("The GM resumes play.") |> assign(paused: false)}
  end

  # Protocol growth never crashes a seat.
  def handle_info({:chan, _topic, _event, _payload}, socket), do: {:noreply, socket}
  def handle_info({:chan_reply, _ref, _status, _payload}, socket), do: {:noreply, socket}

  # Seat auto-rejoin (UX spec §4): the claim is process-owned, so a dropped
  # conn releases it — a fresh Conn re-claims the same PC. The ribbon keeps
  # the disconnected state visible until the rejoin lands.
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %{assigns: %{pc: pc}} = socket)
      when is_binary(pc) do
    Process.send_after(self(), :rejoin, 1_000)
    {:noreply, socket |> system_row("Connection lost — rejoining the seat…") |> assign(conn: nil)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "wire connection lost: #{inspect(reason)}")
     |> assign(conn: nil)}
  end

  def handle_info(:rejoin, %{assigns: %{conn: nil, pc: pc, run_id: run_id}} = socket)
      when is_binary(pc) do
    if url = wire_url() do
      case Conn.start_link(url, run_id: run_id, character_id: pc, parent: self()) do
        {:ok, pid} ->
          {:noreply, monitor_conn(assign(socket, conn: pid)) |> system_row("Seat rejoined.")}

        {:error, _reason} ->
          Process.send_after(self(), :rejoin, 2_500)
          {:noreply, socket}
      end
    else
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

      <form id="hero_builder" phx-change="hero_change" phx-submit="create_hero" class="hero-sheet">
        <div class="form-row">
          <label>
            Name
            <input name="hero[name]" value={@hero.name} data-testid="hero-name" />
          </label>

          <label>
            Race
            <select name="hero[race]">
              <option :for={r <- @races} value={r} selected={@hero.race == r}><%= r %></option>
            </select>
          </label>

          <label>
            Class
            <select name="hero[class]">
              <option :for={c <- @classes} value={c} selected={@hero.class == c}><%= c %></option>
            </select>
          </label>
        </div>

        <div class="form-row vitals">
          <label>
            Level
            <input type="number" name="hero[level]" value={@hero.level} min="1" />
          </label>

          <label>
            XP
            <input type="number" name="hero[xp]" value={@hero.xp} min="0" />
          </label>

          <label>
            HP
            <input type="number" name="hero[hp]" value={@hero.hp} min="1" />
          </label>

          <label>
            AC
            <input type="number" name="hero[ac]" value={@hero.ac} />
          </label>

          <label>
            INT
            <input type="number" name="hero[int]" value={@hero.int} min="3" max="18" />
          </label>

          <div class="thac0-badge" data-testid="hero-thac0">
            <strong>THAC0</strong>
            <span><%= @hero.thac0 %></span>
          </div>
        </div>

        <div class="form-row">
          <label>
            Damage (NdM[+K])
            <input name="hero[damage]" value={@hero.damage} />
          </label>

          <label>
            Armor
            <input name="hero[armor]" value={@hero.armor} />
          </label>

          <label>
            Weapons
            <input name="hero[weapons]" value={@hero.weapons} />
          </label>
        </div>

        <div class="form-row">
          <label>
            Inventory & Gear
            <textarea name="hero[inventory]" rows="3"><%= @hero.inventory %></textarea>
          </label>
        </div>

        <div :if={spell_catalog(@hero.class) != []} class="char-section">
          <h4>Arcane Spellbook</h4>
          <div class="picker-row">
            <select name="hero[chosen_spell]">
              <option value="">-- choose spell --</option>
              <option
                :for={spell <- spell_catalog(@hero.class)}
                value={spell}
                selected={@hero.chosen_spell == spell}
              ><%= spell %></option>
            </select>
            <button type="button" phx-click="add_spell" class="chip">Add Spell</button>
          </div>
          <ul class="chosen-list" :if={@hero.spells != []}>
            <li :for={spell <- @hero.spells}>
              <%= spell %>
              <button
                type="button"
                phx-click="remove_spell"
                phx-value-spell={spell}
                class="chip-small"
              >Remove</button>
            </li>
          </ul>
        </div>

        <div :if={prayer_catalog(@hero.class) != []} class="char-section">
          <h4>Divine Prayers</h4>
          <div class="picker-row">
            <select name="hero[chosen_prayer]">
              <option value="">-- choose prayer --</option>
              <option
                :for={prayer <- prayer_catalog(@hero.class)}
                value={prayer}
                selected={@hero.chosen_prayer == prayer}
              ><%= prayer %></option>
            </select>
            <button type="button" phx-click="add_prayer" class="chip">Add Prayer</button>
          </div>
          <ul class="chosen-list" :if={@hero.prayers != []}>
            <li :for={prayer <- @hero.prayers}>
              <%= prayer %>
              <button
                type="button"
                phx-click="remove_prayer"
                phx-value-prayer={prayer}
                class="chip-small"
              >Remove</button>
            </li>
          </ul>
        </div>

        <button type="submit" class="btn-start-run" data-testid="enter-world">
          Enter The Ruined Tower
        </button>
      </form>
    </div>

    <div :if={@slice} class="seat" data-testid="seat">
      <div class="ribbon" data-testid="status-ribbon">
        <%= status(@conn, @paused, @prompt, @tick) %>
      </div>

      <h2><%= @slice["agent"]["name"] %></h2>

      <div class="prompt" :if={@prompt} data-testid="prompt">
        <strong>Referee asks:</strong> <%= @prompt %>
      </div>

      <div class="play-grid">
        <div class="play-main">
          <section class="slice panel">
            <h3><%= @slice["place"]["name"] %></h3>
            <p><%= @slice["summary"] %></p>

            <p :if={others(@slice) != []} class="here">
              <strong>Here:</strong>
              <button
                :for={who <- others(@slice)}
                type="button"
                class="chip"
                phx-click="scaffold"
                phx-value-text={who["name"] <> " "}
              ><%= who["name"] %></button>
            </p>

            <p :if={party(@slice) != []} class="here">
              <strong>Party:</strong>
              <span :for={p <- party(@slice)} class="chip-static"><%= p["name"] %></span>
            </p>

            <p :if={@slice["place"]["items"] != []} class="here">
              <strong>Items:</strong>
              <span :for={it <- @slice["place"]["items"]} class="chip-static"><%= it["name"] %></span>
            </p>

            <p class="exits">
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
          </section>

          <section class="log panel">
            <h3>Chronicle</h3>
            <ul id="log" class="log chronicle" phx-hook="ChronicleScroll" phx-update="stream">
              <li :for={{dom_id, row} <- @streams.log} id={dom_id} class={"kind-#{row.kind}"}>
                <%= row.text %>
              </li>
            </ul>
          </section>

          <section class="compose panel">
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
                placeholder={if @prompt, do: "your answer", else: "declare intent"}
                disabled={@paused}
              />
              <button type="submit" disabled={@paused}>
                <%= if @prompt, do: "Answer", else: "Declare" %>
              </button>
            </form>

            <p :if={@paused} class="hint">Paused by the GM — the referee will resume play.</p>
            <p :if={!@hint_shown && !@prompt} class="hint"><%= first_run_hint() %></p>

            <form id="ooc" phx-submit="ooc">
              <input name="text" placeholder="table talk" />
              <button type="submit">OOC</button>
            </form>
          </section>
        </div>

        <aside class="rail">
          <section class="sheet panel">
            <%= if sh = @slice["sheet"] do %>
              <h3>Character<%= if sh["race"] || sh["class"], do: " • #{Enum.filter([sh["race"], sh["class"]], &(&1 && &1 != "")) |> Enum.join(" ")}" %></h3>
              <p class="hp">
                <strong>HP</strong>
                <span class="hp-numbers"><%= sh["hp"] %><%= if sh["hp_max"], do: " / #{sh["hp_max"]}" %></span>
              </p>
              <div class="hp-bar">
                <div class="hp-fill" style={"width: #{hp_percent(sh)}%"}></div>
              </div>
              <dl class="stats">
                <div><dt>Level</dt><dd><%= sh["level"] || 1 %></dd></div>
                <div><dt>XP</dt><dd><%= sh["xp"] || 0 %></dd></div>
                <div><dt>AC</dt><dd><%= sh["ac"] %></dd></div>
                <div><dt>THAC0</dt><dd><%= sh["thac0"] %></dd></div>
                <div><dt>Damage</dt><dd><%= sh["damage"] || "—" %></dd></div>
                <div :if={sh["int"]}><dt>INT</dt><dd><%= sh["int"] %></dd></div>
              </dl>
              <p :if={sh["conditions"] != []} class="conditions">
                <span :for={c <- sh["conditions"]} class="chip-static"><%= c %></span>
              </p>

              <div :if={sh["armor"] || sh["weapons"] || sh["inventory"]} class="char-section">
                <div class="char-section-title">Equipment & Inventory</div>
                <ul class="sheet-gear-list">
                  <li :if={sh["armor"]}><span class="gear-label">Armor:</span> <%= sh["armor"] %></li>
                  <li :if={sh["weapons"]}><span class="gear-label">Weapons:</span> <%= sh["weapons"] %></li>
                  <li :if={sh["inventory"]}><span class="gear-label">Gear:</span> <%= sh["inventory"] %></li>
                </ul>
              </div>

              <div :if={sh["spells"]} class="char-section">
                <div class="char-section-title" style="color: #d0a8e8;">✨ Spells</div>
                <div style="font-size: 0.85rem; color: #e8d9a8;"><%= sh["spells"] %></div>
              </div>

              <div :if={sh["prayers"]} class="char-section">
                <div class="char-section-title" style="color: #a8c8e8;">🙏 Prayers</div>
                <div style="font-size: 0.85rem; color: #e8d9a8;"><%= sh["prayers"] %></div>
              </div>
            <% end %>
          </section>

          <section class="dossier panel" :if={@dossier}>
            <h3>Dossier</h3>
            <pre><%= @dossier %></pre>
          </section>
        </aside>
      </div>
    </div>
    """
  end

  ## Internals

  defp default_hero do
    %{
      name: "",
      race: "Human",
      class: "Fighter",
      level: 1,
      xp: 0,
      int: 10,
      hp: 1,
      ac: 10,
      thac0: 20,
      damage: "1d8",
      armor: "",
      weapons: "",
      inventory: "",
      spells: [],
      prayers: [],
      chosen_spell: "",
      chosen_prayer: ""
    }
  end

  defp update_hero(hero, params) do
    parsed =
      Enum.reduce(params, hero, fn {key, value}, acc ->
        atom = String.to_existing_atom(key)

        value =
          case atom do
            a when a in [:level, :xp, :hp, :ac, :int] -> parse_int(value, Map.get(acc, atom))
            :spells -> list_of_strings(value)
            :prayers -> list_of_strings(value)
            _ -> value
          end

        Map.put(acc, atom, value)
      end)

    thac0 = PC.calculate_thac0(parsed.class, parsed.level)
    %{parsed | thac0: thac0}
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

  defp first([h | _]), do: h
  defp first(_), do: ""

  defp spell_catalog(class) do
    case normalize_class(class) do
      "magic-user" -> @mu_spells_1 ++ @mu_spells_2
      "illusionist" -> @illusionist_spells_1 ++ @illusionist_spells_2
      _ -> []
    end
  end

  defp prayer_catalog(class) do
    case normalize_class(class) do
      "cleric" -> @cleric_prayers_1 ++ @cleric_prayers_2
      "druid" -> @druid_prayers_1 ++ @druid_prayers_2
      _ -> []
    end
  end

  defp normalize_class(class) when is_binary(class) do
    class |> String.downcase() |> String.trim()
  end

  defp normalize_class(_), do: ""

  defp slug_for_testid(name) do
    name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  defp wire_url, do: Application.get_env(:client_web, :wire_url)

  defp monitor_conn(%{assigns: %{conn: conn}} = socket) when is_pid(conn) do
    Process.monitor(conn)
    socket
  end

  defp log_row(kind, text),
    do: %{id: "row-#{kind}-#{System.unique_integer([:positive])}", kind: kind, text: text}

  defp system_row(socket, text), do: stream_insert(socket, :log, log_row("system", text))

  # Other player-owned agents among the believed (truth-barrier-safe party
  # rail, UX spec §4): names only, own seat excluded.
  defp party(slice) do
    me = slice["agent"]["id"]

    slice["believed_agents"]
    |> Enum.filter(&(&1["pc"] == true and &1["id"] != me))
  end

  # Everything believed here except the seated player themselves — the
  # mover perceives their own arrival, but "Here:" reads as who else is here.
  defp others(slice) do
    me = slice["agent"]["id"]
    Enum.reject(slice["believed_agents"], &(&1["id"] == me))
  end

  defp verb_palette, do: @verb_palette

  defp first_run_hint,
    do: ~s(Describe what you do — specifics beat dice. Try: "search the crate" or "north".)

  defp status(nil, _paused?, _prompt?, _tick), do: "disconnected — reconnecting…"
  defp status(_conn, true, _prompt?, _tick), do: "paused by GM"
  defp status(_conn, _paused?, prompt, _tick) when is_binary(prompt), do: "answer needed"
  defp status(_conn, _paused?, _prompt?, tick), do: "connected · tick #{tick} · your move"

  defp hp_percent(%{"hp" => hp, "hp_max" => hp_max})
       when is_number(hp) and is_number(hp_max) and hp_max > 0,
       do: hp |> max(0) |> Kernel.min(hp_max) |> Kernel.*(100) |> Kernel.div(hp_max) |> min(100)

  defp hp_percent(_), do: 100

  # Dice tray rendering (UX spec §4): never inspect/1 at the player.
  defp render_dice(%{"purpose" => purpose} = p) when is_map(p) do
    base =
      case p do
        %{"sides" => sides, "roll" => roll} -> "🎲 #{purpose}: d#{sides} → #{roll}"
        _ -> "🎲 #{purpose}"
      end

    case p do
      %{"hit" => true} -> "#{base} — hit"
      %{"hit" => false} -> "#{base} — miss"
      %{"amount" => amount} -> "#{base} — #{amount} damage"
      _ -> base
    end
  end

  defp render_dice(_), do: "🎲 the referee rolls…"
end
