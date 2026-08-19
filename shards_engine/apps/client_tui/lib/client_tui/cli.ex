defmodule ClientTUI.CLI do
  @moduledoc """
  The reference terminal player (plan 5 Task 9; spec §11).

      mix run -e "ClientTUI.CLI.main(System.argv)" -- \
        --url http://localhost:4000 --run r1 --character pc_thistle

  Plain lines are `declare_intent`. Commands: `/ooc text`, `/sheet`,
  `/pause`, `/resume`, `/spend`, `/quit`. Server pushes print prefixed —
  `[perception] T1`, `[prompt] ...` — via a printer process that owns the
  connection's messages; stdin stays responsive in the main loop.
  """

  alias ClientTUI.Conn

  @commands ~w(/ooc /sheet /pause /resume /spend /quit)

  def main(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [
      url: :string, run: :string, character: :string, spectate: :boolean
    ])

    with {:ok, cfg} <- config(opts) do
      {:ok, conn} = Conn.start_link(cfg.url, run_id: cfg.run,
                                    character_id: cfg.character,
                                    spectate: cfg.spectate,
                                    parent: spawn(fn -> printer(:idle) end))

      IO.puts("connected to #{cfg.url} — run #{cfg.run}" <>
                role_suffix(cfg) <> ". /quit exits.")
      repl(conn, cfg)
    else
      {:error, reason} -> IO.puts(:stderr, "client: #{reason}")
    end
  end

  defp config(opts) do
    url = opts[:url] || "http://localhost:4000"
    run = opts[:run]

    cond do
      is_nil(run) ->
        {:error, "missing --run"}

      opts[:spectate] and opts[:character] ->
        {:error, "--spectate and --character are mutually exclusive"}

      true ->
        {:ok, %{url: url, run: run, character: opts[:character], spectate: opts[:spectate] || false}}
    end
  end

  defp repl(conn, cfg) do
    case IO.gets(prompt(cfg)) do
      :eof ->
        IO.puts("bye.")

      {:error, _} = err ->
        err

      line ->
        line = String.trim(line)

        case command(line) do
          :quit ->
            IO.puts("bye.")

          {:cmd, cmd, arg} ->
            handle_command(conn, cmd, arg)
            repl(conn, cfg)

          :say ->
            unless line == "", do: Conn.send_event(conn, "declare_intent", %{"text" => line})
            repl(conn, cfg)
        end
    end
  end

  defp command("/quit" <> _), do: :quit
  defp command(""), do: :say

  defp command("/" <> _ = line) do
    case String.split(line, " ", parts: 2) do
      [cmd] when cmd in @commands -> {:cmd, cmd, nil}
      [cmd, arg] when cmd in @commands -> {:cmd, cmd, String.trim(arg)}
      [unknown | _] -> {:cmd, :unknown, unknown}
    end
  end

  defp command(_line), do: :say

  defp handle_command(_conn, "/ooc", nil), do: IO.puts("usage: /ooc <text>")
  defp handle_command(conn, "/ooc", text), do: Conn.send_event(conn, "ooc", %{"text" => text})
  defp handle_command(conn, "/sheet", _), do: Conn.send_event(conn, "sheet", %{"update" => %{}})
  defp handle_command(conn, "/pause", _), do: Conn.send_event(conn, "pause", %{})
  defp handle_command(conn, "/resume", _), do: Conn.send_event(conn, "resume", %{})
  defp handle_command(conn, "/spend", _), do: Conn.send_event(conn, "spend", %{})
  defp handle_command(_conn, :unknown, cmd), do: IO.puts("unknown command #{cmd} — #{Enum.join(@commands, " ")}")

  # The printer owns pushes: the main loop blocks on IO.gets, so messages
  # must not queue behind stdin.
  defp printer(_topic) do
    receive do
      {:chan, _topic, event, payload} ->
        print_push(event, payload)
        printer(nil)

      {:chan_reply, _ref, status, payload} ->
        IO.puts("[#{status}] " <> brief(payload))
        printer(nil)
    end
  end

  defp print_push("perception", %{"text" => text}), do: IO.puts("[perception] #{text}")
  defp print_push("prompt", %{"question" => q}), do: IO.puts("[prompt] #{q}")
  defp print_push("dice", %{"event_payload" => p}), do: IO.puts("[dice] #{inspect(p)}")
  defp print_push("state_sync", %{"state" => %{"summary" => s}}) when is_binary(s), do: IO.puts("[state] #{s}")
  defp print_push("state_sync", %{"tick" => t}), do: IO.puts("[state] tick #{t}")

  defp print_push("ooc", %{"agent_id" => a, "text" => t}), do: IO.puts("[ooc] #{a}: #{t}")
  defp print_push("ledger_tail", %{"events" => events}) do
    Enum.each(events, fn ev -> IO.puts("[ledger] #{ev["seq"]} #{ev["tick"]} #{ev["class"]}") end)
  end

  defp role_suffix(%{spectate: true}), do: " (spectating)"
  defp role_suffix(%{character: char}), do: " as #{char}"
  defp brief(payload) do
    case payload do
      %{"reply" => text} when is_binary(text) -> text
      %{"dossiers" => dossiers} -> inspect(Map.keys(dossiers))
      %{} = m -> m |> Map.delete("state") |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{brief(v)}" end)
      other -> inspect(other)
    end
  end

  defp prompt(%{spectate: true, run: run}), do: "spectate:#{run} > "
  defp prompt(%{character: char, run: run}), do: "#{char}@run:#{run} > "
end
