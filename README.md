# JustAC - Just Assisted Combat

A World of Warcraft addon that displays Blizzard's Assisted Combat spell suggestions with your keybinds, making it easier to follow the rotation helper without hunting for buttons.

## Features

### Where it shows

- **Main Queue** - a draggable panel: icon count, size, spacing and direction are yours to set, and it can dock to the target frame.
- **Nameplate Queue** - the same queue attached to your target's nameplate, with its own settings. Falls back to the main queue when the nameplate isn't on screen.
- Run either or both. Each has a **Show in** setting for the content it appears in (open world, delves and scenarios, dungeons, raids, PvP), so you can keep the queue for dungeons and hide it in raids.
- **Resource bar** (optional, per surface) - your primary power plus a segmented bar for combo points, runes, chi, holy power, soul shards or essence.

### Damage queue

- The **first slot** is the game's own Assisted Combat pick, with your keybind. A spell you've hidden is replaced by the next one the game would suggest.
- The **queue** after it is ordered by the **Priority** you choose - the game's order, the theorycraft (SimulationCraft) order, or your own list - and re-ranked for the fight in front of you: area abilities rise for a pack, abilities you can't use right now (out of range, wrong form, not in stealth, missing their proc) drop to the back, and procs come first.
- **DoT awareness** - a damage-over-time effect already on your target steps back until it's time to refresh. When the game keeps recommending one that's already up, an arrow on the first slot suggests spreading it to another enemy.
- **Burst-ready cue** - your major cooldown glows purple when a burst window is actually called for, not merely when it's off cooldown, and moves up to the second slot. Trigger lists come from SimulationCraft per spec and can be edited under DPS Queue → Burst.
- **Gap-closers** - melee specs get a movement ability suggested when the target is out of range (DPS Queue → Gap-Closers).
- **Ability markers** - a dot marks abilities you can cast while moving, and (optionally) abilities that don't trigger the global cooldown.
- Spells, trinkets and on-use items are all supported. Icons grey out during casts and channels so you can see what's next.

### Priority

- **Three orders, one queue** - tabs show the game's order, the theorycraft order and your own list, one line per ability with what it waits for. Looking at a tab never changes the queue; **Use This Order** does, and a green dot marks the one in use.
- **Your own list** (per spec) - start from **Export to My List** or **Merge** from another tab, then drag rows to reorder. Click a row for its settings, right-click to open it on the Overrides tab, and undo the last ten changes. If the game's rotation changes later, **Merge Changes** brings your list up to date without reordering it.
- **Who leads** - the first slot is the game's by default. **Fill the gaps** lets the queue use it only while the game has nothing to recommend; **Replace with my list** gives it to your list's first ready entry.
- **Ordering** - Procs first, Unavailable last, and **Use my order exactly** to turn off re-ranking for the fight.
- Per ability: **Always Show** keeps it from being filtered out, and **Hold Until** parks it at the back until it's fully charged.
- Talent variants of the same ability are recognised, so a list survives a talent swap.
- **`/jac why <spell>`** explains why an ability is or isn't showing right now.

### Disruption slot

The slot ahead of the damage queue, for anything that stops what the enemy is doing. Each part can be turned on or off on its own.

- **Interrupts** when your target is casting, optionally only for casts the game marks as important. Hidden on casts that can't be interrupted.
- **Crowd control** on unimportant casts, saving your interrupt for dangerous ones. Knows which crowd control works on which creature type, and which targets are immune.
- **Enrage cleanses** - when an enemy enrages and you carry a dispel for it (Soothe, Tranquilizing Shot, Shiv and the like), it shows here with a green glow.
- Works with the default nameplates and with nameplate addons that keep a compatible cast bar.

### Defensives

- **Your defensive list** - self-heals and major cooldowns in one list with per-spec defaults, arranged the same way as the damage priority. Pet rez/summon and pet heal have lists of their own.
- **Help Your Group** - party-wide buttons (Rallying Cry, Darkness, Anti-Magic Zone, Vampiric Embrace and the like) in a list of their own, offered when your group could use the help or your own health is low.
- **Emergency heals held until you need them** *(on by default)* - immunity bubbles, big instant heals and health potions wait at the end of the queue with a WAIT tag while you're healthy. Damage-reduction cooldowns stay live, since a wall is meant to be pressed before the hit lands.
- The order follows how much trouble you're in: damage reduction first while you're taking damage, big heals after a real hit, bubbles only when you're close to dying.
- **Best healing potion** - picks the potion you're carrying that heals you most.
- Absorb shields step back while their barrier holds, instead of being suggested into a wasted overwrite.
- Druid defensives that need Bear or Cat Form only show in that form (unless you have Fluid Form).
- Compact health bar for you and your pet.

#### Sustain slot

Ahead of the defensives, for what keeps you contributing rather than what keeps you alive:

- **Tank maintenance** - your spec's mitigation buff (Ignore Pain, Shield of the Righteous, Ironfur, Demon Spikes, Bone Shield) with its time left, a warning ring before it drops and a full glow once it has. Set how early it warns, add an alert sound, and have charge-based buffs glow while every charge is ready. Brewmaster isn't covered yet. Most accurate with the Cooldown Manager's **Tracked Bars** left visible in Edit Mode.
- **Crowd Control Escape** *(experimental, opt-in)* - while you're stunned, rooted or feared and have something ready to break it, the slot shows that button.
- **Pet heal** - Hunters are reminded when their pet is low, in combat too.

### Healers

JustAC isn't a healing addon - keep yours. It covers the other half of the job:

- **Damage priority with your heals filtered out**, so the time between heals still does damage. Every healer spec has its own damage priority.
- **Caster mode** *(per spec, opt-in)* - no melee-range or form-shift suggestions for healers who stay at range.
- **Group heal suggestions** - area heals when several allies are hurt, and your biggest save (Tranquility, Aura Mastery, Healing Tide, Divine Hymn, Restoral, Rewind) when the group is in serious trouble.

### Pre-combat buffs

- Out of combat, the defensive queue shows buffs you're **missing but own** - flask, food, augment rune, weapon enchant, poisons, shields, imbues and the group buffs - as icons you can click to use.
- Group buffs are offered again when a party member is missing one, so one cast covers everyone.
- **Recuperate** *(opt-in)* - offered when you're below your top-off level out of combat.
- Covers every expansion's consumables, so leveling characters are covered too, and weapon enchants match the weapon you have equipped.

### Keybinds and filtering

- Finds your keybind for every suggestion across all action bars, including macros with conditions (`[mod]`, `[form]`, `[spec]`, `[stealth]`, `[combat]`) and transformed spells. Gamepad button icons for Xbox, PlayStation and generic controllers.
- Right-click an icon to set your own hotkey label; icons flash when you press their key.
- Buffs you already have, your current form and a pet that's already out aren't suggested. Abilities that stack keep being suggested while you build stacks.
- **Overrides** tab - hide a spell (or Shift+Right-click it in the queue), change its queue settings, or **take it off your action bars** so the game's assist stops suggesting it too. **Put Back** restores it to the same buttons; macros are never touched.
- Light on your CPU: event-driven, with other players' events filtered out before they reach the addon.

## Installation

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/just-assisted-combat) or extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Configuration

Options are organized into 6 tabs:

| Tab | Purpose |
|-----|--------|
| **General** | Disruption slot (interrupts, enrage cleanse, dangerous-cast warning), input, Blizzard UI integration (action-bar highlight, Cooldown Manager) |
| **Display** | 3 sub-tabs: Main Queue (the draggable surface: layout/docking, DPS icons, defensive icons, appearance), Nameplate Queue (the nameplate surface), and Shared Behavior (highlight mode, ability markers, icon labels) |
| **DPS Queue** | Priority (the game's order, the theorycraft order, or your own list, and who leads), ordering, queue content, burst triggers and cue, gap-closers |
| **Defensive Queue** | 2 sub-tabs: General (the priority lists, Help Your Group, ordering, Sustain slot: tank maintenance, CC escape, pet heal), Pre-Combat Buffs |
| **Overrides** | Everything set on one spell or item: visibility (the blacklist) and taking it off your action bars, queue and item settings, situational sets, hotkey label. Lists everything you've customized; click an entry to open its settings under it |
| **Profiles** | AceDB profiles with automatic per-spec switching |

- **Localization** - English, German, French, Italian, Russian, Spanish (ES/MX), Portuguese (BR), Korean, Simplified/Traditional Chinese

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

**[LibSharedMedia-3.0](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)**  
*Created by Elkano, funkehdude*  
Shared media library that lets addons share and access sound, font, statusbar, and border media. Enables user-expandable interrupt alert sounds via SharedMedia packs.

**[AceGUI-3.0-SharedMediaWidgets](https://www.curseforge.com/wow/addons/ace-gui-3-0-shared-media-widgets)**  
*Created by Yssaril*  
AceGUI dropdown widgets for selecting LibSharedMedia-registered media in AceConfig options panels.

### Optional Integrations

**[Masque](https://github.com/SFX-WoW/Masque)**  
*Created by StormFX*  
Button skinning library that allows JustAC icons to match your UI's button theme. Beautiful, flexible, and well-documented.

### Blizzard Entertainment

For the Combat Assistant system. The `C_AssistedCombat` API powers this entire addon-JustAC simply presents what Blizzard's system suggests in a more accessible format.

### The WoW Addon Community

To everyone who has contributed to wowace.com, curseforge, GitHub discussions, and the countless forum threads that help addon developers learn and grow. Your shared knowledge makes projects like this possible.

---

## Technical Notes

- **Midnight compliant, currently live on 12.1.0** - Built around the secret-value system rather than patched over it: `auraInstanceID` mapping for combat-safe buff detection, `isOnGCD` for cooldown readiness, opaque cooldown pipeline, NeverSecret aura whitelist, fail-open design throughout. `/jac inspect validate` self-tests each of these against a known-correct answer, so a patch that changes the rules reports itself instead of degrading quietly
- **Secret-safe visuals** - Where a combat state is a "secret value" that can't be read or branched on (e.g. cast interruptibility), it's forwarded straight into a display sink (`SetAlphaFromBoolean` / `SetCooldownFromDurationObject`) so the engine renders it without the addon ever seeing the value
- **Taint is fatal around secrets** - Tainted execution cannot read a secret at all, so writing any Lua field on a frame that reads secrets (Blizzard's Cooldown Manager viewers) breaks *Blizzard's* code, not just ours. Reads and widget C methods are safe; mixin methods that store state are not. See [AURA_IDENTITY_12.0.md](Documentation/AURA_IDENTITY_12.0.md)
- **Threshold gates** - The engine evaluates a curve the addon authors against a secret value and returns a secret result; the addon reads only whether that result is *zero*. Nothing is compared, ordered or read in Lua, but the answer to "is this below N" is an ordinary branchable boolean. Health, power and aura/cooldown remaining time all go through the same path, which is what makes graded defensive bands and stack-aware ordering possible in combat. Deliberately scoped to answering *questions*, never recovering values
- **Never-secret signals** - Readable side-channels stand in where even that is unavailable: the low-health vignette (~35% binary), and player `UNIT_HEALTH` *event activity* - out-of-combat regen fires events while below full health and goes silent at full, so the firing itself is a "still recovering" signal even when the payload is secret
- **No External Spell Databases** - Native spell classification (`SpellDB` + generated `Data/` tables: archetypes, categories, base cooldowns & charges, aura stack counts, form/stealth requirements, caster-aura requirements, pure self-buffs, healing items, pre-combat buffs) replaces LibPlayerSpells; tables regenerate per patch from client data exports via `tools/`
- **Modular Architecture** - Lua modules across the `BlizzardAPI`, `UI`, `Options`, `Locales`, and `Data` subdirectories, plus library dependencies, with a clear load/dependency order
- **Event-Driven** - Minimal polling; push-based cooldown/range/usability events mark queues dirty for responsive updates
- **Cache-Smart** - Aggressive caching with proper invalidation (throttled, state-hash, event-driven, instance-scoped patterns)

## Commands

```text
/jac                          - Open options panel
/jac toggle                   - Pause/resume display
/jac debug                    - Toggle debug mode
/jac reset                    - Reset frame position
/jac profile [name|list]      - Switch or list profiles
/jac find [spell]             - Find spell on action bars (defaults to AC suggestion)
/jac why [spell]              - Explain stage by stage why an ability is or isn't showing
/jac hud                      - Toggle the diagnostic HUD
/jac help                     - Every command and inspect topic, with descriptions
```

`/jac inspect <topic>` covers dozens of diagnostics. The list isn't duplicated here - it
lives next to the code it inspects and `/jac help` prints it, so the two can't
drift apart. Three are worth knowing by name if something stops working, because
they separate "the game changed" from "the addon broke":

| Command | Answers |
|---|---|
| `/jac inspect validate` | Did a secrecy rule change, or did one of the techniques the addon relies on stop producing its known-correct answer? `arm` diffs across a combat enter/exit |
| `/jac inspect errors` | Did we start taking Lua errors or taint blocks? Run it after a fight |
| `/jac inspect secrecy` | Which combat values actually read plain vs. hidden, right where you're standing |

## License

GNU General Public License v3 (GPL-3.0-or-later) - See [LICENSE](LICENSE) for details.

The embedded Ace3 libraries retain their original licenses and are clearly marked in `Libs/`.

Notable embedded library licenses:

- **Ace3, LibStub, CallbackHandler** - Public domain / BSD-style
- **LibSharedMedia-3.0** - Public domain
- **AceGUI-3.0-SharedMediaWidgets** - GPL v2 or later

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
