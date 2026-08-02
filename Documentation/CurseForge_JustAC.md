**JustAC - play any spec like you've mained it for years.**

Blizzard's Assisted Combat tells you what to press. JustAC turns that into something you can actually play from: a clean queue of your next abilities, with *your* keybinds, right where you're already looking. There's nothing to memorize and no import strings to untangle.

## Why you'll want it

- **Perform instantly on anything.** Jump on a fresh alt, a rusty main, or a spec you've never touched and hold your own. The next button is right there, and so are the three after it.
- **Keep your eyes on the fight.** Your rotation sits in your line of sight, labeled with the keys you actually press. Looking up instead of down makes you faster on mechanics.
- **One place to look.** Rotation, defensives, interrupts, crowd control, gap-closers and burst windows all surface together, at the moment each one matters.
- **Stay alive.** Drop low and JustAC leads with the button that actually saves you: a big instant heal, or an immunity bubble if things are dire. While you're healthy those panic buttons stay parked at the back, so the queue is never cluttered with presses you shouldn't be making yet. Between pulls, the all-classes Recuperate self-heal glows green whenever you're hurt.
- **It just works in 12.0.** The patch that hid cooldowns and health in combat broke a lot of overlays. JustAC tracks them itself, backed by built-in cooldown and charge data - so even an ability it first sees mid-fight (a battle res, a fresh login) reads correctly, including abilities tucked behind modifier-key macros.

## More than the bare glow

Blizzard shows one dim suggestion on your action bar. Simpler addons just echo it with a hotkey. JustAC adds the judgment a good player brings:

- It **re-ranks your follow-ups to the pull**. An AOE pack lifts your AOE tools; a ranged pull sinks the melee ones. Nothing replays from a fixed list.
- It **won't waste a suggestion.** CC never lands on an immune target. Melee abilities disappear when you're out of range, Cat abilities while you're a Bear (unless Fluid Form shifts for you), stealth openers while unstealthed, buff-gated casts while the buff is down. Self-buffs you already have, and anything a proc or cooldown already covers, are filtered out too.
- It's an **assist rather than a bot.** Everything rides Blizzard's own sanctioned recommendation flow, so there's nothing to script and nothing to get banned for.

## What's in the box

**The queue** - Position 1 mirrors Blizzard's pick; follow-ups show your priority next-casts, context-ranked and filtered for cooldowns and redundancy. Order them your own way with a custom per-spec list, or leave the default SimulationCraft-priority ordering on: it arranges your follow-ups by community theorycraft for your spec, re-ranked against what Blizzard is recommending right now, and it counts your combo points, holy power, chi, shards and runes so spenders sink until you can actually afford them. Pin an ability to always show, or hold it until every charge is banked so a two-charge button never gets spent into an overcap. Dynamic inserts for procs and gap-closers, plus a burst-ready cue: your spec's major cooldown glows purple when it's ready to open a burst window.

**Disruption: interrupts, CC & cleanses** - One slot ahead of your queue for everything that takes away what the enemy is doing. Interrupt detection with keybind context and multiple modes. Crowd control that respects immune targets, creature-type restrictions, and stun-vs-silence. Enrage cleanses land there too: when an enemy enrages and you carry Soothe, Tranquilizing Shot, Shiv or similar, your dispel appears with a green glow and the buff it clears. Each part works on its own, so you can run the cleanse with interrupt reminders switched off.

**Sustain: the slot that keeps you contributing** - Beside the defensive queue sits a slot for whatever is currently stopping you from doing your job. Your class decides what claims it:

- **Tanks** get the one mitigation buff your spec keeps rolling: Shield Block, Shield of the Righteous, Ironfur, Demon Spikes, Bone Shield. It counts down and cues you a few seconds before the buff lapses, with a brighter pulse if it does drop. Turn on Blizzard's Cooldown Manager, leave its **Tracked Bars** widget visible in Edit Mode, and the slot reads your buff exactly: true remaining time plus a live stack count for Ironfur and Bone Shield. The other Cooldown Manager panels can stay hidden. Without that widget the countdown is estimated from your own cast and no stack number appears, since showing you another buff's count would be worse than showing none. (Brewmaster isn't covered yet.)
- **Hunters and Warlocks** get a pet heal reminder that finally works **in combat.** 12.0 hides your pet's health the moment a fight starts, and JustAC surfaces the cue anyway. You set how hurt the pet has to be before it shows.
- **Anyone** held by a stun, fear or root gets the button that frees them, counting down until you're loose. A stun costs you just as much uptime as a mitigation buff you let lapse, so it belongs in the same place.

**Defensives** - Configurable priorities (self-heals, major cooldowns, healthstones, potions) with low-health emergency ordering, tuned per spec so each leads with its own biggest survival button. Panic buttons stay parked while you're healthy. Your damage-reduction walls never park, because those want pressing *before* the hit lands. When your target drops into execute range, your finisher lights up.

**Pre-combat buffs** - Out of combat, the buffs you're missing but own appear as clickable icons: flask, food, augment rune, weapon enchants, class buffs like poisons and shields - and Recuperate whenever you're hurt. Group buffs now watch your party too, so if someone joined late or released, one re-cast covers everyone. Click to cast or use, straight from the queue.

**Display & input** - Standard frame, nameplate overlay, or both, each with an optional resource bar (your primary power plus a segmented secondary point resource: combo points, runes, chi, holy power, and so on). Corner markers tell you when an ability can be cast on the move, and when it won't trigger the global cooldown so you can fire it and go straight to the next press. Full layout controls (size, count, orientation, labels, glow styles). Smart hotkey detection from bars and macros, plus manual overrides. Keyboard and gamepad support (Xbox, PlayStation, generic). Masque support.

**Localization & profiles** - Per-spec profiles. Localized: EN, DE, FR, RU, ES (ES/MX), PT-BR, KO, ZH (CN/TW).

## Note on the Disruption slot in 12.0

The interrupt is correctly hidden on casts that can't be interrupted, on any UI setup, driven straight from the cast's protected interruptible flag through a display-only path. The one thing that still needs the Blizzard default cast bar is *substituting* a crowd-control ability for a kick on a non-interruptible cast. Run a cast-bar or nameplate addon that replaces the cast bar and you simply get no suggestion there instead of a CC. You will never get a wrongly-shown kick.

---

What else are you up to? JustAC | Just Delve | Just Loot

Enjoying the addon? I love keeping JustAC updated and providing quick support, but development has real expenses. If you'd like to help out, your support is greatly appreciated - consider buying me a coffee! 😊
