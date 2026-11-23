# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Capture sessions are archived one per file, with their context, in a shape the analyzer reads.

Run: python tools/test_archive_probe.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_probe  # noqa: E402
import archive_probe  # noqa: E402

ROWS_A = [
    "DIAGNOSTICS START session=20261120-101500-1 t=10.000 question=all mode=general limit=1200",
    "DIAGNOSTICS BUILD session=20261120-101500-1 deployed=2026-11-20T10:00:00 commit=abc1234 dirty=true",
    "DIAG session=20261120-101500-1 sample=1 elapsed=0.0",
    "  addonVersion=plain:6.4.1",
    "  build=plain:1.60.1.70959",
    "  class=plain:WARRIOR",
    'EVIDENCE flip session=20261120-101500-1 t=11.000 epoch=0 event=flip from=100 to=200 note="quoted \\\\ slash"',
    "DIAGNOSTICS STOP session=20261120-101500-1 samples=1 changes=1 pulls=0 failures=0 t=12.000 marks=0",
]
ROWS_B = [
    "DIAGNOSTICS START session=20261120-103000-2 t=20.000 question=stability mode=question limit=1200",
    "DIAG session=20261120-103000-2 sample=1 elapsed=0.0",
    "  addonVersion=plain:6.4.1",
]


def saved(path, rows, dropped=0):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(archive_probe.saved_variables_text(rows, dropped))


def main():
    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "JustAC.lua")
        out = os.path.join(work, "archive")
        saved(source, ROWS_A + ROWS_B, dropped=7)
        done = archive_probe.archive([("_forever_", source)], out)
        assert [(d[1], d[2], d[3]) for d in done] == [
            ("20261120-101500-1", "archived", len(ROWS_A)), ("20261120-103000-2", "archived", len(ROWS_B))], done

        first = os.path.join(out, "_forever_", "20261120-101500-1.lua")
        text = open(first, encoding="utf-8").read()
        for line in ("-- session: 20261120-101500-1", "-- client: _forever_", "-- complete: yes", "-- mode: general",
                     "-- addonVersion: plain:6.4.1", "-- build: plain:1.60.1.70959", "-- class: plain:WARRIOR",
                     "-- buildStamp: deployed=2026-11-20T10:00:00 commit=abc1234 dirty=true",
                     "-- rows: %d" % len(ROWS_A)):
            assert line in text, line
        # The analyzer reads an archived session exactly as it reads the live file.
        rows, dropped = analyze_probe.read_saved_variables(first)
        assert rows == ROWS_A and dropped == 7, "rows survive the round trip, escapes included"
        sessions = analyze_probe.split_sessions(rows)
        assert len(sessions) == 1 and sessions[0].started and sessions[0].stopped

        second = open(os.path.join(out, "_forever_", "20261120-103000-2.lua"), encoding="utf-8").read()
        assert "-- complete: no (no stop row)" in second and "-- question: stability" in second

        # Archiving again keeps what is there; a session that grew in the live log is updated.
        again = archive_probe.archive([("_forever_", source)], out)
        assert [d[2] for d in again] == ["kept", "kept"], again
        grown = ROWS_B + ["DIAGNOSTICS STOP session=20261120-103000-2 samples=1 changes=0 pulls=0 failures=0 t=30.000 marks=0"]
        saved(source, grown)
        third = archive_probe.archive([("_forever_", source)], out)
        assert [(d[1], d[2]) for d in third] == [("20261120-103000-2", "updated")], third
        # The first session has left the live log; its archive stays.
        assert os.path.isfile(first)
        listed = dict(archive_probe.listing(out))
        assert len(listed) == 2 and all(head.get("addonVersion") == "plain:6.4.1" for head in listed.values())
    print("archive probe: one file per session, context header, analyzer round trip, kept and updated sessions")


if __name__ == "__main__":
    main()
