# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# AuraClock: one time-left passthrough for held icons. Source ladder per hold kind (engine
# timer, plain window, nothing), secret safety, and redraws only when something changed.
# Also the totem window ladder in BlizzardAPI and the holds SpellQueue records.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def load():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "Libs" / "LibStub" / "LibStub.lua").read_text(encoding="utf-8"))
    lua.execute("""
        now = 100
        function GetTime() return now end
        function wipe(t) for k in pairs(t) do t[k] = nil end return t end
        secret = setmetatable({}, {__tostring = function() return "secret" end})
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI", 1)
        B.IsSecretValue = function(v) return rawequal(v, secret) end
        B.Unsecret = function(v) if v == nil or B.IsSecretValue(v) then return nil end return v end
        buffLeft = {}
        B.GetBuffWindowRemaining = function(id, dur) return buffLeft[id] end
        totemDurObj, totemWindow = nil, nil
        B.GetTotemDurationObject = function(slot) return totemDurObj end
        B.GetTotemWindow = function(slot) if totemWindow then return totemWindow[1], totemWindow[2] end end
        local D = LibStub:NewLibrary("JustAC-DotTracker", 1)
        dotDur, dotWindow = {}, {}
        D.GetDurationObject = function(id) return dotDur[id] end
        D.GetCastWindow = function(id) local w = dotWindow[id]; if w then return w[1], w[2] end end
        local M = LibStub:NewLibrary("JustAC-UIMaintenanceAura", 1)
        containerFor = {}
        M.Attach = function(button, entry)
            button._maintAura = containerFor[entry.aura] and {aura = entry.aura} or nil
            return containerFor[entry.aura] == true
        end
        M.Detach = function(button) button._maintAura = nil end
        handlers = {}
        function CreateFrame()
            return {RegisterEvent = function() end, RegisterUnitEvent = function() end,
                    SetScript = function(self, _, fn) handlers[#handlers + 1] = fn end}
        end
        function Fire(event, ...) for _, fn in ipairs(handlers) do fn(nil, event, ...) end end
        function NewButton()
            local b = {draws = 0}
            b.cooldown = {
                Clear = function() b.drawn = "clear"; b.draws = b.draws + 1 end,
                SetCooldown = function(_, s, l) b.drawn = "window:" .. s .. ":" .. l; b.draws = b.draws + 1 end,
                SetCooldownFromDurationObject = function(_, d)
                    if d == "bad" then error("rejected") end
                    b.drawn = "engine:" .. tostring(d); b.draws = b.draws + 1
                end,
            }
            return b
        end
        function Hold(id, kind, key, dur) AC.BeginQueueHolds(); AC.HoldQueue(id, kind, key, dur); AC.EndQueueHolds() end
    """)
    lua.execute((ROOT / "AuraClock.lua").read_text(encoding="utf-8"))
    lua.execute('AC = LibStub("JustAC-AuraClock")')
    return lua


def main():
    lua = load()
    count = 0

    def check(expression, why):
        nonlocal count
        assert lua.eval(expression), (why, lua.eval("tostring(b and b.drawn)"))
        count += 1

    # Buff: engine container first, then the plain window read at draw time.
    lua.execute('b = NewButton(); Hold(6673, "buff", 6673, 180); containerFor[6673] = true')
    lua.execute("src = AC.Apply(b, 6673, true, false)")
    check('src == "engine-container" and b.drawn == "clear"', "the engine container draws the buff")
    lua.execute("draws = b.draws; Hold(6673, 'buff', 6673, 180); AC.Apply(b, 6673, true, false)")
    check("b.draws == draws", "an unchanged rebuild does not redraw")
    check("AC.Resolve(6673, false) == nil", "queue holds are for queue icons only")
    lua.execute("containerFor[6673] = nil; buffLeft[6673] = 10; AC.Touch(); src = AC.Apply(b, 6673, true, false)")
    check('src == "estimate" and b.drawn == "window:-70:180" and b._maintAura == nil',
          "no container: the plain window, and the container detaches")
    lua.execute("buffLeft[6673] = secret; AC.Touch(); src = AC.Apply(b, 6673, true, false)")
    check('src == "none" and b.drawn == "clear"', "a secret time left is not drawn")
    lua.execute("draws = b.draws; AC.Touch(); AC.Apply(b, 6673, true, false)")
    check("b.draws == draws", "nothing to draw: cleared once, not on every change")

    # GCD owns the widget; the clock comes back after.
    lua.execute("buffLeft[6673] = 10; AC.Touch(); AC.Apply(b, 6673, true, false); draws = b.draws")
    lua.execute("AC.Apply(b, 6673, true, true)")
    check("b.draws == draws", "nothing drawn over the GCD sweep")
    lua.execute("src = AC.Apply(b, 6673, true, false)")
    check('src == "estimate" and b.draws == draws + 1', "the clock redraws when the GCD ends")

    # Debuff: the aura's DurationObject, else the tracker's cast window; target change redraws.
    lua.execute('Hold(1856, "debuff", 703); dotDur[703] = "garrote"; src = AC.Apply(b, 1856, true, false)')
    check('src == "engine-duration" and b.drawn == "engine:garrote"', "the target aura's own timer")
    lua.execute('dotDur[703] = nil; dotWindow[703] = {95, 18}; Fire("PLAYER_TARGET_CHANGED")')
    lua.execute("src = AC.Apply(b, 1856, true, false)")
    check('src == "estimate" and b.drawn == "window:95:18"', "target change redraws from the tracker")
    lua.execute('dotWindow[703] = {secret, 18}; Fire("UNIT_AURA", "target"); src = AC.Apply(b, 1856, true, false)')
    check('src == "none" and b.drawn == "clear"', "a secret window is not drawn")
    lua.execute('dotWindow[703] = nil; dotDur[703] = "bad"; AC.Touch(); src = AC.Apply(b, 1856, true, false)')
    check('src == "none"', "a DurationObject the widget refuses falls through safely")
    lua.execute("dotDur[703] = nil")

    # Totem: the slot's DurationObject, else BlizzardAPI's plain window.
    lua.execute('Hold(3599, "totem", 1); totemDurObj = "slot1"; src = AC.Apply(b, 3599, true, false)')
    check('src == "engine-duration" and b.drawn == "engine:slot1"', "the totem slot's own timer")
    lua.execute('totemDurObj = nil; totemWindow = {98, 30}; Fire("PLAYER_TOTEM_UPDATE", 1)')
    lua.execute("src = AC.Apply(b, 3599, true, false)")
    check('src == "estimate" and b.drawn == "window:98:30"', "a totem update redraws from the plain window")
    lua.execute("totemWindow = nil")

    # Events only redraw when a queue hold exists.
    lua.execute('AC.BeginQueueHolds(); AC.EndQueueHolds(); e = NewButton(); AC.Apply(e, 1, true, false)')
    lua.execute('draws = e.draws; Fire("UNIT_AURA", "player"); AC.Apply(e, 1, true, false)')
    check("e.draws == draws", "aura events with nothing held cost no redraw")

    # Providers apply to every icon (defensives), exact plain window.
    lua.execute("""
        locked = true
        AC.RegisterProvider(function(id) if id == 17 and locked then return "lockout", 6788, 100, 15 end end)
        d = NewButton(); src = AC.Apply(d, 17, false, false)
    """)
    check('src == "estimate" and d.drawn == "window:100:15" and d._auraClockKind == "lockout"',
          "a self-lockout draws on a defensive icon")
    lua.execute("now = 120; locked = false; AC.Touch(); src = AC.Apply(d, 17, false, false)")
    check('src == nil and d.drawn == "clear"', "nothing holds it: cleared")

    # Release forgets the clock (a real cooldown took the widget).
    lua.execute('containerFor[6673] = true; Hold(6673, "buff", 6673, 180); AC.Apply(b, 6673, true, false); AC.Release(b)')
    check("b._maintAura == nil and b._clockVer == nil and b._auraClockSource == nil", "release detaches and resets")

    count += totem_window()
    count += queue_holds()
    print(f"aura clock: {count} checks passed")


def totem_window():
    """BlizzardAPI.GetTotemWindow: a plain GetTotemInfo reading (learning the duration), else our
    latest cast into the slot plus its learned duration, else nothing."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    source = (ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    start = source.index("local ownCastAt = {}")
    end = source.index("\nlocal BUFF_UNKNOWN")
    lua.execute((ROOT / "Libs" / "LibStub" / "LibStub.lua").read_text(encoding="utf-8"))
    lua.execute("""
        now = 100
        function GetTime() return now end
        secret = {}
        IsSecretValue = function(v) return rawequal(v, secret) end
        Unsecret = function(v) if v == nil or IsSecretValue(v) then return nil end return v end
        BlizzardAPI = {ResolveBaseSpellID = function() return nil end}
        local frame = {RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function() end}
        function CreateFrame() return frame end
        LibStub:NewLibrary("JustAC-RotationImport", 1).RankBase = function(id)
            if id == 6363 then return 3599 end return id
        end
        LibStub:NewLibrary("JustAC-SpellDB", 1).FOREVER_TOTEM_SLOTS = {[3599] = 1, [8190] = 1}
        info = nil
        function GetTotemInfo(slot)
            if not info then return false, "", 0, 0, 0, 1, 0 end
            return info.have, "Totem", info.start, info.dur, 0, 1, info.spell
        end
    """ + source[start:end])
    count = 0

    def check(expression, why):
        nonlocal count
        assert lua.eval(expression), why
        count += 1

    lua.execute("info = {have = true, start = 98, dur = 30, spell = 6363}; s, l = BlizzardAPI.GetTotemWindow(1)")
    check("s == 98 and l == 30", "a plain reading is the window")
    lua.execute("""
        BlizzardAPI.NoteOwnCast(3599); castAt = now
        info = {have = secret, start = secret, dur = secret, spell = secret}
        s, l = BlizzardAPI.GetTotemWindow(1)
    """)
    check("s == castAt and l == 30", "secret reading: our cast plus the duration learned while plain (any rank)")
    lua.execute("now = now + 1; BlizzardAPI.NoteOwnCast(8190); s = BlizzardAPI.GetTotemWindow(1)")
    check("s == nil", "the latest totem in the slot decides; its duration is unknown")
    lua.execute("info = {have = false}; BlizzardAPI.NoteOwnCast(3599); s = BlizzardAPI.GetTotemWindow(1)")
    check("s == nil", "a plainly empty slot has no window")
    lua.execute("info = {have = secret, start = secret, dur = secret, spell = secret}; now = now + 31")
    check("BlizzardAPI.GetTotemWindow(1) == nil", "an estimate past its duration has ended")
    return count


def queue_holds():
    """SpellQueue records the right hold for a sunk entry: buff, totem slot, or target debuff."""
    lua = load()
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("--- A refreshed \"debuff\" condition naming a totem")
    end = source.index("\nfunction Upkeep.CostsDrainingPower")
    lua.execute("""
        AuraClock = AC
        SpellQueue, Upkeep = {}, {}
        BlizzardAPI = LibStub("JustAC-BlizzardAPI")
        SpellDB = {GetForeverTotemSlot = function(id) if id == 3599 then return 1 end end}
        DotTracker = LibStub("JustAC-DotTracker")
        BlizzardAPI.HasGamePick = function() return false end
        BlizzardAPI.GetDisplaySpellID = function(id) return id end
        occupied = {}
        BlizzardAPI.IsTotemSlotOccupied = function(slot) return occupied[slot] end
        buffGate = nil
        Upkeep.ActiveBuffGate = function() return buffGate end
        auraUp = {}
        DotTracker.GetTargetAuraState = function(id) return auraUp[id] end
        ownDot = {}
        readCache = {DotActive = function(id) return ownDot[id] end}
    """ + source[start:end])
    count = 0

    def check(gates, expected, why):
        nonlocal count
        got = lua.eval(f"""(function()
            AC.BeginQueueHolds(); SpellQueue._NoteAuraClock(42, {gates}, readCache); AC.EndQueueHolds()
            local kind, key, dur = AC.Resolve(42, true)
            return tostring(kind) .. ":" .. tostring(key) .. ":" .. tostring(dur)
        end)()""")
        assert got == expected, (why, got)
        count += 1

    lua.execute('buffGate = {t="buff", id=6673, dur=180, neg=true}')
    check("{}", "buff:6673:180", "a self-buff carries its duration")
    lua.execute("buffGate = nil; occupied[1] = true")
    check('{{t="totem", slot=1, neg=true}}', "totem:1:nil", "a totem slot it waits on")
    check('{{t="debuff", id=3599, neg=true, refresh=true}}', "totem:1:nil", "a refreshed totem 'debuff' is its slot")
    lua.execute("occupied[1] = false")
    check('{{t="totem", slot=1, neg=true}}', "nil:nil:nil", "an empty slot holds nothing")
    lua.execute("ownDot[42] = true")
    check("{}", "debuff:42:nil", "its own DoT")
    lua.execute("ownDot[42] = nil; auraUp[703] = true")
    check('{{t="debuff", id=703, neg=true}}', "debuff:703:nil", "another debuff that holds it (Garrote)")
    lua.execute("auraUp[703] = secret")
    check('{{t="debuff", id=703, neg=true}}', "nil:nil:nil", "a secret answer holds nothing")
    lua.execute("auraUp[703] = true")
    check('{{t="debuff", id=703, op=">", n=3}}', "nil:nil:nil", "a remaining-time condition is not a hold")
    # The aura the cast itself put on you (Bloodrage: a triggered 10s rage aura), from the data.
    lua.execute("""
        auraUp[703] = nil
        selfAura, left = {[42] = 10}, nil
        SpellDB.GetSelfAuraSeconds = function(id) return selfAura[id] end
        BlizzardAPI.GetBuffWindowRemaining = function(id, dur) assert(id == 42 and dur == 10); return left end
    """)
    check("{}", "nil:nil:nil", "no window for its cast: no clock")
    lua.execute("left = 6.5")
    check("{}", "buff:42:10", "its own aura running (cast window): the clock, with the aura's duration")
    lua.execute("left = 0")
    check("{}", "nil:nil:nil", "its aura over: no clock")
    lua.execute("left = 6.5; selfAura = {}")
    check("{}", "nil:nil:nil", "no self aura in the data: no clock")
    return count


if __name__ == "__main__":
    main()
