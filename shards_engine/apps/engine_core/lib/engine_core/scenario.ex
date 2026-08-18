defmodule EngineCore.Scenario do
  @moduledoc """
  Deterministic scripted combat — Plan-1 acceptance proof (replay determinism + fold = state).
  """
  alias EngineCore.{Dice, Ledger, Loader, Rules.Combat, Rules.Movement, Types, World}

  def party_vs_warband(yaml_path, seed) do
    {:ok, world} = Loader.load(yaml_path)
    rng = Dice.new(seed)
    ledger = start_ledger!()
    world = add_party(world)
    {world, _rng} = loop(world, rng, ledger, 100)

    %{ledger: Ledger.events(ledger), final_world: world}
  end

  # Level-3 party, class-flavored 1E statblocks with strong rolls (no spell
  # engine yet, so casters contribute martial stats: mace and conjured dagger).
  @party [
    {"pc1", "Bran Ironhelm (Fighter)",
     %{
       ac: 2,
       hd: 3,
       hp_max: 26,
       thac0: 16,
       morale: 12,
       int: 10,
       damage: %{dice: 1, sides: 8, plus: 2}
     }},
    {"pc2", "Kestrel Thornwood (Ranger)",
     %{
       ac: 3,
       hd: 3,
       hp_max: 24,
       thac0: 17,
       morale: 11,
       int: 13,
       damage: %{dice: 1, sides: 6, plus: 2}
     }},
    {"pc3", "Aldous Brightmantle (Cleric)",
     %{
       ac: 4,
       hd: 3,
       hp_max: 20,
       thac0: 18,
       morale: 10,
       int: 12,
       damage: %{dice: 1, sides: 6, plus: 2}
     }},
    {"pc4", "Miriel Duskweaver (Illusionist)",
     %{
       ac: 7,
       hd: 3,
       hp_max: 14,
       thac0: 18,
       morale: 9,
       int: 17,
       damage: %{dice: 1, sides: 4, plus: 2}
     }}
  ]

  def add_party(world) do
    pcs =
      for {id, name, stats} <- @party, into: %{} do
        {id,
         struct!(Types.Agent,
           id: id,
           name: name,
           tier: 3,
           place_id: "entry_hall",
           statblock: stats,
           body: %{hp: stats.hp_max, conditions: []},
           capabilities: [:move, :strike, :wait]
         )}
      end

    %{world | agents: Map.merge(world.agents, pcs)}
  end

  defp start_ledger! do
    {:ok, pid} = Ledger.start_link(name: nil)
    pid
  end

  defp loop(world, rng, _ledger, 0), do: {world, rng}

  defp loop(world, rng, ledger, n) do
    {order, rng} = Combat.initiative(rng, alive(world))

    {world, rng} =
      Enum.reduce(order, {world, rng}, fn id, {w, r} -> act(w, r, ledger, id) end)

    if battle_over?(world) do
      {world, rng}
    else
      loop(world, rng, ledger, n - 1)
    end
  end

  defp act(world, rng, ledger, id) do
    case World.agent(world, id) do
      nil -> {world, rng}
      %{body: %{hp: 0}} -> {world, rng}
      a -> choose_action(world, rng, ledger, a)
    end
  end

  defp choose_action(world, rng, ledger, a) do
    foes =
      world
      |> World.agents_in(a.place_id)
      |> Enum.reject(&(&1.id == a.id))
      |> Enum.reject(&(&1.body.hp == 0))
      |> Enum.reject(&same_side?(a.id, &1.id))

    case foes do
      [] ->
        dest = world.places[a.place_id].connections |> List.first()
        move_or_wait(world, rng, ledger, a, dest)

      [foe | _] ->
        case Combat.attack(world, rng, a.id, foe.id) do
          {:ok, events, w2, r2} ->
            Enum.each(events, &Ledger.append(ledger, &1.class, &1.tick, &1.payload))
            {w2, r2}

          {:error, _} ->
            {world, rng}
        end
    end
  end

  defp same_side?(id, other_id), do: pc?(id) == pc?(other_id)
  defp pc?(id), do: String.starts_with?(id, "pc")

  defp move_or_wait(world, rng, _ledger, _a, nil), do: {world, rng}

  defp move_or_wait(world, rng, ledger, a, dest) do
    case Movement.traverse(world, rng, a.id, dest) do
      {:ok, ev, w2, r2} ->
        Ledger.append(ledger, ev.class, ev.tick, ev.payload)
        {w2, r2}

      {:error, _} ->
        {world, rng}
    end
  end

  defp alive(world),
    do: world.agents |> Map.values() |> Enum.filter(&(&1.body.hp > 0)) |> Enum.map(& &1.id)

  defp battle_over?(world) do
    living = alive(world)
    pcs = Enum.filter(living, &String.starts_with?(&1, "pc"))
    living -- pcs == [] or pcs == []
  end
end
