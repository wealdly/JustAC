-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: time-left clocks for held icons, one passthrough for every surface.
--
-- An icon held back by something with a timer (a self-buff, a debuff on the target, a
-- totem, a self-lockout) draws that timer as its swipe. Producers only record WHAT holds
-- an icon; this module alone decides HOW to draw it, most trusted source first:
--   1. the engine's own timer, passed through untouched (the self-buff's aura container,
--      the target aura's or totem slot's DurationObject): right in combat, never read;
--   2. a plain window from our own evidence (BlizzardAPI / DotTracker ladders: a reading
--      taken while it was plain, or our confirmed cast plus a duration we know);
--   3. nothing. Unknown stays unknown: no swipe rather than a guessed one.
-- Every number is unsecreted before arithmetic; DurationObjects only reach widgets.
-- Redraws happen when something that can move a timer changes (the version below), never
-- per frame: a drawn swipe animates by itself in between.
local AuraClock = LibStub:NewLibrary("JustAC-AuraClock", 1)
if not AuraClock then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local DotTracker = LibStub("JustAC-DotTracker", true)

local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local next = next
local type = type
local wipe = wipe

AuraClock.BUFF = "buff"
AuraClock.DEBUFF = "debuff"
AuraClock.TOTEM = "totem"
AuraClock.LOCKOUT = "lockout"

local function PlainNumber(v)
    v = BlizzardAPI and BlizzardAPI.Unsecret and BlizzardAPI.Unsecret(v)
    if type(v) ~= "number" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Version: bumped by anything that can move a drawn timer.
--------------------------------------------------------------------------------
local version = 1

--- Something that can move a timer changed: held icons redraw on their next refresh.
function AuraClock.Touch()
    version = version + 1
end

--------------------------------------------------------------------------------
-- Queue holds: replaced on every queue build. [displayID] = kind, key, dur.
--------------------------------------------------------------------------------
local function NewHoldSet() return { kind = {}, key = {}, dur = {} } end
local holds, staged = NewHoldSet(), NewHoldSet()
local stagedCount, heldCount = 0, 0

local function SameHolds()
    if stagedCount ~= heldCount then return false end
    for id, kind in pairs(staged.kind) do
        if holds.kind[id] ~= kind or holds.key[id] ~= staged.key[id] or holds.dur[id] ~= staged.dur[id] then
            return false
        end
    end
    return true
end

function AuraClock.BeginQueueHolds()
    wipe(staged.kind)
    wipe(staged.key)
    wipe(staged.dur)
    stagedCount = 0
end

--- Record what holds a queue entry back. key: the buff's aura id, the debuff's spell id or
--- the totem slot. dur: the buff's full duration (its plain window is read at draw time).
function AuraClock.HoldQueue(displayID, kind, key, dur)
    if not (displayID and kind and key) then return end
    if staged.kind[displayID] == nil then stagedCount = stagedCount + 1 end
    staged.kind[displayID], staged.key[displayID], staged.dur[displayID] = kind, key, dur
end

--- The build finished: its holds replace the last build's (a redraw only when they differ).
function AuraClock.EndQueueHolds()
    if SameHolds() then return end
    holds, staged = staged, holds
    heldCount = stagedCount
    AuraClock.Touch()
end

--------------------------------------------------------------------------------
-- Providers: holds owned elsewhere (DefensiveEngine's self-lockouts), asked lazily.
-- provider(spellID) -> kind, key, start, length, or nil. A provider calls Touch() itself
-- when its holds start or end.
--------------------------------------------------------------------------------
local providers = {}

function AuraClock.RegisterProvider(provider)
    for i = 1, #providers do
        if providers[i] == provider then return end
    end
    providers[#providers + 1] = provider
    AuraClock.Touch()
end

--- What holds this icon: kind, key, then the hold's extra (queue: the buff's duration;
--- provider: start, length). Queue holds count only for queue icons (includeQueue);
--- providers apply to every icon.
function AuraClock.Resolve(displayID, includeQueue)
    if not displayID then return nil end
    if includeQueue then
        local kind = holds.kind[displayID]
        if kind then return kind, holds.key[displayID], holds.dur[displayID] end
    end
    for i = 1, #providers do
        local kind, key, start, length = providers[i](displayID)
        if kind then return kind, key, start, length end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
AuraClock._buttons = setmetatable({}, { __mode = "k" })   -- buttons that drew a clock (diagnostics)
local maintenanceAura     -- UIMaintenanceAura: UI module, loads after this file

local function MaintenanceAura()
    if maintenanceAura == nil then maintenanceAura = LibStub("JustAC-UIMaintenanceAura", true) or false end
    return maintenanceAura or nil
end

local function DetachContainer(button)
    local ma = MaintenanceAura()
    if ma and button._maintAura then ma.Detach(button) end
end

local function DrawDuration(button, durObj)
    if not (durObj and button.cooldown.SetCooldownFromDurationObject) then return false end
    return pcall(button.cooldown.SetCooldownFromDurationObject, button.cooldown, durObj) == true
end

-- Per kind: draw the engine's own timer (return its source) or return a plain start, length.
local engineOrWindow = {}

engineOrWindow[AuraClock.BUFF] = function(button, key, dur)
    local ma = MaintenanceAura()
    button._auraClockEntry = button._auraClockEntry or {}
    button._auraClockEntry.aura = key
    if ma and ma.Attach(button, button._auraClockEntry) then
        button.cooldown:Clear()
        return "engine-container"
    end
    local left = dur and BlizzardAPI and BlizzardAPI.GetBuffWindowRemaining
        and PlainNumber(BlizzardAPI.GetBuffWindowRemaining(key, dur))
    if left then return nil, GetTime() + left - dur, dur end
    return nil
end

engineOrWindow[AuraClock.DEBUFF] = function(button, key)
    if not DotTracker then return nil end
    if DotTracker.GetDurationObject and DrawDuration(button, DotTracker.GetDurationObject(key)) then
        return "engine-duration"
    end
    if DotTracker.GetCastWindow then return nil, DotTracker.GetCastWindow(key) end
    return nil
end

engineOrWindow[AuraClock.TOTEM] = function(button, key)
    if not BlizzardAPI then return nil end
    if BlizzardAPI.GetTotemDurationObject and DrawDuration(button, BlizzardAPI.GetTotemDurationObject(key)) then
        return "engine-duration"
    end
    if BlizzardAPI.GetTotemWindow then return nil, BlizzardAPI.GetTotemWindow(key) end
    return nil
end

--- Forget what this button drew (a real cooldown took the widget, or its spell changed).
function AuraClock.Release(button)
    if not button then return end
    DetachContainer(button)
    button._clockVer, button._clockID, button._clockQueue = nil, nil, nil
    button._clockCleared, button._auraClockSource, button._auraClockKind = nil, nil, nil
end

--- Draw the clock of whatever holds this icon, or clear the widget when nothing does.
--- gcdShown: the GCD sweep owns the widget this refresh; the clock redraws after it.
--- @return string|nil source "engine-container" | "engine-duration" | "estimate" | "none"
function AuraClock.Apply(button, displayID, includeQueue, gcdShown)
    if not (button and button.cooldown) then return nil end
    if gcdShown then
        DetachContainer(button)
        button._clockVer, button._clockCleared = nil, nil
        return nil
    end
    if button._clockVer == version and button._clockID == displayID and button._clockQueue == includeQueue then
        return button._auraClockSource
    end
    button._clockVer, button._clockID, button._clockQueue = version, displayID, includeQueue

    local kind, key, a, b = AuraClock.Resolve(displayID, includeQueue)
    if kind ~= AuraClock.BUFF then DetachContainer(button) end
    local source, start, length
    local draw = kind and engineOrWindow[kind]
    if draw then
        source, start, length = draw(button, key, a)
    else
        start, length = a, b   -- a provider's plain window (lockouts)
    end
    if not source and kind then
        start, length = PlainNumber(start), PlainNumber(length)
        if start and length and length > 0 and start + length > GetTime() then
            button.cooldown:SetCooldown(start, length)
            source = "estimate"
        else
            source = "none"
        end
    end
    if source == nil or source == "none" then
        -- Nothing to draw: clear once, not on every version change.
        if not button._clockCleared then button.cooldown:Clear() end
        button._clockCleared = true
    else
        button._clockCleared = nil
    end
    button._auraClockSource, button._auraClockKind = source, kind
    if source then AuraClock._buttons[button] = true end
    return source
end

--- Diagnostics: "<spell>:<kind>:<source>" for every shown icon drawing a clock.
function AuraClock.Debug()
    local rows = {}
    for button in pairs(AuraClock._buttons) do
        if button._auraClockSource and button.spellID and button.IsShown and button:IsShown() then
            rows[#rows + 1] = button.spellID .. ":" .. tostring(button._auraClockKind) .. ":" .. button._auraClockSource
        end
    end
    if #rows == 0 then return "none" end
    table.sort(rows)
    return table.concat(rows, ",")
end

--------------------------------------------------------------------------------
-- Events that can move a drawn queue-hold timer. Provider holds Touch() for themselves.
--------------------------------------------------------------------------------
local eventFrame = CreateFrame and CreateFrame("Frame")
if eventFrame and eventFrame.RegisterEvent and eventFrame.SetScript then
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")    -- debuff clocks belong to the new target
    eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")    -- secrecy edges change which source answers
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if eventFrame.RegisterUnitEvent then
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
    end
    eventFrame:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_TOTEM_UPDATE" then
            -- Read while it may be plain: learns the totem's duration for in-combat estimates.
            slot = PlainNumber(slot)
            if slot and BlizzardAPI and BlizzardAPI.GetTotemWindow then BlizzardAPI.GetTotemWindow(slot) end
        end
        if next(holds.kind) then AuraClock.Touch() end
    end)
end
