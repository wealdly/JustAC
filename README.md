# JustAC - Just Assisted Combat

A World of Warcraft addon that displays Blizzard's Assisted Combat spell suggestions with your keybinds, making it easier to follow the rotation helper without hunting for buttons.

![WoW Interface](https://img.shields.io/badge/Interface-11.0.7-blue)
![Version](https://img.shields.io/badge/Version-2.7-green)
![License](https://img.shields.io/badge/License-MIT-brightgreen)

## What It Does

JustAC reads Blizzard's built-in Combat Assistant suggestions (`C_AssistedCombat` API) and displays them as a clean icon queue with your actual keybinds overlaid. The addon:

- Shows the next recommended spell prominently with your keybind
- Displays upcoming rotation spells in a queue
- Filters redundant suggestions (active buffs, current forms, existing pets)
- Finds your keybinds even when spells are inside macros with conditionals
- Supports Masque for icon skinning

## Installation

1. Download and extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Acknowledgments & Inspiration

JustAC wouldn't exist without the incredible work of the WoW addon community. Heartfelt thanks to:

### Libraries

**[Ace3](https://www.wowace.com/projects/ace3)** — The foundational addon framework. AceAddon, AceDB, AceConfig, AceConsole, AceEvent, AceTimer, AceGUI. Created and maintained by the WoWAce community. The backbone that makes addon development manageable.

**[LibStub](https://www.wowace.com/projects/libstub)** — Library versioning system by Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, and others. The glue that lets libraries coexist peacefully.

**[CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler)** — Event callback system by the Ace3 Development Team. Clean event handling without the boilerplate.

**[LibPlayerSpells-1.0](https://github.com/Adirelle/LibPlayerSpells-1.0)** — Spell metadata library by **Adirelle**. Provides rich spell classification data (auras, cooldowns, pets, etc.). Essential for the redundancy filter's intelligent spell detection. Licensed under GPL v3.

### Optional Integrations

**[Masque](https://github.com/SFX-WoW/Masque)** — Button skinning library by **StormFX**. Allows JustAC icons to match your UI's button theme. Beautiful, flexible, and well-documented.

### Blizzard

**Blizzard Entertainment** — For the Combat Assistant system. The `C_AssistedCombat` API powers this entire addon. JustAC simply presents what Blizzard's system suggests.

### Inspiration

The WoW addon community's decades of innovation in action bar addons, rotation helpers, and UI frameworks. Special appreciation to:

- **WeakAuras** — For showing what's possible with custom displays
- **Hekili** — For demonstrating rotation helper UX patterns
- **Bartender4** — For action bar architecture insights
- **OmniCC** — For cooldown display techniques

### Animation & Visual Effects

The marching ants glow effect and proc animations draw inspiration from Blizzard's native `SpellActivationOverlay` system and the community's various glow implementations.

## Technical Notes

- **12.0+ Compatible** — Uses only safe, non-tainted APIs
- **Modular Architecture** — 10 LibStub modules with clear separation of concerns
- **Event-Driven** — Minimal polling, responds to game events
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

MIT License - See [LICENSE](LICENSE) for details.

The embedded libraries retain their original licenses (Ace3 and related libraries are typically public domain or BSD-style licensed).

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
