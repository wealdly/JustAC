# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Print the generated Forever priority lists, one line per tree and context.

Each entry shows its name and the kinds of its gates ([debuff,near], ...); a trailing *
marks a delegated entry. Read-only: it parses Data/Forever/Rotations.lua.

Run: python tools/forever_queue_dump.py [CLASS] [tree]
     python tools/forever_queue_dump.py WARRIOR fury
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def dump(want_class=None, want_tree=None, text=None):
    """Lines for the matching lists; text defaults to the current generated file."""
    if text is None:
        with open(os.path.join(ROOT, "Data", "Forever", "Rotations.lua"), encoding="utf-8") as handle:
            text = handle.read()
    start = text.find("RotationImport.RegisterForever")
    text = text[:text.find("}, {", start)]
    cls = tree = None
    lines = []
    for line in text.splitlines():
        m = re.match(r'  \["(\w+)_F"\] = \{', line)
        if m:
            cls = m.group(1)
            continue
        m = re.match(r"    (\w+) = \{", line)
        if m:
            tree = m.group(1)
            continue
        if (want_class and cls != want_class.upper()) or (want_tree and tree != want_tree):
            continue
        m = re.match(r"      (\w+) = \{", line)
        if m:
            lines.append(f"{cls} {tree} {m.group(1)}:")
            continue
        m = re.match(r"\s+\{id=(\d+),gates=(.*?)(,delegated=true)?(,w=true)?\},\s+--\s+(.*)", line)
        if m and lines:
            kinds = []
            for kind in re.findall(r't="(\w+)"', m.group(2)):
                if kind not in kinds:
                    kinds.append(kind)
            gates = "[" + ",".join(kinds) + "]" if kinds else ""
            lines[-1] += f" {m.group(5)}{gates}{'*' if m.group(3) else ''};"
    return lines


if __name__ == "__main__":
    for row in dump(*sys.argv[1:3]):
        print(row)
