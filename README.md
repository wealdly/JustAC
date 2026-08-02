# JustAC - Just Assisted Combat

A World of Warcraft addon that displays Blizzard's Assisted Combat spell suggestions with your keybinds, making it easier to follow the rotation helper without hunting for buttons.

## Features

### Dual Display Surfaces

- **Standard Queue** - Draggable panel with configurable icon count, spacing, and orientation (left/right/up/down). Optional target frame anchoring. Sub-tabs for Layout, Offensive Display, Defensive Display, and Appearance.
- **Nameplate Overlay** - Icon cluster attached directly to the target nameplate. Mirrors the Standard Queue's sub-tab structure with independent settings. Falls back to the main panel when the nameplate isn't rendered.
- Either or both surfaces can run simultaneously via the Display Mode setting.
- **Resource bar** (optional, per surface) - your primary power plus a segmented secondary point resource (combo points, runes, chi, holy power, soul shards, essence). Anchors to the outermost health bar in view; segments render through a display-only path so they stay correct in 12.0 combat.

### Offensive Queue

- The **AC slot** shows the currently recommended ability with your keybind - blacklisted spells auto-substitute via highlight-mode lookahead
- The **queue** (everything after the AC slot) displays Blizzard's priority list with redundancy filtering, cooldown awareness, and optional **Custom Queue** ordering (user-defined spell/item priority per spec)
- **Context-aware ranking** - the queue ranks each ability by how closely it matches the ability Assisted Combat is recommending right now: the nearest target pattern (single-target / melee-AOE / ranged-AOE, with cleave treated as a melee AOE) and the same builder/spender role float to the top, so the alternatives on offer are the best DPS fit for the current situation. Abilities the game won't let you use sink to the back: out-of-range melee, Cat/Bear-only abilities in the wrong form (skipped when Fluid Form makes them castable anywhere), stealth-only openers while unstealthed (Subterfuge/Shadow Dance respected), and abilities missing their enabling buff (e.g. Arcane Missiles without Clearcasting) - procs always outrank the sink. Applies to the Custom Queue too, and is backed by a DB2-generated table (archetype, range, and builder/spender role) covering every class - including damage-over-time abilities. On by default; switch it off in the Rotation tab's ordering toggles to keep a fixed order
- Dynamic insertion of procs and gap-closers (melee specs), a burst-ready cue (purple glow on your spec's major cooldown when it's ready), and a separate icon for interrupts
- **DoT awareness** - a damage-over-time ability already applied to your target sinks to the back of the queue while its debuff is live, reappearing in time to refresh (pandemic window), the moment it drops or is dispelled, or on a target that doesn't have it. When Assisted Combat keeps recommending a DoT that's already up, a switch-target arrow appears on the AC slot as a cue to spread it to another enemy. Stacking DoTs are left alone so you can keep building stacks. On by default; toggle in the General tab
- **SimC priority ordering** *(on by default; specs without imported data fall back to context-aware ranking)* - orders the abilities after Blizzard's pick using SimulationCraft's priority for your spec, re-ranked against what Blizzard is recommending right now (single-target vs. multi-target, building vs. spending). It also reads point-based resources - combo points, holy power, chi, soul shards, runes - so spenders sink until you can afford them and surface as you reach the threshold. Where the amount can't be read, ordering is left untouched rather than guessed. Multi-target abilities stay out of your single-target order, and openers, execute-only casts, interrupts, defensives and movement abilities are kept out of the damage queue entirely
- **Ability markers** - an azure dot marks abilities you can cast while moving; an amber marker (opt-in) marks abilities that don't trigger the global cooldown, so you can fire one and go straight to the next suggestion. Both sit in the lower-left corner and share it when both apply, the dot splitting half azure and half amber. Shown on the offensive and defensive queues alike, on both display surfaces. Configured under General → Shared Behavior
- Spells and on-use items (trinkets, potions) supported throughout the queue
- Icons grey out during hardcasts and channels so you can see what's next at a glance
- Configurable: font attributes, icon count, size, orientation, glow modes, charge counts, and more

### Custom Queue

- Define a custom spell/item ordering for the queue (per spec, stored in profile)
- **Ordering toggles** - Procs First, Context Aware, and Cooldowns Last (all on by default). Turn them off to keep your exact saved order as a fixed queue; they apply to both the Custom Queue and Blizzard's default rotation
- Auto-seeds from Blizzard's rotation on first enable; unavailable or on-cooldown entries collapse automatically
- Stale queue detection warns when Blizzard's rotation changes - "Merge Changes" preserves custom ordering while syncing additions/removals
- Supports trinkets and on-use items alongside spells
- **Talent-proof** - a stored ability whose spell ID belongs to a different talent variant resolves to the version you currently know instead of silently vanishing
- **Always Show** pin per entry - a pinned ability is never hidden by filtering (active buff, running DoT, gap-closer management); it stays in the queue and only steps back while on cooldown or out of range
- **Hold Until Charged** pin per entry - holds an ability at the back of the queue until every charge is banked, so a two-charge ability isn't spent into an overcap. It keeps its place rather than vanishing; an ability without charges is held until it's off cooldown. Off by default, and requires the "Unavailable last" ordering toggle
- **`/jac why <spell>`** - explains exactly why an ability is or isn't showing right now, stage by stage (known, blacklisted, redundant, cooldown, range, DoT state, icon cap)

### Disruption Slot (interrupts, CC, enrage cleanse)

The slot ahead of the DPS queue, holding everything that takes away what the enemy is doing. Each member is independent - you can run the enrage cleanse with interrupt reminders switched off, or the reverse.

- Shows your interrupt ability before the DPS queue when the target is casting
- **Important Only** mode filters to lethal/must-interrupt casts (`C_Spell.IsSpellImportant`)
- **CC Non-Important Casts** - Uses stuns/incapacitates on trash mobs, saving true interrupt lockout for dangerous casts; prefers a stun over a silence when only CC can stop an uninterruptible cast (a silence can't stop a physical channel)
- **Creature-type-aware CC** - won't suggest a type-restricted CC (e.g. Polymorph, Repentance) on a creature type it can't affect; reads the target's type in combat with an account-wide name→type cache as a fallback
- Boss-aware: CC abilities automatically filtered against CC-immune targets (with instance-level NPC immunity cache)
- The interrupt is correctly hidden on casts that can't be interrupted - driven straight from the cast's protected interruptible flag through a display-only path, so it works regardless of which cast-bar or nameplate addon you use. (Auto-substituting a CC for a kick on a non-interruptible cast still needs the Blizzard default cast bar; with a replaced cast bar you simply get no suggestion there instead of a CC - never a wrongly-shown kick)
- **Enrage cleanses** - when an enemy enrages and you carry a dispel that removes it (Soothe, Tranquilizing Shot, Shiv and the like), the dispel surfaces in the Disruption slot with a green glow, named with the enrage it clears. Detected through a display-only colour path, so it works in 12.0 combat without reading the aura. On by default where the spec has one, under General → Disruption → Show Enrage Cleanse
- Nameplate cast-bar support - auto-discovers cast bars from the Blizzard default nameplate and from nameplate addons that expose a compatible frame structure

### Defensive Suggestions

- Unified priority list: self-heals and major cooldowns combined with configurable per-class ordering

#### Sustain Slot

The defensive queue's "position 0", holding what keeps you *contributing* rather than what keeps you alive - a lapsed mitigation buff, a stun and a dying pet all cost you the same thing. Which member claims it depends on your class and what is happening; they never collide, because the tank buff and the pet cue belong to mutually exclusive classes.

- **Tank maintenance** - tanks get the slot for the one mitigation buff the spec keeps rolling (Shield Block, Shield of the Righteous, Ironfur, Demon Spikes, Bone Shield). It counts down the buff's remaining time, shows the keybind, and greys out when the cast is out of reach or unaffordable. The slot pulses to prompt a refresh (about 3s before decay for a buff that runs on a timer, or once it drops for one spent by damage), and learns the buff's real duration in play so talents that extend it don't fire the cue early. It also adapts per ability: a charge-limited button like Shield Block shows charges and its recharge, while a resource button like Ignore Pain shows the shield remaining. Blood's slot points at Marrowrend, so it can appear in the rotation and here at once. Combat only, tank specs only, on by default under Defensives → Tank Maintenance Slot. Brewmaster isn't covered yet
- **Crowd Control Escape** *(Experimental, opt-in)* - while you're held by crowd control the game reports to addons (stuns, roots, fears) and carry something ready to break it, the Sustain slot turns into that escape button, counting down the effect until you're free. Any spec, tank or not. Movement slows can't be detected in combat, so they aren't covered. Off by default under Defensives → Crowd Control Escape
- **Pet heal reminder** - Hunters and Warlocks get the slot when their pet drops low, **in combat as well as out**. 12.0 hides your pet's health once a fight starts, so the cue is rendered without ever reading it: the pet's health fraction is handed to the engine as a curve index and the engine decides whether the icon is visible. Threshold configurable from 10-90% (default 50) under Defensives → Sustain
- **Exact vs. estimated maintenance tracking** - in combat the game hides which buff is which, so the slot identifies yours through Blizzard's Cooldown Manager. That needs two things: the Cooldown Manager enabled, and its **Tracked Bars** widget left visible in Edit Mode (that one widget is enough - the other Cooldown Manager panels can stay hidden). With it you get the buff's true remaining time and, for Ironfur and Bone Shield, a live stack count. Without it the slot estimates the countdown from your own cast and shows no number, rather than risk displaying another buff's - the refresh cue works either way. Background: [AURA_IDENTITY_12.0.md](Documentation/AURA_IDENTITY_12.0.md)
- **Absorb-barrier awareness** - a shield that outlasts its own cooldown (Ice Barrier, Blazing Barrier, Prismatic Barrier, Rune Tap) sinks to the back while the barrier holds and returns as it runs low, instead of being re-suggested into a wasted overwrite. Defensives that genuinely stack, like Ironfur and Ignore Pain, are exempt
- **Low-health emergency ordering** - below the ~35% threshold the queue leads with big instant heals and immunity bubbles, ahead of mitigation and small fillers; above the threshold fast/free fillers and procs stay first for routine upkeep
- **Emergency heals held until you need them** *(on by default)* - above the low-health threshold, panic buttons (immunity bubbles, big instant heals, health potions) sit parked at the end of the queue with a WAIT tag instead of being suggested while you're healthy. Damage-reduction cooldowns are deliberately exempt and stay live at any health: a wall like Shield Wall or Pain Suppression is meant to be pressed *before* a hit lands, so holding it back would coach the wrong habit
- **Execute-range cue** - when your target drops into execute range, the HP-gated finisher (Kill Shot, Touch of Death and the like) lights up wherever it sits in the queue. Target health is secret in combat, so this too is engine-rendered rather than read
- Procced defensives (Victory Rush, free heals) shown at any health level
- Usability-aware visuals: icons grey out while channeling, blue-tint when lacking resources, desaturate on cooldown
- Pet rez/summon support for Hunter, Warlock, Death Knight (pet *heal* lives in the Sustain slot above)
- Compact health bar (player + pet) with automatic resize
- Items supported (potions, healthstones) with auto-detection from action bars - optional aura linking and combat hiding per item
- **Emergency healing potion** auto-picks the best potion you're carrying, ranked by how much it actually restores - a potion that heals a share of your maximum health can out-rank a bigger fixed-amount one, and the reverse; the tile's tooltip explains the pick
- **Form-aware (Druid)** - defensives that strictly require Bear Form leave the row while you're in Cat Form and vice versa, in combat too (where usability normally can't be read); automatically disabled with Fluid Form
- Combat-safe health detection via LowHealthFrame signal (~35%) for 12.0 secret-value compatibility

### Pre-Combat Buffs

- Out of combat, the defensive queue surfaces the buffs you're **missing but own** as clickable icons with a green glow - flask, food, augment rune, weapon enchant
- **Class maintained buffs** - rogue poisons, shaman shields and weapon imbues, and the standard party/raid buffs. You're reminded when one is missing or has dropped below half its remaining duration; a lapsed buff is refilled with whatever your rotation ranks highest, and rogues get both a lethal and a non-lethal poison at once
- **Party-aware group buffs** - if you have a group buff up but a party member doesn't (they joined late, released, or were out of range), the buff is offered again so one re-cast covers everyone. Party only, and only for members who are alive, online and in range, so every reminder is actionable. Personal buffs like poisons and shields are unaffected
- **Recuperate** - the all-classes out-of-combat self-heal is offered like any other missing buff whenever you're hurt (below 90% where exact health is readable; via never-secret recovery signals where 12.0.7 hides it), and hides while its heal-over-time is running
- **Click-to-use** - a hover highlight and click-to-use layer sits over every out-of-combat icon (like an action button), casting the spell or using the item straight from the queue
- **Eating / applying feedback** - while a buff is being applied (eating food and the like) the whole queue greys out with a channel-style progress sweep across the buff window
- Buff data is DB2-generated (discovered by item class and buff aura, stat decoded from the effect chain) and spans all expansions, so leveling characters are covered too; weapon-enchant suggestions respect your equipped weapon so you're never offered an oil or stone it can't take
- Detection is aura-based and runs out of combat only, sidestepping 12.0 secret values entirely

### Gap-Closer Suggestions

- Suggests movement/gap-closer spells when the target is out of melee range
- Injects into the offensive queue for natural flow
- Push-based range detection via `C_ActionBar.EnableActionRangeCheck` for minimal polling

### Burst-Ready Cue

- In combat, your spec's major offensive cooldown glows purple when a burst window is actually called for - not merely when it's off cooldown. The window is inferred from Blizzard's own recommendation (the only system that can read the secret in-combat context) combined with SimulationCraft's burst conditions: the cue fires when Assisted Combat recommends the trigger itself, when the trigger's SimC window is up (e.g. Berserk during Tiger's Fury), or when Blizzard is recommending the ability that opens that window
- A called-for trigger surfaces at the second queue position (promoted, or inserted when Assisted Combat leaves the cooldown entirely to you), so the signal sits where you're already looking
- Trigger lists are SimC-derived: SimulationCraft's own burst-window markers (potion/trinket/Power Infusion sync) define them per spec, with curated class defaults where no data exists - and you can set your own list per spec under Offensive → General
- Readiness and buff windows are read as engine truth, so the cue is combat-safe under 12.0 secret values; opt-in - enable under Offensive → General

### Smart Hotkey Detection

- Scans all action bars to find your keybinds for any spell
- Parses macro conditionals (`[mod]`, `[form]`, `[spec]`, `[stealth]`, `[combat]`)
- Handles dynamic spell transforms (e.g. Templar Strike → Templar Slash) via override scanning
- Gamepad support with Xbox/PlayStation/Generic button icon styles
- Custom hotkey overrides via right-click menu
- Key press flash feedback when you press the suggested keybind

### Intelligent Filtering

- Hides redundant suggestions (buffs already active, current form, existing pet) - self-buff detection is generated from client data across all classes (pure self-buffs like Slice and Dice suppress while active, reappear in the pandemic window)
- **Stack-aware** - buffs that can stack are never suppressed as "already active", backed by client-data stack counts, so stacking abilities keep getting suggested while building stacks; defensives are always exempt (application-stacking like Ironfur must keep being suggested)
- Per-spell blacklist (Shift+Right-click to toggle) - a blacklisted AC-slot spell auto-substitutes via highlight-mode lookahead
- Respects class-specific mechanics (Druid forms, Rogue Stealth, etc.)
- Cast-based inference for poisons, weapon imbues, and long-duration buffs in 12.0 combat
- Combat-safe aura tracking via `auraInstanceID` mapping - detects buff removal and reapply even when `spellId` is secret
- NeverSecret aura whitelist (~50 spells) for direct resolution without instance-map lookup

### Performance Optimized

- Event-driven updates with minimal polling
- Engine-level unit event filtering (`RegisterUnitEvent`) - other players' aura, health, and cast events never reach the addon, keeping idle CPU low in crowded cities
- Push-based cooldown and range events (`SPELL_UPDATE_COOLDOWN`, `ACTION_RANGE_CHECK_UPDATE`)
- Pooled table allocation to reduce garbage collection pressure
- Cached spell info, override lookups, and filter results per update cycle - macro parses are cached per action slot (including misses) and invalidated slot-by-slot
- 12.0 opaque cooldown pipeline (`SetCooldownFromDurationObject`) bypasses secret-value handling entirely

## Installation

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/just-assisted-combat) or extract to `Interface\AddOns\JustAC`
2. Enable "Assisted Combat" in WoW's Game Menu → Edit Mode → Combat section
3. `/jac` to access options

## Configuration

Options are organized into 6 tabs:

| Tab | Purpose |
|-----|--------|
| **General** | Display mode, visibility rules, queue content toggles, Disruption slot, Shared Behavior (ability markers), Cooldown Manager (3 sub-tabs: Settings, Icon Labels, Hotkeys) |
| **Standard Queue** | Layout, offensive display, defensive display, appearance, resource bar (4 sub-tabs) |
| **Overlay** | Nameplate overlay layout, offensive display, defensive display, resource bar (3 sub-tabs) |
| **Offensive** | Blacklist, custom queue (Always Show / Hold Until Charged), ordering toggles incl. SimC priority, burst-ready cue, gap-closers, interrupt mode |
| **Defensives** | Spell priority list, health thresholds, per-item aura linking, Sustain slot (tank maintenance, CC escape, pet heal), pre-combat buffs |
| **Profiles** | AceDB profiles with automatic per-spec switching |

- **Localization** - English, German, French, Russian, Spanish (ES/MX), Portuguese (BR), Korean, Simplified/Traditional Chinese

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

- **WoW 12.0 Midnight Compliant** - Handles secret values gracefully; `auraInstanceID` mapping for combat-safe buff detection; `isOnGCD` for cooldown readiness; opaque cooldown pipeline; NeverSecret aura whitelist; fail-open design throughout
- **Secret-safe visuals** - Where a combat state is a "secret value" that can't be read or branched on (e.g. cast interruptibility), it's forwarded straight into a display sink (`SetAlphaFromBoolean` / `SetCooldownFromDurationObject`) so the engine renders it without the addon ever seeing the value
- **Curve selectors** - The same idea generalised: a secret number is handed to the engine as an *index* into a curve the addon authors, and the resulting colour sinks into a display property. The enrage cleanse indexes by dispel type; the pet-heal, execute and health top-off cues index by health fraction (`UnitHealthPercent` + `C_CurveUtil`). Graded alphas let one evaluation express several thresholds at once, so a two-tier policy needs no comparison. Display-only by construction - the result is secret, so it can never feed ordering or a gate
- **Taint is fatal around secrets** - Tainted execution cannot read a secret at all, so writing any Lua field on a frame that reads secrets (Blizzard's Cooldown Manager viewers) breaks *Blizzard's* code, not just ours. Reads and widget C methods are safe; mixin methods that store state are not. See [AURA_IDENTITY_12.0.md](Documentation/AURA_IDENTITY_12.0.md)
- **Never-secret signals** - Where values are hidden, readable side-channels stand in: the low-health vignette (~35% binary), and player `UNIT_HEALTH` *event activity* - out-of-combat regen fires events while below full health and goes silent at full, so the firing itself is a "still recovering" signal even when the payload is secret
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
/jac inspect modules          - Check module health
/jac inspect cooldown [spell] - Test cooldown APIs (defaults to AC suggestion)
/jac inspect defensives       - Diagnose defensive system
/jac inspect interrupts       - Diagnose interrupt/CC queue state
/jac inspect burst            - Burst-ready cue state
/jac inspect auras            - Diagnose aura cache state
/jac inspect perf             - Queue build rate statistics (requires /jac debug)
/jac inspect perf reset       - Reset build counters
/jac inspect buffs            - Diagnose pre-combat buff checklist (out of combat)
/jac inspect rank             - Queue context inference and per-spell ordering
/jac inspect rotation         - Dump the resolved SimC priority list for your spec
/jac inspect gates            - Show SimC gate evaluation (buff/resource thresholds)
/jac inspect aoe              - Target-count inference (single-target vs. multi-target)
/jac inspect dots             - Damage-over-time tracking state on your target
/jac inspect stacks           - Aura stack counts behind stack-aware filtering
/jac inspect resource         - Resource bar detection and power channels
/jac inspect resourcepoints   - Discrete point-resource read (combo points, runes, chi...)
/jac inspect enrage           - Enrage detection, dispel matching, and a PASS/FAIL walk of the cue's gates
/jac inspect enragelog        - Log target dispellable-aura counts vs cue state through a fight
/jac inspect errors [off|show]- Capture Lua errors AND taint blocks to SavedVariables, deduped with counts
/jac inspect chargediag [sp]  - Armed charge-event probe (60s window)
/jac inspect castdiag         - Diagnose in-combat interrupt detection (one-shot probe)
/jac inspect healthprobe      - Sweep health-detection channels (run while hurt)
/jac inspect validate [arm]   - Check API readability where you stand; arm = diff on combat enter/exit
/jac help                     - Show all commands in-game
```

## License

GNU General Public License v3 (GPL-3.0-or-later) - See [LICENSE](LICENSE) for details.

The embedded Ace3 libraries retain their original licenses and are clearly marked in `Libs/`.

Notable embedded library licenses:

- **Ace3, LibStub, CallbackHandler** - Public domain / BSD-style
- **LibSharedMedia-3.0** - Public domain
- **AceGUI-3.0-SharedMediaWidgets** - GPL v2 or later

---

*JustAC is not affiliated with or endorsed by Blizzard Entertainment.*
