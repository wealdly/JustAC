-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Curated range-reference abilities for target-distance detection.
-- Moved out of SpellDB.lua; registered into it via RegisterRangeReferences. Logic
-- (IsTargetWithin / bracketing) stays in SpellDB.
--
-- [spellID] = max range in yards. These are RELIABLE, on-target HARMFUL abilities (damage
-- or CC) with stable, known ranges - used as distance probes. SpellDB.IsTargetWithin polls
-- IsSpellInRange (a non-secret boolean; only the yardage is secret) on each ability the
-- player actually KNOWS, and brackets the target between the largest out-of-range and the
-- smallest in-range probe. Resolution is as fine as the available probe spacing.
--
-- Vetting criteria (a bad probe gives a WRONG distance, not just thinner coverage):
--   * SINGLE-TARGET, PLAYER-cast only. Excluded: ground/cursor-targeted (Solar Beam,
--     Shadowfury - IsSpellInRange measures range-to-cursor) and PET abilities (Spell Lock,
--     Axe Toss - they reflect the pet's range, not the player's). Self-centered/PBAoE
--     return nil and are useless as probes.
--   * Fixed range. Form/talent/spec gating is FINE - an unavailable probe drops out via
--     the IsSpellAvailable gate (no wrong reading), and range is form-independent so a
--     form-blocked single-target probe still reads correctly. Avoid same-ID range MORPHS.
-- Why a spread: on-target DAMAGE abilities are bimodal in WoW (melee ~5yd or ranged ~40yd),
-- leaving a sparse 8-32yd middle, so the interrupt CCs (10/13/15/20/25/30) fill that gap.
--
-- Curated, not generated (NPC/legacy name collisions + trigger indirection make a clean
-- sweep impossible). Verify ranges per patch via /jac inspect; the known-filter makes a
-- stale entry harmless (it just never resolves).
local SpellDB = LibStub("JustAC-SpellDB", true)
if not SpellDB or not SpellDB.RegisterRangeReferences then return end

SpellDB.RegisterRangeReferences({
    -- ~5yd melee interrupts (class-baseline)
    [1766]   = 5,   -- Kick (Rogue)
    [6552]   = 5,   -- Pummel (Warrior)
    [183752] = 5,   -- Disrupt (Demon Hunter)
    [116705] = 5,   -- Spear Hand Strike (Monk)
    [96231]  = 5,   -- Rebuke (Paladin)
    [408]    = 5,   -- Kidney Shot (Rogue)
    -- ~5yd melee builders - each melee spec's core attack (always known). This is the bulk
    -- of melee coverage; every melee spec has at least one here. (Rogue Backstab 53 is
    -- omitted: it transforms to Shadowstrike at 25yd in stealth - a misleading 5yd probe.)
    [49998]  = 5,   -- Death Strike (DK)
    [206930] = 5,   -- Heart Strike (DK Blood)
    [49020]  = 5,   -- Obliterate (DK Frost)
    [85948]  = 5,   -- Festering Strike (DK Unholy)
    [162794] = 5,   -- Chaos Strike (DH Havoc)
    [232893] = 5,   -- Felblade (DH)
    [228477] = 5,   -- Soul Cleave (DH Vengeance)
    [204513] = 5,   -- Shear (DH Vengeance)
    [5221]   = 5,   -- Shred (Druid Feral)
    [1822]   = 5,   -- Rake (Druid Feral)
    [33917]  = 5,   -- Mangle (Druid Guardian/Feral)
    [77758]  = 5,   -- Thrash (Druid Guardian)
    [259387] = 5,   -- Mongoose Bite (Hunter Survival)
    [186270] = 5,   -- Raptor Strike (Hunter Survival)
    [100780] = 5,   -- Tiger Palm (Monk)
    [205523] = 5,   -- Blackout Kick (Monk Brewmaster)
    [107428] = 5,   -- Rising Sun Kick (Monk Windwalker)
    [35395]  = 5,   -- Crusader Strike (Paladin)
    [53600]  = 5,   -- Shield of the Righteous (Paladin Protection)
    [215661] = 5,   -- Justicar's Vengeance (Paladin Retribution)
    [1329]   = 5,   -- Mutilate (Rogue Assassination)
    [703]    = 5,   -- Garrote (Rogue Assassination)
    [193315] = 5,   -- Sinister Strike (Rogue Outlaw)
    [17364]  = 5,   -- Stormstrike (Shaman Enhancement)
    [60103]  = 5,   -- Lava Lash (Shaman Enhancement)
    [12294]  = 5,   -- Mortal Strike (Warrior Arms)
    [262161] = 5,   -- Warbreaker (Warrior Arms)
    [23881]  = 5,   -- Bloodthirst (Warrior Fury)
    [85288]  = 5,   -- Raging Blow (Warrior Fury)
    [23922]  = 5,   -- Shield Slam (Warrior Protection)
    [6572]   = 5,   -- Revenge (Warrior Protection)
    -- ~8-15yd short
    [5246]   = 8,   -- Intimidating Shout (Warrior)
    [853]    = 10,  -- Hammer of Justice (Paladin)
    [106839] = 13,  -- Skull Bash (Druid - talent+form-gated, but Druid's ONLY short probe → kept; fail-safe when absent)
    [2094]   = 15,  -- Blind (Rogue)
    [47528]  = 15,  -- Mind Freeze (Death Knight)
    -- ~20-30yd mid
    -- Baseline taunts (30yd, fixed, whole-class): not damage/CC like the rest of the
    -- file, but single-ENEMY-targeted with a plain range read, which is all a probe
    -- needs. They exist here because Druid and Monk otherwise have NO baseline probe
    -- between melee and 40 - so a self-centered CC (Incapacitating Roar, Leg Sweep)
    -- could never be proven out of reach at caster range. (Provoke is a scripted
    -- any-target effect rather than a pure harmful one - IsSpellInRange still
    -- answers for a hostile target, verified against the DB2 data.)
    [6795]   = 30,  -- Growl (Druid - baseline, all specs)
    [115546] = 30,  -- Provoke (Monk - baseline, all specs)
    [115078] = 20,  -- Paralysis (Monk - talent, but Monk's only mid probe → kept)
    [351338] = 25,  -- Quell (Evoker)
    [362969] = 25,  -- Azure Strike (Evoker)
    [20271]  = 30,  -- Judgment (Paladin)
    [57755]  = 30,  -- Heroic Throw (Warrior)
    [49576]  = 30,  -- Death Grip (Death Knight - baseline, all specs)
    [185123] = 30,  -- Throw Glaive (Demon Hunter)
    [64044]  = 30,  -- Psychic Horror (Priest - talent, but Priest's only mid probe → kept)
    [57994]  = 30,  -- Wind Shear (Shaman)
    -- ~40yd long (interrupts + caster damage mains)
    [2139]   = 40,  -- Counterspell (Mage)
    [15487]  = 40,  -- Silence (Priest)
    [147362] = 40,  -- Counter Shot (Hunter)
    [116]    = 40,  -- Frostbolt (Mage - Frost/Arcane)
    [133]    = 40,  -- Fireball (Mage - Fire; level-1 nuke, covers low-level Fire)
    [5176]   = 40,  -- Wrath (Druid)
    [585]    = 40,  -- Smite (Priest)
    [589]    = 40,  -- Shadow Word: Pain (Priest)
    [188196] = 40,  -- Lightning Bolt (Shaman)
    [686]    = 40,  -- Shadow Bolt (Warlock)
    [185358] = 40,  -- Arcane Shot (Hunter)
    [56641]  = 40,  -- Steady Shot (Hunter)
    [172]    = 40,  -- Corruption (Warlock - baseline, all specs; covers the no-kick gap)
    [8921]   = 40,  -- Moonfire (Druid - baseline, all specs; covers the talented-interrupt gap)
})
