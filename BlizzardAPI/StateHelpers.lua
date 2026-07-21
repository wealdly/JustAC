-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Defensive/Item State, Health Detection, Target Analysis, Shapeshift Forms
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SpellQuery.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-StateHelpers", 13
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
local UnitGUID      = UnitGUID      ---@diagnostic disable-line: undefined-global
local strsplit      = strsplit       ---@diagnostic disable-line: undefined-global
local wipe          = wipe

-- Pre-built boss unit tokens (avoids string concat on hot path)
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local GetNumShapeshiftForms = GetNumShapeshiftForms
local GetShapeshiftFormInfo = GetShapeshiftFormInfo

--------------------------------------------------------------------------------
-- Engaged-enemy count (secret-safe, AC-independent AoE signal)
--------------------------------------------------------------------------------
-- Counts hostile nameplate units that have the player on their threat table -
-- enemies actually fighting YOU. Validated in 12.0 as: camera-immune (combat
-- nameplates are pinned), group-correct (excludes mobs tanked by others), and
-- secret-safe (every read is issecretvalue-tested before use). Cached briefly so
-- the per-frame queue build stays cheap. Nameplate frames are restricted, so we
-- go through the unit TOKENS, not C_NamePlate.GetNamePlates().
local UnitCanAttack       = UnitCanAttack
local UnitThreatSituation = _G.UnitThreatSituation
local NAMEPLATE_UNITS = {}
for i = 1, 40 do NAMEPLATE_UNITS[i] = "nameplate" .. i end
local engagedCount, engagedCountAt = 0, -1

--- @return number enemies currently engaged with the player (0 if unknowable)
function BlizzardAPI.GetEngagedEnemyCount()
    local now = GetTime()
    if now - engagedCountAt < 0.25 then return engagedCount end
    local n = 0
    if UnitThreatSituation then
        for i = 1, 40 do
            local u = NAMEPLATE_UNITS[i]
            local ex = UnitExists(u)
            if not IsSecretValue(ex) and ex then
                local ca = UnitCanAttack("player", u)
                if not IsSecretValue(ca) and ca then
                    local ts = UnitThreatSituation("player", u)
                    if not IsSecretValue(ts) and ts ~= nil then
                        n = n + 1
                    end
                end
            end
        end
    end
    engagedCount, engagedCountAt = n, now
    return n
end

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

-- Cache for SpellDB lookup (lazy-loaded)
local cachedSpellDB = nil
local function GetSpellDB()
    if cachedSpellDB == nil then
        cachedSpellDB = LibStub("JustAC-SpellDB", true) or false
    end
    return cachedSpellDB or nil
end

-- Check defensive spell usability in one call (avoids repeated API lookups)
-- Returns: isUsable, isRedundant, isProcced
-- isUsable = spell is known AND NOT redundant (buff already active).
-- Cooldown gating is handled by the caller via IsSpellReady / IsSpellUsable.
-- Resolve a display/override spellID to its castable base - shared impl in
-- BlizzardAPI/CooldownTracking (loads earlier in the .toc).
local ResolveBaseSpellID = BlizzardAPI.ResolveBaseSpellID

-- Loss of control = stun / fear / silence / incapacitate / disorient etc.
-- While one is active the client reports the whole spellbook as uncastable for a
-- NON-resource reason, so the castability gate below would drop every defensive
-- spell in the same rebuild and blink the queue empty for the CC's duration -
-- precisely when the player is staring at it waiting to press something. Items
-- aren't gated on castability, so they'd stay put while the spells vanished:
-- the queue reshuffles rather than cleanly hiding, which is the flicker.
-- The active count is a plain number (no SecretWhen* flag on the count function);
-- if it ever reads secret we return false and the gate behaves as before.
local C_LossOfControl = C_LossOfControl ---@diagnostic disable-line: undefined-global
function BlizzardAPI.IsLossOfControlActive()
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then return false end
    local ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
    if not ok or IsSecretValue(count) then return false end
    return (count or 0) > 0
end
local IsLossOfControlActive = BlizzardAPI.IsLossOfControlActive

function BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
    if not spellID or spellID == 0 then
        return false, false, false
    end

    -- A user may add a display-override id whose castable base differs (e.g.
    -- Recuperate 1231411 surfaces as Frenzied Regeneration 22842 for druids). The
    -- override id may not be independently "known", so resolve to the base and
    -- gate on that for both the availability check and the castability gate below.
    local gateID = spellID
    if not BlizzardAPI.IsSpellAvailable(spellID) then
        local baseID = ResolveBaseSpellID(spellID)
        if not baseID or not BlizzardAPI.IsSpellAvailable(baseID) then
            return false, false, false
        end
        gateID = baseID
    end

    -- Castability gate: the never-secret C_Spell.IsSpellUsable (verified readable
    -- in AND out of combat this build) evaluates form, talents, stealth, and cast
    -- conditions for us - no static form/requirement tables needed, and it knows
    -- form-bypass hero talents (Fluid Form, Empowered Shapeshifting, ...) the
    -- static data can't. Hide only when genuinely uncastable for a NON-resource
    -- reason; a pure resource shortfall (e.g. Frenzied Regeneration's 40 energy)
    -- still shows - downstream renders that state. Fail open when unreadable.
    -- Skipped entirely under loss of control (see IsLossOfControlActive): the CC,
    -- not the spell, is why nothing is castable. Entries fall through to the
    -- caller's ready/on-CD ordering, which stays honest while CC'd; the renderer
    -- greys the icons off its own usability read, so they hold their place, dimmed,
    -- and light back up when control returns.
    if C_Spell and C_Spell.IsSpellUsable and not IsLossOfControlActive() then
        local ok, usable, notEnoughPower = pcall(C_Spell.IsSpellUsable, gateID)
        if ok and not IsSecretValue(usable) and usable == false and notEnoughPower ~= true then
            return false, false, false
        end
    end

    -- Check if procced (instant/free cast available)
    local isProcced = BlizzardAPI.IsSpellProcced(spellID)

    -- Check redundancy (buff already active - reliable, based on UnitBuff not cooldown)
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

-- In combat the numeric item cooldown is secret, so an on-CD item reads as
-- ready (fail-open). Latch observed uses instead: map each checked item's
-- use-spell once (plain read), and when that spell is seen via
-- UNIT_SPELLCAST_SUCCEEDED treat the item as on cooldown for the rest of the
-- combat session. Out of combat the numeric read is authoritative again.
-- ponytail: whole-combat suppression; per-item CD durations (ItemEffect data)
-- only if long-fight healthstone re-suggests ever matter.
local itemUseSpellToItem = {}
local itemUseSpellMapped = {}
local itemUsedInCombat = {}

--- Called from UNIT_SPELLCAST_SUCCEEDED (player): latch defensive item use.
function BlizzardAPI.NoteDefensiveItemUse(spellID)
    local itemID = spellID and itemUseSpellToItem[spellID]
    if itemID then
        itemUsedInCombat[itemID] = true
    end
end

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

    -- Lazily map this item's use-spell for combat use detection (plain values)
    if not itemUseSpellMapped[itemID] then
        itemUseSpellMapped[itemID] = true
        local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
        if getItemSpell then
            local ok, _, useSpellID = pcall(getItemSpell, itemID)
            if ok and type(useSpellID) == "number" then
                itemUseSpellToItem[useSpellID] = itemID
            end
        end
    end

    if UnitAffectingCombat("player") then
        -- Observed-use latch: the only reliable in-combat cooldown signal
        if itemUsedInCombat[itemID] then
            return false, true, true
        end
    else
        itemUsedInCombat[itemID] = nil  -- OOC: numeric read is authoritative
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
--   UnitCreatureType()  - SECRETED in combat. Primary data source, unusable.
--   UnitGUID()          - SECRETED in combat. GUID-keyed cache is not viable.
--   UnitCreatureFamily()- NOT secreted, but only distinguishes Beast from
--                         everything else (nil for Mechanical/Undead/etc.).
--   UnitClassification()- NOT secreted. Used for worldboss/boss slot detection.
--   UnitIsUnit(boss1-5) - SECRET-CAPABLE (SecretWhenUnitComparisonRestricted); returns a bool,
--     so boolean-testing it THROWS on an addon-restricted map. Route via SafeUnitIsUnit.
--
-- DESIGN CONSEQUENCE:
--   The cache is populated out of combat (TARGET_CHANGED, PLAYER_REGEN_ENABLED).
--   If the player tabs to a NEW target mid-combat (not yet cached), the creature
--   type is unknowable and IsTargetCCImmune() returns false (fail-open: assume
--   CC-able). This is intentional - showing a CC suggestion on a Mechanical mob
--   is a minor UX annoyance; suppressing CC on a valid target would be harmful.
--
-- UPDATE (in-game verified 2026-06-28, build 12.0.7): UnitCreatureType("target") is
-- in fact READABLE in combat for resolved targets - targeting resolves the unit, so
-- the type reads back mid-combat (the Feb-2026 finding no longer holds for the target).
-- UnitName is likewise readable in combat. The secret system is volatile (it loosened
-- since Feb 2026), so as a hedge we cache the type keyed by the readable UnitName
-- whenever it's available - a pre-warmed fallback if Blizzard ever re-secrets it.
-- Resolution order (BlizzardAPI.GetTargetCreatureTypeID below): live read -> name
-- cache -> fail-open (assume CC-able).

-- Persistent, bounded name->creatureTypeID cache (account-wide via JustACGlobal).
-- Flat numeric values; hard cap that wipes + re-warms so it never grows without bound.
local NAME_TYPE_CACHE_CAP = 1500

-- Localized creature-type name -> numeric ID, built once from C_CreatureInfo
-- (locale-correct - no hardcoded type strings).
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
-- the rest of the instance - all future mobs with the same NPC ID are suppressed
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
    -- Also reset CC-failure learning on target switch - the new target might
    -- be CC-able even if the previous one wasn't.
    ccCastTime = 0
    ccFailureObserved = false
    ccFailureChecked  = false
    local ct = UnitCreatureType and UnitCreatureType("target")
    if ct and not IsSecretValue(ct) then
        -- Pre-warm the persistent name->type cache while the type is readable, keyed
        -- by the (also-readable) UnitName - insurance if the type is ever re-secreted.
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
--- Order: live UnitCreatureType when readable (resolved targets, even in combat - and
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
-- no restriction). Regenerate per patch by intersecting INTERRUPT_ABILITIES cc
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
    -- Don't clear ccFailureObserved here - if we already know this target is
    -- immune, keep that knowledge.
end

--- Called on PLAYER_REGEN_ENABLED to reset per-target CC-failure learning for
--- the next combat session.  Instance-level ccImmuneNPCIDs is NOT cleared here
--- - it persists across pulls until the player changes zone.
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
        -- NPC ID was known during combat - already persisted in IsTargetCCImmune
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

--- Secret-safe UnitIsUnit. UnitIsUnit is annotated SecretWhenUnitComparisonRestricted and
--- returns a BOOL, so its result can be a secret boolean - and boolean-testing a secret
--- boolean THROWS ("attempt to perform boolean test on a secret boolean value"), it does not
--- merely return the wrong answer. Two triggers, per SecretPredicatesDocumentation:
---   • compound unit tokens (eg. "boss1target") - ALWAYS secret, on any map
---   • any comparison while on an addon-restricted map - i.e. instanced content
--- `default` is returned whenever the answer cannot be read, so each caller states its own
--- fail direction explicitly rather than inheriting a silent one.
--- @param default boolean value to return when the comparison is unreadable
--- @return boolean
function BlizzardAPI.SafeUnitIsUnit(unit1, unit2, default)
    if not (unit1 and unit2 and UnitIsUnit) then return default end
    -- Ask the engine first: this predicate exists precisely because these go secret.
    local pred = C_Secrets and C_Secrets.ShouldUnitComparisonBeSecret
    if pred then
        local predOk, isSecret = pcall(pred, unit1, unit2)
        if not predOk or isSecret then return default end
    end
    local ok, result = pcall(UnitIsUnit, unit1, unit2)
    if not ok then return default end
    -- Belt and braces: the predicate may not exist on every client build.
    if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(result) then return default end
    return result and true or false
end

function BlizzardAPI.IsTargetCCImmune()
    -- 1) World bosses and boss-frame mobs are always CC-immune.
    --    UnitClassification: NeverSecret (no SecretWhenUnitIdentityRestricted).
    --    UnitIsUnit is NOT NeverSecret - the "verified 2026-02-23" claim is retracted; the
    --    generated docs annotate it SecretWhenUnitComparisonRestricted.
    --    Unreadable defaults to FALSE: lose boss detection, not all CC for the instance.
    if UnitClassification("target") == "worldboss" then return true end
    for i = 1, 5 do
        if BlizzardAPI.SafeUnitIsUnit("target", BOSS_UNITS[i], false) then return true end
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
                -- Secret value - can't determine, fail-open
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
    -- UnitCreatureType() Mechanical/Totem check - but works IN combat.
    if UnitIsMinion and UnitIsMinion("target") then return false end
    return true
end

--------------------------------------------------------------------------------
-- Player & Pet Health (moved from SpellQuery - consolidated with health helpers)
--------------------------------------------------------------------------------

-- UnitHealth/UnitHealthMax are SECRET in 12.0 combat - returns nil when secret.
function BlizzardAPI.GetPlayerHealthPercent()
    if not UnitExists("player") then return nil end

    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")

    -- 12.0.7 reality (probe-verified 2026-07-05): HasSecretRestrictions() is TRUE
    -- even out of combat in the open world - UnitHealth is secret there while
    -- UnitHealthMax stays readable. Exact reads only work in unrestricted contexts
    -- (rested areas etc.); every alternative channel (UnitHealthPercent,
    -- UnitPercentHealthFromGUID, frame fill-width/value reads) returns secrets
    -- too, so callers MUST handle nil - see /jac inspect healthprobe.
    -- Gate unconditionally (like GetPetHealthPercent): on builds without the
    -- HasSecretRestrictions predicate, health can still be secret in combat and
    -- the comparison/arithmetic below would throw.
    if IsSecretValue(health) or IsSecretValue(maxHealth) then
        return nil
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
-- UnitExists and UnitIsDead are NOT secret - reliable in combat
-- Pet health IS secret in combat - use GetPetHealthPercent() for best-effort health
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

-- Auras meaning the player has intentionally chosen a petless playstyle.
-- While any is active, "missing pet" is by design - suppress rez/summon reminders.
local PETLESS_BY_CHOICE_AURAS = {
    155228,  -- Lone Wolf (Marksmanship Hunter running without a pet)
    196099,  -- Demonic Power (Warlock with pet sacrificed for a damage buff)
}
function BlizzardAPI.IsPetlessByChoice()
    for _, auraID in ipairs(PETLESS_BY_CHOICE_AURAS) do
        if BlizzardAPI.IsAuraActive("player", auraID) then return true end
    end
    return false
end

-- Player UNIT_HEALTH event activity: a never-secret "below full health" signal.
-- Out of combat, regen/heal ticks fire UNIT_HEALTH("player") continuously while
-- health is below max and go silent at full - the payload stays secret in 12.0.7
-- restricted contexts, but the event FIRING is itself readable information.
-- Stamped by the UNIT_HEALTH handler in JustAC.lua (real events only, not the
-- synthetic periodic rebuild calls).
-- IMPORTANT (probe-verified on a druid at full health): in secret-restricted
-- zones the client can't compare health values, so UNIT_HEALTH also fires for
-- NO-CHANGE server snapshots - lingering HoTs and slow passives (Ysera's Gift,
-- ~5s cadence) keep the event stream alive at FULL health forever. "Events are
-- firing" alone therefore means nothing; only a run of CLOSELY-SPACED ticks
-- (out-of-combat regen / eating, ~1s cadence) indicates genuine recovery.
local RUN_BREAK_SECS = 4        -- silence (or a passive's slow drip) ends a run
local SUSTAINED_TICKS = 3       -- ticks needed before "actively recovering"
local MAX_AVG_TICK_GAP = 2.5    -- run must tick at recovery cadence, not drip
local lastPlayerHealthEventAt = -1e9
local runTickCount, runStartedAt = 0, 0
function BlizzardAPI.NotePlayerHealthEvent()
    local now = GetTime()
    if now - lastPlayerHealthEventAt > RUN_BREAK_SECS then
        runTickCount, runStartedAt = 0, now
    end
    runTickCount = runTickCount + 1
    lastPlayerHealthEventAt = now
end
function BlizzardAPI.HasRecentPlayerHealthActivity()
    return (GetTime() - lastPlayerHealthEventAt) < RUN_BREAK_SECS
end
-- Sustained activity: enough ticks, at recovery cadence, still fresh. A 5s
-- passive drip starts a new 1-tick run each time (never sustained); a scratch
-- repairs in 1-2 ticks (never sustained); real regen qualifies in ~3 seconds.
function BlizzardAPI.HasSustainedPlayerHealthActivity()
    if runTickCount < SUSTAINED_TICKS then return false end
    if not BlizzardAPI.HasRecentPlayerHealthActivity() then return false end
    local avgGap = (lastPlayerHealthEventAt - runStartedAt) / (runTickCount - 1)
    return avgGap <= MAX_AVG_TICK_GAP
end

-- Post-combat bridge window: a short OOC grace period right after leaving combat. Its ONLY
-- job is to cover the few-second delay before out-of-combat health regen starts ticking -
-- once regen is flowing, HasSustainedPlayerHealthActivity (an airtight below-full signal,
-- since health never regenerates at full) carries the top-off reminder and drops it the
-- moment you hit full. So this stays SHORT: long enough to overlap the onset of a sustained
-- regen run, no longer (a longer window would keep the reminder up after a no-damage pull).
-- Combat state is never secret, so the window itself is fully reliable.
local POSTCOMBAT_WINDOW_SECS = 10
local combatEndedAt = -1e9
function BlizzardAPI.NotePlayerLeftCombat()
    combatEndedAt = GetTime()
end
function BlizzardAPI.IsInPostCombatDowntime()
    return (GetTime() - combatEndedAt) <= POSTCOMBAT_WINDOW_SECS
end

-- Returns LowHealthFrame binary state: isLow (bool), isEstimate always true in combat.
-- In combat UnitHealth() is secret - only the LowHealthFrame binary (~35% threshold)
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
--     IS the data - real (non-secret) boolean.
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
--   • UnitCastingInfo notInterruptible / cast barType - secret (IsInterruptable() errors
--     when compared under our taint, on Blizzard's own frames too)
--   • the cast spellID from UNIT_SPELLCAST_START - secret (so no spell-keyed lookup)
--   • CastingBar BorderShield:IsShown() - returns a secret boolean (display state sealed too)
--   • UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE - fire only on mid-cast transitions,
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

    -- Unit events filtered to "target" only - zero overhead for player/party casts
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    -- Empowered casts (Evoker Fire Breath style) fire EMPOWER_*, not START/
    -- CHANNEL_START; without these the event layer never engages for them.
    -- Empowers surface through UnitChannelInfo, so route with the channel branch.
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "target")
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "target")
    -- PLAYER_TARGET_CHANGED is a global event (not unit-filterable)
    castEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

    castEventFrame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            -- Event name IS the data (the event itself carries it) - never secret
            targetCastInterruptible = true
            targetCastInterruptKnown = true
        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            targetCastInterruptible = false
            targetCastInterruptKnown = true
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_START" then
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
            or event == "UNIT_SPELLCAST_EMPOWER_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED" then
            -- Cast ended - reset state
            targetCastActive = false
            targetCastInterruptKnown = false
            targetCastInterruptible = true
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- New target - probe for an existing cast on the new target so we
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
-- "AllowedWhenTainted"). We never read or branch on the value - the engine renders it.
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
--- regardless of cast-bar / nameplate / unit-frame addons - no cast-bar dependency, never
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

--------------------------------------------------------------------------------
-- Discrete class resources (combo points, holy power, chi, shards, runes, ...)
--------------------------------------------------------------------------------
-- EXACT count without reading a secret. Blizzard's own resource bar branches on the secret
-- UnitPower in PRIVILEGED code - `point:SetActive(i <= count)` (DruidComboPointBar.lua) - and
-- leaves the answer behind as ordinary frame state (`point.isActive`), which reads back plain
-- for an addon. Same idiom as the scratch-Cooldown IsShown() readiness probe: let the engine do
-- the comparison, then read the frame state it produced. Confirmed in combat via
-- `/jac inspect resourcepoints` (3 combo points -> 3 actives).
--
-- SAFETY - why a hidden bar is never read: ClassResourceBarMixin:Setup UNREGISTERS
-- UNIT_POWER_FREQUENT / UNIT_MAXPOWER / UNIT_POWER_POINT_CHARGE the moment the bar hides, so a
-- hidden bar's isActive is FROZEN at its last value (combo points persist out of cat form while
-- the bar is gone - a stale read would be confidently wrong). Only a SHOWN bar is trusted;
-- everything else returns nil = UNKNOWN so callers fall back to delegation rather than act on
-- stale data. `isActive` is a Blizzard-internal field, not an API, so every read is guarded and
-- any secret or missing value collapses the whole read to nil.
local RESOURCE_BARS = {
    -- The 12.x Personal Resource Display builds its OWN class frame from the standard class
    -- template and names it globally `prdClassFrame` (Blizzard_PersonalResourceDisplay.lua
    -- SetupClassBar). It is a THIRD source, independent of both the player-frame bars and the
    -- older nameplate bars, and it stays live whenever the PRD is enabled - including when an
    -- addon replaces the player unit frame and hides Blizzard's own bars. Listed first for that
    -- reason; same per-class shapes, so the class filter picks the right one.
    { frame = "prdClassFrame", class = "DRUID",   res = "combo_points", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "ROGUE",   res = "combo_points", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "MONK",    res = "chi", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "WARLOCK", res = "soul_shard", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "MAGE",    res = "arcane_charges", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "EVOKER",  res = "essence", event = "UNIT_POWER_FREQUENT" },
    { frame = "prdClassFrame", class = "PALADIN", event = "UNIT_POWER_FREQUENT", res = "holy_power", indexed = "rune",
      state = "visualState", min = 1, max = 3, isFilled = function(v) return v > 1 end },
    { frame = "prdClassFrame", class = "DEATHKNIGHT", event = "RUNE_POWER_UPDATE", res = "rune", array = "Runes",
      state = "visualState", min = 1, max = 4, isFilled = function(v) return v == 4 end },

    { frame = "DruidComboPointBarFrame", class = "DRUID", res = "combo_points", event = "UNIT_POWER_FREQUENT" },   -- isActive (boolean)
    { frame = "RogueComboPointBarFrame", class = "ROGUE", res = "combo_points", event = "UNIT_POWER_FREQUENT" },   -- isFull   (boolean)
    { frame = "MonkHarmonyBarFrame", class = "MONK", res = "chi", event = "UNIT_POWER_FREQUENT" },            -- active   (boolean)
    { frame = "WarlockPowerFrame", class = "WARLOCK", res = "soul_shard", event = "UNIT_POWER_FREQUENT" },     -- fillAmount (0..1 fractional)
    { frame = "MageArcaneChargesFrame", class = "MAGE", res = "arcane_charges", event = "UNIT_POWER_FREQUENT" },
    { frame = "EssencePlayerFrame", class = "EVOKER", res = "essence", event = "UNIT_POWER_FREQUENT" },
    -- Paladin: runes hang off the bar as rune1..runeN. PaladinPowerBar.VisualState =
    -- 1 Inactive / 2 Active / 3 SpellReady -> filled when > 1.
    { frame = "PaladinPowerBarFrame", class = "PALADIN", event = "UNIT_POWER_FREQUENT", res = "holy_power", indexed = "rune",
      state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    -- Death Knight: runes live in bar.Runes. RuneButtonMixin.VisualState =
    -- 1 Empty / 2 OnCooldown / 3 CooldownEnding / 4 Ready -> AVAILABLE ONLY at 4. Note this is a
    -- different enum to Paladin's under the same field name, hence per-bar semantics.
    { frame = "RuneFrame", class = "DEATHKNIGHT", event = "RUNE_POWER_UPDATE", res = "rune", array = "Runes",
      state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },

    -- Personal Resource Display equivalents. These are SEPARATE globals that reuse the same
    -- mixins (and therefore the same shapes) as the player-frame bars above. They matter because
    -- an addon that replaces the player unit frame hides Blizzard's bars, which stops them
    -- updating - with the PRD enabled these keep running, so a player on a replacement unit-frame
    -- addon still gets a resource read. Listed after the player-frame bars: whichever is SHOWN
    -- wins, and both carry identical data when both are up.
    { frame = "ClassNameplateBarFeralDruidFrame", class = "DRUID", res = "combo_points", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarRogueFrame", class = "ROGUE", res = "combo_points", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarWindwalkerMonkFrame", class = "MONK", res = "chi", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarWarlockFrame", class = "WARLOCK", res = "soul_shard", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarMageFrame", class = "MAGE", res = "arcane_charges", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarDracthyrFrame", class = "EVOKER", res = "essence", event = "UNIT_POWER_FREQUENT" },
    { frame = "ClassNameplateBarPaladinFrame", class = "PALADIN", event = "UNIT_POWER_FREQUENT", res = "holy_power", indexed = "rune",
      state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    { frame = "DeathKnightResourceOverlayFrame", class = "DEATHKNIGHT", event = "RUNE_POWER_UPDATE", res = "rune", array = "Runes",
      state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },
}

-- Each class's point widget stores its state under a DIFFERENT name and in one of two shapes:
--   BOOLEAN "filled" flag - Druid `isActive` (DruidComboPointMixin:SetActive), Monk `active`
--     (MonkLightEnergyMixin:SetActive), Rogue `isFull` (RogueComboPointMixin:Update).
--   NUMERIC 0..1 fill     - Warlock `fillAmount` (WarlockShardMixin:Update). Destruction shards
--     fill fractionally, so summing these reproduces SimC's fractional `soul_shard` exactly.
-- Paladin is a THIRD shape (rune1..runeN with a visualState enum, not classResourceButtonTable)
-- and DK/Evoker/Mage are unmapped - all of those simply read as unknown and fail open.
local POINT_ACTIVE_FIELDS = { "isActive", "active", "isFull" }   -- boolean: filled or not
local POINT_FILL_FIELDS   = { "fillAmount" }                     -- number 0..1: fractional fill

-- Point-array discovery: most bars use `classResourceButtonTable`; Paladin hangs runes off the
-- bar as rune1..runeN (`indexed`), DK keeps them in a named sub-table (`array` = "Runes").
local function BarPoints(bar, def)
    local pts = bar.classResourceButtonTable
    if type(pts) == "table" and #pts > 0 then return pts end
    if def.array then
        pts = bar[def.array]
        if type(pts) == "table" and #pts > 0 then return pts end
    end
    if def.indexed then
        local out = {}
        for i = 1, 10 do
            local p = bar[def.indexed .. i]
            if not p then break end
            out[i] = p
        end
        if #out > 0 then return out end
    end
    return nil
end

-- Is this bar still being UPDATED? Gate on event registration, not visibility.
-- ClassResourceBarMixin registers/unregisters UNIT_POWER_FREQUENT (DK: RUNE_POWER_UPDATE) exactly
-- in step with whether it refreshes, so registration answers the real question directly. Crucially
-- a bar can be HIDDEN YET LIVE: with the Personal Resource Display on, the nameplate bar reads the
-- correct value while IsShown() is false, and gating on visibility would discard it. Conversely an
-- unregistered bar is the frozen one - confirmed on a Paladin at 2 Holy Power, where the
-- unregistered player-frame bar still read 0 while the registered nameplate bar read 2.
-- Falls back to IsShown() only if the API is unavailable.
local function BarIsLive(bar, def)
    if def.event and bar.IsEventRegistered then
        return bar:IsEventRegistered(def.event) and true or false
    end
    return (bar.IsShown and bar:IsShown()) and true or false
end

--- Read one point: 1 / 0 / fractional, or nil when its shape isn't understood.
--- Enum semantics live on the BAR (def.state/def.isFilled), never on the field name: Paladin and
--- DK BOTH store `visualState`, but Paladin is 1=Inactive/2=Active/3=SpellReady (filled when >1)
--- while DK is 1=Empty/2=OnCooldown/3=CooldownEnding/4=Ready (available ONLY at 4). A shared
--- field-name rule would silently count cooling DK runes as available.
local function ReadPoint(p, def)
    if not p then return nil end
    for k = 1, #POINT_ACTIVE_FIELDS do
        local v = p[POINT_ACTIVE_FIELDS[k]]
        if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(v) then return nil, true end
        if type(v) == "boolean" then return v and 1 or 0 end
    end
    for k = 1, #POINT_FILL_FIELDS do
        local v = p[POINT_FILL_FIELDS[k]]
        if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(v) then return nil, true end
        -- Saturate() bounds these to 0..1; outside that is a shape we don't understand.
        if type(v) == "number" and v >= 0 and v <= 1 then return v end
    end
    if def.state and def.isFilled then
        local v = p[def.state]
        if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(v) then return nil, true end
        if type(v) == "number" and v % 1 == 0 and v >= def.min and v <= def.max then
            return def.isFilled(v) and 1 or 0
        end
    end
    return nil
end

--- Current discrete class-resource count, or nil when it can't be trusted.
--- EVERY point must read: a partially-understood bar is not counted. That is the fallback for an
--- unmapped class and for any future Blizzard rename - "unknown" beats a confident zero, which
--- would otherwise report 0 resource and permanently sink every `>=`-gated spender. Callers treat
--- nil as unknown and fail open.
--- @return number|nil count, number|nil max, string|nil resource (SimC resource token)
function BlizzardAPI.GetClassResourcePoints()
    local _, playerClass = UnitClass("player")
    for i = 1, #RESOURCE_BARS do
        local def = RESOURCE_BARS[i]
        -- Only this character's bar: another class's global exists but is never initialised, so
        -- skipping it avoids both the wasted scan and any chance of reading a foreign resource.
        local bar = (def.class == playerClass) and _G[def.frame] or nil
        if bar and BarIsLive(bar, def) then
            local pts = BarPoints(bar, def)
            if pts then
                local count, readable = 0, 0
                for j = 1, #pts do
                    local add, secret = ReadPoint(pts[j], def)
                    if secret then return nil end   -- secret anywhere: trust none of it
                    if add ~= nil then
                        readable = readable + 1
                        count = count + add
                    end
                end
                if readable == #pts then
                    return count, #pts, def.res
                end
            end
        end
    end
    return nil
end

--- Reset target cast tracking. Called from JustAC:OnTargetChanged and
--- anywhere else that needs to clear stale state.
function BlizzardAPI.ResetTargetCastState()
    targetCastActive = false
    targetCastInterruptKnown = false
    targetCastInterruptible = true
end

-- Auto-initialize at load time (cheap: one hidden frame, 9 event registrations).
InitTargetCastTracking()
