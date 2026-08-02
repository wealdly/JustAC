# JustAC priority-logic audit - 2026-07-19

Audit of the SimC/AC priority ranking pipeline, triggered by the Balance Druid mis-ordering report.
Swept all 13 classes plus three cross-cutting investigations of the shared pipeline.

**Caveat: findings are single-pass and unverified.** The verification sweep did not run, so treat
spec-specific rank and spell-ID claims as leads, not facts, and spot-check exact numbers before
acting on them. Confidence in the *mechanisms* is high (the per-class sweeps converged on the same
handful of root causes independently); confidence in any individual number is not.
The Balance chain (Sunfire 93402 absent, moonfire 326646, kotg_st ordering) was confirmed by hand.

**Totals: 193 findings - 35 critical, 74 major, 84 minor.**


## DEATHKNIGHT_1

### [CRITICAL] Blood soul_reaper ranked 5th in st with every source condition lost (execute window, reaper_of_souls buff, active_enemies<=2 all dropped) - suggested top-of-queue all fight outside execute (Data/SimcRotations.lua:25)
Source (deathknight_blood.simc:33-34,46,73) only casts soul_reaper with buff.reaper_of_souls.up OR target.time_to_pct_35<5, and only at active_enemies<=2. Generated: {id=343294,gates={},delegated=true} at rank 5, above reapers_mark/blood_boil/death_and_decay/marrowrend/heart_strike. Losses: 'target.time_to_pct_35<5' matches no classify_atom pattern (the execute regex only knows target.health.pct|target.time_to_die) -> delegated, no {t=execute}; 'buff.reaper_of_souls.up' -> resolve None -> delegated; 'active_enemies<=2' -> silently dropped from ALL tiers (entry-level target-count atoms are never applied - see the desecrate finding). delegated only sinks on resource starvation and Soul Reaper costs 1 rune, so in simc mode Blood shows Soul Reaper in the first refined slots for the entire non-execute phase - the exact Balance-Druid-symptom class. (Unholy's st soul_reaper line 78 DID capture {t="execute"}, proving the pipeline can - but note the runtime never evaluates execute gates either.)

*Evidence:* Data/SimcRotations.lua:25 '{id=343294,gates={},delegated=true},  -- soul_reaper' rank 5 of 12; tools/simc-apl/deathknight_blood.simc:33-34 'soul_reaper,if=active_enemies<=2&buff.reaper_of_souls.up&...' / '...target.time_to_pct_35<5...'; gen_simc_rotations.py:120-121 execute regex lacks time_to_pct_*

*Fix:* Add target.time_to_pct_\d+ to the execute-gate regex; fix buff-token aura resolution; apply entry-level target-count atoms during the tier split.


## DEATHKNIGHT_2

### [CRITICAL] Frost soul_reaper ranked above the entire core rotation with all real conditions lost (reaper_of_souls unresolved; buff.killing_machine.react<2 misparsed into an inert positive gate) (Data/SimcRotations.lua:44)
Source (deathknight_frost.simc:61) gates soul_reaper on talent.reaper_of_souls & buff.reaper_of_souls.up & buff.killing_machine.react<2. Generated entry is {id=343294,gates={{t="buff",id=51128}},delegated=true} at st rank 8 / aoe rank 8 - ABOVE obliterate (rank 10), howling_blast (11), frost_strike (12). Three defects compound: (a) resolve('reaper_of_souls') returned None (469172 exists in SpellName CSV but is not reachable in the spec universe tiers), so the actual gating proc buff was silently dropped to delegation; (b) classify_atom uses prefix re.match(r'buff\.(\w+)\.(up|react|down)') so the atom 'buff.killing_machine.react<2' (a STACK COMPARISON meaning 'KM not capped') matched as a plain positive buff-up gate, discarding '<2' - near-inverted semantics; (c) the resolved id 51128 is the Killing Machine spec PASSIVE (the proc aura is 51124), so IsBuffWindowActive(51128) either never fires (passive has no duration -> DurationObjectActive false) or, if the probe treats the permanent passive as active, permanently promotes soul_reaper to the proc bucket for every Frost DK. Net in-game (simc mode): whenever Soul Reaper is off its short cooldown, it ranks above the Obliterate/Howling Blast/Frost Strike fillers in the queue - visibly wrong for the whole non-execute majority of every fight. The react<N prefix-misparse is systemic to any 'buff.X.react=N/<N' atom in any spec.

*Evidence:* Data/SimcRotations.lua:44 and :58 '{id=343294,gates={{t="buff",id=51128}},delegated=true},  -- soul_reaper'; tools/simc-apl/deathknight_frost.simc:61 'soul_reaper,if=talent.reaper_of_souls&buff.reaper_of_souls.up&buff.killing_machine.react<2'; tools/gen_simc_rotations.py:112-117 (prefix re.match, comparison tail ignored); CSV: 51124='Killing Machine' (proc) vs 51128='Killing Machine' (passive), 469172='Reaper of Souls' exists

*Fix:* In classify_atom, anchor the buff regex to the full atom (re.fullmatch or add $) so comparison atoms fall through to delegation; resolve buff tokens against aura ids, not the castable universe (see the systemic buff-id finding); investigate why 469172 is outside the resolver universe (hero-tree trait rows).

### [MINOR] mind_freeze (interrupt) is rank 1 in both Frost contexts with its 'target is casting' condition lost to delegation (Data/SimcRotations.lua:37)
Source high_prio_actions 'mind_freeze,if=target.debuff.casting.react' (deathknight_frost.simc:66) delegates entirely (unsupported token), leaving the interrupt as the #1 simc priority in st and aoe. Inert as long as AC's fixed rotation never offers Mind Freeze; becomes a visible top-slot squatter if a user adds it to a custom queue in simc mode (costless, off cooldown most of the time, never starved).

*Evidence:* Data/SimcRotations.lua:37,51; tools/simc-apl/deathknight_frost.simc:66

*Fix:* Add interrupts (mind_freeze, kick-class tokens) to the SKIP set - JustAC has a separate interrupt path.


## DEATHKNIGHT_3

### [MAJOR] desecrate (AoE-only in source: active_enemies>=2) ranked 4th in the SINGLE-TARGET list - entry-level target-count conditions are never applied despite the code comment claiming the tier split handles them (Data/SimcRotations.lua:72)
classify_atom returns (None, False) for spell_targets/active_enemies atoms with the comment 'target count -> handled by the tier split' (gen_simc_rotations.py:122-123), but flatten() applies call_applies() ONLY to call_action_list/run_action_list conditions (lines 187-196) - entry-level target-count atoms are silently dropped in EVERY tier. deathknight_unholy.simc:122 gates desecrate on active_enemies>=2&(...), yet the generated st (k=1) list includes it at rank 4, above dark_transformation/apocalypse/outbreak/scourge_strike. A desecrate-talented Unholy player in single target gets an AoE ground effect ranked 4th in simc mode. Same mechanism dropped Blood soul_reaper's active_enemies<=2 (folded into that finding). Systemic generator defect affecting all specs.

*Evidence:* Data/SimcRotations.lua:72 '{id=1234559,gates={},delegated=true},  -- desecrate' in st; tools/simc-apl/deathknight_unholy.simc:122 'desecrate,if=active_enemies>=2&(...)'; gen_simc_rotations.py:122-123 vs 178-199

*Fix:* In make_entry, evaluate entry-level target-count atoms with call_applies(cond, k) and drop the entry from tiers where they fail (requires threading k into make_entry).

### [MAJOR] split_and ignores SimC operator precedence: '&' binds tighter than '|', so A&B|C&D emits gates from OPPOSITE OR-branches as jointly required (death_coil requires Sudden Doom up AND Vampiric Strike down simultaneously) (Data/SimcRotations.lua:77)
split_and splits on every depth-0 '&' even when a depth-0 '|' is present, so 'buff.sudden_doom.react&talent.doomed_bidding|set_bonus.tww2_4pc&...&!buff.vampiric_strike.react' (deathknight_unholy.simc:147, san_fishing death_coil) becomes atoms [sudden_doom.react] [doomed_bidding|set_bonus] [...] [!vampiric_strike.react] - the first and last from DIFFERENT OR branches, both emitted as required gates: {t=buff,id=49530},{t=buff,id=433901,neg=true}. Correct handling: a depth-0 '|' makes the whole expression compound -> delegate-only (as classify_atom already does for parenthesized ORs). Second instance: cleave festering_strike (line 91) carries {t=buff,id=433901,neg=true} although the 'buff.festering_scythe.react' OR-branch (deathknight_unholy.simc:129) should bypass it. Today mostly inert (wrong aura ids, neg gates unevaluated), but it poisons the data for the pending SimC gate layer. Systemic to all specs.

*Evidence:* gen_simc_rotations.py:83-96 split_and has no '|' depth-0 check; Data/SimcRotations.lua:77 '{id=47541,gates={{t="buff",id=49530},{t="buff",id=433901,neg=true}},delegated=true}'; tools/simc-apl/deathknight_unholy.simc:147

*Fix:* In classify_if, if the expression contains a depth-0 '|', emit no gates and set delegated (or properly parse precedence).

### [MINOR] Malformed id-less gate {t="dot"} on cleave outbreak - dot.virulent_plague.refreshable resolved to None (debuff name not in the castable universe) and gate_lua silently emits a dot gate with no id (Data/SimcRotations.lua:88)
cds_aoe outbreak (deathknight_unholy.simc:93) has a bare 'dot.virulent_plague.refreshable' atom; classify_atom returns {t:'dot', id:resolve('virulent_plague')} where resolve fails (Virulent Plague 191587 is a debuff, not a castable, so it is outside the resolver universe; multiple same-name ids exist), producing {"t":"dot","id":None} which gate_lua emits as '{t="dot"}'. The runtime currently never evaluates dot gates (only positive buff gates, SpellQueue.lua:445-455), so this is dead data today - but it is a nil-id landmine for the planned gate evaluator, and the exact pattern behind DRUID_1's observations. Related generator defect: classify_atom discards negation on dot atoms ('!dot.frost_fever.ticking' produces the same gate as the positive form) - polarity is unrepresentable.

*Evidence:* Data/SimcRotations.lua:88 '{id=77575,gates={{t="dot"}},delegated=true},  -- outbreak'; gen_simc_rotations.py:108-110 (no None-check, neg dropped), 203-209 (gate_lua omits missing id); CSV: 191587 'Virulent Plague'

*Fix:* In make_entry's uniq loop, convert a dot gate with id=None to delegation (drop the gate, set delegated=True); carry neg on dot gates or delegate negated dot atoms.

### [MINOR] First-reach dedup across collapsed hero-tree branches gives core spenders San'layn-only gates: st scourge_strike is gated on Infliction of Sorrow, losing the generic (non-San'layn) pop-wounds semantics (Data/SimcRotations.lua:76)
Because san_fishing (San'layn-only list) is walked before san_st/st and dedup keeps the first entry, st scourge_strike carries {t=buff,id=434143} (Infliction of Sorrow, San'layn hero talent) and death_coil carries san_fishing's conditions - the non-San'layn st list's scourge_strike/death_coil conditions (pop_wounds, spend_rp) are discarded for ALL builds. For a Deathbringer/Rider Unholy player the promotion gate references a buff they can never have (inert), so they get plain rank order; harm is capped at 'intended conditional never applies', not misordering (ranks 8/9 sit correctly below the CD block). Design limitation of branch-collapse + id-dedup worth recording for the synthesis: gates from one hero tree silently become the canonical gates for every build of the spec.

*Evidence:* Data/SimcRotations.lua:76-77 vs tools/simc-apl/deathknight_unholy.simc:145,147 (san_fishing) and :177-183 (non-San'layn st list); gen_simc_rotations.py:178-199 first-reach dedup

*Fix:* When deduping, prefer the entry from an unconditionally-reached list over one from a hero-tree-conditional list, or merge gates as alternatives rather than keeping the first.


## DEMONHUNTER_1

### [CRITICAL] DEMONHUNTER_1: immolation_aura and glaive_tempest emitted with ids no other Data table uses - both unrankable at runtime (Data/SimcRotations.lua:120)
Havoc immolation_aura emitted as 320377 while the canonical castable id is 258920 (and the sibling Vengeance block picked yet another id, 320378 - same-token-three-ids across specs, the moonfire 8921-vs-326646 pattern). glaive_tempest emitted as 1244557 while SpellArchetypes carries Glaive Tempest as 342817. GetEntry on AC's real ids misses (FindSpellOverrideByID cannot bridge rank-variants), so in simc mode Havoc's Immolation Aura and Glaive Tempest fall to rank 900 and sink below every ranked entry every time they come off cooldown - a common-situation visible mis-order. Side effect: immolation_aura's non-delegated gate never applies either.

*Evidence:* Data/SimcRotations.lua:120 {id=320377,gates={{t="buff",id=191427,neg=true}}} immolation_aura; :123 {id=1244557} glaive_tempest; vs SpellCooldowns.lua:643 [258920] Immolation Aura, SpellArchetypes.lua:2922 [258920], :3295 [342817] Glaive Tempest. 320377 and 1244557 appear only in SimcRotations.lua.

*Fix:* Curate immolation_aura=258920 (both DH specs) and verify glaive_tempest's current castable id against the client-data CSVs (342817 unless genuinely renumbered in 12.x); regenerate.

### [CRITICAL] DEMONHUNTER_1 st order inversion: opener/special-case first-reach defines permanent ranks - Chaos Strike rank 2, Eye Beam rank 12 under movement abilities, Demon's Bite filler above Sigil of Flame (Data/SimcRotations.lua:111)
flatten() dedups by first reach and walks call_action_list/run_action_list unconditionally when they carry no target-count atom (call_applies ignores time<15, hero_tree, buff conditions - gen_simc_rotations.py:142-152,186-199). In demonhunter_havoc.simc the ar list opens with glaive-flurry special cases and calls ar_opener (time<15 only) at line 56, before the general rotation (lines 60-91). Result: chaos_strike ranked 2 from the special-case line 49 (generic spender is line 85, below eye_beam 75/blade_dance 77/glaive_tempest 81); vengeful_retreat(6)/felblade(7)/fel_rush(8)/essence_break(9)/blade_dance(10) all outrank eye_beam(12) purely because ar_opener was spliced in; demons_bite(13, filler, first reached at ar_opener line 202) outranks sigil_of_flame(15, first reached in ar_fel_barrage line 133) even though the APL main list orders sigil_of_flame (79/88) above demons_bite (89). In simc mode with fury available, Chaos Strike is pinned at slot 2 and Eye Beam sits below fillers - every GCD, single target. Generator behaved as coded; the flattening intent (priority order product) is what's violated.

*Evidence:* Generated ranks Data/SimcRotations.lua:109-127 (chaos_strike 2, vengeful_retreat 6, felblade 7, fel_rush 8, essence_break 9, blade_dance 10, eye_beam 12, demons_bite 13, sigil_of_flame 15) vs tools/simc-apl/demonhunter_havoc.simc:49 (conditional chaos_strike), :56 (run_action_list ar_opener,if=...time<15), :75-89 (real st order eye_beam>blade_dance>sigil_of_flame>felblade>glaive_tempest>chaos_strike>immolation_aura>demons_bite). Re-traced flatten() by hand; generated list matches the walk exactly.

*Fix:* In the flattener, treat opener-ish branches (if= containing time< with no other evaluable atom) as lower priority or skip them for ranking, and/or dedup keeping the LEAST-conditional reach instead of the first reach.

### [MAJOR] Positive buff-gate ids are talent/cast spell ids, not the aura ids the runtime probes - Havoc's buff-window promotions can never fire (Data/SimcRotations.lua:115)
BlizzardAPI.IsBuffWindowActive (CooldownTracking.lua:523-532) resolves the gate id via C_UnitAuras.GetPlayerAuraBySpellID - it needs the actual aura id. The generator resolves buff.X tokens by spell NAME against the talent/spell universe (simc_bridge), emitting the talent/cast id: vengeful_retreat and essence_break carry {t="buff",id=191427} (Metamorphosis CAST id; the Havoc meta aura is 162264), felblade/fel_rush carry {t="buff",id=347461} (Unbound Chaos talent; aura is 347462) and {t="buff",id=388108} (Initiative talent; aura is 391215). None of these aura-mismatched ids appear in Data/SelfAuras.lua. Consequence: the proc-style promotion for these entries (SpellQueue.lua:445-455,529-535) silently never triggers - fail-safe but the entire gate-layer product is dead for these entries. (Cannot verify 12.x aura ids offline; flagging as the structural risk: the resolver consults no aura table, and cast-id==aura-id only holds for some spells.)

*Evidence:* Data/SimcRotations.lua:115-118 (positive buff gates 191427/347461/388108); CooldownTracking.lua:528 GetPlayerAuraBySpellID(spellID); SelfAuras.lua contains none of 191427/347461/388108/162264.

*Fix:* Have the generator resolve buff.X tokens through an aura-id mapping (e.g. the SpellName ids that actually appear as player auras, or a curated buff map validated against Data/SelfAuras.lua) instead of the castable-spell universe.

### [MAJOR] Entry-level active_enemies/spell_targets conditions silently dropped - DH gets no st/aoe differentiation at all and AoE-only abilities are ranked in single-target (tools/gen_simc_rotations.py:122)
classify_atom returns (None, False) for target-count atoms with the comment 'handled by the tier split', but the tier split (call_applies) is only applied to call_action_list/run_action_list lines (flatten, lines 186-199) - never to an entry's own if=. Both DH APLs put ALL target-count logic in entry conditions and none in call conditions, so the st/cleave/aoe flattens are signature-identical and only a single st list is emitted per spec (Data/SimcRotations.lua has no aoe block for either DEMONHUNTER spec). Concrete carriers: Havoc fel_rush ranked 8 in st from an active_enemies>2 line (havoc.simc:181), throw_glaive rank 16 from an active_enemies=3 line (:164), chaos_nova rank 17 from talent.chaos_fragments&active_enemies>4 (:83) - emitted with gates={} and NOT delegated, i.e. the sole distinguishing condition vanished without even the delegated fallback; Vengeance spirit_bomb rank 14 from a spell_targets>=12 line (vengeance.simc:56), bulk_extraction's spell_targets>=3 (unresolved anyway).

*Evidence:* gen_simc_rotations.py:122-123 ('return None, False  # target count -> handled by the tier split') vs :186-199 (call_applies only on call/run lines); Data/SimcRotations.lua:108-148 (st-only blocks for both DH specs); demonhunter_havoc.simc:83,164,181; demonhunter_vengeance.simc:52,56.

*Fix:* In make_entry, evaluate target-count atoms with call_applies(k) per tier: exclude the entry (or at least mark delegated) when the atom fails at that tier. This restores per-tier lists for entry-conditioned APLs.

### [MINOR] cd gates drop the referenced spell and the comparison sense; some reference other spells' cooldowns or non-spells (tools/gen_simc_rotations.py:107)
classify_atom matches cooldown.<name>.(ready|up|remains) by prefix and emits a bare {t="cd"} - the <name> (often a DIFFERENT spell) and the operator (remains vs remains<=X vs up) are discarded. DH examples: sigil_of_spite's {t="cd"} actually encodes 'blade_dance is ON cooldown' (havoc.simc:119), vengeful_retreat/essence_break cd gates encode blade_dance/eye_beam comparisons, and Vengeance demon_spikes' {t="cd"} comes from !cooldown.pause_action.remains where pause_action is not even a spell (vengeance.simc:28), with the negation dropped. Currently harmless only because the runtime never evaluates cd gates (SpellQueue consumes only positive buff gates and the delegated flag) - but the data is misleading and will misfire if a cd-gate evaluator is ever added.

*Evidence:* gen_simc_rotations.py:107-108; Data/SimcRotations.lua:114,115,118,133; SpellQueue.lua:445-455 (only t=="buff" and not neg is consumed), grep shows no other g.t consumer.

*Fix:* Either emit {t="cd",id=<resolved spell>,neg=<sense>} or stop emitting cd gates until a consumer exists.

### [MINOR] DEMONHUNTER_1 Disrupt (interrupt) ranked 1 with no gates and no delegated flag (Data/SimcRotations.lua:110)
Havoc's APL has a bare 'actions+=/disrupt' (havoc.simc:24) so the entry is {id=183752,gates={}} at rank 1 (Vengeance's is at least delegated via target.debuff.casting.react). Interrupts are not in the generator's SKIP set. If AC's rotation ever includes Disrupt, simc mode pins the interrupt at the front of positions 2+ permanently; otherwise dead data. InterruptAbilities.lua already owns interrupt handling.

*Evidence:* Data/SimcRotations.lua:110 vs :131; demonhunter_havoc.simc:24; gen_simc_rotations.py:37-47 (SKIP lacks disrupt/kick-class actions); InterruptAbilities.lua:31.

*Fix:* Add interrupts to SKIP (they're covered by the dedicated interrupt engine).

### [MINOR] Havoc Metamorphosis-override spells (annihilation, death_sweep) and reavers_glaive/fel_barrage are unresolved residue - ranks depend on runtime override resolution working in the AC->base direction (Data/SimcRotations.lua:108)
annihilation/death_sweep/reavers_glaive/fel_barrage never appear in the generated block (unresolved tokens, fail-safe by design). During Metamorphosis, AC will recommend Annihilation/Death Sweep; GetEntry falls back to m[baseID(spellID)] where baseID=FindSpellOverrideByID (SpellQuery.lua:365-373) - which maps base->override, i.e. the WRONG direction for an AC-supplied override id. Whether Annihilation inherits chaos_strike's rank therefore depends on which id AC hands over; if AC supplies 201427/210152, both meta spenders are unranked (900) during every meta window. reavers_glaive (the Aldrachi Reaver centerpiece) is simply unranked. Worth an in-game check via /jac inspect.

*Evidence:* Data/SimcRotations.lua:108-127 (no annihilation/death_sweep/reavers_glaive/fel_barrage entries); RotationImport.lua:90-93,146 (baseID via ResolveSpellID = FindSpellOverrideByID, base->override only).

*Fix:* Curate annihilation->162794-adjacent handling (e.g. also index entries under FindBaseSpellByID of AC ids at lookup time) and add reavers_glaive/fel_barrage to CURATED.


## DEMONHUNTER_2

### [CRITICAL] DEMONHUNTER_2: four core Vengeance abilities emitted with non-castable spell ids (rank-passive variants), so AC's real spells can never match their SimC rank (Data/SimcRotations.lua:135)
The resolver picked wrong same-name ids for fel_devastation (320639; canonical castable 212084), shear (203783; canonical 203782, Fracture 263642 overrides it), immolation_aura (320378; canonical 258920), fiery_brand (320962; canonical 204021). Runtime RotationImport.GetEntry matches AC's spell id directly or via BlizzardAPI.ResolveSpellID, which is FindSpellOverrideByID only (SpellQuery.lua:365-373) - it maps base->current override, never rank-passive->castable. So in simc mode GetEntry(212084/203782/258920/204021) misses, rankOf returns 900 (SpellQueue.lua:468-470), and Fel Devastation, Fracture/Shear, Immolation Aura and Fiery Brand all sink below every ranked spell (below throw_glaive rank 17) permanently. Visible constantly: builders and maintenance pinned at the back of the Vengeance queue while Soul Cleave (correctly-ranked 228477, rank 6) sits at the front. Same defect class as the Balance moonfire 326646 report.

*Evidence:* Data/SimcRotations.lua:135 {id=320639} fel_devastation, :137 {id=203783} shear, :142 {id=320378} immolation_aura, :139 {id=320962} fiery_brand. Addon's own mirrors use the other ids: SpellCooldowns.lua:591 [212084] Fel Devastation, :643 [258920] Immolation Aura, :553 [204021] Fiery Brand; SpellArchetypes.lua:1714/2836 [203782] Shear, :3254 [212084], :2922 [258920]; ChanneledSpells.lua:45 [212084]; SelfAuras.lua:697 [212084]; SpellCategories.lua:26 [204021]. None of 320639/203783/320378/320962 appear in any other Data table.

*Fix:* Add DEMONHUNTER_2 CURATED entries in tools/gen_simc_rotations.py: fel_devastation=212084, shear=203782, immolation_aura=258920, fiery_brand=204021 (and fix the resolver preference tiers to prefer ids that appear in the shipped Data mirrors); regenerate.

### [CRITICAL] DEMONHUNTER_2 st order inversion: Soul Cleave (6) and Shear (7) ranked from glaive-flurry special-case lines, above The Hunt/Fiery Brand/Soul Carver/Sigil of Spite/Immolation Aura/Sigil of Flame (Data/SimcRotations.lua:136)
First-reach dedup: soul_cleave's rank comes from demonhunter_vengeance.simc:40 (only when !rending_strike & glaive_flurry - an Aldrachi Reaver empowerment window) and shear's from :42 (glaive_flurry up). The generic soul_cleave is line 57 and the shear fillers lines 55/62 - BELOW sigil_of_spite(49), immolation_aura(51), sigil_of_flame(54) in the source. Generated ranks invert this permanently: soul_cleave 6 / shear 7 above the_hunt 8, fiery_brand 9, soul_carver 10, sigil_of_spite 11, immolation_aura 12, sigil_of_flame 13. Since soul_cleave (228477) is a correctly-resolved id, the visible effect in simc mode is Soul Cleave pinned near the front whenever affordable (delegated only sinks it when fury-starved) while every maintenance/cooldown ability queues behind it - and the mis-id'd shear/immolation_aura (previous finding) sink to the very back, so the queue reads spender-first, builder-last: the exact user-complaint shape.

*Evidence:* Data/SimcRotations.lua:136 soul_cleave rank 6 delegated, :137 shear rank 7, :138-143 the_hunt/fiery_brand/soul_carver/sigil_of_spite/immolation_aura/sigil_of_flame ranks 8-13; tools/simc-apl/demonhunter_vengeance.simc:40,42 (conditional), :54,55,57,62 (generic order sigil_of_flame > shear > soul_cleave fillers).

*Fix:* Same dedup fix as the Havoc finding: rank an ability from its least-conditional occurrence, not its first conditional one.

### [MAJOR] Hero-tree branch collapse ranks Fel-Scarred players by the Aldrachi Reaver list - FS-specific top-priority actions inherit AR's (lower) ranks (Data/SimcRotations.lua:142)
Both DH APLs branch main into run_action_list ar / fs by hero_tree; call_applies ignores hero_tree so both are walked, AR first, and first-reach wins every rank and gate. IsPlayerSpell cannot re-sort this because all the spell ids are shared between hero trees. Vengeance FS example: the fs list opens with immolation_aura (vengeance.simc:123-124), sigil_of_flame (:125-126) and fiery_brand (:127) at the very top, but the generated ranks (12, 13, 9) come from their much lower AR positions, sitting below the AR-special-case soul_cleave(6)/shear(7). A Fel-Scarred Vengeance player in simc mode gets an AR-shaped queue. Same applies to Havoc (fs list contributes zero entries - every token was already claimed by the ar walk).

*Evidence:* demonhunter_vengeance.simc:29-30 (run_action_list ar / fs by hero_tree), :123-127 (fs top actions) vs Data/SimcRotations.lua:139-143 (ranks 9/12/13 from AR reach); demonhunter_havoc.simc:39-40 and the hand re-trace showing fs adds no new entries.

*Fix:* Emit per-hero-tree lists (specKey + tree, selected at runtime via a hero-tree-unique IsPlayerSpell probe), or at minimum rank each token by the best reach across branches rather than lexical branch order.

### [MINOR] DEMONHUNTER_2 dot-gate negation lost and Fiery Brand absent from TargetDots; The Hunt keyed by dead covenant id (Data/SimcRotations.lua:139)
fiery_brand's '!dot.fiery_brand.ticking' became {t="dot",id=320962} - the dot branch of classify_atom ignores '!' (gen_simc_rotations.py:109-110), and the id is the wrong-variant 320962 besides. Separately, Data/TargetDots.lua has no Fiery Brand entry at all (cast 204021, debuff 207771), so the DotTracker sink never applies to it (moot in practice: 60s cd puts it in the cooldown bucket after cast). TargetDots also carries The Hunt as 323639 (the removed covenant-era cast id) while the live talent cast id is 370965 - DotTracker.OnCastSucceeded keys the cast id (DotTracker.lua:87-88), so IsTargetDot(370965) is false and The Hunt's dot entry is dead data. Mirrors the Sunfire 93402-missing pattern from the druid report.

*Evidence:* Data/SimcRotations.lua:139; Data/TargetDots.lua:65 [323639] The Hunt, no 204021/207771/370965 anywhere in the file; DotTracker.lua:87-88,192-201.

*Fix:* gen_target_dots.py: key The Hunt under 370965 and add Fiery Brand (204021) if the dot-sink should cover it; add neg to dot gates or document that dot gates are unevaluated.

### [MINOR] DEMONHUNTER_2 defensives/utility ranked at the top of the DPS queue: Infernal Strike rank 2 (unconditional), Demon Spikes rank 3, Metamorphosis rank 4 (Data/SimcRotations.lua:132)
The Vengeance APL's use_off_gcd defensive weave (infernal_strike bare at main:27, demon_spikes at :28, metamorphosis at ar:37) flattens into ranks 2-4 with infernal_strike carrying gates={} and no delegated - a movement leap ranked second whenever off cooldown. demon_spikes' buff gate uses the CAST id 203720 while the actual Demon Spikes buff aura is 203819 (Data mirrors carry only 203720; neg gate is unevaluated at runtime anyway). Impact depends on whether AC's fixed queue contains these spells (SpellCategories.lua:462 notes Infernal Strike deliberately kept because it does damage); if it does, simc mode pins the leap/defensives at slots 2-4 in single-target.

*Evidence:* Data/SimcRotations.lua:132-134; demonhunter_vengeance.simc:27-28,37; SpellCategories.lua:25 [203720], :462 (Infernal Strike kept).

*Fix:* Consider adding use_off_gcd-only defensive/mobility actions to SKIP or ranking them from their own priority tier.

### [MINOR] Talent conditions on OTHER spells are dropped, not covered by the IsPlayerSpell filter - e.g. Vengeance vengeful_retreat,if=talent.unhindered_assault ranked for all builds (Data/SimcRotations.lua:146)
classify_atom treats talent.X as 'IsPlayerSpell handles it' (gen_simc_rotations.py:124-125), but the runtime filter checks IsPlayerSpell(entry.id) only (RotationImport.lua:51,67) - it verifies the ENTRY is known, not that talent.X is taken. vengeance vengeful_retreat (if=talent.unhindered_assault, vengeance.simc:60) is emitted gates={} non-delegated at rank 16, so players without Unhindered Assault still get a backwards dash ranked in the queue. Same mechanism affects immolation_aura,if=talent.fallout (rank 12 regardless of Fallout) and Havoc chaos_nova's talent.chaos_fragments. Low visibility (bottom ranks) but a systemic gap between the design comment and the runtime.

*Evidence:* gen_simc_rotations.py:124-125; RotationImport.lua:51,67; Data/SimcRotations.lua:142,146,126; demonhunter_vengeance.simc:51,60; demonhunter_havoc.simc:83.

*Fix:* Emit a {t="talent",id=...} gate (IsPlayerSpell on the talent id is static and secret-safe) and filter entries on it in GetRotationGated/BuildLookup.


## DRUID_1

### [CRITICAL] Sunfire's cast id 93402 is absent from Data/TargetDots.lua, so the DoT sink never fires for Sunfire (mode-independent; direct cause of the user symptom) (tools/gen_target_dots.py:59)
Sunfire is script-applied exactly like Moonfire: cast 93402 has no APPLY_AURA periodic effect and no EffectTriggerSpell link to its DoT aura 164815, so the generator's trigger-link path (gen_target_dots.py:173-179) never maps it, and unlike Moonfire (CURATED 8921->164812 at line 61) there is no curated entry for 93402. TargetDots.lua ends up with only the aura id [164815]=18 (line 42, picked up by the 'aura in universe' direct branch) which UNIT_SPELLCAST_SUCCEEDED never delivers. Runtime chain: DotTracker.OnCastSucceeded (DotTracker.lua:87-90) receives cast id 93402, SpellDB.IsTargetDot(93402) is false, nothing is ever tracked -> DotTracker.IsDotActiveOnCurrentTarget(93402) is always false -> the dot sink in SpellQueue.lua:539-540 never sinks Sunfire. Sunfire therefore sits permanently in the normal bucket even with its DoT live, in BOTH 'ac' and 'simc' contextOrder modes. Moonfire does sink (TargetDots.lua:25 has [8921]=18), which is exactly why the user sees Sunfire stuck but not Moonfire.

*Evidence:* SpellEffect.12.1.0.68301.csv rows for SpellID 93402 (IDs 97908, 324053, 324054): Effect=3/3/30 (school damage, energize), EffectAura=0, EffectTriggerSpell=0 in all three -> no data link to aura 164815. Data/TargetDots.lua:25 '[8921]=18 -- Moonfire (base...)' vs no 93402 anywhere (only [164815]=18 at line 42). gen_target_dots.py CURATED (lines 59-71) lists 8921 but not 93402. DotTracker.lua:88 'if not SpellDB.IsTargetDot(spellID) then return'.

*Fix:* Add `93402: 164815,  # Sunfire - script-applies its DoT (no trigger link)` to CURATED in tools/gen_target_dots.py (plus CURATED_NAMES) and regenerate Data/TargetDots.lua. One line, mirrors the existing Moonfire 8921 entry.

### [CRITICAL] DRUID_1 'moonfire' resolves to 326646 (Balance spec-record 'Moonfire', not the castable 8921), so Moonfire is unranked in simc mode and its dot gate is keyed to a dead id (tools/simc_bridge.py:197)
SpecializationSpells has a Balance (SpecID 102) row granting SpellID 326646 named 'Moonfire' (a spec rank/passive record, OverridesSpellID=0), so it lands in _base_primary[102] = resolver tier 1. In resolver() (simc_bridge.py:196-201) the tier loop returns at the NARROWEST non-empty tier: hit = spec_index['moonfire'] & tier1 = {326646}, unique -> returns 326646 without ever reaching the skill-line tier that contains the real castable 8921. Feral avoids this only because its APL uses moonfire_cat, curated to 155625. Runtime effect: RotationImport.BuildLookup (RotationImport.lua:104-108) keys the rank record under 326646 and baseID(326646) (FindSpellOverrideByID no-ops on a passive -> still 326646); the queue looks up GetEntry(8921/display id) (SpellQueue.lua:515-516) -> nil -> rankOf returns 900 (SpellQueue.lua:470) -> in simc mode Moonfire always sinks below every ranked spell even when its DoT is missing. The emitted gate {t='dot',id=326646} also references an id no runtime system knows (currently inert, see the dot-gate finding).

*Evidence:* SpecializationSpells.12.1.0.68301.csv row ',6827,102,326646,0,9'; SpellName.12.1.0.68301.csv:209674 '326646,Moonfire'; Data/SimcRotations.lua:154 '{id=326646,gates={{t="dot",id=326646}}},  -- moonfire' (and :170 in aoe); simc_bridge.py:180-201 tier list + 'for tier in tiers: hit = ids & tier; if hit: return ...'; DRUID_2 feral uses curated 155625 (SimcRotations.lua:193).

*Fix:* Add a CURATED block for DRUID_1 in gen_simc_rotations.py: {"moonfire": 8921} (and while there, the residue: stellar_flare 202347, warrior_of_elune 202425, incarnation 102560, half_moon 274282, full_moon 274283). Structural alternative: in resolver(), reject a tier hit whose id is not also present in the class_index/SkillLineAbility castable set when a same-name castable exists there - but the one-line curation is the minimal correct fix.

### [CRITICAL] Sunfire cast id 93402 missing from Data/TargetDots.lua - Sunfire never sinks while its DoT is live (both ordering modes) (tools/gen_target_dots.py:59)
gen_target_dots.py only maps casts that either ARE a periodic-damage aura or have an EffectTriggerSpell link to one. Sunfire (cast 93402) script-applies its DoT aura 164815 with no trigger link - exactly the case CURATED exists for (Moonfire 8921->164812 IS curated, tools/gen_target_dots.py:61) - but Sunfire has no CURATED entry. Runtime flow: JustAC.lua:1712 -> DotTracker.OnCastSucceeded(93402) -> SpellDB.IsTargetDot(93402) (DotTracker.lua:88) -> StaticLookup(targetDots,93402) misses (no 93402 key; C_Spell.GetBaseSpell(93402)=self so no base retry, SpellDB.lua:180-192) -> early return, suppression window never armed. Then every queue build: SpellQueue.lua:536-540 sink test calls DotTracker.IsDotActiveOnCurrentTarget(93402) -> applied[] has no entry (DotTracker.lua:196-202) -> false -> Sunfire stays in the normal bucket forever, regardless of the live DoT. This is mode-independent (the sink is the only DoT mechanism in BOTH 'ac' and 'simc' ordering). Same root cause also disables the dot-spread arrow for Sunfire picks (SpellQueue.lua:663-671 IsTargetDot check). Moonfire (8921) IS tracked correctly, which is why the report names Sunfire as stuck but Moonfire only in simc mode.

*Evidence:* Data/TargetDots.lua:42 has only '[164815]=18, -- Sunfire' (the DEBUFF aura id, which never appears as a UNIT_SPELLCAST_SUCCEEDED cast id); no 93402 key anywhere in the file. Contrast Data/TargetDots.lua:25 '[8921]=18 -- Moonfire (base...)' from CURATED (tools/gen_target_dots.py:61-62). DotTracker.lua:87-91 gates all tracking on SpellDB.IsTargetDot(castSpellID).

*Fix:* Add '93402: 164815,  # Sunfire - script-applies its DoT (no trigger link)' to CURATED in tools/gen_target_dots.py (plus CURATED_NAMES) and regenerate Data/TargetDots.lua.

### [CRITICAL] DRUID_1 SimC data uses Moonfire id 326646 (spec-grant record) instead of castable 8921 - simc mode buries Moonfire at the 900 sentinel and its dot gate matches nothing (Data/SimcRotations.lua:154)
simc_bridge.py resolver tiers prefer SpecializationSpells (tier 1, simc_bridge.py:180-201). Balance's SpecializationSpells row grants a spell 326646 named 'Moonfire' (SpecializationSpells.12.1.0.68301.csv line 324: SpecID 102, SpellID 326646), which shadows the actual castable class-skill-line Moonfire 8921 (tier 3). So Data/SimcRotations.lua:154/170 emit id=326646 and dot-gate id=326646. At runtime AC's rotation list carries 8921: RotationImport.GetEntry(8921,'st') (SpellQueue.lua:515-516) -> m[8921] nil, m[baseID(8921)] nil (baseID=FindSpellOverrideByID, RotationImport.lua:90-93 - no override for Balance Moonfire; BuildLookup's extra key FindSpellOverrideByID(326646)=326646 helps nothing, RotationImport.lua:107-108) -> nil -> rankOf returns the 900 sentinel (SpellQueue.lua:468-470). Result in simc mode: when Moonfire's DoT is down/refreshable (i.e. it SHOULD be suggested) it sorts after every ranked ability (wrath 1, starfire 2, sunfire 4, fury 5, ... wild_mushroom 12) and effectively never fits maxIcons. The rank-3 slot is a phantom (326646 never matches a queue spell). The dot-gate id 326646 also can never match DotTracker's cast/base keys (visible in /jac inspect gates, DebugCommands.lua:1576-1578, which will always print 'refresh'). Feral is unaffected because CURATED['DRUID_2'] pins moonfire_cat=155625 (gen_simc_rotations.py:54-58) and GetBaseSpell(155625)=8921 bridges DotTracker.

*Evidence:* Data/SimcRotations.lua:154 '{id=326646,gates={{t="dot",id=326646}}}, -- moonfire' and :170 (aoe). SpellName CSV: 326646='Moonfire'. SpecializationSpells CSV row ',6827,102,326646,0,9'. DRUID_4 (no spec-grant collision) correctly resolved moonfire=8921 (Data/SimcRotations.lua:243).

*Fix:* Add CURATED['DRUID_1'] = {'moonfire': 8921} in tools/gen_simc_rotations.py (CURATED dict, line 53) and regenerate. Consider a bridge self-check asserting every emitted id is castable (present in SkillLineAbility/known-cast set).

### [CRITICAL] Sunfire cast id 93402 missing from Data/TargetDots.lua (only debuff aura 164815 present) - Sunfire NEVER sinks while its DoT is live, in BOTH contextOrder modes (Data/TargetDots.lua:42)
DotTracker.OnCastSucceeded(spellID) (DotTracker.lua:87-91) early-returns unless SpellDB.IsTargetDot(castID) hits; the cast event carries 93402, but TargetDots has only [164815]=18 (the Sunfire DEBUFF aura id, which no cast event ever carries; base-spell resolution of 93402 does not reach 164815). So casting Sunfire never arms the suppression window and IsDotActiveOnCurrentTarget(93402) is always false -> the dot-sink branch in SpellQueue.lua:539-540 never fires for Sunfire. This is mode-independent (the dot sink runs in both 'ac' and 'simc' ordering) and directly explains the user report of Sunfire permanently in a front slot with the DoT applied. Root cause in tools/gen_target_dots.py: Sunfire is script-applied exactly like Moonfire and Immolate, but only Moonfire (8921->164812) and Immolate (348->157736) were added to CURATED (lines 59-71); Sunfire was not, so only the bare aura record 164815 leaked into the table via the universe membership path (gen_target_dots.py:170-172). Affects every Sunfire-casting druid spec (DRUID_1 primary, DRUID_4 too).

*Evidence:* Data/TargetDots.lua:42 '[164815]=18,  -- Sunfire' with no 93402 row; Data/TargetDots.lua:25 '[8921]=18, -- Moonfire (base...)' shows the curated pattern Sunfire lacks; tools/gen_target_dots.py:59-71 CURATED has 8921 and 348 but no 93402; DotTracker.lua:88 'if not ... SpellDB.IsTargetDot(spellID) then return'; SpellDB.lua:247-249 IsTargetDot = StaticLookup(targetDots, id) with only base-spell fallback; wow_spell_csv SpellName: 93402=Sunfire (cast), 164815=Sunfire (aura).

*Fix:* Add 93402: 164815 to gen_target_dots.py CURATED (mirroring the Moonfire entry) and regenerate; optionally drop/keep 164815 and 164812 aura-keyed rows (they are dead as cast keys).

### [CRITICAL] DRUID_1 st ranks are flattened from the kotg_st TWW3-4pc set-bonus branch, not the standard st list: wrath/starfire (conditional eclipse-refresh casts) become ungated ranks 1-2 and sunfire loses its dot gate AND delegated flag entirely (Data/SimcRotations.lua:155)
druid_balance.simc main runs kotg_st (line 49, if=variable.tww3_keeper_4pc&spell_targets=1) BEFORE st (line 50, if=!variable.tww3_keeper_4pc&spell_targets=1). run_action_list branches are mutually exclusive and tww3_keeper_4pc (a set_bonus variable) is false for most players, but flatten()/call_applies (gen_simc_rotations.py:144-152, 178-199) only test target-count atoms, so BOTH lists merge with kotg_st winning every first-reach dedup slot. Consequences at k=1: (a) wrath rank 1 and starfire rank 2 come from kotg_st lines 88-89 - narrow eclipse-edge refresh casts whose compound conditions collapse to gates={} delegated - while the source's unconditional wrath/starfire fillers are the BOTTOM of st (lines 163-164) and sunfire/moonfire maintenance sit above them (lines 138-139); (b) sunfire's first reach is kotg_st line 91 whose conditions are all in target_if= ('remains<(3>?fight_remains)|...') which make_entry (gen_simc_rotations.py:156-175) neither classifies as gates NOR marks delegated (only mods['if'] is classified; target_if is only mined for refreshable/ticking/dot.<token>), emitting {id=93402,gates={},delegated=false} at rank 4 - a falsely 'unconditionally castable' maintenance DoT; the st-branch sunfire (line 138, target_if=remains<3|refreshable..., which WOULD produce {t='dot',id=93402} like the aoe entry at SimcRotations.lua:171) is unreachable due to dedup. In simc mode the visible queue for Balance ST is therefore starfire+sunfire filling positions 2-3 permanently (AC holds pos 1), exactly the user report; combined with the TargetDots miss, sunfire cannot even be sunk by DotTracker.

*Evidence:* Data/SimcRotations.lua:151-164 (st: wrath r1 gates={} delegated, starfire r2, moonfire r3, sunfire r4 gates={} NOT delegated); tools/simc-apl/druid_balance.simc:49-51 (branch calls), 86-124 (kotg_st: wrath 88, starfire 89, moonfire 90, sunfire 91), 134-164 (st: sunfire remains<3 at 138 ABOVE fillers; unconditional wrath/starfire at 163-164); regenerated output is byte-identical to shipped data (verified via SIMC_OUT diff), so this is current generator behavior, not stale data.

*Fix:* Make flatten honor run_action_list exclusivity (stop after the first run_action_list whose condition holds, or prefer the branch with no set_bonus/hero-tree variable in its condition), and make make_entry treat unclassifiable target_if content the same as unclassifiable if content (delegated=true) and classify remains< atoms in target_if as its dot gate.

### [CRITICAL] DRUID_1 moonfire resolves to 326646 (Balance spec-granted PASSIVE 'Moonfire' record), not the cast id 8921 - rank lookup can never match AC's moonfire, so Moonfire is unranked (900) in simc mode (Data/SimcRotations.lua:154)
simc_bridge resolver tier preference (simc_bridge.py:196-201) resolves at the narrowest non-empty tier; for Balance the 'moonfire' slug candidates are {8921, 164812, 326646} and tier 1 (_base_primary = SpecializationSpells SpellID column) contains only 326646 (SpecializationSpells row SpecID=102 SpellID=326646 - the Balance astral-power passive named 'Moonfire'), so 326646 wins over the class-learned cast 8921 (verified by running the bridge offline: resolve('moonfire') -> 326646, '8921 in base_primary' -> False). Runtime effect: RotationImport.BuildLookup (RotationImport.lua:95-116) keys the rank record under 326646 and baseID(326646) (FindSpellOverrideByID, which won't map a passive to 8921); the queue calls GetEntry with AC's rotation ids (8921/155625) -> miss -> rank 900 sentinel -> Moonfire sinks below every ranked entry in simc mode even when the DoT needs applying. Also IsPlayerSpell(326646) filters it out of GetRotation, and the emitted {t='dot',id=326646} gate references a non-cast id. Same-token-different-id across specs confirmed: DRUID_2 curates moonfire_cat=155625, DRUID_3/DRUID_4 auto-resolve moonfire=8921 (SimcRotations.lua:232, 243).

*Evidence:* Data/SimcRotations.lua:154 '{id=326646,gates={{t="dot",id=326646}}},  -- moonfire' vs :232/:243 using 8921; wow_spell_csv SpecializationSpells: ',6827,102,326646,0,9'; offline bridge probe: moonfire candidates {'8921','164812','326646'}, resolve('moonfire')=326646; RotationImport.lua:104-108 lookup keyed only by e.id and its FindSpellOverrideByID variant.

*Fix:* Add DRUID_1 curated entry moonfire=8921 in gen_simc_rotations.py CURATED (and/or make the bridge exclude passive records - SpellMisc attribute check - from the resolution tiers).

### [CRITICAL] Data/TargetDots.lua has no key for Sunfire's cast spell id 93402 - Sunfire's maintained-DoT sink never engages (tools/gen_target_dots.py:59)
Root cause of the reported symptom (Sunfire stuck in the front suggestion slots even with the debuff already applied). Sunfire has two distinct spell IDs in this build: 93402 (the talent-tree-granted, player-castable spell; TraitDefinition.12.1.0.68301.csv row ID=121114, SpellID=93402, OverridesSpellID=0 - confirmed player-learnable via the generator's own 'universe' construction, and independently confirmed as the resolvable token by tools/simc_bridge.py: resolver('DRUID','Balance',{})('sunfire') == 93402) and 164815 (the debuff/self-contained cast+aura variant, SkillLineAbility row ID=33904, SkillLine=798, Spell=164815). SpellEffect.12.1.0.68301.csv shows 93402's effects are Effect=3 (direct damage, EffectIndex 0/1) and Effect=30 (script effect, EffectIndex 2, targeting caster) - NO Effect=6/APPLY_AURA row at all, so it never satisfies gen_target_dots.py's periodic-damage classifier (PERIODIC_DAMAGE_AURAS) and has no EffectTriggerSpell link to 164815 either. This is structurally IDENTICAL to base Moonfire 8921 (also Effect=3/30 only, no APPLY_AURA row), which tools/gen_target_dots.py's author explicitly hand-curated: CURATED[8921]=164812 (gen_target_dots.py:61-62). No equivalent CURATED[93402]=164815 entry exists. Consequence at runtime: SpellDB.IsTargetDot(93402) -> StaticLookup(targetDots,93402): t[93402] is nil, falls back to C_Spell.GetBaseSpell(93402); since 93402 has no override-chain relationship to 164815 anywhere in TraitDefinition/SpecializationSpells (verified: no row has OverridesSpellID=93402 or SpellID=93402 paired with 164815), GetBaseSpell(93402) almost certainly returns 93402 itself (self-is-own-base), and StaticLookup's own documented behavior for that case is to return nil (SpellDB.lua:190-191, 'self is its own base... return nil'). So IsTargetDot(93402) is false. DotTracker.OnCastSucceeded(93402) (JustAC.lua:1712 passes the raw UNIT_SPELLCAST_SUCCEEDED spellID) then returns immediately at its guard clause (DotTracker.lua:88-90) WITHOUT recording anything - not even the pendingCasts entry needed for the aura-instance confirmation bridge. The generic, mode-independent dot-sink check in SpellQueue.lua (line 539-540: 'DotTracker.IsDotActiveOnCurrentTarget(displayID)') therefore can never return true for Sunfire, so Sunfire is never demoted to the cooldown/sunk bucket regardless of whether its debuff is actually live on the target. This defect is independent of ac/simc context-order mode.

*Evidence:* SpellName.12.1.0.68301.csv:224203 '93402,Sunfire'; SpellName.12.1.0.68301.csv:224209 '164815,Sunfire'; TraitDefinition.12.1.0.68301.csv row ID=121114 SpellID=93402 OverridesSpellID=0; SkillLineAbility.12.1.0.68301.csv row ID=33904 SkillLine=798 Spell=164815; SpellEffect.12.1.0.68301.csv rows ID=97908/324053/324054 (SpellID=93402, Effect=3/3/30, no Effect=6) vs rows ID=232416/232417 (SpellID=164815, EffectIndex1 Effect=6 EffectAura=3 - the periodic-damage row that lets 164815 self-map); gen_target_dots.py:59-71 CURATED dict (8921:164812 present, 93402 absent); Data/TargetDots.lua:25,42 (has [8921]=18 and [164815]=18 but no [93402] key); DotTracker.lua:87-90; SpellQueue.lua:539-540; JustAC.lua:1711-1712; SpellDB.lua:180-192,247-249

*Fix:* Generated table - fix the generator input, not Data/TargetDots.lua by hand. Add `93402: 164815,` to the CURATED dict in tools/gen_target_dots.py (with a matching CURATED_NAMES entry, e.g. 'Sunfire (base; script-applies its DoT, mirrors Moonfire 8921)'), then regenerate with `python tools/gen_target_dots.py` (or the full `python tools/update_data.py` cycle) and verify Data/TargetDots.lua now contains a `[93402]=18` line alongside the existing `[164815]=18`.

### [MAJOR] Flatten dedup takes the FIRST textual occurrence, and call_applies ignores non-target-count branch conditions - so the TWW3-set-bonus branch (kotg_st) dictates the entire DRUID_1 st ranking and conditional eclipse-edge occurrences hoist the bottom fillers wrath/starfire to ranks 1-2 (tools/gen_simc_rotations.py:178)
Two compounding generator behaviors. (1) call_applies (gen_simc_rotations.py:142-152) only evaluates target-count atoms; 'variable.tww3_keeper_4pc' and '!variable.tww3_keeper_4pc' are both ignored, so at k=1 BOTH run_action_list kotg_st (druid_balance.simc:49) and run_action_list st (:50) 'apply', and flatten()'s walk order + first-id-wins dedup (:178-199) means the kotg_st (TWW3 4pc set-bonus) branch, which appears first in the file, supplies the position of every shared spell; the plain st list contributes nothing (verified: regenerated st == committed SimcRotations.lua:151-164 == kotg_st file order exactly). (2) Within that, the APL's rank-1/2 lines are eclipse-TRANSITION casts ('wrath,if=...eclipse_remains<cast_time...' at :88, starfire :89) - rare edge-case conditions the classifier can only mark delegated (compound/OR -> classify_atom:104-105) - while the true unconditional fillers are the BOTTOM lines (kotg_st wrath :124; plain st starfire/wrath :163-164). First-occurrence dedup assigns the filler the conditional occurrence's TOP rank with the condition stripped to delegated=true. Result in simc mode: wrath=rank1, starfire=rank2 permanently outrank DoT maintenance (moonfire 3/sunfire 4 are at least adjacent, but starsurge/starfall/spenders all sink below fillers), and since delegated only triggers the resource-starved sink (SpellQueue.lua:522-525, wrath/starfire are free casts -> never starved), the fillers hold slots 2-3 constantly. This is a BUG relative to the generator's stated contract ('delegated ... falls back to priority order': the priority it falls back to is that of an occurrence whose condition almost never holds, inverting the APL's intent). Systemic: many APLs have the same mutually-exclusive run_action_list ladders on hero_tree/set_bonus variables (mage_frost:20-26, demonhunter_havoc:39-40, shaman_elemental:44-45, priest_shadow:26-27), where the first-listed branch always wins.

*Evidence:* Regenerated with --spec druid_balance: ST = wrath DELEG, starfire DELEG, moonfire[dot:326646], sunfire[-], ... identical to Data/SimcRotations.lua:151-164; order matches kotg_st (druid_balance.simc:86-124) line-for-line: wrath@88, starfire@89, moonfire@90, sunfire@91, fury_of_elune via call kotg_pre_cd@92->84, force_of_nature@93, celestial_alignment@94, starsurge@99, starfall@110, convoke@115, new_moon@118, wild_mushroom@123. Plain st fillers at :163-164, kotg filler wrath at :124. call_applies loop only matches active_enemies|spell_targets|desired_targets atoms (gen_simc_rotations.py:145-146).

*Fix:* Two-part generator fix: (a) in flatten()'s dedup, when a later occurrence of an already-seen id is NON-delegated (after also classifying target_if - see the target_if finding) while the stored one is delegated, let the clean occurrence's rank+gates replace the conditional one (the unconditional fallback line is the APL's true priority for an ungated entry). (b) in call_applies, resolve simple 'variable.X' references against their definitions and treat set_bonus.*/hero_tree-derived variables as false, so mutually-exclusive run_action_list ladders take the no-set-bonus default branch instead of whichever is listed first.

### [MAJOR] target_if conditions other than refreshable/ticking are silently dropped without setting delegated - st sunfire emits gates={} with no delegated flag and looks like an unconditional always-castable pick (tools/gen_simc_rotations.py:163)
make_entry classifies mods['if'] via classify_if (line 163) but for target_if (:165-166) only checks two patterns: a bare refreshable/ticking token at a separator, and the literal substring 'dot.<token>.'. Everything else in target_if - the entire condition - is discarded WITHOUT setting delegated. DRUID_1 st sunfire comes from kotg_st (druid_balance.simc:91) whose condition lives entirely in target_if ('remains<(3>?fight_remains)|variable.kotg_single_ca_condition&...'): no refreshable/ticking, no 'dot.sunfire.' substring -> gates=[], delegated=False -> emitted '{id=93402,gates={}}' (SimcRotations.lua:155). st moonfire (:90) only got its dot gate via the incidental '!dot.moonfire.ticking' substring. Contrast aoe sunfire (druid_balance.simc:58, 'target_if=refreshable&...') which correctly emits {t='dot',id=93402}. Consequence: sunfire is a rank-4 'clean' entry - never delegated-starved, never gated - which combined with the TargetDots miss (finding 1) pins it at the top of the queue. The kotg-branch-first walk (finding 3) additionally cost sunfire the dot gate the plain st list (:138 'target_if=remains<3|refreshable&...', :150 'target_if=refreshable') would have produced.

*Evidence:* gen_simc_rotations.py:165-166 is the ONLY target_if handling (regex "(?:^|[:&|(])\\s*!?(refreshable|ticking)\\b" plus 'dot.%s.' substring); no delegated assignment on the miss path. Generated st sunfire: '{id=93402,gates={}}' with no delegated (SimcRotations.lua:155, reproduced by regeneration). kotg_st sunfire target_if at druid_balance.simc:91 contains neither pattern.

*Fix:* In make_entry: run the target_if expression (minus the 'min:'/'max:' prefix) through classify_if like if=, or minimally set delegated=True whenever target_if contains anything beyond the recognized refreshable/ticking patterns; additionally recognize own-dot 'remains<N' in target_if as {'t':'dot','own':True} (it is the standard SimC maintenance idiom, druid_balance.simc:91,138-139).

### [MAJOR] Generator flattens DRUID_1 'st' from the kotg_st (TWW3 set-bonus) branch - call_applies ignores every non-target-count condition and first-reach dedup locks in the wrong branch's ranks/gates (tools/gen_simc_rotations.py:142)
call_applies() (gen_simc_rotations.py:142-152) checks only spell_targets/active_enemies clauses; 'variable.tww3_keeper_4pc' is ignored, so at k=1 BOTH 'run_action_list,name=kotg_st,if=variable.tww3_keeper_4pc&spell_targets=1' (druid_balance.simc:49) and the generic st (line 50) apply - and flatten() walks kotg_st FIRST with dedup-by-id 'first reach wins' (gen_simc_rotations.py:178-199). The emitted DRUID_1.st is exactly kotg_st's first-occurrence order: wrath(APL 88)=1, starfire(89)=2, moonfire(90)=3, sunfire(91)=4, fury_of_elune(via kotg_pre_cd 92->84)=5, force_of_nature(93)=6, celestial_alignment(94)=7, starsurge(99)=8, starfall(110)=9, convoke(115)=10, new_moon(118)=11, wild_mushroom(123)=12. Two user-visible consequences: (a) ranks come from a branch gated on an old set bonus most players don't have; (b) st Sunfire's entry derives from kotg_st line 91 (target_if=remains<...) instead of actions.st line 150 (target_if=refreshable), which is why st sunfire lost its dot gate (see next finding). Note the deeper systemic issue either way: first-occurrence flattening assigns heavily-conditioned duplicate lines (wrath/starfire eclipse-transition casts at APL 136-137/144-145) their most optimistic rank while their unconditional filler occurrences (163-164, the true 'bottom of the list' role) are dropped by dedup - so wrath=1/starfire=2 would emerge from the plain st walk too; 'delegated' carries no runtime demotion (only the starve check, SpellQueue.lua:521-525, moot for mana casters).

*Evidence:* tools/simc-apl/druid_balance.simc:49-51 (branch order), :86-124 (kotg_st) vs :134-164 (st). Data/SimcRotations.lua:151-163 matches the kotg_st walk 1:1 (fury_of_elune at rank 5 is the fingerprint - in a pure st walk it would be rank 1-2, APL line 135).

*Fix:* In call_applies, additionally resolve 'variable.<name>' references whose definition (actions=variable,name=...) contains set_bonus.* to false (don't assume tier-set branches), so kotg_st is skipped and st flattens from actions.st. Longer term, rank a duplicate token by its LAST (unconditional filler) occurrence when its earlier occurrences are delegated.

### [MAJOR] Generator never classifies target_if= conditions - st Sunfire's 'remains<3' refresh condition became gates={} and delegated=false (unconditional rank 4) (tools/gen_simc_rotations.py:163)
make_entry (gen_simc_rotations.py:156-175) runs classify_if only on mods['if']; target_if is merely regex-scanned for 'refreshable|ticking' or 'dot.<token>.' (line 165). kotg_st sunfire (druid_balance.simc:91) is 'sunfire,target_if=remains<(3>?fight_remains)|...' - a pure dot-refresh condition expressed as bare 'remains<', which matches none of the patterns -> emitted as gates={} with delegated=false (Data/SimcRotations.lua:155). Runtime then treats Sunfire as an unconditionally-castable rank-4 ability: never promoted, never sunk, never starve-checked. (Moonfire on the adjacent APL line 90 only got its dot gate because its target_if happens to contain '|!dot.moonfire.ticking'.) Combined with findings 1 and 3 this is why simc mode shows Sunfire permanently at the front even with the DoT running.

*Evidence:* gen_simc_rotations.py:163-167: gates from classify_if(mods.get('if','')); tif scan only r'(refreshable|ticking)' / 'dot.%s.'. druid_balance.simc:91 contains neither token. Data/SimcRotations.lua:155 '{id=93402,gates={}}, -- sunfire'.

*Fix:* In make_entry, treat a target_if containing bare 'remains<' (or any dot.* / refreshable / ticking reference) as an own-dot gate, and otherwise mark the entry delegated when target_if is non-empty - a target-conditioned action is never unconditional.

### [MAJOR] Balance bridge universe is missing whole talent records: warrior_of_elune (202425) and stellar_flare (202347) are not reachable via the spec-tree chain, so both are absent from DRUID_1 despite being top/mid-priority APL actions (tools/simc_bridge.py:124)
Offline probe: 202425 and 202347 are present in TraitDefinition but NOT in bridge.universe(Balance) - the TraitTreeLoadout->TraitNode->TraitNodeEntry->TraitDefinition walk misses them in the pinned CSVs. warrior_of_elune opens both st lists (druid_balance.simc:86, 134) and stellar_flare is a maintenance DoT (lines 102, 116, 154, 62); both are unranked (fail-safe: keep AC order) so a Balance simc-mode user with Stellar Flare talented never sees it ranked. incarnation additionally fails via the short-alias path (multiple 'incarnation_*' hits) and needs curation like Feral's. half_moon/full_moon are absent too, but New Moon's rank partially covers them via the override keying in BuildLookup (though the override baked at lookup-build time can go stale as the moon phase cycles mid-combat - edge case).

*Evidence:* Probe output: warrior_of_elune -> None, stellar_flare -> None, incarnation -> None, half_mooon/full_moon -> None; '202425 in universe: False, 202347 in universe: False' while TraitDefinition rows ',,,108238,202425,0,0,0' and ',,,108277,202347,0,0,0' exist; generator report residue for druid_balance.

*Fix:* Curate DRUID_1 tokens (warrior_of_elune=202425, stellar_flare=202347, incarnation=102560/incarnation_chosen_of_elune) and investigate why the spec-102 trait-tree chain misses these nodes in the 12.1 CSVs.

### [MAJOR] simc_bridge.py resolver('moonfire') for Balance Druid resolves to non-castable passive spell 326646 instead of the real Moonfire cast id (tools/simc_bridge.py:180)
326646 is named 'Moonfire' in SpellName.12.1.0.68301.csv but is NOT the player-cast ability. SpecializationSpells.12.1.0.68301.csv row ID=6827 grants it to SpecID=102 (confirmed Balance via ChrSpecialization.12.1.0.68301.csv row ID=102, Name_lang='Balance', ClassID=11/Druid), OverridesSpellID=0, DisplayOrder=9. Its SpellEffect row (ID=817765, EffectIndex=0, Effect=6/APPLY_AURA, EffectAura=107=AddFlatModifier per WowPacketParser AuraType.cs:112, ImplicitTarget_0=1=TARGET_UNIT_CASTER) shows it is a self-targeted passive stat modifier (likely a scaling/tuning driver tagged to Moonfire's spell-class-mask, EffectSpellClassMask_2=268435456), not a debuff applicator - it is absent from SkillLineAbility entirely (not on the action bar/spellbook). The real castable Moonfire (8921) is only reachable via SkillLineAbility (SkillLine=798, row ID=33228) and via an override-chain entry in TraitDefinition (row ID=140103: SpellID=1252871 'Red Moon', OverridesSpellID=8921). tools/simc_bridge.py's SimcBridge.resolver() builds tier-1 preference from self._base_primary (SpecializationSpells SpellID column only) BEFORE checking tier-2 (talent SpellID column) or tier-3 (skill-line spells); since 326646 uniquely occupies tier-1 for the 'moonfire' name slug on spec 102 (8921/164812 only reach the universe via tier-3/SkillLineAbility), resolve() returns 326646 without ever considering the lower tiers. Verified live: running SimcBridge('Documentation/wow_spell_csv').resolver('DRUID','Balance',{})('moonfine') -> wait, verified resolver(...)('moonfire') returns 326646 directly (confirmed by executing tools/simc_bridge.py's resolver function against the current CSV set). This propagates into Data/SimcRotations.lua DRUID_1.st line154 and DRUID_1.aoe line170 as {id=326646,...}. Because AC's actual rotation-list Moonfire id (8921 or an override variant, never 326646) is what SpellQueue.lua passes to RotationImport.GetEntry(spellID,...), and RotationImport.BuildLookup only registers m[326646] (plus baseID(326646), which almost certainly resolves to itself since nothing overrides it) - NOT m[8921] - GetEntry(8921,'st') misses entirely. Net runtime effect in 'simc' context-order mode: Moonfire's simcRec is nil, so rankOf() falls back to the miss value 900 (RotationImport.lua consumed via SpellQueue.lua:470 'rankOf' -> '(simcRec and simcRec.rank) or 900'), i.e. Moonfire's SimC-derived rank silently degrades to near-bottom-of-bucket instead of the intended position-3 priority - not an over-promotion. (Moonfire's separate DotTracker-based dot-sink is unaffected by this bug since [8921] and [164812] are both correctly keyed in Data/TargetDots.lua.)

*Evidence:* SpecializationSpells.12.1.0.68301.csv row ID=6827 SpecID=102 SpellID=326646 OverridesSpellID=0 DisplayOrder=9; ChrSpecialization.12.1.0.68301.csv ID=102 Name_lang=Balance ClassID=11; SpellEffect.12.1.0.68301.csv ID=817765 SpellID=326646 EffectAura=107 Effect=6 ImplicitTarget_0=1; SkillLineAbility.12.1.0.68301.csv row ID=33228 SkillLine=798 Spell=8921; TraitDefinition.12.1.0.68301.csv row ID=140103 SpellID=1252871 OverridesSpellID=8921; tools/simc_bridge.py:162-212 (resolver tiers, lines 180-201 in particular); Data/SimcRotations.lua:154 '{id=326646,gates={{t="dot",id=326646}}},  -- moonfire' and :170; RotationImport.lua:95-116,130-147 (BuildLookup/GetEntry); SpellQueue.lua:468-475 (rankOf fallback 900); live check via `py -c` invoking SimcBridge(...).resolver('DRUID','Balance',{})('moonfire') -> 326646, ('sunfire') -> 93402, ('starfire') -> 194153, ('wrath') -> 190984

*Fix:* Generated table - fix the generator/bridge, not Data/SimcRotations.lua by hand. In tools/gen_simc_rotations.py's per-spec CURATED dict, add a DRUID_1 entry `{'moonfire': 8921}` (mirroring the existing DRUID_2 curation pattern at gen_simc_rotations.py:54-59) to force the correct base id, then regenerate with `python tools/gen_simc_rotations.py` and confirm Data/SimcRotations.lua DRUID_1 now carries {id=8921,...} for moonfire. Longer-term the same tier1-passive-collision risk exists for any other spec where a SpecializationSpells-granted id shares a name with a non-castable passive; consider having simc_bridge.py's tier-1 preference filter out ids whose only SpellEffect row targets the caster with a non-periodic-damage aura, or cross-check against SkillLineAbility membership before trusting a unique tier-1 hit.

### [MINOR] Balance residue: warrior_of_elune, incarnation, stellar_flare, half_moon, full_moon unresolved - the maintenance DoT Stellar Flare and both moon upgrades are silently unranked (tools/gen_simc_rotations.py:53)
Confirmed by running the generator: DRUID_1 residue = full_moon half_moon incarnation stellar_flare warrior_of_elune. Fail-safe by design (unresolved -> keeps AC order, header lines 22-23), but for Balance this drops a maintenance DoT (Stellar Flare 202347, which IS in TargetDots.lua:45 so at least the sink works) and the Half/Full Moon recharge stages from the simc ranking entirely - the ranked new_moon 274281 will not match when the button has cycled to 274282/274283, so the moons intermittently rank 900. CURATED (:53-59) has a DRUID_2 block only.

*Evidence:* Generator report line: 'druid_balance  DRUID_1  12/-/12  full_moon half_moon incarnation stellar_flare warrior_of_elune'. CURATED in gen_simc_rotations.py:53-59 contains only DRUID_2.

*Fix:* Add CURATED['DRUID_1'] = {moonfire: 8921 (finding 2), stellar_flare: 202347, warrior_of_elune: 202425, incarnation: 102560, half_moon: 274282, full_moon: 274283} - the same pattern the file already prescribes ('Grow this from the coverage report's residue').

### [MINOR] Unresolved DRUID_1 tokens (warrior_of_elune, stellar_flare, incarnation, half/full_moon) silently absent from SimC data - those spells fall to the 900 sentinel in simc mode (Data/SimcRotations.lua:151)
The generator's fail-safe drops unresolved tokens (gen_simc_rotations.py:159-162, reported as residue only at generation time). DRUID_1 has no entries for warrior_of_elune (202425, APL st line 134 = top priority), stellar_flare (202347 - itself a maintained DoT), incarnation (102560), half_moon/full_moon. In 'simc' mode every AC-rotation spell missing from the data gets rank 900 (SpellQueue.lua:470) and is buried below all 12 ranked entries - e.g. Stellar Flare, a talent maintenance DoT, can never surface above Sunfire/Starfire. Fail-safe by design, but for a shipped spec the residue amounts to wrong ordering, not neutral ordering.

*Evidence:* No 202425/202347/102560 ids anywhere in Data/SimcRotations.lua DRUID_1 block (lines 150-179) despite being prominent actions in tools/simc-apl/druid_balance.simc:134,154,143.

*Fix:* Add the missing tokens to CURATED['DRUID_1'] in tools/gen_simc_rotations.py (warrior_of_elune=202425, stellar_flare=202347, incarnation=102560, half_moon/full_moon new-moon chain ids) and regenerate; optionally fail CI when residue touches a token that appears in the top N APL lines.

### [MINOR] Malformed dot gate {t='dot'} with no id on wild_mushroom (st and aoe) - unresolvable dot-name token silently dropped from the gate (Data/SimcRotations.lua:163)
dot.fungal_growth.ticking / dot.fungal_growth.remains<2 classify as {'t':'dot','id':resolve('fungal_growth')} where resolve returns None (fungal_growth is a dot name, not a castable), and gate_lua just omits the id, emitting the schema-violating {t="dot"}. Currently harmless because dot/cd/execute gates in SimcRotations are dead data at runtime (the only gate consumer is SimcBuffWindowActive for positive buff gates; the dot sink rides DotTracker keyed by the queue spell id) - but it will misbehave the day dot gates are evaluated, and DebugCommands' gate renderer (DebugCommands.lua:1575) shows it id-less.

*Evidence:* Data/SimcRotations.lua:163 '{id=88747,gates={{t="dot"}},delegated=true}' and :177; druid_balance.simc:77,123,162; gen_simc_rotations.py:108-110 (resolve may return None), 203-209 (gate_lua drops falsy id).

*Fix:* In classify_atom, return (None, True) when the dot-name token fails to resolve, instead of emitting an id-less gate.

### [MINOR] gen_simc_rotations.py's call_applies() ignores the tww3_keeper_4pc set-bonus condition, so the TWW3 kotg_st branch is walked (and wins id-dedup) ahead of the real 'st' branch for every Balance Druid, corrupting Sunfire's and Moonfire's emitted gates (tools/gen_simc_rotations.py:142)
tools/simc-apl/druid_balance.simc:49-50: 'run_action_list,name=kotg_st,if=variable.tww3_keeper_4pc&spell_targets=1' is listed before 'run_action_list,name=st,if=!variable.tww3_keeper_4pc&spell_targets=1'. gen_simc_rotations.py's call_applies() (lines 142-152) only evaluates target-count clauses (spell_targets/active_enemies/desired_targets) and explicitly ignores everything else (including the tww3_keeper_4pc variable), by design, so both calls 'apply' at k=1 and kotg_st is walked first regardless of whether the player actually has that set bonus. Inside kotg_st, line 91's sunfire uses 'target_if=remains<(3>?fight_remains)|...' with NO top-level if= clause and no 'refreshable'/'ticking'/'dot.sunfire.' keyword in the target_if text, so make_entry()'s dot-gate detection regex (gen_simc_rotations.py:165-166, checking for those literal keywords) misses it entirely, producing gates=[] and delegated=False. Line 90's moonfire target_if DOES contain the literal substring 'dot.moonfire.' (via '!dot.moonfire.ticking'), so it IS classified as a dot gate, but its id is resolve('moonfire')=326646 (see prior finding) - a self-referential, always-inactive gate. flatten()'s per-id dedup (line 194-196: 'first/highest-priority reach wins') then locks these in: the properly-gated sunfire/moonfire occurrences later in the real 'st' list (druid_balance.simc:138,150 sunfire; :139,151 moonfire, both with correct 'refreshable'/'remains<3' target_if text) are skipped because their resolved ids are already in `seen`. Practical impact today is limited: grepping every consumer of SimcRotations.lua entry.gates in SpellQueue.lua shows only t=="buff" gates are evaluated live (SimcBuffWindowActive, SpellQueue.lua:445-449, used only for proc-bucket promotion during a buff window); t="dot"/t="cd"/t="targets"/t="execute" gates are consumed only by DebugCommands.lua (diagnostic display, e.g. /jac inspect rank or /jac why) - they do not currently affect bucket placement. So this bug's live effect today is (a) misleading /jac diagnostics for Balance Druid Sunfire/Moonfire, and (b) it is latent - it would matter if/when dot gates are ever wired into bucket-placement logic, which their SimC-derived semantics clearly intend.

*Evidence:* tools/simc-apl/druid_balance.simc:49-50 (kotg_st before st), :90-91 (kotg_st sunfire/moonfire target_if text), :138-139,150-151 (the real st sunfire/moonfire, correctly phrased with 'refreshable'/'remains<3'); tools/gen_simc_rotations.py:142-152 (call_applies ignores non-target-count clauses), :156-176 (make_entry, dot-gate regex at 165-166), :178-199 (flatten, id-dedup at 194-196); Data/SimcRotations.lua:154-155 (moonfire gates={{t="dot",id=326646}}, sunfire gates={}); SpellQueue.lua:445-449,531 (only t=="buff" gates consumed live); DebugCommands.lua:1572-1588 (t=="cd"/"dot"/"proc"/"buff"/"targets"/"execute" all read only here)

*Fix:* Report-only per this task; if pursued, either (a) stop collapsing hero-tree/set-bonus 'variable.*' branch conditions in call_applies() so kotg_st is only walked when meaningfully distinguishable (tradeoff: loses the 'all builds visible' simplification the current comment explains), or (b) broaden make_entry()'s dot-gate detection to catch bare target_if='remains<N' / 'remains<N|refreshable' phrasing (a SimC idiom meaning 'this ability's own dot', same as the already-handled 'refreshable'/'ticking' bare cases at line 126-127 for non-target_if atoms) so kotg_st's sunfire also gets a correct (if still id-326646-poisoned pending the prior fix) dot gate instead of none. Regenerate via `python tools/gen_simc_rotations.py` after either change and diff Data/SimcRotations.lua's DRUID_1 block.

### [MINOR] GetBaseSpell(93402) self-heal cannot be confirmed to resolve to anything present in Data/TargetDots.lua; code-path analysis says it does not (SpellDB.lua:190)
Direct answer to audit item 3. C_Spell.GetBaseSpell is a live client API not fully reconstructable from the static CSV export set in Documentation/wow_spell_csv (no SpellXSpellPair-equivalent override-chain table is present among the tracked tables), so a 100%-certain answer isn't obtainable from CSVs alone. However, all available override-chain evidence (TraitDefinition.OverridesSpellID column, the only such linkage source in this CSV set) shows NO row anywhere with OverridesSpellID=93402 or SpellID=93402 paired against 164815 in either direction - the row that DOES exist for 93402 (TraitDefinition ID=121114) has OverridesSpellID=0, meaning nothing overrides it and it overrides nothing. GetBaseSpell's documented/observed behavior elsewhere in this codebase (SpellDB.lua:194-208, 'self is its own base, or C_Spell.GetBaseSpell is unavailable' -> returns nil) plus StaticLookup's explicit self-is-own-base early-return-nil (SpellDB.lua:190-191) means that even if GetBaseSpell(93402) returns 93402 (the most likely outcome given no override-chain evidence), SpellDB.IsTargetDot(93402) still resolves to nil/false - it does not silently self-heal onto 164815. The miss is real, not masked by the runtime fallback.

*Evidence:* Documentation/wow_spell_csv/TraitDefinition.12.1.0.68301.csv (grep for OverridesSpellID=93402: no matches; row ID=121114 SpellID=93402 OverridesSpellID=0); SpellDB.lua:178-208 (StaticLookup, GetBaseSpell); Documentation/DEV_TOOLING.md and AGENTS.md list the tracked CSV tables - no override/spell-pair table beyond TraitDefinition is present

*Fix:* No fix needed here directly - this confirms the first finding's severity (the Sunfire sink is definitively broken, not merely unconfirmed-but-maybe-working). If certainty is wanted beyond static-data inference, verify live with `/jac inspect dots` or a scratch print of C_Spell.GetBaseSpell(93402) while playing Balance.


## DRUID_2

### [MAJOR] Feral st: ferocious_bite rank 4 above rip rank 9 inverts the finisher priority (rip before FB), and the apex-proc buff gate that justified FB's high slot is dead (talent id 391881, live aura is 391882) (Data/SimcRotations.lua:185)
FB's rank-4 slot comes from druid_feral.simc:42 (apex_predators_craving proc special case); rip's first reach is line 47. In the actual finisher list rip (line 177) outranks FB (lines 183/185). The gate {t='buff',id=391881} was meant to promote FB only during the Apex proc, but 391881 is the TALENT record - the live proc aura is 391882 (both named 'Apex Predator's Craving' in SpellName; the resolver's talent tier picks 391881). BlizzardAPI.IsBuffWindowActive (CooldownTracking.lua:523-531) probes GetPlayerAuraBySpellID(gateID), which returns nil for 391881, so the promotion never fires - yet the rank persists, so in simc mode at 5cp with rip refreshable the queue shows FB above Rip. Buff gates are promotion-only (SimcBuffWindowActive, SpellQueue.lua:445-455), so the failure is a permanent mis-rank plus a dead feature, not a crash.

*Evidence:* Data/SimcRotations.lua:185 '{id=22568,gates={{t="buff",id=391881}},delegated=true}' at index 4 vs :190 rip at index 9; druid_feral.simc:42,47,175-187; SpellName csv: 391881 and 391882 both 'Apex Predator's Craving'; CooldownTracking.lua:528 GetPlayerAuraBySpellID(spellID).

*Fix:* Curate buff-gate aura ids (391881->391882) or teach the bridge to prefer the record that is an applicable aura for buff.\* atoms; separately consider ranking finisher-list first-reach ahead of proc special cases.

### [MINOR] call_applies AND-collapses target-count atoms across OR branches - cleave-tier flatten can wrongly skip a list call (feral main line 49 at k=2) (tools/gen_simc_rotations.py:144)
call_applies iterates every target-count comparison anywhere in the condition and requires ALL to hold, ignoring OR structure. druid_feral.simc:49 '(...&spell_targets<=2)|spell_targets=1&...' contains both 'spell_targets<=2' (true at k=2) and 'spell_targets=1' (false at k=2) -> returns False at k=2 although the first OR branch applies. For druid the damage is nil today (all druid cleave tiers dedup away; DRUID_2 cleave==aoe), so cosmetic - but it silently skews cleave tiers for any APL with mixed target-count OR branches.

*Evidence:* gen_simc_rotations.py:144-152; druid_feral.simc:49; generator report shows DRUID_2 '16/-/16' (no distinct cleave).

*Fix:* Evaluate call_applies per top-level OR branch (split on depth-0 '|') and apply the call if any branch's target-count atoms hold.


## DRUID_3

### [MAJOR] Guardian/Feral buff-window gate ids are talent-definition ids, not the player-aura ids the runtime probes - all these proc promotions are silently dead (Data/SimcRotations.lua:221)
IsBuffWindowActive requires the id GetPlayerAuraBySpellID sees. Dead gates emitted: DRUID_3 maul {t='buff',id=441583} (Ravage talent; proc aura 441585), DRUID_3 mangle {t='buff',id=210706} (Gore talent; proc aura 93622), DRUID_3 moonfire {t='buff',id=203964} (Galactic Guardian talent; proc aura 213708), DRUID_3 barkskin and moonfire {t='buff',id=270100} ('Bear Form' spec record; the actual form aura is 5487), DRUID_2 regrowth {t='buff',id=16974} (Predatory Swiftness passive; proc aura 69369). Fail-safe (no wrong promotion, just none), but it kills the SimC gate layer's headline feature for these entries. Correct counter-examples exist (5217 Tiger's Fury, 106951 Berserk, 5215 Prowl - cast==aura), so this is specifically the shared-name talent-vs-aura record ambiguity in simc_bridge name resolution.

*Evidence:* Data/SimcRotations.lua:221,230,232,223,197; SpellName csv: 441583/441585 both 'Ravage', 210706/93622 both 'Gore', 203964/213708 'Galactic Guardian', 270100 and 5487 both 'Bear Form', 16974/69369 both 'Predatory Swiftness'; CooldownTracking.lua:523-532.

*Fix:* Validate every emitted buff-gate id against an 'is an aura with duration' predicate from the CSVs (SpellAuraOptions/SpellEffect APPLY_AURA) and prefer the aura record; fall back to delegate when ambiguous.

### [MAJOR] Guardian: thrash_bear (priority ~3 maintenance) unresolved and absent from DRUID_3 - unranked in simc mode; heart_of_the_Wild lost purely to token case-sensitivity (Data/SimcRotations.lua:218)
Generator residue for druid_guardian: berserk_bear heart_of_the_Wild incarnation pulverize rage_of_the_sleeper swipe_bear thrash_bear (reproduced by running gen_simc_rotations.py). Form-suffix tokens (_bear) require curation by design (simc_bridge FORMS check) but only Feral got a CURATED block - Guardian got none, so thrash_bear (druid_guardian.simc:32, the top maintenance action with refreshable/stack conditions) is missing from the generated list entirely and takes the unranked-900 sentinel in simc mode, sinking below every ranked entry. swipe_bear (filler) likewise. heart_of_the_Wild fails only because the APL spells it with a capital W (lines 15, 31) and resolve() never lowercases the token while the index keys are lowercase slugs. berserk_bear/incarnation/rage_of_the_sleeper/pulverize absences are fail-safe (CD spells, AC order kept) - minor by themselves.

*Evidence:* Generator report line 'druid_guardian DRUID_3 14/-/- berserk_bear heart_of_the_Wild incarnation pulverize rage_of_the_sleeper swipe_bear thrash_bear'; gen_simc_rotations.py:53-59 CURATED has only DRUID_2; simc_bridge.py:189-190 form-variant tokens return None without curation; druid_guardian.simc:31-32.

*Fix:* Add a DRUID_3 CURATED block (thrash_bear=77758, swipe_bear=213771, berserk_bear=50334, incarnation=102558, pulverize=80313, rage_of_the_sleeper=200851 - verify against current CSVs) and lowercase tokens in resolve().


## DRUID_4

### [MINOR] TargetDots rows keyed by debuff-aura ids that never occur as cast ids: 164812 (Moonfire aura, redundant) and 164815 (Sunfire aura, non-functional stand-in for the missing 93402) (Data/TargetDots.lua:41)
gen_target_dots.py's 'aura in universe -> cast_aura[aura]=aura' path (lines 170-172) admits pure aura records when they leak into the learnable universe. 8921 already covers Moonfire (so 164812 is dead weight); 164815 is the only Sunfire row and can never match a cast (see the critical Sunfire finding). Cosmetic beyond the Sunfire case, but the pattern suggests auditing other classes' rows for the same cast-vs-aura keying (out of this sweep's scope).

*Evidence:* Data/TargetDots.lua:41-42; gen_target_dots.py:170-172.

*Fix:* Filter the direct 'aura is its own cast' path to spells that are actually castable (has SpellMisc cast data / not passive), or cross-check against SkillLineAbility cast records.


## EVOKER_1

### [CRITICAL] EVOKER_1 st: fillers Living Flame (rank 5) and Azure Strike (rank 9) permanently outrank Fire Breath (8) and Disintegrate (11) because first-reach dedup binds them to niche top-of-APL lines (Data/SimcRotations.lua:257)
flatten() dedups by spell id, first reach wins (gen_simc_rotations.py:184-199). In the Devastation st APL, living_flame first appears at line 114 (a set_bonus.tww3_4pc special case) and azure_strike at line 131 (a 'Dragonrage about to expire' snapshot case); their real roles are the unconditional bottom fillers (APL lines 151/155/157). set_bonus atoms are classified as build gates and dropped (classify_atom, gen_simc_rotations.py:124-125) even though IsPlayerSpell cannot check set bonuses, so nothing marks these entries conditional. Result: st ranks are living_flame=5, fire_breath=8, azure_strike=9, firestorm=10, disintegrate=11. In simc mode SpellQueue rankOf uses that index directly (SpellQueue.lua:468-470); the delegated flag only sinks on insufficient power (SpellQueue.lua:522-525) and LF/AS are free, so at all times in single-target the queue orders Living Flame above Fire Breath and Disintegrate - the exact 'filler in the top slots' symptom the user reported for Balance Druid.

*Evidence:* Data/SimcRotations.lua:252-266 (st order quell,deep_breath,dragonrage,eternity_surge,living_flame,hover,tip_the_scales,fire_breath,azure_strike,firestorm,disintegrate,pyre,...); tools/simc-apl/evoker_devastation.simc:114 (living_flame,if=set_bonus.tww3_4pc&...), :131 (azure_strike,if=buff.dragonrage.up&buff.dragonrage.remains<...), :147 (real disintegrate), :155-157 (real LF/AS fillers); gen_simc_rotations.py:124-125,193-196; SpellQueue.lua:470

*Fix:* In the flattener, treat set_bonus.* atoms as delegated (unreadable) rather than build gates, and/or rank a deduped spell at its LAST (or least-conditional) occurrence instead of first reach; alternatively skip entries whose only distinguishing condition is a set bonus.

### [CRITICAL] EVOKER_1 st: positive buff.dragonrage gates on Living Flame/Azure Strike/Tip/Eternity Surge promote them into the PROC bucket for the entire Dragonrage window, pinning fillers ahead of Disintegrate during every burst (Data/SimcRotations.lua:261)
SimcBuffWindowActive treats ANY positive buff gate as a proc-window promotion (SpellQueue.lua:445-455, 529-535). The generated st entries eternity_surge(4), living_flame(5), tip_the_scales(7), azure_strike(9) all carry {t="buff",id=375087} (Dragonrage aura id == 375087, so IsBuffWindowActive really fires). Those gates came from lines where buff.dragonrage.up was only one AND-term of a narrow condition (tww3 set line 114; expiry-fishing line 131). During every Dragonrage (2min CD, ~18s+ window) Living Flame and Azure Strike are promoted into the proc bucket above ALL normal-bucket spells, while Disintegrate (rank 11, no buff gate) - the APL's actual Dragonrage spender - stays below them. Visible wrong order in the most important common situation for the spec.

*Evidence:* Data/SimcRotations.lua:256-261 ({t="buff",id=375087} on 359073/361469/370553/362969); tools/simc-apl/evoker_devastation.simc:129-131 (LF/AS are only correct when dragonrage.remains < EB-stack refill time); SpellQueue.lua:449-451,529-535; BlizzardAPI/CooldownTracking.lua:523-532

*Fix:* Only emit a promotion-capable buff gate when the buff condition is the entry's PRIMARY condition (no other unreadable AND-terms), or mark such entries so SimcBuffWindowActive skips delegated entries.

### [CRITICAL] EVOKER_1: Shattering Star and Engulf are absent from both generated lists (unresolved tokens, no CURATED entries) and therefore sink to rank 900 below all ranked fillers (Data/SimcRotations.lua:252)
The st APL ranks shattering_star 4th (line 120) and engulf 6th (line 127); aoe uses both too (lines 66, 80). Neither appears anywhere in the generated EVOKER_1 block - the bridge failed to resolve both tokens and CURATED (gen_simc_rotations.py:53-59) has no EVOKER entries. The generator's fail-safe claim ('keeps AC's order', gen_simc_rotations.py:22-23) is false in simc mode: RotationImport.GetEntry returns nil and SpellQueue.rankOf assigns 900 (SpellQueue.lua:470), sorting them BELOW every ranked entry in the normal bucket - i.e. below the mis-ranked Living Flame(5)/Azure Strike(9) fillers. Devastation's two highest-value talent buttons are pushed to the queue tail whenever ready.

*Evidence:* Data/SimcRotations.lua:252-283 contains no id 370452 (Shattering Star) or 443328 (Engulf); tools/simc-apl/evoker_devastation.simc:66,80,120,127; gen_simc_rotations.py:53-59 (CURATED lacks EVOKER_*); SpellQueue.lua:470 ('or 900')

*Fix:* Add CURATED["EVOKER_1"] = { shattering_star = 370452, engulf = 443328 } (verify ids against the client-data CSVs) and regenerate; longer term make unranked spells inherit a neutral rank instead of a below-everything sentinel.

### [MAJOR] EVOKER_1 st: Deep Breath ranked 2 with gates={} and no delegated flag - a TWW3-4pc-only APL line hoisted to the top for all players (Data/SimcRotations.lua:254)
APL st line 110 (deep_breath,if=talent.maneuverability&set_bonus.tww3_4pc) is the first st entry; both atoms classify as build gates and are dropped without setting delegated (gen_simc_rotations.py:124-125), so the emitted entry is unconditional and firmly ranked. The runtime cannot evaluate set_bonus via IsPlayerSpell. For players without the (now outdated) TWW3 set - i.e. everyone at current content - the APL's deep_breath belongs at line 139 (below fire_breath/eternity_surge, just above disintegrate). Effect: whenever Deep Breath is off cooldown, it is the top-ranked normal suggestion, above Dragonrage(3) and every empower.

*Evidence:* Data/SimcRotations.lua:254 ({id=357210,gates={}}); tools/simc-apl/evoker_devastation.simc:110 vs :139 (!set_bonus.tww3_4pc variant); gen_simc_rotations.py:124-125

*Fix:* Classify set_bonus.* (and equipped.*) atoms as delegated, not build gates.

### [MAJOR] EVOKER_1 st: Eternity Surge (rank 4) ordered above Fire Breath (rank 8), inverting the APL's empower priority, via the same TWW3 set-bonus line hoist (Data/SimcRotations.lua:256)
eternity_surge's first reach is APL st line 113 (set_bonus.tww3_4pc branch), so it is ranked 4 with that line's gates ({t="buff",id=375087},{t="cd"}). The generic APL order for non-set players is fire_breath (lines 122-125) BEFORE eternity_surge (lines 135-137). Generated order inverts them (ES=4, FB=8). Additionally, outside Dragonrage the buff gate simply fails to promote (no runtime demotion), so the wrong rank 4 applies unconditionally.

*Evidence:* Data/SimcRotations.lua:256 vs :260; tools/simc-apl/evoker_devastation.simc:113,122-125,135-137

*Fix:* Same as the set-bonus classification fix; or dedup to the least-conditional occurrence.

### [MAJOR] EVOKER_1 aoe: Firestorm ranked 3 with its Snapfire proc gate silently lost (gates={}, delegated only) (Data/SimcRotations.lua:271)
APL aoe line 65 is firestorm,if=buff.snapfire.up ('spend procs ASAP'); the unconditional firestorm is far lower (line 94). resolve('snapfire') fails (Snapfire buff 370818 not in the castable universe), and classify_atom's unknown-buff branch returns delegate-with-no-gate (gen_simc_rotations.py:117). First-reach dedup then ranks firestorm 3rd unconditionally: whenever its 20s cooldown is up in AoE it outranks fire_breath(6), dragonrage(7), disintegrate(10) with no proc condition - a gate loss directly analogous to DRUID_1 st sunfire gates={}.

*Evidence:* Data/SimcRotations.lua:271 ({id=368847,gates={},delegated=true}); tools/simc-apl/evoker_devastation.simc:65,94; gen_simc_rotations.py:112-117

*Fix:* When a proc-buff token fails to resolve on a top-ranked entry, either curate the aura id (snapfire buff 370818) or let the entry fall through to its later unconditional occurrence for ranking.

### [MINOR] Systemic: any target.time_to_die comparison becomes {t="execute"} regardless of operator - Dragonrage (st), Fire Breath (aoe) and Breath of Eons carry inverted execute gates (tools/gen_simc_rotations.py:120)
classify_atom matches r'(target.health.pct|target.time_to_die)' and emits {t="execute"} with neg only from a leading '!'. 'target.time_to_die>=30' (Dragonrage, st line 112), 'target.time_to_die>=duration' (aoe fire_breath lines 72/74) and 'target.time_to_die>=13' (Aug breath_of_eons line 56) mean 'target lives long ENOUGH' - the opposite of an execute window. Currently harmless only because SpellQueue never evaluates execute gates from SimC entries (only positive buff gates and delegated are consumed, SpellQueue.lua:445-455,522-535), but /jac inspect displays them (DebugCommands.lua:1588) and any future gate evaluator would suppress these cooldowns except at low target HP.

*Evidence:* Data/SimcRotations.lua:255,274,297 ({t="execute"} on dragonrage/fire_breath/breath_of_eons); tools/simc-apl/evoker_devastation.simc:112,72,74; tools/simc-apl/evoker_augmentation.simc:56; gen_simc_rotations.py:120-121

*Fix:* Only classify as execute when the comparison direction implies low health/short remaining life (target.health.pct< N, time_to_die< N); otherwise delegate.

### [MINOR] ID sanity: buff-gate ids are talent/spell ids, not aura ids - Leaping Flames gate 369939 (aura is 370901) and Essence Burst gate 369297 (Preservation talent; Aug aura is 392268) can never fire (Data/SimcRotations.lua:279)
IsBuffWindowActive requires the PLAYER AURA to carry the gate id (C_UnitAuras.GetPlayerAuraBySpellID, CooldownTracking.lua:523-532). The bridge resolves buff tokens against the castable-spell universe, yielding talent ids: EVOKER_1 aoe living_flame gate {t="buff",id=369939} (Leaping Flames talent; the applied buff is 370901) and EVOKER_3 emerald_blossom gate {t="buff",id=369297} (Preservation's Essence Burst talent; the Augmentation aura is 392268 - cross-spec wrong id, same pattern as moonfire 8921 vs 326646). Both gates evaluate false forever, so the intended proc promotions never happen (fails safe, no misorder). The working Dragonrage gates (375087) work only because that aura id equals the cast id.

*Evidence:* Data/SimcRotations.lua:279,300; BlizzardAPI/CooldownTracking.lua:523-532; tools/simc-apl/evoker_devastation.simc:89; tools/simc-apl/evoker_augmentation.simc:62

*Fix:* Resolve buff.* tokens through an aura-id table (e.g. extend SelfAuras generation) instead of the castable-spell universe, or curate aura ids for gates.

### [MINOR] ID sanity: Emerald Blossom emitted as 365261 in all three EVOKER lists while every other Data table uses 355913 - the rank can never match the queue's spell id (Data/SimcRotations.lua:265)
SimcRotations uses id 365261 for emerald_blossom (EVOKER_1 st/aoe, EVOKER_3 st) but the addon's canonical cast id is 355913 (SpellDB.lua:458, Data/SpellCategories.lua:179, Data/SpellCooldowns.lua:812, Data/SpellArchetypes.lua:3299). Unless FindSpellOverrideByID happens to link 365261<->355913, RotationImport.GetEntry never matches the AC-suggested id, so the entry is dead data (and had it matched, it would promote a heal into the DPS queue via the broken 369297 gate). Bottom-of-list, so no visible misorder.

*Evidence:* Data/SimcRotations.lua:265,281,300 vs SpellDB.lua:458, Data/SpellCooldowns.lua:812

*Fix:* Curate emerald_blossom = 355913, or prefer the id other Data tables use when the bridge's tier-collision picks a duplicate spell record.

### [MINOR] Gate fidelity: {t="cd"} gates drop both the referenced spell and negation - '!cooldown.fire_breath.up' on aoe Deep Breath becomes a bare positive cd gate; cross-spell cd comparisons on Tip the Scales emit an undelegated cd gate (Data/SimcRotations.lua:272)
classify_atom returns {t="cd"} with no id and ignores the leading '!' (gen_simc_rotations.py:104-107): aoe deep_breath's '!cooldown.fire_breath.up&!cooldown.eternity_surge.up' (APL line 68) becomes a single positive {t="cd"}, and st/aoe tip_the_scales' 'cooldown.fire_breath.remains<cooldown.eternity_surge.remains' (lines 70/118) becomes {t="cd"} with NO delegated flag on the st entry (line 259) even though the comparison is unevaluable. Currently dead at runtime (SpellQueue never reads cd gates), so cosmetic/diagnostic-only, but semantically inverted data.

*Evidence:* Data/SimcRotations.lua:259,272,273; tools/simc-apl/evoker_devastation.simc:68,70,118; gen_simc_rotations.py:99-107

*Fix:* Carry the resolved cooldown spell id and neg on cd gates, and delegate cd-vs-cd comparisons.

### [MINOR] Flattener walks past an unconditional run_action_list: Devastation st-only green-list heals (Emerald Blossom, Verdant Embrace) leak into the aoe ranking (Data/SimcRotations.lua:281)
In SimC, run_action_list halts the caller; flatten() treats it like call_action_list and continues (gen_simc_rotations.py:187-191). For k>=3 the walk does aoe, then still walks the unconditional 'run_action_list,name=st' (APL line 60), appending st leftovers - the green healing list (emerald_blossom 365261, verdant_embrace 360995) - at aoe ranks 13-14. Bottom ranks, so no misorder today; also these heals arguably don't belong in a DPS ranking at all (they enter st at 13-14 via the conditional green call at APL line 149).

*Evidence:* Data/SimcRotations.lua:281-282; tools/simc-apl/evoker_devastation.simc:59-60,107-108,149

*Fix:* Stop the walk after an unconditional (or tier-satisfied) run_action_list, matching SimC semantics.

### [MINOR] Non-rotational actions ranked: Quell (interrupt) is rank 1 in both EVOKER_1 lists; Fury of the Aspects (bloodlust) is rank 7 in EVOKER_3 (Data/SimcRotations.lua:253)
quell and fury_of_the_aspects are not in the generator's SKIP set (gen_simc_rotations.py:37-47, which does skip racials/potions/forms), so the interrupt tops both Devastation lists (253, 269) and bloodlust ranks 7 for Augmentation (293). Harmless as long as AC's rotation list never contains them (Quell is also categorized CC in Data/SpellCategories.lua:312), but they are dead-to-misleading rank slots and shift every real ability down one index.

*Evidence:* Data/SimcRotations.lua:253,269,293; gen_simc_rotations.py:37-47; tools/simc-apl/evoker_devastation.simc:57; tools/simc-apl/evoker_augmentation.simc:52

*Fix:* Add quell (and other pure interrupts) plus bloodlust-family spells to SKIP.


## EVOKER_3

### [CRITICAL] EVOKER_3 st: Azure Strike ranked 4 (from the trinket-helper 'items' list) and Eruption/Living Flame ranked 5-6 (from the 'opener_filler' list) - fillers above Fire Breath (9), Breath of Eons (11), Upheaval (12) (Data/SimcRotations.lua:290)
flatten() walks call_action_list items (APL line 50) and run_action_list opener_filler (line 51) before the main list's real entries, because call_applies ignores non-target-count conditions (gen_simc_rotations.py:142-152). The items list contains a castable azure_strike helper (line 93, only meant to weave an off-GCD trinket) and opener_filler contains eruption/living_flame (lines 106-107, only meant while variable.opener_delay>0). First-reach dedup then locks azure_strike=4, eruption=5, living_flame=6, while the empowers and cooldowns the main list actually prioritizes land at fire_breath=9, deep_breath=10, breath_of_eons=11, upheaval=12. Azure Strike and Living Flame are Augmentation's last-resort fillers (filler list, lines 80-81); Azure Strike is always ready and delegated-starve never triggers (free), so slot 2 is effectively pinned to Azure Strike whenever prescience/ebon_might are on cooldown. Same visible symptom class as the reported Druid bug.

*Evidence:* Data/SimcRotations.lua:286-302 (st order hover,prescience,ebon_might,azure_strike,eruption,living_flame,fury_of_the_aspects,tip_the_scales,fire_breath,deep_breath,breath_of_eons,upheaval,time_skip,...); tools/simc-apl/evoker_augmentation.simc:50-51,93,106-108,80-81; gen_simc_rotations.py:142-152,187-191

*Fix:* Skip helper lists whose entries exist only to weave items (e.g. skip actions inside lists named items/trinkets), and treat run_action_list guarded by variable.* conditions as delegated branches that must not claim first-reach rank for spells that reappear unconditionally later.


## HUNTER_1

### [CRITICAL] Barbed Shot ([217200]=12 in TargetDots) is dot-sunk for ~8.4s after every cast, demoting BM's Frenzy-maintenance builder in ALL modes (ac and simc) (Data/TargetDots.lua:56)
SpellQueue's dot-sink (line 539-540) is DotTracker-driven and independent of simc gates: any queue spell whose cast id is in TargetDots sinks to the cooldown bucket while its debuff is live, un-sinking only in the last 30% (PANDEMIC_LEAD). Barbed Shot's value is stacking/maintaining the pet Frenzy buff (~8s) and burning charges - it must keep being suggested while its bleed ticks, exactly the class of ability the TargetDots header says is excluded ('Stacking DoTs and channels are excluded (they must keep being suggested)'). With duration 12, Barbed Shot is demoted to the back of the queue from 0 to ~8.4s post-cast, i.e. past the Frenzy expiry window, in the DEFAULT ac mode too. The corresponding SimcRotations gate {t=dot,id=217200} (st line 310, aoe line 316) was synthesized from 'target_if=min:dot.barbed_shot.remains' - a target SELECTOR, not a maintenance condition - via the make_entry heuristic ('dot.%s.' % token in target_if), corroborating the misclassification (that gate itself is unused at runtime).

*Evidence:* Data/TargetDots.lua:56 [217200]=12. SpellQueue.lua:536-545 dot-sink path; DotTracker.lua:59-65 PANDEMIC_LEAD=0.30. gen_simc_rotations.py:164-166 target_if heuristic. APL: hunter_beast_mastery.simc lines 30/40/55/59/63 - barbed_shot conditions are charge/buff-window based (full_recharge_time, thrill_of_the_hunt), never dot-refresh based.

*Fix:* Exclude Barbed Shot (217200) from gen_target_dots.py output (builder whose recast is desired while its bleed ticks), and teach the make_entry target_if heuristic to ignore pure selector expressions (min:/max: with no refreshable/ticking predicate).

### [MAJOR] Multi-Shot missing from HUNTER_1 aoe/cleave - BM's beast-cleave enabler sinks to rank 900 in simc mode (Data/SimcRotations.lua:313)
Token 'multishot' resolves for MM (257620) but not for BM: the class-wide universe contains both Multi-Shot ids (2643 BM, 257620 MM), the class_index fallback returns None on ambiguity, and CURATED has no HUNTER entries - so BM's aoe list has no multishot entry. In simc mode Multi-Shot ranks 900, below cobra_shot(7) and every ranked entry, even when Beast Cleave is down. The APL places it mid-priority (cleave line 32, drcleave line 42: 'multishot,if=pet.main.buff.beast_cleave.down&...') - it is the defining BM AoE action. Compounded at 2 targets because HUNTER_1 has no cleave tier (see separate finding) so 2T falls back to this aoe list.

*Evidence:* Data/SimcRotations.lua:313-321 (no 257620/2643 entry). SpellArchetypes.lua:17 [2643] Multi-Shot (BM), :331 [257620] (MM). simc_bridge.py:202-204 class fallback returns None if len(ids)!=1. hunter_beast_mastery.simc lines 32, 42.

*Fix:* CURATED['HUNTER_1'] = { multishot = 2643, call_of_the_wild = 359844 }; regenerate.

### [MAJOR] call_of_the_wild unresolved - BM's 2-minute cooldown missing from st and aoe (Data/SimcRotations.lua:304)
APL ranks call_of_the_wild 3rd in st (line 60) and mid-list in cleave/drst; the generated HUNTER_1 lists contain no entry for it (id 359844 per SpellCooldowns.lua:822), so in simc mode it ranks 900: when it comes off cooldown and AC includes it, it displays after cobra_shot instead of near the front. Fail-safe by generator design, but a visible wrong order for the spec's main cooldown under the simc setting.

*Evidence:* hunter_beast_mastery.simc lines 33, 43, 53, 60. Data/SpellCooldowns.lua:822 [359844]=120000 Call of the Wild. No 359844 in Data/SimcRotations.lua HUNTER_1 block (lines 304-322).

*Fix:* Curate call_of_the_wild=359844 for HUNTER_1.

### [MAJOR] bloodshed emitted as 1272099 while SpellCooldowns says Bloodshed=321530 - inconsistent ids across generated tables, rank 3 possibly dead (Data/SimcRotations.lua:308)
Same-token-different-id across the repo's own generated tables: SimcRotations HUNTER_1 uses 1272099 (st rank 3, aoe rank 4) but SpellCooldowns.lua:743 lists [321530]=60000 Bloodshed and 1272099 appears nowhere else in Data/. If the live cast id is 321530 and 1272099 is a talent-definition variant not connected by FindSpellOverrideByID, bloodshed never matches AC's id and is unranked. One of the two tables is wrong/stale either way.

*Evidence:* Data/SimcRotations.lua:308,317 {id=1272099}. Data/SpellCooldowns.lua:743 [321530]=60000. Grep for 1272099 in Data/ hits only SimcRotations.

*Fix:* Verify in-game (/jac inspect) which id the client casts; curate bloodshed accordingly and reconcile SpellCooldowns.

### [MINOR] No cleave tier emitted for HUNTER_1: call_applies ANDs OR'd target-count atoms, so at k=2 no action list applies (tools/gen_simc_rotations.py:142)
Main-list branch conditions like 'talent.black_arrow&(active_enemies<2|!talent.beast_cleave&active_enemies<3)' contain both active_enemies<2 and active_enemies<3; call_applies requires EVERY target-count comparison found by finditer to hold, ignoring the OR structure. At k=2, drst/st fail (2<2) and drcleave/cleave fail (2>2), so the cleave tier flattens to an empty list and is dropped. Runtime falls back cleave->aoe which is roughly right for beast_cleave builds, but wrong for non-beast_cleave builds where the APL wants the ST list at 2 targets - and it compounds the missing-multishot finding since 2T uses the aoe list.

*Evidence:* gen_simc_rotations.py:142-152. hunter_beast_mastery.simc lines 17-20. Data/SimcRotations.lua HUNTER_1 has st+aoe only (lines 304-322).

*Fix:* Evaluate the target-count condition respecting | at top level (treat unparsable clauses as true per-branch), or take the OR of clause results when a top-level | exists.

### [MINOR] cobra_shot gate id 466990 is the Withering Fire talent id; the buff aura id likely differs (gate currently inert because neg gates are never evaluated) (Data/SimcRotations.lua:311)
'buff.withering_fire.down' resolved via the castable universe to talent 466990; the applied aura id is likely different (same passive-vs-aura defect as the MM gates). Zero runtime impact today because negated buff gates are consumed nowhere in SpellQueue (SimcBuffWindowActive skips neg), but the data is wrong if neg gates ever go live.

*Evidence:* Data/SimcRotations.lua:311,320. SpellQueue.lua:449 'not g.neg' filter. 466990 absent from Data/SelfAuras.lua.

*Fix:* Cover by the same buff-token->aura-id fix as the MM finding.


## HUNTER_2

### [CRITICAL] MM st ranks the unconditional bottom filler steady_shot at #3, above trueshot/black_arrow/aimed_shot/rapid_fire/arcane_shot/kill_shot (Data/SimcRotations.lua:327)
First-reach dedup in flatten() lets the early special-case line 'steady_shot,if=variable.buffer_deathblow&buff.trueshot.down&cooldown.trueshot.remains' (drst) permanently claim steady_shot's rank; the APL's real unconditional steady_shot is the LAST line of both drst and sentst. In simc mode rankOf uses list index, and volley(1)/explosive_shot(2) are 45s/30s cooldowns that are usually cooldown-sunk, so Steady Shot heads the normal bucket almost always: the visible queue shows Steady Shot in slot 2 above Aimed Shot / Rapid Fire / Arcane Shot constantly. Same rank-capture pattern as the DRUID_1 wrath/starfire report. Its gates ({t=buff 288613 neg},{t=cd}) are never evaluated by the queue (SpellQueue only consumes positive buff gates for promotion), so nothing suppresses it. Repeated at rank 6 in cleave (line 341) and aoe (line 353), still above aimed_shot (7/8).

*Evidence:* tools/simc-apl/hunter_marksmanship.simc line 57 (special case) vs line 66 (unconditional filler, last); sentst line 109. Data/SimcRotations.lua:327 {id=56641,...} rank 3. SpellQueue.lua:468-475 rankOf = simcRec.rank; SpellQueue.lua:445-455 only positive buff gates read.

*Fix:* In gen_simc_rotations.py flatten(), when the same token is reached again with a weaker/no condition, let the entry re-rank to the later (unconditional) position, or skip rank capture for entries whose only atoms are variable.* (fully delegated special cases).

### [MAJOR] Positive buff gates carry passive-talent ids instead of aura ids (precise_shots 260240, trick_shots 257621, lock_and_load 194595, bulletstorm 389019) - buff-window promotion is dead for MM (Data/SimcRotations.lua:332)
simc_bridge resolves buff tokens against the castable/talent universe, so 'buff.precise_shots.up' resolves to the passive talent 260240, not the proc aura 260242 (same for trick_shots 257621 vs aura 257622, lock_and_load 194595 vs 194594, bulletstorm 389019 vs 389020). BlizzardAPI.IsBuffWindowActive calls GetPlayerAuraBySpellID(gateID)+GetAuraDuration - a passive talent id never yields a duration-bearing aura, so SimcBuffWindowActive never promotes. Effect in simc mode: arcane_shot (st rank 8, gate {buff 260240}), kill_shot (rank 9), black_arrow (rank 5) and multishot (cleave rank 10) never surface during Precise Shots windows; MM's core 'Aimed Shot then Arcane Shots' reactivity is invisible and arcane_shot stays pinned at the bottom. Contrast: the one MM gate that works is Trueshot 288613 (cast id == aura id, present in SelfAuras.lua:921); none of 260240/260242/194594/194595/257621/257622/389019/389020 appear anywhere in SelfAuras.lua.

*Evidence:* Data/SimcRotations.lua:329,332,333,345,356 (gates {t=buff,id=260240}/{id=257621}); :326 (194595), :338/351 (389019). BlizzardAPI/CooldownTracking.lua:523-532. simc_bridge.py resolver builds only castable universe (lines 124-147). Grep of Data/ shows zero occurrences of 260242/194594/257622/389020.

*Fix:* Give the generator a buff-token -> aura-id resolution path (SpellXDescriptionVariables / simc buff spell ids, or a curated buff map), or fall back to delegate when the resolved id is a passive (no aura). Same defect class likely affects other specs.

### [MAJOR] Top-level OR mangling in classify_if produces wrong-branch gates: black_arrow/kill_shot require precise_shots even for builds where the source condition is an OR alternative (tools/gen_simc_rotations.py:83)
split_and splits only on '&' at depth 0, so 'talent.headshot&buff.precise_shots.up&(...)|!talent.headshot' (drst line 59, sentst line 102) yields buff.precise_shots.up as an unconditional conjunct: black_arrow st (line 329) and kill_shot st/cleave (333/344) carry {t=buff,id=260240} as a hard positive gate although for !headshot builds the source is unconditional (black_arrow) or gated on razor_fragments (kill_shot, that branch silently lost). Similarly aimed_shot cleave (line 342) carries a live positive gate {buff 288613 Trueshot} though the APL's other OR branch (lock_and_load&moving_target) allows it without Trueshot - its lock-and-load promotion path is lost. Runtime impact is confined to (missing/spurious) proc-bucket promotion since only positive buff gates are evaluated, but it is wrong under common talent branches.

*Evidence:* gen_simc_rotations.py:83-96 split_and; :131-138 classify_if treats every atom as a conjunct. hunter_marksmanship.simc lines 59, 102, 46. Data/SimcRotations.lua:329,333,342,344.

*Fix:* In classify_atom/classify_if, detect a top-level '|' anywhere in the original expression and delegate the whole condition (emit no positive gates) unless all OR branches share the atom.

### [MINOR] {t="cd"} gates emitted without the referenced spell id (cooldown.trueshot.remains -> anonymous cd gate) (Data/SimcRotations.lua:327)
classify_atom matches cooldown.<spell>.(ready|up|remains) but discards the spell token, emitting {t="cd"} with no id - steady_shot's gate refers to Trueshot's cooldown, not its own. The queue never evaluates cd gates today (only /jac inspect shows them), so this is dead/ambiguous data rather than a live bug, but any future consumer cannot know which cooldown was meant. Systemic across specs (34 occurrences of bare {t="cd"}).

*Evidence:* gen_simc_rotations.py:106-107 returns {"t": "cd"} without resolving m. Data/SimcRotations.lua:327 and many others. Grep shows g.t=="cd" consumed only in DebugCommands.lua:1572.

*Fix:* Emit {t="cd",id=resolve(spell)} (falling back to bare when unresolvable) so the gate is actionable.

### [MINOR] MM kill_shot data id 53351 vs MM cast id 320976; volley has two ids (260243/438317) in SpellCooldowns (Data/SimcRotations.lua:333)
SpellCooldowns lists both [53351]=10000 and [320976]=10000 Kill Shot (SpellArchetypes.lua:2062 tags 320976 as the MM ranged one). HUNTER_2 uses 53351; matching relies on FindSpellOverrideByID bridging 53351->320976 for an MM player. Likely bridges (spec override), so minor - but same-token-different-id across specs, worth an in-game /jac verify. Similarly SpellCooldowns has two Volley rows ([260243]=45000, [438317]=30000); HUNTER_2 rank 1 uses 260243.

*Evidence:* Data/SimcRotations.lua:333,344,356. Data/SpellCooldowns.lua:223 [53351], :741 [320976], :648 [260243], :997 [438317]. RotationImport.lua:90-93 override-only bridge.

*Fix:* Verify in-game which ids AC hands for MM Kill Shot and Volley; curate if the override bridge does not connect them.


## HUNTER_3

### [CRITICAL] Survival's core kit is entirely unranked: raptor_bite/mongoose_bite/butchery/coordinated_assault/spearhead/flanking_strike all unresolved and missing from HUNTER_3 (Data/SimcRotations.lua:360)
HUNTER_3 st/aoe contain only 8 entries, 3 of which are utility (harpoon/muzzle/aspect_of_the_eagle). The spec's filler (Raptor Strike 186270 / Mongoose Bite 259387 - the most-pressed buttons, and the serpent_sting maintainers), its 2-min cooldown Coordinated Assault 360952, Spearhead 360966, Flanking Strike 269751 and Butchery 212436 resolve to None and are dropped (fail-safe residue). In simc mode unresolved spells get rank 900 (SpellQueue rankOf), so Raptor/Mongoose sink below explosive_shot(7) and kill_shot(8) permanently - visibly wrong SV queue order in every fight. CURATED in gen_simc_rotations.py has only a DRUID_2 block; no HUNTER curation exists despite this being the largest residue of the class.

*Evidence:* Data/SimcRotations.lua:360-381 (8 entries only). tools/simc-apl/hunter_survival.simc lines 61-78 plst uses raptor_bite x5, flanking_strike, coordinated_assault, spearhead; sentst lines 98-116 adds mongoose_bite, butchery. Canonical ids exist in repo tables: SpellCooldowns.lua:600 (Butchery 212436), 691 (Flanking Strike 269751), 826 (Coordinated Assault 360952), 827 (Spearhead 360966); RangeReferences.lua:53-54 (Mongoose 259387, Raptor 186270). gen_simc_rotations.py:53-59 CURATED lacks HUNTER.

*Fix:* Add HUNTER_3 curated tokens: raptor_bite=186270 (or 259387 with Mongoose Bite talent - needs the same override-bridge treatment as other talent swaps), mongoose_bite=259387, butchery=212436, coordinated_assault=360952, spearhead=360966, flanking_strike=269751; regenerate.

### [MAJOR] fury_of_the_eagle emitted as 203413 (old artifact-trait id) while the canonical cast id is 203415 - rank 5 likely dead (Data/SimcRotations.lua:366)
The repo's own mirrors disagree with SimcRotations: SpellCooldowns.lua:549 [203415]=45000 and SelfAuras.lua:690 [203415] use 203415; SimcRotations (and SpellArchetypes.lua:785) use 203413. The resolver's same-name-collision rule picks min(id) (simc_bridge.py line 200), i.e. 203413 < 203415. 203413 is not an override-chain relative of 203415, so RotationImport's baseID bridge (FindSpellOverrideByID) will not map between them: GetEntry(203415) misses and Fury of the Eagle is unranked (900) despite being rank 5, sinking below explosive_shot/kill_shot when ready.

*Evidence:* Data/SimcRotations.lua:366,376 {id=203413}. Data/SpellCooldowns.lua:549 [203415]. Data/SelfAuras.lua:690 [203415]. simc_bridge.py:197-201 min-id collision rule. RotationImport.lua:90-93,107-108 override-only bridging.

*Fix:* Curate fury_of_the_eagle=203415 for HUNTER_3; consider preferring the id present in the SpellCooldowns universe when a collision has one candidate with a cooldown row.

### [MAJOR] SV kill_command emitted as BM's 34026; SV's cast id is 259489 - the moonfire 8921/326646 same-token-different-id pattern (Data/SimcRotations.lua:365)
SpellCooldowns.lua carries both [34026]=7500 (BM) and [259489]={2,5000} (SV, 2 charges). HUNTER_3 uses 34026 for kill_command (rank 4, the top real ability). If the SV client casts/queues 259489 and it is not an override-chain relative that FindSpellOverrideByID(34026) maps forward to, GetEntry misses and SV's Kill Command is unranked in simc mode. Mechanism matches the min-id collision rule (34026 < 259489). Impact is conditional on the override bridge, hence major not critical.

*Evidence:* Data/SimcRotations.lua:365,375 {id=34026}. Data/SpellCooldowns.lua:171 [34026], :645 [259489]={2,5000}. simc_bridge.py:200 min() tie-break. RotationImport.lua:146 m[spellID] or m[baseID(spellID)].

*Fix:* Curate kill_command=259489 for HUNTER_3 (and verify in-game which id AC hands over).

### [MINOR] cds-list utility occupies the top 3 ranks: harpoon(1), muzzle(2), aspect_of_the_eagle(3) (Data/SimcRotations.lua:362)
actions.cds is flattened as ranked rotation entries because harpoon, muzzle and aspect_of_the_eagle are not in SKIP: the gap-closer (source condition prev.kill_command, delegated), the interrupt, and a range utility hold ranks 1-3 in both st and aoe. AC rarely hands these over so it is mostly dead data that offsets real abilities' ranks, but if any of them ever appears in the queue it jumps to the front. Systemic: MAGE_1/MAGE_3 rank counterspell #1 the same way.

*Evidence:* Data/SimcRotations.lua:362-364,372-374. hunter_survival.simc lines 31, 35, 39 (all inside actions.cds). gen_simc_rotations.py:37-47 SKIP lacks interrupts/movement.

*Fix:* Add interrupts (muzzle, counterspell, kick, ...) and utility movement (harpoon, aspect_of_the_eagle) to SKIP, or skip the cds sub-list for ranking.

### [MINOR] Entry-level active_enemies conditions dropped: explosive_shot,if=active_enemies>1 becomes ungated rank 7 in st (Data/SimcRotations.lua:368)
classify_atom returns (None, False) for target-count atoms on the assumption the tier split handles them, but the tier split only gates call_action_list edges, not per-entry ifs. plst's 'explosive_shot,if=active_enemies>1' (line 73) becomes {id=212431,gates={}} (not delegated) at rank 7 in st, above kill_shot (8), while the pure-ST source order is kill_shot (line 77) before the unconditional explosive_shot (line 78). Mild inversion; also makes st vs aoe delegation flags differ for the same spell (aoe explosive_shot is delegated).

*Evidence:* gen_simc_rotations.py:122-123. hunter_survival.simc lines 73-78. Data/SimcRotations.lua:368 vs :378.

*Fix:* For entry-level target-count atoms, evaluate them against the tier's k (drop the entry from tiers where the comparison is false) instead of ignoring them.

### [MINOR] Serpent Sting maintenance has no runtime representation: TargetDots keys a cast id (271788) modern SV never casts, and the applying entries (raptor_bite) are unresolved (Data/TargetDots.lua:58)
The APL's serpent_sting maintenance ('raptor_bite,...,if=!dot.serpent_sting.ticking...', plst line 64) is lost twice over: raptor_bite is unresolved (no entry, no dot gate), and DotTracker's [271788]=18 only arms on OnCastSucceeded(271788) - Serpent Sting is applied passively by Raptor Strike in current SV, so the tracker never fires. Dead data + lost gate; no mis-order, just no dot awareness for SV.

*Evidence:* Data/TargetDots.lua:58. DotTracker.lua:87-90 (armed only by casting a tracked id). hunter_survival.simc lines 64-65.

*Fix:* When raptor_bite/mongoose_bite are curated in, have gen_target_dots (or CURATED) map the applicator casts 186270/259387 to the Serpent Sting debuff duration.


## MAGE_1

### [CRITICAL] Arcane Barrage ranked #2 in st from a fight_remains<2 line; APL uses it as bottom filler / conditional spender (Data/SimcRotations.lua:385)
flatten() dedups by first reach. mage_arcane.simc line 42 'arcane_barrage,if=fight_remains<2' (an almost-never-true fight-end special case) sits near the top of actions=main, so Barrage claims rank 2 with gates={},delegated=true. Its real uses are conditional mid-list (4 charges, intuition, end of burst) and the unconditional copies are the very BOTTOM fillers (spellslinger line 122, sunfury line 160). Runtime (SpellQueue rankOf simcMode): Barrage has no cooldown and negligible cost, so 'delegated' starve-sink never fires -> the queue's first re-ranked slot shows Arcane Barrage essentially always, at any charge count. Exact analog of the reported DRUID_1 Sunfire/Starfire symptom.

*Evidence:* Data/SimcRotations.lua:385 '{id=44425,gates={},delegated=true},  -- arcane_barrage' at list index 2; tools/simc-apl/mage_arcane.simc:42 'actions+=/arcane_barrage,if=fight_remains<2' vs :122 'actions.spellslinger+=/arcane_barrage' (unconditional last) and :160.

*Fix:* In gen_simc_rotations.py, treat fight_remains/time-only conditions as non-ranking (skip that occurrence for dedup purposes, letting a later reach set the rank), or rank an id at its LAST unconditional reach when the first reach is delegated-only.

### [MINOR] Counterspell ranked #1 in MAGE_1 and MAGE_3 st - an interrupt occupies the top SimC rank because it is not in the generator's SKIP set (Data/SimcRotations.lua:384)
'actions=counterspell' heads both the arcane and frost APLs and counterspell is castable and resolvable, so it takes rank 1 with gates={}. Harmless today only if C_AssistedCombat's rotation list never contains Counterspell (GetEntry is only consulted for AC-supplied ids); if AC ever surfaces the interrupt, it would pin to the first re-ranked slot permanently. Fire (MAGE_2) has no counterspell line, confirming this is APL-driven, not intended data.

*Evidence:* Data/SimcRotations.lua:384 and :412,:425,:438 '{id=2139,gates={}},  -- counterspell' at index 1; tools/simc-apl/mage_arcane.simc:26, mage_frost.simc:18; gen_simc_rotations.py SKIP (lines 37-47) lacks counterspell/kick-type interrupts.

*Fix:* Add interrupts (counterspell, kick, pummel, etc.) to SKIP in gen_simc_rotations.py.

### [MINOR] MAGE_1 and MAGE_2 emit only an st list - all AOE/cleave ordering intent (arcane_explosion/barrage AOE lines, sf_filler meteor active_enemies>=2) is lost (Data/SimcRotations.lua:382)
Arcane and fire branch AOE at the ENTRY level (active_enemies in entry if=, or via variables), which the flattener drops, so st/cleave/aoe flatten identically and dedup keeps only st. Consequence: in AOE the arcane queue still ranks arcane_explosion at 11 (APL wants it high for charge-building at >1 targets, lines 115/158 of mage_arcane.simc) and barrage's aggressive AOE lines add nothing; fire aoe accidentally benefits from the flamestrike-rank-3 defect. As coded per the generator's tier design, but the context feature is inert for two of three mage specs.

*Evidence:* Data/SimcRotations.lua:382-397 (MAGE_1: st only), :398-409 (MAGE_2: st only) vs :410-451 (MAGE_3: st/cleave/aoe because frost branches at call level, mage_frost.simc:20-26); gen_simc_rotations.py:141-152.

*Fix:* Extend call_applies to entry-level if= conditions (numeric active_enemies atoms) so per-tier entry inclusion/ordering differs for entry-branching specs.


## MAGE_2

### [CRITICAL] Flamestrike ranked #3 in the single-target list (and fire has ONLY an st list) - AOE spender above Pyroblast/Scorch/Fireball in pure ST (Data/SimcRotations.lua:402)
Two compounding generator gaps: (1) entry-level active_enemies conditions are dropped - classify_atom returns (None,False) claiming 'handled by the tier split', but call_applies() is only applied to call/run_action_list lines, never to entry if=; (2) even at call level, call_applies only parses numeric thresholds (\d+), and fire gates flamestrike on VARIABLES (ff_combustion_flamestrike=100 for frostfire builds, i.e. never in ST). Result: flamestrike enters at its first reach (ff_combustion line 60) with gates={},delegated=true at rank 3. Flamestrike has no cd and modest mana cost, so it is 'ready' constantly -> a fire mage in single target sees Flamestrike ranked above pyroblast(4)/meteor(5)/scorch(6)/fireball(7) in the re-ranked tail. Because entry-level target-count conditions are ignored, st==cleave==aoe for fire and only st was emitted, so this wrong-in-ST order is the only order.

*Evidence:* Data/SimcRotations.lua:402 '{id=2120,gates={},delegated=true},  -- flamestrike' at index 3 of MAGE_2.st (no cleave/aoe blocks exist, lines 398-409); tools/simc-apl/mage_fire.simc:12-15 (flamestrike thresholds are variables, =100 for frostfire), :60 'flamestrike,if=buff.fury_of_the_sun_king.up&active_enemies>=variable.ff_combustion_flamestrike'; gen_simc_rotations.py:122-123 (target-count atom -> None,False) and :144-152 (call_applies only sees call conditions, numeric only).

*Fix:* Apply call_applies (extended to entry-level if=) when flattening entries, and treat a target-count comparison against a variable as 'unsatisfiable at k=1' or at minimum delegate+demote rather than silently dropping the clause.

### [MAJOR] fire_blast neg-gate uses 195283 (Hot Streak passive) instead of proc aura 48108 - systemic 'talent id, not aura id' buff resolution (Data/SimcRotations.lua:401)
Same resolver defect as fingers_of_frost: buff.hot_streak.react resolved to the fire passive 195283; the in-game proc aura is 48108 ('Hot Streak!'). Here the gate is neg=true and SpellQueue only evaluates positive buff gates, so today it is dead data - but any future runtime use of neg buff gates, and the /jac inspect gate display (DebugCommands.lua:1582), evaluate a nonexistent aura. Third instance of the pattern: freezing_rain -> 270233 (talent) on blizzard entries (Data/SimcRotations.lua:421,429) where the granted aura is 270232, meaning blizzard's Freezing-Rain promotion also never fires. Pattern check across specs: gates only work when cast id == aura id (combustion 190319, presence_of_mind 205025).

*Evidence:* Data/SimcRotations.lua:401 '{t="buff",id=195283,neg=true}' and :421/:429 '{t="buff",id=270233}'; 48108/44544/270232 absent from all Data tables; simc_bridge.py resolver tiers 180-201 draw from TraitDefinition SpellID columns.

*Fix:* Resolve buff.<token> against a proc/aura id table (or curated overrides: hot_streak=48108, fingers_of_frost=44544, freezing_rain=270232); have the generator warn when a buff gate id equals a passive/talent definition id.

### [MAJOR] Pyroblast rank 4 with gates={} - Hot Streak condition lost via first-reach (fury_of_the_sun_king line), suggesting hardcast Pyroblast (Data/SimcRotations.lua:403)
First reach is ff_combustion line 61 'pyroblast,if=buff.fury_of_the_sun_king.up'; fury_of_the_sun_king failed to resolve -> unknown buff -> delegate with no gate. The dominant real uses ('pyroblast,if=buff.hot_streak.react', ff_combustion:67, ff_filler:86, sf_filler:118) are dropped by dedup, so the generated entry carries neither a hot_streak gate nor any promotion window. Pyroblast (4.5s hardcast, normally never cast raw) ranks 4, permanently above scorch(6)/fireball(7) in the tail. Blizzard's Hot Streak proc overlay still promotes it when procced, which softens but does not remove the mis-order between procs.

*Evidence:* Data/SimcRotations.lua:403 '{id=11366,gates={},delegated=true},  -- pyroblast'; tools/simc-apl/mage_fire.simc:61 vs :67/:86/:118.

*Fix:* Same as the ice_lance fix: merge evaluable gates across duplicate reaches (would attach the hot_streak buff gate, once the aura-id resolution above is fixed).

### [MAJOR] Phoenix Flames missing from MAGE_2 - unresolved token, demoted below Fireball in simc mode (Data/SimcRotations.lua:398)
phoenix_flames appears at mage_fire.simc lines 69, 89, 105, 123 (in sf_filler it outranks the final scorch/fireball fillers; in sf_combustion it is the 2nd-to-last filler) but is absent from the generated MAGE_2.st -> unresolved. In simc mode it gets rank 900, sorting below fireball(7) always. Data/SpellCooldowns.lua:641 already carries it as [257541]={2,25000}, so the canonical id is known to the repo - only the bridge fails to resolve the token.

*Evidence:* Data/SimcRotations.lua:398-409 has no phoenix_flames; tools/simc-apl/mage_fire.simc:69,89,105,123; Data/SpellCooldowns.lua:641.

*Fix:* Curate phoenix_flames=257541 for MAGE_2 in gen_simc_rotations.py CURATED.

### [MINOR] {t="cd"} gates carry no spell id and lose comparison direction - they encode OTHER spells' cooldown conditions but are dead/uninterpretable at runtime (Data/SimcRotations.lua:407)
classify_atom maps any 'cooldown.X.(ready|up|remains)' to bare {t="cd"}, dropping both X and the operator. MAGE_2 shifting_power's gate came from 'cooldown.combustion.remains>10' (combustion NOT coming up soon), MAGE_3 st shifting_power's from 'cooldown.comet_storm/icy_veins.remains>8', MAGE_3 aoe ice_lance's from 'cooldown.comet_storm.ready' - three different referents and one inverted sense, all collapsed to the same idless shape. SpellQueue never evaluates t="cd" gates (only positive buff gates, SpellQueue.lua:445-455), so today this is dead data plus a misleading /jac inspect display (DebugCommands.lua:1572 shows it as a cd gate on the entry's own spell).

*Evidence:* Data/SimcRotations.lua:407 '{id=314791,gates={{t="cd"}}}', :416, :430, :445, :448; gen_simc_rotations.py:106-107; tools/simc-apl/mage_fire.simc:87, mage_frost.simc:112,124; SpellQueue.lua:445-455 (buff-only evaluation).

*Fix:* Either record the referenced spell id and polarity ({t="cd",id=...,neg=...}) or classify other-spell cooldown atoms as delegated instead of emitting an idless gate.


## MAGE_3

### [CRITICAL] Ice Lance ranked #6 unconditional in st, above Frostfire Bolt (#7) and Frostbolt (#11) - all its FoF/Winter's-Chill conditions lost to first-reach dedup (Data/SimcRotations.lua:417)
First reach of ice_lance at k=1 is ff_st_boltspam line 125 'if=remaining_winters_chill=2' -> unrecognized atom -> gates={},delegated=true; later reaches carrying the evaluable buff.fingers_of_frost.react gate (ff_st:113, ss_st:194) are discarded by seen-id dedup. Ice Lance is instant, no cd, cheap -> never sinks; the frost st tail permanently ranks naked Ice Lance above the primary fillers. Unbuffed hardcast Ice Lance is a dps loss; SimC only casts it under FoF/Winter's Chill. Blizzard's proc overlay still promotes it when FoF actually procs, but the constant rank-6 placement between procs is visibly wrong.

*Evidence:* Data/SimcRotations.lua:417 '{id=30455,gates={},delegated=true},  -- ice_lance' index 6 vs :418 frostfire_bolt index 7 and :422 frostbolt index 11; tools/simc-apl/mage_frost.simc:125 (first reach, remaining_winters_chill=2) vs :113 'ice_lance,if=buff.fingers_of_frost.react' and :194.

*Fix:* On duplicate reaches, merge gates (union of evaluable gates across occurrences) or keep the occurrence with the most evaluable gates instead of strictly first-reach-wins.

### [MAJOR] Ice Lance cleave buff gate uses 112965 (Fingers of Frost passive talent), not the proc aura 44544 - promotion can never fire (Data/SimcRotations.lua:431)
simc_bridge resolves buff tokens through the spell-name universe (talent TraitDefinition ids), so buff.fingers_of_frost.react resolved to the passive talent spell 112965. BlizzardAPI.IsBuffWindowActive (CooldownTracking.lua:523) calls GetPlayerAuraBySpellID(id) + duration probe - a passive has no timed aura window, and the actual proc aura is 44544. The cleave ice_lance entry is NOT delegated and this gate is its only promotion path, so in cleave Ice Lance never proc-promotes via SimC data (Blizzard's overlay is the only remaining path). 44544 appears nowhere in the Data tables to cross-corroborate.

*Evidence:* Data/SimcRotations.lua:431 '{id=30455,gates={{t="buff",id=112965}}},  -- ice_lance'; BlizzardAPI/CooldownTracking.lua:523-532; grep for 44544 across Data/ returns nothing.

*Fix:* Add a curated buff-token -> aura-id map for the generator (fingers_of_frost=44544) or resolve buff tokens against an aura table instead of the castable/talent universe.

### [MAJOR] Glacial Spike missing from every MAGE_3 context - core 5-icicle spender unresolved, sinks to rank 900 below Frostbolt in simc mode (Data/SimcRotations.lua:410)
glacial_spike appears 7 times in mage_frost.simc (lines 78, 92, 109, 123, 155, 175, 192) as a high-priority spender but is absent from all three generated MAGE_3 lists -> unresolved residue. Fail-safe means unranked, but in simc mode unranked = rank 900 (SpellQueue.lua:470), i.e. BELOW frostbolt(11) - worse than neutral: for glacial-spike builds the queue actively demotes GS at 5 icicles under every ranked filler. Candidate ids exist in the repo's own client data (SpellArchetypes.lua: 228600, 1236211, 1262862 - the multi-id collision is the likely resolver failure).

*Evidence:* No 'glacial' token in Data/SimcRotations.lua MAGE_3 (lines 410-451); tools/simc-apl/mage_frost.simc:78,92,109,123,155,175,192; Data/SpellArchetypes.lua:1852,2562,2631.

*Fix:* Add MAGE_3 to CURATED in gen_simc_rotations.py with the canonical cast id for glacial_spike (verify in game; 228600 is the historical cast id).

### [MAJOR] Comet Storm emitted as id 1247777, uncorroborated by any other Data table (SpellArchetypes has 153596/438609; SpellCooldowns has no Comet Storm at all) (Data/SimcRotations.lua:415)
The classic Comet Storm cast id is 153595; the generated entries use 1247777 (appears ONLY in SimcRotations across the repo). SpellArchetypes tags Comet Storm as 153596 and 438609 - a third and fourth id for the same token. If Blizzard's AC rotation reports Comet Storm under 153595 (or the archetype ids) and ResolveSpellID does not bridge to 1247777, RotationImport.GetEntry misses -> Comet Storm silently unranked (rank 900) despite being in the list. Same-token-different-id-across-tables is exactly the moonfire 8921/326646 pattern flagged for DRUID_1. Also: Comet Storm (30s cd) has NO entry in Data/SpellCooldowns.lua under any of its ids. Cannot be fully verified offline - needs an in-game /jac inspect to see which id AC reports.

*Evidence:* Data/SimcRotations.lua:415,428,446 (id=1247777); Data/SpellArchetypes.lua:161 ([153596]="ranged") and :578 ([438609]); grep for 153595 and for 'Comet' in Data/SpellCooldowns.lua: no hits.

*Fix:* Verify in game which spellID AC's rotation and the spellbook report for Comet Storm on 12.0; curate the token to that id and add its cooldown to SpellCooldowns.lua.

### [MAJOR] Ice Nova ranked #8 in st (above Frostbolt #11) solely because the 'movement' fallback action list is flattened into the main priority (Data/SimcRotations.lua:419)
In mage_frost.simc, st-context Ice Nova exists ONLY inside actions.movement (line 135), the cannot-cast-while-moving fallback, reached via 'call_action_list,name=movement' at the tail of each ff list. flatten() walks it like any call with no marker, so ice_nova lands rank 8, gates={}, not delegated. Runtime: 25s-cd instant, ready most of the time -> ranks above the primary filler Frostbolt whenever off cd, in a list where SimC would never press it stationary. (Dedup masks the same issue for flurry/frozen_orb/ice_lance because they were already seen.)

*Evidence:* Data/SimcRotations.lua:419 '{id=157997,gates={}},  -- ice_nova' index 8; tools/simc-apl/mage_frost.simc:130-136 (movement list) and :116,128 (calls at list tails); no other st-context ice_nova line exists.

*Fix:* Skip lists named 'movement' (or any list reached only from a trailing unconditional call) in the flattener, or rank movement-list entries after all main-line entries.

### [MINOR] Icy Veins missing from MAGE_3 (unresolved) even though the repo knows id 12472; buff.icy_veins gates degrade to blanket delegation (Data/SimcRotations.lua:410)
actions.cds line 30 'icy_veins' is unconditional and castable but absent from all generated MAGE_3 lists -> unresolved token. Impact is limited (a 2min cd sinks to the cooldown bucket when down anyway; when ready it ranks 900 instead of ~2). Secondary effect: every 'buff.icy_veins.up/down' condition in the APL resolves to unknown-buff -> delegated, so Icy-Veins-window logic (e.g. blizzard/shifting_power timing, deaths_chill frostbolt lines) carries no gates.

*Evidence:* No icy_veins entry in Data/SimcRotations.lua:410-451; tools/simc-apl/mage_frost.simc:30; Data/SpellCooldowns.lua:97 [12472]=120000 and Data/SelfAuras.lua:67 [12472]=true.

*Fix:* Curate icy_veins=12472 for MAGE_3.


## MONK_1

### [MAJOR] BrM st: tiger_palm rank 9 above breath_of_fire(12)/rushing_jade_wind(14) - first-reach dedup takes the Blackout-Combo-conditional line's rank, unconditional filler line lost (Data/SimcRotations.lua:462)
tiger_palm's first APL reach is line 30 (if=buff.blackout_combo.up); its unconditional filler slot is line 42, dead last. Dedup-by-first-reach assigns rank 9, and since the runtime never demotes on a failed gate (gates only promote via SimcBuffWindowActive, and this gate's id is the wrong/talent id anyway), TP sits above breath_of_fire and rushing_jade_wind permanently. In the common no-Blackout-Combo-buff state the APL wants TP last. Same family as DRUID_1: conditional-early-reach permanently outranks unconditional-late-reach; combined with the promote-only gate model, the condition effectively evaporates.

*Evidence:* tools/simc-apl/monk_brewmaster.simc:30 vs :42; Data/SimcRotations.lua:462 rank 9 {t='buff',id=196736} vs :465 breath_of_fire rank 12, :467 rushing_jade_wind rank 14; gen_simc_rotations.py:178-199 'first/highest-priority reach wins'; SpellQueue.lua:529-549 gates never demote.

*Fix:* When dedup drops a LATER occurrence with strictly weaker conditions, keep the union: rank at the later (unconditional) position unless the first-reach gate is runtime-evaluable.

### [MINOR] BrM keg_smash rank frozen behind Weapons-of-Order first reach; unconditional keg_smash (APL line 40) lost to dedup (Data/SimcRotations.lua:461)
keg_smash first reach is line 29 (buff.weapons_of_order.up & compound) -> rank 8, gates buff 387184, delegated. The unconditional line 40 is dedup'd away. Because gates never demote, rank 8 is kept in all states, which happens to sit correctly between rising_sun_kick(7) and tiger_palm(9), and the WoO gate id 387184 IS the aura id, so promotion during WoO works. Net effect: mostly benign; the WoO-window promotion is a bonus. Documented so synthesis can separate this benign instance from the harmful BrM tiger_palm one.

*Evidence:* tools/simc-apl/monk_brewmaster.simc:29,31,40; Data/SimcRotations.lua:461; SpellCooldowns.lua:914 [387184] Weapons of Order (cast==aura).

*Fix:* Covered by the dedup-union fix above.

### [MINOR] celestial_brew: all readable gates (buff.weapons_of_order.up, !dot.aspect_of_harmony_damage.ticking) lost because the whole if= is wrapped in parentheses (Data/SimcRotations.lua:455)
APL lines 18-21 wrap the entire condition in parens; split_and yields one compound atom -> conservatively delegated with gates={}. Gate-loss pattern (DRUID_1 sunfire category) but the conservative fallback (delegated, rank preserved) plus brew charge cooldowns keep the visible impact small.

*Evidence:* tools/simc-apl/monk_brewmaster.simc:18-21; gen_simc_rotations.py:104-106 compound->delegate; Data/SimcRotations.lua:455 {id=322507,gates={},delegated=true}.

*Fix:* Unwrap a fully-parenthesized top-level expression before split_and.

### [MINOR] Data/TargetDots.lua has no monk entries - Breath of Fire dot never sinks the suggestion (Data/TargetDots.lua:1)
Breath of Fire (cast 115181, debuff 123725) is absent from TargetDots, so DotTracker.IsDotActiveOnCurrentTarget never matches and the queue keeps suggesting BoF while its dot runs. Impact bounded by BoF's 15s cooldown (~= dot duration) sinking it via not-ready most of the window.

*Evidence:* grep of Data/TargetDots.lua for 115181/123725/monk: no matches; SpellQueue.lua:539-540 dot sink path; SpellCooldowns.lua:360 [115181]=15000.

*Fix:* Add Breath of Fire to tools/gen_target_dots.py coverage (cast 115181 -> aura 123725).


## MONK_2

### [MAJOR] MW st: chi_burst ranked 8 at single target from an active_enemies>=2-only line - entry-level target-count conditions are never applied (Data/SimcRotations.lua:479)
classify_atom returns None for spell_targets/active_enemies atoms with the comment 'handled by the tier split', but flatten() only applies call_applies to call_action_list/run_action_list - entry-level if= target counts are silently dropped. MW's APL branches entirely at entry level, so: (a) chi_burst (APL line 26, if=active_enemies>=2, its ONLY line) is ranked 8 in st with gates={} and not delegated - suggested at single target above crackling_jade_lightning(9)/jadefire_stomp(10)/blackout_kick(11)/tiger_palm(12) whenever off cd, though the APL never casts it at 1 target; (b) all MW tier lists collapse identical (only st emitted), so jadefire_stomp's rank/gates come from the 4-10-target line 28 (gates={}) and the st-specific buff.jadefire_stomp.down condition of line 30 is lost.

*Evidence:* tools/simc-apl/monk_mistweaver.simc:26 'chi_burst,if=active_enemies>=2', :28-30; gen_simc_rotations.py:122-123 (returns None,False for target-count) vs :178-199 flatten (call_applies only on calls); Data/SimcRotations.lua:479 {id=123986,gates={}} in st.

*Fix:* In flatten, skip entries whose if= fails call_applies(mods['if'], k) for target-count clauses (reuse the existing function).

### [MAJOR] MW invoke_chiji unresolved and silently absent - Chi-Ji builds get their invoke sunk to rank 900 (Data/SimcRotations.lua:470)
APL line 20 (invoke_chiji, above invoke_yulon) is missing from MONK_2: the token 'invoke_chiji' cannot slug-match 'Invoke Chi-Ji, the Red Crane' (slug 'invoke_chi_ji_the_red_crane' - the underscore split differs, and the prefix-alias check needs startswith('invoke_chiji_')). Fail-safe drop per design, but Chi-Ji is the common MW pick; in simc mode the invoke is unranked (900) and sinks below tiger_palm, while yulon builds get rank 3.

*Evidence:* tools/simc-apl/monk_mistweaver.simc:20-21; Data/SimcRotations.lua:470-484 has invoke_yulon (322118) but no 325197; SpellCooldowns.lua:766 [325197]='Invoke Chi-Ji, the Red Crane'; simc_bridge.py slug/prefix logic lines 33-34, 205-210.

*Fix:* CURATED['MONK_2'] = { invoke_chiji = 325197 }.


## MONK_3

### [CRITICAL] WW blackout_kick/spinning_crane_kick/touch_of_death emitted with non-cast duplicate spell ids (261916/343730/325215) - all three unranked at runtime (Data/SimcRotations.lua:504)
simc_bridge resolver tier-1 (SpecializationSpells) matched same-name duplicate spec records instead of the castable ids: blackout_kick=261916 (cast is 100784), spinning_crane_kick=343730 (cast is 101546), touch_of_death=325215 (cast is 322109). AC hands the queue the cast id; RotationImport.GetEntry tries m[spellID] then m[FindSpellOverrideByID(spellID)] - for WW, 100784/101546/322109 have no override to those duplicate records, so lookup misses -> rank 900 sink. In simc mode, Blackout Kick and Spinning Crane Kick (WW's core spenders) and Touch of Death permanently sink below jadefire_stomp/chi_burst at the queue tail. Same pattern as DRUID_1 moonfire 326646.

*Evidence:* Data/SimcRotations.lua:501-504,522-525 (ids 343730/325215/261916); SpellName CSV: 261916='Blackout Kick', 325215='Touch of Death', 343730='Spinning Crane Kick' (duplicates of 100784/322109/101546); every other Data table uses the cast ids: SpellCooldowns.lua:306 [100784], :746 [322109]; ChanneledSpells.lua:54 [101546]; MONK_1/MONK_2 blocks themselves use 100784/322109/101546/322729. RotationImport.lua:146 m[spellID] or m[baseID(spellID)]; SpellQuery.lua:365-373 ResolveSpellID=FindSpellOverrideByID (base->override only).

*Fix:* Add CURATED['MONK_3'] = { blackout_kick=100784, spinning_crane_kick=101546, touch_of_death=322109 } in tools/gen_simc_rotations.py (or make the resolver prefer ids that are also in SpellCooldowns/known-cast tables); regenerate.

### [CRITICAL] WW st: normal_opener (time<4) flattens into permanent ranks - tiger_palm rank 5 / rising_sun_kick rank 6 above every cooldown and spender (Data/SimcRotations.lua:492)
monk_windwalker.simc line 40 calls normal_opener before cooldowns/default_st, gated only by time<4 (plus active_enemies<3 which call_applies honors). call_applies ignores non-target-count clauses, so the 4-second opener list contributes first-reach ranks forever: tiger_palm (opener line 240) rank 5, rising_sun_kick rank 6, above storm_earth_and_fire(7), invoke_xuen(8), fists_of_fury(11), whirling_dragon_punch(12), strike_of_the_windlord(16). Since gates can only promote (never demote), Tiger Palm - the energy builder, conditional even in the opener (chi<6) - is pinned near the front of the WW st queue whenever affordable. Analogous to the DRUID_1 kotg_st run_action_list issue.

*Evidence:* tools/simc-apl/monk_windwalker.simc:40 'call_action_list,name=normal_opener,if=time<4&active_enemies<3', :240-241; gen_simc_rotations.py:145-152 call_applies only tests target-count atoms; Data/SimcRotations.lua:492-493 tiger_palm/rising_sun_kick at ranks 5-6; hand-walk of flatten(k=1) reproduces the emitted order exactly.

*Fix:* Treat time<N-gated calls as non-applying (or rank opener-only reaches last); or add an opener-list name heuristic in the flattener.

### [MAJOR] Top-level-OR mis-split plants gates from one OR branch as unconditional: WW crackling_jade_lightning and celestial_conduit get spurious SEF-buff promotion gates (Data/SimcRotations.lua:505)
split_and splits on '&' at depth 0 without checking for top-level '|', so conjuncts of ONE OR branch become standalone gates. WW st crackling_jade_lightning (APL line 203): the final branch's 'buff.storm_earth_and_fire.up' becomes gate {t='buff',id=137639}; since any active positive buff gate promotes into the PROC bucket (front of queue), CJL is promoted to the front every SEF window (every ~90s) regardless of the capacitor-stack conditions every branch actually requires. Same mechanism gives celestial_conduit (line 500) its SEF gate while the 'fight_remains<15' branches needed none, and whirling_dragon_punch (502.., line 184 APL) a {t='cd'} gate from one branch only. Gates emitted are boolean-algebraically wrong, not merely conservative.

*Evidence:* gen_simc_rotations.py:83-96 split_and (no top-level-| detection) + 131-138 classify_if; tools/simc-apl/monk_windwalker.simc:203 (SEF conjunct only in last OR branch), :185; Data/SimcRotations.lua:505 {t='cd'},{t='buff',id=137639} on 117952; SpellQueue.lua:529-535 promotion into procced bucket.

*Fix:* In classify_if, if the expression contains '|' at depth 0, delegate the whole expression (gates=[], delegated=True) - matching the existing conservative treatment of parenthesized ORs.

### [MINOR] Movement/interrupt utilities (roll, chi_torpedo, flying_serpent_kick, spear_hand_strike) occupy ranks 1-4 of both WW lists (Data/SimcRotations.lua:488)
These tokens are not in SKIP, so the movement-gated APL lines 17-20 rank them 1-4. AC's rotation list should never contain them, making the ranks dead data (they do not shift relative order of real entries since ranks are list indices compared pairwise), but they bloat every WW list and would front-rank instantly if AC ever surfaces spear_hand_strike.

*Evidence:* tools/simc-apl/monk_windwalker.simc:17-20; gen_simc_rotations.py:37-47 SKIP lacks roll/chi_torpedo/flying_serpent_kick/spear_hand_strike; Data/SimcRotations.lua:488-491,510-513.

*Fix:* Add the four tokens to SKIP.

### [MINOR] WW 'aoe' context is the 3-4-target cleave APL; the real >=5-target list (default_aoe) is never emitted (Data/SimcRotations.lua:509)
TIERS caps at k=3; at k=3 the APL routes to default_cleave (active_enemies>2&<5), and default_aoe (>=5) is unreachable by any tier, so at 5+ targets in-game the 'aoe' context serves cleave ordering (e.g. missing default_aoe's early touch_of_death/whirling_dragon_punch arrangement). Inherent ceiling of the 3-tier model; orders are similar enough to be cosmetic.

*Evidence:* gen_simc_rotations.py:34 TIERS k=3 max; tools/simc-apl/monk_windwalker.simc:44-46; Data/SimcRotations.lua:509-530 aoe list matches hand-flattened default_cleave at k=3.

*Fix:* None needed unless 5+-target fidelity matters; could add a k=5 tier mapped onto the aoe context.

### [MINOR] WW chi_burst id 123986 may not be the id AC suggests (alternate castable 'Chi Burst' 461404 exists) (Data/SimcRotations.lua:507)
Two 'Chi Burst' records exist (123986 talent/cast, 461404 free-cast variant). All addon tables know only 123986 (SpellCooldowns 30s). If the WW proc flow casts 461404, the entry never matches and chi_burst stays unranked - low confidence, listed for the synthesis to cross-check against DRUID-style patterns in other classes.

*Evidence:* SpellName CSV: 123986 and 461404 both 'Chi Burst'; SpellCooldowns.lua:405 [123986]=30000 only; Data/SimcRotations.lua:507,529.

*Fix:* Verify in-game which id AC emits for WW; curate if 461404.


## PALADIN_2

### [MAJOR] PALADIN_2 st: Divine Toll ranked 2 at single target although the source restricts that line to 3+ targets; per-action spell_targets conditions are silently dropped and no aoe list is emitted (Data/SimcRotations.lua:535)
classify_atom returns (None, False) for spell_targets/active_enemies atoms with the comment 'handled by the tier split', but flatten() only applies the target-count tier (call_applies) to call_action_list/run_action_list conditions - a target-count condition on a plain action is discarded entirely (no gate, no delegation, no tier exclusion). So cooldowns-list divine_toll,if=spell_targets.shield_of_the_righteous>=3 (paladin_protection.simc line 30) lands at rank 2 in EVERY tier, and because no atom differs between k=1/2/3 the st and aoe flattenings come out identical, so only one st list is emitted and ST inherits the AoE-intent placement. Source ST intent: divine_toll at standard-list line 58, BELOW hammer_of_wrath (line 57). Visible: prot at 1 target in simc mode shows Divine Toll in slot 2 whenever it is off cooldown (60s cd - common). Same mechanism erases the avengers_shield 3+-target line and judgment line 46.

*Evidence:* Data/SimcRotations.lua:535 {id=375576,gates={}} rank 2 of 14, only an st key exists for PALADIN_2 (lines 532-548); tools/simc-apl/paladin_protection.simc lines 30 vs 57-58; tools/gen_simc_rotations.py lines 122-123 (spell_targets -> None,False) and 187-198 (call_applies used only for calls, make_entry never sees k).

*Fix:* In make_entry/flatten, evaluate call_applies(mods.get('if')) for plain actions too and skip the entry at tiers where its target-count conjunct fails (falling through to the next reach of the same token), so st gets the line-58 rank and aoe gets the line-30 rank.

### [MAJOR] PALADIN_2 st: Eye of Tyr ranked 5 unconditionally - the talent.lights_guidance gate names a DIFFERENT spell, so IsPlayerSpell on the entry cannot enforce it; Lightsmith builds see a bottom-of-list ability in the top 3 refined slots (Data/SimcRotations.lua:538)
classify_atom drops talent./hero_tree. atoms as build gates on the assumption that IsPlayerSpell(entry.id) sorts them at runtime (gen_simc_rotations.py lines 124-125). That only holds when the talent gates the action's own spell. eye_of_tyr is castable by both prot hero trees; the APL uses it at rank ~5 ONLY for Templar (talent.lights_guidance, paladin_protection.simc line 39) and otherwise at the bottom (lines 66/72, gated !talent.lights_deliverance). Generated: one unconditional entry at rank 5. A Lightsmith prot in simc mode gets Eye of Tyr promoted near the front whenever it is ready, contradicting the source order for that build.

*Evidence:* Data/SimcRotations.lua:538 {id=209202,gates={}} rank 5; paladin_protection.simc lines 39, 66, 72; gen_simc_rotations.py classify_atom lines 124-125.

*Fix:* When a talent/hero_tree atom references a token different from the action's own token, either delegate the entry or emit a build-conditional variant (e.g. keep the LOWEST-priority reach's rank when the gating talent spell is not known via IsPlayerSpell at runtime).

### [MAJOR] PALADIN_2 st: Hammer of Wrath ranked dead-last among actives (13/14) while conditional early reaches hoist Judgment(4)/Blessed Hammer(8)/fillers above it, inverting the source where unconditional HoW (line 57) outranks the unconditional filler block (lines 61-70) (Data/SimcRotations.lua:546)
First-reach-wins dedup assigns each token the rank of its FIRST textual appearance even when that appearance is heavily conditional (and the condition is then delegated or dropped): judgment gets rank 4 from the charges>=2 line (37, delegated), blessed_hammer gets rank 8 from a set_bonus+talent-only line (50, conditions dropped as build gates -> unconditional), SotR rank 6, etc. Unconditional hammer_of_wrath (line 57) therefore flattens to rank 13, below every filler, although in the source it sits above unconditional judgment (61), avengers_shield (65), blessed_hammer (68), hammer_of_the_righteous (69) and crusader_strike (70). Visible in simc mode: when HoW lights up (execute / Avenging Wrath window) it is ranked at the very back of the normal bucket instead of near the front. Partially mitigated only if Blizzard's native proc overlay fires for HoW (proc bucket bypasses rank order origin, but proccedRank still uses rank 13 within the bucket).

*Evidence:* Data/SimcRotations.lua:537 (judgment rank 4, delegated), 541 (blessed_hammer rank 8, gates={}), 546 (hammer_of_wrath rank 13); paladin_protection.simc lines 37, 50, 57, 61-70; gen_simc_rotations.py flatten() lines 187-198 (seen-set dedup).

*Fix:* For a token whose first reach carries delegated/dropped conditions but which ALSO appears later unconditionally, take the unconditional reach's rank (or the min rank among reaches whose conditions the runtime can actually evaluate).

### [MINOR] PALADIN_2 st: avengers_shield carries a bulwark_of_righteous_fury neg-buff gate lifted from a 3+-targets-only line into the single-target context (Data/SimcRotations.lua:542)
Gate {t='buff',id=386653,neg=true} comes from paladin_protection.simc line 51 (spell_targets>=3&talent.bulwark_of_righteous_fury); the correct ST first reach is line 65 (talent-only -> gates={}). Currently cosmetic because SpellQueue ignores neg buff gates (SimcBuffWindowActive checks positives only) - but it is wrong recorded data that will misbehave if a future gate layer starts honoring neg gates, and /jac inspect gates already displays it as the ST condition.

*Evidence:* Data/SimcRotations.lua:542; paladin_protection.simc lines 51, 65, 75; SpellQueue.lua:449 (not g.neg).

*Fix:* Covered by the per-action target-count fix (finding 2): with tier-aware action filtering the ST reach becomes line 65 and the gate disappears from st.

### [MINOR] PALADIN_2: word_of_glory loses its buff.shining_light_free proc-window gate (unresolved buff -> delegated), so the Shining Light free-WoG window never promotes via the SimC layer (Data/SimcRotations.lua:547)
Both WoG lines in the source (paladin_protection.simc 71, 73) are gated on buff.shining_light_free.up; the resolver could not map the buff token (it is an aura, not a castable), so classify_atom fell to delegate and the emitted entry has gates={}. The SimC buff-window promotion therefore never lifts WoG during the free proc. Mitigated: Blizzard's native proc overlay typically glows WoG on Shining Light, and IsSpellProcced feeds the same proc bucket, so the visible loss is small. Also note the entry id 315921 is itself non-canonical (see critical finding; canonical 85673 per SpellCategories.lua:211).

*Evidence:* Data/SimcRotations.lua:547 {id=315921,gates={},delegated=true}; paladin_protection.simc lines 71, 73; classify_atom lines 112-117 (unknown buff -> delegate).

*Fix:* Same fix as finding 5: resolve buff tokens against an aura universe (Shining Light free = aura 327510) so the gate survives.


## PALADIN_3

### [MAJOR] PALADIN_3 st: Hammer of Wrath permanently carries the Herald-only blessing_of_anshe buff gate (id 445200, likely the talent id not the player-aura id) from its first conditional reach; its unconditional lines are lost to dedup (Data/SimcRotations.lua:563)
hammer_of_wrath first reach is generators line 53 (buff.blessing_of_anshe.up, Herald of the Sun) -> gate {t='buff',id=445200} plus delegated. The unconditional reaches (lines 58 and 61) are dropped by first-reach dedup. Runtime effect: the only thing SpellQueue does with positive buff gates is promote to the proc bucket via BlizzardAPI.IsBuffWindowActive(g.id), which calls C_UnitAuras.GetPlayerAuraBySpellID(445200) - if 445200 is the Herald talent-definition id rather than the aura the player actually gains, the promotion NEVER fires, silently, for everyone; for non-Herald builds the buff cannot exist at all. So the APL's 'HoW on An'she proc' intent is lost while HoW keeps only its buried rank 12. Compounded by the id-1241288 mismatch (see critical finding).

*Evidence:* Data/SimcRotations.lua:563 {id=1241288,gates={{t="buff",id=445200}},delegated=true} rank 12; paladin_retribution.simc lines 53, 58, 61; SpellQueue.lua:445-455 (SimcBuffWindowActive positive-only), BlizzardAPI/CooldownTracking.lua:523-532 (GetPlayerAuraBySpellID requires the aura id); 445200 appears in no other Data table.

*Fix:* Resolve buff.X tokens against a player-aura source (SelfAuras universe) instead of the castable-spell universe, and validate each emitted buff-gate id with /jac inspect gates in-game; drop gates inherited from a hero-tree-conditional first reach when a later unconditional reach exists.

### [MINOR] PALADIN_3: blade_of_justice dot gate uses the Expurgation debuff id with the negation dropped, and TargetDots keys Expurgation by debuff id instead of the BoJ cast id, so Expurgation maintenance can never track (Data/SimcRotations.lua:560)
Gate {t='dot',id=383344} derives from !dot.expurgation.ticking (paladin_retribution.simc line 47): classify_atom computes neg but only applies it to buff/execute gates, never dot gates (gen_simc_rotations.py lines 108-110), so the polarity is lost in the data. Runtime-inert today (SpellQueue evaluates no dot gates; the dot sink keys DotTracker.IsDotActiveOnCurrentTarget by the CAST/display id, SpellQueue.lua:539-540). Related dead data: Data/TargetDots.lua:74 [383344]=9 'Expurgation' is a debuff-aura id in a table documented as 'applicator cast spells' - Expurgation is applied by casting Blade of Justice 184575, which is absent from TargetDots, so the entry can never match a cast and BoJ never sinks while Expurgation runs (mirror of the Sunfire 164815-vs-93402 defect). Also BoJ inherits rank 9 above judgment rank 13 from its talent.holy_flames-conditional first reach; the source's unconditional order is judgment (55) before blade_of_justice (56).

*Evidence:* Data/SimcRotations.lua:560; Data/TargetDots.lua:74 vs header lines 3-10; paladin_retribution.simc lines 47, 55-56; gen_simc_rotations.py lines 103-110.

*Fix:* gen_target_dots.py should key Expurgation by its applicator cast (184575) or drop it; gen_simc_rotations should record neg on dot gates so a future gate layer keeps the polarity.

### [MINOR] PALADIN_3 st: rank 1 is Rebuke - interrupts are not in the generator SKIP set (Data/SimcRotations.lua:552)
actions+=/rebuke (paladin_retribution.simc line 19) flattens to the top-ranked entry. JustAC handles interrupts through the dedicated InterruptAbilities cue, and AC's rotation feed is unlikely to contain Rebuke, so this is probably dead data - but if Rebuke ever appears in the rotation list it would occupy slot 2 permanently in simc mode. Same pattern: kick rank 2 in ROGUE_1 (Data/SimcRotations.lua:602). mind_freeze appears in DK lists too (line 37).

*Evidence:* Data/SimcRotations.lua:552 {id=96231,gates={}}; SKIP set in gen_simc_rotations.py lines 37-47 contains racials/flow control but no interrupt tokens.

*Fix:* Add interrupt tokens (rebuke, kick, mind_freeze, counterspell, wind_shear, spear_hand_strike, ...) to SKIP, or filter ids present in Data/InterruptAbilities.lua at emit time.

### [MINOR] Generic {t="cd"} gates discard WHICH cooldown the source condition referenced (execution_sentence gated by wake_of_ashes' cooldown, blade_of_justice by divine_toll's) (Data/SimcRotations.lua:554)
classify_atom maps every cooldown.X.(ready|up|remains) atom to bare {t='cd'} with no id (gen_simc_rotations.py lines 106-107). execution_sentence's gate actually encodes cooldown.wake_of_ashes.remains<gcd (sync condition, line 33 of the APL) and blade_of_justice's second gate encodes cooldown.divine_toll.remains. Runtime-inert today (no queue path evaluates cd gates; /jac inspect gates displays them as if they were own-cooldown checks, which is misleading for these two). Dead/incorrect data rather than a queue defect.

*Evidence:* Data/SimcRotations.lua:554, 560; paladin_retribution.simc lines 33, 47; gen_simc_rotations.py lines 106-107; DebugCommands.lua:1572-1574 renders {t='cd'} as the entry's own cooldown.

*Fix:* Emit {t='cd', id=<resolved token>} and have the inspector/gate layer probe that spell's cooldown; or delegate when the referenced cooldown is a different spell.

### [MINOR] call_applies treats target-count comparisons inside OR-branches of a call condition as conjuncts - finishers call skipped at k<4 despite holy_power>=4 alternative (latent for ret, systemic risk) (tools/gen_simc_rotations.py:145)
call_applies regex-scans the whole condition for target-count comparisons and requires ALL to hold at k, ignoring boolean structure. paladin_retribution.simc line 50: call_action_list,name=finishers,if=holy_power>=4|buff.crusade.up&...|spell_targets.divine_storm>=4 - at k=1..3 the >=4 comparison fails so the call is dropped, even though holy_power>=4 alone should reach finishers at any target count. No visible paladin impact ONLY because the earlier unconditional-at-all-k finishers call (line 45) already ranked those entries; any spec whose sole reach of a sublist has a target-count term inside an OR will silently lose the whole sublist at some tiers.

*Evidence:* gen_simc_rotations.py lines 142-152; paladin_retribution.simc lines 45 and 50.

*Fix:* Only apply call_applies when the target-count comparison is a top-level conjunct (reuse split_and and test atoms, skipping atoms containing '|').


## PRIEST_3

### [CRITICAL] Core spender Devouring Plague is entirely absent from PRIEST_3 (unresolved token) and sinks to rank 900 below fillers in simc mode (Data/SimcRotations.lua:568)
devouring_plague appears at high priority in the source APL (main list lines 83, 87, 101 of tools/simc-apl/priest_shadow.simc) but has NO entry in the PRIEST_3 st or aoe blocks. It is not in the generator's SKIP set, so it must be unresolved bridge residue (make_entry returns None, gen_simc_rotations.py:159-162, and unresolved tokens are only reported, never fatal). At runtime in simc mode, rankOf() gives unranked spells rank 900 (SpellQueue.lua:468-470, comment at 463-465: 'spells not in the SimC list sinking below the ranked ones'), so Devouring Plague sorts BELOW mind_flay (rank 10) and shadow_word_pain (rank 11) in the normal bucket whenever both are ready - the main insanity spender displayed after channel/dot fillers in the most common single-target situation. This is the same defect class as the reported Balance Druid issue.

*Evidence:* PRIEST_3 st list = mindbender/swd/void_blast/void_bolt/void_torrent/vampiric_touch/mind_blast/halo/holy_nova/mind_flay/shadow_word_pain only (Data/SimcRotations.lua:569-581); no id 335467/369128 anywhere in the block; APL ranks devouring_plague above void_torrent, mind_blast, mind_flay (priest_shadow.simc:83,87,101). Data/SpellArchetypes.lua:2176 shows Devouring Plague exists in the id universe as 369128.

*Fix:* Add devouring_plague to CURATED["PRIEST_3"] in tools/gen_simc_rotations.py with the canonical Shadow cast id and regenerate; more generally, make the coverage report fail (or at least warn loudly per-spec) when an APL token that appears in the top half of a flattened list is unresolved.

### [MAJOR] Six more rotational tokens unresolved and unranked: shadow_crash, void_eruption, dark_ascension, mind_flay_insanity, void_volley, divine_star (Data/SimcRotations.lua:582)
All six appear as castable actions in priest_shadow.simc (shadow_crash lines 33/95/105/111; void_eruption line 60; dark_ascension line 62; mind_flay_insanity line 93; void_volley lines 91/100; divine_star lines 70/109) and none are in SKIP, yet none appear in the PRIEST_3 block - unresolved residue. In simc mode each ranks 900. Shadow Crash is the AoE Vampiric Touch applicator (the APL's rank-2 aoe action) sinking below every ranked filler in aoe; Void Eruption/Dark Ascension are the primary burst cooldowns; Mind Flay: Insanity is a proc-priority action the APL places above shadow_crash/vampiric_touch/mind_blast, but if AC suggests the override id and ResolveSpellID maps it back to base Mind Flay 15407 it would inherit rank 10 (bottom filler) instead - a visible proc mis-order under Voidweaver/MFI talents.

*Evidence:* No entry for any of these tokens in Data/SimcRotations.lua:568-598. Shadow Crash exists in the universe as 361987 (Data/SpellArchetypes.lua:446); Dark Ascension as 391109 (Data/SpellCooldowns.lua:926); Divine Star as 122121/110744 (Data/SpellArchetypes.lua:2762, Data/SpellCategories.lua:242).

*Fix:* Curate these tokens in CURATED["PRIEST_3"] (tools/gen_simc_rotations.py:53) and regenerate.

### [MAJOR] call_applies treats a target-count atom inside an OR as a required conjunct: entire cds list dropped from st/cleave but included in aoe (tools/gen_simc_rotations.py:142)
call_applies() regex-scans the whole call condition for target-count comparisons and requires ALL of them to hold, ignoring boolean structure (gen_simc_rotations.py:142-152). The cds call (priest_shadow.simc:75) is 'if=fight_remains<30|target.time_to_die>15&(!variable.holding_crash|active_enemies>2)' - active_enemies>2 sits inside an OR alternative, so in the real APL cds runs at ALL target counts. The generator drops the cds walk at k=1/k=2 and includes it at k=3. Two visible consequences: (a) st/cleave lose power_infusion, halo(cds), desperate_prayer, flash_heal rankings entirely (they fall to rank 900 in st); (b) the aoe list ranks flash_heal=2, power_infusion=3, halo=4, desperate_prayer=5 ABOVE mindbender/void_blast/void_bolt/mind_blast (Data/SimcRotations.lua:584-587) - conditional utility casts (trinket-proc fishing at line 54, health<=75% at line 65) outrank core damage in the 3+ target queue whenever AC's fixed queue contains them. This contradicts the flattener's own stated intent that non-target-count clauses collapse in.

*Evidence:* Generated st (Data/SimcRotations.lua:569-581) has no flash_heal/power_infusion/desperate_prayer; generated aoe (583-597) has them at ranks 2/3/5. Source cds list priest_shadow.simc:44-65 is called from main line 75 with the target-count atom under an OR.

*Fix:* In call_applies, only honor target-count comparisons that are top-level conjuncts (reuse split_and and skip atoms containing '|' or parens), delegating/collapsing anything structurally ambiguous - i.e., include the call at all tiers when the target-count atom is not a required conjunct.

### [MAJOR] mindbender id 1230339 contradicts Data/SpellCooldowns.lua Mindbender=123040 (same-token-different-id, the moonfire 8921-vs-326646 pattern) (Data/SimcRotations.lua:570)
PRIEST_3 ranks mindbender #1 in st under id 1230339, but Data/SpellCooldowns.lua:403 maps Mindbender to 123040. No other Data table contains 1230339. If AC suggests Mindbender under 123040 (or the Shadow-specific 200174), RotationImport.GetEntry misses both the direct id and baseID (BuildLookup only indexes 1230339 and its base, RotationImport.lua:102-109), so the #1-ranked entry never matches and mindbender floats unranked (900). Conversely if 1230339 is the correct Midnight-era cast id, SpellCooldowns' 123040 is stale and the cooldown machinery uses the wrong key. Exactly one of the two tables can be right.

*Evidence:* Data/SimcRotations.lua:570 '{id=1230339,...} -- mindbender' (st rank 1) and :588 (aoe rank 6); Data/SpellCooldowns.lua:403 '[123040]=60000, -- Mindbender'. Grep for 1230339 across Data/ hits only SimcRotations.

*Fix:* Determine the live cast id (/jac inspect on a Shadow Priest with Mindbender talented) and align both tables; add a cross-table consistency check to the generator comparing SimcRotations ids for tokens that also appear by name in SpellCooldowns/TargetDots.

### [MAJOR] void_blast id 450405 matches no other Data table; SpellArchetypes has Void Blast as 450215 and 450983 (three ids for one token) (Data/SimcRotations.lua:572)
PRIEST_3 ranks void_blast #3 st under 450405, an id present nowhere else in the repo, while Data/SpellArchetypes.lua carries Void Blast as 450215 (line 2443) and 450983 (lines 2453, 3082). Void Blast is the Voidweaver override of Mind Blast; if AC suggests the castable id (450983) the lookup misses 450405, and if FindBaseSpellByID resolves the override chain down to Mind Blast 8092, GetEntry (RotationImport.lua:146) would return the mind_blast record (rank 7) instead of void_blast (rank 3) - a silent rank downgrade of the highest-priority Voidweaver nuke. The bridge's min-id collision rule (simc_bridge.py:197-201) picking a trait-definition id over the castable id is the likely cause.

*Evidence:* Data/SimcRotations.lua:572,590 '{id=450405,...} -- void_blast'; Data/SpellArchetypes.lua:2443 '[450215] = "ranged", -- Void Blast', :2453/:3082 '[450983] ... Void Blast'. 450405 absent from every other Data table.

*Fix:* Verify the AC-suggested id in-game and curate void_blast in CURATED["PRIEST_3"].

### [MAJOR] void_bolt id 228266 matches no other Data table; SpellArchetypes uses 205448/343355/1264177 for Void Bolt (Data/SimcRotations.lua:573)
228266 (the Void Eruption action-bar override form) appears only in SimcRotations; the archetype tables key Void Bolt as 205448 (Data/SpellArchetypes.lua:1737, 2846) plus 343355/1264177 variants. If AC's rotation list carries 205448, GetEntry misses (205448 is its own base), leaving Void Bolt - the core Voidform button ranked #4 st - unranked at 900 during every Voidform window. If AC carries 228266 the lookup works and the archetype tables are the stale ones. Cross-table disagreement either way; which side is wrong is not determinable offline.

*Evidence:* Data/SimcRotations.lua:573,591 '{id=228266,gates={{t="cd"}},delegated=true} -- void_bolt'; Data/SpellArchetypes.lua:1737/2846 use 205448. 228266 absent from all other Data tables.

*Fix:* Confirm the AC-suggested id in a Voidform window and align; consider indexing BOTH override and base ids in BuildLookup for entries whose token is a known override (it already adds baseID, but 205448 is not on 228266's base chain).

### [MAJOR] call-site if= conditions are discarded when flattening called lists: heal_for_tof's Twist-of-Fate condition lost, halo emitted unconditional and NOT delegated at st rank 8 (tools/gen_simc_rotations.py:188)
flatten() only consults a call's condition via call_applies (target-count atoms); the rest of the call-site if= is neither converted to gates nor propagated as delegated on the walked entries (gen_simc_rotations.py:188-196). priest_shadow.simc:104 calls heal_for_tof with 'if=!buff.twist_of_fate.up&buff.twist_of_fate_can_trigger_on_ally_heal.up&(talent...)'; the list's halo entry (line 68) has no own if=, so it emits as {id=120517,gates={}} with delegated absent (Data/SimcRotations.lua:577) - a fully-confident, ungated rank-8 st action, though the source intent is 'only to fish a Twist of Fate proc via ally healing'. Delegated-sanity violation per the audit's item 4: an entry whose effective source condition contains unreadable buff state is unmarked. Runtime impact for priest is modest (halo never starve-sinks and always outranks mind_flay/SWP), but the mechanism is systemic across all specs.

*Evidence:* Data/SimcRotations.lua:577 '{id=120517,gates={}}, -- halo' (no delegated flag); source condition at priest_shadow.simc:104; contrast holy_nova which got delegated=true only because it happens to carry its own if= (line 72 -> Data/SimcRotations.lua:578).

*Fix:* In walk(), classify the call-site if= once (classify_if) and OR its delegated flag / append its gates onto every entry emitted from the called list.

### [MINOR] target.time_to_die>12 on vampiric_touch mis-classified as an execute gate (semantically inverted); currently dead data (Data/SimcRotations.lua:575)
classify_atom maps ANY target.health.pct/target.time_to_die comparison to {t="execute"} regardless of direction (gen_simc_rotations.py:120-121). VT's condition 'target.time_to_die>12' (priest_shadow.simc:97) means 'target will LIVE long enough to be worth dotting' - the opposite of execute range - yet the st entry carries {t="execute"}. No runtime consumer evaluates execute gates today (SpellQueue only reads buff gates via SimcBuffWindowActive, SpellQueue.lua:445-455; cd/dot/execute gates surface only in /jac inspect, DebugCommands.lua:1572-1592), so this is dead-but-misleading data - and a landmine for any future execute-gate consumer, plus wrong /jac inspect diagnostics. Systemic: every spec's 'time_to_die>N' dot-worthiness condition gets the same inverted tag.

*Evidence:* Data/SimcRotations.lua:575 '{id=34914,gates={{t="dot",id=34914},{t="execute"}},delegated=true} -- vampiric_touch' vs source 'target.time_to_die>12' at priest_shadow.simc:97.

*Fix:* Only classify as execute when the comparison direction implies low health / short remaining life (target.health.pct< N, target.time_to_die< N); delegate the '>' direction.

### [MINOR] shadow_word_pain own-dot refresh intent (target_if=min:remains) not recognized - entry emitted with gates={} (Data/SimcRotations.lua:580)
The tif regex in make_entry only matches refreshable/ticking or an explicit 'dot.<token>.' reference (gen_simc_rotations.py:164-166); 'target_if=min:remains' (priest_shadow.simc:117) - SimC's own-dot lowest-remaining refresh selector - matches neither, so SWP gets no dot gate. Superficially the DRUID_1 sunfire gates={} pattern, but here impact is nil: SWP is the APL's genuine bottom filler (rank 11, matching source order), and the runtime dot-sink keys off Data/TargetDots.lua:18 ([589]=16) via DotTracker independent of simc gates, so an already-ticking SWP still sinks. Cosmetic/dead-data only; distinguishes PRIEST_3 from the Druid case.

*Evidence:* Data/SimcRotations.lua:580 '{id=589,gates={}}' vs priest_shadow.simc:117 'shadow_word_pain,target_if=min:remains'; Data/TargetDots.lua:18 covers the runtime sink.

*Fix:* Extend the target_if regex to treat a bare 'remains' selector as an own-dot gate if gate fidelity for inspect output matters; otherwise leave.


## ROGUE_1

### [CRITICAL] Shiv is proc-promoted to a top queue slot whenever the Envenom buff is up (near-constantly), via a gate salvaged from a narrow Kingsbane-sync branch (Data/SimcRotations.lua:604)
Generated st/aoe shiv (rank 4) = {gates={{t=dot,id=385627(kingsbane)},{t=buff,id=32645(envenom)}},delegated}. It came from the STEALTHED list (rogue_assassination.simc:166: shiv,if=talent.kingsbane&dot.kingsbane.ticking&dot.kingsbane.remains<8&(!shiv.up...)&buff.envenom.up) because flatten() walks 'call_action_list,name=stealthed' (line 42) before cds, and first-reach dedup then drops the entire mainline actions.shiv list (lines 141-159). At runtime only POSITIVE buff gates are live (SpellQueue.lua:445-455 SimcBuffWindowActive -> proc-bucket promotion); the kingsbane dot gate is dead (never evaluated). Result: every time the player's Envenom buff (32645, up after nearly every finisher) is active and Shiv is off cd, Shiv jumps into the proc bucket ahead of the whole normal bucket - in simc mode, for ALL builds including non-Kingsbane ones. Visibly wrong queue order in routine ST play.

*Evidence:* Data/SimcRotations.lua:604/619 '{id=5938,gates={{t="dot",id=385627},{t="buff",id=32645}},delegated=true},  -- shiv'; SpellQueue.lua:449-451 promotes on any positive buff gate whose aura is up; BlizzardAPI/CooldownTracking.lua:523-532 probes GetPlayerAuraBySpellID(32645).

*Fix:* In gen_simc_rotations.py, do not let a stealth-list reach shadow the unstealthed lists (skip lists whose call condition is stealth-only, or dedup keeping the entry with the FEWEST gates); at minimum strip positive buff gates from entries whose source condition also required a (dropped) dot/talent clause.

### [MAJOR] Envenom entry is the stealthed-subterfuge special case: main-spender entry dedup-dropped, Envenom ranked above Rupture/Garrote maintenance, and carries a bogus kingsbane dot gate (Data/SimcRotations.lua:605)
Envenom rank 5 = stealthed-list line 168 (subterfuge maintenance: ...&dot.kingsbane.ticking&buff.envenom.remains<=3...), reached before actions.direct line 101 (the real main spender). Order consequence: envenom(5) > rupture(6) > garrote(7), inverting the source main-path order core_dot (garrote line 90, rupture line 92) BEFORE direct/envenom (line 101). When Garrote/Rupture un-sink inside their pandemic windows (DotTracker), the ready Envenom still outranks the dot refreshes in every ST cycle. The {t=dot,id=385627} gate is runtime-dead so it does no harm today but is semantically wrong for the generic spender.

*Evidence:* Data/SimcRotations.lua:605-607 envenom rank5/rupture rank6/garrote rank7; rogue_assassination.simc:46-50 core_dot called before direct; stealthed list flattened first via line 42 call with non-target-count condition.

*Fix:* Same root fix as the shiv finding (do not flatten stealth-only lists ahead of the main path / prefer least-gated duplicate on dedup).

### [MAJOR] Garrote lost its refreshable/dot gate entirely (druid-sunfire pattern) and instead carries a misclassified {t=execute} gate from target.time_to_die (Data/SimcRotations.lua:607)
The retained garrote entry is the stealthed improved-garrote cast (rogue_assassination.simc:174): its refreshable clauses sit inside parens/target_if where the generator can't see them, so gates carry no {t=dot}. The maintenance garrote entries with bare 'refreshable' (core_dot:90, aoe_dot:62) were dedup-dropped. Additionally classify_atom (gen_simc_rotations.py:120-121) maps 'target.time_to_die-remains>2' to {t=execute}: time_to_die is a fight-length guard ('target lives long enough to be worth dotting'), the OPPOSITE of an execute condition - if execute gates ever become runtime-live, garrote would be gated to low-health targets, backwards. Today both gates are runtime-dead and the DoT sink is rescued by TargetDots[703]+DotTracker, so impact is latent data-wrongness plus the loss of the intended refresh gate.

*Evidence:* Data/SimcRotations.lua:607/622 '{id=703,gates={{t="execute"}},delegated=true}'; gen_simc_rotations.py:120-121 classifies target.time_to_die as execute; same misclassification visible in PRIEST vampiric_touch (Data/SimcRotations.lua:575).

*Fix:* Classify only target.health.pct atoms as execute; treat target.time_to_die as delegate. On dedup, merge dot gates from dropped duplicates of the same spell.

### [MAJOR] AoE: Mutilate ranked above Fan of Knives - the niche caustic-filler mutilate shadows the generic builders (Data/SimcRotations.lua:628)
actions.direct puts the caustic_spatter filler mutilate first (rogue_assassination.simc:98), so first-reach dedup pins mutilate at rank 13 (aoe) and drops the generic fallback mutilate (line 117); fan_of_knives first resolves at line 106 => rank 14. In the aoe context (3+ targets), the queue ranks single-target Mutilate above Fan of Knives, the primary AoE builder - inverted vs the source, where the generic FoK (line 111) sits above the generic mutilate (117). The retained FoK gate {t=buff,id=1248793 clear_the_witnesses} additionally proc-promotes FoK only for Deathstalker builds; other builds see the inverted order permanently.

*Evidence:* Data/SimcRotations.lua:628-629 mutilate rank13, fan_of_knives rank14 (aoe list); rogue_assassination.simc:98 vs 106/111/117.

*Fix:* On dedup, keep the position of the first UNCONDITIONAL (or least-gated) duplicate rather than the first reach, or at least the last unconditional occurrence's position for fillers.

### [MINOR] call_applies ANDs target-count comparisons found anywhere in a call's OR expression - st tier wrongly loses the vanish list (tools/gen_simc_rotations.py:143)
rogue_assassination.simc:85 'call vanish,if=!stealthed.all&master_assassin_remains=0 | talent...&spell_targets.fan_of_knives>=3': the >=3 belongs only to the second disjunct, but call_applies regex-scans the whole condition and requires it at k=1, so the vanish list is excluded from st (present only in aoe, Data/SimcRotations.lua:626). Gameplay impact small (vanish delegated, ranking dubious anyway) but the mechanism can silently drop whole lists from tiers in any spec.

*Evidence:* gen_simc_rotations.py:143-152; ROGUE_1 st (600-614) lacks 1856 while aoe (615-630) has it.

*Fix:* Evaluate target-count gates per OR-disjunct: the call applies at k if ANY disjunct's target-count atoms hold.

### [MINOR] stealth (rank 1) and kick (rank 2) emitted as rotation entries in ROGUE_1/ROGUE_2 - SKIP list omits them (Data/SimcRotations.lua:601)
SKIP (gen_simc_rotations.py:37-47) excludes prowl/shadowmeld but not 'stealth' or 'kick', so both rogue APL preamble actions rank 1-2 in ROGUE_1 and ROGUE_2. Likely dead data (AC's rotation list presumably excludes Stealth in combat and interrupts; unusable spells sink via readiness checks), but if AC ever surfaces Kick it would pin near the queue top whenever ready.

*Evidence:* Data/SimcRotations.lua:601-602,634-635; SKIP set lacks stealth/kick.

*Fix:* Add stealth and kick (interrupts generally) to SKIP.

### [MINOR] Crimson Tempest (1247227) absent from Data/TargetDots.lua - its bleed never dot-sinks (Data/TargetDots.lua:14)
SimcRotations and SpellArchetypes agree on 1247227 for Crimson Tempest (so no cross-id mismatch), but TargetDots has no CT entry under either 1247227 or 121411, so DotTracker never sinks CT while its bleed is live; the {t=dot,id=1247227} gate is runtime-dead like all dot gates. AoE-context, delegated entry - cosmetic-to-minor.

*Evidence:* Data/TargetDots.lua full read: no crimson tempest; Data/SpellArchetypes.lua:676,3126 use 1247227.

*Fix:* Check gen_target_dots.py coverage for CT (aoe-applied bleed may be missed by the applicator heuristic) and curate if intended.

### [MINOR] Delegation is never derived from target_if conditions - rupture entry undelegated despite unreadable CP conditions (tools/gen_simc_rotations.py:163)
make_entry classifies only mods['if']; target_if content is scanned solely for refreshable/ticking. The retained ROGUE_1 rupture (stealthed list line 172) has ALL its conditions (effective_combo_points>=spend, indiscriminate_carnage, regen/scent saturation) in target_if, so the entry emits gates={{t=dot,id=1943}} with NO delegated flag (Data/SimcRotations.lua:606/621). Harmless today (starvation sink reads energy, not CP, and 0-CP rupture is unusable anyway) but the delegated marker is semantically wrong. Same pattern for ROGUE_2 finish-list entries (killing_spree 642, coup_de_grace 643, dispatch 645): the run_action_list call's variable.finish_condition is dropped without delegation - mitigated by usability sinking at 0 CP.

*Evidence:* gen_simc_rotations.py:156-175; Data/SimcRotations.lua:606,642-645.

*Fix:* Run classify_if over target_if (after stripping the sort prefix) and OR the delegated flags; propagate a delegated flag from unreadable call-site conditions.


## ROGUE_2

### [MAJOR] Vanish is proc-promoted whenever Adrenaline Rush is active (high uptime), from a lost 'AR about to expire' condition; its {t=cd} gate is id-less and inverted (Data/SimcRotations.lua:641)
Generated vanish (rank 8) gates={{t=buff,id=13750},{t=cd}}. Source (rogue_outlaw.simc:76) requires buff.adrenaline_rush.remains<2 & cooldown.adrenaline_rush.remains>30 (extend AR via Subterfuge); the remains atoms delegate, leaving a bare positive 'AR is up' gate. At runtime the positive buff gate promotes Vanish into the proc bucket whenever the AR buff (id 13750, confirmed in SelfAuras:68) is active and Vanish is ready - AR uptime is high for outlaw, so Vanish is prominently suggested through most of AR instead of only in its last 2s. Caveat: only visible if AC's rotation list includes Vanish. Secondary defect: classify_atom emits {t=cd} with NO id (gen_simc_rotations.py:106-107) - here the source atom was a DIFFERENT spell's cooldown (adrenaline_rush) and the sense is 'NOT ready' (remains>30); the gate is runtime-dead but is malformed data (which cd? which polarity?) - same pattern repo-wide (e.g. SHAMAN_1 aoe flame_shock {t=cd}).

*Evidence:* Data/SimcRotations.lua:641; SpellQueue.lua:445-455 (positive buff gates promote, cd gates never evaluated); gen_simc_rotations.py:106-107 returns {"t":"cd"} discarding the cooldown's spell and comparison direction.

*Fix:* Only emit a positive buff gate when the buff atom was the entry's sole condition class; record the cd spell id and polarity or drop cd gates entirely.

### [MAJOR] Blade Flurry ranked 5 in SINGLE TARGET: entry-level spell_targets conditions are silently dropped, and the same flaw erases Outlaw's aoe/cleave contexts entirely (Data/SimcRotations.lua:638)
classify_atom returns (None,False) for spell_targets atoms ('handled by the tier split', gen_simc_rotations.py:122-123), but the tier split (call_applies) only filters CALL sites, never entry-level conditions. rogue_outlaw.simc:68 'blade_flurry,if=spell_targets>=2&buff.blade_flurry.remains<gcd' therefore lands ungated in the st list at rank 5, above killing_spree(9)/dispatch(12)/sinister_strike(16) - the queue ranks the cleave buff near the top while fighting one target. Because ALL of Outlaw's st-vs-aoe distinctions are entry-level, the three tiers flatten identically and the aoe/cleave lists are dropped as duplicates: Outlaw gets zero context differentiation. ROGUE_3 is likewise st-only because Subtlety routes every target-count through 'variable.targets' (rogue_subtlety.simc:21), which neither the tier splitter nor the classifier can see.

*Evidence:* Data/SimcRotations.lua:632-650 (ROGUE_2 has only st); generator report '16/-/-' for outlaw and subtlety; gen_simc_rotations.py:143-152 call_applies used only in flatten()'s call branch (lines 188-191).

*Fix:* Apply call_applies-style target-count evaluation to each ENTRY's if= per tier (drop the entry from tiers where its spell_targets clause fails).

### [MAJOR] roll_the_bones emitted as id 1214909 while the repo's own tables use 315508 - rank lookup can miss and leave RtB unranked (sinks to back) (Data/SimcRotations.lua:640)
The resolver's Outlaw universe contains only 1214909 named 'Roll the Bones' (probe confirmed), but Data/SpellCooldowns.lua:734 and Data/SelfAuras.lua:1004 both key RtB as 315508 - the same-token-different-id pattern as druid moonfire 8921 vs 326646. RotationImport.BuildLookup keys the map by e.id and baseID(e.id) only (RotationImport.lua:104-109); if the live client/AC reports RtB as 315508 and ResolveSpellID does not bridge 315508<->1214909, GetEntry misses and RtB gets rank 900 - Outlaw's core maintenance button sinks below every ranked entry in simc mode. Needs an in-game check of which id AC hands over; flagged because two repo tables already disagree with the generated one.

*Evidence:* Resolver probe: Outlaw 'roll_the_bones -> 1214909 candidates=[1214909]'; Data/SpellCooldowns.lua:734 '[315508]=45000  -- Roll the Bones'; Data/SelfAuras.lua:1004 '[315508]=true'.

*Fix:* Curate roll_the_bones to the id AC actually reports (verify in-game via /jac inspect), or extend the lookup to also key known override/rename chains.

### [MAJOR] ghostly_strike unresolved - for Fatebound/Trickster builds the on-cd talent sinks to rank 900 instead of being ranked (tools/gen_simc_rotations.py:53)
Resolver probe: no 'ghostly_strike' candidate in the Outlaw universe or class fallback; the APL uses it every cooldown (rogue_outlaw.simc:64, top of cds). Missing from Data/SimcRotations.lua ROGUE_2 means rank 900 in simc mode - actively demoted below all ranked entries for builds that talent it (see the residue-not-fail-safe mechanism in the ROGUE_3 finding).

*Evidence:* Generator report residue 'cold_blood ghostly_strike' for rogue_outlaw; probe candidates=[] in all three rogue specs.

*Fix:* Curate ghostly_strike (id 196937 or the current client id) for ROGUE_2.

### [MINOR] Sinister Strike's only entry is the Trickster-conditional one; unconditional fallback dedup-dropped and gate id 441274 is the talent id, buff aura unverified (Data/SimcRotations.lua:649)
actions.build:41 (disorienting_strikes branch) is reached before the unconditional fallback (line 59), so SS rank 16 carries {t=buff,id=441274}. Rank/order happen to match the fallback anyway, and the promotion-on-buff coincidentally matches line 41's intent, so impact is low - but 441274 is the Disorienting Strikes TALENT id; if the aura the player receives has a different id, the promotion is dead. Same cast-id-as-aura-id assumption exists on premeditation (343160) and subterfuge (108208) gates in ROGUE_3 (both neg, runtime-dead).

*Evidence:* Data/SimcRotations.lua:649,655,659; classify_atom uses resolve(token) (cast resolver) for buff ids (gen_simc_rotations.py:112-117).

*Fix:* Cross-check positive buff-gate ids against SelfAuras/client aura data at generation time; warn when a buff-gate id is not a known self-aura.


## ROGUE_3

### [CRITICAL] Subtlety rupture and symbols_of_death fail to resolve, and unresolved spells actively SINK below everything ranked - Rupture maintenance never surfaces (Data/SimcRotations.lua:652)
ROGUE_3 has no rupture (1943) or symbols_of_death entry: the resolver finds NO candidate named 'rupture'/'symbols_of_death' in Subtlety's spec universe or the class-wide fallback (confirmed by probe: candidates=[] for Sub, while Assassination resolves rupture=1943). In simc mode an unranked spell gets rank 900 (SpellQueue.lua:470) and sorts BELOW all 16 ranked entries in the normal bucket - so when Rupture needs (re)applying it sits behind backstab/gloomblade/shadowstrike fillers; Symbols of Death likewise. This is the same visible symptom class as the reported druid issue (maintenance ability buried). Note it also falsifies the generator's fail-safe claim ('isn't ranked and keeps AC's order', gen_simc_rotations.py:22-23): rank-900 does NOT keep AC's order, it demotes.

*Evidence:* Generator report: 'rogue_subtlety ROGUE_3 16/-/- cold_blood rupture symbols_of_death'; resolver probe shows Subtlety universe lacks both tokens; Data/SimcRotations.lua:653-670 lists neither 1943 nor SoD; SpellQueue.lua:468-470 'return (simcRec and simcRec.rank) or 900'.

*Fix:* Add ROGUE_3 CURATED entries {"rupture": 1943, "symbols_of_death": 212283} in gen_simc_rotations.py; separately consider making unranked spells inherit a neutral mid rank instead of 900 so residue is genuinely fail-safe.

### [MAJOR] Black Powder ranked above Eviscerate in single target (Data/SimcRotations.lua:662)
finish list order (black_powder line 77 before eviscerate line 78) is preserved as ranks 9 and 10, but black_powder's targets>=2 conditions live in 'variable.targets' expressions the generator cannot read (delegated only). In Subtlety ST, both finishers are castable at 6+ CP and simc-mode sorts Black Powder (AoE finisher) above Eviscerate (ST finisher) every finisher cycle. Starvation-sink does not help (both affordable at the same time).

*Evidence:* Data/SimcRotations.lua:662-663; rogue_subtlety.simc:77-78 with variable.targets defined at line 21.

*Fix:* Resolve simple variable definitions (targets=spell_targets.X) during parsing so tier splitting and entry filtering see through them.


## SHAMAN_1

### [MAJOR] Entry-level target-count conditions are discarded: 2-target-only lightning_bolt outranks the unconditional chain_lightning filler in the 3+ aoe tier (Data/SimcRotations.lua:709)
classify_atom returns (None,False) for spell_targets/active_enemies atoms on the assumption the tier split handles them, but only call_action_list/run_action_list conditions go through call_applies - entry-level ifs are never tier-checked. Elemental aoe: both source lightning_bolt reaches (lines 58 and 86) require spell_targets.chain_lightning=2, yet LB lands in the k=3 aoe list at rank 14, ABOVE chain_lightning at 15 - so at 3+ enemies the simc-mode queue orders single-target LB ahead of the actual AoE filler CL. Same mechanism in SHAMAN_2 aoe: fire_nova rank 15 comes from a line requiring active_enemies>=4 (source line 110), leaked into the 3-target tier.

*Evidence:* Data/SimcRotations.lua:709-710 (aoe LB rank 14 w/ stormkeeper gate, CL rank 15), 761 (enh aoe fire_nova rank 15); tools/simc-apl/shaman_elemental.simc:58,86 (both LB aoe entries are spell_targets=2-only), 87 (unconditional chain_lightning); shaman_enhancement.simc:110; gen_simc_rotations.py:122-123 (target-count atoms dropped), 144-152 (call_applies only used for call/run entries)

*Fix:* In make_entry/flatten, run call_applies(mods.get('if'), k) on ordinary action entries too and drop entries whose target-count clause fails at tier k.

### [MINOR] Positive buff-window gate ids resolve to the passive/talent spell instead of the proc aura, so the only runtime gate consumer (proc-style promotion) can never fire (Data/SimcRotations.lua:711)
SimcBuffWindowActive -> IsBuffWindowActive(gateId) probes C_UnitAuras.GetPlayerAuraBySpellID(gateId), so the gate id must be the AURA id. The resolver instead returns the castable/talent id from the spec universe. SHAMAN_1 aoe lava_burst gate {t="buff",id=77756} = Lava Surge PASSIVE (spec-granted per SpecializationSpells rows 7075/7077); the proc aura is 77762 -> Lava Surge never promotes Lava Burst (partially redundant: Blizzard's IsSpellProcced overlay still promotes it). Same pattern in SHAMAN_2: aoe frost_shock gate id 334195 (Hailstorm talent; buff is 334196), st frost_shock gates 454009 (Tempest keystone talent - the actual cast 452201 is absent from SkillLineAbility/SpecializationSpells, buff id different again) and 342240 (Ice Strike cast; the Frost Shock-empower buff is 384357), st natures_swiftness gate 454009, aoe lightning_bolt gate 375982 (Primordial Wave cast id; the player buff is the 375986 'Primordial Wave' aura). Neg-gate variants (16166 MotE talent vs buff 260734; 192106 lightning_shield is coincidentally correct) are inert since neg gates are never runtime-evaluated. Counter-examples that ARE correct: stormkeeper 191634 (aura id confirmed by Data/AuraStacks.lua:24) and doom_winds 384352 (cast=self-buff).

*Evidence:* Data/SimcRotations.lua:711,737,738,764,768; BlizzardAPI/CooldownTracking.lua:523-532 (probe requires the player-aura spell id); SpellName CSV: 77756+77762 both 'Lava Surge', 334195+334196 both 'Hailstorm', 342240+384357 both 'Ice Strike', 375982+375986 both 'Primordial Wave'; SpellQueue.lua:445-455 (positive-only consumption)

*Fix:* Teach the bridge a buff-token resolution path that prefers aura-bearing ids (e.g. cross-check SpellAuraOptions/SelfAuras) or curate the handful of proc-aura ids per spec (77762, 334196, 384357, MW-related tempest buff).

### [MINOR] Utility occupies ranks 1-4 of both Elemental contexts: spiritwalkers_grace(1), wind_shear(2), lightning_shield(3), natures_swiftness(4) (Data/SimcRotations.lua:674)
The movement filler (spiritwalkers_grace,moving=1) and the interrupt (wind_shear) are main-list utility lines the SKIP set does not cover (racials/potions are skipped) -> they take the top ranks ahead of the entire damage rotation. wind_shear is emitted ungated and not delegated; lightning_shield's !buff gate (192106 neg) is never runtime-evaluated so it too is effectively unconditional at rank 3. Likely dead data (AC's rotation should not contain them), but any custom-queue/pinned appearance pins them to the first re-ranked slots in simc mode; at minimum they compress every real ability's rank by 4.

*Evidence:* Data/SimcRotations.lua:674-677 and 696-699; tools/simc-apl/shaman_elemental.simc:22 (moving=1 modifier not honored - the 'moving' mod is ignored by make_entry), 24, 39, 40

*Fix:* Add wind_shear and spiritwalkers_grace to SKIP (or skip any entry carrying moving=1), regenerate.

### [MINOR] Elemental st flame_shock loses all dot conditions (DRUID_1-sunfire pattern) - but is fully mitigated at runtime because TargetDots has the correct cast id (Data/SimcRotations.lua:682)
First reach (single_target line 98) gates on active_dot.flame_shock=0, which classify_atom cannot express (active_dot prefix does not match the dot.X regex) -> delegated with no dot gate; the later dot.flame_shock.refreshable reach (line 111, Erupting Lava maintenance) is discarded by first-reach dedup. Generated entry: gates={{t="buff",id=16166,neg=true}} (itself the wrong MotE id, and neg-inert), rank 9 above all spenders/fillers. UNLIKE the Balance Druid sunfire case this does NOT visibly break: SkillLineAbility (line 924) confirms 470411 is the current learned Flame Shock cast id, and Data/TargetDots.lua:89 has [470411]=18, so DotTracker.IsDotActiveOnCurrentTarget sinks Flame Shock while the DoT is live regardless of gates. Same story for the enh entries (dot gates carry 470411, matching). Aoe flame_shock (line 704) similarly lost active_dot=0 and kept only a {t="cd"} gate.

*Evidence:* Data/SimcRotations.lua:682,704; tools/simc-apl/shaman_elemental.simc:98,111; Data/TargetDots.lua:89 [470411]=18; SkillLineAbility CSV row ',43434,924,470411,...'; SpellQueue.lua:539-540 (sink path)

*Fix:* Generator: recognize active_dot.<token>=0 and target_if refreshable as own-dot gates, and merge gates from later duplicate reaches instead of dropping them (would also fix the DRUID_1 sunfire gates={}).

### [MINOR] {t="cd"} gates encode OTHER spells' cooldown conditions with no id and no polarity (Data/SimcRotations.lua:704)
classify_atom maps any cooldown.X.(ready|up|remains) atom to a bare {t="cd"}: aoe flame_shock's gate actually encodes 'cooldown.primordial_wave.remains<gcd' AND 'cooldown.ascendance.remains>10' (two different spells, opposite polarities, deduped into one marker); aoe primordial_wave's {t="cd"} encodes 'cooldown.ascendance.remains>15'; SHAMAN_2 aoe elemental_blast's (line 767) encodes 'cooldown.doom_winds.remains=0'. No runtime consumer evaluates t=cd today (only /jac inspect displays it), so this is dead data - but any future consumer treating it as 'own cd ready' would be wrong on all four entries.

*Evidence:* Data/SimcRotations.lua:704,705,767; tools/simc-apl/shaman_elemental.simc:52,53; shaman_enhancement.simc:168; gen_simc_rotations.py:106-107 (return {"t":"cd"} with no id/neg); grep shows no t=="cd" consumer outside DebugCommands.lua:1572

*Fix:* Emit {t="cd",id=<resolved token>,neg=<polarity>} or drop the atom to delegated when the referenced spell is not the entry itself.

### [MINOR] Tempest entries use the keystone talent id 454009, not a castable id - AC's live Tempest cast cannot match the entry (Data/SimcRotations.lua:686)
Both specs' tempest resolved to 454009 (Stormbringer keystone; TraitDefinition rows 122501/131918/132168). The castable Tempest 452201 appears in neither SkillLineAbility nor SpecializationSpells (verified: 0 rows), so the resolver can only see the talent id. IsPlayerSpell(454009) is true when talented, so the entry survives the list filter, but if AC surfaces the actual cast (452201, the Lightning Bolt override), GetEntry(452201) misses 454009 and at best falls to lightning_bolt's rank via override resolution - approximately right by luck for enh st (tempest 11 vs LB 12) and ele st (13 vs 14). Wrong-id-by-one-slot at worst; flagging for the same-token-wrong-id pattern.

*Evidence:* Data/SimcRotations.lua:686,708,731,757; SpellName CSV: both 452201 and 454009 named Tempest; grep -c ',452201,' SkillLineAbility/SpecializationSpells = 0; RotationImport.lua:90-93,146 (base/override matching path)

*Fix:* CURATED tempest=452201 for both shaman specs if AC hands the override cast id; verify in-game with /jac inspect which id AC's rotation reports.


## SHAMAN_2

### [CRITICAL] Enhancement st order is dominated by the time<15 opener list; Maelstrom-Weapon spenders permanently outrank builders (the shaman analog of the reported Balance symptom) (Data/SimcRotations.lua:720)
flatten() walks run_action_list single_open (source line 237, if=time<15) before the sustained `single` list because call_applies ignores non-target-count conditions, and first-reach dedup keeps the OPENER's conditions for most abilities. Result: elemental_blast rank 10, tempest 11, lightning_bolt 12 (all MW-stack spenders whose stack>=5/10 conditions collapse to delegated) sit above ice_strike 13, stormstrike 14, crash_lightning 15, lava_lash 16. At runtime the only enforcement for `delegated` is the insufficientPower starve-sink (SpellQueue.lua:522-525), but Maelstrom Weapon is an aura stack, not a power type, so the spenders NEVER sink -> in simc mode the enh queue slots 2+ persistently show hardcast Lightning Bolt / Elemental Blast / Tempest ahead of Stormstrike and Ice Strike even at 0 MW stacks, where the source APL would pick the builders. Additional opener artifacts: voltaic_blaze rank 3 and primordial_wave rank 4 above feral_spirit 5 / doom_winds 6; windstrike rank 9 got gates={} not-delegated from the unconditional opener line 296, losing the sustained ti_lightning_bolt condition (line 244); ice_strike 13 / stormstrike 14 / lava_lash 16 unconditional from opener lines 300/301/304 while their sustained reaches are conditional.

*Evidence:* Data/SimcRotations.lua:722-736 (st ranks as listed); tools/simc-apl/shaman_enhancement.simc:237 'actions.single=run_action_list,name=single_open,if=time<15', 289-304 (opener list whose order/conditions became the generated top ranks), 255-275 (sustained stack>=N conditions on EB/tempest/LB); SpellQueue.lua:517-525 (starve-sink reads IsSpellUsable insufficientPower only)

*Fix:* In gen_simc_rotations.py, skip or deprioritize run_action_list/call_action_list targets whose call condition contains a time< clause (opener lists), or walk them AFTER the sustained lists so first-reach dedup prefers sustained conditions; separately consider a maelstrom-weapon-stack proxy gate since insufficientPower cannot catch MW spenders.

### [MAJOR] Enhancement block uses Elemental's Ascendance id 114050 instead of 114051 - entry and its buff gates are dead for Enhancement (Data/SimcRotations.lua:727)
simc_bridge builds the 'spec universe' from TraitTreeLoadout, but all three shaman specs map to the same trees (1033/1034/786 - verified in TraitTreeLoadout CSV), so every spec's universe contains all three Ascendance ids {114050,114051,114052}. The same-name collision tie-break picks min(id)=114050 (Elemental's). For an Enhancement player IsPlayerSpell(114050) is false -> ascendance is filtered out of GetRotationGated, and RotationImport.GetEntry(114051) finds no entry (baseID/override resolution cannot bridge two sibling spec spells) -> Ascendance is unranked (rank 900) and sinks below every ranked spell in simc mode instead of holding rank 7 (st) / 9 (aoe). The !buff.ascendance gates emitted as {t="buff",id=114050,neg=true} on voltaic_blaze (line 723) and tempest aoe (line 757) reference the wrong spec's aura (inert today since neg gates are not runtime-evaluated).

*Evidence:* Data/SimcRotations.lua:727,755 '{id=114050,...} -- ascendance' inside SHAMAN_2; TraitDefinition CSV: 106895/131768/132018 SpellID=114051 (Enh), 106820/131840/132090 SpellID=114050 (Ele), 106942 SpellID=114052 (Resto); TraitTreeLoadout CSV rows 493-495/910-912 (specs 262/263/264 share trees); simc_bridge.py:196-201 (min-id tie-break)

*Fix:* Add CURATED["SHAMAN_2"]={ascendance=114051} (and audit every multi-spec-shared token: the same shared-class-tree collision mechanism affects any class whose specs share one TraitTree), or restrict _talent_ids to the spec's own subtree nodes.

### [MAJOR] Totemic hero-tree branch flattened below the entire non-totemic list: surging_totem ranked 22 (st) / 19 (aoe) though it is the branch's top sustained priority (Data/SimcRotations.lua:742)
main calls single (non-totemic) before single_totemic (talent.surging_totem branch); both collapse in, but IsPlayerSpell can only FILTER unknown spells, never reorder shared ones. A Totemic-talented player therefore gets the non-totemic ordering, with the branch-exclusive spells at the bottom: surging_totem st rank 22 / aoe rank 19 and totemic_recall st 23 / aoe 20, below fillers like fire_nova (20/15) and earth_elemental (21) - while the source totemic lists put surging_totem first in sustained play (line 308, and 118 for aoe) and totemic_recall high (312/128). Visible mis-order for the whole Totemic hero tree in simc mode.

*Evidence:* Data/SimcRotations.lua:742-743 (st surging_totem/totemic_recall at ranks 22-23), 765-766 (aoe 19-20); tools/simc-apl/shaman_enhancement.simc:42-43 (branch calls), 308 'actions.single_totemic+=/surging_totem' (2nd line of sustained totemic list), 118 (aoe_totemic surging_totem first)

*Fix:* Generator needs mutually-exclusive-branch awareness: when sibling call_action_list conditions differ only by a talent atom, emit interleaved ranks (e.g. rank branch lists independently and merge by position) or per-branch context lists.

### [MAJOR] Bloodlust ranked #1 in both st and aoe, ungated and not delegated (missing from the generator SKIP list) (Data/SimcRotations.lua:721)
The enhancement APL's 'bloodlust,line_cd=600' (once per 10 min) is a non-rotational raid cooldown, but 'bloodlust' is absent from gen_simc_rotations.py SKIP (which does skip potion/racials/healthstone), and line_cd mods are not parsed as a condition -> emitted as {id=2825,gates={}} at rank 1 of both contexts. If Bloodlust ever enters the ranked queue (AC rotation inclusion or a user's pinned/custom entry), it pins the top re-ranked slot permanently while off cooldown; if AC never surfaces it, it is dead top-rank data. Elemental's APL has no bloodlust line, so only SHAMAN_2 is affected.

*Evidence:* Data/SimcRotations.lua:721 '{id=2825,gates={}},  -- bloodlust' (st rank 1), 747 (aoe rank 1); tools/simc-apl/shaman_enhancement.simc:23 'actions+=/bloodlust,line_cd=600'; gen_simc_rotations.py:37-47 SKIP set contains potion/racials but not bloodlust/heroism/timewarp

*Fix:* Add bloodlust (and heroism/time_warp/primal_rage equivalents) to SKIP in gen_simc_rotations.py and regenerate.

### [MINOR] Dot-gate polarity dropped: positive dot.flame_shock.ticking conditions emit the same gate shape as !ticking refresh gates (Data/SimcRotations.lua:724)
classify_atom ignores negation for dot gates, so primordial_wave st/aoe (source: 'dot.flame_shock.ticking' - cast only WHILE the dot runs) and aoe lava_lash ('molten_assault...&dot.flame_shock.ticking') carry {t="dot",id=470411} identical to flame_shock's own !ticking refresh gate. Currently harmless: SpellQueue never evaluates t=dot gates (the DoT sink keys DotTracker on the SUGGESTED spell's id, and 375982/60103 are not in TargetDots), but a future consumer interpreting the gate as 'suppress while dot active' would suppress primordial_wave/lava_lash exactly when the source wants them cast.

*Evidence:* Data/SimcRotations.lua:724,752,753 vs 722,749; tools/simc-apl/shaman_enhancement.simc:246,74,51; gen_simc_rotations.py:108-110 (neg computed but never stored for dot gates)

*Fix:* Store neg on dot gates ({t="dot",id=...,neg=true} for ticking-required) so a future evaluator can distinguish refresh gates from ticking-required gates.

### [MINOR] set_bonus conditions treated as statically-resolvable build gates: crash_lightning ranked 15 unconditionally (Data/SimcRotations.lua:735)
classify_atom drops (talent|hero_tree|set_bonus|equipped) atoms on the theory that 'IsPlayerSpell sorts them at runtime', but set_bonus/equipped gate nothing IsPlayerSpell can see - crash_lightning is known regardless of tww2_4pc. Its first reach (single_open line 302, if=set_bonus.tww2_4pc) becomes gates={} not-delegated at rank 15, above lava_lash 16, for every enhancement player. Small displacement; the sustained list does have an unconditional-ish crash_lightning near the bottom so the practical error is one or two slots.

*Evidence:* Data/SimcRotations.lua:735; tools/simc-apl/shaman_enhancement.simc:302; gen_simc_rotations.py:124-125

*Fix:* Treat set_bonus./equipped. atoms as delegated (unknowable) rather than build gates.


## WARLOCK_1

### [CRITICAL] end_of_fight sub-list hoisted to top: drain_soul rank 1 and malefic_rapture rank 2 in ALL contexts (st/cleave/aoe), above every maintenance DoT (Data/SimcRotations.lua:774)
flatten() walks call_action_list at its call position and call_applies() ignores every non-target-count condition, so the end_of_fight list (warlock_affliction.simc line 44, entries gated on fight_remains<5 / fight_remains<4) is flattened in BEFORE the rotational body; first-reach dedup then locks drain_soul=rank1 and malefic_rapture=rank2 and DISCARDS their properly-conditioned main-list occurrences. In simc mode the queue tail always shows Drain Soul and Malefic Rapture first, above Agony/Haunt/UA/Wither/Corruption maintenance, even with zero DoTs up. In aoe this is worst: drain_soul's real aoe position is the bottom filler (apl line 104). Side effect: the dedup also drops the line-51 drain_soul variant that carried the buff.nightfall promotion gate, so drain_soul loses its Nightfall window promotion too. Exact same mechanism as the reported DRUID_1 Sunfire/Starfire inversion.

*Evidence:* Data/SimcRotations.lua:774-775 (st), 789-790 (cleave), 804-805 (aoe): {id=388667,gates={},delegated=true} drain_soul then {id=324536,...} malefic_rapture at indexes 1-2. Source tools/simc-apl/warlock_affliction.simc:44 'call_action_list,name=end_of_fight' precedes agony line 45; end_of_fight list lines 142-144 = drain_soul(fight_remains<5), oblivion, malefic_rapture(fight_remains<4). Main-list drain_soul lines 51/60/66/70, MR lines 59-65 all dropped as dups. RotationImport.lua:105 rank = list index; SpellQueue.lua:468-475 simc mode sorts by that rank.

*Fix:* In gen_simc_rotations.py, treat calls whose if= contains only unreadable non-target-count conditions (fight_remains, variable.*) as NOT applying (skip the branch), or at minimum defer end_of_fight/finisher-style lists to after the calling list's own entries; alternatively mark entries reached only through an unreadable-conditioned call as delegated AND rank them at their best main-list occurrence instead of first-reach.

### [MAJOR] drain_soul emitted as talent id 388667; addon's own tables use cast id 198590 (Data/SimcRotations.lua:774)
Data/ChanneledSpells.lua:49 and Data/SpellArchetypes.lua:1676 both use 198590 for Drain Soul; SimcRotations uses 388667 (DF/TWW talent id) in all three contexts. If AC's queue id is 198590 and no override chain links them, the rank-1 drain_soul entry never matches (which accidentally masks the end_of_fight rank-1 hoist for this one spell, but leaves malefic_rapture rank 2 live); if it does match via override, the bogus rank 1 is live. Either way the id is inconsistent with the addon's canonical id for the same token.

*Evidence:* SimcRotations.lua:774,789,804 id=388667 vs ChanneledSpells.lua:49 [198590], SpellArchetypes.lua:1676 [198590].

*Fix:* Curate drain_soul:198590 for WARLOCK_1 (or resolve through the override chain in the bridge).

### [MINOR] Gate loss: st/cleave agony, unstable_affliction, wither, corruption all emitted gates={} - their refreshable/remains<X maintenance conditions vanish (DRUID_1 sunfire pattern) (Data/SimcRotations.lua:776)
The high-priority DoT lines (apl 45-50) wrap remains<3/5/8 in parenthesized OR groups, so every atom delegates and no dot gate is emitted; the later plain 'agony,if=refreshable' / 'unstable_affliction,if=refreshable' lines (68-69) that WOULD produce {t=dot,id=...} gates are dropped by first-reach dedup. Unlike DRUID_1 sunfire this is NOT user-visible today: dot/cd/execute gates are only consumed by /jac inspect (DebugCommands.lua:1572-1589), and the actual already-applied sink runs through DotTracker with TargetDots, which has all the warlock cast ids (980, 172, 1259790, 348, 27243, 205179, 386997, 445468). Dead data plus misleading /jac inspect output.

*Evidence:* SimcRotations.lua:776 agony gates={}, 778 UA, 779 wither, 780 corruption (st); 791-795 (cleave). Source warlock_affliction.simc:45-50 vs 68-69. TargetDots.lua:15,21,86,92 cover the sink.

*Fix:* When deduping, merge gates from later occurrences of the same id (union of dot gates) instead of discarding them, or prefer the occurrence with evaluable gates.


## WARLOCK_2

### [MAJOR] hand_of_guldan (rank-1 Demo entry) emitted as 1250273 while SpellArchetypes uses 105174 (Data/SimcRotations.lua:822)
The top-ranked Demonology entry uses id 1250273; the addon's curated archetype table lists Hand of Gul'dan as 105174 (Data/SpellArchetypes.lua:3203). Lookup succeeds only if the live client override chain FindSpellOverrideByID(105174)==1250273 holds; if AC hands 105174 and that chain doesn't exist, Demonology's rank-1 SimC entry never matches any AC queue spell and HoG sinks to unranked. Same same-token-different-id class as moonfire 8921 vs 326646; needs in-game confirmation of the 1250273 id.

*Evidence:* SimcRotations.lua:822 {id=1250273,...} -- hand_of_guldan vs SpellArchetypes.lua:3203 [105174] = true, -- Hand of Gul'dan.

*Fix:* Verify 1250273 in-game (/jac inspect); if it is a renumbered cast id, update SpellArchetypes for consistency, otherwise curate hand_of_guldan:105174.

### [MINOR] power_siphon lost its '!buff.demonic_core.up' gate - demonic_core token unresolved (Data/SimcRotations.lua:832)
Source line 51 'power_siphon,if=!buff.demonic_core.up' should yield a neg buff gate; resolve('demonic_core') returned nil (buff 264173 not in the castable universe) so the entry fell back to gates={} delegated. Harmless at runtime today (neg gates are unused) but it is a resolver gap for buff tokens that are pure auras.

*Evidence:* SimcRotations.lua:832 {id=264130,gates={},delegated=true}; source warlock_demonology.simc:51.

*Fix:* Same fix as the aura-universe resolver finding; demonic_core -> 264173.


## WARLOCK_3

### [MAJOR] Havoc sub-list hoisted over the cleave/aoe bodies: havoc-window actions take ranks 1-7 at 2T while Summon Infernal/Malevolence/Ruination rank below the Incinerate filler (Data/SimcRotations.lua:852)
Same call-hoisting mechanism: 'call_action_list,name=havoc,if=havoc_active&havoc_remains>gcd.max' (cleave line 106, aoe line 72) has no target-count clause, so call_applies treats it as always applying and the havoc list (meant only while the Havoc debuff is live on an off-target) is flattened in ahead of the whole cleave body. Generated cleave ranks: conflagrate 1, soul_fire 2, cataclysm 3, immolate 4, wither 5 ... incinerate 11 (from havoc line 145), then the actual cleave-body cooldowns malevolence 12, ruination 14, summon_infernal 15 BELOW the incinerate filler. At 2 targets in simc mode the queue bottom-ranks the spec's major cooldowns under the basic filler. Aoe context has the same shape (havoc entries ranks 3-12).

*Evidence:* Data/SimcRotations.lua:852-867 cleave order vs tools/simc-apl/warlock_destruction.simc:106 (havoc call), 108 (malevolence), 118 (ruination), 123 (summon_infernal, unconditional mid-list), 131 (incinerate bottom filler); generated incinerate 863 (rank 11) precedes malevolence 864 (12), ruination 866 (14), summon_infernal 867 (15).

*Fix:* Treat calls gated on unreadable runtime conditions (havoc_active, buff.*, variable.*) as non-applying during flattening, or flatten them after the calling list's own entries so the base rotation keeps its ranks.

### [MINOR] target.time_to_die>8 misclassified as an execute gate on wither/immolate/havoc - semantically inverted (anti-execute dot-worthiness check) (tools/gen_simc_rotations.py:120)
classify_atom maps target.time_to_die to {t="execute"} alongside target.health.pct. 'time_to_die>8' means 'target will LIVE long enough to be worth dotting' - the opposite of execute range. WARLOCK_3 st wither (842), st immolate (848), cleave/aoe havoc (865, 883) carry execute gates that would suppress/boost exactly backwards if ever evaluated. Currently dead data (execute gates are display-only; ContextRank's execute float reads SpellDB.GetGate, not SimC gates), so minor - but it poisons /jac inspect and any future gate evaluator.

*Evidence:* gen_simc_rotations.py:120-121; SimcRotations.lua:842,848,865,883; source warlock_destruction.simc:50,59,89,109 'target.time_to_die>8'.

*Fix:* Only classify target.health.pct (and time_to_die<N) as execute; delegate time_to_die>N atoms.


## WARRIOR_1

### [CRITICAL] Arms: Sweeping Strikes ranked 3 in st with gates={} and delegated=false, though every source occurrence is active_enemies=2-only or AoE-list (Data/SimcRotations.lua:891)
Same root cause as the Fury Whirlwind finding: 'sweeping_strikes,if=active_enemies=2' (warrior_arms.simc:69 colossus_execute, :152 slayer_execute) has its target-count atom dropped as neither gate nor delegation, and the execute sublists are flattened first, so it lands at st rank 3. Runtime: 30s cooldown ability; whenever off cooldown in a pure single-target fight (simc mode) it ranks above every damage button in the normal bucket -> suggestion slot 2 shows a zero-value-in-ST cooldown. Also a delegated-sanity miss: an unevaluable-for-us condition produced delegated=false.

*Evidence:* Data/SimcRotations.lua:891 '{id=260708,gates={}}' at st index 3 (after charge, pummel). Source lines warrior_arms.simc:69,152 (=2 only), :50,:107,:125,:194 (2+/AoE lists). cleave (:912) and aoe (:939) placements are legitimate.

*Fix:* Same generator fix as the Whirlwind finding (tier-filter action-level target-count atoms); Sweeping Strikes then disappears from st entirely.

### [MAJOR] Arms st order is the EXECUTE-PHASE priority: colossus_execute/slayer_execute flatten before colossus_st/slayer_st because their run_action_list if=talent.X&variable.execute_phase passes call_applies at every k, and first-reach dedup locks their order/gates (Data/SimcRotations.lua:899)
call_applies (gen_simc_rotations.py:142-152) only checks target-count clauses, so 'run_action_list,name=colossus_execute,...,if=talent.demolish&variable.execute_phase' (warrior_arms.simc:39) walks at k=1 BEFORE colossus_st (:41). Concrete inversions vs the non-execute st lists: execute at rank 11 above mortal_strike (14); skullsplitter (12) and demolish (13) above mortal_strike, contradicting colossus_st:96-97 and slayer_st:183-184 where mortal_strike outranks skullsplitter; avatar/champions_spear/colossus_smash take the execute lists' unconditional forms so their st conditions (slayer_st:174-178 cd/buff couplings) are lost. No execute gate marks the branch because the health test hides behind variable.execute_phase (variables:230). Visible effect: with Skull Splitter/Demolish off cooldown at full target HP, they outrank Mortal Strike in slots 2+.

*Evidence:* Data/SimcRotations.lua:899-903 (execute 11, skullsplitter 12, demolish 13, mortal_strike 14, overpower 15) vs warrior_arms.simc colossus_st:96-99 (mortal_strike > skullsplitter > overpower > execute) and slayer_st:183-185.

*Fix:* Teach the flattener that a run/call gated on variable.execute_phase (resolvable via the variables list to target.health.pct) is an execute-branch: either walk non-execute lists first for the base order, or stamp the branch's entries with {t="execute"} so a future runtime can demote them.

### [MINOR] Dead dot-gate ids: aoe cleave gated on dot id 1261060 (Deep Wounds, never castable/never tracked) and Prot thunder_clap on dot id 772 (Rend, never cast by Prot); dot gates are runtime-dead anyway (Data/SimcRotations.lua:936)
Repo-wide grep shows entry gates are consumed only by SpellQueue.SimcBuffWindowActive (buff type only) and the DebugCommands inspector; DoT sinking rides the separate DotTracker path keyed by the CAST displayID against Data/TargetDots.lua. So {t="dot"} gates are dead data. Where they'd matter if ever wired up: WARRIOR_1 aoe :936 cleave gate id=1261060 -- Deep Wounds is applied by Cleave(845)/Mortal Strike(12294), 1261060 is never a cast, so DotTracker.IsDotActiveOnCurrentTarget(1261060) is always false (TargetDots.lua:93 [1261060]=6 is equally unreachable); WARRIOR_3 :1000/:1018 thunder_clap gate id=772 -- Prot applies Rend via Thunder Clap (6343), never casts 772. Arms Rend maintenance is the one warrior case that actually works, via TargetDots[772]=15 matching the real cast id (:20).

*Evidence:* Grep: '.gates' consumers = SpellQueue.lua:531 (buff-only) + DebugCommands.lua:1567-1590; DotTracker.OnCastSucceeded (DotTracker.lua:87-92) keys SpellDB.IsTargetDot(castID).

*Fix:* Either wire dot gates into the DotTracker sink using applicator-cast ids (resolve dot.<name> to the APPLICATOR the spec actually casts), or stop emitting dot gates whose id is not a castable applicator for that spec.

### [MINOR] Pure-talent OR compounds mark entries delegated instead of collapsing like single talent atoms: aoe bladestorm delegated from 'talent.unhinged|talent.merciless_bonegrinder' (Data/SimcRotations.lua:946)
classify_atom drops a lone talent.X atom (build gate, gen_simc_rotations.py:124-125) but any '|' makes the atom compound -> delegated=true (:104-105). warrior_arms.simc:58 is talent-only, so aoe bladestorm gets delegated=true (Data/SimcRotations.lua:946) while the st/cleave bladestorm (:904/:925, from an unconditional line) does not. delegated only triggers the insufficient-rage sink; Bladestorm costs no rage, so behavior is unaffected -- data inconsistency only.

*Evidence:* Data/SimcRotations.lua:946 vs :904; warrior_arms.simc:58,:84.

*Fix:* In classify_atom, recognize compounds composed solely of talent/hero_tree atoms and return (None, False).


## WARRIOR_2

### [CRITICAL] Fury: Whirlwind ranked 11 of 21 in st (the ONLY context emitted), above Rampage(13)/Bloodbath(14)/Raging Blow(15)/Bloodthirst(16), though the APL only uses it as an AoE weave or absolute bottom filler (Data/SimcRotations.lua:970)
classify_atom (gen_simc_rotations.py:122-123) returns (None,False) for active_enemies/spell_targets atoms assuming 'handled by the tier split', but flatten() (:178-199) only applies call_applies() to call/run_action_list lines, never to action-level if=. slayer:53 'whirlwind,if=active_enemies>=2&talent.meat_cleaver&buff.meat_cleaver.stack=0' therefore lands in the st list at its high slayer-list position with the target-count silently discarded. Because no per-tier difference survives, WARRIOR_2 emits st only (no aoe/cleave). Runtime: Whirlwind has no cooldown, costs no rage (delegated starvation-sink never fires per SpellQueue.lua:522-524), so in simc mode single-target it permanently sits in the normal bucket at rank 11 while the core ST buttons rank 13-16 -> Whirlwind occupies suggestion slot 2 whenever nothing procs. Same shape as the reported Balance Sunfire/Starfire complaint.

*Evidence:* Data/SimcRotations.lua:970 '{id=190411,gates={},delegated=true},  -- whirlwind' at index 11; WARRIOR_2 block has st only (958-981). Source tools/simc-apl/warrior_fury.simc:53 (aoe-gated), :78 and :108 (unconditional bottom filler). SpellQueue.lua:536-549 buckets/ranks; rank source RotationImport.GetEntry.

*Fix:* In the generator, tier-filter action-level target-count atoms: evaluate call_applies(mods['if'], k) for plain actions too and drop the entry from tiers where the count cannot hold (or at minimum mark it delegated and demote); regenerate.

### [MAJOR] Fury buff gates reference talent/trigger spell ids, not the triggered AURA ids, so buff-window promotion (the only runtime consumer of gates) never fires: enrage 184361 vs aura 184362, ashen_juggernaut 392536 vs 392537, brutal_finish 446085 vs 446918 (Data/SimcRotations.lua:966)
SpellQueue promotes a ranked entry like a proc when any positive buff gate id matches C_UnitAuras.GetPlayerAuraBySpellID(g.id) (SpellQueue.lua:445-455 -> BlizzardAPI/CooldownTracking.lua:523-532). The resolver returns cast/talent ids; for auras triggered by a different id the probe can never match. Affected entries: enrage(184361) on thunderous_roar:966, champions_spear:967, bladestorm:969, bloodthirst:975, thunder_blast:980; ashen_juggernaut(392536) on execute:965; brutal_finish(446085) on onslaught:971, raging_blow:974, bloodthirst:975. Result: the entire 'surface X during Enrage/Brutal Finish/Ashen Juggernaut window' behavior is silently dead for Fury; entries fall back to static rank. Gates where cast==aura (avatar 107574, bladestorm 227847, sweeping_strikes 260708) do work.

*Evidence:* CSV SpellName.12.1.0.68301.csv contains both members of each pair: 184361+184362 'Enrage', 392536+392537 'Ashen Juggernaut', 446085+446918 'Brutal Finish'. Resolver collision rule min() (tools/simc_bridge.py:197-201) picks the lower/talent id.

*Fix:* For buff.<token> atoms, resolve through a triggered-aura mapping (SpellXDescriptionVariables/known trigger column, or a curated buff-token->aura-id table) instead of the castable resolver; add the three Fury pairs to that curation.

### [MAJOR] Fury bloodbath resolved to 113344 (MoP-era Bloodbath) instead of the live cast 335096; entry is dead at runtime and its intended rank is unreachable (Data/SimcRotations.lua:973)
Both 113344 and 335096 are named 'Bloodbath' in the client CSV; the resolver's same-name collision rule takes min(id) (tools/simc_bridge.py:200-201) -> 113344. Runtime: AC hands 335096 (Reckless Abandon override of Bloodthirst); RotationImport.GetEntry misses m[335096], falls to baseID->23881 and returns the bloodthirst entry (rank 16) instead of bloodbath's intended rank 14 -- and the APL ranks bloodbath ABOVE raging_blow/bloodthirst (warrior_fury.simc:60,66 vs :61,:67-75). The 113344 entry itself can never match anything AC suggests. Same stale id is mirrored in Data/TargetDots.lua:35 ([113344]=6) so DotTracker never sinks a live Bloodbath bleed either (casts arrive as 335096). Related residue: crushing_blow (335097) unresolved and absent from the list -- largely compensated because baseID(335097)=85288 hits the raging_blow entry (rank 15).

*Evidence:* SpellName.12.1.0.68301.csv: '113344,Bloodbath' and '335096,Bloodbath'; Data/SimcRotations.lua:973 '{id=113344,...}  -- bloodbath'; Data/TargetDots.lua:35; same-token-different-id cross-spec precedent is the DRUID moonfire 8921 vs 326646 pattern.

*Fix:* Curate WARRIOR_2 {"bloodbath": 335096, "crushing_blow": 335097} in gen_simc_rotations.py CURATED (and gen_target_dots CURATED for the dot); consider preferring the id that is castable/on the spec's override chain over bare min() for name collisions.

### [MINOR] Fury onslaught over-gated for Mountain Thane builds: first-reach dedup keeps the Slayer branch's brutal_finish buff gate, though the Thane list's onslaught is unconditional (talent.tenderize only) (Data/SimcRotations.lua:971)
Hero-branch collapse (slayer walked before thane) plus dedup-by-id means onslaught carries {t="buff",id=446085} from warrior_fury.simc:54 while :94 (thane) has no buff condition. Because buff gates only PROMOTE (never suppress), the practical loss is just the promotion -- which is already dead for 446085 via the wrong-aura-id finding. Cosmetic today; would become an over-gate if gates ever suppress.

*Evidence:* Data/SimcRotations.lua:971; warrior_fury.simc:54 vs :94.

*Fix:* When deduping across collapsed branches, union-or-drop conflicting gates (keep gates only if every reaching branch agrees), or annotate per-branch.


## WARRIOR_3

### [MAJOR] Prot: Thunder Blast ranked 9 (st) ungated above Shield Slam (14) because its main-list AoE condition (spell_targets.thunder_blast>=2&stack=2) was dropped and first-reach dedup locks that slot (Data/SimcRotations.lua:993)
warrior_protection.simc:32 gates the high main-list thunder_blast on spell_targets>=2 (dropped by the target-count hole) and stack=2 (delegated). The generic list intends TB above shield_slam only under a narrow stack/Avatar condition (:51) and otherwise below it (:55-58). Generated st keeps TB at rank 9, shield_slam at 14, so for Mountain Thane Prot in simc mode Thunder Blast persistently outranks Shield Slam in slots 2+ whenever a charge is up. delegated=true only sinks on rage starvation, which TB (a generator) never hits.

*Evidence:* Data/SimcRotations.lua:993 '{id=435607,gates={},delegated=true}' rank 9 vs :998 shield_slam rank 14; source warrior_protection.simc:32,:51-58.

*Fix:* Same target-count tier-filter fix in the generator; the st list then first reaches thunder_blast via generic:51/56 below/around shield_slam.

### [MAJOR] Prot shield_block resolved to 231847, but the castable/action-bar Shield Block is 2565 -- if AC hands 2565 the entry never matches and Shield Block runs unranked (900) with its rage-starvation sink lost (Data/SimcRotations.lua:997)
Both 2565 and 231847 are named 'Shield Block' in the CSV. The resolver's tier preference (SpecializationSpells first, tools/simc_bridge.py:180-201) picks the spec-granted 231847 over the learned castable 2565. FindBaseSpellByID(2565)=2565, so RotationImport.GetEntry(2565) finds neither m[2565] nor a base alias -> rank falls to the unranked 900 default (SpellQueue.lua:470), dropping Shield Block from rank 13 to below devastate, and the delegated flag (rage sink) never applies. PLAUSIBLE rather than confirmed: needs an in-game check of which id C_AssistedCombat/action bar reports for Shield Block.

*Evidence:* SpellName.12.1.0.68301.csv: '2565,Shield Block' and '231847,Shield Block'; Data/SimcRotations.lua:997 '{id=231847,...}  -- shield_block' (st) and :1017 (aoe).

*Fix:* Verify AC's id in-game (/jac inspect); if 2565, curate {"shield_block": 2565} for WARRIOR_3.

### [MINOR] Prot ignore_pain gates {t=execute},{t=cd} are both wrong-by-construction: execute direction inverted (source is target.health.pct>=20, i.e. NOT execute) and the cd atom belongs to the other OR-disjunct (Data/SimcRotations.lua:988)
Two systemic classifier defects meet here. (1) classify_atom (gen_simc_rotations.py:120-121) maps any target.health.pct comparison to {t="execute"} ignoring the comparison direction, so '>=20' (explicitly not-execute) emits an execute-required gate. (2) split_and (:83-96) splits on top-level & before considering top-level |, so in 'A&(B)|(C)&D&E&F' the atoms D ('cooldown.shield_slam.remains<=1') and E leak out of the second disjunct and D becomes a hard cd gate on the whole entry. Runtime impact is nil today because SpellQueue evaluates only positive buff gates, but /jac inspect simc (DebugCommands.lua:1572-1589) renders these as real conditions, and any future evaluator of dot/cd/execute gates would inherit inverted/over-tight logic. The same &-before-| leak conjoins first-disjunct gates onto WARRIOR_2 bloodthirst (:975).

*Evidence:* warrior_protection.simc:27 (the ignore_pain line: 'target.health.pct>=20&(...)|(rage>=70|buff.seeing_red.stack=7&rage>=35)&cooldown.shield_slam.remains<=1&...'); Data/SimcRotations.lua:988/:1008 '{t="execute"},{t="cd"}'.

*Fix:* In classify_if, detect a top-level | (depth-0 scan before split_and) and delegate the whole expression; in classify_atom, drop or negate execute gates for >=/> thresholds.


## SYSTEMIC

### [CRITICAL] Generated {t="dot"}, {t="cd"}, {t="execute"} and negative-buff gates are dead data at runtime - only positive buff gates are consumed, contradicting RotationImport's design doc (SpellQueue.lua:445)
RotationImport.lua:6-9 claims 'the runtime evaluator (SpellQueue) applies them'. Reality: the ONLY runtime consumer of simcRec.gates is SimcBuffWindowActive (SpellQueue.lua:445-455), which scans exclusively g.t=='buff' and not g.neg (proc-like promotion). Grep across all runtime Lua shows no other consumer: dot gates, cd gates, execute gates, targets gates, and neg buff gates are read only by the /jac inspect gates DISPLAY (DebugCommands.lua:1566-1595). Consequence for the report: DRUID_1.aoe Sunfire's {t="dot",id=93402} gate (Data/SimcRotations.lua:171) - the one piece of data that encodes 'don't suggest Sunfire while its DoT is up' - does nothing; the only sink path is DotTracker (broken for Sunfire per finding 1). Similarly DRUID_1.st Moonfire's dot gate is inert. So in simc mode nothing can ever demote a ranked, off-cooldown, dot-already-applied ability: Starfire rank 2 and Sunfire rank 4 surface permanently behind AC's pick, exactly as reported.

*Evidence:* SpellQueue.lua:447-454 loop: 'if g.t == "buff" and not g.neg ...' - the only gate-type branch in runtime code. Sink condition at SpellQueue.lua:536-540 tests only IsSpellReady/starved/IsUnusableNonResource/IsConfirmedOutOfRange/DotTracker - never simcRec.gates. RotationImport.lua:6-9 header claim; Data/SimcRotations.lua carries ~hundreds of dot/cd/execute gates across 34 specs, all unconsumed.

*Fix:* Minimal: in the sink branch (SpellQueue.lua:536-540) also sink when simcRec has a {t="dot"} gate whose id (or, failing that, displayID) satisfies DotTracker.IsDotActiveOnCurrentTarget - one extra or-clause plus a small helper mirroring SimcBuffWindowActive. cd gates are already subsumed by the IsSpellReady sink; execute/targets/neg-buff gates can stay display-only, but correct the RotationImport.lua:6-9 comment to say which gate types are actually applied.

### [CRITICAL] PALADIN blocks resolve core buttons to non-canonical spell ids that match no other Data table (moonfire-326646 pattern, systemic) (Data/SimcRotations.lua:564)
simc_bridge.resolver prefers the narrowest tier (SpecializationSpells / talent SpellID column) before class skill-line spells, so a rank-upgrade passive or talent-definition spell that shares the ability's name shadows the real cast id. Runtime consequence: RotationImport.BuildLookup keys the rank map by these ids (plus FindSpellOverrideByID of them, which is a no-op for passives), so when AC hands the queue the real cast id (20271, 35395, 85673, 26573, 24275, 31884, 184662, 231895, 432459...), GetEntry misses and rankOf falls to the 900 unranked sentinel -> in simc mode the spec's most common buttons (Judgment, Crusader Strike, Hammer of Wrath, Word of Glory, Consecration, Avenging Wrath, Shield of Vengeance, Crusade, Holy Armaments) sink below every id-matched entry (divine_toll 375576, eye_of_tyr 209202, blade_of_justice 184575...), producing exactly the reported 'wrong spells hogging the top slots' signature. Same root cause as Balance moonfire 326646 vs Feral 8921.

*Evidence:* SimcRotations PALADIN_3 st: judgment id=315867 (line 564), crusader_strike id=342348 (565, also PALADIN_2 line 544), hammer_of_wrath id=1241288 (563 and 546), shield_of_vengeance id=1261562 (553), crusade id=1253598 (556), avenging_wrath id=384376 (534/555); PALADIN_2: word_of_glory id=315921 (547), consecration id=327980 (545), holy_armaments id=1289728 (540), divine_hammer id=432929 (557). Canonical ids everywhere else in the repo: Judgment 20271 (SpellCooldowns.lua:120, SpellArchetypes.lua:33, RangeReferences.lua:82), Crusader Strike 35395 (SpellCooldowns.lua:175, RangeReferences.lua:58), Hammer of Wrath 24275 (SpellCooldowns.lua:136, SpellArchetypes.lua:38), Word of Glory 85673 (SpellCategories.lua:211), Consecration 26573 (SpellCooldowns.lua:143), Avenging Wrath 31884 (SpellCooldowns.lua:157, SelfAuras.lua:165), Shield of Vengeance 184662 (SpellCategories.lua:88, SelfAuras.lua:654), Crusade 231895 (SpellCooldowns.lua:624, AuraStacks.lua:29), Holy Armaments/Holy Bulwark 432459 (SpellCooldowns.lua:986), Divine Hammer 198034/198137 (SelfAuras.lua:682, SpellArchetypes.lua:226). None of the SimC-block ids above appear in any other Data table. Contrast: PALADIN_2 judgment=275779 DID resolve to the canonical prot cast id (SpellArchetypes.lua:1998), showing the resolver is only right when SpecializationSpells happens to contain the true override cast.

*Fix:* In tools/simc_bridge.py resolver, filter candidate ids to castable spells (or validate against a cast-id source such as the ids used by gen_target_dots/SpellCooldowns) before the min-id tie-break, or prefer the class skill-line/known-cast tier when the spec-tier hit is a passive rank entry; regenerate and diff every spec block for id churn. Verify in-game which ids C_AssistedCombat returns and add the confirmed cast ids to CURATED for paladin as a stopgap.

### [MAJOR] Unresolved residue silently drops abilities the rest of the repo knows: hammer_of_light, final_reckoning, justicars_vengeance, templar_strike, templar_slash, moment_of_glory, bastion_of_light - Templar prot and Templar-strikes ret get their primary buttons unranked (Data/SimcRotations.lua:550)
The generator drops unresolved tokens fail-safe ('keeps AC order'), but in simc mode an absent entry ranks 900 (SpellQueue rankOf sentinel) - it sinks BELOW every ranked entry, which is not neutral. Missing from PALADIN_2: hammer_of_light (the Templar finisher, APL line 38), moment_of_glory (line 29), bastion_of_light (line 31). Missing from PALADIN_3: final_reckoning (cooldowns line 36), hammer_of_light (finishers line 39), justicars_vengeance (line 42), templar_strike (line 54), templar_slash (lines 46/51/59). templar_strike/templar_slash REPLACE crusader_strike for the Templar Strikes talent, so that build's main builder is unranked; the crusader_strike fallback bridge (BuildLookup baseID via FindSpellOverrideByID) is also broken because the stored crusader_strike id is the non-castable 342348. All of these ids exist elsewhere in the repo: Hammer of Light 427453/429826 (SpellArchetypes.lua:2380/560), Final Reckoning 343721 (SpellCooldowns.lua:791, SpellArchetypes.lua:422), Justicar's Vengeance 215661 (SpellArchetypes.lua:1802, RangeReferences.lua:60), Templar Strike 407480 / Templar Slash 406647 (SpellArchetypes.lua:2346/2343) - so the resolver's universe, not the game data, is the gap.

*Evidence:* Data/SimcRotations.lua PALADIN_2 (532-548) and PALADIN_3 (550-566) contain none of these tokens; source APL lines cited above; SpellQueue.lua:468-475 (unranked -> 900).

*Fix:* Add the seven ids to CURATED for PALADIN_2/PALADIN_3 in tools/gen_simc_rotations.py (mirroring the DRUID_2 precedent) and regenerate; longer term, extend the bridge universe to hero-tree trait trees.

### [MAJOR] Systemic: buff.X.up gates resolve to the TALENT spell id, not the aura id - every talent-granted-buff promotion is dead (Data/SimcRotations.lua:462)
classify_atom resolves buff tokens through the castable-spell resolver, which returns the TraitDefinition (talent) id. BlizzardAPI.IsBuffWindowActive probes C_UnitAuras.GetPlayerAuraBySpellID(gateId) - the applied AURA id. When buff id != talent id the promotion never fires. Monk instances: MONK_1 tiger_palm gate id=196736 (Blackout Combo talent; aura is 228563) - TP never promotes in the Blackout Combo window; MONK_1 spinning_crane_kick gate id=386965 (Charred Passions talent; aura 386963); MONK_2 crackling_jade_lightning gate id=467316 (Jade Empowerment talent; aura 467317) - the Jade-Empowered CJL window, the entire point of that entry, never surfaces; MONK_3 celestial_conduit/strike_of_the_windlord gate id=388661 (Invoker's Delight talent; aura 388663). Gates where cast==aura (116680 TFT, 387184 WoO, 137639 SEF) work correctly.

*Evidence:* SpellName CSV shows paired records: 196736+228563 'Blackout Combo', 386965+386963 'Charred Passions', 467316+467317 'Jade Empowerment', 388661+388663 "Invoker's Delight"; CooldownTracking.lua:523-532 IsBuffWindowActive uses GetPlayerAuraBySpellID; SpellQueue.lua:445-455 SimcBuffWindowActive is the only consumer of buff gates; Data/SimcRotations.lua:462,463,480,500,503.

*Fix:* Resolve buff.X tokens through an aura-id map (e.g. the talent's triggered-aura, or curate: blackout_combo=228563, charred_passions=386963, jade_empowerment=467317, invokers_delight=388663).

### [MAJOR] Systemic: entries whose SimC conditions live entirely in target_if= are emitted with NO gates and NO delegated flag - falsely unconditional (tools/gen_simc_rotations.py:163)
make_entry classifies only mods.get('if'); target_if is mined solely for refreshable/ticking/dot.<token> substrings. Any other target_if content (remains<N, combo_points, energy, dot.X.remains>N) is silently dropped without even setting delegated, so the entry looks unconditionally castable and is never starve-sunk (SpellQueue.lua:522-525 only starve-checks delegated entries). Druid instances: DRUID_1 st sunfire (covered above); DRUID_4 ferocious_bite (druid_restoration.simc:53 - combo_points>3/energy>=50/dot.rip.remains>10 all in target_if) emitted {id=22568,gates={}} undelegated at rank 9 (SimcRotations.lua:246); DRUID_4 rip (druid_restoration.simc:41 - all combo-point/ticking logic in target_if) emitted with only the own-dot gate, undelegated (SimcRotations.lua:241).

*Evidence:* gen_simc_rotations.py:163-168 (classify_if(mods.get('if')) then only the tif regex/substring check appends a dot gate; no delegation from tif); Data/SimcRotations.lua:241,246; druid_restoration.simc:41,53.

*Fix:* In make_entry, run the target_if expression (minus the max:/min: selector prefix) through the same classify_if path so unreadable target_if atoms set delegated=true.

### [MAJOR] Systemic: every positive buff-window gate id in the DK blocks is the castable/talent/passive spell id, not the player's proc-aura id - the entire simc-mode proc-promotion layer is dead for Death Knight (Data/SimcRotations.lua:77)
SpellQueue's only runtime use of gates is SimcBuffWindowActive -> BlizzardAPI.IsBuffWindowActive(g.id), which requires the id to be the aura actually ON the player (GetPlayerAuraBySpellID + duration probe). simc_bridge.resolver is built from the CASTABLE universe with tier preference SpecializationSpells > talent SpellID, so buff tokens resolve to the talent/passive/cast id while a distinct proc-aura id exists in the same CSV under the same name. Confirmed wrong pairs (gate id -> actual aura id): DEATHKNIGHT_1 blood_boil {buff 49028} DRW cast vs buff 81256 (line 27); DEATHKNIGHT_1 death_strike {buff 391477} Coagulopathy talent vs buff 391481 (line 23); DEATHKNIGHT_2 howling_blast {buff 59057} Rime passive vs proc 59052 (lines 47,62); DEATHKNIGHT_3 death_coil {buff 49530} Sudden Doom talent vs proc 81340 (line 77); DEATHKNIGHT_3 scourge_strike {buff 434143} Infliction of Sorrow talent vs buff 434144 (line 76); DEATHKNIGHT_3 cleave scourge_strike {buff 433901} Vampiric Strike talent vs proc 433899 (line 90); DEATHKNIGHT_3 aoe festering_strike {buff 455397} Festering Scythe talent vs buff 458123 (line 101). Effect: intended promotions (Death Coil on Sudden Doom, Scourge Strike on Vampiric Strike proc, Howling Blast on Rime, Blood Boil during DRW) never fire. Partially masked for Rime/KM/Sudden Doom by Blizzard's native activation overlay (IsSpellProcced), NOT masked for the San'layn procs. Flip-risk: if the duration probe ever reports permanent passive auras as active, these become PERMANENT proc-bucket promotions (always-first suggestions). Almost certainly class-wide, not DK-specific.

*Evidence:* SpellQueue.lua:445-455 (only g.t=="buff" and not g.neg evaluated); BlizzardAPI/CooldownTracking.lua:523-532; CSV SpellName pairs: 59052/59057 Rime, 49530/81340 Sudden Doom, 51124/51128 Killing Machine, 433899/433901 Vampiric Strike, 434143/434144 Infliction of Sorrow, 455397/458123 Festering Scythe, 49028/81256 Dancing Rune Weapon, 391477/391481 Coagulopathy

*Fix:* Resolve buff.* tokens through a separate aura-name index (e.g. prefer the id that is NOT in the castable/talent-definition tiers, or cross-check SpellAuraOptions/duration data), with a curated override map for ambiguous pairs.

### [MAJOR] Unresolved-token fail-safe is actually fail-DEMOTE: dropped abilities get rank-900 sentinel and sink below every ranked spell in simc mode; DK loses Unholy Assault, Bonestorm, Tombstone, Rune Tap, Blooddrinker, Blood Tap, Anti-Magic Shell (SpellQueue.lua:470)
gen_simc_rotations.py:22-23 claims 'an ability we can't resolve simply isn't ranked and keeps AC's order (fail-safe)', but SpellQueue rankOf returns (simcRec and simcRec.rank) or 900, so an AC-offered spell absent from the SimC block sorts BELOW all ranked entries in the normal bucket. DK residue (all present in SpellName CSV yet unresolved, so this is resolver-universe gappage, not missing data): DEATHKNIGHT_3 unholy_assault 207289 (a rotational DPS cooldown, cds/cds_san lists) and legion_of_souls (token has NO SpellName row at 12.1.0.68301 - likely renamed); DEATHKNIGHT_1 bonestorm 194844, tombstone 219809, rune_tap 194679, blooddrinker 206931, blood_tap 221699 (bonestorm/tombstone are real Deathbringer/San'layn rotation pieces); DEATHKNIGHT_1/2/3 antimagic_shell 48707. If AC recommends Unholy Assault or Bonestorm, simc mode buries it behind fillers like festering_strike (rank 11) / deaths_caress (rank 12).

*Evidence:* SpellQueue.lua:468-470 'return (simcRec and simcRec.rank) or 900'; gen_simc_rotations.py:22-23; DEATHKNIGHT_1 block (lines 20-33) and DEATHKNIGHT_3 block (68-106) lack these ids; CSV hits: 207289 'Unholy Assault', 194844 'Bonestorm', 219809 'Tombstone', 194679 'Rune Tap', 206931 'Blooddrinker', 221699 'Blood Tap', 48707 'Anti-Magic Shell'; 'Legion of Souls' absent

*Fix:* Either treat unranked spells as neutral (rank between ranked and sink, or fall back to ContextRank) in simc mode, or curate the missing DK tokens in CURATED; fix the universe gap that misses these class/hero talents.

### [MAJOR] Entry-level active_enemies conditions are silently discarded (no gate, no delegation, no tier filter) - entries leak into wrong target tiers (tools/gen_simc_rotations.py:122)
classify_atom returns (None, False) for spell_targets/active_enemies atoms 'handled by the tier split', but the tier split (call_applies) only filters call_action_list conditions, never entry if= conditions. An entry whose only condition is a target-count is emitted ungated, un-delegated, in every tier. Warlock instances: WARLOCK_2 st bilescourge_bombers (apl 'if=active_enemies>1') ranked 8 in SINGLE TARGET with gates={} and no delegated flag - queue ranks Bilescourge Bombers 8th at 1 target where the APL forbids it; WARLOCK_3 cleave rain_of_fire (havoc list 'if=active_enemies>=3') ranked 8 at 2 targets, not delegated so the shard spender also never starve-sinks; WARLOCK_1 aoe agony rank 4 from the '>10 enemies' line 81. It also flattens Demonology's tier differences to nothing, which is why WARLOCK_2 has no aoe list at all (implosion/BB AoE logic lost).

*Evidence:* gen_simc_rotations.py:122-123 'return None, False  # target count -> handled by the tier split' vs call_applies used only at line 190 for call_action_list. Data/SimcRotations.lua:829 {id=267211,gates={}} bilescourge_bombers in WARLOCK_2 st (source warlock_demonology.simc:45); Data/SimcRotations.lua:860 {id=5740,gates={}} rain_of_fire in WARLOCK_3 cleave (source warlock_destruction.simc:141 inside havoc list); Data/SimcRotations.lua:807 agony (source warlock_affliction.simc:81 active_enemies>10).

*Fix:* In make_entry, evaluate target-count atoms against the current tier k (pass k down): drop the entry from tiers where the count condition fails, keep it gate-free where it holds.

### [MAJOR] Wither emitted as 445465 everywhere in SimcRotations while every other Data table uses cast id 445468 - wither rank likely never matches at runtime (moonfire 8921/326646 pattern) (Data/SimcRotations.lua:779)
WARLOCK_1 (st 779, cleave 792, aoe 815) and WARLOCK_3 (st 842, cleave 857, aoe 876) emit wither entries and {t="dot",id=445465} gates with 445465 (the Hellcaller talent id), but the addon's canonical cast id for Wither is 445468 (Data/TargetDots.lua:86, Data/SpellArchetypes.lua:2429). RotationImport.BuildLookup keys m[445465] and m[FindSpellOverrideByID(445465)]; if AC hands the castable 445468 (and FindSpellOverrideByID of a talent-node id doesn't chain to it), GetEntry misses and Wither sinks to the unranked 900 bucket in simc mode - WARLOCK_3 st rank 5 and WARLOCK_1 st rank 6 are inert for Hellcaller builds. The dot-gate id 445465 is additionally not a TargetDots key (dead in /jac inspect gate display). The runtime dot-SINK is unaffected (it keys the queue's own display id, and TargetDots has 445468).

*Evidence:* SimcRotations.lua:779,792,815,842,857,876 id=445465; TargetDots.lua:86 '[445468]=18,  -- Wither'; SpellArchetypes.lua:2429 '[445468]'; RotationImport.lua:104-108,146 lookup by id/override only.

*Fix:* Make the bridge resolver prefer the override/cast id over the talent-definition id for tokens that are castable replacements (cross-check emitted ids against TargetDots/SpellArchetypes in the generator's report), or add wither:445468 to CURATED for both warlock specs.

### [MAJOR] Buff-window gate ids resolve to TALENT ids, not the proc AURA ids IsBuffWindowActive probes - warlock buff-window promotion is inert (Data/SimcRotations.lua:777)
BlizzardAPI.IsBuffWindowActive (BlizzardAPI/CooldownTracking.lua:523-532) calls C_UnitAuras.GetPlayerAuraBySpellID(g.id), so the gate id must be the aura's spell id. The generator's resolve() returns the talent-definition id: nightfall=108558 (proc aura is 264571), tormented_crescendo=387075 (aura 387079), decimation=387176 (aura differs), backdraft=196406 (aura 117828). None of these ids ever appear as a player aura, so SimcBuffWindowActive (SpellQueue.lua:445-455) never fires for WARLOCK_1 haunt/shadow_bolt (777, 781) or WARLOCK_3 soul_fire (841) - the 'promote inside the window' feature is silently dead for warlock. (Aura-id pairs asserted from spell data; confirm in-game with GetBuffWindowSnapshot.)

*Evidence:* SimcRotations.lua:777 {t="buff",id=108558} haunt; 781 shadow_bolt buff 108558+387075; 841 soul_fire buff 387176; 853/872 conflagrate buff 196406 (neg, unused). CooldownTracking.lua:528 GetPlayerAuraBySpellID(spellID). Data/SelfAuras.lua contains none of these ids (only 1214920 'Nightfall Skyreaver', unrelated).

*Fix:* Resolve buff.<token> against the aura universe (SpellName rows reachable as auras / a curated talent-to-proc-aura map) rather than the castable/talent universe; add a generator report line for buff-gate ids that are talent-only.

### [MAJOR] Unanchored re.match truncates comparison atoms: buff.X.react<N / react=N / cooldown.X.remains>N become plain boolean gates with inverted meaning (tools/gen_simc_rotations.py:112)
classify_atom's regexes have no end anchor, so 'buff.nightfall.react<2-prev_gcd.1.drain_soul' (haunt, apl line 46 - meaning FEWER than 2 stacks, including zero) matches the buff-up pattern and becomes a positive {t=buff,id=108558} gate; 'buff.tormented_crescendo.react<buff.tormented_crescendo.max_stack' (shadow_bolt, line 52 - 'not capped') becomes a positive TC-up gate: once the aura-id bug above is fixed, haunt would promote only when Nightfall IS up and shadow_bolt would promote on a Tormented Crescendo proc - exactly when the APL wants Malefic Rapture instead. 'cooldown.soul_rot.remains>5' (soul rot ON cooldown) likewise becomes a bare {t="cd"} gate displayed as own-cd-ready. Currently masked by the dead aura ids, but it is the latent wrong-promotion bug.

*Evidence:* gen_simc_rotations.py:107-118 (re.match, no $); SimcRotations.lua:777, 781. Source warlock_affliction.simc:46,52.

*Fix:* Anchor the atom regexes (fullmatch or trailing $ with optional comparison capture) and delegate any atom containing a comparison operator against stacks/remains.

### [MINOR] parse_apl merges the top-level 'actions=' list with 'actions.main=' under one name - correct for PRIEST_3 only by coincidence (tools/gen_simc_rotations.py:71)
parse_apl assigns lname='main' both to ungrouped 'actions=' lines and to 'actions.main=' lines (gen_simc_rotations.py:68-71), concatenating two distinct SimC lists. For priest_shadow the top-level list (lines 25-27) precedes actions.main in file order and ends with run_action_list,name=main (which walk() no-ops via the visited set), so the merged order happens to equal the intended 'aoe-call then main entries' semantics. Any APL whose top-level list has actions after a run_action_list, or that calls 'main' from a sublist, would silently interleave/mis-order without any error. Systemic latent hazard, no PRIEST_3 output defect.

*Evidence:* gen_simc_rotations.py:71 'lname = m.group(1) or "main"'; priest_shadow.simc:25-27 vs 74+ both land in lists['main']; flatten visited-set at gen_simc_rotations.py:184-190 makes the self-call a no-op.

*Fix:* Name the ungrouped list something reserved (e.g. '__root__') and start walk() there.

### [MINOR] Dot gates carry the CAST id or no id at all (outbreak/wild_mushroom {t="dot"} with no id) because dot.<aura> tokens go through the castable-spell resolver - currently inert since no runtime consumer reads t="dot" gates (tools/gen_simc_rotations.py:108)
classify_atom maps 'dot.X.(refreshable|ticking|remains)' to {'t':'dot','id':resolve(X)} (:108-110), but X is a DEBUFF name resolved through the CASTABLE-universe resolver: when the aura name differs from the cast token (virulent_plague for outbreak, fungal_growth for wild_mushroom) resolve returns None and gate_lua (:203-209) drops the falsy id, emitting the malformed '{t="dot"}' (SimcRotations.lua:88 outbreak DEATHKNIGHT_3 cleave, :163/:177 wild_mushroom); when it matches the cast token (own-dot, :127 and :172-173) the gate id is the cast id (93402, or the wrong 326646 per finding 2), not the aura id. Whether this 'matters at runtime': grep shows t='dot' gates are consumed NOWHERE functionally - SpellQueue's only gate consumer is SimcBuffWindowActive (t=='buff', SpellQueue.lua:445-453); the actual dot sink uses DotTracker.IsDotActiveOnCurrentTarget(displayID) (:539-540) keyed by TargetDots CAST ids, bypassing the gate entirely. Only DebugCommands.lua:1575-1578 displays them (and calls IsDotActiveOnCurrentTarget(g.id) - nil-safe, but for the idless gates it always prints 'refresh', and for 326646 always 'refresh': misleading diagnostics). So today these are meaningful only as a 'has a dot condition' marker; note that IF a future gate layer consumes them, cast-id keying is actually the CORRECT key for DotTracker - the broken cases are the idless gates and the mis-resolved 326646. Related same-classifier nit: 'cooldown.<other_spell>.remains>N' comparisons collapse to an id-less {t='cd'} gate (aoe force_of_nature, SimcRotations.lua:172) which DebugCommands interprets as the entry's OWN readiness (DebugCommands.lua:1573 uses e.id) - semantically wrong, also display-only today.

*Evidence:* SimcRotations.lua:88 '{id=77575,gates={{t="dot"}},delegated=true},  -- outbreak' (from deathknight_unholy.simc:93 'dot.virulent_plague.refreshable' atom, resolve('virulent_plague')=None); :163 wild_mushroom idless dot from 'dot.fungal_growth.remains<2' (druid_balance.simc:123/162). Repo-wide grep for '.gates': only SpellQueue.lua:448 (buff only), RotationImport.lua:105 (pass-through), DebugCommands.lua:1567/1571 (display).

*Fix:* In classify_atom, resolve dot.X against a debuff/aura name index (or emit {'t':'dot','name':X} and let a curated aura map fill ids); never emit a dot gate without an id - fall back to delegated=True instead. Keep own-dot gates on the cast id deliberately (matches DotTracker keying) and document that choice in the generator header.

### [MINOR] gen_simc_rotations.py --spec overwrites the full Data/SimcRotations.lua with a single-spec file (tools/gen_simc_rotations.py:321)
main() unconditionally writes out_path (:321-327) with only the specs that survived the --spec filter (:293-294). Running the documented debug invocation 'python tools/gen_simc_rotations.py --spec druid_feral' clobbers the shipped Data/SimcRotations.lua, silently deleting the other 33 specs' rotations (an addon-data regression that only shows up in-game on another class). Verified by running with SIMC_OUT redirected: the single-spec output file contains exactly one spec block.

*Evidence:* gen_simc_rotations.py:321 'out_path = os.environ.get("SIMC_OUT") or os.path.join(ROOT, "Data", "SimcRotations.lua")' with no --spec guard before the write at :326-327.

*Fix:* When --spec is set, default the output to stdout/scratch (or require SIMC_OUT), or merge the regenerated spec into the existing file instead of replacing it.

### [MINOR] Custom-queue item entries hardcoded normalRank=1 outrank nearly everything in simc mode (SpellQueue.lua:493)
Item entries get normalRank[n]=1 'items: neutral' (SpellQueue.lua:490-494). Neutral is correct for 'ac' mode (ContextRank range 0-9, 1 sits low-middle) but in 'simc' mode ranks are list indices (1..~17) plus the 900 sentinel, so an item ties with the #1 priority ability and sorts ahead of every rank>=2 spell. A user running a custom queue with an on-use item under simc ordering sees the item pinned to slot 2.

*Evidence:* SpellQueue.lua:493 'normalRank[normalCount] = 1  -- items: neutral' vs rankOf() semantics at :467-475 (simc rank = list index, unranked = 900).

*Fix:* Rank items with rankOf()'s neutral for the active mode: 1 in 'ac', 900 (or keep source order via a mid sentinel) in 'simc' - one conditional on simcMode.

### [MINOR] RotationImport id bridge resolves only base->override (FindSpellOverrideByID); an override-id queue entry against base-keyed data (or vice versa) misses and falls to 900 (RotationImport.lua:90)
The comment (RotationImport.lua:85-87) says ids are matched 'by talent-base id', but baseID() calls BlizzardAPI.ResolveSpellID = FindSpellOverrideByID (BlizzardAPI/SpellQuery.lua:365-373), which maps base->current-override only. BuildLookup keys e.id plus its override (RotationImport.lua:107-108) and GetEntry retries m[FindSpellOverrideByID(spellID)] (line 146). If AC's rotation list hands an override id while the data holds the base id of a family whose override chain FindSpellOverrideByID doesn't surface (or C_Spell.GetBaseSpell-only relationships like 155625->8921), neither direction matches and the spell drops to the 900 sentinel. DotTracker solved the same problem with SpellDB.GetBaseSpell (DotTracker.lua:50-52); RotationImport never consults it.

*Evidence:* RotationImport.lua:90-93,146; SpellQuery.lua:365-373 (override direction only); contrast DotTracker.lua:50-52 and SpellDB.lua:198-208 (GetBaseSpell direction).

*Fix:* In GetEntry, add a third probe m[SpellDB.GetBaseSpell(spellID)] (and key BuildLookup by GetBaseSpell(e.id) too) - mirrors the DotTracker pattern; cache already invalidated on SPELLS_CHANGED.

### [MINOR] Dead debuff-keyed rows in TargetDots and st-only /jac why SimC rank make diagnostics lie (Data/TargetDots.lua:41)
(a) Data/TargetDots.lua contains rows keyed by DEBUFF aura ids that are never UNIT_SPELLCAST_SUCCEEDED cast ids (164812 Moonfire, 164815 Sunfire, 55078 Blood Plague, 55095 Frost Fever, ...): they enter via gen_target_dots.py:170-172 ('cast IS a dot aura' branch) because the aura ids leak into the learnable 'universe'. Harmless at runtime but they masked finding 1 - the file LOOKS like it covers Sunfire. (b) /jac why prints the SimC rank from GetEntry(spellID) with no context argument (DebugCommands.lua:634), so it always reports the st rank even when the live build used the aoe/cleave list. (c) /jac inspect gates evaluates dot gates via DotTracker.IsDotActiveOnCurrentTarget(g.id) (DebugCommands.lua:1576-1578) where g.id is a data-domain id (e.g. 326646) that can never match DotTracker's cast/display/base keys - always shows 'refresh'.

*Evidence:* Data/TargetDots.lua:41-42 (164812/164815 as keys); gen_target_dots.py:170-172; DebugCommands.lua:634, 1576-1578.

*Fix:* (a) In gen_target_dots.py, drop 'direct' rows whose spell is not a real cast (e.g. require presence in SkillLineAbility/SpecializationSpells SpellID as a castable, or simply intersect with names present as buttons) or at least comment them as aura-side; (b) pass the live simcCtx into the /jac why GetEntry call; (c) resolve dot-gate ids through GetBaseSpell before querying DotTracker in the gate display.

### [MINOR] Systemic: {t='cd'} gates discard the referenced spell id AND the negation; runtime ignores cd and dot gates entirely (tools/gen_simc_rotations.py:106)
classify_atom returns bare {'t':'cd'} for cooldown.X.(ready|up|remains) - losing WHICH cooldown (usually a different spell: e.g. MONK_3 blackout_kick's gate is from cooldown.fists_of_fury.remains; invoke_xuen's from cooldown.strike_of_the_windlord.remains<3) and whether the atom was negated ('!cooldown.X.remains' = ready vs 'remains>10' = not ready both emit the same gate). Today SpellQueue reads only buff gates (promotion) and delegated (starve sink); cd and dot gates are dead data, so no visible harm - but any future cd-gate evaluator would inherit wrong-spell/inverted semantics. The dot sink is TargetDots/DotTracker-driven, independent of {t='dot'} gates.

*Evidence:* gen_simc_rotations.py:106-107 (no id, neg discarded); SpellQueue.lua:445-455 (buff-only), 536-540 (dot sink via DotTracker, not gates); Data/SimcRotations.lua:495,499,503-505,515-527 bare {t='cd'} instances.

*Fix:* Emit {t='cd', id=<resolved>, neg=<bool>} or drop cd gates until an evaluator exists.

### [MINOR] Cross-table ID sanity (spotted in passing): Data/SpellCategories.lua lists 375087 as 'Dragonriding abilities' in UTILITY_SPELLS, but 375087 is Dragonrage (Data/SpellCategories.lua:545)
The addon's own SpellCooldowns.lua:872 names 375087 'Dragonrage' (120s cd) and the SimC gates use it as the Dragonrage buff. Its presence in UTILITY_SPELLS makes SpellDB.IsOffensiveSpell(375087) false, which blocks Dragonrage from the proc-overlay insertion path (SpellQueue.lua:291). Main rotation path is unaffected, so impact is limited to a suppressed proc-glow insertion.

*Evidence:* Data/SpellCategories.lua:545 ('[375087] = true,  -- Dragonriding abilities') vs Data/SpellCooldowns.lua:872 ('[375087]=120000,  -- Dragonrage'); SpellDB.lua:694-702; SpellQueue.lua:291

*Fix:* Remove 375087 from UTILITY_SPELLS (or replace with the actual dragonriding spell id that was intended).

### [MINOR] Systemic classifier semantics collapse: negation dropped on dot/cd atoms, and cross-spell/comparison cooldown expressions become a bare own-cd {t='cd'} gate (tools/gen_simc_rotations.py:106)
classify_atom: (a) dot atoms ignore negation - '!dot.rake.refreshable' (druid_guardian.simc:50, DRUID_3 shred) and 'dot.X.refreshable' emit the identical positive {t='dot'} gate, inverting intent; (b) the cd regex prefix-matches comparisons and other spells' cooldowns - 'cooldown.rage_of_the_sleeper.remains<=52' (guardian shred) and 'cooldown.convoke_the_spirits.remains>cooldown.force_of_nature.duration-10' (balance aoe force_of_nature, SimcRotations.lua:172) both become a plain {t='cd'} carrying no spell id, i.e. 'own cooldown' semantics. All of this is dead data today (dot/cd gates unevaluated at runtime) but is wrong-by-construction if the gate layer ever grows dot/cd evaluation.

*Evidence:* gen_simc_rotations.py:106-110 (no neg on cd/dot); Data/SimcRotations.lua:231 shred gates '{t="cd"},{t="buff",id=768,neg=true},{t="dot",id=1822}' vs source '!dot.rake.refreshable'; SimcRotations.lua:172 force_of_nature '{t="cd"}'.

*Fix:* Carry neg on dot gates, restrict the cd regex to '.ready|.up' (or anchored full-match) and delegate remains-comparisons, or store the referenced spell id on cd gates.

### [MINOR] Systemic: split_and runs before OR detection, so atoms from one OR-disjunct become hard gates that are not necessary conditions (SimC precedence A&B|C&D = (A&B)|(C&D)) (tools/gen_simc_rotations.py:84)
split_and splits the whole if= on top-level '&' even when top-level '|' is present, so in 'A&B|C&D' atoms A and D are classified as gates although neither is necessary. Rogue instance: ROGUE_2 adrenaline_rush gate {t=buff,id=13750,neg=true} from '!buff.AR.up&(...)|buff.AR.up&talent.improved_adrenaline_rush&combo_points<=2&(...)|fight_remains<2' - the neg gate contradicts the improved-AR recast branch (buff UP). Currently harmless because neg gates are runtime-dead, but any future gate-evaluator work will inherit wrong data.

*Evidence:* gen_simc_rotations.py:84-96; Data/SimcRotations.lua:636.

*Fix:* If the expression contains a top-level '|', classify the whole thing as delegate (no gates) unless every disjunct shares the atom.

### [MINOR] cold_blood unresolved in all three rogue specs (tools/gen_simc_rotations.py:53)
Residue in ROGUE_1/2/3; Cold Blood is an off-GCD utility cd so being unranked (rank 900) barely shows, but it is a curatable one-liner.

*Evidence:* Generator report residue lines for all three rogue APLs; probe candidates=[] in every rogue spec universe.

*Fix:* Curate cold_blood (382245) if it should be ranked; otherwise add to SKIP as off-gcd.

### [MINOR] Emitted gate types cd/dot/execute/neg-buff are never evaluated at runtime - only positive buff gates and the delegated flag do anything, so 'correct' gates like Unholy soul_reaper's {t=execute} are dead data (SpellQueue.lua:445)
SimcBuffWindowActive checks only g.t=='buff' and not g.neg; nothing consumes {t='cd'}, {t='dot',id=..}, {t='execute'}, or negated buff gates outside the /jac inspect display (DebugCommands.lua:1567-1590). Consequences in the DK data: DEATHKNIGHT_3 st soul_reaper's correctly-captured {t=execute} (line 78) does not keep it out of the queue pre-execute (mild there, rank 10; the harm concentrates in Blood/Frost where soul_reaper additionally lost its gates - see the critical findings); vampiric_blood/death_and_decay/breath_of_sindragosa neg gates (lines 21,28,41,55) are inert - and the death_and_decay gate id 43265 would be wrong anyway (the standing-in-DnD player buff is 188290, CSV-confirmed pair). This bounds every gate-loss finding: rank position and TargetDots sinking are the only order-active mechanisms today.

*Evidence:* SpellQueue.lua:445-455, 515-531; grep shows no other consumer of gates except DebugCommands display; CSV 43265/188290 'Death and Decay'

*Fix:* Wire execute gates to the existing ctxExecute machinery and dot gates to DotTracker in simc mode, or stop emitting unevaluated gate types until the gate layer lands.

### [MINOR] Data/TargetDots.lua Frost Fever and Blood Plague entries keyed by AURA id instead of a castable id - dead rows that can never match a cast (same class as the DRUID_1 Sunfire observation) (Data/TargetDots.lua:31)
[55095]=24 Frost Fever and [55078]=24 Blood Plague are the disease AURA ids; no player cast has those ids (applicators are Howling Blast 49184 / Blood Boil 50842 / Death's Caress 195292), so DotTracker.OnCastSucceeded/IsDotActiveOnCurrentTarget can never key them - dead data. Unlike the druid Sunfire case this deadness is arguably protective (sinking Howling Blast whenever Frost Fever is live would suppress the Rime spender), but the rows should either be removed or the generator taught the applicator mapping deliberately. Note Outbreak IS correctly keyed by cast id (line 33, [77575]=24), which is why the Unholy outbreak gate losses (SimcRotations lines 75/88/100) do NOT reproduce the Balance symptom - the dot-sink covers it independently.

*Evidence:* Data/TargetDots.lua:30-31,33; gen_target_dots.py output comment 'applicator cast spells -> debuff duration'; CSV 55078/55095 are the disease auras

*Fix:* Have gen_target_dots.py emit only castable applicator ids (or an explicit cast->aura map) and drop aura-id rows.

### [MINOR] Wither (Warlock) token resolves to spell 445465 which is absent from Data/TargetDots.lua - possible parallel dot-sink gap (unconfirmed, flagged for spot-check) (Data/TargetDots.lua:86)
A name-collision scan of Data/TargetDots.lua against the generator's own 'universe' set (SkillLineAbility + TraitDefinition + SpecializationSpells) found several TargetDots.lua entries sharing a SpellName with another universe-member id that is NOT a table key (list: Corruption 172/16985, Entangling Roots 339/343238, Immolate 348,118297/193541, Rupture 1943/1249804, Frost Fever 55095/195621, Siphon Life 63106/452999, Touch of Karma 124280/122470, Steel Trap 162487/162488, Sunfire 164815/93402,27981 - see the confirmed critical finding above, Conflagration 205023/1271171, Odyn's Fury 205545,205546,385059/205547,1223156, Soul Carver 207407/214743, Ashamane's Frenzy 210723/210722, The Hunt 323639/370965,1246167, Wither 445468/445465). Most of these are very likely legitimate cross-context duplicates (NPC-cast, PvP-rank, item-effect or pre-squish variants) that are NOT actual gaps, and were NOT individually root-caused within this audit's scope. Wither stands out because Data/SimcRotations.lua independently resolves the 'wither' SimC token to spell id 445465 for (at least) two Warlock rotation contexts (Data/SimcRotations.lua:815,857,876: '{id=445465,gates={{t="dot",id=445465}}}'), while Data/TargetDots.lua's only Wither entry is keyed on a DIFFERENT id, 445468 (curated via gen_target_dots.py:69 as '445468: 445474' with the same 'stacking false positive' rationale as Agony/UA). If 445465 is the id actually observed via UNIT_SPELLCAST_SUCCEEDED for the Warlock spec(s) in question, this would be the same class of defect as the Sunfire finding (cast id present in the SimC universe/rank data but absent from TargetDots.lua's cast-keyed table) - but this was not traced through SpellEffect/SpecializationSpells to confirm which spec(s) cast 445465 vs 445468, nor whether they are in fact the same ability under different spec-specific ids (in which case both being present, as with Moonfire's 8921+164812, would be correct and no fix is needed).

*Evidence:* TargetDots.lua/SimcRotations.lua name-collision scan (ad hoc script over SkillLineAbility/TraitDefinition/SpecializationSpells 'universe' + Data/TargetDots.lua current keys); Data/TargetDots.lua:86 '[445468]=18, -- Wither (stacking false positive)'; gen_target_dots.py:69,78 (CURATED[445468]=445474); Data/SimcRotations.lua:815,857,876 (id=445465 for token 'wither')

*Fix:* Not a confirmed defect - recommend a targeted follow-up: pull SpellEffect/SpecializationSpells rows for 445465 and 445468 to determine whether they are the same spec's cast-vs-aura pair (needing the same 93402-style curation) or genuinely different specs' abilities (no action needed). Do not edit Data/TargetDots.lua by hand regardless - any fix goes through tools/gen_target_dots.py's CURATED dict + regeneration.

### [MINOR] Data mirrors disagree on Flame Shock's spell id: 12.1-generated tables use 470411, hand/role/archetype tables still key 188389 (Data/SpellArchetypes.lua:1616)
Generated-from-12.1 tables (TargetDots:89, SpellCooldowns:1038, SimcRotations) all use 470411, which SkillLineAbility confirms is the currently-learned cast id. SpellArchetypes' archetype table has [188389]="ranged" (line 1616) and the Roles table [188389]=true (line 2794) under the superseded id. In the DEFAULT "ac" ContextRank mode these lookups run per queue spell; StaticLookup does have a C_Spell.GetBaseSpell fallback (SpellDB.lua:178-186), which rescues this only if the client maps 470411->188389 - unverified offline. If it does not, Flame Shock is archetype/role-untagged for shaman in ac mode.

*Evidence:* Data/SpellArchetypes.lua:1616 [188389]="ranged", 2794 [188389]=true (Roles table, registered at 2704); Data/TargetDots.lua:89 and Data/SpellCooldowns.lua:1038 use 470411; SkillLineAbility CSV grants 470411

*Fix:* Regenerate/patch the archetype and role tables to 470411 (or verify GetBaseSpell(470411)==188389 in-game and note the reliance).

### [MINOR] {t="cd"} gates drop both the referenced spell and the ready/not-ready sense (tools/gen_simc_rotations.py:106)
Every cooldown.X.(ready|up|remains) atom collapses to a bare {t="cd"} with no id and no polarity. Warlock examples: WARLOCK_1 st shadow_bolt's gate is from 'cooldown.soul_rot.remains>5' (soul rot ON cd), WARLOCK_2 st grimoire_felguard's from tyrant/dreadstalker cds, WARLOCK_3 st malevolence's from 'cooldown.summon_infernal.remains>=55' (infernal NOT ready) - /jac inspect renders all of these as the entry's OWN readiness (DebugCommands.lua:1573 IsSpellReady(e.id)), which is a different spell and sometimes the inverted sense. Diagnostics-only today.

*Evidence:* gen_simc_rotations.py:106-107; SimcRotations.lua:781,824,838; DebugCommands.lua:1572-1574.

*Fix:* Emit {t="cd",id=resolve(name),neg=<sense>} and evaluate/display against that id.

### [MINOR] Unresolved tokens silently unranked: oblivion (WARLOCK_1), infernal_bolt (WARLOCK_2, WARLOCK_3) (tools/simc-apl/warlock_affliction.simc:62)
oblivion (affliction lines 62, 143) and infernal_bolt (demonology 52/56, destruction 64/86/129) appear in the APLs but are absent from all generated WARLOCK blocks - unresolved residue, so they keep AC order (fail-safe by design). Worth curating since infernal_bolt is a rotational Diabolist filler and oblivion a talent spender; on Diabolist builds these spells sit unranked below all ranked entries in simc mode.

*Evidence:* No 'oblivion'/'infernal_bolt' comment in Data/SimcRotations.lua WARLOCK blocks (772-886) despite APL presence.

*Fix:* Add oblivion/infernal_bolt ids to CURATED for the warlock specs (mirroring the DRUID_2 residue pattern).

### [MINOR] Systemic: cd gates never record WHICH cooldown the APL referenced, so every {t=cd} silently degrades to 'this entry's own cd' in diagnostics (tools/gen_simc_rotations.py:106)
classify_atom returns bare {"t":"cd"} for 'cooldown.<spell>.<ready|up|remains>' discarding <spell>. Warrior examples: warbreaker st gate (Data/SimcRotations.lua:898) is really avatar's cooldown (warrior_arms.simc:76,93); champions_spear Fury gate (:967) is bladestorm's cooldown (warrior_fury.simc:50); ignore_pain (:988) is shield_slam's. Runtime-inert (cd gates unused by SpellQueue), but /jac inspect simc (DebugCommands.lua:1572-1574) evaluates them via IsSpellReady(e.id) -- the entry's own cd -- reporting a condition the APL never expressed, and it also drops the polarity (remains>14 = must be ON cd vs .ready = must be OFF cd).

*Evidence:* gen_simc_rotations.py:106-107; DebugCommands.lua:1572-1574.

*Fix:* Emit {t="cd", id=resolve(name), neg=<polarity>} and make the inspector honor it; or stop emitting cd gates until a consumer exists.

