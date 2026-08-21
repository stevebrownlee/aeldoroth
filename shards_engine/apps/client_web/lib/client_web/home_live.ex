defmodule ClientWeb.HomeLive do
  @moduledoc """
  Referee console landing (spec §6): run starter + active-runs registry.

  The landing presents a scenario hook with adventure metadata and starting
  location, an AD&D character card roster builder with inventory, armor,
  weapons, spells, and prayers, and seat-links after launch.
  """

  use ClientWeb, :live_view

  alias EngineCore.Loader
  alias Referee.Run.Session

  @canonical_party [
    %{
      name: "Thistle",
      id: "pc_thistle",
      class: "Fighter",
      int: 13,
      hp: 12,
      ac: 5,
      thac0: 20,
      damage: "1d8",
      armor: "Chain mail & Shield",
      weapons: "Longsword (1d8), Dagger (1d4)",
      inventory: "Backpack, 50ft hemp rope, 3 torches, rations (7 days), waterskin, whetstone, 12 gp",
      spells: "",
      prayers: ""
    },
    %{
      name: "Bramble",
      id: "pc_bramble",
      class: "Thief",
      int: 12,
      hp: 8,
      ac: 6,
      thac0: 19,
      damage: "1d6",
      armor: "Leather armor",
      weapons: "Shortsword (1d6), Shortbow (1d6), Dagger (1d4)",
      inventory: "Thieves' tools, lockpicks, hooded lantern, flask of oil, 30ft silk rope, grappling hook, 18 gp",
      spells: "",
      prayers: ""
    },
    %{
      name: "Mirage",
      id: "pc_mirage",
      class: "Magic-User",
      int: 17,
      hp: 4,
      ac: 10,
      thac0: 20,
      damage: "1d4",
      armor: "Robes",
      weapons: "Quarterstaff (1d6), Darts (1d3), Silver Dagger (1d4)",
      inventory: "Spellbook, component pouch, parchment & quill, ink vial, chalk, lantern, 8 gp",
      spells: "Magic Missile, Sleep, Shield",
      prayers: ""
    },
    %{
      name: "Sister Lyra",
      id: "pc_lyra",
      class: "Cleric",
      int: 11,
      hp: 8,
      ac: 5,
      thac0: 20,
      damage: "1d6",
      armor: "Scale mail & Wooden Shield",
      weapons: "Warhammer (1d4+1), Mace (1d6)",
      inventory: "Wooden holy symbol, holy water (2 vials), healer's kit, bandages, iron rations, 15 gp",
      spells: "",
      prayers: "Cure Light Wounds, Bless, Purify Food and Drink"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    yaml = default_yaml()
    starting_place = resolve_starting_place(yaml)

    {:ok,
     assign(socket,
       run_id: "web-#{:erlang.unique_integer([:positive])}",
       seed: 42,
       yaml: yaml,
       starting_place: starting_place,
       starting_place_label: place_label(starting_place),
       roster: "",
       seat_rows: default_seat_rows(starting_place),
       created: nil,
       runs: list_runs()
     )}
  end

  @impl true
  def handle_event("load_canonical", _params, socket) do
    {:noreply,
     assign(socket,
       seat_rows: canonical_seat_rows(socket.assigns.starting_place)
     )}
  end

  def handle_event("clear_roster", _params, socket) do
    sp = socket.assigns.starting_place
    {:noreply,
     assign(socket,
       seat_rows: Enum.map(0..3, fn i -> empty_seat_row(i, sp) end)
     )}
  end

  def handle_event("create", %{"run" => _} = params, socket) do
    run_params = params["run"]
    yaml = String.trim(run_params["yaml"] || default_yaml())
    run_id = String.trim(run_params["run_id"] || "")
    seed_result = parse_seed(run_params["seed"])

    starting_place =
      case String.trim(run_params["starting_place"] || "") do
        "" -> resolve_starting_place(yaml)
        custom -> custom
      end

    seat_params = params["seat"] || %{}
    seat_rows = seat_rows_from_params(seat_params, starting_place)

    case roster_from_form(seat_rows, run_params["roster"], starting_place) do
      {:ok, pcs} ->
        with {:run_id, run_id} when run_id != "" <- {:run_id, run_id},
             {:seed, {:ok, seed}} <- {:seed, seed_result},
             {:yaml, true} <- {:yaml, File.exists?(yaml)},
             {:start, {:ok, _pid}} <- {:start, Session.start_link(run_id, yaml, seed, pcs)} do
          seats = Enum.map(pcs, &%{id: &1.id, name: &1.name})

          {:noreply,
           socket
           |> put_flash(:info, "Run #{run_id} started")
           |> assign(
             created: %{run_id: run_id, seats: seats},
             runs: list_runs(),
             seat_rows: default_seat_rows(starting_place),
             roster: ""
           )}
        else
          {:run_id, _} ->
            error_reply(socket, "Run id is required", seat_rows)

          {:seed, _} ->
            error_reply(socket, "Seed must be an integer", seat_rows)

          {:yaml, _} ->
            error_reply(socket, "Adventure YAML not found: #{yaml}", seat_rows)

          {:start, {:error, {:already_started, _pid}}} ->
            error_reply(socket, "A run with that id already exists", seat_rows)

          {:start, {:error, reason}} ->
            error_reply(socket, "Could not start run: #{inspect(reason)}", seat_rows)
        end

      {:error, :override, msg} ->
        {:noreply,
         socket
         |> put_flash(:error, "Roster override: #{msg}")
         |> assign(seat_rows: seat_rows, created: nil)}

      {:error, :rows, errors} ->
        {:noreply,
         socket
         |> put_flash(:error, row_errors_message(errors))
         |> assign(seat_rows: seat_rows_with_errors(seat_rows, errors), created: nil)}
    end
  end

  def handle_event("create", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Malformed form")}
  @impl true
  def render(assigns) do
    ~H"""
    <section class="scenario-card panel">
      <h1>The Ruined Tower</h1>
      <p>
        Livestock has been disappearing from Thornhollow over the past two weeks.
        Strange lights have been seen at the old ruins of a wizard's tower on the nearby hill.
        Mayor Grevik offers 100 gold pieces to investigate and stop the threat.
      </p>
      <div>
        <span class="location-badge">
          📍 <strong>Starting Location:</strong> <%= @starting_place_label %>
        </span>
      </div>
      <p class="hint">Recommended for 4 Level 1 adventurers. One connection per player.</p>
    </section>

    <section class="panel">
      <h2>Assemble Your Party</h2>
      <form id="new_run" phx-submit="create">
        <div class="preset-bar">
          <span class="hint">Configure adventurer vitals, equipment, inventory, and spells:</span>
          <div>
            <button type="button" class="preset-btn" phx-click="load_canonical">Load Canonical Party</button>
            <button type="button" class="preset-btn" phx-click="clear_roster">Clear</button>
          </div>
        </div>

        <div class="roster-cards">
          <div :for={row <- @seat_rows} class="character-card">
            <div class="character-card-header">
              <h3>
                <span class="card-slot-badge">Slot <%= row.index + 1 %></span>
                <%= if row.name != "", do: row.name, else: "New Adventurer" %>
              </h3>
              <span :if={row.class != ""} class={"badge-class " <> class_slug(row.class)}>
                <%= row.class %>
              </span>
            </div>

            <!-- Hidden or background fields -->
            <input type="text" name={"seat[#{row.index}][place_id]"} value={row.place_id} style="display: none;" />

            <!-- Core Identity & Vitals -->
            <div class="card-grid-vitals">
              <div class="card-field">
                <label>PC Name</label>
                <input name={"seat[#{row.index}][name]"} value={row.name} placeholder="Name" />
              </div>
              <div class="card-field">
                <label>Class / Role</label>
                <input name={"seat[#{row.index}][class]"} value={row.class} placeholder="e.g. Fighter" />
              </div>
              <div class="card-field">
                <label>HP</label>
                <input name={"seat[#{row.index}][hp]"} value={row.hp} inputmode="numeric" placeholder="10" />
              </div>
              <div class="card-field">
                <label>AC</label>
                <input name={"seat[#{row.index}][ac]"} value={row.ac} inputmode="numeric" placeholder="5" />
                <span class="hint-text">Desc (10..2)</span>
              </div>
              <div class="card-field">
                <label>THAC0</label>
                <input name={"seat[#{row.index}][thac0]"} value={row.thac0} inputmode="numeric" placeholder="20" />
              </div>
              <div class="card-field">
                <label>Damage</label>
                <input name={"seat[#{row.index}][damage]"} value={row.damage} placeholder="1d8" />
              </div>
              <div class="card-field">
                <label>INT</label>
                <input name={"seat[#{row.index}][int]"} value={row.int} inputmode="numeric" placeholder="10" />
              </div>
            </div>

            <!-- Optional ID field for advanced customization -->
            <div class="card-field" style="margin-bottom: 0.5rem;">
              <label style="font-size: 0.75rem; color: #6f7885;">Internal Character ID (leave blank to auto-generate)</label>
              <input name={"seat[#{row.index}][id]"} value={row.id} placeholder={"pc_" <> (if row.name != "", do: String.downcase(row.name), else: "hero")} style="font-size: 0.8rem; padding: 0.25rem 0.4rem;" />
            </div>

            <!-- Equipment & Combat Gear -->
            <div class="char-section">
              <div class="char-section-title">Equipment & Combat Gear</div>
              <div class="card-grid-gear">
                <div class="card-field">
                  <label>Armor Worn</label>
                  <input name={"seat[#{row.index}][armor]"} value={row.armor} placeholder="e.g. Chain mail & Shield" />
                </div>
                <div class="card-field">
                  <label>Weapons</label>
                  <input name={"seat[#{row.index}][weapons]"} value={row.weapons} placeholder="e.g. Longsword (1d8), Dagger (1d4)" />
                </div>
              </div>
              <div class="card-field">
                <label>Initial Inventory & Supplies</label>
                <input name={"seat[#{row.index}][inventory]"} value={row.inventory} placeholder="e.g. Backpack, 50ft rope, 3 torches, rations (7 days), waterskin, 10 gp" />
              </div>
            </div>

            <!-- Arcane Spells & Divine Prayers -->
            <div class="char-section">
              <div class="char-section-title">Arcane Spells & Divine Prayers</div>
              <div class="magic-box">
                <label>✨ Spells Prepared (Magic-Users / Illusionists)</label>
                <input name={"seat[#{row.index}][spells]"} value={row.spells} placeholder="e.g. Magic Missile, Sleep, Shield, Read Magic" />
              </div>
              <div class="cleric-box">
                <label>🙏 Prayers Prepared (Clerics)</label>
                <input name={"seat[#{row.index}][prayers]"} value={row.prayers} placeholder="e.g. Cure Light Wounds, Bless, Purify Food and Drink" />
              </div>
            </div>

            <p :for={err <- row.errors} class="hint error"><%= err %></p>
          </div>
        </div>

        <p class="hint">
          Adventurers with a blank name are dropped on launch.
        </p>

        <details class="advanced">
          <summary>Advanced Engine Options</summary>
          <div style="margin-top: 0.6rem;">
            <label>
              Run ID
              <input data-testid="run_id" name="run[run_id]" value={@run_id} />
            </label>
            <label>
              Starting Place Override
              <input name="run[starting_place]" value={@starting_place} placeholder={@starting_place} />
            </label>
            <label>
              Seed
              <input data-testid="seed" name="run[seed]" value={@seed} />
            </label>
            <label>
              Adventure YAML Path
              <input data-testid="yaml" name="run[yaml]" value={@yaml} size="60" />
            </label>
            <label>
              Roster Override (Pipe-delimited: id|name|place|int|hp|ac|thac0|damage)
              <textarea data-testid="roster" name="run[roster]" rows="3"><%= @roster %></textarea>
            </label>
          </div>
        </details>

        <div style="margin-top: 1.2rem;">
          <button type="submit" class="btn-start-run">Enter The Ruined Tower</button>
        </div>
      </form>
    </section>

    <div :if={@created} class="seat-links panel">
      <h2>Seat links — <%= @created.run_id %></h2>
      <ul>
        <li :for={seat <- @created.seats}>
          <.link navigate={"/runs/#{@created.run_id}/#{seat.id}"} data-testid={"seat-link-#{seat.id}"}>
            <%= seat.name %>
          </.link>
        </li>
      </ul>
      <.link navigate={"/runs/#{@created.run_id}/gm"} data-testid="gm-console-link">GM console</.link>
    </div>

    <section class="panel">
      <h2>Active runs</h2>
      <table>
        <thead>
          <tr><th>Run</th><th>Status</th><th>Tick</th><th></th></tr>
        </thead>
        <tbody>
          <tr :for={run <- @runs}>
            <td>
              <.link navigate={"/runs/#{run.id}"} data-testid={"run-link-#{run.id}"}>
                <%= run.id %>
              </.link>
            </td>
            <td><%= run.status %></td>
            <td><%= run.tick %></td>
            <td>
              <.link navigate={"/runs/#{run.id}/gm"}>GM console</.link>
            </td>
          </tr>
          <tr :if={@runs == []}>
            <td colspan="4">No active runs.</td>
          </tr>
          <tr class="dim">
            <td colspan="4"><%= length(@runs) %> run(s)</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  ## Internals

  defp default_yaml do
    Application.get_env(
      :client_web,
      :adventure_yaml,
      Path.expand("../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
    )
  end

  defp parse_seed(raw) when is_integer(raw), do: {:ok, raw}

  defp parse_seed(raw) do
    case Integer.parse(String.trim(raw || "")) do
      {seed, ""} -> {:ok, seed}
      _ -> :error
    end
  end

  # One PC per line: id|name|place|int|hp|ac|thac0|damage (hd fixed at 1).
  defp parse_roster_text(text) do
    lines = text |> String.split("\n", trim: true)

    case Enum.reduce_while(lines, {:ok, []}, &reduce_line/2) do
      {:ok, pcs} -> {:ok, Enum.reverse(pcs)}
      {:error, _} = err -> err
    end
  end

  defp reduce_line(line, {:ok, acc}) do
    case parse_line(line) do
      {:ok, pc} -> {:cont, {:ok, [pc | acc]}}
      {:error, _} = err -> {:halt, err}
    end
  end

  defp parse_line(line) do
    fields = line |> String.split("|") |> Enum.map(&String.trim/1)

    with [id, name, place_id, int, hp, ac, thac0, damage] <- fields,
         true <- id != "" and name != "" and place_id != "" and damage != "",
         {:ok, int} <- int_field(int, line),
         {:ok, hp} <- int_field(hp, line),
         {:ok, ac} <- int_field(ac, line),
         {:ok, thac0} <- int_field(thac0, line) do
      {:ok,
       %{
         id: id,
         name: name,
         place_id: place_id,
         int: int,
         hd: 1,
         hp: hp,
         ac: ac,
         thac0: thac0,
         damage: damage
       }}
    else
      [_ | _] ->
        {:error, "expected 8 fields id|name|place|int|hp|ac|thac0|damage: #{line}"}

      false ->
        {:error, "no field may be blank: #{line}"}

      {:error, _} = err ->
        err
    end
  end

  defp int_field(raw, line) do
    case Integer.parse(raw) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "expected an integer, got #{inspect(raw)}: #{line}"}
    end
  end

  defp resolve_starting_place(yaml) do
    if File.exists?(yaml) do
      Loader.starting_place(yaml)
    else
      "maras_inn"
    end
  end

  defp place_label("maras_inn"), do: "Mara's Inn (Common Room), Thornhollow"
  defp place_label("entry_hall"), do: "Entry Hall (The Ruined Tower)"
  defp place_label(other), do: other |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp class_slug(class) when is_binary(class) do
    case String.downcase(String.trim(class)) do
      "fighter" -> "fighter"
      "thief" -> "thief"
      "magic-user" -> "magic-user"
      "magic user" -> "magic-user"
      "illusionist" -> "magic-user"
      "cleric" -> "cleric"
      _ -> "general"
    end
  end

  defp canonical_seat_rows(starting_place) do
    @canonical_party
    |> Enum.with_index()
    |> Enum.map(fn {pc, i} ->
      seat_row_from_pc(Map.put(pc, :place_id, starting_place), i)
    end)
  end

  defp default_seat_rows(starting_place) do
    [
      seat_row_from_pc(Map.put(Enum.at(@canonical_party, 0), :place_id, starting_place), 0),
      seat_row_from_pc(Map.put(Enum.at(@canonical_party, 1), :place_id, starting_place), 1),
      empty_seat_row(2, starting_place),
      empty_seat_row(3, starting_place)
    ]
  end

  defp seat_row_from_pc(pc, index) do
    %{
      index: index,
      id: to_string(pc[:id] || auto_id(pc[:name] || "")),
      name: to_string(pc[:name] || ""),
      class: to_string(pc[:class] || ""),
      place_id: to_string(pc[:place_id] || "maras_inn"),
      int: to_string(pc[:int] || ""),
      hp: to_string(pc[:hp] || ""),
      ac: to_string(pc[:ac] || ""),
      thac0: to_string(pc[:thac0] || ""),
      damage: to_string(pc[:damage] || ""),
      armor: to_string(pc[:armor] || ""),
      weapons: to_string(pc[:weapons] || ""),
      inventory: to_string(pc[:inventory] || ""),
      spells: to_string(pc[:spells] || ""),
      prayers: to_string(pc[:prayers] || ""),
      errors: []
    }
  end

  defp empty_seat_row(index, starting_place) do
    %{
      index: index,
      id: "",
      name: "",
      class: "",
      place_id: starting_place,
      int: "",
      hp: "",
      ac: "",
      thac0: "",
      damage: "",
      armor: "",
      weapons: "",
      inventory: "",
      spells: "",
      prayers: "",
      errors: []
    }
  end

  defp seat_rows_from_params(seat_params, default_place) do
    seat_params = seat_params || %{}

    Enum.map(0..3, fn i ->
      fields = Map.get(seat_params, "#{i}") || Map.get(seat_params, i) || %{}

      place_id =
        case String.trim(to_string(fields["place_id"] || "")) do
          "" -> default_place
          p -> p
        end

      %{
        index: i,
        id: to_string(fields["id"] || ""),
        name: to_string(fields["name"] || ""),
        class: to_string(fields["class"] || ""),
        place_id: place_id,
        int: to_string(fields["int"] || ""),
        hp: to_string(fields["hp"] || ""),
        ac: to_string(fields["ac"] || ""),
        thac0: to_string(fields["thac0"] || ""),
        damage: to_string(fields["damage"] || ""),
        armor: to_string(fields["armor"] || ""),
        weapons: to_string(fields["weapons"] || ""),
        inventory: to_string(fields["inventory"] || ""),
        spells: to_string(fields["spells"] || ""),
        prayers: to_string(fields["prayers"] || ""),
        errors: []
      }
    end)
  end

  defp roster_from_form(seat_rows, override, default_place) do
    trimmed = String.trim(override || "")

    if trimmed != "" do
      case parse_roster_text(trimmed) do
        {:ok, pcs} -> {:ok, pcs}
        {:error, msg} -> {:error, :override, msg}
      end
    else
      {pcs, errors} =
        Enum.reduce(seat_rows, {[], []}, fn row, {pcs_acc, errs} ->
          if blank_name?(row) do
            {pcs_acc, errs}
          else
            case parse_seat_row(row, default_place) do
              {:ok, pc} ->
                {[pc | pcs_acc], errs}

              {:error, msg} ->
                {pcs_acc, [%{index: row.index, name: String.trim(row.name), message: msg} | errs]}
            end
          end
        end)

      errors = Enum.reverse(errors)

      cond do
        errors != [] ->
          {:error, :rows, errors}

        pcs == [] ->
          {:error, :rows, [%{index: 0, name: "", message: "Roster must have at least one PC"}]}

        true ->
          {:ok, Enum.reverse(pcs)}
      end
    end
  end

  defp blank_name?(row), do: String.trim(row.name || "") == ""

  defp auto_id(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")
      |> String.trim("_")

    if slug != "", do: "pc_#{slug}", else: ""
  end

  defp parse_seat_row(row, default_place) do
    name = String.trim(row.name || "")
    id = String.trim(row.id || "")
    id = if id != "", do: id, else: auto_id(name)
    place_id = String.trim(row.place_id || "")
    place_id = if place_id != "", do: place_id, else: default_place
    damage = String.trim(row.damage || "")
    class = String.trim(row.class || "")
    armor = String.trim(row.armor || "")
    weapons = String.trim(row.weapons || "")
    inventory = String.trim(row.inventory || "")
    spells = String.trim(row.spells || "")
    prayers = String.trim(row.prayers || "")

    with {:id, true} <- {:id, id != ""},
         {:place, true} <- {:place, place_id != ""},
         {:damage, true} <- {:damage, damage != ""},
         {:ok, int} <- int_attr(row.int, "INT"),
         {:ok, hp} <- int_attr(row.hp, "HP"),
         {:ok, ac} <- int_attr(row.ac, "AC"),
         {:ok, thac0} <- int_attr(row.thac0, "THAC0") do
      {:ok,
       %{
         id: id,
         name: name,
         place_id: place_id,
         class: if(class != "", do: class, else: nil),
         armor: if(armor != "", do: armor, else: nil),
         weapons: if(weapons != "", do: weapons, else: nil),
         inventory: if(inventory != "", do: inventory, else: nil),
         spells: if(spells != "", do: spells, else: nil),
         prayers: if(prayers != "", do: prayers, else: nil),
         int: int,
         hd: 1,
         hp: hp,
         ac: ac,
         thac0: thac0,
         damage: damage
       }}
    else
      {:id, false} -> {:error, "id is required"}
      {:place, false} -> {:error, "place is required"}
      {:damage, false} -> {:error, "damage is required"}
      {:error, msg} -> {:error, msg}
    end
  end

  defp int_attr(raw, label) do
    case Integer.parse(String.trim(to_string(raw))) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "#{label} must be an integer"}
    end
  end

  defp row_errors_message(errors) do
    "Roster: " <>
      Enum.map_join(errors, "; ", fn e ->
        label = if e.name != "", do: " (#{e.name})", else: ""
        "row #{e.index}#{label} — #{e.message}"
      end)
  end

  defp seat_rows_with_errors(seat_rows, errors) do
    by_index = Enum.group_by(errors, & &1.index)

    Enum.map(seat_rows, fn row ->
      %{row | errors: Enum.map(Map.get(by_index, row.index, []), & &1.message)}
    end)
  end

  defp error_reply(socket, msg, seat_rows) do
    {:noreply,
     socket
     |> put_flash(:error, msg)
     |> assign(seat_rows: seat_rows, created: nil)}
  end

  defp list_runs do
    Referee.SessionReg
    |> Registry.select([{{{:session, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.map(fn id ->
      case Session.state(id) do
        %{status: status, tick: tick} ->
          %{id: id, status: status, tick: tick}

        nil ->
          %{id: id, status: :gone, tick: nil}
      end
    end)
    |> Enum.sort_by(& &1.id)
  end
end
