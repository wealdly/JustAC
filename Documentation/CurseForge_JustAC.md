**JustAC - play any spec like you've mained it for years.**

Blizzard's Assisted Combat tells you what to press. JustAC turns that into something you can actually play from: a clean queue of your next abilities, with *your* keybinds, right where you're already looking. No rotation guides to memorize, no import-string spaghetti to untangle, no eyes glued to your hotbar.

## Why you'll want it

- **Perform instantly on anything.** Jump on a fresh alt, a rusty main, or a spec you've never touched and hold your own. The next button is right there - and so are the three after it.
- **Watch the fight, not your bars.** Your rotation sits in your line of sight, labeled with the keys you actually press. Eyes up means faster reactions, fewer avoidable hits, cleaner mechanics.
- **Track one thing, not ten.** Rotation, defensives, interrupts, crowd control, gap-closers, and burst windows all surface in the same place - the moment they matter.
- **Stay alive.** When you drop low, JustAC leads with the button that *saves* you - an immunity bubble or a big instant heal - not a token mitigation, and it pulls your defensives forward exactly when you need them. After the fight, the new all-classes Recuperate self-heal glows green in the queue the moment you're hurt - one click and you're topping up for the next pull.
- **It just works in 12.0.** The patch that hid cooldowns and health in combat broke a lot of overlays. JustAC tracks them itself, backed by built-in cooldown and charge data - so even an ability it first sees mid-fight (a battle res, a fresh login) reads correctly, including abilities tucked behind modifier-key macros.

## More than the bare glow

Blizzard shows one dim suggestion on your action bar. Simpler addons just echo it with a hotkey. JustAC adds the judgment a good player brings:

- It **re-ranks your follow-ups to the pull** - an AOE pack lifts your AOE tools, a ranged pull sinks the melee ones - instead of replaying a fixed list.
- It **won't waste a suggestion**: no CC on an immune target, no melee ability when you're out of range, no Cat-only ability while you're a Bear (unless Fluid Form shifts for you), no stealth opener while unstealthed, no buff-gated cast while its buff is down, no re-suggesting a self-buff you already have - and nothing already covered by a proc or cooldown.
- It's an **assist, not a bot** - it rides Blizzard's own sanctioned recommendation flow, so there's nothing to script and nothing to get banned for.

## What's in the box

**The queue** - Position 1 mirrors Blizzard's pick; follow-ups show your priority next-casts, context-ranked and filtered for cooldowns and redundancy. Order them your own way with a custom per-spec list, or switch on SimulationCraft-priority ordering: it arranges your follow-ups by community theorycraft for your spec, re-ranked against what Blizzard is recommending right now, and it counts your combo points, holy power, chi, shards and runes so spenders sink until you can actually afford them. Pin an ability to always show, or hold it until every charge is banked so a two-charge button never gets spent into an overcap. Dynamic inserts for procs, gap-closers, and burst windows.

**Defensives, interrupts & CC** - Configurable defensive priorities (self-heals, major cooldowns, healthstones, potions) with low-health emergency ordering. Interrupt detection with keybind context and multiple modes. Enrage cleanses too: when an enemy enrages and you can remove it - Soothe, Tranquilizing Shot, Shiv, and the like - your dispel surfaces in the interrupt slot with a green glow and the enrage it clears. Crowd control that respects immune targets, creature-type restrictions, and stun-vs-silence.

**Tanks: a slot for the buff you keep rolling** - Shield Block, Shield of the Righteous, Ironfur, Demon Spikes, Bone Shield - the one mitigation buff your spec maintains gets its own slot beside the defensive queue, counting down and cueing you to refresh before you lose it, not after. The cue comes in two stages: a slow crawl around 3 seconds out, then a brighter pulse if it actually drops. Turn on Blizzard's Cooldown Manager and leave its panel visible and the slot reads your buff exactly - true remaining time, plus a live stack count for Ironfur and Bone Shield. Without it the countdown is estimated from your own cast and no number is shown, because a wrong stack count is worse than none. (Brewmaster isn't covered yet.)

**Pre-combat buffs** - Out of combat, the buffs you're missing but own appear as clickable icons: flask, food, augment rune, weapon enchants, class buffs like poisons and shields - and Recuperate whenever you're hurt. Group buffs now watch your party too, so if someone joined late or released, one re-cast covers everyone. Click to cast or use, straight from the queue.

**Display & input** - Standard frame, nameplate overlay, or both - each with an optional resource bar (your primary power plus a segmented secondary point resource: combo points, runes, chi, holy power, and so on). Corner markers tell you when an ability can be cast on the move, and when it won't trigger the global cooldown - so you know you can fire it and go straight to the next press. Full layout controls (size, count, orientation, labels, glow styles). Smart hotkey detection from bars and macros, plus manual overrides. Keyboard and gamepad support (Xbox, PlayStation, generic). Masque support.

**Localization & profiles** - Per-spec profiles. Localized: EN, DE, FR, RU, ES (ES/MX), PT-BR, KO, ZH (CN/TW).

## Note on interrupts in 12.0

The interrupt is correctly hidden on casts that can't be interrupted, on any UI setup - it's driven straight from the cast's protected interruptible flag through a display-only path. The only thing that needs the Blizzard default cast bar is *substituting* a crowd-control ability for a kick on a non-interruptible cast; with a cast-bar/nameplate addon that replaces the cast bar you simply get no suggestion there instead of a CC - never a wrongly-shown kick.

---

What else are you up to? JustAC | Just Delve | Just Loot

Enjoying the addon? I love keeping JustAC updated and providing quick support, but development has real expenses. If you'd like to help out, your support is greatly appreciated - consider buying me a coffee! 😊
