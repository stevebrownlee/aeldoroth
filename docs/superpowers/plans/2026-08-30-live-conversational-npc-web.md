# Live Conversational NPCs in Web Play — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make web-play NPC speech organic (LLM-live) instead of canned rumor parroting: deterministic `.env` → routing activation, lobby hard requirement, GM live/offline badge, and an organic-derivation deliberation prompt.

**Architecture:** The routing activation logic moves from `config/runtime.exs` into one module (`LLMGateway.Config`) that boot, the web server script, the lobby gate, and the GM badge all share, so "live" has exactly one definition. The deliberation prompt is rebuilt to derive persona, listeners, and the question from the agent's own slice — no YAML speech authoring. Offline deterministic behavior is untouched.

**Tech Stack:** Elixir umbrella (`shards_engine/apps/{engine_core,llm_gateway,referee,wire,client_tui,client_web}`), Phoenix LiveView, ExUnit. Spec: `docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md` (approved).

## Global Constraints

- All Elixir work happens under `shards_engine/`; run suites with `mix test` from `shards_engine/` (umbrella root). Single test file: `cd shards_engine/apps/<app> && mix test test/<file>.exs`.
- Decision 69 stands: **five** live classes (`deliberate, adopt, interpret, narrate, summarize`), Anthropic config-only, defaults `model: claude-haiku-4-5-20251001`, `endpoint: https://api.anthropic.com/v1/messages`, `temperature: 0.2`, `max_tokens: 1024`, `timeout` from `ANTHROPIC_TIMEOUT` (default `10_000`).
- Decision 36: keys are deployment config resolved via `key_ref: :anthropic_main` against `config :llm_gateway, :keys`; never literals in code.
- Decision 88 (addressee-private directed speech; unaddressed NPCs hold) must not weaken. Its two prompt rules appear **verbatim** in the new system prompt (exact strings in Task 6).
- No new dependencies. No changes to ledger, perception, Resolve, or the offline heuristic fallback.
- `LLMGateway.Config.live?/0` is THE one definition of "live": `Application.get_env(:llm_gateway, :routing)` has `:deliberate` **and** `:interpret` entries whose `adapter` is not `LLMGateway.Adapters.Scripted`.
- `home_live_test.exs` flips to `async: false` (it mutates global `Application` env). `spectate_live_test.exs` is already `async: false`.
- Commit after every task; commit messages given in each task.

---

### Task 1: `LLMGateway.Config` — single-source routing builder

**Files:**
- Create: `shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex`
- Test: `shards_engine/apps/llm_gateway/test/config_test.exs`

**Interfaces:**
- Consumes: nothing (reads `System.get_env`, `Application.get_env/put_env`).
- Produces (all later tasks rely on these exact names):
  - `routing_from_env/0` → `%{keys: map(), routing: map()}` (both empty maps when no usable key)
  - `apply_env_routing/0` → `:ok` (fills app env, never clobbers when no key)
  - `live?/0` → `boolean()`
  - `model/0` → `String.t() | nil`

- [ ] **Step 1: Write the failing test**

Create `shards_engine/apps/llm_gateway/test/config_test.exs`:

```elixir
defmodule LLMGateway.ConfigTest do
  @moduledoc "Env → routing activation (spec 2026-08-30): one builder, one live? definition."
  use ExUnit.Case, async: false

  alias LLMGateway.Config

  @env_vars ["ANTHROPIC_API_KEY", "ANTHROPIC_MODEL", "ANTHROPIC_ENDPOINT", "ANTHROPIC_TIMEOUT"]

  setup do
    Enum.each(@env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(@env_vars, &System.delete_env/1)
      Application.delete_env(:llm_gateway, :routing)
      Application.delete_env(:llm_gateway, :keys)
    end)

    :ok
  end

  test "routing_from_env builds live routing for all five classes when a key is present" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    System.put_env("ANTHROPIC_MODEL", "test-model")

    %{keys: keys, routing: routing} = Config.routing_from_env()

    assert keys == %{anthropic_main: "sk-test"}

    assert MapSet.new(Map.keys(routing)) ==
             MapSet.new([:deliberate, :adopt, :interpret, :narrate, :summarize])

    Enum.each(routing, fn {_class, cfg} ->
      assert cfg.adapter == LLMGateway.Adapters.Anthropic
      assert cfg.model == "test-model"
      assert cfg.key_ref == :anthropic_main
      assert cfg.timeout == 10_000
      assert cfg.temperature == 0.2
      assert cfg.max_tokens == 1024
    end)
  end

  test "routing_from_env is empty without a key (nil or blank)" do
    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
    System.put_env("ANTHROPIC_API_KEY", "")
    assert %{keys: %{}, routing: %{}} = Config.routing_from_env()
  end

  test "routing_from_env honors ANTHROPIC_TIMEOUT and ANTHROPIC_ENDPOINT" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    System.put_env("ANTHROPIC_TIMEOUT", "5000")
    System.put_env("ANTHROPIC_ENDPOINT", "https://proxy.example/v1/messages")

    %{routing: %{deliberate: cfg}} = Config.routing_from_env()

    assert cfg.timeout == 5000
    assert cfg.endpoint == "https://proxy.example/v1/messages"
  end

  test "live? is true only when deliberate and interpret are non-Scripted" do
    live_cfg = %{adapter: LLMGateway.Adapters.Anthropic, model: "m"}

    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg, interpret: live_cfg})
    assert Config.live?()

    scripted = %{adapter: LLMGateway.Adapters.Scripted, scripts: %{}}
    Application.put_env(:llm_gateway, :routing, %{deliberate: scripted, interpret: scripted})
    refute Config.live?()

    Application.put_env(:llm_gateway, :routing, %{deliberate: live_cfg})
    refute Config.live?()

    Application.delete_env(:llm_gateway, :routing)
    refute Config.live?()
  end

  test "apply_env_routing fills app env when a key is present and is a no-op without" do
    System.put_env("ANTHROPIC_API_KEY", "sk-test")
    assert :ok = Config.apply_env_routing()

    assert %{deliberate: %{adapter: LLMGateway.Adapters.Anthropic}} =
             Application.get_env(:llm_gateway, :routing)

    assert %{anthropic_main: "sk-test"} = Application.get_env(:llm_gateway, :keys)
  end

  test "model returns the deliberate model, nil offline" do
    Application.put_env(:llm_gateway, :routing, %{deliberate: %{model: "stub-1"}})
    assert Config.model() == "stub-1"

    Application.delete_env(:llm_gateway, :routing)
    assert Config.model() == nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shards_engine/apps/llm_gateway && mix test test/config_test.exs`
Expected: FAIL — `LLMGateway.Config` module not defined (compile error).

- [ ] **Step 3: Write the implementation**

Create `shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex`:

```elixir
defmodule LLMGateway.Config do
  @moduledoc """
  Single source of LLM routing activation from the environment (spec
  2026-08-30, decision 69). `config/runtime.exs` boot and the web server's
  re-apply both call `routing_from_env/0`/`apply_env_routing/0`, so the two
  can never drift. `live?/0` is THE definition of "live" — the lobby gate
  and the GM badge both read it.
  """

  @default_model "claude-haiku-4-5-20251001"
  @default_endpoint "https://api.anthropic.com/v1/messages"
  @default_timeout 10_000
  @classes [:deliberate, :adopt, :interpret, :narrate, :summarize]

  @doc "Live Anthropic routing for all five classes, or empty maps when no key."
  @spec routing_from_env() :: %{keys: map(), routing: map()}
  def routing_from_env do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" ->
        cfg = %{
          adapter: LLMGateway.Adapters.Anthropic,
          model: System.get_env("ANTHROPIC_MODEL", @default_model),
          endpoint: System.get_env("ANTHROPIC_ENDPOINT", @default_endpoint),
          key_ref: :anthropic_main,
          temperature: 0.2,
          max_tokens: 1024,
          timeout: timeout_from_env()
        }

        %{keys: %{anthropic_main: key}, routing: Map.new(@classes, &{&1, cfg})}

      _ ->
        %{keys: %{}, routing: %{}}
    end
  end

  @doc "Merge env routing into Application env. Only fills; a no-op without a key."
  @spec apply_env_routing() :: :ok
  def apply_env_routing do
    %{keys: keys, routing: routing} = routing_from_env()

    if map_size(keys) != 0 do
      Application.put_env(:llm_gateway, :keys, keys)
      Application.put_env(:llm_gateway, :routing, routing)
    end

    :ok
  end

  @doc """
    The one definition of "live": deliberate AND interpret are configured
    with an adapter that is not the offline Scripted adapter.
  """
  @spec live?() :: boolean()
  def live? do
    routing = Application.get_env(:llm_gateway, :routing, %{})

    Enum.all?([:deliberate, :interpret], fn class ->
      case routing[class] do
        %{adapter: LLMGateway.Adapters.Scripted} -> false
        %{adapter: a} when is_atom(a) -> true
        _ -> false
      end
    end)
  end

  @doc "Model name for display (badge, lobby hint); nil when offline."
  @spec model() :: String.t() | nil
  def model do
    case Application.get_env(:llm_gateway, :routing, %{})[:deliberate] do
      %{model: m} -> m
      _ -> nil
    end
  end

  defp timeout_from_env do
    case System.get_env("ANTHROPIC_TIMEOUT") do
      nil -> @default_timeout
      val -> String.to_integer(val)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shards_engine/apps/llm_gateway && mix test test/config_test.exs`
Expected: PASS (all 6 tests).

Run the rest of the app suite for collateral: `cd shards_engine/apps/llm_gateway && mix test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex shards_engine/apps/llm_gateway/test/config_test.exs
git commit -m "feat(gateway): single-source env routing builder (LLMGateway.Config)"
```

---

### Task 2: `runtime.exs` delegates to `LLMGateway.Config`

**Files:**
- Modify: `shards_engine/config/runtime.exs:1-35` (the `if config_env() != :test do ... end` block)

**Interfaces:**
- Consumes: `LLMGateway.Config.routing_from_env/0` (Task 1).
- Produces: identical Application env shape as before (`:llm_gateway` `:keys` + `:routing`, set only when a key is present).

- [ ] **Step 1: Replace the env block**

Replace lines 1–35 of `shards_engine/config/runtime.exs` (everything through the first `end` closing the `config_env() != :test` block) with:

```elixir
import Config

# Live LLM routing activates from the environment (decision 69); the logic
# lives in LLMGateway.Config so boot and web_server re-apply cannot drift
# (spec 2026-08-30 §4.1).
if config_env() != :test do
  %{keys: keys, routing: routing} = LLMGateway.Config.routing_from_env()

  if map_size(keys) != 0 do
    config :llm_gateway, keys: keys
    config :llm_gateway, routing: routing
  end
end
```

Keep lines 36–41 (the `wire` prod-server block) untouched.

- [ ] **Step 2: Verify both branches resolve identically to the old logic**

Without a key (must stay offline):
```bash
cd shards_engine && env -u ANTHROPIC_API_KEY MIX_ENV=dev mix run -e 'IO.inspect(Application.get_env(:llm_gateway, :routing))'
```
Expected output: `nil`

With a key (must go live):
```bash
cd shards_engine && ANTHROPIC_API_KEY=sk-fake MIX_ENV=dev mix run -e 'IO.inspect(Application.get_env(:llm_gateway, :routing))'
```
Expected: a map with keys `[:deliberate, :adopt, :interpret, :narrate, :summarize]`, each `%{adapter: LLMGateway.Adapters.Anthropic, model: "claude-haiku-4-5-20251001", ...}`.

- [ ] **Step 3: Run the referee suite (the consumer of this config)**

Run: `cd shards_engine/apps/referee && mix test`
Expected: PASS (155 tests) — sessions resolve routing lazily per run; test env never enters this block.

- [ ] **Step 4: Commit**

```bash
git add shards_engine/config/runtime.exs
git commit -m "refactor(gateway): runtime.exs delegates env routing to LLMGateway.Config"
```

---

### Task 3: `.env` activation in the web server script

**Files:**
- Modify: `shards_engine/scripts/web_server.exs` (insert after line 8 `port = ...`; extend the `IO.puts` block at lines 25–30; append two private helpers at file end)

**Interfaces:**
- Consumes: `LLMGateway.Config.{apply_env_routing/0, live?/0, model/0}` (Task 1).
- Produces: server process env sourced from `shards_engine/.env` (per-var: explicit shell env wins), routing applied before any session can be created, one log line.

- [ ] **Step 1: Insert env sourcing after the `port =` line (line 8)**

Insert immediately after line 8 (`port = String.to_integer(System.get_env("PORT", "4000"))`):

```elixir
# LLM activation (spec 2026-08-30 §4.2): source shards_engine/.env (per-var,
# explicit shell env wins), then apply live routing — Run.new reads
# Application config lazily per run creation, so sessions created after this
# point go live with no server restart.
source_env_file(Path.expand(".env", __DIR__))
LLMGateway.Config.apply_env_routing()

routing_state =
  if LLMGateway.Config.live?() do
    "live (#{LLMGateway.Config.model()})"
  else
    "offline (set ANTHROPIC_API_KEY)"
  end
```

- [ ] **Step 2: Add the routing line to the boot banner**

Replace the `IO.puts("""` block (lines 25–30) with:

```elixir
IO.puts("""
[web_server] llm routing: #{routing_state}
[web_server] serving http://0.0.0.0:#{port}
[web_server] home (referee console):  /
[web_server] run seat:                /runs/<run_id>?pc=<pc_id>
[web_server] GM console:              /runs/<run_id>/gm
""")
```

- [ ] **Step 3: Append the `.env` parser helpers at file end**

Append after the final `:timer.sleep(:infinity)` line:

```elixir
# Plain KEY=VALUE lines (optional `export ` prefix — this repo's .env uses
# `export KEY=...`), `#` comments; outer matching quotes are stripped.
# A variable already present in the environment is never overwritten.
defp source_env_file(path) do
  if File.exists?(path) do
    path
    |> File.read!()
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.each(&put_env_line/1)
  end

  :ok
end

defp put_env_line(line) do
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
            System.put_env(key, strip_quotes(String.trim(value)))
          end

          :ok

        _ ->
          :ok
      end
  end
end

defp strip_quotes(<<q::utf8, rest::binary>>) when q in [?", ?'] do
  size = byte_size(rest)

  if size >= 1 and :binary.part(rest, size - 1, 1) == <<q>> do
    :binary.part(rest, 0, size - 1)
  else
    rest
  end
end

defp strip_quotes(value), do: value
```

- [ ] **Step 4: Verify the offline branch (shell wins over `.env`)**

`shards_engine/.env` exists and carries a real `ANTHROPIC_API_KEY`. Force the shell value to empty to prove precedence:

```bash
cd shards_engine && ANTHROPIC_API_KEY= MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Run in background; wait for the banner. Expected first banner line: `[web_server] llm routing: offline (set ANTHROPIC_API_KEY)`. Then stop the process.

- [ ] **Step 5: Verify the live branch (`.env` key activates routing)**

```bash
cd shards_engine && env -u ANTHROPIC_API_KEY MIX_ENV=dev mix run --no-halt scripts/web_server.exs
```

Run in background; wait for the banner. Expected first banner line: `[web_server] llm routing: live (claude-haiku-4-5-20251001)` (or whatever `ANTHROPIC_MODEL` the `.env` sets). Then stop the process.

- [ ] **Step 6: Commit**

```bash
git add shards_engine/scripts/web_server.exs
git commit -m "feat(web): source .env and activate live routing at web server boot"
```

---

### Task 4: Lobby hard requirement (`ClientWeb.HomeLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/test_support.ex` (append stub adapter module at file end)
- Modify: `shards_engine/apps/client_web/lib/client_web/home_live.ex:48-52` (with-chain), `:54-72` (else branches), alias block at top
- Test: `shards_engine/apps/client_web/test/home_live_test.exs`

**Interfaces:**
- Consumes: `LLMGateway.Config.live?/0` (Task 1).
- Produces: `ClientWeb.TestSupport.StubAdapter` — a non-Scripted adapter module other test files (Task 5) reuse for live-shaped routing; lobby refuses run creation while `live?/0` is false.

- [ ] **Step 1: Add the shared stub adapter**

Append at the end of `shards_engine/apps/client_web/lib/client_web/test_support.ex`:

```elixir
defmodule ClientWeb.TestSupport.StubAdapter do
  @moduledoc """
  Non-Scripted adapter stand-in: enough for `LLMGateway.Config.live?/0` to
  see live-shaped routing in tests. Never called — tests that configure it
  never drive an LLM round.
  """

  def complete(_request, _cfg), do: {:error, :stub, %LLMGateway.Audit{}, nil}
end
```

- [ ] **Step 2: Write the failing tests**

In `shards_engine/apps/client_web/test/home_live_test.exs`:

(a) Flip async and add the live-routing setup. Replace line 6 (`use ClientWeb.ConnCase, async: true`) with:

```elixir
  # async: false — the gate reads global Application env; setup below
  # installs live-shaped routing and restoring it must not race siblings.
  use ClientWeb.ConnCase, async: false
```

And add a setup block after the `@pcs` definition (after line 22):

```elixir
  setup do
    old_routing = Application.get_env(:llm_gateway, :routing)
    old_keys = Application.get_env(:llm_gateway, :keys)

    stub = %{adapter: ClientWeb.TestSupport.StubAdapter, model: "stub-1"}

    Application.put_env(:llm_gateway, :keys, %{anthropic_main: "stub-key"})
    Application.put_env(:llm_gateway, :routing, %{
      deliberate: stub,
      adopt: stub,
      interpret: stub,
      narrate: stub,
      summarize: stub
    })

    on_exit(fn ->
      if old_routing,
        do: Application.put_env(:llm_gateway, :routing, old_routing),
        else: Application.delete_env(:llm_gateway, :routing)

      if old_keys,
        do: Application.put_env(:llm_gateway, :keys, old_keys),
        else: Application.delete_env(:llm_gateway, :keys)
    end)

    :ok
  end
```

(b) Add the two gate tests before the final `end` of the module:

```elixir
  test "GM launch is refused while LLM routing is offline", %{conn: conn} do
    Application.delete_env(:llm_gateway, :routing)
    slug = "web-offline_#{:erlang.unique_integer([:positive])}"

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#gm_launch", run: %{run_id: slug, seed: "42", yaml: @yaml})
      |> render_submit()

    assert html =~ "LLM routing is offline"
    assert html =~ "ANTHROPIC_API_KEY"
    refute match?(%{status: :running}, Session.state(slug))
  end

  test "GM launch passes when routing is live-shaped and the session runs", %{conn: conn} do
    slug = "web-live_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> ClientWeb.TestSupport.stop_run(slug) end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#gm_launch", run: %{run_id: slug, seed: "42", yaml: @yaml})
    |> render_submit()

    assert_redirect(view, "/runs/#{slug}/gm")
    assert %{status: :running} = Session.state(slug)
  end
```

- [ ] **Step 3: Run tests to verify the offline test fails**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: FAIL — `test "GM launch is refused while LLM routing is offline"` starts the run (no gate yet), so `html` lacks the flash and the run is `:running`. All other tests PASS (setup installs live-shaped routing; note the previously-passing launch tests now depend on that setup — that is the spec §4.3 test-injection requirement).

- [ ] **Step 4: Implement the gate**

In `shards_engine/apps/client_web/lib/client_web/home_live.ex`:

(a) Add `alias LLMGateway.Config` to the module's alias list at the top (next to `alias Referee.Run.Session`).

(b) Replace lines 48–52 (the `with` chain head):

```elixir
    with {:run_id, true} <- {:run_id, run_id != ""},
         {:seed, {:ok, seed}} <- {:seed, seed_result},
         {:yaml, true} <- {:yaml, File.exists?(yaml)},
         {:roster, true} <- {:roster, pcs != :error},
         {:live, true} <- {:live, Config.live?()},
         {:start, {:ok, _pid}} <- {:start, Session.start_link(run_id, yaml, seed, pcs)} do
```

(c) Insert the refusal branch in the `else` after the `{:roster, false}` branch (after line 65):

```elixir
      {:live, false} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "LLM routing is offline. Set ANTHROPIC_API_KEY (see shards_engine/.env) and restart the server to enable live NPC brains."
         )}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: PASS (all 6 tests: 4 existing + 2 new).

- [ ] **Step 6: Run the full client_web suite**

Run: `cd shards_engine/apps/client_web && mix test`
Expected: PASS — `run_live_test` and `spectate_live_test` create sessions while HomeLive's live-shaped routing may be installed in app env; that is behaviorally harmless because neither file drives an LLM round, and HomeLive is now `async: false` so its own gate tests never race each other.

- [ ] **Step 7: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/home_live.ex shards_engine/apps/client_web/lib/client_web/test_support.ex shards_engine/apps/client_web/test/home_live_test.exs
git commit -m "feat(web): lobby refuses to create runs while LLM routing is offline"
```

---

### Task 5: GM console LIVE/OFFLINE badge (`ClientWeb.SpectateLive`)

**Files:**
- Modify: `shards_engine/apps/client_web/lib/client_web/spectate_live.ex` (mount assigns at lines 36–55; template header at line 243; alias block at top)
- Test: `shards_engine/apps/client_web/test/spectate_live_test.exs`

**Interfaces:**
- Consumes: `LLMGateway.Config.{live?/0, model/0}` (Task 1); `ClientWeb.TestSupport.StubAdapter` (Task 4).
- Produces: assigns `live: boolean()` and `model: String.t() | nil`; header badge `data-testid="llm-badge"` rendering `LIVE · <model>` or `OFFLINE`. Describes what the *next* run gets — same source as the lobby gate.

- [ ] **Step 1: Write the failing tests**

In `shards_engine/apps/client_web/test/spectate_live_test.exs`, add before the final `end` of the module:

```elixir
  test "renders OFFLINE badge when server routing is offline", %{conn: conn, run_id: id} do
    old_routing = Application.get_env(:llm_gateway, :routing)
    Application.delete_env(:llm_gateway, :routing)

    on_exit(fn ->
      if old_routing,
        do: Application.put_env(:llm_gateway, :routing, old_routing),
        else: Application.delete_env(:llm_gateway, :routing)
    end)

    {:ok, _view, html} = live(conn, "/runs/#{id}/gm")
    assert html =~ ~s(data-testid="llm-badge")
    assert html =~ "OFFLINE"
  end

  test "renders LIVE badge with model when server routing is live", %{conn: conn, run_id: id} do
    old_routing = Application.get_env(:llm_gateway, :routing)
    stub = %{adapter: ClientWeb.TestSupport.StubAdapter, model: "stub-1"}

    Application.put_env(:llm_gateway, :routing, %{deliberate: stub, interpret: stub})

    on_exit(fn ->
      if old_routing,
        do: Application.put_env(:llm_gateway, :routing, old_routing),
        else: Application.delete_env(:llm_gateway, :routing)
    end)

    {:ok, _view, html} = live(conn, "/runs/#{id}/gm")
    assert html =~ ~s(data-testid="llm-badge")
    assert html =~ "LIVE · stub-1"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: FAIL — both new tests, on `data-testid="llm-badge"` absent (mount assigns no `live`/`model` yet; the template would also crash on the missing assigns, which is the same failure).

- [ ] **Step 3: Implement**

In `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`:

(a) Add `alias LLMGateway.Config` to the alias list (next to `alias Referee.Run.Session`).

(b) In `mount/3`, extend the `assign` list (inside the `assign(socket, run_id: run_id, ...)` call, after `ooc_log: []` at line 54):

```elixir
        gm_chat_draft: "",
        ooc_log: [],
        live: Config.live?(),
        model: Config.model()
```

(c) In the template, insert the badge directly after line 243 (`<h1>GM console — run <%= @run_id %></h1>`):

```html
    <p class="llm-badge" data-testid="llm-badge">
      <%= if @live do %>LIVE · <%= @model %><% else %>OFFLINE<% end %>
    </p>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: PASS (all tests, including the two new badge tests and the existing snapshot/ribbon tests).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/client_web/lib/client_web/spectate_live.ex shards_engine/apps/client_web/test/spectate_live_test.exs
git commit -m "feat(web): GM console shows persistent LIVE/OFFLINE routing badge"
```

---

### Task 6: Organic deliberation prompt (`Agents.Prompt.deliberate/1`)

**Files:**
- Modify: `shards_engine/apps/agents/lib/agents/prompt.ex` — replace `deliberate/1` (lines 9–56), replace `speech_block/1` (lines 60–73), add `people_block/1` + `the_moment_block/1`; leave `adopt/1` and dossier helpers untouched
- Test: `shards_engine/apps/agents/test/deliberate_test.exs` (append new contract tests)

**Interfaces:**
- Consumes: slice shape — `agent: %{id, name}`, `place: %{name, exits}`, `dossier` (string- or atom-keyed `role, personality, goals, knowledge, rumors`), `believed: [id]`, `believed_agents: [%{id, name, pc, salience}]`, `salient: [id]`, `commitments`, `capabilities`, `recent_speech: [%{from_id, from_name, words, addressed, tick}]`, `summary`.
- Produces: same `{system, user, schema}` triple; existing `deliberate_test.exs` contracts stay green (labels `Commitments:`, `Salient here:`, `Role:`, `Personality:`, `Goals:`, `Knowledge / Rumors:`, `Summary:` retained; `Summary:` last).

- [ ] **Step 1: Write the failing contract tests**

Append before the final `end` of `shards_engine/apps/agents/test/deliberate_test.exs`:

```elixir
  test "prompt introduces perceived people by name with ids and marks PCs" do
    slice =
      slice("mara", %{
        agent: %{id: "mara", name: "Mara", place_id: "chiefs_room"},
        believed_agents: [
          %{id: "pc_thistle", name: "Thistle", pc: true, salience: 0.4},
          %{id: "npc_grevik", name: "Mayor Grevik", pc: false, salience: 0.2}
        ]
      })

    {_system, user, _schema} = Agents.Prompt.deliberate(slice)

    assert user =~ "Mara (mara) in Chief's Room"
    assert user =~ "Thistle (pc_thistle) — an adventurer here"
    assert user =~ "Mayor Grevik (npc_grevik) — someone here"
  end

  test "prompt renders addressed ask, hearsay overheard, and the moment" do
    slice =
      slice("mara", %{
        recent_speech: [
          %{from_id: "pc_bramble", from_name: "Bramble", words: "pass the ale", addressed: false, tick: 2},
          %{from_id: "pc_thistle", from_name: "Thistle", words: "how is your flock?", addressed: true, tick: 3}
        ]
      })

    {_system, user, _schema} = Agents.Prompt.deliberate(slice)

    assert user =~ ~s(Thistle says to YOU: "how is your flock?")
    assert user =~ "You overhear Bramble: \"pass the ale\" (hearsay"
    assert user =~ "secondhand, may be wrong"
    assert user =~ ~s(you were just asked, by Thistle: "how is your flock?")
  end

  test "system prompt carries the organic reply rules and decision-88 contract verbatim" do
    {system, _user, _schema} = Agents.Prompt.deliberate(slice("mara"))

    assert system =~
             ~s(If someone just addressed you: verb "shout", their id as target_id, message = your spoken reply, aimed at that person alone.)

    assert system =~
             "If nobody addressed you and no active commitment demands speaking: verb \"wait\". Do not volunteer speech unprompted."

    assert system =~ "first person"
    assert system =~ "1-4 sentences"
    assert system =~ "you may ask a question back"
    assert system =~ "Never invent world facts"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd shards_engine/apps/agents && mix test test/deliberate_test.exs`
Expected: FAIL — the three new tests (no `says to YOU:`, no `You overhear ... hearsay`, no `The moment:` block; system prompt lacks the new rules). All existing tests still PASS.

- [ ] **Step 3: Implement the rebuilt prompt**

In `shards_engine/apps/agents/lib/agents/prompt.ex`:

(a) Replace `deliberate/1` (lines 9–56) — keep the schema exactly as-is, replace system and user assembly:

```elixir
  def deliberate(slice) do
    schema = %{
      type: :object,
      properties: %{
        verb: %{type: :string},
        target_id: %{type: :string, nullable: true},
        direction: %{type: :string, nullable: true},
        message: %{type: :string, nullable: true},
        reason: %{type: :string}
      },
      required: [:verb, :reason]
    }

    system = """
    You are the brain of #{slice.agent.name} (#{slice.agent.id}), a character in a
    tabletop RPG world. You act ONLY on your beliefs, never on hidden truth.
    Choose exactly one action for this moment. Respond ONLY with a JSON object:
    {"verb": string, "target_id": string | null, "direction": string | null,
    "message": string | null, "reason": string}.
    verb must be one of your capabilities. target_id must come from your believed
    list — never invent one. Ordering a subordinate uses verb "order", the
    subordinate's id as target_id, and the spoken order as message.
    Reply rules:
    - Answer the actual question you were asked, in first person, in your own
      voice; 1-4 sentences; you may ask a question back.
    - Speak only from your persona, what you have perceived, and general
      common-sense life experience of your station. Never invent world facts
      (names, places, magic) beyond them.
    - If someone just addressed you: verb "shout", their id as target_id, message = your spoken reply, aimed at that person alone.
    - If nobody addressed you and no active commitment demands speaking: verb "wait". Do not volunteer speech unprompted.
    """

    dossier = format_dossier(slice[:dossier])
    speech = speech_block(slice)
    the_moment = the_moment_block(Map.get(slice, :recent_speech, []))

    user =
      [
        "You are #{slice.agent.name} (#{slice.agent.id}) in #{slice.place.name}.",
        dossier,
        people_block(Map.get(slice, :believed_agents, [])),
        speech,
        the_moment,
        "Commitments: #{commitment_lines(slice.commitments)}",
        "Salient here: #{Enum.join(slice.salient, ", ")}",
        "Believed here: #{Enum.join(slice.believed, ", ")}",
        "Exits: #{Enum.join(slice.place.exits, ", ")}",
        "Capabilities: #{Enum.join(slice.capabilities, ", ")}",
        "",
        "Summary: #{slice.summary}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    {system, user, schema}
  end
```

(b) Replace `speech_block/1` (lines 60–73):

```elixir
  # What has been said in earshot. Addressed lines are first-class and name
  # the speaker; overheard lines are explicitly hearsay the brain may doubt.
  defp speech_block(slice) do
    case Map.get(slice, :recent_speech, []) do
      [] ->
        nil

      lines ->
        "Recent speech:\n" <>
          Enum.map_join(lines, "\n", fn l ->
            if l[:addressed] do
              ~s(  #{l[:from_name]} says to YOU: "#{l[:words]}")
            else
              ~s(  You overhear #{l[:from_name]}: "#{l[:words]}" (hearsay — secondhand, may be wrong))
            end
          end)
    end
  end

  # Names make the conversation personal; ids keep target_id legal. PCs are
  # labelled adventurers; beliefs carry no role for other agents.
  defp people_block([]), do: nil

  defp people_block(agents) do
    "People you can perceive:\n" <>
      Enum.map_join(agents, "\n", fn a ->
        role = if a[:pc], do: "an adventurer here", else: "someone here"
        "  #{a[:name]} (#{a[:id]}) — #{role}"
      end)
  end

  # The last person to address the brain drives answer-the-question instead
  # of topic rotation.
  defp the_moment_block(recent_speech) do
    case Enum.find(Enum.reverse(recent_speech), & &1[:addressed]) do
      nil ->
        nil

      line ->
        ~s(The moment: you were just asked, by #{line[:from_name]}: "#{line[:words]}")
    end
  end
```

Note: the two decision-88 rule lines are deliberately single (long) lines in the heredoc — the contract test matches them as continuous substrings.

- [ ] **Step 4: Run the full agents suite**

Run: `cd shards_engine/apps/agents && mix test`
Expected: PASS — new tests green; existing contracts green (`prompt shape` test still finds `Commitments:`/`Salient here:` before `Summary:`; dossier tests unchanged; heuristic no-route tests don't touch the prompt).

- [ ] **Step 5: Commit**

```bash
git add shards_engine/apps/agents/lib/agents/prompt.ex shards_engine/apps/agents/test/deliberate_test.exs
git commit -m "feat(agents): organic-derivation deliberation prompt (persona, named listeners, answer-the-question)"
```

---

### Task 7: Full umbrella suite

**Files:** none (verification only)

- [ ] **Step 1: Run everything**

Run: `cd shards_engine && mix test`
Expected: PASS across all apps (engine_core, referee, wire, client_tui, client_web, llm_gateway, agents) — decision-88 directed-speech suites unaffected.

- [ ] **Step 2: Format check**

Run: `cd shards_engine && mix format --check-formatted`
Expected: clean; run `mix format` first if the executor touched files without formatting.

---

### Task 8: Live-API inn smoke (spec §5.6 — human-reviewed)

**Files:**
- Create: `shards_engine/scripts/inn_smoke.exs` (committed — `scripts/` precedent: `protocol_smoke.exs`)

**Interfaces:**
- Consumes: `LLMGateway.Config.{apply_env_routing/0, live?/0}` (Task 1); `Referee.Run.Session.{start_link/5, declare/3, advance/2, stop/1}` — `advance/2` returns `{:ok, texts}` where `texts` is `%{pc_id => String.t()}` (referee/test/session_test.exs:195).
- Produces: printed transcript + mechanical checks; exit code 0 on pass.

- [ ] **Step 1: Write the smoke script**

Create `shards_engine/scripts/inn_smoke.exs`:

```elixir
# Live-API inn smoke (spec docs/superpowers/specs/2026-08-30-live-conversational-npc-web-design.md §5.6).
# Run from shards_engine/ with ANTHROPIC_API_KEY exported (or present in .env
# already sourced into your shell):
#   MIX_ENV=dev mix run scripts/inn_smoke.exs
#
# Boots one session on the real ruined_tower.yaml with live routing, has
# Thistle ask Erik about his sheep while Bramble only listens, then prints
# each PC's text and runs mechanical checks: Erik answers Thistle, the reply
# is private, no unaddressed NPC speaks, and no verbatim YAML knowledge line
# comes back as the reply.

LLMGateway.Config.apply_env_routing()

unless LLMGateway.Config.live?() do
  IO.puts("[inn_smoke] live routing unavailable — export ANTHROPIC_API_KEY and retry")
  System.halt(1)
end

run_id = "smoke_#{System.unique_integer([:positive])}"
yaml = Path.expand("../the-ruined-tower/ruined_tower.yaml", __DIR__)

pcs = [
  %{id: "pc_thistle", name: "Thistle", place_id: "maras_inn",
    int: 13, hd: 1, hp: 12, ac: 5, thac0: 20, damage: "1d8"},
  %{id: "pc_bramble", name: "Bramble", place_id: "maras_inn",
    int: 12, hd: 1, hp: 8, ac: 6, thac0: 19, damage: "1d6"}
]

{:ok, _pid} = Referee.Run.Session.start_link(run_id, yaml, 42, pcs)

{:ok, %{reply: _}} =
  Referee.Run.Session.declare(run_id, "pc_thistle", "Erik, what happened to your sheep?")

IO.puts("[inn_smoke] live round: interpret + NPC deliberations + narrate (be patient)...")

# Long timeout: several billed Haiku calls run sequentially (spec §6 cadence risk).
{:ok, texts} = Referee.Run.Session.advance(run_id, 300_000)

IO.puts("\n=== pc_thistle (asked) ===\n#{texts["pc_thistle"]}")
IO.puts("\n=== pc_bramble (listened) ===\n#{texts["pc_bramble"] || "(nothing)"}")

both = (texts["pc_thistle"] || "") <> " " <> (texts["pc_bramble"] || "")

failures =
  []
  |> Kernel.++(
    if texts["pc_thistle"] =~ "Erik the Shepherd says to you",
      do: [],
      else: ["Erik never replied to Thistle"]
  )
  |> Kernel.++(
    if texts["pc_bramble"] && texts["pc_bramble"] =~ "says to you",
      do: ["Erik's reply leaked to the listener"],
      else: []
  )
  |> Kernel.++(
    if Regex.match?(~r/(Mara|Mayor Grevik|Anna Mordale) says to you/, both),
      do: ["an unaddressed NPC volunteered speech"],
      else: []
  )
  |> Kernel.++(
    if Enum.any?(
         [
           "Green-skinned creatures carried off three sheep two nights ago.",
           "They headed toward the ruined tower on the hill.",
           "Strange green lights have flickered from the tower for two weeks."
         ],
         &String.contains?(both, &1)
       ),
      do: ["verbatim YAML knowledge/rumor line surfaced as a reply"],
      else: []
  )

IO.puts(
  "\nmechanical checks: #{if failures == [], do: "PASS", else: "FAIL — #{inspect(failures)}"}"
)

Referee.Run.Session.stop(run_id)
System.halt(if(failures == [], do: 0, else: 1))
```

- [ ] **Step 2: Run the smoke against the real API**

```bash
cd shards_engine && MIX_ENV=dev mix run scripts/inn_smoke.exs
```

Expected: exit 0, `mechanical checks: PASS`, and — human judgment, per spec §5.6 — Erik's reply is first-person with personal stakes (his flock, fear for winter, etc.), addressed to Thistle alone, no parroted line. If Erik's stakes are too thin, that is the spec §6 "Dossier coverage" risk surfacing: stop and report — do NOT author speech into the YAML (explicit non-goal).

- [ ] **Step 3: Record and commit the script**

Commit the script (not the output): 

```bash
git add shards_engine/scripts/inn_smoke.exs
git commit -m "test(scripts): live-API inn smoke for organic NPC conversation"
```

---

### Task 9: Engrams session end + export

**Files:** none (project memory)

- [ ] **Step 1: Log the decision**

```bash
engrams decision log --summary "Live conversational NPCs in web play: one Config source for env routing activation (Config.routing_from_env/apply_env_routing/live?), lobby hard-requirement gate, GM LIVE/OFFLINE badge, organic-derivation deliberation prompt" --rationale "Web runs booted offline because nothing sourced .env; lobby silently created offline runs whose brains parrot YAML rumor lines. Run.new already falls back to Application config per run (run.ex:40), so activation is Application-env timing, not plumbing. live?/0 is the single live definition shared by gate and badge. Prompt rebuild derives persona/listeners/question from the slice alone (user rejected YAML speech authoring); decision-88 rules verbatim; offline heuristic untouched." --tags engine,web,llm,agents --anchor shards_engine/apps/llm_gateway/lib/llm_gateway/config.ex --importance 8
```

If the near-duplicate gate fires on decision 88, resolve with `--supersedes <id>` only if truly replacing — expected relation is `implements` decision 88 / `refines` decision 69; use `--force` then `engrams link add` to record the real relations.

- [ ] **Step 2: Link and close out** (use the id from Step 1's output for `<new-id>`)

```bash
engrams link add --source-type decision --source-id <new-id> --target-type decision --target-id 88 --rel implements
engrams link add --source-type decision --source-id <new-id> --target-type decision --target-id 69 --rel refines
engrams progress log --status Done --description "Live conversational NPCs: env routing activation, lobby gate, GM badge, organic prompt; full suite green; live inn smoke reviewed"
engrams active-context update --patch '{"current_focus":"Live organic NPC conversation verified in web smoke; next: run The Ruined Tower session with real players","current_plan":"Next: play through ruined tower; watch cadence LLM cost (spec 2026-08-30 §6) and declare latency before tuning"}'
engrams export
```

- [ ] **Step 3: Commit the export**

```bash
git add engrams_export
git commit -m "chore(engrams): log live-conversational-NPC decision, progress, export"
```

(Push only when the user asks.)
