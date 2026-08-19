defmodule LLMGateway.Json do
  @moduledoc "Single import point for JSON encode/decode (Jason)."

  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(term), do: Jason.encode(term)

  @spec encode!(term()) :: String.t()
  def encode!(term), do: Jason.encode!(term)

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(bin), do: Jason.decode(bin)
end
