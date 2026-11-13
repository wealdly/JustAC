-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- PrecombatEngine.lua - Out-of-combat buff checklist. Detects pre-combat buffs (flask,
-- food, augment rune, weapon enchant) the player is missing AND owns something to fix.
-- Detection is aura-based and normally runs out of combat. Denied or unreadable aura
-- queries are treated as unknown, never as proof that an offer is missing.

local PrecombatEngine = LibStub:NewLibrary("JustAC-PrecombatEngine", 15)
if not PrecombatEngine then return end

local SpellDB = LibStub("JustAC-SpellDB", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

local InCombatLockdown = InCombatLockdown
local C_UnitAuras = C_UnitAuras
local ipairs = ipairs
local GetTime = GetTime
local type = type
local UnitClass = UnitClass
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsPlayerSpell = IsPlayerSpell or IsSpellKnown
local pcall = pcall
local issecretvalue = issecretvalue
local geterrorhandler = geterrorhandler
local UnitIsVisible = UnitIsVisible

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
        pcall(handler, "JustAC PrecombatEngine: " .. apiName .. " failed: " .. tostring(err))
    end
end

local function IsSecret(value)
    return (issecretvalue and issecretvalue(value)) or type(value) == "secret"
end

local function SafeAuraCall(fn, apiName, ...)
    if not fn then return nil, false end
    local ok, aura = pcall(fn, ...)
    if not ok then
        ReportAuraReadError(apiName, aura)
        return nil, false
    end
    if IsSecret(aura) then return nil, false end
    return aura, true
end

-- This list is used to prove an aura is absent. A denied or partial enumeration
-- cannot establish absence, so read the batch API directly and treat any failure
-- as unknown instead of falling back to BlizzardAPI.GetAuras' partial-list path.
local function SafeAuraList(unit, filter)
    local unitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
    if unitAuras then
        local auras, known = SafeAuraCall(unitAuras, "GetUnitAuras", unit, filter)
        if not known or type(auras) ~= "table" then return nil, false end
        return auras, true
    end

    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not byIndex then return nil, false end
    local auras = {}
    for i = 1, 40 do
        local aura, known = SafeAuraCall(byIndex, "GetAuraDataByIndex", unit, i, filter)
        if not known then return nil, false end
        if aura == nil then return auras, true end
        auras[#auras + 1] = aura
    end
    return nil, false
end

-- Top-off "between pulls" reminder fires below this (exact read, OOC only) - toggle-gated.
local RECUPERATE_HEALTH_PCT = 80
-- Emergency floor: at/below this (the never-secret low-health vignette) the heal ALWAYS
-- shows, regardless of the top-off toggle - a critical-health survival cue.
local LOW_HEALTH_PCT = 35

-- Onset debounce: "below the selected threshold" must persist before the reminder
-- appears. Health can dip below full for a moment for uninteresting reasons (a
-- scratch that regen erases immediately, a passive's no-change snapshot), and a
-- reminder that pops for one frame each time is worse than no reminder.
-- Deliberately ASYMMETRIC: appearing is delayed, but reaching full clears it
-- instantly - being told to top off when you are already topped off is the one
-- state this feature must never show.
local TOPOFF_ONSET_SECONDS = 2
local notFullSince = 0

-- Re-offer a buff once it has this much time left, rather than waiting for it to lapse
-- outright. FLAT time remaining, not a fraction of the duration: what matters is whether
-- the buff outlasts the pull, and a 60-minute flask with 20 minutes on it needs nothing.
-- Wider in a group, where a recast covers everyone and wants to land while people are
-- still standing around rather than mid-pull. Applies to long-duration upkeep categories -
-- flasks, food, runes, oils, poisons, imbues, raid buffs. Short preparation uses its own cap.
local PRECOMBAT_REFRESH_SOLO  = 180   -- 3 minutes
local PRECOMBAT_REFRESH_GROUP = 300   -- 5 minutes
local PREPARATION_REFRESH_FRACTION = 0.25
local PREPARATION_REFRESH_MAX = 10

local function RefreshWindow()
    local inGroup = IsInGroup and IsInGroup()
    -- Group-membership probes can come back secret in instanced contexts; unreadable means
    -- we cannot establish a group, and the narrower window is the one that nags less.
    if issecretvalue and issecretvalue(inGroup) then return PRECOMBAT_REFRESH_SOLO end
    return inGroup and PRECOMBAT_REFRESH_GROUP or PRECOMBAT_REFRESH_SOLO
end

-- Exported because the redundancy filter has to agree with us: it decides when a buff that
-- IS up stops being reason enough to hide the recast, and that has to be the same moment we
-- start offering it. Two numbers here meant the queue nagged long before we did.
PrecombatEngine.RefreshWindow = RefreshWindow

-- Is this aura close enough to lapsing to be worth re-applying now?
-- A permanent aura (duration 0) never lapses. Unreadable timing answers "no": a buff we
-- cannot time is one we must not nag about, since the cost of a false cue is a wasted
-- flask. Same rule the class-buff path uses, so one window governs everything.
local function IsLapsing(aura)
    if not aura then return false end
    local dur, exp = aura.duration, aura.expirationTime
    if issecretvalue and (issecretvalue(dur) or issecretvalue(exp)) then return false end
    if type(dur) ~= "number" or type(exp) ~= "number" or dur <= 0 then return false end
    return (exp - GetTime()) <= RefreshWindow()
end

-- Weapon expiry is milliseconds remaining, not an aura expiration timestamp.
local function WeaponEnchantHolds(slot, imbue)
    local has, expiryMs = BlizzardAPI.GetWeaponEnhancementInfo(slot, imbue)
    if has == nil then return true, false end
    if not has then return false, true end
    if IsSecret(expiryMs) then return true, false end
    if type(expiryMs) ~= "number" then return true, false end
    return (expiryMs / 1000) > RefreshWindow(), true
end

-- The off-hand imbue to offer, or nil. Blizzard routes the hands in SPELL DATA:
-- Windfury's tooltip reads "main-hand", and Flametongue's is conditional on KNOWING
-- Windfury ($?s33757[off-hand][]) - so when both are known (Enhancement), Flametongue
-- IS the off-hand cast and a plain spell click applies to the right slot; no
-- slot-targeted macro needed. Offerable only when the off-hand holds a WEAPON
-- (classID 2): shields and frills can't take an imbue. GetItemInfoInstant is
-- cache-free, so this never waits on an item query.
local function OffHandImbue()
    if not (IsPlayerSpell(33757) and IsPlayerSpell(318038)) then return nil end
    local itemID = GetInventoryItemID and GetInventoryItemID("player", 17)
    if not itemID then return nil end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= 2 then return nil end
    return 318038
end

-- True if the player currently has any aura whose spellId is in the set AND it is not
-- already inside the refresh window. Iterates the player's helpful auras (usually < 40),
-- so cost is independent of how big the set is - which matters because the food set can
-- hold a few hundred Well Fed buff ids.
local function HasAnyAura(buffSet)
    if not buffSet then return true, false end
    local auras, known = SafeAuraList("player", "HELPFUL")
    if not known then return true, false end
    local ok, found, uncertain = pcall(function()
        local unsure = false
        for i = 1, #auras do
            local aura = auras[i]
            if IsSecret(aura) then
                unsure = true
            else
                local spellId = aura and aura.spellId
                if spellId == nil or IsSecret(spellId) then
                    unsure = true
                elseif buffSet[spellId] then
                    local lapsing = IsLapsing(aura)
                    if not lapsing then return true, false end
                end
            end
        end
        return false, unsure
    end)
    if not ok then
        ReportAuraReadError("HELPFUL aura fields", found)
        return true, false
    end
    return found or uncertain, not uncertain
end

-- The known weapon preparation in preference order (Shaman imbues or Paladin rites).
-- Existing enchants satisfy this path; never replace the player's chosen alternative.
local function KnownWeaponImbue()
    local list = SpellDB and SpellDB.WEAPON_IMBUE_SPELLS
    if not list then return nil end
    for i = 1, #list do
        if IsPlayerSpell(list[i]) then return list[i] end
    end
    return nil
end

-- Optimistic post-click suppression for weapon enhancements. Applying one is a server
-- round trip, so GetWeaponEnchantInfo keeps reporting "no enchant" for a beat after the
-- click - long enough that the suggestion lingers, still clickable, and a double-click
-- burns a second stone (the click applies in one go; it isn't a harmless cursor arm).
-- Treat the category as satisfied for a moment after a click so the icon clears at once.
-- Purely a display latch: if the application never landed, the window lapses and the
-- suggestion returns on the next rebuild.
local ENCHANT_APPLY_GRACE = 2
local enchantAppliedAt = -1e9

--- Called by the click overlay the instant a weapon enhancement is used.
function PrecombatEngine.NoteWeaponEnchantApplied()
    enchantAppliedAt = GetTime()
    PrecombatEngine.ClearCache()
end

--- Mid-application guard: is an application in progress right now? Every category here is
--- satisfied by an AURA (or a weapon enchant) that only lands when the cast/channel COMPLETES,
--- so while you are eating, applying a poison or imbue, or using an oil, the category still
--- reads "missing". One more click then cancels the channel (wasting the food) or burns a
--- second consumable - and ANY suggestion cancels it, not just the one being applied.
---
--- The suggestions STAY on screen through the wait (you are still out of combat, and the icon
--- is what tells you what you're waiting on); it's the CLICK that has to stop. The click
--- overlay disarms every layer while this is true - see UIPrecombatOverlay.
---
--- Eating counts even though it is aura-based (no cast bar, no UnitChannelInfo) - but only
--- for the ~10s it takes Well Fed to land, not the whole meal. The buff persists once you
--- stand up, so waiting out the rest of the food aura buys nothing.
--- OOC-only system, and we only test truthiness (never compare/concat), so this is secret-safe.
function PrecombatEngine.IsBusyApplying()
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if UnitChannelInfo and UnitChannelInfo("player") then return true end
    if SpellDB and SpellDB.IsEatingForBuff then
        return SpellDB.IsEatingForBuff()
    end
    return false
end

--- Is the buff category already satisfied? Weapon enchant is read off the weapon (temp
--- enchant); every other category from the player's auras. Out of combat only.
function PrecombatEngine.IsCategorySatisfied(category)
    -- 12.0.7: in aura-restricted contexts (PvP instances - restriction is per-context,
    -- not per-combat) every aura reads as secret, so nothing can be verified. Report
    -- satisfied so we never nag someone to re-consume a buff they may already have.
    -- Live gate; false in normal content keeps this a no-op.
    if BlizzardAPI and BlizzardAPI.AreAurasSecret() then
        return true, false
    end
    if category == "weaponEnchant" then
        if GetTime() - enchantAppliedAt < ENCHANT_APPLY_GRACE then return true, true end
        return WeaponEnchantHolds(0)
    end
    local set = SpellDB and SpellDB.GetPrecombatBuffSet and SpellDB.GetPrecombatBuffSet(category)
    return HasAnyAura(set)
end

--- Pre-combat buffs the player is missing AND can fix right now:
--- { {category=, entry=}, ... } - the best owned entry per enabled, unsatisfied category.
--- Out of combat only (returns empty in combat; buffs can't be applied there anyway). A
--- category only appears if the player actually OWNS something that satisfies it.
--- `settings` (optional), keyed by category:
---   settings[category] = false             -> category disabled
---   settings[category] = "haste"/"crit"/…  -> stat preference for the best-owned pick
function PrecombatEngine.GetMissingBuffs(settings)
    local out = {}
    if InCombatLockdown() then return out end
    if not SpellDB or not SpellDB.GetPrecombatBuffCategories then return out end
    for _, category in ipairs(SpellDB.GetPrecombatBuffCategories()) do
        -- An imbue-using class (Enhancement shaman) fills the main-hand enchant slot with its
        -- weapon imbue, so never suggest a weapon oil for it - the imbue is offered instead by
        -- GetMissingClassBuffs (and an oil would just overwrite the imbue anyway).
        local skip = category == "weaponEnchant" and KnownWeaponImbue() ~= nil
        local pref = settings and settings[category]
        if not skip and pref ~= false and not PrecombatEngine.IsCategorySatisfied(category) then
            local entry = SpellDB.GetBestOwnedBuff(category,
                type(pref) == "string" and pref or nil)
            if entry then
                out[#out + 1] = { category = category, entry = entry }
            end
        end
    end
    return out
end

--- Just the bag-item IDs to insert at the front of the defensive queue, in category order
--- (bag items only; toys/spells are handled elsewhere). Out of combat only.
---
--- Cached for a short window: the defensive queue rebuilds up to ~10x/s, but this scans
--- every buff item (GetItemCount) + aura state, which only changes on bag/aura/gear events.
--- A 0.5s expiry caps the full scan at ~2x/s and still reflects changes within half a
--- second. (In combat the queue insertion is skipped entirely, so the cache is OOC-only.)
local cachedItems, cachedItemsAt = nil, -1
local cachedClassBuffs, cachedClassBuffsAt = nil, -1
function PrecombatEngine.GetMissingBuffItems(settings, recoveryManaPct)
    local now = GetTime()
    if cachedItems and (now - cachedItemsAt) < 0.5 then
        return cachedItems
    end
    local out = {}
    for _, m in ipairs(PrecombatEngine.GetMissingBuffs(settings)) do
        if (m.entry.source or "item") == "item" then
            out[#out + 1] = m.entry.id
        end
    end
    PrecombatEngine.AddRecoveryItems(out, recoveryManaPct, settings)
    cachedItems, cachedItemsAt = out, now
    return out
end

-- WoW Forever: recover between pulls. Out of combat with mana below RECOVERY_MANA_PCT, offer
-- the best drink; with health below RECOVERY_HEALTH_PCT, the best food, or a bandage when no
-- food is in the bags. Health and mana are secret there even out of combat; the engine-side
-- "below N%" checks answer (measured build 70245). Nothing while already eating or drinking,
-- mounted or dead. A no-op on retail, where no recovery items are registered.
local RECOVERY_HEALTH_PCT, RECOVERY_MANA_PCT = 70, 80
function PrecombatEngine.GetRecoveryThresholds(recoveryManaPct)
    return RECOVERY_HEALTH_PCT, recoveryManaPct or RECOVERY_MANA_PCT
end
local RECENTLY_BANDAGED = 11196
local NO_MANA = { WARRIOR = true, ROGUE = true }
function PrecombatEngine.IsRecoveryEnabled(settings, category)
    if not settings then return true end
    if settings[category] ~= nil then return settings[category] ~= false end
    return settings.recovery ~= false
end
function PrecombatEngine.AddRecoveryItems(out, recoveryManaPct, settings)
    if not (SpellDB and SpellDB.IsForever() and SpellDB.GetBestRecoveryItem and BlizzardAPI) then return end
    local dead = UnitIsDeadOrGhost("player")
    local eating, eatingKnown = nil, true
    if SpellDB.GetActiveEatingAura then
        eating, eatingKnown = SpellDB.GetActiveEatingAura()
    end
    if InCombatLockdown() or (IsMounted and IsMounted())
       or (issecretvalue and issecretvalue(dead)) or dead
       or not eatingKnown or eating then
        return
    end
    local function add(id)
        if not id then return end
        for i = 1, #out do
            if out[i] == id then return end
        end
        out[#out + 1] = id
    end
    local _, manaPct = PrecombatEngine.GetRecoveryThresholds(recoveryManaPct)
    if PrecombatEngine.IsRecoveryEnabled(settings, "manaRecovery")
       and not NO_MANA[select(2, UnitClass("player")) or ""] and BlizzardAPI.IsUnitPowerBelow
       and BlizzardAPI.IsUnitPowerBelow("player", manaPct, Enum.PowerType.Mana) == true then
        add(SpellDB.GetBestRecoveryItem("drink"))
    end
    if PrecombatEngine.IsRecoveryEnabled(settings, "healthRecovery")
       and BlizzardAPI.IsUnitHealthBelow
       and BlizzardAPI.IsUnitHealthBelow("player", RECOVERY_HEALTH_PCT) == true then
        local heal, healing = PrecombatEngine.GetReadyRecoveryHeal(settings and settings.healthRecovery)
        if heal or healing then return end
        local food = SpellDB.GetBestRecoveryItem("food")
        if food then
            add(food)
        else
            local bandaged, known = SafeAuraCall(
                C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID,
                "GetPlayerAuraBySpellID", RECENTLY_BANDAGED)
            if known and not bandaged then add(SpellDB.GetBestRecoveryItem("bandage")) end
        end
    end
end

--- Drop the cache so the next query recomputes immediately (call on options changes).
local preparationAuraCache = {}

function PrecombatEngine.ClearCache()
    cachedItemsAt = -1
    cachedClassBuffsAt = -1
    wipe(preparationAuraCache)
end

-- Class maintained buffs (poisons, imbues) that need (re)applying, as spell IDs. For each
-- group we find the option that's currently ACTIVE and re-suggest it once it is close enough
-- to lapsing to be worth a recast; if none is up we fall back to the group's default. Only
-- spells the player knows (IsPlayerSpell) surface, so it self-gates by class. Out of combat
-- only; cached. Shares the flat refresh window with the consumable categories (IsLapsing);
-- preparation groups use a bounded OOC refresh window, never the upkeep window.
--
-- One override on all of that: when the assisted-combat rotation expresses its own pick
-- within a group (see ACPickInGroup), that pick WINS - over the default, over the queue
-- scan, and even over a different member that is already active and fresh.

-- Forever ranks: groups name rank 1, while casts, the queue and the bar carry the rank
-- pressed. Every match below goes through rank 1 (the id itself on retail).
local RotationImport = LibStub("JustAC-RotationImport", true)
local function R1(id) return RotationImport and RotationImport.RankBase(id) or id end
local function KnownClassBuff(id)
    if RotationImport and RotationImport.HighestKnownRank then
        return RotationImport.HighestKnownRank(id)
    end
    if IsPlayerSpell(id) then return id end
end

function PrecombatEngine.GetRecoveryHeals()
    local out = {}
    local class = select(2, UnitClass("player"))
    local lists = SpellDB and SpellDB.CLASS_TOPOFF_HEALS
    local list = lists and lists[class]
    for _, id in ipairs(list or {}) do
        local known = KnownClassBuff(id)
        if known then out[#out + 1] = known end
    end
    local recuperate = SpellDB and SpellDB.RECUPERATE
    if recuperate and (KnownClassBuff(recuperate)
       or (IsSpellKnown and IsSpellKnown(recuperate))
       or (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(recuperate))) then
        out[#out + 1] = recuperate
    end
    return out
end

function PrecombatEngine.GetReadyRecoveryHeal(preference)
    if InCombatLockdown() or preference == false or preference == "items" then return nil, false end
    local heals = PrecombatEngine.GetRecoveryHeals()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for _, heal in ipairs(heals) do
        if heal == SpellDB.RECUPERATE then
            local aura, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", SpellDB.RECUPERATE_AURA)
            if not known or aura then return nil, true end
            break
        end
    end
    for _, heal in ipairs(heals) do
        if type(preference) ~= "number" or R1(heal) == R1(preference) then
            if heal ~= SpellDB.RECUPERATE then
                local aura, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", heal)
                if not known or aura then return nil, true end
            end
            if BlizzardAPI
               and SafeAuraCall(BlizzardAPI.IsSpellUsable, "IsSpellUsable", heal, false) == true
               and SafeAuraCall(BlizzardAPI.IsSpellReady, "IsSpellReady", heal) == true then
                return heal, false
            end
        end
    end
    return nil, false
end

-- The member of `group` the assisted-combat rotation itself runs, or nil. Matching it is
-- mandatory, not cosmetic: the AC manager keeps recommending ITS member until that exact
-- one is applied - a different member of the same group never satisfies it - so offering
-- anything else sends the player in a circle (apply ours, AC still nags for the other).
-- Two sources, in authority order:
--   1. The live demand (GetAnyNextCastSpell / plain queue head) - the very spell slot 1
--      is frozen on. Plain and readable out of combat, which is the only place this runs.
--   2. GetRotationSpells - the spec's full AC spell list (also plain). Confirmed in game:
--      it carries EVERY member of a group the spec can use (Sub lists all three
--      non-lethal poisons), so it expresses a pick ONLY when exactly one member appears.
--      Several listed members = no opinion - return nil and let the demand chain (or,
--      with no demand pending, the caller's fallbacks) decide.
local function ACPickInGroup(nextCast, rotation, group)
    if nextCast then
        nextCast = R1(nextCast)
        for j = 1, #group do
            if nextCast == group[j] and KnownClassBuff(group[j]) then return group[j] end
        end
    end
    if not rotation then return nil end
    local found
    for j = 1, #group do
        if KnownClassBuff(group[j]) then
            for i = 1, #rotation do
                if R1(rotation[i]) == group[j] then
                    if found then return nil end   -- second member listed: ambiguous
                    found = group[j]
                    break
                end
            end
        end
    end
    return found
end

-- Highest-priority member of `group` that the current rotation/fixed queue wants, or nil.
-- Fallback pick when a maintained buff is missing entirely and the rotation list gave no
-- answer (ACPickInGroup above is the preferred source): offer the poison the fixed queue
-- is actually trying to apply instead of a blind default. Best-effort only - position 1
-- of the queue is Blizzard's 12.0 secret suggestion, which can't be compared (a raw `==`
-- throws), so secret entries are skipped. Returns the known group constant (never a queue
-- value) and only one the player knows, so it can NEVER suppress the reliable default
-- fallback at the call site.
local function HighestQueuedInGroup(group)
    local SQ = LibStub("JustAC-SpellQueue", true)
    local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
    if type(queue) ~= "table" then return nil end
    for i = 1, #queue do
        local q = queue[i]
        if not (issecretvalue and issecretvalue(q)) then
            q = R1(q)
            for j = 1, #group do
                if q == group[j] and KnownClassBuff(group[j]) then return group[j] end
            end
        end
    end
    return nil
end

-- Unit-state probes (exists / connected / dead / in-range) can return a SECRET BOOLEAN even
-- out of combat: secrecy is per-CONTEXT, not per-combat, so an instanced context secrets them
-- while player auras still read fine - which is exactly why the `restricted` aura gate upstream
-- does NOT cover this. A bare `if UnitInRange(unit) then` on a secret boolean THROWS.
-- Resolve to a real boolean when readable, nil when secret; every caller treats nil as
-- "can't tell" and skips the member (fail-silent - never cue what we can't verify).
local function ReadableBool(v)
    if v == nil then return nil end
    if IsSecret(v) then return nil end
    return v and true or false
end

-- Does `unit` carry any of `auraIDs` as a HELPFUL aura? Reads the unit's aura list directly -
-- deliberately NOT BlizzardAPI.IsAuraActive, which serves the player-only RedundancyFilter
-- cache when it's warm and would report every party member as buffed.
-- `auraIDs` is a LIST because a buff need not apply its own cast id - some trigger a
-- per-class sub-aura instead, and matching only the cast id would report a fully buffed
-- player as missing forever.
-- Fail-SILENT: an unreadable (secret) spellId means we can't prove the buff is missing, so
-- we report "has it". Note this bails on the FIRST unreadable entry rather than skipping it:
-- skipping could walk past the buff itself and produce a false "missing" cue. The cost is
-- that the party check goes quiet wherever auras are secret - the right trade for a feature
-- whose only failure mode would otherwise be nagging about a buff that is already up.
local function UnitHasHelpfulAura(unit, auraIDs)
    if not auraIDs then return true end
    -- GetUnitAuraBySpellID also returns nil for units that cannot be seen, so it
    -- proves absence only for a visible unit while aura reads are unrestricted.
    local visible, visibleKnown = SafeAuraCall(UnitIsVisible, "UnitIsVisible", unit)
    if not visibleKnown or ReadableBool(visible) ~= true
       or (BlizzardAPI and BlizzardAPI.AreAurasSecret()) then
        return true
    end
    local byId = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if byId then
        for j = 1, #auraIDs do
            local data, known = SafeAuraCall(byId, "GetUnitAuraBySpellID", unit, auraIDs[j])
            if not known or data ~= nil then return true end
        end
        return false
    end
    local auras, known = SafeAuraList(unit, "HELPFUL")
    if not known then return true end
    local ok, found = pcall(function()
        for i = 1, #auras do
            local aura = auras[i]
            local sid
            if not IsSecret(aura) and aura then sid = aura.spellId end
            if sid == nil or IsSecret(sid) then return true end
            for j = 1, #auraIDs do
                if sid == auraIDs[j] then return true end
            end
        end
        return false
    end)
    if not ok then
        ReportAuraReadError("HELPFUL aura fields", found)
        return true
    end
    return found
end

-- True when a PARTY member who could actually receive the buff right now is missing it.
-- Party only (party1-4): raid scale would be up to 39 unit scans per refresh and would
-- cue constantly for people out of range or freshly resurrected, so raids are skipped
-- outright. Dead / disconnected / out-of-range members are excluded so every cue is one
-- the player can act on immediately. Note UnitInRange is ~40yd while these buffs reach
-- further - the mismatch errs toward silence, never toward a false cue.
local function PartyMemberMissingBuff(castID, auraIDs)
    -- Group-membership probes go through the same readable-boolean gate: anything we can't
    -- read plainly means we can't establish there's a party to check, so offer nothing.
    if ReadableBool(IsInGroup and IsInGroup()) ~= true then return false end
    if ReadableBool(IsInRaid and IsInRaid()) ~= false then return false end
    for i = 1, 4 do
        local unit = "party" .. i
        if ReadableBool(UnitExists(unit)) == true then
            -- Compare against explicit true/false, never a bare truthiness test: a secret
            -- probe resolves to nil here and the member is skipped, which is the only safe
            -- reading of "we cannot tell whether they are buffable".
            -- NPCs (dungeon followers, companions) never carry player raid buffs, so a
            -- follower party would nag forever - no recast can satisfy the check. And a
            -- cross-faction open-world member the buff cannot legally reach is noise, not
            -- a cue: UnitCanAssist filters those (plain reaction booleans, both).
            local isPlayer  = ReadableBool(UnitIsPlayer(unit))
            local canAssist = ReadableBool(UnitCanAssist("player", unit))
            local connected = ReadableBool(UnitIsConnected(unit))
            local dead      = ReadableBool(UnitIsDeadOrGhost(unit))
            -- Range via the BUFF's own spell-range query, which stays PLAIN for allies
            -- where the generic 40yd probe reads secret (measured 2026-08-10: UnitInRange
            -- returned a secret boolean for an open-world party member OUT of combat, so
            -- this gate silently skipped everyone and the recast nudge never fired). It
            -- is also the truer question - "can my recast reach them". The generic probe
            -- stays as fallback when the spell query has no answer.
            local inRange
            if castID and C_Spell and C_Spell.IsSpellInRange then
                local ok, sr = pcall(C_Spell.IsSpellInRange, castID, unit)
                if ok then inRange = ReadableBool(sr) end
            end
            if inRange == nil then
                inRange = ReadableBool(UnitInRange(unit))
            end
            if isPlayer == true and canAssist == true
               and connected == true and dead == false and inRange == true
               and not UnitHasHelpfulAura(unit, auraIDs) then
                return true
            end
        end
    end
    return false
end

-- Applied-latch for class-buff and imbue SPELL casts - the spell twin of
-- NoteWeaponEnchantApplied above, fed from UNIT_SPELLCAST_SUCCEEDED. The cast has
-- landed but the aura (or weapon enchant) takes a server beat to register; without
-- this the offer stays on screen with a live "click" hint for those seconds, and a
-- second click re-applies for nothing. Purely a display latch: if the application
-- somehow never lands, the grace lapses and the offer returns.
local CLASSBUFF_APPLY_GRACE = 3
local classBuffAppliedAt = {}
local function IsFreshlyApplied(spellID)
    -- Combat preparation may be consumed immediately after the pull. Its OOC
    -- settle latch must not hide a legitimate combat reapplication.
    if InCombatLockdown() and SpellDB and SpellDB.PREPARATION_BUFF_MEMBERS
       and SpellDB.PREPARATION_BUFF_MEMBERS[spellID] then return false end
    local t = classBuffAppliedAt[R1(spellID)]
    return t ~= nil and (GetTime() - t) < CLASSBUFF_APPLY_GRACE
end
-- Exported for RedundancyFilter's sibling rule: a group with a freshly-applied member
-- keeps its siblings out of the queue for the same settle window.
PrecombatEngine.IsClassBuffFresh = IsFreshlyApplied

--- Called from the addon's UNIT_SPELLCAST_SUCCEEDED handler for player casts.
--- Latches only maintained members and imbues, so the table stays a handful of keys.
function PrecombatEngine.NoteClassBuffApplied(spellID)
    if not spellID then return end
    local members = SpellDB and SpellDB.MAINTAINED_BUFF_MEMBERS
    local enchants = SpellDB and SpellDB.WEAPON_ENCHANT_SPELLS
    if (members and members[spellID]) or (enchants and enchants[spellID]) then
        classBuffAppliedAt[R1(spellID)] = GetTime()
        PrecombatEngine.ClearCache()
    end
end

-- Is the player currently CASTING a maintained application (a poison's several-second
-- apply, a weapon imbue)? Read for the mid-cast hold below. OOC cast info is plain.
local function CastingMaintainedBuff()
    if not UnitCastingInfo then return false end
    local castID = select(9, UnitCastingInfo("player"))
    if not castID or (issecretvalue and issecretvalue(castID)) then return false end
    if SpellDB and SpellDB.WEAPON_ENCHANT_SPELLS and SpellDB.WEAPON_ENCHANT_SPELLS[castID] then
        return true
    end
    castID = R1(castID)
    local class = select(2, UnitClass("player"))
    local groups = class and SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS
        and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    if not groups then return false end
    for _, grp in ipairs(groups) do
        for _, id in ipairs(grp.group) do
            if castID == id then return true end
        end
    end
    return false
end

-- Cooldown-free stealths worth entering before a pull, per class. Vanish and Shadowmeld are
-- left out: they are escapes with real cooldowns, not an opener stance. Prowl is Feral
-- only - every druid knows it, and on by default it would nag the other three specs.
local STEALTH_REMINDER = {
    ROGUE = { spell = 1784 },            -- Stealth
    DRUID = { spell = 5215, spec = 2, tree = "feral" },  -- Prowl (Feral)
}

local function PreparationMatches(group)
    if group.tree then
        local rotationImport = LibStub("JustAC-RotationImport", true)
        if not rotationImport or not rotationImport.GetForeverTree
           or rotationImport.GetForeverTree() ~= group.tree then return false end
    end
    if group.spec then
        local spec, known = SafeAuraCall(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization,
            "GetSpecialization")
        if not known or spec ~= group.spec then return false end
    end
    if group.form then
        local mounted, mountKnown = SafeAuraCall(IsMounted, "IsMounted")
        if not mountKnown or mounted ~= false then return false end
        local formCache = LibStub("JustAC-FormCache", true)
        local form, known = SafeAuraCall(formCache and formCache.GetActiveForm, "GetActiveForm")
        if not known or form ~= 0 then return false end
    end
    return true
end

local function PreparationReady(spellID)
    return BlizzardAPI and BlizzardAPI.IsSpellUsable
        and BlizzardAPI.IsSpellUsable(spellID, false) == true
        and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(spellID) == true
end

local function PreparationAuraActive(group)
    -- Shared viewer records can represent every alternative (Forever's Seals).
    -- Read live, before the aura cache, so consumption/hidden viewers release the signal.
    local trackedActive = false
    if not group.form then
        local tracker = LibStub("JustAC-MaintenanceTracker", true)
        if tracker and tracker.IsTrackedAuraActive then
            for _, member in ipairs(group.group) do
                if SafeAuraCall(tracker.IsTrackedAuraActive, "IsTrackedAuraActive", member) == true then
                    trackedActive = true
                    break
                end
            end
        end
    end
    if trackedActive and InCombatLockdown() then return true end
    -- Shared by queue filtering and glow selection; aura events invalidate the cache.
    -- Use current guarded reads, not cast/expiry estimates: seals can be consumed early.
    local now = GetTime()
    local cached = preparationAuraCache[group]
    if cached and now - cached.at < 0.25 then
        return trackedActive or cached.active, cached.aura, cached.auraID
    end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local active, activeAura, activeAuraID = false, nil, nil
    for _, auraID in ipairs(group.auraIDs or group.group) do
        local aura, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", auraID)
        if known and aura ~= nil then
            active, activeAura, activeAuraID = true, aura, auraID
            break
        end
        if not known then active = nil end
    end
    preparationAuraCache[group] = { at = now, active = active, aura = activeAura, auraID = activeAuraID }
    return trackedActive or active, activeAura, activeAuraID
end

local function PreparationRefreshSpell(group, aura, auraID)
    if InCombatLockdown() or group.form or not aura or not auraID
       or not PreparationMatches(group) or CastingMaintainedBuff()
       or SafeAuraCall(BlizzardAPI and BlizzardAPI.AreAurasSecret, "AreAurasSecret") ~= false then
        return nil
    end
    for _, member in ipairs(group.group) do
        if IsFreshlyApplied(member) then return nil end
    end
    local ok, duration, expiration = pcall(function() return aura.duration, aura.expirationTime end)
    if not ok then
        ReportAuraReadError("preparation aura timing", duration)
        return nil
    end
    if IsSecret(duration) or IsSecret(expiration)
       or type(duration) ~= "number" or type(expiration) ~= "number"
       or duration <= 0 or expiration <= 0
       or expiration - GetTime() > math.min(PREPARATION_REFRESH_MAX, duration * PREPARATION_REFRESH_FRACTION) then
        return nil
    end
    -- Refresh only the identified active member, never a default or competing seal.
    for _, member in ipairs(group.group) do
        local matches = R1(auraID) == R1(member)
        for _, id in ipairs(group.memberAuraIDs and group.memberAuraIDs[member] or {}) do
            if auraID == id then matches = true; break end
        end
        if matches then
            local spell = KnownClassBuff(member)
            if not spell or not PreparationReady(spell)
               or SafeAuraCall(GetSpellBaseCooldown, "GetSpellBaseCooldown", spell) ~= 0 then return nil end
            return spell
        end
    end
end

function PrecombatEngine.IsPreparationFamilyActive(spellID)
    if not spellID or IsSecret(spellID) then return false end
    local group = SpellDB and SpellDB.PREPARATION_BUFF_MEMBERS[spellID]
    -- Forms/stances can deliberately change during combat; their form gates own eligibility.
    if not group or group.form then return false end
    return PreparationAuraActive(group) == true
end

function PrecombatEngine.IsPreparationFamilySatisfied(spellID)
    if not spellID or IsSecret(spellID) then return false end
    local group = SpellDB and SpellDB.PREPARATION_BUFF_MEMBERS[spellID]
    if not group or group.form then return false end
    local active, aura, auraID = PreparationAuraActive(group)
    if active ~= true then return false end
    local refresh = PreparationRefreshSpell(group, aura, auraID)
    return refresh == nil or R1(refresh) ~= R1(spellID)
end

function PrecombatEngine.ShouldEmphasizePreparation(spellID)
    if not spellID or IsSecret(spellID) then return false end
    local group = SpellDB and SpellDB.PREPARATION_BUFF_MEMBERS[spellID]
    local weapon = SpellDB and SpellDB.WEAPON_ENCHANT_SPELLS[spellID]
    if not (group and group.combatCritical) and not weapon then return false end
    if not KnownClassBuff(spellID) or not PreparationReady(spellID)
       or IsFreshlyApplied(spellID) or CastingMaintainedBuff() then return false end
    if SafeAuraCall(UnitExists, "UnitExists", "target") ~= true
       or SafeAuraCall(UnitCanAttack, "UnitCanAttack", "player", "target") ~= true
       or SafeAuraCall(UnitIsDeadOrGhost, "UnitIsDeadOrGhost", "target") ~= false
       or SafeAuraCall(UnitIsDeadOrGhost, "UnitIsDeadOrGhost", "player") ~= false
       or SafeAuraCall(IsMounted, "IsMounted") ~= false
       or SafeAuraCall(UnitInVehicle, "UnitInVehicle", "player") ~= false then return false end
    if weapon then
        if GetTime() - enchantAppliedAt < ENCHANT_APPLY_GRACE then return false end
        local offHand = OffHandImbue()
        if spellID ~= offHand and R1(spellID) ~= KnownWeaponImbue() then return false end
        local slot = spellID == offHand and 1 or 0
        local itemID = SafeAuraCall(GetInventoryItemID, "GetInventoryItemID", "player", 16 + slot)
        if type(itemID) ~= "number" or itemID <= 0 then return false end
        return SafeAuraCall(BlizzardAPI.GetWeaponEnhancementInfo,
            "GetWeaponEnhancementInfo", slot, true) == false
    end
    if not PreparationMatches(group)
       or SafeAuraCall(BlizzardAPI.AreAurasSecret, "AreAurasSecret") ~= false then return false end
    for _, member in ipairs(group.group) do
        if IsFreshlyApplied(member) then return false end
    end
    local active, aura, auraID = PreparationAuraActive(group)
    if active == false then return true end
    local refresh = PreparationRefreshSpell(group, aura, auraID)
    return refresh ~= nil and R1(refresh) == R1(spellID)
end

--- The entry's spec gate. WoW Forever has one spec per class, so Feral there is the
--- installed talent tree (RotationImport picks it from points spent), not spec index 2.
local function StealthSpecMatches(entry)
    if not entry.spec then return true end
    if SpellDB and SpellDB.IsForever and SpellDB.IsForever() then
        local RI = LibStub("JustAC-RotationImport", true)
        local tree = RI and RI.GetForeverTree and RI.GetForeverTree()
        return tree == entry.tree or tree == (entry.tree and entry.tree .. "_bear")
    end
    return C_SpecializationInfo.GetSpecialization() == entry.spec
end
PrecombatEngine.STEALTH_REMINDER = STEALTH_REMINDER

--- The player's stealth, when it is worth reminding about: known, not already stealthed, and
--- not in a state where stealthing makes no sense (mounted, flying, on a taxi, resting, in a
--- vehicle, dead). Deliberately NOT gated on the cooldown: the offer keeps its slot with the
--- cooldown swipe, and the renderer holds its glow until the spell is ready.
local function StealthReminderSpell()
    if (IsStealthed and IsStealthed()) or (IsMounted and IsMounted())
        or (IsFlying and IsFlying()) or (UnitOnTaxi and UnitOnTaxi("player"))
        or (IsResting and IsResting())
        or ReadableBool(UnitInVehicle and UnitInVehicle("player")) == true
        or ReadableBool(UnitIsDeadOrGhost("player")) ~= false then
        return nil
    end
    local entry = STEALTH_REMINDER[select(2, UnitClass("player"))]
    if not entry or not StealthSpecMatches(entry) then return nil end
    -- OverridesKnown: Subterfuge replaces Stealth (1784 -> 115191), and a replaced base
    -- spell can read as unknown to IsPlayerSpell. Casting the base id still casts the override.
    local known = IsPlayerSpell(entry.spell)
        or (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(entry.spell))
    return known and entry.spell or nil
end

--- @param offerTopoff boolean|nil  include the OOC top-off self-heal (gated by the
---   precombatBuffs.topoffHeal option; passed by the caller which owns the profile). Poisons
---   and imbues are unaffected - only the health top-off reminder honors this flag.
--- @param topoffPct number|nil  the player's top-off threshold percent. Passed in rather
---   than read here for the same reason as offerTopoff: this module never touches the
---   profile. nil falls back to the default 80% threshold.
--- @param offerStealth boolean|nil  include the stealth reminder (precombatBuffs.stealth).
function PrecombatEngine.GetMissingClassBuffs(offerTopoff, topoffPct, offerStealth, settings)
    local now = GetTime()
    if cachedClassBuffs and (now - cachedClassBuffsAt) < 0.5 then
        return cachedClassBuffs
    end
    -- Mid-application hold: the moment a poison/imbue CAST starts, AC's demand pointer
    -- moves on to its next reveal, but the state it left won't settle until the cast
    -- lands and the aura updates. Recomputing during the cast surfaces that transient -
    -- a third poison flashing while the second is still applying - so serve the answer
    -- from before the cast began and recompute when it resolves (lands OR is cancelled;
    -- either way UnitCastingInfo goes quiet and the next call falls through). Bounded by
    -- the cast itself, so a hold can never outlive the confusion it hides.
    if cachedClassBuffs and CastingMaintainedBuff() then
        cachedClassBuffsAt = now   -- keep the cache warm for the cast's duration
        return cachedClassBuffs
    end
    local out = {}
    -- Which spell (if any) this pass offered as the health top-off, so the renderer can tell it
    -- apart from the poisons/imbues alongside it and drive its alpha from the health curve.
    -- Cleared on RECOMPUTE only: an early return from the cache above must keep the value that
    -- produced that cache, or the cue would blink off for the rest of the cache window.
    PrecombatEngine.offeredTopoffHeal = nil
    local groups = (not InCombatLockdown()) and SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS
    local class = groups and select(2, UnitClass("player"))
    groups = class and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    local allGroups = groups
    if groups then
        local matching = {}
        for _, group in ipairs(groups) do
            if PreparationMatches(group) then matching[#matching + 1] = group end
        end
        groups = matching
    end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    -- 12.0.7: in aura-restricted contexts the by-ID probe returns nil for secret-flagged
    -- auras (RequiresNonSecretAura), so every class buff would look lapsed - offer nothing.
    local restricted = BlizzardAPI and BlizzardAPI.AreAurasSecret()
    if groups and get and not restricted then
        -- AC's live demand, from the strongest source available:
        --   1. GetAnyNextCastSpell - the include-hidden API read. The visible-only
        --      variants skip spells with no action-bar button, and poisons rarely
        --      have one, so they'd report the demand as "nothing" (observed on Sub).
        --   2. The queue's position 1, when plain (it is out of combat) - the very
        --      icon the player sees frozen, so deferring to it can never disagree
        --      with what's on screen.
        local nextCast = BlizzardAPI and BlizzardAPI.GetAnyNextCastSpell
            and BlizzardAPI.GetAnyNextCastSpell()
        if not nextCast then
            local SQ = LibStub("JustAC-SpellQueue", true)
            local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
            local head = type(queue) == "table" and queue[1] or nil
            if head and not (issecretvalue and issecretvalue(head)) then nextCast = head end
        end
        if nextCast then nextCast = R1(nextCast) end
        local rotation = BlizzardAPI and BlizzardAPI.GetRotationSpells
            and BlizzardAPI.GetRotationSpells()
        -- AC surfaces its maintained-buff demands ONE at a time through the demand
        -- probe, and the rotation list can't break the tie (it carries every member
        -- the spec can use, not a preference). So while AC is demanding a member of
        -- ANY group, the picks for the OTHER groups are still hidden behind that
        -- demand - and offering our own default in that window is a trap: apply it,
        -- and AC's next reveal freezes on a member we just displaced. Those groups
        -- HOLD instead; each applied demand reveals the next group's pick.
        local pendingDemand = false
        if nextCast then
            for _, grp in ipairs(groups) do
                for _, id in ipairs(grp.group) do
                    if nextCast == id then pendingDemand = true; break end
                end
                if pendingDemand then break end
            end
            -- A demanded weapon IMBUE must hold the group fallbacks exactly like a
            -- demanded group member. Imbues live outside the aura groups (weapon
            -- enchants), so without this the shield default could fire while AC's
            -- shield pick is still hidden behind the imbue demand - the same
            -- displacement trap the hold exists for. The imbue itself is offered
            -- by the enchant tail below, so holding here hides nothing.
            if not pendingDemand and SpellDB and SpellDB.WEAPON_ENCHANT_SPELLS
               and SpellDB.WEAPON_ENCHANT_SPELLS[nextCast] then
                pendingDemand = true
            end
        end
        for _, grp in ipairs(groups) do
            local active, aura, activeAuraID, latchedActive
            local groupKnown = true
            for _, spellID in ipairs(grp.group) do
                -- Received group buffs and alternate ranks can be active even when
                -- their cast is not learned. Cast knowledge gates offers, not detection.
                local a, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", spellID)
                local detectedAuraID = spellID
                if not known then groupKnown = false; break end
                -- A buff that applies a per-class sub-aura instead of its own cast id
                -- is invisible to the cast-id probe. Forever rank families associate
                -- each aura with its own cast member; legacy shared families retain
                -- their group-wide detection semantics.
                local memberAuraIDs = grp.memberAuraIDs and grp.memberAuraIDs[spellID]
                local auraIDs = memberAuraIDs or grp.auraIDs
                if not a and auraIDs then
                    for _, auraID in ipairs(auraIDs) do
                        a, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", auraID)
                        if not known then groupKnown = false; break end
                        if a then detectedAuraID = auraID; break end
                    end
                end
                if not groupKnown then break end
                if a then active, aura, activeAuraID = spellID, a, detectedAuraID; break end
                -- Applied-latch: the cast landed a moment ago but the aura hasn't
                -- registered yet. Treat as active with UNKNOWN timing (aura nil -
                -- IsLapsing answers false), so the group goes quiet the instant the
                -- cast completes instead of a clickable beat later.
                if IsFreshlyApplied(spellID) then
                    active, latchedActive = spellID, true
                    break
                end
            end
            local acPick = groupKnown and ACPickInGroup(nextCast, rotation, grp.group)
            -- While the active member is FRESHLY APPLIED, a differing AC demand is stale
            -- by definition - the demand API settles a few seconds behind the cast we
            -- just watched land (and behind Blizzard's own visible slot), and offering
            -- its member in that window is the sibling flash again, from the other side.
            -- Ask the latch DIRECTLY, not just latchedActive: when the aura registers
            -- faster than the demand settles (the common order right after a reload),
            -- `active` comes from the aura probe and latchedActive stays unset - the
            -- gate must hold in both orders. If AC still demands a different member
            -- once the grace lapses, that is a genuine wrong-member and it fires.
            if groupKnown and active and not grp.preparation and acPick and acPick ~= active
               and not (latchedActive or IsFreshlyApplied(active)) then
                -- The WRONG member is up: the assisted rotation runs a different one, and
                -- the active buff doesn't satisfy it, so AC's queue slot stays frozen on
                -- its pick no matter how fresh the current buff is. Offer AC's member -
                -- applying it replaces the active one and unfreezes the recommendation.
                out[#out + 1] = KnownClassBuff(acPick)
            elseif groupKnown and active then
                local refresh
                if grp.preparation then
                    refresh = PreparationRefreshSpell(grp, aura, activeAuraID)
                elseif IsLapsing(aura) then
                    refresh = KnownClassBuff(active)
                end
                local offered = refresh ~= nil
                if offered then out[#out + 1] = refresh end
                -- Group buff the player already has, but a party member is missing it
                -- (joined late, released, or was out of range when it went out). One
                -- re-cast covers everyone, so offer it even though the player's own
                -- copy is nowhere near lapsing.
                -- latchedActive also blocks the party recast: the cast that just landed
                -- covered the party too, and THEIR auras lag the same server beat.
                local activeAuras = (grp.memberAuraIDs and grp.memberAuraIDs[active])
                    or grp.auraIDs or grp.group
                if not offered and not grp.preparation and grp.raidWide and not latchedActive
                   and PartyMemberMissingBuff(active, activeAuras) then
                    out[#out + 1] = KnownClassBuff(active)
                end
            elseif groupKnown then
                -- Missing entirely (lapsed/cancelled): defer to the assisted rotation's
                -- pick; the queue-scan/default fallbacks only run when NO AC demand is
                -- pending in another group (see pendingDemand above) - otherwise this
                -- group holds until the chain reveals its pick.
                local pick = acPick
                if not pick and not pendingDemand then
                    local default = grp.default
                    if grp.defaultByTree then
                        local rotationImport = LibStub("JustAC-RotationImport", true)
                        local tree = rotationImport and rotationImport.GetForeverTree
                            and rotationImport.GetForeverTree()
                        default = grp.defaultByTree[tree] or default
                    end
                    pick = HighestQueuedInGroup(grp.group) or default
                    if not pick or not KnownClassBuff(pick) then
                        for _, member in ipairs(grp.group) do
                            if KnownClassBuff(member) then pick = member; break end
                        end
                    end
                end
                local knownPick = pick and KnownClassBuff(pick)
                if knownPick and (not grp.preparation or PreparationReady(knownPick)) then
                    out[#out + 1] = knownPick
                end
            end
        end

    end

    -- ENGINE-KNOWN group buffs the curated table does not cover (12.1.0+).
    -- C_CooldownViewer.GetGroupBuffItems is Blizzard's own registry, so a class buff
    -- added or reworked in a patch appears here without a data update. Kept strictly
    -- ADDITIVE - the curated groups above run first and own anything they claim -
    -- because a GroupBuffItem names only its cast id and carries no aura FAMILY, so
    -- detection for it is the plain by-id probe and nothing more.
    -- Skips hideByDefault entries: Blizzard de-emphasises those deliberately.
    --
    -- OUTSIDE the `groups` block on purpose. A class with NO curated entry is exactly
    -- the case this registry exists to cover, and nesting it under `groups` would
    -- have skipped precisely those classes - the gap it was added to close.
    -- `get`/`restricted` are still required: without a readable aura probe every buff
    -- reads as missing and we would nag for buffs already up.
    local engineBuffs = (not InCombatLockdown()) and get and not restricted
        and BlizzardAPI and BlizzardAPI.GetGroupBuffItems and BlizzardAPI.GetGroupBuffItems()
    if engineBuffs then
        local covered = {}
        for _, grp in ipairs(allGroups or {}) do
            for _, id in ipairs(grp.group) do covered[id] = true end
            for _, id in ipairs(grp.auraIDs or {}) do covered[id] = true end
        end
        -- Blizzard's registry is broader than "maintainable buff" (user-confirmed live on
        -- a Holy Priest, which got its whole registry offered at full health): it also
        -- carries group SAVE cooldowns (a raid heal channel, an external) and even known
        -- PASSIVES - isKnown answers true for those, and so does IsPlayerSpell. Neither
        -- is a precombat offer. The registry item carries no discriminating field, so:
        --   * passives are refused outright;
        --   * anything with a real cooldown is refused - a buff you keep up between
        --     pulls has none, a group save has minutes. GetSpellBaseCooldown is plain
        --     out of combat, which is the only place this block runs.
        for i = 1, #engineBuffs do
            local it = engineBuffs[i]
            if it.isKnown and not it.hideByDefault and not covered[it.spellID]
               and IsPlayerSpell(it.spellID) then
                local aura, known = SafeAuraCall(get, "GetPlayerAuraBySpellID", it.spellID)
                if known and not aura
                   and not (BlizzardAPI and BlizzardAPI.IsPassiveSpell and BlizzardAPI.IsPassiveSpell(it.spellID)) then
                    local cdMs = GetSpellBaseCooldown and GetSpellBaseCooldown(it.spellID)
                    if not (cdMs and not (issecretvalue and issecretvalue(cdMs)) and cdMs > 60000) then
                        out[#out + 1] = it.spellID
                    end
                end
            end
        end
    end
    -- Weapon preparation: a temp weapon ENCHANT, not a player aura, so it can't
    -- ride the group loop above. Suggest the known imbue while the main hand is bare or the
    -- enchant is inside the refresh window - the same read IsCategorySatisfied uses for oils.
    if not InCombatLockdown() then
        local imbue = KnownWeaponImbue()
        if imbue and not WeaponEnchantHolds(0, true) and not IsFreshlyApplied(imbue)
           and PreparationReady(imbue) then
            out[#out + 1] = imbue
        end
        -- Off-hand imbue (dual-imbue specs, i.e. Enhancement). Never collides with the
        -- main-hand offer: that one is Windfury whenever Windfury is known, which is
        -- exactly the condition that makes Flametongue an off-hand cast (see OffHandImbue).
        local ohImbue = OffHandImbue()
        if ohImbue and not WeaponEnchantHolds(1, true) and not IsFreshlyApplied(ohImbue)
           and PreparationReady(ohImbue) then
            out[#out + 1] = ohImbue
        end
    end
    -- Recuperate (cross-class OOC self-heal): a maintained buff whose "missing"
    -- condition is health-based instead of aura-expiry - offer it while the player
    -- is below the comfortable threshold and its heal-over-time isn't running.
    -- (1231411 also applies its own 30s active aura, hence the second probe.)
    -- A procced heal (free instant Regrowth and the like) is the better way to
    -- top up after combat and already surfaces with its proc glow - step aside.
    local function HasProccedHeal()
        local ABS = LibStub("JustAC-ActionBarScanner", true)
        local procs = ABS and ABS.GetDefensiveProccedSpells and ABS.GetDefensiveProccedSpells()
        if not procs or not SpellDB.IsHealingSpell then return false end
        for i = 1, #procs do
            if SpellDB.IsHealingSpell(procs[i]) then return true end
        end
        return false
    end
    -- Gate on the HoT (1231418) ONLY - deliberately not the 30s active aura
    -- (1231411): a damage tick interrupts the heal but leaves the active aura
    -- (and its animation) running, and that is exactly when a re-cast must be
    -- offered. The click layer cancels the stale aura before re-casting.
    -- Emergency and optional top-off remain independent of automatic 70% recovery:
    --   * EMERGENCY (<= ~35%): ALWAYS on, even with the top-off toggle OFF. The low-health
    --     vignette is never secret (and a low exact read counts too), so a critical-health
    --     player is always shown the heal.
    --   * TOP-OFF: exact health or the selected threshold's confirmed gate only.
    --     Below-full, regen and party-alert signals do not prove this threshold.
    if not InCombatLockdown() and not restricted and get then
        local preference = settings and settings.healthRecovery
        local healPreference
        if type(preference) == "number" then healPreference = preference end
        local heal = PrecombatEngine.GetReadyRecoveryHeal(healPreference)
        local recoveryHurt = SpellDB and SpellDB.IsForever() and preference ~= "items"
            and PrecombatEngine.IsRecoveryEnabled(settings, "healthRecovery")
            and BlizzardAPI and BlizzardAPI.IsUnitHealthBelow
            and BlizzardAPI.IsUnitHealthBelow("player", RECOVERY_HEALTH_PCT) == true
        local hurt = recoveryHurt
        if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
            local pct, estimated = BlizzardAPI.GetPlayerHealthPercentSafe()
            if pct and pct <= LOW_HEALTH_PCT then
                hurt = true                                  -- emergency floor: always on
                notFullSince = 0                             -- onset timer is the gate path's alone
            elseif offerTopoff then
                if pct and not estimated then
                    hurt = hurt or pct < (topoffPct or RECUPERATE_HEALTH_PCT)
                    notFullSince = 0
                else
                    -- ONE QUESTION: are you below your top-off threshold? The
                    -- ENGINE answers it - IsUnitHealthBelow encodes the threshold
                    -- as a curve and returns only a plain yes/no, or unknown.
                    local below
                    if BlizzardAPI.IsUnitHealthBelow then
                        below = BlizzardAPI.IsUnitHealthBelow(
                            "player", topoffPct or RECUPERATE_HEALTH_PCT)
                    end
                    if below == true then
                        if notFullSince == 0 then notFullSince = now end
                        hurt = hurt or (now - notFullSince) >= TOPOFF_ONSET_SECONDS
                    else
                        notFullSince = 0
                    end
                end
            end
        end
        -- Same secret-boolean hazard as the party probes above: UnitIsDeadOrGhost can come
        -- back secret, and a bare truthiness test on it throws. "Not KNOWN to be dead" is
        -- the right fail direction here - a secret must not swallow a critical-health cue.
        if hurt and heal and ReadableBool(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) ~= true
            and (recoveryHurt or not HasProccedHeal()) then
            out[#out + 1] = heal
            PrecombatEngine.offeredTopoffHeal = heal
        end
    end
    -- Stealth reminder, last: entering stealth is the final step before a pull.
    local stealth = offerStealth and not InCombatLockdown() and StealthReminderSpell()
    if stealth then out[#out + 1] = stealth end
    cachedClassBuffs, cachedClassBuffsAt = out, now
    return out
end

-- Are out-of-combat buff offers live right now? The defensive queue builds under exactly
-- this gate, and the DPS queue asks the same question so it can drop an ability that is
-- already sitting one cluster over as a clickable buff icon. One gate, two surfaces - they
-- cannot disagree about whether the offer exists.
function PrecombatEngine.IsOfferingNow(profile)
    if not profile or InCombatLockdown() then return false end
    local def, pre = profile.defensives, profile.precombatBuffs
    return (def and def.enabled and pre and pre.enabled ~= false) and true or false
end

local function DefensiveIcons()
    local addon = BlizzardAPI and BlizzardAPI.GetAddon and BlizzardAPI.GetAddon()
    return addon and addon.defensiveIcons
end

-- Is this spell being offered on screen, right now, as a pre-combat buff? Asked of the
-- rendered icons rather than of the checklist, because only the icons know whether the
-- offer is actually VISIBLE - the cluster can be hidden with the rest of the panel, and the
-- queue is capped at maxIcons, so "we would like to offer this" is not the same claim. An
-- icon carries isPrecombatBuff only while shown out of combat by the pre-combat path (the
-- renderer clears it on hide), and IsVisible answers false when an ancestor is hidden.
-- Only spells are asked about: the consumable offers are items, which never reach the DPS
-- queue. Reads one frame behind the DPS build, which is the safe direction - a buff that
-- has just lapsed is listed in both for one pass, never dropped from both.
function PrecombatEngine.IsOfferedNow(spellID, profile)
    if not spellID or not PrecombatEngine.IsOfferingNow(profile) then return false end
    local icons = DefensiveIcons()
    if not icons then return false end
    local preparation = SpellDB and SpellDB.PREPARATION_BUFF_MEMBERS
    local group = preparation and preparation[spellID]
    for i = 1, #icons do
        local icon = icons[i]
        if icon and icon.isPrecombatBuff and icon.spellID
           and (R1(icon.spellID) == R1(spellID)
                or (group and preparation[icon.spellID] == group))
           and icon:IsVisible() then
            return true
        end
    end
    return false
end
