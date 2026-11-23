# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Slot 2 forecasts the next press (SpellQueueForever.lua _StageNextPress): a spell waiting only
# on its cooldown that will be ready once the player can act again after slot 1 (any GCD now
# plus the longer of slot 1's cast and a GCD) and ranks above slot 2's choice takes slot 2.
# Loads the real functions from SpellQueueForever.lua with stubs.
#
# Run: python tools/test_next_press.py
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
SMITE, MIND_BLAST, WAND, PAIN = 591, 8092, 5019, 594


def main():
    source = (ROOT / "SpellQueueForever.lua").read_text(encoding="utf-8")
    beats = source[source.index("function SpellQueue._SpellBeatsWeapon("):source.index("function SpellQueue._AddWeaponFiller(")]
    stage = source[source.index("local function ForecastRank("):source.index("function SpellQueue._StageSwingPress(")]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now = 100
        function GetTime() return now end
        cooldownLeft, castSeconds, ranks = {}, {}, {}
        gcdStart, gcdDuration = nil, nil
        forever, gamePick = true, false
        BlizzardAPI = {
            IsForever = function() return forever end,
            HasGamePick = function() return gamePick end,
            CooldownEndsWithin = function(id, seconds)
                local left = cooldownLeft[id]
                if left == nil then return true end
                return left <= seconds
            end,
            GetGCDRemaining = function(at)
                if not (gcdStart and gcdDuration and gcdDuration > 0) then return 0 end
                return math.max(0, gcdStart + gcdDuration - (at or now))
            end,
            GetCastSeconds = function(id) return castSeconds[id] or 0 end,
        }
        -- Shadow Word: Pain rank 2 (594) is rank 1 (589) of a chain; its condition is its own debuff missing.
        gates = { [594] = { { t = "debuff", id = 589, neg = true } } }
        RotationImport = {
            GetEntry = function(id) if ranks[id] then return { rank = ranks[id], gates = gates[id] } end end,
            RankBase = function(id) if id == 594 then return 589 end return id end,
        }
        SpellQueue = { _cooldownRank = {}, _weaponFillers = { dps = {}, manaPlenty = true },
                       _OneGCD = function() return 1.5 end }
        sunkSet, lastCtx = {}, {}
        function PlaceQueueSpell(b, id, insertAt, position)
            for i = position, insertAt + 1, -1 do b.recommendedSpells[i] = b.recommendedSpells[i - 1] end
            b.recommendedSpells[insertAt] = id
        end
    """ + beats + stage + """
        function Forecast(queue, setup)
            local b = { recommendedSpells = {}, spellCount = #queue, now = now, contextOrder = "simc",
                        simcCtx = "st", weaponFillerID = 5019, weaponFillerDPS = 10 }
            for i, id in ipairs(queue) do b.recommendedSpells[i] = id end
            if setup then setup(b) end
            SpellQueue._StageNextPress(b)
            return b.recommendedSpells[1], b.recommendedSpells[2], b.recommendedSpells[3]
        end
    """)
    g = lua.globals()

    def reset(extra=""):
        lua.execute("""
            cooldownLeft, castSeconds = {}, {}
            ranks = { [594] = 1, [8092] = 2, [591] = 3 }
            SpellQueue._cooldownRank = {}
            SpellQueue._weaponFillers = { dps = { [8092] = 25, [591] = 12 }, manaPlenty = true }
            SpellQueue._rotationIsCustom = false
            gcdStart, gcdDuration, forever, gamePick = nil, nil, true, false
            sunkSet = {}
            castSeconds[591] = 2.5
        """ + extra)

    forecast = g.Forecast
    # Smite leads (2.5s cast), the wand shows second, Mind Blast waits on 2.0s of cooldown.
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 2.0")
    assert forecast(lua.table(SMITE, WAND, MIND_BLAST)) == (SMITE, MIND_BLAST, WAND), \
        "Mind Blast ready by the end of Smite's cast is the next press"
    assert g.lastCtx.nextPressID == MIND_BLAST
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 3.0")
    assert forecast(lua.table(SMITE, WAND, MIND_BLAST)) == (SMITE, WAND, MIND_BLAST), \
        "still cooling down after Smite: the wand stays second"
    # An instant lead with a GCD running: the next press comes after the GCD and one more.
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 2.2; gcdStart, gcdDuration = 99.5, 1.5")
    assert forecast(lua.table(PAIN, WAND, MIND_BLAST)) == (PAIN, MIND_BLAST, WAND), \
        "1.0s of GCD left plus one more GCD reaches Mind Blast"
    # Against the wand the comparison's own rule holds: conserving mana, a cast must beat it by 20%.
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 2.0;"
          "SpellQueue._weaponFillers.manaPlenty = false; SpellQueue._weaponFillers.dps[8092] = 11")
    assert forecast(lua.table(SMITE, WAND, MIND_BLAST)) == (SMITE, WAND, MIND_BLAST), \
        "a cast that would not beat the conserving wand does not take its place"
    # A better-ranked spell already second keeps its place.
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 1.0")
    assert forecast(lua.table(SMITE, PAIN, MIND_BLAST)) == (SMITE, PAIN, MIND_BLAST), \
        "Shadow Word: Pain outranks Mind Blast"
    # Only waits held by their cooldown alone are forecast (a resource or condition wait is not).
    reset("cooldownLeft[8092] = 1.0")
    assert forecast(lua.table(SMITE, WAND, MIND_BLAST)) == (SMITE, WAND, MIND_BLAST), \
        "a wait not held only by its cooldown stays"
    # Untouched: custom lists, exact order, a game pick, retail, a waiting lead.
    for setup, why in (("SpellQueue._rotationIsCustom = true", "custom list"),
                       ("gamePick = true", "game pick"),
                       ("forever = false", "retail"),
                       ("sunkSet[591] = true", "slot 1 itself waits")):
        reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 2.0;" + setup)
        assert forecast(lua.table(SMITE, WAND, MIND_BLAST)) == (SMITE, WAND, MIND_BLAST), why
    reset("SpellQueue._cooldownRank[8092] = 2; cooldownLeft[8092] = 2.0")
    off = lua.eval("function(b) b.contextOrder = 'off' end")
    assert forecast(lua.table(SMITE, WAND, MIND_BLAST), off) == (SMITE, WAND, MIND_BLAST), "exact order"
    # Closing on the target with another enemy engaged: slot 2 names the opener on a fresh target.
    W = lua.eval("SpellQueue_WAIT or -999999999")
    closing = lua.eval("function(b) b.inCombat = true; b.ctxExecute = true; b.ctxEnemies = 2 end")
    reset("sunkSet[594] = true")
    assert forecast(lua.table(W, SMITE, MIND_BLAST, PAIN), closing) == (W, PAIN, SMITE),         "the next target's Shadow Word: Pain shows second while the wand finishes this one"
    assert g.lastCtx.nextPressID == PAIN
    one = lua.eval("function(b) b.inCombat = true; b.ctxExecute = true; b.ctxEnemies = 1 end")
    reset()
    assert forecast(lua.table(W, SMITE, MIND_BLAST, PAIN), one)[1] == SMITE, "no other enemy: no next-target forecast"
    notExec = lua.eval("function(b) b.inCombat = true; b.ctxExecute = false; b.ctxEnemies = 3 end")
    reset()
    assert forecast(lua.table(W, SMITE, MIND_BLAST, PAIN), notExec)[1] == SMITE, "not closing: no next-target forecast"
    lua.execute("gates[594] = nil")
    reset()
    assert forecast(lua.table(W, SMITE, MIND_BLAST, PAIN), closing)[1] == SMITE, "no debuff opener on the list: unchanged"
    lua.execute("gates[594] = { { t = 'debuff', id = 589, neg = true } }")
    print("Next press: cast and GCD horizon, weapon rule, rank, cooldown-only waits, closing forecast and untouched modes passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
