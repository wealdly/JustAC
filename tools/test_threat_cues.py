# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Threat cues (opt-in): which threat role the target calls for, and which spell answers it.

Loads the real threat block of DefensiveEngine.lua. Damage or healer about to pull (state 1)
or holding aggro: a threat drop. A tank (aura or Tank role) on the list but not tanking: a
taunt; tanking with a slipping lead: a boost. Only with a group or a pet; every unknown or
secret read offers nothing; the spell must be known, ready, usable and in range.

Run: python tools/test_threat_cues.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8")
    start = source.index("-- Threat cues (opt-in: profile.defensives.threatCues)")
    start = source.rindex("\n----", 0, start)
    end = source.index("\n", source.index("DefensiveEngine._AppendThreatCue = AppendThreatCue"))
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        DefensiveEngine, secret = {}, {}
        function PushEntry(results, id) local e = {spellID = id}; results[#results + 1] = e; return e end
        SpellDB = { FOREVER_THREAT_ROLES = {
            [355] = "taunt", [694] = "taunt", [7400] = "taunt",   -- Taunt; Mocking Blow r1, r2
            [586] = "drop", [9578] = "drop", [1966] = "drop",     -- Fade r1, r2; Feint
            [7386] = "boost", [71] = "tank",
        } }
        ranks = { [7400] = 694, [9578] = 586 }
        known, cooldown, unusable, short, outOfRange = {}, {}, {}, {}, {}
        rank = function(id) return ranks[id] or id end
        libs = { ["JustAC-RotationImport"] = {
            RankBase = rank,
            HighestKnownRank = function(base)
                local best
                for id in pairs(SpellDB.FOREVER_THREAT_ROLES) do
                    if rank(id) == base and known[id] and (not best or id > best) then best = id end
                end
                return best
            end,
        } }
        LibStub = function(name) return libs[name] end
        BlizzardAPI = {
            IsSecretValue = function(v) return rawequal(v, secret) end,
            IsGrouped = function() return grouped end,
            IsSpellReady = function(id) return not cooldown[id] end,
            IsSpellUsable = function(id) return not unusable[id], short[id] == true end,
            AbilityInRange = function(id) if outOfRange[id] then return false end return nil end,
        }
        function UnitExists(u) if u == "pet" then return pet end return target end
        function UnitCanAttack() return true end
        function UnitHasEffectivelyTankAura() return tankAura end
        function UnitGroupRolesAssigned() return role end
        function UnitThreatSituation() return state end
        function UnitDetailedThreatSituation() return tanking end
        function UnitThreatLeadSituation() return lead end
        C_Secrets = { ShouldUnitThreatStateBeSecret = function() return stateSecret end }
    """ + source[start:end])
    append = lua.eval("DefensiveEngine._AppendThreatCue")
    base = ("target, grouped, pet, tankAura, role = true, true, false, false, 'DAMAGER';"
            "state, tanking, lead, stateSecret = nil, nil, nil, false;"
            "known, cooldown, unusable, short, outOfRange = {[355]=true,[694]=true,[7400]=true,"
            "[586]=true,[9578]=true,[1966]=true,[7386]=true}, {}, {}, {}, {}")
    for setup, role, spell, why in (
        ("state=0", None, None, "below the tank: nothing"),
        ("state=1", "drop", 9578, "about to pull: a threat drop, at its highest known rank"),
        ("state=1; known[9578]=nil; known[586]=nil", "drop", 1966, "no Fade known: Feint"),
        ("state=3", "drop", 9578, "already holding aggro as damage: drop it"),
        ("state=1; grouped=false", None, None, "solo, no pet: threat means nothing"),
        ("state=1; grouped=false; pet=true", "drop", 9578, "solo with a pet holding aggro"),
        ("state=1; grouped=nil", None, None, "group unknown and no pet: nothing"),
        ("state=secret", None, None, "a secret state offers nothing"),
        ("state=1; stateSecret=true", None, None, "the game says threat is secret here"),
        ("state=1; stateSecret=nil", None, None, "unknown secrecy offers nothing"),
        ("state=nil", None, None, "not on its threat list"),
        ("target=false; state=1", None, None, "no target"),
        ("role='TANK'; state=0; tanking=false", "taunt", 355, "a tank not tanking its target: taunt"),
        ("tankAura=true; state=0; tanking=false", "taunt", 355, "a tank stance counts as a tank"),
        ("role='TANK'; state=0; tanking=false; cooldown[355]=true", "taunt", 7400,
         "Taunt on cooldown: Mocking Blow, highest known rank"),
        ("role='TANK'; state=0; tanking=false; outOfRange[355]=true; outOfRange[7400]=true", "taunt", None,
         "every taunt out of range: nothing to press"),
        ("role='TANK'; state=3; tanking=true; lead=0", None, None, "a secure lead: nothing"),
        ("role='TANK'; state=2; tanking=true; lead=1", "boost", 7386, "a slipping lead: a threat boost"),
        ("role='TANK'; state=2; tanking=true; lead=1; short[7386]=true", "boost", None, "the boost unaffordable"),
        ("role='TANK'; state=2; tanking=true; lead=secret", None, None, "an unreadable lead: nothing"),
        ("role='TANK'; state=0; tanking=secret", None, None, "an unreadable tanking flag: nothing"),
        ("role=secret; state=1", "drop", 9578, "an unreadable role is not a tank"),
    ):
        lua.execute(base + ";" + setup)
        got_role = lua.eval("DefensiveEngine.WantedThreatRole()")
        results = lua.eval("{}")
        append(lua.eval("{defensives={threatCues=true}}"), results, lua.eval("{}"), 4)
        got_spell = results[1]["spellID"] if results[1] else None
        got_kind = results[1]["threat"] if results[1] else None
        assert got_role == role, (why, "role", got_role, role)
        assert got_spell == spell and (spell is None or got_kind == role), (why, "spell", got_spell, spell)
    lua.execute(base + "; state=1")
    results = lua.eval("{}")
    append(lua.eval("{defensives={threatCues=false}}"), results, lua.eval("{}"), 4)
    assert results[1] is None, "off by default: no cue"
    results = lua.eval("{1,2,3,4}")
    append(lua.eval("{defensives={threatCues=true}}"), results, lua.eval("{}"), 4)
    assert results[5] is None, "a full cluster takes no cue"
    print("Threat cues: drop, taunt and boost from the target's plain reads; unknowns, solo and off give none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
