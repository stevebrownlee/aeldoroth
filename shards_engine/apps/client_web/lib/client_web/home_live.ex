defmodule ClientWeb.HomeLive do
  @moduledoc """
  Referee console landing (plan 7 Task 3): new-run form (run id, seed,
  adventure YAML, roster) + the active-runs registry listing.

  Trusted surface: this is the only page that starts `Referee.Run.Session`
  processes. Player seats live under `/runs/:id`, spectators under
  `/runs/:id/gm`.
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
       roster: @default_roster,
       runs: list_runs()
     )}
  end

  @impl true
  def handle_event("create", %{"run" => params}, socket) do
    yaml = String.trim(params["yaml"] || default_yaml())

    with {:run_id, run_id} when run_id != "" <- {:run_id, String.trim(params["run_id"] || "")},
         {:seed, {:ok, seed}} <- {:seed, parse_seed(params["seed"])},
         {:roster, {:ok, pcs}} <- {:roster, parse_roster(params["roster"] || "")},
         {:yaml, true} <- {:yaml, File.exists?(yaml)},
         {:start, {:ok, _pid}} <- {:start, Session.start_link(run_id, yaml, seed, pcs)} do
      {:noreply, push_navigate(socket, to: "/runs/#{run_id}")}
    else
      {:run_id, _} ->
        {:noreply, put_flash(socket, :error, "Run id is required")}

      {:seed, _} ->
        {:noreply, put_flash(socket, :error, "Seed must be an integer")}

      {:roster, {:error, msg}} ->
        {:noreply, put_flash(socket, :error, "Roster: #{msg}")}

      {:yaml, _} ->
        {:noreply, put_flash(socket, :error, "Adventure YAML not found: #{yaml}")}

      {:start, {:error, {:already_started, _pid}}} ->
        {:noreply, put_flash(socket, :error, "A run with that id already exists")}

      {:start, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, "Could not start run: #{inspect(reason)}")}
    end
  end

  def handle_event("create", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Malformed form")}

  @impl true
  def render(assigns) do
    ~H"""
    <h1>The Shattered Kingdoms</h1>
    <p>Referee console — trusted surface. Player seats: /runs/:id · GM console: /runs/:id/gm</p>

    <section>
      <h2>New run</h2>
      <form id="new_run" phx-submit="create">
        <label>Run id <input data-testid="run_id" name="run[run_id]" value={@run_id} /></label>
        <label>Seed <input data-testid="seed" name="run[seed]" value={@seed} /></label>
        <label>
          Adventure YAML <input data-testid="yaml" name="run[yaml]" value={@yaml} size="60" />
        </label>
        <label>
          Roster — one PC per line: id|name|place|int|hp|ac|thac0|damage
          <textarea data-testid="roster" name="run[roster]" rows="4"><%= @roster %></textarea>
        </label>
        <button type="submit">Start run</button>
      </form>
    </section>

    <section>
      <h2>Active runs</h2>
      <table>
        <thead>
          <tr><th>Run</th><th>Status</th><th></th></tr>
        </thead>
        <tbody>
          <tr :for={run <- @runs}>
            <td><.link navigate={"/runs/#{run.id}"} data-testid={"run-link-#{run.id}"}>{run.id}</.link></td>
            <td>{run.status}</td>
            <td><.link navigate={"/runs/#{run.id}/gm"}>GM console</.link></td>
          </tr>
          <tr :if={@runs == []}>
            <td colspan="3">No active runs.</td>
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

  # One PC per line: id|name|place|int|hp|ac|thac0|damage (hd fixed at 1 —
  # the starter roster is 1st-level; levels arrive with content, not forms).
  defp parse_roster(text) do
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

  defp list_runs do
    Referee.SessionReg
    |> Registry.select([{{{:session, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.map(fn id -> %{id: id, status: status_of(id)} end)
    |> Enum.sort_by(& &1.id)
  end

  defp status_of(id) do
    case Session.state(id) do
      %{status: status} -> status
      nil -> :gone
    end
  end
end
