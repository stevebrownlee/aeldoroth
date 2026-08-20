# Agent Engine — Plan 7: `client_web` LiveView Web Client

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement plan task-by-task. Steps use checkbox (`- [ ]`) syntax tracking.

**Goal:** Spec §11 client surface — a Phoenix LiveView web client (`apps/client_web`) over the *existing* WS wire protocol. Players play through the exact same channel contract the TUI uses (`Wire.Socket` → `run:<id>`); a GM console renders the spectate channel and holds the referee's advance lever. Ends with a browser-driven two-PC live session over `the-ruined-tower` as deliverable proof.

**Scope split (deliberate):** The wire protocol is frozen (plan 5; decision 50) — **zero changes to `apps/wire`, `apps/engine_core`, `apps/agents`, `apps/llm_gateway`, `apps/client_tui`**. One small referee addition: `Session.roster/1` (read-only, live-run surface) so the web seat-picker can list PCs. v2 campaign memory and platform packaging remain out (decisions 34, 35).

**Architecture (the load-bearing decision):** one endpoint, two sockets, two trust zones.

- `ClientWeb.Endpoint` (Bandit) serves **both** sockets on one port:
  - `/live` — `Phoenix.LiveView.Socket` (the UI)
  - `/socket` — the wire app's `Wire.Socket`, re-mounted verbatim (channels are endpoint-agnostic; `apps/wire` needs no change)
- **Player surfaces are protocol clients, nothing more.** `RunLive` connects through `ClientTUI.Conn` (WebSockex, loopback to this same endpoint) — every datum it renders came over the wire as a slice/push. The truth barrier (spec §9, §11) holds by construction: the LiveView never calls World/Run/Session for player data.
- **Host surfaces are a trusted engine console.** `HomeLive` creates runs (`Session.start_link/5`); `SpectateLive` adds one lever the wire doesn't carry in v1: `Session.advance/1`. Zero-routing sessions are the web default — smoke-proven 2026-08-19: `Session.start_link` with no routing → grammar interpretation + template narration play deterministically with zero LLM config.
- Web runs pass `data_dir: nil` (no journals) in v1; restore stays a script/test surface.

**Tech Stack:** Elixir 1.17 / OTP 27, Phoenix 1.8.11 (locked), `phoenix_live_view ~> 1.1` (new dep), Bandit, WebSockex (via client_tui), HEEx + hand-rolled minimal CSS (no npm/esbuild/Tailwind). LV JS + Phoenix JS are **vendored** into `priv/static/assets/` (committed) — the referee console must run offline.

**Spec:** `docs/superpowers/specs/agent-engine-spec.md` §11 (protocol & clients), §12.1 (topology), §12.2 (umbrella layout); seed adventure `the-ruined-tower/ruined_tower.yaml`.

**Engrams (settled — do not re-litigate):** 24/50 (wire protocol is the public contract; app named `wire`, never `Protocol`), 37 (v1 client = TUI; **client_web is the sanctioned post-v1 next step** — this plan supersedes the "channels + TUI only" half, the protocol-freeze half stands), 17 (custom Elixir/Phoenix codebase), 34/35 (out-of-scope items). Patterns: 9 (`brains-hold-no-authority-state`), 10 (`append-only-ledger`), 11 (`effects-via-referee-pipeline`), 14 (`llm-gateway-single-chokepoint`).

## Context & Constraints

- **Do not touch:** `apps/wire/**`, `apps/engine_core/**`, `apps/agents/**`, `apps/llm_gateway/**`, `apps/client_tui/**`. `apps/referee` gets exactly one addition (`Session.roster/1`, Task 2). Umbrella test count 316 must stay green (317 after Task 2).
- **Wire contract (frozen, from `apps/wire/PROTOCOL.md` + reference client `apps/client_tui/lib/client_tui/conn.ex` + `cli.ex`):**
  - Socket connect params (query string): `vsn=2.0.0`, `run_id` (required), optional `character_id`. No `character_id` ⇒ spectate role.
  - `ClientTUI.Conn.start_link(url, run_id:, character_id: nil, spectate: false, parent: self(), heartbeat_every: 30_000)` — parent receives `{:chan, topic, event, payload}` (pushes) and `{:chan_reply, ref, :ok | :error, payload}` (replies).
  - `run:<id>` channel — join reply `%{state: slice, dossier: text|nil}`; in-events `declare_intent`/`answer` `%{"text" => s}`, `ooc` `%{"text" => s}`, `sheet` `%{"update" => %{}}`; pushes `perception` `%{text, tick}`, `prompt` `%{question}`, `dice` `%{event_payload}`, `state_sync` `%{state: slice}`, `ooc` `%{agent_id, text}`.
  - `spectate:<id>` channel — join reply `%{tick, boundaries, spend, tail}` (tail = last 50 ledger events as JSON maps); in-events `pause`, `resume`, `spend` (all `%{}`); pushes `ledger_tail` `%{events}`, `state_sync` `%{tick, boundaries}`.
  - Slice shape (`Referee.Slice.for_actor/2`): `%{agent: %{id,name,place_id}, place: %{id,name,kind,exits,visible_items}, believed, salient, commitments, capabilities, summary}`.
- **Session API (live-run surface, `Referee.Run.Session`):** `start_link(run_id, yaml, seed, pcs, opts \\ [])`, `declare/3 → {:ok, %{reply: text}} | {:error, :paused | :no_run}`, `advance/1`, `pause/1 → {:ok, %{dossiers: %{pc_id => text}}}`, `resume/1`, `state/1 → %{run_id, status, tick, seq} | nil`, `stop/1`. Registry `Referee.SessionReg` keys `{:session, run_id}`; world truth via `EngineCore.RunSup.stop_run/1` at teardown.
- **Test topology (mirror `apps/client_tui/test/e2e_ws_test.exs`):** endpoint starts with `server: false`; each WS-touching test starts its own `Bandit.start_link(plug: ClientWeb.Endpoint, port: 0)`, stores the URL in `Application.get_env(:client_web, :wire_url)`, tears down `Session.stop(id); EngineCore.RunSup.stop_run(id)`. LiveView tests (`Phoenix.LiveViewTest`) drive the LV in-process while its `ClientTUI.Conn` talks to the real Bandit loopback.
- **Determinism:** the web app adds no ledger content and no new event kinds. `run_id` uniqueness (`web-<unique_integer>`) and DOM ids may use non-deterministic sources — they are UI-local, never ledgered. Player flows produce the same ledger as TUI flows (same channel code path).
- **No new LLM routing:** web runs use the empty routing table → grammar/template fallback. Budgets/spend behave as scripted-free sessions already do.
- Runs created by tests must be torn down (sessions are `:temporary`; the ETS ledger replica and World.Server leak otherwise).

## File Map

```
shards_engine/
├── apps/
│   ├── referee/lib/referee/run/session.ex   # MODIFY: +roster/1 (Task 2, only referee change)
│   └── client_web/                           # CREATE app (deps: phoenix, phoenix_live_view,
│       │                                     #   bandit, jason, client_tui+referee+wire in_umbrella)
│       ├── mix.exs · lib/client_web.ex · README.md
│       ├── lib/client_web/application.ex     # PubSub + Endpoint (server: false)
│       ├── lib/client_web/endpoint.ex        # /live + /socket sockets, static assets
│       ├── lib/client_web/router.ex          # 3 live routes
│       ├── lib/client_web/layouts.ex         # root + app HEEx (vendored JS, minimal CSS)
│       ├── lib/client_web/home_live.ex       # new-run form + active runs list (engine console)
│       ├── lib/client_web/run_live.ex        # seat picker → play surface (wire client)
│       ├── lib/client_web/spectate_live.ex   # GM console (wire spectate + Session.advance)
│       ├── lib/client_web/test_support.ex    # Bandit boot + run teardown helper (shared by tests)
│       ├── priv/static/assets/phoenix.min.js              # vendored (copy from deps/phoenix)
│       ├── priv/static/assets/phoenix_live_view.min.js    # vendored (fetched once, committed)
│       └── test/
│           ├── test_helper.exs
│           ├── home_live_test.exs
│           ├── run_live_test.exs
│           └── spectate_live_test.exs
└── config/config.exs                          # MODIFY: +client_web endpoint config
```

## Shared Interfaces (tasks must match these exactly)

- `ClientWeb.Endpoint` — sockets: `/live` (LiveView, `connect_info: [session: @session_options]`) and `/socket` (`Wire.Socket`, `websocket: [timeout: 45_000, check_origin: false]`, mirroring `Wire.Endpoint`). `plug Plug.Static, at: "/assets", from: {:client_web, "priv/static/assets"}, only: ~w(phoenix.min.js phoenix_live_view.min.js)` — the tuple's path is app-relative (joined to `Application.app_dir/1`), so `priv/` must be explicit.
- `ClientWeb.Router` — `live "/", HomeLive` · `live "/runs/:run_id", RunLive` · `live "/runs/:run_id/gm", SpectateLive`, all through a `:browser` pipeline (`accepts ["html"]`, `fetch_session`, `fetch_live_flash`, `put_root_layout html: {ClientWeb.Layouts, :root}`).
- `Referee.Run.Session.roster(run_id) :: [%{id: String.t(), name: String.t()}] | nil` — the seat list; `nil` when the run doesn't exist.
- `ClientWeb.TestSupport.start_bandit!() :: :ok` — boots `ClientWeb.Endpoint` on port 0, `Application.put_env(:client_web, :wire_url, "http://127.0.0.1:#{port}")`, registers `on_exit` teardown. `ClientWeb.TestSupport.stop_run(run_id)` — `Session.stop/1` + `EngineCore.RunSup.stop_run/1`.
- `HomeLive` — form params: `run_id` (slug, prefilled `web-<unique_integer>`), `seed` (int, default 42), `yaml` (path, default `Application.get_env(:client_web, :adventure_yaml, "../the-ruined-tower/ruined_tower.yaml")`), `roster` (textarea, one PC per line `id|name|place|hp|ac|thac0|damage`, prefilled with the two canonical PCs). Submits via `Session.start_link(run_id, yaml, seed, pcs)`; redirects to `/runs/:run_id`. Active runs list: `Registry.select(Referee.SessionReg, [{{{:_, :"$1"}, :_, :_}, [], [:"$1"]}])` filtered to `{:session, id}` tuples, each linked with status from `Session.state/1`.
- `RunLive` — no `pc` param ⇒ picker from `Session.roster/1`. With `pc`: on `connected?/1`, `ClientTUI.Conn.start_link(wire_url, run_id:, character_id: pc, parent: self())`; `handle_info/2` fans out: join reply → `assign(slice, dossier, joined: true)`; `perception`/`ooc`/`dice` → `stream_insert(:log, …)`; `prompt` → `assign(prompt: question)`; `state_sync` → `assign(slice)`; `{:chan_reply, _, :error, %{"reason" => reason}}` → flash. Forms: `declare_intent` (or `answer` when a prompt is open, which also clears it) and `ooc`.
- `SpectateLive` — `Conn.start_link(wire_url, run_id:, spectate: true)`; join reply snapshot → assigns `tick`, `boundaries`, `spend`; `ledger_tail` → `stream_insert(:tail, …)` with `id: "seq-#{e["seq"]}"`; `state_sync` → update `tick`/`boundaries`. Buttons: **Advance tick** (`Session.advance(run_id)`, the engine-console lever), pause (reply `{:ok, %{"dossiers" => dossiers}}` → flash the dossier texts), resume, spend refresh.
- Ledger-tail rows render `seq · tick · class` (+ payload summary line, JSON-ish inspect).

---

### Task 1: Scaffold `client_web` app, endpoint, router, layouts, vendored assets

**Files:**
- Create: `shards_engine/apps/client_web/{mix.exs, lib/client_web.ex, lib/client_web/application.ex, lib/client_web/endpoint.ex, lib/client_web/router.ex, lib/client_web/layouts.ex, priv/static/assets/, test/test_helper.exs, test/home_live_test.exs, README.md}`
- Modify: `shards_engine/config/config.exs`, `shards_engine/.gitignore` (nothing new expected — verify `priv/static/assets` is NOT ignored)

**Steps:**

- [ ] **1.1 Create the app** from `shards_engine/`: `mix new apps/client_web --sup` then rewrite:
  - `mix.exs` app `:client_web`; deps: `{:phoenix, "~> 1.8"}`, `{:phoenix_live_view, "~> 1.1"}`, `{:bandit, "~> 1.0"}`, `{:jason, "~> 1.0"}`, `{:client_tui, in_umbrella: true}`, `{:referee, in_umbrella: true}`, `{:wire, in_umbrella: true}`. `extra_applications: [:logger, :runtime_tools]`. Run `mix deps.get` and record the resolved `phoenix_live_view` version (needed in 1.4).
  - `lib/client_web/application.ex`: children `[{Phoenix.PubSub, name: ClientWeb.PubSub}, ClientWeb.Endpoint]`, `strategy: :one_for_one`.
  - `test/test_helper.exs`: `ExUnit.start()`.
- [ ] **1.2 Endpoint** (`lib/client_web/endpoint.ex`) per Shared Interfaces — both sockets, static plug, `Plug.Session` with cookie store + fixed dev/test `secret_key_base` in config, then `ClientWeb.Router`. Mirror `apps/wire/lib/wire/endpoint.ex` for the `/socket` options (`check_origin: false`, `timeout: 45_000`).
- [ ] **1.3 Router + Layouts** per Shared Interfaces. `lib/client_web/layouts.ex`: `use ClientWeb, :html` with `embed_templates "layouts/*"`. `layouts/root.html.heex`: `<html>` skeleton, inline `<style>` (dark background, monospace, max-width column, simple log/table styling), vendored script tags, `LiveView` bootstrap:
  ```html
  <script defer src="/assets/phoenix.min.js"></script>
  <script defer src="/assets/phoenix_live_view.min.js"></script>
  <script defer>
    window.addEventListener("phx:page-loading-stop", () => {});
    const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket);
    liveSocket.connect();
  </script>
  ```
  `layouts/app.html.heex`: `<.flash_group flash={@flash} />` hand-rolled (two small `<div>`s reading `@flash["info"|"error"]`) + `@inner_content`.
  Also create `lib/client_web.ex` (`defmodule ClientWeb`) with `def html` macro (`use Phoenix.Component, global_prefixes: ~w(phx)`) so `use ClientWeb, :html` works.
- [ ] **1.4 Vendor JS assets:** `cp deps/phoenix/priv/static/phoenix.min.js apps/client_web/priv/static/assets/`. For LV: resolve the exact version from 1.1 (`mix deps | grep live_view`), list package files at `https://data.jsdelivr.com/v1/packages/npm/phoenix_live_view@<version>`, fetch the prebuilt minified IIFE (typically `priv/static/phoenix_live_view.min.js` inside the npm tarball) to `apps/client_web/priv/static/assets/phoenix_live_view.min.js`. Verify offline-fitness: file exists, non-empty, defines `LiveSocket` (grep once). Commit it — never fetched at runtime.
- [ ] **1.5 Config** (`shards_engine/config/config.exs`): `config :client_web, ecto_repos: []` not needed; add:
  ```elixir
  config :client_web, ClientWeb.Endpoint,
    adapter: Bandit.PhoenixAdapter,
    server: false,
    url: [host: "localhost"],
    secret_key_base: "clientweb-local-referee-console-not-a-secret",
    pubsub_server: ClientWeb.PubSub,
    live_view: [signing_salt: "clientweb_lv_salt"]
  ```
  Serving on a real port is deliberately **not** configured here — the endpoint stays `server: false` in dev/test (exactly like `Wire.Endpoint`; tests boot their own Bandit). Task 6.1's `scripts/web_server.exs` flips `server: true` + `http: [port: …]` into the env at boot.
- [ ] **1.6 Landing smoke test** (`test/home_live_test.exs`): stub `HomeLive` renders `<h1>The Shattered Kingdoms</h1>` + form shell (no Session calls yet):
  ```elixir
  defmodule ClientWeb.HomeLiveTest do
    use ClientWeb.ConnCase
    import Phoenix.LiveViewTest
    test "renders home", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      assert html =~ "The Shattered Kingdoms"
    end
  end
  ```
  `test/support/conn_case.ex`: `use ExUnit.CaseTemplate` + `using do quote do use Phoenix.ConnTest, endpoint: ClientWeb.Endpoint import Phoenix.LiveViewTest end end` + `setup` mapping `conn: build_conn()`. Add `elixirc_paths(:test)` in mix.exs.
- [ ] **1.7 Verify:** `mix test apps/client_web` green; `mix compile --warnings-as-errors` clean; full `mix test` still 316.
- [ ] **1.8 Commit:** `client_web: scaffold LiveView app with dual-socket endpoint and vendored assets`.

### Task 2: `Session.roster/1` — seat list for the picker (only referee change)

**Files:**
- Modify: `shards_engine/apps/referee/lib/referee/run/session.ex`
- Test: `shards_engine/apps/referee/test/session_test.exs` (extend)

**Steps:**

- [ ] **2.1 Failing test:** in `session_test.exs`, start a session with the canonical two PCs (existing test module already has helpers) and assert `Session.roster(id) == [%{id: "pc_thistle", name: "Thistle"}, %{id: "pc_bramble", name: "Bramble"}]`; assert `Session.roster("nope") == nil`.
- [ ] **2.2 Implement:** client API mirroring `state/1` (`whereis` → `GenServer.call(pid, :roster)`); `handle_call(:roster, _from, st)` replies `Enum.map(st.run.pcs, &%{id: &1.id, name: &1.name})` (the injected pc maps carry `id`/`name`). Add `@doc` noting: GM-console introspection, not on the wire.
- [ ] **2.3 Verify:** `mix test apps/referee` green (117 tests now).
- [ ] **2.4 Commit:** `referee: Session.roster/1 seat list for web picker`.

### Task 3: `HomeLive` — new-run form + active runs (engine console)

**Files:**
- Create: `shards_engine/apps/client_web/lib/client_web/home_live.ex`
- Create: `shards_engine/apps/client_web/lib/client_web/test_support.ex`
- Test: `shards_engine/apps/client_web/test/home_live_test.exs` (replace stub)

**Steps:**

- [ ] **3.1 `TestSupport`** per Shared Interfaces: `start_bandit!/0` (copy the pattern from `apps/client_tui/test/e2e_ws_test.exs` — `Bandit.start_link(plug: ClientWeb.Endpoint, port: 0)`, read the bound port from the ThousandIsland listener, `Application.put_env(:client_web, :wire_url, …)`, `on_exit` kill + `delete_env`) and `stop_run/1`. Put it in `lib/` (not `test/support/`) so Task 6's serve script can reuse teardown; it's test+console plumbing, not player surface.
- [ ] **3.2 Failing tests (TDD):**
  - "creates a run and redirects" — `live(conn, "/")`, fill `[data-testid=run_id]` with a fixed slug, `[data-testid=seed]` 42, roster textarea default, `render_click` submit → assert `redirect` to `/runs/<slug>`; assert `Session.state(slug)` non-nil and `Session.roster(slug)` == parsed PCs. Teardown `TestSupport.stop_run/1`.
  - "lists active runs" — start a session via `Session.start_link/5` directly, render `/`, assert the run slug appears with its status; teardown.
  - "rejects a malformed roster line" — roster `pc_x|NoPlace` (missing fields) → no redirect, error flash names the line; no session registered.
- [ ] **3.3 Implement `HomeLive`:**
  - `mount/3`: `assign(run_id: "web-#{:erlang.unique_integer([:positive])}", seed: 42, yaml: default_yaml(), roster: default_roster_text(), runs: list_runs())` where `default_yaml/0` reads app env (`../the-ruined-tower/ruined_tower.yaml`, cwd = `shards_engine/`).
  - `handle_event("create", %{"run" => params}, socket)`: parse roster lines (`String.split("|")`, 7 fields, trim; map to `%{id, name, place_id, hp, ac, thac0, damage}` + `int: 10` default — hmm: the canonical roster line has `id|name|place|hp|ac|thac0|damage`; `int` matters for interpretation — extend the line format to `id|name|place|int|hp|ac|thac0|damage` (8 fields) and prefill accordingly: `pc_thistle|Thistle|entry_hall|13|12|5|20|1d8`). Coerce ints; any malformed line → `{:noreply, put_flash(socket, :error, "bad line: …")}`.
  - `Session.start_link(run_id, yaml, seed, pcs)` → `{:ok, _pid}` → `{:noreply, push_navigate(socket, to: "/runs/#{run_id}")}`; `{:error, reason}` → error flash `inspect(reason)`.
  - `list_runs/0`: `Registry.select(Referee.SessionReg, [{{{:_, :"$1"}, :_, :_}, [], [:"$1"]}]) |> Enum.filter(&match?({:session, _}, &1)) |> Enum.map(fn {:session, id} -> %{id: id, status: Session.state(id).status} end) |> Enum.sort_by(& &1.id)`.
  - HEEx: form with the four inputs (`phx-submit="create"`, `data-testid`s), runs table linking `/runs/:id` (+ `/runs/:id/gm` link per row). Mark the block "Referee console — trusted" in the header copy to make the trust split visible.
- [ ] **3.4 Verify:** `mix test apps/client_web`; full umbrella green.
- [ ] **3.5 Commit:** `client_web: HomeLive run creation and registry listing`.

### Task 4: `RunLive` — seat picker and play surface (wire client)

**Files:**
- Create: `shards_engine/apps/client_web/lib/client_web/run_live.ex`
- Test: `shards_engine/apps/client_web/test/run_live_test.exs`

**Steps:**

- [ ] **4.1 Failing tests (TDD)** — each: `TestSupport.start_bandit!()`, start a zero-routing session (`Session.start_link/5`, canonical PCs, yaml via `Path.expand`), teardown. Wait-for pattern: poll `render(view)` up to ~2s (helper `eventually/1`).
  - "picker lists PCs when no seat chosen" — `live(conn, "/runs/#{id}")` → assert both PC names render as seat links (`live(conn, "/runs/#{id}?pc=pc_thistle")` for the seat).
  - "joining a seat renders the slice" — `?pc=pc_thistle` → eventually assert Thistle's name, `Entry Hall` (slice `place.name`), summary text, and dossier (join reply) render.
  - "declare flows and perceptions stream" — submit `declare_intent` "I head north" → eventually assert the reply ("You go north.") appears in the log stream; then (GM lever, in-test via `Session.advance/1`) eventually assert the next perception/state_sync tick rows appear.
  - "paused run refuses declares" — `Session.pause(id)` → submit declare → eventually assert error flash carries "paused".
  - "ooc renders for everyone" — second seat (bramble, separate `live` view in the same test) sees the ooc row after thistle sends it.
- [ ] **4.2 Implement `RunLive`** per Shared Interfaces. Shape:
  ```elixir
  def mount(%{"run_id" => run_id} = params, _s, socket) do
    socket = assign(socket, run_id: run_id, pc: params["pc"], slice: nil, dossier: nil,
                    prompt: nil, conn: nil, joined: false)
    if connected?(socket) && socket.assigns.pc do
      {:ok, pid} = Conn.start_link(wire_url(), run_id: run_id, character_id: socket.assigns.pc, parent: self())
      {:ok, assign(socket, conn: pid)}
    else
      roster = Session.roster(run_id)
      {:ok, assign(socket, roster: roster) |> stream(:log, [])}
    end
  end
  ```
  - `handle_info({:chan_reply, _ref, :ok, %{"state" => slice} = reply}, socket)` — join reply: `assign(slice: slice, dossier: reply["dossier"], joined: true) |> stream(:log, [])`.
  - `handle_info({:chan, "run:" <> _, "perception", %{"text" => t, "tick" => n}}, s)` → `stream_insert(:log, %{id: "p#{n}-#{uniq()}", kind: "perception", text: "[tick #{n}] #{t}"})`. Same shape for `ooc` (`%{agent_id, text}`) and `dice` (`inspect(event_payload)`).
  - `prompt` → `assign(prompt: question)`; `state_sync` `%{"state" => slice}` → `assign(slice: slice)`; unknown pushes → `{:noreply, socket}` (never crash on protocol growth).
  - `{:chan_reply, _ref, :error, %{"reason" => reason}}` → error flash `to_string(reason)`.
  - Forms: one input, submit target `"declare"`; `handle_event("declare", …)` sends `answer` when `prompt` non-nil (and clears it), else `declare_intent`. `/ooc` toggle or a second small form → `"ooc"`.
  - HEEx: dossier panel, slice panel (place name, exits, salient beliefs, commitments), prompt banner when set, `id="log"` stream container, forms. All content from assigns only — no engine calls anywhere in this module (grep-verifiable: no `Session.`, no `World.`, no `Run.`).
- [ ] **4.3 Verify:** `mix test apps/client_web`; grep the module for forbidden calls (`Session\.|EngineCore\.|Referee\.`) — must be absent.
- [ ] **4.4 Commit:** `client_web: RunLive seat picker and wire play surface`.

### Task 5: `SpectateLive` — GM console (spectate channel + advance lever)

**Files:**
- Create: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

**Steps:**

- [ ] **5.1 Failing tests (TDD):**
  - "renders snapshot" — live `/runs/#{id}/gm` → eventually assert tick, boundary rows, spend table, and tail rows (join reply snapshot) render.
  - "advance grows the tail" — click `[data-testid=advance]` → eventually assert new `seq-` rows in the tail stream and tick advanced (state_sync).
  - "pause returns dossiers" — click pause → eventually assert dossier text(s) flash; resume re-enables advance.
  - "unknown run" — `/runs/nope/gm` → error message, no crash (Conn join error reply → flash + `assign(joined: false)`).
- [ ] **5.2 Implement** per Shared Interfaces: `Conn.start_link(wire_url(), run_id:, spectate: true)`; join reply → assigns + `stream(:tail, …)`; `ledger_tail`/`state_sync` handlers; advance button calls `Session.advance(run_id)` (explicitly labeled "Referee authority — engine console, not wire"); pause/resume/spend via `Conn.send_event` with reply handling.
- [ ] **5.3 Verify:** `mix test apps/client_web`; full umbrella green.
- [ ] **5.4 Commit:** `client_web: SpectateLive GM console with advance lever`.

### Task 6: Live browser proof + serve script

**Files:**
- Create: `shards_engine/scripts/web_server.exs` (+ optional thin `web_smoke.sh`)
- Modify: this plan's checkboxes; `docs/superpowers/specs/agent-engine-spec.md` §12.2 umbrella layout note (add client_web) — one line.

**Steps:**

- [ ] **6.1 `web_server.exs`:** boots the umbrella in dev, merges `server: true` + `http: [port: System.get_env("PORT", "4000")]` into the endpoint child spec (restart `ClientWeb.Endpoint` if already started), prints the URL, `:timer.sleep(:infinity)`. This is the boring single-file server entry — no runtime.exs machinery.
- [ ] **6.2 Browser e2e (deliverable proof, via the `browser` tool):**
  1. `MIX_ENV=dev mix run --no-halt scripts/web_server.exs` (cwd `shards_engine/`; the default yaml path resolves to `../the-ruined-tower/…`).
  2. Browser tab A: create a run on `/` → redirected to `/runs/<id>`; pick Thistle.
  3. Tab B: `/runs/<id>?pc=pc_bramble` (Bramble seat).
  4. Tab C: `/runs/<id>/gm` — click Advance.
  5. Assert in tabs A/B: perception/`You go north.` rows appear after declare + advance; assert tab C tail rows grow and tick increments.
  6. Screenshot each surface; save under `shards_engine/runs/` (gitignored) — proof artifacts.
- [ ] **6.3 Full verification sweep:** `mix test` (umbrella, all apps green — expected count 316 + ~15 client_web + 1 referee); `MIX_ENV=dev mix compile --warnings-as-errors`.
- [ ] **6.4 Commit:** `client_web: serve script and browser-verified live session`.

## Verification (plan complete when all hold)

1. `mix test` from `shards_engine/` — green, including the new `client_web` suite (Bandit loopback WS in LiveView tests).
2. `grep -rE "Session\.|EngineCore\.|Referee\." apps/client_web/lib/client_web/run_live.ex` — empty (player surface is wire-only; the truth barrier is structural).
3. Browser session per Task 6.2 with screenshots — two PC seats + GM console playing `the-ruined-tower` live.
4. `apps/wire`, `apps/engine_core`, `apps/agents`, `apps/llm_gateway`, `apps/client_tui` diff-free vs. `main` (only `referee/run/session.ex` gains `roster/1`).

## Session end (after verification)

`engrams decision log` — web client architecture: dual-socket endpoint, player-LiveViews-are-protocol-clients (truth barrier by construction), host-console trust split (Home/GM call Session directly), vendored assets, zero-routing default (supersedes the "no web client" half of decision 37; protocol freeze stands). Link: `implements` spec §11; `link add` to decision 37 (`refines`). `engrams progress log --status Done`; `active-context update --patch`; `engrams export`; commit & push `engrams_export/`.
