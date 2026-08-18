defmodule EngineCore.LoaderTest do
  use ExUnit.Case, async: true

  path = Path.expand("../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)
  @yaml if File.exists?(path), do: path, else: Path.expand("../../../../../../the-ruined-tower/ruined_tower.yaml", __DIR__)

  test "loads the tower into a coherent world" do
    {:ok, w} = EngineCore.Loader.load(@yaml)
    assert map_size(w.places) == 7
    assert w.tick == 0
    tiers = w.agents |> Map.values() |> Map.new(&{&1.tier, true})
    assert tiers[3] and tiers[2] and tiers[0] and tiers[1]
    assert Enum.all?(w.agents |> Map.values(), &(&1.place_id != nil))
  end

  test "refuses to load a file failing validation" do
    tmp = Path.join(System.tmp_dir!(), "bad_adventure_#{:erlang.unique_integer()}.yaml")
    File.write!(tmp, "monsters:\n- id: m1\n  name: x\n  description: bad (3 (7\n")
    on_exit(fn -> File.rm!(tmp) end)
    assert {:error, _} = EngineCore.Loader.load(tmp)
  end
end
