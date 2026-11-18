# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Test the local Forever immunity audit without executing SavedVariables."""
import sqlite3
import tempfile
from contextlib import closing
from pathlib import Path

from audit_forever_immunity import compare, load_mechanics, read_observations


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        saved = root / "JustAC.lua"
        saved.write_text(
            'JustACDB = {\n["dotImmuneNPCs"] = {\n[999] = {\n[1] = 9,\n},\n},\n}\n'
            'JustACGlobal = {\n["dotImmuneNPCs"] = {\n'
            '[480] = {\n[772] = 2,\n[172] = 1,\n},\n[481] = {\n[772] = 1,\n},\n},\n}\n',
            encoding="utf-8",
        )
        observations = read_observations(saved)
        assert observations == {(480, 772): 2, (480, 172): 1, (481, 772): 1}
        categories = root / "SpellCategories.1.csv"
        categories.write_text("SpellID,DifficultyID,Mechanic\n772,0,15\n172,0,0\n",
                              encoding="utf-8")
        mechanics = load_mechanics(root, {772, 172})
        assert mechanics == {772: 15}
        database = root / "classic.sqlite"
        with closing(sqlite3.connect(database)) as db:
            db.execute("CREATE TABLE creature_template (entry INTEGER, patch INTEGER, mechanic_immune_mask INTEGER)")
            db.executemany("INSERT INTO creature_template VALUES (?, ?, ?)",
                           [(480, 0, 0), (480, 1, 1 << 14), (481, 0, 0)])
            db.commit()
        assert compare(database, observations, mechanics) == [
            (480, 172, 1, "unknown"), (480, 772, 2, "mask-match"), (481, 772, 1, "not-marked")
        ]
        saved.write_text('JustACGlobal = {\n["dotImmuneNPCs"] = {\n[480] = {\n', encoding="utf-8")
        try:
            read_observations(saved)
        except ValueError:
            pass
        else:
            raise AssertionError("a truncated cache must not be accepted")
    print("Forever immunity audit: account cache, SQL masks, unknowns and malformed input passed")


if __name__ == "__main__":
    main()
