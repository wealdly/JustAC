**JustAC - play any spec like you've mained it for years.**

Blizzard's Assisted Combat tells you what to press. JustAC turns that into something you can actually play from: a clean queue of your next abilities, with *your* keybinds, right where you're already looking. Nothing to memorize, no import strings to untangle.

**Working on Midnight, and kept that way.** Midnight changed what an addon is allowed to see mid-fight, and a lot of rotation helpers quietly broke or stopped being updated. JustAC was rebuilt around the new rules rather than patched over them, and it tracks live right now on 12.1.0.

- **Perform instantly on anything.** A fresh alt, a rusty main, a spec you've never touched. The next button is right there, and so are the three after it.
- **Keep your eyes on the fight.** Rotation, defensives, interrupts, CC and burst windows all surface in one place, in your line of sight, labeled with the keys you press.
- **Stay alive.** Drop low and JustAC leads with the button that saves you: a wall while you're taking chip damage, a big heal after a real hit, an immunity when things are dire. While you're healthy those panic buttons stay parked at the back.

## Whatever you play

Same addon, same queue, nothing to set up. It shows what your spec needs:

**Damage** - Follow-ups ordered by community theorycraft for your spec, then re-ranked against the pull in front of you. Spenders sink until you can afford them. Stack-hungry abilities wait until you've built up, and DoTs come back for refreshing at the right moment. Execute abilities rise when your target is worth finishing, and your burst cooldown glows purple when it's ready.

**Tanks** - A dedicated slot for the mitigation buff your spec keeps rolling: Ignore Pain, Shield of the Righteous, Ironfur, Demon Spikes, Bone Shield. Marching ants start a few seconds before it lapses. Miss that window and the slot flares into a full proc glow, because letting it drop is the part worth shouting about. It counts stacks where stacks matter, and stays dark when the button isn't pressable. Blizzard's Cooldown Manager sharpens the timing if you leave its **Tracked Bars** widget visible; without it the cue runs off your own casts. (Brewmaster isn't covered yet.)

**Healers** - Keep your healing addon. JustAC isn't one, and what it adds is the other half of your job: the queue becomes a damage priority with heals kept out of the follow-ups, and an optional caster mode drops melee-weave suggestions, so your filler time between casts still contributes. Group heal suggestions ride alongside as a nudge. An ally who's taken real damage points you at an area heal, and a group in trouble raises your biggest save. Multi-target only, so who to heal stays your call.

**Pet classes** - Hunters and Warlocks get a pet heal reminder in the queue, so a hurt pet reaches you without you having to watch its frame mid-fight.

**Everyone** - Interrupts, CC and cleanses, the pre-combat checklist, and an escape button when a stun, fear or root has you.

## More than the bare glow

Blizzard shows one dim suggestion on your action bar. Simpler addons echo it with a hotkey. JustAC adds the judgment a good player brings:

- It **re-ranks your follow-ups to the pull.** An AOE pack lifts your AOE tools, a ranged pull sinks the melee ones. Nothing replays from a fixed list.
- It **won't waste a suggestion.** Melee abilities vanish out of range, Cat abilities while you're a Bear, stealth openers while unstealthed. Self-buffs you already have drop out, and so does anything a proc or cooldown already covers. Big cooldowns stop being pushed at you once the last mob standing is nearly dead, bosses excepted.
- It **learns what your CC won't work on.** Bosses and pets are ruled out from the start, but nothing tells an addon in advance which trash mob shrugs off a stun. So it watches. The moment one refuses your crowd control, that mob type stops being offered. `/jac inspect ccdb` shows what it learned, and clears it if it learned wrong.
- It's an **assist, not a bot.** Everything rides Blizzard's own sanctioned recommendation flow. Nothing to script, nothing to get banned for.

## What's in the box

**The queue** - Position 1 mirrors Blizzard's pick. The follow-ups are yours: context-ranked, filtered for cooldowns and redundancy. Keep the default SimulationCraft-priority ordering or build a custom per-spec list. Pin an ability to always show, or hold it until every charge is banked. Dynamic inserts for procs and gap-closers.

**Disruption** - One slot ahead of your queue for everything that takes away what the enemy is doing. Interrupts with keybind context and multiple modes. Crowd control that knows stun from silence. Enrage cleanses too: when an enemy enrages and you carry Soothe, Tranquilizing Shot, Shiv or similar, your dispel glows green with the buff it clears. Each part works on its own.

**Defensives** - Configurable priorities (self-heals, major cooldowns, healthstones, potions), tuned per spec so each leads with its own biggest survival button, and sorted by how much trouble you're in. Damage-reduction walls never park at the back, because those want pressing *before* the hit lands.

**Pre-combat buffs** - Out of combat, the buffs you're missing but own appear as clickable icons: flask, food, augment rune, weapon enchants, class buffs like poisons and shields, plus the all-classes Recuperate self-heal whenever you're hurt. Group buffs watch your party, so one re-cast covers whoever joined late.

**Display & input** - Standard frame, nameplate overlay, or both, each with an optional resource bar. Corner markers show when an ability can be cast on the move, and when it's off the global cooldown. Full layout control. Smart hotkey detection from bars and macros, plus manual overrides. Keyboard and gamepad. Masque support. Per-spec profiles. Localized: EN, DE, FR, IT, RU, ES (ES/MX), PT-BR, KO, ZH (CN/TW).

**One limitation:** the interrupt is correctly hidden on casts that can't be interrupted, whatever your UI. *Substituting* crowd control for a kick on a non-interruptible cast is the one thing that still needs Blizzard's default cast bar. Replace the cast bar and you get no suggestion there instead of a CC. You'll never get a wrongly-shown kick.

---

What else are you up to? JustAC, Just Delve, Just Loot

Enjoying the addon? I love keeping JustAC updated and providing quick support, but development has real expenses. If you'd like to help out, your support is greatly appreciated - consider buying me a coffee! 😊
