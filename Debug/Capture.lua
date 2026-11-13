-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- Bounded, shared capture storage. Color codes are removed without wrapping rows.
-- SavedVariables flush on /reload or logout, not while the recorder is running.
--------------------------------------------------------------------------------
local PROBE_LOG_MAX = 8000
local RESEARCH_LOG_MAX = 32000

local function ProbeLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.probeLog = g.probeLog or {}
    return g.probeLog
end

local function ProbeLogEmit(msg)
    local log = ProbeLogStore()
    log[#log + 1] = tostring(msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local limit = PROBE_LOG_MAX
    if DebugCommands.CombatSignalReads then limit = RESEARCH_LOG_MAX end
    if #log > limit then
        local keep, half = {}, math.floor(limit / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        local dropped = #log - #keep
        _G.JustACGlobal.probeLogDropped = (_G.JustACGlobal.probeLogDropped or 0) + dropped
        local session = DebugCommands._diagnosticSession
        if session then session.dropped = (session.dropped or 0) + dropped end
        _G.JustACGlobal.probeLog = keep
    end
end

--- Proxy addon whose Print goes to the log instead of chat; everything else
--- falls through to the real addon (db, methods).
local function LogProxy(addon)
    return setmetatable({ Print = function(_, msg) ProbeLogEmit(msg) end }, { __index = addon })
end

--------------------------------------------------------------------------------
-- /jac inspect errors [off|clear|show] - capture Lua errors AND taint blocks to
-- SavedVariables (JustACGlobal.errorLog), so a fight's worth of errors can be read
-- off disk after a /reload instead of copied out of a chat frame.
--
-- TWO channels, deliberately: a tainted-execution failure NEVER reaches
-- seterrorhandler - the client fires ADDON_ACTION_BLOCKED/FORBIDDEN as an event
-- carrying (addonName, functionName) instead. Capturing only the Lua handler is
-- how a taint problem looks like "no errors at all" while the screen fills up.
--
-- Entries are DEDUPED by message and counted. One bad call inside a combat-frequency
-- hook produces thousands of identical errors; storing each one buries the single
-- other error that actually matters and bloats the saved file for nothing.
--------------------------------------------------------------------------------
local ERRORLOG_MAX = 250      -- distinct entries, not occurrences

local function ErrorLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.errorLog = g.errorLog or {}
    return g.errorLog
end

--- Record one error/block, collapsing repeats into a count + last-seen time.
local function ErrorLogRecord(kind, msg, stack)
    local log = ErrorLogStore()
    local key = kind .. "|" .. tostring(msg or "?")
    for i = 1, #log do
        if log[i].key == key then
            local e = log[i]
            e.count = e.count + 1
            e.last = GetTime()
            e.lastCombat = UnitAffectingCombat("player") and true or false
            return
        end
    end
    if #log >= ERRORLOG_MAX then return end   -- full: keep the first N, they came first
    log[#log + 1] = {
        key = key, kind = kind, count = 1,
        msg = tostring(msg or "?"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
        stack = stack and tostring(stack):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil,
        first = GetTime(), last = GetTime(),
        firstCombat = UnitAffectingCombat("player") and true or false,
    }
end

function DebugCommands.ErrorCapture(addon, arg)
    arg = arg and arg:lower() or nil

    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.errorLog = nil end
        addon:Print("errors: |cffffff00log cleared|r")
        return
    end

    if arg == "show" then
        local log = ErrorLogStore()
        if #log == 0 then addon:Print("errors: none captured.") return end
        addon:Print(string.format("errors: |cffffff00%d distinct|r", #log))
        for i = 1, math.min(#log, 10) do
            local e = log[i]
            addon:Print(string.format("|cffff6600%d.|r [%s x%d%s] %s",
                i, e.kind, e.count, e.firstCombat and " COMBAT" or "", e.msg))
        end
        if #log > 10 then addon:Print(string.format("|cff888888... %d more; /reload and read the file|r", #log - 10)) end
        return
    end

    if arg == "off" or (not arg and DebugCommands._errorCapture) then
        local f = DebugCommands._errorCapture
        if f then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._errorCapture = nil
        end
        -- The Lua handler stays chained: seterrorhandler has no unregister, and
        -- restoring a stale handler would clobber whatever installed itself after us.
        -- The flag below is what actually gates recording.
        DebugCommands._errorCaptureOn = false
        addon:Print(string.format("errors: |cffff6600OFF|r - %d distinct entries held.", #ErrorLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.errorLog)|r")
        return
    end

    if DebugCommands._errorCapture then addon:Print("errors: already ON"); return end
    DebugCommands._errorCaptureOn = true

    -- Chain the Lua error handler once per session; the flag gates recording so
    -- toggling off/on never stacks handlers.
    if not DebugCommands._errorHandlerHooked then
        DebugCommands._errorHandlerHooked = true
        local prev = geterrorhandler and geterrorhandler()
        if seterrorhandler then
            seterrorhandler(function(msg)
                if DebugCommands._errorCaptureOn then
                    -- debugstack(2) skips this closure and the handler frame.
                    ErrorLogRecord("LUA", msg, debugstack and debugstack(2, 12, 12))
                end
                if prev then return prev(msg) end
            end)
        end
    end

    local f = CreateFrame("Frame")
    DebugCommands._errorCapture = f
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addonName, funcName)
        if not DebugCommands._errorCaptureOn then return end
        ErrorLogRecord(event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
            string.format("%s tried to call %s", tostring(addonName), tostring(funcName)))
    end)

    addon:Print("errors: |cff00ff00ON|r - capturing Lua errors and taint blocks.")
    addon:Print("|cff888888Fight, then '/jac inspect errors off' and /reload. '/jac inspect errors show' for a quick look.|r")
    addon:Print("|cff888888Repeats are collapsed into a count, so a flood shows as one line xN.|r")
end

DebugCommands._Capture = {
    ProbeLogStore = ProbeLogStore,
    ProbeLogEmit = ProbeLogEmit,
    LogProxy = LogProxy,
}
