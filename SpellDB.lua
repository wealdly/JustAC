-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Database - Native spell classification tables for filtering and categorization
local SpellDB = LibStub:NewLibrary("JustAC-SpellDB", 20)
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

-- Cached override->base resolution: the base spell ID, or false when there is
-- none. Callers guard C_Spell_GetBaseSpell availability.
local function resolveBase(spellID)
    local base = baseIDCache[spellID]
    if base == nil then
        local ok, b = pcall(C_Spell_GetBaseSpell, spellID)
        base = (ok and type(b) == "number" and b > 0) and b or false
        baseIDCache[spellID] = base
    end
    return base
end

local function StaticLookup(t, spellID)
    if not t or not spellID then return nil end
    local v = t[spellID]
    if v ~= nil or not C_Spell_GetBaseSpell then return v end
    local base = resolveBase(spellID)
    if base and base ~= spellID then return t[base] end
    return nil
end

-- Distinct base spell of a talent-override variant, or nil when there is none
-- (self is its own base, or C_Spell.GetBaseSpell is unavailable). Shares
-- StaticLookup's cache; exposed so other modules reuse this resolution instead
-- of maintaining their own override->base cache.
function SpellDB.GetBaseSpell(spellID)
    if not spellID or not C_Spell_GetBaseSpell then return nil end
    local base = resolveBase(spellID)
    if base and base ~= spellID then return base end
    return nil
end

-- Aura max stacks: generated table only. The earlier "the live API throws" note was WRONG -
-- it probed C_UnitAuras.GetSpellMaxCumulativeAuraApplications, but the function lives in
-- C_Spell (SpellDocumentation.lua:423), so that was an attempt-to-call-nil, not a restriction.
-- The real availability is UNTESTED. The validate suite's tripwire probe now calls the correct
-- namespace; re-run it before treating the generated table as the only possible source.
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
        PRECOMBAT_ITEM_CATEGORY[e.id] = cat
    end
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
    if UnitAffectingCombat("player") then return nil end
    -- Lazy resolve: SpellDB loads BEFORE BlizzardAPI in the TOC, so this cannot
    -- be an upvalue (same reason as IsInterruptOnCooldown below).
    local api = LibStub("JustAC-BlizzardAPI", true)
    if not (api and api.GetAuras) then return nil end
    local now = GetTime()
    if now - eatCacheAt < 0.2 then return eatCache end
    eatCacheAt = now
    eatCache = nil
    local auras = api.GetAuras("player", "HELPFUL")
    for i = 1, (auras and #auras or 0) do
        local a = auras[i]
        if a.spellId and not (issecretvalue and issecretvalue(a.spellId))
           and EATING_AURAS[a.spellId] then
            eatCache = a
            break
        end
    end
    return eatCache
end

--- Well Fed lands after ~10s of eating, not at the end of the ~20s food aura. Past that
--- point the rest of the meal is only health/mana regen, so nothing should still be told
--- to wait on it - you are free to move on, and standing up keeps the buff.
--- True only inside that window; false once the buff has been granted (or is not being
--- eaten for). Callers: the mid-application wait/disarm and the queue grey-out.
local WELL_FED_SECONDS = 10
function SpellDB.IsEatingForBuff()
    local a = SpellDB.GetActiveEatingAura()
    if not a then return false end
    local dur, exp = a.duration, a.expirationTime
    -- Secret timing (aura-restricted contexts): elapsed is unmeasurable, so hold the
    -- conservative answer - the whole meal counts, exactly as before.
    if issecretvalue and (issecretvalue(dur) or issecretvalue(exp)) then return true end
    if not dur or not exp or dur <= 0 then return true end
    local elapsed = GetTime() - (exp - dur)
    return elapsed < math.min(dur, WELL_FED_SECONDS)
end

--------------------------------------------------------------------------------
-- CLASS MAINTAINED BUFFS: self-buffs the player keeps up pre-combat (poisons, imbues...).
-- Each group holds interchangeable options; we maintain whichever is ACTIVE (refresh before
-- it lapses) rather than picking a "best", and suggest `default` only when none is up. Cast
-- and detect share the same spellID (the ability applies a like-named self-buff). Gated at
-- runtime by IsPlayerSpell, so only spells the player actually knows ever surface.
-- The assisted-combat rotation's own pick within a group overrides ALL of this - default,
-- queue scan, and even a fresh active member - because AC keeps recommending its exact
-- member until it's applied (see PrecombatEngine.ACPickInGroup for the full rationale).
--
-- raidWide = true marks a group buff: one cast covers the whole party, so it is ALSO
-- re-offered when the player has it but a party member doesn't (someone who joined,
-- released, or was out of range when it went out). Entries without the flag are
-- genuinely personal - poisons, shields, imbues - and are never group-checked.
--------------------------------------------------------------------------------
SpellDB.CLASS_MAINTAINED_BUFFS = {
    DRUID = {
        { group = { 1126 }, default = 1126, raidWide = true },         -- Mark of the Wild
    },
    EVOKER = {
        -- Blessing of the Bronze does NOT apply its own cast id: the cast triggers one of
        -- 13 per-class sub-auras, so both the self-check and the party check must match the
        -- whole family or a fully buffed player reads as missing forever. auraIDs overrides
        -- `group` for DETECTION only - `default`/`group` stay the id that gets cast.
        { group = { 364342 }, default = 364342, raidWide = true,       -- Blessing of the Bronze
          auraIDs = { 381732, 381741, 381746, 381748, 381749,
                      381750, 381751, 381752, 381753, 381754,
                      381756, 381757, 381758 } },
    },
    MAGE = {
        { group = { 1459 }, default = 1459, raidWide = true },         -- Arcane Intellect
    },
    PALADIN = {
        -- Auras are stance-style toggles but DO register as normal player auras under
        -- their cast id (validated in game: active Devotion Aura answers the by-id
        -- probe as 465). NOT raidWide: an Aura is radius-based - re-casting it does
        -- nothing for a party member who is simply out of range.
        { group = { 465, 32223, 183435 }, default = 465 },             -- Devotion/Crusader/Retribution Aura
    },
    PRIEST = {
        { group = { 21562 }, default = 21562, raidWide = true },       -- Power Word: Fortitude
    },
    ROGUE = {
        { group = { 315584, 2823, 8679, 381664 }, default = 315584 },  -- Lethal (Instant default)
        { group = { 3408, 5761, 381637 }, default = 3408 },            -- Non-lethal (Crippling default)
    },
    SHAMAN = {
        { group = { 192106, 52127, 974 }, default = 192106 },          -- Shield (Lightning/Water/Earth)
        { group = { 462854 }, default = 462854, raidWide = true },     -- Skyfury
    },
    WARRIOR = {
        { group = { 6673 }, default = 6673, raidWide = true },         -- Battle Shout
    },
    -- No aura-based maintained pre-combat self-buff (or handled by the pet system):
    -- DEATHKNIGHT, DEMONHUNTER, HUNTER, MONK, WARLOCK. Shaman weapon imbues
    -- (Windfury/Flametongue/Earthliving) are weapon enchants, not auras - they're suggested
    -- via GetWeaponEnchantInfo in PrecombatEngine (see WEAPON_IMBUE_SPELLS below).
}

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

-- Cheap self-heals castable out of combat, per class: preferred over Recuperate
-- for topping off (faster, and the resource regenerates out of combat anyway).
-- Only no/short-cooldown heals belong here - never real combat cooldowns
-- (Exhilaration, Renewal), which Recuperate exists to preserve. First KNOWN
-- entry wins; classes without an entry fall back to Recuperate.
-- These spells also appear as regular defensive-list entries, so the green glow
-- must key on entry provenance (the queue entry's precombat flag), never on spell
-- identity - an identity check would glow the defensive copy too.
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

local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local IsSpellKnown = IsSpellKnown

--- Is the current target within `yards`? Returns true / false / nil (unknown).
--- Brackets the target using the player's KNOWN reference abilities: a reference of range
--- ≤ yards that IS in range proves target ≤ yards (within); a reference of range ≥ yards
--- that is OUT of range proves target > yards (beyond). Distance in yards is a secret in
--- combat, but IsSpellInRange's boolean is not - this is built entirely on it.
--- Reliability scales with probe density near `yards`; nil when no probe brackets it.
-- Spec-filtered probe list + per-tick verdict memo: the naive version scanned all
-- ~65 references with an IsSpellKnown call each, twice per queue build (gap-closer
-- + melee-context checks in the same tick). The known set only changes on talent
-- swaps, so a short refresh window self-heals those; the memo collapses the
-- second same-tick call to a table read.
local knownRangeProbes = {}      -- flat pairs: id1, ref1, id2, ref2, ...
local knownRangeProbesTime = -math.huge
local KNOWN_PROBE_REFRESH = 5    -- seconds
-- Per-tick verdict memo keyed by yards (the gap closer asks 5yd AND its near-band in
-- the same build, plus ContextRank's 5yd - a single-slot memo would thrash and re-poll
-- every probe). UNKNOWN stands in for a memoized nil verdict, which a table can't hold.
local withinVerdicts = {}
local lastWithinTime = -1
local WITHIN_UNKNOWN = {}
local cachedBlizzAPIRef
function SpellDB.IsTargetWithin(yards)
    if not C_Spell_IsSpellInRange then return nil end
    local now = GetTime()
    if now == lastWithinTime then
        local v = withinVerdicts[yards]
        if v ~= nil then
            if v == WITHIN_UNKNOWN then return nil end
            return v
        end
    else
        wipe(withinVerdicts)
        lastWithinTime = now
    end

    local api = cachedBlizzAPIRef
    if not api then
        api = LibStub("JustAC-BlizzardAPI", true)
        cachedBlizzAPIRef = api
    end
    local isSecret = api and api.IsSecretValue

    if (now - knownRangeProbesTime) >= KNOWN_PROBE_REFRESH then
        knownRangeProbesTime = now
        local n = 0
        for id, ref in pairs(RANGE_REFERENCES) do
            -- Gate on KNOWN (form-independent), NOT castability: IsSpellAvailable would skip a
            -- form-gated probe (a Druid's Mangle while shifted, anything on GCD/low resources),
            -- which silently breaks detection. IsSpellInRange only needs the spell to be known.
            if not IsSpellKnown or IsSpellKnown(id) then
                knownRangeProbes[n + 1], knownRangeProbes[n + 2] = id, ref
                n = n + 2
            end
        end
        for i = #knownRangeProbes, n + 1, -1 do knownRangeProbes[i] = nil end
    end

    local within, beyond
    for i = 1, #knownRangeProbes, 2 do
        local id, ref = knownRangeProbes[i], knownRangeProbes[i + 1]
        local r = C_Spell_IsSpellInRange(id, "target")   -- "target" unit is required
        if r ~= nil and not (isSecret and isSecret(r)) then
            if r ~= false then
                if ref <= yards then                     -- target ≤ ref ≤ yards
                    within = true
                    break  -- within outranks beyond: the verdict is already decided
                end
            elseif ref >= yards then
                beyond = true                            -- target > ref ≥ yards
            end
        end
    end

    local verdict
    if within then verdict = true elseif beyond then verdict = false end
    withinVerdicts[yards] = (verdict == nil) and WITHIN_UNKNOWN or verdict
    return verdict
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
--- Memoized on the spec index: class never changes in-session, and the concat
--- allocated a fresh string per call - this runs per spell per queue build via
--- RotationImport.GetEntry and per defensive list fetch.
local specKeyCache, specKeyClass, specKeySpec
function SpellDB.GetSpecKey()
    local spec = GetSpecialization and GetSpecialization()
    if specKeyClass and spec == specKeySpec then
        return specKeyCache, specKeyClass
    end
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil, nil end
    specKeyClass, specKeySpec = playerClass, spec
    specKeyCache = spec and (playerClass .. "_" .. spec) or nil
    return specKeyCache, playerClass
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
-- ORDERING RULE - cast-time heals go BELOW instants, always.
-- List order is the above-threshold "what should I press now" order, and in combat a heal
-- you have to stand still for is the wrong answer while any instant is available. The case
-- where a cast-time heal IS right - its proc is up, making it instant and free - needs no
-- help from this list: a proc promotes a spell to the front tier ahead of even position 1
-- (see the procced/non-procced split in DefensiveEngine.GetUsableDefensiveSpells), so
-- ranking it high only makes it a slow hardcast sitting at the top the rest of the time.
-- Verified against the DB2 exports: exactly three entries in this whole table are non-
-- instant (SpellMisc CastingTimeIndex ~= 1) - Regrowth, Healing Surge and Vivify - and all
-- three are last in their lists. Re-run that check before adding a heal.
SpellDB.CLASS_DEFENSIVE_DEFAULTS = {
    -- ── Death Knight ────────────────────────────────────────────────────────
    -- Class fallback (Frost/Unholy DPS): quick heal then big CDs
    DEATHKNIGHT   = {49998, 48743, 48792, 48707, 51052, 49039, 327574}, -- Death Strike, Death Pact, Icebound Fortitude, Anti-Magic Shell, Anti-Magic Zone, Lichborne, Sacrificial Pact
    -- Blood (tank): active mitigation first, Death Strike for heal, then big CDs
    -- (Rune Tap 194679 verified still live in 12.1 DB2 despite older "removed" notes)
    DEATHKNIGHT_1 = {49998, 55233, 194679, 48743, 48792, 48707, 51052, 219809, 49039}, -- Death Strike, Vampiric Blood, Rune Tap, Death Pact, IBF, AMS, AMZ, Tombstone, Lichborne

    -- ── Demon Hunter ────────────────────────────────────────────────────────
    -- Class fallback (Havoc DPS): Blur, Netherwalk (talent), Darkness
    DEMONHUNTER   = {198589, 196555, 196718},                   -- Blur, Netherwalk, Darkness
    -- Vengeance (tank): Soul Cleave heal, Demon Spikes, Fiery Brand, Metamorphosis (a
    -- Vengeance SURVIVAL cd, not a DPS burst - unlike Havoc's), then Blur
    DEMONHUNTER_2 = {228477, 203720, 204021, 187827, 198589, 263648}, -- Soul Cleave, Demon Spikes, Fiery Brand, Metamorphosis, Blur, Soul Barrier

    -- ── Druid ───────────────────────────────────────────────────────────────
    -- Class fallback (Balance): self-heals then CDs. Rejuvenation, Survival Instincts and
    -- Heart of the Wild are class talents any spec can take - included so a talented caster
    -- gets them; the runtime known-spell gate drops them when untalented. Heart of the Wild
    -- empowers abilities OUTSIDE your spec, so for a non-healer it's the button that makes
    -- the class-tree heals actually land.
    -- Frenzied Regeneration is deliberately ABSENT here and from Resto, for the mirror of
    -- the reason Rejuvenation is absent from Feral: DB2 SpellShapeshift gives it
    -- ShapeshiftMask_0 = 16, i.e. Bear Form only. A form-gated button is not dropped by the
    -- queue - unusable entries are pushed to the end and rendered greyed - so leaving it in
    -- costs a permanent dead slot out of the four the queue shows by default. Feral keeps it
    -- because bear-weaving to Frenzied Regen is real play there; a caster shifting to Bear
    -- has already stopped doing its job.
    DRUID         = {774, 108238, 1261867, 61336, 22812, 8936},         -- Rejuvenation, Renewal, Heart of the Wild, Survival Instincts, Barkskin, Regrowth
    -- Feral: Frenzied Regen (class talent, Bear-only - see above) leads, and Regrowth is
    -- deliberately near the BOTTOM despite being the bigger heal. In combat Regrowth is only
    -- worth pressing when Predatory Swiftness makes it instant, and that case needs no help
    -- from list order: a proc promotes it to the front tier ahead of everything, above even
    -- position 1. Ranking it high would only make it a slow hardcast sitting at the top of
    -- the queue the rest of the time. Frenzied Regen has no proc to wait for, so list order
    -- is the only thing that can rank it, and it is pressable whenever it is off cooldown.
    -- (Rejuvenation omitted: castable only out of form, so it self-gates away for most Ferals)
    DRUID_2       = {22842, 1261867, 61336, 22812, 8936, 108238},       -- Frenzied Regen, Heart of the Wild, Survival Instincts, Barkskin, Regrowth, Renewal
    -- Guardian (tank): Frenzied Regen, Ironfur, Barkskin, Heart of the Wild, Survival Instincts, Rage of the Sleeper
    DRUID_3       = {22842, 192081, 22812, 1261867, 61336, 200851},     -- Frenzied Regen, Ironfur, Barkskin, Heart of the Wild, Survival Instincts, Rage of the Sleeper  (Renewal removed in 12.0)
    -- Restoration: the class fallback minus Heart of the Wild - it empowers off-spec
    -- abilities, which for a healer means damage, not survival - plus Ironbark, which is a
    -- Resto button that happens to be self-targetable and is its only real damage-reduction
    -- cooldown. (Frenzied Regen omitted: Bear-only, see the class note above.)
    DRUID_4       = {774, 108238, 102342, 61336, 22812, 8936},          -- Rejuvenation, Renewal, Ironbark, Survival Instincts, Barkskin, Regrowth

    -- ── Evoker ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs): self-heals then defensive CDs. Renewing Blaze, Zephyr and
    -- Emerald Communion are class talents (verified live in 12.1 DB2); dropped by the
    -- known-spell gate when untalented.
    EVOKER        = {360995, 374348, 363916, 374227, 370960},   -- Verdant Embrace, Renewing Blaze, Obsidian Scales, Zephyr, Emerald Communion

    -- ── Hunter ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs)
    HUNTER        = {109304, 264735, 281195, 186265, 388035},  -- Exhilaration, Survival of the Fittest, SotF (Lone Wolf), Aspect of the Turtle, Fortitude of the Bear

    -- ── Mage ────────────────────────────────────────────────────────────────
    -- Class fallback (Fire/Frost). The spec-appropriate barrier is auto-learned; all three
    -- are listed so the one the player actually knows will be shown.
    MAGE          = {11426, 235313, 235450, 342245, 45438},    -- Ice/Blazing/Prismatic Barrier, Alter Time, Ice Block
    -- Arcane: its barrier is Prismatic, so the other two are dropped rather than carried as
    -- known-gated filler, making room for Greater Invisibility - Arcane's signature wall
    -- (heavy damage reduction plus a threat drop) and the one defensive the class fallback
    -- cannot cover, since no other spec has it.
    MAGE_1        = {235450, 110959, 342245, 45438},           -- Prismatic Barrier, Greater Invisibility, Alter Time, Ice Block

    -- ── Monk ────────────────────────────────────────────────────────────────
    -- Class fallback (Windwalker): Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic
    MONK          = {322101, 115203, 122278, 122783},          -- Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic
    -- Brewmaster (tank): Purifying Brew first (stagger is the real damage signal - the
    -- float hint below surfaces it whenever Moderate/Heavy Stagger is up), then Celestial
    -- Brew, Expel Harm, Fortifying Brew, then class-talent DR (Dampen Harm / Diffuse Magic /
    -- Zen Meditation - verified live in 12.1 DB2; known-gate drops any untalented)
    -- Guard (115295) was removed from all three lists: it is a MoP-era ability the DB2
    -- exports still carry a name row for, but it has no SkillLineAbility row and no
    -- TraitDefinition entry, while every live Monk talent checked alongside it (Dampen
    -- Harm, Diffuse Magic, Zen Meditation, Celestial Brew, Purifying Brew) has both.
    -- The known-spell gate was hiding it, so this costs nothing and removes the pretence
    -- of coverage. Do not restore it without a SkillLineAbility or TraitDefinition row.
    MONK_1        = {119582, 322507, 322101, 120954, 122278, 122783, 115176}, -- Purifying Brew, Celestial Brew, Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic, Zen Meditation
    -- Mistweaver: Life Cocoon leads - a big instant absorb it can cast on ITSELF, and the
    -- spec's single strongest defensive - then the DR CDs. Vivify is last: it is a hardcast,
    -- and the case where it is the right button - instant off its own proc - is promoted
    -- automatically without needing a high slot here.
    MONK_2        = {116849, 243435, 115203, 122278, 122783, 388615, 116670}, -- Life Cocoon, Fortifying Brew (MW), Fortifying Brew, Dampen Harm, Diffuse Magic, Restoral, Vivify
    -- Windwalker: Expel Harm, Touch of Karma, Fortifying Brew, Diffuse Magic
    MONK_3        = {322101, 122470, 201318, 122278, 122783}, -- Expel Harm, Touch of Karma, Fortifying Brew (WW), Dampen Harm, Diffuse Magic

    -- ── Paladin ─────────────────────────────────────────────────────────────
    -- Class fallback (Ret): Word of Glory, Divine Protection, Divine Shield, Lay on Hands
    PALADIN       = {85673, 403876, 184662, 1022, 642, 633},   -- Word of Glory, Divine Protection, Shield of Vengeance, Blessing of Protection, Divine Shield, Lay on Hands
    -- Holy: Ret's list is the wrong shape - Shield of Vengeance is Ret-only, and Holy's own
    -- Divine Protection is a different spell id (498, not 403876; both are live in 12.1).
    -- Aura Mastery is the spec's major cooldown and is self-covering.
    PALADIN_1     = {85673, 498, 31821, 1022, 642, 633},       -- Word of Glory, Divine Protection (Holy), Aura Mastery, Blessing of Protection, Divine Shield, Lay on Hands
    -- Protection (tank): Word of Glory, Ardent Defender, Guardian of Ancient Kings,
    -- Divine Shield, Lay on Hands.  Shield of the Righteous is deliberately absent -
    -- AC recommends it rotationally, so it lives in the offensive queue.
    -- Blessing of Spellwarding is self-castable and is the spec's only true magic wall.
    PALADIN_2     = {85673, 31850, 86659, 387174, 389539, 378974, 204018, 642, 633}, -- Word of Glory, Ardent Defender, Guardian of Ancient Kings, Eye of Tyr, Sentinel, Bastion of Light, Blessing of Spellwarding, Divine Shield, Lay on Hands

    -- ── Priest ──────────────────────────────────────────────────────────────
    -- Class fallback: Desperate Prayer, PW:Shield, Fade. Every spec has a major cooldown
    -- of its own on top of this - all three are self-castable - so all three get an entry
    -- and this list is a floor, not the expected shape for anyone.
    PRIEST        = {19236, 17, 586},                          -- Desperate Prayer, PW:Shield, Fade
    -- Discipline: Pain Suppression, its big damage-reduction cooldown, self-cast.
    PRIEST_1      = {19236, 17, 33206, 586},                   -- Desperate Prayer, PW:Shield, Pain Suppression, Fade
    -- Holy: Guardian Spirit, a cheat-death that works perfectly well aimed at yourself.
    PRIEST_2      = {19236, 17, 47788, 586},                   -- Desperate Prayer, PW:Shield, Guardian Spirit, Fade
    -- Shadow: Desperate Prayer, PW:Shield, Dispersion, Fade
    PRIEST_3      = {19236, 17, 47585, 586},                   -- Desperate Prayer, PW:Shield, Dispersion, Fade

    -- ── Rogue ───────────────────────────────────────────────────────────────
    -- Class fallback (all specs share the same toolkit)
    ROGUE         = {185311, 1966, 31224, 5277},               -- Crimson Vial, Feint, Cloak of Shadows, Evasion

    -- ── Shaman ──────────────────────────────────────────────────────────────
    -- Class fallback (Elemental/Enhancement). Earth Shield is talent-gated for them and
    -- self-castable; the known-spell gate drops it when untalented.
    -- Healing Surge is last: it is a hardcast, and the case where it is the right button -
    -- Enhancement with Maelstrom Weapon stacked, making it instant - arrives as a proc and
    -- is promoted automatically.
    SHAMAN        = {108271, 974, 108281, 198103, 8004},       -- Astral Shift, Earth Shield, Ancestral Guidance, Earth Elemental, Healing Surge
    -- Restoration: Earth Shield is baseline and belongs on the player between casts, and the
    -- spec owns two panic totems the other specs have no access to. Earth Elemental is
    -- dropped - a healer under pressure is not stopping to summon one.
    SHAMAN_3      = {108271, 974, 98008, 207399, 108281, 8004}, -- Astral Shift, Earth Shield, Spirit Link Totem, Ancestral Protection Totem, Ancestral Guidance, Healing Surge

    -- ── Warlock ─────────────────────────────────────────────────────────────
    -- Class fallback (all specs share dark pact / drain / UR)
    WARLOCK       = {108416, 234153, 212295, 104773},          -- Dark Pact, Drain Life, Nether Ward, Unending Resolve

    -- ── Warrior ─────────────────────────────────────────────────────────────
    -- Class fallback (Arms/Fury DPS). Die by the Sword is Arms-only and Enraged
    -- Regeneration Fury-only - the runtime known-spell gate shows each spec its own wall.
    -- Bitter Immunity is a class talent all three specs can take (instant self-heal plus a
    -- dispel), so it sits with the other quick heals.
    WARRIOR       = {34428, 202168, 383762, 190456, 118038, 184364, 23920, 386208, 97462},  -- Victory Rush, Impending Victory, Bitter Immunity, Ignore Pain, Die by the Sword, Enraged Regeneration, Spell Reflection, Defensive Stance, Rallying Cry
    -- Protection (tank): Shield Block first (physical active mitigation, used on CD -
    -- the sink hint below parks it while its buff is already rolling), then Ignore Pain,
    -- Impending Victory, Last Stand + Shield Wall (major CDs), Rallying Cry, Spell Reflection.
    -- (Last Stand 12975 is an active 3-min CD in 12.1 DB2 - the older "passive" note was wrong.)
    WARRIOR_3     = {2565, 190456, 202168, 383762, 12975, 871, 97462, 23920}, -- Shield Block, Ignore Pain, Impending Victory, Bitter Immunity, Last Stand, Shield Wall, Rallying Cry, Spell Reflection
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
    [196555] = 1,  -- Netherwalk (Demon Hunter, full damage immunity - a true bubble, not
                   -- the partial avoidance Blur gives, which is why only this one is tiered)
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
    [383762] = 2,  -- Bitter Immunity (Warrior, instant % heal - Desperate Prayer's shape)
    [116849] = 2,  -- Life Cocoon (Mistweaver, instant absorb, self-castable)
    -- Tier 4 - PRE-EMPTIVE walls: major damage reduction, plus cheat-deaths that have to be up
    -- before the hit resolves. Split out of tier 2 because the two behave oppositely when you
    -- are HEALTHY: a heal at 90% is wasted, so parking it costs nothing, but a wall at 90% is
    -- correct play - you press Shield Wall on the telegraphed slam BEFORE it lands, not after
    -- you are at 30%. Parking these coached reactive-only cooldown use, backwards, and it hit
    -- tanks hardest since they own most of this list.
    -- The NUMBER is a label, not a rank: TIER_ORDER_LOW/CRITICAL in DefensiveEngine permute
    -- them explicitly, so 4 is not "less urgent than 3". Tier 3 remains the untagged default.
    -- Whenever you add a value here you MUST add it to both order arrays, or the spell drops
    -- out of the low-health ordering entirely.
    -- Life Cocoon is deliberately NOT here despite being an absorb: JustAC only ever renders it
    -- self-cast, and self-cast it is the spec's panic button, not a pre-applied shield.
    -- NOT tiered at all, on purpose: semi-rotational short DR (Blur, Barkskin, Ignore Pain, Ironbark),
    -- school-limited walls (AMS, Anti-Magic Zone, Spell Reflection, Diffuse Magic, and both
    -- Blessings - Protection stops physical only, Spellwarding magic only, so neither
    -- "survives any hit" the way a tier 1 bubble does), group utility that is not a personal
    -- answer (Zephyr, Spirit Link Totem), maintenance buffs (Earth Shield), and situational
    -- avoidance (Feint, Evasion) - parking or floating those would miscoach.
    [871] = 4,  -- Shield Wall (Warrior)
    [61336] = 4,  -- Survival Instincts (Druid)
    [31850] = 4,  -- Ardent Defender (Paladin)
    [86659] = 4,  -- Guardian of Ancient Kings (Paladin)
    [115203] = 4,  -- Fortifying Brew (Monk)
    [120954] = 4,  -- Fortifying Brew (Brewmaster variant)
    [201318] = 4,  -- Fortifying Brew (Windwalker variant)
    [55233] = 4,  -- Vampiric Blood (Death Knight)
    [48792] = 4,  -- Icebound Fortitude (Death Knight)
    [204021] = 4,  -- Fiery Brand (Demon Hunter)
    [108271] = 4,  -- Astral Shift (Shaman)
    [104773] = 4,  -- Unending Resolve (Warlock)
    [47585] = 4,  -- Dispersion (Shadow Priest)
    [363916] = 4,  -- Obsidian Scales (Evoker)
    [118038] = 4,  -- Die by the Sword (Arms Warrior)
    [184364] = 4,  -- Enraged Regeneration (Fury Warrior; heal-over-time BUT 30% DR while
                   -- active - the DR component makes it Fury's wall, not a trickle heal)
    [12975] = 4,  -- Last Stand (Warrior; Shield Wall's partner, tiered for the same reason)
    [200851] = 4,  -- Rage of the Sleeper (Guardian Druid)
    [187827] = 4,  -- Metamorphosis (Vengeance DH survival CD - id is Vengeance-only, Havoc's
                   -- damage version is 191427 and is deliberately not listed anywhere)
    [33206] = 4,  -- Pain Suppression (Discipline Priest)
    [47788] = 4,  -- Guardian Spirit (Holy Priest)
    [31821] = 4,  -- Aura Mastery (Holy Paladin)
    [110959] = 4,  -- Greater Invisibility (Arcane Mage)
    [207399] = 4,  -- Ancestral Protection Totem (Restoration Shaman, cheat death)
}

-- Per-spec overrides layered over DEFENSE_TIER ("CLASS_N" → { [spellID] = tier }).
-- Protection Paladin: Divine Shield drops all threat mid-pull, so as a tank it must
-- never float to the top at low health - demoted to filler tier (still listed).
local DEFENSE_TIER_SPEC = {
    PALADIN_2 = { [642] = 3 },  -- Divine Shield
}

--- Emergency tier for the low-health defensive reorder: 1 = immunity bubble, 2 = big instant
--- heal, 4 = pre-emptive wall (major DR / cheat-death), 3 = everything else (the default for
--- anything untagged). The numbers are LABELS, not ranks - DefensiveEngine's TIER_ORDER_LOW /
--- TIER_ORDER_CRITICAL permute them - which is why 4 sits above 3 in urgency.
--- Only tiers 1 and 2 are held back when healthy; 4 stays live because a wall pressed after
--- you are already low is a wall pressed too late.
--- Looks up the base list ID (talent overrides resolve to the same tool); spec overrides win.
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
-- Absorb barriers are the clearest sink case: the buff outlasts the cooldown (60s vs 30s),
-- so the button comes back up while the barrier is still on you, and re-casting REPLACES
-- the shield - throwing away whatever absorb was left. Each applies an aura with the same
-- id it is cast under, and none of them stack.
SpellDB.DEFENSIVE_AURA_HINTS = {
    [2565]   = { sinkAura = 132404 },              -- Shield Block → its own buff
    [203720] = { sinkAura = 203819 },              -- Demon Spikes → its own buff
    [11426]  = { sinkAura = 11426 },               -- Ice Barrier → its own buff
    [235313] = { sinkAura = 235313 },              -- Blazing Barrier → its own buff
    [235450] = { sinkAura = 235450 },              -- Prismatic Barrier → its own buff
    -- Rune Tap reaches the same problem from the other direction: the buff is SHORT (4s)
    -- but it carries 2 charges, so the on-cooldown park never fires while one is banked -
    -- the button stays live and a second press just overwrites the first 4s of mitigation.
    [194679] = { sinkAura = 194679 },              -- Rune Tap → its own buff
    [119582] = { floatAuras = {124273, 124274} },  -- Purifying Brew → Heavy/Moderate Stagger
}

--- Base-aware lookup of the active-mitigation ordering hint for a spell (resolves
--- talent-override variants to the base list ID). Returns the hint table or nil.
function SpellDB.GetDefensiveAuraHint(spellID)
    return StaticLookup(SpellDB.DEFENSIVE_AURA_HINTS, spellID)
end

-- The ONE mitigation buff each tank spec is expected to keep rolling, for the defensive
-- maintenance slot. `cast` is the button pressed, `aura` the buff that lands on the PLAYER -
-- they differ for every spec except Ironfur. `stacks` marks the two buffs whose COUNT is
-- meaningful (Ironfur, Bone Shield); printing "1" on a non-stacking buff is noise.
--
-- Duration and stacks are SECRET in combat - our logic only ever gets the up/down boolean.
-- `dur` is the aura's BASE duration from client data, used ONLY to lead the refresh glow, and
-- must be carried statically because remaining time cannot be measured. Talents that extend a
-- duration make the estimate EARLY, the safe direction: an early cue costs one refresh, a late
-- one costs a gap in mitigation. The countdown SWIPE is engine-drawn and exact regardless - so
-- never tune `dur` to fix a timer, it only moves the glow.
SpellDB.MAINTENANCE_DEFENSIVE = {
    -- chargeGated: limited by CHARGES, not resources. These CANNOT be held up perpetually -
    -- uptime is capped by the recharge rate - so the early "refresh" pre-warning is wrong for
    -- them: pressing before the buff drops throws away buff time you cannot get back, and the
    -- charge may not even be available. They cue only once the buff has actually gone, and the
    -- icon shows the ABILITY (charges + recharge) rather than the aura.
    -- `dur` is kept because the swipe still wants it; only the pre-warning is suppressed.
    -- Set it from SpellCategories.ChargeCategory, NOT from resemblance: Shield of the
    -- Righteous looks like these three and is resource-gated (ChargeCategory=0).
    -- Charge counts here are TALENT-DEPENDENT, so never hardcode them - the renderer reads
    -- maxCharges live from C_Spell.GetSpellCharges, which is correct under any build.
    -- SpellCategory gives only the BASE: Shield Block category 1385 = MaxCharges 1 / 16s
    -- recharge, Demon Spikes category 1586 = 1 / 20s. A talent adds the second charge -
    -- confirmed in game for Prot, and visible in DB2 as "Shield Master" (165340) carrying
    -- EffectAura=411 (modify charges) with EffectMiscValue_0=1385.
    -- NOTE FOR FUTURE AUDITS: charge modifiers target the CHARGE CATEGORY, not the spell, so
    -- searching SpellEffect for rows referencing the spell id finds nothing and wrongly reads
    -- as "no talent adds a charge". Search EffectMiscValue for the category id instead.
    -- Each spec is a LIST, ordered by priority for ties. The slot shows whichever entry most
    -- needs pressing right now, so a spec that genuinely maintains two buffs gets both.
    --
    -- Protection: IGNORE PAIN ONLY. Shield Block is deliberately NOT here, and the reason is
    -- SITUATIONAL VALUE, not uptime. Shield Block raises block chance against MELEE attacks -
    -- it does nothing against magic - so whether it is worth pressing depends on what is
    -- hitting you. That is a "which defensive suits this situation" question, which is the
    -- defensive queue's job; it sits at position 1 of the Prot list there. Ignore Pain absorbs
    -- damage of any school, so it is unconditionally worth keeping up - which is what this
    -- slot is for. The split is by KIND of decision, not by how often the button is pressed.
    -- Do NOT restore it on the theory that the offensive queue covers it: active mitigation is
    -- deliberately excluded from the SimC rotation (see the SKIP set in gen_simc_rotations.py,
    -- which lists shield_block alongside ignore_pain and ironfur), so it never appears there.
    -- The defensive queue is its only home, and that is the correct one.
    -- Contrast DEATHKNIGHT_1 below, where Marrowrend IS in both surfaces on purpose: there the
    -- two carry different meanings ("spend runes" vs "your stacks are running out"). Shield
    -- Block carries the same meaning in both places, so a second home adds nothing.
    WARRIOR_3     = {
        -- absorb: the buff can end EARLY, when the shield is eaten rather than when the timer
        -- runs out - so the swipe alone overstates protection.
        -- OBSERVED in game: the aura carries a count rendered where a stack count normally
        -- sits. It RISES as you recast (absorb accumulating) and FALLS as damage comes in,
        -- capping at 100. Measured on one character: 35 ~= 14k absorbed, 100 ~= 37k - linear
        -- at roughly 370-400 damage per point - so the number is the absorb pool NORMALISED
        -- to its cap, i.e. a percentage. 100 means capped and further casts waste rage.
        -- Displaying the normalised 0-100 rather than the raw amount is the right call: the
        -- absolute values scale with gear and rage, the percentage does not.
        -- Related mechanic, for anyone reasoning about drain rate: Ignore Pain absorbs at most
        -- 50% of any single incoming hit, so the pool empties more slowly than raw damage
        -- taken would suggest. Do not model depletion as 1:1 with damage.
        -- DB2 cannot settle any of this: there is no SpellAuraOptions row for 190456 at all,
        -- so the accumulate/cap behaviour is script-driven and invisible to the CSVs.
        -- We show it anyway, because whatever its unit, it demonstrably tracks depletion - and
        -- that is the one thing the swipe cannot tell you. We only pass it through to the
        -- engine; nothing here interprets or compares it, so being wrong about the unit costs
        -- nothing. Do not build logic on its scale without confirming what it counts.
        -- `dur` = 12s, the real expiry (SpellDuration id 29). `lead` = 4s.
        -- Be careful about WHY, because the obvious reason is wrong: the number is a POOL of
        -- total absorb, not a buff strength, so holding it at 100 does not absorb more than
        -- letting it sit low. Take 14k of damage and one application covers it exactly as well
        -- as three. High uptime is not itself the goal, and "keep it capped" is not the advice
        -- - topping up beyond the damage you will actually take just wastes rage.
        -- What the lead IS for: absorb left in the pool when the aura expires is absorb thrown
        -- away, and refreshing rolls it forward instead. The press is close to free (Ignore
        -- Pain is an off-GCD dump for rage that would otherwise overcap), so pre-warning costs
        -- little and preserves whatever remains. That is a weaker justification than the
        -- chargeGated entries have for the opposite choice, and it is deliberately a soft cue.
        -- The genuinely optimal call - size the pool to incoming damage - needs to know both
        -- the remaining pool and the damage coming, and we can read neither in combat.
        -- If the shield is eaten before the timer, the aura drops and the authoritative "down"
        -- path catches it at rank 1, so that case needs no prediction.
        -- project: same cast-timestamp model as Ironfur. dur verified against the DB2 exports
        -- (SpellMisc DurationIndex 29 -> 12000ms). The absorb-eaten-early case is NOT projected
        -- away: a confirmed drop clears the projection, per the note above.
        { cast = 190456, aura = 190456, dur = 12.0, lead = 4.0, stacks = true, project = true },  -- Ignore Pain
    },
    PALADIN_2     = {
        -- NOT chargeGated, despite looking like its Warrior/DH counterparts: SpellCategories
        -- for 53600 has ChargeCategory=0, i.e. no charge system exists for it. It is a HOLY
        -- POWER spender, so it behaves like Ignore Pain - generation-limited, not recharge-
        -- limited - and therefore CAN be held up and DOES want the early pre-warning cue.
        -- project WITHOUT stacks = refresh semantics: a recast replaces the timer instead of
        -- adding a stack, so the sweep anchors on the NEWEST cast. Being cast-driven means the
        -- sweep no longer waits on an aura bind. Unlike Ironfur this buff has one instance, so
        -- that instance dying is still honoured as a real drop (see the note in EntryState) -
        -- an early removal cannot be outlived by the projected clock.
        -- UNMEASURED: whether a recast mints a new auraInstanceID here as Ironfur does. If it
        -- does, this also fixes the same stack-hopping sweep; if it refreshes one instance, the
        -- gain is only the removed bind latency. Either way the projection is not worse.
        { cast = 53600,  aura = 132403, dur = 4.5, project = true },  -- Shield of the Righteous
    },
    DEMONHUNTER_2 = {
        { cast = 203720, aura = 203819, dur = 12.0, chargeGated = true },  -- Demon Spikes
    },
    -- Ironfur casts and buffs under one id. NOTE: SpellAuraOptions says CumulativeAura=1, and an
    -- earlier /jac inspect stacks run read it as ONE instance with applications=2 - so the cap
    -- is enforced outside that DB2 field either way. SUPERSEDED for anything about instances:
    -- a 2026-07-25 maintlog run recorded 94 casts producing 94 DISTINCT auraInstanceIDs, with
    -- older ids still alive after newer ones appeared. Whatever the applications field shows,
    -- the stacks are separate aura instances with independent expiries - which is why this entry
    -- projects from casts instead of tracking one instance.
    -- lead: glow ~3s before decay. 7s is short enough that the proportional 30% default gives
    -- barely 2s of warning - too tight to react to mid-pull. Pressing EARLIER than the cue is
    -- always legitimate (stacking Ironfur is a damage-intake call the player makes, not one we
    -- can see), so the cue is a floor, never a "do not press yet".
    DRUID_3       = {
        -- project: each cast is its own aura instance with its own expiry (measured: 94 casts,
        -- 94 distinct instance ids, older ones outliving newer). Tracked by cast timestamps
        -- instead of by instance, so the sweep and stack count stop hopping between stacks.
        -- dur verified against the DB2 exports (SpellMisc DurationIndex 165 -> 7000ms).
        { cast = 192081, aura = 192081, dur = 7.0, lead = 3.0, stacks = true, project = true },  -- Ironfur
    },
    -- Blood is deliberately a rotational OFFENSIVE button. Blizzard fused rune-spending and
    -- Bone Shield upkeep into one press, so there is no defensive-only alternative - checked,
    -- Heart Strike has no self-target grant of the right shape. The two slots carry different
    -- signals, not different buttons: the queue says "spend runes", this says "your stacks are
    -- running out". Do not "fix" this to some other spell.
    -- No `dur`, deliberately - the duration DATA exists (SpellMisc DurationIndex=9 = 30000ms),
    -- we decline to use it. Stacks are eaten by incoming DAMAGE, not time (SpellAuraOptions
    -- 19756: ProcChance=100, ProcCategoryRecovery=2500, ProcTypeMask_0=40), so a time-based
    -- refresh cue would sit quiet for 21s while the stacks were actually consumed in five.
    -- The count is also not inferable from our casts: damage-taken events live only in the
    -- hard-blocked combat log, so there is no decrement signal, and the Bone Collector talent
    -- (458572) grants stacks with no cast to observe - wrong in both directions at once.
    -- Blood therefore glows only when Bone Shield is fully GONE: a real emergency, not a guess.
    DEATHKNIGHT_1 = {
        { cast = 195182, aura = 195181, stacks = true },  -- Marrowrend -> Bone Shield
    },
    -- MONK_1 Brewmaster is intentionally ABSENT. Shuffle has two live spell ids (215479 with a
    -- real 5s duration, 322120 wired into the talent tree but durationless and proc-shaped) and
    -- neither Blackout Kick nor Keg Smash shows a grant link in the data - it is a side effect
    -- of two different buttons. Needs an in-game check before an entry is curated; a wrong
    -- button here is worse than no button.
}

--- The current spec's maintenance defensives as a LIST, or nil when the spec has none (every
--- non-tank, plus Brewmaster).
function SpellDB.GetMaintenanceDefensives()
    local specKey = SpellDB.GetSpecKey()
    local list = specKey and SpellDB.MAINTENANCE_DEFENSIVE[specKey] or nil
    if list and #list > 0 then return list end
    return nil
end

--- The spec's PRIMARY maintenance defensive. Kept for existence checks and diagnostics that
--- only need "does this spec have one at all"; anything that tracks state must use the list,
--- since a spec can maintain more than one buff.
function SpellDB.GetMaintenanceDefensive()
    local list = SpellDB.GetMaintenanceDefensives()
    return list and list[1] or nil
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

--------------------------------------------------------------------------------
-- Healer group-heal data (spec-keyed; healer specs only, so a non-healer spec
-- resolves to nil and the heal surface never appears).
--
-- Every ID below was verified against the client data export for build
-- 12.0.7.68974 - name, cooldown, cast class and target type - rather than
-- recalled. Ordering follows the defensive-list convention: cheap/rotational
-- first, cast-time heals later.
--------------------------------------------------------------------------------

-- Group-heal suggestions injected into the defensive queue while allies are
-- low, in priority order. MULTI-TARGET HEALS ONLY: single-target heals are
-- out of scope by design - aiming a heal at a person is a group-frame job.
-- A targeted AoE (Wild Growth, Chain Heal) is fine: cast with no friendly
-- target it lands on the player and the splash still covers the group.
SpellDB.CLASS_GROUPHEAL_DEFAULTS = {
    -- Restoration Druid: Wild Growth, Efflorescence, Grove Guardians
    DRUID_4 = {48438, 145205, 102693},
    -- Holy Paladin: Light of Dawn (cone), Divine Toll (multi Holy Shock)
    PALADIN_1 = {85222, 375576},
    -- Discipline Priest: multi-target ATONEMENT APPLICATORS - Discipline
    -- heals by damaging while Atonement is out. Radiance (target + allies),
    -- Prayer of Healing.
    PRIEST_1 = {194509, 596},
    -- Holy Priest: Prayer of Mending (bounces), Circle of Healing,
    -- HW: Sanctify (ground), Prayer of Healing, Halo
    PRIEST_2 = {33076, 204883, 34861, 596, 120517},
    -- Restoration Shaman: Chain Heal (bounces), Healing Stream Totem,
    -- Healing Rain (ground), Wellspring (wave)
    SHAMAN_3 = {1064, 5394, 73920, 197995},
    -- Mistweaver Monk: Vivify (cleaves to Renewing Mist holders),
    -- Renewing Mist (self-spreading HoT)
    MONK_2 = {116670, 119611},
    -- Preservation Evoker: Emerald Blossom, Dream Breath + Spiritbloom
    -- (empowered), Temporal Anomaly (wave)
    EVOKER_2 = {355913, 382614, 367226, 373861},
}

-- Group-crisis ladder for the emergency slot: first READY spell wins, so these
-- are ordered strongest-first. Dedicated group cooldowns only, DISJOINT from
-- CLASS_GROUPHEAL_DEFAULTS - a spell must never render on both surfaces at
-- once. Group-save DR cooldowns (Aura Mastery, Spirit Link, Zephyr) belong
-- here too: at 3+ allies low, stopping damage is healing.
SpellDB.HEAL_EMERGENCY_LADDER = {
    DRUID_4   = {740, 197721},                      -- Tranquility, Flourish
    PALADIN_1 = {31821, 216331},                    -- Aura Mastery, Avenging Crusader
    PRIEST_1  = {62618, 421453, 47536},             -- PW: Barrier, Ultimate Penitence, Rapture
    PRIEST_2  = {64843},                            -- Divine Hymn
    SHAMAN_3  = {108280, 207399, 98008, 108281},    -- Healing Tide, Ancestral Protection, Spirit Link, Ancestral Guidance
    MONK_2    = {388615, 322118, 325197, 231633},   -- Restoral, Yu'lon, Chi-Ji, Essence Font
    EVOKER_2  = {363534, 374227},                   -- Rewind, Zephyr
}

-- True when this spec has group-heal data (drives heal-surface visibility).
function SpellDB.SpecHasGroupHeals(specKey)
    if not specKey then specKey = SpellDB.GetSpecKey() end
    return specKey ~= nil and SpellDB.CLASS_GROUPHEAL_DEFAULTS[specKey] ~= nil
end

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
-- BURST TRIGGER DEFAULTS
-- Per-spec list of major offensive CDs. When one is visible in the queue and
-- off cooldown, SpellQueue marks it with the purple burst-ready cue ("press
-- this to start your burst"). Includes talent alternatives (e.g. Incarnation
-- vs Berserk) - unknown ones simply never appear in the queue.
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

-- MUTUALLY EXCLUSIVE pet summons: picking any one of these makes the rest pointless, because
-- they all solve the same problem ("you have no pet"). The queue keeps only the first.
--
-- Deliberately a SEPARATE, much smaller table than PET_SUMMON_SPELLS above. That one means
-- "this spell summons something", which sweeps in Army of the Dead, Summon Gargoyle, Feral
-- Spirit and the three elementals - major DPS cooldowns that are meant to be queued together
-- and alongside a real pet summon. Excluding those against each other would be a far worse bug
-- than the duplicate summons this exists to stop, so do NOT be tempted to reuse that set here.
--
-- Death Knight lists only the two Raise Dead variants, which are alternatives to each other;
-- Army and Gargoyle are separate cooldowns and stay out.
SpellDB.PET_SUMMON_EXCLUSIVE = {
    -- Hunter: any Call Pet slot gets you a pet, so one is enough
    [883] = true, [83242] = true, [83243] = true, [83244] = true, [83245] = true,
    -- Warlock: five demons, one decision
    [688] = true, [697] = true, [712] = true, [691] = true, [30146] = true,
    -- Death Knight: permanent + temporary ghoul
    [46584] = true, [46585] = true,
    -- Mage: only one exists, listed for completeness
    [31687] = true,
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
