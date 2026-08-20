defmodule ClientWeb.ConnCase do
  @moduledoc """
  Conn case for LiveView surface tests: endpoint + LiveViewTest wired.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      @endpoint ClientWeb.Endpoint
    end
  end

  setup _context do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
