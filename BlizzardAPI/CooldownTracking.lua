-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Cooldown, charge and buff-window state (12.0+ secret value workarounds)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after BlizzardAPI.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-CooldownTracking", 13
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime               = GetTime
local pcall                 = pcall
local type                  = type
local wipe                  = wipe
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges  = C_Spell and C_Spell.GetSpellCharges
local GetSpellBaseCooldown     = GetSpellBaseCooldown ---@diagnostic disable-line: undefined-global
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

--------------------------------------------------------------------------------
-- Cooldown state (12.0+ secret values)
--------------------------------------------------------------------------------
-- NO local cooldown model, flat or charge. Everything a decision or a swipe needs is an
-- engine read that stays plain in combat: GetSpellCooldown().isActive / isOnGCD, the
-- ignore-GCD duration object (IsSpellOnCooldown), and the duration object itself for the
-- swipe. The old cast-timed model (tooltip-parsed durations, per-category tracking, resync
-- on combat exit, pick-oracle expiry) had drifted down to one reader - a swipe fallback that
-- already had the engine path behind it - and could only ever disagree with the engine.
--
-- Charge spells keep NO local model. The engine answers everything a decision needs, plainly,
-- in combat: GetSpellCooldown().isActive is false while any charge is banked and true at zero
-- (measured in and out of combat), GetSpellCharges().isActive says a recharge is running, and
-- maxCharges is never secret. The old cast-counting model could only drift - haste, refunds,
-- a cast id that was not the tracked id - and nothing ever lowered an over-count.
--- The ONE engine charge read behind both "at max charges" verdicts: maxCharges
--- and isActive are NeverSecret (validated in combat 2026-07-24), and isActive false
--- means no charge is recharging, i.e. with maxCharges > 1 the spell is capped.
--- Returns maxCharges (nil unknown), isActive (nil unknown/secret).
local function LiveChargeState(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return nil, nil end
    local ok, ci = pcall(C_Spell_GetSpellCharges, spellID)
    if not ok or not ci then return nil, nil end
    local active = ci.isActive
    if IsSecretValue(active) then active = nil end
    return Unsecret(ci.maxCharges), active
end

local function IsChargeSpell(spellID)
    local maxCharges = LiveChargeState(spellID)
    return maxCharges ~= nil and maxCharges > 1
end

--- Resolve a display/override spellID to its castable base (override -> base), nil if
--- none. ONE resolver for the addon: SpellDB's (cached; it loads before this file).
--- The deprecated FindBaseSpellByID second tier was a wrapper for the same lookup.
local SpellDB = LibStub("JustAC-SpellDB", true)
function BlizzardAPI.ResolveBaseSpellID(spellID)
    return SpellDB and SpellDB.GetBaseSpell and SpellDB.GetBaseSpell(spellID) or nil
end

-- Static base cooldown/charge data generated from client data (Data/SpellCooldowns.lua).
-- Unlike every runtime CD API, it can't be secreted - the only source that works
-- for a spell first seen mid-combat (battle res, first engage after login).
local staticCooldownData
local function GetStaticCooldownData()
    if staticCooldownData == nil then
        staticCooldownData = LibStub("JustAC-CooldownData", true) or false
    end
    return staticCooldownData or nil
end

--- Base cooldown in seconds from static client data, or 0. Keyed by base ids, so an
--- override cast id is resolved when the direct lookup misses.
local function StaticBaseSeconds(spellID)
    local staticData = GetStaticCooldownData()
    if not staticData then return 0 end
    local cdMs = staticData.Get(spellID)
    if not cdMs or cdMs == 0 then
        local base = BlizzardAPI.ResolveBaseSpellID(spellID)
        if base then cdMs = staticData.Get(base) end
    end
    return (cdMs and cdMs > 0) and (cdMs / 1000) or 0
end

-- Base cooldown (seconds) for a spell, cached. MUST be populated OUT of combat -
-- GetSpellBaseCooldown returns secrets in combat, so an unreadable value is NOT
-- cached (it's retried on the next OOC pass). Charge-based spells report 0 base
-- CD; fall back to their per-charge recharge time. Shared by the engines.
local baseCdSecondsCache = {}
function BlizzardAPI.GetBaseCooldownSeconds(spellID)
    if not spellID or spellID <= 0 then return 0 end
    local cached = baseCdSecondsCache[spellID]
    if cached ~= nil then return cached end
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if ms == nil or IsSecretValue(ms) then
        return 0  -- unreadable (in combat): don't cache; a later OOC pass fills it
    end
    local sec = (ms > 0) and (ms / 1000) or 0
    if sec == 0 and C_Spell_GetSpellCharges then
        local ok, charges = pcall(C_Spell_GetSpellCharges, spellID)
        if ok and charges and charges.cooldownDuration
           and not IsSecretValue(charges.cooldownDuration) and charges.cooldownDuration > 0 then
            sec = charges.cooldownDuration
        end
    end
    baseCdSecondsCache[spellID] = sec
    return sec
end

--- Cache-only read of the base cooldown: never touches the API, so it is safe
--- for per-tick combat checks. A spell the OOC pass never saw (reload in combat, first
--- pull) answers from static client data instead of 0, so a long cooldown is still held.
function BlizzardAPI.PeekBaseCooldownSeconds(spellID)
    if not spellID then return 0 end
    return baseCdSecondsCache[spellID] or StaticBaseSeconds(spellID)
end

--- Pre-cache base cooldowns for every spell in the Blizzard rotation list.
--- Must be called OUT of combat (GetSpellBaseCooldown returns secrets in combat).
--- Safe to call repeatedly - already-cached spells are skipped above.
function BlizzardAPI.PreCacheRotationCooldowns()
    if not BlizzardAPI.GetRotationSpells then return end
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return end
    for _, spellID in ipairs(rotationSpells) do
        if spellID and spellID > 0 then
            BlizzardAPI.GetBaseCooldownSeconds(spellID)
        end
    end
end

--- At maximum charges right now (charge regen idle, so holding it wastes recharge
--- time)? Promotion heuristic: any doubt reads as "not capped".
function BlizzardAPI.IsSpellChargeCapped(spellID)
    local maxC, active = LiveChargeState(spellID)
    return (maxC or 0) >= 2 and active == false
end

--------------------------------------------------------------------------------
-- Secret-safe readiness probes (12.0). Cooldown-remaining and aura durations are
-- secret in combat, but a DurationObject fed into a scratch Cooldown widget drives
-- that widget's SHOWN state, and IsShown() is a plain, branchable boolean. So we
-- read "on cooldown?" / "buff active?" as engine truth without ever touching the
-- secret numbers. (Verified in combat: numeric startTime SECRET, probe still correct.)
-- The remaining TIME stays unreadable - only the boolean is exposed, which is all a
-- gate needs. Reads fail safe: no duration object / no aura -> false.
-- This is an UNINTENDED workaround Blizzard could close - see
-- Documentation/SECRET_VALUE_READINESS_PROBE.md for the /jac inspect durprobe
-- detector and the fallback ladder if it stops working.
local scratchCooldown
local function DurationObjectActive(durObj)
    if durObj == nil then return false end
    if not scratchCooldown then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()  -- parent hidden -> the probe frame never renders
        scratchCooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    end
    if not scratchCooldown.SetCooldownFromDurationObject then return false end
    scratchCooldown:SetCooldownFromDurationObject(durObj)
    local shown = scratchCooldown:IsShown()
    scratchCooldown:SetCooldown(0, 0)
    return shown and true or false
end

--------------------------------------------------------------------------------
-- Group buffs, straight from the engine (12.1.0+).
--
-- C_CooldownViewer.GetGroupBuffItems is Blizzard's own registry of raid/group
-- buffs: plain spellID, name, and - the part curation cannot keep up with -
-- `isKnown`. No secrecy annotations at all, so this is an ordinary read.
--
-- It does NOT replace SpellDB.CLASS_MAINTAINED_BUFFS. A GroupBuffItem names ONE
-- spellID, while the curated groups also carry the aura FAMILY a buff can land as
-- (Mark of the Wild applies 1126 or 432661), and detection needs that family or a
-- buffed player reads as unbuffed forever. So the engine answers "which group
-- buffs exist and can I cast them" and curation keeps answering "what does it look
-- like once applied".
--
-- Cached until SPELLS_CHANGED-ish staleness: the answer only moves on talent or
-- spec changes, and the call allocates a table per invocation.
--------------------------------------------------------------------------------
local groupBuffCache, groupBuffCacheAt = nil, -1
local GROUP_BUFF_CACHE_SECONDS = 5

--- @return table|nil array of { spellID, name, isKnown, hideByDefault }, or nil
---         when the client predates the API or the call fails.
function BlizzardAPI.GetGroupBuffItems()
    local now = GetTime()
    if groupBuffCache ~= nil and (now - groupBuffCacheAt) < GROUP_BUFF_CACHE_SECONDS then
        return groupBuffCache or nil
    end
    groupBuffCacheAt = now
    groupBuffCache = false
    local CV = C_CooldownViewer ---@diagnostic disable-line: undefined-global
    if not (CV and CV.GetGroupBuffItems) then return nil end
    local ok, items = pcall(CV.GetGroupBuffItems)
    if not ok or type(items) ~= "table" then return nil end
    local hideFlag = Enum and Enum.GroupBuffItemFlags and Enum.GroupBuffItemFlags.HideByDefault
    local out = {}
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and type(it.spellID) == "number" then
            out[#out + 1] = {
                spellID = it.spellID,
                name    = it.name,
                isKnown = it.isKnown == true,
                -- Blizzard marks some entries as de-emphasised. Carried through rather
                -- than filtered here so callers decide; the buff list honours it.
                hideByDefault = (hideFlag and type(it.flags) == "number"
                    and bit.band(it.flags, hideFlag) ~= 0) or false,
            }
        end
    end
    groupBuffCache = out
    return out
end

--- Clear the group-buff cache (talent/spec change invalidates `isKnown`).
function BlizzardAPI.FlushGroupBuffItems()
    groupBuffCache, groupBuffCacheAt = nil, -1
end

--- The active/not boolean for any duration object, exposed so diagnostics can use
--- the SAME trusted baseline the production readers do rather than a lookalike.
function BlizzardAPI.IsDurationObjectActive(durObj)
    return DurationObjectActive(durObj)
end

local totemSlotMemo, totemSlotErrors = {}, {}
--- A successful nil duration means empty (measured on Forever).
--- A failed API read returns nil: unknown, never evidence that a slot is empty.
function BlizzardAPI.IsTotemSlotOccupied(slot)
    local now = GetTime()
    local memo = totemSlotMemo[slot]
    if memo and memo.t == now then return memo.occupied end
    if not memo then memo = {}; totemSlotMemo[slot] = memo end
    memo.t, memo.occupied = now, nil
    local ok, occupied = pcall(function()
        local duration = GetTotemDuration(slot)
        return DurationObjectActive(duration)
    end)
    if not ok then
        if totemSlotErrors[slot] ~= occupied then
            totemSlotErrors[slot] = occupied
            geterrorhandler()(occupied)
        end
        return nil
    end
    totemSlotErrors[slot] = nil
    memo.occupied = occupied
    return occupied
end

--- True while spellID is on a REAL cooldown (GCD excluded), read as engine truth.
function BlizzardAPI.IsSpellOnCooldown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldownDuration) then return false end
    -- pcall like every sibling read: this runs inside the queue build, where a throw on
    -- an odd id blanks the queue instead of degrading one entry.
    local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    return ok and DurationObjectActive(dur) or false
end

--- Does the spell's own cooldown (GCD excluded) end within `seconds`? true / false, nil when
--- unanswerable. One threshold question on the duration object, never the remaining time.
function BlizzardAPI.CooldownEndsWithin(spellID, seconds)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldownDuration and BlizzardAPI.IsDurationBelowSeconds) then
        return nil
    end
    local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    if not ok then return nil end
    if not DurationObjectActive(dur) then return true end
    return BlizzardAPI.IsDurationBelowSeconds(dur, seconds)
end

-- Our own casts, [spell id] = GetTime(). Player buffs are SECRET in combat (measured: the
-- aura lookup returns nil for a buff that is up), so inside a fight the only thing that knows
-- a buff window opened is the cast that opened it.
local ownCastAt = {}
local auraUntil = {}   -- [spellID] = the buff's expiry, read while its aura was plain
local auraUntilReadAt = {}   -- [spellID] = when that expiry was read
-- [spellID] = the buff's real full duration, read while its aura was plain (talents and ranks
-- included). Stands in for the data's base duration when a later cast is timed.
local learnedDuration = {}
BlizzardAPI._learnedBuffDuration = learnedDuration   -- tests
-- A removal this soon after our own cast is the refresh replacing the old aura, not an end.
local REMOVAL_GRACE = 0.5
local redundancyFilterRef
--- When the buff was last seen removed (RedundancyFilter, from UNIT_AURA), or nil.
local function AuraRemovedAt(spellID)
    if redundancyFilterRef == nil then redundancyFilterRef = LibStub("JustAC-RedundancyFilter", true) or false end
    if not (redundancyFilterRef and redundancyFilterRef.GetAuraRemovedAt) then return nil end
    return redundancyFilterRef.GetAuraRemovedAt(spellID)
end
--- Did a seen removal end what `since` describes (a reading, a snapshot, our cast)?
local function RemovedSince(removedAt, since, grace)
    return removedAt ~= nil and since ~= nil and removedAt > since + (grace or 0)
end
local formCache   -- resolved on first use: FormCache loads after this file
local rotationImport   -- resolved on first use: rank chains (WoW Forever)
local NoteDamageCast   -- Measured damage (below): one of the player's casts, for the meter
local FOREVER_CLIENT = SpellDB and SpellDB.IsForever and SpellDB.IsForever() or false
local maintenanceTracker   -- resolved on first use: Cooldown Manager aura state (loads later)

-- The last cast, and the last one on the global cooldown, by base id (SimC's `prev.x` and
-- `prev_gcd.1.x`). Own casts are plain in combat; kept across pulls, like the game's own
-- "same ability twice" rule.
local lastCast, lastGcdCast

-- The global cooldown each spell triggers, [spell id] = seconds, read off the GCD reference
-- spell as our own cast starts it. Spells differ (Forever, 2026-11-17: 1.304s after Priest and
-- Hunter spells, 1.500s after ranged shots) and haste moves them, so each keeps its own.
local gcdBySpell = {}
local GCD_START_WINDOW = 0.5   -- a GCD that began this long ago or less was started by this cast

--- Record the GCD this cast started: called at a cast's start (cast-time spells start the GCD
--- there) and at its success (instants). A GCD already running before the cast is not its own.
function BlizzardAPI.NoteCastGCD(spellID)
    if not spellID or IsSecretValue(spellID) or not BlizzardAPI.GetGCDInfo then return end
    local start, duration = BlizzardAPI.GetGCDInfo()
    if IsSecretValue(start) or IsSecretValue(duration) or type(start) ~= "number" or type(duration) ~= "number"
       or not (duration > 0 and duration < 5) then
        return
    end
    local age = GetTime() - start
    if age < 0 or age > GCD_START_WINDOW then return end
    gcdBySpell[spellID] = duration
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local r1 = rotationImport and rotationImport.RankBase(spellID)
    if r1 and r1 ~= spellID then gcdBySpell[r1] = duration end
end

--- The global cooldown this spell triggers, as last measured from our own cast (any rank),
--- else the last GCD seen running (BlizzardAPI.GetGCDLength), else nil.
function BlizzardAPI.GetSpellGCD(spellID)
    local gcd = spellID and gcdBySpell[spellID]
    if gcd == nil and spellID then
        if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
        local r1 = rotationImport and rotationImport.RankBase(spellID)
        gcd = r1 and gcdBySpell[r1]
    end
    if gcd then return gcd end
    return BlizzardAPI.GetGCDLength and BlizzardAPI.GetGCDLength() or nil
end

--- Record a successful player cast (every cast, in or out of combat).
function BlizzardAPI.NoteOwnCast(spellID)
    if not spellID then return end
    local now = GetTime()
    ownCastAt[spellID] = now
    BlizzardAPI.NoteCastGCD(spellID)
    local base = BlizzardAPI.ResolveBaseSpellID(spellID)
    if base then ownCastAt[base] = now end
    -- Forever ranks: a rank-3 cast opens the window the data names by rank 1.
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local r1 = rotationImport and rotationImport.RankBase(spellID)
    if r1 and r1 ~= spellID then ownCastAt[r1] = now end
    lastCast = base or r1 or spellID   -- rank 1 on Forever: prev.x matches any rank
    if not (BlizzardAPI.IsOffGCDSpell and BlizzardAPI.IsOffGCDSpell(spellID)) then
        lastGcdCast = lastCast
    end
    if FOREVER_CLIENT and NoteDamageCast then NoteDamageCast(spellID) end
end

--- Was spellID the last cast (gcdOnly: the last one on the global cooldown)? false before
--- any cast. Compared by base id, so a talent's form of the spell counts as the spell.
function BlizzardAPI.WasLastCast(spellID, gcdOnly)
    local last = gcdOnly and lastGcdCast or lastCast
    if not (last and spellID) then return false end
    return last == spellID or last == (BlizzardAPI.ResolveBaseSpellID(spellID) or spellID)
end

--------------------------------------------------------------------------------
-- Swing timer (WoW Forever). PLAYER_SWING carries swingDuration and swingType PLAIN in combat
-- (measured: 1.9s on a 1.9s weapon, inter-swing gaps 1.82-2.00s), so the last swing per type
-- plus its duration IS the swing timer. It is also the only plain in-combat attack speed -
-- UnitAttackSpeed is secret there - which makes attack-speed buffs visible as a shorter
-- swing against the out-of-combat base. Retail has no PLAYER_SWING: everything here stays
-- nil there and every caller falls back to its old behaviour.
--------------------------------------------------------------------------------
local SWING_MH, SWING_OH, SWING_RANGED = 0, 1, 2   -- Enum.PlayerSwingType
local swingLast, swingDur, swingBase = {}, {}, {}
local meleeActivityAt, meleeActivityTargetEpoch
local meleeTargetEpoch = 0

local function ReadTargetBoolean(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then
        geterrorhandler()(value)
        return nil
    end
    if IsSecretValue(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function HasLiveMeleeTarget()
    return ReadTargetBoolean(UnitExists, "target") == true
        and ReadTargetBoolean(UnitCanAttack, "player", "target") == true
        and ReadTargetBoolean(UnitIsDeadOrGhost, "target") == false
end

--- Last melee swing event in the current observed-target context, not a hit/range verdict.
--- The caller owns freshness. Combat entry preserves an immediately preceding opening swing.
function BlizzardAPI.GetMeleeActivityTime()
    if not BlizzardAPI.IsForever() or not meleeActivityAt then return nil end
    if meleeActivityTargetEpoch ~= meleeTargetEpoch or not HasLiveMeleeTarget()
       or BlizzardAPI.RunningAutoSwing(6603) ~= SWING_MH then
        meleeActivityAt, meleeActivityTargetEpoch = nil, nil
        return nil
    end
    return meleeActivityAt
end
-- An attack-speed gain at or above this reads as "boosted": every buff modelled
-- (SpellDB.HASTE_BUFFS) is 20% or more, gear-proc noise rarely reaches it.
local HASTE_BOOSTED = 1.08

--- Seconds until the next auto attack of swingType (0 main hand, 1 off hand, 2 ranged), or
--- nil when unknown: no swing seen, or none for a whole extra round (not auto-attacking).
function BlizzardAPI.GetSwingRemaining(swingType)
    local last, dur = swingLast[swingType], swingDur[swingType]
    if not (last and dur) then return nil end
    local rem = last + dur - GetTime()
    if rem < -dur then return nil end
    return rem > 0 and rem or 0
end

--- The current swing of swingType as (startTime, landTime), or nil when unknown (see
--- GetSwingRemaining). Drives the queue's fill on a queued next-swing ability.
function BlizzardAPI.GetSwingWindow(swingType)
    if not BlizzardAPI.GetSwingRemaining(swingType) then return nil end
    local last = swingLast[swingType]
    return last, last + swingDur[swingType]
end

local function IsAttackChecked(read, id)
    if not read then return false end
    local ok, active = pcall(read, id)
    if not ok then
        geterrorhandler()(active)
        return false
    end
    return not IsSecretValue(active) and active == true
end

--- Forever: 0 for running Attack or a queued next-swing ability, 2 for an active
--- auto-repeat (Auto Shot, wand Shoot), or nil without a confirmed pending swing.
--- Only a plain true counts. nil on retail: no swing timer there to show.
function BlizzardAPI.RunningAutoSwing(spellID)
    if not BlizzardAPI.IsForever() then return nil end
    local on, swingType
    if spellID == 6603 or (SpellDB and SpellDB.NEXT_SWING_SPELLS and SpellDB.NEXT_SWING_SPELLS[spellID]) then
        on, swingType = IsAttackChecked(C_Spell and C_Spell.IsCurrentSpell, spellID), 0
    else
        on, swingType = IsAttackChecked(C_Spell and C_Spell.IsAutoRepeatSpell, spellID), 2
    end
    if on then return swingType end
    -- Repeat shots can expose their checked state on the action button instead.
    if spellID == 75 or spellID == 5019 then
        local scanner = LibStub("JustAC-ActionBarScanner", true)
        local findSlot = scanner and (scanner.GetAutoAttackSlotForSpell or scanner.GetDirectSlotForSpell)
        local slot = findSlot and findSlot(spellID)
        if slot and C_ActionBar then
            if IsAttackChecked(C_ActionBar.IsCurrentAction, slot)
               or IsAttackChecked(C_ActionBar.IsAutoRepeatAction, slot) then
                return swingType
            end
        end
    end
    return nil
end

local damageBaseline, damageBaselineAt

local DAMAGE_BASELINE_REFRESH = 1

local function PlainDamageNumber(value)
    return not IsSecretValue(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

--- One auto attack from the character sheet: the average hit and interval of the ranged shot
--- (5019, 75) or of the main hand plus the off hand when one is equipped (6603). nil when
--- unreadable; an off hand that cannot be read leaves the whole answer unknown.
local function SheetSwing(spellID)
    local ok, speed, low, high
    if spellID == 5019 or spellID == 75 then
        if not UnitRangedDamage or not UnitAttackSpeed then return nil end
        ok, speed, low, high = pcall(UnitRangedDamage, "player")
        if not ok then geterrorhandler()(speed); return nil end
        local mainSpeed, _
        ok, mainSpeed, _, speed = pcall(UnitAttackSpeed, "player")
        if not ok then geterrorhandler()(mainSpeed); return nil end
        if not PlainDamageNumber(speed) or speed <= 0
           or not PlainDamageNumber(low) or not PlainDamageNumber(high) or low < 0 or high < low then return nil end
        return (low + high) / 2, speed
    elseif spellID == 6603 then
        if not UnitAttackSpeed or not UnitDamage then return nil end
        local offSpeed, offLow, offHigh
        ok, speed, offSpeed = pcall(UnitAttackSpeed, "player")
        if not ok then geterrorhandler()(speed); return nil end
        ok, low, high, offLow, offHigh = pcall(UnitDamage, "player")
        if not ok then geterrorhandler()(low); return nil end
        if not PlainDamageNumber(speed) or speed <= 0
           or not PlainDamageNumber(low) or not PlainDamageNumber(high) or low < 0 or high < low then return nil end
        if IsSecretValue(offSpeed) then return nil end
        if offSpeed == nil then return (low + high) / 2, speed end
        if not PlainDamageNumber(offSpeed) or offSpeed <= 0
           or not PlainDamageNumber(offLow) or not PlainDamageNumber(offHigh)
           or offLow < 0 or offHigh < offLow then return nil end
        return (low + high) / 2, speed, (offLow + offHigh) / 2, offSpeed
    end
    return nil
end

--- Damage per second of SheetSwing's answer, or nil.
local function SwingDPS(hit, speed, offHit, offSpeed)
    if not hit then return nil end
    local dps = hit / speed
    if offHit then dps = dps + offHit / offSpeed end
    if PlainDamageNumber(dps) and dps > 0 then return dps end
    return nil
end

local function ReadDamageNumber(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then
        geterrorhandler()(value)
        return nil
    end
    if PlainDamageNumber(value) then return value end
end

-- Estimate row: [1] base, [2] per-level gain, [3] spell level, [4] max level, [5] SP coefficient,
-- [6] school; then [7] 1 when a damage over time follows (or, with base 0, is) the hit, and that
-- damage over time's [8] full-duration base, [9] per-level gain, [10] SP coefficient and
-- [11] seconds when the data has them; [12] 1 for a measure-only row (an instant damage over time
-- with no hit: priced for measured damage, never by the public reads) else 0, [13] tick period.
local function ScaledDamage(e, baseline, base, perLevel, coefficient)
    if baseline and not damageBaseline then return nil end
    local level
    if baseline then
        level = damageBaseline.level
    else
        level = ReadDamageNumber(UnitLevel, "player")
    end
    if not level or level < e[3] then return nil end
    if e[4] > 0 then level = math.min(level, e[4]) end
    local damage = base + math.max(0, level - e[3]) * perLevel
    if coefficient ~= 0 then
        local bonus
        if baseline then
            bonus = damageBaseline.bonuses[e[6]]
        else
            bonus = ReadDamageNumber(GetSpellBonusDamage, e[6])
        end
        if not bonus then return nil end
        damage = damage + bonus * coefficient
    end
    if PlainDamageNumber(damage) and damage > 0 then return damage end
    return nil
end

local function DamageEstimate(spellID)
    if not BlizzardAPI.IsForever() then return nil end
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local RI = rotationImport
    return RI and RI.GetDirectDamageEstimate and RI.GetDirectDamageEstimate(spellID)
end

--- value scaled by what spellID's attack measured against its paper damage in earlier fights
--- (talents, crits, misses, resists: BlizzardAPI.GetMeasuredDamageRatio); unmeasured, as given.
--- Every damage read below answers with it, so every comparison sees the same correction.
local function Measured(spellID, value)
    if type(value) ~= "number" then return value end
    local ratio = BlizzardAPI.GetMeasuredDamageRatio and BlizzardAPI.GetMeasuredDamageRatio(spellID)
    if ratio then return value * ratio end
    return value
end

--- Is spellID's estimate priced for measured damage only (an instant damage over time with no
--- hit: its row's 12th field)? Such a spell never chooses an opener or a filler on its price.
function BlizzardAPI.IsMeasureOnlyEstimate(spellID)
    local e = DamageEstimate(spellID)
    return e ~= nil and e[12] == 1
end

--- Paper direct hit of one cast from the data model: excludes talents, crit and mitigation.
--- The measurement prices its casts with this, never with the measured read.
local function PaperSpellHit(spellID, baseline, wholeSpell)
    local e = DamageEstimate(spellID)
    if not e then return nil end
    -- A damage over time with no hit of its own (Corruption) has only a whole-spell figure.
    if e[1] == 0 then
        if not wholeSpell or not e[7] or not e[8] then return nil end
        return ScaledDamage(e, baseline, e[8], e[9], e[10])
    end
    local hit = ScaledDamage(e, baseline, e[1], e[2], e[5])
    if not hit or not wholeSpell or not e[7] then return hit end
    if not e[8] then return nil end
    local dot = ScaledDamage(e, baseline, e[8], e[9], e[10])
    if not dot then return nil end
    return hit + dot
end

--- Expected direct hit of one cast: the paper hit (PaperSpellHit), scaled by what the spell
--- measured. wholeSpell adds the full damage over time that follows the hit (nil when that
--- total is unknown); otherwise the hit alone. baseline=true uses captured pre-combat stats.
function BlizzardAPI.GetDirectSpellHit(spellID, baseline, wholeSpell)
    local e = DamageEstimate(spellID)
    if e and e[12] == 1 then return nil end   -- measure-only (an instant damage over time)
    return Measured(spellID, PaperSpellHit(spellID, baseline, wholeSpell))
end

--- Baseline direct spell DPS, not a simulator: excludes talents, crit and target mitigation.
--- baseline=true uses the explicitly captured pre-combat stats, not live combat stats.
--- A hit followed by a damage over time (e[7]) counts the part of it that runs during one cycle.
--- Per cycle: the cast time, but never less than the global cooldown the spell triggers
--- (measured from our own casts, BlizzardAPI.GetSpellGCD), so an instant has a DPS too. With no
--- GCD measured yet a cast-time spell falls back to its cast time (an upper bound below one GCD)
--- and an instant stays unknown. An explicit castSeconds is used as given.
--- A spell's current cast time in plain seconds (0 for an instant), or nil when unreadable.
--- Read fresh: a proc that makes the spell instant, or haste, changes it.
function BlizzardAPI.GetCastSeconds(spellID)
    if not (spellID and BlizzardAPI.GetSpellInfo) then return nil end
    local ok, info = pcall(BlizzardAPI.GetSpellInfo, spellID)
    if not ok then geterrorhandler()(info); return nil end
    if IsSecretValue(info) or type(info) ~= "table" or not PlainDamageNumber(info.castTime) then return nil end
    return info.castTime / 1000
end

function BlizzardAPI.GetSpellCycleSeconds(spellID)
    local cast = BlizzardAPI.GetCastSeconds(spellID)
    if not cast then return nil end
    local gcd = BlizzardAPI.GetSpellGCD and BlizzardAPI.GetSpellGCD(spellID)
    local cycle = cast
    if PlainDamageNumber(gcd) and gcd > cycle then cycle = gcd end
    if cycle <= 0 then return nil end
    return cycle, cast
end

--- Seconds before a DoT or HoT runs out at which to recast it, where a recast restarts the
--- effect and loses the ticks left (Forever): its cast time, so the new one lands as the last
--- tick goes and the player's own reaction puts it just after. A stacking aura adds one global
--- cooldown (the spell's measured GCD, else the unhasted 1.5s), since a drop loses every
--- stack. 0 for an instant that does not stack; an unreadable cast time counts as instant.
function BlizzardAPI.GetPeriodicRefreshLead(spellID, stacking)
    local lead = BlizzardAPI.GetCastSeconds(spellID) or 0
    if lead < 0 then lead = 0 end
    if stacking then
        local gcd = BlizzardAPI.GetSpellGCD and BlizzardAPI.GetSpellGCD(spellID)
        if not PlainDamageNumber(gcd) or gcd <= 0 then gcd = 1.5 end
        lead = lead + gcd
    end
    return lead
end

function BlizzardAPI.GetDirectSpellDPS(spellID, castSeconds, baseline)
    local e = DamageEstimate(spellID)
    if not e then return nil end
    if castSeconds == nil then castSeconds = BlizzardAPI.GetSpellCycleSeconds(spellID) end
    if not PlainDamageNumber(castSeconds) or castSeconds <= 0 then return nil end
    local damage = ScaledDamage(e, baseline, e[1], e[2], e[5])
    if not damage then return nil end
    if e[7] then
        -- Cast back to back, the next cast replaces the damage over time, so each cast is
        -- worth only the part that runs during its own cycle. Total or length unknown: unknown.
        local seconds = e[11]
        if not e[8] or not PlainDamageNumber(seconds) or seconds <= 0 then return nil end
        local dot = ScaledDamage(e, baseline, e[8], e[9], e[10])
        if not dot then return nil end
        damage = damage + dot * math.min(1, castSeconds / seconds)
    end
    local dps = damage / castSeconds
    if PlainDamageNumber(dps) and dps > 0 then return Measured(spellID, dps) end
    return nil
end

--- Expected equipped-weapon DPS: the sheet's, scaled by what the attack measured;
--- baseline=true starts from the captured pre-combat sheet.
function BlizzardAPI.GetAutoAttackDPS(spellID, baseline)
    if not BlizzardAPI.IsForever() then return nil end
    if baseline then return Measured(spellID, damageBaseline and damageBaseline.weapons[spellID]) end
    return Measured(spellID, SwingDPS(SheetSwing(spellID)))
end

--- Base mana regeneration per second captured with the pre-combat damage baseline, or nil.
function BlizzardAPI.GetBaselineManaRegen()
    return damageBaseline and damageBaseline.manaRegen
end

function BlizzardAPI.InvalidateDamageBaseline()
    damageBaseline, damageBaselineAt = nil, nil
end

--- Called by live hostile-target queue builds only; never refresh hidden combat stats.
function BlizzardAPI.RefreshDamageBaseline()
    if not BlizzardAPI.IsForever() or InCombatLockdown() then return end
    local now = GetTime()
    if damageBaselineAt and now - damageBaselineAt < DAMAGE_BASELINE_REFRESH then return end
    local rangedHit, rangedSpeed = SheetSwing(5019)
    local mainHit, mainSpeed, offHit, offSpeed = SheetSwing(6603)
    local ranged = SwingDPS(rangedHit, rangedSpeed)
    local melee = SwingDPS(mainHit, mainSpeed, offHit, offSpeed)
    local snapshot = {
        level = ReadDamageNumber(UnitLevel, "player"),
        bonuses = {},
        weapons = {
            [5019] = ranged,
            [75] = ranged,
            [6603] = melee,
        },
        -- Base regeneration read nil in combat in a 2026-11-16 capture; Spirit rarely changes
        -- mid-fight, so the comparison charges mana at the pre-combat rate like its damage.
        manaRegen = BlizzardAPI.GetBaseManaRegen and BlizzardAPI.GetBaseManaRegen(),
        -- Average damage of one swing by PLAYER_SWING type (0 main hand, 1 off hand, 2 ranged):
        -- the price of each auto attack the measurement counts.
        swingHit = {},
    }
    if melee then snapshot.swingHit[0], snapshot.swingHit[1] = mainHit, offHit end
    if ranged then snapshot.swingHit[2] = rangedHit end
    for school = 1, 7 do snapshot.bonuses[school] = ReadDamageNumber(GetSpellBonusDamage, school) end
    damageBaseline, damageBaselineAt = snapshot, now
end

--------------------------------------------------------------------------------
-- Measured damage (WoW Forever). The weapon comparison prices a weapon from the character
-- sheet and a spell from the data model: both leave out talents, crits, misses and resists, and
-- gear changes while levelling. After a fight the built-in damage meter's per-spell totals for
-- the player are plain (secret in combat: never read there), so the damage it measured over the
-- casts, ranged shots and melee swings counted, against their paper damage at the time, gives a
-- ratio per attack. The ratio carries over, not a number: a new weapon moves the paper figure at
-- once and the ratio keeps the talents, crit and hit it measured. No measurement: nil, paper
-- stands.
--------------------------------------------------------------------------------
-- Every key is the meter's own id: it reports a wand's damage as Auto Shot (75), never Shoot
-- (5019) (2026-11-18 warlock captures), and white melee as 6603 (2026-11-20 warrior capture).
local METER_ALIAS = { [5019] = 75 }
local RANGED_KEY, MELEE_KEY = 75, 6603
local SWING_KEYS = { [0] = MELEE_KEY, [1] = MELEE_KEY, [2] = RANGED_KEY }
local WEAPON_SLOT = { [RANGED_KEY] = INVSLOT_RANGED or 18, [MELEE_KEY] = INVSLOT_MAINHAND or 16 }
-- Weapon subclass -> skill line, as the character sheet maps them (PaperDollFrameStats, by
-- Enum.ItemWeaponSubclass name); a druid in a shapeshift form uses the feral skill.
local WEAPON_SKILL_BY_NAME = {
    Sword1H = 43, Axe1H = 44, Bows = 45, Guns = 46, Mace1H = 54, Sword2H = 55, Staff = 136,
    Mace2H = 160, Axe2H = 172, Dagger = 173, Thrown = 176, Crossbow = 226, Wand = 228,
    Polearm = 229, Unarmed = 162,
}
local FERAL_WEAPON_SKILL = 3014
local weaponSkillBySubclass
local MEASURE_KEEP = 0.7            -- weight of earlier fights each time a fight is added
local MEASURE_MIN_CASTS, MEASURE_MIN_SWINGS = 3, 8
local MEASURE_RATIO_MIN, MEASURE_RATIO_MAX = 0.25, 4   -- outside: the identities did not match
local MEASURE_SKILL_STEP = 5        -- weapon skill this much higher: earlier misses no longer apply
-- Normal levelling targets only: misses and resists climb steeply three or more levels above,
-- and a grey mob dies to overkill. The gap is the target's level minus the player's.
local MEASURE_GAP_MIN, MEASURE_GAP_MAX = -4, 2
local talentSignature               -- points spent per tree when the measurements were taken
local MEASURE_SESSIONS_KEPT = 8
local fightSession                  -- the meter session notified during this fight
-- Solo fights only: with a partner, kills come sooner and a shot in flight or the overkill of a
-- last hit lands nothing on the meter, so a grouped fight measures who else hit the mob, not
-- the attack (wand 0.85 and 0.92 in the two grouped fights of the 2026-11-20 priest capture,
-- 1.06 solo, skill 2 to 3 under its cap). A fight counts only when every press read not grouped.
local skipped = { grouped = 0, level = 0 }   -- fights left unmeasured, by reason (capture report)
local sessionTallies, sessionOrder = {}, {}
local measured = {}                 -- key -> { damage, paper, count, skill, gap }

--- Casts and swings per key: count, paper price, keys with an unpriced press, the meter damage
--- already credited, and the target level gap when the first press was counted. A fight's tally
--- also carries its damage over time: dotKeys (keys cast), dotTarget (the GUID every cast went on,
--- false once that is not one enemy) and dotSampled (the enemy count was read in combat).
local function NewTally()
    return { count = {}, paper = {}, bad = {}, credited = {}, dotKeys = {} }
end
local fightTally = NewTally()       -- since the last fight ended
-- Damage over time this fight. A cast is priced when its run ends: its hit plus the damage over
-- time for the part of its duration it could tick, until it expires, is recast (a refresh drops
-- the ticks left) or the fight ends. That stands for the target's death only in a fight with
-- one enemy, so a fight is measured for damage over time only when every such cast went on one
-- target and the engaged count read 1 at every sample (an inference from confirmed inputs).
local openDots = {}                 -- key -> { at, hit, dot, seconds, period } the running cast

local function MeasureKey(id)
    id = METER_ALIAS[id] or id
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local RI = rotationImport
    return RI and RI.RankBase and RI.RankBase(id) or id
end

--- n presses of key (default 1; -1 takes one back) at price each. An unpriced press leaves the
--- fight's total for that key unsplittable.
local function Tally(key, price, n)
    n = n or 1
    local t = fightTally
    t.count[key] = (t.count[key] or 0) + n
    if price then
        t.paper[key] = (t.paper[key] or 0) + price * n
    else
        t.bad[key] = true
    end
    if t.solo ~= false then
        t.solo = BlizzardAPI.IsGrouped ~= nil and BlizzardAPI.IsGrouped() == false
    end
    if not t.gapRead then
        t.gapRead = true
        local target, player = ReadDamageNumber(UnitLevel, "target"), ReadDamageNumber(UnitLevel, "player")
        if target and player and target > 0 then t.gap = target - player end
    end
end

--- Pre-combat sheet price of one swing of PLAYER_SWING type swingType, or nil.
local function SwingPrice(swingType)
    return damageBaseline and damageBaseline.swingHit[swingType]
end

--- The skill line of the weapon in the attack's slot (the feral skill in a druid form, Unarmed
--- with an empty melee slot), or nil.
local function WeaponSkillLine(key)
    if key == MELEE_KEY then
        if formCache == nil then formCache = LibStub("JustAC-FormCache", true) or false end
        local form = formCache and formCache.GetActiveForm and formCache.GetActiveForm()
        if type(form) == "number" and form ~= 0 and UnitClass then
            local ok, _, class = pcall(UnitClass, "player")
            if ok and class == "DRUID" then return FERAL_WEAPON_SKILL end
        end
    end
    local ok, itemID = pcall(GetInventoryItemID, "player", WEAPON_SLOT[key])
    if not ok or IsSecretValue(itemID) then return nil end
    if itemID == nil then
        if key == MELEE_KEY then return WEAPON_SKILL_BY_NAME.Unarmed end
        return nil
    end
    local _, classID, subclass
    ok, _, _, _, _, _, classID, subclass = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or classID ~= ((Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2) then return nil end
    if not weaponSkillBySubclass then
        weaponSkillBySubclass = {}
        local names = Enum and Enum.ItemWeaponSubclass
        for name, line in pairs(WEAPON_SKILL_BY_NAME) do
            if names and type(names[name]) == "number" then weaponSkillBySubclass[names[name]] = line end
        end
    end
    return weaponSkillBySubclass[subclass]
end

--- Skill (rank plus modifier) and its cap for the weapon in the attack's slot, or nil. Out of
--- combat only.
local function WeaponSkill(key)
    if InCombatLockdown() or not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and GetInventoryItemID
                                   and C_Item and C_Item.GetItemInfoInstant) then return nil end
    local line = WeaponSkillLine(key)
    if not line then return nil end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, line)
    if not ok or IsSecretValue(info) or type(info) ~= "table" then return nil end
    local rank, modifier, maxRank = info.rank, info.modifier, info.maxRank
    if not PlainDamageNumber(rank) or not PlainDamageNumber(maxRank) then return nil end
    if not PlainDamageNumber(modifier) then modifier = 0 end
    return rank + modifier, maxRank
end

--- One engaged-enemy sample for this fight's damage over time (in combat only). Once it is
--- not one enemy, further samples change nothing.
local function SampleEnemies()
    local t = fightTally
    if t.dotTarget == false or not next(openDots) or not InCombatLockdown() then return end
    t.dotSampled = true
    if (BlizzardAPI.GetEngagedEnemyCount and BlizzardAPI.GetEngagedEnemyCount()) ~= 1 then t.dotTarget = false end
end

--- Is a pet out (a plain true; unknown counts as out)?
local function PetOut()
    local ok, exists = pcall(UnitExists, "pet")
    return not ok or IsSecretValue(exists) or exists ~= false and exists ~= nil
end

--- One auto attack (PLAYER_SWING, Forever only: 0 main hand, 1 off hand, 2 ranged). The meter
--- files a pet's damage under its owner (a warlock's imp Firebolt, 2026-11-18 captures); whether
--- a pet's white swings land in the owner's melee row is not known, so a fight with a pet out is
--- not measured for melee.
local function NoteSwing(swingType)
    local key = SWING_KEYS[swingType]
    if key then
        Tally(key, SwingPrice(swingType))
        if key == MELEE_KEY and not fightTally.bad[MELEE_KEY] and PetOut() then fightTally.bad[MELEE_KEY] = true end
    end
    SampleEnemies()
end

--- The run of key's damage over time ends at now: it is counted, priced for the part of its
--- duration it could tick.
local function CloseDot(key, now)
    local d = openDots[key]
    if not d then return end
    openDots[key] = nil
    local elapsed = math.max(0, now - d.at)
    local ran
    if d.period then
        -- Ticks land every period after the cast: a run cut short has ticked whole periods.
        local ticks = math.min(math.floor(elapsed / d.period + 1e-6), math.floor(d.seconds / d.period + 1e-6))
        ran = ticks * d.period / d.seconds
    else
        ran = math.min(1, elapsed / d.seconds)
    end
    Tally(key, d.hit + d.dot * ran)
end

--- A cast with damage over time: the previous run of the same spell ends (a refresh), this one
--- starts. Unpriceable (no pre-combat stats, no duration): the fight's total for it cannot be
--- split.
local function OpenDot(spellID, e)
    local key, now = MeasureKey(spellID), GetTime()
    CloseDot(key, now)
    local hit = 0
    if e[1] ~= 0 then hit = ScaledDamage(e, true, e[1], e[2], e[5]) end
    local dot = e[8] and ScaledDamage(e, true, e[8], e[9], e[10])
    local seconds = e[11]
    if not (hit and dot and PlainDamageNumber(seconds) and seconds > 0) then
        Tally(key, nil)
        return
    end
    local period = e[13]
    if not (PlainDamageNumber(period) and period > 0) then period = nil end
    openDots[key] = { at = now, hit = hit, dot = dot, seconds = seconds, period = period }
    local t = fightTally
    t.dotKeys[key] = true
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or IsSecretValue(guid) or type(guid) ~= "string" then
        t.dotTarget = false
    elseif t.dotTarget == nil then
        t.dotTarget = guid
    elseif t.dotTarget ~= guid then
        t.dotTarget = false
    end
    SampleEnemies()
end

--- The fight ended: every running damage over time ends now. Unless the fight had one enemy
--- throughout, its damage over time is left unmeasured.
local function CloseDots()
    local now, t = GetTime(), fightTally
    for key in pairs(openDots) do CloseDot(key, now) end
    if t.dotTarget == false or not t.dotSampled then
        for key in pairs(t.dotKeys) do t.bad[key] = true end
    end
end

--- One of the player's casts succeeded (from NoteOwnCast, Forever only). A next-swing attack
--- (Heroic Strike, Cleave, Maul, Raptor Strike) took a main-hand swing whose damage is its own,
--- not a white hit's: that swing leaves the white count (its PLAYER_SWING fires at the same
--- moment, 2026-11-20 warrior capture). A direct hit with no damage over time is counted.
NoteDamageCast = function(spellID)
    if type(spellID) ~= "number" or METER_ALIAS[spellID] or spellID == RANGED_KEY then return end
    if SpellDB and SpellDB.NEXT_SWING_SPELLS and SpellDB.NEXT_SWING_SPELLS[spellID] then
        Tally(MELEE_KEY, SwingPrice(0), -1)
        return
    end
    local e = DamageEstimate(spellID)
    if not e then return end
    if e[7] then
        -- A channel's run ends when the channel stops, which no refresh or fight end marks.
        if not (SpellDB and SpellDB.IsChanneled and SpellDB.IsChanneled(spellID)) then OpenDot(spellID, e) end
        return
    end
    if e[1] == 0 then return end
    Tally(MeasureKey(spellID), PaperSpellHit(spellID, true))
    SampleEnemies()
end

local function Credit(key, damage, paper, count, skill, gap)
    local m = measured[key]
    if not m or (skill and m.skill and skill - m.skill >= MEASURE_SKILL_STEP) then
        m = { damage = 0, paper = 0, count = 0 }
        measured[key] = m
    end
    m.damage = m.damage * MEASURE_KEEP + damage
    m.paper = m.paper * MEASURE_KEEP + paper
    m.count = m.count * MEASURE_KEEP + count
    m.skill, m.gap = skill, gap
end

--- The meter's damage per key of the session (keys the tally counted), or nil while it cannot
--- be read: in combat, no source, or any field secret.
local function SessionDamage(sessionID, guid, tally)
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID,
        Enum.DamageMeterType.DamageDone, guid)
    if not ok or IsSecretValue(source) or type(source) ~= "table" then return nil end
    local list = source.combatSpells
    if IsSecretValue(list) or type(list) ~= "table" then return nil end
    local damage = {}
    for i = 1, #list do
        local spell = list[i]
        if type(spell) ~= "table" or IsSecretValue(spell) then return nil end
        local id, amount = spell.spellID, spell.totalAmount
        if not (PlainDamageNumber(id) and PlainDamageNumber(amount)) then return nil end
        local key = MeasureKey(id)
        if tally.count[key] then damage[key] = (damage[key] or 0) + amount end
    end
    return damage
end

--- Read the meter for finished fights still waiting (only sessionID's when given). Out of
--- combat only. Credited presses are zeroed, so a session read again (one session can span
--- pulls) credits only what it gained since; a spell the meter does not list yet waits, since
--- an absent row is not proof that every cast missed.
local function ReadMeterSessions(onlySession)
    if InCombatLockdown() or not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromID
                                  and Enum and Enum.DamageMeterType) then return end
    local guid = UnitGUID and UnitGUID("player")
    if IsSecretValue(guid) or type(guid) ~= "string" then return end
    local skills
    for _, sessionID in ipairs(sessionOrder) do
        local tally = (onlySession == nil or sessionID == onlySession) and sessionTallies[sessionID]
        local damage = tally and SessionDamage(sessionID, guid, tally)
        if damage then
            for key, count in pairs(tally.count) do
                local total, paper = damage[key], tally.paper[key]
                local gained = total and total - (tally.credited[key] or 0)
                if gained and gained >= 0 and count > 0 and paper and paper > 0 and not tally.bad[key] then
                    if not skills then
                        skills = { [RANGED_KEY] = WeaponSkill(RANGED_KEY), [MELEE_KEY] = WeaponSkill(MELEE_KEY) }
                    end
                    Credit(key, gained, paper, count, skills[key], tally.gap)
                    tally.credited[key], tally.count[key], tally.paper[key] = total, 0, 0
                end
            end
        end
    end
end

--- A fight ended: its tally joins its meter session's. A fight the meter named no session
--- for cannot be matched and is dropped.
local function CloseFight()
    local fight, sessionID = fightTally, fightSession
    fightTally, fightSession = NewTally(), nil
    if not sessionID or not next(fight.count) then return end
    local reason
    if not fight.solo then
        reason = "grouped"
    elseif not fight.gap or fight.gap < MEASURE_GAP_MIN or fight.gap > MEASURE_GAP_MAX then
        reason = "level"
    end
    if reason then
        skipped[reason] = skipped[reason] + 1
        return
    end
    local tally = sessionTallies[sessionID]
    if not tally then
        tally = NewTally()
        sessionTallies[sessionID] = tally
        sessionOrder[#sessionOrder + 1] = sessionID
        if #sessionOrder > MEASURE_SESSIONS_KEPT then
            sessionTallies[table.remove(sessionOrder, 1)] = nil
        end
    end
    for key, count in pairs(fight.count) do
        tally.count[key] = (tally.count[key] or 0) + count
        tally.paper[key] = (tally.paper[key] or 0) + (fight.paper[key] or 0)
        if fight.bad[key] then tally.bad[key] = true end
    end
    if tally.gap == nil then tally.gap = fight.gap end
end

--- Points spent per tree as one string, or nil when unreadable.
local function TalentSignature()
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local RI = rotationImport
    if not (RI and RI.SpentByTree) then return nil end
    local ok, _, spent = pcall(RI.SpentByTree)
    if not ok or type(spent) ~= "table" then return nil end
    local parts = {}
    for group, n in pairs(spent) do
        if PlainDamageNumber(group) and PlainDamageNumber(n) then parts[#parts + 1] = group .. ":" .. n end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

--- Measurements survive /reload and logout, per character (JustACDB char): learning takes
--- several fights, and the player reloads often (to save a capture). Restored once, with the
--- talents they were taken under; the saved table is then the live one, so it is current
--- whenever the game saves. Returns the character's saved data, or nil before the addon loads.
local function RestoreMeasured()
    local addon = BlizzardAPI.GetAddon and BlizzardAPI.GetAddon()
    local char = addon and addon.db and addon.db.char
    if not char or char.measuredDamage == measured then return char end
    local saved = char.measuredDamage
    if type(saved) == "table" then
        for key, m in pairs(saved) do
            if type(key) == "number" and type(m) == "table" and PlainDamageNumber(m.damage)
               and PlainDamageNumber(m.paper) and PlainDamageNumber(m.count) and m.paper > 0 then
                measured[key] = m
            end
        end
        if type(char.measuredTalents) == "string" then talentSignature = char.measuredTalents end
    end
    char.measuredDamage = measured
    return char
end

--- Talents spent differently from when the measurements were taken: they no longer apply.
local function NoteTalents()
    local char = RestoreMeasured()
    local signature = TalentSignature()
    if signature == nil or signature == talentSignature then return end
    if talentSignature ~= nil then wipe(measured) end
    talentSignature = signature
    if char then char.measuredTalents = signature end
end
BlizzardAPI._NoteTalents = NoteTalents

local function ForgetSessions()
    wipe(sessionTallies)
    wipe(sessionOrder)
    fightSession = nil
end

local function RatioForKey(key)
    local m = measured[key]
    if not m or m.paper <= 0 then return nil end
    local need = MEASURE_MIN_CASTS
    if key == RANGED_KEY or key == MELEE_KEY then need = MEASURE_MIN_SWINGS end
    if m.count < need then return nil end
    -- Damped toward paper: as if `need` more presses had landed at exactly their paper price,
    -- so a few lucky crits or misses move it gradually and real data takes over as it comes.
    local prior = need * m.paper / m.count
    local ratio = (m.damage + prior) / (m.paper + prior)
    if ratio < MEASURE_RATIO_MIN or ratio > MEASURE_RATIO_MAX then return nil end
    return ratio, m.count
end

--- Measured damage over paper damage for spellID's attack (ranged: 5019 or 75; melee: 6603),
--- and the weighted count behind it; nil until enough has been measured or when implausible.
function BlizzardAPI.GetMeasuredDamageRatio(spellID)
    if not spellID or next(measured) == nil or not BlizzardAPI.IsForever() then return nil end
    return RatioForKey(MeasureKey(spellID))
end

--- Every measurement, for the capture: key=ratio count used skill gap, then weapon skills and
--- waiting sessions.
function BlizzardAPI.GetMeasuredDamageReport()
    local keys = {}
    for key in pairs(measured) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local m = measured[key]
        local ratio = m.paper > 0 and m.damage / m.paper or nil
        parts[#parts + 1] = string.format("%d=%s:count=%.1f:used=%s:skill=%s:gap=%s", key,
            ratio and string.format("%.3f", ratio) or "nil", m.count, tostring(RatioForKey(key) ~= nil),
            tostring(m.skill), tostring(m.gap))
    end
    for _, key in ipairs({ RANGED_KEY, MELEE_KEY }) do
        local skill, maxSkill = WeaponSkill(key)
        parts[#parts + 1] = (key == RANGED_KEY and "rangedSkill=" or "meleeSkill=")
            .. tostring(skill) .. "/" .. tostring(maxSkill)
    end
    parts[#parts + 1] = "sessions=" .. #sessionOrder
    parts[#parts + 1] = "groupedSkipped=" .. skipped.grouped
    parts[#parts + 1] = "levelSkipped=" .. skipped.level
    return table.concat(parts, " ")
end

--- Tests: forget every measurement and tally.
function BlizzardAPI._ResetMeasuredDamage()
    wipe(measured)
    ForgetSessions()
    fightTally = NewTally()
    skipped.grouped, skipped.level, talentSignature = 0, 0, nil
    wipe(openDots)
end


-- PLAYER_SWING_RANGE_UPDATE (Forever): (swingType, inRange, checksRange), plain in combat and
-- fired on every target change and range crossing (measured build 70245: a target acquired
-- from a distance read false/true, walking into melee true/true, a dead target true/false).
local swingInRange = {}

--- Is the current target within auto-attack reach of swingType (0 main hand, 2 ranged)?
--- The game's own range check: true / false, or nil with no target or no event seen (retail).
function BlizzardAPI.IsTargetInSwingRange(swingType)
    local swingTimer = _G.C_SwingTimer
    if BlizzardAPI.IsForever() and swingTimer and swingTimer.IsTargetWithinSwingRange then
        local ok, inRange = pcall(swingTimer.IsTargetWithinSwingRange, swingType)
        if not ok then
            geterrorhandler()(inRange)
        elseif not IsSecretValue(inRange) and type(inRange) == "boolean" then
            return inRange
        end
    end
    return swingInRange[swingType]
end

--- Current attack speed relative to the out-of-combat base for swingType: 1.0 normal, 1.3 =
--- 30% faster. nil without a recent swing or a known base.
function BlizzardAPI.GetSwingHaste(swingType)
    local last, dur, base = swingLast[swingType], swingDur[swingType], swingBase[swingType]
    if not (last and dur and base and dur > 0) then return nil end
    if GetTime() - last > 2 * dur then return nil end
    return base / dur
end

-- The base speeds: read only while they are plain (out of combat). ponytail: a haste buff
-- already up when this reads inflates the base; refreshed on every equip / speed change OOC.
local function RefreshSwingBase()
    if InCombatLockdown() then return end
    local okA, mh, oh = pcall(UnitAttackSpeed, "player")
    if okA then
        if type(mh) == "number" and not IsSecretValue(mh) and mh > 0 then swingBase[SWING_MH] = mh end
        if type(oh) == "number" and not IsSecretValue(oh) and oh > 0 then swingBase[SWING_OH] = oh end
    end
    local okR, ranged = pcall(UnitRangedDamage, "player")
    if okR and type(ranged) == "number" and not IsSecretValue(ranged) and ranged > 0 then
        swingBase[SWING_RANGED] = ranged
    end
end

-- The first shot after Auto Shot (or a wand) is switched on: the previous shot's cooldown keeps
-- running while it is off, so the shot comes when that runs out, or FIRST_SHOT_AIM after a press
-- made standing still, whichever is later. Measured on Forever (build 70245, START_AUTOREPEAT_SPELL
-- to the first ranged PLAYER_SWING, 10 presses): 0.08-0.16s - quicker than the aim after a stop
-- (0.27-0.50s). Seeding that window lets the swing bar show it from the press instead of
-- from the first shot; the shot's own PLAYER_SWING then replaces it.
local FIRST_SHOT_AIM = 0.15
local rangedShotAt   -- the last real ranged shot (kept through Auto Shot being switched off)

local function SeedRangedWindow()
    local dur = swingDur[SWING_RANGED] or swingBase[SWING_RANGED]
    if not dur then return end
    local now = GetTime()
    local landAt = now + FIRST_SHOT_AIM
    if rangedShotAt and rangedShotAt + dur > landAt then landAt = rangedShotAt + dur end
    swingLast[SWING_RANGED], swingDur[SWING_RANGED] = landAt - dur, dur
end

do
    local f = CreateFrame("Frame")
    -- pcall: PLAYER_SWING only exists on Forever.
    if pcall(f.RegisterEvent, f, "PLAYER_SWING") then
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
        pcall(f.RegisterEvent, f, "PLAYER_SWING_RANGE_UPDATE")
        pcall(f.RegisterEvent, f, "PLAYER_LEAVE_COMBAT")     -- Attack switched off
        pcall(f.RegisterEvent, f, "STOP_AUTOREPEAT_SPELL")   -- Auto Shot / wand switched off
        pcall(f.RegisterEvent, f, "START_AUTOREPEAT_SPELL")  -- ... and on: seed the first shot
        f:SetScript("OnEvent", function(_, event, duration, swingType, checksRange)
            if event == "PLAYER_SWING" then
                if not IsSecretValue(swingType) and not IsSecretValue(duration)
                   and type(swingType) == "number" and type(duration) == "number" and duration > 0 then
                    swingLast[swingType], swingDur[swingType] = GetTime(), duration
                    if swingType == SWING_RANGED then rangedShotAt = swingLast[swingType] end
                    NoteSwing(swingType)
                    if swingType == SWING_MH or swingType == SWING_OH then
                        meleeActivityTargetEpoch = nil
                        meleeActivityAt = nil
                        if HasLiveMeleeTarget() then
                            meleeActivityAt = swingLast[swingType]
                            meleeActivityTargetEpoch = meleeTargetEpoch
                        end
                    end
                end
            elseif event == "START_AUTOREPEAT_SPELL" then
                SeedRangedWindow()
            elseif event == "PLAYER_LEAVE_COMBAT" then
                -- Stopped: the last swing no longer times anything, so no bar shows a stale
                -- sweep when it is switched back on; the next real swing restarts it.
                swingLast[SWING_MH], swingLast[SWING_OH] = nil, nil
                meleeActivityAt, meleeActivityTargetEpoch = nil, nil
            elseif event == "STOP_AUTOREPEAT_SPELL" then
                swingLast[SWING_RANGED] = nil
            elseif event == "PLAYER_SWING_RANGE_UPDATE" then
                -- Payload (swingType, inRange, checksRange); the first argument slot is named
                -- for PLAYER_SWING above.
                local st, inRange = duration, swingType
                if type(st) == "number" and type(inRange) == "boolean" and type(checksRange) == "boolean" then
                    if checksRange then swingInRange[st] = inRange else swingInRange[st] = nil end
                end
            elseif event == "PLAYER_TARGET_CHANGED" then
                wipe(swingInRange)
                meleeTargetEpoch = meleeTargetEpoch + 1
                meleeActivityAt, meleeActivityTargetEpoch = nil, nil
            else
                if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED"
                   or event == "PLAYER_REGEN_ENABLED" then
                    BlizzardAPI.InvalidateDamageBaseline()
                    meleeActivityAt, meleeActivityTargetEpoch = nil, nil
                end
                -- The range event fires only for swing types with a range check enabled. Once
                -- per world entry: every call resets the check (and fires a "no target" update).
                if event == "PLAYER_ENTERING_WORLD" and C_SwingTimer and C_SwingTimer.EnableRangeCheck then
                    pcall(C_SwingTimer.EnableRangeCheck, SWING_MH, true)
                    pcall(C_SwingTimer.EnableRangeCheck, SWING_RANGED, true)
                end
                RefreshSwingBase()
            end
        end)
    end
end

-- Measured damage: fight ends and meter sessions (see "Measured damage" above). Forever only;
-- casts arrive through NoteOwnCast.
if FOREVER_CLIENT then
    local f = CreateFrame("Frame")
    -- pcall: the damage meter's events exist only where the meter does.
    if pcall(f.RegisterEvent, f, "DAMAGE_METER_COMBAT_SESSION_UPDATED") then
        pcall(f.RegisterEvent, f, "DAMAGE_METER_RESET")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        for _, talentEvent in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
                                       "CHARACTER_POINTS_CHANGED" }) do
            pcall(f.RegisterEvent, f, talentEvent)
        end
        f:SetScript("OnEvent", function(_, event, kind, sessionID)
            if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
                -- Payload (type, sessionID). The session a fight's damage goes to is the one
                -- notified while it runs; after it, an update is the moment to read that session.
                -- Each update also comes as session 0, the current-fight placeholder, in the same
                -- moment and after the real id (2026-11-20 priest capture): 0 is never a session.
                local damageDone = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
                if IsSecretValue(kind) or IsSecretValue(sessionID) or type(sessionID) ~= "number"
                   or sessionID <= 0 or (damageDone ~= nil and kind ~= damageDone) then return end
                if InCombatLockdown() then
                    fightSession = sessionID
                elseif sessionTallies[sessionID] then
                    ReadMeterSessions(sessionID)
                end
            elseif event == "DAMAGE_METER_RESET" then
                ForgetSessions()
            elseif event ~= "PLAYER_REGEN_ENABLED" then
                NoteTalents()
            else
                CloseDots()
                CloseFight()
                if C_Timer and C_Timer.After then
                    C_Timer.After(1, function() ReadMeterSessions() end)
                else
                    ReadMeterSessions()
                end
            end
        end)
    end
end

--- An attack-speed buff from SpellDB.HASTE_BUFFS, judged by the swings after its cast.
--- @return boolean|nil true/false once a swing since the cast has been seen; nil otherwise
local function HasteBuffEvidence(spellID)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local h = SpellDB and SpellDB.HASTE_BUFFS and SpellDB.StaticLookup(SpellDB.HASTE_BUFFS, spellID)
    local castAt = h and ownCastAt[spellID]
    if not castAt or GetTime() - castAt > h.max then return nil end
    -- A swing that STARTED before the cast still ran at the old speed: only a later one counts.
    local last = swingLast[h.swing]
    if not last or last <= castAt then return nil end
    local haste = BlizzardAPI.GetSwingHaste(h.swing)
    if haste == nil then return nil end
    -- ponytail: two modelled buffs on one swing type cannot be told apart - while either is
    -- up, both read as up. Per-buff ratios would need the exact talent-scaled percentages.
    return haste >= HASTE_BOOSTED
end

-- Evidence independent of a gate's cast-duration fallback. Nil permits that
-- fallback; a known false (form, CDM or swing evidence) overrides it.
local function BuffWindowEvidence(spellID, readCache)
    if formCache == nil then formCache = LibStub("JustAC-FormCache", true) or false end
    local formID = formCache and formCache.GetFormIDBySpellID(spellID)
    if formID then return formCache.GetActiveForm() == formID, "form" end
    -- WoW Forever: a buff the player tracks in the Cooldown Manager is read off Blizzard's own
    -- icon - exact, and the only aura state readable in combat there. Untracked: on to the rest.
    local forever = BlizzardAPI.IsForever and BlizzardAPI.IsForever()
    if forever then
        if maintenanceTracker == nil then
            maintenanceTracker = LibStub("JustAC-MaintenanceTracker", true) or false
        end
        -- Not `x and x.f()`: with the module missing that is false, read as "buff down".
        local tracked
        if maintenanceTracker then tracked = maintenanceTracker.IsTrackedAuraActive(spellID, nil, readCache) end
        if tracked ~= nil then return tracked, "cooldown-manager" end
    end
    -- An attack-speed buff is proven by the swings themselves (Forever): its length can
    -- depend on combo points, and an early cancel or dispel shows as the speed going away.
    local evidence = HasteBuffEvidence(spellID)
    if evidence ~= nil then return evidence, "swing-haste" end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return nil
    end
    -- The aura table in hand proves the buff is up. Its duration adds nothing and cost
    -- two answers: GetAuraDuration is access-denied to a tainted caller while auras are
    -- secret (12.1.0), and a buff with no expiry (Prowl, Shadowmeld) has an empty duration
    -- that read as down while it was up.
    -- Forever ranks: the aura carries the rank that was cast, so every rank is asked.
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local chain = rotationImport and rotationImport.RankChain(spellID)
    for i = 1, chain and #chain or 1 do
        -- Protected: on Forever (build 70245) the aura LIST calls throw in combat; this lookup
        -- has not, but a throw here would blank the whole queue build.
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, chain and chain[i] or spellID)
        if ok and aura and aura.auraInstanceID then
            -- Remember the expiry while it reads plain (out of combat): in combat the aura
            -- is unreadable, and a /reload forgets the cast that would otherwise time it.
            local exp = aura.expirationTime
            if type(exp) == "number" and not IsSecretValue(exp) and exp > 0 and forever then
                auraUntil[spellID], auraUntilReadAt[spellID] = exp, GetTime()
            end
            -- Its real length too (an Improved talent, a higher rank): the next cast is timed
            -- with it once the aura goes unreadable again.
            local length = aura.duration
            if type(length) == "number" and not IsSecretValue(length) and length > 0 and forever then
                learnedDuration[spellID] = length
            end
            return true, "aura"
        end
    end
    -- Retail: unchanged - the cast window is the whole fallback there. (A remembered expiry
    -- would also hold a buff consumed early in combat "up" until its old expiry.)
    if not forever then return nil end
    if not BlizzardAPI.AreAurasSecret() then
        auraUntil[spellID] = nil   -- readable and absent: really gone
        return nil
    end
    local untilAt = auraUntil[spellID]
    if untilAt ~= nil and GetTime() < untilAt
       and not RemovedSince(AuraRemovedAt(spellID), auraUntilReadAt[spellID]) then
        return true, "remembered-expiry"
    end
    return nil
end

--- When no evidence answered: our own cast plus the buff's duration. Returns active, source.
local function CastWindowFallback(spellID, durSecs)
    durSecs = learnedDuration[spellID] or durSecs
    local castAt = durSecs and ownCastAt[spellID]
    if RemovedSince(AuraRemovedAt(spellID), castAt, REMOVAL_GRACE) then return false, "aura-removed" end
    if castAt ~= nil then return (GetTime() - castAt) < durSecs, "cast-estimate" end
    return false, "no-evidence"
end

-- How good each buff source is. Unlisted sources are the game's own answer: "confirmed".
-- Estimated: inferred from swing speed, remembered from an expiry read before combat, or our
-- cast time plus a duration.
local BUFF_EVIDENCE = {
    ["swing-haste"] = "estimated", ["remembered-expiry"] = "estimated",
    ["cast-estimate"] = "estimated", ["no-evidence"] = "none",
}

--- IsBuffWindowActive's verdict with the quality of the evidence behind it: active, grade
--- ("confirmed" / "estimated" / "none"), source. Diagnostics: read fresh, never cached, and
--- nothing on the queue path decides from the grade.
function BlizzardAPI.GetBuffWindowEvidence(spellID, durSecs)
    if not spellID then return false, "none", "invalid-spell" end
    local active, source = BuffWindowEvidence(spellID, nil)
    if active == nil then active, source = CastWindowFallback(spellID, durSecs) end
    return active, BUFF_EVIDENCE[source] or "confirmed", source
end

--- Seconds left on a self-buff window from plain evidence only, most reliable first:
---   1. the expiry this spell's aura showed while it read plain (the real aura: talents and
---      ranks included);
---   2. the last complete out-of-combat aura scan (also the real aura, any rank);
---   3. our own cast plus its full duration: the length its aura last showed while plain
---      (talents and ranks included), else the data's base duration (an estimate).
--- A reading taken before our latest cast describes the previous application, so it yields
--- to the cast. nil when nothing is known; never read from a live aura in combat.
local redundancyFilter   -- resolved on first use: loads after this file
function BlizzardAPI.GetBuffWindowRemaining(spellID, durSecs)
    if not spellID then return nil end
    local now = GetTime()
    local castAt = ownCastAt[spellID]
    local untilAt, readAt = auraUntil[spellID], auraUntilReadAt[spellID]
    -- A removal seen after a source (dispelled, cancelled, expired early) ends what it said.
    local removedAt = AuraRemovedAt(spellID)
    if untilAt ~= nil and untilAt > now and not (castAt and readAt and castAt > readAt)
       and not RemovedSince(removedAt, readAt) then
        return untilAt - now
    end
    if redundancyFilter == nil then redundancyFilter = LibStub("JustAC-RedundancyFilter", true) or false end
    if redundancyFilter and redundancyFilter.GetTrustedAuraExpiry then
        if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
        local chain = rotationImport and rotationImport.RankChain(spellID)
        for i = 1, chain and #chain or 1 do
            local exp, takenAt = redundancyFilter.GetTrustedAuraExpiry(chain and chain[i] or spellID)
            if exp and not (castAt and takenAt and castAt > takenAt) and not RemovedSince(removedAt, takenAt) then
                return exp - now
            end
        end
    end
    durSecs = learnedDuration[spellID] or durSecs
    if RemovedSince(removedAt, castAt, REMOVAL_GRACE) then return nil end
    if castAt ~= nil and durSecs and now - castAt < durSecs then return durSecs - (now - castAt) end
    return nil
end

--- Seconds since our own last cast of this spell (any rank), or nil when never seen.
function BlizzardAPI.GetOwnCastAge(spellID)
    local castAt = spellID and ownCastAt[spellID]
    if castAt == nil then return nil end
    return GetTime() - castAt
end

--- The totem slot's own timer: a DurationObject for a cooldown widget, never read. nil when the
--- read fails.
function BlizzardAPI.GetTotemDurationObject(slot)
    if not (slot and GetTotemDuration) then return nil end
    local ok, duration = pcall(GetTotemDuration, slot)
    if ok then return duration end
    return nil
end

local totemDurationLearned = {}   -- [rank-1 totem spell] = seconds, read while GetTotemInfo was plain

--- Plain start, length for the totem in a slot, most reliable first:
---   1. GetTotemInfo while it reads plain (which also learns that totem's duration);
---   2. our latest cast of a totem for this slot plus the duration learned for it.
--- nil when unknown, and when the slot reads plainly empty.
function BlizzardAPI.GetTotemWindow(slot)
    if not slot then return nil end
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    if GetTotemInfo then
        local ok, have, _, start, duration, _, _, spellID = pcall(GetTotemInfo, slot)
        if ok then
            if not IsSecretValue(have) and have == false then return nil end
            start, duration, spellID = Unsecret(start), Unsecret(duration), Unsecret(spellID)
            if type(duration) == "number" and duration > 0 then
                if type(spellID) == "number" and spellID > 0 then
                    local r1 = rotationImport and rotationImport.RankBase(spellID)
                    totemDurationLearned[r1 or spellID] = duration
                end
                if type(start) == "number" and start > 0 then return start, duration end
            end
        end
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local slots = SpellDB and SpellDB.FOREVER_TOTEM_SLOTS
    if not slots then return nil end
    -- The latest totem cast into this slot decides, even when its duration is not known.
    local lastAt, lastSpell
    for spellID, s in pairs(slots) do
        local castAt = s == slot and ownCastAt[spellID]
        if castAt and (not lastAt or castAt > lastAt) then lastAt, lastSpell = castAt, spellID end
    end
    local known = lastSpell and totemDurationLearned[lastSpell]
    if known and GetTime() - lastAt < known then return lastAt, known end
    return nil
end

local BUFF_UNKNOWN = {}

--- readCache is owned and cleared by the caller for each synchronous queue pass.
--- Cache evidence, not duration-dependent cast estimates: two gates may name
--- the same buff with different fallback windows.
--- @param spellID number
--- @param durSecs number|nil base aura seconds; nil disables cast inference
function BlizzardAPI.IsBuffWindowActive(spellID, durSecs, readCache)
    if not spellID then return false end
    local reads = readCache and readCache.buffs
    local evidence = reads and reads[spellID]
    if evidence == nil then
        evidence = BuffWindowEvidence(spellID, readCache)
        if reads then
            if evidence == nil then
                reads[spellID] = BUFF_UNKNOWN
            else
                reads[spellID] = evidence
            end
        end
    end
    if evidence ~= nil and evidence ~= BUFF_UNKNOWN then return evidence end
    return (CastWindowFallback(spellID, durSecs))
end

--- Diagnostic: which of the given self-buff ids are active right now.
--- @param ids number[] spell ids to probe
--- @return table snapshot array of { id, active }
function BlizzardAPI.GetBuffWindowSnapshot(ids)
    local out = {}
    if type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        out[#out + 1] = { id = id, active = BlizzardAPI.IsBuffWindowActive(id) }
    end
    return out
end

-- Talents change base cooldowns; the cache refills on the next out-of-combat read.
do
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    f:RegisterEvent("PLAYER_TALENT_UPDATE")
    f:RegisterEvent("TRAIT_CONFIG_UPDATED")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    f:SetScript("OnEvent", function()
        wipe(baseCdSecondsCache)
        BlizzardAPI.InvalidateDamageBaseline()
    end)
end

--- Returns true when a charge-based spell has 0 charges remaining. Engine truth: the main
--- cooldown is inactive while any charge is banked and active at zero; isOnGCD == true is
--- the global cooldown over banked charges, not depletion. Unknown reads false (fail-open).
function BlizzardAPI.IsChargeSpellOnCooldown(spellID)
    if not (IsChargeSpell(spellID) and C_Spell_GetSpellCooldown) then return false end
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd or IsSecretValue(cd.isActive) then return false end
    return cd.isActive == true and cd.isOnGCD ~= true
end

--- Returns true when a charge-based spell has ALL of its charges banked - the same
--- engine read as IsSpellChargeCapped, so the "hold until charged" dial and the
--- charge-cap promotion can never disagree. Its doubt goes the OTHER way: a
--- chargeless spell or an unreadable state reads as "at max", so the hold releases
--- and IsSpellReady (which callers pair this with) carries the answer.
function BlizzardAPI.IsSpellAtMaxCharges(spellID)
    local maxC, active = LiveChargeState(spellID)
    if not maxC or maxC < 2 then return true end
    return active ~= true
end

--------------------------------------------------------------------------------
-- Spell Readiness
--------------------------------------------------------------------------------

--- Check if a spell is ready (not on a real cooldown).
--- 12.0 combat: duration/startTime are blanket-secreted.
--- isOnGCD is NeverSecret with three observable states:
---   true  → GCD only (spell is ready, just on GCD)
---   false → real cooldown running (only for spells Blizzard flags internally;
---           typically short-CD rotation spells like Judgment, Blade of Justice)
---   nil   → absent (spell off CD OR unflagged spell on CD - ambiguous)
--- When isOnGCD is nil in combat, SpellCooldownInfo.isActive (NeverSecret) is
--- used as ground truth: true → real unflagged CD running; false → spell ready.
--------------------------------------------------------------------------------
-- GCD lookahead. "Ready" has to mean "pressable when the global cooldown ends", because
-- that is the next moment anything can be pressed. Without it, an ability with half a
-- second of its own cooldown left reads NOT ready for the whole GCD, sinks, and a filler
-- takes its place - then the real ability snaps back the instant the GCD ends. Blizzard's
-- own pick looks ahead like this, which is why the flicker only showed with My List Leads,
-- where slot 1 is ours (field report: single-target filler flashing between attacks in a
-- pack).
--
-- Both durations are secret in combat, so neither is read. The GCD is bracketed with the
-- seconds-threshold gate ("below 0.3s? 0.6s? ..."), then the ability's own cooldown is
-- asked the same question at that bracket. The bracket rounds UP, so an ability can show
-- ready up to 0.4s early - inside the game's own spell-queue window, where the press is
-- accepted anyway. Off-GCD abilities are excluded: they can be pressed NOW, so for them
-- "ready" must stay literal.
--------------------------------------------------------------------------------
-- The GCD reference: an uncastable spell in start-recovery category 133 whose cooldown is
-- the player's current GCD. The first one this client's spell data has wins. Retail has the
-- "Global Cooldown" dummy 61304. Forever's data has none, so it reads 1283885 ("[DNT]
-- Cooldown Never Secret Test Spell", category 133, no class), which tracked every GCD
-- plainly in and out of combat there (gcdref captures, build 1.60.1.70959: Mage, Priest,
-- Hunter).
local GCD_REFERENCE_CANDIDATES = { 61304, 1283885 }
local gcdReferenceSpell  -- resolved once (static spell data); false: no candidate exists

--- The spell whose cooldown reads the player's global cooldown, or nil when this client's
--- spell data has no reference. Callers treat nil as "GCD unknown".
function BlizzardAPI.GetGCDReferenceSpell()
    if gcdReferenceSpell == nil then
        gcdReferenceSpell = false
        if C_Spell and C_Spell.DoesSpellExist then
            for i = 1, #GCD_REFERENCE_CANDIDATES do
                local id = GCD_REFERENCE_CANDIDATES[i]
                local ok, exists = pcall(C_Spell.DoesSpellExist, id)
                if ok and exists == true then
                    gcdReferenceSpell = id
                    break
                end
            end
        end
    end
    if gcdReferenceSpell then return gcdReferenceSpell end
    return nil
end
-- 0.4s steps / 0.1s memo: every step is a threshold-gate evaluation (curve + widget round
-- trip), so this costs at most 4 per 0.1s plus one per ability on cooldown - and 0.4s is the
-- game's default spell-queue window, so rounding up by a step never shows a press that fails.
local LOOKAHEAD_STEPS = { 0.4, 0.8, 1.2, 1.6 }
local LOOKAHEAD_MEMO = 0.1
local lookaheadAt, lookaheadSecs = -1, nil
local readyByGcdMemo, readyByGcdAt = {}, -1

--- Seconds of GCD left, rounded up to a step; nil when no GCD is running or the gate
--- cannot answer (then there is no lookahead and readiness stays literal).
local function GCDLookahead()
    local now = GetTime()
    if now - lookaheadAt < LOOKAHEAD_MEMO then return lookaheadSecs end
    lookaheadAt, lookaheadSecs = now, nil
    if not (C_Spell and C_Spell.GetSpellCooldownDuration and BlizzardAPI.IsDurationBelowSeconds) then return nil end
    local reference = BlizzardAPI.GetGCDReferenceSpell()
    if not reference then return nil end
    local ok, gcd = pcall(C_Spell.GetSpellCooldownDuration, reference)
    if not ok or not DurationObjectActive(gcd) then return nil end
    for i = 1, #LOOKAHEAD_STEPS do
        local below = BlizzardAPI.IsDurationBelowSeconds(gcd, LOOKAHEAD_STEPS[i])
        if below == nil then return nil end
        if below then
            lookaheadSecs = LOOKAHEAD_STEPS[i]
            return lookaheadSecs
        end
    end
    lookaheadSecs = LOOKAHEAD_STEPS[#LOOKAHEAD_STEPS]
    return lookaheadSecs
end

--- True if casting this spell starts no global cooldown. Static client data (never a secret
--- read, so combat-safe). The table is keyed on BASE spell ids, so an override/form variant
--- is resolved first. Unknown id -> false: a missing marker is harmless, a wrong one tells
--- the player to clip a real GCD.
local offGcdCache = {}
local function IsOffGCD(spellID)
    if not spellID then return false end
    local hit = offGcdCache[spellID]
    if hit ~= nil then return hit end
    local CD = GetStaticCooldownData()
    local result = false
    if CD and CD.IsOffGCD then
        result = CD.IsOffGCD(spellID)
        if not result and BlizzardAPI.ResolveBaseSpellID then
            local base = BlizzardAPI.ResolveBaseSpellID(spellID)
            result = base and CD.IsOffGCD(base) or false
        end
    end
    offGcdCache[spellID] = result
    return result
end
BlizzardAPI.IsOffGCDSpell = IsOffGCD

--- Is the player's global cooldown running? true / false, or nil when unknown: the GCD
--- reference spell is absent from the client's spell data or the read failed. Read
--- from the reference's duration object (the same evidence GCDLookahead uses), memoized for
--- one frame so per-icon callers can skip their own per-spell GCD query while no GCD
--- runs. Callers must treat nil as "ask the spell itself".
local gcdRunningAt, gcdRunning = -1, nil
function BlizzardAPI.IsGlobalCooldownRunning()
    local now = GetTime()
    if now == gcdRunningAt then return gcdRunning end
    gcdRunningAt, gcdRunning = now, nil
    local reference = BlizzardAPI.GetGCDReferenceSpell()
    if not reference or not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local ok, gcd = pcall(C_Spell.GetSpellCooldownDuration, reference)
    if not ok then return nil end
    -- With the reference present, no duration object means no GCD (as GCDLookahead reads it).
    gcdRunning = DurationObjectActive(gcd)
    return gcdRunning
end

-- How soon after a wand shot or Auto Shot a GCD spell's cooldown may be the shot's lockout.
-- The lockout reads at the first queue update after the shot (about 40 ms later in captures).
local SHOT_LOCKOUT_WINDOW = 0.25
-- The lockout and the swing timer end together (both are the shot's length); a little slack keeps
-- a read taken a frame apart from deciding it.
local SHOT_LOCKOUT_SLACK = 0.1

--- Forever: is spellID's running cooldown only the lockout of the ranged shot just fired? true
--- when a wand shot or Auto Shot landed within SHOT_LOCKOUT_WINDOW and the spell's own cooldown
--- ends by the time that shot's swing does. An off-GCD spell is never locked by a shot.
local function ShotLockoutOnly(spellID)
    local start, finish = BlizzardAPI.GetSwingWindow(2)
    if type(start) ~= "number" or type(finish) ~= "number" then return false end
    local now = GetTime()
    if now - start < 0 or now - start > SHOT_LOCKOUT_WINDOW or finish <= now then return false end
    if IsOffGCD(spellID) then return false end
    return BlizzardAPI.CooldownEndsWithin(spellID, finish - now + SHOT_LOCKOUT_SLACK) == true
end

--- Will this ability's own cooldown be over by the time the GCD ends?
local function ReadyByGCDEnd(spellID)
    local secs = GCDLookahead()
    if not secs then return false end
    local now = GetTime()
    if now - readyByGcdAt >= LOOKAHEAD_MEMO then
        wipe(readyByGcdMemo)
        readyByGcdAt = now
    end
    local hit = readyByGcdMemo[spellID]
    if hit ~= nil then return hit end
    local result = false
    if not IsOffGCD(spellID) then
        local ok, own = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        result = ok and own ~= nil and BlizzardAPI.IsDurationBelowSeconds(own, secs) == true
    end
    readyByGcdMemo[spellID] = result
    return result
end

--- Returns true when the spell is ready (no real cooldown running).
--- Second return (diagnostics only, e.g. /jac why): a short string naming which
--- signal decided the verdict. Callers on hot paths ignore it (no allocation).
function BlizzardAPI.IsSpellReady(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return true, "no cooldown API" end

    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return true, "cooldown query failed (fail-open)" end

    -- WoW Forever: a wand shot or Auto Shot locks every GCD spell for about the shot's length,
    -- and the game reports that lockout as the spell's own cooldown through whichever flag it
    -- happens to use (isOnGCD false for Mind Blast, unset for Shadow Word: Pain, captures
    -- 2026-11-23). Read through one flag and not another, spells swapped places in the first
    -- slot for a frame after every shot. A cooldown that ends by the end of the shot just fired
    -- is that lockout, whatever the flags say, so every GCD spell is judged alike through it.
    if cd.isActive and BlizzardAPI.IsForever() and ShotLockoutOnly(spellID) then
        return true, "wand or Auto Shot lockout (Forever)"
    end

    -- isOnGCD == true → GCD only for unflagged spells.
    -- However, unflagged spells with real CDs also show isOnGCD=true during
    -- GCD (~1.5s). Check local tracking: if a real CD is ticking underneath,
    -- don't short-circuit - the spell is NOT ready.
    if cd.isOnGCD == true then
        -- Is a REAL cooldown ticking under the GCD? The ignore-GCD duration object
        -- answers this as engine truth - immune to the CDR / proc-reset / refund drift
        -- the local timer suffers.
        if not BlizzardAPI.IsSpellOnCooldown(spellID) then
            return true, "isOnGCD (GCD only)"
        end
        -- Real CD ticking under the GCD: ready only if it ends by the time the GCD does.
        if ReadyByGCDEnd(spellID) then return true, "cooldown ends by GCD end" end
    end

    -- isOnGCD == false → real cooldown running (definitive for flagged spells)
    if cd.isOnGCD == false then
        if ReadyByGCDEnd(spellID) then return true, "cooldown ends by GCD end" end
        return false, "isOnGCD flag (real cooldown)"
    end

    -- Out of combat: duration/startTime are readable. Unsecret both together -
    -- the secret system is volatile enough that one field can read plain while
    -- the other is still marked.
    local duration = Unsecret(cd.duration)
    local startTime = duration and Unsecret(cd.startTime)
    if duration and startTime then
        return startTime == 0 or (startTime + duration) <= GetTime(), "cooldown timer (out of combat)"
    end

    -- In combat with secreted values and isOnGCD == nil:
    -- Spell is either off cooldown OR on CD but unflagged (major CDs like
    -- Divine Toll, Execution Sentence, Shadow Blades) - isActive decides below

    -- SpellCooldownInfo.isActive is NeverSecret (source-verified).
    -- At this point isOnGCD is nil and duration is secret (combat) - both the
    -- isOnGCD true and false cases already exited above, and Unsecret(duration)
    -- returned nil (OOC path already exited). We are definitively in combat.
    --
    -- isOnGCD == nil + isActive == true  → real unflagged CD running (Cloak of
    --   Shadows, Shadow Blades, Execution Sentence, etc. - long CDs Blizzard
    --   doesn't flag, so isOnGCD never transitions to false).
    -- isOnGCD == nil + isActive == false → no CD timer running; spell is ready.
    --
    -- isActive is ground truth from Blizzard's state machine; no further
    -- fallback chain needed - local tracking / charge tracking / usability
    -- checks would all be redundant here.
    --
    -- WoW Forever differs: right after a wand shot every GCD spell read isActive with
    -- isOnGCD unset (capture 2026-11-16: Smite and Shadow Word: Pain), a shared lockout
    -- rather than their own cooldown, and the queue thrashed as they all sank at once.
    -- The ignore-GCD duration object (documented on Forever) says whether a cooldown of
    -- the spell's own is running.
    if cd.isActive and BlizzardAPI.IsForever() and C_Spell and C_Spell.GetSpellCooldownDuration then
        if not BlizzardAPI.IsSpellOnCooldown(spellID) then
            return true, "isActive without own cooldown (Forever)"
        end
    end
    return not cd.isActive, "isActive (in combat)"
end
