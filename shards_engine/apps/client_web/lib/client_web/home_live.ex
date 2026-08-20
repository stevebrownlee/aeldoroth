defmodule ClientWeb.HomeLive do
  @moduledoc """
  Referee console landing (spec §6): run starter + active-runs registry.

  The landing presents a scenario hook, a roster builder of fixed seat rows,
  and a seat-links panel after a successful in-place start. Player seats
  live under `/runs/:id/:pc_id`; spectators under `/runs/:id/gm`.
  """

  use ClientWeb, :live_view

  alias Referee.Run.Session

  @default_roster """
  pc_thistle|Thistle|entry_hall|13|12|5|20|1d8
  pc_bramble|Bramble|entry_hall|12|8|6|19|1d6
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       run_id: "web-#{:erlang.unique_integer([:positive])}",
       seed: 42,
       yaml: default_yaml(),
       roster: "",
       seat_rows: default_seat_rows(),
       created: nil,
       runs: list_runs()
     )}
  end

  @impl true
  def handle_event("create", %{"run" => _} = params, socket) do
    run_params = params["run"]
    seat_params = params["seat"] || %{}
    seat_rows = seat_rows_from_params(seat_params)

    yaml = String.trim(run_params["yaml"] || default_yaml())
    run_id = String.trim(run_params["run_id"] || "")
    seed_result = parse_seed(run_params["seed"])

    case roster_from_form(seat_rows, run_params["roster"]) do
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
             seat_rows: default_seat_rows(),
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
      <p class="hint">A party of four. One connection per player.</p>
    </section>

    <section class="panel">
      <h2>New run</h2>
      <form id="new_run" phx-submit="create">
        <label>
          Run id
          <input data-testid="run_id" name="run[run_id]" value={@run_id} />
        </label>

        <div class="roster">
          <div :for={row <- @seat_rows} class="roster-row">
            <label>
              PC name
              <input name={"seat[#{row.index}][name]"} value={row.name} />
            </label>
            <label>
              ID
              <input name={"seat[#{row.index}][id]"} value={row.id} />
            </label>
            <label>
              Place
              <input name={"seat[#{row.index}][place_id]"} value={row.place_id} />
            </label>
            <label>
              INT
              <input name={"seat[#{row.index}][int]"} value={row.int} inputmode="numeric" />
            </label>
            <label>
              HP
              <input name={"seat[#{row.index}][hp]"} value={row.hp} inputmode="numeric" />
            </label>
            <label>
              AC
              <input name={"seat[#{row.index}][ac]"} value={row.ac} inputmode="numeric" />
            </label>
            <label>
              THAC0
              <input name={"seat[#{row.index}][thac0]"} value={row.thac0} inputmode="numeric" />
            </label>
            <label>
              Damage
              <input name={"seat[#{row.index}][damage]"} value={row.damage} />
            </label>
            <p :for={err <- row.errors} class="hint"><%= err %></p>
          </div>
        </div>

        <p class="hint">
          Rows with a blank PC name are dropped on submit.
          Use the advanced roster override to paste a full roster.
        </p>

        <details class="advanced">
          <summary>Advanced</summary>
          <label>
            Seed
            <input data-testid="seed" name="run[seed]" value={@seed} />
          </label>
          <label>
            Adventure YAML
            <input data-testid="yaml" name="run[yaml]" value={@yaml} size="60" />
          </label>
          <label>
            Roster override — id|name|place|int|hp|ac|thac0|damage
            <textarea data-testid="roster" name="run[roster]" rows="4"><%= @roster %></textarea>
          </label>
        </details>

        <button type="submit">Start run</button>
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

  defp default_seat_rows do
    pcs =
      case parse_roster_text(@default_roster) do
        {:ok, pcs} -> pcs
        {:error, _} -> []
      end

    pcs
    |> Enum.map(&seat_row_from_pc/1)
    |> Kernel.++([empty_seat_row(), empty_seat_row()])
    |> Enum.with_index()
    |> Enum.map(fn {row, i} -> %{row | index: i} end)
  end

  defp seat_row_from_pc(pc) do
    %{
      index: nil,
      id: pc.id,
      name: pc.name,
      place_id: pc.place_id,
      int: to_string(pc.int),
      hp: to_string(pc.hp),
      ac: to_string(pc.ac),
      thac0: to_string(pc.thac0),
      damage: pc.damage,
      errors: []
    }
  end

  defp empty_seat_row do
    %{
      index: nil,
      id: "",
      name: "",
      place_id: "entry_hall",
      int: "",
      hp: "",
      ac: "",
      thac0: "",
      damage: "",
      errors: []
    }
  end

  defp seat_rows_from_params(seat_params) do
    seat_params = seat_params || %{}

    Enum.map(0..3, fn i ->
      fields = Map.get(seat_params, "#{i}") || Map.get(seat_params, i) || %{}

      %{
        index: i,
        id: to_string(fields["id"] || ""),
        name: to_string(fields["name"] || ""),
        place_id: to_string(fields["place_id"] || ""),
        int: to_string(fields["int"] || ""),
        hp: to_string(fields["hp"] || ""),
        ac: to_string(fields["ac"] || ""),
        thac0: to_string(fields["thac0"] || ""),
        damage: to_string(fields["damage"] || ""),
        errors: []
      }
    end)
  end

  defp roster_from_form(seat_rows, override) do
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
            case parse_seat_row(row) do
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

  defp blank_name?(row), do: String.trim(row.name) == ""

  defp parse_seat_row(row) do
    name = String.trim(row.name)
    id = String.trim(row.id)
    place_id = String.trim(row.place_id)
    damage = String.trim(row.damage)

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
