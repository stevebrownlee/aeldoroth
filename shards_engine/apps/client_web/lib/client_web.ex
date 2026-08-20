defmodule ClientWeb do
  @moduledoc """
  The web client's HTML layer helper (Phoenix 1.8 generated-app style):
  `use ClientWeb, :html` brings in `Phoenix.Component` with phx-only
  global attribute prefixes.
  """

  def html do
    quote do
      unquote(html_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {ClientWeb.Layouts, :app}
      import Phoenix.HTML
      import Plug.CSRFProtection, only: [get_csrf_token: 0]
    end
  end

  # Phoenix.Component is pulled in by both `use Phoenix.Component` (plain
  # HTML modules) and `use Phoenix.LiveView`; the :live_view path above
  # must not repeat it — a second `use` defines a redundant
  # __phoenix_component_verify__/1 clause.

  defp html_helpers do
    quote do
      use Phoenix.Component, global_prefixes: ~w(phx-)
      import Phoenix.HTML
      import Plug.CSRFProtection, only: [get_csrf_token: 0]
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
