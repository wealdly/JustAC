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

--- True while spellID is on a REAL cooldown (GCD excluded), read as engine truth.
function BlizzardAPI.IsSpellOnCooldown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldownDuration) then return false end
    -- pcall like every sibling read: this runs inside the queue build, where a throw on
    -- an odd id blanks the queue instead of degrading one entry.
    local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    return ok and DurationObjectActive(dur) or false
end

-- Our own casts, [spell id] = GetTime(). Player buffs are SECRET in combat (measured: the
-- aura lookup returns nil for a buff that is up), so inside a fight the only thing that knows
-- a buff window opened is the cast that opened it.
local ownCastAt = {}
local auraUntil = {}   -- [spellID] = the buff's expiry, read while its aura was plain
local formCache   -- resolved on first use: FormCache loads after this file
local rotationImport   -- resolved on first use: rank chains (WoW Forever)
local maintenanceTracker   -- resolved on first use: Cooldown Manager aura state (loads later)

--- Record a successful player cast (every cast, in or out of combat).
function BlizzardAPI.NoteOwnCast(spellID)
    if not spellID then return end
    local now = GetTime()
    ownCastAt[spellID] = now
    local base = BlizzardAPI.ResolveBaseSpellID(spellID)
    if base then ownCastAt[base] = now end
    -- Forever ranks: a rank-3 cast opens the window the data names by rank 1.
    if rotationImport == nil then rotationImport = LibStub("JustAC-RotationImport", true) or false end
    local r1 = rotationImport and rotationImport.RankBase(spellID)
    if r1 and r1 ~= spellID then ownCastAt[r1] = now end
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

-- PLAYER_SWING_RANGE_UPDATE (Forever): (swingType, inRange, hasTarget), plain in combat and
-- fired on every target change and range crossing (measured build 70245: a target acquired
-- from a distance read false/true, walking into melee true/true, a dead target true/false).
local swingInRange = {}

--- Is the current target within auto-attack reach of swingType (0 main hand, 2 ranged)?
--- The game's own range check: true / false, or nil with no target or no event seen (retail).
function BlizzardAPI.IsTargetInSwingRange(swingType)
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

do
    local f = CreateFrame("Frame")
    -- pcall: PLAYER_SWING only exists on Forever.
    if pcall(f.RegisterEvent, f, "PLAYER_SWING") then
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
        pcall(f.RegisterEvent, f, "PLAYER_SWING_RANGE_UPDATE")
        f:SetScript("OnEvent", function(_, event, duration, swingType, hasTarget)
            if event == "PLAYER_SWING" then
                if type(swingType) == "number" and type(duration) == "number"
                   and not IsSecretValue(duration) and duration > 0 then
                    swingLast[swingType], swingDur[swingType] = GetTime(), duration
                end
            elseif event == "PLAYER_SWING_RANGE_UPDATE" then
                -- Payload (swingType, inRange, hasTarget); the first argument slot is named
                -- for PLAYER_SWING above.
                local st, inRange = duration, swingType
                if type(st) == "number" and type(inRange) == "boolean" and type(hasTarget) == "boolean" then
                    if hasTarget then swingInRange[st] = inRange else swingInRange[st] = nil end
                end
            else
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

--- True while our own self-buff (spellID) is active on the player. Three sources, best
--- first: the stance bar for a form (plain, always), the aura itself (blind to secret
--- auras - i.e. most of combat), then our own cast of the spell within its base duration.
--- ponytail: the cast window is the BASE length - blind to early cancels and to talents that
--- extend it; the game's pick still reveals a window this under-calls.
--- @param spellID number the spell a SimC buff-window gate references (5217, ...)
--- @param durSecs number|nil base aura seconds from the gate; nil = no cast inference
function BlizzardAPI.IsBuffWindowActive(spellID, durSecs)
    if not spellID then return false end
    if formCache == nil then formCache = LibStub("JustAC-FormCache", true) or false end
    local formID = formCache and formCache.GetFormIDBySpellID(spellID)
    if formID then return formCache.GetActiveForm() == formID end
    -- WoW Forever: a buff the player tracks in the Cooldown Manager is read off Blizzard's own
    -- icon - exact, and the only aura state readable in combat there. Untracked: on to the rest.
    local forever = BlizzardAPI.IsForever and BlizzardAPI.IsForever()
    if forever then
        if maintenanceTracker == nil then
            maintenanceTracker = LibStub("JustAC-MaintenanceTracker", true) or false
        end
        -- Not `x and x.f()`: with the module missing that is false, read as "buff down".
        local tracked
        if maintenanceTracker then tracked = maintenanceTracker.IsTrackedAuraActive(spellID) end
        if tracked ~= nil then return tracked end
    end
    -- An attack-speed buff is proven by the swings themselves (Forever): its length can
    -- depend on combo points, and an early cancel or dispel shows as the speed going away.
    local evidence = HasteBuffEvidence(spellID)
    if evidence ~= nil then return evidence end
    local castAt = durSecs and ownCastAt[spellID]
    local castLive = castAt and (GetTime() - castAt) < durSecs or false
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return castLive
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
                auraUntil[spellID] = exp
            end
            return true
        end
    end
    -- Retail: unchanged - the cast window is the whole fallback there. (A remembered expiry
    -- would also hold a buff consumed early in combat "up" until its old expiry.)
    if not forever then return castLive end
    if not BlizzardAPI.AreAurasSecret() then
        auraUntil[spellID] = nil   -- readable and absent: really gone
        return castLive
    end
    local untilAt = auraUntil[spellID]
    return castLive or (untilAt ~= nil and GetTime() < untilAt)
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
    f:SetScript("OnEvent", function() wipe(baseCdSecondsCache) end)
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
local GCD_DUMMY_SPELL = 61304
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
    local ok, gcd = pcall(C_Spell.GetSpellCooldownDuration, GCD_DUMMY_SPELL)
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
    return not cd.isActive, "isActive (in combat)"
end
