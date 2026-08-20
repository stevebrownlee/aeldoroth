defmodule ClientWeb.HomeLiveTest do
  @moduledoc """
  Landing smoke (plan 7 Task 1.6): HomeLive renders the shell.
  """

  use ClientWeb.ConnCase, async: true

  test "renders home", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "<h1>The Shattered Kingdoms</h1>"
  end
end
