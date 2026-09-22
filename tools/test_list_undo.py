# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The priority list's undo stack, checked outside the game.
#
# The bookkeeping is pure list logic: an edit pushes the copy held from last time, and a
# restore must NOT push the state it just undid back on. That second rule is the one this
# shape of undo gets wrong, and it is invisible until someone presses the button twice.
#
# Run: python tools/test_list_undo.py

import re
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "Options" / "PriorityList.lua"

PRELUDE = """
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
spec, cq = "SPEC_1", { spells = {} }
profile = {}
function SpecKey() return spec end
function CustomQueueFor(p) return (p == profile) and cq or nil end
addon = { GetProfile = function() return profile end }
PriorityList = {}
function PriorityList.Changed(a) NoteEdit(a) end
function edit(...)
    cq.spells = { ... }
    NoteEdit(addon)
end
function ids()
    local out = {}
    for i, v in ipairs(cq.spells) do out[i] = v end
    return table.concat(out, ",")
end
"""


def extract(text):
    """The undo block, from the depth constant to the end of Undo."""
    start = text.index("local UNDO_DEPTH")
    end = text.index("\nend\n", text.index("function PriorityList.Undo(", start))
    return text[start:end + len("\nend\n")].replace("local function NoteEdit", "function NoteEdit", 1)


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract(SRC.read_text(encoding="utf-8")).replace("\r\n", "\n"))
    run = lua.eval("function(src) return assert(load(src))() end")
    bad = []

    def check(want, got, why):
        if want != got:
            bad.append("  FAIL %-46s got %r, want %r" % (why, got, want))

    run("edit(1,2,3)")            # first sighting: nothing to undo yet
    check(False, run("return PriorityList.CanUndo()"), "no history before the second edit")

    run("edit(1,2,3,4)")
    check(True, run("return PriorityList.CanUndo()"), "an edit is undoable")
    run("PriorityList.Undo(addon)")
    check("1,2,3", run("return ids()"), "undo restores the previous list")

    check(False, run("return PriorityList.CanUndo()"),
          "the restore does not become its own undo step")

    run("edit(9)")
    run("edit(9,8)")
    run("PriorityList.Undo(addon)")
    run("PriorityList.Undo(addon)")
    check("1,2,3", run("return ids()"), "two undos walk back two edits")

    for n in range(1, 16):        # depth cap
        run("edit(%d)" % n)
    depth = run("return PriorityList.CanUndo()")
    for _ in range(20):
        run("PriorityList.Undo(addon)")
    check(True, depth, "deep history is still undoable")
    check(False, run("return PriorityList.CanUndo()"), "undoing past the end stops cleanly")

    run("spec = 'SPEC_2'; cq = { spells = {} }")
    run("edit(7)")
    run("edit(7,7)")
    run("spec = 'SPEC_1'; cq = { spells = { 5 } }")
    run("edit(5,6)")
    check(False, run("return PriorityList.CanUndo()"),
          "history does not cross a spec change")
    run("PriorityList.Undo(addon)")
    check("5,6", run("return ids()"),
          "and undo cannot reach the other spec's list")

    # The panel calls Changed when it opens and when a tab is picked, which seeds the copy,
    # so in the game the FIRST edit after a spec change is undoable. Nothing else does.
    run("NoteEdit(addon)")
    run("edit(5,6,7)")
    run("PriorityList.Undo(addon)")
    check("5,6", run("return ids()"), "a seen list makes the next edit undoable")

    for line in bad:
        print(line)
    print("list undo: 10 case(s), %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
