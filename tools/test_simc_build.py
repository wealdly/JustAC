# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The imported priority lists, per build, checked outside the game.
#
# Data/SimcRotations.lua ships every priority LINE with the talents and hero tree it is for,
# and the runtime merges those lines into one entry per spell for the player's build
# (RotationImport Resolve). The generator runs the same merge offline (gen_simc_rotations
# `merge`). Two copies of one rule drift, so this holds them to the same answer: for a fixed
# fake build, every spec and context must rank the same spells the same way, with the same
# gates. It also checks that the data really does depend on the build somewhere - a test
# that passes because every build condition vanished would prove nothing.
#
# Run: python tools/test_simc_build.py

import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from gen_simc_rotations import merge  # noqa: E402

PRELUDE = """
local libs = {}
LibStub = setmetatable({
    NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end,
}, { __call = function(_, name) return libs[name] end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
spec, hero = nil, nil
libs["JustAC-SpellDB"] = { GetSpecKey = function() return spec end }
libs["JustAC-BlizzardAPI"] = { ResolveSpellID = function(id) return id end }
-- The fake build: every talent whose id is not a multiple of 3, and one hero tree.
function IsPlayerSpell(id) return id % 3 ~= 0 end
C_ClassTalents = { GetActiveHeroTalentSpec = function() return hero end }
"""


def holds_for(hero):
    def holds(b):
        for c in b:
            if c["k"] == "talent":
                have = any(i % 3 != 0 for i in (c["ids"] if "ids" in c else [c["id"]]))
            else:
                have = c["id"] == hero
            if have == bool(c.get("neg")):
                return False
        return True
    return holds


def tolist(t):
    return [] if t is None else [t[i] for i in range(1, len(t) + 1)]


def py(v):
    if hasattr(v, "keys"):
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [py(x) for x in tolist(v)]
        return {k: py(v[k]) for k in keys}
    return v


def gate_key(g):
    return str(sorted((k, gate_key(v) if k == "g" else v)
                      for k, v in (g.items() if isinstance(g, dict) else enumerate(g))))


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "RotationImport.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "SimcRotations.lua").read_text(encoding="utf-8"))
    RI = lua.eval('LibStub("JustAC-RotationImport")')
    data = lua.eval('LibStub("JustAC-RotationImport")._rotations')
    bad, checked, depends = [], 0, 0
    for spec in sorted(data.keys()):
        contexts = {c: py(data[spec][c]) for c in ("st", "cleave", "aoe") if data[spec][c]}
        heroes = sorted({b["id"] for lst in contexts.values() for e in lst
                         for b in e.get("b", []) if b["k"] == "hero"}) or [None]
        for hero in heroes:
            lua.globals().spec, lua.globals().hero = spec, hero
            RI.InvalidateLookup()
            for ctx, lines in contexts.items():
                for e in lines:
                    # An empty Lua table reads back as an empty dict: make lists lists.
                    for key in ("gates", "b"):
                        if not isinstance(e.get(key), list):
                            e[key] = []
                    e.setdefault("delegated", False)
                want = merge(lines, holds_for(hero))
                if len(merge(lines)) != len(want) or [e["id"] for e in merge(lines)] != [e["id"] for e in want]:
                    depends += 1
                for rank, e in enumerate(want, 1):
                    got = RI.GetEntry(e["id"], ctx)
                    checked += 1
                    if not got or got.rank != rank:
                        bad.append("%s %s %d: rank %s, want %d" % (spec, ctx, e["id"], got and got.rank, rank))
                        continue
                    g1 = sorted(gate_key(g) for g in e["gates"])
                    g2 = sorted(gate_key(py(g)) for g in tolist(got.gates))
                    if g1 != g2 or bool(got.delegated) != bool(e["delegated"]):
                        bad.append("%s %s %d: gates or delegation differ" % (spec, ctx, e["id"]))
    for line in bad[:20]:
        print("  FAIL", line)
    if depends == 0:
        bad.append("no list depends on the build")
        print("  FAIL no list depends on the build: the build conditions did not survive")
    print("simc build: %d entries checked, %d build-dependent lists, %d failure(s)"
          % (checked, depends, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
