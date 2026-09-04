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

