-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Curated spell category data (defensive / healing / crowd-control / utility).
-- Moved out of SpellDB.lua; registered into it via RegisterCategories. Logic stays in SpellDB.
local SpellDB = LibStub("JustAC-SpellDB", true)
if not SpellDB or not SpellDB.RegisterCategories then return end

local DEFENSIVE_SPELLS = {
    -- Death Knight
    [48707] = true,   -- Anti-Magic Shell
    [48792] = true,   -- Icebound Fortitude
    [49028] = true,   -- Dancing Rune Weapon (Blood)
    [55233] = true,   -- Vampiric Blood
    [194679] = true,  -- Rune Tap
    -- REMOVED: Blooddrinker (206931) - Blood DK damage channel, rotational DPS
    [219809] = true,  -- Tombstone
    [49039] = true,   -- Lichborne
    [51052] = true,   -- Anti-Magic Zone
    [327574] = true,  -- Sacrificial Pact
    
    -- Demon Hunter
    [187827] = true,  -- Metamorphosis (Vengeance)
    [196555] = true,  -- Netherwalk
    [198589] = true,  -- Blur
    [203720] = true,  -- Demon Spikes
    [204021] = true,  -- Fiery Brand
    -- REMOVED: Fel Devastation (212084) - Core Vengeance DH rotational AoE damage
    [263648] = true,  -- Soul Barrier
    
    -- Druid
    [22812] = true,   -- Barkskin
    [61336] = true,   -- Survival Instincts
    [102342] = true,  -- Ironbark
    [200851] = true,  -- Rage of the Sleeper (Guardian)  [re-ID'd from 106922]
    [108238] = true,  -- Renewal
    [22842] = true,   -- Frenzied Regeneration
    [192081] = true,  -- Ironfur
    -- REMOVED: Earthwarden (203974) - passive talent, not castable
    
    -- Evoker
    [363916] = true,  -- Obsidian Scales
    [370960] = true,  -- Emerald Communion
    [374348] = true,  -- Renewing Blaze
    [357170] = true,  -- Time Dilation
    [374227] = true,  -- Zephyr (group damage reduction)
    [378441] = true,  -- Time Stop
    [406732] = true,  -- Spatial Paradox (also supportive/healing for Preservation)
    [360827] = true,  -- Blistering Scales (Augmentation - shield + thorns)

    -- Hunter
    [186265] = true,  -- Aspect of the Turtle
    [109304] = true,  -- Exhilaration
    [264735] = true,  -- Survival of the Fittest
    [281195] = true,  -- Survival of the Fittest (Lone Wolf)
    [53480] = true,   -- Roar of Sacrifice (Pet)
    -- MOVED: Primal Rage (264667) - Bloodlust variant, classified as utility
    
    -- Mage
    [45438] = true,   -- Ice Block
    -- MOVED: Mirror Image (55342) - DPS cooldown, not defensive
    [66] = true,      -- Invisibility
    [110959] = true,  -- Greater Invisibility
    [235313] = true,  -- Blazing Barrier
    [235450] = true,  -- Prismatic Barrier
    [11426] = true,   -- Ice Barrier
    [342245] = true,  -- Alter Time
    -- MOVED: Ice Floes (108839) - cast-while-moving utility, not defensive
    
    -- Monk
    [115176] = true,  -- Zen Meditation
    [115203] = true,  -- Fortifying Brew
    [116849] = true,  -- Life Cocoon
    [122278] = true,  -- Dampen Harm
    [122783] = true,  -- Diffuse Magic
    [120954] = true,  -- Fortifying Brew (Brewmaster)
    [243435] = true,  -- Fortifying Brew (Mistweaver)
    [201318] = true,  -- Fortifying Brew (Windwalker)
    [322507] = true,  -- Celestial Brew
    [115295] = true,  -- Guard
    -- MOVED: Ring of Peace (116844) - displacement CC, classified as crowd control
    
    -- Paladin
    [403876] = true,  -- Divine Protection
    [642] = true,     -- Divine Shield
    [1022] = true,    -- Blessing of Protection
    [6940] = true,    -- Blessing of Sacrifice
    [31850] = true,   -- Ardent Defender
    [86659] = true,   -- Guardian of Ancient Kings
    [184662] = true,  -- Shield of Vengeance
    [204018] = true,  -- Blessing of Spellwarding
    [228049] = true,  -- Guardian of the Forgotten Queen
    -- REMOVED: Seraphim (152262) - Prot Paladin DPS cooldown
    [378974] = true,  -- Bastion of Light
    [387174] = true,  -- Eye of Tyr
    [389539] = true,  -- Sentinel
    
    -- Priest
    [19236] = true,   -- Desperate Prayer
    [47536] = true,   -- Rapture
    [47585] = true,   -- Dispersion
    [33206] = true,   -- Pain Suppression
    [47788] = true,   -- Guardian Spirit
    [62618] = true,   -- Power Word: Barrier
    [81782] = true,   -- Power Word: Barrier (aura)
    -- REMOVED: Spirit Shell (109964) - removed from game in Dragonflight
    [108968] = true,  -- Void Shift
    [586] = true,     -- Fade
    -- REMOVED: Greater Fade (213602) - spell deleted from game (audit; verified nil in-game)
    [271466] = true,  -- Luminous Barrier
    [372760] = true,  -- Divine Word
    [421453] = true,  -- Ultimate Penitence
    
    -- Rogue
    [1966] = true,    -- Feint
    [5277] = true,    -- Evasion
    [31224] = true,   -- Cloak of Shadows
    [45182] = true,   -- Cheating Death (passive trigger)
    [185311] = true,  -- Crimson Vial
    [114018] = true,  -- Shroud of Concealment
    [1856] = true,    -- Vanish
    
    -- Shaman
    [108271] = true,  -- Astral Shift
    [198103] = true,  -- Earth Elemental
    [207399] = true,  -- Ancestral Protection Totem
    [108281] = true,  -- Ancestral Guidance
    [114052] = true,  -- Ascendance (Restoration)
    [98008] = true,   -- Spirit Link Totem
    -- MOVED: Wind Rush Totem (192077) - movement speed utility, not defensive
    -- REMOVED: Storm Elemental (192249) - offensive DPS cooldown for Elemental Shaman
    -- MOVED: Mana Tide Totem (16191) - mana restoration utility, not defensive
    
    -- Warlock
    [104773] = true,  -- Unending Resolve
    [108416] = true,  -- Dark Pact
    [212295] = true,  -- Nether Ward
    -- MOVED: Mortal Coil (6789) - horror CC, classified as crowd control
    -- REMOVED: Soul Harvester (386997) - hero talent tree name, not a castable spell
    -- REMOVED: Deathbolt (264106) - offensive damage ability, not defensive
    
    -- Warrior
    [871] = true,     -- Shield Wall
    [12975] = true,   -- Last Stand
    [23920] = true,   -- Spell Reflection
    [97462] = true,   -- Rallying Cry
    [118038] = true,  -- Die by the Sword
    [184364] = true,  -- Enraged Regeneration
    [190456] = true,  -- Ignore Pain
    [213871] = true,  -- Bodyguard
    [386208] = true,  -- Defensive Stance
    -- REMOVED: Odyn's Fury (385060) - Fury Warrior major DPS cooldown
    -- REMOVED: Thunderous Roar (384318) - Warrior AoE damage cooldown (bleed)
}

--------------------------------------------------------------------------------
-- HEALING SPELLS: Direct heals, HoTs, healing cooldowns
-- These should NOT appear in DPS queue positions 2+
--------------------------------------------------------------------------------
local HEALING_SPELLS = {
    -- Death Knight
    [48743] = true,   -- Death Pact
    [206940] = true,  -- Mark of Blood
    
    -- Druid
    [774] = true,     -- Rejuvenation
    [8936] = true,    -- Regrowth
    [18562] = true,   -- Swiftmend
    [33763] = true,   -- Lifebloom
    [48438] = true,   -- Wild Growth
    [102351] = true,  -- Cenarion Ward
    -- MOVED: Wild Charge (102401) - movement ability, classified as utility
    [145205] = true,  -- Efflorescence
    [155777] = true,  -- Rejuvenation (Germination)
    [197721] = true,  -- Flourish
    [203651] = true,  -- Overgrowth
    [207385] = true,  -- Spring Blossoms
    [391888] = true,  -- Adaptive Swarm (heal component)
    [740] = true,     -- Tranquility
    [50464] = true,   -- Nourish
    [102693] = true,  -- Grove Guardians
    [33891] = true,   -- Incarnation: Tree of Life
    -- SKIPPED: Convoke the Spirits (391528) - heals as Restoration but is a
    -- damage cooldown for Balance/Feral; a flat entry would exclude it from
    -- their DPS tails. Dual-use spells stay uncategorized.
    
    -- Evoker
    [355913] = true,  -- Emerald Blossom
    [360823] = true,  -- Naturalize
    -- MOVED: Blistering Scales (360827) - defensive shield + thorns, classified as defensive
    [360995] = true,  -- Verdant Embrace
    -- SKIPPED: Living Flame (361469) - one spell ID heals a friendly target or
    -- damages a hostile one; it is Devastation's AND Preservation's rotational
    -- damage filler, so a flat heal entry would strip it from their DPS tails.
    -- Dual-use spells stay uncategorized. [removed from this list 2026-08]
    [363534] = true,  -- Rewind
    [366155] = true,  -- Reversion
    [367226] = true,  -- Spiritbloom
    [382614] = true,  -- Dream Breath (4-stage empower variant)
    [382731] = true,  -- Spiritbloom (4-stage empower variant)  [comment was mislabeled Temporal Anomaly]
    [373861] = true,  -- Temporal Anomaly
    [364343] = true,  -- Echo
    -- MOVED: Ebon Might (395152) - Augmentation buff, classified as utility
    -- MOVED: Prescience (409311) - Augmentation buff, classified as utility
    -- Spatial Paradox (406732) already in DEFENSIVE_SPELLS (primary classification)
    
    -- Monk
    [115175] = true,  -- Soothing Mist
    [116670] = true,  -- Vivify
    [116680] = true,  -- Thunder Focus Tea
    [119611] = true,  -- Renewing Mist
    [124682] = true,  -- Enveloping Mist
    [231633] = true,  -- Essence Font  [re-ID'd from 191837]
    [198898] = true,  -- Song of Chi-Ji
    [205234] = true,  -- Healing Sphere
    [322118] = true,  -- Invoke Yu'lon
    [325197] = true,  -- Invoke Chi-Ji
    [388615] = true,  -- Restoral
    [388193] = true,  -- Faeline Stomp (heal)
    [399491] = true,  -- Sheilun's Gift
    -- SKIPPED: Chi Burst (123986) and Celestial Conduit (443028) - heal as
    -- Mistweaver but are rotational damage for Windwalker; flat entries would
    -- exclude them from its DPS tail. Dual-use spells stay uncategorized.
    
    -- Paladin
    [19750] = true,   -- Flash of Light
    [82326] = true,   -- Holy Light
    [85222] = true,   -- Light of Dawn
    [85673] = true,   -- Word of Glory (can proc free via Divine Purpose)
    [633] = true,     -- Lay on Hands
    [20473] = true,   -- Holy Shock
    [53563] = true,   -- Beacon of Light
    [156910] = true,  -- Beacon of Faith
    -- SKIPPED: Divine Toll (375576) - heals as Holy but is a damage cooldown
    -- for Ret/Prot (role-conditional). Dual-use spells stay uncategorized.
    [114158] = true,  -- Light's Hammer
    [114165] = true,  -- Holy Prism
    -- REMOVED: Light of the Protector (183998) - replaced by Word of Glory
    -- MOVED: Cleanse Toxins (213644) - dispel, classified as utility
    [223306] = true,  -- Bestow Faith
    [200025] = true,  -- Beacon of Virtue
    [216331] = true,  -- Avenging Crusader
    [388007] = true,  -- Blessing of Summer
    [388010] = true,  -- Blessing of Autumn
    [388011] = true,  -- Blessing of Winter
    [388013] = true,  -- Blessing of Spring
    [31821] = true,   -- Aura Mastery
    [4987] = true,    -- Cleanse
    -- REMOVED: Hand of the Protector (213652) - merged into Word of Glory
    
    -- Priest
    [17] = true,      -- Power Word: Shield
    [139] = true,     -- Renew
    [186263] = true,  -- Shadow Mend
    [194509] = true,  -- Power Word: Radiance
    [2050] = true,    -- Holy Word: Serenity
    [2060] = true,    -- Heal
    [2061] = true,    -- Flash Heal
    [32546] = true,   -- Binding Heal
    [34861] = true,   -- Holy Word: Sanctify
    [64843] = true,   -- Divine Hymn
    -- MOVED: Holy Word: Chastise (88625) - damage + incapacitate, classified as CC
    [110744] = true,  -- Divine Star (heal)
    [120517] = true,  -- Halo (heal)
    [200183] = true,  -- Apotheosis
    [204883] = true,  -- Circle of Healing
    -- REMOVED: Greater Heal (289666) - not a learnable spell in retail
    [73325] = true,   -- Leap of Faith
    [596] = true,     -- Prayer of Healing
    [33076] = true,   -- Prayer of Mending
    [527] = true,     -- Purify
    -- Dispel Magic (528) already in UTILITY_SPELLS (primary classification)
    [200829] = true,  -- Plea
    [472433] = true,  -- Evangelism
    [64901] = true,   -- Symbol of Hope
    [265202] = true,  -- Holy Word: Salvation
    -- SKIPPED: Penance (47540) - Discipline's Atonement design makes its damage
    -- cast rotational healing; excluding it from the DPS tail would be wrong.
    
    -- Shaman
    [5394] = true,    -- Healing Stream Totem
    [61295] = true,   -- Riptide
    [73920] = true,   -- Healing Rain
    [77472] = true,   -- Healing Wave
    [8004] = true,    -- Healing Surge
    [108280] = true,  -- Healing Tide Totem
    -- REMOVED: Cloudburst Totem (157153) - spell deleted from game (audit; verified nil in-game)
    [197995] = true,  -- Wellspring
    [198838] = true,  -- Earthen Wall Totem
    [207778] = true,  -- Downpour
    [382024] = true,  -- Earthliving Weapon (imbue)  [comment was mislabeled Primordial Wave]
    [428332] = true,  -- Primordial Wave (Restoration heal variant)
    [1064] = true,    -- Chain Heal
    [974] = true,     -- Earth Shield
    [73685] = true,   -- Unleash Life
    [51886] = true,   -- Cleanse Spirit
    [77130] = true,   -- Purify Spirit
    
    -- Warlock
    [755] = true,     -- Health Funnel (out-of-combat pet healing)
    
    -- Warrior
    [34428] = true,   -- Victory Rush
    [202168] = true,  -- Impending Victory
}

--------------------------------------------------------------------------------
-- CROWD CONTROL SPELLS: Stuns, fears, roots, incapacitates, silences
-- These should NOT appear in DPS queue positions 2+
--------------------------------------------------------------------------------
local CROWD_CONTROL_SPELLS = {
    -- Death Knight
    [47476] = true,   -- Strangulate (silence)
    [47528] = true,   -- Mind Freeze (interrupt)
    [91800] = true,   -- Gnaw (pet stun)
    [108194] = true,  -- Asphyxiate
    [207167] = true,  -- Blinding Sleet
    [221562] = true,  -- Asphyxiate (Blood)
    
    -- Demon Hunter
    [179057] = true,  -- Chaos Nova
    [183752] = true,  -- Disrupt (interrupt)
    [211881] = true,  -- Fel Eruption
    [217832] = true,  -- Imprison
    [207684] = true,  -- Sigil of Misery
    [202137] = true,  -- Sigil of Silence
    
    -- Druid
    [99] = true,      -- Incapacitating Roar
    [339] = true,     -- Entangling Roots
    [2637] = true,    -- Hibernate
    [5211] = true,    -- Mighty Bash
    [22570] = true,   -- Maim
    [33786] = true,   -- Cyclone
    [78675] = true,   -- Solar Beam (interrupt)
    [102359] = true,  -- Mass Entanglement
    [102793] = true,  -- Ursol's Vortex
    [106839] = true,  -- Skull Bash (interrupt)
    [132469] = true,  -- Typhoon (knockback+daze)
    [203123] = true,  -- Maim
    
    -- Evoker
    [351338] = true,  -- Quell (interrupt)
    [360806] = true,  -- Sleep Walk (1.7s cast, incapacitate)
    [372048] = true,  -- Oppressing Roar (CC duration extender)
    -- Note: 357208 is Fire Breath (DPS ability), removed from this exclusion list
    
    -- Hunter
    [1513] = true,    -- Scare Beast
    [5116] = true,    -- Concussive Shot
    [19386] = true,   -- Wyvern Sting
    [24394] = true,   -- Intimidation
    [117405] = true,  -- Binding Shot (root trigger)
    [147362] = true,  -- Counter Shot (interrupt)
    [162488] = true,  -- Steel Trap (root)
    [187650] = true,  -- Freezing Trap
    [186387] = true,  -- Bursting Shot (disorient knockback)
    [187707] = true,  -- Muzzle (interrupt)
    [213691] = true,  -- Scatter Shot
    [236776] = true,  -- Hi-Explosive Trap (knockback)
    
    -- Mage
    [31661] = true,   -- Dragon's Breath
    [33395] = true,   -- Freeze (pet)
    -- REMOVED: Deep Freeze (44572) - removed from game
    [82691] = true,   -- Ring of Frost
    [118] = true,     -- Polymorph
    [122] = true,     -- Frost Nova
    [2139] = true,    -- Counterspell (interrupt)
    [157981] = true,  -- Blast Wave
    [157997] = true,  -- Ice Nova
    [113724] = true,  -- Ring of Frost
    [61305] = true,   -- Polymorph (Black Cat)
    [161353] = true,  -- Polymorph (Polar Bear Cub)
    [161354] = true,  -- Polymorph (Monkey)
    [161355] = true,  -- Polymorph (Penguin)
    [161372] = true,  -- Polymorph (Peacock)
    [126819] = true,  -- Polymorph (Porcupine)
    [28272] = true,   -- Polymorph (Pig)
    [28271] = true,   -- Polymorph (Turtle)
    [61721] = true,   -- Polymorph (Rabbit)
    [61780] = true,   -- Polymorph (Turkey)
    [277787] = true,  -- Polymorph (Direhorn)
    [277792] = true,  -- Polymorph (Bumblebee)
    
    -- Monk
    [115078] = true,  -- Paralysis
    [116705] = true,  -- Spear Hand Strike (interrupt)
    [119381] = true,  -- Leg Sweep
    -- Song of Chi-Ji (198898) already in HEALING_SPELLS (primary classification)
    [116844] = true,  -- Ring of Peace (displacement)
    [233759] = true,  -- Grapple Weapon
    
    -- Paladin
    [853] = true,     -- Hammer of Justice
    [20066] = true,   -- Repentance
    [31935] = true,   -- Avenger's Shield (interrupt)
    [96231] = true,   -- Rebuke (interrupt)
    [105421] = true,  -- Blinding Light
    [115750] = true,  -- Blinding Light
    [10326] = true,   -- Turn Evil
    [217824] = true,  -- Shield of Virtue
    
    -- Priest
    [8122] = true,    -- Psychic Scream
    [9484] = true,    -- Shackle Undead
    [15487] = true,   -- Silence
    [64044] = true,   -- Psychic Horror
    [88625] = true,   -- Holy Word: Chastise (incapacitate)
    -- REMOVED: Mind Bomb (205369) - spell deleted from game (audit; verified nil in-game)
    [605] = true,     -- Mind Control
    
    -- Rogue
    [408] = true,     -- Kidney Shot
    [1330] = true,    -- Garrote - Silence
    [1776] = true,    -- Gouge
    [1833] = true,    -- Cheap Shot
    [2094] = true,    -- Blind
    [6770] = true,    -- Sap
    [1766] = true,    -- Kick (interrupt)
    [315341] = true,  -- Between the Eyes (stun)  [re-ID'd from 199804]
    [207777] = true,  -- Dismantle
    
    -- Shaman
    [51490] = true,   -- Thunderstorm (knockback)
    [51514] = true,   -- Hex
    [57994] = true,   -- Wind Shear (interrupt)
    [64695] = true,   -- Earthgrab Totem
    [77505] = true,   -- Earthquake (stun proc)
    [118905] = true,  -- Static Charge (stun)
    [192058] = true,  -- Capacitor Totem
    [196932] = true,  -- Voodoo Totem
    [197214] = true,  -- Sundering (incap)
    [210873] = true,  -- Hex (Compy)
    [211004] = true,  -- Hex (Spider)
    [211010] = true,  -- Hex (Snake)
    [211015] = true,  -- Hex (Cockroach)
    [269352] = true,  -- Hex (Skeletal Hatchling)
    [277778] = true,  -- Hex (Zandalari Tendonripper)
    [277784] = true,  -- Hex (Wicker Mongrel)
    [309328] = true,  -- Hex (Living Honey)
    
    -- Warlock
    [5484] = true,    -- Howl of Terror
    [6358] = true,    -- Seduction (Succubus)
    [6789] = true,    -- Mortal Coil (horror)
    [19647] = true,   -- Spell Lock (interrupt)
    [30283] = true,   -- Shadowfury
    [89766] = true,   -- Axe Toss (Felguard stun)
    [710] = true,     -- Banish
    [118699] = true,  -- Fear
    [171017] = true,  -- Meteor Strike (Infernal stun)
    [212619] = true,  -- Call Felhunter (interrupt)
    
    -- Warrior
    [5246] = true,    -- Intimidating Shout
    [6552] = true,    -- Pummel (interrupt)
    [46968] = true,   -- Shockwave
    [107570] = true,  -- Storm Bolt
    [132168] = true,  -- Shockwave (stun)
    [132169] = true,  -- Storm Bolt
}

--------------------------------------------------------------------------------
-- UTILITY SPELLS: Movement, dispels, rezzes, taunts, externals, transfers
-- Non-damage abilities that shouldn't appear in DPS queue
-- NOTE: Mobility abilities with significant damage (Heroic Leap, Fel Rush, Charge)
-- are intentionally EXCLUDED from this list so they remain offensive spells in queue
--------------------------------------------------------------------------------
local UTILITY_SPELLS = {
    -- Movement Abilities (pure mobility, no damage)
    [2983] = true,    -- Sprint (Rogue)
    -- REMOVED: Shadowstep (36554) - Offensive gap closer, enables DPS
    [1953] = true,    -- Blink (Mage)
    [212653] = true,  -- Shimmer (Mage)
    [186257] = true,  -- Aspect of the Cheetah (Hunter)
    [781] = true,     -- Disengage (Hunter)
    [109132] = true,  -- Roll (Monk)
    [116841] = true,  -- Tiger's Lust (Monk)
    [1850] = true,    -- Dash (Druid)
    [252216] = true,  -- Tiger Dash (Druid)
    [106898] = true,  -- Stampeding Roar (Druid)
    [111771] = true,  -- Demonic Gateway (Warlock)
    [48265] = true,   -- Death's Advance (DK)
    [212552] = true,  -- Wraith Walk (DK)
    [79206] = true,   -- Spiritwalker's Grace (Shaman)
    [192063] = true,  -- Gust of Wind (Shaman)
    -- REMOVED: Charge (100) - generates rage, enables DPS
    -- REMOVED: Heroic Leap (6544, 52174) - does damage on landing
    [355] = true,     -- Taunt (Warrior)
    [190784] = true,  -- Divine Steed (Paladin)
    -- REMOVED: Fel Rush (195072) - significant DPS ability for Havoc
    -- REMOVED: Infernal Strike (189110) - does damage
    [358267] = true,  -- Hover (Evoker)
    
    -- Taunts (Tank utility)
    [56222] = true,   -- Dark Command (DK)
    [185245] = true,  -- Torment (DH)
    [6795] = true,    -- Growl (Druid)
    [115546] = true,  -- Provoke (Monk)
    [62124] = true,   -- Hand of Reckoning (Paladin)
    -- [355] already listed above (Warrior Taunt)
    
    -- Resurrects
    [2006] = true,    -- Resurrection (Priest)
    [2008] = true,    -- Ancestral Spirit (Shaman)
    [7328] = true,    -- Redemption (Paladin)
    [50769] = true,   -- Revive (Druid)
    [115178] = true,  -- Resuscitate (Monk)
    [361227] = true,  -- Return (Evoker)
    [212056] = true,  -- Absolution (Mass Rez - Priest)
    [212036] = true,  -- Mass Resurrection (generic)
    
    -- Battle Resurrects
    [20484] = true,   -- Rebirth (Druid)
    [212051] = true,  -- Reawaken (Monk)
    [61999] = true,   -- Raise Ally (DK)
    [20707] = true,   -- Soulstone (Warlock)
    [391054] = true,  -- Intercession (Paladin)
    
    -- External Buffs (cast on others)
    [10060] = true,   -- Power Infusion (Priest)
    [29166] = true,   -- Innervate (Druid)
    [1044] = true,    -- Blessing of Freedom (Paladin)
    -- Blessing of Sacrifice (6940) already in DEFENSIVE_SPELLS (primary classification)
    -- Blessing of Protection (1022) already in DEFENSIVE_SPELLS (primary classification)
    -- Blessing of Spellwarding (204018) already in DEFENSIVE_SPELLS (primary classification)
    [80353] = true,   -- Time Warp (Mage)
    [32182] = true,   -- Heroism (Shaman)
    [2825] = true,    -- Bloodlust (Shaman)
    [264667] = true,  -- Primal Rage (Hunter pet Bloodlust)
    [390386] = true,  -- Fury of the Aspects (Evoker)
    [381748] = true,  -- Blessing of the Bronze (Evoker)
    [395152] = true,  -- Ebon Might (Evoker Augmentation buff)
    [409311] = true,  -- Prescience (Evoker Augmentation buff)
    -- REMOVED: Blessing of Salvation (1038) - not in retail
    
    -- Threat Transfers
    [34477] = true,   -- Misdirection (Hunter)
    [57934] = true,   -- Tricks of the Trade (Rogue)
    
    -- Dispels/Purges (offensive dispels are still utility, not DPS)
    [528] = true,     -- Dispel Magic (Priest - can be offensive but utility)
    [370] = true,     -- Purge (Shaman)
    [19801] = true,   -- Tranquilizing Shot (Hunter)
    [30449] = true,   -- Spellsteal (Mage - steals buff, utility)
    [2782] = true,    -- Remove Corruption (Druid)
    [88423] = true,   -- Nature's Cure (Druid)
    [115450] = true,  -- Detox (Monk)
    [218164] = true,  -- Detox (Mistweaver)
    [475] = true,     -- Remove Curse (Mage)
    [2908] = true,    -- Soothe (Druid - enrage dispel)
    [89808] = true,   -- Singe Magic (Warlock Imp dispel)
    [132411] = true,  -- Singe Magic (Command Demon)
    [365585] = true,  -- Expunge (Evoker)
    [374251] = true,  -- Cauterizing Flame (Evoker)
    
    -- Pet Utility
    [2641] = true,    -- Dismiss Pet (Hunter)
    [883] = true,     -- Call Pet 1 (Hunter)
    [83242] = true,   -- Call Pet 2
    [83243] = true,   -- Call Pet 3
    [83244] = true,   -- Call Pet 4
    [83245] = true,   -- Call Pet 5
    [272651] = true,  -- Command Demon (Warlock)
    
    -- Miscellaneous Utility
    [115313] = true,  -- Summon Jade Serpent Statue (Monk)
    [115315] = true,  -- Summon Black Ox Statue (Monk)
    [61304] = true,   -- Spirit Bond (Hunter - passive but can show)
    [1725] = true,    -- Distract (Rogue)
    [921] = true,     -- Pick Pocket (Rogue)
    [3714] = true,    -- Path of Frost (DK)
    [111400] = true,  -- Burning Rush (Warlock)
    [131347] = true,  -- Glide (DH)
    [202138] = true,  -- Sigil of Chains (DH)
    [375087] = true,  -- Dragonriding abilities
    [192077] = true,  -- Wind Rush Totem (Shaman - movement speed)
    [16191] = true,   -- Mana Tide Totem (Shaman - mana restoration)
    [108839] = true,  -- Ice Floes (Mage - cast while moving)
    [102401] = true,  -- Wild Charge (Druid - movement)
    [213644] = true,  -- Cleanse Toxins (Paladin - dispel)
}

SpellDB.RegisterCategories({
    defensive = DEFENSIVE_SPELLS,
    healing   = HEALING_SPELLS,
    cc        = CROWD_CONTROL_SPELLS,
    utility   = UTILITY_SPELLS,
})
