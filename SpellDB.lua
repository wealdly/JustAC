-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Database - Native spell classification tables for filtering and categorization
local SpellDB = LibStub:NewLibrary("JustAC-SpellDB", 22)
if not SpellDB then return end

local IsPlayerSpell = C_SpellBook.IsSpellKnown
local pcall = pcall
local geterrorhandler = geterrorhandler
local issecretvalue = issecretvalue
local GetTime = GetTime
local type = type
local ipairs = ipairs

local AURA_ERROR_THROTTLE = 30
local auraErrorReportedAt = {}
local function ReportAuraReadError(apiName, err)
    local now = GetTime()
    local last = auraErrorReportedAt[apiName]
    if last and now - last < AURA_ERROR_THROTTLE then return end
    auraErrorReportedAt[apiName] = now
    if not geterrorhandler then return end
    local ok, handler = pcall(geterrorhandler)
    if ok and type(handler) == "function" then
        pcall(handler, "JustAC SpellDB: " .. apiName .. " failed: " .. tostring(err))
    end
end

local function IsSecret(value)
    return (issecretvalue and issecretvalue(value)) or type(value) == "secret"
end

--- The WoW Forever client (game type camelot). A property of the CLIENT, fixed at load:
--- WOW_PROJECT_CAMELOT only exists on that client. Lives here because SpellDB loads first
--- (the Data files consult it); BlizzardAPI.IsForever is this same function.
local isForever
function SpellDB.IsForever()
    if isForever == nil then
        isForever = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT) and true or false
    end
    return isForever
end

--------------------------------------------------------------------------------
-- DEFENSIVE SPELLS: Major cooldowns, shields, damage reduction, immunities
-- These should NOT appear in DPS queue positions 2+
--------------------------------------------------------------------------------
-- Curated category data lives in Data/SpellCategories.lua (registered below).
local DEFENSIVE_SPELLS = {}
local HEALING_SPELLS = {}
local CROWD_CONTROL_SPELLS = {}
local NON_OFFENSIVE_SPELLS = {}   -- defensive, healing, crowd control and utility, for IsOffensiveSpell's one lookup
local NON_OFFENSIVE_KEYS = { "defensive", "healing", "cc", "utility" }
local FOREVER_REAR_ATTACKS = {}
local FOREVER_TARGET_SETUP = {}
local FOREVER_RANGED_FILLERS = {}
-- Curated interrupt/CC ability data lives in Data/InterruptAbilities.lua (registered below).
-- Flat [spellID] = {kind, mech, reach, radius, pri}; see that file for the field contract.
local INTERRUPT_ABILITIES = {}
local SOOTHE_ABILITIES    = {}  -- enrage-dispel abilities (Data/InterruptAbilities.lua); see ResolveSootheSpells
-- Curated range-reference abilities live in Data/RangeReferences.lua (registered below).
-- [spellID] = max range in yards. On-target harmful abilities (damage + CC) with stable,
-- known ranges, used as distance probes: IsSpellInRange (a non-secret boolean - only the
-- yardage is secret) on each KNOWN reference brackets the target's distance. See IsTargetWithin.
local RANGE_REFERENCES = {}
-- WoW Forever reference items for target distance: [yards] = { itemID, ... }. Registered
-- only on Forever (Data/RangeReferences.lua). Every item in a tier must agree.
local RANGE_ITEM_REFERENCES = {}

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
    for _, key in ipairs(NON_OFFENSIVE_KEYS) do
        if t[key] then for id in pairs(t[key]) do NON_OFFENSIVE_SPELLS[id] = true end end
    end
    if t.foreverRear then
        for id, requirement in pairs(t.foreverRear) do FOREVER_REAR_ATTACKS[id] = requirement end
    end
    if t.foreverTargetSetup then
        for id, policy in pairs(t.foreverTargetSetup) do FOREVER_TARGET_SETUP[id] = policy end
    end
    if t.foreverRanged then
        for id in pairs(t.foreverRanged) do FOREVER_RANGED_FILLERS[id] = true end
    end
end

--- Populate the interrupt/CC ability list from Data/InterruptAbilities.lua. Merges into
--- the existing local table so ResolveInterruptSpells/BuildInterruptTypeSpellIDs see it.
--- `false` REMOVES an entry: WoW Forever retracts a retail id that is a different spell
--- there (99 is Demoralizing Roar, not Incapacitating Roar).
function SpellDB.RegisterInterruptAbilities(t)
    if type(t) ~= "table" then return end
    for id, meta in pairs(t) do INTERRUPT_ABILITIES[id] = meta or nil end
end

--- Populate the enrage-dispel ("soothe") ability list from Data/InterruptAbilities.lua.
--- Kept separate from the interrupt/CC table: enrage-triggered (not cast-triggered), and
--- some entries are talent-gated dual-purpose spells (e.g. Paralysis is also a CC).
function SpellDB.RegisterSootheAbilities(t)
    if type(t) ~= "table" then return end
    -- `false` REMOVES an entry: a later data file (WoW Forever) can retract a retail id that
    -- is a different spell there (2908 is Soothe Animal, not an enrage dispel).
    for id, meta in pairs(t) do SOOTHE_ABILITIES[id] = meta or nil end
end

--- Populate the range-reference list from Data/RangeReferences.lua.
function SpellDB.RegisterRangeReferences(t)
    if type(t) ~= "table" then return end
    for id, yards in pairs(t) do RANGE_REFERENCES[id] = yards end
end

--- Populate the reference-item tiers ([yards] = { itemID, ... }) from Data/RangeReferences.lua.
function SpellDB.RegisterRangeItems(t)
    if type(t) ~= "table" then return end
    for yards, ids in pairs(t) do
        if type(yards) == "number" and type(ids) == "table" and #ids > 0 then
            RANGE_ITEM_REFERENCES[yards] = ids
        end
    end
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
-- scales with max health, clamped to its stated ceiling ("... up to 175,000"); a fixed
-- pot uses its largest heal number. The '%' symbol and
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
    local best = 0
    for n in desc:gsub("%d+%s*%%", ""):gmatch("%d[%d,]*") do
        local num = tonumber((n:gsub(",", "")))
        if num and num > best then best = num end
    end
    local pct = desc:match("(%d+)%s*%%")
    if pct then
        pct = tonumber(pct)
        local heal = (pct / 100) * (UnitHealthMax("player") or 0)
        -- ponytail: any non-percent number >= 1000 on the line is the ceiling; durations
        -- and cooldowns stay far below that. Parse "up to" if a pot ever breaks this.
        if best >= 1000 and best < heal then heal = best end
        return heal, true, pct
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
            if (C_Item.GetItemCount(id) or 0) > 0 then
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
        if (C_Item.GetItemCount(HEALING_ITEMS[i]) or 0) > 0 then owned = owned + 1 end
    end
    return { id = id, name = (C_Item.GetItemInfo(id)) or ("item " .. id),
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

local RotationImport_   -- lazy: RotationImport loads after SpellDB
local function StaticLookup(t, spellID)
    if not t or not spellID then return nil end
    local v = t[spellID]
    if v ~= nil then return v end
    if C_Spell_GetBaseSpell then
        local base = resolveBase(spellID)
        if base and base ~= spellID then
            v = t[base]
            if v ~= nil then return v end
        end
    end
    -- Forever ranks: every rank of a chain matches the rank-1 id the data is keyed by
    -- (a no-op on retail, which has no rank chains).
    RotationImport_ = RotationImport_ or LibStub("JustAC-RotationImport", true)
    local r1 = RotationImport_ and RotationImport_.RankBase(spellID)
    if r1 and r1 ~= spellID then return t[r1] end
    return nil
end
SpellDB.StaticLookup = StaticLookup   -- shared with RedundancyFilter's own tables

function SpellDB.GetForeverRearRequirement(spellID)
    if not SpellDB.IsForever() then return nil end
    return StaticLookup(FOREVER_REAR_ATTACKS, spellID)
end

function SpellDB.GetForeverTargetSetupPolicy(spellID)
    if not SpellDB.IsForever() then return nil end
    return StaticLookup(FOREVER_TARGET_SETUP, spellID)
end

function SpellDB.IsForeverRangedFiller(spellID)
    return SpellDB.IsForever() and StaticLookup(FOREVER_RANGED_FILLERS, spellID) == true
end

function SpellDB.GetForeverAbilityRole(spellID)
    return SpellDB.FOREVER_ABILITY_ROLES and StaticLookup(SpellDB.FOREVER_ABILITY_ROLES, spellID) or nil
end

function SpellDB.GetForeverTotemSlot(spellID)
    return SpellDB.FOREVER_TOTEM_SLOTS and StaticLookup(SpellDB.FOREVER_TOTEM_SLOTS, spellID) or nil
end

--- Does casting this carry the player to the target (spell effect CHARGE: Charge, Intercept,
--- Feral Charge)? Forever data, every rank; empty on retail.
function SpellDB.LandsAtTarget(spellID)
    return SpellDB.FOREVER_LANDS_AT_TARGET ~= nil
        and StaticLookup(SpellDB.FOREVER_LANDS_AT_TARGET, spellID) == true
end

--- What casting this gives the caster, from the spell data: power type (Enum.PowerType; combo
--- points 4) and amount in the game's units (Charge rank 1: rage, 9). nil when it gives nothing.
--- Forever data, every rank; empty on retail.
function SpellDB.GetEnergize(spellID)
    local gain = SpellDB.FOREVER_ENERGIZE and StaticLookup(SpellDB.FOREVER_ENERGIZE, spellID)
    if type(gain) ~= "table" then return nil end
    return gain[1], gain[2]
end

--- How long the aura this cast puts on yourself lasts, in seconds (its own, or one from the
--- spell it triggers: Bloodrage's rage aura). nil without one. Forever data, every rank.
function SpellDB.GetSelfAuraSeconds(spellID)
    local seconds = SpellDB.FOREVER_SELF_AURA_SECONDS and StaticLookup(SpellDB.FOREVER_SELF_AURA_SECONDS, spellID)
    if type(seconds) ~= "number" then return nil end
    return seconds
end

--- Does casting this keep paying the caster a resource after the cast (a periodic energize on
--- yourself: Bloodrage's rage over ten seconds)? Forever data, every rank; empty on retail.
function SpellDB.GainsOverTime(spellID)
    return SpellDB.FOREVER_GAINS_OVER_TIME ~= nil
        and StaticLookup(SpellDB.FOREVER_GAINS_OVER_TIME, spellID) == true
end

--- What casting this does to threat, from the spell data: "tank" (the effectively-tank aura:
--- Defensive Stance, Bear Form, Righteous Fury), "taunt" (on the target), "groupTaunt" (every
--- enemy around: Challenging Shout), "drop" (sheds threat: Fade, Feint,
--- Feign Death) or "boost" (bonus threat: Sunder Armor). nil otherwise. Forever data, every
--- rank; empty on retail.
--- Is this talent tree a tank's (generated, Forever)? Its list is a damage order all the same.
function SpellDB.IsTankTree(specKey, tree)
    local trees = SpellDB.FOREVER_TANK_TREES and specKey and SpellDB.FOREVER_TANK_TREES[specKey]
    return trees ~= nil and tree ~= nil and trees[tree] == true
end

--- Order inside a threat role, higher first (generated, Forever, every rank): an attack-me taunt
--- (2) before a forced-attack one (1); a threat ability by its bonus threat. nil when unranked.
function SpellDB.GetThreatOrder(spellID)
    return StaticLookup(SpellDB.FOREVER_THREAT_ORDER, spellID)
end

--- Is the player the tank? An assigned group role decides: Tank is, Damage or Healer is not,
--- whatever the stance or talents (a Protection-heavy leveler playing damage beside the group's
--- tank). With no role, or an unreadable one: a tank stance or form, else a tank talent tree,
--- which holds through a stance swap. Every read is plain or treated as not given.
function SpellDB.IsPlayerTank()
    local okRole, role = pcall(UnitGroupRolesAssigned, "player")
    if okRole and not IsSecret(role) then
        if role == "TANK" then return true end
        if role == "DAMAGER" or role == "HEALER" then return false end
    end
    local okAura, aura = pcall(UnitHasEffectivelyTankAura, "player")
    if okAura and not IsSecret(aura) and aura == true then return true end
    local RI = LibStub("JustAC-RotationImport", true)
    local tree = RI and RI.GetForeverTree and RI.GetForeverTree()
    return SpellDB.IsTankTree(SpellDB.GetSpecKey(), tree) == true
end

--- A strong tank signal: grouped, and the assigned role is Tank, or no role is assigned and a
--- tank aura is up (Defensive Stance, Bear Form, Righteous Fury). Solo, or a tank tree alone, is
--- not one: threat buys nothing alone, and a talent tree says nothing of who is tanking. Every
--- read is plain or it counts as no signal.
function SpellDB.HasStrongTankSignal()
    local api = LibStub("JustAC-BlizzardAPI", true)
    if not (api and api.IsGrouped and api.IsGrouped() == true) then return false end
    local okRole, role = pcall(UnitGroupRolesAssigned, "player")
    if okRole and not IsSecret(role) then
        if role == "TANK" then return true end
        if role == "DAMAGER" or role == "HEALER" then return false end
    end
    local okAura, aura = pcall(UnitHasEffectivelyTankAura, "player")
    return okAura and not IsSecret(aura) and aura == true
end

--- Does this talent tree's damage repay an armor reduction at once (generated, Forever)? Only
--- once one of the tree's main weapon spenders is learned (Slam for a levelling Arms warrior):
--- before that the reduction's rage and global cooldown buy nothing back. A spender the client
--- cannot answer for counts as not learned, so the armor reduction waits like other slow payoffs.
function SpellDB.IsEarlyArmorTree(specKey, tree)
    local trees = SpellDB.FOREVER_EARLY_ARMOR_TREES and specKey and SpellDB.FOREVER_EARLY_ARMOR_TREES[specKey]
    local spenders = trees and tree and trees[tree]
    if type(spenders) ~= "table" or not IsPlayerSpell then return false end
    for i = 1, #spenders do
        local ok, known = pcall(IsPlayerSpell, spenders[i])
        if ok and known == true then return true end
    end
    return false
end

function SpellDB.GetThreatRole(spellID)
    local role = SpellDB.FOREVER_THREAT_ROLES and StaticLookup(SpellDB.FOREVER_THREAT_ROLES, spellID)
    if type(role) ~= "string" then return nil end
    return role
end

--- Damage that lands only after a long delay (Forever data: Bane of Doom), so it pays off in
--- long fights only.
function SpellDB.IsDelayedPayoff(spellID)
    return SpellDB.FOREVER_DELAYED_PAYOFF ~= nil
        and StaticLookup(SpellDB.FOREVER_DELAYED_PAYOFF, spellID) == true
end

--- Area damage that comes only over time, with no hit of its own (Forever data: Consecration).
--- Like a damage over time spell on the target, it pays only while an enemy outlives it.
function SpellDB.IsAreaDot(spellID)
    return SpellDB.FOREVER_AREA_DOTS ~= nil
        and StaticLookup(SpellDB.FOREVER_AREA_DOTS, spellID) == true
end

function SpellDB.IsMaintainedProtection(spellID)
    return SpellDB.FOREVER_MAINTAINED_PROTECTION ~= nil
        and StaticLookup(SpellDB.FOREVER_MAINTAINED_PROTECTION, spellID) == true
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

-- Action-bar transforms (Data/SpellTransforms.lua): [form id] = { original button ids }.
-- A form is what a button temporarily becomes (Eviscerate -> Coup de Grace). The player never
-- learns a form's id and it is not in the spellbook.
local transformBases, transformForms = {}, nil
function SpellDB.RegisterTransforms(t)
    if type(t) == "table" then transformBases, transformForms = t, nil end
end

--- The button this FORM belongs to, for this character: the first original they know. nil
--- when the id is not a form, or is a form of something this character cannot cast.
function SpellDB.GetTransformBase(formID)
    local bases = formID and transformBases[formID]
    if not bases then return nil end
    -- LibStub directly: the file's GetBlizzardAPI helper is defined further down.
    local api = LibStub("JustAC-BlizzardAPI", true)
    for i = 1, #bases do
        if api and api.IsSpellAvailable and api.IsSpellAvailable(bases[i]) then return bases[i] end
    end
    return nil
end

--- Every form a button can take (array), or nil. Reverse index, built on first use.
function SpellDB.GetTransformForms(baseID)
    if not transformForms then
        transformForms = {}
        for form, bases in pairs(transformBases) do
            for i = 1, #bases do
                local list = transformForms[bases[i]]
                if not list then list = {}; transformForms[bases[i]] = list end
                list[#list + 1] = form
            end
        end
    end
    return baseID and transformForms[baseID]
end
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

-- Observation eligibility is independent of unconditional queue suppression.
local targetAuras
function SpellDB.RegisterTargetAuras(t) targetAuras = t end
function SpellDB.IsTrackedTargetAura(spellID)
    return targetAuras ~= nil and StaticLookup(targetAuras, spellID) ~= nil
end
-- How a tracked target aura's cast reaches the target (generated, Forever):
-- [spellID] = { defense type (1 magic, 2 melee, 3 ranged), missile speed in yards per second }.
local auraDelivery
function SpellDB.RegisterAuraDelivery(t) auraDelivery = t end
--- Defense type and missile speed of a tracked target aura's cast, or nil when unknown.
function SpellDB.GetAuraDelivery(spellID)
    local d = auraDelivery and StaticLookup(auraDelivery, spellID)
    if not d then return nil end
    return d[1], d[2]
end
-- Forever periodic refresh data (generated): stacking target auras and class heals over time.
-- A recast there restarts a DoT or HoT and loses the ticks left, so these refresh by lead
-- (BlizzardAPI.GetPeriodicRefreshLead), not by a share of their duration.
local stackingAuras, periodicHeals
function SpellDB.RegisterPeriodicRefresh(stacking, heals) stackingAuras, periodicHeals = stacking, heals end
function SpellDB.IsStackingAura(spellID)
    return stackingAuras ~= nil and StaticLookup(stackingAuras, spellID) ~= nil
end
--- Most stacks a stacking target aura holds (Sunder Armor: 5), or nil.
function SpellDB.GetStackingMax(spellID)
    local n = stackingAuras and StaticLookup(stackingAuras, spellID)
    if type(n) == "number" and n > 1 then return n end
    return nil
end
function SpellDB.IsPeriodicHeal(spellID)
    return periodicHeals ~= nil and StaticLookup(periodicHeals, spellID) ~= nil
end
-- Pure heals over time (generated, Forever): [spellID] = duration in seconds. Nothing lands at
-- once, so a recast while one ticks only restarts it (Renew, Rejuvenation).
local pureHots
function SpellDB.RegisterPureHots(t) pureHots = t end
--- Duration of a pure heal over time, or nil when the spell is not one.
function SpellDB.GetPureHotDuration(spellID)
    local duration = pureHots and StaticLookup(pureHots, spellID)
    if type(duration) == "number" and duration > 0 then return duration end
    return nil
end
-- Attacks that hit and slow movement (generated, Forever): Frostbolt, Frost Shock.
local slowingAttacks
function SpellDB.RegisterSlowingAttacks(t) slowingAttacks = t end
function SpellDB.IsSlowingAttack(spellID)
    return slowingAttacks ~= nil and StaticLookup(slowingAttacks, spellID) ~= nil
end
-- Creature-type limits from spell data (generated, Forever): [spellID] = bitmask of allowed
-- types (bit typeID-1). Exorcism hits only Demons and Undead.
local creatureTypeMasks
function SpellDB.RegisterCreatureTypes(t) creatureTypeMasks = t end
function SpellDB.GetCreatureTypeMask(spellID)
    return creatureTypeMasks and StaticLookup(creatureTypeMasks, spellID) or nil
end
function SpellDB.GetTargetAuraDuration(spellID)
    local duration = targetAuras and StaticLookup(targetAuras, spellID)
    if duration and duration > 0 then return duration end
    return SpellDB.GetTargetDotDuration(spellID)
end

-- Channeled player spells (curated from the SpellMisc channel bit). Channels
-- report cast time 0 like instants, so the move-cast marker excludes these -
-- movement breaks a channel. StaticLookup resolves talent-override / base IDs.
local channeledSpells
-- Merges, so a second data file (WoW Forever) adds to the curated set instead of replacing it.
function SpellDB.RegisterChanneledSpells(t)
    if type(t) ~= "table" then return end
    channeledSpells = channeledSpells or {}
    for id, v in pairs(t) do channeledSpells[id] = v end
end
function SpellDB.IsChanneled(spellID)
    return channeledSpells ~= nil and StaticLookup(channeledSpells, spellID) == true
end

do
    -- Move-cast marker classification. A spell is castable while moving when it is
    -- INSTANT right now: base instants always, hardcasts only while a proc has made
    -- them instant (Hot Streak, Lava Surge, ...). Channels are excluded (movement
    -- breaks them) even though they also report cast time 0.
    --
    -- The static class is cached per spell; the proc state is read live per render.
    -- castTime is static spell metadata (not a live/secret value), but the compare is
    -- guarded just in case, failing safe to "hardcast" (proc-gated, never a false yes).
    local issecretvalue = issecretvalue
    local C_SpellActivationOverlay_IsSpellOverlayed =
        C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
    local moveCastClassCache = {}
    -- Auto-repeat shots report cast time 0 but only fire while standing still. The API answers for
    -- known spells; the IDs back it up (Auto Shot, wand Shoot, Throw, bow/gun Shoot).
    local IsAutoRepeatSpell = C_Spell and C_Spell.IsAutoRepeatSpell
    local AUTO_REPEAT_IDS = { [75] = true, [5019] = true, [2764] = true, [3018] = true }
    local function MoveCastClass(spellID, spellInfo)
        if not spellID then return nil end
        local cached = moveCastClassCache[spellID]
        if cached ~= nil then return cached end
        if SpellDB.IsChanneled(spellID) then
            moveCastClassCache[spellID] = "channel"
            return "channel"
        end
        local autoOk, autoRepeat = false, false
        if IsAutoRepeatSpell then autoOk, autoRepeat = pcall(IsAutoRepeatSpell, spellID) end
        if issecretvalue and issecretvalue(autoRepeat) then autoOk = false end
        if AUTO_REPEAT_IDS[spellID] or (autoOk and autoRepeat == true) then
            moveCastClassCache[spellID] = "autorepeat"
            return "autorepeat"
        end
        local ct = spellInfo and spellInfo.castTime
        if ct == nil then return nil end               -- no info yet; retry next render
        if issecretvalue and issecretvalue(ct) then return "hardcast" end  -- unreadable; proc-gate it
        local class = (ct == 0) and "instant" or "hardcast"
        moveCastClassCache[spellID] = class
        return class
    end

    -- A hardcast is castable while moving only while a proc has made it instant. Reuse
    -- Blizzard's spell-activation overlay (the same "proc ready" cue that glows the
    -- icon) as the live signal. Fail-safe: any error / secret -> not proc'd (no mark),
    -- never a wrong "cast while moving" claim.
    local function IsSpellProcActive(spellID)
        if not (spellID and C_SpellActivationOverlay_IsSpellOverlayed) then return false end
        local ok, overlayed = pcall(C_SpellActivationOverlay_IsSpellOverlayed, spellID)
        if not ok then return false end
        if issecretvalue and issecretvalue(overlayed) then return false end
        return overlayed == true
    end

    --- Can the spell be cast while moving right now? true / false, nil before its info is available.
    function SpellDB.IsMoveCastableNow(spellID, spellInfo)
        local class = MoveCastClass(spellID, spellInfo)
        if class == nil then return nil end
        if class == "instant" then return true end
        if class == "hardcast" then return IsSpellProcActive(spellID) end
        -- "channel" / "autorepeat" / nil. Auto-repeat shots (Auto Shot, wands) start on the move but
        -- fire only standing still - no marker; their swing bar turns green when it is time to stop.
        return false
    end
end

-- Form / stealth / caster-aura CASTABILITY gating was removed: the never-secret
-- C_Spell.IsSpellUsable evaluates all of it live (form, talents incl. form-bypass
-- hero talents, stealth, and cast-condition auras), so SpellQueue and the
-- defensive engine gate on that directly. The generated FormRequirements/
-- AuraRequirements data files and their generators were deleted with it.
-- Kept accessors above (GetAuraMaxStacks, IsPureSelfAura) are REDUNDANCY data,
-- not usability, and have no live equivalent.

--- Health items the player currently owns, best-first: { {id=, name=}, ... }. Feeds the
--- Emergency Potion tile's dropdown. Out of combat only (item names); call lazily.
function SpellDB.GetOwnedHealingItems()
    local owned = {}
    for i = 1, #HEALING_ITEMS do
        local id = HEALING_ITEMS[i]
        if (C_Item.GetItemCount(id) or 0) > 0 then
            owned[#owned + 1] = { id = id, name = (C_Item.GetItemInfo(id)) or ("Item " .. id) }
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
local eatCache, eatCacheAt, eatCacheKnown = nil, -1, false
-- SpellDB loads BEFORE BlizzardAPI in the TOC, so the reference is resolved lazily at
-- call time (once) rather than as a file-scope upvalue, which would always be nil.
local cachedBlizzardAPI
local function GetBlizzardAPI()
    if not cachedBlizzardAPI then cachedBlizzardAPI = LibStub("JustAC-BlizzardAPI", true) end
    return cachedBlizzardAPI
end

function SpellDB.GetActiveEatingAura()
    if UnitAffectingCombat("player") then return nil, true end
    local api = GetBlizzardAPI()
    if not api then return nil, false end
    if api.AreAurasSecret and api.AreAurasSecret() then return nil, false end
    local now = GetTime()
    if now - eatCacheAt < 0.2 then return eatCache, eatCacheKnown end
    eatCacheAt = now
    eatCache = nil
    eatCacheKnown = false
    local getAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
    local auras
    if getAuras then
        local ok, result = pcall(getAuras, "player", "HELPFUL")
        if not ok then
            ReportAuraReadError("GetUnitAuras", result)
            return nil, false
        end
        auras = result
    else
        local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if not byIndex then return nil, false end
        auras = {}
        for i = 1, 40 do
            local ok, aura = pcall(byIndex, "player", i, "HELPFUL")
            if not ok then
                ReportAuraReadError("GetAuraDataByIndex", aura)
                return nil, false
            end
            if not aura then break end
            auras[#auras + 1] = aura
        end
    end
    if IsSecret(auras) or type(auras) ~= "table" then return nil, false end
    local ok, found, unknown = pcall(function()
        local unsure
        for i = 1, #auras do
            local aura = auras[i]
            if IsSecret(aura) then
                unsure = true
            else
                local spellId = aura and aura.spellId
                if spellId == nil or IsSecret(spellId) then
                    unsure = true
                elseif EATING_AURAS[spellId] then
                    return aura, false
                end
            end
        end
        return nil, unsure
    end)
    if not ok then
        ReportAuraReadError("HELPFUL aura fields", found)
        return nil, false
    end
    if found then
        eatCache, eatCacheKnown = found, true
    elseif not unknown then
        eatCacheKnown = true
    end
    return eatCache, eatCacheKnown
end

--- Well Fed lands after ~10s of eating, not at the end of the ~20s food aura. Past that
--- point the rest of the meal is only health/mana regen, so nothing should still be told
--- to wait on it - you are free to move on, and standing up keeps the buff.
--- True only inside that window; false once the buff has been granted (or is not being
--- eaten for). Callers: the mid-application wait/disarm and the queue grey-out.
local WELL_FED_SECONDS = 10
function SpellDB.IsEatingForBuff()
    local a, known = SpellDB.GetActiveEatingAura()
    if not known then return true end
    if not a then return false end
    local ok, dur, exp = pcall(function() return a.duration, a.expirationTime end)
    if not ok then
        ReportAuraReadError("HELPFUL aura timing", dur)
        return true
    end
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
-- preparation = true is pre-pull preparation, not long-duration upkeep:
-- active members satisfy it except for bounded OOC refreshes of readable timed buffs.
-- Combat remains missing-only, without an in-combat apply latch; forms never refresh.
-- combatCritical = true enables the contextual missing-preparation tint; routine
-- upkeep groups do not become urgent merely because a hostile is targeted.
-- Optional spec/tree scope selects a context; form groups never replace an active form.
-- defaultByTree selects a missing group's fallback, never overrides an active member.
-- Active family members can be received without learning their casts; cast knowledge
-- gates recommendations, not aura detection.
--------------------------------------------------------------------------------
SpellDB.CLASS_MAINTAINED_BUFFS = {
    DRUID = {
        -- Two aura identities: the base cast id plus the 432661 variant (both named
        -- "Mark of the Wild" in the 68974 export). Matching only 1126 read a member
        -- carrying the variant as unbuffed - a recast nag that never cleared.
        { group = { 1126 }, default = 1126, raidWide = true,
          auraIDs = { 1126, 432661 } },                                -- Mark of the Wild
        { group = { 24858 }, default = 24858, preparation = true, spec = 1, form = true, combatCritical = true },
        { group = { 768 }, default = 768, preparation = true, spec = 2, form = true, combatCritical = true },
        { group = { 5487 }, default = 5487, preparation = true, spec = 3, form = true, combatCritical = true },
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
        -- Same two-identity shape as Mark of the Wild: 432778 is a second
        -- "Arcane Intellect" aura id at 68974.
        { group = { 1459 }, default = 1459, raidWide = true,
          auraIDs = { 1459, 432778 } },                                -- Arcane Intellect
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
        { group = { 232698 }, default = 232698, preparation = true, spec = 3, form = true, combatCritical = true },
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
-- Derived from CLASS_MAINTAINED_BUFFS so they can never drift: the rogue poison set, and
-- every maintained-buff member across all classes, flat (PrecombatEngine's applied-latch
-- keys off it). auraIDs count as members too - a ranked buff (WoW Forever) is cast as any
-- rank. Rebuilt IN PLACE (readers hold the tables) whenever the source changes:
-- Data/Forever/Defaults.lua swaps in Forever's groups.
SpellDB.ROGUE_POISON_CAST_IDS = {}
SpellDB.MAINTAINED_BUFF_MEMBERS = {}
-- Values are the owning group, so sibling routing is an identity comparison.
SpellDB.PREPARATION_BUFF_MEMBERS = {}
function SpellDB.IndexMaintainedBuffs()
    wipe(SpellDB.ROGUE_POISON_CAST_IDS)
    wipe(SpellDB.MAINTAINED_BUFF_MEMBERS)
    wipe(SpellDB.PREPARATION_BUFF_MEMBERS)
    for _, grp in ipairs(SpellDB.CLASS_MAINTAINED_BUFFS.ROGUE or {}) do
        for _, id in ipairs(grp.group) do SpellDB.ROGUE_POISON_CAST_IDS[id] = true end
    end
    for _, classGroups in pairs(SpellDB.CLASS_MAINTAINED_BUFFS) do
        for _, grp in ipairs(classGroups) do
            for _, id in ipairs(grp.group) do
                SpellDB.MAINTAINED_BUFF_MEMBERS[id] = true
                if grp.preparation then SpellDB.PREPARATION_BUFF_MEMBERS[id] = grp end
            end
            -- Forever's aura ids are each rank's cast id, so a rank-3 cast must latch; on
            -- retail aura ids are separate auras, never cast, and stay out as before.
            if SpellDB.IsForever() then
                for _, id in ipairs(grp.auraIDs or {}) do
                    SpellDB.MAINTAINED_BUFF_MEMBERS[id] = true
                    if grp.preparation then SpellDB.PREPARATION_BUFF_MEMBERS[id] = grp end
                end
            end
        end
    end
end
SpellDB.IndexMaintainedBuffs()

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
    [382021] = true,  -- Earthliving Weapon
    [433568] = true,  -- Rite of Sanctification
    [433583] = true,  -- Rite of Adjuration
    -- Frostbrand (196834) removed: retired at 12.1 (no SpellName row, no acquisition
    -- route, no live replacement) - a detection entry that could never match.
}
SpellDB.WEAPON_IMBUE_SPELLS = { 33757, 318038, 382021, 433568, 433583 }

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

-- Bag ownership memo for the consumable scans: [itemID] = true/false. The buff and
-- recovery lists hold hundreds of items, and a scan asked GetItemCount for every one
-- of them up to twice a second out of combat. Counts only change when the bags do, so
-- the answer is kept until BAG_UPDATE_DELAYED (SpellDB.MarkConsumableBagsDirty) and,
-- as a backstop against a missed event, for at most OWNED_ITEM_MAX_AGE seconds.
-- Usability (level, zone) is still asked live, and only for items the player owns.
local OWNED_ITEM_MAX_AGE = 30
local ownedItemMemo = {}
local ownedItemMemoAt = -1

--- Mark the consumable ownership memo stale (call on BAG_UPDATE_DELAYED / zone-in).
function SpellDB.MarkConsumableBagsDirty()
    wipe(ownedItemMemo)
    ownedItemMemoAt = -1
end

local function OwnsItem(itemID)
    local now = GetTime()
    if now - ownedItemMemoAt > OWNED_ITEM_MAX_AGE then
        wipe(ownedItemMemo)
        ownedItemMemoAt = now
    end
    local owned = ownedItemMemo[itemID]
    if owned == nil then
        owned = (C_Item.GetItemCount(itemID) or 0) > 0
        ownedItemMemo[itemID] = owned
    end
    return owned
end

-- Does the player have this buff entry available to use right now? Source-aware:
-- bag item (GetItemCount), toy (PlayerHasToy), or known spell (IsPlayerSpell).
local function OwnsBuffEntry(e)
    local source = e.source or "item"
    if source == "toy" then
        return PlayerHasToy and PlayerHasToy(e.id)
    elseif source == "spell" then
        return IsPlayerSpell and IsPlayerSpell(e.id)
    end
    if source ~= "item" or not OwnsItem(e.id) or not C_Item.IsUsableItem then
        return false
    end
    return C_Item.IsUsableItem(e.id) == true
end

-- Caster specs (intellect primary) want weapon oils; physical specs want stones/whetstones.
-- The spec's primary stat is deterministic and non-secret; reading raw UnitStat instead
-- returns a SECRET number under taint (e.g. options opened from addon code), and comparing
-- secrets throws. C_SpecializationInfo.GetSpecializationInfo's 6th return is the primary stat (same enum as
-- UnitStat: 1=Str, 2=Agi, 4=Int).
local function PlayerPrefersOil()
    if not (C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo) then return false end
    local spec = C_SpecializationInfo.GetSpecialization()
    if not spec then return false end
    return select(6, C_SpecializationInfo.GetSpecializationInfo(spec)) == 4  -- 4 = Intellect -> caster -> oil
end

-- WoW Forever: the stats each class gets something from (Data/Forever/Consumables.lua tags
-- each buff with one). Druids use them all, so they are left out (no filter).
local FOREVER_CLASS_STATS = {}
for class, stats in pairs({
    WARRIOR = { "strength", "agility", "stamina", "attackpower", "armor" },
    ROGUE   = { "agility", "strength", "stamina", "attackpower", "armor" },
    HUNTER  = { "agility", "stamina", "intellect", "rangedattackpower", "attackpower", "armor" },
    PALADIN = { "strength", "stamina", "intellect", "attackpower", "spellpower", "healing", "armor" },
    SHAMAN  = { "strength", "agility", "stamina", "intellect", "attackpower", "spellpower", "healing", "armor" },
    PRIEST  = { "intellect", "spirit", "stamina", "spellpower", "healing", "armor" },
    MAGE    = { "intellect", "spirit", "stamina", "spellpower", "armor" },
    WARLOCK = { "intellect", "spirit", "stamina", "spellpower", "armor" },
}) do
    local set = {}
    for _, s in ipairs(stats) do set[s] = true end
    FOREVER_CLASS_STATS[class] = set
end

-- Out-of-combat recovery items (WoW Forever: food, drink, bandages): kind -> list, the most
-- restored per use first. Filled by Data/Forever/Consumables.lua; empty on retail.
local RECOVERY = {}
function SpellDB.RegisterRecoveryItems(t)
    if type(t) ~= "table" then return end
    for kind, list in pairs(t) do RECOVERY[kind] = list end
end

--- The best recovery item of `kind` ("food" / "drink" / "bandage") the player owns and can
--- use now (usability covers the level requirement), or nil. Plain food before Well Fed
--- food: that one is worth more as a pre-pull buff, so it is eaten for recovery only when
--- nothing else is in the bags.
function SpellDB.GetBestRecoveryItem(kind)
    local list = RECOVERY[kind]
    if not list then return nil end
    local fallback
    for i = 1, #list do
        local e = list[i]
        if OwnsItem(e.id) and C_Item.IsUsableItem(e.id) then
            if not e.wellfed then return e.id end
            fallback = fallback or e.id
        end
    end
    return fallback
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
        weaponExp = mh and select(15, C_Item.GetItemInfo(mh))
        local getInstant = C_Item.GetItemInfoInstant
        if mh and getInstant then
            local classID, subClassID = select(6, getInstant(mh))
            if classID == 2 and subClassID then weaponTypeBit = 2 ^ subClassID end
        end
    end
    local prefKind  -- weaponEnchant: soft-prefer the class-appropriate archetype
    if cat == "weaponEnchant" then
        prefKind = PlayerPrefersOil() and "caster" or "physical"
    end
    local classStats = cat ~= "weaponEnchant" and SpellDB.IsForever()
        and FOREVER_CLASS_STATS[select(2, UnitClass("player")) or ""] or nil
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
                local oilExp = select(15, C_Item.GetItemInfo(e.id))
                applies = oilExp ~= nil and oilExp >= weaponExp
            end
            if applies and e.wmask and weaponTypeBit then
                applies = bit.band(e.wmask, weaponTypeBit) ~= 0
            end
            -- WoW Forever, Auto: only a stat the class uses (a warrior is never handed an
            -- Elixir of Wisdom). Retail's Auto is newest-first, which on Forever's single era
            -- of items would pick by item level alone.
            if applies and classStats and e.stat and not (statPref and statPref ~= "optimal") then
                applies = classStats[e.stat] == true
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
local function IsSpellInBook(spellID)
    return C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player, false)
end

--- Is the current target within `yards`? Returns true / false / nil (unknown).
--- Uses curated on-target abilities, with readable range endpoints for the known rank,
--- plus the swing-range check and, on WoW Forever, reference items and the interaction
--- check (see the Forever notes below).
--- A positive read proves within its maximum. A negative read proves beyond its maximum
--- only when the minimum is zero, or when the target would already have attacked a
--- player standing inside the minimum (see AggroImpliesDistance). Unknown maxima exclude
--- a probe; unknown minima cannot prove beyond. Sources that contradict each other make
--- every radius unknown for that snapshot.
local knownRangeProbes = {}
local knownRangeProbesTime = -math.huge
local KNOWN_PROBE_REFRESH = 5
local rangeSnapshotTime
local withinBound, beyondBound, swingRange
local MELEE_YARDS = 5
local aggroRangeApplies, aggroRangeReason = false, "not evaluated"
-- UnitReaction: 1 hated, 2 hostile. Unfriendly (3) and neutral (4) NPCs do not attack on sight.
local AGGRESSIVE_REACTION_MAX = 2
-- An aggressive NPC does not attack the instant a player arrives: a target selected while
-- already in melee read as "beyond" until the pull (measured 2026-11-15, Forever 1.60.1).
-- The failed reading must hold, observed continuously on the same target out of combat,
-- before it means "too far". A gap between readings restarts the wait.
local AGGRO_SETTLE_SECONDS = 1.5
local AGGRO_OBSERVATION_GAP = 0.5
local aggroSince, aggroObservedAt
-- WoW Forever-only distance sources, measured 2026-11-16 on 1.60.1.70938
-- (Documentation/FOREVER_COMBAT_SIGNALS.md, external range-source review):
--   * Melee references report no live maximum (0) yet read plain, correct melee range
--     (Wing Clip matched the 5-yard items on 157 of 159 samples). A curated 5-yard
--     reference with a zero minimum and a zero or missing maximum is a melee probe there.
--     Next-swing attacks read "in range" at any distance and never qualify.
--   * Reference items answer plain true/false for a live hostile target in combat; every
--     main-hand swing on a live target came with the 5-yard tier true.
--   * CheckInteractDistance index 3 flipped exactly at Auto Shot's 8-yard minimum. Shorter
--     racial variants (6, 7) mean true proves within 8 and false proves beyond melee only.
--     With no target it returns false rather than nil, so a live target is required.
-- Item and interaction reads count only for a live, attackable target.
local C_Item_IsItemInRange = C_Item and C_Item.IsItemInRange
local C_Item_IsItemDataCachedByID = C_Item and C_Item.IsItemDataCachedByID
local C_Item_RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID
local CheckInteractDistance = CheckInteractDistance
local INTERACT_DUEL_INDEX = 3
local INTERACT_WITHIN_YARDS = 8
local INTERACT_BEYOND_YARDS = MELEE_YARDS
local itemLoadRequested = {}
local itemTierReady = {}       -- [yards] = true when every item in the tier has cached data
local itemTierRead = {}        -- [yards] = last snapshot verdict (diagnostic)
local interactRead             -- last snapshot interaction verdict (diagnostic)
local contradiction = false    -- sources disagreed in the last snapshot

-- quiet: a failed call is an expected "unknown" (restricted unit reads), not an error to report.
local function ReadRangeValue(api, fn, quiet, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then
        if not quiet then geterrorhandler()(value) end
        return nil
    end
    if api and api.IsSecretValue and api.IsSecretValue(value) then return nil end
    return value
end

-- Plain true/false of a quiet read, or nil when unreadable.
local function PlainBool(api, fn, ...)
    local value = ReadRangeValue(api, fn, true, ...)
    if value == nil then return nil end
    return value and true or false
end

function SpellDB.InvalidateRangeCache(spellsChanged)
    rangeSnapshotTime = nil
    aggroSince, aggroObservedAt = nil, nil
    if spellsChanged then knownRangeProbesTime = -math.huge end
end

-- Out of combat, an aggressive NPC target attacks a player who comes inside a minimum
-- range, so a failed minimum-range probe means "beyond its maximum" rather than "too
-- close". Every condition must be a plain positive read; anything unreadable, secret or
-- failed keeps the reading ambiguous. Known blind spots: an aggro radius smaller than
-- the minimum range on a non-trivial target, and crowd control applied out of combat
-- without stealth. The pre-combat range research question watches for both.
local function AggroImpliesDistance(api)
    if PlainBool(api, UnitAffectingCombat, "player") ~= false then return false, "player in combat or unknown" end
    if PlainBool(api, UnitIsDeadOrGhost, "player") ~= false then return false, "player dead or unknown" end
    if PlainBool(api, IsStealthed) ~= false then return false, "player stealthed or unknown" end
    if PlainBool(api, UnitIsFeignDeath, "player") ~= false then return false, "player feigning or unknown" end
    if PlainBool(api, UnitExists, "target") ~= true then return false, "no target" end
    if PlainBool(api, UnitIsDeadOrGhost, "target") ~= false then return false, "target dead or unknown" end
    if PlainBool(api, UnitIsPlayer, "target") ~= false then return false, "target is a player or unknown" end
    if PlainBool(api, UnitCanAttack, "target", "player") ~= true then return false, "target cannot attack or unknown" end
    local reaction = ReadRangeValue(api, UnitReaction, true, "target", "player")
    if type(reaction) ~= "number" then return false, "reaction unknown" end
    if reaction > AGGRESSIVE_REACTION_MAX then return false, "target not aggressive" end
    if PlainBool(api, UnitAffectingCombat, "target") ~= false then return false, "target in combat or unknown" end
    if PlainBool(api, UnitIsTapDenied, "target") ~= false then return false, "target tapped by others or unknown" end
    if PlainBool(api, UnitIsTrivial, "target") ~= false then return false, "target trivial or unknown" end
    return true, "aggressive target out of combat"
end

-- Tighten the snapshot's proven bounds: within the smallest proven reach, beyond the
-- largest proven miss.
local function Within(yards)
    if not withinBound or yards < withinBound then withinBound = yards end
end
local function Beyond(yards)
    if not beyondBound or yards > beyondBound then beyondBound = yards end
end

local function RefreshRangeSnapshot()
    local now = GetTime()
    if rangeSnapshotTime == now then return end
    local api = GetBlizzardAPI()
    local forever = SpellDB.IsForever and SpellDB.IsForever() or false
    local nextSwing = SpellDB.NEXT_SWING_SPELLS
    if (now - knownRangeProbesTime) >= KNOWN_PROBE_REFRESH then
        knownRangeProbesTime = now
        wipe(knownRangeProbes)
        RotationImport_ = RotationImport_ or LibStub("JustAC-RotationImport", true)
        for refID, ref in pairs(RANGE_REFERENCES) do
            local id = refID
            if RotationImport_ and RotationImport_.RankChain(refID) then
                id = RotationImport_.HighestKnownRank(refID)
            end
            -- Known, not castable: form, cooldown and resource gates do not change reach.
            if id and ReadRangeValue(api, IsSpellInBook, false, id) == true then
                local probe = { id = id, baseID = refID, ref = ref }
                local info = ReadRangeValue(api, api and api.GetCachedSpellInfo, false, id)
                if type(info) == "table" then
                    local minRange, maxRange = info.minRange, info.maxRange
                    if not (api and api.IsSecretValue and api.IsSecretValue(minRange))
                       and type(minRange) == "number" and minRange >= 0 then
                        probe.minRange = minRange
                    end
                    local maxSecret = api and api.IsSecretValue and api.IsSecretValue(maxRange)
                    if not maxSecret and type(maxRange) == "number" and maxRange > 0 then
                        probe.maxRange = maxRange
                    elseif forever and not maxSecret and (maxRange == nil or maxRange == 0)
                       and ref == MELEE_YARDS and probe.minRange == 0
                       and not (nextSwing and (nextSwing[id] or nextSwing[refID])) then
                        probe.maxRange = MELEE_YARDS
                        probe.meleeReference = true
                    end
                end
                knownRangeProbes[#knownRangeProbes + 1] = probe
            end
        end
        wipe(itemTierReady)
        if forever and C_Item_IsItemInRange then
            for yards, ids in pairs(RANGE_ITEM_REFERENCES) do
                local ready = true
                for i = 1, #ids do
                    local itemID = ids[i]
                    local cached = ReadRangeValue(api, C_Item_IsItemDataCachedByID, false, itemID)
                    if cached ~= true then
                        ready = false
                        if not itemLoadRequested[itemID] and C_Item_RequestLoadItemDataByID then
                            itemLoadRequested[itemID] = true
                            ReadRangeValue(api, C_Item_RequestLoadItemDataByID, false, itemID)
                        end
                    end
                end
                itemTierReady[yards] = ready or nil
            end
        end
    end

    withinBound, beyondBound = nil, nil
    aggroRangeApplies, aggroRangeReason = false, "no failed minimum-range probe"
    local aggroChecked, aggroCandidate = false, false
    for i = 1, #knownRangeProbes do
        local probe = knownRangeProbes[i]
        local r = ReadRangeValue(api, C_Spell_IsSpellInRange, false, probe.id, "target")
        probe.r = nil
        if type(r) == "boolean" then probe.r = r end
        local maxRange = probe.maxRange
        if maxRange and r == true and (not withinBound or maxRange < withinBound) then
            withinBound = maxRange
        elseif maxRange and r == false and probe.minRange == 0
           and (not beyondBound or maxRange > beyondBound) then
            beyondBound = maxRange
        elseif maxRange and r == false and probe.minRange and probe.minRange > 0 then
            if not aggroChecked then
                aggroChecked = true
                aggroCandidate, aggroRangeReason = AggroImpliesDistance(api)
                if aggroCandidate then
                    if not aggroObservedAt or now - aggroObservedAt > AGGRO_OBSERVATION_GAP then
                        aggroSince = now
                    end
                    aggroObservedAt = now
                    local held = now - aggroSince
                    aggroRangeApplies = held >= AGGRO_SETTLE_SECONDS
                    if not aggroRangeApplies then
                        aggroRangeReason = string.format("settling %.1fs of %.1fs", held, AGGRO_SETTLE_SECONDS)
                    end
                end
            end
            if aggroRangeApplies and (not beyondBound or maxRange > beyondBound) then
                beyondBound = maxRange
            end
        end
    end
    if not aggroCandidate then aggroSince, aggroObservedAt = nil, nil end
    swingRange = ReadRangeValue(api, api and api.IsTargetInSwingRange, false, 0)
    if swingRange == true then Within(MELEE_YARDS) elseif swingRange == false then Beyond(MELEE_YARDS) end

    wipe(itemTierRead)
    interactRead = nil
    if forever and (next(itemTierReady) or CheckInteractDistance)
       and PlainBool(api, UnitExists, "target") == true
       and PlainBool(api, UnitIsDeadOrGhost, "target") == false
       and PlainBool(api, UnitCanAttack, "player", "target") == true then
        for yards in pairs(itemTierReady) do
            local ids, verdict = RANGE_ITEM_REFERENCES[yards], nil
            for i = 1, #ids do
                local r = ReadRangeValue(api, C_Item_IsItemInRange, false, ids[i], "target")
                if type(r) ~= "boolean" or (verdict ~= nil and r ~= verdict) then
                    verdict = nil
                    break
                end
                verdict = r
            end
            itemTierRead[yards] = verdict
            if verdict == true then Within(yards) elseif verdict == false then Beyond(yards) end
        end
        local r = ReadRangeValue(api, CheckInteractDistance, false, "target", INTERACT_DUEL_INDEX)
        if type(r) == "boolean" then
            interactRead = r
            if r then Within(INTERACT_WITHIN_YARDS) else Beyond(INTERACT_BEYOND_YARDS) end
        end
    end

    -- Within N and beyond M with N <= M cannot both hold: the sources disagree, so no
    -- distance verdict is trusted until they agree again.
    contradiction = withinBound ~= nil and beyondBound ~= nil and withinBound <= beyondBound
    rangeSnapshotTime = now
end

--- Diagnostic: did the last range snapshot treat a failed minimum-range probe as
--- "beyond", and why or why not.
function SpellDB.GetAggroRangeState()
    RefreshRangeSnapshot()
    return aggroRangeApplies, aggroRangeReason
end

function SpellDB.IsTargetWithin(yards)
    RefreshRangeSnapshot()
    if contradiction then return nil end
    if withinBound and withinBound <= yards then return true end
    if beyondBound and beyondBound >= yards then return false end
    return nil
end

--- Could a "within N yards" verdict ever be PROVEN for this character? True when some
--- known probe reaches no further than N - only such a probe can answer "within". Callers
--- use it to tell "the target is too far" apart from "this character owns no probe short
--- enough to say", which are the same nil from IsTargetWithin but want opposite handling.
--- Short probes are melee attacks, so on retail casters cannot prove the ~8yd radii at all;
--- on WoW Forever the reference items and interaction check give every class short probes.
function SpellDB.CanProveWithin(yards)
    RefreshRangeSnapshot()
    if yards >= MELEE_YARDS and type(swingRange) == "boolean" then
        return true
    end
    -- Item tiers count only once every item's data is cached: before that they answer nil,
    -- and claiming a proof is possible would turn "not loaded yet" into "too far".
    for tierYards in pairs(itemTierReady) do
        if tierYards <= yards then return true end
    end
    if CheckInteractDistance and SpellDB.IsForever and SpellDB.IsForever()
       and INTERACT_WITHIN_YARDS <= yards then
        return true
    end
    if not C_Spell_IsSpellInRange then return false end
    for i = 1, #knownRangeProbes do
        local maxRange = knownRangeProbes[i].maxRange
        if maxRange and maxRange <= yards then return true end
    end
    return false
end

--- Diagnostic only (/jac inspect range): the Forever item and interaction sources and
--- whether the last snapshot found the sources in disagreement.
function SpellDB.DebugRangeSources()
    RefreshRangeSnapshot()
    local items = {}
    for yards, ids in pairs(RANGE_ITEM_REFERENCES) do
        items[#items + 1] = { yards = yards, ids = ids, ready = itemTierReady[yards] == true,
            r = itemTierRead[yards] }
    end
    table.sort(items, function(a, b) return a.yards < b.yards end)
    return { items = items, interact = interactRead, swing = swingRange,
        within = withinBound, beyond = beyondBound, contradiction = contradiction }
end

--- Diagnostic only (/jac inspect range): every KNOWN range reference with its
--- raw spell-path answer against the current target, so a wedged verdict can be
--- traced to the probes that produced it.
function SpellDB.DebugRangeProbes()
    RefreshRangeSnapshot()
    local out = {}
    for i = 1, #knownRangeProbes do
        local p = knownRangeProbes[i]
        out[i] = { id = p.id, baseID = p.baseID, ref = p.ref,
            minRange = p.minRange, maxRange = p.maxRange, r = p.r,
            meleeReference = p.meleeReference }
    end
    return out
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

--- The curated interrupt/CC entry (kind, mech, reach, ...) for a spell, override-resolved.
function SpellDB.GetInterruptAbility(spellID)
    return StaticLookup(INTERRUPT_ABILITIES, spellID)
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
    
    -- In any non-offensive table (defensive, healing, crowd control, utility): not offensive.
    -- Base-resolve so a talent-override variant is excluded like its base.
    return not StaticLookup(NON_OFFENSIVE_SPELLS, spellID)
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
--           "execute"                    → HP-gated finisher. Execute phase is now DETECTED
--                                          directly (target-health threshold gate, SpellQueue
--                                          _StageContext); this gate is the FALLBACK, covering
--                                          the 20-35% window where only Massacre-class
--                                          thresholds are live and DB2 gives us no per-spell
--                                          percentage. Either source boosts execute-gated
--                                          spells in positions 2+.
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

--- Build the spec key ("CLASS_N"; "CLASS_F" on WoW Forever) for the current player.
--- Returns specKey, playerClass or nil, nil if unavailable.
--- Forever has one spec per class, and its index must not alias retail's per-spec data
--- (WARRIOR_1 is retail Arms), so it gets its own "_F" key: Forever entries live under
--- it in every per-spec table, and retail never builds one. The Forever talent tree is
--- chosen inside RotationImport, not here.
--- Memoized on the spec index: class never changes in-session, and the concat
--- allocated a fresh string per call - this runs per spell per queue build via
--- RotationImport.GetEntry and per defensive list fetch.
local specKeyCache, specKeyClass, specKeySpec
function SpellDB.GetSpecKey()
    if SpellDB.IsForever() then
        if specKeyClass then return specKeyCache, specKeyClass end
        local _, playerClass = UnitClass("player")
        if not playerClass then return nil, nil end
        specKeyClass, specKeyCache = playerClass, playerClass .. "_F"
        return specKeyCache, playerClass
    end
    local spec = C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
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
    -- WoW Forever's one spec per class (ChrSpecialization 1482-1491): the ranged classes.
    [1482] = true, [1485] = true, [1487] = true, [1490] = true,  -- Mage, Hunter, Priest, Warlock
}
local rangedSpecCacheIdx, rangedSpecCacheVal
--- True if the current spec is a ranged DPS or a healer (move-cast dot auto-on).
--- Cached by spec index; recomputed only when the player changes spec.
function SpellDB.IsRangedOrHealerSpec()
    local spec = C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
    if not spec then return false end
    if rangedSpecCacheIdx ~= spec then
        rangedSpecCacheIdx = spec
        local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(spec)
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
--   "CLASS_N"      = spec-specific override (N = C_SpecializationInfo.GetSpecialization() index)
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
-- Verified against the 12.1.0 DB2 exports: exactly three SPELLS in this whole table are
-- non-instant (SpellMisc CastingTimeIndex -> SpellCastTimes.Base > 0) - Regrowth, Healing
-- Surge and Vivify - and each is last in every list carrying it. Re-run that check before
-- adding a heal; Feral had Regrowth one slot too high until the 12.1 audit caught it.
--
-- The same audit checks something the eye cannot: that every id is actually OBTAINABLE.
-- A spell can have a live SpellName row and still be unreachable - no SkillLineAbility,
-- no TraitDefinition, no SpecializationSpells - in which case the runtime known-spell gate
-- hides it forever and it costs a permanent dead slot. Several ids failed that in 12.1
-- (see the Monk, Blood, Protection Paladin and Warlock notes below). "It exists in DB2" is
-- not the test; "something grants it" is.
SpellDB.CLASS_DEFENSIVE_DEFAULTS = {
    -- ── Death Knight ────────────────────────────────────────────────────────
    -- Class fallback (Frost/Unholy DPS): quick heal then big CDs
    -- Anti-Magic Zone moved to CLASS_GROUP_HELP_DEFAULTS: it protects the party, and as a
    -- personal-list filler it showed at full health.
    DEATHKNIGHT   = {49998, 48743, 48792, 48707, 49039, 327574}, -- Death Strike, Death Pact, Icebound Fortitude, Anti-Magic Shell, Lichborne, Sacrificial Pact
    -- Blood (tank): active mitigation first, Death Strike for heal, then big CDs.
    -- Rune Tap (194679) and Tombstone (219809) REMOVED: an earlier note called Rune Tap
    -- "still live in 12.1 DB2", which was true of the wrong thing - the SpellName row
    -- exists, but neither id has a SkillLineAbility, a TraitDefinition or a
    -- SpecializationSpells row, so neither is obtainable. Same shape as the Guard removal
    -- in the Monk block. Sibling Blood talents (Vampiric Blood, Icebound Fortitude) all
    -- resolve, so this is not an export gap. Do not restore without an acquisition row.
    DEATHKNIGHT_1 = {49998, 55233, 48743, 48792, 48707, 49039}, -- Death Strike, Vampiric Blood, Death Pact, IBF, AMS, Lichborne

    -- ── Demon Hunter ────────────────────────────────────────────────────────
    -- Class fallback (Havoc DPS): Blur, Netherwalk (talent). Darkness is in the group list.
    DEMONHUNTER   = {198589, 196555},                           -- Blur, Netherwalk
    -- Vengeance (tank): Soul Cleave heal, Demon Spikes, Fiery Brand, Metamorphosis (a
    -- Vengeance SURVIVAL cd, not a DPS burst - unlike Havoc's), then Blur
    -- Soul Barrier REMOVED: nine ids carry the name and not one is castable - the only one
    -- with a talent row (1265924) is a PASSIVE node with no castable button behind it, and
    -- the rest have no acquisition route at all. It could never render.
    DEMONHUNTER_2 = {228477, 203720, 204021, 187827, 198589}, -- Soul Cleave, Demon Spikes, Fiery Brand, Metamorphosis, Blur

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
    -- Renewal ahead of Regrowth: both are heals, but Renewal is instant and Regrowth is a
    -- 1.5s hardcast, and the rule at the top of this table is that cast-time heals go below
    -- instants without exception. This list had them the other way round.
    DRUID_2       = {22842, 1261867, 61336, 22812, 108238, 8936},       -- Frenzied Regen, Heart of the Wild, Survival Instincts, Barkskin, Renewal, Regrowth
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
    -- Renewing Blaze (374348) REMOVED: PASSIVE in 12.1 (attrs 0x10040) - never castable.
    -- Zephyr is in the group list (Devastation / Augmentation) and the emergency ladder
    -- (Preservation).
    EVOKER        = {360995, 363916, 370960},                   -- Verdant Embrace, Obsidian Scales, Emerald Communion

    -- ── Hunter ──────────────────────────────────────────────────────────────
    -- Class fallback (all specs)
    -- 281195 dropped: it was carried as the "Lone Wolf" variant of Survival of the Fittest,
    -- but it has no acquisition row in 12.1 and 264735 (already here) is the live one. Note
    -- 203965 also reads "Survival of the Fittest" and is a DRUID ability - do not use it.
    -- Fortitude of the Bear (388035) REMOVED: PASSIVE in 12.1 - never castable.
    HUNTER        = {109304, 264735, 186265},          -- Exhilaration, Survival of the Fittest, Aspect of the Turtle

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
    -- FORTIFYING BREW is 115203 - the CASTABLE button. 388917 is the PASSIVE talent node
    -- that grants it (TraitDefinition.VisibleSpellID 388917 -> 115203), so the node owns the
    -- acquisition row and the button owns none. That is exactly why "has an acquisition row"
    -- is the wrong test on its own: a passive id here is dropped by IsSpellAvailable and the
    -- slot stays empty forever, which is the same dead slot as an unobtainable id.
    -- The per-spec variants ARE dead (120954 Brewmaster, 243435 Mistweaver, 201318
    -- Windwalker): no route, and no node makes them visible. Removed.
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
    MONK_1        = {119582, 322507, 322101, 115203, 122278, 122783, 115176}, -- Purifying Brew, Celestial Brew, Expel Harm, Fortifying Brew, Dampen Harm, Diffuse Magic, Zen Meditation
    -- Mistweaver: Life Cocoon leads - a big instant absorb it can cast on ITSELF, and the
    -- spec's single strongest defensive - then the DR CDs. Vivify is last: it is a hardcast,
    -- and the case where it is the right button - instant off its own proc - is promoted
    -- automatically without needing a high slot here.
    MONK_2        = {116849, 115203, 122278, 122783, 388615, 116670}, -- Life Cocoon, Fortifying Brew, Dampen Harm, Diffuse Magic, Restoral, Vivify
    -- Windwalker: Expel Harm, Touch of Karma, Fortifying Brew, Diffuse Magic
    MONK_3        = {322101, 122470, 115203, 122278, 122783}, -- Expel Harm, Touch of Karma, Fortifying Brew, Dampen Harm, Diffuse Magic

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
    -- Eye of Tyr is 209202, not 387174 (the latter has no acquisition row in 12.1).
    -- Bastion of Light (378974) removed - its only id has no acquisition row either.
    PALADIN_2     = {85673, 31850, 86659, 209202, 389539, 204018, 642, 633}, -- Word of Glory, Ardent Defender, Guardian of Ancient Kings, Eye of Tyr, Sentinel, Blessing of Spellwarding, Divine Shield, Lay on Hands

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
    -- Ancestral Guidance is in the group list: it heals the party off your damage.
    SHAMAN        = {108271, 974, 198103, 8004},               -- Astral Shift, Earth Shield, Earth Elemental, Healing Surge
    -- Restoration: Earth Shield is baseline and belongs on the player between casts, and the
    -- spec owns two panic totems the other specs have no access to. Earth Elemental is
    -- dropped - a healer under pressure is not stopping to summon one.
    SHAMAN_3      = {108271, 974, 98008, 207399, 108281, 8004}, -- Astral Shift, Earth Shield, Spirit Link Totem, Ancestral Protection Totem, Ancestral Guidance, Healing Surge

    -- ── Warlock ─────────────────────────────────────────────────────────────
    -- Class fallback (all specs share dark pact / drain / UR)
    -- Nether Ward (212295) removed: sole id, no acquisition row in 12.1.
    WARLOCK       = {108416, 234153, 104773},                  -- Dark Pact, Drain Life, Unending Resolve

    -- ── Warrior ─────────────────────────────────────────────────────────────
    -- Class fallback (Arms/Fury DPS). Die by the Sword is Arms-only and Enraged
    -- Regeneration Fury-only - the runtime known-spell gate shows each spec its own wall.
    -- Bitter Immunity is a class talent all three specs can take (instant self-heal plus a
    -- dispel), so it sits with the other quick heals.
    -- Rallying Cry is in the group list (all three specs).
    WARRIOR       = {34428, 202168, 383762, 190456, 118038, 184364, 23920, 386208},  -- Victory Rush, Impending Victory, Bitter Immunity, Ignore Pain, Die by the Sword, Enraged Regeneration, Spell Reflection, Defensive Stance
    -- Protection (tank): Shield Block first (physical active mitigation, used on CD -
    -- the sink hint below parks it while its buff is already rolling), then Ignore Pain,
    -- Impending Victory, Last Stand + Shield Wall (major CDs), Rallying Cry, Spell Reflection.
    -- (Last Stand 12975 is an active 3-min CD in 12.1 DB2 - the older "passive" note was wrong.)
    WARRIOR_3     = {2565, 190456, 202168, 383762, 12975, 871, 23920}, -- Shield Block, Ignore Pain, Impending Victory, Bitter Immunity, Last Stand, Shield Wall, Spell Reflection
}

-- Emergency tier for the graded defensive reorder. Tier 1 = immunity bubble (survives any
-- hit), tier 2 = big instant heal, tier 4 = pre-emptive wall (see the block below).
-- Untagged = tier 3 (rotational mitigation / small filler / cast-time or over-time heal),
-- left in the normal filler-first order.
-- Drives the ordering inside each health BAND (DefensiveEngine.HEALTH_BANDS = 25/50/80):
-- walls lead while you are taking chip damage, big heals once you have taken a real hit,
-- bubbles only when you are close to dying. Above every band, list order (filler-first)
-- and proc-priority already do the right thing.
--
-- Tier 2 heals must land INSTANTLY. Cast-time heals (Healing Surge), HoTs / over-time
-- heals (Regrowth, Frenzied Regeneration, Crimson Vial), and channels do NOT qualify -
-- a heal that trickles in can't save you before the next hit lands, so floating
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
    [48743]  = 2,  -- Death Pact (Death Knight). Effect 136 BasePoints 50 - a 50% instant,
                   -- double Desperate Prayer above. The aura-118 damage-taken downside is
                   -- the cost of the heal, not a reason to treat it as filler.
    [327574] = 2,  -- Sacrificial Pact (Death Knight, 25% instant - Desperate Prayer's exact
                   -- shape). Pet-gated, but usability already sinks it when there is no pet.
    -- Tier 4 - PRE-EMPTIVE walls: major damage reduction, plus cheat-deaths that have to be up
    -- before the hit resolves. Split out of tier 2 because the two behave oppositely when you
    -- are HEALTHY: a heal at 90% is wasted, so parking it costs nothing, but a wall at 90% is
    -- correct play - you press Shield Wall on the telegraphed slam BEFORE it lands, not after
    -- you are at 30%. Parking these coached reactive-only cooldown use, backwards, and it hit
    -- tanks hardest since they own most of this list.
    -- The NUMBER is a label, not a rank: TIER_ORDER_BY_BAND in DefensiveEngine permutes them
    -- per health band, so 4 is not "less urgent than 3". Tier 3 remains the untagged default.
    -- A NEW tier value must appear in every band's order array; the ordering pass appends
    -- anything unnamed at the end rather than dropping it, but relying on that gives you an
    -- arbitrary position rather than a chosen one.
    -- Life Cocoon is deliberately NOT here despite being an absorb: JustAC only ever renders it
    -- self-cast, and self-cast it is the spec's panic button, not a pre-applied shield.
    -- NOT tiered at all, on purpose: semi-rotational short DR (Blur, Barkskin, Ignore Pain, Ironbark),
    -- school-limited walls (AMS, Anti-Magic Zone, Spell Reflection, Diffuse Magic, Cloak of
    -- Shadows - a magic-only immunity pressed before the spell lands, like AMS - and both
    -- Blessings - Protection stops physical only, Spellwarding magic only, so neither
    -- "survives any hit" the way a tier 1 bubble does), group utility that is not a personal
    -- answer (Zephyr, Spirit Link Totem), maintenance buffs (Earth Shield), and situational
    -- avoidance (Feint, Evasion) - parking or floating those would miscoach.
    [871] = 4,  -- Shield Wall (Warrior)
    [61336] = 4,  -- Survival Instincts (Druid)
    [31850] = 4,  -- Ardent Defender (Paladin)
    [86659] = 4,  -- Guardian of Ancient Kings (Paladin)
    [115203] = 4,  -- Fortifying Brew (Monk). The CASTABLE id, not the 388917 passive node
                   -- that grants it - tagging the node tiers a spell that never renders.
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
    [403876] = 4,  -- Divine Protection (Paladin, Ret/base id). Aura 118 damage-taken
                   -- modifier - the same wall shape as Astral Shift above, and the one
                   -- major DR the Paladin lists had left sitting at filler tier.
    [498]    = 4,  -- Divine Protection (Holy Paladin's separate id for the same button)
}

-- Per-spec overrides layered over DEFENSE_TIER ("CLASS_N" → { [spellID] = tier }).
-- Protection Paladin: Divine Shield drops all threat mid-pull, so as a tank it must
-- never float to the top at low health - demoted to filler tier (still listed).
local DEFENSE_TIER_SPEC = {
    PALADIN_2 = { [642] = 3 },  -- Divine Shield
}

-- Auto's own "wait until below" for defensives that are not panic buttons but have no
-- business lit at full health. Only read while "Hold Emergency Heals Until Low Health" is
-- on, and a player's own setting always wins. Goes through the same fail-safe as a level
-- the player picks (DefensiveEngine.PlayerBelow): an unreadable health shows it as usual.
--   90 - heals over time: rolling one early is how they are meant to be used, so only a
--        top-of-the-bar health holds them.
--   80 - cheap instant heals: once you have taken some damage.
--   60 / 50 - cast-time and channelled heals; their instant procs are promoted anyway.
--   25 - the bubble band, for panic buttons that are not tier 1: a ten-minute full heal,
--        and the immunities that lock out Divine Shield and Lay on Hands (Forbearance).
-- Direct healing effects (10/136) with a base cast time in the client exports:
-- Retail 12.1.5.70783 and Forever 1.60.1.70888. The broader healing category also
-- contains buffs and utility, so it cannot establish this classification alone.
local CAST_TIME_HEALS = {
    [331] = true,     -- Healing Wave (Forever)
    [596] = true,     -- Prayer of Healing
    [635] = true,     -- Holy Light (Forever)
    [1064] = true,    -- Chain Heal
    [2060] = true,    -- Heal
    [2061] = true,    -- Flash Heal
    [5185] = true,    -- Healing Touch (Forever)
    [8004] = true,    -- Healing Surge / Lesser Healing Wave
    [8936] = true,    -- Regrowth
    [19750] = true,   -- Flash of Light
    [32546] = true,   -- Binding Heal
    [50464] = true,   -- Nourish
    [77472] = true,   -- Healing Wave (Retail)
    [82326] = true,   -- Holy Light (Retail)
    [116670] = true,  -- Vivify
    [124682] = true,  -- Enveloping Mist
    [186263] = true,  -- Shadow Mend
    [194509] = true,  -- Power Word: Radiance
    [265202] = true,  -- Holy Word: Salvation
    [399491] = true,  -- Sheilun's Gift
}
local CAST_TIME_HEAL_WAIT_BELOW = 60

local DEFAULT_WAIT_BELOW = {
    [85673]  = 80,  -- Word of Glory
    [49998]  = 80,  -- Death Strike (not Blood's, see below)
    [202168] = 80,  -- Impending Victory
    [360995] = 80,  -- Verdant Embrace
    [322101] = 80,  -- Expel Harm
    [185311] = 90,  -- Crimson Vial (heal over time)
    [774]    = 90,  -- Rejuvenation (heal over time)
    [22842]  = 90,  -- Frenzied Regeneration (heal over time)
    [234153] = 60,  -- Drain Life
    [370960] = 50,  -- Emerald Communion (three-minute channel)
    [633]    = 25,  -- Lay on Hands
    [1022]   = 25,  -- Blessing of Protection
    [204018] = 25,  -- Blessing of Spellwarding
}
-- Per spec, over the table above. false = no level of its own.
local DEFAULT_WAIT_SPEC = {
    DEATHKNIGHT_1 = { [49998] = false },  -- Blood: Death Strike IS the rotation
    PALADIN_2     = { [642] = 25 },       -- Divine Shield: kept out of the bubble tier so it
                                          -- never floats (threat), but still waits like one
}

--- Auto's own wait level for a spell, or nil when the kind rule applies.
function SpellDB.GetDefaultWaitBelow(spellID)
    if not spellID or spellID < 0 then return nil end
    local specKey = SpellDB.GetSpecKey()
    local spec = specKey and DEFAULT_WAIT_SPEC[specKey]
    local v = spec and StaticLookup(spec, spellID)
    if v == nil then v = StaticLookup(DEFAULT_WAIT_BELOW, spellID) end
    if v == nil and StaticLookup(CAST_TIME_HEALS, spellID) then
        return CAST_TIME_HEAL_WAIT_BELOW
    end
    return v or nil
end

--- Emergency tier for the low-health defensive reorder: 1 = immunity bubble, 2 = big instant
--- heal, 4 = pre-emptive wall (major DR / cheat-death), 3 = everything else (the default for
--- anything untagged). The numbers are LABELS, not ranks - DefensiveEngine's TIER_ORDER_BY_BAND
--- permutes them per health band - which is why 4 sits above 3 in urgency.
--- Only tiers 1 and 2 are held back when healthy; 4 stays live because a wall pressed after
--- you are already low is a wall pressed too late.
--- Looks up the base list ID (talent overrides resolve to the same tool); spec overrides win.
--- Negative IDs are heal items (potion/healthstone): instant burst heals, tier 2 - they
--- must float when low just like they park as emergencies when healthy (IsHoldWorthy).
--- Add tiers from a later data file (WoW Forever's ids). Merges into DEFENSE_TIER.
function SpellDB.RegisterDefenseTiers(t)
    if type(t) ~= "table" then return end
    for id, tier in pairs(t) do DEFENSE_TIER[id] = tier end
end

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

-- Self-lockouts: a successful cast ON THE PLAYER puts an aura on them that blocks casting
-- the listed spells on themselves, while the game still reports them usable. Keyed by spec
-- key, so an entry applies only where it was checked. `aura` is the lockout aura and keys the
-- hold, so every entry sharing it is held together; `dur` is its duration. The aura cannot be
-- read in combat, so the hold is timed from our own confirmed cast.
--   selfOnly  - the spell can only land on the caster, so no target identity check is made.
--   applyOnly - the cast starts the hold but the spell itself is not blocked by the aura.
-- PRIEST_F: Weakened Soul (6788) after Power Word: Shield. Measured 2026-11-16 on Forever:
-- the recast returns "immune" while C_Spell.IsSpellUsable reads true, Weakened Soul lasted
-- 15s (SpellDuration agrees), and it reads nil in combat even while present. Talents that
-- shorten or clear it only make the hold run long, which costs a late shield, never a wasted
-- press. See Documentation/FOREVER_COMBAT_SIGNALS.md (ability lockouts).
-- PALADIN_F: Forbearance (25771, 60s). Build 1.60.1.70938 data: SpellAuraRestrictions
-- excludes it on the caster for Divine Shield and Divine Protection and on the target for
-- Blessing of Protection; Avenging Wrath 407788 triggers it (SpellEffect) and is not blocked.
-- Divine Shield / Divine Protection / Blessing of Protection applying it is not in the data
-- (hardcoded, like Weakened Soul) and not yet captured; a wrong hold only moves a spell
-- behind ready defensives for 60s. Divine Shield and Divine Protection already share a
-- cooldown, so the gap this closes is Blessing of Protection on yourself against the other two.
local FORBEARANCE, FORBEARANCE_DUR = 25771, 60.0
SpellDB.SELF_LOCKOUTS = {
    PRIEST_F = {
        [17] = { aura = 6788, dur = 15.0 },  -- Power Word: Shield -> Weakened Soul
    },
    PALADIN_F = {
        [642] = { aura = FORBEARANCE, dur = FORBEARANCE_DUR, selfOnly = true },   -- Divine Shield
        [498] = { aura = FORBEARANCE, dur = FORBEARANCE_DUR, selfOnly = true },   -- Divine Protection
        [1022] = { aura = FORBEARANCE, dur = FORBEARANCE_DUR },                   -- Blessing of Protection
        [407788] = { aura = FORBEARANCE, dur = FORBEARANCE_DUR, selfOnly = true,  -- Avenging Wrath
                     applyOnly = true },
    },
}

--- How long a debuff that weakens the enemy runs after your cast (Demoralizing Shout, Hex of
--- Weakness; generated, Forever, every rank), in seconds, or nil.
function SpellDB.GetEnemyMitigationDuration(spellID)
    local t = SpellDB.FOREVER_ENEMY_MITIGATION
    if not (t and spellID) then return nil end
    return StaticLookup(t, spellID)
end

--- A spell that lands on everything around you (Demoralizing Shout, Challenging Shout): its
--- radius in yards (generated, Forever, every rank); nil for a single-target spell.
function SpellDB.GetAreaRadius(spellID)
    return StaticLookup(SpellDB.FOREVER_AREA_RADIUS, spellID)
end

--- The current spec's self-lockout entry for a spell (any rank), or nil.
function SpellDB.GetSelfLockout(spellID)
    local specKey = SpellDB.GetSpecKey()
    local list = specKey and SpellDB.SELF_LOCKOUTS[specKey]
    if not list or not spellID then return nil end
    return StaticLookup(list, spellID)
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

-- Pet rez/summon spells (precombat checklist for pet classes; in combat for Beast Mastery
-- Hunter and Demonology Warlock, which rely on the pet for their rotation).
SpellDB.CLASS_PET_REZ_DEFAULTS = {
    -- Heart of the Phoenix (55709) removed: no acquisition route at 12.1.
    HUNTER = {982, 883},                             -- Revive Pet, Call Pet 1
    -- Succubus is Summon Sayaad (366222) at 12.1; 712 and its 18 same-name siblings have
    -- no acquisition route.
    WARLOCK = {688, 697, 366222, 691, 30146},        -- Summon Imp/Voidwalker/Sayaad/Felhunter/Felguard
    WARLOCK_2 = {30146, 688, 697, 366222, 691},      -- Demonology: Felguard first (its mandatory pet), others as fallback
    DEATHKNIGHT_3 = {46584, 46585},                  -- Raise Dead (Unholy only - permanent ghoul 46584; 46585 covers the temporary variant. Blood/Frost ghoul is a Guardian, not a pet)
}

-- Pet heal spells (shown when PET health is low - OUT OF COMBAT ONLY)
-- In 12.0 combat, UnitHealth("pet") is secret so pet heals cannot trigger.
SpellDB.CLASS_PETHEAL_DEFAULTS = {
    HUNTER = {136, 109304},                          -- Mend Pet, Exhilaration (heals pet too)
    -- WARLOCK has no entry at 12.1: Health Funnel (755) and all ten same-name ids have no
    -- acquisition route, and no other Warlock pet heal is reachable. The cue was already
    -- dead in play - the known-spell gate hid it - so removing it only makes the data
    -- honest. Restore a WARLOCK list the moment a castable pet heal exists again.
}

--------------------------------------------------------------------------------
-- Healer group-heal data (spec-keyed; healer specs only, so a non-healer spec
-- resolves to nil and the heal surface never appears).
--
-- Every ID below is checked against the CURRENT client data export by
-- tools/audit_defensives.py - name, acquisition route and passive flag - rather
-- than recalled. Re-run it after every data refresh: this block was last hand-
-- verified at 12.0.7.68974 and had silently drifted by 12.1.0.
-- Ordering follows the defensive-list convention: cheap/rotational first,
-- cast-time heals later.
--------------------------------------------------------------------------------

-- Group-heal suggestions injected into the defensive queue while allies are
-- low, in priority order. MULTI-TARGET HEALS ONLY: single-target heals are
-- out of scope by design - aiming a heal at a person is a group-frame job.
-- A targeted AoE (Wild Growth, Chain Heal) is fine: cast with no friendly
-- target it lands on the player and the splash still covers the group.
SpellDB.CLASS_GROUPHEAL_DEFAULTS = {
    -- Restoration Druid: Wild Growth, Efflorescence
    -- (Grove Guardians 102693 removed at 12.1: no acquisition route, and the only other id
    -- carrying the name - 1226140 - is a passive node with no castable button behind it.)
    DRUID_4 = {48438, 145205},
    -- Holy Paladin: Light of Dawn (cone), Divine Toll (multi Holy Shock)
    PALADIN_1 = {85222, 375576},
    -- Discipline Priest: multi-target ATONEMENT APPLICATORS - Discipline
    -- heals by damaging while Atonement is out. Radiance (target + allies),
    -- Prayer of Healing.
    PRIEST_1 = {194509, 596},
    -- Holy Priest: Prayer of Mending (bounces), HW: Sanctify (ground),
    -- Prayer of Healing, Halo
    -- (Circle of Healing 204883 removed at 12.1: none of its six ids has an acquisition
    -- route, so it could never be suggested.)
    PRIEST_2 = {33076, 34861, 596, 120517},
    -- Restoration Shaman: Chain Heal (bounces), Healing Stream Totem,
    -- Healing Rain (ground), Wellspring (wave)
    SHAMAN_3 = {1064, 5394, 73920, 197995},
    -- Mistweaver Monk: Vivify (cleaves to Renewing Mist holders),
    -- Renewing Mist (self-spreading HoT)
    MONK_2 = {116670, 119611},
    -- Preservation Evoker: Emerald Blossom, Dream Breath + Spiritbloom
    -- (empowered), Temporal Anomaly (wave)
    -- Dream Breath is 355936, not 382614 - the latter is one of seven ids sharing the
    -- name and has no acquisition route; 355936 is the one the talent tree grants.
    EVOKER_2 = {355913, 355936, 367226, 373861},
}

-- Party-wide buttons for DPS and tank specs: things that take pressure off the healer
-- without asking anyone to heal. Offered when the party is taking a beating, and solo once
-- your own health is low (DefensiveEngine, "group help"). Press-and-done only, like the
-- group heals above: nothing aimed at one ally.
-- Healer specs get an EMPTY list on purpose. Their group heals and emergency ladder above
-- already cover this job, and a spell must never render on two surfaces at once - which
-- the class fallback would otherwise do for Ancestral Guidance and Zephyr.
-- Classes with nothing party-wide (Druid, Hunter, Monk, Paladin DPS, Rogue, Warlock) have
-- no key. Nature's Vigil (124974) would suit Druids but has no acquisition route in 12.1.
SpellDB.CLASS_GROUP_HELP_DEFAULTS = {
    DEATHKNIGHT = {51052},            -- Anti-Magic Zone
    DEMONHUNTER = {196718},           -- Darkness
    EVOKER      = {374227, 355913},   -- Zephyr, Emerald Blossom
    EVOKER_2    = {},
    MAGE        = {414660},           -- Mass Barrier
    PRIEST_3    = {15286},            -- Vampiric Embrace
    SHAMAN      = {108281, 5394},     -- Ancestral Guidance, Healing Stream Totem
    SHAMAN_3    = {},
    WARRIOR     = {97462},            -- Rallying Cry
}

-- Group-crisis ladder for the emergency slot: first READY spell wins, so these
-- are ordered strongest-first. Dedicated group cooldowns only, DISJOINT from
-- CLASS_GROUPHEAL_DEFAULTS - a spell must never render on both surfaces at
-- once. Group-save DR cooldowns (Aura Mastery, Spirit Link, Zephyr) belong
-- here too: at 3+ allies low, stopping damage is healing.
SpellDB.HEAL_EMERGENCY_LADDER = {
    DRUID_4   = {740},                              -- Tranquility (Flourish 197721 is PASSIVE)
    PALADIN_1 = {31821, 216331},                    -- Aura Mastery, Avenging Crusader
    PRIEST_1  = {62618, 421453},                    -- PW: Barrier, Ultimate Penitence (Rapture 47536 has no route at 12.1)
    PRIEST_2  = {64843},                            -- Divine Hymn
    SHAMAN_3  = {108280, 207399, 98008, 108281},    -- Healing Tide, Ancestral Protection, Spirit Link, Ancestral Guidance
    MONK_2    = {388615, 322118, 325197},           -- Restoral, Yu'lon, Chi-Ji (Essence Font 231633 is PASSIVE)
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
-- C_SpecializationInfo.GetSpecialization() returns the spec index (1-4); compose key as CLASS .. "_" .. specIndex.
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
-- functions as a regular melee attack), but GapCloserEngine should only
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
    -- Dark Transformation is 1233448, the castable id. 63560 and 325554 both carry the name
    -- and are both PASSIVE, so the burst cue could never fire on them.
    DEATHKNIGHT_3 = {1233448, 42650},                -- Unholy: Dark Transformation (60s), Army of the Dead (180s)

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

--- Check whether an interrupt/CC spell is on a real cooldown (not just GCD).
--- Delegates to BlizzardAPI.IsSpellReady() (engine cooldown state, plain in combat).
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
--- Rebuilt on every call (spec change, SPELLS_CHANGED, surface creation); callers cache.
-- Shared resolver: build sorted {spellID, type, ...} entries for the abilities of the
-- given kinds that THIS character knows.
local function ResolveAbilitiesByKind(kindSet)
    local BlizzardAPI = GetBlizzardAPI()
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
    local BlizzardAPI = GetBlizzardAPI()
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
-- Attack-speed buffs the player casts, judged on WoW Forever by the swings after the cast
-- (BlizzardAPI CooldownTracking: PLAYER_SWING's duration is the plain in-combat attack
-- speed). swing = which auto attack speeds up (0 main hand, 2 ranged); max = the longest the
-- buff can last, the window inside which swing evidence is trusted. Rank-1 ids (any rank
-- matches via StaticLookup). Inert on retail, which has no swing events.
SpellDB.HASTE_BUFFS = {
    [5171]  = { swing = 0, max = 40 },  -- Slice and Dice (length scales with combo points)
    [13877] = { swing = 0, max = 20 },  -- Blade Flurry
    [3045]  = { swing = 2, max = 20 },  -- Rapid Fire
}

-- On-next-swing abilities (Heroic Strike, Cleave, Raptor Strike, Maul): pressing one queues
-- it onto the next auto attack instead of firing at once, so the queue shows it as in
-- progress until the swing lands. Every rank, filled on WoW Forever (Data/ForeverDefaults);
-- empty on retail, which has none.
SpellDB.NEXT_SWING_SPELLS = {}

-- DoTs whose cast also hits hard up front (a quarter or more of the total: Moonfire, Flame
-- Shock, Rake, Immolate). The hit still lands on a target about to die, so the dying-target
-- DoT block skips these. Every rank, filled on WoW Forever from the client data
-- (tools/gen_forever_defaults.py); empty on retail.
SpellDB.FRONTAL_DOTS = {}
function SpellDB.IsFrontalDot(spellID)
    return spellID ~= nil and StaticLookup(SpellDB.FRONTAL_DOTS, spellID) ~= nil
end
--- Is at least half of this spell's damage its own hit (Fireball, Moonfire)? The table holds
--- the hit's share for a frontal spell; an older `true` entry has no share and answers false.
function SpellDB.IsMostlyUpfrontDot(spellID)
    local share = spellID ~= nil and StaticLookup(SpellDB.FRONTAL_DOTS, spellID)
    return type(share) == "number" and share >= 0.5
end

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
