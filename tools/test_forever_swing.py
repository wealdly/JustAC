# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The Forever swing tracker and attack-speed buff inference (BlizzardAPI/CooldownTracking.lua),
# run outside the game against the real file with PLAYER_SWING events fired through it. The
# event payload is the game's measured behaviour (plain duration + type, inter-swing gaps
# matching the duration); what is tested is the tracker built on it.
#
# Run: python tools/test_forever_swing.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.IsSecretValue = function() return false end
B.Unsecret = function(v) return v end
B.ResolveBaseSpellID = function() return nil end
B.IsForever = function() return true end
-- Slice and Dice: rank 1 5171, rank 3 6774 (the rank the player casts).
local RI = LibStub:NewLibrary("JustAC-RotationImport")
RI.RankBase = function(id) if id == 6774 then return 5171 end return id end
-- Battle Shout ranks 1-2, for the aura memory below.
RI.RankChain = function(id) if id == 6673 or id == 5242 then return { 6673, 5242 } end end
-- Player auras by id: { auraInstanceID, expirationTime }. aurasSecret = combat on Forever.
auras, aurasSecret = {}, true
B.AreAurasSecret = function() return aurasSecret end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if not aurasSecret then return auras[id] end end }
local SDB = LibStub:NewLibrary("JustAC-SpellDB")
SDB.HASTE_BUFFS = { [5171] = { swing = 0, max = 40 } }
SDB.StaticLookup = function(t, id) return t[id] end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
now = 100
function GetTime() return now end
local frames = {}
function CreateFrame()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:SetScript(_, fn) self.script = fn end
    frames[#frames + 1] = f
    return f
end
function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.script then f.script(f, event, ...) end
    end
end
C_Spell = {}
inCombat = false
function InCombatLockdown() return inCombat end
function UnitAttackSpeed() return 2.0, nil end
function UnitRangedDamage() return 3.0 end
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8"))
    B = lua.eval('LibStub("JustAC-BlizzardAPI")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    def at(t):
        g.now = t

    check(B.GetSwingRemaining(0) is None, "no swing yet -> unknown")
    # The game's melee check (PLAYER_SWING_RANGE_UPDATE: swingType, inRange, hasTarget).
    check(B.IsTargetInSwingRange(0) is None, "no range event yet -> unknown")
    lua.execute('Fire("PLAYER_SWING_RANGE_UPDATE", 0, false, true)')
    check(B.IsTargetInSwingRange(0) is False, "target out of swing range")
    lua.execute('Fire("PLAYER_SWING_RANGE_UPDATE", 0, true, true)')
    check(B.IsTargetInSwingRange(0) is True, "walked into melee")
    lua.execute('Fire("PLAYER_SWING_RANGE_UPDATE", 0, true, false)')
    check(B.IsTargetInSwingRange(0) is None, "target gone -> unknown, not 'in range'")
    lua.execute('Fire("PLAYER_ENTERING_WORLD")')          # base speeds read out of combat
    g.inCombat = True
    at(100); lua.execute('Fire("PLAYER_SWING", 2.0, 0)')
    at(100.5)
    check(abs(B.GetSwingRemaining(0) - 1.5) < 1e-9, "1.5s to the next main-hand swing")
    check(abs(B.GetSwingHaste(0) - 1.0) < 1e-9, "normal speed = 1.0")
    check(B.GetSwingRemaining(2) is None, "ranged untouched")
    w = B.GetSwingWindow(0)
    check(w == (100, 102.0), "swing window = last swing .. the swing a queued Heroic Strike waits for")
    at(103.0)
    check(B.GetSwingRemaining(0) == 0, "overdue swing clamps to 0")
    at(105.0)
    check(B.GetSwingRemaining(0) is None, "a whole extra round without a swing -> not swinging")

    # Slice and Dice cast at rank 3; its window is judged by the swings AFTER the cast.
    at(110); lua.execute('Fire("PLAYER_SWING", 2.0, 0)')
    at(110.2); B.NoteOwnCast(6774)
    check(B.IsBuffWindowActive(5171, 6) is True, "fresh cast, no later swing yet: base window")
    t = 111.8
    while t < 120:                                             # 25% faster, swing after swing
        at(t); lua.execute('Fire("PLAYER_SWING", 1.6, 0)')
        t += 1.6
    at(120)
    check(B.IsBuffWindowActive(5171, 6) is True, "swings show the speed-up: up past its 6s base")
    check(abs(B.GetSwingHaste(0) - 1.25) < 1e-9, "haste ratio 1.25")
    at(126)
    check(B.IsBuffWindowActive(5171, 6) is False, "stopped swinging: no evidence, base window over")
    at(121); lua.execute('Fire("PLAYER_SWING", 2.0, 0)')     # speed back to normal
    at(121.5)
    check(B.IsBuffWindowActive(5171, 6) is False, "speed gone: fell off / cancelled")
    at(160)
    check(B.IsBuffWindowActive(5171, 6) is False, "past its maximum: plain window (expired)")

    # Battle Shout cast before a /reload: no cast memory, but the aura read out of combat
    # (rank 2 on the player) carries its expiry into the fight.
    g.aurasSecret = False
    lua.execute("auras[5242] = { auraInstanceID = 1, expirationTime = 300 }")
    at(240)
    check(B.IsBuffWindowActive(6673, 180) is True, "out of combat: rank-2 aura found by rank 1")
    g.aurasSecret = True
    at(280)
    check(B.IsBuffWindowActive(6673, 180) is True, "in combat after a reload: up from the remembered expiry")
    at(301)
    check(B.IsBuffWindowActive(6673, 180) is False, "past the remembered expiry: down")
    g.aurasSecret = False
    lua.execute("auras[5242] = nil")
    at(250)
    check(B.IsBuffWindowActive(6673, 180) is False, "readable and absent: gone, memory dropped")
    g.aurasSecret = True
    check(B.IsBuffWindowActive(6673, 180) is False, "dropped memory stays dropped in combat")

    # Auto Shot switched on: the bar is seeded before the first shot. Its cooldown kept running
    # while off, so the first shot is due when that ends, or 0.15s in (measured), whichever is later.
    at(400); lua.execute('Fire("PLAYER_SWING", 2.0, 2)')       # a real shot
    at(400.5); lua.execute('Fire("STOP_AUTOREPEAT_SPELL")')
    check(B.GetSwingWindow(2) is None, "switched off: no ranged window")
    at(401); lua.execute('Fire("START_AUTOREPEAT_SPELL")')
    check(B.GetSwingWindow(2) == (400, 402.0), "back on within the cooldown: due when it ends")
    at(410); lua.execute('Fire("STOP_AUTOREPEAT_SPELL")')
    at(411); lua.execute('Fire("START_AUTOREPEAT_SPELL")')
    w = B.GetSwingWindow(2)
    check(w and abs(w[0] - 409.15) < 1e-6 and abs(w[1] - 411.15) < 1e-6, "on after a long pause: due 0.15s later")
    at(411.3); lua.execute('Fire("PLAYER_SWING", 2.0, 2)')     # the real first shot replaces it
    check(B.GetSwingWindow(2) == (411.3, 413.3), "the shot itself takes over")

    for why in bad:
        print("  FAIL", why)
    print("forever swing: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
