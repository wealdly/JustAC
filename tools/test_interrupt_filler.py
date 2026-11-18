# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""A short-cooldown damaging interrupt fills as damage only against a quiet open-world target.

Loads SpellQueue._InterruptFreeForDamage from SpellQueueForever.lua and the role clause of
PassesRotationFilters from SpellQueue.lua. Every unknown read must keep the spell reserved.

Run: python tools/test_interrupt_filler.py
"""
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
EARTH_SHOCK, KICK, FLAME_SHOCK = 8042, 1766, 8050


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        secret = {}
        forever, custom = true, false
        inInstance, isPlayer, controlled, boss, class = false, false, false, false, "normal"
        casting, hasCast, live = false, false, true
        SpellQueue = {}
        BlizzardAPI = {
            IsForever = function() return forever end,
            IsSecretValue = function(v) return v == secret end,
            IsTargetBoss = function() return boss end,
            GetTargetCastInterruptState = function() return casting, true, false end,
            HasTargetCastSinceSelected = function() return hasCast end,
            IsSpellAvailable = function() return true end,
            IsTotemSlotOccupied = function() return false end,
        }
        SpellDB = {
            IsInterruptTypeSpell = function(id) return id == 8042 or id == 1766 end,
            GetForeverAbilityRole = function(id)
                if id == 8042 or id == 1766 then return "utility" end
            end,
            GetForeverTotemSlot = function() return nil end,
        }
        RotationImport = {
            GetPushbackDamageCooldown = function(id)
                if id == 8042 then return 6 end
                if id == 1766 then return 10 end
            end,
        }
        function IsInInstance() return inInstance end
        function UnitIsPlayer() return isPlayer end
        function UnitPlayerControlled() return controlled end
        function UnitClassification() return class end
        function geterrorhandler() return function(message) error(message) end end
        local function IsLiveAttackableTarget() return live end
        local function PushbackRead(fn, ...)
            if not fn then return nil end
            local ok, value = pcall(fn, ...)
            if not ok or BlizzardAPI.IsSecretValue(value) then return nil end
            return value
        end
        rotationFilterCache = {}
        RedundancyFilter = nil
        SpellQueue._rotationIsCustom = false
        SpellQueue.ResolvePetRecoveryPick = function(id) return id end
    """ + section("SpellQueueForever.lua", "local FREE_INTERRUPT_TARGETS", "\n--- Can this be pressed right now")
        + section("SpellQueue.lua", "local function PassesRotationFilters", "\n-- Per-spell proc-priority")
        + """
        function Free(id) return SpellQueue._InterruptFreeForDamage(id) end
        function Filter(id)
            SpellQueue._rotationIsCustom = custom
            for key in pairs(rotationFilterCache) do rotationFilterCache[key] = nil end
            return PassesRotationFilters(id, {}, id)
        end
        function Reset()
            forever, custom = true, false
            inInstance, isPlayer, controlled, boss, class = false, false, false, false, "normal"
            casting, hasCast, live = false, false, true
        end
    """)
    return lua


def section(path, start, end):
    source = (ROOT / path).read_text(encoding="utf-8")
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


def main():
    lua = runtime()
    count = 0

    def check(setup, expression, why):
        nonlocal count
        lua.execute("Reset(); " + setup)
        assert lua.eval(expression), (setup, expression, why)
        count += 1

    check("", f"Free({EARTH_SHOCK}) and Filter({EARTH_SHOCK})", "quiet open-world normal target")
    check("", f"Filter({FLAME_SHOCK})", "an ordinary damage spell is unaffected")
    for setup, why in (
        ("inInstance = true", "inside an instance"),
        ("inInstance = secret", "instance state unreadable"),
        ("class = 'elite'", "elite target"),
        ("class = 'rareelite'", "rare elite target"),
        ("class = 'worldboss'", "world boss"),
        ("class = secret", "classification unreadable"),
        ("boss = true", "boss"),
        ("boss = secret", "boss state unreadable"),
        ("isPlayer = true", "player target"),
        ("controlled = true", "player-controlled target"),
        ("casting = true", "target is casting"),
        ("hasCast = true", "target has cast since it was selected"),
        ("live = false", "no live attackable target"),
        ("forever = false", "not the Forever client"),
    ):
        check(setup, f"not Free({EARTH_SHOCK})", why)
    for setup in ("inInstance = true", "class = 'elite'", "casting = true", "hasCast = true", "live = false"):
        check(setup, f"not Filter({EARTH_SHOCK})", "reserved: out of the automatic queue")
    check("", f"not Free({KICK}) and not Filter({KICK})", "a long-cooldown interrupt is never a filler")
    check("class = 'rare'", f"Free({EARTH_SHOCK})", "a non-elite rare is an ordinary fight")
    check("custom = true; casting = true", f"Filter({EARTH_SHOCK})", "a custom list keeps its own entries")
    print(f"ok ({count} checks)")


if __name__ == "__main__":
    main()
