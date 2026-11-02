# BV Addon Suite

Installable addon files for BV Addon Suite. Every module has its own version
and states the oldest Core it works with.
The table lists the release version of each installable module.

## Versions

| Folder | Version |
| --- | --- |
| `BVAddonSuite` | 0.8.117 |
| `BVAddonSuite_AuraStudio` | 0.8.94 |
| `BVAddonSuite_Experience` | 0.8.94 |
| `BVAddonSuite_Reputation` | 0.8.90 |
| `BVAddonSuite_Bags` | 0.8.116 |
| `BVAddonSuite_MicroMenu` | 0.8.91 |
| `BVAddonSuite_Loot` | 0.8.97 |
| `BVAddonSuite_CombatText` | 0.7.15 |
| `BVAddonSuite_Quest` | 0.1.6 |
| `BVAddonSuite_Map` | 0.2.10 |
| `BVAddonSuite_Routing` | 0.1.11 |
| `BVAddonSuite_Codex` | 0.1.5 |
| `BVAddonSuite_QuestNavigation` | 0.1.2 |
| `BVAddonSuite_Gather` | 0.2.5 |
| `BVAddonSuite_GatherData` | 0.1.2 |
| `BVAddonSuite_MapData` | 0.1.2 |
| `BVAddonSuite_Chat` | 0.1.18 |

## Installation

Copy the desired addon folders directly into your compatible WoW client's
`Interface/AddOns` directory:

- `BVAddonSuite`: required shared core.
- `BVAddonSuite_AuraStudio`: AuraStudio graph editor and runtime.
- `BVAddonSuite_Experience`: optional experience module with a level-up card and a
  class trainer reminder.
- `BVAddonSuite_Reputation`: optional reputation module.
- `BVAddonSuite_Bags`: inventory categories, stack grouping, reagent counters and a configurable bag bar. The inventory and the bar can be enabled independently.
- `BVAddonSuite_Chat`: mix tabs in one timeline, choose public channels and color messages by source or sender. Open it with `/bvchat`.
- `BVAddonSuite_MicroMenu`: optional micro menu module (disabled by default).
- `BVAddonSuite_Loot`: optional loot module: roll bars, loot monitor, roll results
  and master loot window with roll requests (disabled by default, `/bv loot`).
- `BVAddonSuite_CombatText`: optional floating combat text with own styles, anchors,
  nameplates and animations (disabled by default, `/bv sct`).
- `BVAddonSuite_Quest`: optional quest log beside the world map, focus tracker and
  dungeon banner (disabled by default, `/bv quest`).
- `BVAddonSuite_Map`: optional world map extras: coordinates, fading, waypoints,
  terrain map, search and zone banner (disabled by default, `/bv map`).
- `BVAddonSuite_Routing`: ways you can really walk, by flight, ship, zeppelin and
  tram, with a guide (`/bv route`); needs `BVAddonSuite_MapData`.
- `BVAddonSuite_Codex`: search for places (Ctrl + Space). Requires Map Data. Install Routing to follow a tour.
- `BVAddonSuite_QuestNavigation`: leads you to quest objectives and turn-ins, spot by
  spot (`/bv questnav`); needs Quest, Routing and the Questie addon.
- `BVAddonSuite_Gather`: herbs, ore and routes with gather mode, HUD, tracker and
  minimap scanner. The tracker values gathered items using TradeSkillMaster, Auctionator, Blackthornes Tradeskills or vendor prices. Requires Routing (disabled by default, `/bv gather`).
- `BVAddonSuite_GatherData`: known herb and ore spawn points for Gather (GPL-2.0 data).
- `BVAddonSuite_MapData`: NPCs, services and dungeon entrances for Routing and Codex
  (GPL-2.0 data).

For AuraStudio alone, install the core and AuraStudio folders. For the full suite,
install all of them. Do not add another enclosing directory around these folders.
Modules can be updated one by one; keep Core at least at the version a module
requires. Preserve your existing SavedVariables when updating.

## License

Copyright (c) 2026 BlackVortexAI. All rights reserved.

The addon is free to use. Modifications are allowed for private use only.
Publishing or redistributing this addon or any part of it requires explicit
permission. See [LICENSE](LICENSE) for the full terms.

Bundled third-party libraries, fonts and symbols keep their own licenses; their
notices are included with them.
