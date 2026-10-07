## [Unreleased]

### New
- **WoW Forever support (early test build).** JustAC now runs on WoW Forever as well as retail, from the same download. WoW Forever has no Assisted Combat, so JustAC builds the queue itself: its own priority for every class and talent tree, tuned for levelling, plus the abilities on your action bars.
- On WoW Forever:
  - Spell ranks are handled for you: the queue shows the rank on your bars, with its keybind.
  - Heroic Strike, Cleave, Raptor Strike and Maul show a bar filling to the swing they wait for, and a tick in place of the keybind, so you can see pressing again does nothing. Attack, Auto Shot and wands show their swing timer while they run.
  - Hunters: Auto Shot leads at range and gives way to Attack in melee.
  - Damage-over-time effects, including the one you open with, step back while they tick and come back as they run out. They are not suggested on a target about to die.
  - Life Tap, Evocation and Innervate come forward when you can't afford your spells. Life Tap, Bloodrage and Hellfire are only offered while your health is above half.
  - Area abilities such as Thunder Clap and Volley lead when two or more enemies are fighting you.
  - Between pulls, the defensive queue offers food, drink or a bandage when you need them, and flasks, elixirs and scrolls you carry.
  - Tracking, travel forms, conjuring, pet care, crowd control and other abilities that deal no damage stay out of the damage queue.
- This is an early build for the WoW Forever beta. Some suggestions are still being checked in game, so please report anything that feels off.

### Fixed
- Spells on action buttons without a keybind now grey out when you can't afford them, like the rest of the queue.
- A `/startattack` macro now gives Attack its keybind.
