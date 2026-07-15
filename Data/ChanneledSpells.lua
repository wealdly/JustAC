-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Channeled player spells -> excluded from the move-cast marker.
-- Channeled spells report a base cast time of 0 (like instants), so without this
-- list the "castable while moving" marker would falsely flag them - movement
-- breaks a channel. Derived from SpellMisc.Attributes_1 channel bits (0x4 | 0x40,
-- SPELL_ATTR1_CHANNELED_1 | _2) intersected with the player-castable spell
-- universe, client data build 12.1.0.68301. Base/override IDs preferred; SpellDB's
-- StaticLookup resolves talent variants via GetBaseSpell. Empowered Evoker casts
-- carry the channel bit and are included (excluded from the marker by design).
-- Curated snapshot - re-derive from the channel bit when channels change.
local SpellDB = LibStub("JustAC-SpellDB", true)
if not SpellDB or not SpellDB.RegisterChanneledSpells then return end

SpellDB.RegisterChanneledSpells({
    -- Mage
    [5143]   = true,  -- Arcane Missiles
    [12051]  = true,  -- Evocation
    [314791] = true,  -- Shifting Power
    [205021] = true,  -- Ray of Frost
    -- Priest
    [15407]  = true,  -- Mind Flay
    [263165] = true,  -- Void Torrent
    [205065] = true,  -- Void Torrent (older ID)
    [47540]  = true,  -- Penance
    [64843]  = true,  -- Divine Hymn
    -- Hunter
    [257044] = true,  -- Rapid Fire
    [120360] = true,  -- Barrage
    -- Evoker (Disintegrate + empowered casts)
    [356995] = true,  -- Disintegrate
    [357208] = true,  -- Fire Breath
    [359073] = true,  -- Eternity Surge
    [396286] = true,  -- Upheaval
    [404977] = true,  -- Time Skip
    [355936] = true,  -- Dream Breath
    [367226] = true,  -- Spiritbloom
    [370960] = true,  -- Emerald Communion
    -- Druid
    [391528] = true,  -- Convoke the Spirits
    [323764] = true,  -- Convoke the Spirits (older ID)
    [740]    = true,  -- Tranquility
    -- Demon Hunter
    [198013] = true,  -- Eye Beam
    [212084] = true,  -- Fel Devastation
    [473728] = true,  -- Void Ray
    -- Warlock
    [196447] = true,  -- Channel Demonfire
    [198590] = true,  -- Drain Soul
    [234153] = true,  -- Drain Life
    [417537] = true,  -- Oblivion
    [1257052] = true, -- Dark Harvest
    -- Monk
    [101546] = true,  -- Spinning Crane Kick (Mistweaver)
    [322729] = true,  -- Spinning Crane Kick (Brewmaster)
    [113656] = true,  -- Fists of Fury
    [117952] = true,  -- Crackling Jade Lightning
    [443028] = true,  -- Celestial Conduit
    [1217413] = true, -- Slicing Winds
    [115175] = true,  -- Soothing Mist
    [115176] = true,  -- Zen Meditation
    -- Rogue
    [51690]  = true,  -- Killing Spree
    -- Death Knight
    [1263824] = true, -- Consumption
    [206931] = true,  -- Blooddrinker
    -- Warrior
    [436358] = true,  -- Demolish
})
