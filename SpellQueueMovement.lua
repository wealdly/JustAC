-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: the On the Move queue stage. While the player moves in combat, attacks that can be
-- cast on the move rise ahead of what needs standing still. Both clients; a custom list and
-- Retail's game pick in slot 1 keep their place.
-- Extends the JustAC-SpellQueue library. Loaded by JustAC.toc after SpellQueue.lua.
local SUBMAJOR, SUBMINOR = "JustAC-SpellQueue-Movement", 1
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local SpellQueue = LibStub("JustAC-SpellQueue", true)
if not SpellQueue then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

local IsPlayerMoving = IsPlayerMoving
local pcall = pcall
local type = type
local wipe = wipe

local sunkSet = SpellQueue._sunkSet
local lastCtx = SpellQueue._lastCtx

-- How long movement must last before the queue reorders, and how long standing still must last
-- before it returns. Shorter than a reaction, so a real move is answered by the time the player
-- could act on it; long enough that a sidestep or a stutter-step between casts does not flip
-- slot 1. The return is slower: a player weaving short moves stays on instants throughout.
local MOVE_START_DELAY = 0.25
local MOVE_STOP_DELAY = 0.40

local movingSince, stillSince
local onTheMove = false

local function ResetMovement()
    movingSince, stillSince, onTheMove = nil, nil, false
end

--- Has the player been moving long enough to count? An unreadable answer counts as standing.
function SpellQueue._OnTheMove(now)
    local ok, moving = pcall(IsPlayerMoving)
    if not ok or BlizzardAPI.IsSecretValue(moving) or type(moving) ~= "boolean" then
        ResetMovement()
        return false
    end
    if moving then
        stillSince = nil
        movingSince = movingSince or now
        if now - movingSince >= MOVE_START_DELAY then onTheMove = true end
    else
        movingSince = nil
        stillSince = stillSince or now
        if now - stillSince >= MOVE_STOP_DELAY then onTheMove = false end
    end
    return onTheMove
end

--- The player's choice, or the per-spec default when never set (ranged and healers on, melee
--- off), the same default as the move-cast marker.
function SpellQueue.OnTheMoveEnabled(profile)
    local setting = profile and profile.promoteOnTheMove
    if setting ~= nil then return setting end
    return SpellDB ~= nil and SpellDB.IsRangedOrHealerSpec ~= nil and SpellDB.IsRangedOrHealerSpec() == true
end

local promoted, others = {}, {}

--- While on the move, pressable attacks castable on the move go ahead of the first entry that
--- needs standing still. Each group keeps its order; with nothing to promote the queue is unchanged.
function SpellQueue._StageOnTheMove(b)
    lastCtx.onTheMove = nil
    if not b.inCombat or SpellQueue._rotationIsCustom or b.contextOrder == "off"
       or not SpellQueue.OnTheMoveEnabled(b.profile) then
        ResetMovement()
        return
    end
    if not SpellQueue._OnTheMove(b.now) then return end
    lastCtx.onTheMove = true

    local queue = b.recommendedSpells
    local first = 1
    if BlizzardAPI.HasGamePick() and b.leadMode ~= "mylist" then first = 2 end
    wipe(promoted)
    wipe(others)
    local blockedAt
    for i = first, b.spellCount do
        local id = queue[i]
        local castable
        if type(id) == "number" and id > 0 and not sunkSet[id] then
            local info = BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(id)
            castable = SpellDB.IsMoveCastableNow(id, info)
        end
        if not blockedAt then
            if castable == false then
                blockedAt = i
                others[1] = id
            end
        elseif castable == true and SpellQueue._PressableNow(id) then
            promoted[#promoted + 1] = id
        else
            others[#others + 1] = id
        end
    end
    if not blockedAt or #promoted == 0 then return end

    local position = blockedAt
    for i = 1, #promoted do
        queue[position] = promoted[i]
        position = position + 1
    end
    for i = 1, #others do
        queue[position] = others[i]
        position = position + 1
    end
end
