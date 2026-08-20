defmodule ClientWeb.ErrorView do
  @moduledoc """
  Plain-text error page. The console is a referee tool; errors surface in
  the terminal log, not styled HTML.
  """

  use ClientWeb, :html

  def render(template, _assigns) when is_binary(template) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
