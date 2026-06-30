#!/usr/bin/env bash
# Completeness audit: finds player class spells that MATCH a category's DB2 signal
# but are MISSING from our curated lists (Data/SpellCategories.lua). Output is a
# candidate report for human review (signals are heuristic; trigger-based effects
# and variants produce noise). Re-run per patch with fresh CSVs.
set -euo pipefail
cd "$(dirname "$0")/.."
CSV="Documentation/wow_spell_csv"
pick() { ls "$CSV/$1".*.csv 2>/dev/null | head -1; }
SCO=$(pick SpellClassOptions); SN=$(pick SpellName); SCAT=$(pick SpellCategories); SE=$(pick SpellEffect)
for v in "$SCO" "$SN" "$SCAT" "$SE"; do [ -n "$v" ] || { echo "missing CSV" >&2; exit 1; }; done

# Curated IDs, tagged by category, from the moved data file.
awk '
  /local DEFENSIVE_SPELLS/      { c="DEF" }
  /local HEALING_SPELLS/        { c="HEAL" }
  /local CROWD_CONTROL_SPELLS/  { c="CC" }
  /local UTILITY_SPELLS/        { c="UTIL" }
  /\[[0-9]+\] = true/ { match($0,/\[[0-9]+\]/); print substr($0,RSTART+1,RLENGTH-2)"\t"c }
' Data/SpellCategories.lua > /tmp/cur.txt

awk -F',' '
  FNR==NR { split($0,a,"\t"); CUR[a[1]"_"a[2]]=1; next }      # curated tags
  FNR==1  { next }                                            # skip CSV headers
  FILENAME ~ /SpellClassOptions/ { if(($4+0)!=0) PLAYER[$2+0]=1; next }
  FILENAME ~ /SpellName/         { id=$1+0; nm=$0; sub(/^[0-9]*,/,"",nm); gsub(/"/,"",nm); NAME[id]=nm; next }
  FILENAME ~ /SpellCategories/ {
      sid=$NF+0; m=$7+0
      if(m==1||m==2||m==5||m==7||m==9||m==10||m==12||m==13||m==17||m==18||m==20||m==24||m==30) CCSIG[sid]=1
      next }
  FILENAME ~ /SpellEffect/ {
      sid=$NF+0; eff=$5+0; aura=$2+0
      if(eff==10||eff==67||eff==75||eff==117||eff==136||aura==8||aura==62) HEALSIG[sid]=1
      if(aura==14||aura==39||aura==40||aura==69||aura==77||aura==87||aura==101||aura==113||aura==114||aura==125||aura==126||aura==143||aura==160||aura==255) DEFSIG[sid]=1
      if(eff==68) INTSIG[sid]=1
      next }
  END {
      for(id in PLAYER){
          if(!(id in NAME) || NAME[id]=="") continue
          if((id in HEALSIG) && !((id"_HEAL") in CUR)) print "HEAL\t"id"\t"NAME[id]
          if((id in DEFSIG)  && !((id"_DEF")  in CUR)) print "DEF\t" id"\t"NAME[id]
          if((id in INTSIG)  && !((id"_CC")   in CUR)) print "INT\t" id"\t"NAME[id]
          if((id in CCSIG)   && !((id"_CC")   in CUR)) print "CC\t"  id"\t"NAME[id]
      }
  }
' /tmp/cur.txt "$SCO" "$SN" "$SCAT" "$SE" > /tmp/cand.txt

for cat in INT CC DEF HEAL; do
    label=$cat
    [ "$cat" = INT ] && label="INTERRUPT (Effect=InterruptCast, vs CC list)"
    [ "$cat" = CC ]  && label="CROWD CONTROL (spell-level Mechanic)"
    [ "$cat" = DEF ] && label="DEFENSIVE (mitigation/absorb/immunity aura)"
    [ "$cat" = HEAL ]&& label="HEALING (heal effect or periodic-heal aura)"
    n=$(awk -F'\t' -v c="$cat" '$1==c{print $3}' /tmp/cand.txt | sort -u | wc -l | tr -d ' ')
    echo "=== $label - $n candidates not in list (deduped by name; sample) ==="
    awk -F'\t' -v c="$cat" '$1==c{print "  "$2"  "$3}' /tmp/cand.txt | sort -t' ' -k2 -u | head -25
    echo ""
done
rm -f /tmp/cur.txt /tmp/cand.txt
