---
title: "Platform Marketplace Vision"
description: "Long-term business model for The Shattered Kingdoms platform: user-provided LLM keys, per-run sandbox isolation, upcharge billing, and the module marketplace roadmap."
order: 9
category: "Ecosystem"
tags: ["marketplace", "billing", "platform", "sandbox", "roadmap", "llm"]
---

# Platform Marketplace Vision

The Shattered Kingdoms is not only an Elixir engine and a set of adventure modules. It is intended to become a hosted platform where authors publish modules, game masters run sessions, and players participate from browsers or terminal clients. This chapter describes the economic and architectural shape of that platform: who pays for inference, how runs are isolated, how the platform captures value, and what comes after the initial release.

## Core economic thesis

The engine consumes frontier LLMs heavily: perception, deliberation, narration, summarization, and dossier generation each issue one or more LLM calls per tick. Hosting those calls centrally would be ruinously expensive and would tie the platform's margins to a single provider's token pricing.

The platform therefore adopts a **bring-your-own-key model**:

- The user supplies API credentials for the providers they want to use.
- The platform routes traffic through its `LLMGateway.Router` chokepoint but never pays the provider directly.
- The platform adds a transparent per-token upcharge for routing, schema validation, circuit breaking, and audit logging.
- The user sees the true inference cost plus platform fee per run.

This model decouples platform revenue from provider price wars while keeping the platform honest: if it offers no value beyond proxying, users will route around it.

## User-provided keys

Today the umbrella supports multiple adapters:

- `LLMGateway.Adapters.Scripted` — deterministic, local responses for tests.
- `LLMGateway.Adapters.Anthropic` — Anthropic Claude via HTTPS.
- `LLMGateway.Adapters.OpenAICompat` — any OpenAI-compatible endpoint.

Each class of call is routed independently:

```elixir
%LLMGateway.Ctx{
  routing: %{
    adopt:     %{adapter: LLMGateway.Adapters.Anthropic, model: "claude-sonnet-4-20250514", key_ref: :anthropic_key},
    deliberate:%{adapter: LLMGateway.Adapters.Anthropic, model: "claude-sonnet-4-20250514", key_ref: :anthropic_key},
    narrate:   %{adapter: LLMGateway.Adapters.OpenAICompat, model: "gpt-4.1-mini", key_ref: :openai_key},
    summarize: %{adapter: LLMGateway.Adapters.OpenAICompat, model: "gpt-4.1-mini", key_ref: :openai_key}
  },
  budget: %{cap: :inf, spent: 0},
  breaker: %{}
}
```

A key is referred to by an atom (`:anthropic_key`, `:openai_key`) rather than being stored in the config. In a hosted deployment those atoms resolve to secrets injected per user or per run, never checked into the repository.

## Routing and budget-aware degradation

`LLMGateway.Router.complete/2` is the only place an LLM call is made. It performs:

1. **Route lookup** by class.
2. **Budget gate** against the run's spend cap.
3. **Circuit breaker** check.
4. **Adapter invocation**.
5. **Bounded schema retry** once for transient parse failures.
6. **Audit record** appended to the ledger.

If the cap is exceeded, the gateway degrades gracefully. Narration drops first because a missing paragraph is survivable; interpretation may run at 2× cap because blocking player actions mid-combat is worse than a small overage.

```elixir
# Pseudo-formula for budget-aware degradation
remaining = cap - spent
if remaining <= 0 do
  if class == :narrate, do: {:degraded, :silence}
  if class == :interpret and spent <= 2 * cap, do: :allow
  else {:degraded, :refuse}
end
```

Every call produces an `LLMGateway.Audit` record that becomes a `:llm_call` ledger event:

```elixir
%{
  kind: :llm_call,
  class: :deliberate,
  agent_id: "grisk_the_snatcher",
  adapter: "Elixir.LLMGateway.Adapters.Anthropic",
  model: "claude-sonnet-4-20250514",
  tokens_in: 1842,
  tokens_out: 127,
  prompt_slice_ref: "prompts/grisk_12.json",
  parse_verdict: :ok,
  ok: true
}
```

## Per-run sandboxing

A platform run is isolated at multiple layers:

| Layer | Mechanism |
| ----- | --------- |
| Process | `EngineCore.RunSup` DynamicSupervisor spawns a dedicated writer and world server per `run_id`. |
| Registry | `EngineCore.RunReg` scopes every process name by `{kind, run_id}`. |
| Filesystem | Journals and snapshots live under `shards_engine/runs/<run_id>/`, gitignored and never shared between runs. |
| LLM context | Each run has its own `LLMGateway.Ctx` accumulator; keys are looked up per session, not globally. |

This isolation means a long-running campaign can be checkpointed, restored, or moved between hosts without leaking state into another run. It also means a malicious or buggy module cannot corrupt the global engine; its effects are confined to one `run_id`.

## Upcharge billing

The platform's revenue comes from a transparent gross margin on LLM inference. The ledger already captures every token spent. Billing is therefore a pure function over the journal:

```elixir
Referee.Spend.report(events)
# => %{
#   total: %{calls: 42, tokens_in: 38021, tokens_out: 4062},
#   by_class: %{deliberate: %{calls: 18, ...}, narrate: %{calls: 14, ...}},
#   by_agent: %{"grisk_the_snatcher" => %{calls: 7, ...}}
# }
```

The platform charges:

```text
platform_fee = provider_cost × upcharge_rate
invoice      = provider_cost + platform_fee
```

A typical upcharge rate would be 20–40%. The exact rate is a commercial decision, but the architecture guarantees it can be computed without hidden bypass paths. Every adapter records tokens in and out; no adapter can silently skip the audit step because the Router is the only caller.

## Marketplace of modules

Module authors publish YAML adventure files plus optional assets such as custom art, audio cues, or CSS themes for the web client. The storefront provides:

- **Module catalog** with title, recommended party size and level, difficulty, and preview extract.
- **Ratings and reviews** tied to completed runs, not to purchasers.
- **Revenue share**: author receives a fixed percentage of platform fees generated by runs of their module.
- **Free and paid tiers**, with paid modules gating premium content such as multi-dungeon campaigns or custom cognition tiers.

The runtime enforces module integrity by loading only validated YAML. A module cannot execute arbitrary Elixir because the Loader interprets a fixed schema. This is the security boundary that lets the platform host third-party content.

## Trust and moderation

Because modules are data, harmful content is mostly textual. Curation layers include:

1. **Automated validation** (`EngineCore.Validator`) rejects malformed or structurally dangerous YAML.
2. **Community reporting** on narration outputs that violate storefront standards.
3. **Editorial curation** for featured modules, similar to an app store.
4. **Cryptographic signing** in v2 so players can verify that a module has not been tampered with after purchase.

The platform itself never sees the LLM prompts in the clear because prompt construction happens inside the user's runtime. It sees only audit metadata: class, adapter, model, tokens, and a slice reference.

## Future roadmap

| Milestone | Capability |
|-----------|------------|
| v1 (current) | Single-module runs, per-run sandbox, user-provided keys, ledger billing. |
| v2 | Cross-run campaign memory: persistent world state, NPC relationships, and timeline continuity across multiple sessions. |
| v2.1 | Cryptographic module signing and provenance for paid modules. |
| v3 | Curated storefront with revenue share, ratings, and author tools. |
| v3.1 | Hosted TUI and web client with real-time spectator mode over `Wire` channels. |
| v4 | Marketplace API and SDK for third-party engine integrations. |

## Architectural summary

```
┌─────────────────────────────────────────────────────────────┐
│                       Platform Host                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │   Web UI     │  │   TUI Client │  │  Author Dashboard  │  │
│  └──────┬───────┘  └──────┬───────┘  └─────────┬──────────┘  │
│         │                 │                    │             │
│         └─────────────────┴────────────────────┘             │
│                           │                                   │
│                    ┌──────┴──────┐                            │
│                    │  Referee    │  one GenServer per run     │
│                    │  Session    │  routes via user keys      │
│                    └──────┬──────┘                            │
│                           │                                   │
│         ┌─────────────────┼─────────────────┐                 │
│         ▼                 ▼                 ▼                 │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐         │
│  │ EngineCore  │   │ LLMGateway  │   │   Ledger    │         │
│  │  World      │   │   Router    │   │  Writer     │         │
│  │  Server     │   │  (choke)    │   │  (audit)    │         │
│  └─────────────┘   └─────────────┘   └─────────────┘         │
│         │                 │                 │                  │
│         └─────────────────┴─────────────────┘                  │
│                           │                                   │
│                    ┌──────┴──────┐                            │
│                    │  Provider   │  user keys, platform fee   │
│                    │  endpoints  │                            │
│                    └─────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

## Summary

The Shattered Kingdoms platform is built around three economic and architectural commitments:

1. **Users bring their own LLM keys**, so the platform can scale without subsidizing inference.
2. **Every call is routed, audited, and ledgered** through a single gateway, making billing transparent and enforceable.
3. **Runs are sandboxed by design**, so modules, keys, and campaign states never leak across boundaries.

From these commitments follow the marketplace: authors write data-first modules, players run them in isolated sandboxes, and the platform captures value through a per-token upcharge rather than through walled-garden lock-in. The current Elixir umbrella already contains the runtime kernel of that vision; the remaining work is mostly storefront, signing, and cross-run persistence.
