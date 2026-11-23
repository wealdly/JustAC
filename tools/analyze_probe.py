#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
#
# tools/analyze_probe.py
#
# Score JustAC diagnostic captures against research question definitions.
#
# Every diagnostic session writes the definitions of the questions it can answer
# (QUESTION DEF/CONTROL/CHECK rows from Debug/Research/Questions.lua) into
# JustACGlobal.probeLog. This tool reads a client's SavedVariables, splits the log
# into sessions and reports, per question:
#   - controls: how many times each required in-game transition or mark occurred;
#   - checks: consistency contradictions found without reading any hidden value
#     (latches that release on the same target, implications that fail, states
#     reached in the wrong order), time shares, mark responses and tallies.
# A question whose required controls all occurred with no contradiction is
# "CONTROLS MET": a candidate for adoption review, not proof of correctness.
#
# Captures recorded before the harness carry no definitions; they are scored
# against the current registry (requires lupa) and labeled as such.
#
# Usage:
#   python tools/analyze_probe.py                       # latest session, both clients
#   python tools/analyze_probe.py path/to/JustAC.lua    # explicit SavedVariables
#   python tools/analyze_probe.py --all --question execute --json
# SavedVariables flush only on /reload or logout: check the session time printed.
import argparse
import functools
import glob
import json
import os
import re
import sys
import time
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY_PATH = os.path.join(ROOT, "Debug", "Research", "Questions.lua")
DEFAULT_WOW_ROOT = os.environ.get("JUSTAC_WOW_ROOT", r"C:\Blizzard\World of Warcraft")

LIST_FIELDS = {"has", "lacks", "prevHas", "prevLacks", "on", "off", "forbid", "firstHas",
               "resetMarks", "keys", "rows", "audit", "marks", "rowHas", "per", "perLacks"}
DEFAULT_REPEATS = 2
MARK_FIGHT_LOOKAHEAD = 15.0   # seconds: a mark typed before the pull belongs to that fight
CELL_STATUS = re.compile(r"^(plain|nil|secret|err):")
KEY_LINE = re.compile(r"^  ([A-Za-z][A-Za-z0-9_.]*)=(.*)$")
FIELD = re.compile(r"\b([A-Za-z][A-Za-z0-9_]*)=(\S*)")
LEADING_TIME = re.compile(r"^\S+(?: \S+)? (\d+\.\d+)\b")
T_FIELD = re.compile(r"\bt=(\d+(?:\.\d+)?)\b")
TIMED_PREFIXES = ("DOT ", "PRIORITY ", "EDGE ")


# --------------------------------------------------------------------------- log
def _unescape(text):
    escapes = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}

    def repl(match):
        token = match.group(1)
        if token.isdigit():
            return chr(int(token))
        return escapes.get(token, token)

    return re.sub(r"\\(\d{1,3}|.)", repl, text)


def read_saved_variables(path):
    """Return (probeLog rows, probeLogDropped) from a JustAC SavedVariables file."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    rows, dropped, inside = [], 0, False
    entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)",?\s*(?:--.*)?$')
    for line in lines:
        if not inside:
            if re.match(r'^\s*\["probeLog"\]\s*=\s*\{\s*$', line):
                inside = True
                continue
            match = re.match(r'^\s*\["probeLogDropped"\]\s*=\s*(\d+)', line)
            if match:
                dropped = int(match.group(1))
            continue
        if re.match(r"^\s*\},?\s*$", line):
            inside = False
            continue
        match = entry.match(line)
        if match:
            rows.append(_unescape(match.group(1)))
    return rows, dropped


class Session:
    def __init__(self, session_id):
        self.id = session_id
        self.rows = []
        self.started = False
        self.stopped = False
        self.question = None
        self.mode = "unknown"
        self.stop_row = None


def split_sessions(rows):
    """Assign log rows to diagnostic sessions in log order."""
    sessions, order, current = {}, [], None

    def get(session_id):
        if session_id not in sessions:
            sessions[session_id] = Session(session_id)
            order.append(session_id)
        return sessions[session_id]

    for row in rows:
        start = re.match(r"^DIAGNOSTICS START session=(\S+)", row)
        diag = re.match(r"^DIAG session=(\S+)", row)
        stop = re.match(r"^DIAGNOSTICS STOP session=(\S+)", row)
        if start:
            current = get(start.group(1))
            current.started = True
            question = re.search(r"\bquestion=(\S+)", row)
            current.question = question.group(1) if question else None
            mode = re.search(r"\bmode=(\S+)", row)
            current.mode = mode.group(1) if mode else "unknown"
        elif diag and (current is None or current.id != diag.group(1)):
            current = get(diag.group(1))
        elif stop:
            session = get(stop.group(1))
            session.stopped = True
            session.stop_row = row
            session.rows.append(row)
            current = None
            continue
        if current is not None:
            current.rows.append(row)
    return [sessions[session_id] for session_id in order]


# ------------------------------------------------------------------- definitions
def _parse_fields(text):
    spec = {}
    for name, raw in FIELD.findall(text):
        if name in LIST_FIELDS:
            # "," today; captures before 2026-11-15 used "|" (both are percent-encoded in values).
            spec[name] = [unquote(part) for part in re.split(r"[,|]", raw)] if raw else []
        else:
            spec[name] = unquote(raw)
    for name in ("combat", "optional"):
        if name in spec:
            spec[name] = spec[name] == "true"
    for name in ("repeats", "within"):
        if name in spec:
            spec[name] = float(spec[name]) if "." in spec[name] else int(spec[name])
    return spec


def parse_definitions(rows):
    """QUESTION rows -> {question id: {"title", "keys", "controls", "checks", ...}}."""
    questions = {}
    for row in rows:
        match = re.match(r"^QUESTION (DEF|CONTROL|CHECK) session=\S+ q=(\S+) ?(.*)$", row)
        if not match:
            continue
        kind, qid, rest = match.groups()
        question = questions.setdefault(qid, {"id": qid, "controls": [], "checks": []})
        fields = _parse_fields(rest)
        if kind == "DEF":
            question.update(fields)
        elif kind == "CONTROL":
            question["controls"].append(fields)
        else:
            question["checks"].append(fields)
    return questions


def registry_definitions():
    """Definitions from the current Questions.lua, for captures that predate the harness."""
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        return None
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        emitted = {}
        DebugCommands = {_Capture={ProbeLogEmit=function(row) emitted[#emitted+1]=row end}}
        LibStub = function() return DebugCommands end
    """)
    with open(REGISTRY_PATH, encoding="utf-8") as handle:
        lua.execute(handle.read())
    lua.execute("DebugCommands.EmitQuestionDefinitions('registry', DebugCommands.InstrumentedResearchQuestions())")
    emitted = lua.globals().emitted
    return parse_definitions([emitted[i] for i in range(1, len(emitted) + 1)])


# ---------------------------------------------------------------------- timeline
FIELD_PATTERN = re.compile(r"^[A-Za-z][\w.]*=\S*[^=\s]$")


def _contains(value, part):
    """A `name=value` pattern matches that whole field (count=0 never matches count=05);
    anything else (a prefix ending in `=`, text with spaces, plain:true) is a substring."""
    part = part.strip() if FIELD_PATTERN.match(part.strip()) else part
    if FIELD_PATTERN.match(part):
        return re.search(r"(?<![\w.])" + re.escape(part) + r"(?![\w.])", value) is not None
    return part in value


def _matches(value, has=None, lacks=None):
    if value is None:
        return False
    return all(_contains(value, part) for part in (has or [])) \
        and not any(_contains(value, part) for part in (lacks or []))


def _entered(value, previous, has=None, lacks=None):
    """value satisfies has/lacks and the previous value did not."""
    return _matches(value, has, lacks) and not _matches(previous, has, lacks)


def _is_combat(value):
    return "plain:true" in value


def build_timeline(session):
    """Ordered events: ("sample", t, epoch), ("key", t, epoch, key, value),
    ("mark", t, epoch, label), ("row", t, epoch, text)."""
    keys = None
    for row in session.rows:
        match = re.match(r"^DIAGNOSTICS KEYS session=\S+ keys=(\S*)", row)
        if match:
            keys = set(filter(None, match.group(1).split(",")))
    def is_key(match):
        if not match:
            return False
        if keys is not None:
            return match.group(1) in keys
        return bool(CELL_STATUS.match(match.group(2)))

    # Captures without a header epoch: infer it from the research epoch key. Keys of
    # one sample are written alphabetically, so apply the sample's epoch to the
    # whole sample instead of only to the keys sorted after it.
    block_epoch = {}
    if keys is None:
        current_header, inferred = None, None
        for index, row in enumerate(session.rows):
            if row.startswith("DIAG session="):
                current_header = index
                block_epoch[index] = inferred
                continue
            match = KEY_LINE.match(row)
            if current_header is not None and is_key(match) and match.group(1) == "signal.targetEpoch":
                number = re.search(r"(\d+)$", match.group(2))
                if number:
                    inferred = int(number.group(1))
                    block_epoch[current_header] = inferred

    events, t, epoch = [], 0.0, None
    relative, absolute, offsets = False, set(), []
    for index, row in enumerate(session.rows):
        if row.startswith("DIAG session="):
            fields = dict(FIELD.findall(row))
            if "t" in fields:
                t = float(fields["t"])
            elif "elapsed" in fields:
                t = float(fields["elapsed"])
                relative = True
            epoch = int(fields["epoch"]) if "epoch" in fields else block_epoch.get(index)
            events.append(("sample", t, epoch))
            continue
        key_line = KEY_LINE.match(row)
        if is_key(key_line):
            events.append(("key", t, epoch, key_line.group(1), key_line.group(2)))
            continue
        if row.startswith("MARK "):
            fields = dict(FIELD.findall(row))
            mark_epoch = int(fields["epoch"]) if fields.get("epoch", "").isdigit() else epoch
            if "t" in fields:
                absolute.add(len(events))
            events.append(("mark", float(fields.get("t", t)), mark_epoch, fields.get("label", "")))
            continue
        if row.startswith(("QUESTION ", "DIAGNOSTICS ")):
            continue
        stamped = T_FIELD.search(row)
        row_t = stamped or (LEADING_TIME.match(row) if row.startswith(TIMED_PREFIXES) else None)
        if row_t:
            absolute.add(len(events))
            if relative and stamped:
                offsets.append(float(stamped.group(1)) - t)
        events.append(("row", float(row_t.group(1)) if row_t else t, epoch, row))
    if relative and offsets:
        # Captures without game time in DIAG headers: rows written after a sample carry
        # game time, so the smallest gap estimates the session's clock offset (to
        # within one sample interval) and puts every event on the game clock.
        offset = min(offsets)
        events = [event if i in absolute else (event[0], event[1] + offset) + tuple(event[2:])
                  for i, event in enumerate(events)]
    return events


# ---------------------------------------------------------------------- scoring
def _combat_ok(spec, in_combat):
    wanted = spec.get("combat")
    return wanted is None or wanted == in_combat


def score_question(question, events):
    controls = {c["name"]: {"spec": c, "count": 0, "times": []} for c in question["controls"]}
    checks = []
    state, state_epoch = {}, {}
    in_combat = False
    marks = [(e[1], e[2], e[3]) for e in events if e[0] == "mark"]

    # Controls.
    for event in events:
        kind = event[0]
        if kind == "key":
            _, t, epoch, key, value = event
            if key == "combat":
                in_combat = _is_combat(value)
            previous, previous_epoch = state.get(key), state_epoch.get(key)
            for entry in controls.values():
                spec = entry["spec"]
                if spec.get("key") != key or not _combat_ok(spec, in_combat):
                    continue
                if "prevHas" in spec or "prevLacks" in spec:
                    if not (_matches(value, spec.get("has"), spec.get("lacks"))
                            and _matches(previous, spec.get("prevHas"), spec.get("prevLacks"))):
                        continue
                elif not _entered(value, previous, spec.get("has"), spec.get("lacks")):
                    continue
                if spec.get("epoch") == "same" and previous_epoch != epoch:
                    continue
                if spec.get("epoch") == "changed" and previous_epoch == epoch:
                    continue
                entry["count"] += 1
                entry["times"].append(t)
            state[key], state_epoch[key] = value, epoch
        elif kind == "row":
            _, t, _, text = event
            for entry in controls.values():
                spec = entry["spec"]
                if spec.get("row") and text.startswith(spec["row"]) and _combat_ok(spec, in_combat) \
                        and _matches(text, spec.get("has"), spec.get("lacks")):
                    entry["count"] += 1
                    entry["times"].append(t)
        elif kind == "mark":
            for entry in controls.values():
                if entry["spec"].get("mark") == event[3]:
                    entry["count"] += 1
                    entry["times"].append(event[1])

    for spec in question["checks"]:
        checks.append(CHECKS.get(spec.get("kind"), _unknown_check)(spec, events, marks))

    required = [e for e in controls.values() if not e["spec"].get("optional")]
    contradictions = sum(c.get("contradictions", 0) for c in checks)
    if contradictions:
        verdict = "CONTRADICTED"
    elif required and all(e["count"] >= e["spec"].get("repeats", DEFAULT_REPEATS) for e in required):
        verdict = "CONTROLS MET"
    else:
        verdict = "INCOMPLETE"
    return {
        "id": question["id"],
        "title": question.get("title", ""),
        "verdict": verdict,
        "controls": [{
            "name": name,
            "count": entry["count"],
            "repeats": entry["spec"].get("repeats", DEFAULT_REPEATS),
            "optional": bool(entry["spec"].get("optional")),
        } for name, entry in controls.items()],
        "checks": checks,
    }


def _replay(events, on_key, on_sample=None):
    """Drive a check across the timeline with current combat state."""
    in_combat = False
    for event in events:
        if event[0] == "key":
            if event[3] == "combat":
                in_combat = _is_combat(event[4])
            on_key(event, in_combat)
        elif event[0] == "sample" and on_sample:
            on_sample(event, in_combat)


def _check_latch(spec, events, marks):
    """A state reached on a target must not release on the same target in combat."""
    key, findings = spec.get("key"), []
    latched = {"epoch": None, "t": None}

    explained = 0
    explain_times = [e[1] for e in events if e[0] == "row" and spec.get("explainRow")
                     and e[3].startswith(spec["explainRow"])]
    window = float(spec.get("within", 3))

    def reset_marked(epoch, since, until):
        return any(label in spec.get("resetMarks", []) and mark_epoch == epoch and since <= mark_t <= until
                   for mark_t, mark_epoch, label in marks)

    def evidence_explains(until):
        return any(until - window <= row_t <= until for row_t in explain_times)

    def on_key(event, in_combat):
        nonlocal explained
        _, t, epoch, event_key, value = event
        if event_key == "combat" and not in_combat:
            latched["epoch"] = None
        if event_key != key:
            return
        if spec.get("combat") and not in_combat:
            latched["epoch"] = None
            return
        if latched["epoch"] is not None and latched["epoch"] != epoch:
            latched["epoch"] = None
        if _matches(value, spec.get("on")):
            if latched["epoch"] is None:
                latched["epoch"], latched["t"] = epoch, t
        elif latched["epoch"] is not None and _matches(value, spec.get("off")):
            if reset_marked(epoch, latched["t"], t):
                pass
            elif evidence_explains(t):
                explained += 1
            else:
                findings.append({"t": t, "epoch": epoch, "value": value})
            latched["epoch"] = None

    _replay(events, on_key)
    result = _finding(spec, findings)
    if spec.get("explainRow"):
        result["explained"] = explained
    return result


def _check_implies(spec, events, marks):
    """Where key has `has`, otherKey must not contain `forbid`. Evaluated at each
    recorded sample; persisting across two samples on one target is a contradiction,
    a single sample is reported as transient (keys of one sample update in order)."""
    state, findings, transient = {}, [], []
    streak = {"count": 0, "epoch": None, "t": None}

    def on_key(event, _):
        state[event[3]] = event[4]

    def on_sample(event, _):
        _, t, epoch = event
        holds = _matches(state.get(spec.get("key")), spec.get("has")) \
            and _matches(state.get(spec.get("otherKey")), spec.get("forbid"))
        if holds and streak["epoch"] == epoch and streak["count"] > 0:
            streak["count"] += 1
            if streak["count"] == 2:
                findings.append({"t": streak["t"], "epoch": epoch})
        elif holds:
            streak.update(count=1, epoch=epoch, t=t)
        else:
            if streak["count"] == 1:
                transient.append({"t": streak["t"], "epoch": streak["epoch"]})
            streak.update(count=0, epoch=None, t=None)

    _replay(events, on_key, on_sample)
    result = _finding(spec, findings)
    result["transient"] = len(transient)
    return result


def _check_before(spec, events, marks):
    """Entering `key`/`has` on a target without having seen `firstKey`/`firstHas` first."""
    seen, state, findings = set(), {}, []

    def on_key(event, _):
        _, t, epoch, key, value = event
        previous = state.get(key)
        state[key] = value
        if key == spec.get("firstKey") and _matches(value, spec.get("firstHas")):
            seen.add(epoch)
        if key == spec.get("key") and previous is not None and epoch not in seen \
                and _entered(value, previous, spec.get("has")):
            findings.append({"t": t, "epoch": epoch})

    _replay(events, on_key)
    return _finding(spec, findings)


def _check_share(spec, events, marks):
    """Time share (between recorded samples) where `key` satisfies has/lacks."""
    state, totals = {}, {"eligible": 0.0, "holds": 0.0}
    last = {"t": None, "combat": False}

    def account(t):
        if last["t"] is not None and t >= last["t"] and _combat_ok(spec, last["combat"]) \
                and state.get(spec.get("key")) is not None:
            span = t - last["t"]
            totals["eligible"] += span
            if _matches(state.get(spec.get("key")), spec.get("has"), spec.get("lacks")):
                totals["holds"] += span

    def on_key(event, in_combat):
        state[event[3]] = event[4]
        last["combat"] = in_combat

    def on_sample(event, in_combat):
        account(event[1])
        last["t"], last["combat"] = event[1], in_combat

    _replay(events, on_key, on_sample)
    share = totals["holds"] / totals["eligible"] if totals["eligible"] else None
    return {"name": spec.get("name"), "kind": "share", "seconds": round(totals["eligible"], 1),
            "share": None if share is None else round(share, 3)}


def _combat_periods(events):
    """[(start, end)] of combat from the `combat` key; an open period ends at the last event."""
    periods, start = [], None
    for event in events:
        if event[0] == "key" and event[3] == "combat":
            fighting = _is_combat(event[4])
            if fighting and start is None:
                start = event[1]
            elif not fighting and start is not None:
                periods.append((start, event[1]))
                start = None
    if start is not None:
        periods.append((start, events[-1][1] if events else start))
    return periods


def _check_after_mark(spec, events, marks):
    """After each mark, does the state (a key value or a row) appear in the mark's window?
    The window is `within` seconds after the mark, or with scope=combat the fight containing
    the mark or the next to start within MARK_FIGHT_LOOKAHEAD seconds. A state already
    present when the window opens is reported as `already`, not as a hit."""
    within = float(spec.get("within", 2))
    periods = _combat_periods(events) if spec.get("scope") == "combat" else None
    key, row, has, lacks = spec.get("key"), spec.get("row"), spec.get("has"), spec.get("lacks")
    outcomes = {"hits": 0, "already": 0, "misses": 0}
    for mark_t, _, label in marks:
        if label != spec.get("mark"):
            continue
        if periods is None:
            start, end = mark_t, mark_t + within
        else:
            fight = next((p for p in periods if p[0] - MARK_FIGHT_LOOKAHEAD <= mark_t <= p[1]), None)
            if fight is None:
                outcomes["misses"] += 1
                continue
            start, end = max(fight[0], mark_t - MARK_FIGHT_LOOKAHEAD), fight[1]
        state = None
        if key:
            for event in events:
                if event[0] == "key" and event[3] == key and event[1] <= start:
                    state = event[4]
        if key and _matches(state, has, lacks):
            outcomes["already"] += 1
        elif any(start < event[1] <= end and (
                (event[0] == "key" and event[3] == key and _matches(event[4], has, lacks))
                or (event[0] == "row" and row and event[3].startswith(row) and _matches(event[3], has, lacks)))
                for event in events):
            outcomes["hits"] += 1
        else:
            outcomes["misses"] += 1
    return dict({"name": spec.get("name"), "kind": "afterMark"}, **outcomes)


def _check_followed_by(spec, events, marks):
    """After `key` enters has/lacks (optionally only in or out of combat), does a row
    starting with `row` and containing `rowHas` follow within `within` seconds? Each
    entry followed by such a row is a finding: independent evidence against the state."""
    within = float(spec.get("within", 2))
    entries, state = [], {}

    def on_key(event, in_combat):
        _, t, epoch, key, value = event
        previous = state.get(key)
        state[key] = value
        if key != spec.get("key") or not _combat_ok(spec, in_combat):
            return
        if _entered(value, previous, spec.get("has"), spec.get("lacks")):
            entries.append((t, epoch))

    _replay(events, on_key)
    rows = [(e[1], e[3]) for e in events if e[0] == "row" and spec.get("row") and e[3].startswith(spec["row"])
            and _matches(e[3], spec.get("rowHas"))]
    findings = []
    for t, epoch in entries:
        if any(t <= row_t <= t + within for row_t, _ in rows):
            findings.append({"t": t, "epoch": epoch})
    result = _finding(spec, findings)
    result["entries"] = len(entries)
    return result


def _matching_rows(spec, events):
    """Row texts starting with spec's row prefix and satisfying its has/lacks."""
    for event in events:
        if event[0] == "row" and event[3].startswith(spec.get("row", "")) \
                and _matches(event[3], spec.get("has"), spec.get("lacks")):
            yield event[3]


def _check_tally(spec, events, marks):
    counts = {}
    pattern = re.compile(r"\b" + re.escape(spec.get("field", "")) + r"=(\S+)")
    for text in _matching_rows(spec, events):
        match = pattern.search(text)
        if match:
            counts[match.group(1)] = counts.get(match.group(1), 0) + 1
    return {"name": spec.get("name"), "kind": "tally", "counts": counts}


def _check_stats(spec, events, marks):
    """Numeric summary of one field over the rows matching row/has/lacks (timing and
    resource deltas a pass/fail check cannot express); non-numeric cells are skipped."""
    pattern = re.compile(r"(?<![\w.])" + re.escape(spec.get("field", "")) + r"=(-?\d+(?:\.\d+)?)(?![\w.])")
    values = []
    for text in _matching_rows(spec, events):
        match = pattern.search(text)
        if match:
            values.append(float(match.group(1)))
    values.sort()
    result = {"name": spec.get("name"), "kind": "stats", "n": len(values)}
    if values:
        middle = len(values) // 2
        median = values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2
        result.update(min=round(values[0], 3), median=round(median, 3), max=round(values[-1], 3))
    return result


def _check_ratio(spec, events, marks):
    """Rows matching row/has per row matching row/per (flips per press): a rate a
    count of either alone cannot show. None when the denominator never matched."""
    numerator = sum(1 for _ in _matching_rows(spec, events))
    denominator = sum(1 for _ in _matching_rows(dict(spec, has=spec.get("per"), lacks=spec.get("perLacks")), events))
    ratio = None if denominator == 0 else round(numerator / denominator, 3)
    return {"name": spec.get("name"), "kind": "ratio", "numerator": numerator,
            "denominator": denominator, "ratio": ratio}


def _unknown_check(spec, events, marks):
    return {"name": spec.get("name"), "kind": spec.get("kind"), "error": "unknown check kind"}


def _finding(spec, findings):
    severity = spec.get("severity", "suspicious")
    result = {"name": spec.get("name"), "kind": spec.get("kind"), "severity": severity,
              "findings": len(findings), "examples": findings[:3]}
    if spec.get("note"):
        result["note"] = spec["note"]
    if severity == "contradiction":
        result["contradictions"] = len(findings)
    return result


CHECKS = {
    "latch": _check_latch,
    "implies": _check_implies,
    "before": _check_before,
    "share": _check_share,
    "afterMark": _check_after_mark,
    "followedBy": _check_followed_by,
    "tally": _check_tally,
    "stats": _check_stats,
    "ratio": _check_ratio,
}


# ----------------------------------------------------------------- fingerprint
STATUSES = ("plain", "secret", "err", "nil", "unknown", "unavailable")
BAD_CLASSES = {"secret", "err", "inner:secret", "inner:err"}
GOOD_CLASSES = {"plain", "inner:plain"}
STATUS_FIELD = re.compile(r"([A-Za-z][A-Za-z0-9_.]*)=(" + "|".join(STATUSES) + r"):")
LEAD_STATUS = re.compile(r"^(" + "|".join(STATUSES) + r"):")
BRACED = re.compile(r"([A-Za-z][A-Za-z0-9_.]*)\{([^{}]*)\}")
ERROR_ROWS = ("PROBE ERROR", "FOCUS SAMPLE ERROR", "AUDIT SAMPLE ERROR", "DIAGNOSTICS ERROR",
              "RANGE OBSERVER ERROR")
FINGERPRINT_VERSION = 1
LEVEL_ORDER = {"CHANGED": 0, "LOST": 1, "NOT SEEN": 2, "INFO": 3}


@functools.lru_cache(maxsize=None)   # change-only logs repeat a handful of values
def value_classes(value):
    """Qualitative read classes of one recorded cell: its outer status and, for
    research cells that wrap their own classification, the inner status."""
    match = CELL_STATUS.match(value)
    if not match:
        return {"raw"}
    classes = {match.group(1)}
    if match.group(1) == "plain":
        inner = LEAD_STATUS.match(value[len("plain:"):])
        if inner:
            classes.add("inner:" + inner.group(1))
    return classes


@functools.lru_cache(maxsize=None)
def field_statuses(value):
    """(field, status) pairs inside a cell, braced groups qualified by their parent."""
    found = set()
    for parent, inner in BRACED.findall(value):
        lead = LEAD_STATUS.match(inner)
        if lead:
            found.add((parent, lead.group(1)))
        for name, status in STATUS_FIELD.findall(inner):
            found.add((parent + "." + name, status))
    for name, status in STATUS_FIELD.findall(BRACED.sub("", value)):
        found.add((name, status))
    return found


def row_kind(text):
    match = re.match(r"^(?:\d+\.\d+ )?([A-Z][A-Z_]+)(?: ([A-Za-z][A-Za-z_]*))?", text)
    if not match:
        return None
    if match.group(1) in ("EVIDENCE", "SIGNAL", "PRIORITY") and match.group(2):
        return match.group(1) + " " + match.group(2)
    return match.group(1)


def fingerprint(session, events, questions):
    """Qualitative behavior of one session, comparable across sessions and builds."""
    keys, rows, latest = {}, {}, {}
    in_combat, last_t, combat_seconds, ooc_seconds = False, None, 0.0, 0.0
    epochs = set()
    for event in events:
        kind = event[0]
        if kind == "sample":
            if last_t is not None and event[1] >= last_t:
                if in_combat:
                    combat_seconds += event[1] - last_t
                else:
                    ooc_seconds += event[1] - last_t
            last_t = event[1]
            if event[2] is not None:
                epochs.add(event[2])
        elif kind == "key":
            _, _, _, key, value = event
            if key == "combat":
                in_combat = "plain:true" in value
            latest[key] = value
            bucket = keys.setdefault(key, {}).setdefault("combat" if in_combat else "ooc",
                                                         {"changes": 0, "classes": {}, "fields": {}})
            bucket["changes"] += 1
            for cls in value_classes(value):
                bucket["classes"][cls] = bucket["classes"].get(cls, 0) + 1
            for name, status in field_statuses(value):
                label = name + "=" + status
                bucket["fields"][label] = bucket["fields"].get(label, 0) + 1
        elif kind == "row":
            label = row_kind(event[3])
            if label:
                rows[label] = rows.get(label, 0) + 1
    errors = sum(1 for row in session.rows if row.startswith(ERROR_ROWS))
    # Constant keys are written once, in the BASELINE sample; without it, absence
    # of a key means the rolling log evicted it, not that it stopped being read.
    complete = any(row.startswith("DIAG session=") and " BASELINE " in row for row in session.rows)
    failures = 0
    if session.stop_row:
        match = re.search(r"\bfailures=(\d+)", session.stop_row)
        failures = int(match.group(1)) if match else 0

    def plain(key):
        value = latest.get(key)
        if value and value.startswith("plain:"):
            return value[len("plain:"):]
        return value

    summary = {}
    for question in questions:
        summary[question["id"]] = {
            "verdict": question["verdict"],
            "controls": {c["name"]: c["count"] for c in question["controls"]},
            "contradictions": {c["name"]: c.get("contradictions", 0) for c in question["checks"]
                               if "contradictions" in c},
            "tallies": {c["name"]: c["counts"] for c in question["checks"] if c.get("kind") == "tally"},
        }
    return {
        "version": FINGERPRINT_VERSION,
        "session": session.id,
        "build": plain("build"),
        "addonVersion": plain("addonVersion"),
        "class": plain("class"),
        "level": plain("level"),
        "research": plain("researchAvailable"),
        "complete": complete,
        "context": {"combatSeconds": round(combat_seconds, 1), "oocSeconds": round(ooc_seconds, 1),
                    "targets": len(epochs), "errors": errors, "failures": failures},
        "keys": keys,
        "rows": rows,
        "questions": summary,
    }


def _fields_by_name(fields):
    grouped = {}
    for label in fields:
        name, status = label.rsplit("=", 1)
        grouped.setdefault(name, set()).add(status)
    return grouped


def _shares(counts):
    total = sum(counts.values())
    if not total:
        return {}
    return {value: count / total for value, count in counts.items()}


def _compare_bucket(key, bucket, base_b, cur_b, out):
    for cls in sorted(set(cur_b["classes"]) - set(base_b["classes"])):
        level = "CHANGED" if cls in BAD_CLASSES else "INFO"
        out.append((level, f"{key} [{bucket}]: now reads {cls} (baseline: never)"))
    for cls in sorted(set(base_b["classes"]) - set(cur_b["classes"])):
        level = "LOST" if cls in GOOD_CLASSES else "INFO"
        out.append((level, f"{key} [{bucket}]: no {cls} reads (baseline: {base_b['classes'][cls]})"))
    base_fields = _fields_by_name(base_b["fields"])
    cur_fields = _fields_by_name(cur_b["fields"])
    for name in sorted(set(base_fields) & set(cur_fields)):
        for status in sorted(cur_fields[name] - base_fields[name]):
            level = "CHANGED" if status in ("secret", "err") else "INFO"
            out.append((level, f"{key} [{bucket}] {name}: now {status} (baseline: never)"))
        for status in sorted(base_fields[name] - cur_fields[name]):
            level = "LOST" if status == "plain" else "INFO"
            out.append((level, f"{key} [{bucket}] {name}: no {status} reads now"))


def _compare_questions(baseline, current, combat_present, out):
    for qid, base_q in sorted(baseline.get("questions", {}).items()):
        cur_q = current.get("questions", {}).get(qid)
        if cur_q is None:
            continue
        if base_q["verdict"] != cur_q["verdict"]:
            level = "CHANGED" if cur_q["verdict"] == "CONTRADICTED" else "INFO"
            out.append((level, f"[{qid}] verdict {base_q['verdict']} -> {cur_q['verdict']}"))
        for name, count in sorted(cur_q.get("contradictions", {}).items()):
            if count and not base_q.get("contradictions", {}).get(name):
                out.append(("CHANGED", f"[{qid}] {name}: {count} new contradiction(s)"))
        if combat_present:
            for name, count in sorted(base_q.get("controls", {}).items()):
                if count and not cur_q.get("controls", {}).get(name):
                    out.append(("NOT SEEN", f"[{qid}] control {name} (baseline: {count})"))
        for name, counts in sorted(cur_q.get("tallies", {}).items()):
            base_shares, cur_shares = _shares(base_q.get("tallies", {}).get(name, {})), _shares(counts)
            if not base_shares or not cur_shares:
                continue
            for value, share in sorted(cur_shares.items()):
                if share >= 0.1 and base_shares.get(value, 0) == 0:
                    out.append(("CHANGED", f"[{qid}] {name}: {value} now {share:.0%} (baseline: none)"))
            for value, share in sorted(base_shares.items()):
                if share >= 0.1 and cur_shares.get(value, 0) == 0:
                    out.append(("CHANGED", f"[{qid}] {name}: {value} gone (baseline: {share:.0%})"))


def compare(baseline, current, min_combat=30.0):
    """Differences that indicate changed behavior, most significant first, as
    (level, text). Levels: CHANGED, LOST, NOT SEEN, INFO."""
    out = []
    for field, label in (("build", "client build"), ("addonVersion", "JustAC version"),
                         ("class", "class"), ("research", "Research companion loaded")):
        if baseline.get(field) != current.get(field):
            out.append(("INFO", f"{label}: {baseline.get(field)} -> {current.get(field)}"))
    base_ctx, cur_ctx = baseline["context"], current["context"]
    combat_present = cur_ctx["combatSeconds"] >= min_combat
    if not combat_present:
        out.append(("INFO", f"only {cur_ctx['combatSeconds']}s in combat: combat behavior not compared"
                    f" (needs {min_combat:.0f}s)"))
    if cur_ctx["errors"] > base_ctx.get("errors", 0):
        out.append(("CHANGED", f"probe error rows: {base_ctx.get('errors', 0)} -> {cur_ctx['errors']}"))
    if cur_ctx["failures"] > base_ctx.get("failures", 0):
        out.append(("CHANGED", f"sampler read failures: {base_ctx.get('failures', 0)} -> {cur_ctx['failures']}"))
    presence = current.get("complete") and baseline.get("complete")
    if not presence:
        out.append(("INFO", "baseline sample missing (evicted or older capture): key presence not compared"))
    for key in sorted(set(baseline["keys"]) | set(current["keys"])):
        base_key, cur_key = baseline["keys"].get(key), current["keys"].get(key)
        if cur_key is None or base_key is None:
            if presence and cur_key is None:
                out.append(("LOST", f"{key}: no longer recorded"))
            elif presence:
                out.append(("INFO", f"{key}: newly recorded"))
            continue
        for bucket in ("combat", "ooc"):
            if bucket == "combat" and not combat_present:
                continue
            base_b, cur_b = base_key.get(bucket), cur_key.get(bucket)
            if base_b and cur_b:
                _compare_bucket(key, bucket, base_b, cur_b, out)
    _compare_questions(baseline, current, combat_present, out)
    if combat_present:
        for kind, count in sorted(baseline.get("rows", {}).items()):
            if count and not current.get("rows", {}).get(kind):
                out.append(("NOT SEEN", f"row kind {kind} (baseline: {count})"))
    return sorted(out, key=lambda item: LEVEL_ORDER[item[0]])


def baseline_path(directory, client):
    return os.path.join(directory, re.sub(r"[^A-Za-z0-9_.-]", "_", client) + ".json")


def load_baseline(directory, client):
    path = baseline_path(directory, client)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("version") != FINGERPRINT_VERSION:
        return None
    return data


def save_baseline(directory, client, data):
    """Write the new baseline; the one it replaces is kept beside it as .prev.json."""
    os.makedirs(directory, exist_ok=True)
    path = baseline_path(directory, client)
    if os.path.exists(path):
        os.replace(path, path[:-len(".json")] + ".prev.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=1, sort_keys=True)
    return path


# ----------------------------------------------------------------------- report
def analyze_session(session, question_filter=None, fallback=None):
    definitions = parse_definitions(session.rows)
    source = "capture"
    if not definitions:
        definitions, source = fallback() if fallback else None, "registry (capture predates harness)"
    events = build_timeline(session)
    marks = sum(1 for event in events if event[0] == "mark")
    mode = session.mode
    result = {
        "session": session.id,
        "question": session.question or "all",
        "mode": mode,
        "started": session.started,
        "stopped": session.stopped,
        "marks": marks,
        "events": len(events),
        "definitions": source if definitions else "none",
        "questions": [],
        "comparison": None,
    }
    for qid, question in (definitions or {}).items():
        if question_filter and qid != question_filter:
            continue
        result["questions"].append(score_question(question, events))
    result["fingerprint"] = fingerprint(session, events, result["questions"])
    return result


def _session_time(session_id):
    match = re.match(r"^(\d{8}-\d{6})", session_id)
    if not match:
        return "unknown time"
    return time.strftime("%Y-%m-%d %H:%M:%S", time.strptime(match.group(1), "%Y%m%d-%H%M%S"))


def _format_question_details(question):
    lines = [f"   [{question['id']}] {question['verdict']}: {question['title']}"]
    for control in question["controls"]:
        status = "met" if control["count"] >= control["repeats"] else "missing"
        if control["optional"]:
            status += ", optional"
        lines.append(f"      control {control['name']}: {control['count']}/{control['repeats']} ({status})")
    for check in question["checks"]:
        lines.append("      check " + _format_check(check))
    return lines


def format_summary(report, details=False, info=False):
    """One screen per client: what changed since the baseline first."""
    lines = [f"== {report['client']}: {report['path']}",
             f"   file modified {report['modified']}; rolling log rows discarded (all sessions):"
             f" {report['dropped']}"]
    if not report["sessions"]:
        lines.append("   no diagnostic sessions in probeLog")
        return "\n".join(lines)
    baseline = report.get("baseline")
    for result in report["sessions"]:
        fp = result["fingerprint"]
        ctx = fp["context"]
        lines.append(f"-- session {result['session']} ({_session_time(result['session'])}) mode={result['mode']}"
                     f" build={fp['build']} JustAC={fp['addonVersion']} {fp['class']} {fp['level']}")
        lines.append(f"   combat {ctx['combatSeconds']}s, out of combat {ctx['oocSeconds']}s,"
                     f" targets {ctx['targets']}, marks {result['marks']}, definitions={result['definitions']}")
        if not result["stopped"]:
            lines.append("   WARNING: no STOP row. Run /jac inspect stop, then /reload, before analyzing.")
        if result["comparison"] is None:
            if baseline is None:
                lines.append("   no baseline yet: review this capture, then rerun with --accept to make it the baseline")
        else:
            lines.append(f"   compared with baseline {baseline['session']} ({_session_time(baseline['session'])})"
                         f" build={baseline['build']} JustAC={baseline['addonVersion']}")
            shown = [item for item in result["comparison"] if info or item[0] != "INFO"]
            if not shown:
                lines.append("   no behavior changes detected")
            for level, text in shown:
                lines.append(f"   {level:<8} {text}")
            hidden = len(result["comparison"]) - len(shown)
            if hidden:
                lines.append(f"   ({hidden} informational differences; --info lists them)")
        verdicts = []
        for question in result["questions"]:
            text = f"{question['id']}={question['verdict']}"
            missing = [c["name"] for c in question["controls"]
                       if not c["optional"] and c["count"] < c["repeats"]]
            if missing and question["verdict"] == "INCOMPLETE":
                text += f" (untested: {', '.join(missing)})"
            verdicts.append(text)
        if verdicts:
            lines.append("   questions: " + "; ".join(verdicts))
        if details:
            for question in result["questions"]:
                lines.extend(_format_question_details(question))
    return "\n".join(lines)


def _format_check(check):
    kind = check.get("kind")
    if "error" in check:
        return f"{check['name']}: {check['error']} ({kind})"
    if kind == "share":
        share = "n/a" if check["share"] is None else f"{check['share'] * 100:.1f}%"
        return f"{check['name']}: {share} of {check['seconds']}s eligible"
    if kind == "afterMark":
        return f"{check['name']}: hit={check['hits']} already={check['already']} miss={check['misses']}"
    if kind == "tally":
        counts = ", ".join(f"{k}={v}" for k, v in sorted(check["counts"].items())) or "none"
        return f"{check['name']}: {counts}"
    if kind == "ratio":
        ratio = "n/a" if check["ratio"] is None else check["ratio"]
        return f"{check['name']}: {ratio} ({check['numerator']} per {check['denominator']})"
    if kind == "stats":
        if not check["n"]:
            return f"{check['name']}: no values"
        return f"{check['name']}: n={check['n']} min={check['min']} median={check['median']} max={check['max']}"
    text = f"{check['name']}: {check['findings']} {check['severity']}"
    if "entries" in check:
        text += f" of {check['entries']} entries"
    if "explained" in check:
        text += f", {check['explained']} explained by evidence"
    if "transient" in check:
        text += f", {check['transient']} transient"
    if check.get("examples"):
        text += " e.g. " + "; ".join(f"t={e['t']} epoch={e['epoch']}" for e in check["examples"])
    if check.get("note"):
        text += f" ({check['note']})"
    return text


def client_label(path):
    for part in os.path.normpath(path).split(os.sep):
        if re.match(r"^_[A-Za-z0-9]+_$", part):
            return part
    return "custom"


def default_paths(wow_root):
    pattern = os.path.join(wow_root, "_*_", "WTF", "Account", "*", "SavedVariables", "JustAC.lua")
    return [(client_label(path), path) for path in sorted(glob.glob(pattern))]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Compare JustAC diagnostic captures with a saved baseline.")
    parser.add_argument("paths", nargs="*", help="SavedVariables JustAC.lua files (default: every client)")
    parser.add_argument("--wow-root", default=DEFAULT_WOW_ROOT)
    parser.add_argument("--baseline-dir", default=os.path.join(ROOT, ".probe-baselines"))
    parser.add_argument("--accept", action="store_true",
                        help="save the latest analyzed session as each client's baseline")
    parser.add_argument("--session", help="analyze this session id")
    parser.add_argument("--all", action="store_true", help="analyze every session, not just the latest")
    parser.add_argument("--question", help="only this question id (no baseline comparison)")
    parser.add_argument("--details", action="store_true", help="list every control and check")
    parser.add_argument("--info", action="store_true", help="also list informational differences")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    targets = [(client_label(p), p) for p in args.paths] or default_paths(args.wow_root)
    if not targets:
        print(f"no SavedVariables found under {args.wow_root}", file=sys.stderr)
        return 1
    cache = {}

    def fallback():
        if "registry" not in cache:
            cache["registry"] = registry_definitions()
        return cache["registry"]

    reports = []
    for label, path in targets:
        rows, dropped = read_saved_variables(path)
        sessions = split_sessions(rows)
        if args.session:
            sessions = [s for s in sessions if s.id == args.session]
        elif not args.all:
            sessions = sessions[-1:]
        baseline = load_baseline(args.baseline_dir, label)
        results = []
        for session in sessions:
            result = analyze_session(session, args.question, fallback)
            if baseline and not args.question and baseline.get("session") != session.id:
                result["comparison"] = compare(baseline, result["fingerprint"])
            results.append(result)
        report = {"client": label, "path": path, "dropped": dropped, "baseline": baseline,
                  "modified": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(path))),
                  "sessions": results}
        if args.accept and results and not args.question:
            latest = results[-1]
            if not latest["stopped"]:
                report["accepted"] = "refused: the session has no STOP row"
            elif not latest["fingerprint"]["complete"]:
                report["accepted"] = "refused: the session's baseline sample was evicted from the log"
            else:
                report["accepted"] = save_baseline(args.baseline_dir, label, latest["fingerprint"])
        reports.append(report)
    if args.json:
        print(json.dumps(reports, indent=2, default=str))
        return 0
    print("\n\n".join(format_summary(r, args.details, args.info) for r in reports))
    for report in reports:
        if "accepted" in report:
            print(f"\n{report['client']} baseline: {report['accepted']}")
    print("\nCHANGED and LOST lines differ from the baseline. NOT SEEN means a previously observed"
          " control or row did not occur this time (possibly untested).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
