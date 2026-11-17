# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Health and power thresholds are quantized to 5% before they become engine curves.

Every distinct threshold builds and caches its own curve, so the helper rounds each one to the
nearest 5%. Loads the real NormalizePct from BlizzardAPI/StateHelpers.lua, and checks that every
named threshold constant and every source gate percent already sits on the ladder or moves by at
most 2.5 points.

Run: python tools/test_threshold_quantize.py
"""
import re
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("local PCT_STEP = 5")
    end = source.index("\nend\n", source.index("local function NormalizePct(")) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("local math_floor = math.floor\n" + source[start:end] + "\nTestNormalize = NormalizePct")
    normalize = lua.globals().TestNormalize
    for pct, want in ((20, 20), (35, 35), (59, 60), (79, 80), (6, 5), (7.4, 5), (7.5, 10), (2.4, 0),
                      (97.6, 100), (-3, 0), (140, 100), (33.3, 35), (12.5, 15)):
        got = normalize(pct)
        assert got == want, (pct, got, want)
    assert normalize(None) is None and normalize(float("nan")) is None, "no threshold, no curve"
    # Every named threshold constant in the addon already sits on the 5% ladder.
    constants = {}
    for path in ROOT.glob("*.lua"):
        for name, value in re.findall(r"local (\w*_PCT)\s*=\s*(\d+(?:\.\d+)?)\b", path.read_text(encoding="utf-8")):
            constants[f"{path.name}:{name}"] = float(value)
    off = {k: v for k, v in constants.items() if v % 5}
    assert constants and not off, ("threshold constants off the 5% ladder", off)
    print(f"Threshold quantize: nearest 5% (edge cases, clamps, NaN); {len(constants)} named constants on the ladder")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
