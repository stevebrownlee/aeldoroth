defmodule Referee.SessionTest do
  @moduledoc """
  Run.Session (plan 5 Task 5): live run owner over the pure pipeline. Every
  step flushes new ledger events to the per-run writer; pause/resume gate the
  pipeline behind dossiers; checkpoint/restore continues byte-identically.
  """
  use ExUnit.Case, async: true
  alias EngineCore.{RunSup, World}
  alias EngineCore.Ledger.Writer
  alias LLMGateway.Adapters.Scripted
  alias Referee.Run
  alias Referee.Run.Session

  @yaml Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @pcs [
    %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
      int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
    %{id: "pc_bramble", name: "Bramble", place_id: "entry_hall",
      int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
  ]

  @moves ~w(east south north east)

  defp interpret_scripts do
    Enum.map(@moves, fn dir ->
      Jason.encode!(%{"verb" => "move", "target_id" => nil, "params" => %{"direction" => dir}})
    end)
  end

  defp routing do
    scripts = %{interpret: interpret_scripts(), salt: System.unique_integer()}
    %{interpret: %{adapter: Scripted, scripts: scripts}}
  end

  defp tmp_dir(tag) do
    dir = Path.join(System.tmp_dir!(), "session_#{tag}_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp with_session(tag, fun) do
    id = "sess_#{tag}_#{:erlang.unique_integer([:positive])}"
    dir = tmp_dir(tag)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, pid} = Session.start_link(id, @yaml, 42, @pcs, routing: routing(), data_dir: dir)
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      RunSup.stop_run(id)
    end)

    fun.(id, dir, pid)
  end

  test "declare through session mirrors the pure path byte-identically", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      {:ok, a} = Run.new(@yaml, 42, @pcs, routing: routing())
      {:ok, text_a, a2} = Run.declare(a, "pc_thistle", "go east")

      assert {:ok, %{reply: text_b}} = Session.declare(id, "pc_thistle", "go east")
      assert text_b == text_a

      assert :erlang.term_to_binary(Run.events(a2)) ==
               :erlang.term_to_binary(Writer.events(id))
    end)
  end

  test "roster lists seats for the web picker", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert Session.roster(id) == [
               %{id: "pc_thistle", name: "Thistle"},
               %{id: "pc_bramble", name: "Bramble"}
             ]
    end)
  end

  test "roster of an unknown run is nil" do
    assert Session.roster("nope") == nil
  end

  test "advance through session mirrors the pure path", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      {:ok, base} = Run.new(@yaml, 42, @pcs, routing: routing())
      {:ok, _, run} = Run.declare(base, "pc_thistle", "go east")
      {:ok, texts_a, a2} = Run.advance(run)

      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, texts_b} = Session.advance(id)
      assert texts_b == texts_a

      assert :erlang.term_to_binary(Run.events(a2)) ==
               :erlang.term_to_binary(Writer.events(id))
    end)
  end

  test "pause blocks pipeline and ledgers dossiers", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, %{dossiers: dossiers}} = Session.pause(id)
      assert Map.has_key?(dossiers, "pc_thistle")
      assert Map.has_key?(dossiers, "pc_bramble")

      dossier_events = Writer.events(id) |> Enum.filter(&(&1.class == :dossier))
      assert length(dossier_events) == 2
      assert Enum.all?(dossier_events, &(&1.payload[:kind] == :dossier))

      assert %{status: :paused} = Session.state(id)

      assert {:error, :paused} = Session.declare(id, "pc_thistle", "go east")
      assert {:error, :paused} = Session.advance(id)

      assert :ok = Session.resume(id)
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go east")
    end)
  end

  test "pause twice errors", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, _} = Session.pause(id)
      assert {:error, :already_paused} = Session.pause(id)
    end)
  end

  test "checkpoint restore continues deterministically", ctx do
    with_session(ctx.test, fn id, dir, pid ->
      # uninterrupted reference: same four declares on the pure path
      {:ok, base} = Run.new(@yaml, 42, @pcs, routing: routing())
      ref = declare_all(base)

      # two declares, pause, then crash session + per-run processes
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go south")
      assert {:ok, _} = Session.pause(id)

      :ok = GenServer.stop(pid, :normal)
      :ok = RunSup.stop_run(id)

      # fresh routing for the continued session: real adapters are
      # stateless; the scripted queue's position is per-session runtime
      # state, so leg 2 gets scripts for the remaining two declares.
      {:ok, _pid2} = Session.restore(id, dir, routing: leg2_routing())

      assert {:ok, _} = Session.declare(id, "pc_thistle", "go north")
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")

      # Dossier events are excluded (pause artifact); their seq numbers
      # still shift later events, so compare content triples, not seqs.
      restored = Writer.events(id) |> Enum.reject(&(&1.class == :dossier))
      content = fn evs -> Enum.map(evs, &{&1.tick, &1.class, &1.payload}) end
      assert content.(Run.events(ref)) == content.(restored)

      assert %World{} = EngineCore.World.Server.snapshot(id)
    end)
  end

  defp declare_all(run) do
    Enum.reduce(@moves, run, fn dir, acc ->
      {:ok, _, acc2} = Run.declare(acc, "pc_thistle", "go #{dir}")
      acc2
    end)
  end

  defp leg2_routing do
    scripts = %{interpret: interpret_scripts() |> Enum.drop(2), salt: System.unique_integer()}
    %{interpret: %{adapter: Scripted, scripts: scripts}}
  end
end
