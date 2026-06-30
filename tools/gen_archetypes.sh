#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generates Data/SpellArchetypes.lua from wago.tools DB2 CSV exports.
#
# Classifies player class *damage* spells by:
#   arch  = st | cleave | aoe   (SpellEffect implicit targets + SpellTargetRestrictions)
#   range = melee | ranged      (SpellMisc.RangeIndex -> SpellRange.RangeMax; <=8 = melee)
#
# Conservative by design: only spells with a direct SchoolDamage effect (Effect=2) are
# tagged. Spells whose damage is indirect (triggers/clones, e.g. Secret Technique) have
# no direct area/single damage target, so they're left UNTAGGED -> neutral at runtime
# (never a wrong boost). Refine those by hand / SimC intent later.
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
for v in "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE"; do
    [ -n "$v" ] || { echo "ERROR: a required CSV is missing in $CSV/" >&2; exit 1; }
done

# The spell SET = every class-family spell (SpellClassOptions.SpellClassSet != 0 -
# covers all class abilities incl. talents) UNIONed with accumulated GetRotationSpells()
# dumps (belt-and-suspenders for anything lacking a family). DB2 then classifies them.
IDSFILE="tools/rotation_spell_ids.txt"
[ -f "$IDSFILE" ] || { echo "ERROR: $IDSFILE not found" >&2; exit 1; }
IDS=$(grep -vE '^\s*#' "$IDSFILE" | grep -oE '[0-9]+' | sort -un | tr '\n' ' ')
echo "Using:"; printf '  %s\n' "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE" "$IDSFILE"

BUILD=$(basename "$SE" | sed -E 's/^SpellEffect\.(.*)\.csv$/\1/')

awk -F',' -v ids="$IDS" '
function basef(p,  a,n){ n=split(p,a,"/"); return a[n] }
BEGIN{
    split("15 16 24 28 54 104", X, " "); for(i in X) AREA[X[i]]=1;   # area-enemy targets
    split("24 54 104", C, " ");          for(i in C) CONET[C[i]]=1;  # cone-enemy targets
    split("2 6", Y, " ");                for(i in Y) SINGLE[Y[i]]=1; # single-enemy targets
    n=split(ids, II, " "); for(i=1;i<=n;i++) if(II[i]!="") PLAYER[II[i]+0]=1;
}
FNR==1 { file=basef(FILENAME); next }                                # skip header rows
file ~ /^SpellRange\./        { m=($NF+0>$(NF-1)+0)?$NF+0:$(NF-1)+0; RANGE[$1+0]=m; next }
file ~ /^SpellClassOptions\./ { if(($4+0)!=0) PLAYER[$2+0]=1; next }  # SpellClassSet!=0 = class spell
file ~ /^SpellMisc\./         { MRANGE[$NF+0]=$23+0; next }           # SpellID -> RangeIndex
file ~ /^SpellTargetRestrictions\./ { MAXT[$NF+0]=$4+0; CONE[$NF+0]=$3+0; next }
file ~ /^SpellName\./        { nm=$0; sub(/^[0-9]*,/,"",nm); NAME[$1+0]=nm; next }
file ~ /^SpellEffect\./ {
    sid=$NF+0
    if(!(sid in PLAYER)) next
    if(($5+0)!=2) next                                               # SchoolDamage only
    DMG[sid]=1
    t0=$(NF-2)+0; t1=$(NF-1)+0
    if((t0 in AREA)||(t1 in AREA))     AREAD[sid]=1
    if((t0 in CONET)||(t1 in CONET))   ICONE[sid]=1
    if((t0 in SINGLE)||(t1 in SINGLE)) SINGD[sid]=1
    next
}
END{
    for(sid in DMG){
        if(sid in AREAD){
            mt=MAXT[sid]
            if((sid in ICONE)||(CONE[sid]>0)||(mt>=2 && mt<=8)) arch="cleave"
            else arch="aoe"
        } else if(sid in SINGD){
            arch="st"
        } else continue                                             # ambiguous -> untagged
        rmax=RANGE[MRANGE[sid]]
        rng=(rmax<=8)?"melee":"ranged"
        nm=NAME[sid]; gsub(/[\t\r"]/,"",nm)
        print arch "\t" sid "\t" rng "\t" nm
    }
}
' "$SR" "$SM" "$SCO" "$STR" "$SN" "$SE" > /tmp/_arch_raw.txt

# Emit one archetype group: "[id] = "range",  -- Spell Name" lines, sorted by id.
emit_group() {
    awk -F'\t' -v a="$1" '$1==a{print $2"\t"$3"\t"$4}' /tmp/_arch_raw.txt | sort -n | \
        awk -F'\t' '{printf "        [%s] = \"%s\",  -- %s\n", $1, $2, $3}'
}

TOTAL=$(awk -F'\t' '$1=="aoe"||$1=="cleave"||$1=="st"' /tmp/_arch_raw.txt | wc -l | tr -d ' ')
{
    echo "-- SPDX-License-Identifier: GPL-3.0-or-later"
    echo "-- Copyright (C) 2024-2026 wealdly"
    echo "-- JustAC: Spell archetype data (GENERATED -- do not edit by hand)."
    echo "-- Source: wago.tools DB2 build $BUILD. Regenerate with tools/gen_archetypes.sh."
    echo "-- Player class damage spells grouped by archetype; value = range; comment = name."
    echo "-- Indirect-damage spells (triggered/cloned) are intentionally absent (neutral)."
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
} > "$OUT"
rm -f /tmp/_arch_raw.txt

echo "Wrote $OUT ($TOTAL spells, build $BUILD)."
