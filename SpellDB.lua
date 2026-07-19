-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Database - Native spell classification tables for filtering and categorization
local SpellDB = LibStub:NewLibrary("JustAC-SpellDB", 13)
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
-- Curated interrupt/CC ability data lives in Data/InterruptAbilities.lua (registered below).
-- Flat [spellID] = {kind, mech, reach, radius, pri}; see that file for the field contract.
local INTERRUPT_ABILITIES = {}
local SOOTHE_ABILITIES    = {}  -- enrage-dispel abilities (Data/InterruptAbilities.lua); see ResolveSootheSpells
-- Curated range-reference abilities live in Data/RangeReferences.lua (registered below).
-- [spellID] = max range in yards. On-target harmful abilities (damage + CC) with stable,
-- known ranges, used as distance probes: IsSpellInRange (a non-secret boolean - only the
-- yardage is secret) on each KNOWN reference brackets the target's distance. See IsTargetWithin.
local RANGE_REFERENCES = {}

-- Ranked health-restoring consumables (Data/HealingItems.lua); see GetBestHealingItem.
local HEALING_ITEMS = {}
local bestHealingItem = nil    -- cached best owned item id, or nil
local healingBagsDirty = true  -- bags changed; re-scan on next OOC GetBestHealingItem

--- Populate the category tables from Data/SpellCategories.lua. Merges into the
--- existing local table objects so the IsXSpell closures keep seeing the data.
function SpellDB.RegisterCategories(t)
    if type(t) ~= "table" then return end
    if t.defensive then for id in pairs(t.defensive) do DEFENSIVE_SPELLS[id] = true end end
    if t.healing   then for id in pairs(t.healing)   do HEALING_SPELLS[id] = true end end
    if t.cc        then for id in pairs(t.cc)        do CROWD_CONTROL_SPELLS[id] = true end end
    if t.utility   then for id in pairs(t.utility)   do UTILITY_SPELLS[id] = true end end
end

--- Populate the interrupt/CC ability list from Data/InterruptAbilities.lua. Merges into
--- the existing local table so ResolveInterruptSpells/BuildInterruptTypeSpellIDs see it.
function SpellDB.RegisterInterruptAbilities(t)
    if type(t) ~= "table" then return end
    for id, meta in pairs(t) do INTERRUPT_ABILITIES[id] = meta end
end

--- Populate the enrage-dispel ("soothe") ability list from Data/InterruptAbilities.lua.
--- Kept separate from the interrupt/CC table: enrage-triggered (not cast-triggered), and
--- some entries are talent-gated dual-purpose spells (e.g. Paralysis is also a CC).
function SpellDB.RegisterSootheAbilities(t)
    if type(t) ~= "table" then return end
    for id, meta in pairs(t) do SOOTHE_ABILITIES[id] = meta end
end

--- Populate the range-reference list from Data/RangeReferences.lua.
function SpellDB.RegisterRangeReferences(t)
    if type(t) ~= "table" then return end
    for id, yards in pairs(t) do RANGE_REFERENCES[id] = yards end
end

--- Populate the ranked healing-item list from Data/HealingItems.lua (best first).
function SpellDB.RegisterHealingItems(t)
    if type(t) ~= "table" then return end
    for i = 1, #t do HEALING_ITEMS[i] = t[i] end
    healingBagsDirty = true
end

--- Mark the bag scan stale (call on BAG_UPDATE / zone-in so leveling pot swaps are caught).
function SpellDB.MarkHealingBagsDirty()
    healingBagsDirty = true
end

-- Reads a healing item's heal from its ITEM tooltip's "Use:" line. Returns the effective
-- heal (for ranking owned pots), whether it is percentage-based, and the raw number
-- behind it (the percent, or the fixed amount). A percentage pot ("Restores 50% ...")
-- scales with max health; a fixed pot uses its largest heal number. The '%' symbol and
-- the digits are locale-independent; all-zero if the tooltip can't be read yet (item data
-- loads async), which keeps the scan dirty rather than ranking the pot at zero.
--
-- The ITEM tooltip is the only source carrying item context, and that is load-bearing:
-- a pot family's variants all share ONE on-use spell whose heal effect is item-level
-- scaled (zero base points), so C_Spell.GetSpellDescription(spellID) cannot tell a 295
-- from a 278 and renders neither's real number. Reading the spell ranked every variant
-- identically and let a flat-heal pot outrank a strictly better scaled one.
local ONUSE_PREFIX = ITEM_SPELL_TRIGGER_ONUSE or "Use:"  ---@diagnostic disable-line: undefined-global
local function HealInfo(itemID)
    local getItemTooltip = C_TooltipInfo and C_TooltipInfo.GetItemByID
    local data = getItemTooltip and getItemTooltip(itemID)
    local desc
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            if text and text:find(ONUSE_PREFIX, 1, true) then desc = text; break end
        end
    end
    if not desc or desc == "" then return 0, false, 0 end
    local pct = desc:match("(%d+)%s*%%")
    if pct then
        pct = tonumber(pct)
        return (pct / 100) * (UnitHealthMax("player") or 0), true, pct
    end
    local best = 0
    for n in desc:gmatch("%d[%d,]*") do
        local num = tonumber((n:gsub(",", "")))
        if num and num > best then best = num end
    end
    return best, false, best
end

--- Best health-restoring item the player currently owns, or nil. Scans out of combat
--- (GetItemCount + tooltips are readable there) and caches until bags change. Ranks
--- by effective heal so a percentage pot is compared correctly against a fixed one;
--- exact ties fall back to the list's recency order. A scan with any owned pot still
--- unreadable stays dirty and re-runs rather than latching a partial ranking.
function SpellDB.GetBestHealingItem()
    if healingBagsDirty and not InCombatLockdown() then
        bestHealingItem = nil
        local bestHeal = -1
        local allReadable = true
        for i = 1, #HEALING_ITEMS do
            local id = HEALING_ITEMS[i]
            if (GetItemCount(id) or 0) > 0 then
                local heal = HealInfo(id)
                if heal <= 0 then allReadable = false end
                if heal > bestHeal then
                    bestHeal = heal
                    bestHealingItem = id
                end
            end
        end
        -- Tooltips load async, so an owned pot that read as 0 is "not loaded yet", not
        -- "heals nothing" - latching that ranks it below every pot that did load. Stay
        -- dirty and re-scan on the next OOC build; the pick is still served meanwhile,
        -- it just isn't final. ponytail: rescans while ANY owned pot is unreadable.
        -- Bags cache within seconds of login so this converges and then never runs
        -- again; if a pot ever parses to 0 permanently, cap the retries.
        healingBagsDirty = not allReadable
    end
    return bestHealingItem
end

--- Detail about the current auto-best pot, for the options tooltip: a table
--- { id, name, isPct, value, heal, owned } or nil. Out of combat only (reads
--- descriptions / max health). `value` is the percent (isPct) or the fixed amount.
function SpellDB.GetBestHealingItemInfo()
    if InCombatLockdown() then return nil end
    local id = SpellDB.GetBestHealingItem()
    if not id then return nil end
    local heal, isPct, value = HealInfo(id)
    local owned = 0
    for i = 1, #HEALING_ITEMS do
        if (GetItemCount(HEALING_ITEMS[i]) or 0) > 0 then owned = owned + 1 end
    end
    return { id = id, name = (GetItemInfo(id)) or ("item " .. id),
             isPct = isPct, value = value, heal = heal, owned = owned }
end

-- Reserved sentinel id for the user-positioned "Emergency Potion" tile in the defensive
-- list. Resolved at queue-build to the chosen/best owned healing item; never a real item.
SpellDB.EMERGENCY_POTION = -9000000

-- Recuperate: cross-class out-of-combat self-heal (auto-learned, "All Classes" skill
-- line; not castable in combat). Casting 1231411 applies the 1231418 heal-over-time.
SpellDB.RECUPERATE = 1231411
SpellDB.RECUPERATE_AURA = 1231418

--------------------------------------------------------------------------------
-- Generated client-data tables (registered by Data/ files at load)
--------------------------------------------------------------------------------

-- Static tables key by BASE spell IDs (client records); the queue often carries
-- talent-OVERRIDE IDs. On a miss, retry the lookup on the base spell so overrides
-- inherit the base spell's gates and classification (FormCache self-normalizes;
-- these accessors previously did not). Override->base mapping is immutable client
-- data, so the cache never needs invalidation. SpellDB loads before BlizzardAPI,
-- so raw issecretvalue is used here instead of BlizzardAPI.Unsecret.
local C_Spell_GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
local baseIDCache = {}
local function StaticLookup(t, spellID)
    if not t or not spellID then return nil end
    local v = t[spellID]
    if v ~= nil or not C_Spell_GetBaseSpell then return v end
    local base = baseIDCache[spellID]
    if base == nil then
        local ok, b = pcall(C_Spell_GetBaseSpell, spellID)
        base = (ok and type(b) == "number" and b > 0) and b or false
        baseIDCache[spellID] = base
    end
    if base and base ~= spellID then return t[base] end
    return nil
end

-- Distinct base spell of a talent-override variant, or nil when there is none
-- (self is its own base, or C_Spell.GetBaseSpell is unavailable). Shares
-- StaticLookup's cache; exposed so other modules reuse this resolution instead
-- of maintaining their own override->base cache.
function SpellDB.GetBaseSpell(spellID)
    if not spellID or not C_Spell_GetBaseSpell then return nil end
    local base = baseIDCache[spellID]
    if base == nil then
        local ok, b = pcall(C_Spell_GetBaseSpell, spellID)
        base = (ok and type(b) == "number" and b > 0) and b or false
        baseIDCache[spellID] = base
    end
    if base and base ~= spellID then return base end
    return nil
end

-- Aura max stacks: generated table only. The live equivalent
-- (C_UnitAuras.GetSpellMaxCumulativeAuraApplications) THROWS from addon code
-- for every spell tested - non-stacking AND stacking (Ironfur), in-game
-- 12.0.7 2026-07-05 - so there is no live front to prefer. The validate
-- suite keeps a tripwire probe in case a patch makes it callable.
local auraMaxStacks
function SpellDB.RegisterAuraStacks(t) auraMaxStacks = t end
function SpellDB.GetAuraMaxStacks(spellID)
    return StaticLookup(auraMaxStacks, spellID)
end

-- Pure self-buff spells: live classifier first. C_Spell.IsSelfBuff (plain bool,
-- combat-safe) plus the max-stacks veto reconstructs "non-stacking self-applied
-- aura" - the veto keeps application-stacking buffs (Ironfur-style) suggestable,
-- the pitfall the generated table avoids by construction. Table as fallback.
local C_Spell_IsSelfBuff = C_Spell and C_Spell.IsSelfBuff
local selfAuras
function SpellDB.RegisterSelfAuras(t) selfAuras = t end
function SpellDB.IsPureSelfAura(spellID)
    if C_Spell_IsSelfBuff and spellID then
        local ok, v = pcall(C_Spell_IsSelfBuff, spellID)
        if ok and type(v) == "boolean" then
            return v and SpellDB.GetAuraMaxStacks(spellID) == nil
        end
    end
    return selfAuras ~= nil and StaticLookup(selfAuras, spellID) == true
end

-- Maintained enemy DoT applicators (generated): rotation cast spells that apply
-- a non-stacking periodic-damage debuff to the target, mapped to the debuff's
-- estimated duration in seconds (0 = unknown). DotTracker sinks these in
-- positions 2+ while their debuff is live on the current target, un-sinking ~30%
-- before the duration estimate (pandemic refresh window). Stacking DoTs and
-- channels are excluded by the generator, so a hit here is always safe to sink.
-- StaticLookup resolves talent-override / base IDs the same as the other tables.
local targetDots
function SpellDB.RegisterTargetDots(t) targetDots = t end
function SpellDB.IsTargetDot(spellID)
    return targetDots ~= nil and StaticLookup(targetDots, spellID) ~= nil
end
--- Estimated debuff duration in seconds for a tracked DoT, or nil if unknown.
function SpellDB.GetTargetDotDuration(spellID)
    local d = targetDots ~= nil and StaticLookup(targetDots, spellID)
    return (d and d > 0) and d or nil
end

-- Channeled player spells (curated from the SpellMisc channel bit). Channels
-- report cast time 0 like instants, so the move-cast marker excludes these -
-- movement breaks a channel. StaticLookup resolves talent-override / base IDs.
local channeledSpells
function SpellDB.RegisterChanneledSpells(t) channeledSpells = t end
function SpellDB.IsChanneled(spellID)
    return channeledSpells ~= nil and StaticLookup(channeledSpells, spellID) == true
end

-- Form / stealth / caster-aura CASTABILITY gating was removed: the never-secret
-- C_Spell.IsSpellUsable evaluates all of it live (form, talents incl. form-bypass
-- hero talents, stealth, and cast-condition auras), so SpellQueue and the
-- defensive engine gate on that directly. The generated FormRequirements/
-- AuraRequirements data files and their generators were deleted with it.
-- Kept accessors below (GetAuraMaxStacks, IsPureSelfAura) are REDUNDANCY data,
-- not usability, and have no live equivalent.

--- Health items the player currently owns, best-first: { {id=, name=}, ... }. Feeds the
--- Emergency Potion tile's dropdown. Out of combat only (item names); call lazily.
function SpellDB.GetOwnedHealingItems()
    local owned = {}
    for i = 1, #HEALING_ITEMS do
        local id = HEALING_ITEMS[i]
        if (GetItemCount(id) or 0) > 0 then
            owned[#owned + 1] = { id = id, name = (GetItemInfo(id)) or ("Item " .. id) }
        end
    end
    return owned
end

--------------------------------------------------------------------------------
-- PRE-COMBAT BUFFS: flasks, food, augment runes, weapon enchants (Data/PrecombatBuffs.lua)
-- category -> { items = { {id, buff, stat, source}, ... }, buffSet = { [spellID]=true } }.
-- buffSet is the aura set the engine checks to know if a category is satisfied; items
-- drive the owns-gate / best-owned pick. source: "item" (bag) | "toy" | "spell".
--------------------------------------------------------------------------------
local PRECOMBAT_BUFFS = {}
local PRECOMBAT_ORDER = {}  -- categories in registration order (stable display order)
local PRECOMBAT_ITEM_SET = {}  -- every bag-item buff id, for IsPrecombatBuffItem (click layers)
local PRECOMBAT_ITEM_CATEGORY = {}  -- bag-item buff id -> category ("flask"/"food"/…)

local function AddPrecombatEntry(cat, e)
    if not cat or type(e) ~= "table" or not e.id then return end
    local bucket = PRECOMBAT_BUFFS[cat]
    if not bucket then
        bucket = { items = {}, buffSet = {} }
        PRECOMBAT_BUFFS[cat] = bucket
        PRECOMBAT_ORDER[#PRECOMBAT_ORDER + 1] = cat
    end
    e.source = e.source or "item"
    bucket.items[#bucket.items + 1] = e
    if e.buff then bucket.buffSet[e.buff] = true end
    if e.source == "item" then
        PRECOMBAT_ITEM_SET[e.id] = true
        PRECOMBAT_ITEM_CATEGORY[e.id] = cat
    end
end

--- True if itemID is any registered pre-combat buff consumable. Lets the defensive render
--- recognise inserted buff icons so the click-layer overlay can sit on exactly those.
function SpellDB.IsPrecombatBuffItem(itemID)
    return itemID ~= nil and PRECOMBAT_ITEM_SET[itemID] == true
end

--- Category of a buff item ("flask"/"food"/…), or nil. Lets the render pick the food icon.
function SpellDB.GetPrecombatBuffCategory(itemID)
    return itemID and PRECOMBAT_ITEM_CATEGORY[itemID] or nil
end

-- Eating/drinking is aura-based (not a spell channel) and uses a generic "Food"/"Drink"
-- aura separate from the food's on-use spell - so the queue can show an eat-progress sweep.
-- Each food generation has its own aura id (200+ across expansions); the full set is
-- generated into Data/PrecombatBuffs.lua (RegisterEatingAuras below) from the DB2 trigger
-- chains. The seeds here are live-verified fallbacks in case the data file is missing.
-- A missing id silently disables the eat sweep and "wait" hint for that food: verify with
-- /jac inspect auras while eating, regenerate via tools/gen_precombat_buffs.py.
local EATING_AURAS = { [452276] = true, [396918] = true }

--- Called by the generated Data/PrecombatBuffs.lua with the full eating-aura id list.
function SpellDB.RegisterEatingAuras(ids)
    if type(ids) ~= "table" then return end
    for i = 1, #ids do EATING_AURAS[ids[i]] = true end
end

--- Register extra "Well Fed" family aura ids into the food category's buffSet. The adaptive
--- Midnight feast foods apply their stat by server script (not tied to the item), landing one
--- of the per-secondary "Well Fed" buffs - so no single food ENTRY can carry the right buff.
--- Registering the whole family lets the food category detect "fed" regardless of which dish
--- (and resulting stat) the player ate. Generated into Data/PrecombatBuffs.lua.
function SpellDB.RegisterFoodWellFedBuffs(ids)
    if type(ids) ~= "table" then return end
    local food = PRECOMBAT_BUFFS and PRECOMBAT_BUFFS.food
    if not food then return end
    food.buffSet = food.buffSet or {}
    for i = 1, #ids do food.buffSet[ids[i]] = true end
end

--- The player's active eating/drinking aura (with timing), or nil.
--- The set is too large to probe id-by-id, so scan the player's buffs and test set
--- membership. Combat bail is correctness, not just cost: you can't eat in combat.
--- 12.0.7: some aura spellIds are secret even OUT of combat (secret table keys throw),
--- so those auras are skipped - their identity is unknowable here. Memoized briefly -
--- called per render frame while a food suggestion is displayed.
local eatCache, eatCacheAt = nil, 0
function SpellDB.GetActiveEatingAura()
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get or UnitAffectingCombat("player") then return nil end
    local now = GetTime()
    if now - eatCacheAt < 0.2 then return eatCache end
    eatCacheAt = now
    eatCache = nil
    for i = 1, 60 do
        local a = get("player", i, "HELPFUL")
        if not a then break end
        if a.spellId and not (issecretvalue and issecretvalue(a.spellId))
           and EATING_AURAS[a.spellId] then
            eatCache = a
            break
        end
    end
    return eatCache
end

--------------------------------------------------------------------------------
-- CLASS MAINTAINED BUFFS: self-buffs the player keeps up pre-combat (poisons, imbues...).
-- Each group holds interchangeable options; we maintain whichever is ACTIVE (refresh before
-- it lapses) rather than picking a "best", and suggest `default` only when none is up. Cast
-- and detect share the same spellID (the ability applies a like-named self-buff). Gated at
-- runtime by IsPlayerSpell, so only spells the player actually knows ever surface.
--------------------------------------------------------------------------------
SpellDB.CLASS_MAINTAINED_BUFFS = {
    DRUID = {
        { group = { 1126 }, default = 1126 },                          -- Mark of the Wild
    },
    EVOKER = {
        { group = { 364342 }, default = 364342 },                      -- Blessing of the Bronze
    },
    MAGE = {
        { group = { 1459 }, default = 1459 },                          -- Arcane Intellect
    },
    PRIEST = {
        { group = { 21562 }, default = 21562 },                        -- Power Word: Fortitude
    },
    ROGUE = {
        { group = { 315584, 2823, 8679, 381664 }, default = 315584 },  -- Lethal (Instant default)
        { group = { 3408, 5761, 381637 }, default = 3408 },            -- Non-lethal (Crippling default)
    },
    SHAMAN = {
        { group = { 192106, 52127, 974 }, default = 192106 },          -- Shield (Lightning/Water/Earth)
        { group = { 462854 }, default = 462854 },                      -- Skyfury
    },
    WARRIOR = {
        { group = { 6673 }, default = 6673 },                          -- Battle Shout
    },
    -- No aura-based maintained pre-combat self-buff (or handled by the pet system):
    -- DEATHKNIGHT, DEMONHUNTER, HUNTER, MONK, PALADIN, WARLOCK. Shaman weapon imbues
    -- (Windfury/Flametongue/Earthliving) are weapon enchants, not auras - they're suggested
    -- via GetWeaponEnchantInfo in PrecombatEngine (see WEAPON_IMBUE_SPELLS below).
}

local CLASS_BUFF_SET = {}  -- flat spellID set, for the green-glow emphasis on class-buff icons
for _, groups in pairs(SpellDB.CLASS_MAINTAINED_BUFFS) do
    for _, grp in ipairs(groups) do
        for _, id in ipairs(grp.group) do CLASS_BUFF_SET[id] = true end
    end
end

-- Rogue poison cast IDs, derived from the maintained-buff groups above so the two
-- can never drift. RedundancyFilter consumes this for cast-based poison detection
-- and its NeverSecret whitelist merge.
SpellDB.ROGUE_POISON_CAST_IDS = {}
for _, grp in ipairs(SpellDB.CLASS_MAINTAINED_BUFFS.ROGUE) do
    for _, id in ipairs(grp.group) do SpellDB.ROGUE_POISON_CAST_IDS[id] = true end
end

-- Weapon imbues (shaman): these apply a temp weapon ENCHANT, not a player aura, so they can't
-- live in CLASS_MAINTAINED_BUFFS (that path detects via auras). PrecombatEngine suggests them
-- by reading the weapon directly (GetWeaponEnchantInfo).
-- WEAPON_ENCHANT_SPELLS is the full cast-ID set and the single source (RedundancyFilter
-- consumes it for enchant-cast detection). WEAPON_IMBUE_SPELLS is the maintained-default
-- LIST: it excludes Frostbrand (a situational swap that's never the default) and exists so
-- imbues green-glow and get the OOC click hint. IsPlayerSpell picks the first the player
-- knows, which cleanly separates specs (Enhancement -> Windfury, Resto -> Earthliving).
SpellDB.WEAPON_ENCHANT_SPELLS = {
    [33757] = true,   -- Windfury Weapon
    [318038] = true,  -- Flametongue Weapon
    [196834] = true,  -- Frostbrand Weapon (situational; never a maintained default)
    [382021] = true,  -- Earthliving Weapon
}
SpellDB.WEAPON_IMBUE_SPELLS = { 33757, 318038, 382021 }  -- Windfury, Flametongue, Earthliving
for _, id in ipairs(SpellDB.WEAPON_IMBUE_SPELLS) do CLASS_BUFF_SET[id] = true end

-- Cheap self-heals castable out of combat, per class: preferred over Recuperate
-- for topping off (faster, and the resource regenerates out of combat anyway).
-- Only no/short-cooldown heals belong here - never real combat cooldowns
-- (Exhilaration, Renewal), which Recuperate exists to preserve. First KNOWN
-- entry wins; classes without an entry fall back to Recuperate.
-- Deliberately NOT added to CLASS_BUFF_SET: these spells also appear as regular
-- defensive-list entries, and the green glow keys on entry provenance (the
-- queue entry's precombat flag), never on spell identity.
SpellDB.CLASS_TOPOFF_HEALS = {
    DRUID   = { 8936 },       -- Regrowth
    EVOKER  = { 355913 },     -- Emerald Blossom
    MONK    = { 322101, 116670 },  -- Expel Harm (instant), Vivify
    PALADIN = { 19750 },      -- Flash of Light
    PRIEST  = { 2061, 139 },  -- Flash Heal, Renew
    ROGUE   = { 185311 },     -- Crimson Vial (30s recharge - back before next pull)
    SHAMAN  = { 8004 },       -- Healing Surge
}

--- First top-off heal the player's class knows, or nil.
function SpellDB.GetKnownTopoffHeal()
    local _, class = UnitClass("player")
    local list = class and SpellDB.CLASS_TOPOFF_HEALS[class]
    if not list then return nil end
    for i = 1, #list do
        if IsPlayerSpell(list[i]) then return list[i] end
    end
    return nil
end

--- True if spellID is any class maintained buff (lets the render green-glow inserted ones).
function SpellDB.IsClassMaintainedBuff(spellID)
    return spellID ~= nil and StaticLookup(CLASS_BUFF_SET, spellID) == true
end

--- Register generated buff categories: { flask = { {id=,buff=,stat=}, ... }, food = ... }.
function SpellDB.RegisterPrecombatBuffs(t)
    if type(t) ~= "table" then return end
    for cat, list in pairs(t) do
        for i = 1, #list do AddPrecombatEntry(cat, list[i]) end
    end
end

--- Register hand-curated entries (toys/class spells): a flat list, each carrying its own
--- `category` and `source`. Kept separate so a generator re-run never clobbers them.
function SpellDB.RegisterPrecombatBuffsExtra(t)
    if type(t) ~= "table" then return end
    for i = 1, #t do AddPrecombatEntry(t[i].category, t[i]) end
end

--- Categories in display order, and the buff-aura set / item list for one category.
function SpellDB.GetPrecombatBuffCategories() return PRECOMBAT_ORDER end
function SpellDB.GetPrecombatBuffSet(cat)
    local b = PRECOMBAT_BUFFS[cat]; return b and b.buffSet
end
function SpellDB.GetPrecombatBuffItems(cat)
    local b = PRECOMBAT_BUFFS[cat]; return b and b.items
end

local PlayerHasToy = PlayerHasToy
local IsPlayerSpell = IsPlayerSpell or IsSpellKnown

-- Does the player have this buff entry available to use right now? Source-aware:
-- bag item (GetItemCount), toy (PlayerHasToy), or known spell (IsPlayerSpell).
local function OwnsBuffEntry(e)
    if e.source == "toy" then
        return PlayerHasToy and PlayerHasToy(e.id)
    elseif e.source == "spell" then
        return IsPlayerSpell and IsPlayerSpell(e.id)
    end
    return (GetItemCount(e.id) or 0) > 0
end

-- Caster specs (intellect primary) want weapon oils; physical specs want stones/whetstones.
-- The spec's primary stat is deterministic and non-secret; reading raw UnitStat instead
-- returns a SECRET number under taint (e.g. options opened from addon code), and comparing
-- secrets throws. GetSpecializationInfo's 6th return is the primary stat (same enum as
-- UnitStat: 1=Str, 2=Agi, 4=Int).
local function PlayerPrefersOil()
    if not (GetSpecialization and GetSpecializationInfo) then return false end
    local spec = GetSpecialization()
    if not spec then return false end
    return select(6, GetSpecializationInfo(spec)) == 4  -- 4 = Intellect -> caster -> oil
end

--- Best owned buff entry for a category, honoring a stat preference, or nil. statPref
--- nil/"optimal" keeps the list's newest-first order; a stat string ("haste", "crit",
--- "mastery", "versatility", "primary") floats matching entries to the top. Out of combat
--- only for the bag scan; entries are ranked, the first owned match wins ties by recency.
function SpellDB.GetBestOwnedBuff(cat, statPref)
    local b = PRECOMBAT_BUFFS[cat]
    if not b then return nil end
    -- Weapon enhancements only apply to weapons from their own expansion or earlier - a
    -- newer weapon rejects an older oil/stone as "too high level". Skip any enhancement
    -- older than the equipped main-hand (expansion read from GetItemInfo's expacID, #15).
    -- They're also weapon-type restricted (whetstone = bladed, weightstone = blunt):
    -- each entry's wmask is the enchant's allowed weapon-subclass bitmask; test the
    -- main hand's subclass bit against it so a spear never gets a weightstone offered.
    local weaponExp, weaponTypeBit
    if cat == "weaponEnchant" and GetInventoryItemID then
        local mh = GetInventoryItemID("player", 16)
        weaponExp = mh and select(15, GetItemInfo(mh))
        local getInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
        if mh and getInstant then
            local classID, subClassID = select(6, getInstant(mh))
            if classID == 2 and subClassID then weaponTypeBit = 2 ^ subClassID end
        end
    end
    local prefKind  -- weaponEnchant: soft-prefer the class-appropriate archetype
    if cat == "weaponEnchant" then
        prefKind = PlayerPrefersOil() and "caster" or "physical"
    end
    local n = #b.items
    local best, bestScore = nil, -1
    for i = 1, n do
        local e = b.items[i]
        -- Speed (the Speed secondary stat) is an explicit pick: entries match ONLY statPref
        -- "speed" and never surface under Auto or another stat pref - Speed is niche, so we
        -- don't let it masquerade as a spec's combat stat/flask. No-op when neither is "speed".
        if OwnsBuffEntry(e) and (e.stat == "speed") == (statPref == "speed") then
            local applies = true
            if weaponExp then
                local oilExp = select(15, GetItemInfo(e.id))
                applies = oilExp ~= nil and oilExp >= weaponExp
            end
            if applies and e.wmask and weaponTypeBit then
                applies = bit.band(e.wmask, weaponTypeBit) ~= 0
            end
            if applies then
                local score = n - i  -- recency: earlier in the list = newer = higher
                if statPref and statPref ~= "optimal" and e.stat
                    and e.stat:find(statPref, 1, true) then
                    score = score + 1000000  -- a stat match outranks any recency gap
                end
                if prefKind and e.stat == prefKind then
                    score = score + 500000  -- class-appropriate oil vs stone (soft bias)
                end
                if score > bestScore then bestScore = score; best = e end
            end
        end
    end
    return best
end

--- Owned buff entries for a category, best-first: { {id=, name=, stat=}, ... }. Feeds the
--- per-category dropdown. Out of combat only (item names).
function SpellDB.GetOwnedPrecombatBuffs(cat)
    local b = PRECOMBAT_BUFFS[cat]
    if not b then return {} end
    local owned = {}
    for i = 1, #b.items do
        local e = b.items[i]
        if OwnsBuffEntry(e) then
            owned[#owned + 1] = { id = e.id, stat = e.stat,
                                  name = (GetItemInfo(e.id)) or ("Item " .. e.id) }
        end
    end
    return owned
end

local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local IsSpellKnown = IsSpellKnown

--- Is the current target within `yards`? Returns true / false / nil (unknown).
--- Brackets the target using the player's KNOWN reference abilities: a reference of range
--- ≤ yards that IS in range proves target ≤ yards (within); a reference of range ≥ yards
--- that is OUT of range proves target > yards (beyond). Distance in yards is a secret in
--- combat, but IsSpellInRange's boolean is not - this is built entirely on it.
--- Reliability scales with probe density near `yards`; nil when no probe brackets it.
function SpellDB.IsTargetWithin(yards)
    if not C_Spell_IsSpellInRange then return nil end
    local api = LibStub("JustAC-BlizzardAPI", true)
    local isSecret = api and api.IsSecretValue
    local within, beyond
    for id, ref in pairs(RANGE_REFERENCES) do
        -- Gate on KNOWN (form-independent), NOT castability: IsSpellAvailable would skip a
        -- form-gated probe (a Druid's Mangle while shifted, anything on GCD/low resources),
        -- which silently breaks detection. IsSpellInRange only needs the spell to be known.
        if not IsSpellKnown or IsSpellKnown(id) then
            local r = C_Spell_IsSpellInRange(id, "target")   -- "target" unit is required
            if r ~= nil and not (isSecret and isSecret(r)) then
                if r ~= false then
                    if ref <= yards then within = true end   -- target ≤ ref ≤ yards
                elseif ref >= yards then
                    beyond = true                            -- target > ref ≥ yards
                end
            end
        end
    end
    if within then return true elseif beyond then return false end
    return nil
end

--------------------------------------------------------------------------------
-- API Functions
--------------------------------------------------------------------------------

-- Check if a spell is defensive (should not appear in DPS queue 2+)
-- StaticLookup resolves talent-override variants to the base list ID so a variant
-- of a defensive/heal/CC spell can't slip through classification as offensive.
function SpellDB.IsDefensiveSpell(spellID)
    if not spellID then return false end
    return StaticLookup(DEFENSIVE_SPELLS, spellID) == true
end

-- Check if a spell is a healing spell (should not appear in DPS queue 2+)
function SpellDB.IsHealingSpell(spellID)
    if not spellID then return false end
    return StaticLookup(HEALING_SPELLS, spellID) == true
end

-- Check if a spell is crowd control (should not appear in DPS queue 2+)
function SpellDB.IsCrowdControlSpell(spellID)
    if not spellID then return false end
    return StaticLookup(CROWD_CONTROL_SPELLS, spellID) == true
end

-- Lazily-built set of pure interrupt spells (kind="interrupt" in INTERRUPT_ABILITIES).
-- Interrupts apply a lockout but no CC mechanic - they must not trigger CC-failure learning.
local interruptTypeSpellIDs = nil
local function BuildInterruptTypeSpellIDs()
    interruptTypeSpellIDs = {}
    for id, e in pairs(INTERRUPT_ABILITIES) do
        if e.kind == "interrupt" then
            interruptTypeSpellIDs[id] = true
        end
    end
end

-- Returns true if spellID is a pure lockout interrupt (kind="interrupt" in INTERRUPT_ABILITIES).
-- Returns false for cc-type entries (stun, silence, incapacitate) even if also in CROWD_CONTROL_SPELLS.
function SpellDB.IsInterruptTypeSpell(spellID)
    if not spellID then return false end
    if not interruptTypeSpellIDs then BuildInterruptTypeSpellIDs() end
    -- Base-resolve: the set is built from INTERRUPT_ABILITIES base keys, but callers
    -- pass the resolved/override cast ID (ResolveInterruptSpells works in that form).
    return StaticLookup(interruptTypeSpellIDs, spellID) == true
end

-- Per-CC mechanic (silence/fear/stun/…) now lives in INTERRUPT_ABILITIES[id].mech and
-- travels on each resolved entry (entry.mech), so callers branch on entry.mech directly:
--   mech == 9 (silence) only stops SPELL casts, not physical channels - in ccOnly mode the
--             tracker prefers a stun-class CC and defers silence (see EvaluateInterrupt).
--   mech == 5 (fear) breaks on damage and scatters packs - excluded unless includeFears.

-- Check if a spell is offensive (NOT defensive, healing, CC, or utility)
-- This is the primary check for DPS queue filtering
function SpellDB.IsOffensiveSpell(spellID)
    if not spellID then return true end  -- Fail-open: unknown = assume offensive
    
    -- If it's in any of the non-offensive tables, it's not offensive.
    -- Base-resolve so a talent-override variant is excluded like its base.
    if StaticLookup(DEFENSIVE_SPELLS, spellID) then return false end
    if StaticLookup(HEALING_SPELLS, spellID) then return false end
    if StaticLookup(CROWD_CONTROL_SPELLS, spellID) then return false end
    if StaticLookup(UTILITY_SPELLS, spellID) then return false end
    
    -- Not in any exclusion list = offensive
    return true
end

--------------------------------------------------------------------------------
-- OFFENSIVE SPELL ATTRIBUTES (archetype / range / gate)
-- Flat per-spell map - archetype and range are properties of the spell, so this is
-- robust to talent/priority-queue changes. Used to bias the fixed queue (positions
-- 2+) by the context of Blizzard's position-1 pick:
--   arch  = "st" | "cleave" | "aoe"      → boost same-archetype spells up
--   range = "melee" | "ranged"           → soft-demote melee spells when the
--                                          context spell is ranged (out of melee)
--   gate  = "stealth"                    → reserved (usability tint already greys it)
--           "execute"                    → HP-gated finisher. When Blizzard's position-1
--                                          pick carries this gate, the target is below the
--                                          execute threshold (a secret-free target-HP read),
--                                          so other execute-gated spells are boosted in 2+.
-- Sourced from DB2 (wago.tools): arch from SpellEffect ImplicitTarget + MaxTargets,
-- range from SpellRange. Intended to grow into a full auto-generated table.
--------------------------------------------------------------------------------
-- Spell archetype/range stored as flat tables with interned string values (far less
-- memory than per-spell sub-tables for ~2k spells; lookups stay O(1)). Populated by
-- the generated Data/SpellArchetypes.lua via RegisterArchetypes.
local ARCH  = {}   -- [spellID] = "aoe" | "cleave" | "st"
local RANGE = {}   -- [spellID] = "melee" | "ranged"
local GATE  = {}   -- [spellID] = "stealth" | ...  (reserved; not yet filtered)
local ROLE  = {}   -- [spellID] = "builder" | "spender"  (accumulator resource-phase)

-- Hand overrides on top of the generated data: gates, and arch fixes for spells whose
-- damage is indirect (triggered/cloned) and so can't be classified mechanically.
local function ApplyArchOverrides()
    GATE[185438] = "stealth"          -- Shadowstrike (stealth-gated)
    -- Execute (HP-gated finishers). DB2 has no health-threshold column, so this is a
    -- hand-verified list of cast IDs GetNextCastSpell actually returns; extend per spec
    -- via /jac inspect while in execute phase. Stale IDs are harmless (never match).
    GATE[53351]  = "execute"          -- Kill Shot (Marksmanship/Beast Mastery)
    GATE[320976] = "execute"          -- Kill Shot (Survival)
    GATE[322109] = "execute"          -- Touch of Death (Monk)
    ARCH[280719] = "cleave"           -- Secret Technique: AOE via clones
    ARCH[426591] = "cleave"           -- Goremaw's Bite: AOE via trigger
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
--- Base-resolve so a talent-override variant inherits its base's archetype/range/gate
--- instead of falling to neutral in the context ranker.
function SpellDB.GetArch(spellID)  return StaticLookup(ARCH, spellID)  end
function SpellDB.GetRange(spellID) return StaticLookup(RANGE, spellID) end
function SpellDB.GetGate(spellID)  return StaticLookup(GATE, spellID)  end

--- Called by the generated Data/SpellArchetypes.lua. Groups: { builder = {[id]=true,...},
--- spender = {[id]=true,...} }. Role = the accumulator resource-phase (generates vs spends
--- combo points / holy power / soul shards / etc.), orthogonal to archetype. Fuel resources
--- (mana/rage/focus/energy/runes) are intentionally untagged -> nil -> neutral.
function SpellDB.RegisterRoles(t)
    if type(t) ~= "table" then return end
    if t.builder then for id in pairs(t.builder) do ROLE[id] = "builder" end end
    if t.spender then for id in pairs(t.spender) do ROLE[id] = "spender" end end
end

--- Builder/spender role ("builder"/"spender") or nil if untagged/neutral.
function SpellDB.GetRole(spellID)  return StaticLookup(ROLE, spellID)  end

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

-- Ranged-DPS spec IDs (healers resolve via role below). Everything else - melee
-- DPS and tanks - is treated as melee. Used to auto-default the move-cast dot on
-- for specs that actually hardcast (ranged/healers) and off for melee.
local RANGED_DPS_SPECS = {
    [253] = true, [254] = true,               -- Hunter: Beast Mastery, Marksmanship
    [62]  = true, [63]  = true, [64] = true,  -- Mage: Arcane, Fire, Frost
    [258] = true,                             -- Priest: Shadow
    [102] = true,                             -- Druid: Balance
    [262] = true,                             -- Shaman: Elemental
    [265] = true, [266] = true, [267] = true, -- Warlock: Affliction, Demonology, Destruction
    [1467] = true, [1473] = true,             -- Evoker: Devastation, Augmentation
}
local rangedSpecCacheIdx, rangedSpecCacheVal
--- True if the current spec is a ranged DPS or a healer (move-cast dot auto-on).
--- Cached by spec index; recomputed only when the player changes spec.
function SpellDB.IsRangedOrHealerSpec()
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return false end
    if rangedSpecCacheIdx ~= spec then
        rangedSpecCacheIdx = spec
        local specID, _, _, _, role = GetSpecializationInfo(spec)
        rangedSpecCacheVal = (role == "HEALER") or (RANGED_DPS_SPECS[specID] == true)
    end
    return rangedSpecCacheVal
end

--- Resolve defaults from a table that supports both spec-level and class-level keys.
--- Tries "CLASS_N" first, then falls back to "CLASS".
--- @param defaultsTable table - e.g. SpellDB.CLASS_DEFENSIVE_DEFAULTS
--- @param specKey string|nil - e.g. "WARRIOR_3" (optional; computed if nil)
--- @param playerClass string|nil - e.g. "WARRIOR" (optional; computed if nil)
--- @return table|nil - the default spell list, or nil
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
    DEATHKNIGHT   = {49998, 48743, 48792, 48707, 49039, 327574}, -- Death Strike, Death Pact, Icebound Fortitude, Anti-Magic Shell, Lichborne, Sacrificial Pact
    -- Blood (tank): active mitigation first, Death Strike for heal, then big CDs
    -- (Rune Tap 194679 verified still live in 12.1 DB2 despite older "removed" notes)
    DEATHKNIGHT_1 = {49998, 55233, 194679, 48743, 48792, 48707, 219809, 49039}, -- Death Strike, Vampiric Blood, Rune Tap, Death Pact, IBF, AMS, Tombstone, Lichborne

    -- ── Demon Hunter ────────────────────────────────────────────────────────
    -- Class fallback (Havoc DPS): Blur, Netherwalk (talent), Darkness
    DEMONHUNTER   = {198589, 196555, 196718},                   -- Blur, Netherwalk, Darkness
    -- Vengeance (tank): Soul Cleave heal, Demon Spikes, Fiery Brand, Metamorphosis (a
    -- Vengeance SURVIVAL cd, not a DPS burst - unlike Havoc's), then Blur
    DEMONHUNTER_2 = {228477, 203720, 204021, 187827, 198589, 263648}, -- Soul Cleave, Demon Spikes, Fiery Brand, Metamorphosis, Blur, Soul Barrier

    -- ── Druid ───────────────────────────────────────────────────────────────
    -- Class fallback (Balance): self-heals then CDs. Rejuvenation, Frenzied Regeneration,
    -- Survival Instincts and Heart of the Wild are class talents any spec can take -
    -- included so a talented caster gets them; the runtime known-spell gate drops them
    -- when untalented. Heart of the Wild empowers abilities OUTSIDE your spec, so for a
    -- non-healer it's the button that makes the class-tree heals actually land.
    DRUID         = {8936, 774, 22842, 108238, 1261867, 61336, 22812},  -- Regrowth, Rejuvenation, Frenzied Regen, Renewal, Heart of the Wild, Survival Instincts, Barkskin
    -- Feral: Regrowth, Frenzied Regen (class talent), Heart of the Wild, Survival Instincts, Barkskin, Renewal
    -- (Rejuvenation omitted: castable only out of form, so it self-gates away for most Ferals)
    DRUID_2       = {8936, 22842, 1261867, 61336, 22812, 108238},       -- Regrowth, Frenzied Regen, Heart of the Wild, Survival Instincts, Barkskin, Renewal
    -- Guardian (tank): Frenzied Regen, Ironfur, Barkskin, Heart of the Wild, Survival Instincts, Rage of the Sleeper
    DRUID_3       = {22842, 192081, 22812, 1261867, 61336, 200851},     -- Frenzied Regen, Ironfur, Barkskin, Heart of the Wild, Survival Instincts, Rage of the Sleeper  (Renewal removed in 12.0)
    -- Restoration: the class fallback minus Heart of the Wild - it empowers off-spec
    -- abilities, which for a healer means damage, not survival.
    DRUID_4       = {8936, 774, 22842, 108238, 61336, 22812},           -- Regrowth, Rejuvenation, Frenzied Regen, Renewal, Survival Instincts, Barkskin

    -- ── Evoker ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs): self-heals then defensive CDs. Renewing Blaze and
    -- Emerald Communion are class talents (verified live in 12.1 DB2); dropped by the
    -- known-spell gate when untalented.
    EVOKER        = {360995, 374348, 363916, 370960},           -- Verdant Embrace, Renewing Blaze, Obsidian Scales, Emerald Communion

    -- ── Hunter ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs)
    HUNTER        = {109304, 264735, 281195, 186265, 388035},  -- Exhilaration, Survival of the Fittest, SotF (Lone Wolf), Aspect of the Turtle, Fortitude of the Bear

    -- ── Mage ────────────────────────────────────────────────────────────────
    -- Class fallback (spec-appropriate barrier is auto-learned; list all three so
    -- the one the player actually knows will be shown)
    MAGE          = {11426, 235313, 235450, 342245, 45438},    -- Ice/Blazing/Prismatic Barrier, Alter Time, Ice Block

    -- ── Monk ────────────────────────────────────────────────────────────────
    -- Class fallback (Windwalker): Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic
    MONK          = {322101, 115203, 122278, 122783},          -- Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic
    -- Brewmaster (tank): Purifying Brew first (stagger is the real damage signal - the
    -- float hint below surfaces it whenever Moderate/Heavy Stagger is up), then Celestial
    -- Brew, Expel Harm, Fortifying Brew, then class-talent DR (Dampen Harm / Diffuse Magic /
    -- Zen Meditation - verified live in 12.1 DB2; known-gate drops any untalented)
    MONK_1        = {119582, 322507, 322101, 120954, 122278, 122783, 115176, 115295}, -- Purifying Brew, Celestial Brew, Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic, Zen Meditation, Guard
    -- Mistweaver: self-heals then DR CDs
    MONK_2        = {116670, 243435, 115203, 122278, 122783, 388615, 115295}, -- Vivify, Fortifying Brew (MW), Fortifying Brew, Dampen Harm, Diffuse Magic, Restoral, Guard
    -- Windwalker: Expel Harm, Touch of Karma, Fortifying Brew, Diffuse Magic
    MONK_3        = {322101, 122470, 201318, 122278, 122783, 115295}, -- Expel Harm, Touch of Karma, Fortifying Brew (WW), Dampen Harm, Diffuse Magic, Guard

    -- ── Paladin ─────────────────────────────────────────────────────────────
    -- Class fallback (Holy/Ret): Word of Glory, Divine Protection, Divine Shield, Lay on Hands
    PALADIN       = {85673, 403876, 184662, 642, 633},         -- Word of Glory, Divine Protection, Shield of Vengeance, Divine Shield, Lay on Hands
    -- Protection (tank): Word of Glory, Ardent Defender, Guardian of Ancient Kings,
    -- Divine Shield, Lay on Hands.  Shield of the Righteous is deliberately absent -
    -- AC recommends it rotationally, so it lives in the offensive queue.
    PALADIN_2     = {85673, 31850, 86659, 387174, 389539, 378974, 642, 633}, -- Word of Glory, Ardent Defender, Guardian of Ancient Kings, Eye of Tyr, Sentinel, Bastion of Light, Divine Shield, Lay on Hands

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
    SHAMAN        = {108271, 8004, 108281, 198103},            -- Astral Shift, Healing Surge, Ancestral Guidance, Earth Elemental

    -- ── Warlock ─────────────────────────────────────────────────────────────
    -- Class fallback (all specs share dark pact / drain / UR)
    WARLOCK       = {108416, 234153, 212295, 104773},          -- Dark Pact, Drain Life, Nether Ward, Unending Resolve

    -- ── Warrior ─────────────────────────────────────────────────────────────
    -- Class fallback (Arms/Fury DPS). Die by the Sword is Arms-only and Enraged
    -- Regeneration Fury-only - the runtime known-spell gate shows each spec its own wall.
    WARRIOR       = {34428, 202168, 190456, 118038, 184364, 23920, 386208, 97462},  -- Victory Rush, Impending Victory, Ignore Pain, Die by the Sword, Enraged Regeneration, Spell Reflection, Defensive Stance, Rallying Cry
    -- Protection (tank): Shield Block first (physical active mitigation, used on CD -
    -- the sink hint below parks it while its buff is already rolling), then Ignore Pain,
    -- Impending Victory, Last Stand + Shield Wall (major CDs), Rallying Cry, Spell Reflection.
    -- (Last Stand 12975 is an active 3-min CD in 12.1 DB2 - the older "passive" note was wrong.)
    WARRIOR_3     = {2565, 190456, 202168, 12975, 871, 97462, 23920}, -- Shield Block, Ignore Pain, Impending Victory, Last Stand, Shield Wall, Rallying Cry, Spell Reflection
}

-- Emergency tier for the <35% defensive reorder. Tier 1 = immunity bubble (survives any
-- hit), tier 2 = survival button: a big instant heal OR a major damage-reduction cooldown
-- (a tank's equivalent - Shield Wall-class CDs that stop the next hit from killing).
-- Untagged = tier 3 (rotational mitigation / small filler / cast-time or over-time heal),
-- left in the normal filler-first order.
-- Used only when below the low-health threshold to float survival buttons above fillers;
-- above the threshold, list order (filler-first) and proc-priority already do the right thing.
--
-- Tier 2 heals must land INSTANTLY. Cast-time heals (Healing Surge), HoTs / over-time
-- heals (Regrowth, Frenzied Regeneration, Crimson Vial), and channels do NOT qualify -
-- at <35% a heal that trickles in can't save you before the next hit lands, so floating
-- it to the top would be actively misleading. Likewise short rotational mitigation
-- (Ignore Pain, Ironfur, Demon Spikes, Celestial Brew, Barkskin) stays tier 3: it's
-- uptime play, not an emergency answer.
--
-- Hand-curated over CLASS_DEFENSIVE_DEFAULTS: DB2 SpellEffect cleanly tags only the
-- direct-aura bubbles (39/40 + broad school mask) and %-heals (Effect 136/67); the
-- indirect-aura immunities (Turtle, Cloak) and flat/SP-scaled heals (Death Strike, Word
-- of Glory) are verified by hand. Regenerate the candidate set per patch from SpellEffect;
-- hand-verify the misses.
local DEFENSE_TIER = {
    -- Tier 1 - immunity bubbles
    [642]    = 1,  -- Divine Shield (Paladin)
    [45438]  = 1,  -- Ice Block (Mage)
    [186265] = 1,  -- Aspect of the Turtle (Hunter)
    [31224]  = 1,  -- Cloak of Shadows (Rogue, magic immunity)
    -- Tier 2 - big instant heals
    [633]    = 2,  -- Lay on Hands (Paladin, 100%)
    [19236]  = 2,  -- Desperate Prayer (Priest, 25%)
    [108238] = 2,  -- Renewal (Druid, 30%)
    [109304] = 2,  -- Exhilaration (Hunter, 30%)
    [34428]  = 2,  -- Victory Rush (Warrior)
    [202168] = 2,  -- Impending Victory (Warrior)
    [49998]  = 2,  -- Death Strike (Death Knight)
    [85673]  = 2,  -- Word of Glory (Paladin)
    [360995] = 2,  -- Verdant Embrace (Evoker)
    [228477] = 2,  -- Soul Cleave (Demon Hunter, instant spender-heal like Death Strike)
    -- Tier 2 - major damage-reduction cooldowns (survival buttons; all have long base
    -- CDs, so the hold-worthy logic also parks them as emergencies when healthy).
    -- NOT tiered on purpose: semi-rotational short DR (Blur, Barkskin, Ignore Pain),
    -- school-limited walls (AMS, Spell Reflection, Diffuse Magic), situational
    -- avoidance (Feint, Evasion) - parking or floating those would miscoach.
    [871]    = 2,  -- Shield Wall (Warrior)
    [61336]  = 2,  -- Survival Instincts (Druid)
    [31850]  = 2,  -- Ardent Defender (Paladin)
    [86659]  = 2,  -- Guardian of Ancient Kings (Paladin)
    [115203] = 2,  -- Fortifying Brew (Monk)
    [120954] = 2,  -- Fortifying Brew (Brewmaster variant)
    [201318] = 2,  -- Fortifying Brew (Windwalker variant)
    [55233]  = 2,  -- Vampiric Blood (Death Knight)
    [48792]  = 2,  -- Icebound Fortitude (Death Knight)
    [204021] = 2,  -- Fiery Brand (Demon Hunter)
    [108271] = 2,  -- Astral Shift (Shaman)
    [104773] = 2,  -- Unending Resolve (Warlock)
    [47585]  = 2,  -- Dispersion (Shadow Priest)
    [363916] = 2,  -- Obsidian Scales (Evoker)
    [118038] = 2,  -- Die by the Sword (Arms Warrior)
    [184364] = 2,  -- Enraged Regeneration (Fury Warrior; heal-over-time BUT 30% DR while
                   -- active - the DR component makes it Fury's wall, not a trickle heal)
}

-- Per-spec overrides layered over DEFENSE_TIER ("CLASS_N" → { [spellID] = tier }).
-- Protection Paladin: Divine Shield drops all threat mid-pull, so as a tank it must
-- never float to the top at low health - demoted to filler tier (still listed).
local DEFENSE_TIER_SPEC = {
    PALADIN_2 = { [642] = 3 },  -- Divine Shield
}

--- Emergency tier for the low-health defensive reorder: 1 = bubble, 2 = survival button
--- (big instant heal or major DR cooldown), 3 = everything else. Looks up the base list
--- ID (talent overrides resolve to the same tool); spec overrides win over class tiers.
--- Negative IDs are heal items (potion/healthstone): instant burst heals, tier 2 - they
--- must float when low just like they park as emergencies when healthy (IsHoldWorthy).
function SpellDB.GetDefenseTier(spellID)
    if not spellID then return 3 end
    if spellID < 0 then return 2 end
    local specKey = SpellDB.GetSpecKey()
    local specTiers = specKey and DEFENSE_TIER_SPEC[specKey]
    return (specTiers and StaticLookup(specTiers, spellID)) or StaticLookup(DEFENSE_TIER, spellID) or 3
end

-- Aura-linked ordering hints for tank active mitigation. Combat-safe: only aura
-- PRESENCE is read (via the instance-map cache); stacks and durations are secret.
--   sinkAura   - while this self-buff is active the button is already doing its job:
--                park it with the on-CD entries instead of suggesting a re-press.
--   floatAuras - while ANY of these auras is present the button is the answer right
--                now: float it to the front like a proc (e.g. purify heavy stagger).
-- Keyed by base list ID (talent overrides resolve to the same tool).
-- Ironfur is deliberately absent: stacking it is legitimate play and stack counts are
-- secret in combat, so buff presence alone can't justify a sink.
SpellDB.DEFENSIVE_AURA_HINTS = {
    [2565]   = { sinkAura = 132404 },              -- Shield Block → its own buff
    [203720] = { sinkAura = 203819 },              -- Demon Spikes → its own buff
    [119582] = { floatAuras = {124273, 124274} },  -- Purifying Brew → Heavy/Moderate Stagger
}

--- Base-aware lookup of the active-mitigation ordering hint for a spell (resolves
--- talent-override variants to the base list ID). Returns the hint table or nil.
function SpellDB.GetDefensiveAuraHint(spellID)
    return StaticLookup(SpellDB.DEFENSIVE_AURA_HINTS, spellID)
end

-- Pet rez/summon spells (shown when pet is dead or missing - reliable in combat via UnitIsDead/UnitExists)
SpellDB.CLASS_PET_REZ_DEFAULTS = {
    HUNTER = {982, 55709, 883},                      -- Revive Pet, Heart of the Phoenix, Call Pet 1
    WARLOCK = {688, 697, 712, 691, 30146},           -- Summon Imp/Voidwalker/Succubus/Felhunter/Felguard
    WARLOCK_2 = {30146, 688, 697, 712, 691},         -- Demonology: Felguard first (its mandatory pet), others as fallback
    DEATHKNIGHT_3 = {46584, 46585},                  -- Raise Dead (Unholy only - permanent ghoul 46584; 46585 covers the temporary variant. Blood/Frost ghoul is a Guardian, not a pet)
}

-- Pet heal spells (shown when PET health is low - OUT OF COMBAT ONLY)
-- In 12.0 combat, UnitHealth("pet") is secret so pet heals cannot trigger.
SpellDB.CLASS_PETHEAL_DEFAULTS = {
    HUNTER = {136, 109304},                          -- Mend Pet, Exhilaration (heals pet too)
    WARLOCK = {755},                                 -- Health Funnel
}

-- Returns true if the given class has any pet rez or heal defaults (drives pet-UI visibility).
function SpellDB.ClassHasPetDefaults(playerClass)
    if not playerClass then return false end
    return SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass] ~= nil
        or SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass] ~= nil
end

-- Interrupt/CC ability data: see Data/InterruptAbilities.lua (registered via
-- RegisterInterruptAbilities). Resolved + sorted by ResolveInterruptSpells below.

-- Gap-closer spells for melee specs (shown when target is out of melee range).
-- Spec-aware: keyed by "CLASS_SPECINDEX" so only melee specs get suggestions.
-- GetSpecialization() returns the spec index (1-4); compose key as CLASS .. "_" .. specIndex.
-- Omitted entries = ranged/healer spec → no gap-closer suggestions.
-- Priority-ordered: first usable spell is shown.
SpellDB.CLASS_GAPCLOSER_DEFAULTS = {
    -- Death Knight: all specs are melee
    DEATHKNIGHT_1 = {49576},                         -- Blood: Death Grip
    DEATHKNIGHT_2 = {49576},                         -- Frost: Death Grip
    DEATHKNIGHT_3 = {49576},                         -- Unholy: Death Grip

    -- Demon Hunter: Havoc is melee (spec 1), Vengeance is melee tank (spec 2)
    DEMONHUNTER_1 = {195072, 232893},                -- Havoc: Fel Rush, Felblade (charge-to-target backup)
    -- REMOVED: Vengeful Retreat (198793) - jumps backward, not a gap closer
    DEMONHUNTER_2 = {189110},                        -- Vengeance: Infernal Strike

    -- Druid: Feral (2) and Guardian (3) are melee
    DRUID_2 = {102401},                              -- Feral: Wild Charge
    DRUID_3 = {102401},                              -- Guardian: Wild Charge

    -- Evoker: Augmentation (3) is mid-range, not truly melee - omit all

    -- Hunter: Survival (3) is melee
    HUNTER_3 = {190925},                             -- Survival: Harpoon (190925; 186270 is Raptor Strike, a melee attack - not a gap closer)

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

-- Melee-range detection is handled by SpellDB.IsTargetWithin(5), which polls every melee
-- ability the player knows (5yd probes in Data/RangeReferences.lua). There is no per-spec
-- reference table or user override - the probe set is comprehensive on its own.

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

--------------------------------------------------------------------------------
-- BURST TRIGGER DEFAULTS
-- Per-spec list of major offensive CDs that Blizzard's Assisted Combat will
-- recommend when a burst window is appropriate.  When any of these appear at
-- position 1, the engine activates burst injection.
-- Includes talent alternatives (e.g. Incarnation vs Berserk) - the engine
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
    MONK_1  = {387184},                              -- Brewmaster: Weapons of Order (120s)
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
    [228260] = 194249,   -- Shadow Priest: Void Eruption cast → Voidform buff
    [391109] = 194249,   -- Shadow Priest: Dark Ascension cast → Voidform buff
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
-- Intentionally sparse - users can customize. Ship with known combos only.
--------------------------------------------------------------------------------
SpellDB.CLASS_BURST_INJECTION_DEFAULTS = {
    -- Death Knight
    DEATHKNIGHT_1 = {194844},                        -- Blood: Bonestorm (60s)
    DEATHKNIGHT_2 = {51271},                         -- Frost: Pillar of Frost (60s) - stack during Breath window
    DEATHKNIGHT_3 = {42650},                         -- Unholy: Army of the Dead (180s) - stack during Dark Transformation

    -- Demon Hunter
    DEMONHUNTER_1 = {370965},                        -- Havoc: The Hunt (90s)
    DEMONHUNTER_2 = {370965},                        -- Vengeance: The Hunt (90s)

    -- Druid
    DRUID_1 = {391528},                              -- Balance: Convoke the Spirits (120s)
    DRUID_2 = {391528, 274837},                      -- Feral: Convoke the Spirits (120s), Feral Frenzy (45s)
    DRUID_3 = {50334, 102558, 391528},               -- Guardian: Berserk/Incarnation + Convoke

    -- Evoker
    EVOKER_1 = {357210},                             -- Devastation: Deep Breath (120s)
    -- EVOKER_3 (Augmentation): Breath of Eons is the trigger; no distinct secondary burst CD to force

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
    PALADIN_2 = {387174},                            -- Protection: Eye of Tyr (60s)
    PALADIN_3 = {255937},                            -- Retribution: Wake of Ashes (45s)

    -- Priest
    PRIEST_3 = {263165},                             -- Shadow: Void Torrent (45s)

    -- Rogue
    ROGUE_1 = {385627},                              -- Assassination: Kingsbane (60s)
    ROGUE_2 = {51690},                               -- Outlaw: Killing Spree (120s)
    ROGUE_3 = {280719},                              -- Subtlety: Secret Technique (45s)

    -- Shaman
    -- SHAMAN_1 (Elemental): Ascendance is the trigger; no distinct secondary burst CD to force
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
    local specKey = SpellDB.GetSpecKey()
    return specKey and SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey] or nil
end

--- Return the burst trigger default list for the current class+spec, or nil.
function SpellDB.GetBurstTriggerDefaults()
    local specKey = SpellDB.GetSpecKey()
    return specKey and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey] or nil
end

--- Return the default burst window duration for the current class+spec.
function SpellDB.GetBurstDurationDefault()
    local specKey = SpellDB.GetSpecKey()
    return (specKey and SpellDB.CLASS_BURST_DURATION_DEFAULTS[specKey])
        or SpellDB.BURST_DURATION_FALLBACK
end

--- Check whether the current spec has gap-closer defaults (i.e. is a melee spec).
--- Returns true if CLASS_GAPCLOSER_DEFAULTS has an entry for the current class+spec.
function SpellDB.IsMeleeSpec()
    local specKey = SpellDB.GetSpecKey()
    return (specKey and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]) ~= nil
end

--- Return the gap-closer default list for the current class+spec, or nil.
function SpellDB.GetGapCloserDefaults()
    local specKey = SpellDB.GetSpecKey()
    return specKey and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey] or nil
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

-- Reliability tier for interrupt-reminder ordering (lower = preferred). A kick locks the
-- school and works on bosses; a stun stops anything; a silence stops only magic casts; the
-- rest are softer / situational. Fear is last and gated behind includeFears.
local function CCTier(e)
    if e.type == "interrupt" then return 0 end
    local m = e.mech
    if m == 12 then return 1      -- stun
    elseif m == 9  then return 2  -- silence (magic-only)
    elseif m == 14 then return 3  -- incapacitate
    elseif m == 2  then return 4  -- disorient
    elseif m == 10 then return 4  -- sleep/charm (breaks on damage)
    elseif m == 5  then return 5  -- fear
    end
    return 6
end

-- Best-first: reliability tier, then intra-tier priority (old hand-order), then spellID
-- (stable/deterministic since the source table is iterated with pairs()).
local function CCSortLess(a, b)
    local ta, tb = CCTier(a), CCTier(b)
    if ta ~= tb then return ta < tb end
    local pa, pb = a.pri or 0, b.pri or 0
    if pa ~= pb then return pa < pb end
    return a.spellID < b.spellID
end

--- Resolve the current player's interrupt/CC abilities from the central INTERRUPT_ABILITIES
--- list, filtered to what THIS character actually knows (IsSpellAvailable - auto-handles
--- class spells, racials, and multi-class variants), then sorted best-first by reliability
--- tier then intra-tier priority. Returns an ordered array, or nil if none.
--- Each entry: { spellID, type = "interrupt"|"cc", mech, reach, radius }.
--- Called once during frame/overlay creation; result is cached.
-- Shared resolver: build sorted {spellID, type, ...} entries for the abilities of the
-- given kinds that THIS character knows, each registered for local CD tracking.
local function ResolveAbilitiesByKind(kindSet)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if not BlizzardAPI or not BlizzardAPI.IsSpellAvailable then return nil end
    local result = {}
    for spellID, meta in pairs(INTERRUPT_ABILITIES) do
        if kindSet[meta.kind] then
            local resolvedID = spellID
            if FindSpellOverrideByID then
                local ov = FindSpellOverrideByID(spellID)
                if ov and ov ~= 0 and ov ~= spellID then resolvedID = ov end
            end
            if BlizzardAPI.IsSpellAvailable(resolvedID) then
                result[#result + 1] = {
                    spellID = resolvedID, type = meta.kind,
                    mech = meta.mech, reach = meta.reach, radius = meta.radius, pri = meta.pri,
                }
                -- Register for local cooldown tracking so IsSpellReady() can detect
                -- CD state in combat (isOnGCD is nil for most interrupt spells).
                if BlizzardAPI.RegisterSpellForTracking then
                    BlizzardAPI.RegisterSpellForTracking(resolvedID, "interrupt")
                end
            end
        end
    end
    if #result == 0 then return nil end
    table.sort(result, CCSortLess)
    return result
end

local INTERRUPT_KINDS = { interrupt = true, cc = true }

function SpellDB.ResolveInterruptSpells()
    return ResolveAbilitiesByKind(INTERRUPT_KINDS)
end

--- Resolve the player's usable enrage-dispel ("soothe") abilities from SOOTHE_ABILITIES.
--- Usually 0 or 1 (class-specific). Talent-gated entries (meta.requires) only count when at
--- least one enabling talent is known - so a Monk without Pressure Points isn't offered
--- Paralysis as a soothe. Enrage-triggered (dispel type 9), not cast-triggered.
function SpellDB.ResolveSootheSpells()
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if not BlizzardAPI or not BlizzardAPI.IsSpellAvailable then return nil end
    local result = {}
    for spellID, meta in pairs(SOOTHE_ABILITIES) do
        local resolvedID = spellID
        if FindSpellOverrideByID then
            local ov = FindSpellOverrideByID(spellID)
            if ov and ov ~= 0 and ov ~= spellID then resolvedID = ov end
        end
        if BlizzardAPI.IsSpellAvailable(resolvedID) then
            -- Talent gate: at least one `requires` talent must be known (nil = always on).
            local gated = false
            if meta.requires then
                gated = true
                for _, talentID in ipairs(meta.requires) do
                    if BlizzardAPI.IsSpellAvailable(talentID) then gated = false; break end
                end
            end
            if not gated then
                result[#result + 1] = { spellID = resolvedID, type = "soothe", reach = meta.reach }
                if BlizzardAPI.RegisterSpellForTracking then
                    BlizzardAPI.RegisterSpellForTracking(resolvedID, "interrupt")
                end
            end
        end
    end
    if #result == 0 then return nil end
    return result
end

--------------------------------------------------------------------------------
-- Static spell classification tables (shared with RedundancyFilter)
-- Pure data - no dependency on filter state. Maintained here so other modules
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

-- Raid buffs are also unique auras (can only have one active) - merge at load time.
for spellID in pairs(SpellDB.RAID_BUFF_SPELLS) do
    SpellDB.UNIQUE_AURA_SPELLS[spellID] = true
end
