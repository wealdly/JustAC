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

### Dual Display Surfaces

- **Standard Queue** — Draggable panel with configurable icon count, spacing, and orientation (left/right/up/down). Optional target frame anchoring. Sub-tabs for Layout, Offensive Display, Defensive Display, and Appearance.
- **Nameplate Overlay** — Icon cluster attached directly to the target nameplate. Mirrors the Standard Queue's sub-tab structure with independent settings. Falls back to the main panel when the nameplate isn't rendered.
- Either or both surfaces can run simultaneously via the Display Mode setting.

### Smart Interrupt Reminders

- Shows your interrupt ability before the DPS queue when the target is casting
- **Important Only** mode filters to lethal/must-interrupt casts (`C_Spell.IsSpellImportant`)
- **CC Non-Important Casts** — Uses stuns/incapacitates on trash mobs, saving true interrupt lockout for dangerous casts
- Boss-aware: CC abilities automatically filtered against CC-immune targets (with instance-level NPC immunity cache)
- Third-party nameplate support — auto-discovers cast bars from Plater, ElvUI, and Blizzard nameplates

### Defensive Suggestions

- Unified priority list: self-heals and major cooldowns combined with configurable per-class ordering
- Procced defensives (Victory Rush, free heals) shown at any health level
- Usability-aware visuals: icons grey out while channeling, blue-tint when lacking resources, desaturate on cooldown
- Pet rez/summon and pet heal support for Hunter, Warlock, Death Knight
- Compact health bar (player + pet) with automatic resize
- Items supported (potions, healthstones) with auto-detection from action bars — optional aura linking and combat hiding per item
- Combat-safe health detection via LowHealthFrame signal (~35%) for 12.0 secret-value compatibility

### Gap-Closer Suggestions

- Suggests movement/gap-closer spells when the target is out of melee range
- Injects into the offensive queue for natural flow
- Push-based range detection via `C_ActionBar.EnableActionRangeCheck` for minimal polling

### Burst Injection *(Experimental)*

- Detects burst windows via aura tracking — when a trigger spell's self-buff is active on the player, configured burst spells inject at position 1 with a purple glow
- Trigger spell at position 1 shows glow as a "press to start burst" signal before the window opens
- Timer fallback for triggers that don't create a self-buff (pet summons, target debuffs)
- Per-spec trigger and injection spell lists with class-appropriate defaults
- Configurable fallback window duration
- **Experimental in 12.0**: Aura identity relies on `auraInstanceID` mapping (combat-safe). Works well for self-buff triggers but may miss edge cases. This feature is opt-in and disabled by default.

### Smart Hotkey Detection

- Scans all action bars to find your keybinds for any spell
- Parses macro conditionals (`[mod]`, `[form]`, `[spec]`, `[stealth]`, `[combat]`)
- Handles dynamic spell transforms (e.g. Templar Strike → Templar Slash) via override scanning
- Gamepad support with Xbox/PlayStation/Generic button icon styles
- Custom hotkey overrides via right-click menu
- Key press flash feedback when you press the suggested keybind

### Intelligent Filtering

- Hides redundant suggestions (buffs already active, current form, existing pet)
- Per-spell blacklist (Shift+Right-click to toggle)
- Respects class-specific mechanics (Druid forms, Rogue Stealth, etc.)
- Cast-based inference for poisons, weapon imbues, and long-duration buffs in 12.0 combat
- Combat-safe aura tracking via `auraInstanceID` mapping — detects buff removal and reapply even when `spellId` is secret
- NeverSecret aura whitelist (~50 spells) for direct resolution without instance-map lookup

### Performance Optimized

- Event-driven updates with minimal polling
- Push-based cooldown and range events (`SPELL_UPDATE_COOLDOWN`, `ACTION_RANGE_CHECK_UPDATE`)
- Pooled table allocation to reduce garbage collection pressure
- Cached spell info, override lookups, and filter results per update cycle
- 12.0 opaque cooldown pipeline (`SetCooldownFromDurationObject`) bypasses secret-value handling entirely

## Installation

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/justac) or extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Configuration

Options are organized into 6 tabs:

| Tab | Purpose |
|-----|--------|
| **General** | Display mode, visibility rules, queue content toggles (3 sub-tabs: Settings, Icon Labels, Hotkeys) |
| **Standard Queue** | Layout, offensive display, defensive display, appearance (4 sub-tabs) |
| **Overlay** | Nameplate overlay layout, offensive display, defensive display (3 sub-tabs) |
| **Offensive** | Blacklist, gap-closers, burst injection, interrupt mode |
| **Defensives** | Spell priority list, health thresholds, per-item aura linking |
| **Profiles** | AceDB profiles with automatic per-spec switching |

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

## Known Issues

### Non-interruptible cast detection with nameplate replacement addons

Addons that replace or heavily modify Blizzard's nameplate cast bars (e.g. Platynator) can break JustAC's ability to distinguish interruptible from non-interruptible casts. When this happens, interrupt/CC abilities may be suggested on uninterruptible (shielded) casts.

**Why:** In WoW 12.0, the `notInterruptible` field from `UnitCastingInfo()` is a secret value in combat — addons cannot read it directly. JustAC's only reliable signal is the Blizzard nameplate cast bar's icon visibility (`HideIconWhenNotInterruptible`), which Blizzard resolves internally. Addons that disable or replace that cast bar remove the only working signal.

**Workaround:** Use Blizzard default nameplates, or a nameplate addon that preserves the Blizzard cast bar frame (Plater and ElvUI work correctly). If you use a nameplate addon that fully replaces the cast bar, interrupt suggestions will fail-open (assume interruptible).

### Burst injection cooldown detection

See [Burst Injection *(Experimental)*](#burst-injection-experimental) above. Major cooldown tracking in WoW 12.0 combat relies on local timer estimates which may drift or miss cooldown reduction effects.

---

## Technical Notes

- **WoW 12.0 Midnight Compliant** — Handles secret values gracefully; `auraInstanceID` mapping for combat-safe buff detection; `isOnGCD` for cooldown readiness; opaque cooldown pipeline; NeverSecret aura whitelist; fail-open design throughout
- **No External Spell Databases** — Native spell classification (SpellDB) replaces LibPlayerSpells
- **Modular Architecture** — 36 Lua files across 4 subdirectories (BlizzardAPI, UI, Options, Locales) plus library dependencies with clear dependency order
- **Event-Driven** — Minimal polling; push-based cooldown/range/usability events mark queues dirty for responsive updates
- **Cache-Smart** — Aggressive caching with proper invalidation (throttled, state-hash, event-driven, instance-scoped patterns)

## Commands

```text
/jac              - Open options panel
/jac toggle       - Pause/resume display
/jac debug        - Toggle debug mode
/jac reset        - Reset frame position
/jac profile      - Switch or list profiles
/jac modules      - Check module health
/jac find <spell> - Locate a spell on action bars
/jac burst        - Burst injection diagnostics
/jac testcd       - Test cooldown APIs for a spell
/jac defensive    - Diagnose defensive icon system
/jac poisons      - Diagnose rogue poison detection
/jac help         - Show all commands in-game
```

## License

GNU General Public License v3 (GPL-3.0-or-later) - See [LICENSE](LICENSE) for details.

The embedded Ace3 libraries retain their original licenses and are clearly marked in `Libs/`.

Notable embedded library licenses:

- **Ace3, LibStub, CallbackHandler** — Public domain / BSD-style

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
