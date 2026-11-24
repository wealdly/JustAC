# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Coverage sweep: does the simulator model what each generated list presses at a level?

Offline analysis only; writes nothing inside the addon. For every class and tree in
tools/forever_sim_bench.py's CLASSES it runs the generated single-target list alone against one
even-level target at each level (default 5,10,15,20,25,30) and, for every list entry the
character has learned at that level, says whether the simulator:

  cast      pressed it at least once in a fight
  silent    knows it but never pressed it (a condition that never held in this fight, or a
            talent the level's build lacks: check by hand)
  missing   has no action for it, or the action does nothing at this level (the simulator
            defines some classes' attacks only at levels 25, 40, 50 and 60)

A tree passes a level when nothing learned is missing and some ability other than the auto
attack was pressed. This is the measure of "modelled at this level": a comparison of two lists
means nothing where the entries they differ in are missing.

    python tools/forever_sim_sweep.py --sim <simulator checkout> [--class rogue] [--levels 10,20,30]
                                      [--out sweep.md]

Learned: the rank-1 spell's level in the client's SpellLevels. A talent ability (a client
TraitDefinition spell) or a racial (a race-limited skill line row, or one of the combat racials)
is not judged: the level's build or the bench's race may not have it. It is listed apart when it
was never pressed. Run one sweep or bench at a time.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import forever_sim_bench as bench  # noqa: E402

AUTO = re.compile(r"^OtherAction(Attack|Shoot)")
# A list played in a form is not the character's list before the form is learned: the addon
# follows another list there (RotationImport.PickTree), so those tree-levels are not judged.
FORM_LEVEL = {("druid", "feral"): 20, ("druid", "feral_bear"): 10}
JUDGEMENT = 20271
JUDGEMENTS = set()   # spell ids named "Judgement of ...", filled in main()


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def optional_spells():
    """Spell ids a character of the level may not have: talents and racials."""
    import check_forever_apl as cfa
    out = set()
    for row in cfa.rows("TraitDefinition"):
        for key in ("SpellID", "VisibleSpellID", "OverridesSpellID"):
            if row.get(key) and row[key] != "0":
                out.add(int(row[key]))
    for row in cfa.rows("SkillLineAbility"):
        if row.get("RaceMasks_0") not in (None, "", "0", "-1"):
            out.add(int(row["Spell"]))
    racial = set(s for names in cfa.RACIAL_ROLES.values() for s in names)
    for row in cfa.rows("SpellName"):
        if slug(row["Name_lang"]) in racial:
            out.add(int(row["ID"]))
    return out


def rank_chains():
    """rank id -> rank-1 id, from the generated lists' rank chain table."""
    text = open(bench.ROTATIONS, encoding="utf-8").read()
    out = {}
    for base, ids in re.findall(r"^  \[(\d+)\] = \{([\d,]+)\},?\s*$", text, re.M):
        for rank in ids.split(","):
            out.setdefault(int(rank), int(base))
    return out


def parse_report(text):
    """(entries, levels): entries = [(id, name, omitted reason or None)];
    levels = {level: {"kill": float or None, "casts": {action: (casts, damage)}, "failed": str or None}}."""
    entries, current = [], None
    for line in text.splitlines():
        m = re.match(r"- `\d+ (.+) \((\d+)\)`$", line)
        if m:
            current = [int(m.group(2)), m.group(1), None]
            entries.append(current)
            continue
        if current and "LINE OMITTED" in line:
            current[2] = line.split("LINE OMITTED:", 1)[1].strip()
        if line.startswith("## Can each entry"):
            current = None
    # Source files the simulator defines only at its bracket levels (the bench's caveat line).
    bracket = set()
    m = re.search(r"defined only at levels [\d, ]+\): ([a-z0-9_, ]+)\.", text)
    if m:
        bracket = set(x.strip() for x in m.group(1).split(","))
    for entry in entries:
        entry.append(slug(entry[1]) in bracket)
    levels, level = {}, None
    for line in text.splitlines():
        m = re.match(r"## Level (\d+), gear", line)
        if m:
            level = int(m.group(1))
            levels[level] = {"kill": None, "casts": {}, "failed": None}
            continue
        if level is None:
            continue
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 6 and cells[4] == "justac":
            if cells[5].startswith("failed"):
                levels[level]["failed"] = cells[5]
            else:
                try:
                    levels[level]["kill"] = float(cells[5].split()[0])
                except ValueError:
                    pass
        m = re.match(r"  - justac: (.*)$", line)
        if m:
            body = m.group(1).split("; mana spent")[0]
            for part in body.split(", "):
                pm = re.match(r"(\S+) x([\d.]+) \(([\d.]+)\)$", part.strip())
                if pm:
                    levels[level]["casts"][pm.group(1)] = (float(pm.group(2)), float(pm.group(3)))
    return entries, levels


def judge(entries, run, level, learn_level, chains, optional=()):
    """One level of one tree -> (verdict, cast, silent, missing, not judged, share of damage from
    auto attacks)."""
    by_base = {}
    total = auto = 0.0
    abilities = 0
    for action, (casts, damage) in run["casts"].items():
        total += damage
        if AUTO.match(action):
            auto += damage
            continue
        abilities += 1
        key = action.split(":")[0]
        if key.isdigit():
            base = chains.get(int(key), int(key))
            # A spell the simulator counts no casts for (Execute) still shows its damage.
            casts = casts or (1.0 if damage > 0 else 0.0)
            by_base[base] = by_base.get(base, 0) + casts
            # The simulator records a paladin's Judgement under the judged seal's own spell.
            if int(key) in JUDGEMENTS:
                by_base[JUDGEMENT] = by_base.get(JUDGEMENT, 0) + casts
    cast, silent, missing, unjudged = [], [], [], []
    for sid, name, omitted, bracket_only in entries:
        if (learn_level.get(sid) or 0) > level:
            continue
        if sid in (5019, 6603, 75):
            continue   # the weapon attacks: the automatic attack, not an action
        pressed = by_base.get(chains.get(sid, sid), 0) > 0
        if pressed:
            cast.append(name)
        elif sid in optional or (omitted and omitted.startswith("unmodelled")):
            # A talent or racial the build may lack, or an entry the bench declares it does not
            # model and says why (Victory Rush needs a kill before the fight).
            unjudged.append(name)
        elif omitted:
            missing.append("%s (%s)" % (name, omitted[:50]))
        elif bracket_only and level not in bench.BRACKET_LEVELS:
            missing.append("%s (only at levels %s)" % (name, ", ".join(str(x) for x in bench.BRACKET_LEVELS)))
        else:
            silent.append(name)
    share = auto / total if total else float("nan")
    if run["failed"]:
        verdict = "FAILED"
    elif missing or not abilities:
        verdict = "FAIL"
    elif silent:
        verdict = "check"
    else:
        verdict = "pass"
    return verdict, cast, silent, missing, unjudged, share


SCHOOL_DAMAGE, APPLY_AURA, PERIODIC_DAMAGE = 2, 6, 3
# A simulated cast is flagged when it deals more than HIGH times the client's whole spell (hit plus
# every tick) or less than LOW times its hit alone. Wide on purpose: talents, crits, misses and a
# little spell power move a real cast by tens of percent, a wrong rank by several times.
HIGH, LOW = 1.6, 0.5


def class_chain_index(cls):
    """spell id -> its ability's rank chain, for one class."""
    import check_forever_apl as cfa
    _, by_id = cfa.class_chains(cfa.CLASS_MASK[cls])
    return by_id


def client_damage():
    """spell id -> (learn level, growth cap level, [(mean hit, per level)], [(tick, ticks)]) for
    spells whose damage the client states outright (school damage and periodic damage). Weapon
    strikes and anything scaled by attack power are not in here and are not checked."""
    import check_forever_apl as cfa
    levels = {}
    for r in cfa.rows("SpellLevels"):
        if r["DifficultyID"] == "0":
            levels[r["SpellID"]] = (int(float(r["SpellLevel"] or 0) or float(r["BaseLevel"] or 0)), int(float(r["MaxLevel"] or 0)))
    durations = dict((r["ID"], (float(r["Duration"] or 0), float(r.get("DurationPerResource") or 0)))
                     for r in cfa.rows("SpellDuration"))
    # A finisher's duration can grow with combo points (Rupture, Rip): the upper bound takes five.
    misc = dict((r["SpellID"], sum(x * k for x, k in zip(durations.get(r["DurationIndex"], (0.0, 0.0)), (1, 5))))
                for r in cfa.rows("SpellMisc") if r["DifficultyID"] == "0")
    # Physical attacks (school mask 1) add attack power on the server (Revenge, Rend: coefficients
    # the simulator measured); the client never states it, so they cannot be priced from it.
    physical = set(r["SpellID"] for r in cfa.rows("SpellMisc") if r["DifficultyID"] == "0" and r["SchoolMask"] == "1")
    out = {}
    for r in cfa.rows("SpellEffect"):
        if r["DifficultyID"] != "0" or r["SpellID"] in physical:
            continue
        effect, aura = int(float(r["Effect"] or 0)), int(float(r["EffectAura"] or 0))
        points, per_level = float(r["EffectBasePointsF"] or 0), float(r["EffectRealPointsPerLevel"] or 0)
        if points <= 0:
            continue
        rec = out.setdefault(int(r["SpellID"]), list(levels.get(r["SpellID"], (0, 0))) + [[], []])
        per_point = float(r["EffectPointsPerResource"] or 0)
        if effect == SCHOOL_DAMAGE:
            rec[2].append((points, per_level, per_point))
        elif effect == APPLY_AURA and aura == PERIODIC_DAMAGE:
            period = float(r["EffectAuraPeriod"] or 0)
            if period > 0 and misc.get(r["SpellID"], 0) > 0:
                rec[3].append((points, misc[r["SpellID"]] / period, per_point))
    return dict((k, v) for k, v in out.items() if v[2] or v[3])


# Not checked: Seal of Righteousness's strike scales with the weapon's speed, which its client row
# does not state (no data says how, so no rule can read it).
UNCHECKED_NAMES = ("Seal of Righteousness",)


def rank_for_level(sid, level, chain_of, client):
    """The rank of sid's ability a character of this level has. The simulator may cast one id at
    every level (the warrior keeps its top rank's id), so the cast id's own row is not the rank."""
    chain = chain_of.get(sid)
    if not chain:
        return sid
    have = [int(r) for r, _ in chain if int(r) in client and client[int(r)][0] <= level]
    return have[-1] if have else sid


# An action pressed at least this often a second for no damage at all is flagged: a debuff whose
# "is it up?" check never matches what the simulator applies is recast every global cooldown
# (2026-11-24: Faerie Fire 15 times in a 26 s fight). A buff or Life Tap is pressed far less often.
REPEAT_PER_SECOND = 0.2


def repeat_flags(run, names):
    """Actions pressed over and over for no damage."""
    out = []
    if not run["kill"]:
        return out
    # A next-swing attack (Heroic Strike, Maul, Raptor Strike) is recorded twice: the queued press
    # and the hit, under the same id with another tag. Resource events (OtherActionRageGain) are
    # not presses.
    dealt = set(a.split(":")[0] for a, (_, d) in run["casts"].items() if d > 0)
    for action, (casts, damage) in sorted(run["casts"].items()):
        key = action.split(":")[0]
        if (action.startswith("OtherAction") or damage > 0 or key in dealt
                or casts / run["kill"] < REPEAT_PER_SECOND):
            continue
        name = names.get(int(key), "?") if key.isdigit() else action
        out.append("%s (%s): pressed %.1f times in a %.1f s fight for no damage" % (name, key, casts, run["kill"]))
    return out


def damage_flags(run, level, client, names, cls=None, chain_of=None):
    """Casts whose simulated damage is far from what the client's spell data says."""
    out = []
    for action, (casts, damage) in sorted(run["casts"].items()):
        key = action.split(":")[0]
        if not key.isdigit() or casts < 0.2 or damage <= 0:
            continue
        sid = rank_for_level(int(key), level, chain_of or {}, client)
        rec = client.get(sid)
        if not rec or names.get(sid) in UNCHECKED_NAMES:
            continue
        learned, cap, hits, ticks = rec
        grown = max(0, (min(level, cap) if cap else level) - learned)
        hit = sum(points + per_level * grown for points, per_level, _ in hits)
        # The upper bound allows five combo points on a finisher (Eviscerate, Rip).
        whole = (sum(points + per_level * grown + 5 * per_point for points, per_level, per_point in hits)
                 + sum((points + 5 * per_point) * count for points, count, per_point in ticks))
        per_cast = damage / casts
        if per_cast > HIGH * whole or (hit > 0 and per_cast < LOW * hit):
            out.append("%s (%s): %.0f a cast, client %s" % (
                names.get(int(key), "?"), key, per_cast,
                "%.0f" % hit if not ticks else "%.0f hit, %.0f with every tick" % (hit, whole)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", required=True, help="the simulator checkout")
    ap.add_argument("--cli", help="the simulator's command-line tool (default: the one built in --sim)")
    ap.add_argument("--class", dest="cls", help="one class (default: every class)")
    ap.add_argument("--tree", help="one tree of --class")
    ap.add_argument("--levels", default="5,10,15,20,25,30")
    ap.add_argument("--iterations", type=int, default=200)
    ap.add_argument("--out", help="write the report here as well")
    args = ap.parse_args()

    chains = rank_chains()
    learn_level = dict((int(k), v) for k, v in bench.client_spell_levels().items())
    optional = optional_spells()
    client = client_damage()
    spell_names = dict((int(r["ID"]), r["Name_lang"]) for r in __import__("check_forever_apl").rows("SpellName"))
    flagged, repeated = [], []
    chain_of = {}
    import check_forever_apl as cfa
    JUDGEMENTS.update(int(r["ID"]) for r in cfa.rows("SpellName") if r["Name_lang"].startswith("Judgement of "))
    lines = ["# Simulator coverage sweep: levels %s" % args.levels, "",
             "One even-level target, the generated single-target list alone, gear `behind`, %d iterations. "
             "`FAIL`: an entry the level has learned is missing from the simulator, or nothing but the auto attack "
             "was pressed. `check`: every learned entry exists but some were never pressed in this fight. Talents and racials "
             "never pressed are listed apart and not judged." % args.iterations,
             "", "| Class | Tree | Level | Verdict | Kill s | Auto attack share | Cast | Silent | Missing | Not judged |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    details = []
    for cls in sorted(bench.CLASSES):
        if args.cls and cls != args.cls:
            continue
        for tree in sorted(bench.CLASSES[cls]["trees"]):
            if args.tree and tree != args.tree:
                continue
            out = os.path.join(tempfile.mkdtemp(prefix="jac_sweep_"), "report.md")
            cmd = [sys.executable, os.path.join(HERE, "forever_sim_bench.py"), "--sim", args.sim, "--class", cls,
                   "--tree", tree, "--levels", args.levels, "--gear", "behind", "--batches", "1",
                   "--iterations", str(args.iterations), "--justac-only", "--any-level", "--gaps=0", "--out", out]
            if args.cli:
                cmd += ["--cli", args.cli]
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0 or not os.path.exists(out):
                why = (proc.stderr or proc.stdout).strip().splitlines()[-1:] or ["no report"]
                lines.append("| %s | %s | all | FAILED | | | | | %s | |" % (cls, tree, why[0][:160].replace("|", "/")))
                continue
            entries, levels = parse_report(open(out, encoding="utf-8").read())
            for level in sorted(levels):
                run = levels[level]
                if level < FORM_LEVEL.get((cls, tree), 0):
                    lines.append("| %s | %s | %d | n/a | | | | | | the form is learned at %d |"
                                 % (cls, tree, level, FORM_LEVEL[(cls, tree)]))
                    continue
                verdict, cast, silent, missing, unjudged, share = judge(entries, run, level, learn_level, chains,
                                                                        optional)
                lines.append("| %s | %s | %d | %s | %s | %s | %d | %s | %s | %s |" % (
                    cls, tree, level, verdict, "%.1f" % run["kill"] if run["kill"] else (run["failed"] or "-")[:40],
                    "-" if share != share else "%.0f%%" % (100 * share), len(cast),
                    ", ".join(silent) or "-", ", ".join(missing) or "-", ", ".join(unjudged) or "-"))
                details.append((cls, tree, level, verdict))
                for flag in damage_flags(run, level, client, spell_names, cls, chain_of.setdefault(cls, class_chain_index(cls))):
                    flagged.append("| %s | %s | %d | %s |" % (cls, tree, level, flag))
                for flag in repeat_flags(run, spell_names):
                    repeated.append("| %s | %s | %d | %s |" % (cls, tree, level, flag))
            sys.stderr.write("swept %s %s\n" % (cls, tree))
    lines += ["", "## Damage per cast against the client's spell data", "",
              "A cast is listed when the simulator's damage per cast is above %g times the client's whole spell (hit plus "
              "every tick) or below %g times its hit. Only spells whose damage the client states outright are checked: "
              "no weapon strikes and no physical attacks (their attack power scaling is server-side)." % (HIGH, LOW), ""]
    if flagged:
        lines += ["| Class | Tree | Level | Spell |", "|---|---|---|---|"] + flagged
    else:
        lines.append("Nothing flagged.")
    lines += ["", "## Pressed over and over for no damage", "",
              "An action pressed %g times a second or more that deals no damage: usually a condition that never "
              "reads true in the simulator (an aura id the simulator does not apply), so the press repeats." % REPEAT_PER_SECOND, ""]
    if repeated:
        lines += ["| Class | Tree | Level | Action |", "|---|---|---|---|"] + repeated
    else:
        lines.append("Nothing flagged.")
    bad = sum(1 for d in details if d[3] in ("FAIL", "FAILED"))
    lines += ["", "%d of %d tree-levels fail." % (bad, len(details))]
    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")


if __name__ == "__main__":
    main()
