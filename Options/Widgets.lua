-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Widgets - AceConfig entry builders.
--
-- Collapses the ~280 hand-written get/set/disabled closures that were duplicated
-- across the option panels into a handful of builders. Each builder takes the
-- addon, a profile path ("iconSize" or "nameplateOverlay.iconSize" - dots mean
-- nested, auto nil-guarded on write), and an opts table.
--
-- opts fields:
--   name, desc, order, width, values, sorting, min, max, step, ...  → passed through
--   default   → returned by get when the stored value is nil
--   onSet     → function(addon, val) run after the value is written
--   notify    → true to call AceConfigRegistry:NotifyChange afterwards
--   disabled  → function(addon) → bool  (wrapped so AceConfig calls it with addon)
--   hidden    → function(addon) → bool  (same)
--
-- Entries with exotic get/set logic (migrations, multi-field writes, frame
-- rebuilds) stay raw - the builders are opt-in, not mandatory.
local W = LibStub:NewLibrary("JustAC-OptionsWidgets", 1)
if not W then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local function notifyChange()
    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
end
W.NotifyChange = notifyChange

-- Full nameplate-overlay cluster rebuild (most overlay tweaks need it).
function W.rebuildNPO(addon)
    local NPO = LibStub("JustAC-UINameplateOverlay", true)
    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
end

-- displayMode == "disabled" turns off every surface; content toggles gate on it.
-- Resolved per call, not at load: Options/Core.lua loads after this file.
function W.fullyDisabled(addon)
    return LibStub("JustAC-Options", true).IsFullyDisabled(addon)
end

-- True when the player's class has no pet defaults (hides pet-related controls).
function W.petClassHidden()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local _, playerClass = UnitClass("player")
    return not (SpellDB and SpellDB.ClassHasPetDefaults and SpellDB.ClassHasPetDefaults(playerClass))
end

-- Keys consumed by the builders; everything else in opts is copied to the entry.
local CONTROL = {
    default = true, onSet = true, notify = true,
    disabled = true, hidden = true, get = true, set = true, path = true,
}

-- Split "a.b.c" → {"a","b","c"} once at build time (paths are constant strings).
local function compilePath(path)
    local segs = {}
    for seg in string.gmatch(path, "[^.]+") do
        segs[#segs + 1] = seg
    end
    return segs
end

-- Read profile[seg1][seg2]...; returns nil if any intermediate is missing.
local function pathGet(profile, segs)
    local t = profile
    for i = 1, #segs - 1 do
        t = t[segs[i]]
        if type(t) ~= "table" then return nil end
    end
    return t[segs[#segs]]
end

-- Return the parent table of the final segment, creating intermediates as needed.
local function pathEnsureParent(profile, segs)
    local t = profile
    for i = 1, #segs - 1 do
        if type(t[segs[i]]) ~= "table" then t[segs[i]] = {} end
        t = t[segs[i]]
    end
    return t
end

-- Copy passthrough fields and normalize the disabled/hidden predicates.
local function buildBase(addon, wtype, opts)
    local entry = {}
    for k, v in pairs(opts) do
        if not CONTROL[k] then entry[k] = v end
    end
    entry.type = wtype
    if opts.disabled ~= nil then
        if type(opts.disabled) == "function" then
            entry.disabled = function() return opts.disabled(addon) end
        else
            entry.disabled = opts.disabled
        end
    end
    if opts.hidden ~= nil then
        if type(opts.hidden) == "function" then
            entry.hidden = function() return opts.hidden(addon) end
        else
            entry.hidden = opts.hidden
        end
    end
    return entry
end

-- Standard scalar widget (toggle/range/select/etc.): get returns the stored value
-- or the default; set writes it, runs onSet, optionally notifies.
-- An explicit opts.get overrides the path read (e.g. remapping a legacy stored
-- value for display) - it was silently discarded before, which left the caller's
-- remap dead and the dropdown blank on legacy values.
local function scalar(addon, wtype, path, opts)
    local segs = compilePath(path)
    local lastKey = segs[#segs]
    local default = opts.default
    local onSet = opts.onSet
    local notify = opts.notify
    local entry = buildBase(addon, wtype, opts)
    entry.get = opts.get or function()
        local v = pathGet(addon.db.profile, segs)
        if v == nil then return default end
        return v
    end
    entry.set = function(_, val)
        local parent = pathEnsureParent(addon.db.profile, segs)
        parent[lastKey] = val
        if onSet then onSet(addon, val) end
        if notify then notifyChange() end
    end
    return entry
end

function W.toggle(addon, path, opts) return scalar(addon, "toggle", path, opts) end
function W.range(addon, path, opts)  return scalar(addon, "range",  path, opts) end
function W.select(addon, path, opts) return scalar(addon, "select", path, opts) end

-- Descriptions that cite an ability as an example carry a %s and name it by spell ID
-- here, letting the client supply the localized name. Hardcoding names into each locale
-- file got them wrong more often than right - the game's own strings are the only source
-- correct in every language, and they stay correct when Blizzard renames a spell.
--
-- Keep the cited examples few and class-agnostic. A list of per-spec abilities is noise:
-- the reader plays one spec, so every name but theirs is filler. Three survive - Victory
-- Rush, Execute, Soothe - each the canonical example of its concept for any class.
--
-- Returns a function, so names resolve when the tooltip is drawn rather than when the
-- options table is built (spell data is not guaranteed loaded that early). Falls back to
-- the unformatted string if a translation's placeholder count ever drifts, since a raw
-- format() error would take the whole panel down.
function W.spellDesc(key, ...)
    local ids = { ... }
    return function()
        local names = {}
        for i = 1, #ids do
            names[i] = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ids[i]))
                or ("#" .. tostring(ids[i]))
        end
        local ok, text = pcall(string.format, L[key], unpack(names))
        return ok and text or L[key]
    end
end

-- Standard "reset to defaults" scaffold shared by every panel: returns the empty
-- header spacer (at `order`) and the reset execute button (at `order + 1`) as two
-- values, so a call site assigns them to its resetHeader/resetDefaults keys. Only
-- desc and func vary between panels.
function W.resetButton(order, desc, func)
    return
        { type = "header", name = "", order = order },
        { type = "execute", name = L["Reset to Defaults"], desc = desc, order = order + 1, width = "normal", func = func }
end

-- Select value/sorting tables duplicated across panels. Locale strings are static
-- and loaded before this file, so building these once matches the inline copies
-- byte-for-byte. Read-only - never mutate.
W.GLOW_VALUES = {
    all         = L["All Glows"],
    primaryOnly = L["Primary Only"],
    procOnly    = L["Proc Only"],
    none        = L["No Glows"],
}
W.GLOW_SORTING = { "all", "primaryOnly", "procOnly", "none" }

-- Per-surface variants add the follow-the-shared-setting choice ("shared" is
-- also the AceDB default for the per-surface glow keys).
W.GLOW_VALUES_SHARED = {
    shared      = L["Use Shared Setting"],
    all         = L["All Glows"],
    primaryOnly = L["Primary Only"],
    procOnly    = L["Proc Only"],
    none        = L["No Glows"],
}
W.GLOW_SORTING_SHARED = { "shared", "all", "primaryOnly", "procOnly", "none" }

W.DEFENSIVE_DISPLAY_VALUES = {
    healthBased = L["When Health Low"],
    combatOnly  = L["In Combat Only"],
    always      = L["Always"],
}
W.DEFENSIVE_DISPLAY_SORTING = { "healthBased", "combatOnly", "always" }

W.QUEUE_VISIBILITY_VALUES = {
    always         = L["Always"],
    combatOnly     = L["In Combat Only"],
    requireHostile = L["Require Hostile Target"],
}
W.QUEUE_VISIBILITY_SORTING = { "always", "combatOnly", "requireHostile" }

-- The two per-surface enable toggles map onto the stored displayMode enum
-- ("disabled"/"queue"/"overlay"/"both") - presentation only; every existing
-- gate keeps reading the enum.
function W.SurfaceEnabled(addon, surface)
    local mode = addon.db.profile.displayMode or "queue"
    if surface == "queue" then return mode == "queue" or mode == "both" end
    return mode == "overlay" or mode == "both"
end

function W.SetSurfaceEnabled(addon, surface, on)
    local p = addon.db.profile
    local previous = p.displayMode or "queue"
    local queueOn = W.SurfaceEnabled(addon, "queue")
    local overlayOn = W.SurfaceEnabled(addon, "overlay")
    if surface == "queue" then queueOn = on else overlayOn = on end
    p.displayMode = (queueOn and overlayOn and "both") or (queueOn and "queue")
        or (overlayOn and "overlay") or "disabled"
    local NPO = LibStub("JustAC-UINameplateOverlay", true)
    if NPO then
        NPO.Destroy(addon)
        if overlayOn then NPO.Create(addon) end
    end
    if previous == "disabled" and p.displayMode ~= "disabled" then
        addon:InvalidateCaches({spells = true})
        addon:OnHealthChanged(nil, "player")
    end
    addon:ForceUpdateAll()
    notifyChange()
end

return W
