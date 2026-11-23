# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Keep capture sessions for later review.

The capture log in SavedVariables is a rolling one: old rows leave as new ones arrive, and
`/jac inspect audit clear` empties it. This copies each diagnostic session out of it into its
own file, with the context needed to read it later: the client, the JustAC version and the
deployed build stamp recorded in the session, the game build, the character, and when the
file it came from was written.

An archived session is a small SavedVariables-shaped file, so the analyzer reads it as it reads
the live one:

    python tools/archive_probe.py                 # every client, into .probe-archive/
    python tools/archive_probe.py --list          # what is archived
    python tools/analyze_probe.py .probe-archive/_forever_/<session>.lua --question stability

Sessions already archived are skipped unless the live copy has more rows (a session still in
the log when it was archived earlier). Nothing is deleted from SavedVariables or the archive.
"""
import argparse
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_probe  # noqa: E402

DEFAULT_DIR = os.path.join(analyze_probe.ROOT, ".probe-archive")
# What a reader needs before opening the rows, in the order the header prints it. The first
# three come from the session's start and build rows, the rest from its first key reads.
HEADER_KEYS = ("mode", "question", "buildStamp", "addonVersion", "build", "interface", "forever",
               "class", "level", "spec", "instanceType", "mapID")


def _quote(row):
    return '"' + row.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def session_context(session):
    """Header facts from the session's own rows: its start row, build stamp and first key reads."""
    context = {"mode": session.mode, "question": session.question or "all"}
    for row in session.rows:
        if row.startswith("DIAGNOSTICS BUILD "):
            context["buildStamp"] = row.split(" ", 3)[3] if row.count(" ") >= 3 else ""
        match = analyze_probe.KEY_LINE.match(row)
        if match and match.group(1) in HEADER_KEYS and match.group(1) not in context:
            context[match.group(1)] = match.group(2)
    return context


def read_header(path):
    """The `-- key: value` lines an archived session opens with."""
    head = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.startswith("-- "):
                break
            key, _, value = line[3:].strip().partition(": ")
            head[key] = value
    return head


def archived_rows(path):
    """Rows an archived session holds, from its own header; None when there is no such file."""
    if not os.path.isfile(path):
        return None
    count = read_header(path).get("rows", "")
    if count.isdigit():
        return int(count)
    return len(analyze_probe.read_saved_variables(path)[0])


def saved_variables_text(rows, dropped=0):
    """Rows as the saved file holds them: the shape `analyze_probe.read_saved_variables` reads."""
    body = ["JustACGlobal = {", '\t["probeLogDropped"] = %d,' % dropped, '\t["probeLog"] = {']
    body += ["\t\t%s," % _quote(row) for row in rows]
    body += ["\t},", "}"]
    return "\n".join(body) + "\n"


def write_session(path, label, source, session, dropped):
    context = session_context(session)
    modified = datetime.datetime.fromtimestamp(os.path.getmtime(source))
    header = [
        "-- JustAC capture session, archived by tools/archive_probe.py",
        "-- session: %s" % session.id,
        "-- client: %s" % label,
        "-- complete: %s" % ("yes" if session.started and session.stopped else
                             "no (%s)" % ("no stop row" if session.started else "start row lost to the rolling log")),
    ]
    for key in HEADER_KEYS:
        if key in context:
            header.append("-- %s: %s" % (key, context[key]))
    header += [
        "-- rows: %d" % len(session.rows),
        "-- rows the rolling log had discarded when archived (all sessions): %d" % dropped,
        "-- source written: %s" % modified.strftime("%Y-%m-%d %H:%M:%S"),
        "-- archived: %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    ]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(header) + "\n" + saved_variables_text(session.rows, dropped))


def archive(paths, out_dir):
    """Archive every session in each (label, path). Returns [(label, session id, state, rows)]."""
    done = []
    for label, path in paths:
        rows, dropped = analyze_probe.read_saved_variables(path)
        for session in analyze_probe.split_sessions(rows):
            target = os.path.join(out_dir, label.strip("\\/"), session.id + ".lua")
            have = archived_rows(target)
            if have is not None and have >= len(session.rows):
                done.append((label, session.id, "kept", have))
                continue
            write_session(target, label, path, session, dropped)
            done.append((label, session.id, "updated" if have is not None else "archived", len(session.rows)))
    return done


def listing(out_dir):
    out = []
    for folder, _, files in os.walk(out_dir):
        for name in sorted(files):
            if not name.endswith(".lua"):
                continue
            path = os.path.join(folder, name)
            out.append((os.path.relpath(path, out_dir), read_header(path)))
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", help="SavedVariables JustAC.lua files (default: every client)")
    parser.add_argument("--wow-root", default=analyze_probe.DEFAULT_WOW_ROOT)
    parser.add_argument("--dir", default=DEFAULT_DIR, help="archive folder (default: .probe-archive in the checkout)")
    parser.add_argument("--list", action="store_true", help="list what is archived and stop")
    args = parser.parse_args(argv)
    if args.list:
        for rel, head in listing(args.dir):
            print("%-44s %-8s %-10s JustAC %-8s rows %-6s %s" % (
                rel, head.get("mode", "?"), head.get("question", "?"), head.get("addonVersion", "?"),
                head.get("rows", "?"), head.get("buildStamp", "")))
        return 0
    if args.paths:
        paths = [(analyze_probe.client_label(p), p) for p in args.paths]
    else:
        paths = analyze_probe.default_paths(args.wow_root)
    if not paths:
        print("no SavedVariables JustAC.lua found")
        return 1
    for label, session_id, state, rows in archive(paths, args.dir):
        print("%-10s %-9s %s (%d rows)" % (label, state, session_id, rows))
    print("archive: %s" % args.dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
