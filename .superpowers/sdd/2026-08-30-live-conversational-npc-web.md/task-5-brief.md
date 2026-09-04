# Task 5: GM console LIVE/OFFLINE badge (`ClientWeb.SpectateLive`)

Implementer for plan `docs/superpowers/plans/2026-08-30-live-conversational-npc-web.md` Task 5. TDD strictly. Work in `/Users/chortlehoort/Campaigns/the-shattered-kingdoms`. Current HEAD: `0360202f` (Tasks 1–4 landed; `LLMGateway.Config.{live?/0, model/0}` and `ClientWeb.TestSupport.StubAdapter` exist). Commit only the two named files.

Purpose: the GM console must show what routing the *next* run gets — `LIVE · <model>` or `OFFLINE` — same source as the lobby gate (spec §4.4).

## Step 1 — Failing tests

Append before the final `end` of `shards_engine/apps/client_web/test/spectate_live_test.exs` (verify the existing setup provides `%{conn: conn, run_id: id}` — read the file first; if the fixture differs, adapt the test bodies' `id` sourcing, not the assertions):

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

Note: the second test installs partial routing (2 of 5 classes) — `Config.live?/0` must accept that (Task 1's contract). If it doesn't, STOP and report FAILED with the actual contract; do not widen the test.

## Step 2 — RED

`cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs`
Expected: both new tests FAIL (no `data-testid="llm-badge"` yet).

## Step 3 — Implement in `shards_engine/apps/client_web/lib/client_web/spectate_live.ex`

(a) `alias LLMGateway.Config` next to `alias Referee.Run.Session`.
(b) In `mount/3`'s assign list (after `ooc_log: []`):

```elixir
        live: Config.live?(),
        model: Config.model()
```

(c) In the template, directly after the `<h1>GM console — run <%= @run_id %></h1>` line:

```html
    <p class="llm-badge" data-testid="llm-badge">
      <%= if @live do %>LIVE · <%= @model %><% else %>OFFLINE<% end %>
    </p>
```

## Step 4 — GREEN

`cd shards_engine/apps/client_web && mix test test/spectate_live_test.exs` → all pass (badge tests + existing snapshot/ribbon tests).

## Step 5 — Commit

```bash
git add shards_engine/apps/client_web/lib/client_web/spectate_live.ex shards_engine/apps/client_web/test/spectate_live_test.exs
git commit -m "feat(web): GM console shows persistent LIVE/OFFLINE routing badge"
```

## Report

Write `.superpowers/sdd/2026-08-30-live-conversational-npc-web.md/task-5-report.md`: commit sha, deviations (justified), test counts. Final reply: status (DONE / DONE_WITH_CONCERNS / FAILED), commit sha, test summary, concerns, report path. Never commit `.env` or `engrams/` artifacts.
