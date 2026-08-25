defmodule Referee.Rules.SheetTables do
  @moduledoc """
  Authentic AD&D 1E rules lookup tables for character sheets (PHB pp. 9–30, DMG pp. 61–79):
  - Ability sub-stats (Str, Int, Wis, Dex, Con, Cha, Com)
  - Saving throws by class and level
  - Combat to-hit matrix (AC 10..2)
  - Turning undead table (Cleric / Paladin)
  - Thieving skills percentage table (Thief / Assassin / Monk)
  """

  # 1. Strength (PHB p. 9)
  @spec strength_substats(integer(), integer() | nil) :: map()
  def strength_substats(score, percent \\ nil) do
    score = clamp(score, 3, 19)

    cond do
      score == 18 and is_integer(percent) and percent > 0 ->
        cond do
          percent in 1..50 ->
            %{hit_adj: "+1", dam_adj: "+3", open_doors: "1-3", bend_bars: "20%"}

          percent in 51..75 ->
            %{hit_adj: "+2", dam_adj: "+3", open_doors: "1-4", bend_bars: "25%"}

          percent in 76..90 ->
            %{hit_adj: "+2", dam_adj: "+4", open_doors: "1-4", bend_bars: "30%"}

          percent in 91..99 ->
            %{hit_adj: "+2", dam_adj: "+5", open_doors: "1-4(1)", bend_bars: "35%"}

          percent >= 100 ->
            %{hit_adj: "+3", dam_adj: "+6", open_doors: "1-5(2)", bend_bars: "40%"}
        end

      score <= 3 ->
        %{hit_adj: "-3", dam_adj: "-1", open_doors: "1", bend_bars: "0%"}

      score in 4..5 ->
        %{hit_adj: "-2", dam_adj: "-1", open_doors: "1", bend_bars: "0%"}

      score in 6..7 ->
        %{hit_adj: "-1", dam_adj: "0", open_doors: "1", bend_bars: "0%"}

      score in 8..9 ->
        %{hit_adj: "0", dam_adj: "0", open_doors: "1-2", bend_bars: "1%"}

      score in 10..11 ->
        %{hit_adj: "0", dam_adj: "0", open_doors: "1-2", bend_bars: "2%"}

      score in 12..13 ->
        %{hit_adj: "0", dam_adj: "0", open_doors: "1-2", bend_bars: "4%"}

      score in 14..15 ->
        %{hit_adj: "0", dam_adj: "0", open_doors: "1-2", bend_bars: "7%"}

      score == 16 ->
        %{hit_adj: "0", dam_adj: "+1", open_doors: "1-3", bend_bars: "10%"}

      score == 17 ->
        %{hit_adj: "+1", dam_adj: "+1", open_doors: "1-3", bend_bars: "13%"}

      score == 18 ->
        %{hit_adj: "+1", dam_adj: "+2", open_doors: "1-3", bend_bars: "16%"}

      score >= 19 ->
        %{hit_adj: "+3", dam_adj: "+7", open_doors: "1-5(3)", bend_bars: "50%"}
    end
  end

  # 2. Intelligence (PHB p. 10)
  @spec intelligence_substats(integer()) :: map()
  def intelligence_substats(score) do
    score = clamp(score, 3, 19)

    cond do
      score <= 8 ->
        %{add_lang: "0", know_spell: "—", min_spells: "—", max_spells: "—"}

      score == 9 ->
        %{add_lang: "1", know_spell: "35%", min_spells: "4", max_spells: "6"}

      score == 10 ->
        %{add_lang: "2", know_spell: "40%", min_spells: "5", max_spells: "7"}

      score == 11 ->
        %{add_lang: "2", know_spell: "45%", min_spells: "5", max_spells: "7"}

      score == 12 ->
        %{add_lang: "3", know_spell: "50%", min_spells: "5", max_spells: "7"}

      score == 13 ->
        %{add_lang: "3", know_spell: "55%", min_spells: "6", max_spells: "9"}

      score == 14 ->
        %{add_lang: "4", know_spell: "65%", min_spells: "6", max_spells: "9"}

      score == 15 ->
        %{add_lang: "4", know_spell: "75%", min_spells: "7", max_spells: "11"}

      score == 16 ->
        %{add_lang: "5", know_spell: "85%", min_spells: "7", max_spells: "11"}

      score == 17 ->
        %{add_lang: "6", know_spell: "95%", min_spells: "8", max_spells: "14"}

      score >= 18 ->
        %{add_lang: "7", know_spell: "99%", min_spells: "9", max_spells: "All"}
    end
  end

  # 3. Wisdom (PHB p. 11)
  @spec wisdom_substats(integer()) :: map()
  def wisdom_substats(score) do
    score = clamp(score, 3, 19)

    cond do
      score <= 3 ->
        %{mag_atk_adj: "-3", spell_bonus: "—", spell_failure: "45%"}

      score == 4 ->
        %{mag_atk_adj: "-2", spell_bonus: "—", spell_failure: "35%"}

      score == 5 ->
        %{mag_atk_adj: "-1", spell_bonus: "—", spell_failure: "25%"}

      score in 6..7 ->
        %{mag_atk_adj: "-1", spell_bonus: "—", spell_failure: "15%"}

      score == 8 ->
        %{mag_atk_adj: "0", spell_bonus: "—", spell_failure: "10%"}

      score in 9..12 ->
        %{mag_atk_adj: "0", spell_bonus: "—", spell_failure: "0%"}

      score == 13 ->
        %{mag_atk_adj: "+1", spell_bonus: "+1 1st", spell_failure: "0%"}

      score == 14 ->
        %{mag_atk_adj: "+2", spell_bonus: "+1 1st", spell_failure: "0%"}

      score == 15 ->
        %{mag_atk_adj: "+3", spell_bonus: "+2 1st", spell_failure: "0%"}

      score == 16 ->
        %{mag_atk_adj: "+4", spell_bonus: "+2 1st, +1 2nd", spell_failure: "0%"}

      score == 17 ->
        %{mag_atk_adj: "+4", spell_bonus: "+2 1st, +2 2nd", spell_failure: "0%"}

      score >= 18 ->
        %{mag_atk_adj: "+4", spell_bonus: "+2 1st, +2 2nd, +1 3rd", spell_failure: "0%"}
    end
  end

  # 4. Dexterity (PHB p. 11)
  @spec dexterity_substats(integer()) :: map()
  def dexterity_substats(score) do
    score = clamp(score, 3, 19)

    cond do
      score <= 3 ->
        %{react_adj: "-3", missile_adj: "-3", def_adj: "+4"}

      score == 4 ->
        %{react_adj: "-2", missile_adj: "-2", def_adj: "+3"}

      score == 5 ->
        %{react_adj: "-1", missile_adj: "-1", def_adj: "+2"}

      score == 6 ->
        %{react_adj: "0", missile_adj: "0", def_adj: "+1"}

      score in 7..14 ->
        %{react_adj: "0", missile_adj: "0", def_adj: "0"}

      score == 15 ->
        %{react_adj: "0", missile_adj: "0", def_adj: "-1"}

      score == 16 ->
        %{react_adj: "+1", missile_adj: "+1", def_adj: "-2"}

      score == 17 ->
        %{react_adj: "+2", missile_adj: "+2", def_adj: "-3"}

      score >= 18 ->
        %{react_adj: "+3", missile_adj: "+3", def_adj: "-4"}
    end
  end

  # 5. Constitution (PHB p. 12)
  @spec constitution_substats(integer(), String.t() | nil) :: map()
  def constitution_substats(score, class \\ nil) do
    score = clamp(score, 3, 19)
    warrior? = class in ["Fighter", "Paladin", "Ranger"]

    hp_adj =
      cond do
        score <= 3 -> "-2"
        score in 4..6 -> "-1"
        score in 7..14 -> "0"
        score == 15 -> "+1"
        score == 16 -> "+2"
        score == 17 and warrior? -> "+3"
        score == 17 -> "+2"
        score >= 18 and warrior? -> "+4"
        score >= 18 -> "+2"
      end

    cond do
      score <= 3 ->
        %{hp_adj: hp_adj, system_shock: "35%", resurrect_survival: "40%"}

      score == 4 ->
        %{hp_adj: hp_adj, system_shock: "40%", resurrect_survival: "45%"}

      score == 5 ->
        %{hp_adj: hp_adj, system_shock: "45%", resurrect_survival: "50%"}

      score == 6 ->
        %{hp_adj: hp_adj, system_shock: "50%", resurrect_survival: "55%"}

      score in 7..8 ->
        %{hp_adj: hp_adj, system_shock: "55%", resurrect_survival: "60%"}

      score in 9..10 ->
        %{hp_adj: hp_adj, system_shock: "65%", resurrect_survival: "70%"}

      score in 11..12 ->
        %{hp_adj: hp_adj, system_shock: "75%", resurrect_survival: "80%"}

      score == 13 ->
        %{hp_adj: hp_adj, system_shock: "85%", resurrect_survival: "90%"}

      score == 14 ->
        %{hp_adj: hp_adj, system_shock: "88%", resurrect_survival: "92%"}

      score == 15 ->
        %{hp_adj: hp_adj, system_shock: "90%", resurrect_survival: "94%"}

      score == 16 ->
        %{hp_adj: hp_adj, system_shock: "95%", resurrect_survival: "96%"}

      score == 17 ->
        %{hp_adj: hp_adj, system_shock: "97%", resurrect_survival: "98%"}

      score >= 18 ->
        %{hp_adj: hp_adj, system_shock: "99%", resurrect_survival: "100%"}
    end
  end

  # 6. Charisma (PHB p. 13)
  @spec charisma_substats(integer()) :: map()
  def charisma_substats(score) do
    score = clamp(score, 3, 19)

    cond do
      score <= 3 ->
        %{max_henchmen: "1", loyalty_base: "-30%", react_adj: "-25%"}

      score == 4 ->
        %{max_henchmen: "1", loyalty_base: "-25%", react_adj: "-20%"}

      score == 5 ->
        %{max_henchmen: "2", loyalty_base: "-20%", react_adj: "-15%"}

      score == 6 ->
        %{max_henchmen: "2", loyalty_base: "-15%", react_adj: "-10%"}

      score == 7 ->
        %{max_henchmen: "3", loyalty_base: "-10%", react_adj: "-5%"}

      score == 8 ->
        %{max_henchmen: "3", loyalty_base: "-5%", react_adj: "0%"}

      score in 9..11 ->
        %{max_henchmen: "4", loyalty_base: "0%", react_adj: "0%"}

      score in 12..13 ->
        %{max_henchmen: "5", loyalty_base: "0%", react_adj: "+5%"}

      score in 14..15 ->
        %{max_henchmen: "7", loyalty_base: "+5%", react_adj: "+15%"}

      score == 16 ->
        %{max_henchmen: "8", loyalty_base: "+15%", react_adj: "+25%"}

      score == 17 ->
        %{max_henchmen: "10", loyalty_base: "+20%", react_adj: "+30%"}

      score >= 18 ->
        %{max_henchmen: "15", loyalty_base: "+30%", react_adj: "+35%"}
    end
  end

  # 7. Comeliness (Unearthed Arcana p. 6)
  @spec comeliness_substats(integer()) :: map()
  def comeliness_substats(score) do
    score = clamp(score, 3, 19)

    cond do
      score <= 3 -> %{response: "Repulsive (-25%)"}
      score in 4..5 -> %{response: "Ugly (-15%)"}
      score in 6..8 -> %{response: "Plain (-5%)"}
      score in 9..12 -> %{response: "Normal (0%)"}
      score in 13..15 -> %{response: "Attractive (+10%)"}
      score in 16..17 -> %{response: "Beautiful (+20%)"}
      score >= 18 -> %{response: "Fascinating (+30%)"}
    end
  end

  # 8. Saving Throws (DMG p. 79)
  @spec saving_throws(String.t(), integer()) :: map()
  def saving_throws(class, level) do
    lvl = max(level, 1)

    case class do
      c when c in ["Fighter", "Paladin", "Ranger"] ->
        cond do
          lvl in 1..2 -> %{poison: 14, petrification: 15, wand: 16, breath: 17, spell: 17}
          lvl in 3..4 -> %{poison: 13, petrification: 14, wand: 15, breath: 16, spell: 16}
          lvl in 5..6 -> %{poison: 11, petrification: 12, wand: 13, breath: 13, spell: 14}
          lvl in 7..8 -> %{poison: 10, petrification: 11, wand: 12, breath: 12, spell: 13}
          lvl in 9..10 -> %{poison: 8, petrification: 9, wand: 10, breath: 9, spell: 11}
          lvl in 11..12 -> %{poison: 7, petrification: 8, wand: 9, breath: 8, spell: 10}
          lvl in 13..14 -> %{poison: 5, petrification: 6, wand: 7, breath: 5, spell: 8}
          lvl in 15..16 -> %{poison: 4, petrification: 5, wand: 6, breath: 4, spell: 7}
          true -> %{poison: 3, petrification: 4, wand: 5, breath: 4, spell: 6}
        end

      c when c in ["Cleric", "Druid"] ->
        cond do
          lvl in 1..3 -> %{poison: 10, petrification: 13, wand: 14, breath: 16, spell: 15}
          lvl in 4..6 -> %{poison: 9, petrification: 12, wand: 13, breath: 15, spell: 14}
          lvl in 7..9 -> %{poison: 7, petrification: 10, wand: 11, breath: 13, spell: 12}
          lvl in 10..12 -> %{poison: 6, petrification: 9, wand: 10, breath: 12, spell: 11}
          lvl in 13..15 -> %{poison: 5, petrification: 8, wand: 9, breath: 11, spell: 10}
          true -> %{poison: 4, petrification: 7, wand: 8, breath: 10, spell: 9}
        end

      c when c in ["Magic-User", "Illusionist"] ->
        cond do
          lvl in 1..5 -> %{poison: 14, petrification: 13, wand: 11, breath: 15, spell: 12}
          lvl in 6..10 -> %{poison: 13, petrification: 11, wand: 9, breath: 13, spell: 10}
          lvl in 11..15 -> %{poison: 11, petrification: 9, wand: 7, breath: 11, spell: 8}
          true -> %{poison: 10, petrification: 7, wand: 5, breath: 9, spell: 6}
        end

      c when c in ["Thief", "Assassin"] ->
        cond do
          lvl in 1..4 -> %{poison: 13, petrification: 12, wand: 14, breath: 16, spell: 15}
          lvl in 5..8 -> %{poison: 12, petrification: 11, wand: 12, breath: 15, spell: 13}
          lvl in 9..12 -> %{poison: 11, petrification: 10, wand: 10, breath: 14, spell: 11}
          lvl in 13..16 -> %{poison: 10, petrification: 9, wand: 8, breath: 13, spell: 9}
          true -> %{poison: 9, petrification: 8, wand: 6, breath: 12, spell: 7}
        end

      "Monk" ->
        cond do
          lvl in 1..4 -> %{poison: 13, petrification: 12, wand: 14, breath: 16, spell: 15}
          lvl in 5..8 -> %{poison: 12, petrification: 11, wand: 12, breath: 15, spell: 13}
          lvl in 9..12 -> %{poison: 11, petrification: 10, wand: 10, breath: 14, spell: 11}
          true -> %{poison: 10, petrification: 9, wand: 8, breath: 13, spell: 9}
        end

      _ ->
        %{poison: 14, petrification: 15, wand: 16, breath: 17, spell: 17}
    end
  end

  # 9. Attack To-Hit Matrix (AC 10..2) (DMG p. 74)
  @spec to_hit_matrix(String.t(), integer()) :: %{integer() => integer()}
  def to_hit_matrix(class, level) do
    lvl = max(level, 1)

    thac0 =
      case class do
        c when c in ["Fighter", "Paladin", "Ranger"] ->
          cond do
            lvl <= 2 -> 20
            lvl in 3..4 -> 18
            lvl in 5..6 -> 16
            lvl in 7..8 -> 14
            lvl in 9..10 -> 12
            lvl in 11..12 -> 10
            true -> 8
          end

        c when c in ["Cleric", "Druid"] ->
          cond do
            lvl <= 3 -> 20
            lvl in 4..6 -> 18
            lvl in 7..9 -> 16
            lvl in 10..12 -> 14
            true -> 12
          end

        c when c in ["Thief", "Assassin", "Monk"] ->
          cond do
            lvl <= 4 -> 20
            lvl in 5..8 -> 19
            lvl in 9..12 -> 16
            true -> 14
          end

        _ -> # Magic-User, Illusionist
          cond do
            lvl <= 5 -> 20
            lvl in 6..10 -> 19
            lvl in 11..15 -> 16
            true -> 13
          end
      end

    Map.new(10..2//-1, fn ac -> {ac, thac0 - ac} end)
  end

  # 10. Turning Undead Table (DMG p. 65)
  @spec turning_table(integer()) :: map()
  def turning_table(level) do
    lvl = max(level, 1)

    case lvl do
      1 ->
        %{skeleton: "10", zombie: "13", ghoul: "16", shadow: "19", wight: "20", ghast: "—", wraith: "—", mummy: "—", spectre: "—", vampire: "—", ghost: "—", lich: "—"}

      2 ->
        %{skeleton: "7", zombie: "10", ghoul: "13", shadow: "16", wight: "19", ghast: "20", wraith: "—", mummy: "—", spectre: "—", vampire: "—", ghost: "—", lich: "—"}

      3 ->
        %{skeleton: "4", zombie: "7", ghoul: "10", shadow: "13", wight: "16", ghast: "19", wraith: "20", mummy: "—", spectre: "—", vampire: "—", ghost: "—", lich: "—"}

      4 ->
        %{skeleton: "T", zombie: "4", ghoul: "7", shadow: "10", wight: "13", ghast: "16", wraith: "19", mummy: "20", spectre: "—", vampire: "—", ghost: "—", lich: "—"}

      5 ->
        %{skeleton: "T", zombie: "T", ghoul: "4", shadow: "7", wight: "10", ghast: "13", wraith: "16", mummy: "19", spectre: "20", vampire: "—", ghost: "—", lich: "—"}

      _ ->
        %{skeleton: "D", zombie: "T", ghoul: "T", shadow: "4", wight: "7", ghast: "10", wraith: "13", mummy: "16", spectre: "19", vampire: "20", ghost: "—", lich: "—"}
    end
  end

  # 11. Thieving Skills Table (PHB p. 28)
  @spec thieving_skills(String.t(), integer(), String.t(), integer()) :: map()
  def thieving_skills(_class, level, race, dex) do
    lvl = max(level, 1)

    {base_pp, base_ol, base_ft, base_ms, base_hs, base_hn, base_cw, base_rl} =
      case lvl do
        1 -> {30, 25, 20, 15, 10, 10, 85, 0}
        2 -> {35, 29, 25, 21, 15, 10, 86, 0}
        3 -> {40, 33, 30, 27, 20, 15, 87, 0}
        4 -> {45, 37, 35, 33, 25, 15, 88, 20}
        5 -> {50, 42, 40, 40, 31, 20, 90, 25}
        6 -> {55, 47, 45, 47, 37, 20, 92, 30}
        7 -> {60, 52, 50, 55, 43, 25, 94, 35}
        _ -> {65, 57, 55, 62, 49, 25, 96, 40}
      end

    # Dex modifiers
    {d_pp, d_ol, d_ft, d_ms, d_hs} =
      cond do
        dex >= 18 -> {10, 15, 5, 10, 10}
        dex == 17 -> {5, 10, 0, 5, 5}
        dex == 16 -> {0, 5, 0, 0, 0}
        dex <= 9 -> {-15, -10, -10, -20, -10}
        true -> {0, 0, 0, 0, 0}
      end

    # Racial modifiers
    {r_pp, r_ol, r_ft, r_ms, r_hs, r_hn, r_cw, r_rl} =
      case race do
        "Dwarf" -> {0, 10, 15, 0, 0, 0, -10, 0}
        "Elf" -> {5, -5, 0, 5, 10, 5, 0, 0}
        "Gnome" -> {0, 5, 10, 5, 5, 5, -15, 0}
        "Half-Elf" -> {10, 0, 0, 0, 5, 0, 0, 0}
        "Halfling" -> {5, 5, 5, 10, 10, 5, -15, -5}
        "Half-Orc" -> {-5, 5, -5, 0, 0, 5, 5, 0}
        _ -> {0, 0, 0, 0, 0, 0, 0, 0}
      end

    pp = clamp_pct(base_pp + d_pp + r_pp)
    ol = clamp_pct(base_ol + d_ol + r_ol)
    ft = clamp_pct(base_ft + d_ft + r_ft)
    ms = clamp_pct(base_ms + d_ms + r_ms)
    hs = clamp_pct(base_hs + d_hs + r_hs)
    hn = clamp_pct(base_hn + r_hn)
    cw = clamp_pct(base_cw + r_cw)
    rl = if base_rl > 0, do: "#{clamp_pct(base_rl + r_rl)}%", else: "—"

    %{
      pick_pockets: "#{pp}%",
      open_locks: "#{ol}%",
      find_traps: "#{ft}%",
      move_silently: "#{ms}%",
      hide_in_shadows: "#{hs}%",
      hear_noise: "#{hn}%",
      climb_walls: "#{cw}%",
      read_languages: rl
    }
  end

  defp clamp(n, min, _max) when is_integer(n) and n < min, do: min
  defp clamp(n, _min, max) when is_integer(n) and n > max, do: max
  defp clamp(n, _min, _max) when is_integer(n), do: n
  defp clamp(_, min, _max), do: min

  defp clamp_pct(n) when n < 0, do: 0
  defp clamp_pct(n) when n > 99, do: 99
  defp clamp_pct(n), do: n
end
