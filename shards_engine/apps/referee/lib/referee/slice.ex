defmodule Referee.Slice do
  @moduledoc """
  Truth-barrier actor-visible view (spec §9; pattern: llm-proposes-engine-disposes).

  `for_actor/2` derives everything an LLM prompt may reference for one agent.
  Returned keys:
    * `:agent` — identity (`id`, `name`, `place_id`)
    * `:sheet` — the actor's own body (`hp`, `hp_max`, `ac`, `thac0`, `damage`,
      `conditions`, `morale`, `int`, `hd`); truth-barrier safe
    * `:place` — current place (`id`, `name`, `kind`, `exits`, `visible_items`,
      `items` with `id` and `name`)
    * `:believed` — ids of believed agents at this place
    * `:believed_agents` — the same ids resolved to `%{id: ..., name: ...}`
    * `:salient` — seen beliefs, sorted by salience
    * `:commitments`, `:capabilities`, `:dossier`, `:summary`

  Hidden items and agents in other places never appear — the slice is the only
  world data that reaches a prompt, and the sheet is the actor's own body,
  so it is truth-barrier safe.
  """

  alias EngineCore.World

  @spec for_actor(World.t(), String.t()) :: %{
          agent: map(),
          sheet: %{
            hp: integer(),
            hp_max: integer(),
            ac: integer(),
            thac0: integer(),
            damage: String.t() | nil,
            conditions: [atom()],
            morale: integer(),
            int: integer(),
            hd: integer(),
            level: integer(),
            xp: integer(),
            class: String.t() | nil,
            race: String.t() | nil,
            armor: String.t() | nil,
            weapons: String.t() | nil,
            inventory: String.t() | nil,
            spells: String.t() | nil,
            prayers: String.t() | nil
          },
          place: %{
            id: String.t(),
            name: String.t(),
            kind: atom(),
            exits: [String.t()],
            exits_labeled: [%{dir: String.t() | nil, to: String.t(), sealed: boolean()}],
            visible_items: [String.t()],
            items: [%{id: String.t(), name: String.t()}]
          },
          believed: [String.t()],
          believed_agents: [%{id: String.t(), name: String.t(), pc: boolean()}],
          salient: [String.t()],
          commitments: [map()],
          capabilities: [atom()],
          dossier: map(),
          recent_speech: [map()],
          summary: String.t()
        }
  def for_actor(%World{} = world, agent_id) do
    agent = World.agent(world, agent_id)
    place = World.place(world, agent.place_id)

    believed =
      agent.beliefs
      |> Map.get(agent.place_id, %{})
      |> Map.keys()
      |> Enum.sort()

    salient =
      agent.beliefs
      |> Map.get(agent.place_id, %{})
      |> Enum.filter(fn {_about, b} -> b[:seen] end)
      |> Enum.sort_by(fn {about, b} -> {-b[:salience], about} end)
      |> Enum.map(&elem(&1, 0))

    %{
      agent: %{id: agent.id, name: agent.name, place_id: agent.place_id},
      sheet: sheet(agent),
      place: %{
        id: place.id,
        name: place.name,
        kind: place.kind,
        exits: exits(world, agent.place_id),
        exits_labeled: exits_labeled(world, agent.place_id),
        visible_items: visible_items(world, agent.place_id),
        items: place_items(world, agent.place_id)
      },
      believed: believed,
      believed_agents: believed_agents(world, believed),
      salient: salient,
      commitments: commitments(agent),
      capabilities: agent.capabilities,
      dossier: Map.get(agent, :dossier) || %{},
      recent_speech: recent_speech(world, agent),
      summary: summarize(place, believed, world, agent.id)
    }
  end

  # Voiced words still held in beliefs: who spoke, what they said, and
  # whether it was aimed at this agent (addressed_tick set by the fold).
  # Speech is fleeting — only the last few ticks reach the slice, so a
  # reply obligation expires instead of being re-answered every tick
  # forever (belief history persists; only deliberation forgets).
  @speech_fresh_ticks 3
  defp recent_speech(world, agent) do
    believed = Map.get(agent.beliefs, agent.place_id, %{})

    Enum.flat_map(believed, fn {about, b} ->
      words = if is_binary(b[:words]), do: b[:words], else: ""

      # A wordless address (e.g. "talk to mayor grevik" carries no
      # utterance) is still speech this agent must answer: keep the line
      # whenever it was aimed here, even without words.
      if words != "" or b[:addressed_tick] != nil do
        speaker = world.agents[about]

        [
          %{
            from_id: about,
            from_name: if(speaker, do: speaker.name, else: about),
            words: if(words == "", do: "(no words — seeks your attention)", else: words),
            addressed: b[:addressed_tick] != nil,
            tick: b[:addressed_tick] || b[:last_tick]
          }
        ]
      else
        []
      end
    end)
    |> Enum.filter(&(&1.tick > world.tick - @speech_fresh_ticks))
    |> Enum.sort_by(&{-&1.tick, &1.from_id})
  end

  defp sheet(agent) do
    body = agent.body
    st = Map.get(agent, :statblock) || %{}

    %{
      hp: body.hp,
      hp_max: Map.get(st, :hp_max),
      ac: Map.get(st, :ac),
      thac0: Map.get(st, :thac0),
      damage: format_damage(Map.get(st, :damage)),
      conditions: body.conditions,
      morale: Map.get(st, :morale),
      int: Map.get(st, :int),
      hd: Map.get(st, :hd),
      level: Map.get(st, :level) || Map.get(st, :hd) || 1,
      xp: Map.get(st, :xp) || 0,
      class: Map.get(st, :class),
      race: Map.get(st, :race),
      armor: Map.get(st, :armor),
      weapons: Map.get(st, :weapons),
      inventory: Map.get(st, :inventory),
      spells: Map.get(st, :spells),
      prayers: Map.get(st, :prayers)
    }
  end

  defp format_damage(%{dice: dice, sides: sides, plus: plus}) when plus > 0,
    do: "#{dice}d#{sides}+#{plus}"

  defp format_damage(%{dice: dice, sides: sides}), do: "#{dice}d#{sides}"
  defp format_damage(_), do: nil

  defp believed_agents(world, believed) do
    believed
    |> Enum.map(fn id ->
      case World.agent(world, id) do
        nil -> %{id: id, name: id, pc: false}
        agent -> %{id: id, name: agent.name, pc: Map.get(agent, :pc, false)}
      end
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp commitments(agent) do
    agent.commitments
    |> Enum.map(fn c ->
      %{id: c.id, deed: c.deed, status: c.status, priority: c.priority, creditor: c.creditor}
    end)
    |> Enum.sort_by(& &1.id)
  end

  @doc "Stable content reference for audit rows: lowercase md5 hex of the slice term."
  @spec prompt_slice_ref(map()) :: String.t()
  def prompt_slice_ref(slice) do
    :erlang.md5(:erlang.term_to_binary(slice)) |> Base.encode16(case: :lower)
  end

  defp exits(world, place_id) do
    world.edges
    |> Enum.filter(&(&1.from == place_id))
    |> Enum.map(& &1.to)
    |> Enum.sort()
  end

  # Direction-labeled exits for one-click moves (UX spec §4): `label` is the
  # YAML exit direction when present, nil for bare connection lists.
  defp exits_labeled(world, place_id) do
    world.edges
    |> Enum.filter(&(&1.from == place_id))
    |> Enum.map(&%{dir: &1.label, to: &1.to, sealed: &1.sealed})
    |> Enum.sort_by(& &1.to)
  end

  defp visible_items(world, place_id) do
    world.items
    |> Map.values()
    |> Enum.filter(&(&1.place_id == place_id and not Map.get(&1, :is_hidden, false)))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp place_items(world, place_id) do
    world.items
    |> Map.values()
    |> Enum.filter(&(&1.place_id == place_id and not Map.get(&1, :is_hidden, false)))
    |> Enum.map(&%{id: &1.id, name: &1.name})
    |> Enum.sort_by(& &1.id)
  end

  # The mover perceives their own arrival, so `believed` can include the
  # actor; the prose reads as who *else* is here (UX spec §4).
  defp summarize(place, believed, world, actor_id) do
    names =
      believed
      |> Enum.reject(&(&1 == actor_id))
      |> Enum.map(fn about ->
        case World.agent(world, about) do
          nil -> about
          a -> a.name
        end
      end)

    case names do
      [] -> "#{place.name}."
      _ -> "#{place.name}. You believe here: #{Enum.join(names, ", ")}."
    end
  end
end
