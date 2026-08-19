defmodule Agents.BrainTest do
  @moduledoc "Brain lifecycle: one temporary process per tier-3 agent id."
  use ExUnit.Case, async: true

  test "ensure_brain starts a registered brain, idempotently" do
    assert :ok == Agents.ensure_brain("grisk_the_snatcher")
    pid = Agents.whereis("grisk_the_snatcher")
    assert is_pid(pid)
    assert :ok == Agents.ensure_brain("grisk_the_snatcher")
    assert pid == Agents.whereis("grisk_the_snatcher")
  end

  test "kill leaves no brain; ensure restarts a fresh one" do
    Agents.ensure_brain("willem")
    pid = Agents.whereis("willem")
    Agents.kill_brain("willem")
    :timer.sleep(10)
    assert nil == Agents.whereis("willem")
    assert :ok == Agents.ensure_brain("willem")
    refute pid == Agents.whereis("willem")
  end

  test "distinct agents get distinct brains" do
    Agents.ensure_brain("goblin_guard_1")
    Agents.ensure_brain("goblin_guard_2")
    refute Agents.whereis("goblin_guard_1") == Agents.whereis("goblin_guard_2")
  end
end
