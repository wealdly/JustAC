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
printed = {}
libs["AceAddon-3.0"] = { GetAddon = function(_, name)
    if name ~= "JustAssistedCombat" then return nil end   -- the name JustAC.lua registers
    return { db = db, Print = function(_, msg) printed[#printed + 1] = msg end }
end }
popups = {}
function StaticPopup_Show(name, text, _, data) popups[#popups + 1] = { name = name, text = text, data = data } end
function StaticPopup_Visible() return false end
C_Timer = { After = function(_, f) f() end, NewTimer = function() return { Cancel = function() end } end }
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

    bad.extend(track_hidden())
    bad.extend(prompts())
    bad.extend(one_prompt())

    for why in bad:
        print("  FAIL", why)
    print("forever cdm: %d failure(s)" % len(bad))
    return 1 if bad else 0


# Track every hidden buff (both clients): what counts as "Not displayed" the way Blizzard's
# settings build it, the JAC layout copied from the active one and made active, the player's own
# layout untouched, and the undo (switch back; delete only an unchanged JAC layout).
HIDDEN_PRELUDE = r"""
bit = { band = function(a, b) return a & b end }
Enum.CooldownSetSpellFlags = { HideByDefault = 2 }
HIDE = 2
-- id -> { category set, flags, isKnown, isInvisible }
entries = {
    [301] = { C.TrackedBuff, HIDE, true, false },   -- hidden by default: moved
    [302] = { C.TrackedBuff, 0, true, false },      -- shown by default: left
    [303] = { C.TrackedBuff, HIDE, false, false },  -- unlearned: moved, shows once learned
    [304] = { C.TrackedBuff, HIDE, true, true },    -- invisible: never listed
    [305] = { C.TrackedBar, HIDE, true, false },    -- hidden by default: moved
    [306] = { C.TrackedBar, 0, true, false },       -- the player set it to "Not displayed": moved
    [307] = { C.TrackedBar, HIDE, true, false },    -- the player moved it into Tracked Buffs: left
}
C_CooldownViewer.GetCooldownViewerCategorySet = function(cat)
    local out = {}
    for cid, e in pairs(entries) do if e[1] == cat then out[#out + 1] = cid end end
    table.sort(out)
    return out
end
C_CooldownViewer.GetCooldownViewerCooldownInfo = function(cid)
    local e = entries[cid]
    return e and { cooldownID = cid, spellID = cid, category = e[1], flags = e[2], isKnown = e[3],
                   isInvisible = e[4], linkedSpellIDs = {} }
end
C_SpecializationInfo = { GetSpecialization = function() return 1 end,
                         GetSpecializationInfo = function() return 71, "Arms" end }
nameOK = true
C_EditMode = { IsValidLayoutName = function() return nameOK end }
function UnitClass() return "Warrior", "WARRIOR" end
function saveMine()
    db.char = {}
    saved = "1|" .. C_EncodingUtil.SerializeCBOR({ 5, { WARRIOR1 = 7 },
        { WARRIOR1 = { [7] = { {}, { [C.HiddenPassive] = { 306 }, [C.TrackedBuff] = { 307 } } } } },
        { [7] = "Mine" } })
    writes = nil
end
saveMine()
"""


def track_hidden():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(HIDDEN_PRELUDE)
    lua.execute((ROOT / "CdmAdvisor.lua").read_text(encoding="utf-8"))
    CA = lua.eval('LibStub("JustAC-CdmAdvisor")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append("track hidden: " + why)

    def lua_list(t):
        return [t[i] for i in range(1, len(t) + 1)] if t is not None else None

    def active():
        data = CA.Decode(g.saved)
        layout, lid, name = CA.ActiveLayout(data)[:3]
        return data, layout, lid, name

    def overrides(layout):
        return {cat: sorted(v.values()) for cat, v in layout[2].items()} if layout and layout[2] else {}

    # The rotation advisor reads the same default: hidden by default is "Not displayed", not tracked.
    check(CA.CooldownIDsFor(301)[301] == g.C.HiddenPassive and CA.CooldownIDsFor(302)[302] == g.C.TrackedBuff,
          "CooldownIDsFor maps HideByDefault to its Not displayed group")

    # The command speaks: a refusal is printed, a plan opens the confirm popup.
    g.combat = True
    CA.ConfirmTrackHidden()
    check(len(g.printed) == 1 and g.printed[1] == "CDM not in combat", "in combat the refusal is printed")
    g.combat = False
    CA.ConfirmTrackHidden()
    check(len(g.popups) == 1 and g.popups[1].name == "JUSTAC_CDM_TRACK_HIDDEN" and g.writes is None,
          "out of combat it asks first, without writing")
    confirm = g.StaticPopupDialogs["JUSTAC_CDM_TRACK_HIDDEN"]
    check(confirm.selectCallbackByIndex and confirm.button1 == "CDM add all"
          and confirm.button2 == "CDM add learned" and sorted(g.popups[1].data.keys()) == [301, 305, 306],
          "the confirm offers Add All or only the learned ones (301, 305, 306; not 303)")

    # Only Learned: the unlearned one stays hidden; undo afterwards for the full run below.
    confirm.OnButton2(None, g.popups[1].data)
    check(lua_list(CA.HiddenAuraIDs(active()[1])) == [303], "Only Learned leaves the unlearned one hidden")
    CA.UndoTrackHidden()
    lua.execute("printed = {}; popups = {}; writes = nil")

    check(lua_list(CA.HiddenAuraIDs(active()[1])) == [301, 303, 305, 306],
          "hidden by default or set by the player, learned or not, never invisible: %s"
          % lua_list(CA.HiddenAuraIDs(active()[1])))

    plan = CA.PlanTrackHidden()
    check(plan is not None and plan.name == "JAC - Arms" and plan.id == 8 and plan.prev == 7,
          "plan: a new layout named after the spec, back to Mine on undo")
    check(g.writes is None, "planning never writes")

    g.combat = True
    check(CA.TrackHidden()[0] == 0 and g.writes is None, "never writes in combat")
    g.combat, g.settingsOpen = False, True
    check(CA.TrackHidden()[0] == 0 and g.writes is None, "never writes while the settings window is open")
    g.settingsOpen = False

    n, name, target = CA.TrackHidden()
    check(n == 4 and name == "JAC - Arms", "moves all four: %s %s" % (n, name))
    data, layout, lid, lname = active()
    check(lid == 8 and lname == "JAC - Arms", "the JAC layout is now active: %s %s" % (lid, lname))
    ov = overrides(layout)
    check(target == g.C.TrackedBuff, "the batch goes to Tracked Buffs: %s" % target)
    check(ov.get(target) and set([301, 303, 305, 306]) <= set(ov[target]) and not ov.get(g.C.HiddenPassive),
          "the hidden buffs sit in Tracked Buffs: %s" % ov)
    check(307 in (ov.get(g.C.TrackedBuff) or []), "the copy keeps the player's own moves: %s" % ov)
    mine = data[3]["WARRIOR1"][7]
    check(overrides(mine) == {g.C.HiddenPassive: [306], g.C.TrackedBuff: [307]},
          "the player's layout is unchanged: %s" % overrides(mine))
    check(CA.PlanTrackHidden()[0] is None and CA.HasTrackHidden(), "nothing left to move; undo available")

    ok, now, kept = CA.UndoTrackHidden()
    data, layout, lid, lname = active()
    check(ok and now == "Mine" and not kept and lid == 7, "undo switches back to Mine: %s %s %s" % (ok, now, lid))
    check(data[3]["WARRIOR1"][8] is None and data[4][8] is None, "the unchanged JAC layout is deleted")
    check(not CA.HasTrackHidden() and not CA.UndoTrackHidden()[0], "nothing left to undo")

    # From the default layout: undo returns to Default and leaves nothing behind.
    lua.execute("db.char = {}; saved = nil")
    check(CA.TrackHidden()[0] == 4, "default layout: the four hidden by default move (303 and 307 too)")
    ok, now, _ = CA.UndoTrackHidden()
    data = CA.Decode(g.saved)
    check(ok and now == "CDM default layout" and CA.ActiveLayout(data)[0] is None and data[3]["WARRIOR1"] is None,
          "back on Default, no layout left")

    # The player changed the JAC layout: undo switches back but keeps it.
    lua.execute("saveMine()")
    CA.TrackHidden()
    lua.execute("""
        local CA = LibStub("JustAC-CdmAdvisor")
        local d = CA.Decode(saved)
        CA.ActiveLayout(d)[1] = { 302, 301 }
        saved = CA.Encode(d)
    """)
    ok, now, kept = CA.UndoTrackHidden()
    data, _, lid, _ = active()
    check(ok and kept and lid == 7 and data[4][8] == "JAC - Arms", "a changed JAC layout is kept, Mine active")

    # The player switched away themselves: undo leaves their choice and deletes the JAC layout.
    lua.execute("saveMine()")
    CA.TrackHidden()
    lua.execute("""
        local CA = LibStub("JustAC-CdmAdvisor")
        local d = CA.Decode(saved)
        d[2].WARRIOR1 = 7
        saved = CA.Encode(d)
    """)
    ok, now, kept = CA.UndoTrackHidden()
    data, _, lid, _ = active()
    check(ok and not kept and lid == 7 and data[4][8] is None, "switched away: JAC deleted, Mine stays active")

    # Run again after a new hidden buff appears: the same JAC layout, undo still goes to Mine.
    lua.execute("saveMine()")
    CA.TrackHidden()
    lua.execute("entries[308] = { C.TrackedBuff, HIDE, true, false }")
    n = CA.TrackHidden()[0]
    _, _, lid, _ = active()
    check(n == 1 and lid == 8, "a rerun moves only the new one, in the same layout: %s %s" % (n, lid))
    check(CA.UndoTrackHidden()[1] == "Mine", "undo after a rerun still returns to Mine")
    lua.execute("entries[308] = nil")

    # Five layouts in use: refused, nothing written. A name the game rejects: plain "JAC".
    lua.execute("""
        db.char = {}
        saved = "1|" .. C_EncodingUtil.SerializeCBOR({ 5, {}, {}, { [1] = "a", [2] = "b", [3] = "c", [4] = "d", [5] = "e" } })
        writes = nil
    """)
    check(CA.TrackHidden()[0] == 0 and g.writes is None, "five layouts already: nothing written")
    lua.execute("saveMine()")
    g.nameOK = False
    check(CA.PlanTrackHidden().name == "JAC", "a rejected name falls back to JAC")
    g.nameOK = True

    # Not Forever-only, but never over data JustAC cannot read or with the Cooldown Manager off.
    g.forever = False
    check(CA.TrackHidden()[0] == 4, "works on Retail too")
    lua.execute('db.char = {}; saved = "9|unknown"; writes = nil')
    check(CA.TrackHidden()[0] == 0 and g.writes is None, "unreadable saved layouts are left alone")
    lua.execute("saveMine()")
    g.cvar = False
    check(CA.TrackHidden()[0] == 0 and g.writes is None, "Cooldown Manager off: nothing written")
    return bad



# The prompts (both clients): one per spec the first time (turn the Cooldown Manager on, or add
# what it hides), then only for a newly learned hidden buff; each can add all.
def prompts():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(HIDDEN_PRELUDE)
    lua.execute("""
        mt = { enabled = 0 }
        LibStub:NewLibrary("JustAC-MaintenanceTracker")
        local MT = LibStub("JustAC-MaintenanceTracker")
        MT.SetCooldownManagerEnabled = function(on) mt.enabled = mt.enabled + 1; cvar = on; return true end
        MT.ApplyViewerVisibility = function(p) mt.applied = p end
    """)
    lua.execute((ROOT / "CdmAdvisor.lua").read_text(encoding="utf-8"))
    CA = lua.eval('LibStub("JustAC-CdmAdvisor")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append("prompts: " + why)

    def last():
        n = len(g.popups)
        return g.popups[n] if n else None

    def overrides():
        data = CA.Decode(g.saved)
        layout = CA.ActiveLayout(data)[0]
        return {cat: sorted(v.values()) for cat, v in layout[2].items()} if layout and layout[2] else {}

    check(CA.GetMode() == "detect", "asks by default")
    CA.MaybePrompt()
    p = last()
    check(p is not None and p.name == "JUSTAC_CDM_INTRO" and p.text == 3,
          "first check: one intro prompt for the three learned hidden buffs: %s" % (p and (p.name, p.text),))
    CA.MaybePrompt()
    check(len(g.popups) == 1, "the intro is shown once")

    # Learning the unlearned one: a short prompt naming it; Add moves only that one.
    lua.execute("entries[303][3] = true")
    CA.MaybePrompt()
    p = last()
    check(p.name == "JUSTAC_CDM_NEW" and p.text == "spell303" and list(p.data.keys()) == [303],
          "a newly learned hidden buff prompts by name: %s %s" % (p.name, p.text))
    g.StaticPopupDialogs["JUSTAC_CDM_NEW"].OnButton1(None, p.data)
    ov = overrides()
    check(ov.get(g.C.TrackedBuff) == [303, 307] and 301 not in ov.get(g.C.TrackedBuff, []),
          "Add moves only the new one: %s" % ov)
    CA.MaybePrompt()
    check(last().name != "JUSTAC_CDM_NEW" or last() is p, "not asked again for the same buff")

    # Another one: Add All moves every hidden buff.
    lua.execute("entries[309] = { C.TrackedBar, HIDE, true, false }")
    CA.MaybePrompt()
    p = last()
    check(p.name == "JUSTAC_CDM_NEW" and p.text == "spell309", "the next new one prompts: %s" % p.text)
    g.StaticPopupDialogs["JUSTAC_CDM_NEW"].OnButton2(None, p.data)
    check(CA.PlanTrackHidden()[0] is None, "Add All leaves nothing hidden")

    # A buff the player hides themselves later was already learned: never a prompt.
    n = len(g.popups)
    lua.execute("""
        local CA = LibStub("JustAC-CdmAdvisor")
        local d = CA.Decode(saved)
        local l = CA.ActiveLayout(d)
        for _, ids in pairs(l[2]) do for i = #ids, 1, -1 do if ids[i] == 302 then table.remove(ids, i) end end end
        l[2][C.HiddenPassive] = { 302 }
        saved = CA.Encode(d)
    """)
    CA.MaybePrompt()
    check(len(g.popups) == n, "hiding a learned buff yourself does not prompt")

    # Don't ask again; and the old Forever "Don't ask again" carries over.
    g.StaticPopupDialogs["JUSTAC_CDM_NEW"].OnButton4()
    lua.execute("entries[310] = { C.TrackedBuff, HIDE, true, false }")
    CA.MaybePrompt()
    check(CA.GetMode() == "manual" and len(g.popups) == n, "Don't ask again stops the prompts")
    lua.execute("entries[310] = nil; entries[309] = nil; db.char = { cdm = { neverAsk = true } }")
    check(CA.GetMode() == "manual", "the old Don't ask again means manual")

    # Cooldown Manager off: one offer to turn it on; "Turn On, Hidden" enables it, hides every
    # panel and adds all; the spec is not asked again.
    lua.execute("db.char = {}; db.profile = {}; saveMine(); cvar = false; popups = {}")
    CA.MaybePrompt()
    p = last()
    check(p is not None and p.name == "JUSTAC_CDM_OFF", "Cooldown Manager off: offer to turn it on")
    g.StaticPopupDialogs["JUSTAC_CDM_OFF"].OnButton1()
    prof = g.db.profile
    check(g.mt.enabled == 1 and g.cvar and prof.cooldownManagerEnable and prof.hideCdmTrackedBuff
          and prof.hideCdmTrackedBar and prof.hideCdmEssential and prof.hideCdmUtility,
          "turned on, every panel kept invisible")
    check(CA.PlanTrackHidden()[0] is None, "and every hidden buff added")
    CA.MaybePrompt()
    check(len(g.popups) == 2 and last().name == "JUSTAC_CDM_RELOAD", "no second first-time prompt")

    # In combat: nothing now, a check once combat ends.
    lua.execute("db.char = {}; popups = {}; saveMine()")
    g.combat = True
    CA.MaybePrompt()
    check(len(g.popups) == 0, "never prompts in combat")
    g.combat = False
    return bad


# Several new buffs make one prompt: learned together, learned while it is open, or learned while
# a reload is still on offer (that offer is folded in and comes back after the answer).
def one_prompt():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(HIDDEN_PRELUDE)
    lua.execute("""
        visible = {}
        function StaticPopup_Show(name, text, _, data)
            popups[#popups + 1] = { name = name, text = text, data = data }
            visible[name] = true
        end
        function StaticPopup_Hide(name) visible[name] = nil end
        function StaticPopup_Visible(name) return visible[name] end
    """)
    lua.execute((ROOT / "CdmAdvisor.lua").read_text(encoding="utf-8"))
    CA = lua.eval('LibStub("JustAC-CdmAdvisor")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append("one prompt: " + why)

    def last():
        return g.popups[len(g.popups)]

    def keys(d):
        return sorted(d.keys())

    NEW = g.StaticPopupDialogs["JUSTAC_CDM_NEW"]
    CA.MaybePrompt()
    check(last().name == "JUSTAC_CDM_INTRO", "first the intro")
    lua.execute('visible.JUSTAC_CDM_INTRO = nil')

    lua.execute("entries[303][3] = true; entries[309] = { C.TrackedBar, HIDE, true, false }")
    CA.MaybePrompt()
    check(last().name == "JUSTAC_CDM_NEW" and keys(last().data) == [303, 309]
          and last().text == "spell303, spell309", "two learned together: one prompt naming both")

    lua.execute("entries[310] = { C.TrackedBuff, HIDE, true, false }")
    n = len(g.popups)
    CA.MaybePrompt()
    check(len(g.popups) == n + 1 and keys(last().data) == [303, 309, 310] and g.visible.JUSTAC_CDM_NEW,
          "one learned while it is open joins it: %s" % (last().text,))

    data = last().data
    lua.execute('visible.JUSTAC_CDM_NEW = nil')
    NEW.OnButton1(None, data)
    check(last().name == "JUSTAC_CDM_RELOAD", "Add offers the reload")
    check(lua.eval("#popups") == n + 2, "and nothing else")

    lua.execute("entries[311] = { C.TrackedBuff, HIDE, true, false }")
    CA.MaybePrompt()
    check(last().name == "JUSTAC_CDM_NEW" and keys(last().data) == [311] and not g.visible.JUSTAC_CDM_RELOAD,
          "one learned while the reload is on offer: the prompt takes the offer's place")
    lua.execute('visible.JUSTAC_CDM_NEW = nil')
    NEW.OnButton3()
    check(last().name == "JUSTAC_CDM_RELOAD" and last().text == "CDM reload pending",
          "Not now brings the reload back: %s" % (last().text,))
    return bad


if __name__ == "__main__":
    sys.exit(main())
