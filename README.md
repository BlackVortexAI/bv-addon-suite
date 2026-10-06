# BV Addon Suite

Installable addon files for BV Addon Suite. Every module has its own version
and states the oldest Core it works with.
This development version is undergoing in-game acceptance testing.

## Versions

| Folder | Version |
| --- | --- |
| `BVAddonSuite` | 0.8.94 |
| `BVAddonSuite_AuraStudio` | 0.8.91 |
| `BVAddonSuite_Experience` | 0.8.89 |
| `BVAddonSuite_Reputation` | 0.8.89 |
| `BVAddonSuite_Bags` | 0.8.91 |
| `BVAddonSuite_MicroMenu` | 0.8.89 |
| `BVAddonSuite_Loot` | 0.8.90 |
| `BVAddonSuite_CombatText` | 0.7.1 |

## Installation

Copy the desired addon folders directly into your compatible WoW client's
`Interface/AddOns` directory:

- `BVAddonSuite`: required shared core.
- `BVAddonSuite_AuraStudio`: AuraStudio graph editor and runtime.
- `BVAddonSuite_Experience`: optional experience module.
- `BVAddonSuite_Reputation`: optional reputation module.
- `BVAddonSuite_Bags`: optional bag bar module (disabled by default).
- `BVAddonSuite_MicroMenu`: optional micro menu module (disabled by default).
- `BVAddonSuite_Loot`: optional loot module: roll bars, loot monitor, roll results
  and master loot window with roll requests (disabled by default, `/bv loot`).
- `BVAddonSuite_CombatText`: optional floating combat text with own styles, anchors,
  nameplates and animations (beta, disabled by default, `/bv sct`).

For AuraStudio alone, install the core and AuraStudio folders. For the full suite,
install all eight. Do not add another enclosing directory around these folders.
Modules can be updated one by one; keep Core at least at the version a module
requires. Preserve your existing SavedVariables when updating.

## License

Copyright (c) 2026 BlackVortexAI. All rights reserved.

The addon is free to use. Modifications are allowed for private use only.
Publishing or redistributing this addon or any part of it requires explicit
permission. See [LICENSE](LICENSE) for the full terms.

Bundled third-party libraries, fonts and symbols keep their own licenses; their
notices are included with them.
