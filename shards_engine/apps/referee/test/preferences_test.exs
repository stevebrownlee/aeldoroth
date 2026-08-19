defmodule Referee.PreferencesTest do
  use ExUnit.Case, async: true
  alias Referee.Preferences

  test "core defaults exist" do
    c = Preferences.core()

    assert c.tone == "neutral"
    assert c.narration_style == "terse"
    assert c.lethality == "standard"
    assert c.dice_visibility == "open"
    assert c.xp == %{gold_per_xp: 1, creative_bonus: true}
  end

  test "module overrides core, personal overrides module" do
    {m, []} = Preferences.resolve(%{tone: "grim-but-heroic", xp: %{gold_per_xp: 2}}, %{})
    assert m.tone == "grim-but-heroic"
    assert m.xp == %{gold_per_xp: 2, creative_bonus: true}
    assert m.narration_style == "terse"

    {p, []} = Preferences.resolve(%{tone: "grim-but-heroic"}, %{tone: "hopeful", lethality: "heroic"})
    assert p.tone == "hopeful"
    assert p.lethality == "heroic"
    assert p.narration_style == "terse"
  end

  test "nil layers are accepted" do
    {r, []} = Preferences.resolve(nil, nil)
    assert r == Preferences.core()
  end

  test "unknown keys dropped with warnings, nested included" do
    {r, warns} = Preferences.resolve(%{mist: "x", xp: %{gold_per_xp: 2, bloat: true}}, %{frob: 1})

    assert Map.has_key?(r, :tone)
    refute Map.has_key?(r, :mist)
    refute Map.has_key?(r, :frob)
    assert r.xp == %{gold_per_xp: 2, creative_bonus: true}

    assert Enum.any?(warns, &String.contains?(&1, "mist"))
    assert Enum.any?(warns, &String.contains?(&1, "frob"))
    assert Enum.any?(warns, &String.contains?(&1, "bloat"))
  end

  test "hash/1 is stable and value-sensitive" do
    {a, []} = Preferences.resolve(%{}, %{})
    {b, []} = Preferences.resolve(%{}, %{})

    assert Preferences.hash(a) == Preferences.hash(b)

    {c, []} = Preferences.resolve(%{tone: "x"}, %{})
    refute Preferences.hash(a) == Preferences.hash(c)

    {d, []} = Preferences.resolve(%{xp: %{gold_per_xp: 2}}, %{})
    refute Preferences.hash(a) == Preferences.hash(d)
  end
end
