-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Database - Native spell classification tables for filtering and categorization
local SpellDB = LibStub:NewLibrary("JustAC-SpellDB", 9)
if not SpellDB then return end

--------------------------------------------------------------------------------
-- DEFENSIVE SPELLS: Major cooldowns, shields, damage reduction, immunities
-- These should NOT appear in DPS queue positions 2+
--------------------------------------------------------------------------------
-- Curated category data lives in Data/SpellCategories.lua (registered below).
local DEFENSIVE_SPELLS = {}
local HEALING_SPELLS = {}
local CROWD_CONTROL_SPELLS = {}
local UTILITY_SPELLS = {}

--- Populate the category tables from Data/SpellCategories.lua. Merges into the
--- existing local table objects so the IsXSpell closures keep seeing the data.
function SpellDB.RegisterCategories(t)
    if type(t) ~= "table" then return end
    if t.defensive then for id in pairs(t.defensive) do DEFENSIVE_SPELLS[id] = true end end
    if t.healing   then for id in pairs(t.healing)   do HEALING_SPELLS[id] = true end end
    if t.cc        then for id in pairs(t.cc)        do CROWD_CONTROL_SPELLS[id] = true end end
    if t.utility   then for id in pairs(t.utility)   do UTILITY_SPELLS[id] = true end end
end

--------------------------------------------------------------------------------
-- API Functions
--------------------------------------------------------------------------------

-- Check if a spell is defensive (should not appear in DPS queue 2+)
function SpellDB.IsDefensiveSpell(spellID)
    if not spellID then return false end
    return DEFENSIVE_SPELLS[spellID] == true
end

-- Check if a spell is a healing spell (should not appear in DPS queue 2+)
function SpellDB.IsHealingSpell(spellID)
    if not spellID then return false end
    return HEALING_SPELLS[spellID] == true
end

-- Check if a spell is crowd control (should not appear in DPS queue 2+)
function SpellDB.IsCrowdControlSpell(spellID)
    if not spellID then return false end
    return CROWD_CONTROL_SPELLS[spellID] == true
end

-- Lazily-built set of pure interrupt spells (type="interrupt" in CLASS_INTERRUPT_DEFAULTS).
-- Interrupts apply a lockout but no CC mechanic — they must not trigger CC-failure learning.
local interruptTypeSpellIDs = nil
local function BuildInterruptTypeSpellIDs()
    interruptTypeSpellIDs = {}
    for _, entries in pairs(SpellDB.CLASS_INTERRUPT_DEFAULTS) do
        for _, entry in ipairs(entries) do
            if entry[2] == "interrupt" then
                interruptTypeSpellIDs[entry[1]] = true
            end
        end
    end
end

-- Returns true if spellID is a pure lockout interrupt (type="interrupt" in CLASS_INTERRUPT_DEFAULTS).
-- Returns false for cc-type entries (stun, silence, incapacitate) even if also in CROWD_CONTROL_SPELLS.
function SpellDB.IsInterruptTypeSpell(spellID)
    if not spellID then return false end
    if not interruptTypeSpellIDs then BuildInterruptTypeSpellIDs() end
    return interruptTypeSpellIDs[spellID] == true
end

-- Silence-class CC: only prevents SPELL casts, not physical channels. In ccOnly mode
-- (uninterruptible cast, which may be physical) the interrupt tracker prefers a stun-class
-- CC that stops anything. From DB2 SpellCategories.Mechanic == 9 (silence) intersected with
-- the CLASS_INTERRUPT_DEFAULTS cc spells; regenerate per patch. Currently just Strangulate.
local SILENCE_CC_SPELLS = { [47476] = true }
function SpellDB.IsSilenceClassCC(spellID)
    return spellID ~= nil and SILENCE_CC_SPELLS[spellID] == true
end

-- Check if a spell is utility (movement, rez, taunt, external, etc.)
function SpellDB.IsUtilitySpell(spellID)
    if not spellID then return false end
    return UTILITY_SPELLS[spellID] == true
end

-- Check if a spell is offensive (NOT defensive, healing, CC, or utility)
-- This is the primary check for DPS queue filtering
function SpellDB.IsOffensiveSpell(spellID)
    if not spellID then return true end  -- Fail-open: unknown = assume offensive
    
    -- If it's in any of the non-offensive tables, it's not offensive
    if DEFENSIVE_SPELLS[spellID] then return false end
    if HEALING_SPELLS[spellID] then return false end
    if CROWD_CONTROL_SPELLS[spellID] then return false end
    if UTILITY_SPELLS[spellID] then return false end
    
    -- Not in any exclusion list = offensive
    return true
end

--------------------------------------------------------------------------------
-- OFFENSIVE SPELL ATTRIBUTES (archetype / range / gate)
-- Flat per-spell map — archetype and range are properties of the spell, so this is
-- robust to talent/priority-queue changes. Used to bias the fixed queue (positions
-- 2+) by the context of Blizzard's position-1 pick:
--   arch  = "st" | "cleave" | "aoe"      → boost same-archetype spells up
--   range = "melee" | "ranged"           → soft-demote melee spells when the
--                                          context spell is ranged (out of melee)
--   gate  = "stealth" | ...              → reserved (not yet filtered; usability
--                                          tint already greys gated spells)
-- Sourced from DB2 (wago.tools): arch from SpellEffect ImplicitTarget + MaxTargets,
-- range from SpellRange. Intended to grow into a full auto-generated table.
--------------------------------------------------------------------------------
-- Spell archetype/range stored as flat tables with interned string values (far less
-- memory than per-spell sub-tables for ~2k spells; lookups stay O(1)). Populated by
-- the generated Data/SpellArchetypes.lua via RegisterArchetypes.
local ARCH  = {}   -- [spellID] = "aoe" | "cleave" | "st"
local RANGE = {}   -- [spellID] = "melee" | "ranged"
local GATE  = {}   -- [spellID] = "stealth" | ...  (reserved; not yet filtered)

-- Hand overrides on top of the generated data: gates, and arch fixes for spells whose
-- damage is indirect (triggered/cloned) and so can't be classified mechanically.
local function ApplyArchOverrides()
    GATE[185438] = "stealth"          -- Shadowstrike (stealth-gated)
    -- ARCH[280719] = "cleave"        -- Secret Technique: AOE via clones (uncomment to boost)
    -- ARCH[426591] = "cleave"        -- Goremaw's Bite: AOE via trigger
end

--- Called by the generated Data/SpellArchetypes.lua. Accepts archetype groups, each a
--- [spellID] = range map: { aoe = {[id]="melee",...}, cleave = {...}, st = {...} }.
--- The grouped/named source stays human-readable; we flatten it into ARCH/RANGE here
--- (the source sub-tables are transient and collected after load).
function SpellDB.RegisterArchetypes(t)
    if type(t) ~= "table" then return end
    if t.aoe    then for id, rng in pairs(t.aoe)    do ARCH[id] = "aoe";    RANGE[id] = rng end end
    if t.cleave then for id, rng in pairs(t.cleave) do ARCH[id] = "cleave"; RANGE[id] = rng end end
    if t.st     then for id, rng in pairs(t.st)     do ARCH[id] = "st";     RANGE[id] = rng end end
    ApplyArchOverrides()
end

--- Archetype ("aoe"/"cleave"/"st") or nil if untagged. Reads with a nil key are safe.
function SpellDB.GetArch(spellID)  return ARCH[spellID]  end
function SpellDB.GetRange(spellID) return RANGE[spellID] end
function SpellDB.GetGate(spellID)  return GATE[spellID]  end

-- Apply overrides immediately so gate entries exist even before (or without) the data file.
ApplyArchOverrides()

--------------------------------------------------------------------------------
-- DEFAULT RESOLUTION HELPERS
-- Shared spec→class fallback logic for all per-spec default tables.
--------------------------------------------------------------------------------

--- Build the spec key ("CLASS_N") for the current player and spec.
--- Returns specKey, playerClass or nil, nil if unavailable.
function SpellDB.GetSpecKey()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil, nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil, playerClass end
    return playerClass .. "_" .. spec, playerClass
end

--- Resolve defaults from a table that supports both spec-level and class-level keys.
--- Tries "CLASS_N" first, then falls back to "CLASS".
--- @param defaultsTable table — e.g. SpellDB.CLASS_DEFENSIVE_DEFAULTS
--- @param specKey string|nil — e.g. "WARRIOR_3" (optional; computed if nil)
--- @param playerClass string|nil — e.g. "WARRIOR" (optional; computed if nil)
--- @return table|nil — the default spell list, or nil
function SpellDB.ResolveDefaults(defaultsTable, specKey, playerClass)
    if not defaultsTable then return nil end
    if not specKey or not playerClass then
        specKey, playerClass = SpellDB.GetSpecKey()
    end
    if specKey and defaultsTable[specKey] then
        return defaultsTable[specKey]
    end
    if playerClass and defaultsTable[playerClass] then
        return defaultsTable[playerClass]
    end
    return nil
end

--------------------------------------------------------------------------------
-- CLASS DEFAULTS: Per-class spell lists for defensive queue feature
-- These are user-configurable starting points, stored in saved variables
--------------------------------------------------------------------------------

-- Unified defensive spells (self-heals first, then major cooldowns).
-- Fast heals / short-CD abilities ranked higher to preserve natural priority.
--
-- Keying convention (matches gap-closers):
--   "CLASS"        = class-level fallback (used when no spec-specific entry exists)
--   "CLASS_N"      = spec-specific override (N = GetSpecialization() index)
-- Resolution order: spec key → class key.  Spec entries are only added where the
-- defaults diverge meaningfully from the class fallback (primarily tank specs and
-- specs with unique defensive tools).  All other specs use the class fallback.
SpellDB.CLASS_DEFENSIVE_DEFAULTS = {
    -- ── Death Knight ────────────────────────────────────────────────────────
    -- Class fallback (Frost/Unholy DPS): quick heal then big CDs
    DEATHKNIGHT   = {49998, 48792, 48707},                     -- Death Strike, Icebound Fortitude, Anti-Magic Shell
    -- Blood (tank): active mitigation first, Death Strike for heal, then big CDs
    DEATHKNIGHT_1 = {49998, 55233, 48792, 48707},              -- Death Strike, Vampiric Blood, IBF, AMS  (Rune Tap removed in 12.0)

    -- ── Demon Hunter ────────────────────────────────────────────────────────
    -- Class fallback (Havoc DPS): Blur, then Darkness
    DEMONHUNTER   = {198589, 196718},                           -- Blur, Darkness  (Netherwalk removed in 12.0)
    -- Vengeance (tank): Soul Cleave heal, Demon Spikes, Fiery Brand, then Blur
    DEMONHUNTER_2 = {228477, 203720, 204021, 198589, 263648},  -- Soul Cleave, Demon Spikes, Fiery Brand, Blur, Soul Barrier

    -- ── Druid ───────────────────────────────────────────────────────────────
    -- Class fallback (Balance/Resto): Regrowth, Barkskin, Renewal
    DRUID         = {8936, 108238, 22812},                     -- Regrowth, Renewal, Barkskin
    -- Feral: Regrowth, Survival Instincts, Barkskin, Renewal
    DRUID_2       = {8936, 61336, 22812, 108238},              -- Regrowth, Survival Instincts, Barkskin, Renewal
    -- Guardian (tank): Frenzied Regen, Ironfur, Barkskin, Survival Instincts, Rage of the Sleeper
    DRUID_3       = {22842, 192081, 22812, 61336, 200851},     -- Frenzied Regen, Ironfur, Barkskin, Survival Instincts, Rage of the Sleeper  (Renewal removed in 12.0)

    -- ── Evoker ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs — Renewing Blaze merged into Obsidian Scales in 12.0)
    EVOKER        = {363916, 360995},                           -- Obsidian Scales, Verdant Embrace

    -- ── Hunter ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs)
    HUNTER        = {109304, 186265, 388035},                  -- Exhilaration, Aspect of the Turtle, Fortitude of the Bear

    -- ── Mage ────────────────────────────────────────────────────────────────
    -- Class fallback (spec-appropriate barrier is auto-learned; list all three so
    -- the one the player actually knows will be shown)
    MAGE          = {11426, 235313, 235450, 45438},            -- Ice/Blazing/Prismatic Barrier, Ice Block  (Greater Invis lost DR in 12.0)

    -- ── Monk ────────────────────────────────────────────────────────────────
    -- Class fallback (Windwalker): Expel Harm, Fortifying Brew, Diffuse Magic
    MONK          = {322101, 115203, 122783},                  -- Expel Harm, Fortifying Brew, Diffuse Magic
    -- Brewmaster (tank): Celestial Brew, Expel Harm, Fortifying Brew  (Dampen Harm removed in 12.0; Diffuse Magic merged into Fortifying Brew talent)
    MONK_1        = {322507, 322101, 120954},                  -- Celestial Brew, Expel Harm, Fortifying Brew
    -- Mistweaver: Fortifying Brew, Diffuse Magic  (Expel Harm removed in 12.0)
    MONK_2        = {115203, 122783},                           -- Fortifying Brew, Diffuse Magic
    -- Windwalker: Expel Harm, Touch of Karma, Fortifying Brew, Diffuse Magic
    MONK_3        = {322101, 122470, 201318, 122783},          -- Expel Harm, Touch of Karma, Fortifying Brew, Diffuse Magic

    -- ── Paladin ─────────────────────────────────────────────────────────────
    -- Class fallback (Holy/Ret): Word of Glory, Divine Protection, Divine Shield, Lay on Hands
    PALADIN       = {85673, 403876, 642, 633},                 -- Word of Glory, Divine Protection, Divine Shield, Lay on Hands
    -- Protection (tank): Shield of the Righteous (rotational but defensive), Ardent Defender,
    -- Guardian of Ancient Kings, Word of Glory, Divine Shield, Lay on Hands
    PALADIN_2     = {85673, 31850, 86659, 642, 633},           -- Word of Glory, Ardent Defender, Guardian of Ancient Kings, Divine Shield, Lay on Hands

    -- ── Priest ──────────────────────────────────────────────────────────────
    -- Class fallback (Holy/Disc): Desperate Prayer, PW:Shield, Fade
    PRIEST        = {19236, 17, 586},                          -- Desperate Prayer, PW:Shield, Fade
    -- Shadow: Desperate Prayer, PW:Shield, Dispersion, Fade
    PRIEST_3      = {19236, 17, 47585, 586},                   -- Desperate Prayer, PW:Shield, Dispersion, Fade

    -- ── Rogue ───────────────────────────────────────────────────────────────
    -- Class fallback (all specs share the same toolkit)
    ROGUE         = {185311, 1966, 31224, 5277},               -- Crimson Vial, Feint, Cloak of Shadows, Evasion

    -- ── Shaman ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs)
    SHAMAN        = {108271, 8004, 198103},                    -- Astral Shift, Healing Surge, Earth Elemental

    -- ── Warlock ─────────────────────────────────────────────────────────────
    -- Class fallback (all specs share dark pact / drain / UR)
    WARLOCK       = {108416, 234153, 104773},                  -- Dark Pact, Drain Life, Unending Resolve

    -- ── Warrior ─────────────────────────────────────────────────────────────
    -- Class fallback (Arms/Fury DPS): Victory Rush, Impending Victory, Ignore Pain, Die by the Sword, Rallying Cry
    WARRIOR       = {34428, 202168, 190456, 118038, 97462},    -- Victory Rush, Impending Victory, Ignore Pain, Die by the Sword, Rallying Cry
    -- Protection (tank): Ignore Pain, Shield Wall, Rallying Cry, Spell Reflection  (Last Stand is now a passive talent in 12.0)
    WARRIOR_3     = {190456, 871, 97462, 23920},               -- Ignore Pain, Shield Wall, Rallying Cry, Spell Reflection
}

-- Pet rez/summon spells (shown when pet is dead or missing — reliable in combat via UnitIsDead/UnitExists)
SpellDB.CLASS_PET_REZ_DEFAULTS = {
    HUNTER = {982, 55709, 883},                      -- Revive Pet, Heart of the Phoenix, Call Pet 1
    WARLOCK = {688, 697, 712, 691, 30146},           -- Summon Imp/Voidwalker/Succubus/Felhunter/Felguard
    DEATHKNIGHT_3 = {46585},                         -- Raise Dead (Unholy only — Blood/Frost ghoul is a Guardian, not a pet)
}

-- Pet heal spells (shown when PET health is low — OUT OF COMBAT ONLY)
-- In 12.0 combat, UnitHealth("pet") is secret so pet heals cannot trigger.
SpellDB.CLASS_PETHEAL_DEFAULTS = {
    HUNTER = {136, 109304},                          -- Mend Pet, Exhilaration (heals pet too)
    WARLOCK = {755},                                 -- Health Funnel
}

-- Interrupt/CC spells for the interrupt reminder feature (priority-ordered per class).
-- Each entry is {spellID, type} where type is:
--   "interrupt" = pure lockout (works on bosses)
--   "cc"       = stun/silence/incapacitate (filtered against boss mobs)
-- First entry is the class's primary interrupt. Subsequent entries are fallbacks
-- shown when earlier spells are on cooldown.
SpellDB.CLASS_INTERRUPT_DEFAULTS = {
    DEATHKNIGHT = {{47528,"interrupt"}, {108194,"cc"}, {221562,"cc"}, {207167,"cc"}, {47476,"cc"}}, -- Mind Freeze, Asphyxiate, Asphyxiate (Blood), Blinding Sleet, Strangulate
    DEMONHUNTER = {{183752,"interrupt"}, {179057,"cc"}, {211881,"cc"}},                     -- Disrupt, Chaos Nova, Fel Eruption
    DRUID       = {{106839,"interrupt"}, {78675,"interrupt"}, {5211,"cc"}, {99,"cc"}},      -- Skull Bash, Solar Beam, Mighty Bash, Incapacitating Roar
    EVOKER      = {{351338,"interrupt"}},                                                  -- Quell (no reliable instant CC fallback: Oppressing Roar buffs CC duration but does not apply CC; Sleep Walk has 1.7s cast time)
    HUNTER      = {{147362,"interrupt"}, {187707,"interrupt"}, {24394,"cc"}},                -- Counter Shot, Muzzle, Intimidation
    MAGE        = {{2139,"interrupt"}, {31661,"cc"}},                                       -- Counterspell, Dragon's Breath
    MONK        = {{116705,"interrupt"}, {119381,"cc"}, {115078,"cc"}},                      -- Spear Hand Strike, Leg Sweep, Paralysis
    PALADIN     = {{96231,"interrupt"}, {31935,"interrupt"}, {853,"cc"}, {20066,"cc"}},      -- Rebuke, Avenger's Shield, Hammer of Justice, Repentance
    PRIEST      = {{15487,"interrupt"}, {64044,"cc"}, {205369,"cc"}, {8122,"cc"}},           -- Silence, Psychic Horror (stun, Shadow), Mind Bomb (silence+disorient), Psychic Scream (AoE fear)
    ROGUE       = {{1766,"interrupt"}, {2094,"cc"}, {408,"cc"}, {1833,"cc"}, {1776,"cc"}},   -- Kick, Blind, Kidney Shot, Cheap Shot (usable after Vanish/Shadow Dance), Gouge
    SHAMAN      = {{57994,"interrupt"}, {192058,"cc"}},                                    -- Wind Shear, Capacitor Totem (Sundering removed: 2s incapacitate breaks from auto-attacks immediately)
    WARLOCK     = {{19647,"interrupt"}, {212619,"interrupt"}, {89766,"cc"}, {30283,"cc"}},   -- Spell Lock, Call Felhunter, Axe Toss, Shadowfury
    WARRIOR     = {{6552,"interrupt"}, {107570,"cc"}, {46968,"cc"}, {5246,"cc"}},            -- Pummel, Storm Bolt, Shockwave, Intimidating Shout
}

-- Gap-closer spells for melee specs (shown when target is out of melee range).
-- Spec-aware: keyed by "CLASS_SPECINDEX" so only melee specs get suggestions.
-- GetSpecialization() returns the spec index (1-4); compose key as CLASS .. "_" .. specIndex.
-- Omitted entries = ranged/healer spec → no gap-closer suggestions.
-- Priority-ordered: first usable spell is shown.
-- Hot-path locals for gap-closer helpers (config-time only, but keep consistent)
local UnitClass = UnitClass
local GetSpecialization = GetSpecialization

SpellDB.CLASS_GAPCLOSER_DEFAULTS = {
    -- Death Knight: all specs are melee
    DEATHKNIGHT_1 = {49576},                         -- Blood: Death Grip
    DEATHKNIGHT_2 = {49576},                         -- Frost: Death Grip
    DEATHKNIGHT_3 = {49576},                         -- Unholy: Death Grip

    -- Demon Hunter: Havoc is melee (spec 1), Vengeance is melee tank (spec 2)
    DEMONHUNTER_1 = {195072},                        -- Havoc: Fel Rush
    -- REMOVED: Vengeful Retreat (198793) - jumps backward, not a gap closer
    DEMONHUNTER_2 = {189110},                        -- Vengeance: Infernal Strike

    -- Druid: Feral (2) and Guardian (3) are melee
    DRUID_2 = {102401},                              -- Feral: Wild Charge
    DRUID_3 = {102401},                              -- Guardian: Wild Charge

    -- Evoker: Augmentation (3) is mid-range, not truly melee — omit all

    -- Hunter: Survival (3) is melee
    HUNTER_3 = {186270},                             -- Survival: Harpoon

    -- Monk: Windwalker (3) is melee, Brewmaster (1) is melee tank
    MONK_1 = {109132, 115008},                       -- Brewmaster: Roll, Chi Torpedo
    MONK_3 = {109132, 115008, 101545},               -- Windwalker: Roll, Chi Torpedo, Flying Serpent Kick

    -- Paladin: Retribution (3) is melee, Protection (2) is melee tank
    PALADIN_2 = {190784},                            -- Protection: Divine Steed
    PALADIN_3 = {190784},                            -- Retribution: Divine Steed

    -- Rogue: all specs are melee
    ROGUE_1 = {36554, 2983},                         -- Assassination: Shadowstep, Sprint
    ROGUE_2 = {36554, 195457, 2983},                 -- Outlaw: Shadowstep, Grappling Hook, Sprint
    ROGUE_3 = {185438, 36554, 2983},                 -- Subtlety: Shadowstrike (stealth), Shadowstep, Sprint

    -- Shaman: Enhancement (2) is melee
    SHAMAN_2 = {192063, 58875},                      -- Enhancement: Gust of Wind, Spirit Walk

    -- Warrior: all specs are melee
    WARRIOR_1 = {100, 6544},                         -- Arms: Charge, Heroic Leap
    WARRIOR_2 = {100, 6544},                         -- Fury: Charge, Heroic Leap
    WARRIOR_3 = {100, 6544},                         -- Protection: Charge, Heroic Leap
}

--------------------------------------------------------------------------------
-- MELEE RANGE REFERENCE SPELLS
-- Two core melee abilities per spec, ordered by priority.  We poll their
-- action-bar slot with IsActionInRange() to decide "out of melee range".
-- [1] = primary (shown as default in options), [2] = hidden backup.
-- The engine tries user override first, then [1], then [2] — first one
-- found on the action bar wins.  Must be reliable, always-known, ~5 yd
-- melee abilities the player is likely to have on their bar.
--------------------------------------------------------------------------------
SpellDB.MELEE_RANGE_REFERENCE_SPELLS = {
    -- Death Knight
    DEATHKNIGHT_1 = {49998, 206930},  -- Blood: Death Strike, Heart Strike
    DEATHKNIGHT_2 = {49020, 49998},   -- Frost: Obliterate, Death Strike
    DEATHKNIGHT_3 = {55090, 49998},   -- Unholy: Scourge Strike, Death Strike

    -- Demon Hunter
    DEMONHUNTER_1 = {162794, 232893}, -- Havoc: Chaos Strike, Felblade
    DEMONHUNTER_2 = {228477, 204513}, -- Vengeance: Soul Cleave, Shear

    -- Druid
    DRUID_2 = {5221, 1822},           -- Feral: Shred, Rake
    DRUID_3 = {33917, 77758},         -- Guardian: Mangle, Thrash

    -- Hunter
    HUNTER_3 = {259387, 186270},      -- Survival: Mongoose Bite, Raptor Strike

    -- Monk
    MONK_1 = {100780, 205523},        -- Brewmaster: Tiger Palm, Blackout Kick
    MONK_3 = {100780, 107428},        -- Windwalker: Tiger Palm, Rising Sun Kick

    -- Paladin
    PALADIN_2 = {35395, 53600},       -- Protection: Crusader Strike, Shield of the Righteous
    PALADIN_3 = {35395, 215661},      -- Retribution: Crusader Strike, Justicar's Vengeance

    -- Rogue (backups must be stealth-stable: primary builders transform
    -- in stealth, but Kidney Shot never changes range)
    ROGUE_1 = {1329, 703},            -- Assassination: Mutilate, Garrote
    ROGUE_2 = {193315, 408},          -- Outlaw: Sinister Strike, Kidney Shot (melee-stable fallback)
    ROGUE_3 = {53, 408},              -- Subtlety: Backstab, Kidney Shot (melee-stable fallback)

    -- Shaman
    SHAMAN_2 = {17364, 60103},        -- Enhancement: Stormstrike, Lava Lash

    -- Warrior
    WARRIOR_1 = {12294, 262161},      -- Arms: Mortal Strike, Warbreaker
    WARRIOR_2 = {23881, 85288},       -- Fury: Bloodthirst, Raging Blow
    WARRIOR_3 = {23922, 6572},        -- Protection: Shield Slam, Revenge
}

--------------------------------------------------------------------------------
-- GAP-CLOSERS THAT ONLY WORK IN STEALTH
-- Spells whose gap-closer (teleport/charge) component requires stealth or
-- Shadow Dance.  The spell itself is usable out of stealth (e.g. Shadowstrike
-- functions as a regular melee attack), but DefensiveEngine should only
-- suggest it as a gap-closer when the player is actually stealthed.
-- Keyed by spell ID → true.
--------------------------------------------------------------------------------
SpellDB.GAP_CLOSER_REQUIRES_STEALTH = {
    [185438] = true,  -- Shadowstrike (Sub Rogue): teleports only in stealth/Shadow Dance
}

--------------------------------------------------------------------------------
-- BURST WINDOW DURATION DEFAULTS (seconds)
-- How long the burst window stays active after trigger fires.
-- Per-spec overrides for specs with shorter/longer burst CDs.
-- Fallback: 10 seconds.
--------------------------------------------------------------------------------
SpellDB.CLASS_BURST_DURATION_DEFAULTS = {
    -- Specs with notably longer burst windows
    DEATHKNIGHT_1 = 15,  -- Dancing Rune Weapon lasts 15s
    DEMONHUNTER_1 = 24,  -- Metamorphosis lasts 24s
    DRUID_2       = 20,  -- Berserk lasts 20s
    DRUID_3       = 15,  -- Guardian Berserk lasts 15s
    MAGE_2        = 12,  -- Combustion lasts 12s
    ROGUE_2       = 20,  -- Adrenaline Rush lasts 20s
    ROGUE_3       = 20,  -- Shadow Blades lasts 20s
    WARRIOR_2     = 12,  -- Recklessness lasts 12s
    WARRIOR_3     = 20,  -- Avatar lasts 20s
    -- Default (10s) is fine for most specs
}

SpellDB.BURST_DURATION_FALLBACK = 10  -- seconds
SpellDB.BURST_TRIGGER_THRESHOLD_DEFAULT = 45  -- seconds; legacy, kept for Options UI compatibility

--------------------------------------------------------------------------------
-- BURST TRIGGER DEFAULTS
-- Per-spec list of major offensive CDs that Blizzard's Assisted Combat will
-- recommend when a burst window is appropriate.  When any of these appear at
-- position 1, the engine activates burst injection.
-- Includes talent alternatives (e.g. Incarnation vs Berserk) — the engine
-- filters by IsSpellAvailable at runtime.
--------------------------------------------------------------------------------
SpellDB.CLASS_BURST_TRIGGER_DEFAULTS = {
    -- Death Knight
    DEATHKNIGHT_1 = {49028},                         -- Blood: Dancing Rune Weapon (120s)
    DEATHKNIGHT_2 = {51271, 152279},                 -- Frost: Pillar of Frost (60s), Breath of Sindragosa (120s)
    DEATHKNIGHT_3 = {63560, 42650},                  -- Unholy: Dark Transformation (60s), Army of the Dead (180s)

    -- Demon Hunter
    DEMONHUNTER_1 = {191427},                        -- Havoc: Metamorphosis (180s)
    DEMONHUNTER_2 = {187827},                        -- Vengeance: Metamorphosis (180s)

    -- Druid
    DRUID_1 = {194223, 102560},                      -- Balance: Celestial Alignment (180s), Incarnation: Chosen of Elune (180s)
    DRUID_2 = {106951, 102543},                      -- Feral: Berserk (180s), Incarnation: Avatar of Ashamane (180s)
    DRUID_3 = {50334, 102558},                       -- Guardian: Berserk (180s), Incarnation: Guardian of Ursoc (180s)

    -- Evoker
    EVOKER_1 = {375087},                             -- Devastation: Dragonrage (120s)
    EVOKER_3 = {403631},                             -- Augmentation: Breath of Eons (120s)

    -- Hunter
    HUNTER_1 = {19574, 359844},                      -- Beast Mastery: Bestial Wrath (90s), Call of the Wild (120s)
    HUNTER_2 = {288613},                             -- Marksmanship: Trueshot (120s)
    HUNTER_3 = {360952},                             -- Survival: Coordinated Assault (120s)

    -- Mage
    MAGE_1  = {365350},                              -- Arcane: Arcane Surge (90s)
    MAGE_2  = {190319},                              -- Fire: Combustion (120s)
    MAGE_3  = {12472},                               -- Frost: Icy Veins (180s)

    -- Monk
    MONK_3  = {137639},                              -- Windwalker: Storm, Earth, and Fire (90s)

    -- Paladin
    PALADIN_2 = {31884},                             -- Protection: Avenging Wrath (120s)
    PALADIN_3 = {31884, 231895},                     -- Retribution: Avenging Wrath (120s), Crusade (120s)

    -- Priest
    PRIEST_3 = {228260, 391109},                     -- Shadow: Void Eruption (90s), Dark Ascension (60s)

    -- Rogue
    ROGUE_1 = {360194},                              -- Assassination: Deathmark (120s)
    ROGUE_2 = {13750},                               -- Outlaw: Adrenaline Rush (180s)
    ROGUE_3 = {121471},                              -- Subtlety: Shadow Blades (180s)

    -- Shaman
    SHAMAN_1 = {114050},                             -- Elemental: Ascendance (180s)
    SHAMAN_2 = {51533},                              -- Enhancement: Feral Spirit (90s)

    -- Warlock
    WARLOCK_1 = {205180},                            -- Affliction: Summon Darkglare (120s)
    WARLOCK_2 = {265187},                            -- Demonology: Summon Demonic Tyrant (120s)
    WARLOCK_3 = {1122},                              -- Destruction: Summon Infernal (180s)

    -- Warrior
    WARRIOR_1 = {167105, 262161},                    -- Arms: Colossus Smash (45s), Warbreaker (45s)
    WARRIOR_2 = {1719},                              -- Fury: Recklessness (90s)
    WARRIOR_3 = {107574},                            -- Protection: Avatar (90s)
}

--------------------------------------------------------------------------------
-- BURST TRIGGER AURA OVERRIDES
-- Maps cast spellID → buff spellID for triggers where the self-buff uses a
-- different spell ID than the cast.  Most CDs share the same ID for cast and
-- buff; only list exceptions here.  BurstInjectionEngine uses this to resolve
-- which aura to scan for during the aura-based burst window.
--------------------------------------------------------------------------------
SpellDB.BURST_TRIGGER_AURA_OVERRIDES = {
    [191427] = 162264,   -- Havoc DH: Metamorphosis cast → Meta buff
}

--- Return the aura spell ID to scan for a given trigger spell.
--- Falls back to the trigger spellID itself when no override exists.
function SpellDB.GetTriggerAuraID(triggerSpellID)
    return SpellDB.BURST_TRIGGER_AURA_OVERRIDES[triggerSpellID] or triggerSpellID
end

--------------------------------------------------------------------------------
-- BURST INJECTION DEFAULTS
-- Per-spec ordered list of spells to inject at position 1 during burst.
-- First usable spell wins. Typically secondary CDs, empowered abilities,
-- or spells the player wants to guarantee during a burst window.
-- Intentionally sparse — users can customize. Ship with known combos only.
--------------------------------------------------------------------------------
SpellDB.CLASS_BURST_INJECTION_DEFAULTS = {
    -- Death Knight
    DEATHKNIGHT_1 = {194844},                        -- Blood: Bonestorm (60s)
    DEATHKNIGHT_2 = {51271},                         -- Frost: Pillar of Frost (60s) — stack during Breath window
    DEATHKNIGHT_3 = {42650},                         -- Unholy: Army of the Dead (180s) — stack during Dark Transformation

    -- Demon Hunter
    DEMONHUNTER_1 = {370965},                        -- Havoc: The Hunt (90s)
    DEMONHUNTER_2 = {187827},                        -- Vengeance: Metamorphosis (180s)

    -- Druid
    DRUID_1 = {391528},                              -- Balance: Convoke the Spirits (120s)
    DRUID_2 = {391528, 274837},                      -- Feral: Convoke the Spirits (120s), Feral Frenzy (45s)
    DRUID_3 = {50334, 102558, 391528},               -- Guardian: Berserk/Incarnation + Convoke

    -- Evoker
    EVOKER_1 = {357210},                             -- Devastation: Deep Breath (120s)
    EVOKER_3 = {403631},                             -- Augmentation: Breath of Eons (120s)

    -- Hunter
    HUNTER_1 = {359844, 321530},                     -- Beast Mastery: Call of the Wild (120s), Bloodshed (60s)
    HUNTER_2 = {260243},                             -- Marksmanship: Volley (45s)
    HUNTER_3 = {203415},                             -- Survival: Fury of the Eagle (45s)

    -- Mage
    MAGE_1  = {321507},                              -- Arcane: Touch of the Magi (45s)
    MAGE_2  = {153561},                              -- Fire: Meteor (45s)
    MAGE_3  = {84714},                               -- Frost: Frozen Orb (60s)

    -- Monk
    MONK_1  = {325153},                              -- Brewmaster: Exploding Keg (60s)
    MONK_3  = {123904},                              -- Windwalker: Invoke Xuen, the White Tiger (120s)

    -- Paladin
    PALADIN_1 = {387174},                            -- Protection: Eye of Tyr (60s)
    PALADIN_3 = {255937},                            -- Retribution: Wake of Ashes (45s)

    -- Priest
    PRIEST_3 = {263165},                             -- Shadow: Void Torrent (45s)

    -- Rogue
    ROGUE_1 = {360194},                              -- Assassination: Deathmark (120s)
    ROGUE_2 = {51690},                               -- Outlaw: Killing Spree (120s)
    ROGUE_3 = {280719},                              -- Subtlety: Secret Technique (45s)

    -- Shaman
    SHAMAN_1 = {114050},                             -- Elemental: Ascendance (180s)
    SHAMAN_2 = {384352},                             -- Enhancement: Doom Winds (60s)

    -- Warlock
    WARLOCK_1 = {386997},                            -- Affliction: Soul Rot (60s)
    WARLOCK_2 = {111898},                            -- Demonology: Grimoire: Felguard (120s)
    WARLOCK_3 = {152108},                            -- Destruction: Cataclysm (45s)

    -- Warrior
    WARRIOR_1 = {107574},                            -- Arms: Avatar (90s)
    WARRIOR_2 = {107574},                            -- Fury: Avatar (90s)
    WARRIOR_3 = {228920},                            -- Protection: Ravager (45s)
}

--- Return the burst injection default list for the current class+spec, or nil.
function SpellDB.GetBurstInjectionDefaults()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    return SpellDB.CLASS_BURST_INJECTION_DEFAULTS[playerClass .. "_" .. spec]
end

--- Return the burst trigger default list for the current class+spec, or nil.
function SpellDB.GetBurstTriggerDefaults()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    return SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[playerClass .. "_" .. spec]
end

--- Return the default burst window duration for the current class+spec.
function SpellDB.GetBurstDurationDefault()
    local _, playerClass = UnitClass("player")
    if not playerClass then return SpellDB.BURST_DURATION_FALLBACK end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return SpellDB.BURST_DURATION_FALLBACK end
    return SpellDB.CLASS_BURST_DURATION_DEFAULTS[playerClass .. "_" .. spec]
        or SpellDB.BURST_DURATION_FALLBACK
end

--- Check whether the current spec has gap-closer defaults (i.e. is a melee spec).
--- Returns true if CLASS_GAPCLOSER_DEFAULTS has an entry for the current class+spec.
function SpellDB.IsMeleeSpec()
    local _, playerClass = UnitClass("player")
    if not playerClass then return false end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return false end
    local key = playerClass .. "_" .. spec
    return SpellDB.CLASS_GAPCLOSER_DEFAULTS[key] ~= nil
end

--- Return the gap-closer default list for the current class+spec, or nil.
function SpellDB.GetGapCloserDefaults()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    return SpellDB.CLASS_GAPCLOSER_DEFAULTS[playerClass .. "_" .. spec]
end

-- Hot-path locals for ResolveInterruptSpells / IsInterruptOnCooldown
local FindSpellOverrideByID = FindSpellOverrideByID
local pcall = pcall
-- NOTE: cachedBlizzardAPI intentionally resolved lazily inside IsInterruptOnCooldown.
-- SpellDB.lua loads BEFORE BlizzardAPI.lua in JustAC.toc, so a file-scope
-- LibStub("JustAC-BlizzardAPI", true) here would always return nil.
local _cachedBlizzardAPIRef = nil
local function GetBlizzardAPI()
    if not _cachedBlizzardAPIRef then
        _cachedBlizzardAPIRef = LibStub("JustAC-BlizzardAPI", true)
    end
    return _cachedBlizzardAPIRef
end

--- Check whether an interrupt/CC spell is on a real cooldown (not just GCD).
--- Delegates to BlizzardAPI.IsSpellReady() which handles the full 12.0 fallback
--- chain: isOnGCD → OOC duration → local cooldown tracking → action bar usability.
--- Interrupt spells are registered for local CD tracking in ResolveInterruptSpells().
--- Fail-open: returns false (spell ready) if anything errors.
function SpellDB.IsInterruptOnCooldown(spellID)
    local api = GetBlizzardAPI()
    if not api or not api.IsSpellReady then return false end
    return not api.IsSpellReady(spellID)
end

--- Resolve the current player's interrupt spell IDs (primary interrupt + CC backups).
--- Returns an ordered array of {spellID, type} entries, or nil if none found.
--- Each entry: {spellID = number, type = "interrupt"|"cc"}
--- Called once during frame/overlay creation; result is cached.
function SpellDB.ResolveInterruptSpells()
    if not SpellDB.CLASS_INTERRUPT_DEFAULTS then return nil end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if not BlizzardAPI or not BlizzardAPI.IsSpellAvailable then return nil end
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local defaults = SpellDB.CLASS_INTERRUPT_DEFAULTS[playerClass]
    if not defaults then return nil end
    local result = {}
    for _, entry in ipairs(defaults) do
        local spellID = entry[1]
        local spellType = entry[2] or "interrupt"
        local resolvedID = spellID
        if FindSpellOverrideByID then
            local ov = FindSpellOverrideByID(spellID)
            if ov and ov ~= 0 and ov ~= spellID then resolvedID = ov end
        end
        if BlizzardAPI.IsSpellAvailable(resolvedID) then
            result[#result + 1] = { spellID = resolvedID, type = spellType }
            -- Register for local cooldown tracking so IsSpellReady() can detect
            -- CD state in combat (isOnGCD is nil for most interrupt spells).
            if BlizzardAPI.RegisterSpellForTracking then
                BlizzardAPI.RegisterSpellForTracking(resolvedID, "interrupt")
            end
        end
    end
    return #result > 0 and result or nil
end

--------------------------------------------------------------------------------
-- Static spell classification tables (shared with RedundancyFilter)
-- Pure data — no dependency on filter state. Maintained here so other modules
-- can reference them without depending on RedundancyFilter.
--------------------------------------------------------------------------------

-- Raid buff spell IDs (includes alternate IDs from 12.0 Midnight Exclusion Whitelist)
SpellDB.RAID_BUFF_SPELLS = {
    [1126] = true,    -- Mark of the Wild (Druid)
    [264778] = true,  -- Mark of the Wild (alternate)
    [21562] = true,   -- Power Word: Fortitude (Priest)
    [264764] = true,  -- Power Word: Fortitude (alternate)
    [6673] = true,    -- Battle Shout (Warrior)
    [264761] = true,  -- Battle Shout (alternate)
    [1459] = true,    -- Arcane Intellect (Mage)
    [264760] = true,  -- Arcane Intellect (alternate)
    [381732] = true,  -- Blessing of the Bronze (Evoker)
}

-- Pet summon spell IDs
SpellDB.PET_SUMMON_SPELLS = {
    -- Hunter
    [883] = true,     -- Call Pet 1
    [83242] = true,   -- Call Pet 2
    [83243] = true,   -- Call Pet 3
    [83244] = true,   -- Call Pet 4
    [83245] = true,   -- Call Pet 5
    -- Warlock
    [688] = true,     -- Summon Imp
    [697] = true,     -- Summon Voidwalker
    [712] = true,     -- Summon Succubus
    [691] = true,     -- Summon Felhunter
    [30146] = true,   -- Summon Felguard
    -- Death Knight
    [46584] = true,   -- Raise Dead (permanent ghoul)
    [46585] = true,   -- Raise Dead (temporary)
    [42650] = true,   -- Army of the Dead
    [49206] = true,   -- Summon Gargoyle
    -- Mage
    [31687] = true,   -- Summon Water Elemental
    -- Shaman
    [51533] = true,   -- Feral Spirit
    [198103] = true,  -- Earth Elemental
    [198067] = true,  -- Fire Elemental
    [192249] = true,  -- Storm Elemental
}

-- Unique aura spell IDs: buffs that can only have one active instance at a time.
-- These are filtered when already active (outside pandemic window).
-- Raid buff IDs are merged in below so this table is the authoritative union.
SpellDB.UNIQUE_AURA_SPELLS = {
    -- Druid Forms
    [768] = true,     -- Cat Form
    [5487] = true,    -- Bear Form
    [783] = true,     -- Travel Form
    [24858] = true,   -- Moonkin Form
    [197625] = true,  -- Moonkin Form (affinity)
    [114282] = true,  -- Tree of Life
    -- Warrior Stances
    [386164] = true,  -- Battle Stance
    [386208] = true,  -- Defensive Stance
    -- Paladin Auras
    [465] = true,     -- Devotion Aura
    [183435] = true,  -- Retribution Aura
    [32223] = true,   -- Crusader Aura
    -- Rogue Stealth
    [1784] = true,    -- Stealth
    [115191] = true,  -- Stealth (Subterfuge)
    -- Hunter Aspects
    [5118] = true,    -- Aspect of the Cheetah
    [186257] = true,  -- Aspect of the Cheetah
    [186265] = true,  -- Aspect of the Turtle
    [186289] = true,  -- Aspect of the Eagle
}

-- Raid buffs are also unique auras (can only have one active) — merge at load time.
for spellID in pairs(SpellDB.RAID_BUFF_SPELLS) do
    SpellDB.UNIQUE_AURA_SPELLS[spellID] = true
end
