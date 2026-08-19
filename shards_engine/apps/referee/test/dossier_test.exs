defmodule Referee.DossierTest do
  @moduledoc """
  Referee.Dossier (plan 5 Task 4): PC dossier via one `:summarize` call,
  template fallback listing current beliefs, truth barrier on prompt inputs.
  """
  use ExUnit.Case, async: true
  alias EngineCore.Ledger
  alias LLMGateway.{Ctx, Adapters.Scripted}
  alias Referee.Dossier

  defp ctx(scripts \\ %{}),
    do: Ctx.from_config(%{summarize: %{adapter: Scripted, scripts: scripts}})

  defp pc(beliefs \\ %{}) do
    %{
      id: "pc_thistle",
      name: "Thistle",
      place_id: "guard_room",
      beliefs: beliefs
    }
  end

  defp beliefs(abouts) do
    metas = Map.new(abouts, &{&1, %{count: 1, seen: true, last_fidelity: 3, last_tick: 1, salience: 4.0}})
    %{"guard_room" => metas}
  end

  defp narration(seq, agent_id, text),
    do: %Ledger.Event{seq: seq, tick: seq, class: :narration, payload: %{kind: :narration, agent_id: agent_id, text: text}}

  test "routed LLM dossier is used verbatim with an audit" do
    scripts = %{summarize: [~s({"dossier":"Thistle remembers dust, shouts, and a locked stair."})]}

    {text, _ctx2, audit} = Dossier.build(ctx(scripts), pc(beliefs(["goblin_guard_1"])), [narration(1, "pc_thistle", "You go east.")])

    assert text == "Thistle remembers dust, shouts, and a locked stair."
    assert audit.class == :summarize and audit.parse_verdict == :ok
  end

  test "schema-invalid LLM output falls back to the template; it never fails" do
    scripts = %{summarize: ["not the shape you wanted"]}

    {text, _ctx2, audit} = Dossier.build(ctx(scripts), pc(beliefs(["goblin_guard_1", "goblin_guard_2"])), [])

    assert text == "Thistle recalls: guard_room — goblin_guard_1, goblin_guard_2. (narrations elided)"
    assert audit.adapter == :template and audit.parse_verdict == :fallback
  end

  test "no summarize route falls back to the template with nil audit" do
    {text, _ctx2, audit} = Dossier.build(%Ctx{}, pc(beliefs(["goblin_guard_1"])), [])
    assert text =~ "Thistle recalls:"
    assert is_nil(audit)
  end

  test "narrations are chronological, capped at 20, and only this PC's" do
    mine = for i <- 1..25, do: narration(i, "pc_thistle", "line #{i}")
    others = [narration(26, "pc_bramble", "someone else's line")]

    # prompt_text is the deterministic LLM-path prompt; narrations included
    prompt = Dossier.prompt_text(pc(beliefs([])), mine ++ others)

    assert prompt =~ "- line 25"
    refute prompt =~ "- line 1\n"
    refute prompt =~ "- line 5\n"
    assert prompt =~ "- line 6\n"
    refute prompt =~ "someone else"
    assert prompt =~ "Thistle"
  end

  test "truth barrier: prompt references only believed agents, never the wider world" do
    # full world has four guards; Thistle believes only the first
    world_agent_ids = ~w(goblin_guard_1 goblin_guard_2 goblin_guard_3 goblin_guard_4 pc_thistle)

    prompt = Dossier.prompt_text(pc(beliefs(["goblin_guard_1"])), [narration(1, "pc_thistle", "You go east.")])

    assert prompt =~ "goblin_guard_1"
    assert prompt =~ "You go east."

    for id <- world_agent_ids -- ["goblin_guard_1", "pc_thistle"] do
      refute prompt =~ id
    end
  end
end
