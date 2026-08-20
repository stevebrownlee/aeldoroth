defmodule ClientWeb.Layouts do
  @moduledoc """
  Root + app layouts. Hand-rolled minimal dark styling; JS is vendored
  (committed under priv/static/assets) — the console runs offline.
  """

  use ClientWeb, :html

  embed_templates "layouts/*"

  @doc "Minimal flash rendering (info/error only — no core_components)."
  attr :flash, :map, required: true
  def flash_group(assigns) do
    ~H"""
    <div class="flashes">
      <div :if={msg = Phoenix.Flash.get(@flash, :info)} class="flash-info" data-testid="flash-info">{msg}</div>
      <div :if={msg = Phoenix.Flash.get(@flash, :error)} class="flash-error" data-testid="flash-error">{msg}</div>
    </div>
    """
  end
end
