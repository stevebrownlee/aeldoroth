defmodule EngineCore.NarrateTest do
  use ExUnit.Case, async: true
  alias EngineCore.{Loader, Narrate}

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  @yaml if File.exists?(path),
          do: path,
          else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  defp view(kind, class, intensity, nl),
    do: %{
      kind: kind,
      intensity: intensity,
      content_nl: nl,
      content_core: %{class: class, threat: class == :combat, about: "pc1", count: 1}
    }

  test "fidelity tier ladder for sound" do
    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 0, "east") == ""

    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 1, nil) ==
             "You hear something."

    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 2, nil) ==
             "You hear a sounds-of-fighting noise."

    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 3, "east") ==
             "You hear a loud sounds-of-fighting noise to the east."

    assert Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 4, "east") ==
             "You hear the crash of steel to the east."

    out = Narrate.render(view(:sound, :combat, 8, "the crash of steel"), 5, "east")
    assert String.starts_with?(out, "You hear the crash of steel to the east.")
    assert String.contains?(out, "something is wrong")
  end

  test "intensity words and unknown direction" do
    assert String.contains?(
             Narrate.render(view(:sound, :footsteps, 2, nil), 3, nil),
             "faint scraping-of-feet noise somewhere nearby"
           )

    assert String.contains?(
             Narrate.render(view(:sound, :alarm, 10, "pots and pans crashing"), 3, nil),
             "deafening"
           )
  end

  test "sight, smell, tremor openers" do
    assert Narrate.render(view(:sight, :movement, 5, nil), 1, nil) == "You glimpse movement."
    assert Narrate.render(view(:smell, :musk, 4, nil), 1, nil) == "You catch an odor."
    assert Narrate.render(view(:tremor, :footfall, 6, nil), 1, nil) == "You feel a vibration."

    assert Narrate.render(view(:sight, :movement, 6, "four small figures"), 4, "north") ==
             "You see four small figures to the north."
  end

  test "direction from edges over the real tower" do
    {:ok, w} = Loader.load(@yaml)
    assert Narrate.direction(w, "entry_hall", "guard_room") == "east"
    assert Narrate.direction(w, "guard_room", "entry_hall") == "west"
    assert Narrate.direction(w, "entry_hall", "chiefs_room") == "somewhere nearby"
    assert Narrate.direction(w, "entry_hall", "entry_hall") == "very close"
  end
end
