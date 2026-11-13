-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- Shared probe primitives.
--
-- Every probe in this file has to answer the same first question - "did that read
-- come back plain, secret, absent, or blocked?" - and the whole point of the file
-- is that those answers stay trustworthy when the client changes underneath us. So
-- there is ONE definition of each, and the probes format it rather than re-deriving
-- it. Copies drift, and a probe that disagrees with the next probe about what
-- "secret" means is worse than no probe at all: it sends you looking in the wrong
-- layer. (One did exactly that - the heal grid used the weak test below and would
-- print a struct field as plain when it was not.)
--------------------------------------------------------------------------------

-- The ENGINE primitive, not our wrapper around it. BlizzardAPI.IsSecretValue is a
-- nil-guarded passthrough to exactly this, and a probe should measure the client
-- rather than the addon's opinion of the client - if the two ever disagree, that
-- disagreement is the finding.
local function IsSecret(v)
    return v ~= nil and issecretvalue ~= nil and issecretvalue(v) or false
end

-- The STRONG secrecy test, and the reason SafeSecret is not just IsSecret: event
-- args and struct fields can be secret in ways IsSecretValue misses, so force the
-- value through the operations a secret throws on (compare + concat) inside a
-- pcall and treat any throw as secret.
-- @return string|nil plain text, or nil when the value is secret
local function PlainText(v)
    local ok, s = pcall(function()
        local str = tostring(v)
        local _ = (str == "")
        return str .. ""
    end)
    if ok and type(s) == "string" then return s end
    return nil
end

-- Print-safe stringify: "nil" for nil, "<secret>" for secret values, else the
-- plain string.
local function SafeSecret(v)
    if v == nil then return "nil" end
    return PlainText(v) or "<secret>"
end

-- Chat-only presentation. Capture proxies continue receiving the original rows.
function DebugCommands.ChatOutput(addon)
    return setmetatable({ Print = function(_, message)
        local text = SafeSecret(message)
        for row in (text .. "\n"):gmatch("(.-)\n") do
            local plain = row:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if #plain <= 76 then
                addon:Print(row)
            else
                local line, pos = "", 1
                while pos <= #plain do
                    local first, last = plain:find("%S+", pos)
                    if not first then break end
                    -- Keep clickable links intact, including spaces in their labels.
                    local linkStart = plain:find("|H", first, true)
                    if linkStart and linkStart <= last then
                        local label = plain:find("|h", linkStart + 2, true)
                        local finish = label and plain:find("|h", label + 2, true)
                        if finish then last = finish + 1 end
                    end
                    local word = plain:sub(first, last)
                    if #line + #word + 1 > 76 and line:find("%S") then
                        addon:Print(line)
                        line = "  "
                    end
                    if line == "" or line == "  " then
                        line = line .. word
                    else
                        line = line .. " " .. word
                    end
                    pos = last + 1
                end
                if line:find("%S") then addon:Print(line) end
            end
        end
    end }, { __index = addon, __newindex = addon })
end

--- Perform one candidate read and classify what came back. THE primitive every
--- probe's per-read verdict is built on.
--- @param fn function the read, called under pcall
--- @param cap number|nil truncate the plain text to this many characters
--- @return string status one of "err" | "nil" | "secret" | "plain"
--- @return string text the error message, "nil", "<secret>", or the plain value
--- @return any value the raw value, for probes that need to measure it further
local function ProbeRead(fn, cap)
    local ok, v = pcall(fn)
    if not ok then
        return "err", tostring(v):gsub("^.-:%d+: ", ""):sub(1, 52), nil
    end
    if v == nil then return "nil", "nil", nil end
    local s = PlainText(v)
    if not s then return "secret", "<secret>", v end
    if cap and #s > cap then s = s:sub(1, cap) .. ".." end
    return "plain", s, v
end

-- ProbeReport closes over the classifier defined below.
local ClassifyRead

--- The line shape the capability sweeps print: "  <label> = <classified read>".
--- Returns a closure so the sweeps read as a flat list of the things they measure
--- rather than repeating the formatting on every row.
local function ProbeReport(addon)
    return function(label, fn)
        addon:Print("  " .. label .. " = " .. ClassifyRead(fn))
    end
end

--- Walk a global frame path, nil-safe at every hop: FramePath("PlayerFrame",
--- "PlayerFrameContent", ...). Blizzard renames and re-nests these between
--- patches, which is the whole reason the probes read them - so a missing hop is
--- an ANSWER ("that node is gone"), not an error.
local function FramePath(root, ...)
    local node = _G[root]
    for i = 1, select("#", ...) do
        if node == nil then return nil end
        node = node[select(i, ...)]
    end
    return node
end

--- The player health bar, wherever it currently lives. Two probes read this and
--- they must agree: if one resolved the frame and the other did not, the reports
--- would disagree about whether the FRAME moved or the READ broke - which is the
--- exact question they exist to answer. The retail path first, then the legacy
--- alias a unit-frame replacement addon may still expose.
local function PlayerHealthBar()
    return FramePath("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                     "HealthBarsContainer", "HealthBar")
        or FramePath("PlayerFrame", "healthbar")
end

--- The nameplate cast bar, resolved the way PRODUCTION resolves it. Every probe below used
--- to hardcode `np.UnitFrame.castBar`, which 12.x emptied by nesting the bar under
--- CastBarsContainer - so the probes reported "no cast bar" on a client that has one, and
--- would have blamed a third-party addon for a path change. A probe that re-derives a frame
--- differently from the code it is diagnosing answers a question nobody asked.
local function NameplateCastBar(np)
    if not np then return nil end
    local CIT = LibStub("JustAC-CastInterruptTracker", true)
    if CIT and CIT.DebugFindCastBar then
        local bar = CIT.DebugFindCastBar(np)
        if bar then return bar end
    end
    local uf = np.UnitFrame
    if not uf then return nil end
    return (uf.CastBarsContainer and uf.CastBarsContainer.castBar) or uf.castBar
end

--- "Name (id)" for a spell, or "? (id)" when the client has not streamed it in.
local function SpellLabel(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return (n or "?") .. " (" .. tostring(id) .. ")"
end

--- One colour per status, so a green cell means the same thing in every probe.
local function ProbeColour(status)
    return (status == "err" and "|cffff6666") or (status == "nil" and "|cff888888")
        or (status == "secret" and "|cffff6600") or "|cff2ecc71"
end

--- ProbeRead, pre-coloured for a report line.
--- @return string coloured cell
--- @return string status
--- @return any value
local function ProbeCell(fn, cap)
    local status, text, value = ProbeRead(fn, cap)
    return ProbeColour(status) .. text .. "|r", status, value
end

--- Classify one candidate read. Never throws.
function ClassifyRead(fn)   -- forward-declared local, see ProbeReport
    local status, text, v = ProbeRead(fn, 24)
    if status == "err" then return "|cffff6600ERROR|r " .. text end
    if status == "nil" then return "|cff888888nil|r (absent - not evidence either way)" end

    local isSecret = status == "secret"
    -- `if v then` is ALLOWED on a secret NUMBER (its truthiness is always true, so it leaks
    -- nothing) but THROWS on a secret BOOLEAN (there, truthiness IS the secret). That is the
    -- whole rule: the engine permits exactly the operations that leak no information. So this
    -- column is only interesting when the value is a boolean.
    local branchOk = pcall(function() if v then return 1 end return 0 end)
    -- Ordering is only meaningful for numbers - `false > 0` is a TYPE error, not secrecy, and
    -- reporting that as "n" made plain booleans look blocked in the first run of this probe.
    local isNum = (type(v) == "number") or (isSecret and not pcall(function() return v == true end))
    local cmpOk = isNum and pcall(function() return v > 0 end) or false

    local shown = isSecret and "|cffff6600SECRET|r" or ("|cff2ecc71plain|r=" .. text)
    return string.format("%s [%s] branch:%s cmp:%s", shown, type(v),
        branchOk and "|cff2ecc71y|r" or "|cffff6600n THROWS|r",
        isNum and (cmpOk and "|cff2ecc71y|r" or "|cffff6600n|r") or "|cff888888-|r")
end

-- SecrecyLevel enum, hoisted: 0 = the direct lookup always works for that spell.
local SECRECY_LEVEL = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }

--------------------------------------------------------------------------------
-- Shared rotation-pool lookup for capability diagnostics.
--------------------------------------------------------------------------------

--- Rotation ids helper for the audit probes (first n, fail-open to empty).
local function RotationIds(n)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local list = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
    local ids = {}
    if list then for i = 1, math.min(n, #list) do ids[i] = list[i] end end
    return ids
end

DebugCommands._Common = {
    IsSecret = IsSecret,
    PlainText = PlainText,
    SafeSecret = SafeSecret,
    ProbeRead = ProbeRead,
    ClassifyRead = ClassifyRead,
    ProbeReport = ProbeReport,
    FramePath = FramePath,
    PlayerHealthBar = PlayerHealthBar,
    NameplateCastBar = NameplateCastBar,
    SpellLabel = SpellLabel,
    ProbeColour = ProbeColour,
    ProbeCell = ProbeCell,
    SECRECY_LEVEL = SECRECY_LEVEL,
    RotationIds = RotationIds,
}
