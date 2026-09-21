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
local formCache   -- resolved on first use: FormCache loads after this file

--- Record a successful player cast (every cast, in or out of combat).
function BlizzardAPI.NoteOwnCast(spellID)
    if not spellID then return end
    local now = GetTime()
    ownCastAt[spellID] = now
    local base = BlizzardAPI.ResolveBaseSpellID(spellID)
    if base then ownCastAt[base] = now end
end

--- True while our own self-buff (spellID) is active on the player. Three sources, best
--- first: the stance bar for a form (plain, always), the aura's DurationObject (engine
--- truth, but blind to secret auras - i.e. most of combat), then our own cast of the spell
--- within its base duration.
--- ponytail: the cast window is the BASE length - blind to early cancels and to talents that
--- extend it; the game's pick still reveals a window this under-calls.
--- @param spellID number the spell a SimC buff-window gate references (5217, ...)
--- @param durSecs number|nil base aura seconds from the gate; nil = no cast inference
function BlizzardAPI.IsBuffWindowActive(spellID, durSecs)
    if not spellID then return false end
    if formCache == nil then formCache = LibStub("JustAC-FormCache", true) or false end
    local formID = formCache and formCache.GetFormIDBySpellID(spellID)
    if formID then return formCache.GetActiveForm() == formID end
    local castAt = durSecs and ownCastAt[spellID]
    local castLive = castAt and (GetTime() - castAt) < durSecs or false
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetAuraDuration) then
        return castLive
    end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    local instId = aura and aura.auraInstanceID
    if not instId then return castLive end
    -- 12.1.0: GetAuraDuration is ACCESS-DENIED to a tainted caller while auras are secret,
    -- and the denial ignores the aura's OWN exemption - a NeverSecret buff whose data reads
    -- fully plain still throws here. That is why this needs a pcall even though the lookup
    -- above just succeeded: reaching an aura and reading its duration are separate permissions.
    -- Unguarded, the throw propagated into the queue build (SimcBuffWindowActive /
    -- SimcNegativeBuffBlocks) and blanked the queue mid-fight rather than degrading it.
    -- false on denial is the same answer as "no such aura", which the SimC gate layer already
    -- compensates for: positive windows fall back to AC's pick, negative gates fail open.
    local ok, dur = pcall(C_UnitAuras.GetAuraDuration, "player", instId)
    if not ok then return true end   -- denied, but the aura table in hand proves it is up
    return DurationObjectActive(dur)
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
