# Serve script (plan 7 Task 6): boots the umbrella in dev and serves
# ClientWeb.Endpoint on PORT (default 4000). Single-file, boring on purpose —
# no runtime.exs machinery; the config stays `server: false` everywhere else.
#
# Run from shards_engine/:  MIX_ENV=dev mix run --no-halt scripts/web_server.exs

endpoint = ClientWeb.Endpoint
port = String.to_integer(System.get_env("PORT", "4000"))

# Plain KEY=VALUE lines (optional `export ` prefix — this repo's .env uses
# `export KEY=...`), `#` comments; outer matching quotes are stripped.
# A variable already present in the environment is never overwritten.
# (Closures rather than defp helpers: a .exs script cannot define functions.)
strip_quotes = fn
  <<q::utf8, rest::binary>> when q in [?", ?'] ->
    size = byte_size(rest)

    if size >= 1 and :binary.part(rest, size - 1, 1) == <<q>> do
      :binary.part(rest, 0, size - 1)
    else
      rest
    end

  value ->
    value
end

put_env_line = fn line ->
  case String.trim(line) do
    "" ->
      :ok

    "#" <> _ ->
      :ok

    trimmed ->
      trimmed = String.replace_prefix(trimmed, "export ", "")

      case :binary.split(trimmed, "=") do
        [key, value] ->
          key = String.trim(key)

          if key != "" and is_nil(System.get_env(key)) do
            System.put_env(key, strip_quotes.(String.trim(value)))
          end

          :ok

        _ ->
          :ok
      end
  end
end

source_env_file = fn path ->
  if File.exists?(path) do
    path
    |> File.read!()
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.each(&put_env_line.(&1))
  end

  :ok
end

# LLM activation (spec 2026-08-30 §4.2): source shards_engine/.env (per-var,
# explicit shell env wins), then apply live routing — Run.new reads
# Application config lazily per run creation, so sessions created after this
# point go live with no server restart. `../.env` is anchored on __DIR__
# (this script's directory) so the documented `cd shards_engine` command
# sources shards_engine/.env regardless of the invoking shell's cwd.
source_env_file.(Path.expand("../.env", __DIR__))
LLMGateway.Config.apply_env_routing()

routing_state =
  if LLMGateway.Config.live?() do
    "live (#{LLMGateway.Config.model()})"
  else
    "offline (set ANTHROPIC_API_KEY)"
  end

# Endpoint config is read at application start, so: merge server config into
# app env, then restart the client_web app alone (PubSub + Endpoint).
cfg = Keyword.merge(Application.get_env(:client_web, endpoint) || [], server: true, check_origin: false, http: [port: port])
Application.put_env(:client_web, endpoint, cfg)

# WebSockex client for player seats needs the app tree running.
Application.ensure_all_started(:client_tui)

Application.stop(:client_web)
Application.ensure_all_started(:client_web)

# Publish the loopback wire URL that player LiveViews connect through (same
# mechanism tests use; without an ExUnit server there is no teardown).
_wire_port = ClientWeb.TestSupport.start_bandit!()

IO.puts("""
[web_server] llm routing: #{routing_state}
[web_server] serving http://0.0.0.0:#{port}
[web_server] home (referee console):  /
[web_server] run seat:                /runs/<run_id>?pc=<pc_id>
[web_server] GM console:              /runs/<run_id>/gm
""")

:timer.sleep(:infinity)
