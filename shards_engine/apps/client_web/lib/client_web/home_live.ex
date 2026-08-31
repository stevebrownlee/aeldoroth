defmodule ClientWeb.HomeLive do
  @moduledoc """
  Landing surface: GM launch desk + adventurer portal + active-runs registry.

  The left column lets a Game Master start a run with Advanced Engine Options.
  The right column lets players join an existing run and lists all active runs.
  """

  use ClientWeb, :live_view

  alias EngineCore.Loader
  alias Referee.Run.Session
  alias LLMGateway.Config

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
       runs: list_runs()
     )}
  end

  @impl true
  def handle_event("create", %{"run" => run_params}, socket) do
    yaml = String.trim(run_params["yaml"] || default_yaml())
    run_id = String.trim(run_params["run_id"] || "")
    seed_result = parse_seed(run_params["seed"])
    roster_text = run_params["roster"] || ""

    pcs =
      case String.trim(roster_text) do
        "" -> []
        trimmed ->
          case parse_roster_text(trimmed) do
            {:ok, pcs} -> pcs
            {:error, _} -> :error
          end
      end

    with {:run_id, true} <- {:run_id, run_id != ""},
         {:seed, {:ok, seed}} <- {:seed, seed_result},
         {:yaml, true} <- {:yaml, File.exists?(yaml)},
         {:roster, true} <- {:roster, pcs != :error},
         {:live, true} <- {:live, Config.live?()},
         {:start, {:ok, _pid}} <- {:start, Session.start_link(run_id, yaml, seed, pcs)} do
      {:noreply, push_navigate(socket, to: "/runs/#{run_id}/gm")}
    else
      {:run_id, false} ->
        {:noreply, put_flash(socket, :error, "Run id is required")}

      {:seed, _} ->
        {:noreply, put_flash(socket, :error, "Seed must be an integer")}

      {:yaml, false} ->
        {:noreply, put_flash(socket, :error, "Adventure YAML not found: #{yaml}")}

      {:roster, false} ->
        {:noreply, put_flash(socket, :error, "Roster override is malformed")}

      {:live, false} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "LLM routing is offline. Set ANTHROPIC_API_KEY (see shards_engine/.env) and restart the server to enable live NPC brains."
         )}

      {:start, {:error, {:already_started, _pid}}} ->
        {:noreply, put_flash(socket, :error, "A run with that id already exists")}

      {:start, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, "Could not start run: #{inspect(reason)}")}
    end
  end

  def handle_event("join_run", %{"join" => %{"run_id" => run_id}}, socket) do
    {:noreply, push_navigate(socket, to: "/runs/#{String.trim(run_id)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-split">
      <section class="panel gm-launch-desk">
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

        <h2>Game Master Launch Desk</h2>
        <form id="gm_launch" phx-submit="create">
          <label>
            Run ID
            <input data-testid="run_id" name="run[run_id]" value={@run_id} />
          </label>

          <details class="advanced">
            <summary>Advanced Engine Options</summary>
            <div style="margin-top: 0.6rem;">
              <label>
                Seed
                <input data-testid="seed" name="run[seed]" value={@seed} />
              </label>
              <label>
                Starting Place Override
                <input name="run[starting_place]" value={@starting_place} placeholder={@starting_place} />
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

          <button type="submit" class="btn-start-run">Launch Game as GM</button>
        </form>
      </section>

      <section class="panel adventurer-portal">
        <h2>Adventurer Portal & Active Games</h2>

        <form id="player_join" phx-submit="join_run">
          <label>
            Join an existing adventure
            <input data-testid="join_run_id" name="join[run_id]" placeholder="Enter Run ID" />
          </label>
          <button type="submit" class="btn-join-run">Join Adventure</button>
        </form>

        <section class="active-runs">
          <h3>Active Games</h3>
          <table>
            <thead>
              <tr><th>Run</th><th>Status</th><th>Current Tick</th><th>Actions</th></tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs}>
                <td><%= run.id %></td>
                <td><%= run.status %></td>
                <td><%= run.tick %></td>
                <td>
                  <.link navigate={"/runs/#{run.id}"}>Join as Player</.link>
                  <.link navigate={"/runs/#{run.id}/gm"}>GM Console</.link>
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
      </section>
    </div>
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
      "entry_hall"
    end
  end

  defp place_label("maras_inn"), do: "Mara's Inn (Common Room), Thornhollow"
  defp place_label("entry_hall"), do: "Entry Hall (The Ruined Tower)"

  defp place_label(other),
    do: other |> to_string() |> String.replace("_", " ") |> String.capitalize()

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
