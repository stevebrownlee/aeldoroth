defmodule ClientWeb.Router do
  @moduledoc """
  Three surfaces (plan 7): home (referee console — run creation),
  run (player seat over the wire protocol), GM (spectate + advance lever).
  """

  use Phoenix.Router, helpers: false

  import Phoenix.LiveView.Router
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ClientWeb.Layouts, :root}
  end

  scope "/", ClientWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/runs/:run_id", RunLive
    live "/runs/:run_id/gm", SpectateLive
  end
end
