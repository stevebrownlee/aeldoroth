# Serve script (plan 7 Task 6): boots the umbrella in dev and serves
# ClientWeb.Endpoint on PORT (default 4000). Single-file, boring on purpose —
# no runtime.exs machinery; the config stays `server: false` everywhere else.
#
# Run from shards_engine/:  MIX_ENV=dev mix run --no-halt scripts/web_server.exs

endpoint = ClientWeb.Endpoint
port = String.to_integer(System.get_env("PORT", "4000"))

# Endpoint config is read at application start, so: merge server config into
# app env, then restart the client_web app alone (PubSub + Endpoint).
cfg = Keyword.merge(Application.get_env(:client_web, endpoint) || [], server: true, http: [port: port])
Application.put_env(:client_web, endpoint, cfg)

# WebSockex client for player seats needs the app tree running.
Application.ensure_all_started(:client_tui)

Application.stop(:client_web)
Application.ensure_all_started(:client_web)

# Publish the loopback wire URL that player LiveViews connect through (same
# mechanism tests use; without an ExUnit server there is no teardown).
_wire_port = ClientWeb.TestSupport.start_bandit!()

IO.puts("""
[web_server] serving http://0.0.0.0:#{port}
[web_server] home (referee console):  /
[web_server] run seat:                /runs/<run_id>?pc=<pc_id>
[web_server] GM console:              /runs/<run_id>/gm
""")

:timer.sleep(:infinity)
