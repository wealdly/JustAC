# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The whole capture flow, offline: start the standard session with the real probe loaded
(Lua 5.1, Research companion included), sample, stop, save, archive, analyze.

The unit tests stub the session's neighbours; this runs them together, which is where the
flow broke before (rows written before the start row were lost to the session).

Run: python tools/test_capture_flow.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_probe  # noqa: E402
import archive_probe  # noqa: E402
import test_debug_probes as probes  # noqa: E402


def capture(mode):
    lua = probes.loaded_runtime(True, True)
    g = lua.globals()
    lua.execute("clock = 100; function GetTime() return clock end")
    commands = g.DebugCommands
    commands.StartDiagnostics(g.addon, mode)
    session = commands._diagnosticSession
    assert session is not None, list(g.output.values())
    owned = sorted(session.ownedLoggers.values())
    for _ in range(8):
        lua.execute("clock = clock + 0.25")
        session.ticker.fn()
    commands.StopDiagnostics(g.addon)
    return session, owned, list(g.JustACGlobal.probeLog.values()), commands


def main():
    if not probes.RESEARCH_FILES:
        print("capture flow: research companion absent, skipped")
        return
    for mode, name in ((None, "general"), ("full", "full")):
        session, owned, rows, commands = capture(mode)
        assert session.mode == name, session.mode
        # One capture: it runs the passive recorders itself and stops what it started.
        for logger in ("MaintenanceLog", "EnrageLog", "MobProfileProbe", "PetProfileProbe"):
            assert logger in owned, (name, owned)
        assert "PickLog" not in owned, "the pick logger needs a game pick"
        for state in ("_maintLog", "_enrageLog", "_mobProfileOn", "_petProfileOn"):
            assert not commands[state], (name, state, "left running after the session stopped")
        assert bool(session.ownsAudit) == (name == "full") and bool(session.ownsWatch) == (name == "full"), name
        assert commands._probeSession is None and commands._foreverWatch is None, "full mode stops what it started"
        # Every row belongs to the session: nothing is written before its start row.
        assert rows[0].startswith("DIAGNOSTICS START session=" + session.id), rows[0]
        assert rows[1].startswith("DIAGNOSTICS BUILD session=" + session.id) or not commands._buildStamp, rows[1]
        assert rows[-1].startswith("DIAGNOSTICS STOP session=") or any(
            r.startswith("DIAGNOSTICS STOP session=") for r in rows[-3:]), rows[-3:]
        # Recorder chat lines (how to switch one off by hand) stay out of a session's log.
        assert not any("inspect maintlog off" in r or "inspect enragelog off" in r for r in rows), name
        with tempfile.TemporaryDirectory() as work:
            saved = os.path.join(work, "JustAC.lua")
            with open(saved, "w", encoding="utf-8") as handle:
                handle.write(archive_probe.saved_variables_text(rows))
            done = archive_probe.archive([("_forever_", saved)], os.path.join(work, "archive"))
            assert [(d[1], d[2], d[3]) for d in done] == [(session.id, "archived", len(rows))], (name, done, len(rows))
            kept, _ = analyze_probe.read_saved_variables(os.path.join(work, "archive", "_forever_", session.id + ".lua"))
            assert kept == rows, "the archive holds the whole session"
            # The standard capture carries the question definitions, so any question can be
            # scored from it afterwards without a focused session.
            assert any(r.startswith("QUESTION DEF") and "stability" in r for r in kept), "definitions ride along"
    print("capture flow: standard and full sessions own their recorders, lose no rows, archive whole and stay scorable")


if __name__ == "__main__":
    main()
