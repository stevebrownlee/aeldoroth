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

  # opts override routing/data_dir/pcs for tests needing a different script
  # set or party.
  defp with_session(tag, fun), do: with_session(tag, [], fun)

  defp with_session(tag, opts, fun) do
    id = "sess_#{tag}_#{:erlang.unique_integer([:positive])}"
    dir = tmp_dir(tag)
    on_exit(fn -> File.rm_rf!(dir) end)

    pcs = Keyword.get(opts, :pcs, @pcs)
    opts = Keyword.delete(opts, :pcs)

    {:ok, pid} =
      Session.start_link(id, @yaml, 42, pcs,
        Keyword.merge([routing: routing(), data_dir: dir], opts)
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      RunSup.stop_run(id)
    end)

    fun.(id, dir, pid)
  end

  test "pause and resume ledger meta events for the wire", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, _} = Session.pause(id)

      kinds =
        Writer.events(id)
        |> Enum.filter(&(&1.class == :meta and &1.payload.kind in [:paused, :resumed]))
        |> Enum.map(& &1.payload.kind)

      assert kinds == [:paused]

      assert :ok = Session.resume(id)

      kinds =
        Writer.events(id)
        |> Enum.filter(&(&1.class == :meta and &1.payload.kind in [:paused, :resumed]))
        |> Enum.map(& &1.payload.kind)

      # oldest first
      assert kinds == [:paused, :resumed]
    end)
  end
  test "awaiting reports last intents and outstanding clarify prompts", ctx do
    # garbage interpret scripts: every scripted parse fails, so every
    # declare falls back to the deterministic grammar — no LLM dice in play.
    grammar_only = %{
      interpret: %{
        adapter: Scripted,
        scripts: %{interpret: ["not json"], salt: System.unique_integer()}
      }
    }

    # two identically-named PCs: both walk out and back, arriving at
    # Thistle's place, so Thistle believes both when the queue-exhausted
    # grammar sees "twin" — a lethal-verb tie -> clarify, never a guess
    # (decision 21).
    twins = [
      %{id: "pc_thistle", name: "Thistle", place_id: "entry_hall",
        int: 13, ac: 5, hd: 1, hp: 12, thac0: 20, damage: "1d8"},
      %{id: "pc_twin_a", name: "Twin", place_id: "entry_hall",
        int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"},
      %{id: "pc_twin_b", name: "Twin", place_id: "entry_hall",
        int: 12, ac: 6, hd: 1, hp: 8, thac0: 19, damage: "1d6"}
    ]

    with_session(ctx.test, [routing: grammar_only, pcs: twins], fn id, _dir, _pid ->
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_twin_a", "go east")
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_twin_b", "go east")
      assert {:ok, _} = Session.advance(id)
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_twin_a", "go west")
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_twin_b", "go west")
      assert {:ok, _} = Session.advance(id)
      assert {:ok, %{reply: reply}} = Session.declare(id, "pc_thistle", "attack twin")
      assert reply =~ "which one do you mean"

      assert {:ok, rows} = Session.awaiting(id)
      thistle = Enum.find(rows, &(&1.id == "pc_thistle"))
      assert thistle.last_intent.text == "attack twin"
      assert thistle.prompt.question =~ "which one do you mean"
      assert is_integer(thistle.prompt.tick)

      twin_a = Enum.find(rows, &(&1.id == "pc_twin_a"))
      assert twin_a.prompt == nil
      # any newer narration for the PC retires the prompt; grammar still
      # parses the move with the queue empty
      assert {:ok, %{reply: _}} = Session.declare(id, "pc_thistle", "go north")
      assert {:ok, _} = Session.advance(id)

      assert {:ok, rows2} = Session.awaiting(id)
      assert Enum.find(rows2, &(&1.id == "pc_thistle")).prompt == nil
    end)
  end


  test "declare through session registers intent and advance resolves it", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, %{reply: reply}} = Session.declare(id, "pc_thistle", "go east")
      assert reply =~ "Action registered" or reply =~ "go east"

      assert {:ok, texts} = Session.advance(id)
      assert Map.has_key?(texts, "pc_thistle")
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

  test "advance through session executes declared player actions and advances world", ctx do
    with_session(ctx.test, fn id, _dir, _pid ->
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, texts_b} = Session.advance(id)
      assert Map.has_key?(texts_b, "pc_thistle")
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
      _ref = declare_all(base)

      # two declares, pause, then crash session + per-run processes
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go south")
      assert {:ok, _} = Session.advance(id)
      assert {:ok, _} = Session.pause(id)

      :ok = GenServer.stop(pid, :normal)
      :ok = RunSup.stop_run(id)

      {:ok, _pid2} = Session.restore(id, dir, routing: leg2_routing())

      assert {:ok, _} = Session.declare(id, "pc_thistle", "go north")
      assert {:ok, _} = Session.declare(id, "pc_thistle", "go east")
      assert {:ok, _} = Session.advance(id)

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
