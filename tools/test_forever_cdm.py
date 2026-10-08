# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The Cooldown Manager advisor (CdmAdvisor.lua), run outside the game against the real file: a
# guest in the player's layout. Which entries are offered (only ones still at Blizzard's
# default), where they go (the panel the player uses least), that a write is recorded, that an
# addition the player removes is never offered again, that removal touches only ours, and the
# combat / open-settings guards. The Cooldown Manager and the encoding are stubbed: the layout
# round-trips as a deep copy, which is all the module relies on (the real codec is checked in
# game by /jac inspect cdmlayout).
#
# Run: python tools/test_forever_cdm.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
libs["AceLocale-3.0"] = { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end }
forever = true
libs["JustAC-SpellDB"] = { IsForever = function() return forever end, HASTE_BUFFS = {} }
-- Rotation: Battle Shout (buff), Rend (DoT), Mortal Strike (buff gate on itself).
libs["JustAC-RotationImport"] = {
    RankBase = function(id) return id end,
    HighestKnownRank = function(id) return id end,
    GetInsertable = function() return { 6673, 772, 12294 } end,
    GetEntry = function(id) return { gates = { { t = id == 772 and "dot" or "buff", id = id } } } end,
}
db = { char = {}, profile = {} }
libs["AceAddon-3.0"] = { GetAddon = function() return { db = db } end }
C = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
Enum = { CooldownViewerCategory = C, CompressionMethod = { Deflate = 1 } }
-- Cooldown entries: id -> { spellID, default category }. 201/202 = the player's own icons.
entries = { [101] = { 6673, C.HiddenPassive }, [102] = { 772, C.HiddenPassive },
            [103] = { 12294, C.TrackedBuff }, [201] = { 1, C.HiddenPassive }, [202] = { 2, C.HiddenPassive } }
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
store = {}
C_EncodingUtil = {
    SerializeCBOR = function(t) store[#store + 1] = copy(t); return tostring(#store) end,
    DeserializeCBOR = function(s) return copy(store[tonumber(s)]) end,
    CompressString = function(s) return s end, DecompressString = function(s) return s end,
    EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
}
saved = nil
C_CooldownViewer = {
    GetLayoutData = function() return saved end,
    SetLayoutData = function(s) saved = s; writes = (writes or 0) + 1 end,
    GetCooldownViewerCategorySet = function(cat)
        local out = {}
        for cid, e in pairs(entries) do if e[2] == cat then out[#out + 1] = cid end end
        table.sort(out)
        return out
    end,
    GetCooldownViewerCooldownInfo = function(cid)
        local e = entries[cid]
        return e and { spellID = e[1], category = e[2], linkedSpellIDs = {} }
    end,
}
CooldownViewerUtil = { GetCurrentClassAndSpecTag = function() return "WARRIOR1" end }
cvar = true
function GetCVarBool() return cvar end
function IsPlayerSpell() return true end
C_Spell = { GetSpellName = function(id) return "spell" .. id end }
combat = false
function InCombatLockdown() return combat end
settingsOpen = false
CooldownViewerSettings = { IsShown = function() return settingsOpen end }
StaticPopupDialogs = {}
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
-- The player's saved layout: Rend set to "Not in bar" by hand, two own icons in Tracked Buffs.
function savePlayerLayout()
    saved = C_EncodingUtil.SerializeCBOR({ 1, { WARRIOR1 = 7 },
        { WARRIOR1 = { [7] = { {}, { [C.HiddenPassive] = { 102 }, [C.TrackedBuff] = { 201, 202 } } } } },
        { [7] = "Mine" } })
    saved = "1|" .. saved
end
savePlayerLayout()
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "CdmAdvisor.lua").read_text(encoding="utf-8"))
    CA = lua.eval('LibStub("JustAC-CdmAdvisor")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    def n(ret):   # Add / RemoveAdded return a count, or (0, reason) when refused
        return ret[0] if isinstance(ret, tuple) else ret

    def status():
        state, can, hidden, added = CA.Status()
        names = lambda t: sorted(t[i].id for i in range(1, len(t) + 1))
        return state, names(can), names(hidden), added

    def layout_overrides():
        data = CA.Decode(g.saved)
        layout = CA.ActiveLayout(data)[0]
        return {cat: sorted(v for v in layout[2][cat].values()) for cat in layout[2].keys()}

    check(status() == ("ok", [6673], [772], 0),
          "offer Battle Shout only: Rend is hidden by the player, Mortal Strike already tracked: %s" % (status(),))

    check(CA.TargetCategory(CA.ActiveLayout(CA.Decode(g.saved))[0]) == g.C.TrackedBar,
          "additions go to Tracked Bars, the panel the player does not use")

    g.combat = True
    check(n(CA.Add()) == 0 and g.writes is None, "never writes in combat")
    g.combat, g.settingsOpen = False, True
    check(n(CA.Add()) == 0 and g.writes is None, "never writes while the settings window is open")
    g.settingsOpen = False

    check(n(CA.Add()) == 1, "adds Battle Shout")
    ov = layout_overrides()
    check(ov.get(g.C.TrackedBar) == [101] and ov.get(g.C.HiddenPassive) == [102] and ov.get(g.C.TrackedBuff) == [201, 202],
          "only Battle Shout moved, into Tracked Bars; the player's entries untouched: %s" % ov)
    check(status() == ("ok", [], [772], 1), "nothing left to offer, one recorded as ours: %s" % (status(),))

    # The player drags our Battle Shout back out of the bar: theirs now, never offered again.
    lua.execute("""
        local d = LibStub("JustAC-CdmAdvisor").Decode(saved)
        local l = LibStub("JustAC-CdmAdvisor").ActiveLayout(d)
        l[2][C.TrackedBar] = {}
        l[2][C.HiddenPassive] = { 102, 101 }
        saved = LibStub("JustAC-CdmAdvisor").Encode(d)
    """)
    check(status() == ("ok", [], [772, 6673], 0),
          "an addition the player removed is declined, not re-offered: %s" % (status(),))

    # Fresh layout, add, then Remove What JustAC Added puts back only ours.
    lua.execute("db.char = {}; savePlayerLayout()")
    CA.Add()
    check(n(CA.RemoveAdded()) == 1, "removes the one addition")
    ov = layout_overrides()
    check(not ov.get(g.C.TrackedBar) and ov.get(g.C.TrackedBuff) == [201, 202] and ov.get(g.C.HiddenPassive) == [102],
          "removal leaves the player's own choices: %s" % ov)

    # Nothing saved (the spec is on the default layout): adding creates a "JustAC" layout, active
    # for this spec; removing it again deletes the layout while the player has not changed it.
    lua.execute("db.char = {}; saved = nil; writes = nil")
    st = status()
    check(st[0] == "nolayout" and st[1] == [772, 6673], "default layout: everything not at its default offered: %s" % (st,))
    check(n(CA.Add()) == 2, "adds both into a new layout")
    data = CA.Decode(g.saved)
    layout, lid, lname = CA.ActiveLayout(data)[:3]
    check(lname == "JustAC" and lid == 1, "a layout named JustAC, id 1, active for the spec: %s %s" % (lname, lid))
    check(status()[0] == "ok", "the spec now has a saved layout")
    check(n(CA.RemoveAdded()) == 2, "removes both")
    data = CA.Decode(g.saved)
    check(CA.ActiveLayout(data)[0] is None and data[4][1] is None, "the untouched JustAC layout is deleted: back on Default")

    # The player customises the JustAC layout: removal then takes back only our entries.
    lua.execute("db.char = {}; saved = nil")
    CA.Add()
    lua.execute("""
        local d = LibStub("JustAC-CdmAdvisor").Decode(saved)
        local l = LibStub("JustAC-CdmAdvisor").ActiveLayout(d)
        l[2][C.TrackedBuff] = { 201 }
        saved = LibStub("JustAC-CdmAdvisor").Encode(d)
    """)
    CA.RemoveAdded()
    data = CA.Decode(g.saved)
    layout, _, lname = CA.ActiveLayout(data)[:3]
    check(lname == "JustAC" and layout is not None, "a JustAC layout the player changed is kept")

    # The name is taken by another spec's layout: numbered. Five layouts already: refused.
    lua.execute("""
        db.char = {}
        saved = "1|" .. C_EncodingUtil.SerializeCBOR({ 5, { MAGE1 = 4 }, { MAGE1 = { [4] = {} } }, { [4] = "JustAC" } })
    """)
    CA.Add()
    lname = CA.ActiveLayout(CA.Decode(g.saved))[2]
    check(lname == "JustAC 2", "a taken name is numbered: %s" % lname)
    lua.execute("""
        db.char = {}
        saved = "1|" .. C_EncodingUtil.SerializeCBOR({ 5, {}, {}, { [1] = "a", [2] = "b", [3] = "c", [4] = "d", [5] = "e" } })
        writes = nil
    """)
    check(n(CA.Add()) == 0 and g.writes is None, "five layouts already: nothing written")

    # Saved data JustAC cannot decode is never written over.
    lua.execute('db.char = {}; saved = "9|unknown"; writes = nil')
    check(status()[0] == "unreadable" and n(CA.Add()) == 0 and g.writes is None,
          "unreadable saved layouts are left alone")
    lua.execute("savePlayerLayout()")
    g.cvar = False
    check(status()[0] == "disabled", "Cooldown Manager off: nothing offered")
    g.cvar, g.forever = True, False
    check(status()[0] == "unavailable", "retail: unavailable")

    for why in bad:
        print("  FAIL", why)
    print("forever cdm: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
