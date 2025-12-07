# JustAC - Just Assisted Combat

A World of Warcraft addon that displays Blizzard's Assisted Combat spell suggestions with your keybinds, making it easier to follow the rotation helper without hunting for buttons.

## What It Does

JustAC reads Blizzard's built-in Combat Assistant suggestions (`C_AssistedCombat` API) and displays them as a clean icon queue with your actual keybinds overlaid. The addon:

- Shows the next recommended spell prominently with your keybind
- Displays upcoming rotation spells in a queue
- Filters redundant suggestions (active buffs, current forms, existing pets)
- Finds your keybinds even when spells are inside macros with conditionals
- Handles spell transformations (Hot Streak, etc.) with cached slot lookups
- Supports Masque for icon skinning

## Features

### Smart Hotkey Detection

- Scans action bars to find your keybinds for any spell
- Parses macro conditionals (`[mod]`, `[form]`, `[spec]`, etc.)
- Caches spell→slot mappings for instant transform lookups

### Intelligent Filtering

- Hides redundant suggestions (buffs already active, current form, existing pet)
- Filters completed defensive cooldowns
- Respects class-specific mechanics (Druid forms, Rogue Stealth, etc.)

### Performance Optimized

- Event-driven updates with minimal polling
- Smart cache invalidation (only rescans when necessary)
- Instant sync via `AssistedCombatManager.OnSetActionSpell` callback

## Installation

1. Download and extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Acknowledgments & Credits

JustAC wouldn't exist without the incredible work of the WoW addon community. Heartfelt thanks to:

### Libraries

**[Ace3 Framework](https://www.wowace.com/projects/ace3)**  
*Created by the WoWAce Community*  
The foundational addon framework powering AceAddon, AceDB, AceConfig, AceConsole, AceEvent, AceTimer, and AceGUI. The backbone that makes modern addon development manageable.

**[LibStub](https://www.wowace.com/projects/libstub)**  
*Created by Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke*  
Library versioning system. The glue that lets libraries coexist peacefully. Public domain.

**[CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler)**  
*Maintained by Nevcairiel and the Ace3 Team*  
Clean event callback system without the boilerplate.

**[LibPlayerSpells-1.0](https://github.com/Adirelle/LibPlayerSpells-1.0)**  
*Created by Adirelle*  
Spell metadata library providing rich spell classification data (auras, cooldowns, pets, survival, etc.). Essential for intelligent redundancy filtering and defensive spell detection. Licensed under GPL v3.

### Optional Integrations

**[Masque](https://github.com/SFX-WoW/Masque)**  
*Created by StormFX*  
Button skinning library that allows JustAC icons to match your UI's button theme. Beautiful, flexible, and well-documented.

### Blizzard Entertainment

For the Combat Assistant system. The `C_AssistedCombat` API powers this entire addon—JustAC simply presents what Blizzard's system suggests in a more accessible format.

### Inspiration & Learning

The WoW addon community's decades of innovation in action bar addons, rotation helpers, and UI frameworks:

- **WeakAuras** by *Mirrored and the WeakAuras Team* — For showing what's possible with custom displays
- **Hekili** by *Hekili* — For demonstrating rotation helper UX patterns
- **Bartender4** by *Nevcairiel* — For action bar architecture insights
- **OmniCC** by *Tuller* — For cooldown display techniques
- **TellMeWhen** by *Cybeloras* — For icon-based notification patterns

### The WoW Addon Community

To everyone who has contributed to wowace.com, curseforge, GitHub discussions, and the countless forum threads that help addon developers learn and grow. Your shared knowledge makes projects like this possible.

---

## Technical Notes

- **12.0+ Compatible** — Uses only safe, non-tainted APIs
- **Modular Architecture** — 10 LibStub modules with clear separation of concerns
- **Event-Driven** — Minimal polling, responds to game events for proc detection
- **Cache-Smart** — Aggressive caching with proper invalidation

## Commands

```text
/jac           - Open options panel
/jac test      - Run API diagnostics
/jac modules   - Check module health
/jac formcheck - Debug form detection
/jac find Name - Locate a spell on action bars
```

## License

GNU General Public License v3 (GPL-3.0-or-later) - See [LICENSE](LICENSE) for details.

This addon contains a bundled copy of LibPlayerSpells-1.0 which is licensed under GPLv3. To comply with the terms of that library, the combined distributed addon is licensed under the GNU GPL v3 (or later). The embedded libraries retain their original licenses and are clearly marked in `Libs/`.

Notable embedded library licenses:

- **Ace3, LibStub, CallbackHandler** — Public domain / BSD-style
- **LibPlayerSpells-1.0** — GNU GPL v3

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
