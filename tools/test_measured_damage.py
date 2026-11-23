# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Measured damage for the Forever weapon comparison (BlizzardAPI/CooldownTracking.lua), run
# outside the game against the real file with its events fired through it. The meter contract
# (per-spell totals plain only out of combat, a wand reported as spell 75) is the client's
# documented and captured behaviour; what is tested is the measurement built on it.
#
# Run: python tools/test_measured_damage.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.IsSecretValue = function(v) return v == "secret" end
B.Unsecret = function(v) return v end
B.ResolveBaseSpellID = function() return nil end
forever = true
B.IsForever = function() return forever end
-- Smite: rank 1 585, rank 2 591 (both priced from their own estimate rows).
local RI = LibStub:NewLibrary("JustAC-RotationImport")
RI.RankBase = function(id) if id == 591 then return 585 end return id end
RI.RankChain = function() return nil end
estimates = {
    [585] = {20, 0, 1, 0, 0, 2},           -- 20 per hit, no scaling
    [591] = {40, 0, 1, 0, 0, 2},
    [589] = {0, 0, 1, 0, 0, 6, 1, 30, 0, 0, 18, 1},   -- Shadow Word: Pain: instant, damage over time only
    [10797] = {0, 0, 1, 0, 0, 7, 1, 60, 0, 0, 6, 1},  -- Starshards: a channel
    [14914] = {50, 0, 1, 0, 0, 2, 1, 20, 0, 0, 8}, -- Holy Fire: a hit and damage over time
}
RI.GetDirectDamageEstimate = function(id) return estimates[id] end
B.GetEngagedEnemyCount = function() return enemies end
grouped = false
B.IsGrouped = function() return grouped end
-- The addon's per-character saved data (AceDB db.char).
charData = {}
B.GetAddon = function() return { db = { char = charData } } end
petOut = false
function UnitExists(unit) if unit == "pet" then return petOut end return true end
local SDB = LibStub:NewLibrary("JustAC-SpellDB")
SDB.IsForever = function() return forever end
SDB.HASTE_BUFFS = {}
SDB.NEXT_SWING_SPELLS = {}
SDB.StaticLookup = function(t, id) return t[id] end
SDB.IsChanneled = function(id) return id == 10797 end
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
function UnitAttackSpeed() return 2.0, offSpeed, 1.5 end
-- Wand on the sheet: 8-12 per shot (10 average) every 1.5s.
wandLow, wandHigh = 8, 12
function UnitRangedDamage() return 1.5, wandLow, wandHigh end
-- Melee on the sheet: main hand 10-20 (15 average), off hand 4-6 (5 average).
function UnitDamage() return 10, 20, offLow, offHigh end
offLow, offHigh = 0, 0
function UnitLevel(unit) if unit == "target" then return targetLevel end return 10 end
targetLevel = 11
function GetSpellBonusDamage() return 0 end
targetGUID, enemies = "Creature-1", 1
function UnitGUID(unit) if unit == "target" then return targetGUID end return "Player-1" end
errors = 0
function geterrorhandler() return function() errors = errors + 1 end end
Enum = { DamageMeterType = { DamageDone = 0, Healing = 1 }, ItemClass = { Weapon = 2 },
         ItemWeaponSubclass = { Axe1H = 0, Sword1H = 7, Staff = 10, Dagger = 15, Wand = 19 } }
-- Meter: session id -> list of { spellID, totalAmount }; nil while in combat (secret there).
meter = {}
C_DamageMeter = {
    GetCombatSessionSourceFromID = function(id, kind, guid)
        if inCombat then return "secret" end
        assert(kind == 0 and guid == "Player-1")
        return { combatSpells = meter[id] or {}, totalAmount = 0 }
    end,
}
wandSkill = { rank = 30, modifier = 0, maxRank = 50 }
skills = { [228] = wandSkill, [136] = { rank = 40, modifier = 0, maxRank = 50 },
           [43] = { rank = 12, modifier = 0, maxRank = 50 }, [3014] = { rank = 50, modifier = 0, maxRank = 50 } }
C_SkillInfo = { GetSkillLineInfoByID = function(id) return skills[id] end }
-- Slot 16 main hand (a staff), 18 ranged (a wand).
items = { [16] = 100, [18] = 11287 }
subclasses = { [100] = 10, [101] = 7, [11287] = 19 }
function GetInventoryItemID(_, slot) return items[slot] end
C_Item = { GetItemInfoInstant = function(id) return id, "Weapon", "", "", 0, 2, subclasses[id] end }
SDB.NEXT_SWING_SPELLS = { [78] = true, [284] = true }
form, class = 0, "PRIEST"
LibStub:NewLibrary("JustAC-FormCache").GetActiveForm = function() return form end
function UnitClass() return class, class end
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

    def used(spell):
        """The ratio the queue uses: damped toward paper."""
        r = B.GetMeasuredDamageRatio(spell)
        return r[0] if isinstance(r, tuple) else r

    def ratio(spell):
        """The raw measured ratio behind it: the damping (as if 3 casts, or 8 shots or swings,
        had landed at paper) taken back out using the weighted count returned with it."""
        r = B.GetMeasuredDamageRatio(spell)
        if not isinstance(r, tuple):
            return r
        damped, count = r
        prior = 8 if spell in (5019, 75, 6603) else 3
        return (damped * (count + prior) - prior) / count

    def fight(session, casts=(), shots=0, spells=None, update_after=True, swings=0, off=0, after=()):
        """One fight: casts, shots and melee swings, the meter notifying `session` in combat, then
        the end. `after` are casts during the fight (a next-swing attack lands with its swing)."""
        g.inCombat = False
        g.now = g.now + 2
        B.RefreshDamageBaseline()
        for spell in casts:
            lua.execute('LibStub("JustAC-BlizzardAPI").NoteOwnCast(%d)' % spell)
        g.inCombat = True
        for _ in range(shots):
            lua.execute('Fire("PLAYER_SWING", 1.5, 2)')
        for _ in range(swings):
            lua.execute('Fire("PLAYER_SWING", 2.0, 0)')
        for _ in range(off):
            lua.execute('Fire("PLAYER_SWING", 2.0, 1)')
        for spell in after:
            lua.execute('LibStub("JustAC-BlizzardAPI").NoteOwnCast(%d)' % spell)
        lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, %d)' % session)
        # The game follows each update with session 0, the current-fight placeholder (captured).
        lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0)')
        if spells is not None:
            lua.execute("meter[%d] = { %s }" % (session, ", ".join(
                "{spellID=%d, totalAmount=%d}" % (s, d) for s, d in spells)))
        g.inCombat = False
        lua.execute('C_Timer = nil; Fire("PLAYER_REGEN_ENABLED")')
        if update_after:
            lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, %d)' % session)

    # Unmeasured: paper stands.
    check(ratio(5019) is None and ratio(585) is None, "nothing measured: no ratio")

    # Ten wand shots (10 paper each) that the meter reports as 75 with 120 damage: 1.2.
    fight(1, shots=10, spells=[(75, 120)])
    check(abs((ratio(5019) or 0) - 1.2) < 1e-9, ("wand ratio from spell 75", ratio(5019)))
    check(ratio(75) == ratio(5019), "Shoot and Auto Shot are one ranged attack")
    # Too few casts: no Smite ratio yet; then enough of them, across ranks, priced by rank.
    fight(2, casts=[585, 585], spells=[(585, 60)])
    check(ratio(585) is None, "two casts are not enough")
    fight(3, casts=[591, 591], spells=[(591, 60)])
    # Decay 0.7: damage 60*0.7+60=102, paper 40*0.7+80=108, count 2*0.7+2=3.4.
    check(abs((ratio(585) or 0) - 102 / 108) < 1e-9, ("Smite ratio across ranks", ratio(585)))
    check(ratio(591) == ratio(585), "a rank reads its rank-1 measurement")
    # Every damage read answers with the measured figure; the measurement itself stays on paper.
    smite = ratio(585)
    check(abs(B.GetDirectSpellHit(585) - 20 * used(585)) < 1e-9, "the expected hit is scaled")
    check(abs(B.GetDirectSpellDPS(585, 2) - 10 * used(585)) < 1e-9, "the expected DPS is scaled")
    check(abs(B.GetAutoAttackDPS(5019) - (10 / 1.5) * used(5019)) < 1e-9, "the live weapon DPS is scaled")
    # Damped toward paper: 3.4 weighted casts measured at 102/108, plus 3 at paper.
    check(abs(used(585) - (smite * 3.4 + 3) / (3.4 + 3)) < 1e-9, ("small samples move gradually", used(585)))
    # The meter stub writes whole numbers: the expectation uses the same rounded damage.
    landed = int(60 * smite)
    fight(5, casts=[585, 585, 585], spells=[(585, landed)])
    steady = (102 * 0.7 + landed) / (108 * 0.7 + 60)   # paper stays 20 a cast, never 20 * ratio
    check(abs((ratio(585) or 0) - steady) < 1e-9, ("pricing at paper keeps the ratio steady", ratio(585), steady))

    # Damage over time with no enemy count read in combat: one enemy is not confirmed.
    fight(4, casts=[589, 14914, 14914, 14914], spells=[(589, 90), (14914, 300)])
    check(ratio(589) is None and ratio(14914) is None, "damage over time needs a confirmed single enemy")

    # A fight with no meter session cannot be matched: nothing credited.
    before = ratio(5019)
    g.inCombat = False
    B.RefreshDamageBaseline()
    g.inCombat = True
    for _ in range(10):
        lua.execute('Fire("PLAYER_SWING", 1.5, 2)')
    g.inCombat = False
    lua.execute('Fire("PLAYER_REGEN_ENABLED")')
    check(ratio(5019) == before, "an unnotified fight changes nothing")

    # One session over two pulls: the second read credits only what was gained since.
    B._ResetMeasuredDamage()
    fight(10, shots=10, spells=[(75, 100)])
    fight(10, shots=10, spells=[(75, 300)])
    # First: 100/100. Second gains 200 over 100 paper: 100*0.7+200=270 over 100*0.7+100=170.
    check(abs((ratio(5019) or 0) - 270 / 170) < 1e-9, ("a shared session credits its gain", ratio(5019)))
    # Reading again gains nothing.
    lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 10)')
    check(abs((ratio(5019) or 0) - 270 / 170) < 1e-9, "a repeated read credits nothing")

    # A meter that has not listed the spell yet is waited for, not read as all misses.
    B._ResetMeasuredDamage()
    fight(20, shots=10, spells=[])
    check(ratio(5019) is None, "an absent row is not counted as zero")
    lua.execute("meter[20] = { {spellID=75, totalAmount=90} }")
    lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 20)')
    check(abs((ratio(5019) or 0) - 0.9) < 1e-9, ("the later read credits it", ratio(5019)))

    # A new wand moves the paper price, the ratio carries over.
    lua.execute("wandLow, wandHigh = 18, 22")
    fight(21, shots=10, spells=[(75, 180)])
    check(abs((ratio(5019) or 0) - (90 * 0.7 + 180) / (100 * 0.7 + 200)) < 1e-9,
          ("a new wand is priced at its own sheet damage", ratio(5019)))

    # Wand skill five points higher: the earlier misses no longer apply.
    lua.execute("skills[228] = { rank = 36, modifier = 0, maxRank = 50 }")
    fight(22, shots=10, spells=[(75, 200)])
    check(abs((ratio(5019) or 0) - 1.0) < 1e-9, ("a higher wand skill starts afresh", ratio(5019)))

    # Implausible ratios (identities that did not match) are not used.
    B._ResetMeasuredDamage()
    fight(30, shots=10, spells=[(75, 5000)])
    check(ratio(5019) is None, "a ratio of 50 is rejected")

    # Secret payloads are never read; nothing measured off Forever.
    B._ResetMeasuredDamage()
    fight(31, shots=10, spells=None)
    lua.execute('meter[31] = { {spellID="secret", totalAmount=100} }')
    lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 31)')
    check(ratio(5019) is None, "a secret entry stops the read")
    g.forever = False
    check(ratio(5019) is None, "retail: no measurement")
    g.forever = True

    # Solo fights only: a grouped fight, an unknown group state, or joining mid-fight is skipped.
    B._ResetMeasuredDamage()
    lua.execute("grouped = true")
    fight(60, shots=10, spells=[(75, 80)])
    check(ratio(5019) is None, "a grouped fight is not measured")
    lua.execute("grouped = nil")
    fight(61, shots=10, spells=[(75, 80)])
    check(ratio(5019) is None, "an unknown group state is not solo")
    lua.execute("grouped = false")
    g.inCombat = False
    B.RefreshDamageBaseline()
    g.inCombat = True
    for i in range(10):
        if i == 5:
            lua.execute("grouped = true")
        lua.execute('Fire("PLAYER_SWING", 1.5, 2)')
    lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 62)')
    lua.execute("meter[62] = { {spellID=75, totalAmount=80} }")
    g.inCombat = False
    lua.execute('C_Timer = nil; Fire("PLAYER_REGEN_ENABLED")')
    lua.execute("grouped = false")
    check(ratio(5019) is None, "joining a group mid-fight leaves the fight unmeasured")
    check("groupedSkipped=3" in B.GetMeasuredDamageReport(), ("skipped fights reported", B.GetMeasuredDamageReport()))
    fight(63, shots=10, spells=[(75, 240)])   # the 18-22 wand from above: 20 a shot
    check(abs((ratio(5019) or 0) - 1.2) < 1e-9, ("a solo fight is measured", ratio(5019)))

    # Melee: white swings in both hands, priced per hand, measured as the meter's 6603.
    B._ResetMeasuredDamage()
    lua.execute("offLow, offHigh, offSpeed = 4, 6, 2.0")
    fight(40, swings=8, off=4, spells=[(6603, 2 * (8 * 15 + 4 * 5))])
    check(abs((ratio(6603) or 0) - 2.0) < 1e-9, ("melee ratio over both hands", ratio(6603)))
    # A pet out: its swings may share the owner's melee row, so melee is not measured.
    B._ResetMeasuredDamage()
    lua.execute("petOut = true")
    fight(44, swings=10, shots=10, spells=[(6603, 300), (75, 120)])
    check(ratio(6603) is None, "melee is not measured with a pet out")
    check(ratio(5019) is not None, "the wand still is")
    lua.execute("petOut = false")
    # A Heroic Strike swing is its own damage: that swing leaves the white count.
    B._ResetMeasuredDamage()
    fight(41, swings=10, after=[284, 284], spells=[(6603, 8 * 15), (284, 200)])
    check(abs((ratio(6603) or 0) - 1.0) < 1e-9, ("next-swing attacks leave the white count", ratio(6603)))
    check(ratio(284) is None, "a next-swing attack is not priced as a spell")
    # Too few swings: none yet.
    B._ResetMeasuredDamage()
    fight(42, swings=5, spells=[(6603, 75)])
    check(ratio(6603) is None, "five swings are not enough")
    # Skill follows the weapon in the slot: a new sword with a low skill starts afresh.
    B._ResetMeasuredDamage()
    lua.execute("offLow, offHigh, offSpeed = 0, 0, nil")
    fight(43, swings=10, spells=[(6603, 150)])
    report = B.GetMeasuredDamageReport()
    check("meleeSkill=40/50" in report, ("staff skill", report))
    lua.execute("items[16] = 101")
    report = B.GetMeasuredDamageReport()
    check("meleeSkill=12/50" in report, ("sword skill", report))
    lua.execute("form, class = 1, 'DRUID'")
    check("meleeSkill=50/50" in B.GetMeasuredDamageReport(), "a druid in form uses the feral skill")
    lua.execute("form, class = 0, 'PRIEST'; items[16] = nil")
    check("meleeSkill=nil" in B.GetMeasuredDamageReport(), "no Unarmed skill row: unknown")
    lua.execute("items[16] = 100")

    # Damage over time: priced for the part of its duration it could tick, one-enemy fights only.
    def dot_fight(session, casts, end, spells, enemy_count=1):
        """casts: (seconds into the fight, spell, target GUID); the fight ends at `end`."""
        g.inCombat = False
        g.now = g.now + 100
        start = g.now
        B.RefreshDamageBaseline()
        g.inCombat = True
        g.enemies = enemy_count
        for at, spell, target in casts:
            g.now = start + at
            g.targetGUID = target
            B.NoteOwnCast(spell)
        lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, %d)' % session)
        lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0)')
        lua.execute("meter[%d] = { %s }" % (session, ", ".join(
            "{spellID=%d, totalAmount=%d}" % (s, d) for s, d in spells)))
        g.now = start + end
        g.inCombat = False
        lua.execute('C_Timer = nil; Fire("PLAYER_REGEN_ENABLED")')
        g.targetGUID = "Creature-1"
        g.enemies = 1

    B._ResetMeasuredDamage()
    # Shadow Word: Pain (30 over 18s) cast at 0, refreshed at 6 and 12, the fight ending at 18:
    # each run ticked 6 of 18 seconds, 10 a run, 30 in all; the meter saw 36.
    dot_fight(50, [(0, 589, "A"), (6, 589, "A"), (12, 589, "A")], 18, [(589, 36)])
    check(abs((ratio(589) or 0) - 1.2) < 1e-9, ("a refreshed damage over time is priced by its ticking time", ratio(589)))
    check(B.GetDirectSpellHit(589, None, True) is None,
          "a measure-only row stays private: the public whole-spell read never prices it")
    # Whole ticks (every 3s): casts at 0, 4 and 8 and the fight ending at 12 each ticked once,
    # 5 a run (time alone would price 4 of 18 seconds, 6.7); the meter saw 18.
    B._ResetMeasuredDamage()
    lua.execute("estimates[589][13] = 3")
    dot_fight(57, [(0, 589, "A"), (4, 589, "A"), (8, 589, "A")], 12, [(589, 18)])
    check(abs((ratio(589) or 0) - 1.2) < 1e-9, ("a cut-short run is priced by its whole ticks", ratio(589)))
    lua.execute("estimates[589][13] = nil")
    # Holy Fire (50 hit, 20 over 8s) at 0, 4 and 8, the fight ending at 10: 60 + 60 + 55 = 175.
    dot_fight(51, [(0, 14914, "A"), (4, 14914, "A"), (8, 14914, "A")], 10, [(14914, 175)])
    check(abs((ratio(14914) or 0) - 1.0) < 1e-9, ("a hit and its damage over time, cut by the fight's end", ratio(14914)))
    check(B.IsMeasureOnlyEstimate(589) is True and B.IsMeasureOnlyEstimate(14914) is False,
          "an instant damage over time is priced for measurement only")
    # A channel's run ends when the channel stops, which nothing here marks: not measured.
    dot_fight(56, [(0, 10797, "A"), (7, 10797, "A"), (14, 10797, "A")], 20, [(10797, 180)])
    check(ratio(10797) is None, "a channel is not measured as damage over time")
    # Two targets, or a second enemy engaged: the fight's end is not the target's death.
    B._ResetMeasuredDamage()
    dot_fight(52, [(0, 589, "A"), (6, 589, "B"), (12, 589, "A")], 18, [(589, 36)])
    check(ratio(589) is None, "damage over time on two targets is not measured")
    dot_fight(53, [(0, 589, "A"), (6, 589, "A"), (12, 589, "A")], 18, [(589, 36)], enemy_count=2)
    check(ratio(589) is None, "damage over time with a second enemy engaged is not measured")
    dot_fight(54, [(0, 589, "A"), (6, 589, "A"), (12, 589, "A")], 18, [(589, 36)], enemy_count=0)
    check(ratio(589) is None, "an unreadable enemy count is not one enemy")
    # A direct-hit spell in the same several-enemy fight is still measured.
    dot_fight(55, [(0, 585, "A"), (2, 585, "B"), (4, 585, "C")], 6, [(585, 66)], enemy_count=3)
    check(abs((ratio(585) or 0) - 1.1) < 1e-9, ("direct hits do not need one enemy", ratio(585)))

    # Normal levelling targets only: six above, six below, or a skull (level -1) is skipped.
    B._ResetMeasuredDamage()
    for level in (16, 4, -1):
        lua.execute("targetLevel = %d" % level)
        fight(70 + level, shots=10, spells=[(75, 300)])
    lua.execute("targetLevel = 11")
    check(ratio(5019) is None and "levelSkipped=3" in B.GetMeasuredDamageReport(),
          ("targets outside four below to two above are not measured", B.GetMeasuredDamageReport()))
    fight(80, shots=10, spells=[(75, 240)])
    check(ratio(5019) is not None, "a target one above is measured")

    # A weapon swapped mid-fight: the pre-fight price no longer holds, so the fight is not measured.
    B._ResetMeasuredDamage()
    g.inCombat = False
    g.now = g.now + 2
    B.RefreshDamageBaseline()
    g.inCombat = True
    for i in range(10):
        if i == 5:
            lua.execute('Fire("PLAYER_EQUIPMENT_CHANGED", 18, false)')
        lua.execute('Fire("PLAYER_SWING", 1.5, 2)')
    lua.execute('Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 81)')
    lua.execute("meter[81] = { {spellID=75, totalAmount=240} }")
    g.inCombat = False
    lua.execute('C_Timer = nil; Fire("PLAYER_REGEN_ENABLED")')
    check(ratio(5019) is None, "a weapon swapped in combat leaves the fight unmeasured")

    # Talents spent differently: the measurements no longer apply.
    B._ResetMeasuredDamage()
    lua.execute("spentTalents = {[1] = 5}; LibStub('JustAC-RotationImport').SpentByTree = function() return {}, spentTalents end")
    B._NoteTalents()
    fight(82, shots=10, spells=[(75, 240)])
    check(ratio(5019) is not None, "measured before the respec")
    B._NoteTalents()
    check(ratio(5019) is not None, "the same talents keep the measurements")
    lua.execute("spentTalents = {[1] = 5, [2] = 1}")
    B._NoteTalents()
    check(ratio(5019) is None, "a point spent clears the measurements")

    # Kept across /reload, per character, with the talents they were taken under.
    B._ResetMeasuredDamage()
    lua.execute("LibStub('JustAC-RotationImport').SpentByTree = function() return {}, {[1] = 4} end")
    lua.execute('Fire("PLAYER_ENTERING_WORLD")')
    fight(90, shots=10, spells=[(75, 240)])
    kept = ratio(5019)
    check(kept is not None and lua.eval("charData.measuredDamage[75] ~= nil"), "the measurement is in the saved data")
    def reload(signature):
        lua.execute("""
            local saved = {}
            for k, m in pairs(charData.measuredDamage) do saved[k] = { damage = m.damage, paper = m.paper, count = m.count } end
            local talents = charData.measuredTalents
            LibStub('JustAC-BlizzardAPI')._ResetMeasuredDamage()
            charData.measuredDamage, charData.measuredTalents = saved, talents
        """)
        lua.execute("LibStub('JustAC-RotationImport').SpentByTree = function() return {}, %s end" % signature)
        lua.execute('Fire("PLAYER_ENTERING_WORLD")')
    reload("{[1] = 4}")
    check(ratio(5019) is not None and abs(ratio(5019) - kept) < 1e-9, ("restored after /reload", ratio(5019), kept))
    reload("{[1] = 4, [2] = 1}")
    check(ratio(5019) is None and lua.eval("next(charData.measuredDamage) == nil"),
          "talents spent since: the saved measurements are dropped")

    report = B.GetMeasuredDamageReport()
    check("rangedSkill=36/50" in report and "sessions=" in report, ("capture report", report))
    check(g.errors == 0, ("no errors", g.errors))

    for why in bad:
        print("  FAIL", why)
    print("measured damage: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
