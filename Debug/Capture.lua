-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- The one capture log. Detail first: the limits are generous, and when one is reached only the
-- oldest tenth goes, so a long session keeps nearly all of itself. Every row is a constant of
-- the saved file's single Lua chunk, which holds 262,143 of them for the whole file (stock
-- Lua 5.1; not measured on the client), so the limit stays well below that. Color codes are
-- removed without wrapping rows. SavedVariables flush on /reload or logout, not while the
-- recorder is running.
--------------------------------------------------------------------------------
local IsSecret = DebugCommands._Common.IsSecret

local PROBE_LOG_MAX = 30000
local RESEARCH_LOG_MAX = 120000
local PROBE_LOG_KEEP = 0.9
local function ProbeLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.probeLog = g.probeLog or {}
    return g.probeLog
end

local function ProbeLogEmit(msg)
    local log = ProbeLogStore()
    msg = tostring(msg or "")
    -- A row built from a secret value (an enemy's name in a group) is itself secret: it cannot
    -- be searched or saved, so it is replaced, never indexed.
    if IsSecret(msg) then msg = "<secret row>" end
    -- Most rows carry no color code: only those that do pay for stripping it.
    if msg:find("|", 1, true) then msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    local count = #log + 1
    log[count] = msg
    local limit = PROBE_LOG_MAX
    if DebugCommands.CombatSignalReads then limit = RESEARCH_LOG_MAX end
    if count > limit then
        -- In place: the newest rows move to the front and the tail is cleared. No second table.
        local kept = math.floor(limit * PROBE_LOG_KEEP)
        local dropped = count - kept
        for i = 1, kept do log[i] = log[i + dropped] end
        for i = count, kept + 1, -1 do log[i] = nil end
        _G.JustACGlobal.probeLogDropped = (_G.JustACGlobal.probeLogDropped or 0) + dropped
        local session = DebugCommands._diagnosticSession
        if session then session.dropped = (session.dropped or 0) + dropped end
    end
end

--- Proxy addon whose Print goes to the log instead of chat; everything else
--- falls through to the real addon (db, methods).
local function LogProxy(addon)
    return setmetatable({ Print = function(_, msg) ProbeLogEmit(msg) end }, { __index = addon })
end

--- Proxy addon whose Print goes nowhere: for a recorder the session runs, whose own rows go to
--- the log directly and whose chat lines (how to switch it off by hand) say nothing true.
local function QuietProxy(addon)
    return setmetatable({ Print = function() end }, { __index = addon })
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
        addon:Print("errors: log cleared")
        return
    end

    if arg == "show" then
        local log = ErrorLogStore()
        if #log == 0 then addon:Print("errors: none captured.") return end
        addon:Print(string.format("errors: %d distinct", #log))
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
        addon:Print(string.format("errors: OFF - %d distinct entries held; /reload to save (JustACGlobal.errorLog)",
            #ErrorLogStore()))
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

    addon:Print("errors: ON - capturing Lua errors and taint blocks (repeats collapsed)")
    addon:Print("  /jac inspect errors show for a quick look; errors off, then /reload to save")
end

DebugCommands._Capture = {
    QuietProxy = QuietProxy,
    ProbeLogStore = ProbeLogStore,
    ProbeLogEmit = ProbeLogEmit,
    LogProxy = LogProxy,
}
