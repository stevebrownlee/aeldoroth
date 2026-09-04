# Task 2 Report: `runtime.exs` delegates to `LLMGateway.Config`

**Status:** DONE_WITH_CONCERNS (one minor brief-expectation correction, see below)
**Commit:** `fa6ddce10505133fc18546844c1938ab4de323b5` — `refactor(gateway): runtime.exs delegates env routing to LLMGateway.Config` (1 file changed, +7/−29)

## Change

`shards_engine/config/runtime.exs` lines 1–35 replaced with the brief's exact transcription:

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

The `wire` prod-server block (formerly lines 36–41) is untouched. No other files modified.

## Verification (steps run in order)

**Step 2a — offline boot check** (`env -u ANTHROPIC_API_KEY MIX_ENV=dev mix run -e 'IO.inspect(Application.get_env(:llm_gateway, :routing))'`):
- Result: `%{}`
- Brief expected `nil`. **The brief's expectation was wrong on this point**: `shards_engine/config/config.exs:8` statically sets `config :llm_gateway, routing: %{}`, and both the old and the new runtime block write `:routing` only when a key is present. So offline the observable value was `%{}` before this change and remains `%{}` after — byte-identical behavior. The contract ("no `:routing` config written when offline") holds; nothing writes the key without an env key. Confirmed by inspection that no other code writes `:routing` outside tests (`grep` over the repo: only `config.exs` static default, Task 1 module, and test files).
- This boot check also proves `LLMGateway.Config` is loadable at runtime.exs eval time: the umbrella compiled `llm_gateway` first (output: `Compiling 1 file (.ex)`) and the call resolved with no `UndefinedFunctionError`.

**Step 2b — live boot check** (`ANTHROPIC_API_KEY=sk-fake MIX_ENV=dev mix run -e '...'`):
- Result: map with exactly the 5 classes `[:deliberate, :adopt, :interpret, :narrate, :summarize]`, each `%{adapter: LLMGateway.Adapters.Anthropic, model: "claude-haiku-4-5-20251001", endpoint: "https://api.anthropic.com/v1/messages", key_ref: :anthropic_main, temperature: 0.2, max_tokens: 1024, timeout: 10000}` — matches brief expectation.

**Step 3 — referee suite** (`cd shards_engine/apps/referee && mix test`):
- Result: `155 passed`, 0 failures — matches brief expectation.

**Step 4 — commit**: made with the brief's exact message; only `shards_engine/config/runtime.exs` staged.

## Concerns

1. Brief Step 2a's "Expected output: `nil`" does not match reality (`%{}`, due to the static `%{}` default in `config/config.exs:8`). Actual behavior is byte-identical to the pre-change code, so the change is correct; recommend the plan author fix the brief's expected output so a future re-run doesn't false-fail.
