#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generates Data/SpellArchetypes.lua from wago.tools DB2 CSV exports.
#
# Classifies player class *damage* spells by:
#   arch  = st | cleave | aoe   (SpellEffect implicit targets + SpellTargetRestrictions)
#   range = melee | ranged      (SpellMisc.RangeIndex -> SpellRange.RangeMax; <=8 = melee)
#
# Conservative by design: only spells with a direct SchoolDamage effect (Effect=2) or a
# periodic-damage aura (Effect=6 APPLY_AURA, DoT/bleed/leech) are tagged - the periodic pass
# covers DoTs the direct-only classification missed. Spells whose damage is indirect
# (triggers/clones, e.g. Secret Technique) have no direct/periodic damage target, so they're
# left UNTAGGED -> neutral at runtime (never a wrong boost). Refine those by hand later.
#
# Re-run per patch after dropping fresh CSVs in Documentation/wow_spell_csv/.
set -euo pipefail
cd "$(dirname "$0")/.."
CSV="Documentation/wow_spell_csv"
OUT="Data/SpellArchetypes.lua"
mkdir -p Data

# Resolve each table by prefix (robust to build-version drift in filenames).
pick() { ls "$CSV/$1".*.csv 2>/dev/null | head -1; }
SR=$(pick SpellRange); SM=$(pick SpellMisc); SCO=$(pick SpellClassOptions)
STR=$(pick SpellTargetRestrictions); SN=$(pick SpellName); SE=$(pick SpellEffect)
SP=$(pick SpellPower)
for v in "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE" "$SP"; do
    [ -n "$v" ] || { echo "ERROR: a required CSV is missing in $CSV/" >&2; exit 1; }
done

# The spell SET = every class-family spell (SpellClassOptions.SpellClassSet != 0 -
# covers all class abilities incl. talents) UNIONed with accumulated GetRotationSpells()
# dumps (belt-and-suspenders for anything lacking a family). DB2 then classifies them.
IDSFILE="tools/rotation_spell_ids.txt"
[ -f "$IDSFILE" ] || { echo "ERROR: $IDSFILE not found" >&2; exit 1; }
IDS=$(grep -vE '^\s*#' "$IDSFILE" | grep -oE '[0-9]+' | sort -un | tr '\n' ' ')
echo "Using:"; printf '  %s\n' "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE" "$SP" "$IDSFILE"

BUILD=$(basename "$SE" | sed -E 's/^SpellEffect\.(.*)\.csv$/\1/')

awk -F',' -v ids="$IDS" '
function basef(p,  a,n){ n=split(p,a,"/"); return a[n] }
# Shape of one spell from its own damage rows: "" when it has none (or only ambiguous
# targets), which is the signal to try its trigger children instead.
function classify(s,   mt){
    if(s in AREAD){
        mt=MAXT[s]
        if((s in ICONE)||(CONE[s]>0)||(mt>=2 && mt<=8)) return "cleave"
        return "aoe"
    }
    if(s in SINGD) return "st"
    return ""
}
BEGIN{
    split("15 16 24 28 54 104", X, " "); for(i in X) AREA[X[i]]=1;   # area-enemy targets
    split("24 54 104", C, " ");          for(i in C) CONET[C[i]]=1;  # cone-enemy targets
    split("2 6", Y, " ");                for(i in Y) SINGLE[Y[i]]=1; # single-enemy targets
    n=split(ids, II, " "); for(i=1;i<=n;i++) if(II[i]!="") PLAYER[II[i]+0]=1;
    # Accumulator resources for builder/spender (crisp point pools). Excludes fuel:
    # Mana(0), Rage(1), Focus(2), Energy(3), Runes(5).
    split("4 6 7 8 9 11 12 13 16 17 18 19", R, " "); for(i in R) POINT[R[i]]=1;
    # Periodic-damage EffectAura types (DoT / bleed / leech) so Effect=6 auras count as damage.
    split("3 89 53", PP, " "); for(i in PP) PERIODIC[PP[i]]=1;
}
FNR==1 { file=basef(FILENAME); next }                                # skip header rows
file ~ /^SpellRange\./        { m=($NF+0>$(NF-1)+0)?$NF+0:$(NF-1)+0; RANGE[$1+0]=m; next }
file ~ /^SpellClassOptions\./ { if(($4+0)!=0) PLAYER[$2+0]=1; next }  # SpellClassSet!=0 = class spell
file ~ /^SpellMisc\./         { MRANGE[$NF+0]=$23+0; next }           # SpellID -> RangeIndex
file ~ /^SpellTargetRestrictions\./ { MAXT[$NF+0]=$4+0; CONE[$NF+0]=$3+0; next }
file ~ /^SpellName\./        { nm=$0; sub(/^[0-9]*,/,"",nm); NAME[$1+0]=nm; next }
file ~ /^SpellPower\./ {                                             # point-resource cost = spender
    if(((($3+0)+($8+0)+($14+0))>0) && (($12+0) in POINT)) COSTPT[$NF+0]=1
    next
}
file ~ /^SpellEffect\./ {
    sid=$NF+0
    e=$5+0
    if((sid in PLAYER) && e==30 && (($(NF-10)+0) in POINT)) ENGPT[sid]=1  # ENERGIZE a point pool = builder
    # Trigger links, player spells only (only they are ever emitted). A button whose damage
    # lives in a CHILD spell has no damage row of its own: Whirlwind and Execute are
    # TRIGGER_SPELL(64), Frostbolt is TRIGGER_MISSILE(32), Blizzard is CREATE_AREATRIGGER(179).
    # Remember the child so the parent can inherit its shape below.
    if((sid in PLAYER) && (e==64 || e==32 || e==179 || e==3)) {
        ch=$17+0                                                     # EffectTriggerSpell
        if(ch>0) TRIG[sid]=TRIG[sid] " " ch
    }
    # Damage targets are recorded for EVERY spell, not just player ones. A triggered child is
    # usually not a class-family spell, so the old `if(!(sid in PLAYER)) next` gate here threw
    # away precisely the rows a parent needs to inherit from. Emission is still player-only.
    # Damage = direct SchoolDamage (Effect 2) OR a periodic-damage aura (Effect 6 w/ a
    # periodic-damage EffectAura $2) - the latter picks up DoTs/bleeds the direct pass missed.
    if(e!=2 && !(e==6 && (($2+0) in PERIODIC))) next
    DMG[sid]=1
    t0=$(NF-2)+0; t1=$(NF-1)+0
    if((t0 in AREA)||(t1 in AREA))     AREAD[sid]=1
    if((t0 in CONET)||(t1 in CONET))   ICONE[sid]=1
    if((t0 in SINGLE)||(t1 in SINGLE)) SINGD[sid]=1
    next
}
END{
    for(sid in PLAYER){
        arch=classify(sid); via=""
        if(arch==""){
            # No damage row of its own - inherit from whatever it triggers. The CHILD is what
            # actually hits, so it decides st/cleave/aoe; the PARENT is what the player presses,
            # so it keeps its own range. First child that resolves wins.
            if(sid in TRIG){
                n=split(TRIG[sid], kids, " ")
                for(i=1;i<=n;i++){
                    if(kids[i]=="") continue
                    a=classify(kids[i]+0)
                    if(a!=""){ arch=a; via=kids[i]; break }
                }
            }
        }
        if(arch=="") continue                                       # ambiguous -> untagged
        rmax=RANGE[MRANGE[sid]]
        # RangeMax 100 is the "no target-range check" sentinel, not a 100-yard spell, and it
        # does NOT imply either answer: it covers self-centered melee AoE (Whirlwind,
        # Consecration) and ground-targeted ranged AoE (Earthquake, Frozen Orb) alike. For an
        # INHERITED entry that is a new claim we cannot substantiate, so skip it and leave the
        # spell neutral - the same "never a wrong boost" rule that left it untagged before.
        # Directly-classified spells carrying this sentinel are left exactly as they were:
        # ~1000 entries, a mix of right and wrong, and re-deciding them is its own pass, not a
        # side effect of this one.
        if(via!="" && rmax>=100) continue
        rng=(rmax<=8)?"melee":"ranged"
        nm=NAME[sid]; gsub(/[\t\r"]/,"",nm)
        if(via!="") nm=nm " (via " via ")"
        print arch "\t" sid "\t" rng "\t" nm
    }
    for(sid in PLAYER){                                             # builder/spender (cost wins over energize)
        if(sid in COSTPT)     role="spender"
        else if(sid in ENGPT) role="builder"
        else continue
        nm=NAME[sid]; if(nm=="") continue; gsub(/[\t\r"]/,"",nm)
        print "role_" role "\t" sid "\t-\t" nm
    }
}
' "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE" "$SP" > /tmp/_arch_raw.txt

# Emit one archetype group: "[id] = "range",  -- Spell Name" lines, sorted by id.
emit_group() {
    awk -F'\t' -v a="$1" '$1==a{print $2"\t"$3"\t"$4}' /tmp/_arch_raw.txt | sort -n | \
        awk -F'\t' '{printf "        [%s] = \"%s\",  -- %s\n", $1, $2, $3}'
}
emit_role() {
    awk -F'\t' -v a="$1" '$1==a{print $2"\t"$4}' /tmp/_arch_raw.txt | sort -n | \
        awk -F'\t' '{printf "        [%s] = true,  -- %s\n", $1, $2}'
}

TOTAL=$(awk -F'\t' '$1=="aoe"||$1=="cleave"||$1=="st"' /tmp/_arch_raw.txt | wc -l | tr -d ' ')
{
    echo "-- SPDX-License-Identifier: GPL-3.0-or-later"
    echo "-- Copyright (C) 2024-2026 wealdly"
    echo "-- JustAC: Spell archetype data (GENERATED -- do not edit by hand)."
    echo "-- Source: wago.tools DB2 build $BUILD. Regenerate with tools/gen_archetypes.sh."
    echo "-- Player class damage spells grouped by archetype; value = range; comment = name."
    echo "-- Indirect-damage spells (triggered/cloned) are intentionally absent (neutral)."
    echo "-- Plus builder/spender roles: spender = costs an accumulator resource, builder ="
    echo "-- generates one (ENERGIZE). Fuel resources (mana/rage/focus/energy/runes) excluded."
    echo "local SpellDB = LibStub(\"JustAC-SpellDB\", true)"
    echo "if not SpellDB or not SpellDB.RegisterArchetypes then return end"
    echo ""
    echo "SpellDB.RegisterArchetypes({"
    for cat in aoe cleave st; do
        n=$(awk -F'\t' -v a="$cat" '$1==a' /tmp/_arch_raw.txt | wc -l | tr -d ' ')
        echo "    $cat = {  -- $n spells (value = range)"
        emit_group "$cat"
        echo "    },"
    done
    echo "})"
    echo ""
    echo "if not SpellDB.RegisterRoles then return end"
    echo "SpellDB.RegisterRoles({"
    for role in builder spender; do
        n=$(awk -F'\t' -v a="role_$role" '$1==a' /tmp/_arch_raw.txt | wc -l | tr -d ' ')
        echo "    $role = {  -- $n spells"
        emit_role "role_$role"
        echo "    },"
    done
    echo "})"
} > "$OUT"
rm -f /tmp/_arch_raw.txt

echo "Wrote $OUT ($TOTAL spells, build $BUILD)."
