-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Fight Window - the last few abilities the game SERVED (its picks) and the player
-- USED (own casts), for the current fight. See Documentation/SAFE_LEAD_PLAN.md.
--
-- The game's pick churns faster than the situation it reveals, and one pick is thin evidence:
-- judged from the current pick alone, single/multi-target context flipped 49 times across 19
-- recorded fights; judged from recent history it flipped 16 times, and it caught packs the
-- nameplate count cannot see (mobs on a companion, name-only mobs).
--
-- This is the game's own view, a fraction of a second late. It supplies context and
-- safeguards. It is NEVER evidence for leading over the pick.
local FightWindow = LibStub:NewLibrary("JustAC-FightWindow", 1)
if not FightWindow then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local GetTime = GetTime

-- Ring of parallel arrays (no per-entry table): kind "S" served, "U" used, "T" target change.
-- Sized so six TYPED picks survive the casts, off-GCD presses and untyped picks between them.
local SIZE = 32
local rT, rID, rKind, rArch, rRange = {}, {}, {}, {}, {}
local head, count = 0, 0

local function Push(now, id, kind, arch, range)
    head = head % SIZE + 1
    rT[head], rID[head], rKind[head], rArch[head], rRange[head] = now, id, kind, arch, range
    if count < SIZE then count = count + 1 end
end

-- Stuck-pick tracking for the pick currently being served.
local servedID, servedSince, usedOther, usedPick = nil, 0, 0, false
local STUCK_SECONDS, STUCK_CASTS = 6, 3
local stuckSeen = {}   -- [pick id] = longest stretch (s) it sat unpressed this session

local function SamePress(castID, pickID)
    if castID == pickID then return true end
    if not BlizzardAPI then return false end
    local shown = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(pickID)
    if shown == castID then return true end
    local base = BlizzardAPI.ResolveBaseSpellID and BlizzardAPI.ResolveBaseSpellID(castID)
    return base ~= nil and (base == pickID or base == shown)
end

--- The game's pick for this build. Only a CHANGE of pick is a new entry; nil = the game is
--- serving nothing (a wait), which ends the current stretch.
--- @param arch string|nil the PICK's own tag ("aoe" | "cleave" | "st"), before any promotion
function FightWindow.Served(id, now, arch, range)
    if id == servedID then return end
    servedID, servedSince, usedOther, usedPick = id, now, 0, false
    if id then Push(now, id, "S", arch, range) end
end

--- A successful player cast.
function FightWindow.Used(id, now)
    if not id then return end
    now = now or GetTime()
    Push(now, id, "U")
    if not servedID then return end
    if SamePress(id, servedID) then
        usedPick = true
    else
        usedOther = usedOther + 1
        -- Pressing other things for seconds while one pick stays up and never gets pressed:
        -- the player cannot press it (off the bars, missing from a custom list, out of reach).
        local secs = now - servedSince
        if not usedPick and usedOther >= STUCK_CASTS and secs >= STUCK_SECONDS
           and secs > (stuckSeen[servedID] or 0) then
            stuckSeen[servedID] = secs
        end
    end
end

--- History across a target swap may or may not still apply; consumers decide.
function FightWindow.TargetChanged(now)
    Push(now or GetTime(), 0, "T")
end

--- Leaving combat: the next fight starts with no history.
function FightWindow.Reset()
    head, count = 0, 0
    servedID, usedOther, usedPick = nil, 0, false
end

local TYPED_LOOKBACK, MULTI_NEEDED = 6, 2

--- Multi-target context from recent picks: at least MULTI_NEEDED multi-target picks among the
--- last TYPED_LOOKBACK TYPED picks. Untyped picks (a cooldown, a buff) say nothing about the
--- pack and are skipped, so a long untyped stretch does not age the memory of one.
--- @return string|nil arch, string|nil range  of the most recent multi-target pick
function FightWindow.MultiContext()
    local typed, multi, arch, range = 0, 0, nil, nil
    local i = head
    for _ = 1, count do
        if rKind[i] == "S" and rArch[i] then
            typed = typed + 1
            if rArch[i] == "aoe" or rArch[i] == "cleave" then
                multi = multi + 1
                if not arch then arch, range = rArch[i], rRange[i] end
            end
            if typed >= TYPED_LOOKBACK then break end
        end
        i = (i - 2) % SIZE + 1
    end
    if multi >= MULTI_NEEDED then return arch, range end
    return nil
end

--- Longest stretch (seconds) this pick sat served-but-unpressed this session, or nil.
function FightWindow.StuckSeconds(id)
    return id and stuckSeen[id] or nil
end

--- Diagnostics: newest first. fn(age, kind, id, arch)
function FightWindow.ForEach(fn)
    local now, i = GetTime(), head
    for _ = 1, count do
        fn(now - rT[i], rKind[i], rID[i], rArch[i])
        i = (i - 2) % SIZE + 1
    end
end

--- Self-check (/jac inspect window selftest): the ring, the lookback and the stuck rule.
function FightWindow.SelfTest()
    local savedHead, savedCount, savedStuck = head, count, stuckSeen
    local sT, sID, sK, sA, sR = rT, rID, rKind, rArch, rRange
    rT, rID, rKind, rArch, rRange, stuckSeen = {}, {}, {}, {}, {}, {}
    FightWindow.Reset()
    local ok = true
    FightWindow.Served(1, 0, "aoe", "melee")
    ok = ok and FightWindow.MultiContext() == nil            -- one multi pick is not a pack
    FightWindow.Served(2, 1, "st")
    FightWindow.Served(3, 2, nil)                             -- untyped: skipped
    FightWindow.Served(4, 3, "cleave", "ranged")
    local a, r = FightWindow.MultiContext()
    ok = ok and a == "cleave" and r == "ranged"               -- 2 of last 6 typed, newest wins
    for i = 5, 9 do FightWindow.Served(i, i, "st") end
    ok = ok and FightWindow.MultiContext() == nil             -- single-target picks flush it
    for i = 10, 40 do FightWindow.Served(i, i, "st") end      -- wraps the ring
    ok = ok and count == SIZE
    FightWindow.Served(99, 100, "st")
    FightWindow.Used(7, 101); FightWindow.Used(7, 104); FightWindow.Used(7, 107)
    ok = ok and FightWindow.StuckSeconds(99) == 7             -- 3 other casts over >= 6s
    FightWindow.Served(98, 200, "st")
    FightWindow.Used(98, 201); FightWindow.Used(7, 204); FightWindow.Used(7, 207); FightWindow.Used(7, 210)
    ok = ok and FightWindow.StuckSeconds(98) == nil           -- it WAS pressed: not stuck
    rT, rID, rKind, rArch, rRange, stuckSeen = sT, sID, sK, sA, sR, savedStuck
    head, count = savedHead, savedCount
    servedID, usedOther, usedPick = nil, 0, false
    return ok
end
