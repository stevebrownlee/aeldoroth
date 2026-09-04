# Task 4: Lobby hard-requirement gate (`ClientWeb.HomeLive`)

Implementer for plan `docs/superpowers/plans/2026-08-30-live-conversational-npc-web.md` Task 4. TDD strictly: write failing tests first, see them fail, implement, see them pass. Work in `/Users/chortlehoort/Campaigns/the-shattered-kingdoms`. Current HEAD: `bfaba97e`. Commit only the three named files.

Context: web runs booted offline whenever the server process lacked `ANTHROPIC_API_KEY`, silently degrading NPC brains to canned rumor lines (spec 2026-08-30 §4.3 — user hard requirement: live mode). Task 1 shipped `LLMGateway.Config` (`live?/0`, `model/0` — reads `Application.get_env(:llm_gateway, :routing)`). You add the lobby gate plus a shared stub adapter.

## Step 1 — Add the shared stub adapter

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

Check the struct shape against the real `LLMGateway.Audit` first; adapt field-for-field if it does not build empty (keep the 4-tuple contract).

## Step 2 — Failing tests in `shards_engine/apps/client_web/test/home_live_test.exs`

(a) Replace `use ClientWeb.ConnCase, async: true` (line 6) with:

```elixir
  # async: false — the gate reads global Application env; setup below
  # installs live-shaped routing and restoring it must not race siblings.
  use ClientWeb.ConnCase, async: false
```

(b) Add after the `@pcs` definition (after line 22):

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

(c) Before the module's final `end`:

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

Adapt selector/form details to the actual HomeLive template if the brief's assumed names differ (read the file first); intent is non-negotiable: offline → flash + no session; live-shaped → redirect + session running.

## Step 3 — RED

`cd shards_engine/apps/client_web && mix test test/home_live_test.exs`
Expected: the offline-refusal test FAILS (run starts today). Others pass.

## Step 4 — Implement the gate in `shards_engine/apps/client_web/lib/client_web/home_live.ex`

(a) `alias LLMGateway.Config` next to `alias Referee.Run.Session`.

(b) In `handle_event`'s launch `with` chain, add after the `{:roster, ...}` step and before `{:start, ...}`:

```elixir
         {:live, true} <- {:live, Config.live?()},
```

(c) In the `else`, after the `{:roster, false}` branch:

```elixir
      {:live, false} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "LLM routing is offline. Set ANTHROPIC_API_KEY (see shards_engine/.env) and restart the server to enable live NPC brains."
         )}
```

## Step 5–6 — GREEN + suite

`mix test test/home_live_test.exs` → all pass. Then `mix test` (full client_web) → pass. Plan §Task 4 Step 6 says cross-file app-env bleed is behaviorally harmless; if it is NOT (a test fails), stop and report the failure — do not hack a fix.

## Step 7 — Commit

```bash
git add shards_engine/apps/client_web/lib/client_web/home_live.ex shards_engine/apps/client_web/lib/client_web/test_support.ex shards_engine/apps/client_web/test/home_live_test.exs
git commit -m "feat(web): lobby refuses to create runs while LLM routing is offline"
```

## Report

Write `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-4-report.md`: commit sha, deviations (with justification), test counts. Final reply: status (DONE / DONE_WITH_CONCERNS / FAILED), commit sha, test summary, concerns list, report path. Never commit `.env` or `engrams/` artifacts.
