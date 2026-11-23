# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""A target that holds its range (Forever): once a lone target casts, or keeps hitting the player
from out of melee, a slowing filler (Frostbolt) gives its place to a stronger unlisted attack
that does not slow (Fireball). No evidence, a target in melee, or a list that names both keeps the
list's order. Loads the real functions from SpellQueueForever.lua.

Run: python tools/test_ranged_filler.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
FROSTBOLT, FIREBALL, ARCANE_MISSILES = 116, 133, 5143


def main():
    source = (ROOT / "SpellQueueForever.lua").read_text(encoding="utf-8")
    start = source.index("local HOLD_RANGE_AFTER = 3")
    end = source.index("-- A next-swing attack (Heroic Strike) costs no global cooldown")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        secret = {}
        guid, within, casting, hit = "Creature-A", false, false, false
        listed, hits, cycles = {}, { [116] = 300, [133] = 450, [5143] = 380 }, { [116] = 2.5, [133] = 3, [5143] = 5 }
        sunkSet, lastCtx = {}, {}
        function UnitGUID() return guid end
        function UnitCastingInfo()
            if casting == true then return "Shoot" end
            if casting then return casting end   -- a secret name
        end
        function UnitChannelInfo() return nil end
        tanking = true   -- the target is attacking the player
        function UnitDetailedThreatSituation()
            if tanking == "error" then error("denied") end
            return tanking
        end
        BlizzardAPI = {
            IsForever = function() return true end,
            IsSecretValue = function(v) return rawequal(v, secret) end,
            GetDisplaySpellID = function(id) return id end,
            GetDirectSpellHit = function(id) return hits[id] end,
            GetSpellCycleSeconds = function(id) return cycles[id] end,
            AbilityInRange = function() return true end,
            IsSpellUsable = function() return true, false end,
        }
        SpellDB = {
            IsTargetWithin = function() return within end,
            IsSlowingAttack = function(id) return id == 116 end,
        }
        RotationImport = { GetEntry = function(id) return listed[id] end }
        SpellQueue = {
            IsSpellBlacklisted = function() return false end,
            _BeingHit = function() return hit end,
            _IsLeftOut = function(id) return leftOut == id end,
        }
        function PushbackRead(fn, ...) return fn(...) end
        function PushbackReady() return true end
        function PassesRotationFilters() return true end
        function HeldByUserHold() return false end
        function PlaceQueueSpell(b, id, at)
            local q = b.recommendedSpells
            b.spellCount = math.min(b.spellCount + 1, b.maxIcons)
            for i = b.spellCount, at + 1, -1 do q[i] = q[i - 1] end
            q[at] = id
        end
    """ + source[start:end] + """
        function Build(now, enemies)
            local b = { inCombat = true, now = now, ctxEnemies = enemies or 1, spellCount = 3, maxIcons = 4,
                        recommendedSpells = { 116, 5143, 6603 }, profile = {}, blacklist = {} }
            SpellQueue._StageRangedFiller(b, { 116, 5143, 133 })
            return b.recommendedSpells[1], b.recommendedSpells[2], lastCtx.holdsRange
        end
    """)
    build = lua.eval("Build")

    first, _, holds = build(0)
    assert first == FROSTBOLT and holds is False, "no evidence yet: the list's Frostbolt"
    lua.execute("hit = true")
    first, _, holds = build(1)
    assert first == FROSTBOLT and holds is False, "hit too early: could be the pull"
    first, second, holds = build(4)
    assert (first, second, holds) == (FIREBALL, FROSTBOLT, True), "a lone target hitting from range: Fireball"
    lua.execute("hit = false")
    first, _, _ = build(5)
    assert first == FIREBALL, "the verdict holds for this target"
    lua.execute("within = true")
    first, _, holds = build(6)
    assert first == FROSTBOLT and holds is False, "it reached melee: back to the list"
    lua.execute("within, guid, casting = false, 'Creature-B', true")
    first, _, _ = build(7)
    assert first == FIREBALL, "a new target casting from range"
    for value, why in (("false", "another mob is hitting the player"),
                       ("nil", "the target has not engaged the player"),
                       ("secret", "an unreadable threat read proves nothing")):
        lua.execute(f"guid, casting, hit, tanking = 'Threat-{value}', false, true, {value}")
        build(60)
        first, _, holds = build(64)
        assert first == FROSTBOLT and holds is False, why
    lua.execute("tanking = true")
    lua.execute("guid, casting, hit = 'Creature-C', false, true")
    first, _, _ = build(20, 2)
    assert first == FROSTBOLT, "being hit in a pack proves nothing about this target"
    lua.execute("guid, casting, listed[133] = 'Creature-D', true, {}")
    first, _, _ = build(30)
    assert first == FROSTBOLT, "a list that names Fireball keeps its own order"
    lua.execute("listed[133] = nil; hits[133] = 200; guid = 'Creature-E'")
    first, _, _ = build(40)
    assert first == FROSTBOLT, "nothing stronger: Frostbolt stays"
    lua.execute("hits[133] = 450; casting = secret; guid = 'Creature-F'")
    first, _, holds = build(50)
    assert first == FROSTBOLT and holds is False, "an unreadable cast is no evidence"
    print("Ranged filler: a target holding range swaps a slowing filler for a stronger one")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
