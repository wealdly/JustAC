-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Defensive/Item State, Health Detection, Target Analysis, Shapeshift Forms
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SpellQuery.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-StateHelpers", 7
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local math_max         = math.max
local math_min         = math.min
local GetTime          = GetTime
local GetItemCount     = GetItemCount
local GetItemCooldown  = GetItemCooldown
local UnitClassification = UnitClassification ---@diagnostic disable-line: undefined-global
local UnitIsUnit         = UnitIsUnit         ---@diagnostic disable-line: undefined-global
local UnitCreatureType   = UnitCreatureType   ---@diagnostic disable-line: undefined-global
local UnitIsMinion       = UnitIsMinion       ---@diagnostic disable-line: undefined-global
local UnitIsCrowdControlled = UnitIsCrowdControlled ---@diagnostic disable-line: undefined-global
local pcall          = pcall
local UnitHealth     = UnitHealth
local UnitHealthMax  = UnitHealthMax
local UnitExists     = UnitExists
local UnitIsDead     = UnitIsDead    ---@diagnostic disable-line: undefined-global
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret
local C_Secrets     = C_Secrets
local UnitGUID      = UnitGUID      ---@diagnostic disable-line: undefined-global
local strsplit      = strsplit       ---@diagnostic disable-line: undefined-global
local wipe          = wipe

-- Pre-built boss unit tokens (avoids string concat on hot path)
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local GetNumShapeshiftForms = GetNumShapeshiftForms
local GetShapeshiftFormInfo = GetShapeshiftFormInfo

--------------------------------------------------------------------------------
-- Defensive Spell State Helper (consolidates common validation pattern)
--------------------------------------------------------------------------------

-- Cache for RedundancyFilter lookup (lazy-loaded)
local cachedRedundancyFilter = nil
local function GetRedundancyFilter()
    if cachedRedundancyFilter == nil then
        cachedRedundancyFilter = LibStub("JustAC-RedundancyFilter", true) or false
    end
    return cachedRedundancyFilter or nil
end

-- Check defensive spell usability in one call (avoids repeated API lookups)
-- Returns: isUsable, isRedundant, isProcced
-- isUsable = spell is known AND NOT redundant (buff already active).
-- Cooldown gating is handled by the caller via IsSpellReady / IsSpellUsable.
function BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
    if not spellID or spellID == 0 then
        return false, false, false
    end

    -- Check if spell is known/available
    if not BlizzardAPI.IsSpellAvailable(spellID) then
        return false, false, false
    end

    -- Check if procced (instant/free cast available)
    local isProcced = BlizzardAPI.IsSpellProcced(spellID)

    -- Check redundancy (buff already active — reliable, based on UnitBuff not cooldown)
    local RedundancyFilter = GetRedundancyFilter()
    local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant(spellID, profile, true) or false
    if isRedundant then
        return false, true, isProcced
    end

    return true, false, isProcced
end

--------------------------------------------------------------------------------
-- Defensive Item State Helper (mirrors CheckDefensiveSpellState for items)
--------------------------------------------------------------------------------

-- Check defensive item usability in one call
-- Returns: isUsable, hasItem, onCooldown
-- isUsable = hasItem AND NOT onCooldown
function BlizzardAPI.CheckDefensiveItemState(itemID, profile)
    if not itemID or itemID == 0 then
        return false, false, false
    end

    -- Check if player has the item in bags/inventory
    local count = GetItemCount(itemID) or 0
    if count == 0 then
        return false, false, false
    end

    -- Check cooldown (fail-open: if values are secret, assume NOT on cooldown)
    local start, duration = GetItemCooldown(itemID)
    local onCooldown = false
    if start and duration then
        if not IsSecretValue(start) and not IsSecretValue(duration) then
            onCooldown = start > 0 and duration > 1.5
        end
    end

    if onCooldown then
        return false, true, true
    end

    return true, true, false
end

--------------------------------------------------------------------------------
-- Aura Active Detection (used by item→aura linking in defensive queue)
--------------------------------------------------------------------------------

--- Check if a specific aura (by spellID) is active on a unit.
--- Uses RedundancyFilter's combat-safe instance map (resolves secret aura IDs).
--- Fail-open: returns false if aura status cannot be determined.
--- @param unit string  Unit token (typically "player")
--- @param auraSpellID number  The spellID of the aura to check
--- @return boolean  true if the aura is currently active
function BlizzardAPI.IsAuraActive(unit, auraSpellID)
    if not auraSpellID or auraSpellID == 0 then return false end

    -- Prefer RedundancyFilter's aura cache (combat-safe, maintains instance maps)
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    if RedundancyFilter and RedundancyFilter.GetAuraCache then
        local cache = RedundancyFilter.GetAuraCache()
        if cache and cache.byID then
            return cache.byID[auraSpellID] == true
        end
    end

    -- Fallback: direct scan (works OOC when aura fields are readable)
    if unit and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not data then break end
            if data.spellId and not IsSecretValue(data.spellId) and data.spellId == auraSpellID then
                return true
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Low Health Detection via LowHealthFrame (works when UnitHealth() is secret)
--------------------------------------------------------------------------------

function BlizzardAPI.GetLowHealthState()
    local frame = LowHealthFrame ---@diagnostic disable-line: undefined-global
    if not frame then
        return false, false, 0
    end

    local isShown = frame:IsShown()
    if not isShown then
        return false, false, 0
    end

    -- Alpha indicates severity (~0.3-0.5 at 35%, ~0.8-1.0 at critical)
    local alpha = frame:GetAlpha() or 0
    local isCritical = alpha > 0.5

    return true, isCritical, alpha
end

--------------------------------------------------------------------------------
-- Target CC Immunity Detection
-- Shared by UIRenderer and UINameplateOverlay so both panels always agree.
-- Refreshed on PLAYER_TARGET_CHANGED and PLAYER_REGEN_ENABLED.
-- UnitCreatureType is SECRET in combat; cached out of combat only.
--------------------------------------------------------------------------------

-- Creature type cache for CC immunity detection (Mechanical / Totem).
--
-- HARD LIMITATION (verified via in-game /script testing, 2026-02-23):
--   In WoW 12.0+, BOTH UnitCreatureType() AND UnitGUID() return secret values
--   while in combat. There is no in-combat API that can identify mob type on a
--   *fresh* target. All known alternative approaches have been evaluated:
--
--   UnitCreatureType()  — SECRETED in combat. Primary data source, unusable.
--   UnitGUID()          — SECRETED in combat. GUID-keyed cache is not viable.
--   UnitCreatureFamily()— NOT secreted, but only distinguishes Beast from
--                         everything else (nil for Mechanical/Undead/etc.).
--   UnitClassification()— NOT secreted. Used for worldboss/boss slot detection.
--   UnitIsUnit(boss1-5) — NOT secreted. Used for boss slot detection.
--
-- DESIGN CONSEQUENCE:
--   The cache is populated out of combat (TARGET_CHANGED, PLAYER_REGEN_ENABLED).
--   If the player tabs to a NEW target mid-combat (not yet cached), the creature
--   type is unknowable and IsTargetCCImmune() returns false (fail-open: assume
--   CC-able). This is intentional — showing a CC suggestion on a Mechanical mob
--   is a minor UX annoyance; suppressing CC on a valid target would be harmful.
--
-- UPDATE (in-game verified 2026-06-28, build 12.0.7): UnitCreatureType("target") is
-- in fact READABLE in combat for resolved targets — targeting resolves the unit, so
-- the type reads back mid-combat (the Feb-2026 finding no longer holds for the target).
-- UnitName is likewise readable in combat. The secret system is volatile (it loosened
-- since Feb 2026), so as a hedge we cache the type keyed by the readable UnitName
-- whenever it's available — a pre-warmed fallback if Blizzard ever re-secrets it.
-- Resolution order (BlizzardAPI.GetTargetCreatureTypeID below): live read -> name
-- cache -> fail-open (assume CC-able).

-- Persistent, bounded name->creatureTypeID cache (account-wide via JustACGlobal).
-- Flat numeric values; hard cap that wipes + re-warms so it never grows without bound.
local NAME_TYPE_CACHE_CAP = 1500

-- Localized creature-type name -> numeric ID, built once from C_CreatureInfo
-- (locale-correct — no hardcoded type strings).
local creatureTypeByName = nil
local function BuildCreatureTypeMap()
    if creatureTypeByName then return end
    creatureTypeByName = {}
    if C_CreatureInfo and C_CreatureInfo.GetCreatureTypeIDs and C_CreatureInfo.GetCreatureTypeInfo then
        for _, tid in ipairs(C_CreatureInfo.GetCreatureTypeIDs()) do
            local info = C_CreatureInfo.GetCreatureTypeInfo(tid)
            if info and info.name then creatureTypeByName[info.name] = tid end
        end
    end
end

local function StoreNameType(name, typeID)
    if not name or not typeID then return end
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    local c = g.creatureTypeCache
    if not c then c = {}; g.creatureTypeCache = c; g.creatureTypeCacheN = 0 end
    if c[name] == typeID then return end
    if c[name] == nil then
        if (g.creatureTypeCacheN or 0) >= NAME_TYPE_CACHE_CAP then
            wipe(c); g.creatureTypeCacheN = 0   -- bounded: wipe and re-warm
        end
        g.creatureTypeCacheN = (g.creatureTypeCacheN or 0) + 1
    end
    c[name] = typeID
end

-- Instance-level CC immunity cache (keyed by NPC ID from GUID).
-- UnitGUID() is SECRET in combat, so NPC ID is only populated when a target is
-- acquired out of combat (pre-pull) or on PLAYER_REGEN_ENABLED.  When a CC
-- failure is detected and the NPC ID is known, that mob TYPE is remembered for
-- the rest of the instance — all future mobs with the same NPC ID are suppressed
-- without needing to re-learn.
local ccImmuneNPCIDs = {}           -- [npcID] = true; persists across pulls
local currentTargetNPCID = nil      -- NPC ID from GUID when readable

--- Extract NPC ID from a WoW GUID string.
--- Creature GUIDs: "Creature-0-SERVERID-INSTANCEID-ZONEID-NPCID-SPAWNUID"
--- Vehicle GUIDs:  "Vehicle-0-..." (same layout)
--- Returns tonumber(npcID) or nil for non-creature GUIDs (Player, Pet, etc.).
local function ExtractNPCID(guid)
    if not guid then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
    return nil
end

-- CC-failure learning: if we suggested a CC and the target didn't become
-- crowd-controlled, mark the current target as CC-immune for the rest of
-- combat.  Uses UnitIsCrowdControlled() which is NeverSecret (verified
-- 2026-02-24).  Reset on PLAYER_TARGET_CHANGED and PLAYER_REGEN_ENABLED.
local CC_FAILURE_CHECK_DELAY = 0.4  -- seconds after CC cast to check result
local ccCastTime = 0                -- GetTime() when player cast a CC
local ccFailureObserved = false     -- true = current target resisted/immune
local ccFailureChecked  = false     -- true = we already checked this cast

function BlizzardAPI.RefreshTargetCreatureType()
    -- Clear per-target state first; a stale NPC ID is worse than nil (nil fails open).
    currentTargetNPCID = nil
    -- Also reset CC-failure learning on target switch — the new target might
    -- be CC-able even if the previous one wasn't.
    ccCastTime = 0
    ccFailureObserved = false
    ccFailureChecked  = false
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and not IsSecretValue(ct) then
        -- Pre-warm the persistent name->type cache while the type is readable, keyed
        -- by the (also-readable) UnitName — insurance if the type is ever re-secreted.
        BuildCreatureTypeMap()
        local name = UnitName and UnitName("target")
        if name and not IsSecretValue(name) then
            StoreNameType(name, creatureTypeByName[ct])
        end
    end
    -- Extract NPC ID from GUID (only readable out of combat; secret in combat).
    -- Used to persist CC immunity per mob TYPE across pulls within an instance.
    local guid = UnitGUID and UnitGUID("target")
    if guid and not IsSecretValue(guid) then
        currentTargetNPCID = ExtractNPCID(guid)
    end
end

--- Resolve the current target's creature type ID (numeric, locale-independent), or nil.
--- Order: live UnitCreatureType when readable (resolved targets, even in combat — and
--- caches it by name); else the persistent name cache (UnitName stays readable when the
--- type is secret); else nil so the caller fails open. See the creature-type notes above.
function BlizzardAPI.GetTargetCreatureTypeID()
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and not IsSecretValue(ct) then
        BuildCreatureTypeMap()
        local id = creatureTypeByName[ct]
        if id then
            local name = UnitName and UnitName("target")
            if name and not IsSecretValue(name) then StoreNameType(name, id) end
        end
        return id
    end
    -- Type secret/unavailable: fall back to the name cache.
    local name = UnitName and UnitName("target")
    if name and not IsSecretValue(name) then
        local g = _G.JustACGlobal
        if g and g.creatureTypeCache then return g.creatureTypeCache[name] end
    end
    return nil
end

-- spellID -> allowed-creature-type bitmask (bit (typeID-1) set = type allowed), from
-- SpellTargetRestrictions.TargetCreatureType. Only the type-restricted subset of the CC
-- spells we actually suggest; every other suggested CC is a universal stun (no entry =
-- no restriction). Regenerate per patch by intersecting CLASS_INTERRUPT_DEFAULTS cc
-- spells with non-zero TargetCreatureType. Verified: 118 = Dragonkin/Demon/Giant/Undead/
-- Humanoid (blocks Beast/Elemental/Mechanical/Critter).
local CC_TYPE_MASK = {
    [20066] = 118,   -- Repentance
}

--- True unless the target's creature type is KNOWN and the CC spell's type restriction
--- excludes it. Fail-open (unknown type or unrestricted spell -> true) so we never
--- suppress a CC we can't prove is invalid.
function BlizzardAPI.IsCCSpellTypeValid(spellID)
    local mask = CC_TYPE_MASK[spellID]
    if not mask then return true end
    local tid = BlizzardAPI.GetTargetCreatureTypeID()
    if not tid then return true end
    return bit.band(mask, bit.lshift(1, tid - 1)) ~= 0
end

--- Called when the player successfully casts a CC spell on the current target.
--- Starts the CC-failure detection timer so we can check if the CC took effect.
function BlizzardAPI.NotifyCCCastOnTarget()
    ccCastTime = GetTime()
    ccFailureChecked = false
    -- Don't clear ccFailureObserved here — if we already know this target is
    -- immune, keep that knowledge.
end

--- Called on PLAYER_REGEN_ENABLED to reset per-target CC-failure learning for
--- the next combat session.  Instance-level ccImmuneNPCIDs is NOT cleared here
--- — it persists across pulls until the player changes zone.
function BlizzardAPI.ResetCCFailureLearning()
    ccCastTime = 0
    ccFailureObserved = false
    ccFailureChecked  = false
end

--- Called on PLAYER_REGEN_ENABLED BEFORE ResetCCFailureLearning to backfill the
--- instance NPC ID cache.  If a CC failure was observed on a target whose NPC ID
--- wasn't known during combat (tab-targeted mid-fight), and the player is still
--- targeting that mob when combat ends, we can now read GUID and persist the
--- immunity for future pulls.
function BlizzardAPI.BackfillCCImmunity()
    if not ccFailureObserved then return end
    if currentTargetNPCID then
        -- NPC ID was known during combat — already persisted in IsTargetCCImmune
        return
    end
    -- Combat just ended; GUID is readable again. If the player is still
    -- targeting the mob that resisted CC, extract its NPC ID.
    local guid = UnitGUID and UnitGUID("target")
    if guid and not IsSecretValue(guid) then
        local npcID = ExtractNPCID(guid)
        if npcID then
            ccImmuneNPCIDs[npcID] = true
        end
    end
end

--- Clear the instance-level CC immunity cache.  Called on PLAYER_ENTERING_WORLD
--- (zone changes, loading screens) so stale data from a previous instance or
--- zone doesn't bleed into the next one.
function BlizzardAPI.ResetInstanceCCCache()
    wipe(ccImmuneNPCIDs)
end

function BlizzardAPI.IsTargetCCImmune()
    -- 1) World bosses and boss-frame mobs are always CC-immune.
    --    UnitClassification: NeverSecret (no SecretWhenUnitIdentityRestricted).
    --    UnitIsUnit: NeverSecret for boss1-5 comparison (verified 2026-02-23).
    if UnitClassification("target") == "worldboss" then return true end
    for i = 1, 5 do
        if UnitIsUnit("target", BOSS_UNITS[i]) then return true end
    end

    -- 2) Minions (pets, totems, treants, guardians) are CC-immune.
    --    UnitIsMinion: NeverSecret (no SecretWhenUnitIdentityRestricted,
    --    verified 2026-02-24).
    if UnitIsMinion and UnitIsMinion("target") then return true end

    -- NOTE: UnitLevel == -1 (skull mobs) intentionally NOT checked here.
    -- Many skull-level mobs (open-world rares, M+ elites) are fully CC-able.
    -- Actual bosses are already caught by worldboss + boss1-5 checks above.
    --
    -- NOTE: Mechanical creature type intentionally NOT checked here.
    -- Mechanicals are immune to creature-type-restricted CCs (Sap, Polymorph,
    -- Hex), but universal stuns (Kidney Shot, Cheap Shot, HoJ, Leg Sweep)
    -- work on them. Our CC lists contain universal stuns.

    -- 3) Instance-level NPC ID cache: if we previously learned that this mob
    --    TYPE is CC-immune (on a prior pull), suppress CC immediately.
    if currentTargetNPCID and ccImmuneNPCIDs[currentTargetNPCID] then
        return true
    end

    -- 4) Per-target CC-failure learning: if we cast a CC on this target and it
    --    didn't take effect, treat the target as CC-immune.  Uses
    --    UnitIsCrowdControlled (NeverSecret, verified 2026-02-24).
    --    Early-out: skip the timer check if no CC is pending.
    if ccFailureObserved then return true end
    if ccCastTime > 0 and not ccFailureChecked
        and (GetTime() - ccCastTime) >= CC_FAILURE_CHECK_DELAY then
        ccFailureChecked = true
        if UnitIsCrowdControlled then
            local isCCd = UnitIsCrowdControlled("target")
            if IsSecretValue(isCCd) then
                -- Secret value — can't determine, fail-open
            elseif not isCCd then
                ccFailureObserved = true
                -- Persist to instance cache if NPC ID is known (target was
                -- acquired out of combat or NPC ID was populated earlier).
                if currentTargetNPCID then
                    ccImmuneNPCIDs[currentTargetNPCID] = true
                end
                return true
            end
        end
    end

    return false
end

--- Check whether the current target is worth interrupting at all.
--- Returns false for trivial targets (minus mobs, minions) where spending
--- any interrupt/CC cooldown is a waste.  All APIs used here are NeverSecret
--- in 12.0 combat (verified 2026-02-24).
---
--- Design: fail-open.  If anything errors, assume target IS worth interrupting.
function BlizzardAPI.IsTargetInterruptWorthy()
    -- "minus" mobs are trivial adds (e.g. Explosive affix, swarm adds).
    -- Not worth a 15-24s kick cooldown.
    if UnitClassification("target") == "minus" then return false end
    -- Minions are pets, totems, treants, guardians.  UnitIsMinion() is
    -- NeverSecret and covers the same ground as the secreted
    -- UnitCreatureType() Mechanical/Totem check — but works IN combat.
    if UnitIsMinion and UnitIsMinion("target") then return false end
    return true
end

--------------------------------------------------------------------------------
-- Player & Pet Health (moved from SpellQuery — consolidated with health helpers)
--------------------------------------------------------------------------------

-- UnitHealth/UnitHealthMax are SECRET in 12.0 combat — returns nil when secret.
function BlizzardAPI.GetPlayerHealthPercent()
    if not UnitExists("player") then return nil end

    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")

    -- 12.0+ fast path: skip per-value IsSecretValue() when no restrictions are active.
    -- C_Secrets.HasSecretRestrictions() is false out of combat (the common case).
    if C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() then
        if IsSecretValue(health) or IsSecretValue(maxHealth) then
            return nil
        end
    end
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

-- Pet health IS secret in 12.0 combat (PvE and PvP). Returns nil when secret.
-- This means pet heals only trigger out of combat. Pet rez/summon uses
-- GetPetStatus() instead, which relies on UnitIsDead/UnitExists (not secret).
function BlizzardAPI.GetPetHealthPercent()
    if not UnitExists("pet") then return nil end

    local ok, isDead = pcall(UnitIsDead, "pet")
    if ok then
        if IsSecretValue(isDead) then
            -- Can't determine dead status
        elseif isDead then
            return 0
        end
    end

    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")

    if IsSecretValue(health) or IsSecretValue(maxHealth) then
        return nil
    end
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

-- Returns pet status string: "dead", "missing", "alive", or nil (no pet class)
-- UnitExists and UnitIsDead are NOT secret — reliable in combat
-- Pet health IS secret in combat — use GetPetHealthPercent() for best-effort health
function BlizzardAPI.GetPetStatus()
    local ok, exists = pcall(UnitExists, "pet")
    if not ok or not exists then
        return "missing"
    end

    local ok2, isDead = pcall(UnitIsDead, "pet")
    if ok2 and isDead and not IsSecretValue(isDead) then
        return "dead"
    end

    return "alive"
end

-- Returns LowHealthFrame binary state: isLow (bool), isEstimate always true in combat.
-- In combat UnitHealth() is secret — only the LowHealthFrame binary (~35% threshold)
-- is reliable. Health percentages above 35% are indistinguishable in combat.
function BlizzardAPI.GetPlayerHealthPercentSafe()
    local exactPct = BlizzardAPI.GetPlayerHealthPercent()
    if exactPct then
        return exactPct, false
    end

    local isLow, isCritical, alpha = BlizzardAPI.GetLowHealthState()
    if isCritical then
        local pct = 20 - (alpha - 0.5) * 30
        return math_max(5, math_min(20, pct)), true
    elseif isLow then
        local pct = 35 - alpha * 30
        return math_max(20, math_min(35, pct)), true
    else
        return 100, true
    end
end

--------------------------------------------------------------------------------
-- Shapeshift form wrappers (pcall-safe; used by FormCache)
--------------------------------------------------------------------------------

--- Returns the number of shapeshift forms available, or 0 on error.
function BlizzardAPI.GetNumShapeshiftForms()
    local ok, result = pcall(GetNumShapeshiftForms)
    return ok and result or 0
end

--- Returns icon, active, castable, spellID for the given shapeshift form index.
--- Returns nil, nil, nil, nil on error.
function BlizzardAPI.GetShapeshiftFormInfo(index)
    local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, index)
    if ok then
        return icon, active, castable, spellID
    end
    return nil, nil, nil, nil
end

--------------------------------------------------------------------------------
-- Target cast interruptibility tracking (event-driven, NeverSecret)
--------------------------------------------------------------------------------
-- Three sources, combined for maximum compatibility with third-party cast-bar /
-- nameplate / unit-frame addons that may hide or replace the Blizzard cast bars:
--
--  1. UNIT_SPELLCAST_INTERRUPTIBLE / UNIT_SPELLCAST_NOT_INTERRUPTIBLE events
--     fire for mid-cast transitions (e.g. boss becoming immune). Event name
--     IS the data — real (non-secret) boolean.
--
--  2. UnitCastingInfo() / UnitChannelInfo() notInterruptible field, read
--     immediately in the UNIT_SPELLCAST_START handler. This catches casts
--     that START as non-interruptible (grey bar), which do NOT fire the
--     transition events. In 11.x this is a plain boolean; in 12.0 combat
--     it may be secret (fail-open in that case).
--
--  3. Cast bar visual inspection in UIRenderer (BorderShield / .Shield) as
--     a final fallback when the above are inconclusive.
--
-- Reset on: PLAYER_TARGET_CHANGED, UNIT_SPELLCAST_STOP, CHANNEL_STOP,
--           UNIT_SPELLCAST_FAILED, UNIT_SPELLCAST_INTERRUPTED
--------------------------------------------------------------------------------
local targetCastInterruptible = true   -- fail-open default
local targetCastInterruptKnown = false -- true once event provides definitive state
local targetCastActive = false         -- true when a cast/channel is in progress

local UnitCastingInfo  = UnitCastingInfo  ---@diagnostic disable-line: undefined-global
local UnitChannelInfo  = UnitChannelInfo  ---@diagnostic disable-line: undefined-global
local castEventFrame = nil

-- Resolve a notInterruptible flag. In 12.0 combat this is genuinely UNRESOLVABLE: every
-- candidate signal is a secret value or silent. Verified via /jac inspect castdiag (12.0.7):
--   • UnitCastingInfo notInterruptible / cast barType — secret (IsInterruptable() errors
--     when compared under our taint, on Blizzard's own frames too)
--   • the cast spellID from UNIT_SPELLCAST_START — secret (so no spell-keyed lookup)
--   • CastingBar BorderShield:IsShown() — returns a secret boolean (display state sealed too)
--   • UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE — fire only on mid-cast transitions,
--     not at cast start, so they don't establish the initial state
-- This is the secret-value system, not a UI-addon issue. For a secret value we return nil
-- and the caller fails open (assume interruptible). A plain boolean (out of combat / pre-12.0)
-- is returned as-is. The transition events above are still consumed where they do fire.
local function ResolveSecretBool(val)
    if val == nil then return nil end
    if not IsSecretValue(val) then return val end
    return nil  -- secret in combat: unresolvable, caller fails open
end

--- Probe the current target for an in-progress cast/channel and resolve its
--- notInterruptible flag.  Called on PLAYER_TARGET_CHANGED (to catch casts
--- already in progress that won't fire SPELLCAST_START for us).
local function ProbeTargetCast()
    local castName, notInt
    castName, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
    if not (IsSecretValue(castName) or castName) then
        castName, _, _, _, _, _, notInt = UnitChannelInfo("target")
        if not (IsSecretValue(castName) or castName) then
            return  -- No cast or channel on target
        end
    end
    targetCastActive = true
    local resolved = ResolveSecretBool(notInt)
    if resolved ~= nil then
        targetCastInterruptible = not resolved
        targetCastInterruptKnown = true
    else
        -- Unresolvable: fail-open, let downstream cascade handle it
        targetCastInterruptible = true
        targetCastInterruptKnown = false
    end
end

local function InitTargetCastTracking()
    if castEventFrame then return end
    castEventFrame = CreateFrame("Frame")

    -- Unit events filtered to "target" only — zero overhead for player/party casts
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    -- PLAYER_TARGET_CHANGED is a global event (not unit-filterable)
    castEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

    castEventFrame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            -- Event name IS the data (the event itself carries it) — never secret
            targetCastInterruptible = true
            targetCastInterruptKnown = true
        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            targetCastInterruptible = false
            targetCastInterruptKnown = true
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            -- New cast started. INTERRUPTIBLE/NOT_INTERRUPTIBLE events only
            -- fire for mid-cast transitions, NOT for initially non-interruptible
            -- casts. Read notInterruptible from the API immediately and resolve
            -- it through C++ if secret (addon-agnostic: no cast bar frame needed).
            targetCastActive = true
            local notInt
            if event == "UNIT_SPELLCAST_START" then
                _, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
            else
                _, _, _, _, _, _, notInt = UnitChannelInfo("target")
            end
            local resolved = ResolveSecretBool(notInt)
            if resolved ~= nil then
                targetCastInterruptible = not resolved
                targetCastInterruptKnown = true
            else
                -- Unresolvable: fail-open, let downstream cascade handle it
                targetCastInterruptible = true
                targetCastInterruptKnown = false
            end
        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED" then
            -- Cast ended — reset state
            targetCastActive = false
            targetCastInterruptKnown = false
            targetCastInterruptible = true
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- New target — probe for an existing cast on the new target so we
            -- detect mid-cast interruptibility without depending on a visible
            -- cast bar frame (addon-agnostic).
            targetCastActive = false
            targetCastInterruptKnown = false
            targetCastInterruptible = true
            ProbeTargetCast()
        end
    end)
end

--- Returns (isCasting, isInterruptible, isKnown)
---  isCasting:       true if a cast/channel event is active on the target
---  isInterruptible: true if the last INTERRUPTIBLE/NOT_INTERRUPTIBLE event
---                   said it was interruptible (fail-open default)
---  isKnown:         true if the state was set by a definitive event
---                   (false = initial cast start, event hasn't fired yet)
function BlizzardAPI.GetTargetCastInterruptState()
    return targetCastActive, targetCastInterruptible, targetCastInterruptKnown
end

--------------------------------------------------------------------------------
-- Secret-aware display sinks (12.0)
--------------------------------------------------------------------------------
-- These FORWARD a possibly-secret value into a Blizzard widget method that consumes it
-- for display without revealing it to us (the method is marked SecretArguments =
-- "AllowedWhenTainted"). We never read or branch on the value — the engine renders it.
-- The complete set of such sinks: SetAlphaFromBoolean / SetVertexColorFromBoolean (secret
-- booleans) and SetCooldownFromDurationObject (secret durations). This is how the addon can
-- reflect a secret bool visually (interruptibility, range, usability) without resolving it.

--- Drive region:SetAlphaFromBoolean from a (possibly secret) boolean, safely.
---   secret bool → forwarded to the sink (pcall-guarded; falls back to nilAlpha on error)
---   plain bool  → forwarded to the sink
---   nil         → region:SetAlpha(nilAlpha)
--- @param trueAlpha number   alpha when the boolean is true
--- @param falseAlpha number  alpha when the boolean is false
--- @param nilAlpha number|nil alpha when value is nil/unavailable (default falseAlpha)
function BlizzardAPI.SetAlphaFromSecretBool(region, value, trueAlpha, falseAlpha, nilAlpha)
    nilAlpha = nilAlpha or falseAlpha or 1
    if not (region and region.SetAlphaFromBoolean) then
        if region and region.SetAlpha then region:SetAlpha(nilAlpha) end
        return
    end
    if IsSecretValue(value) then
        if not pcall(region.SetAlphaFromBoolean, region, value, trueAlpha, falseAlpha) then
            region:SetAlpha(nilAlpha)
        end
    elseif value == nil then
        region:SetAlpha(nilAlpha)
    else
        region:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
    end
end

--- Drive an interrupt icon's alpha from the target cast's secret notInterruptible:
--- non-interruptible (or no active cast) → alpha 0; interruptible → shownAlpha. Works
--- regardless of cast-bar / nameplate / unit-frame addons — no cast-bar dependency, never
--- reads the secret. See the INTERRUPT DETECTION notes in CastInterruptTracker for why this is the
--- only robust path. Caller should apply this only to a KICK suggestion (a CC is the correct
--- call on a non-interruptible cast and must stay visible).
function BlizzardAPI.ApplyInterruptIconAlpha(icon, shownAlpha)
    local notInt = select(8, UnitCastingInfo("target"))
    if not IsSecretValue(notInt) and notInt == nil then
        notInt = select(7, UnitChannelInfo("target"))  -- channels: notInterruptible is 7th
    end
    -- true (can't interrupt) → 0 ; false (interruptible) → shownAlpha ; nil (no cast) → 0
    BlizzardAPI.SetAlphaFromSecretBool(icon, notInt, 0, shownAlpha, 0)
end

--- Reset target cast tracking. Called from JustAC:OnTargetChanged and
--- anywhere else that needs to clear stale state.
function BlizzardAPI.ResetTargetCastState()
    targetCastActive = false
    targetCastInterruptKnown = false
    targetCastInterruptible = true
end

--- Initialize the target cast tracking frame. Called once from
--- BlizzardAPI initialization or first use.
function BlizzardAPI.InitTargetCastTracking()
    InitTargetCastTracking()
end

-- Auto-initialize at load time (cheap: one hidden frame, 9 event registrations).
InitTargetCastTracking()
