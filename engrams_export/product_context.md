---
identifier: product_context
title: Product Context
created: 2026-08-18T03:30:29Z
---
# Product Context

```json
{
  "content": {
    "campaign_series": "The Shattered Kingdoms",
    "campaign_setting": {
      "atmosphere": "Worried villagers, disappearing livestock, mysterious lights on the hill",
      "location": "Village of Thornhollow, small farming community",
      "season": "Late autumn, harvest time"
    },
    "canonical_documents": {
      "adventure": "the-ruined-tower/README.md",
      "adventure_game_state": "the-ruined-tower/ruined_tower.yaml",
      "campaign_arc": "Aeldoroth/campaign-arc-shadow-crystal.md",
      "lore": "Aeldoroth/world-guide-shattered-kingdoms.md",
      "map_spec": "Aeldoroth/regions-quick-reference.md",
      "rules_reference": "Aeldoroth/gameplay-reference.md"
    },
    "canonical_history": "Alternative History (Titan/Shadow focus)",
    "current_age": "The Age of Reclamation",
    "current_status": "Authored and ready to play as of 2026-08-17: no sessions run, session log empty, all enemies alive, no treasure collected",
    "difficulty": "Balanced for level 1, deadly if played recklessly",
    "dm_philosophy": [
      "Old-school D&D - challenging but fair",
      "Player skill > character stats (reward creativity)",
      "Reward specific descriptions over dice rolls",
      "Real death risk but avoidable with smart play",
      "XP: 1 gp = 1 XP, bonus for exceptional play, +10% for creative monster removal"
    ],
    "dungeon_overview": {
      "current_threat": "Goblins moved in 2 weeks ago, using as base for raids. Led by Grisk the Snatcher.",
      "history": "Built ~40 years ago by Vaelith the Mirage-Weaver (master illusionist). Tower collapsed in magical accident ~30 years ago. Vaelith disappeared (presumed dead). Abandoned until recently.",
      "name": "The Ruined Tower",
      "structure": "6 rooms across 2 levels (ground floor partially collapsed, lower level intact)"
    },
    "essential_equipment": [
      "10-foot pole (detect pit)",
      "Rope",
      "Torches/lantern",
      "Thieves' tools",
      "Chalk"
    ],
    "expected_duration": "2-3 sessions (3-4 hours each)",
    "future_hooks": [
      "Who was Vaelith really? What caused the tower collapse?",
      "More of Vaelith's treasures/knowledge hidden elsewhere?",
      "Where did goblins come from? Part of larger tribe?",
      "Other ruins or dungeons in the region?",
      "Thornhollow becomes home base for further adventures",
      "Mirage's connection to Vaelith's legacy develops",
      "Goblin revenge attack if any escaped?"
    ],
    "historical_framework": "Age of Titans → Age of Ascension → Age of Shadow (The Darkening) → Age of Reclamation (current)",
    "hook": "Livestock disappearing from Thornhollow over past two weeks. Strange lights at old wizard tower ruins. Mayor Grevik offers 100 gp to investigate and stop the threat.",
    "initialized": "2025-12-27T17:26:00Z",
    "journal_clue_expanded": "Water-damaged journal page in Room 2 library contains partially legible dual clues: (1) Treasure cache hint: 'third stone behind... crate from town... hidden...' points to hidden wall cache in Room 5. (2) Secret chamber hint: 'Lux Memoriae... ritual circle... Talven remains...' reveals password for secret door and hints at ritual chamber below.",
    "key_npcs": {
      "antagonists": [
        "Grisk the Snatcher (goblin chief)",
        "~7 goblins total",
        "2 Wolves"
      ],
      "historical": [
        "Vaelith the Mirage-Weaver (deceased illusionist)"
      ],
      "objectives": [
        "Willem (kidnapped farmer, rescue target)"
      ],
      "quest_givers": [
        "Mayor Grevik",
        "Erik the Shepherd"
      ],
      "support": [
        "Mara (innkeeper)",
        "Jorren (supplies)",
        "Sister Aldara (healing)"
      ]
    },
    "naming_convention": "Aeldoroth is the world/realm setting. The Shattered Kingdoms is the AD&D campaign series taking place within Aeldoroth during the Age of Reclamation.",
    "primary_themes": [
      "Investigation and dungeon crawl",
      "Legacy of a dead wizard (Vaelith)",
      "Trap awareness and careful exploration"
    ],
    "project_type": "AD&D 1E campaign series 'The Shattered Kingdoms' in the world of Aeldoroth; starter adventure: The Ruined Tower (Thornhollow)",
    "rewards_summary": {
      "gold_per_character": "180-200 gp if treasure split evenly",
      "magic_items": [
        "Illusionist's Spellbook (Invisibility, Mirror Image)",
        "+1 Dagger",
        "Spell Scroll",
        "Healing Potion"
      ],
      "quest_rewards": "100 gp from Mayor + ~20 gp from farmer's family",
      "total_xp": "~875 XP (219 per character in 4-person party)"
    },
    "rooms": {
      "room_1": "Entry Hall - Collapsed entrance, alarm tripwire trap",
      "room_2": "Library - 3 Giant Rats, healing potion, illusionist's spellbook, journal page with dual clues (treasure cache + secret door)",
      "room_3": "Guard Room - 4 Goblins, caltrops trap, 40 gp",
      "room_4": "Prison Cells - Kidnapped farmer Willem (rescue objective), bell tripwire",
      "room_5": "Chief's Room (Vaelith's old supply room) - Goblin Chief + 2 Guards, pit trap, false cache needle trap, major treasure including hidden wall cache",
      "room_6": "Beast Pen - 2 Wolves (optional)",
      "room_7": "SECRET: Vaelith's Ritual Chamber - Hidden below library, accessed via secret door with password 'Lux Memoriae', contains Shadow-Touched Skeleton (Talven's corpse), reveals Vaelith's shadow magic research and true cause of tower collapse"
    },
    "source_file": "README.md",
    "success_conditions": {
      "exceptional": "+ Creative solutions, memorable moments, party wants to continue",
      "full": "+ Find hidden cache, recover spellbook, detect all traps, no PC deaths",
      "minimum": "Stop goblin raids (kill/drive off goblins)",
      "standard": "+ Rescue Willem, claim obvious treasure, avoid most traps"
    },
    "target_party": "4 level-1 characters (Fighter, Cleric, Illusionist, Thief)",
    "vaelith_backstory_expanded": "Vaelith the Mirage-Weaver wasn't just an illusionist - he was researching the Age of Shadow, attempting to understand and purify shadow corruption from the Darkening. His apprentice Talven volunteered for a ritual 30 years ago. The ritual failed catastrophically, killing Talven and animating his corpse with shadow magic. The magical backlash caused the tower to collapse. Vaelith fled, mad with guilt, and died in the wilderness. The secret ritual chamber remained sealed until potentially discovered by the party.",
    "workspace_layout": {
      "Aeldoroth/": "Campaign-series canon: world guide, campaign arc (Shadow Weaver Cult), regions map spec, AD&D 1E DM quick reference",
      "engrams/": "engrams memory DB (context.db) - canonical campaign memory",
      "shards-of-dimwood/": "Act 3 seed fragments (citadel dungeon, treasurer's vault scenes; README.md and traps.md currently empty)",
      "the-ruined-tower/": "Starter adventure: README (authoritative overview), ruined_tower.yaml (game state), npc.md, traps.md, xp-reference.md, treasure-checklist.md, images/",
      "the-ruined-tower/context_portal/": "Legacy Context Portal backup (context-backup.db); migrated into engrams 2026-08-17"
    },
    "world_connection": "The ritual chamber directly connects The Ruined Tower to The Shattered Kingdoms' history of the Age of Shadow and the Darkening. Vaelith's failed shadow purification ritual echoes the larger catastrophic magical failures that shattered the kingdoms. Evidence in chamber (letter from Master Gearheart) connects to gnome Rekindlers and the Underhearth.",
    "world_name": "Aeldoroth",
    "world_tone": "Dark fantasy with hope; cosmic horror elements; emphasis on light vs shadow; adventurers as essential heroes; undead and demons still threaten",
    "years_since_darkening": "~100 years"
  },
  "updated_at": "2026-08-18T03:30:29Z",
  "version": 1
}
```
