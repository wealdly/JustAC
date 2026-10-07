# WoW Forever guide references

Researched 2026-10-07 (beta, level-30 cap; launch 2026-11-04). Paraphrased summaries of
every Forever combat, defensive and healing guide found, with sources and disagreements.
Reference for authoring and checking priority lists; never copy guide text into the addon.

| File | Covers |
|---|---|
| [warrior-rogue.md](warrior-rogue.md) | Arms, Fury, Protection; Assassination, Combat, Subtlety (no rogue tank exists) |
| [paladin-priest.md](paladin-priest.md) | Holy, Protection, Retribution; Discipline, Holy, Shadow |
| [druid-shaman.md](druid-shaman.md) | Balance, Feral cat, Feral bear, Restoration; Elemental, Enhancement, Restoration |
| [hunter-mage-warlock.md](hunter-mage-warlock.md) | Beast Mastery, Marksmanship, Survival; Arcane, Fire, Frost; Affliction, Demonology, Destruction |
| [cross-class.md](cross-class.md) | Blizzard notes, combat-mechanic changes, healing, consumables, simulators, builds at the cap |

## Machine-readable rotations

**ElliotWood/Forever** (github.com/ElliotWood/Forever, MIT, fork of wowsims/classic, active):
49 `ui/specs/<class>/<spec>/apls/*.apl.json` covering all nine classes, written for level 60
with Forever spell ids (max rank) and structured conditions (`auraIsActive`,
`auraNumStacks`, `dotIsActive`, `isExecutePhase`, `numberTargets`, `currentRage`,
`spellTimeToReady`, `spellCastTime`, fight time remaining). The best list source found:
see `FOREVER_ENGINE_DESIGN.md` section 5. MIT requires keeping its copyright notice with
anything derived from it.

Not usable as list sources: SimulationCraft's `forever` branch (engine work only), wowsims
org (no Forever repo), wow4_sims (vanilla 1.12 lists), MythicSim (closed).

## What the guides change for the engine

1. **Guides go stale fast.** Tiger's Fury removed and Mangle renamed Primal Bite (Oct 1), Fury
   rework (Oct 1), Slam cooldown raised (Sep 24), Bloodthrill odds doubled (Sep 24). Every
   list must build cleanly with `tools/gen_forever_rotations.py`, which checks every
   ability against the current Forever data (exit 1 on one no class can learn).
2. **Ranks.** New ranks do not replace old ones on action bars, low ranks get less spell power
   and fewer proc chances. Show the highest known rank, find the hotkey for whatever rank is
   on the bar (probe H14).
3. **Swing timer is a real gate.** Baseline Slam resets the swing (18s cooldown; the Arms
   talent Improved Slam removes the reset); hunter abilities no longer clip Auto Shot.
4. **Carry-over state.** Combo points stay on a target when you switch (rogue, feral).
5. **Reactive triggers.** Overpower via dodge or Bloodthrill (main-hand hits on your Rend
   target), Victory Rush on Victorious, Fingers of Frost / Frostbite for Ice Lance,
   Maelstrom Weapon at 5 stacks.
6. **Upkeep changes.** Warlock Curse of Agony / Doom are now Banes and stack with a curse;
   Judgement no longer consumes the seal.
7. **Mechanics.** DoTs and HoTs can crit; crits give +100% rage; mana regen is continuous
   (no 2s ticks) with the five-second rule kept; hit and crit are single stats.
8. **Above the beta cap.** Mortal Strike, Whirlwind, Shadowform, Shadow Word: Death, Light's
   Vigil and most capstones are learned past 30, so lists will skip them until launch.
9. **Addon rules.** Midnight API with secret values (as measured); built-in damage meter and
   Cooldown Manager, the latter without spell-rank support yet.
