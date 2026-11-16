# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Research question registry validity and offline capture scoring.
import os
import sys
import tempfile
from pathlib import Path

from lupa.lua51 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze_probe as ap  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
QUESTIONS = ROOT / "Debug" / "Research" / "Questions.lua"


def registry():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        DebugCommands = {_Capture={ProbeLogEmit=function() end}}
        LibStub = function() return DebugCommands end
    """)
    lua.execute(QUESTIONS.read_text(encoding="utf-8"))
    dc = lua.globals().DebugCommands

    def plain(value):
        if hasattr(value, "items"):
            items = dict(value.items())
            if items and all(isinstance(k, int) for k in items):
                return [plain(items[i]) for i in range(1, len(items) + 1)]
            return {k: plain(v) for k, v in items.items()}
        return value

    return plain(dc.RESEARCH_QUESTIONS), plain(dc.RESEARCH_CORE_KEYS)


def test_registry_is_valid():
    questions, core = registry()
    ids = [q["id"] for q in questions]
    assert len(ids) == len(set(ids)), "question ids are unique"
    audit_rows = {"dot": "DOT "}
    for q in questions:
        assert q.get("title"), q["id"]
        if q.get("needs"):
            assert not q.get("controls"), f"{q['id']}: uninstrumented questions define no controls"
            continue
        keys = set(q["keys"]) | set(core)
        marks = set(q.get("marks", []))
        rows = {audit_rows[name] for name in q.get("audit", [])}
        if q.get("rows"):
            rows.add("EVIDENCE ")
            rows |= {"EVIDENCE " + kind + " " for kind in q["rows"]}
        controls = q["controls"]
        assert any(not c.get("optional") for c in controls), f"{q['id']}: needs a required control"
        names = [c["name"] for c in controls] + [c["name"] for c in q.get("checks", [])]
        assert len(names) == len(set(names)), f"{q['id']}: control/check names are unique"
        for c in controls:
            subjects = [field for field in ("key", "row", "mark") if c.get(field)]
            assert len(subjects) == 1, f"{q['id']}.{c['name']}: exactly one of key/row/mark"
            if c.get("key"):
                assert c["key"] in keys, f"{q['id']}.{c['name']}: key not captured"
                assert c.get("has") or c.get("lacks"), f"{q['id']}.{c['name']}: needs a state"
            if c.get("row"):
                assert c["row"] in rows, f"{q['id']}.{c['name']}: row needs its audit sampler"
            if c.get("mark"):
                assert c["mark"] in marks, f"{q['id']}.{c['name']}: mark not declared"
            assert c.get("epoch") in (None, "same", "changed")
        for check in q.get("checks", []):
            assert check["kind"] in ap.CHECKS, f"{q['id']}.{check['name']}: unknown kind"
            for field in ("key", "otherKey", "firstKey"):
                if check.get(field):
                    assert check[field] in keys, f"{q['id']}.{check['name']}: {field} not captured"
            if check.get("row"):
                assert check["row"] in rows, f"{q['id']}.{check['name']}: row needs its audit sampler"
            for label in [check.get("mark")] + list(check.get("resetMarks", [])):
                if label:
                    assert label in marks, f"{q['id']}.{check['name']}: mark not declared"
            assert check.get("severity") in (None, "contradiction", "suspicious")
            assert check.get("scope") in (None, "combat"), f"{q['id']}.{check['name']}: unknown scope"
            if check.get("scope"):
                assert check["kind"] == "afterMark", f"{q['id']}.{check['name']}: scope is for marks"
        for label in marks:
            assert label == label.lower() and " " not in label and len(label) <= 40


def saved_variables(rows, dropped=0):
    escaped = [row.replace("\\", "\\\\").replace('"', '\\"') for row in rows]
    body = "\n".join(f'"{row}", -- [{i}]' for i, row in enumerate(escaped, 1))
    text = ("JustACGlobal = {\n" + '["probeLog"] = {\n' + body + "\n},\n"
            + f'["probeLogDropped"] = {dropped},\n' + "}\n")
    handle = tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return handle.name


HEADER = ("QUESTION DEF session=S1 q=t title=Test keys=queueContext,health rows= audit= marks=heal,cc\n"
          "QUESTION CONTROL session=S1 q=t name=enter key=queueContext prevHas=execute=false has=execute=true combat=true\n"
          "QUESTION CONTROL session=S1 q=t name=swap key=queueContext prevHas=execute=true has=execute=false epoch=changed repeats=1\n"
          "QUESTION CONTROL session=S1 q=t name=healMark mark=heal repeats=1 optional=true\n"
          "QUESTION CONTROL session=S1 q=t name=space key=health lacks=x%20y repeats=1\n"
          "QUESTION CHECK session=S1 q=t name=latch kind=latch key=queueContext on=execute=true off=execute=false resetMarks=heal combat=true severity=contradiction\n"
          "QUESTION CHECK session=S1 q=t name=implies kind=implies key=queueContext has=execute=true otherKey=health forbid=high severity=contradiction\n"
          "QUESTION CHECK session=S1 q=t name=before kind=before firstKey=health firstHas=low key=queueContext has=execute=true\n"
          "QUESTION CHECK session=S1 q=t name=share kind=share key=health has=low combat=true\n"
          "QUESTION CHECK session=S1 q=t name=after kind=afterMark mark=cc key=health has=low within=2\n"
          "QUESTION CHECK session=S1 q=t name=tally kind=tally row=DOT%20 field=source").splitlines()


def sample(t, epoch, **keys):
    rows = [f"DIAG session=S1 sample=1 elapsed={t:.2f} t={t:.3f} epoch={epoch} SAMPLE pull=1"]
    rows += [f"  {key}={value}" for key, value in keys.items()]
    return rows


def capture(body, stop=True):
    rows = ["older row", "DIAGNOSTICS START session=S1 t=0.000 question=t limit=1200",
            "DIAGNOSTICS KEYS session=S1 keys=combat,queueContext,health"] + HEADER + body
    if stop:
        rows.append("DIAGNOSTICS STOP session=S1 samples=1 changes=1 pulls=1 failures=0 t=99.000 marks=1")
    return rows


def score(body, stop=True):
    path = saved_variables(capture(body, stop), dropped=7)
    try:
        rows, dropped = ap.read_saved_variables(path)
    finally:
        os.unlink(path)
    assert dropped == 7
    sessions = ap.split_sessions(rows)
    assert [s.id for s in sessions] == ["S1"] and sessions[0].question == "t"
    result = ap.analyze_session(sessions[0])
    assert result["definitions"] == "capture" and result["stopped"] == stop
    question = result["questions"][0]
    return question, {c["name"]: c for c in question["controls"]}, {c["name"]: c for c in question["checks"]}


def test_clean_capture_meets_controls():
    body = []
    body += sample(1, 1, combat="plain:true", queueContext="plain:execute=false", health="plain:high")
    body += sample(2, 1, health="plain:low")
    body += sample(3, 1, queueContext="plain:execute=true")
    body += sample(4, 2, queueContext="plain:execute=false", health="plain:high")
    body += sample(5, 2, health="plain:low")
    body += sample(6, 2, queueContext="plain:execute=true")
    body += ["MARK session=S1 t=6.500 epoch=2 combat=true label=cc"]
    body += sample(7, 2, health='plain:low "quoted" \\ path')
    body += ["DOT 7.5 1130 active=true source=cooldown-manager", "DOT 7.6 1130 active=false source=estimate"]
    question, controls, checks = score(body)
    assert controls["enter"]["count"] == 2
    assert controls["swap"]["count"] == 1, "a release on a new target is a swap, not a contradiction"
    assert controls["space"]["count"] == 1, "percent-encoded spaces decode"
    assert checks["latch"]["contradictions"] == 0
    assert checks["implies"]["contradictions"] == 0
    assert checks["before"]["findings"] == 0
    assert checks["after"]["already"] == 1, "a state present at the mark is reported, not a hit"
    assert checks["tally"]["counts"] == {"cooldown-manager": 1, "estimate": 1}
    assert 0.5 < checks["share"]["share"] < 0.9
    assert question["verdict"] == "CONTROLS MET"


def test_contradictions_and_reset_marks():
    body = []
    body += sample(1, 1, combat="plain:true", queueContext="plain:execute=false", health="plain:high")
    body += sample(2, 1, queueContext="plain:execute=true")
    body += sample(3, 1, health="plain:low")
    body += sample(4, 1, queueContext="plain:execute=false")
    body += sample(5, 1, queueContext="plain:execute=true", health="plain:high")
    body += sample(6, 1, combat="plain:true")
    body += ["MARK session=S1 t=6.500 epoch=1 combat=true label=heal"]
    body += sample(7, 1, queueContext="plain:execute=false")
    body += ["MARK session=S1 t=8.000 epoch=1 combat=true label=cc"]
    body += sample(9, 1, health="plain:low")
    body += ["MARK session=S1 t=20.000 epoch=1 combat=true label=cc"]
    question, controls, checks = score(body, stop=False)
    assert checks["latch"]["contradictions"] == 1, "only the unmarked release on one target counts"
    assert checks["implies"]["contradictions"] == 1, "high health persisting with execute is contradictory"
    assert checks["implies"]["transient"] == 1, "execute before the health key updates is transient"
    assert checks["before"]["findings"] == 1
    assert checks["after"]["hits"] == 1 and checks["after"]["already"] == 1
    assert controls["healMark"]["count"] == 1
    assert question["verdict"] == "CONTRADICTED"


def test_combat_exit_releases_latches():
    body = []
    body += sample(1, 1, combat="plain:true", queueContext="plain:execute=false", health="plain:low")
    body += sample(2, 1, queueContext="plain:execute=true")
    body += sample(3, 1, combat="plain:false")
    body += sample(4, 1, queueContext="plain:execute=false")
    question, controls, checks = score(body)
    assert checks["latch"]["contradictions"] == 0, "evade/reset outside combat is not a contradiction"
    assert question["verdict"] == "INCOMPLETE"


def test_legacy_capture_uses_registry():
    rows = [
        "DIAG session=20261115-123354-1 sample=1 elapsed=1.00 BASELINE pull=0",
        "  combat=plain:true",
        "  queueContext=plain:simc=st enemies=1 outOfMelee=false dying=false execute=true pick=nil",
        "  signal.targetEpoch=plain:4",
        "  GetPlayerAuraBySpellID = nil",
        "DIAG session=20261115-123354-1 sample=2 elapsed=2.00 SAMPLE pull=0",
        "  queueContext=plain:simc=st enemies=1 outOfMelee=false dying=false execute=false pick=nil",
        "  signal.targetEpoch=plain:5",
    ]
    session = ap.split_sessions(rows)[0]
    events = ap.build_timeline(session)
    keys = [(e[2], e[3]) for e in events if e[0] == "key"]
    assert (4, "queueContext") in keys and (5, "queueContext") in keys, "epoch applies to the whole sample"
    assert not any(e[0] == "key" and "GetPlayerAura" in e[3] for e in events)
    result = ap.analyze_session(session, "execute", ap.registry_definitions)
    assert result["definitions"].startswith("registry")
    question = result["questions"][0]
    swap = next(c for c in question["controls"] if c["name"] == "swapReset")
    assert swap["count"] == 1
    report = {"client": "x", "path": __file__, "dropped": 0, "modified": "now", "baseline": None,
              "sessions": [result]}
    text = ap.format_summary(report, details=True)
    assert "WARNING: no STOP row" in text and "no baseline yet" in text and "control swapReset" in text


def test_release_explained_by_target_cast():
    rows = ["DIAGNOSTICS START session=S2 t=0.000 question=all mode=general limit=1200",
            "DIAGNOSTICS KEYS session=S2 keys=combat,queueContext",
            "QUESTION DEF session=S2 q=x title=X keys=queueContext rows= audit= marks=",
            "QUESTION CONTROL session=S2 q=x name=c key=queueContext has=execute=true repeats=1",
            "QUESTION CHECK session=S2 q=x name=latch kind=latch key=queueContext on=execute=true"
            " off=execute=false explainRow=SIGNAL%20UNIT_SPELLCAST_STOP within=3 combat=true"
            " severity=contradiction",
            "DIAG session=S2 sample=1 elapsed=0 t=100.000 epoch=1 BASELINE pull=1",
            "  combat=plain:true", "  queueContext=plain:execute=true",
            "SIGNAL UNIT_SPELLCAST_STOP t=101.500 epoch=1 arg4=plain:x",
            "DIAG session=S2 sample=2 elapsed=2 t=102.000 epoch=1 SAMPLE pull=1",
            "  queueContext=plain:execute=false",
            "DIAG session=S2 sample=3 elapsed=3 t=103.000 epoch=1 SAMPLE pull=1",
            "  queueContext=plain:execute=true",
            "DIAG session=S2 sample=4 elapsed=9 t=109.000 epoch=1 SAMPLE pull=1",
            "  queueContext=plain:execute=false",
            "DIAGNOSTICS STOP session=S2 samples=4 changes=4 pulls=1 failures=0 t=110.000 marks=0"]
    result = ap.analyze_session(ap.split_sessions(rows)[0])
    latch = result["questions"][0]["checks"][0]
    assert latch["explained"] == 1, "a completed target cast just before the release explains it"
    assert latch["contradictions"] == 1, "a release with no nearby evidence still contradicts"
    assert result["mode"] == "general" and result["fingerprint"]["complete"]


def general_capture(session_id, combat_values, ooc_value="plain:plain:true", extra_key=True, failures=0,
                    baseline=True):
    rows = [f"DIAGNOSTICS START session={session_id} t=0.000 question=all mode=general limit=1200",
            f"DIAGNOSTICS KEYS session={session_id} keys=combat,build,probe,extra"]
    tag = "BASELINE" if baseline else "SAMPLE"
    rows += [f"DIAG session={session_id} sample=1 elapsed=0 t=0.000 epoch=0 {tag} pull=0",
             "  combat=plain:false", "  build=plain:1.0", f"  probe={ooc_value}"]
    if extra_key:
        rows.append("  extra=plain:on")
    t = 0
    for index, value in enumerate(combat_values):
        t += 20
        rows += [f"DIAG session={session_id} sample={index + 2} elapsed={t} t={t}.000 epoch=1 SAMPLE pull=1"]
        if index == 0:
            rows.append("  combat=plain:true")
        rows.append(f"  probe={value}")
    rows += [f"DIAG session={session_id} sample=99 elapsed={t + 20} t={t + 20}.000 epoch=1 SAMPLE pull=1",
             "  combat=plain:false",
             f"DIAGNOSTICS STOP session={session_id} samples=9 changes=9 pulls=1 failures={failures}"
             f" t={t + 30}.000 marks=0"]
    return rows


def test_fingerprint_classes():
    assert ap.value_classes("plain:plain:true") == {"plain", "inner:plain"}
    assert ap.value_classes("plain:unknown:nil input") == {"plain", "inner:unknown"}
    assert ap.value_classes("secret:<secret>") == {"secret"}
    fields = ap.field_statuses("plain:plain:cast notInterruptible{raw=secret:<secret> bridge=plain:false}"
                               " fullControl{plain:raw=plain:true} actual=plain:true")
    assert ("notInterruptible.raw", "secret") in fields and ("notInterruptible.bridge", "plain") in fields
    assert ("fullControl", "plain") in fields and ("actual", "plain") in fields
    assert ("raw", "secret") not in fields, "braced fields are qualified by their parent"
    assert ap.row_kind("EVIDENCE range session=x") == "EVIDENCE range"
    assert ap.row_kind("12.5 AURAINST epoch=1") == "AURAINST"
    assert ap.row_kind("DOT 12.0 target -> none") == "DOT"


def test_compare_detects_behavior_changes():
    def fp(rows):
        return ap.analyze_session(ap.split_sessions(rows)[0])["fingerprint"]

    base = fp(general_capture("B", ["plain:plain:x raw=plain:true", "plain:plain:y raw=plain:false"]))
    assert base["context"]["combatSeconds"] >= 30 and base["complete"]
    same = ap.compare(base, fp(general_capture("C", ["plain:plain:y raw=plain:false"] * 2)))
    assert not [item for item in same if item[0] != "INFO"], same
    secret = ap.compare(base, fp(general_capture("D", ["secret:<secret>", "plain:plain:y raw=secret:<secret>"])))
    texts = [f"{level} {text}" for level, text in secret]
    assert any(t.startswith("CHANGED probe [combat]: now reads secret") for t in texts), texts
    assert any(t.startswith("CHANGED probe [combat] raw: now secret") for t in texts), texts
    assert any(t.startswith("LOST probe [combat] raw: no plain") for t in texts), texts
    assert secret[0][0] == "CHANGED", "most significant differences come first"
    missing = ap.compare(base, fp(general_capture("E", ["plain:plain:y"] * 2, extra_key=False)))
    assert ("LOST", "extra: no longer recorded") in missing
    evicted = ap.compare(base, fp(general_capture("F", ["plain:plain:y"] * 2, extra_key=False, baseline=False)))
    assert ("LOST", "extra: no longer recorded") not in evicted, "evicted keys are not reported as lost"
    quiet = ap.compare(base, fp(general_capture("G", ["secret:<secret>"])))
    assert not any(level == "CHANGED" and "[combat]" in text for level, text in quiet), \
        "too little combat to compare combat behavior"
    failing = ap.compare(base, fp(general_capture("H", ["plain:plain:y"] * 2, failures=2)))
    assert ("CHANGED", "sampler read failures: 0 -> 2") in failing


def test_baseline_accept_and_compare_end_to_end():
    import contextlib
    import io
    work = tempfile.mkdtemp()
    first = saved_variables(general_capture("20261116-100000-1", ["plain:plain:x raw=plain:true"] * 2))
    unstopped = saved_variables(general_capture("20261116-110000-1", ["plain:plain:x"] * 2)[:-1])
    second = saved_variables(general_capture("20261116-120000-1", ["secret:<secret>"] * 2))
    try:
        def run(*args):
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                assert ap.main(list(args) + ["--baseline-dir", work]) == 0
            return buffer.getvalue()

        out = run(first)
        assert "no baseline yet" in out
        out = run(unstopped, "--accept")
        assert "refused: the session has no STOP row" in out
        assert not os.path.exists(ap.baseline_path(work, "custom"))
        out = run(first, "--accept")
        assert ap.baseline_path(work, "custom") in out
        out = run(first)
        assert "compared with baseline" not in out, "a session is not compared with itself"
        out = run(second)
        assert "compared with baseline 20261116-100000-1" in out
        assert "CHANGED  probe [combat]: now reads secret" in out
        run(second, "--accept")
        assert os.path.exists(os.path.join(work, "custom.prev.json")), "the replaced baseline is kept"
        assert ap.load_baseline(work, "custom")["session"] == "20261116-120000-1"
    finally:
        for path in (first, unstopped, second):
            os.unlink(path)


def test_followed_by_independent_evidence():
    rows = ["DIAGNOSTICS START session=S3 t=0.000 question=all mode=general limit=1200",
            "DIAGNOSTICS KEYS session=S3 keys=combat,aggroRange",
            "QUESTION DEF session=S3 q=p title=P keys=aggroRange rows= audit= marks=",
            "QUESTION CONTROL session=S3 q=p name=c key=aggroRange has=applies=true repeats=1",
            "QUESTION CHECK session=S3 q=p name=swing kind=followedBy key=aggroRange has=applies=true"
            " row=EVIDENCE%20 rowHas=HandSwing%20session= within=2 combat=false severity=contradiction",
            "DIAG session=S3 sample=1 elapsed=0 t=100.000 epoch=1 BASELINE pull=0",
            "  combat=plain:false", "  aggroRange=plain:applies=true reason=x within5=false",
            "EVIDENCE mainHandSwing session=S3 t=101.200 epoch=1 timing-only",
            "DIAG session=S3 sample=2 elapsed=1 t=101.500 epoch=1 SAMPLE pull=1",
            "  combat=plain:true", "  aggroRange=plain:applies=false reason=player in combat within5=nil",
            "DIAG session=S3 sample=3 elapsed=20 t=120.000 epoch=2 SAMPLE pull=1",
            "  combat=plain:false", "  aggroRange=plain:applies=true reason=x within5=false",
            "EVIDENCE rangedSwing session=S3 t=120.500 epoch=2 timing-only",
            "EVIDENCE mainHandSwing session=S3 t=125.000 epoch=2 timing-only",
            "DIAGNOSTICS STOP session=S3 samples=3 changes=3 pulls=1 failures=0 t=130.000 marks=0"]
    check = ap.analyze_session(ap.split_sessions(rows)[0])["questions"][0]["checks"][0]
    assert check["entries"] == 2
    assert check["contradictions"] == 1, "only a melee swing inside the window contradicts"
    assert check["examples"][0]["t"] == 100.0


def test_tally_honors_has_and_lacks():
    rows = ["DIAGNOSTICS START session=S6 t=0.000 question=gcd mode=question limit=1200",
            "DIAGNOSTICS KEYS session=S6 keys=combat",
            "QUESTION DEF session=S6 q=g title=G keys= rows=gcd audit= marks=",
            "QUESTION CONTROL session=S6 q=g name=c row=EVIDENCE%20gcd%20 repeats=1",
            "QUESTION CHECK session=S6 q=g name=combat kind=tally row=EVIDENCE%20gcd%20 has=combat=true field=gcd",
            "QUESTION CHECK session=S6 q=g name=all kind=tally row=EVIDENCE%20gcd%20 field=gcd",
            "QUESTION CHECK session=S6 q=g name=hasted kind=stats row=EVIDENCE%20gcd%20"
            " lacks=haste=0.00 field=gcd",
            "DIAG session=S6 sample=1 elapsed=0 t=100.000 epoch=0 BASELINE pull=0", "  combat=plain:false",
            "EVIDENCE gcd session=S6 t=101.000 epoch=0 spell=1243 base=1243 from=success cast=0 gcd=1.500"
            " haste=0.00 combat=false",
            "EVIDENCE gcd session=S6 t=103.000 epoch=0 spell=1243 base=1243 from=success cast=0 gcd=1.304"
            " haste=15.00 combat=false",
            "EVIDENCE gcd session=S6 t=105.000 epoch=0 spell=591 base=585 from=start cast=1739 gcd=secret"
            " haste=secret combat=true",
            "DIAGNOSTICS STOP session=S6 samples=1 changes=1 pulls=0 failures=0 t=130.000 marks=0"]
    checks = {c["name"]: c for c in ap.analyze_session(ap.split_sessions(rows)[0])["questions"][0]["checks"]}
    assert checks["combat"]["counts"] == {"secret": 1}, "has filters a tally"
    assert checks["all"]["counts"] == {"1.500": 1, "1.304": 1, "secret": 1}
    assert (checks["hasted"]["n"], checks["hasted"]["min"]) == (1, 1.304), "haste=0.00 is a whole-field match"


def test_stats_summarize_numeric_fields():
    rows = ["DIAGNOSTICS START session=S5 t=0.000 question=swing mode=question limit=1200",
            "DIAGNOSTICS KEYS session=S5 keys=combat",
            "QUESTION DEF session=S5 q=s title=S keys= rows=mainHandSwing,rage audit= marks=",
            "QUESTION CONTROL session=S5 q=s name=c row=EVIDENCE%20mainHandSwing%20 has=afterCast=none repeats=1",
            "QUESTION CHECK session=S5 q=s name=slam kind=stats row=EVIDENCE%20mainHandSwing%20"
            " has=afterCast=1240193 field=ratio",
            "QUESTION CHECK session=S5 q=s name=reckless kind=stats row=EVIDENCE%20rage%20"
            " has=cause=swing,;1329555: lacks=;78:0. field=delta",
            "QUESTION CHECK session=S5 q=s name=none kind=stats row=EVIDENCE%20mainHandSwing%20"
            " has=afterCast=78 field=ratio",
            "DIAG session=S5 sample=1 elapsed=0 t=100.000 epoch=0 BASELINE pull=1", "  combat=plain:true",
            "EVIDENCE mainHandSwing session=S5 t=101.000 epoch=0 gap=2.000 ratio=1.00 afterCast=none",
            "EVIDENCE mainHandSwing session=S5 t=104.000 epoch=0 gap=3.000 ratio=1.50 afterCast=1240193 sinceCast=2.0",
            "EVIDENCE mainHandSwing session=S5 t=107.400 epoch=0 gap=3.400 ratio=1.70 afterCast=1240193 sinceCast=2.0",
            "EVIDENCE mainHandSwing session=S5 t=110.000 epoch=0 gap=unknown ratio=unknown afterCast=1240193",
            "EVIDENCE mainHandSwing session=S5 t=112.000 epoch=0 gap=2.000 ratio=1.00 afterCast=12401930",
            "EVIDENCE rage session=S5 t=112.100 epoch=0 rage=30 delta=9 sinceSwing=0.1 cause=swing recent=;1329555:1.0;",
            "EVIDENCE rage session=S5 t=114.100 epoch=0 rage=25 delta=-5 sinceSwing=0.1 cause=swing"
            " recent=;78:0.1;1329555:3.0;",
            "EVIDENCE rage session=S5 t=116.100 epoch=0 rage=36 delta=11 sinceSwing=0.1 cause=swing"
            " recent=;1329555:5.0;",
            "DIAGNOSTICS STOP session=S5 samples=1 changes=1 pulls=1 failures=0 t=130.000 marks=0"]
    checks = {c["name"]: c for c in ap.analyze_session(ap.split_sessions(rows)[0])["questions"][0]["checks"]}
    assert checks["slam"] == {"name": "slam", "kind": "stats", "n": 2, "min": 1.5, "median": 1.6, "max": 1.7}, \
        "a whole-field id match; unknown cells are skipped"
    assert (checks["reckless"]["n"], checks["reckless"]["median"]) == (2, 10.0), "lacks excludes the next-swing row"
    assert checks["none"] == {"name": "none", "kind": "stats", "n": 0}
    assert ap._format_check(checks["slam"]) == "slam: n=2 min=1.5 median=1.6 max=1.7"
    assert ap._format_check(checks["none"]) == "none: no values"


def test_fight_wide_marks():
    rows = ["DIAGNOSTICS START session=S4 t=0.000 question=all mode=general limit=1200",
            "DIAGNOSTICS KEYS session=S4 keys=combat,count",
            "QUESTION DEF session=S4 q=m title=M keys=count rows= audit= marks=add",
            "QUESTION CONTROL session=S4 q=m name=c mark=add repeats=1",
            "QUESTION CHECK session=S4 q=m name=fight kind=afterMark mark=add key=count lacks=n=0 scope=combat",
            "QUESTION CHECK session=S4 q=m name=window kind=afterMark mark=add key=count lacks=n=0 within=2",
            "DIAG session=S4 sample=1 elapsed=0 t=100.000 epoch=0 BASELINE pull=0",
            "  combat=plain:false", "  count=plain:n=0",
            "MARK session=S4 t=101.000 epoch=0 combat=false label=add",      # typed before the pull
            "DIAG session=S4 sample=2 elapsed=8 t=108.000 epoch=1 SAMPLE pull=1", "  combat=plain:true",
            "DIAG session=S4 sample=3 elapsed=12 t=112.000 epoch=1 SAMPLE pull=1", "  count=plain:n=1",
            "DIAG session=S4 sample=4 elapsed=20 t=120.000 epoch=1 SAMPLE pull=1",
            "  combat=plain:false", "  count=plain:n=0",
            "MARK session=S4 t=125.000 epoch=1 combat=false label=add",      # no fight follows
            "MARK session=S4 t=160.000 epoch=1 combat=false label=add",      # far before the next pull
            "DIAG session=S4 sample=5 elapsed=80 t=180.000 epoch=2 SAMPLE pull=2", "  combat=plain:true",
            "  count=plain:n=1",
            "DIAGNOSTICS STOP session=S4 samples=5 changes=5 pulls=2 failures=0 t=190.000 marks=3"]
    checks = {c["name"]: c for c in ap.analyze_session(ap.split_sessions(rows)[0])["questions"][0]["checks"]}
    assert checks["fight"]["hits"] == 1 and checks["fight"]["misses"] == 2, checks["fight"]
    assert checks["window"]["hits"] == 0, "a fixed window misses a mark typed before the pull"


def main():
    for test in (test_registry_is_valid, test_clean_capture_meets_controls,
                 test_contradictions_and_reset_marks, test_combat_exit_releases_latches,
                 test_legacy_capture_uses_registry, test_release_explained_by_target_cast,
                 test_fingerprint_classes, test_compare_detects_behavior_changes,
                 test_baseline_accept_and_compare_end_to_end, test_followed_by_independent_evidence,
                 test_fight_wide_marks, test_stats_summarize_numeric_fields,
                 test_tally_honors_has_and_lacks):
        test()
    print("analyze probe: registry validity, capture parsing, controls, checks, verdicts, legacy captures,"
          " evidence explanations, fingerprints, baseline comparison, accept flow and independent follow-up evidence passed")


if __name__ == "__main__":
    main()
