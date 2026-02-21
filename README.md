# JustAC - Just Assisted Combat

A World of Warcraft addon that displays Blizzard's Assisted Combat spell suggestions with your keybinds, making it easier to follow the rotation helper without hunting for buttons.

## What It Does

JustAC reads Blizzard's built-in Combat Assistant suggestions (`C_AssistedCombat` API) and displays them as a clean icon queue with your actual keybinds overlaid. The addon:

- Shows the next recommended spell prominently with your keybind
- Displays upcoming rotation spells in a queue
- Filters redundant suggestions (active buffs, current forms, existing pets)
- Finds your keybinds even when spells are inside macros with conditionals
- Handles spell transformations (talent overrides, combat morphs) with cached slot lookups
- Supports gamepad/controller button icons (Xbox, PlayStation, Generic styles)
- Supports Masque for icon skinning

## Features

### Dual Display Modes

- **Standard Queue** — Draggable panel with configurable icon count, spacing, and orientation (left/right/up/down). Optional target frame anchoring.
- **Nameplate Overlay** — Icon cluster attached directly to the target nameplate. Fully independent settings. Either or both modes can run simultaneously.

### Smart Interrupt Reminders

- Shows your interrupt ability before the DPS queue when the target is casting
- **Important Only** mode filters to lethal/must-interrupt casts (`C_Spell.IsSpellImportant`)
- **CC Non-Important Casts** — Uses stuns/incapacitates on trash mobs, saving true interrupt lockout for dangerous casts
- Boss-aware: CC abilities automatically filtered against CC-immune targets

### Defensive Suggestions

- Two-tier health-based system: self-heals at ~80% HP, major cooldowns at ~60% HP
- Procced defensives (Victory Rush, free heals) shown at any health level
- Pet rez/summon and pet heal support for Hunter, Warlock, Death Knight
- Compact health bar (player + pet) with automatic resize
- Items supported (potions, healthstones) with auto-detection from action bars

### Smart Hotkey Detection

- Scans all action bars to find your keybinds for any spell
- Parses macro conditionals (`[mod]`, `[form]`, `[spec]`, `[stealth]`, `[combat]`)
- Handles dynamic spell transforms (e.g. Templar Strike → Templar Slash) via override scanning
- Gamepad support with Xbox/PlayStation/Generic button icon styles
- Custom hotkey overrides via right-click menu

### Intelligent Filtering

- Hides redundant suggestions (buffs already active, current form, existing pet)
- Per-spell blacklist (Shift+Right-click to toggle)
- Respects class-specific mechanics (Druid forms, Rogue Stealth, etc.)
- Cast-based inference for poisons, weapon imbues, and long-duration buffs in 12.0 combat

### Performance Optimized

- Event-driven updates with minimal polling
- Throttled cooldown/range checks (6-7x/sec instead of every frame)
- Pooled table allocation to reduce garbage collection pressure
- Cached spell info, override lookups, and filter results per update cycle
- Gamepad keybind hash computed once, not per-lookup

## Installation

1. Download and extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Configuration

- **Display Mode** — Standard Queue, Nameplate Overlay, Both, or Disabled
- **Interrupt Reminder** — Important Only (default), All Casts, or Off; with optional CC for non-important casts
- **Defensives** — Enable/disable, configure health thresholds, spell priority lists per class
- **Per-Spec Profiles** — Automatic profile switching by specialization; set healer specs to "Disabled"
- **Visibility** — Hide out of combat, when mounted, for healer specs, or without hostile target
- **Localization** — English, German, French, Russian, Spanish (ES/MX), Portuguese (BR), Simplified/Traditional Chinese

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

- **WoW 12.0 Midnight Compliant** — Handles secret values gracefully; fail-open design throughout
- **No External Spell Databases** — Native spell classification (SpellDB) replaces LibPlayerSpells
- **Modular Architecture** — 12 LibStub modules with clear dependency order
- **Event-Driven** — Minimal polling; events mark queues dirty for responsive updates
- **Cache-Smart** — Aggressive caching with proper invalidation (throttled, state-hash, event-driven patterns)

## Commands

```text
/jac            - Open options panel
/jac test       - Run API diagnostics
/jac modules    - Check module health
/jac formcheck  - Debug form detection
/jac find Name  - Locate a spell on action bars
/jac defensive  - Diagnose defensive icon system
```

## License

GNU General Public License v3 (GPL-3.0-or-later) - See [LICENSE](LICENSE) for details.

The embedded Ace3 libraries retain their original licenses and are clearly marked in `Libs/`.

Notable embedded library licenses:

- **Ace3, LibStub, CallbackHandler** — Public domain / BSD-style

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
