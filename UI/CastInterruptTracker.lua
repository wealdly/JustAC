-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Cast Interrupt Tracker Module
-- Centralises all interrupt-detection state, cast-bar discovery, and sound playback.
-- UIRenderer and UINameplateOverlay both delegate to the public functions here
-- so there is exactly one debounce timer for the whole addon.
local CastInterruptTracker = LibStub:NewLibrary("JustAC-CastInterruptTracker", 1)
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
-- Curated for alert utility — short, distinctive, attention-grabbing.
if LSM then
    local BUILTIN_SOUNDS = {
        -- Iconic WoW alerts
        ["JAC: Night Elf Bell"]    = 566558,  -- DBM default raid warning
        ["JAC: Raid Emote"]        = 876098,  -- Blizzard raid warning chime
        ["JAC: Algalon Black Hole"]= 543587,  -- DBM special warning 2
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
-- Cast bar discovery: Blizzard → Plater → ElvUI.
-- Source-verified paths (2026-03-01):
--   Blizzard : nameplate.UnitFrame.castBar  (capital U)
--   Plater   : nameplate.unitFrame.castBar  (lowercase u)
--   ElvUI    : nameplate child → .Castbar   (capital C, oUF element)
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

    -- Plater: lowercase .unitFrame (Details! Framework)
    local puf = nameplate.unitFrame
    if puf and puf ~= uf then
        local bar = puf.castBar
        if bar and bar.IsShown and bar:IsShown() then
            return bar, "plater"
        end
    end

    -- ElvUI: oUF child .Castbar is not a named field, must enumerate children.
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
                        return cb, "elvui"
                    end
                end
            end
        end
    end

    return nil, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Returns (isCasting, isInterruptible, castBar).
-- Cascades: event tracker → cast bar frame fields → API fallback → fail-open.
-- Only one pcall remains (notInterruptible may be a secret boolean in 12.0).
-- ─────────────────────────────────────────────────────────────────────────────
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

        -- Direct field: notInterruptible (secret boolean in combat)
        local niOk, ni = pcall(function() return bar.notInterruptible and true or false end)
        if niOk and ni then return true, false, bar end

        -- Icon hidden when not interruptible (IsShown inherits secret from SetShown)
        local iconOk, iconHidden = pcall(function()
            return bar.Icon and bar.HideIconWhenNotInterruptible and not bar.Icon:IsShown()
        end)
        if iconOk and iconHidden then return true, false, bar end

        -- BorderShield visible = not interruptible (IsShown/GetAlpha inherit secret)
        local shieldOk, shieldShown = pcall(function()
            return bar.BorderShield and bar.BorderShield:IsShown() and (bar.BorderShield:GetAlpha() or 0) > 0.5
        end)
        if shieldOk and shieldShown then return true, false, bar end

        -- ElvUI uses .Shield instead of .BorderShield
        if barSource == "elvui" then
            local elvOk, elvShown = pcall(function()
                return bar.Shield and bar.Shield:IsShown() and (bar.Shield:GetAlpha() or 0) > 0.5
            end)
            if elvOk and elvShown then return true, false, bar end
        end
    end

    -- API fallback when no cast bar frame is available (nameplates off + addon target frame).
    if barSource == "api" then
        local castName, notInt
        castName, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
        -- Cast name is secret in 12.0 combat; secret non-nil = cast exists.
        if not BlizzardAPI.IsSecretValue(castName) and not castName then
            castName, _, _, _, _, _, notInt = UnitChannelInfo("target")
        end
        -- notInterruptible is a secret boolean in 12.0 — check before comparing.
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

--- Cached per-frame (≤0.015 s); both renderers share the same answer and debounce timer.
---
--- @param resolvedInts  table?   ordered {spellID, type} array from SpellDB.ResolveInterruptSpells
--- @param interruptMode string   "kickOnly" | "ccPrefer"
--- @param currentTime   number   GetTime() value from the caller
--- @return table  { shouldShow, spellID, castBar } — reused each call; do NOT hold across frames
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

    local debounceActive = (currentTime - lastInterruptUsedTime) < INTERRUPT_DEBOUNCE
                        or (currentTime - lastCCAppliedTime)    < CC_APPLIED_SUPPRESS

    if not debounceActive and resolvedInts and BlizzardAPI.IsTargetInterruptWorthy() then
        local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target", false)

        -- Unified interruptibility check: event tracker → cast bar fields → API fallback.
        local isCasting, interruptible, bar = IsTargetCastInterruptible(nameplate)

        if isCasting then
            local targetCCImmune  = BlizzardAPI.IsTargetCCImmune()
            local targetAlreadyCC = UnitIsCrowdControlled and UnitIsCrowdControlled("target") or false
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
                for _, entry in ipairs(resolvedInts) do
                    local sid, stype = entry.spellID, entry.type
                    -- In ccOnly mode, skip non-CC spells (kicks can't stop shielded casts).
                    -- In kickOnly mode, skip CC spells entirely.
                    if ccOnly and stype ~= "cc" then
                        -- skip
                    elseif interruptMode == "kickOnly" and stype == "cc" then
                        -- skip
                    elseif (stype == "cc" and targetCCImmune) or targetAlreadyCC then
                        -- CC spells unusable on immune / already CC'd targets — skip.
                    elseif stype == "cc" and not BlizzardAPI.IsCCSpellTypeValid(sid) then
                        -- Type-restricted CC (e.g. Repentance) on an incompatible creature type — skip.
                    -- failOpen=true for kicks (short CD, always useful to remind);
                    -- failOpen=false for CCs so we never recommend one we can't confirm is castable.
                    elseif BlizzardAPI.IsSpellUsable(sid, stype ~= "cc") and not SpellDB.IsInterruptOnCooldown(sid) then
                        if (preferCC or ccOnly) and stype == "cc" then
                            if ccOnly and SpellDB.IsSilenceClassCC(sid) then
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
                    intSpellID = silenceFallbackID or fallbackID
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
