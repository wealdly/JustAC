#!/usr/bin/env python3
# tools/simc_bridge.py
#
# Offline SimC-token -> spellID resolver, built from the wago.tools client-data
# CSVs in Documentation/wow_spell_csv/ (build-time only; never shipped - see
# .pkgmeta). It assembles a spec's *castable universe* -
#   - spec-granted spells       (SpecializationSpells, + its override target)
#   - talent-tree spells         (TraitTreeLoadout -> TraitNode -> ...Entry ->
#                                 TraitDefinition, unioning the SpellID /
#                                 VisibleSpellID / OverridesSpellID columns)
#   - class/spec skill-line spells (SkillLineXTraitTree -> SkillLineAbility)
# - then slug-matches SimC's snake_case action tokens against the spell names in
# that universe. A match that is unique within the spec resolves; anything
# ambiguous, form-specific (_cat/_bear/_moonkin), or sitting downstream of an
# override chain is left to a caller-supplied `curated` map. A token that is
# neither auto-resolved nor curated returns None so the generator can fail LOUD
# rather than silently drop a rotation step.
#
# The auto-resolved majority refreshes itself when the CSVs are re-pulled between
# patches; the curated residue is a small stable backstop (form-heavy specs like
# feral need the most; caster specs need few or none).
import csv, os, re, glob

# class token -> ChrSpecialization.ClassID
CLASS_ID = {
    "WARRIOR": 1, "PALADIN": 2, "HUNTER": 3, "ROGUE": 4, "PRIEST": 5,
    "DEATHKNIGHT": 6, "SHAMAN": 7, "MAGE": 8, "WARLOCK": 9, "MONK": 10,
    "DRUID": 11, "DEMONHUNTER": 12, "EVOKER": 13,
}
FORMS = ("cat", "bear", "moonkin", "owl", "astral")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower().replace("'", "")).strip("_")


class SimcBridge:
    def __init__(self, csv_dir):
        self.dir = csv_dir
        self.NM = {r["ID"]: r.get("Name_lang", "") for r in self._rows("SpellName")}
        # Passive spells (SPELL_ATTR0_PASSIVE) are never rotational buttons and are
        # never what Assisted Combat suggests, yet the client data files a passive
        # spec/talent record under the SAME NAME as the castable ability (e.g. the
        # passive "Moonfire" 326646 shadowing the cast 8921). Excluded from the
        # resolver universe so a name collision can never pick the passive.
        self.PASSIVE = {
            r["SpellID"] for r in self._rows("SpellMisc")
            if int(r.get("DifficultyID") or 0) == 0
            and (int(r.get("Attributes_0") or 0) & 0x40)
        }
        _chrspec = self._rows("ChrSpecialization")
        self.SPEC = {r["ID"]: (r["ClassID"], r["Name_lang"]) for r in _chrspec}
        # spec index within its class (OrderIndex 0-based) -> our spec key uses +1
        self.SPEC_ORDER = {r["ID"]: int(r.get("OrderIndex") or 0) for r in _chrspec}

        # spec-granted spells. _base_primary is the canonical granted SpellID;
        # _base also folds in the override target to broaden the candidate universe.
        self._base = {}
        self._base_primary = {}
        for r in self._rows("SpecializationSpells"):
            self._base.setdefault(r["SpecID"], set()).add(r["SpellID"])
            self._base_primary.setdefault(r["SpecID"], set()).add(r["SpellID"])
            ov = r.get("OverridesSpellID", "0")
            if ov not in ("0", ""):
                self._base[r["SpecID"]].add(ov)

        # talent chain
        self._tdef = {r["ID"]: r for r in self._rows("TraitDefinition")}
        self._entry = {r["ID"]: r["TraitDefinitionID"]
                       for r in self._rows("TraitNodeEntry")}
        self._node_entries = {}
        for r in self._rows("TraitNodeXTraitNodeEntry"):
            self._node_entries.setdefault(r["TraitNodeID"], []).append(r["TraitNodeEntryID"])
        self._tree_nodes = {}
        for r in self._rows("TraitNode"):
            self._tree_nodes.setdefault(r["TraitTreeID"], []).append(r["ID"])
        self._spec_trees = {}
        for r in self._rows("TraitTreeLoadout"):
            self._spec_trees.setdefault(r["ChrSpecializationID"], set()).add(r["TraitTreeID"])

        # skill lines (spec tree -> skill line -> its abilities)
        self._tree_sl = {}
        for r in self._rows("SkillLineXTraitTree"):
            self._tree_sl.setdefault(r["TraitTreeID"], set()).add(r["SkillLineID"])
        self._sl_spells = {}
        self._class_spells = {}  # class bit -> spells (ClassMask): the completeness fallback
        for r in self._rows("SkillLineAbility"):
            self._sl_spells.setdefault(r["SkillLine"], set()).add(r["Spell"])
            try:
                cm = int(r.get("ClassMask") or 0)
            except ValueError:
                cm = 0
            if cm:
                for cid in range(1, 14):
                    if cm & (1 << (cid - 1)):
                        self._class_spells.setdefault(str(cid), set()).add(r["Spell"])

        # Actionbar overrides (EffectAura 332 = SPELL_AURA_OVERRIDE_ACTIONBAR_SPELLS): an
        # aura on OWNER replaces a base button with TARGET (EffectBasePointsF). Hero-talent
        # and form abilities (Annihilation while in Metamorphosis, Death Sweep, ...) exist in
        # the data ONLY as these targets - not as a granted/talent spell. The 332 effect sits
        # on the applied AURA (Metamorphosis buff 162264), which the granted CAST (191427)
        # reaches via EffectTriggerSpell, so we also index triggers to bridge that hop.
        self._overrides = {}   # owner -> {target ids}
        self._triggers = {}    # spell -> {triggered spell ids}
        for r in self._rows("SpellEffect"):
            if int(r.get("DifficultyID") or 0) != 0:
                continue
            trig = r.get("EffectTriggerSpell")
            if trig and trig != "0":
                self._triggers.setdefault(r["SpellID"], set()).add(trig)
            if r.get("EffectAura") == "332":
                try:
                    tgt = str(int(round(float(r.get("EffectBasePointsF") or "0"))))
                except ValueError:
                    continue
                if tgt != "0" and tgt in self.NM:
                    self._overrides.setdefault(r["SpellID"], set()).add(tgt)

        self._uni_cache = {}
        self._prim_cache = {}

    # --- CSV loading ---------------------------------------------------------
    def _find(self, table):
        hits = sorted(glob.glob(os.path.join(self.dir, table + ".*.csv")))
        if not hits:
            raise FileNotFoundError("no CSV for table %r in %s" % (table, self.dir))
        return hits[-1]

    def _rows(self, table):
        with open(self._find(table), encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))

    # --- universe ------------------------------------------------------------
    def spec_id(self, class_token, spec_name):
        cid = str(CLASS_ID[class_token])
        for sid, (c, n) in self.SPEC.items():
            if c == cid and n == spec_name:
                return sid
        raise KeyError((class_token, spec_name))

    def _talent_ids(self, spec, cols=("SpellID", "VisibleSpellID", "OverridesSpellID")):
        out = set()
        for tree in self._spec_trees.get(spec, ()):
            for node in self._tree_nodes.get(tree, ()):
                for e in self._node_entries.get(node, ()):
                    d = self._tdef.get(self._entry.get(e))
                    if not d:
                        continue
                    for col in cols:
                        v = d.get(col)
                        if v and v != "0":
                            out.add(v)
        return out

    def universe(self, spec):
        if spec in self._uni_cache:
            return self._uni_cache[spec]
        ids = set(self._base.get(spec, ()))
        ids |= self._talent_ids(spec)
        for tree in self._spec_trees.get(spec, ()):
            for sl in self._tree_sl.get(tree, ()):
                ids |= self._sl_spells.get(sl, set())
        # Fold in actionbar-override targets reachable from this spec's spells, following up
        # to two EffectTriggerSpell hops (granted cast -> applied aura -> the aura's override),
        # so a form/hero override (Annihilation from Metamorphosis) resolves by its own name.
        # Only the override TARGETS are added to the name universe, not the intermediate auras.
        targets, frontier, visited = set(), set(ids), set(ids)
        for _hop in range(3):
            for s in frontier:
                targets |= self._overrides.get(s, set())
            nxt = set()
            for s in frontier:
                for t in self._triggers.get(s, ()):
                    if t not in visited:
                        visited.add(t)
                        nxt.add(t)
            if not nxt:
                break
            frontier = nxt
        ids |= targets
        self._uni_cache[spec] = ids
        return ids

    def primary(self, spec):
        """Canonical cast ids: granted SpellID + talent SpellID (NO override columns)
        + skill-line spells. Used to break same-name collisions in the broad universe -
        prefer the canonical id over talent override-column variants that share a name."""
        if spec in self._prim_cache:
            return self._prim_cache[spec]
        ids = set(self._base_primary.get(spec, ()))
        ids |= self._talent_ids(spec, cols=("SpellID",))
        for tree in self._spec_trees.get(spec, ()):
            for sl in self._tree_sl.get(tree, ()):
                ids |= self._sl_spells.get(sl, set())
        self._prim_cache[spec] = ids
        return ids

    # --- resolver ------------------------------------------------------------
    def _build_index(self, ids):
        index = {}
        for sid in ids:
            if sid in self.PASSIVE:
                continue
            nm = self.NM.get(sid)
            if nm:
                s = slug(nm)
                index.setdefault(s, set()).add(sid)
                compact = s.replace("_", "")  # SimC drops some separators: Multi-Shot -> multishot
                if compact != s:
                    index.setdefault(compact, set()).add(sid)
        return index

    def resolver(self, class_token, spec_name, curated=None):
        """Return resolve(token) -> spellID (int) or None. Two-tier: the SPEC universe
        first (spec spells + talents + skill lines - few name collisions, keeps e.g.
        `convoke` unambiguous), then a CLASS-wide ClassMask fallback that catches core
        learned spells (Wrath, Chaos Strike, Lightning Bolt) the spec universe misses.
        `curated` overrides everything."""
        curated = curated or {}
        spec = self.spec_id(class_token, spec_name)
        classid = self.SPEC[spec][0]
        spec_index = self._build_index(self.universe(spec))
        class_index = self._build_index(self._class_spells.get(classid, set()))
        # Preference tiers, most spec-specific -> class-learned. A same-name collision
        # resolves to the NARROWEST tier with a unique candidate - so "wrath" for
        # balance picks the spec-granted Balance Wrath, not the shared low-level one.
        sl_spells = set()
        for tree in self._spec_trees.get(spec, ()):
            for sl in self._tree_sl.get(tree, ()):
                sl_spells |= self._sl_spells.get(sl, set())
        tiers = [
            self._base_primary.get(spec, set()),         # SpecializationSpells (spec-granted)
            self._talent_ids(spec, cols=("SpellID",)),   # talent-granted (canonical column)
            sl_spells,                                   # class/spec skill line (learned)
        ]

        def resolve(token):
            if token in curated:
                return curated[token]
            # form variants are inherently ambiguous by name -> require curation
            if any(token.endswith("_" + f) for f in FORMS):
                return None
            ids = spec_index.get(token)
            if ids:  # in the spec universe
                # Resolve at the narrowest non-empty preference tier. Within a tier,
                # a unique candidate wins outright; a same-name collision falls to the
                # lowest id (the base/canonical spell predates its override variants).
                for tier in tiers:
                    hit = ids & tier
                    if hit:
                        return int(next(iter(hit))) if len(hit) == 1 else min(int(x) for x in hit)
                return int(next(iter(ids))) if len(ids) == 1 else min(int(x) for x in ids)
            ids = class_index.get(token)  # class-wide completeness fallback
            if ids:
                return int(next(iter(ids))) if len(ids) == 1 else None
            # SimC short alias: unique prefix within the spec universe
            hits = set()
            for s, v in spec_index.items():
                if s.startswith(token + "_"):
                    hits |= v
            return int(next(iter(hits))) if len(hits) == 1 else None

        return resolve


# --- self-check: feral must reproduce the hand-verified ground truth ---------
if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    b = SimcBridge(os.path.join(root, "Documentation", "wow_spell_csv"))
    CURATED = {
        "swipe_cat": 106785, "thrash_cat": 106830, "moonfire_cat": 155625,
        "berserk": 106951, "brutal_slash": 202028, "adaptive_swarm": 391888,
        "incarnation": 102543, "bs_inc": 106951,
    }
    r = b.resolver("DRUID", "Feral", CURATED)
    GROUND = {
        "rake": 1822, "shred": 5221, "rip": 1079, "ferocious_bite": 22568,
        "tigers_fury": 5217, "berserk": 106951, "incarnation": 102543,
        "convoke_the_spirits": 391528, "feral_frenzy": 274837, "primal_wrath": 285381,
        "swipe_cat": 106785, "thrash_cat": 106830, "brutal_slash": 202028,
        "moonfire_cat": 155625, "adaptive_swarm": 391888,
    }
    auto = sum(1 for t in GROUND if t not in CURATED)
    bad = []
    for tok, want in GROUND.items():
        got = r(tok)
        mark = "OK" if got == want else "FAIL"
        if got != want:
            bad.append((tok, want, got))
        src = "curated" if tok in CURATED else "auto"
        print("  %-22s want %-7s got %-7s %-4s (%s)" % (tok, want, got, mark, src))
    print("\n%d/%d correct  (%d auto, %d curated)"
          % (len(GROUND) - len(bad), len(GROUND), auto, len(CURATED) - 1))
    assert not bad, "bridge mismatch: %r" % bad
    print("self-check: OK")
