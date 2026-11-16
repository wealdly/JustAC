# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Range-reference verdicts use the real shared distance evaluator.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "SpellDB.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
    start = source.index("local knownRangeProbes =")
    end = source.index("\n--------------------------------------------------------------------------------\n-- API Functions", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        forever = false
        SpellDB = {IsForever = function() return forever end}
        RANGE_REFERENCES = {[3044] = 35}
        RANGE_ITEM_REFERENCES = {}
        itemCached, itemAnswers, itemLoads, itemReads = {}, {}, 0, 0
        C_Item = {
            IsItemDataCachedByID = function(id) return itemCached[id] == true end,
            RequestLoadItemDataByID = function() itemLoads = itemLoads + 1 end,
            IsItemInRange = function(id, unit)
                assert(unit == "target")
                itemReads = itemReads + 1
                return itemAnswers[id]
            end,
        }
        interact, interactReads = nil, 0
        CheckInteractDistance = function(unit, index)
            assert(unit == "target" and index == 3)
            interactReads = interactReads + 1
            return interact
        end
        now, answers, info, swing = 0, {}, {}, nil
        reads, swingReads = 0, 0
        ranks, known = {}, {}
        secret, errors = {}, 0
        function GetTime() return now end
        function wipe(t) for k in pairs(t) do t[k] = nil end end
        function IsSpellKnown(id) return known[id] ~= false end
        function LibStub()
            return {
                RankChain = function(id) return ranks[id] end,
                HighestKnownRank = function(id) return ranks[id] end,
            }
        end
        function geterrorhandler() return function() errors = errors + 1 end end
        C_Spell_IsSpellInRange = function(id, unit)
            assert(unit == "target")
            reads = reads + 1
            if answers[id] == "error" then error("range denied") end
            return answers[id]
        end
        api = {
            IsSecretValue = function(value) return value == secret end,
            GetCachedSpellInfo = function(id)
                if info[id] == "error" then error("denied") end
                return info[id]
            end,
            IsTargetInSwingRange = function() swingReads = swingReads + 1; return swing end,
        }
        function GetBlizzardAPI() return api end
    """)
    lua.execute(source[start:end])
    lua.execute("""
        info[3044], answers[3044] = {minRange=8, maxRange=35}, false
        assert(SpellDB.IsTargetWithin(5) == nil,
            "a minimum-range failure cannot prove the target is beyond melee")
        now=6; info[3044]={minRange=0, maxRange=35}
        assert(SpellDB.IsTargetWithin(5) == false,
            "a zero-minimum ranged reference still proves an out-of-range target")
        now=12; info[3044]=nil
        assert(SpellDB.IsTargetWithin(5) == nil, "missing range metadata remains unknown")
        now=18; info[3044]={minRange=secret, maxRange=35}
        assert(SpellDB.IsTargetWithin(5) == nil, "secret minimum remains unknown")
        now=24; info[3044]="error"
        assert(SpellDB.IsTargetWithin(5) == nil and errors == 1, "denied metadata is reported")
        now=30; info[3044]={minRange=8, maxRange=35}; answers[3044]=true
        assert(SpellDB.IsTargetWithin(40) == true, "an in-range reference still proves within")
        now=36; answers[3044]=false; swing=true
        assert(SpellDB.IsTargetWithin(5) == true, "confirmed swing reach still wins")
        now=42; swing=false
        assert(SpellDB.IsTargetWithin(5) == false, "confirmed swing rejection still wins")

        swing=nil; info[3044]={minRange=0, maxRange=15}; answers[3044]=true
        RANGE_REFERENCES[3044]=5; SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(5) == nil, "15yd ability cannot prove melee despite stale 5yd data")
        local count, swings = reads, swingReads
        assert(SpellDB.IsTargetWithin(15) == true)
        assert(SpellDB.CanProveWithin(5) == false)
        assert(reads == count and swingReads == swings, "all radii share one frame snapshot")
        local probe = SpellDB.DebugRangeProbes()[1]
        assert(probe.id == 3044 and probe.maxRange == 15 and probe.ref == 5,
            "diagnostics expose live and curated endpoints from the same snapshot")

        answers[3044]=false; RANGE_REFERENCES[3044]=40
        info[3044]={minRange=0, maxRange=10}; SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(25) == nil, "10yd rejection cannot prove beyond 25yd")
        assert(SpellDB.IsTargetWithin(5) == false)
        answers[3044]=true; SpellDB.InvalidateRangeCache()
        assert(SpellDB.IsTargetWithin(10) == true, "same-frame target switch drops stale evidence")

        for _, maxRange in ipairs({secret, 0, "35"}) do
            info[3044]={minRange=0, maxRange=maxRange}; SpellDB.InvalidateRangeCache(true)
            assert(SpellDB.IsTargetWithin(40) == nil, "unreadable/invalid maximum cannot prove reach")
        end
        info[3044]={minRange=0}; SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(40) == nil, "missing maximum cannot prove reach")
        info[3044]=secret; SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(40) == nil, "secret metadata is never indexed")

        ranks[3044]=14281; known[3044]=false
        info[14281]={minRange=0, maxRange=35}; answers[14281]=true
        SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(40) == true, "newly learned rank is available immediately")
        probe=SpellDB.DebugRangeProbes()[1]
        assert(probe.id == 14281 and probe.baseID == 3044 and probe.r == true,
            "diagnostics and production resolve the same rank")
        answers[14281]=secret; now=43
        assert(SpellDB.IsTargetWithin(40) == nil, "secret verdict remains unknown")
        answers[14281]="error"; now=44
        assert(SpellDB.IsTargetWithin(40) == nil and errors == 2, "denied range is reported")

        -- Out of combat, an aggressive NPC would already have attacked a player inside a
        -- minimum range, so a failed minimum-range probe means beyond its maximum.
        ranks[3044]=nil; known[3044]=true; swing=nil
        info[3044]={minRange=8, maxRange=35}; answers[3044]=false
        state = {
            playerCombat=false, playerDead=false, stealthed=false, feign=false,
            targetExists=true, targetDead=false, targetPlayer=false, canAttack=true,
            reaction=2, targetCombat=false, tapDenied=false, trivial=false,
        }
        local function v(key) return function() return state[key] end end
        function UnitAffectingCombat(unit)
            if unit == "player" then return state.playerCombat end
            return state.targetCombat
        end
        function UnitIsDeadOrGhost(unit)
            if unit == "player" then return state.playerDead end
            return state.targetDead
        end
        IsStealthed = v("stealthed")
        UnitIsFeignDeath = v("feign")
        UnitExists = v("targetExists")
        UnitIsPlayer = v("targetPlayer")
        function UnitCanAttack(unit, other)
            assert(unit == "target" and other == "player", "the target's ability to attack us")
            return state.canAttack
        end
        function UnitReaction(unit, other)
            assert(unit == "target" and other == "player", "the target's reaction to us")
            if state.reaction == "error" then error("reaction denied") end
            return state.reaction
        end
        UnitIsTapDenied = v("tapDenied")
        UnitIsTrivial = v("trivial")
        -- Observe continuously (0.25s frames) for `seconds`; returns the last 5yd verdict.
        local function observe(seconds)
            local verdict
            for _ = 1, math.floor(seconds / 0.25 + 0.5) do
                now = now + 0.25
                verdict = SpellDB.IsTargetWithin(5)
            end
            return verdict
        end
        now=50; SpellDB.InvalidateRangeCache(true)
        assert(SpellDB.IsTargetWithin(5) == nil, "a fresh reading is not yet trusted")
        local _, settling = SpellDB.GetAggroRangeState()
        assert(settling:find("^settling 0.0s of 1.5s"), settling)
        assert(observe(1.25) == nil, "still settling after 1.25s")
        assert(observe(0.25) == false, "held for 1.5s: beyond the failed probe's maximum")
        assert(SpellDB.IsTargetWithin(35) == false)
        assert(SpellDB.IsTargetWithin(40) == nil, "nothing is claimed past the probe's maximum")
        local applies, reason = SpellDB.GetAggroRangeState()
        assert(applies == true and reason == "aggressive target out of combat")
        local blockers = {
            {"playerCombat", true}, {"playerCombat", nil}, {"playerDead", true}, {"stealthed", true},
            {"feign", true}, {"targetExists", false}, {"targetDead", true}, {"targetPlayer", true},
            {"canAttack", false}, {"reaction", 3}, {"reaction", 4}, {"reaction", secret},
            {"reaction", "error"}, {"reaction", nil}, {"targetCombat", true}, {"tapDenied", true},
            {"trivial", true}, {"trivial", secret},
        }
        for _, case in ipairs(blockers) do
            local key, value = case[1], case[2]
            local saved = state[key]
            state[key] = value
            now = now + 0.25
            assert(SpellDB.IsTargetWithin(5) == nil, "blocked by " .. key .. "=" .. tostring(value))
            assert(SpellDB.GetAggroRangeState() == false)
            state[key] = saved
            now = now + 0.25
            assert(SpellDB.IsTargetWithin(5) == nil, "a blocker restarts the wait: " .. key)
            assert(observe(1.5) == false, "settles again after " .. key)
        end
        SpellDB.InvalidateRangeCache()
        now = now + 0.25
        assert(SpellDB.IsTargetWithin(5) == nil, "a target change restarts the wait")
        assert(observe(1.5) == false)
        now = now + 0.75
        assert(SpellDB.IsTargetWithin(5) == nil, "an observation gap restarts the wait")
        assert(observe(1.5) == false)
        state.reaction=1; now = now + 0.25
        assert(SpellDB.IsTargetWithin(5) == false, "hated targets are aggressive too")
        now = now + 0.25; answers[3044]=true
        assert(SpellDB.IsTargetWithin(35) == true, "an in-range reading is unaffected")
        local _, idle = SpellDB.GetAggroRangeState()
        assert(idle == "no failed minimum-range probe", "the rule is only evaluated when needed")
        answers[3044]=false; now = now + 0.25
        assert(SpellDB.IsTargetWithin(5) == nil, "an in-range reading in between restarts the wait")
        UnitIsTrivial = nil; assert(observe(2) == nil, "a client without the API keeps the reading ambiguous")

        C_Spell_IsSpellInRange=nil; swing=true; now = now + 1
        assert(SpellDB.IsTargetWithin(5) == true, "swing evidence survives an absent spell API")
        swing=nil; now = now + 1
        assert(not SpellDB.CanProveWithin(40), "absent spell and swing checks cannot establish reach")
        assert(itemReads == 0 and interactReads == 0, "retail never reads Forever-only sources")
    """)
    lua.execute("""
        -- WoW Forever: melee references, reference items, interaction check, contradictions.
        local function fresh() SpellDB.InvalidateRangeCache(true); now = now + 1 end
        forever = true; swing = nil
        C_Spell_IsSpellInRange = function(id, unit)
            assert(unit == "target")
            return answers[id]
        end
        state.playerCombat = true; state.targetCombat = true; state.playerCanAttack = true
        function UnitCanAttack(unit, other)
            if unit == "player" then
                assert(other == "target")
                return state.playerCanAttack
            end
            return state.canAttack
        end
        for k in pairs(RANGE_REFERENCES) do RANGE_REFERENCES[k] = nil end
        RANGE_REFERENCES[2974] = 5   -- Wing Clip
        RANGE_REFERENCES[2973] = 5   -- Raptor Strike (next-swing)
        SpellDB.NEXT_SWING_SPELLS = {[2973] = true}
        info[2974] = {minRange=0, maxRange=0}; info[2973] = {minRange=0, maxRange=0}
        answers[2974] = true; answers[2973] = true
        fresh()
        assert(SpellDB.IsTargetWithin(5) == true, "a zero-maximum 5yd reference is a melee probe on Forever")
        assert(SpellDB.CanProveWithin(5) == true)
        local byID = {}
        for _, p in ipairs(SpellDB.DebugRangeProbes()) do byID[p.id] = p end
        assert(byID[2974].meleeReference and byID[2974].maxRange == 5)
        assert(not byID[2973].meleeReference and byID[2973].maxRange == nil,
            "next-swing attacks read in range at any distance and never become probes")
        answers[2974] = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == false, "a recovered melee probe proves out of melee")
        info[2974] = {minRange=0}; fresh()
        assert(SpellDB.IsTargetWithin(5) == false, "a missing maximum is recovered too")
        for _, bad in ipairs({{minRange=0, maxRange=secret}, {minRange=8, maxRange=0}, {minRange=secret, maxRange=0}}) do
            info[2974] = bad; fresh()
            assert(SpellDB.IsTargetWithin(5) == nil, "secret or non-melee endpoints are not recovered")
        end
        info[2974] = {minRange=0, maxRange=0}; RANGE_REFERENCES[2974] = 10; fresh()
        assert(SpellDB.IsTargetWithin(5) == nil, "only 5yd references are melee probes")
        RANGE_REFERENCES[2974] = 5; forever = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == nil, "retail keeps discarding zero maxima")
        forever = true
        RANGE_REFERENCES[2974] = nil; RANGE_REFERENCES[2973] = nil

        -- Reference items: requested once, used only once cached, both items must agree.
        RANGE_ITEM_REFERENCES[5] = {11, 12}; RANGE_ITEM_REFERENCES[10] = {21, 22}
        fresh()
        assert(SpellDB.IsTargetWithin(5) == nil and itemReads == 0, "uncached items are not read")
        assert(itemLoads == 4 and SpellDB.CanProveWithin(5) == false, "loading items prove nothing yet")
        fresh()
        assert(itemLoads == 4, "item data is requested once")
        for _, id in ipairs({11, 12, 21, 22}) do itemCached[id] = true; itemAnswers[id] = true end
        fresh()
        assert(SpellDB.IsTargetWithin(5) == true and SpellDB.CanProveWithin(5) == true)
        itemAnswers[12] = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == nil and SpellDB.IsTargetWithin(10) == true,
            "a tier whose items disagree is unknown")
        itemAnswers[11] = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == false and SpellDB.IsTargetWithin(10) == true)
        itemAnswers[21], itemAnswers[22] = false, false; fresh()
        assert(SpellDB.IsTargetWithin(10) == false)
        local function tier5() return SpellDB.DebugRangeSources().items[1] end
        itemAnswers[11] = secret; fresh()
        assert(tier5().yards == 5 and tier5().ready and tier5().r == nil, "a secret item read is unknown")
        assert(SpellDB.IsTargetWithin(5) == false, "the 10yd tier still proves beyond melee")
        itemAnswers[11] = nil; fresh()
        assert(tier5().r == nil, "a nil item read is unknown")
        itemAnswers[11], itemAnswers[12] = false, false
        for _, case in ipairs({{"targetExists", false}, {"targetDead", true}, {"playerCanAttack", false},
                               {"playerCanAttack", secret}}) do
            local saved = state[case[1]]
            state[case[1]] = case[2]; fresh()
            assert(SpellDB.IsTargetWithin(10) == nil, "no live attackable target: " .. case[1])
            state[case[1]] = saved
        end
        for k in pairs(RANGE_ITEM_REFERENCES) do RANGE_ITEM_REFERENCES[k] = nil end

        -- Interaction check: true proves within 8, false proves beyond melee only.
        interact = true; fresh()
        assert(SpellDB.IsTargetWithin(8) == true and SpellDB.IsTargetWithin(5) == nil)
        assert(SpellDB.CanProveWithin(8) == true and SpellDB.CanProveWithin(5) == false)
        interact = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == false and SpellDB.IsTargetWithin(8) == nil)
        state.targetExists = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == nil, "no-target false is not distance evidence")
        state.targetExists = true

        -- Contradictions make every radius unknown.
        swing = true; fresh()
        assert(SpellDB.IsTargetWithin(5) == nil and SpellDB.IsTargetWithin(40) == nil,
            "swing reach against a failed interaction check is a contradiction")
        assert(SpellDB.DebugRangeSources().contradiction == true)
        interact = true; fresh()
        assert(SpellDB.IsTargetWithin(5) == true and SpellDB.DebugRangeSources().contradiction == false)
        swing = false; fresh()
        assert(SpellDB.IsTargetWithin(5) == false and SpellDB.IsTargetWithin(8) == true,
            "out of melee and within 8 are compatible")
        swing = nil; interact = nil
    """)
    print("Range references: endpoints, ranks, unknowns, invalidation, shared snapshots and"
          " pre-combat aggro inference, Forever melee references, reference items, interaction"
          " and contradictions passed")


if __name__ == "__main__":
    main()
