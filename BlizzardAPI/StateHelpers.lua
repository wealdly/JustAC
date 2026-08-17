-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Defensive/Item State, Health Detection, Target Analysis, Shapeshift Forms
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SpellQuery.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-StateHelpers", 14
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local math_max         = math.max
local math_min         = math.min
local math_floor       = math.floor
local GetTime          = GetTime
local GetItemCount     = GetItemCount
local GetItemCooldown  = GetItemCooldown
local UnitClassification = UnitClassification ---@diagnostic disable-line: undefined-global
local UnitIsUnit         = UnitIsUnit         ---@diagnostic disable-line: undefined-global
local UnitCreatureType   = UnitCreatureType   ---@diagnostic disable-line: undefined-global
local UnitIsMinion       = UnitIsMinion       ---@diagnostic disable-line: undefined-global
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
-- Important casts nearby (secret-safe danger cue)
--------------------------------------------------------------------------------
-- C_Spell.IsSpellImportant is the engine's own "lethal if not interrupted" flag, and it is
-- AllowedWhenTainted, so we may call it - and may hand it a secret spell id. What comes back
-- inherits that secrecy, so the verdict can never be read or branched on. It does not have to
-- be: each nearby caster's verdict is poured straight into one region's alpha, and if ANY
-- region lights up, something lethal is being cast. The compositor performs the OR that Lua
-- cannot, which is the whole reason this works without a branchable boolean.
--
-- Deliberately independent of Blizzard's own indicator: that one is gated on the cast bar's
-- highlightImportantCasts setting, so a player with it switched off would see nothing.
--
--- @param regions table  array of textures to drive; every one is written each pass
--- @param litAlpha number|nil  alpha for "important" (default 1)
--- @return number  how many nearby casters were measured (diagnostics; NOT how many are important)
function BlizzardAPI.DriveImportantCastAlphas(regions, litAlpha)
    if not regions or #regions == 0 then return 0 end
    local IsImportant = C_Spell and C_Spell.IsSpellImportant
    local canRead = IsImportant and UnitCastingInfo and UnitChannelInfo
    local measured = 0
    -- One region PER NAMEPLATE TOKEN, not per caster found. Packing casters into the first
    -- free regions would mean a cap drops whichever mobs were scanned last - and since the
    -- verdicts can't be read, there is no way to prefer the dangerous ones. A fixed mapping
    -- has no such bias: region i always belongs to nameplate i, and an absent or silent mob
    -- simply leaves its own region dark.
    for i = 1, #regions do
        local region = regions[i]
        local lit = nil                     -- nil => nothing to say, region goes dark
        local u = canRead and NAMEPLATE_UNITS[i]
        if u then
            local ex = UnitExists(u)
            if not IsSecretValue(ex) and ex then
                local ca = UnitCanAttack("player", u)
                if not IsSecretValue(ca) and ca then
                    -- spellID: 9th return casting, 8th channelling. Test secrecy BEFORE any
                    -- comparison - `id ~= nil` on a secret is itself a forbidden read.
                    local id = select(9, UnitCastingInfo(u))
                    if not IsSecretValue(id) and id == nil then
                        id = select(8, UnitChannelInfo(u))
                    end
                    if IsSecretValue(id) or id ~= nil then
                        local ok, important = pcall(IsImportant, id)
                        if ok then
                            lit = important
                            measured = measured + 1
                        end
                    end
                end
            end
        end
        -- nilAlpha 0: no caster behind this region must never leave a stale verdict lit.
        BlizzardAPI.SetAlphaFromSecretBool(region, lit, litAlpha or 1, 0, 0)
    end
    return measured
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

--- Is the player unable to use their own abilities as a whole, right now?
--- Two causes, one consequence: loss of control (stun, fear, silence, disarm - the engine
--- reports these), or an override action bar, where a debuff has swapped the buttons out
--- from under them (an aura applying OVERRIDE_SPELLS; the engine reports no LoC entry for
--- it, so the count above stays 0 and only the bar state gives it away).
--- Callers use this to SKIP the usability gate, never to hide anything: when NOTHING is
--- castable, the reason is the player's state rather than a fact about any one spell, and
--- dropping every entry empties the queue at the exact moment someone is looking at it to
--- see what to press when they get control back. The renderer greys the icons from its own
--- usability read, so they hold their place, dimmed, and light back up on release.
--- Plain never-secret reads (validated for LoC 2026-07-24); fail-open - doubt reads as false.
function BlizzardAPI.IsPlayerAbilityLockout()
    if IsLossOfControlActive() then return true end
    return HasOverrideActionBar and HasOverrideActionBar() or false
end
local IsPlayerAbilityLockout = BlizzardAPI.IsPlayerAbilityLockout

--- Is this specific spell locked out by an active loss-of-control effect?
--- GetSpellLossOfControlCooldownInfo().isActive is NeverSecret - validated in-game
--- 2026-07-24 in both states: true for every spell during a stun, false when free.
--- Covers full CC (stun/fear locks everything) AND school lockouts (a kick locks
--- one school). Gated on an active LoC entry so the common case costs one count
--- read; fail-open - any doubt reads as "not locked".
function BlizzardAPI.IsSpellLoCLocked(spellID)
    if not spellID or not IsLossOfControlActive() then return false end
    if not (C_Spell and C_Spell.GetSpellLossOfControlCooldownInfo) then return false end
    local ok, info = pcall(C_Spell.GetSpellLossOfControlCooldownInfo, spellID)
    if not ok or not info then return false end
    local v = info.isActive
    if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(v) then return false end
    return v == true
end

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
    -- Skipped entirely under a player-wide ability lockout (see IsPlayerAbilityLockout - CC,
    -- or a debuff that swaps the action bar): the lockout, not the spell, is why nothing is
    -- castable. Entries fall through to the caller's ready/on-CD ordering, which stays honest
    -- while locked out; the renderer greys the icons off its own usability read, so they hold
    -- their place, dimmed, and light back up when control returns.
    if C_Spell and C_Spell.IsSpellUsable and not IsPlayerAbilityLockout() then
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
--- Single source: RedundancyFilter's aura cache, which already runs the whole ladder for us -
--- it picks its strategy off AreAurasSecret, resolves secret aura IDs through the instance
--- maps, and merges the trusted out-of-combat snapshot. There is deliberately no second rung
--- here: this answer is two-valued, so "absent" and "unknown" both come back false, and any
--- fallback placed below would be unreachable (the cache table always exists once built).
--- False is the fail-open direction every caller wants - an unresolved aura keeps its
--- suggestion visible rather than hiding an ability whose buff we could not confirm.
--- @param unit string  Unit token - unused; the cache is player-only (kept for call-site clarity)
--- @param auraSpellID number  The spellID of the aura to check
--- @return boolean  true if the aura is known to be active
function BlizzardAPI.IsAuraActive(unit, auraSpellID)
    if not auraSpellID or auraSpellID == 0 then return false end

    local RedundancyFilter = GetRedundancyFilter()
    local cache = RedundancyFilter and RedundancyFilter.GetAuraCache
        and RedundancyFilter.GetAuraCache()
    return (cache and cache.byID and cache.byID[auraSpellID]) == true
end

--------------------------------------------------------------------------------
-- Spell range (tri-state)
--------------------------------------------------------------------------------

local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

--- Tri-state range read: true (in range), false (confirmed out of range), nil (unknown -
--- no range requirement, no valid target, API absent, or an unreadable return). The ONE
--- owner for two facts every caller used to hand-roll, four copies strong:
---   * The unit argument is REQUIRED despite the docs calling it optional. The no-unit
---     form answers nil - measured twice (Data/RangeReferences.lua probe notes,
---     CastInterruptTracker.IsReachable), and the copy that omitted it read nil as
---     "in range" and silently lost the red range state. That drift is why this exists.
---   * The return is guarded against being secret. The docs say plain bool; the guard is
---     belt-and-braces each copy carried anyway, now paid for once.
--- Callers keep their own fail direction - that part differs deliberately per site
--- (a wasted press is cheap for a kick, expensive for a placed cooldown).
function BlizzardAPI.SpellInRange(spellID, unit)
    if not C_Spell_IsSpellInRange or not spellID then return nil end
    local r = C_Spell_IsSpellInRange(spellID, unit or "target")
    if r == nil or (IsSecretValue and IsSecretValue(r)) then return nil end
    return r
end

--------------------------------------------------------------------------------
-- Low Health Detection via LowHealthFrame (works when UnitHealth() is secret)
--------------------------------------------------------------------------------

--- Is the player under Blizzard's low-health threshold? ONE boolean, because that is all
--- the vignette encodes: LowHealthFrameMixin has a single `lowHealthPercentStart = .35`
--- and no critical tier at all.
---
--- This used to also report severity from the frame's ALPHA, which was noise. The frame
--- runs `pulseAnim` as a looping BOUNCE from .75 to .2 over 0.524s, so its alpha sweeps
--- its whole range about twice a second and both display states straddle any cut you pick
--- (LOW_HEALTH animates .15-1.0, FULLSCREEN .2-.75). An `alpha > 0.5` test therefore
--- sampled the animation's PHASE, not the player's health, and flipped roughly once a
--- second at a fixed health value.
---
--- Caveat kept deliberately, because it is not fixable from here: DetermineFlashState
--- returns FULLSCREEN from `inCombat` + the screenEdgeFlash CVar + GetUIPanel("fullscreen")
--- with NO health condition, so a true reading is "the vignette is up", which is USUALLY
--- but not always low health. It is still the only binary that survives combat secrecy,
--- and it is consumed as the last rung of a ladder that has already tried better sources.
function BlizzardAPI.GetLowHealthState()
    local frame = LowHealthFrame ---@diagnostic disable-line: undefined-global
    if not frame then return false end
    return frame:IsShown() and true or false
end

--------------------------------------------------------------------------------
-- Ally-low detection (party1-4) - the ONLY branchable "an ally needs healing"
-- signal in 12.0.
--
-- Blizzard's combat audio-alert manager watches player+party1-4 and, in its own
-- UNTAINTED code, inserts/removes a plain Lua table KEY per unit exactly when
-- that unit crosses the CAAPartyHealthPercent threshold. Key existence is the
-- laundered boolean: the comparison happened privileged, so what reaches us is
-- an ordinary table lookup, not a secret. Validated in game 2026-08-09 (Resto
-- Druid, follower dungeon, thresholds 90/70/60%): keys flip both directions in
-- combat, unitCount stays consistent with them, and it all works with the alert
-- VOLUME at 0 (volume gates the speech, not the processing).
--
-- Rules this must never break:
--   * READ KEYS ONLY. The stored values (frequency/updateAfter) are derived from
--     secret health - touching them re-secrets what we just laundered.
--   * READ ONLY, never write a field on the manager (a Lua write taints the
--     frame and breaks Blizzard's own secret comparison).
--   * The addon does not enable the feature here; a managed setup toggle owns
--     that. Feature off -> the manager clears its table -> count 0 -> callers
--     see "nobody low", which is the correct fail-open direction.
--   * party1-4 only; there is no raid equivalent.
--------------------------------------------------------------------------------

--- Number of watched units currently below the alert threshold (0 when the
--- feature is off, ungrouped, or the value is unreadable). Plain integer.
-- Probe closure hoisted through an upvalue: this runs per party UNIT_HEALTH
-- event in combat (the edge-trigger in JustAC.lua), and an inline closure
-- would allocate on every call.
local lowCountProbeInfo
local function LowCountProbe() return lowCountProbeInfo.unitCount end

function BlizzardAPI.GetPartyLowCount()
    local mgr = CombatAudioAlertManager ---@diagnostic disable-line: undefined-global
    local info = mgr and mgr.partyHealthInfo
    if not info then return 0 end
    lowCountProbeInfo = info
    local ok, n = pcall(LowCountProbe)
    if not ok or type(n) ~= "number" then return 0 end
    if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(n) then return 0 end
    return n
end

--- Is this unit currently below the alert threshold? Key existence only.
--- @param unit string "player" or "party1".."party4"
function BlizzardAPI.IsUnitLow(unit)
    if not unit then return false end
    local mgr = CombatAudioAlertManager ---@diagnostic disable-line: undefined-global
    local info = mgr and mgr.partyHealthInfo
    local byUnit = info and info.unitInfo
    if not byUnit then return false end
    local ok, present = pcall(function() return byUnit[unit] ~= nil end)
    return ok and present == true
end

--- True when the ally-low signal is actually running (feature enabled with a
--- non-zero threshold). Callers use this to distinguish "nobody is hurt" from
--- "we cannot see who is hurt" - the emergency tier stays dark for the latter
--- rather than pretending the group is healthy.
function BlizzardAPI.IsPartyLowAvailable()
    local api = C_CombatAudioAlert ---@diagnostic disable-line: undefined-global
    if not (api and api.IsEnabled) then return false end
    local ok, enabled = pcall(api.IsEnabled)
    if not (ok and enabled == true) then return false end
    local threshold = tonumber(GetCVar and GetCVar("CAAPartyHealthPercent"))
    return (threshold or 0) > 0
end

--------------------------------------------------------------------------------
-- Pet liveness
--------------------------------------------------------------------------------

--- Is there a pet worth acting on? UnitExists("pet") is NOT that question: when a
--- hunter mounts, the pet is dismissed but the unit lingers for a beat, still
--- "existing" and reading as unhealthy - a max health of 0 is below every threshold
--- - so the pet-heal cue lit up for a pet that was gone (user-reported, mounted
--- hunter, pre-combat offers switched off and rightly suspected). Mounted / in a
--- vehicle there is no pet to heal regardless of what the unit says. All plain
--- reads, safe in and out of combat; UnitHealthMax is guarded in case that ever
--- changes - an unreadable max falls through to the plain existence answer.
function BlizzardAPI.HasActionablePet()
    if not UnitExists("pet") then return false end
    if IsMounted and IsMounted() then return false end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return false end
    local maxHP = UnitHealthMax("pet")
    if maxHP ~= nil and not IsSecretValue(maxHP) and maxHP <= 0 then return false end
    return true
end

--------------------------------------------------------------------------------
-- Zero-gate consumers (BlizzardAPI.IsSecretZero - see SecretValues.lua).
-- Each returns true / false / NIL, where nil means "no answer": callers must
-- treat it as unknown and keep their fallback, never as a verdict.
--------------------------------------------------------------------------------

--- Is this unit provably at FULL health? The deficit is computed engine-side
--- (UnitHealthMissing) and only its zero-ness is read, so no secret is touched.
--- Certified in game 2026-08-10 both directions, including the at-full "-0".
function BlizzardAPI.IsUnitFullHealth(unit)
    if not (unit and UnitHealthMissing and BlizzardAPI.IsSecretZero) then return nil end
    local ok, missing = pcall(UnitHealthMissing, unit)
    if not ok or missing == nil then return nil end
    return BlizzardAPI.IsSecretZero(missing)
end

--------------------------------------------------------------------------------
-- THRESHOLD GATES - "is this unit below N% health/power", for any unit and any
-- percentage. Nothing else in 12.0 provides this: the party health alert's
-- threshold is configurable but its table only exists while UnitInParty("player")
-- (Blizzard's own IsInPartyHealthMode), and every other player-health signal is
-- pinned at 20% or 35%.
--
-- THE ENGINE DOES THE COMPARING. A curve maps "below the threshold" to a large
-- number and "at or above" to 0; UnitHealthPercent/UnitPowerPercent evaluates it
-- against the secret value and returns a secret result; the zero-gate reads only
-- that result's zero-ness. No secret is compared, ordered, or read in Lua.
-- Validated in game 2026-08-10 on a player at full and a damaged hostile target.
--
-- LINEAR, never Step: step-curve band semantics cannot be verified from Lua
-- (they cost us an invisible top-off icon), so the threshold is a steep ramp
-- between two FLAT segments - unambiguous under interpolation, and its 0.2% width
-- is far finer than any threshold a feature sets.
--
-- SCOPE RULE, deliberate: these answer QUESTIONS, never values. Asking one
-- threshold to make a decision is what the engine's curve mechanism is for;
-- chaining many to binary-search the hidden number back out is precisely what
-- the secret-value system exists to prevent, would break our legitimate uses
-- when it got patched, and is not something this addon does. There is no
-- "what percent is it" function here, and there should not be one.
--------------------------------------------------------------------------------

-- ONE curve cache for the whole addon, keyed by domain and threshold: a curve has
-- no idea whether it is being evaluated against health, power or a duration, so
-- every consumer of "below 35%" shares the same object. Seconds thresholds live
-- here too under their own domain - see GetSecondsCurve.
local thresholdCurves, thresholdCurveCount = {}, 0
local THRESHOLD_CURVE_CAP = 64   -- distinct thresholds; real use is under a dozen

--- Normalize a requested percentage into a cache key: 0.1% resolution, clamped in
--- range, NaN rejected. Quantizing bounds the curve cache and lifts the memo hit
--- rate when generated data (SimC absolute->percent conversion) yields long
--- fractions that differ meaninglessly.
local function NormalizePct(pct)
    if type(pct) ~= "number" or pct ~= pct then return nil end   -- nil / NaN
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return math_floor(pct * 10 + 0.5) / 10
end

--- Build + SELF-TEST one threshold curve: flat-high below `t`, flat-zero at and
--- above it, joined by a ramp `eps` wide. Runs inside a pcall (see below): every
--- step here is an engine call that could change shape between patches, and a
--- throw must disable this one threshold, never propagate into a render pass.
--- `domain` is the upper bound of the value being evaluated - 1 for the 0-1
--- fraction the percent APIs use, SECONDS_DOMAIN for a raw duration.
local function BuildStepCurve(t, eps, domain)
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
    if not (cu and cu.CreateCurve and linear) then return nil end
    local c = cu.CreateCurve()
    if not c then return nil end
    c:SetType(linear)
    -- BELOW_VALUE is 100, not 1: the zero-gate's transform (TruncateWhenZero)
    -- formats "as an integer, ROUNDING DOWN", so anything the ramp interpolates
    -- below 1.0 would floor to zero and read as "above threshold". A large value
    -- keeps every interpolated point inside the ramp comfortably non-zero.
    c:AddPoint(0, 100)
    c:AddPoint(math_max(0, t - eps), 100)
    c:AddPoint(math_min(domain, t + eps), 0)
    c:AddPoint(domain, 0)
    -- SELF-TEST, with PLAIN inputs: Evaluate takes an ordinary number, so the
    -- curve can prove itself before we ever trust it with a secret. This pins down
    -- the two things we cannot otherwise verify from Lua - that the domain really
    -- is what we think, and that interpolation lands where we expect. Fail -> the
    -- curve is marked unusable and every caller falls back, so this can be
    -- wrong-or-absent but never silently backwards.
    -- Five epsilons out: guaranteed clear of the ramp in either domain, and still
    -- close enough to the threshold that the test means something.
    local probe = eps * 5
    local okLo, lo = pcall(c.Evaluate, c, math_max(0, t - probe))
    local okHi, hi = pcall(c.Evaluate, c, math_min(domain, t + probe))
    if okLo and okHi and type(lo) == "number" and type(hi) == "number"
        and lo >= 1 and hi < 1 then
        return c
    end
    return nil
end

--- Cached curve, or nil when unavailable. `false` is the memo for "this threshold
--- failed to build" so a broken one is not retried every frame. The cap is pure
--- paranoia against generated data asking for unbounded distinct thresholds.
local function GetStepCurve(key, t, eps, domain)
    local curve = thresholdCurves[key]
    if curve ~= nil then
        if curve == false then return nil end
        return curve
    end
    if thresholdCurveCount >= THRESHOLD_CURVE_CAP then
        wipe(thresholdCurves)
        thresholdCurveCount = 0
    end
    local ok, built = pcall(BuildStepCurve, t, eps, domain)
    curve = (ok and built) or false
    thresholdCurves[key] = curve
    thresholdCurveCount = thresholdCurveCount + 1
    if curve == false then return nil end
    return curve
end

--- Curve for a NORMALIZED percentage, evaluated against the 0-1 FRACTION that
--- UnitHealthPercent / UnitPowerPercent / EvaluateRemainingPercent all share.
local function GetThresholdCurve(pct)
    local t = pct / 100
    if t < 0.002 then t = 0.002 elseif t > 0.998 then t = 0.998 end
    return GetStepCurve(pct, t, 0.001, 1)
end

--- Shared evaluation: hand the curve to the engine, read the result's zero-ness.
--- `unmodified`/`predicted` are both false deliberately - an incoming heal or a
--- transient modifier must not flip a threshold gate back and forth.
local function EvaluateBelow(unit, pct, isPower, powerType)
    local curve = GetThresholdCurve(pct)
    if not (curve and unit and BlizzardAPI.IsSecretZero) then return nil end
    local ok, result
    if isPower then
        if not UnitPowerPercent then return nil end
        ok, result = pcall(UnitPowerPercent, unit, powerType, false, curve)
    else
        if not UnitHealthPercent then return nil end
        ok, result = pcall(UnitHealthPercent, unit, false, curve)
    end
    if not ok or result == nil then return nil end
    local zero = BlizzardAPI.IsSecretZero(result)
    if zero == nil then return nil end
    return not zero
end

-- Per-tick memo. A rotation build asks the same question many times inside one
-- update, and every miss costs a curve evaluation plus a widget round-trip.
-- "?" stands in for nil, which a Lua table cannot store as a cached answer.
local belowMemo, belowMemoAt = {}, 0
local BELOW_MEMO_WINDOW = 0.1
local NO_ANSWER = "?"
-- Cost counters. Each MISS is a curve evaluation plus a FontString round-trip;
-- hits are table lookups. Surfaced by /jac inspect perf so the real cost of this
-- layer is measured rather than assumed.
local belowHits, belowMisses, belowWipes = 0, 0, 0
function BlizzardAPI.GetThresholdGateStats()
    return belowHits, belowMisses, belowWipes, thresholdCurveCount
end
local function CachedBelow(unit, pct, isPower, powerType)
    if type(unit) ~= "string" then return nil end
    -- Normalize ONCE, here: the memo key and the curve cache must agree, or two
    -- spellings of the same threshold would each build a curve and never share
    -- a memo entry.
    pct = NormalizePct(pct)
    if not pct then return nil end
    local now = GetTime()
    if now - belowMemoAt >= BELOW_MEMO_WINDOW then
        wipe(belowMemo)
        belowMemoAt = now
        belowWipes = belowWipes + 1
    end
    local key = (isPower and "p" or "h") .. tostring(powerType or "") .. "|" .. unit .. "|" .. pct
    local hit = belowMemo[key]
    if hit ~= nil then
        belowHits = belowHits + 1
        if hit == NO_ANSWER then return nil end
        return hit
    end
    belowMisses = belowMisses + 1
    local result = EvaluateBelow(unit, pct, isPower, powerType)
    belowMemo[key] = (result == nil) and NO_ANSWER or result
    return result
end

--- Plain true/false, or nil when the value cannot be read. Never test a possibly
--- secret boolean for truthiness directly - that throws.
local function ReadableBool(v)
    if v == nil then return nil end
    if IsSecretValue and IsSecretValue(v) then return nil end
    if type(v) ~= "boolean" then return v and true or false end
    return v
end

--- Can this party member actually receive a heal right now? Dead members need a
--- rez, not a heal, and a direct health gate would otherwise count a corpse as
--- the lowest-health ally in the group.
local function IsHealableParty(unit)
    if ReadableBool(UnitExists(unit)) ~= true then return false end
    if ReadableBool(UnitIsDeadOrGhost(unit)) ~= false then return false end
    if ReadableBool(UnitIsConnected(unit)) == false then return false end
    return true
end

--- How many party members are below `pct` health, read DIRECTLY. Returns nil if
--- any member cannot be answered, so callers can fall back to the alert-key path
--- rather than acting on a partial count.
--- Direct beats the alert keys on every axis: no accessibility CVar, exact
--- thresholds instead of 10% steps, and it works past party4.
function BlizzardAPI.GetPartyBelowCount(pct)
    local n = 0
    for i = 1, 4 do
        local unit = "party" .. i
        if IsHealableParty(unit) then
            local below = CachedBelow(unit, pct, false, nil)
            if below == nil then return nil end
            if below then n = n + 1 end
        end
    end
    return n
end

--- Is one specific ally below `pct`? nil = cannot answer.
function BlizzardAPI.IsPartyUnitBelow(unit, pct)
    if not IsHealableParty(unit) then return false end
    return CachedBelow(unit, pct, false, nil)
end

--- Is the whole threshold-gate mechanism usable on this client right now? One
--- probe against the player, so callers and diagnostics can distinguish "the
--- answer is no" from "we cannot answer". Cheap: it rides the same memo.
function BlizzardAPI.IsThresholdGateAvailable()
    return CachedBelow("player", 50, false, nil) ~= nil
end

function BlizzardAPI.IsUnitHealthBelow(unit, pct)
    return CachedBelow(unit, pct, false, nil)
end

--- Is this unit's power below `pct` percent? Same engine-side comparison as the
--- health gate (UnitPowerPercent takes the identical curve argument), which is
--- what finally makes CONTINUOUS resources gateable: mana, energy, focus, rage,
--- runic power, astral power. Until now the only power fact available was
--- IsSpellUsable().insufficientPower - "can I afford this right now", never
--- "am I saving up". DISCRETE points (combo points, holy power, chi) have an
--- exact read of their own; keep using that instead of this.
--- @param powerType number|nil Enum.PowerType; nil = the unit's current type
function BlizzardAPI.IsUnitPowerBelow(unit, pct, powerType)
    return CachedBelow(unit, pct, true, powerType)
end

--- Which band does this unit's health fall in? `boundaries` is an ASCENDING
--- list of percentages; returns 1 for "below the first", #boundaries+1 for "at
--- or above the last", or nil if any gate could not answer.
--- Costs one gate per boundary tested (it short-circuits at the first hit), so
--- keep the list short and DECISION-shaped: boundaries should come from what a
--- feature does differently, never from wanting resolution. There is
--- deliberately no "what percent is it" call anywhere in this file.
function BlizzardAPI.GetHealthBand(unit, boundaries)
    if type(boundaries) ~= "table" then return nil end
    for i = 1, #boundaries do
        local below = CachedBelow(unit, boundaries[i], false, nil)
        if below == nil then return nil end
        if below then return i end
    end
    return #boundaries + 1
end

--- Power equivalent of GetHealthBand.
function BlizzardAPI.GetPowerBand(unit, boundaries, powerType)
    if type(boundaries) ~= "table" then return nil end
    for i = 1, #boundaries do
        local below = CachedBelow(unit, boundaries[i], true, powerType)
        if below == nil then return nil end
        if below then return i end
    end
    return #boundaries + 1
end

--- "There is nothing to heal right now": the player is provably at full AND no
--- party member is below the alert threshold. TRUE only on certain answers -
--- any doubt returns false, because every caller uses this to SUPPRESS a cue
--- and a wrong suppression hides a real one. Memoized at 0.25s: it feeds
--- per-icon decisions on the render path.
local healUnneededCache, healUnneededAt = false, 0
function BlizzardAPI.IsHealingUnneeded()
    local now = GetTime()
    if now - healUnneededAt < 0.25 then return healUnneededCache end
    healUnneededAt = now
    healUnneededCache = false
    if BlizzardAPI.IsUnitFullHealth("player") == true then
        healUnneededCache = (BlizzardAPI.GetPartyLowCount() == 0)
    end
    return healUnneededCache
end

--------------------------------------------------------------------------------
-- DURATION THRESHOLDS - "is this aura/cooldown below N% or N seconds remaining".
-- The same engine-side comparison as the health gates: LuaDurationObject's
-- Evaluate* methods take the identical curve argument, and the zero-gate reads the
-- result. Field-verified in combat 2026-08-10 against ground truth in both states.
--
-- Two facts that had to be measured rather than assumed, both settled:
--   * EvaluateRemainingPercent's domain is the 0-1 FRACTION - the same as
--     UnitHealthPercent - so the percentage curves below are shared with them.
--   * The result is SECRET for a cooldown in combat and PLAIN for a non-secret
--     aura. Costs nothing: IsSecretZero has a plain fast path, so one call covers
--     both. Callers must still never read the number - see the SCOPE RULE above;
--     plainness is a property of one aura, not of the API.
--------------------------------------------------------------------------------

-- Seconds thresholds evaluate against a raw duration, not the 0-1 fraction, so
-- they need their own domain - but the same builder and the same cache. The key
-- is prefixed so "below 5 seconds" and "below 5 percent" can never collide.
local SECONDS_DOMAIN = 3600      -- an hour; longer than any buff or cooldown
local function GetSecondsCurve(sec)
    if type(sec) ~= "number" or sec ~= sec or sec <= 0 then return nil end
    sec = math_floor(sec * 10 + 0.5) / 10
    -- Epsilon from the THRESHOLD, never the domain bound: a domain-scaled one
    -- makes a multi-second ramp that interpolates instead of stepping, which turns
    -- a threshold into a value read.
    return GetStepCurve("s" .. sec, sec, math_max(sec * 0.002, 0.001), SECONDS_DOMAIN)
end

--- Shared tail: evaluate one method against one curve and read the result's
--- zero-ness. The curve is 100 BELOW the threshold and 0 at/above it, so a
--- non-zero result means below. nil = no answer; callers must keep their fallback.
--- Counted into the SAME miss counter as the unit-threshold gates. Deliberately not
--- memoised: a duration object is a fresh userdata per call, so there is no stable
--- key to memo on, and the per-tick caches that would work live at the CALLER (a
--- DoT entry, a maintenance entry) where the identity is stable. Counting them here
--- means /jac inspect perf sees the real total instead of reporting only half the
--- layer - the DoT path runs per rotation spell per build and would otherwise be
--- invisible.
local function DurationBelow(durObj, method, curve)
    local fn = curve and durObj and durObj[method]
    if not fn then return nil end
    belowMisses = belowMisses + 1
    local ok, result = pcall(fn, durObj, curve)
    if not ok or result == nil then return nil end
    local zero = BlizzardAPI.IsSecretZero(result)
    if zero == nil then return nil end
    return not zero
end

--- Is less than `pct` percent of this duration left?
function BlizzardAPI.IsDurationBelowPercent(durObj, pct)
    pct = NormalizePct(pct)
    if not pct then return nil end
    return DurationBelow(durObj, "EvaluateRemainingPercent", GetThresholdCurve(pct))
end

--- Are fewer than `seconds` seconds left?
function BlizzardAPI.IsDurationBelowSeconds(durObj, seconds)
    return DurationBelow(durObj, "EvaluateRemainingDuration", GetSecondsCurve(seconds))
end

--- Is this duration's TOTAL length under `seconds`? Distinct from the question
--- above in the way that matters for interrupts: "how long is this cast" is a
--- property of the spell, "how much is left" is a property of the moment, and a
--- kick wants both (see BlizzardAPI.ShouldInterruptNow).
function BlizzardAPI.IsDurationTotalBelowSeconds(durObj, seconds)
    return DurationBelow(durObj, "EvaluateTotalDuration", GetSecondsCurve(seconds))
end

--------------------------------------------------------------------------------
-- INTERRUPT TIMING - kick LATE in a long cast, immediately in a short one.
--
-- Kicking the instant a cast starts is the common mistake: against anything with a
-- real cast time the target can simply start again, and against a player it invites
-- a deliberate fake-cast. Waiting is only correct when there IS time to wait -
-- holding a kick through a 1.5s cast risks missing it outright.
--
-- So the rule needs BOTH facts, and 12.0 hid both behind the cast bar's secret
-- duration. Two threshold reads answer it without reading either number:
--   short cast  (total < LONG_CAST)      -> kick NOW, there is no room to wait
--   long cast   + remaining < LATE_KICK  -> kick NOW, we are late enough
--   long cast   + plenty left            -> HOLD
-- Any unreadable answer returns nil, and callers must treat that as "no opinion"
-- and keep suggesting the kick - never as HOLD, which would silently withhold an
-- interrupt. Fail-open is the only safe direction here.
--------------------------------------------------------------------------------
-- Tuned off the failure asymmetry, not the midpoint. Kicking too EARLY costs one
-- interrupt cooldown (they simply cast again). Kicking too LATE lets the cast land,
-- which is the expensive half - and the player still has to see the cue and press,
-- so a threshold with no reaction margin is effectively "too late" by default.
-- Both numbers therefore bias toward pressing: hold only when the cast is long
-- enough that waiting genuinely buys something, and stop holding with a full second
-- still on the clock.
local LONG_CAST_SECONDS = 2.5   -- below this, waiting buys less than it risks
local LATE_KICK_SECONDS = 1.0   -- "late" = inside this much of the finish

--- @return boolean|nil true = press it now, false = hold, nil = cannot tell
function BlizzardAPI.ShouldInterruptNow(unit)
    if not (unit and UnitCastingInfo and UnitChannelInfo) then return nil end
    local durObj
    if UnitCastingDuration then                     ---@diagnostic disable-line: undefined-global
        local ok, d = pcall(UnitCastingDuration, unit)  ---@diagnostic disable-line: undefined-global
        if ok then durObj = d end
    end
    -- A channel is already "in progress" from the first tick, so there is no early
    -- window to avoid - it is only ever worth kicking now.
    if not durObj then return nil end
    local shortCast = BlizzardAPI.IsDurationTotalBelowSeconds(durObj, LONG_CAST_SECONDS)
    if shortCast == nil then return nil end
    if shortCast then return true end               -- no room to wait
    local late = BlizzardAPI.IsDurationBelowSeconds(durObj, LATE_KICK_SECONDS)
    if late == nil then return nil end
    return late
end

--- The duration object for a live aura instance, or nil. Verified in combat
--- 2026-08-10: the spellID->instanceID hop is NOT blocked, so callers that already
--- track an instance (MaintenanceTracker, DotTracker) can go straight here.
function BlizzardAPI.GetAuraDurationObject(unit, auraInstanceID)
    if not (unit and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration) then
        return nil
    end
    local ok, d = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    return ok and d or nil
end

--- Does this unit carry an absorb shield? UnitGetTotalAbsorbs is secret, so
--- before the zero-gate this was unknowable for anyone but ourselves (the
--- absorb GLOW booleans cover the player only). nil = no answer.
function BlizzardAPI.UnitHasAbsorb(unit)
    if not (unit and UnitGetTotalAbsorbs and BlizzardAPI.IsSecretZero) then return nil end
    local ok, amount = pcall(UnitGetTotalAbsorbs, unit)
    if not ok or amount == nil then return nil end
    local zero = BlizzardAPI.IsSecretZero(amount)
    if zero == nil then return nil end
    return not zero
end

--- Is this aura at or above `threshold` stacks? The engine renders the count
--- ONLY at/above the threshold (nil below it), so the nil-vs-string answer is
--- itself the boolean - the count is never read, and `~= nil` on a secret
--- string is a type-mismatch short-circuit (field-proven safe, no compare).
function BlizzardAPI.AuraStacksAtLeast(unit, auraInstanceID, threshold)
    local fn = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if not (fn and unit and auraInstanceID and threshold) then return nil end
    local ok, text = pcall(fn, unit, auraInstanceID, threshold)
    if not ok then return nil end
    return text ~= nil
end

--- The same question addressed by SPELL id instead of instance id - the form SimC
--- speaks. The spellID -> auraInstanceID hop is the one IsBuffWindowActive has used
--- in production since the buff-window gates shipped.
--- @return boolean|nil true / false / nil when the answer cannot be trusted
function BlizzardAPI.GetAuraStackAtLeast(unit, spellID, threshold)
    if not (unit and spellID and threshold and C_UnitAuras
            and BlizzardAPI.AuraStacksAtLeast) then return nil end
    if threshold <= 0 then return true end          -- "at least zero" is always true
    local ok, aura
    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    elseif C_UnitAuras.GetUnitAuraBySpellID then
        ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    else
        return nil
    end
    if not ok then return nil end
    local instId = aura and aura.auraInstanceID
    if not instId then
        -- Nothing came back. That means ZERO STACKS only where the lookup can be
        -- trusted: these queries are RequiresNonSecretAura, so under aura secrecy a
        -- PRESENT aura also returns nothing and absent-vs-hidden is undecidable.
        -- Answer only in the clear; otherwise say nothing and let callers fail open.
        if BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret() then return nil end
        return false
    end
    return BlizzardAPI.AuraStacksAtLeast(unit, instId, threshold)
end

--------------------------------------------------------------------------------
-- Managed setup for the party health alert (the signal group heals ride on).
--
-- Without this the player must find the alert in Blizzard's Accessibility
-- settings themselves, which is most of the reason the feature goes unused.
-- The addon may configure it because a controlled experiment (2026-08-09,
-- armed error capture) PROVED an addon-side SetCVar here does NOT taint the
-- alert manager: its laundered keys kept flipping plainly through several
-- fights after the write, with zero taint blocks recorded.
--
-- Discipline, mirroring the nameplate-CVar precedent: save exactly what we
-- found BEFORE the first write, never overwrite that snapshot with our own
-- values, and hand it all back when switched off. Writes are pcall'd - CVar
-- sets have been combat-restricted on some clients.
--------------------------------------------------------------------------------

local PARTY_ALERT_DEFAULT_PERCENT = 50

--- CVar value for a threshold percent, from Blizzard's own option table when
--- it is loaded (settings definitions are load-on-demand), else the shipped
--- layout: 0 = off, then 100, 90 ... 10.
function BlizzardAPI.PartyAlertValueForPercent(pct)
    local util = CombatAudioAlertUtil ---@diagnostic disable-line: undefined-global
    local get = util and util.GetPartyHealthPercentInfo
    if get then
        for v = 1, 20 do
            local ok, info = pcall(get, v)
            if not ok or type(info) ~= "table" then break end
            if info.percentVal == pct then return v end
        end
    end
    if pct and pct >= 10 and pct <= 100 and pct % 10 == 0 then return (110 - pct) / 10 end
    return nil
end

--- Turn the alert on at `pct`, silently. `store` is a persistent table (the
--- addon's saved variables) that receives the pre-change snapshot.
--- @return boolean applied, number|nil percent
function BlizzardAPI.ApplyManagedPartyAlert(store, pct)
    if type(store) ~= "table" or not SetCVar then return false end
    pct = pct or PARTY_ALERT_DEFAULT_PERCENT
    local value = BlizzardAPI.PartyAlertValueForPercent(pct)
    if not value then return false end
    -- Snapshot ONCE: a second apply must not capture our own values as the
    -- "originals" - that is how a restore silently becomes a no-op.
    if type(store.saved) ~= "table" then
        store.saved = {
            enabled = GetCVar("CAAEnabled"),
            percent = GetCVar("CAAPartyHealthPercent"),
            volume  = GetCVar("CAAPartyHealthVolume"),
        }
    end
    local ok = true
    ok = pcall(SetCVar, "CAAEnabled", "1") and ok
    ok = pcall(SetCVar, "CAAPartyHealthPercent", tostring(value)) and ok
    ok = pcall(SetCVar, "CAAPartyHealthVolume", "0") and ok
    store.percent = pct
    return ok, pct
end

--- Hand back exactly what was there before. Keeps the snapshot when a write
--- fails (combat restriction) so a later attempt can still restore it.
function BlizzardAPI.RestoreManagedPartyAlert(store)
    local saved = type(store) == "table" and store.saved or nil
    if not saved or not SetCVar then return true end
    local ok = true
    if saved.enabled ~= nil then ok = pcall(SetCVar, "CAAEnabled", saved.enabled) and ok end
    if saved.percent ~= nil then ok = pcall(SetCVar, "CAAPartyHealthPercent", saved.percent) and ok end
    if saved.volume  ~= nil then ok = pcall(SetCVar, "CAAPartyHealthVolume",  saved.volume)  and ok end
    if ok then store.saved = nil end
    return ok
end

--- Primary resource at cap, via the player-frame full-power pulse: the engine
--- branches on the secret amount and Plays/Stops the animation, leaving a plain
--- IsPlaying() (validated in combat 2026-07-24 - oscillates exactly with
--- energy/rage capping). Animations do not run on hidden frames, so a unit-frame
--- replacement addon yields a permanent false (fail-open), never a frozen true.
--- Only power types Blizzard gives a full-power animation ever report true.
function BlizzardAPI.IsPrimaryPowerCapped()
    local pf = PlayerFrame ---@diagnostic disable-line: undefined-global
    local f = pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
    f = f and f.ManaBarArea and f.ManaBarArea.ManaBar and f.ManaBarArea.ManaBar.FullPowerFrame
    local anim = f and f.PulseFrame and f.PulseFrame.PulseAnim
    if not (anim and anim.IsPlaying) then return false end
    local ok, playing = pcall(anim.IsPlaying, anim)
    return ok and playing == true
end

--- Engine-classified "unit currently has a crowd-control aura". The instance-ID
--- list is plain and countable in combat (validated 2026-07-24, incl. on a delve
--- boss), and CROWD_CONTROL is the engine's own classification - no curated list.
--- Fail-open: any doubt reads as "not CC'd".
function BlizzardAPI.IsUnitCrowdControlled(unit)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then return false end
    local ok, t = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HARMFUL|CROWD_CONTROL")
    if not ok or type(t) ~= "table" then return false end
    local okN, n = pcall(function() return #t end)
    if not okN or type(n) ~= "number" then return false end
    if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(n) then return false end
    return n > 0
end

--- How long is this unit's crowd control good for? Returns true when EVERY engine
--- classified CC aura on the unit expires within `seconds` - i.e. "the CC is about
--- to break". false when at least one is comfortably long, nil when it cannot be
--- answered (no CC, technique unavailable, or a duration that will not resolve).
---
--- Why this one is cheap where target DoTs were not: the aura filter hands back
--- PLAIN instance ids directly, so it skips the spellID -> auraInstanceID hop that
--- IS blocked for secret target auras (measured in combat 2026-08-10). The engine
--- both classifies the aura and supplies the handle; nothing is read or compared.
---
--- ADDON-INDEPENDENT, which is the point. Every other CC signal this file carries
--- is either inferred (a cast that kept going) or scraped from text the client
--- prints, and both are sensitive to what else is loaded and to locale. This asks
--- the aura system, so a UI replacement cannot affect the answer.
--- @return boolean|nil
function BlizzardAPI.IsCrowdControlExpiring(unit, seconds)
    if not (unit and seconds and C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
            and BlizzardAPI.IsDurationBelowSeconds) then return nil end
    local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, "HARMFUL|CROWD_CONTROL")
    if not ok or type(ids) ~= "table" then return nil end
    local answered, allExpiring = false, true
    for i = 1, #ids do
        local durObj = BlizzardAPI.GetAuraDurationObject(unit, ids[i])
        local below = durObj and BlizzardAPI.IsDurationBelowSeconds(durObj, seconds)
        if below ~= nil then
            answered = true
            -- One CC with real time left means the unit stays locked, whatever the
            -- others are doing - so a single `false` settles it.
            if not below then allExpiring = false break end
        end
    end
    if not answered then return nil end
    return allExpiring
end

--- Channeling right now? Own-unit channel info is fully plain in combat -
--- SecretWhenUnitSpellCastRestricted fires only for OTHER units (validated in
--- combat 2026-07-24, every field plain).
function BlizzardAPI.IsPlayerChanneling()
    return (UnitChannelInfo("player")) ~= nil
end

--- "Took unabsorbed damage within the last ~0.25s". The PlayerFrame animated-loss
--- bar is Show()n/Hide()n by privileged control flow on secret health deltas, so its
--- visibility reads plain - validated in combat 2026-07-24: flaps at ~1s cadence
--- under sustained damage, and stays hidden entirely while an absorb is up (its
--- OnUpdate cancels on any absorb). IsVisible, NOT IsShown: a unit-frame replacement
--- addon that hides PlayerFrame stops the bar updating, and IsVisible reads false
--- through the hidden ancestor instead of serving a frozen true.
function BlizzardAPI.IsActivelyTakingDamage()
    local pf = PlayerFrame ---@diagnostic disable-line: undefined-global
    local f = pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
    f = f and f.HealthBarsContainer and f.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
    if not (f and f.IsVisible) then return false end
    local ok, vis = pcall(f.IsVisible, f)
    return ok and vis == true
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

-- Shared bounded-insert for the JustACGlobal caches below: lazily creates
-- g[cacheKey] with its g[cacheKey.."N"] counter, and on a NEW key wipes at cap
-- (wipe-and-relearn) before counting it. Returns the cache table; the caller
-- writes the value.
local function BoundedGlobalCache(cacheKey, cap, key)
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    local nKey = cacheKey .. "N"
    local c = g[cacheKey]
    if not c then c = {}; g[cacheKey] = c; g[nKey] = 0 end
    if c[key] == nil then
        if (g[nKey] or 0) >= cap then
            wipe(c); g[nKey] = 0
        end
        g[nKey] = (g[nKey] or 0) + 1
    end
    return c
end

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
    local c = BoundedGlobalCache("creatureTypeCache", NAME_TYPE_CACHE_CAP, name)
    c[name] = typeID
end

-- Persistent, bounded name -> npcID cache, same shape and cap as the type cache above.
-- UnitGUID is secret in combat, so a mid-fight target swap otherwise loses the mob's
-- identity outright - and with it every chance to apply what we already learned about that
-- mob type. UnitName stays readable (the type cache above already leans on this), and a name
-- is enough to look up what was recorded while the GUID WAS readable.
--
-- Names are not unique across the game, so a recovered id is weaker evidence than one read
-- from a GUID. It is therefore allowed to READ what we know and never to WRITE it: nothing
-- reaches the immunity table on the strength of a name match. Same evidence rule as
-- engine-announced vs inferred immunity.
local function StoreNameNPCID(name, npcID)
    if not name or not npcID then return end
    local c = BoundedGlobalCache("npcIDCache", NAME_TYPE_CACHE_CAP, name)
    c[name] = npcID
end

local function LookupNameNPCID(name)
    if not name then return nil end
    local g = _G.JustACGlobal
    return g and g.npcIDCache and g.npcIDCache[name] or nil
end

-- Instance-level CC immunity cache (keyed by NPC ID from GUID).
-- UnitGUID() is SECRET in combat, so NPC ID is only populated when a target is
-- acquired out of combat (pre-pull) or on PLAYER_REGEN_ENABLED.  When a CC
-- failure is detected and the NPC ID is known, that mob TYPE is remembered for
-- the rest of the instance - all future mobs with the same NPC ID are suppressed
-- without needing to re-learn.
local ccImmuneNPCIDs = {}           -- [npcID] = true; persists across pulls
local currentTargetNPCID = nil      -- NPC ID from GUID when readable (authoritative)
local inferredTargetNPCID = nil     -- NPC ID recovered by NAME when the GUID is secret

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

-- CC-failure learning: mark the current target as CC-immune for the rest of combat once
-- something proves CC doesn't work on it.  Reset on PLAYER_TARGET_CHANGED and
-- PLAYER_REGEN_ENABLED.
--
-- This used to poll UnitIsCrowdControlled("target") after each CC. That function DOES NOT
-- EXIST: it appears nowhere in the 12.0 UI source, not even in the generated API
-- documentation, so the poll sat behind `if UnitIsCrowdControlled then` and never ran once.
-- Learning was left resting entirely on the two engine announcements below, which only fire
-- when the engine says "Immune" outright - so the ordinary case (the CC resolves, or is
-- quietly ignored, and the cast rolls on) taught us nothing and CC kept being offered.
-- Do not re-add a UnitIsCrowdControlled poll. The combat log, which would answer this
-- directly via SPELL_MISS, is a hard-blocked data source in 12.0 (see DebugCommands).
local ccFailureObserved = false     -- true = current target resisted/immune

-- Assigned further down, once the target-cast state it reads exists; called from
-- NotifyCCCastOnTarget, which only runs long after load.
local ArmCCInterruptCheck

-- Direct immunity signals (wired up in InitTargetCastTracking below).  The engine
-- announces a shrugged-off spell outright - that beats inferring immunity from a
-- crowd-control aura that never showed up.  Both signals are only trusted inside a
-- short window after a CC attempt, so an unrelated damage immunity (a shielded mob,
-- a phase where the boss ignores damage) can't condemn a target that CC would land on.
local CC_IMMUNE_SIGNAL_WINDOW = 1.5 -- seconds a CC attempt counts as "just tried"
local ccAttemptTime = 0             -- GetTime() when the player SENT a CC
local ccImmuneSignal = nil          -- which signal marked the target immune (diagnostics)

-- Cross-session CC immunity, account-wide (JustACGlobal), keyed by NPC ID.
--
-- Only ENGINE-ANNOUNCED immunities are written here. "cast-continued" is an inference - it
-- proves the CC did not stop THAT cast, which is a weaker claim than "CC does not work on
-- this mob": a boss with an unstoppable cast would otherwise blacklist its whole type
-- forever. Inference stays in the session cache below, where a mistake dies at the next
-- zone change; only the engine saying "Immune" outright earns a place on disk.
--
-- Two sightings before it counts, so a single fluke (an immunity phase, a shield that
-- happened to be up) can't condemn a mob type permanently.
local CC_IMMUNE_DB_CAP     = 500  -- ponytail: bounded by wipe-and-relearn, as the name cache
local CC_CONFIRM_SIGHTINGS = 2

local function CCImmuneDB()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    local db = g.ccImmuneNPCs
    if not db then db = {}; g.ccImmuneNPCs = db; g.ccImmuneNPCsN = 0 end
    return db, g
end

local function NoteConfirmedImmunity(npcID)
    local db = BoundedGlobalCache("ccImmuneNPCs", CC_IMMUNE_DB_CAP, npcID)
    db[npcID] = (db[npcID] or 0) + 1
end

local function IsConfirmedImmuneNPC(npcID)
    if not npcID then return false end
    local db = CCImmuneDB()
    return (db[npcID] or 0) >= CC_CONFIRM_SIGHTINGS
end

--- What the addon has learned, and a way to throw it away. A self-modifying blacklist that
--- can be wrong needs both. /jac inspect ccdb.
function BlizzardAPI.GetCCImmunityDBInfo()
    local db, g = CCImmuneDB()
    local target = currentTargetNPCID or inferredTargetNPCID
    return (g.ccImmuneNPCsN or 0), target, target and db[target] or nil, CC_CONFIRM_SIGHTINGS,
        (currentTargetNPCID == nil and inferredTargetNPCID ~= nil)
end

function BlizzardAPI.ClearCCImmunityDB()
    local _, g = CCImmuneDB()
    g.ccImmuneNPCs = nil
    g.ccImmuneNPCsN = nil
end

-- Which sources are the engine's own word rather than our inference.
local CC_ENGINE_ANNOUNCED = { ["unit-combat"] = true, ["ui-error"] = true }

--- Single sink for "this target shrugged off crowd control", whatever noticed it.
--- Remembers the immunity per mob TYPE when the NPC ID is known (only readable when the
--- target was acquired out of combat, or backfilled on combat exit - UnitGUID is secret in
--- combat) so later pulls of the same mob skip re-learning entirely.
local function MarkTargetCCImmune(source)
    ccFailureObserved = true
    ccImmuneSignal = source
    if currentTargetNPCID then
        ccImmuneNPCIDs[currentTargetNPCID] = true            -- this zone, any evidence
        if CC_ENGINE_ANNOUNCED[source] then
            NoteConfirmedImmunity(currentTargetNPCID)         -- on disk, engine's word only
        end
    end
end

function BlizzardAPI.RefreshTargetCreatureType()
    -- Clear per-target state first; a stale NPC ID is worse than nil (nil fails open).
    currentTargetNPCID = nil
    inferredTargetNPCID = nil
    -- Also reset CC-failure learning on target switch - the new target might
    -- be CC-able even if the previous one wasn't.
    ccFailureObserved = false
    ccAttemptTime = 0
    ccImmuneSignal = nil
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
    local tname = UnitName and UnitName("target")
    if tname and IsSecretValue(tname) then tname = nil end
    if guid and not IsSecretValue(guid) then
        currentTargetNPCID = ExtractNPCID(guid)
        -- Learn the name while the GUID is readable, so a later in-combat swap onto this
        -- same mob type can still be identified.
        if currentTargetNPCID and tname then StoreNameNPCID(tname, currentTargetNPCID) end
    elseif tname then
        -- GUID secret (mid-fight target swap): recover the id by name. READ-ONLY - see
        -- StoreNameNPCID. It lets us APPLY what we know, never add to it.
        inferredTargetNPCID = LookupNameNPCID(tname)
    end
end

--- The target's NPC ID for LOOKUPS: the GUID-derived one when we have it, otherwise the
--- name-recovered one. Never use this to record anything - writes take currentTargetNPCID.
local function LookupTargetNPCID()
    return currentTargetNPCID or inferredTargetNPCID
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

--- Called when the player successfully casts a real CC (not a pure interrupt) on the current
--- target. Arms the one check we can still make: if the target was mid-cast, did that cast
--- stop? Deliberately does NOT clear ccFailureObserved - knowing this target is immune
--- survives further attempts.
function BlizzardAPI.NotifyCCCastOnTarget()
    if ArmCCInterruptCheck then ArmCCInterruptCheck() end
end

--- Called on PLAYER_REGEN_ENABLED to reset per-target CC-failure learning for
--- the next combat session.  Instance-level ccImmuneNPCIDs is NOT cleared here
--- - it persists across pulls until the player changes zone.
function BlizzardAPI.ResetCCFailureLearning()
    ccFailureObserved = false
    ccAttemptTime = 0
    ccImmuneSignal = nil
end

--- Diagnostics only: which signal condemned the current target, or nil.
--- One of "unit-combat" (engine combat feedback), "ui-error" (cast rejected
--- outright), "cast-continued" (the CC did not stop the cast), or "npc-cache".
function BlizzardAPI.GetCCImmuneSignal()
    return ccImmuneSignal
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
            -- Same evidence rule as the live path: a backfilled sighting still only reaches
            -- disk if the ENGINE announced the immunity. This is the common case for a mob
            -- tab-targeted mid-fight, whose ID could not be read while it mattered, so
            -- skipping it here would keep the persistent table nearly empty in practice.
            if CC_ENGINE_ANNOUNCED[ccImmuneSignal] then
                NoteConfirmedImmunity(npcID)
            end
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

--- Is the current target an actual boss - a world boss, or a mob the encounter
--- engine put on a boss frame? UnitClassification is NeverSecret (no
--- SecretWhenUnitIdentityRestricted, re-checked against the 12.1 docs);
--- UnitIsUnit is not, so it goes through SafeUnitIsUnit and an unreadable
--- comparison counts as "not a boss".
--- Fail-open in both directions it is used: CC immunity loses a boss check, and
--- the wasted-cooldown guard declines to suppress. Never the reverse - a mob
--- wrongly called a boss would let CC through; a boss wrongly called trash would
--- suppress cooldowns during a real execute phase, which is far worse.
function BlizzardAPI.IsTargetBoss()
    if UnitClassification("target") == "worldboss" then return true end
    for i = 1, 5 do
        if BlizzardAPI.SafeUnitIsUnit("target", BOSS_UNITS[i], false) then return true end
    end
    return false
end

function BlizzardAPI.IsTargetCCImmune()
    -- 1) World bosses and boss-frame mobs are always CC-immune.
    if BlizzardAPI.IsTargetBoss() then return true end

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
    --     Looked up by GUID id when we have one, else by the name-recovered one, so a mob
    --     tab-targeted mid-fight still benefits from what earlier pulls taught us.
    local lookupNPCID = LookupTargetNPCID()
    if lookupNPCID and ccImmuneNPCIDs[lookupNPCID] then
        ccImmuneSignal = "npc-cache"
        return true
    end
    -- 3b) And what previous SESSIONS learned, but only where the engine itself announced the
    --     immunity, twice. Inference never reaches this table - see NoteConfirmedImmunity.
    if IsConfirmedImmuneNPC(lookupNPCID) then
        ccImmuneSignal = "npc-db"
        return true
    end

    -- 4) Per-target CC-failure learning: something proved CC does not work here. Set by the
    --    engine's own "Immune" announcements and by the cast-continued check (see
    --    ArmCCInterruptCheck) - no polling, the observation arrives on its own.
    if ccFailureObserved then return true end

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

    -- A flat value per side of the one threshold we actually have. The previous version
    -- interpolated a percentage out of the vignette's ALPHA, which is an animation phase
    -- (see GetLowHealthState) - it returned a number that swung across a 15-point range
    -- about twice a second while the player's health sat still. 30 is not a measurement,
    -- it is "somewhere under the 35% line", which is the entire content of the signal;
    -- callers that need better must use the threshold gate or an exact percent, and the
    -- `estimated` flag is how they tell. DefensiveEngine already refuses this branch
    -- outright (it gates on `estimated == false`).
    return BlizzardAPI.GetLowHealthState() and 30 or 100, true
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
-- Bumped whenever the cast being tracked becomes a DIFFERENT cast (new cast, new target).
-- Lets a delayed check tell "the cast I was watching is still running" from "a cast is
-- running", which are the same boolean and opposite conclusions.
local targetCastSerial = 0

-- A CC aimed at a target that is MID-CAST is being used as an interrupt, so the question is
-- not whether the mob got crowd-controlled - it is whether the cast stopped. If the same cast
-- is still going once the CC has had time to land, CC does not interrupt this target, and
-- that is the one thing we can still observe: no combat log, and no UnitIsCrowdControlled to
-- ask. Silence teaches nothing, so this is the signal that makes learning happen at all in
-- the ordinary case - the engine only announces "Immune" for outright rejections.
local CC_INTERRUPT_CHECK_DELAY = 0.6   -- seconds: cast travel + aura application, then look
ArmCCInterruptCheck = function()
    if not targetCastActive then return end
    local watched = targetCastSerial
    C_Timer.After(CC_INTERRUPT_CHECK_DELAY, function()
        if targetCastActive and targetCastSerial == watched then
            MarkTargetCCImmune("cast-continued")
        end
    end)
end

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
    targetCastSerial = targetCastSerial + 1   -- a probed cast is a different cast
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

--- True only for spells that apply an actual crowd-control mechanic.  Pure interrupts
--- are excluded: they impose a lockout rather than a CC, so their own immunity replies
--- would condemn targets that a real CC would land on just fine.
local SpellDBRef = nil
local function IsCCMechanicSpell(spellID)
    if not spellID then return false end
    if not SpellDBRef then SpellDBRef = LibStub("JustAC-SpellDB", true) end
    if not (SpellDBRef and SpellDBRef.IsCrowdControlSpell) then return false end
    if not SpellDBRef.IsCrowdControlSpell(spellID) then return false end
    return not (SpellDBRef.IsInterruptTypeSpell and SpellDBRef.IsInterruptTypeSpell(spellID))
end

local function CCAttemptIsRecent()
    return ccAttemptTime > 0 and (GetTime() - ccAttemptTime) <= CC_IMMUNE_SIGNAL_WINDOW
end

-- Locale-safe by construction: the message and the string we match it against both
-- come from the running client, so no English text is hardcoded.
local immuneErrorText = nil
local function IsImmuneErrorText(msg)
    if not msg or msg == "" then return false end
    if not immuneErrorText then
        immuneErrorText = {}
        local a, b = _G.SPELL_FAILED_IMMUNE, _G.IMMUNE
        if a then immuneErrorText[a] = true end
        if b then immuneErrorText[b] = true end
    end
    return immuneErrorText[msg] == true
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

    -- Direct CC-immunity signals.  UNIT_COMBAT carries no SecretPayloads annotation in
    -- 12.0, so its feedback string is plain and branchable - this is the same signal that
    -- paints the "Immune" text over the mob, i.e. the engine stating the spell did nothing.
    castEventFrame:RegisterUnitEvent("UNIT_COMBAT", "target")
    -- The other half: some targets reject the cast outright rather than resolving it, and
    -- that path reports through the red error line instead of combat feedback.
    castEventFrame:RegisterEvent("UI_ERROR_MESSAGE")
    -- Arms the window both signals are trusted in.  SENT rather than SUCCEEDED because a
    -- rejected cast never succeeds - which is exactly the case we're here to catch.
    castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

    castEventFrame:SetScript("OnEvent", function(_, event, _, arg2, _, arg4)
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
            -- Only cast STARTS bump the serial. An end sets targetCastActive false, which
            -- the delayed check already treats as "not still casting"; the serial exists
            -- solely so a REPLACEMENT cast can't be mistaken for the one we were watching.
            targetCastSerial = targetCastSerial + 1
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
        elseif event == "UNIT_SPELLCAST_SENT" then
            -- arg4 = spellID, plain for our own casts (the event is
            -- SecretWhenUnitSpellCastRestricted, which exempts the player).
            if not IsSecretValue(arg4) and IsCCMechanicSpell(arg4) then
                ccAttemptTime = GetTime()
            end
        elseif event == "UNIT_COMBAT" then
            -- arg2 = the feedback string behind the floating "Immune" over the mob.
            if arg2 == "IMMUNE" and CCAttemptIsRecent() then
                MarkTargetCCImmune("unit-combat")
            end
        elseif event == "UI_ERROR_MESSAGE" then
            -- arg2 = the error text. Gated on a recent CC attempt so an immunity raised
            -- against something else (a damage spell into a shield) doesn't cost the
            -- target its CC suggestions.
            if CCAttemptIsRecent() and IsImmuneErrorText(arg2) then
                MarkTargetCCImmune("ui-error")
            end
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
-- One def per class, expanded below into one RESOURCE_BARS entry per frame name.
-- `frames` are probed in order:
--   1. The 12.x Personal Resource Display builds its OWN class frame from the standard class
--      template and names it globally `prdClassFrame` (Blizzard_PersonalResourceDisplay.lua
--      SetupClassBar). It is a THIRD source, independent of both the player-frame bars and the
--      older nameplate bars, and it stays live whenever the PRD is enabled - including when an
--      addon replaces the player unit frame and hides Blizzard's own bars. Listed first for that
--      reason; same per-class shapes, so the class filter picks the right one.
--   2. The player-frame bar.
--   3. The older nameplate bar - a SEPARATE global reusing the same mixin (and therefore the
--      same shape) as the player-frame bar. It matters because an addon that replaces the
--      player unit frame hides Blizzard's bars, which stops them updating - with the PRD
--      enabled these keep running, so a player on a replacement unit-frame addon still gets a
--      resource read. Whichever bar is LIVE first wins; all carry identical data when up.
local RESOURCE_BAR_DEFS = {
    { class = "DRUID", res = "combo_points", event = "UNIT_POWER_FREQUENT",   -- isActive (boolean)
      frames = { "PersonalResourceDisplayFrame.classFrame", "DruidComboPointBarFrame", "ClassNameplateBarFeralDruidFrame" } },
    { class = "ROGUE", res = "combo_points", event = "UNIT_POWER_FREQUENT",   -- isFull   (boolean)
      frames = { "PersonalResourceDisplayFrame.classFrame", "RogueComboPointBarFrame", "ClassNameplateBarRogueFrame" } },
    { class = "MONK", res = "chi", event = "UNIT_POWER_FREQUENT",             -- active   (boolean)
      frames = { "PersonalResourceDisplayFrame.classFrame", "MonkHarmonyBarFrame", "ClassNameplateBarWindwalkerMonkFrame" } },
    { class = "WARLOCK", res = "soul_shard", event = "UNIT_POWER_FREQUENT",   -- fillAmount (0..1 fractional)
      frames = { "PersonalResourceDisplayFrame.classFrame", "WarlockPowerFrame", "ClassNameplateBarWarlockFrame" } },
    { class = "MAGE", res = "arcane_charges", event = "UNIT_POWER_FREQUENT",
      frames = { "PersonalResourceDisplayFrame.classFrame", "MageArcaneChargesFrame", "ClassNameplateBarMageFrame" } },
    { class = "EVOKER", res = "essence", event = "UNIT_POWER_FREQUENT",
      frames = { "PersonalResourceDisplayFrame.classFrame", "EssencePlayerFrame", "ClassNameplateBarDracthyrFrame" } },
    -- Paladin: runes hang off the bar as rune1..runeN. PaladinPowerBar.VisualState =
    -- 1 Inactive / 2 Active / 3 SpellReady -> filled when > 1.
    { class = "PALADIN", res = "holy_power", event = "UNIT_POWER_FREQUENT", indexed = "rune",
      state = "visualState", min = 1, max = 3, isFilled = function(v) return v > 1 end,
      frames = { "PersonalResourceDisplayFrame.classFrame", "PaladinPowerBarFrame", "ClassNameplateBarPaladinFrame" } },
    -- Death Knight: runes live in bar.Runes. RuneButtonMixin.VisualState =
    -- 1 Empty / 2 OnCooldown / 3 CooldownEnding / 4 Ready -> AVAILABLE ONLY at 4. Note this is a
    -- different enum to Paladin's under the same field name, hence per-bar semantics.
    { class = "DEATHKNIGHT", res = "rune", event = "RUNE_POWER_UPDATE", array = "Runes",
      state = "visualState", min = 1, max = 4, isFilled = function(v) return v == 4 end,
      frames = { "PersonalResourceDisplayFrame.classFrame", "RuneFrame", "DeathKnightResourceOverlayFrame" } },
}

--- Resolve a frame by global name, or by a dotted path off a global ("A.b.c").
--- The Personal Resource Display's class bar has NO global: SetupClassBar creates it with
--- FrameUtil.CreateFrame(nil, ...) - a nil name arg - so it is only ever reachable as
--- PersonalResourceDisplayFrame.classFrame. The old entry named a global "PersonalResourceDisplayFrame.classFrame"
--- that has never existed (zero occurrences in the entire UI source), so the PRD source -
--- listed FIRST precisely because it survives a replacement unit-frame addon - silently
--- never resolved and every class fell through to the player-frame bar. Fail-safe, and
--- therefore invisible: exactly the frame-path class of bug that hid the nameplate cast bar.
local function ResolveFrame(path)
    if type(path) ~= "string" then return nil end
    local obj
    for part in path:gmatch("[^.]+") do
        obj = (obj == nil) and _G[part] or obj[part]
        if obj == nil then return nil end
    end
    return obj
end

local RESOURCE_BARS = {}
for _, def in ipairs(RESOURCE_BAR_DEFS) do
    for _, frameName in ipairs(def.frames) do
        local entry = { frame = frameName }
        for k, v in pairs(def) do
            if k ~= "frames" then entry[k] = v end
        end
        RESOURCE_BARS[#RESOURCE_BARS + 1] = entry
    end
end

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

-- FAST PATH (validated in combat 2026-07-24, build 68887): the discrete power types are
-- flagged NeverSecret at the data level, so a direct UnitPower read stays plain even with
-- combat restrictions latched (measured on Feral: 3 CP at +4s, 5 CP at +10s, while
-- GetSpellCastCount read SECRET in the same snapshots). Gated per-type at RUNTIME via
-- GetPowerTypeSecrecy - if Blizzard ever unflags a type this falls back to the point-widget
-- reader below instead of reading a secret. Avoids the widget path's frozen-hidden-bar
-- hazard and its per-class field/enum mapping entirely.
-- DEATHKNIGHT deliberately absent: UnitPower's ready-rune semantics are unverified in-game,
-- and a wrong-but-plain number would mislead gates; runes keep the widget reader until a DK
-- session probes it (/jac inspect frames prints the raw read).
local DIRECT_POWER = {
    DRUID       = { pt = 4,  res = "combo_points" },
    ROGUE       = { pt = 4,  res = "combo_points" },
    WARLOCK     = { pt = 7,  res = "soul_shard", fractional = true },
    PALADIN     = { pt = 9,  res = "holy_power" },
    MONK        = { pt = 12, res = "chi" },
    MAGE        = { pt = 16, res = "arcane_charges" },
    EVOKER      = { pt = 19, res = "essence" },
}

local function DirectPowerRead(playerClass)
    local def = DIRECT_POWER[playerClass]
    if not def then return nil end
    if not (C_Secrets and C_Secrets.GetPowerTypeSecrecy) then return nil end
    local okS, lv = pcall(C_Secrets.GetPowerTypeSecrecy, def.pt)
    if not okS or lv ~= 0 then return nil end   -- 0 = Enum.SecrecyLevel.NeverSecret
    -- unmodified=true for fractional types: Destruction shards come back in tenths,
    -- preserving SimC's fractional soul_shard exactly as the widget fillAmount sum did.
    local okC, cur = pcall(UnitPower, "player", def.pt, def.fractional or nil)
    local okM, max = pcall(UnitPowerMax, "player", def.pt)
    if not (okC and okM) then return nil end
    if BlizzardAPI.IsSecretValue and (BlizzardAPI.IsSecretValue(cur) or BlizzardAPI.IsSecretValue(max)) then
        return nil   -- flag said plain but the read didn't: trust the read, fall back
    end
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    if def.fractional then cur = cur / 10 end
    return cur, max, def.res
end

--- Current discrete class-resource count, or nil when it can't be trusted.
--- Direct UnitPower first (NeverSecret-gated); the point-widget reader below is the fallback.
--- EVERY point must read: a partially-understood bar is not counted. That is the fallback for an
--- unmapped class and for any future Blizzard rename - "unknown" beats a confident zero, which
--- would otherwise report 0 resource and permanently sink every `>=`-gated spender. Callers treat
--- nil as unknown and fail open.
--- @return number|nil count, number|nil max, string|nil resource (SimC resource token)
function BlizzardAPI.GetClassResourcePoints()
    local _, playerClass = UnitClass("player")
    local cur, max, res = DirectPowerRead(playerClass)
    if cur ~= nil then return cur, max, res end
    for i = 1, #RESOURCE_BARS do
        local def = RESOURCE_BARS[i]
        -- Only this character's bar: another class's global exists but is never initialised, so
        -- skipping it avoids both the wasted scan and any chance of reading a foreign resource.
        local bar = (def.class == playerClass) and ResolveFrame(def.frame) or nil
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
