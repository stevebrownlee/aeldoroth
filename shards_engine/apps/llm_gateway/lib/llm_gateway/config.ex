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
