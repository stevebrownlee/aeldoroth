defmodule ClientWeb.HomeLive do
  @moduledoc """
  Referee console landing: new-run form + active runs list.

  Task 1 stub — renders the shell only; Session wiring lands in Task 3.
  """

  use ClientWeb, :live_view

  def render(assigns) do
    ~H"""
    <h1>The Shattered Kingdoms</h1>
    <p>Referee console — new-run form arrives with Task 3.</p>
    """
  end
end
