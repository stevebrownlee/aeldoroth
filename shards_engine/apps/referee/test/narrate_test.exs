defmodule Referee.NarrateTest do
  @moduledoc "Narration stage: LLM for action outcomes, deterministic templates for received-speech delivery (decision 31)."
  use ExUnit.Case, async: true
  alias EngineCore.{Ledger, Types}
  alias LLMGateway.{Ctx, Adapters.Scripted}
  alias Referee.Narrate

  @prefs %{tone: "grim-but-heroic", narration_style: "terse", lethality: "standard", dice_visibility: "open",
           xp: %{gold_per_xp: 1, creative_bonus: true}}

  defp ctx(scripts \\ %{}),
    do: Ctx.from_config(%{narrate: %{adapter: Scripted, scripts: scripts}})

  defp action(verb, params \\ %{}),
    do: struct!(Types.Action, actor_id: "pc", verb: verb, params: params)

  test "routed LLM text is used verbatim with an audit" do
    {text, _ctx2, audit} = Narrate.action(ctx(%{narrate: ["You slip north, boots silent on ash."]}), @prefs, "pc", action(:move, %{direction: "north"}), {:ok, []})

    assert text == "You slip north, boots silent on ash."
    assert audit.class == :narrate and audit.parse_verdict == :ok
  end

  test "budget-degraded routing falls back to template with :fallback audit" do
    degraded = %Ctx{ctx() | budget: %{cap: 10, spent: 1_000}}
    {text, _ctx2, audit} = Narrate.action(degraded, @prefs, "pc", action(:move, %{direction: "north"}), {:ok, []})

    assert is_binary(text) and text != ""
    assert audit.parse_verdict == :fallback
    assert audit.adapter == :template
  end

  test "no narrate route falls back to template" do
    {text, _ctx2, audit} = Narrate.action(%Ctx{}, @prefs, "pc", action(:wait), {:ok, []})
    assert is_binary(text) and text != ""
    assert audit.parse_verdict == :fallback
  end

  test "templates: move ok, move fail, rejected reason, wait hesitation, shout, damage, death, stale miss" do
    c = %Ctx{}

    assert Narrate.action(c, @prefs, "pc", action(:move, %{direction: "north"}), {:ok, []}) |> elem(0) =~ "north"
    assert Narrate.action(c, @prefs, "pc", action(:move, %{direction: "up"}), {:diegetic_fail, []}) |> elem(0) =~ "no way through"

    assert Narrate.action(c, @prefs, "pc", action(:strike), {:rejected, "You see no such creature."}) |> elem(0) ==
             "You see no such creature."

    assert Narrate.action(c, @prefs, "pc", struct!(Types.Action, actor_id: "pc", verb: :wait, params: %{hesitant: true}), {:ok, []})
           |> elem(0) =~ "hesitate"

    assert Narrate.action(c, @prefs, "pc", action(:shout, %{message: "HELLO"}), {:ok, []}) |> elem(0) =~ "HELLO"

    dmg = [%Ledger.Event{seq: 1, tick: 1, class: :world, payload: %{kind: :damage, target_id: "gob", amount: 3}}]
    assert Narrate.action(c, @prefs, "pc", action(:strike, %{target_id: "gob"}), {:ok, dmg}) |> elem(0) =~ "3"

    death =
      dmg ++ [%Ledger.Event{seq: 2, tick: 1, class: :world, payload: %{kind: :death, agent_id: "gob"}}]

    assert Narrate.action(c, @prefs, "pc", action(:strike, %{target_id: "gob"}), {:ok, death}) |> elem(0) =~ "falls"

    stale = [%Ledger.Event{seq: 1, tick: 1, class: :world, payload: %{kind: :belief_corrected, agent_id: "pc", place_id: "hall", about: "gob"}}]
    assert Narrate.action(c, @prefs, "pc", action(:strike, %{target_id: "gob"}), {:diegetic_fail, stale}) |> elem(0) =~ "nothing there"
  end

  test "rich narration style appends assumptions; terse does not" do
    rich = Map.put(@prefs, :narration_style, "rich")
    c = %Ctx{}
    opts = [assumptions: ["taking 'north' as the library passage"]]

    terse_text = Narrate.action(c, @prefs, "pc", action(:move, %{direction: "north"}), {:ok, []}, opts) |> elem(0)
    rich_text = Narrate.action(c, rich, "pc", action(:move, %{direction: "north"}), {:ok, []}, opts) |> elem(0)

    refute terse_text =~ "taking 'north'"
    assert rich_text =~ "taking 'north'"
  end

  test "received never calls the LLM: attribution templates render even with a live route" do
    payloads = [
      %{kind: :signal_received, agent_id: "pc", place_id: "hall", about: "erik", signal_kind: :sound,
        intensity: 7.0, fidelity: 4, salience: 1.0, roll: nil, speaker_name: "Erik the Shepherd",
        content_nl: "Goblins took three sheep.", content_core: %{class: :voices, to: "pc"}},
      %{kind: :signal_received, agent_id: "pc", place_id: "hall", about: "grevik", signal_kind: :sound,
        intensity: 7.0, fidelity: 4, salience: 0.9, roll: nil, speaker_name: "Mayor Grevik",
        content_nl: "One hundred gold to whoever ends the raids.", content_core: %{class: :voices}}
    ]

    {text, _ctx2, audit} =
      Narrate.received(ctx(%{narrate: ["garbage that must never surface"]}), @prefs, "pc", payloads)

    # A directed reply is attributed to this PC alone; room chatter is overheard.
    assert text =~ "Erik the Shepherd says to you:"
    assert text =~ "Goblins took three sheep."
    assert text =~ "You hear Mayor Grevik"
    assert text =~ "One hundred gold to whoever ends the raids."

    # Delivery is mechanical formatting of already-organic words: zero LLM traffic.
    assert Scripted.take_requests() == []
    assert audit.adapter == :template
  end

  test "received with no route still renders attributed templates" do
    payloads = [
      %{kind: :signal_received, agent_id: "pc", place_id: "hall", about: "erik", signal_kind: :sound,
        intensity: 7.0, fidelity: 4, salience: 1.0, roll: nil, speaker_name: "Erik the Shepherd",
        content_nl: "Aye.", content_core: %{class: :voices, to: "pc"}}
    ]

    {text, _ctx2, audit} = Narrate.received(%Ctx{}, @prefs, "pc", payloads)

    assert text =~ "Erik the Shepherd says to you:"
    assert audit.parse_verdict == :skipped and audit.adapter == :template and audit.ok
  end

  test "shout narration distinguishes directed, wordless address, and ambient" do
    directed = struct!(Types.Action, actor_id: "pc", verb: :shout, target_id: "gob", params: %{message: "hello"})
    wordless = struct!(Types.Action, actor_id: "pc", verb: :shout, target_id: "gob", params: %{message: ""})
    ambient = struct!(Types.Action, actor_id: "pc", verb: :shout, target_id: nil, params: %{message: "hello"})

    {t1, _c, _a} = Narrate.action(ctx(), @prefs, "pc", directed, {:ok, []}, target_name: "Gob")
    assert t1 =~ ~s(You say to Gob: "hello")

    {t2, _c, _a} = Narrate.action(ctx(), @prefs, "pc", wordless, {:ok, []}, target_name: "Gob")
    assert t2 =~ "You address Gob"

    {t3, _c, _a} = Narrate.action(ctx(), @prefs, "pc", ambient, {:ok, []})
    assert t3 =~ ~s(You shout: "hello")
  end
end
