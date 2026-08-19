# One file, four top-level shapes (see Shared Interfaces in the plan).
defmodule LLMGateway.Request do
  @moduledoc "One LLM call. `schema` constrains expected JSON output."
  @enforce_keys [:class, :system, :user]
  defstruct [:class, :system, :user, schema: nil, agent_id: nil, temperature: 0.1, max_tokens: 512]

  @type t :: %__MODULE__{
          class: atom(),
          agent_id: String.t() | nil,
          system: String.t(),
          user: String.t(),
          schema: map() | nil,
          temperature: float(),
          max_tokens: pos_integer()
        }
end

defmodule LLMGateway.Result do
  @moduledoc "Adapter output: raw content plus parsed JSON when it decoded to a map."
  defstruct [:content, :parsed, usage: %{tokens_in: 0, tokens_out: 0}]

  @type t :: %__MODULE__{
          content: String.t(),
          parsed: map() | nil,
          usage: %{tokens_in: non_neg_integer(), tokens_out: non_neg_integer()}
        }
end

defmodule LLMGateway.Audit do
  @moduledoc """
  Audit record for one routed call. Ledger payload form (`to_ledger/1`) is
  `%{kind: :llm_call, ...}` with atoms/values only.
  """

  defstruct [
    :class,
    :adapter,
    agent_id: nil,
    model: nil,
    tokens_in: 0,
    tokens_out: 0,
    prompt_slice_ref: nil,
    parse_verdict: :ok,
    ok: true
  ]

  @type verdict :: :ok | :retry_ok | :failed | :fallback | :skipped

  @type t :: %__MODULE__{
          class: atom(),
          agent_id: nil | String.t(),
          adapter: atom(),
          model: String.t() | nil,
          tokens_in: non_neg_integer(),
          tokens_out: non_neg_integer(),
          prompt_slice_ref: String.t() | nil,
          parse_verdict: verdict(),
          ok: boolean()
        }

  @spec to_ledger(t()) :: map()
  def to_ledger(%__MODULE__{} = a) do
    %{
      kind: :llm_call,
      class: a.class,
      agent_id: a.agent_id,
      adapter: a.adapter,
      model: a.model,
      tokens_in: a.tokens_in,
      tokens_out: a.tokens_out,
      prompt_slice_ref: a.prompt_slice_ref,
      parse_verdict: a.parse_verdict,
      ok: a.ok
    }
  end
end

defmodule LLMGateway.Ctx do
  @moduledoc """
  Routing + budget + breaker state, threaded through every stage call and
  returned alongside results (the Router is pure; Ctx is its accumulator).
  """

  defstruct routing: %{}, budget: %{cap: :inf, spent: 0}, breaker: %{}

  @type adapter_cfg :: %{
          adapter: module(),
          model: String.t() | nil,
          endpoint: String.t() | nil,
          key_ref: atom() | nil,
          temperature: float(),
          max_tokens: pos_integer()
        }

  @type t :: %__MODULE__{
          routing: %{atom() => adapter_cfg()},
          budget: %{cap: non_neg_integer() | :inf, spent: non_neg_integer()},
          breaker: %{atom() => non_neg_integer()}
        }

  @spec from_config(map() | nil) :: t()
  def from_config(routing \\ nil) do
    routing = routing || Application.get_env(:llm_gateway, :routing, %{})

    %__MODULE__{
      routing:
        Map.new(routing, fn {class, cfg} ->
          {class,
           %{
             adapter: Map.fetch!(cfg, :adapter),
             model: Map.get(cfg, :model),
             endpoint: Map.get(cfg, :endpoint),
             key_ref: Map.get(cfg, :key_ref),
             temperature: Map.get(cfg, :temperature, 0.1),
             max_tokens: Map.get(cfg, :max_tokens, 512)
           }
           # adapter-specific keys (e.g. Scripted's :scripts) pass through
           |> Map.merge(Map.drop(cfg, [:adapter, :model, :endpoint, :key_ref, :temperature, :max_tokens]))}
        end)
    }
  end
end
