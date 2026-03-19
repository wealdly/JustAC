-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Database - Native spell classification tables for filtering and categorization
local SpellDB = LibStub:NewLibrary("JustAC-SpellDB", 9)
if not SpellDB then return end

--------------------------------------------------------------------------------
-- DEFENSIVE SPELLS: Major cooldowns, shields, damage reduction, immunities
-- These should NOT appear in DPS queue positions 2+
--------------------------------------------------------------------------------
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
    [106922] = true,  -- Rage of the Sleeper (Guardian)
    [108238] = true,  -- Renewal
    [22842] = true,   -- Frenzied Regeneration
    [192081] = true,  -- Ironfur
    -- REMOVED: Earthwarden (203974) - passive talent, not castable
    
    -- Evoker
    [363916] = true,  -- Obsidian Scales
    [370960] = true,  -- Emerald Communion
    [374348] = true,  -- Renewing Blaze
    [357170] = true,  -- Time Dilation
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
    [62618] = true,   -- Power Word: Barrier
    [81782] = true,   -- Power Word: Barrier (aura)
    -- REMOVED: Spirit Shell (109964) - removed from game in Dragonflight
    [108968] = true,  -- Void Shift
    [586] = true,     -- Fade
    [213602] = true,  -- Greater Fade
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
    
    -- Evoker
    [355913] = true,  -- Emerald Blossom
    [360823] = true,  -- Naturalize
    -- MOVED: Blistering Scales (360827) - defensive shield + thorns, classified as defensive
    [360995] = true,  -- Verdant Embrace
    [361469] = true,  -- Living Flame (heal)
    [363534] = true,  -- Rewind
    [366155] = true,  -- Reversion
    [367226] = true,  -- Spiritbloom
    [382614] = true,  -- Dream Breath
    [382731] = true,  -- Temporal Anomaly
    -- MOVED: Ebon Might (395152) - Augmentation buff, classified as utility
    -- MOVED: Prescience (409311) - Augmentation buff, classified as utility
    -- Spatial Paradox (406732) already in DEFENSIVE_SPELLS (primary classification)
    
    -- Monk
    [115175] = true,  -- Soothing Mist
    [116670] = true,  -- Vivify
    [116680] = true,  -- Thunder Focus Tea
    [119611] = true,  -- Renewing Mist
    [124682] = true,  -- Enveloping Mist
    [191837] = true,  -- Essence Font
    [198898] = true,  -- Song of Chi-Ji
    [205234] = true,  -- Healing Sphere
    [322118] = true,  -- Invoke Yu'lon
    [325197] = true,  -- Invoke Chi-Ji
    [388615] = true,  -- Restoral
    [388193] = true,  -- Faeline Stomp (heal)
    
    -- Paladin
    [19750] = true,   -- Flash of Light
    [82326] = true,   -- Holy Light
    [85222] = true,   -- Light of Dawn
    [85673] = true,   -- Word of Glory (can proc free via Divine Purpose)
    [633] = true,     -- Lay on Hands
    [20473] = true,   -- Holy Shock
    [53563] = true,   -- Beacon of Light
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
    
    -- Shaman
    [5394] = true,    -- Healing Stream Totem
    [61295] = true,   -- Riptide
    [73920] = true,   -- Healing Rain
    [77472] = true,   -- Healing Wave
    [8004] = true,    -- Healing Surge
    [108280] = true,  -- Healing Tide Totem
    [157153] = true,  -- Cloudburst Totem
    [197995] = true,  -- Wellspring
    [198838] = true,  -- Earthen Wall Totem
    [207778] = true,  -- Downpour
    [382024] = true,  -- Primordial Wave (heal component)
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
    [357208] = true,  -- Oppressing Roar
    [360806] = true,  -- Sleep Walk
    [372048] = true,  -- Oppressing Roar
    
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
    [205369] = true,  -- Mind Bomb
    [605] = true,     -- Mind Control
    
    -- Rogue
    [408] = true,     -- Kidney Shot
    [1330] = true,    -- Garrote - Silence
    [1776] = true,    -- Gouge
    [1833] = true,    -- Cheap Shot
    [2094] = true,    -- Blind
    [6770] = true,    -- Sap
    [1766] = true,    -- Kick (interrupt)
    [199804] = true,  -- Between the Eyes (stun)
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

-- Legacy tables (kept for migration from older versions)
SpellDB.CLASS_SELFHEAL_DEFAULTS = {
    DEATHKNIGHT = {49998},
    DEMONHUNTER = {198589, 228477},
    DRUID = {8936, 22842, 108238, 22812},
    EVOKER = {363916, 360995},
    HUNTER = {109304},
    MAGE = {11426, 235313, 235450},
    MONK = {322101},
    PALADIN = {85673, 403876},
    PRIEST = {19236, 17},
    ROGUE = {185311, 1966},
    SHAMAN = {108271, 8004},
    WARLOCK = {108416, 234153},
    WARRIOR = {34428, 202168, 190456},
}

SpellDB.CLASS_COOLDOWN_DEFAULTS = {
    DEATHKNIGHT = {48792, 48707},
    DEMONHUNTER = {196718},                                  -- Netherwalk removed in 12.0
    DRUID = {61336},
    EVOKER = {},                                             -- Renewing Blaze merged into Obsidian Scales in 12.0
    HUNTER = {186265, 388035},
    MAGE = {45438},                                         -- Greater Invis lost DR in 12.0
    MONK = {115203, 122470, 122783},
    PALADIN = {642, 633},
    PRIEST = {47585, 586},
    ROGUE = {31224, 5277},
    SHAMAN = {198103},
    WARLOCK = {104773},
    WARRIOR = {871, 118038, 97462},
}
-- NOTE: Rune Tap (194679), Dampen Harm (122278), Last Stand (12975) removed/made passive in 12.0
-- Netherwalk (196555), Renewing Blaze (374348) removed/merged in 12.0

-- Pet rez/summon spells (shown when pet is dead or missing — reliable in combat via UnitIsDead/UnitExists)
SpellDB.CLASS_PET_REZ_DEFAULTS = {
    HUNTER = {982, 55709, 883},                      -- Revive Pet, Heart of the Phoenix, Call Pet 1
    WARLOCK = {688, 697, 712, 691, 30146},           -- Summon Imp/Voidwalker/Succubus/Felhunter/Felguard
    DEATHKNIGHT = {46585},                           -- Raise Dead
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
    EVOKER      = {{351338,"interrupt"}, {357208,"cc"}},                                    -- Quell, Oppressing Roar
    HUNTER      = {{147362,"interrupt"}, {187707,"interrupt"}, {24394,"cc"}},                -- Counter Shot, Muzzle, Intimidation
    MAGE        = {{2139,"interrupt"}, {31661,"cc"}},                                       -- Counterspell, Dragon's Breath
    MONK        = {{116705,"interrupt"}, {119381,"cc"}, {115078,"cc"}},                      -- Spear Hand Strike, Leg Sweep, Paralysis
    PALADIN     = {{96231,"interrupt"}, {31935,"interrupt"}, {853,"cc"}, {20066,"cc"}},      -- Rebuke, Avenger's Shield, Hammer of Justice, Repentance
    PRIEST      = {{15487,"interrupt"}, {8122,"cc"}, {205369,"cc"}, {64044,"cc"}},           -- Silence, Psychic Scream, Mind Bomb, Psychic Horror
    ROGUE       = {{1766,"interrupt"}, {408,"cc"}, {1833,"cc"}, {1776,"cc"}},                -- Kick, Kidney Shot, Cheap Shot, Gouge
    SHAMAN      = {{57994,"interrupt"}, {192058,"cc"}, {197214,"cc"}},                       -- Wind Shear, Capacitor Totem, Sundering
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
local cachedBlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

--- Check whether an interrupt/CC spell is on a real cooldown (not just GCD).
--- Delegates to BlizzardAPI.IsSpellReady() which handles the full 12.0 fallback
--- chain: isOnGCD → OOC duration → local cooldown tracking → action bar usability.
--- Interrupt spells are registered for local CD tracking in ResolveInterruptSpells().
--- Fail-open: returns false (spell ready) if anything errors.
function SpellDB.IsInterruptOnCooldown(spellID)
    if not cachedBlizzardAPI or not cachedBlizzardAPI.IsSpellReady then return false end
    return not cachedBlizzardAPI.IsSpellReady(spellID)
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
