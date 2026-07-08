-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Curated interrupt / crowd-control ability data for the interrupt reminder.
-- Moved out of SpellDB.lua; registered into it via RegisterInterruptAbilities. Logic
-- (resolve, reliability sort, reach filtering) stays in SpellDB.
--
-- FLAT, not class-keyed: ResolveInterruptSpells() filters to abilities THIS character
-- actually knows (IsSpellAvailable), which auto-handles class spells, racials, and
-- multi-class variants without a class/race partition. The intelligent sort (CCTier + pri)
-- replaces the old hand-ordered per-class lists. Entry fields:
--   kind   = "interrupt" (pure lockout kick, works on bosses) | "cc" (filtered vs bosses)
--   mech   = CC mechanic, for the reliability tier (DB2 SpellCategories.Mechanic):
--            12 stun, 9 silence, 14 incapacitate, 2 disorient, 5 fear; nil for kicks.
--            Trigger-based CCs report mech 0 in DB2; hand-set here to the real mechanic.
--   reach  = "ranged" (reach read live via IsSpellInRange) | "pbaoe" (centered/cone)
--   radius = yards, pbaoe only (DB2 SpellRadius); reach proxied vs melee range
--   pri    = intra-tier tiebreaker (lower preferred); carries the old hand-order.
local SpellDB = LibStub("JustAC-SpellDB", true)
if not SpellDB or not SpellDB.RegisterInterruptAbilities then return end

SpellDB.RegisterInterruptAbilities({
    -- Death Knight
    [47528]  = { kind="interrupt", reach="ranged", pri=1 },             -- Mind Freeze
    [108194] = { kind="cc", mech=12, reach="ranged", pri=2 },           -- Asphyxiate
    [221562] = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Asphyxiate (Blood)
    [207167] = { kind="cc", mech=2,  reach="pbaoe", radius=12, pri=4 }, -- Blinding Sleet
    [47476]  = { kind="cc", mech=9,  reach="ranged", pri=5 },           -- Strangulate
    [47481]  = { kind="cc", mech=12, reach="ranged", pri=8 },           -- Gnaw (ghoul pet stun)
    [91800]  = { kind="cc", mech=12, reach="ranged", pri=8 },           -- Gnaw (Dark Transformation)
    -- Demon Hunter
    [183752] = { kind="interrupt", reach="ranged", pri=1 },             -- Disrupt
    [179057] = { kind="cc", mech=12, reach="pbaoe", radius=8, pri=2 },  -- Chaos Nova
    [211881] = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Fel Eruption
    -- Druid
    [106839] = { kind="interrupt", reach="ranged", pri=1 },             -- Skull Bash
    [78675]  = { kind="interrupt", reach="ranged", pri=2 },             -- Solar Beam
    [5211]   = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Mighty Bash
    [99]     = { kind="cc", mech=14, reach="pbaoe", radius=10, pri=4 }, -- Incapacitating Roar
    -- Evoker
    [351338] = { kind="interrupt", reach="ranged", pri=1 },             -- Quell
    -- Hunter
    [147362] = { kind="interrupt", reach="ranged", pri=1 },             -- Counter Shot
    [187707] = { kind="interrupt", reach="ranged", pri=2 },             -- Muzzle
    [24394]  = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Intimidation
    [355589] = { kind="cc", mech=9,  reach="ranged", pri=4 },           -- Wailing Arrow (silence hybrid; cast-variant)
    [392060] = { kind="cc", mech=9,  reach="ranged", pri=4 },           -- Wailing Arrow (silence hybrid; cast-variant)
    -- Mage
    [2139]   = { kind="interrupt", reach="ranged", pri=1 },             -- Counterspell
    [31661]  = { kind="cc", mech=2,  reach="pbaoe", radius=12, pri=2 }, -- Dragon's Breath
    -- Monk
    [116705] = { kind="interrupt", reach="ranged", pri=1 },             -- Spear Hand Strike
    [119381] = { kind="cc", mech=12, reach="pbaoe", radius=6, pri=2 },  -- Leg Sweep
    [115078] = { kind="cc", mech=14, reach="ranged", pri=3 },           -- Paralysis
    -- Paladin
    [96231]  = { kind="interrupt", reach="ranged", pri=1 },             -- Rebuke
    [31935]  = { kind="interrupt", reach="ranged", pri=2 },             -- Avenger's Shield
    [853]    = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Hammer of Justice
    [20066]  = { kind="cc", mech=14, reach="ranged", pri=4 },           -- Repentance
    -- Priest (Mind Bomb 205369 removed/reworked in 12.x - dropped)
    [15487]  = { kind="interrupt", reach="ranged", pri=1 },             -- Silence
    [64044]  = { kind="cc", mech=12, reach="ranged", pri=2 },           -- Psychic Horror
    [8122]   = { kind="cc", mech=5,  reach="pbaoe", radius=8, pri=3 },  -- Psychic Scream (fear)
    -- Rogue
    [1766]   = { kind="interrupt", reach="ranged", pri=1 },             -- Kick
    [2094]   = { kind="cc", mech=2,  reach="ranged", pri=2 },           -- Blind
    [408]    = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Kidney Shot
    [1833]   = { kind="cc", mech=12, reach="ranged", pri=4 },           -- Cheap Shot
    [1776]   = { kind="cc", mech=14, reach="ranged", pri=5 },           -- Gouge
    -- Shaman
    [57994]  = { kind="interrupt", reach="ranged", pri=1 },             -- Wind Shear
    [192058] = { kind="cc", mech=12, reach="ranged", pri=2 },           -- Capacitor Totem
    -- Warlock
    [19647]  = { kind="interrupt", reach="ranged", pri=1 },             -- Spell Lock
    [212619] = { kind="interrupt", reach="ranged", pri=2 },             -- Call Felhunter
    [89766]  = { kind="cc", mech=12, reach="ranged", pri=3 },           -- Axe Toss
    [30283]  = { kind="cc", mech=12, reach="ranged", pri=4 },           -- Shadowfury
    [5484]   = { kind="cc", mech=5,  reach="pbaoe", radius=8, pri=5 },  -- Howl of Terror (fear)
    [6358]   = { kind="cc", mech=10, reach="ranged", pri=8 },           -- Seduction (Succubus pet)
    [115268] = { kind="cc", mech=10, reach="ranged", pri=8 },           -- Mesmerize (Incubus pet)
    -- Warrior
    [6552]   = { kind="interrupt", reach="ranged", pri=1 },             -- Pummel
    [107570] = { kind="cc", mech=12, reach="ranged", pri=2 },           -- Storm Bolt
    [46968]  = { kind="cc", mech=12, reach="pbaoe", radius=10, pri=3 }, -- Shockwave
    [5246]   = { kind="cc", mech=5,  reach="ranged", pri=4 },           -- Intimidating Shout (fear)

    -- Racials. Cross-class (race-gated); IsSpellAvailable filters by race, and for
    -- Arcane Torrent it also auto-picks the player's per-resource variant. pri=9 keeps
    -- them after class abilities within the same reliability tier (racial = fallback).
    [20549]  = { kind="cc", mech=12, reach="pbaoe", radius=8, pri=9 },  -- War Stomp (Tauren)
    [107079] = { kind="cc", mech=14, reach="ranged", pri=9 },           -- Quaking Palm (Pandaren)
    [255654] = { kind="cc", mech=12, reach="ranged", pri=9 },           -- Bull Rush (Highmountain) [+knockback]
    [287712] = { kind="cc", mech=12, reach="ranged", pri=9 },           -- Haymaker (Kul Tiran) [+knockback]
    -- Arcane Torrent (Blood Elf) - AoE silence; one per-resource variant per class.
    [28730]  = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (mana)
    [25046]  = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (energy)
    [50613]  = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (runic power)
    [69179]  = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (rage)
    [80483]  = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (focus)
    [129597] = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (chi)
    [155145] = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (holy power)
    [202719] = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (fury)
    [232633] = { kind="cc", mech=9, reach="pbaoe", radius=8, pri=9 },   -- Arcane Torrent (insanity)
})

-- Enrage dispels ("soothe" family). Shown as a sink-gated green cue over the interrupt
-- slot when the target is ENRAGED (dispel type 9). Kept separate from the interrupt/CC
-- table above because they are enrage-triggered (not cast-triggered) and some are talent-
-- gated dual-purpose spells (Paralysis is also a CC). Derived from DB2 SpellEffect
-- Effect=38 (Dispel) + EffectMiscValue_0=9 (Enrage). `requires` = talent spell(s) that must
-- be known for the dispel to be active (any one satisfies); IsSpellAvailable filters base +
-- talent to the player's class/build, so the list auto-narrows to this character's soothe.
if SpellDB.RegisterSootheAbilities then
    SpellDB.RegisterSootheAbilities({
        [2908]   = { reach="ranged" },                                    -- Soothe (Druid)
        [19801]  = { reach="ranged" },                                    -- Tranquilizing Shot (Hunter)
        [5938]   = { reach="ranged" },                                    -- Shiv (Rogue)
        [115078] = { reach="ranged", requires={457389, 450432, 287599} }, -- Paralysis (Monk) - dispels w/ Pressure Points
        [406971] = { reach="ranged", requires={374346} },                 -- Oppressing Roar (Evoker) - dispels w/ Overawe
    })
end
