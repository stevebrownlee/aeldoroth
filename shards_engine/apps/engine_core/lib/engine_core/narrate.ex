defmodule EngineCore.Narrate do
  @moduledoc """
  Template narration at fidelity tiers (decision 31). The LLM narrate class
  (Plan 3) swaps these templates out; facts stay engine-side.
  """

  @class_words %{
    sound: %{
      alarm: "clattering",
      combat: "sounds-of-fighting",
      footsteps: "scraping-of-feet",
      voices: "murmur-of-voices",
      metallic: "metallic-clinking"
    },
    sight: %{movement: "movement", figures: "figures"},
    smell: %{musk: "rank", smoke: "smoke", blood: "blood"},
    tremor: %{footfall: "heavy", collapse: "rumbling"}
  }

  @openers %{
    sound: {"You hear something.", "You hear"},
    sight: {"You glimpse movement.", "You see"},
    smell: {"You catch an odor.", "You smell"},
    tremor: {"You feel a vibration.", "You feel"}
  }

  @inferences %{
    combat: "something is wrong",
    alarm: "a trap has been sprung",
    stealth: "something is trying to be quiet"
  }

  @spec render(map, 0..5, String.t() | nil) :: String.t()
  def render(view, fidelity, direction \\ nil)
  def render(_view, 0, _dir), do: ""

  # Voiced speech with usable words renders attributed, not as ambient
  # noise: the addressee gets the words plainly; a listener gets an
  # overheard line. Callers supply `speaker` / `addressed` on the view.
  def render(%{kind: :sound, content_core: %{class: :voices}} = view, fidelity, _dir)
      when fidelity >= 4 do
    case view do
      %{content_nl: nl, speaker: speaker}
      when is_binary(nl) and nl != "" and is_binary(speaker) and speaker != "" ->
        if Map.get(view, :addressed),
          do: "#{speaker} says to you: “#{nl}”",
          else: "You hear #{speaker} say: “#{nl}”"

      %{content_nl: nl} when is_binary(nl) and nl != "" ->
        if Map.get(view, :addressed),
          do: "Someone says to you: “#{nl}”",
          else: "You hear #{nl} nearby."

      _ ->
        if Map.get(view, :addressed),
          do: "#{Map.get(view, :speaker) || "Someone"} turns to speak with you.",
          else: "You hear a #{intensity_word(view.intensity)} murmur-of-voices nearby."
    end
  end

  def render(view, fidelity, direction) do
    kind = view.kind
    dir = dir_phrase(direction)
    iw = intensity_word(view.intensity)
    cw = class_word(kind, view.content_core)
    {bare, verb} = @openers[kind]

    case fidelity do
      1 -> bare
      2 -> "#{verb} a #{cw} #{noun(kind)}."
      3 -> "#{verb} a #{iw} #{cw} #{noun(kind)} #{dir}."
      4 -> rich(view, verb, iw, cw, dir)
      5 -> rich(view, verb, iw, cw, dir) <> " — " <> inference(view)
    end
  end

  # F4: prefer the emitter's natural-language payload; fall back to the
  # class-word template when the arrival carried no prose.
  defp rich(%{content_nl: nil} = view, verb, iw, cw, dir) do
    "#{verb} a #{iw} #{cw} #{noun(view.kind)} #{dir}."
  end

  defp rich(view, verb, _iw, _cw, dir), do: "#{verb} #{view.content_nl} #{dir}."

  defp noun(:sound), do: "noise"
  defp noun(:sight), do: "movement"
  defp noun(:smell), do: "smell"
  defp noun(:tremor), do: "tremor"

  defp class_word(kind, cc) do
    Map.get(@class_words[kind] || %{}, Map.get(cc || %{}, :class, :unknown), "strange")
  end

  defp intensity_word(i) when i >= 9, do: "deafening"
  defp intensity_word(i) when i >= 7, do: "loud"
  defp intensity_word(i) when i >= 4, do: "distinct"
  defp intensity_word(_), do: "faint"

  defp dir_phrase(nil), do: "somewhere nearby"
  defp dir_phrase("very close"), do: "very close"
  defp dir_phrase(d), do: "to the #{d}"

  defp inference(view) do
    cc = view.content_core || %{}

    cond do
      Map.get(cc, :stealth) == true -> @inferences.stealth
      true -> Map.get(@inferences, Map.get(cc, :class, :none), @inferences.combat)
    end
  end

  @spec direction(EngineCore.World.t(), String.t(), String.t()) :: String.t()
  def direction(_world, from, to) when from == to, do: "very close"

  def direction(world, from, to) do
    case Enum.find(world.edges, &(&1.from == from and &1.to == to and &1.label)) do
      %EngineCore.Types.Edge{label: label} -> label
      nil -> "somewhere nearby"
    end
  end
end
