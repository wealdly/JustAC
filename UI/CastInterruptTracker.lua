-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Cast Interrupt Tracker Module
-- Centralises all interrupt-detection state, cast-bar discovery, and sound playback.
-- UIRenderer and UINameplateOverlay both delegate to the public functions here
-- so there is exactly one debounce timer for the whole addon.
local CastInterruptTracker = LibStub:NewLibrary("JustAC-CastInterruptTracker", 2)
if not CastInterruptTracker then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellDB     = LibStub("JustAC-SpellDB", true)

-- Hot path cache
local GetTime = GetTime
local pcall   = pcall
local pairs   = pairs

local C_NamePlate           = C_NamePlate
local UnitIsCrowdControlled = UnitIsCrowdControlled
local UnitCastingInfo       = UnitCastingInfo
local UnitChannelInfo       = UnitChannelInfo
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

-- Cast bar lingers after interrupt lands; suppress to avoid re-suggesting.
local INTERRUPT_DEBOUNCE    = 1.0
local lastInterruptUsedTime = 0
local lastInterruptShownID  = nil
-- 2s covers state-registration lag; short enough for back-to-back CCs to still work.
local CC_APPLIED_SUPPRESS = 2.0
local lastCCAppliedTime   = 0

-- LibSharedMedia integration for user-expandable interrupt sounds.
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Register built-in interrupt alert sounds with LSM.
-- Curated for alert utility - short, distinctive, attention-grabbing.
if LSM then
    local BUILTIN_SOUNDS = {
        -- Iconic WoW alerts
        ["JAC: Night Elf Bell"]    = 566558,  -- clear bell toll
        ["JAC: Raid Emote"]        = 876098,  -- Blizzard raid warning chime
        ["JAC: Algalon Black Hole"]= 543587,  -- deep warning swell
        ["JAC: PvP Flag"]          = 569200,  -- PVP flag taken
        -- Crisp alert tones
        ["JAC: Shing!"]            = 566240,  -- sharp metallic bling
        ["JAC: Wham!"]             = 566946,  -- heavy thud
        ["JAC: Simon Chime"]       = 566076,  -- classic alert chime
        ["JAC: Short Circuit"]     = 568975,  -- electric snap
        -- Dramatic stings
        ["JAC: Worgen Transform"]  = 552035,  -- dramatic sting
        ["JAC: Loatheb Aggro"]     = 554236,  -- eerie piercing
        ["JAC: Horseman Laugh"]    = 551703,  -- unmistakable
        -- Horns & blasts
        ["JAC: Dwarf Horn"]        = 566064,  -- short brass horn
        ["JAC: Grimrail Horn"]     = 1023633, -- train horn blast
        ["JAC: Fel Nova"]          = 568582,  -- arcane pulse
    }
    for name, fileDataID in pairs(BUILTIN_SOUNDS) do
        LSM:Register(LSM.MediaType.SOUND, name, fileDataID)
    end
end

local PlaySoundFile = PlaySoundFile
local lastInterruptSoundTime    = 0
local INTERRUPT_SOUND_DEBOUNCE  = 0.5

-- Shared between both renderers so interrupt debounce is unified.
local lastInterruptEvalTime = -1
local cachedIntResult = { shouldShow = false, spellID = nil, castBar = nil, interruptMode = nil }

-- ─────────────────────────────────────────────────────────────────────────────
-- Cast bar discovery. Source-verified frame paths (2026-03-01) covering the Blizzard
-- default and the common third-party cast-bar / nameplate addons:
--   "blizzard"     : nameplate.UnitFrame.castBar  (capital U)
--   "lowercaseUF"  : nameplate.unitFrame.castBar  (lowercase u)
--   "childCastbar" : a nameplate child's .Castbar  (unit-frame-library element)
-- ─────────────────────────────────────────────────────────────────────────────
local function FindVisibleCastBar(nameplate)
    if not nameplate then return nil, nil end

    local uf = nameplate.UnitFrame
    if uf then
        local bar = uf.castBar
        if bar and bar.IsVisible and bar:IsVisible() then
            return bar, "blizzard"
        end
    end

    -- lowercase .unitFrame (used by some cast-bar frameworks)
    local puf = nameplate.unitFrame
    if puf and puf ~= uf then
        local bar = puf.castBar
        if bar and bar.IsShown and bar:IsShown() then
            return bar, "lowercaseUF"
        end
    end

    -- child-element .Castbar is not a named field, must enumerate children.
    if nameplate.GetNumChildren then
        local numKids = nameplate:GetNumChildren()
        if numKids > 0 then
            -- Avoid re-evaluating the GetChildren() vararg per iteration.
            local children = { nameplate:GetChildren() }
            for i = 1, numKids do
                local child = children[i]
                if child then
                    local cb = child.Castbar
                    if cb and cb.IsShown and cb:IsShown() then
                        return cb, "childCastbar"
                    end
                end
            end
        end
    end

    return nil, nil
end

-- ═════════════════════════════════════════════════════════════════════════════
-- INTERRUPT DETECTION - what's secret, what works (verified 2026-06-28 via
-- /jac inspect castdiag; READ THIS before concluding interruptibility is "sealed").
-- In 12.0 an enemy cast's interruptibility is a secret value in combat. It is handled
-- in two layers:
--
-- 1. VISUAL suppression (universal) - in UIRenderer / UINameplateOverlay via
--    BlizzardAPI.ApplyInterruptIconAlpha. We forward UnitCastingInfo's secret
--    notInterruptible straight into the icon's SetAlphaFromBoolean - a secret-aware sink
--    (SecretArguments = AllowedWhenTainted) - so the engine sets the kick icon's alpha to 0
--    on a non-interruptible cast WITHOUT us ever reading the value. No cast-bar dependency,
--    so the kick is correctly hidden regardless of any cast-bar / nameplate / unit-frame
--    addon. (This is the same display mechanism Blizzard's own cast bars use for the shield.)
--
-- 2. LOGIC (kick-vs-CC substitution) - this function. Substituting a CC for a kick on a
--    non-interruptible cast requires BRANCHING on interruptibility, which a secret can't do.
--    The only readable signal is the "icon-hidden" check below: Blizzard hides the cast bar's
--    spell Icon on a non-interruptible cast, and bar.Icon:IsShown() is a CONCRETE, non-secret
--    boolean - but only when that bar's update ran in Blizzard's UNTAINTED, privileged stack.
--    A cast-bar addon that replaces or reskins (taints) the bar removes this signal.
--
-- WHAT IS SECRET / DOES NOT WORK (red herrings - do NOT re-derive "sealed" from these):
--   • bar.notInterruptible field    - never assigned by Blizzard's mixin (local/param only)
--   • bar:IsInterruptable()/barType  - `barType ~= CastingBarType.Uninterruptable`; comparing
--                                      those secret-wrapped enums errors under our taint
--   • BorderShield:IsShown()         - secret, but NOT via SetShown(notInterruptible): it is
--                                      driven by `showShield and not IsInterruptable()`, so the
--                                      secrecy comes from that same barType comparison
--   • cast bar fill atlas / color    - secret;  the cast spellID - secret
--   • UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE events - do NOT fire for these casts (any unit token)
--   • a private CastingBarFrame we create - runs in OUR taint → IsInterruptable() coerces wrong
--   • setting HideIconWhenNotInterruptible on a tainted bar - makes it THROW; do not do it
--
-- NET: the kick is correctly hidden everywhere (layer 1). Only the CC-substitution LOGIC
-- (layer 2) degrades when a cast-bar addon replaces/reskins the bar - there you get no
-- suggestion instead of a CC, never a wrongly-shown kick.
--
-- Returns (isCasting, isInterruptible, castBar). Cascade: event tracker (no-op for these
-- casts) → cast bar fields (icon-hidden is the one that works, on an untainted Blizzard bar)
-- → API fallback → fail-open.
-- ═════════════════════════════════════════════════════════════════════════════
local function IsTargetCastInterruptible(nameplate)
    local evtActive, evtInterruptible, evtKnown = BlizzardAPI.GetTargetCastInterruptState()
    local bar, barSource = FindVisibleCastBar(nameplate)

    -- No bar: confirm a cast via API (unless event tracker already says "no cast").
    if not bar then
        local spell
        if evtActive or not evtKnown then
            spell = UnitCastingInfo("target")
            -- Spell name is secret in 12.0 combat; a secret value IS non-nil → cast exists.
            if not BlizzardAPI.IsSecretValue(spell) and not spell then
                spell = UnitChannelInfo("target")
            end
        end
        if not BlizzardAPI.IsSecretValue(spell) and not spell then
            return false, false, nil
        end
        barSource = "api"
    end

    -- Event tracker is definitive (real boolean, never secret).
    if evtKnown then
        return true, evtInterruptible, bar
    end

    if bar then
        -- Every cast bar field/widget may propagate secret booleans in 12.0 combat.
        -- Blizzard's CastingBarMixin does BorderShield:SetShown(self.notInterruptible),
        -- so IsShown()/GetAlpha() on sub-widgets inherit the secrecy and crash on
        -- boolean tests. Wrap each check in pcall; crash = skip to next check.

        -- Direct field: notInterruptible. Blizzard's own mixin NEVER assigns this - it exists
        -- there only as a local/parameter - so on a stock bar this is always nil and falls
        -- through. Kept for a replacement bar that does expose it as a field.
        local niOk, ni = pcall(function() return bar.notInterruptible and true or false end)
        if niOk and ni then return true, false, bar end

        -- Icon hidden when not interruptible. CastingBarMixin:ShouldIconBeShown returns false
        -- from TWO guards BEFORE it ever tests interruptibility: `showIcon` (false when the
        -- player turns the cast-bar spell icon off) and a `look` other than "UNITFRAME" (set
        -- by a bar that reskins it). Without checking those first, a hidden icon reads as
        -- "uninterruptible" for EVERY cast, silently suppressing every kick suggestion for
        -- that player, permanently. Compare against false, not truthiness: a replacement bar
        -- may not carry these fields at all, and nil must keep the signal rather than kill it.
        local iconOk, iconHidden = pcall(function()
            return bar.Icon and bar.HideIconWhenNotInterruptible
                and bar.showIcon ~= false
                and (bar.look == nil or bar.look == "UNITFRAME")
                and not bar.Icon:IsShown()
        end)
        if iconOk and iconHidden then return true, false, bar end

        -- BorderShield visible = not interruptible (IsShown/GetAlpha inherit secret)
        local shieldOk, shieldShown = pcall(function()
            return bar.BorderShield and bar.BorderShield:IsShown() and (bar.BorderShield:GetAlpha() or 0) > 0.5
        end)
        if shieldOk and shieldShown then return true, false, bar end

        -- child-element cast bars use .Shield instead of .BorderShield
        if barSource == "childCastbar" then
            local altOk, altShown = pcall(function()
                return bar.Shield and bar.Shield:IsShown() and (bar.Shield:GetAlpha() or 0) > 0.5
            end)
            if altOk and altShown then return true, false, bar end
        end
    end

    -- API fallback when no cast bar frame is available (nameplates off + addon target frame).
    if barSource == "api" then
        local castName, notInt
        castName, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
        -- Cast name is secret in 12.0 combat; secret non-nil = cast exists.
        if not BlizzardAPI.IsSecretValue(castName) and not castName then
            _, _, _, _, _, _, notInt = UnitChannelInfo("target")
        end
        -- notInterruptible is a secret boolean in 12.0 - check before comparing.
        if BlizzardAPI.IsSecretValue(notInt) then
            return true, true, nil  -- secret → fail-open
        end
        if notInt ~= nil then
            return true, not notInt, nil
        end
    end

    -- Fail-open: no negative signal → assume interruptible.
    return true, true, bar
end

-- Diagnostic hook (/jac inspect castdiag): the live verdict the addon actually computes for
-- the current target, plus WHICH cascade check flagged "not interruptible" - so we read the
-- decision and its source instead of guessing from raw fields.
function CastInterruptTracker.DebugInterruptState()
    local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    local isCasting, interruptible = IsTargetCastInterruptible(nameplate)
    local _, _, evtKnown = BlizzardAPI.GetTargetCastInterruptState()
    local src
    if evtKnown then
        src = "event-tracker"
    else
        local b = FindVisibleCastBar(nameplate)
        if not b then src = "no-bar/api" else
            local niOk, ni = pcall(function() return b.notInterruptible and true or false end)
            local icOk, icHid = pcall(function() return b.Icon and b.HideIconWhenNotInterruptible
                and b.showIcon ~= false and (b.look == nil or b.look == "UNITFRAME")
                and not b.Icon:IsShown() end)
            local shOk, shShown = pcall(function() return b.BorderShield and b.BorderShield:IsShown() and (b.BorderShield:GetAlpha() or 0) > 0.5 end)
            if niOk and ni then src = "notInterruptible-field"
            elseif icOk and icHid then src = "icon-hidden"
            elseif shOk and shShown then src = "borderShield"
            else src = "fail-open(checks-passed)" end
        end
    end
    return isCasting, interruptible, src
end

--- Can the suggested ability actually hit the current target right now?
--- Ranged CCs/kicks: exact via IsSpellInRange. Player-centered AoE (reach="pbaoe"):
--- IsSpellInRange returns nil for self-centered spells and no API exposes radius-vs-distance,
--- so it FAILS OPEN. ponytail: PBAoE reach needs a distance signal we don't have; the melee-
--- range proxy (gap-closer, melee specs only) is the upgrade path if it proves worth it.
local function IsReachable(entry)
    if entry.reach == "pbaoe" then
        -- Self-centered AoE: reach = radius, and IsSpellInRange is nil for it. Use the
        -- range-probe bracket instead. nil (no probe / can't tell) → fail-open (never hide).
        local within = SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(entry.radius or 8)
        if within == nil then return true end
        return within
    end
    local r = C_Spell_IsSpellInRange and C_Spell_IsSpellInRange(entry.spellID)
    if r == nil or BlizzardAPI.IsSecretValue(r) then return true end  -- unknown → assume reachable
    return r ~= false
end

--- Cached per-frame (≤0.015 s); both renderers share the same answer and debounce timer.
---
--- @param resolvedInts  table?   ordered {spellID, type} array from SpellDB.ResolveInterruptSpells
--- @param interruptMode string   "kickOnly" | "ccPrefer"
--- @param currentTime   number   GetTime() value from the caller
--- @return table  { shouldShow, spellID, castBar } - reused each call; do NOT hold across frames
function CastInterruptTracker.EvaluateInterrupt(resolvedInts, interruptMode, currentTime)
    -- Keyed on time AND interruptMode so different renderer modes don't share stale results.
    if (currentTime - lastInterruptEvalTime) < 0.015
        and cachedIntResult.interruptMode == interruptMode then
        return cachedIntResult
    end
    lastInterruptEvalTime = currentTime
    cachedIntResult.interruptMode = interruptMode

    local shouldShow = false
    local intSpellID = nil
    local castBar    = nil

    -- Fears scatter packs and break on damage; excluded from suggestions by default.
    -- nil profile → exclude (fail-safe to the default-off behavior).
    local profile = BlizzardAPI.GetProfile()
    local includeFears = profile and profile.includeFears

    local debounceActive = (currentTime - lastInterruptUsedTime) < INTERRUPT_DEBOUNCE
                        or (currentTime - lastCCAppliedTime)    < CC_APPLIED_SUPPRESS

    if not debounceActive and resolvedInts and BlizzardAPI.IsTargetInterruptWorthy() then
        local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target", false)

        -- Unified interruptibility check: event tracker → cast bar fields → API fallback.
        local isCasting, interruptible, bar = IsTargetCastInterruptible(nameplate)

        if isCasting then
            local targetCCImmune  = BlizzardAPI.IsTargetCCImmune()
            -- Engine-classified CC check (plain instance-ID count, validated 2026-07-24)
            -- backs the speculative global, which has never been confirmed to exist.
            local targetAlreadyCC = (UnitIsCrowdControlled and UnitIsCrowdControlled("target"))
                or (BlizzardAPI.IsUnitCrowdControlled and BlizzardAPI.IsUnitCrowdControlled("target"))
                or false
            local canCC = not targetCCImmune and not targetAlreadyCC
            -- kickPrefer / ccPrefer: when cast is shielded, only CC spells can stop it.
            local ccOnly = not interruptible and canCC
                and (interruptMode == "kickPrefer" or interruptMode == "ccPrefer")
            local preferCC = interruptMode == "ccPrefer" and canCC

            -- Uninterruptible + kickOnly → nothing useful to suggest.
            if not interruptible and not ccOnly then
                -- fall through to no-show
            else
                -- Single-pass spell selection: prefer CC when configured, otherwise first usable.
                local fallbackID = nil
                local silenceFallbackID = nil   -- ccOnly: silence-class CC, used only if no stun-class CC found
                local outOfRangeFallbackID = nil -- usable but can't reach target; last resort (renderer flags out-of-range)
                for _, entry in ipairs(resolvedInts) do
                    local sid, stype = entry.spellID, entry.type
                    -- In ccOnly mode, skip non-CC spells (kicks can't stop shielded casts).
                    -- In kickOnly mode, skip CC spells entirely.
                    if ccOnly and stype ~= "cc" then
                        -- skip
                    elseif interruptMode == "kickOnly" and stype == "cc" then
                        -- skip
                    elseif (stype == "cc" and targetCCImmune) or targetAlreadyCC then
                        -- CC spells unusable on immune / already CC'd targets - skip.
                    elseif stype == "cc" and not BlizzardAPI.IsCCSpellTypeValid(sid) then
                        -- Type-restricted CC (e.g. Repentance) on an incompatible creature type - skip.
                    elseif stype == "cc" and not includeFears and entry.mech == 5 then
                        -- Fear-class CC: scatters packs / breaks on damage - skip unless opted in.
                    -- failOpen=true for kicks (short CD, always useful to remind);
                    -- failOpen=false for CCs so we never recommend one we can't confirm is castable.
                    elseif BlizzardAPI.IsSpellUsable(sid, stype ~= "cc") and not SpellDB.IsInterruptOnCooldown(sid) then
                        if not IsReachable(entry) then
                            -- Usable but can't hit the target now (e.g. a ranged CC out of range).
                            -- Keep only as a last resort; prefer any reachable option found below.
                            if not outOfRangeFallbackID then outOfRangeFallbackID = sid end
                        elseif (preferCC or ccOnly) and stype == "cc" then
                            if ccOnly and entry.mech == 9 then
                                -- A silence only stops magic casts; an uninterruptible cast
                                -- may be physical. Defer it and keep looking for a stun-class
                                -- CC that stops anything; use it only if nothing else turns up.
                                if not silenceFallbackID then silenceFallbackID = sid end
                            else
                                intSpellID = sid; shouldShow = true; break
                            end
                        elseif not fallbackID then
                            fallbackID = sid
                            if not preferCC and not ccOnly then break end
                        end
                    end
                end
                if not shouldShow then
                    intSpellID = silenceFallbackID or fallbackID or outOfRangeFallbackID
                    if intSpellID then shouldShow = true end
                end
            end
            -- castBar is nil for API fallback; callers gracefully hide cast aura.
            if shouldShow then castBar = bar end
        end
    end

    -- Runs every frame: detects when suggested spell goes on CD (≈ was cast).
    if lastInterruptShownID then
        if SpellDB.IsInterruptOnCooldown(lastInterruptShownID) then
            lastInterruptUsedTime = currentTime
            lastInterruptShownID  = nil
        elseif not shouldShow then
            lastInterruptShownID = nil
        end
    end
    if shouldShow and intSpellID then
        lastInterruptShownID = intSpellID
    end

    cachedIntResult.shouldShow = shouldShow
    cachedIntResult.spellID    = intSpellID
    cachedIntResult.castBar    = castBar
    return cachedIntResult
end

function CastInterruptTracker.PlayInterruptAlertSound(profile)
    local alertSound = profile.interruptAlertSound
    if not alertSound or alertSound == "None" then return end
    if not LSM then return end
    local soundFile = LSM:Fetch(LSM.MediaType.SOUND, alertSound, true)
    if not soundFile then return end
    local now = GetTime()
    if (now - lastInterruptSoundTime) < INTERRUPT_SOUND_DEBOUNCE then return end
    lastInterruptSoundTime = now
    PlaySoundFile(soundFile, "Master")
end

-- Suppresses CC suggestions until the game registers the CC state on the target.
function CastInterruptTracker.NotifyCCApplied()
    lastCCAppliedTime = GetTime()
end
