
# Changelog

## [Unreleased]

## [5.1.3] - 2026-08-11

### Fixed
- Crowd control is suggested again when an enemy is casting something you cannot interrupt. Game patch 12.1.0 moved the part of the interface this reads, and without it your kick was suggested instead and then correctly hidden - so you heard the alert with nothing to press
- The interrupt alert no longer sounds for a suggestion you cannot see. It now only plays when the icon is certain to be visible
- Resource tracking works for players whose unit frames are replaced by another addon. It was meant to fall back to the game's personal resource display, and that fallback had never actually been reachable

### Changed
- The enrage cleanse cue is back, and plainer than it was: the icon and its keybind, without the countdown swipe or the pulsing glow. Game patch 12.1.0 removed every way an addon could watch an enemy's buffs directly, and the replacement the game provides can show the cue but not decorate it. The timing is unchanged - it appears the moment an enemy enrages and clears when the enrage ends

## [5.1.2] - 2026-08-11

### Fixed
- Game patch 12.1.0 changed what an addon may read about buffs during a fight, and JustAC was still asking the old way in several places. That caused errors in combat and could leave the queue blank or stop it updating. The queue, damage-over-time tracking and the tank maintenance slot all work again
- Some settings showed an error instead of their description, and the Cooldown Manager settings described precision the game no longer allows. Both read correctly now

### Changed
- Tanks: the flare for a dropped mitigation buff no longer needs Blizzard's Cooldown Manager turned on, so the two-stage cue works out of the box. With it on you still get the sharper version, which also catches an absorb used up early
- Around forty more abilities are ranked against the pull instead of sitting neutral. Ones that deal their damage through a follow-up effect - Frostbolt, Execute, Fury's Whirlwind and more - were not being recognised as damage at all
- The enrage cleanse cue no longer appears in combat. Game patch 12.1.0 closed every way to tell which buff on an enemy is an enrage, so it stands down rather than risk being wrong, and returns if a way back opens

## [5.1.1] - 2026-08-11

### Fixed
- A sweep of every built-in suggestion list against the current game data turned up entries that could never appear - abilities the game no longer grants under that name, and abilities that are now passives rather than something you press. Each one quietly held a slot open for a button you can't press. Affected Blood Death Knights, Protection Paladins, Warlocks, Vengeance Demon Hunters, Hunters and Evokers in the defensive lists; Holy Priests (Circle of Healing), Restoration Druids (Grove Guardians) and Discipline Priests (Rapture) in the healer suggestions; and the emergency group heal for Restoration Druids and Mistweaver Monks. All now point at the live ability, or are gone where there no longer is one
- Preservation Evokers: Dream Breath is suggested as the version you actually cast
- Unholy Death Knights: the burst reminder never lit up for Dark Transformation, because it was watching a version of the ability that no longer exists
- Warlocks: the Succubus is summoned as Sayaad now, so the pet summon reminder works again
- Divine Protection (Paladin) and Death Pact (Death Knight) are now treated as what they are - a major damage-reduction cooldown and a big instant heal - so they rise when you're in trouble instead of sitting among the routine fillers. Sacrificial Pact joins them
- Feral Druids: Regrowth no longer sits above Renewal in the defensive list. Renewal is instant and Regrowth is a cast, and the faster button should come first

### Changed
- Translations are complete again in every supported language. The options rework had left around fifty labels showing English to everyone else; German, French, Italian, Russian, Spanish, Portuguese, Korean and both Chinese locales are caught up
- The Warlock pet heal reminder has been retired. Health Funnel is gone from the game and nothing has replaced it, so the cue could never appear - it returns the moment a Warlock pet heal exists again. Hunter pet heals are unaffected

## [5.1.0] - 2026-08-11

### Added
- Updated for game patch 12.1.0, including this patch's spell, talent and consumable changes, and refreshed rotation priorities
- Group buff reminders now also follow the game's own raid-buff list, so a buff your class gains in a future patch is picked up without waiting for an addon update
- Group Heal Suggestions no longer need the game's party health alert switched on, and no longer stop at the first four party members. An ally who has taken meaningful damage counts toward an area heal, and one in serious trouble raises the emergency cue on their own. Where that alert is the only signal available, it is still used automatically
- "Set Up The Alert For Me" (Defensive Queue tab, with Group Heal Suggestions): one click configures the game's party health alert the way group heals need it - on, watching for allies below 50%, and silent - instead of sending you into the Accessibility settings to do it by hand. It says exactly what it changes, remembers what you had, and puts it back when you switch it (or Group Heal Suggestions) off

### Fixed
- The between-pulls heal reminder no longer flickers, and no longer turns invisible while you are hurt. It is now an ordinary suggestion icon - fully visible for as long as it is up

### Changed
- The between-pulls heal reminder now honors its Top-Off Threshold anywhere in the world: it appears once you are below the percentage you set, and clears as soon as you are back above it. It also waits a couple of seconds before appearing, so a scratch that heals on its own never makes it pop up
- A free-heal proc (Clearcasting and friends) no longer glows at you, or pushes its way to the front of the defensive queue, while you are at full health and nobody in the party needs healing - both return the moment there is actually something to heal. Other procs are unchanged
- The pet heal cue now appears only while your pet is below your Pet Heal Threshold, and steps aside otherwise - leaving the slot beside the queue free for whatever else needs it
- Execute abilities rise in the queue as soon as your target is low enough to be worth finishing
- Rotation ordering now understands priorities that depend on how many stacks of a buff you are holding, so abilities that want a specific stack count stop being suggested before you have it
- Tanks: the "refresh your mitigation" cue now lands at the right moment on talent-extended buffs, and no longer warns you early. It also arrives in two stages - a marching-ants ring a few seconds before the buff lapses, brightening into a full glow if you let it drop - so a warning you can safely finish your cast through looks different from one you cannot
- Damage-over-time abilities come back for refreshing at the right moment. Keeping a DoT rolling no longer makes its refresh cue creep earlier and earlier the longer you maintain it, and haste and talents are accounted for automatically
- Big offensive cooldowns stop being suggested - and stop glowing as ready - when the one enemy still fighting you is nearly dead. Nothing is hidden, so you can still press them; they simply stop being pushed at you for the last few seconds of a mob's life. Bosses are exempt, because that is exactly when you should be spending everything
- Defensive suggestions now sort by how much trouble you are actually in, in three grades instead of two: damage reduction leads while you are taking chip damage, big heals lead once you have taken a real hit, and immunities jump the queue only when you are close to dying
- The emergency ordering of defensive suggestions - and "Hide Emergency Until Low" - now switches over closer to the health level those settings describe

## [5.0.1] - 2026-08-10

### Fixed
- Stray glows are gone. The enrage-cleanse cue's glow could outlive its enrage or arm itself before its icon was ready - leaving an empty glow floating near the queue - a proc glow could come back from the dead on entering combat after being hidden, the execute cue's orange rim could survive the queue being hidden, and the nameplate overlay could carry a stale maintenance-slot glow across a hide. A full audit of the glow system closed every one of these paths: each glow's on and off can no longer disagree
- The "party member is missing your buff" recast nudge actually works now, in both directions: it silently never fired in the open world, where the range and aura checks it relied on read as unavailable; it could nag forever at a fully-buffed party, because some raid buffs (Mark of the Wild, Arcane Intellect) carry a second identity it didn't recognize; and it counted dungeon follower companions, who can never receive player buffs, so no recast could ever satisfy it. It now asks range through the buff's own spell, matches every identity the buff can wear, and only counts real players
- The between-pulls heal reminder is more accurate in open-world groups: with the party health alert enabled, it now knows you are actually below the alert threshold instead of guessing from health regeneration alone

## [5.0.0] - 2026-08-10

### Added
- New Ability Overrides tab: search any spell or item and manage everything about it in one card - visibility (formerly the Blacklist tab), pins, item aura-linking, priority-list membership, and its hotkey label - plus a "Your Customizations" list of every ability you've changed. The Blacklist and Hotkeys tabs are retired; their settings and your existing entries all live on the card
- Healer specs now work out of the box: the queue suggests your damage rotation - the same one Blizzard's Assisted Combat drives - for soloing, delves, and dungeon downtime, with healing spells kept out of the damage slots across every healer class. A new Caster Filler toggle also keeps melee suggestions out for healers who stay at range. Characters where a healer spec was previously switched off keep that choice; a one-time hint points at the new `/jac enable` command
- Group Heal Suggestions (Defensive Queue tab, healer specs): in combat, when party members drop below the game's party health alert threshold, your group heals - the ones that heal several allies at once - join the defensive queue in a priority order you can edit. When several allies are low at once, your strongest ready group cooldown takes over the slot beside the queue as an emergency cue, holding a few seconds so it can't flicker while your heals land. Single-target heals are deliberately left out: aiming a heal at the right person is your party frames' job, and this addon never competes with them. Cast a group heal with no target and it simply lands on you, still covering the group. Needs the party health alert enabled in the game's Accessibility settings (set its volume to 0 if you would rather not hear it): that alert is the only thing an addon can know about ally health in combat, and it only says that someone crossed the line - never who, or how badly
- Paladin Auras join the pre-combat suggestions: with no Aura active, one is offered (Devotion by default) - like a rogue's poisons or a shaman's shield

### Fixed
- A talent that replaces an active ability with a passive effect no longer puts that passive in any queue - a passive can't be pressed - and the stray glow it brought along is gone; the queue moves on to your next ability
- Fixed a crash in the Burst-Ready Cue that could freeze the entire queue for a whole fight - with the cue now on by default this would have hit everyone, and it explains the queue "sticking" mid-combat for players who had it enabled
- Pre-combat poison and shield suggestions now follow Assisted Combat's own picks, in its own order - a suggestion can no longer get stuck asking for one poison while you carry another
- Gap closers no longer double up or waste themselves: after one fires, the suggestion stands down while you travel, and none are offered when the target is only barely out of melee reach - walk the last couple of steps instead. A new "Only Suggest For Real Gaps" toggle turns the distance check off
- The Disruption slot respects range: a melee kick is no longer suggested as if usable from across the room - a reachable alternative is preferred, or your interrupt shows dimmed as a reminder - and area abilities centered on you only appear when the target is confirmed inside their radius, because pressing one out of reach fires anyway and wastes the cooldown
- Dragging now picks a frame up the instant you press, and it stays exactly where you grabbed it - no more late starts, frames trailing beside the cursor, docked panels jumping when a drag begins, or accidental nudges from a press without movement
- A long list of placement fixes: everything lines up at any icon scale; the nameplate overlay reliably moves Blizzard's crowd-control displays clear of its icons, even in combat, and a blocked attempt can no longer leave badges misplaced; attaching to a target frame that another addon keeps hidden stands down and re-attaches on its own; pet bars and power bars appear and disappear promptly; the pre-combat "click" hint follows the frame while you drag it
- Smaller fixes: custom hotkey labels on items survive a reload; a group member changing talents no longer resets cooldown tracking mid-fight; a nameplate-only setup no longer inherits the main queue's visibility conditions; no more keypress error after a mid-combat reload

### Changed
- Substantially lower CPU and memory use in combat
- The options are reorganized around what they hold: one Display tab carries both display surfaces plus the Shared Behavior they follow; DPS Queue and Defensive Queue hold the two suggestion queues; Ability Overrides sits after them; General keeps the Disruption slot, input, and Blizzard UI integration. Controls that can't currently take effect grey themselves out and say why
- Simpler controls, same choices: queue ordering is now a single preset (Smart, Match Blizzard's pick, or Fixed order) with a Customize expander for mixed setups; each display is enabled with a checkbox at the top of its own page; one shared Highlight Mode covers every surface, with per-surface overrides still available; the paired grey-out and tint toggles are merged. Existing choices are preserved throughout
- Now on by default: gap-closer suggestions, and the Burst-Ready Cue (purple glow on your spec's major cooldown when a burst window is called for)
- Reset to Defaults is properly scoped: the General tab's reset no longer switches your displays on or off, and the Defensive Queue tab has its own reset button covering all its sub-tabs

## [4.59.0] - 2026-08-02

### Changed
- SimC priority is now the default ordering for the queue positions after Blizzard's pick
  (previously opt-in; specs without SimC data keep the previous ordering). If you ever
  chose an ordering yourself, your choice is kept - change it any time under
  Offensive → General → Context ordering.
- Burst Injection (experimental) has been replaced by a burst-ready cue: in combat, your
  spec's major cooldown glows purple right next to Blizzard's pick when it's actually time
  to burst - Feral's Berserk lights up during Tiger's Fury, for example, not just whenever
  it's off cooldown. Off by default - enable it under Offensive → General.
- Burst trigger spells come from SimulationCraft's burst data for your spec, and you can
  set your own list per spec under Offensive → General - your own triggers light up
  whenever they're ready, and custom triggers from the old feature carry over. Injection
  spell lists are retired.
- Rotation priorities refreshed from the latest SimulationCraft data, and all spell data
  rebuilt against the current game build - including full support for Devourer Demon
  Hunters.

### Fixed
- Two options-panel strings showed in English regardless of your game language: the spell
  search "no matches" hint and the class-name fallback in search results. Both are now
  translated.
- The nameplate overlay's Reset to Defaults now also restores Queue Visibility and Hide When
  Mounted, and the defensive resource-bar toggle now resets correctly.
- The nameplate overlay could leave a gap-closer or burst glow running on an icon after the
  overlay was switched off.
- Defensive icon glows could stay dark after the overlay was disabled and re-enabled.

## [4.58.0] - 2026-08-02

### Fixed

- **Ability names in tooltips are now the game's own.** Where a setting names an
  example ability, the name comes from the game instead of being written into each
  translation by hand - so it is correct in every language, and stays correct if an
  ability is ever renamed. Most of the translated names were wrong before this.
- **JustAC now notices when crowd control doesn't interrupt a target.** It was
  supposed to stop offering a stun or incapacitate once one had failed to stop a
  target's cast, but the check it relied on could never fire, so it kept offering
  them all fight. It now watches whether the cast actually stops, and drops CC from
  the suggestions for that enemy - and for others of the same kind - when it doesn't.
  Where the game states outright that an enemy shrugged off crowd control, that is
  remembered for good, so later pulls and later evenings skip the lesson entirely.
- **The queue no longer vanishes when a debuff takes your abilities away.** Some
  effects swap your action bar out from under you for a few seconds. JustAC treated
  that like being put in a vehicle and hid everything, right when you most wanted to
  see what to press next. The queue now stays put and greys out, and lights back up
  the moment the debuff falls off - the same way it behaves while you are stunned.
- **"In Combat Only" now really hides the defensive icons out of combat.** Free procced
  self-heals ignored the setting and stayed on screen between pulls, so the cluster never
  fully went away. With the mode set to In Combat Only - and pre-combat buffs turned off -
  nothing is shown until a fight starts.
- **Long buffs no longer reappear in the queue while they still have ages left.** A
  raid buff or poison you already had could show up as a suggestion once it passed
  30% of its total duration - eighteen minutes of nagging on a one-hour buff. It now
  waits for the same last-few-minutes window the pre-combat reminders use.

### Changed

- **A buff waiting on the defensive bar no longer shows up twice.** Out of combat,
  a missing poison, imbue or raid buff is offered on the defensive bar, where you
  can click it. It used to be listed in the rotation queue at the same time - the
  same reminder twice, and only one of them clickable. The rotation queue now
  leaves it to the defensive bar.
- **Trimmed example abilities out of some tooltips.** Settings that listed examples
  from other classes - the five tank mitigation buffs, the damage-reduction walls,
  the fear spells - no longer do. At most one ever applied to you, and the settings
  read the same without them.

### Added

- **Optional warning for dangerous casts nearby.** Off by default, under General.
  When on, a marker appears above the queue whenever any enemy around you - not
  only your target - begins casting something the game itself flags as dangerous.
  It uses the game's own judgement of which casts are lethal, so it needs no list
  of abilities and works in any dungeon or raid.
- **Italian translation.** JustAC now speaks every language the game ships in.
  Italian players previously saw the whole interface in English; every option,
  dropdown and tooltip is now translated.

## [4.57.0] - 2026-07-29

### Fixed

- **No more error when you target an enemy.** With nameplate icons on, picking an
  enemy target could throw a "failed because Can't measure restricted regions"
  error. The overlay now skips that measurement and retries on the next pass.

### Changed

- **Out-of-combat buff reminders now come back before the buff runs out.** Flasks,
  food, augment runes, weapon oils, poisons, imbues and raid buffs used to be
  re-offered only once they had lapsed entirely (or, for the class buffs, from the
  halfway mark - half an hour of nagging on a 60-minute buff). Everything now
  surfaces on the same schedule: in the last 3 minutes solo, or the last 5 minutes
  in a group, where one recast covers everyone and wants to land before the pull.
- **Korean translation updated.** Every option and tooltip is now translated, and
  a number of earlier mistranslations have been corrected. Thanks to Crazyyoungs
  for the contribution.
- **All other translations completed.** German, Spanish, French, Portuguese,
  Russian, Simplified Chinese and Traditional Chinese now cover every option and
  tooltip, including the newer pre-combat buffs, Sustain slot, crowd-control
  escape and Cooldown Manager settings. Some older wording has been refreshed to
  match what the options actually do now, and accents that had been stripped from
  a few German and French lines are back.

## [4.56.0] - 2026-07-28

### Changed

- **The gap-closer glow is now magenta.** The old pale gold sat right next to the
  game's own proc glow and read as the same cue at a glance. Magenta is the one
  colour on the offensive row that can't be mistaken for either that or the red
  interrupt glow.
- **Pre-combat suggestions stop saying "wait" once Well Fed lands.** That happens
  about ten seconds in, not when the food runs out - the buff sticks when you stand
  up, so the rest of the meal is only health and mana. The icons go clickable again
  the moment there is nothing left to wait for.

### Fixed

- **Custom Queue no longer keeps warning that Blizzard's rotation has changed.**
  Shapeshifting (and similar form swaps) reports the same ability under a different
  spell ID, which the check mistook for one spell added and one removed - so the
  warning came back no matter how often you refreshed it.
- **Hidden Cooldown Manager panels no longer show tooltips.** Passing the cursor
  over where a hidden panel used to be popped up its tooltips, and the panel could
  quietly wake back up after a spec change, a zone or a Cooldown Manager settings
  change. It now stays out of the way for good.

## [4.55.0] - 2026-07-27

### Changed
- **Crowd control stops being suggested the moment a target shrugs it off.** When your CC comes back "Immune", JustAC now takes the game at its word and drops CC suggestions for that target immediately, instead of working it out a moment later from the missing debuff. As before, the lesson sticks: the same mob won't be offered CC again for the rest of the instance.

### Fixed
- **Locking the panel now says so.** Shift+right-click toggles the panel lock, which is one small miss away from the shift+right-click that blacklists a spell - and it used to happen in total silence, leaving the panel refusing to be dragged with nothing on screen to say why. It now announces the lock, and tells you how to undo it.
- **`/jac reset` now actually rescues a lost panel.** It moved the panel back to the centre but left it locked, so it still wouldn't drag - and if you had it docked to the target frame, the dock immediately pulled it away again and the new position was never saved. It now unlocks, undocks and re-centres, which is what you need when the panel can't be reached with the mouse at all.
- **The panel no longer drifts off the top of the screen.** Saved positions dropped part of the anchor, so a panel that WoW had anchored corner-to-opposite-corner after a drag reloaded measured from the wrong edge - which could throw it off the top of the screen, where the off-screen safety check (see below) then failed to rescue it.
- **The panel no longer jumps back to the centre on its own.** The off-screen safety check, which exists to rescue a panel stranded by a resolution or UI-scale change, measured the panel's position in a way that only held if it was anchored from its middle. Dragged somewhere it wasn't, the check could decide a perfectly visible panel had been lost and move it - or leave a genuinely stranded one out of reach. It now measures where the panel actually is.
- **Clicking a pre-combat buff now always applies the one you clicked.** Out of combat the clickable icons could briefly lag the queue behind them, so a click just after the list shifted would apply the buff you had *just* used - a second helping of food, a second weapon stone. Icons whose item was still loading could also carry the previous slot's ability. Clicking now tracks the queue as it changes, so what you click is what you get.
- **Clicks on empty space no longer cast anything.** When the defensive queue was cleared while you weren't in combat - vehicles, possessed control, an emptied queue - the invisible click areas stayed behind over the vacated slots, so a click there fired whatever had last been suggested.
- **Pre-combat reminders stay on screen while you eat.** Sitting down to food - or applying a poison, imbue or weapon oil - made the whole out-of-combat reminder list vanish until it finished, including the food you were in the middle of and its timing bar. The reminders now stay put, greyed out with a "wait" hint, and simply can't be clicked until what you're doing has finished.
- **Only one pet summon in the queue at a time.** With no pet out, a Warlock could see Felguard, Imp and Felhunter queued together, and a Hunter every Call Pet slot they own. They are alternatives to the same problem, so only the first is shown now. Summoned cooldowns like Army of the Dead, Feral Spirit and the elementals are unaffected and still queue alongside each other.

## [4.54.0] - 2026-07-25

### Added
- **Pet heal threshold is now yours to set** (Defensives → Sustain). Choose how hurt your pet has to be before the reminder appears, anywhere from 10% to 90%. Defaults to 50%, which is what it always used.
- **Pet heal reminder now works in combat.** Hunters and Warlocks previously only got a pet-heal suggestion out of combat, because the game hides your pet's health once a fight starts. It now appears in the Sustain slot the moment your pet drops low, in combat or out - the one time it was actually needed.
- **Execute-range cue.** When your target drops into execute range, your finisher (Kill Shot, Touch of Death and the like) lights up with an orange glow wherever it appears in the queue - so you can see the window has opened even before it gets recommended.
- **Show Enrage Cleanse toggle** (General → Disruption). Turns the enrage-removal reminder on or off. On by default, and only ever appears if your specialization actually has an enrage cleanse. It shares the interrupt icon but is now independent of it - you can run the cleanse reminder with interrupt reminders switched off, or the other way round.

### Fixed
- **The enrage cleanse cue works again.** The soothe reminder on the interrupt icon stopped appearing entirely after an internal rework of how those icons are built - it was being created in a state where it could never draw, no matter what your target was doing.
- **Hidden Cooldown Manager panels no longer pop tooltips.** A panel JustAC was keeping invisible still reacted to your cursor, so moving the mouse over empty screen space could bring up a spell tooltip from a panel you could not see.
- **The Emergency Potion tile no longer goes missing from your defensive list.** Reordering or removing entries could drop the tile, and once it was gone the only way back was Restore Class Defaults. Reordering is now safe, and a tile that disappears for any reason other than you removing it comes back on the next load. Removing it yourself still sticks, exactly as before. If you had already lost it, it returns automatically - remove it once more if you didn't want it.

### Changed
- **Emergency heals are now held back by default, and your walls never are.** Above the low-health threshold, panic buttons - immunity bubbles, big instant heals and health potions - sit parked at the end of the queue instead of being suggested while you are healthy. Damage-reduction cooldowns like Shield Wall, Ardent Defender and Pain Suppression are deliberately excluded and stay live at any health: those are meant to be pressed before a hit lands, not after you are already low. The setting also moved to Defensives → Defensive Queue, since it affects the nameplate overlay too.
- **Cooldown Manager settings moved to General → Settings**, under their own heading, and are no longer greyed out for non-tank specs. They turn on the game's own Cooldown Manager and hide its panels, which any specialization may want - the extra precision it buys is what's tank-specific, not the setting.
- **Better starting defensive lists for a lot of specs.** Discipline, Holy, Arcane, Holy Paladin and Restoration Shaman now get their own lists instead of a shared one that ignored their biggest defensive - Pain Suppression, Guardian Spirit, Greater Invisibility, Aura Mastery, Spirit Link and Ancestral Protection Totem are all there now. Mistweaver gets Life Cocoon, Restoration Druid gets Ironbark, Protection Paladin gets Blessing of Spellwarding, and Bitter Immunity, Anti-Magic Zone, Zephyr and Earth Shield were added class-wide. Netherwalk, Last Stand, Rage of the Sleeper, Metamorphosis and the new additions are now recognised as emergency buttons, so they rise to the front when you are about to die. A few entries that could never actually be cast were removed: Frenzied Regeneration off the Balance and Restoration lists (it needs Bear Form) and an ability the Monk lists carried that no longer exists in the game. Cast-time heals - Regrowth, Healing Surge and Vivify - now sit at the bottom of their lists instead of the top: standing still to cast is rarely the right answer mid-fight, and when one of them procs into an instant it jumps to the front on its own anyway. Your existing lists are left alone - use Restore Class Defaults on a spec if you want its new list.
- **JustAC now tells you when a Cooldown Manager panel is switched off**: a panel left on "Hidden" in Edit Mode is genuinely switched off as far as the game is concerned, so JustAC can read nothing from it - which looks like the feature simply not working. You now get a one-time message telling you to set it to "Always" in Edit Mode, and JustAC keeps it invisible for you from there.

## [4.53.0] - 2026-07-25

### Fixed
- **The tank upkeep timer no longer flickers or empties while the buff is still on you**: buffs you stack, like Ironfur and Ignore Pain, put every press on its own separate timer, and the slot used to follow just one of them - so it jumped between them and went blank whenever the one it was watching ran out. It now tracks your presses directly: the sweep counts down to your next stack falling off, and the number shows how many you are holding. If the game confirms the buff is actually gone, that still wins.
- **The tank upkeep sweep starts immediately for Shield of the Righteous too**: it now runs from your press rather than waiting for the game to confirm the buff, so there is no dead moment at the start of it.
- **The tank upkeep refresh cue no longer fires early**: it could warn you to re-press only a second after a press, because it had latched onto a buff length shorter than the real one.

## [4.52.0] - 2026-07-25

### Added
- **The queue now knows when you're crowd-controlled**: while you're stunned, feared, or locked out of a spell school, abilities you can't actually press sink to the back of the queue instead of holding a front slot. The moment you're free, the queue snaps back.
- **Capped charges surface with proc priority**: an ability sitting at maximum charges is wasting its recharge timer, so it steps forward until you spend one.
- **Capped resources push spenders forward**: when your primary resource is full, ready spenders surface so regeneration stops going to waste.
- **The queue holds steady while you channel** instead of flickering through upcoming suggestions mid-channel, and the suggestions grey out for the duration so nothing looks pressable while you're committed; it updates the moment the channel ends.
- **No more overlapping crowd control**: CC suggestions are suppressed while the target is already crowd-controlled, using the game's own aura classification rather than a spell list.
- **Defensives escalate when it's actually an emergency**: being low while still taking unshielded hits jumps defensive suggestions to emergency priority - a stable 30% and a dropping 30% are different situations, and only the second one is urgent. A major defensive already running counts as handled, so it won't escalate on top of one.

### Changed
- **Class resources are now read straight from the game** (combo points, holy power, chi, soul shards, arcane charges, essence), making resource-based suggestion ordering more reliable - including with a replacement unit-frame addon installed, where the old reading could go quiet.
- **The tank maintenance slot trusts the Cooldown Manager's own buff state**: with a tracked-buff bar enabled (Edit Mode), the "buff dropped - press it" cue is exact in combat instead of estimated, and a buff the game confirms is still up never asks to be re-pressed. That bar also supplies the exact remaining time and the stack count, and JustAC can keep it hidden if you would rather not see it on screen.

### Fixed
- **The tank maintenance slot reacts the instant you press it**: its timer sweep used to lag up to half a second behind the button, most noticeably when topping the buff up before it dropped.
- **The tank maintenance sweep no longer starts out blank**: it used to show nothing at all until the game confirmed which buff was yours. It now runs from your cast and switches to the game's exact timer as soon as one is available.
- **The tank maintenance slot no longer flickers**: its timer sweep could draw over the icon's border instead of underneath it, which read as the icon flashing.
- **The maintenance timer keeps its look after a skin change**: its blue "running out" sweep no longer reverts to a plain dark one, and the nameplate version now matches the main queue's.
- **Cast and channel fill no longer spills over the icon border** on the nameplate overlay.

## [4.51.0] - 2026-07-21

### Added
- **Escape from crowd control** *(Experimental, off by default)*: while you're held by something you can break - a stun, root or fear with a racial, trinket or class ability ready to counter it - the tank maintenance slot turns into that escape button, counting down the effect and glowing until you're free. It works on any specialization. This is experimental: it can only offer an escape for crowd control the game reports to addons, and movement slows in particular can't be detected in combat, so it won't cover everything. Turn it on under Defensives → Crowd Control Escape.

### Changed
- **The on-the-move and off-global-cooldown markers now show on interrupts, crowd control and the tank maintenance slot**, not just the offensive and defensive queues. The off-global marker earns its place on the maintenance slot especially: every tank upkeep button is off the global cooldown, so topping your mitigation back up costs nothing from your rotation.

### Fixed
- **Blood Death Knight's maintenance slot no longer asks for Bone Shield on a timer**: it glowed about 21 seconds after Marrowrend as though the buff were running down, but Bone Shield's stacks are spent by damage taken rather than by time, so that warning meant nothing. It now glows only when Bone Shield has actually gone.

## [4.50.0] - 2026-07-21

### Fixed
- **The tank maintenance slot no longer cues a button you can't press**: it now accounts for charges, so an ability with none banked stays quiet instead of glowing at you to press it.
- **Protection Paladin's Shield of the Righteous gets its early warning back**: it was being treated as charge-limited, which suppressed the cue. It runs on Holy Power, so you *can* keep it up - and you're now told before it lapses rather than after.

### Changed
- **Protection Warrior's maintenance slot now follows Ignore Pain instead of Shield Block**: Ignore Pain is the buff you genuinely keep rolling, and it absorbs damage of any kind, so it's worth having up whatever you're fighting. The slot shows how much shield is left and warns about 4 seconds before it drops, so you can renew and carry the remainder over instead of losing it and building back up from nothing. Shield Block hasn't gone anywhere - it sits in the defensive queue right beside the slot, which is the better home for it: it blocks melee only, so whether it's worth pressing depends on what's hitting you.
- **Vengeance's Demon Spikes slot now shows the ability rather than the buff** - charges available and the wait for the next one - because that, not the buff's duration, is what limits how often you can use it.
- **The maintenance refresh cue is a single clear pulse again**: the two-stage version added last release (a soft crawl, then a pulse) was too faint to catch mid-pull.

### Added
- **Blizzard's Cooldown Manager can be switched on from JustAC, and its panels hidden** (Defensives → Tank Maintenance Slot). Mid-fight the game conceals which buff is which, and the Cooldown Manager is the only thing that can tell yours apart - with it on, the maintenance slot shows an exact countdown and a live stack count. Each of its four panels can be made invisible separately, so you get the accuracy without the bars on your screen; they reappear while you're in Edit Mode so you can still move them.

## [4.49.0] - 2026-07-21

### Fixed
- **The tank maintenance slot now tracks the right buff**: mid-fight the game hides which buff is which, so the slot worked out which one was yours from the moment you cast it - and a trinket or talent proc landing in the same instant could be picked up instead. When that happened the countdown showed the other buff's remaining time, which could be wildly wrong. The slot now identifies your mitigation buff exactly wherever the game allows it, and where it can't, the countdown is estimated from your own cast instead of borrowed from something else.
- **The slot no longer tells you to re-press a buff you already have**: when it couldn't identify your buff it assumed the worst and glowed as though the mitigation had lapsed - sometimes for a whole fight. It now stays quiet unless it has actually seen the buff drop.

### Added
- **The stack count is back on the maintenance slot** (Ironfur, Bone Shield). It appears whenever your buff can be identified exactly, which needs Blizzard's Cooldown Manager turned on with its panel visible. Without that the slot shows no number rather than risk showing another buff's - the countdown and refresh glow still work either way.
- **A two-stage refresh cue**: the slot outlines with a slow crawl while the buff is still up but running low, then switches to a brighter pulse once it has actually dropped. Same colour throughout, so it reads as one cue at two levels of urgency rather than two separate warnings.

### Changed
- **The refresh cue now comes about 3 seconds before the buff decays** instead of 2 - enough time to react while tanking - and it learns your buff's real duration, so talents that extend it no longer make the cue fire early.

## [4.48.0] - 2026-07-21

### Changed
- **The tank maintenance slot no longer shows a stack count**: the number could be another buff's. Mid-fight the game hides which buff is which, so the slot works out which one is yours from the moment you cast it - and a trinket or talent proc landing in the same instant could be picked up instead, putting its stack count on your icon. A wrong number there is worse than none, so it's gone; the countdown and the blue refresh glow are unaffected and still tell you when to press it.

## [4.47.0] - 2026-07-20

### Added
- **Tank maintenance slot**: a dedicated slot beside the defensive queue for the one mitigation buff your spec keeps rolling - Shield Block, Shield of the Righteous, Ironfur, Demon Spikes or Bone Shield. It counts down the buff's real remaining time and glows blue as it runs low, so you refresh before the mitigation drops. Shows the keybind, greys out when you can't reach or afford the cast, and shows your stack count for Ironfur and Bone Shield. Blood's slot points at Marrowrend, so it can sit in your rotation and here at once - your runes and your Bone Shield want the same press. Hovering a slot names the buff it keeps up. Combat only, on the standard queue and the nameplate overlay. Tank specs only, on by default under Defensives -> Tank Maintenance Slot. Brewmaster isn't covered yet.
- **Off-global-cooldown marker** (opt-in): an amber marker in the lower-left corner of abilities that don't trigger the global cooldown - Tiger's Fury, Fire Blast, Combustion, Shield of the Righteous and the like. When you see it, cast and go straight to the next suggestion instead of pausing for a global. Most valuable on defensives, where firing one off the global costs you nothing. Both queues, both displays. Off by default: General -> Shared Behavior -> Mark Off-Global-Cooldown Spells.
- **Hold Until Charged** (opt-in, per ability): a toggle beside Always Show on each ability in your custom rotation. The ability is held at the back of the queue until every charge is banked, so a two-charge ability like Judgment or Throw Glaive isn't spent into an overcap. It keeps its place so you can watch it bank, though on a full queue the back may be off screen. An ability without charges is held until it's off cooldown. Off by default; needs the "Unavailable last" ordering toggle on.
- **Group buff reminders now watch your party**: out of combat, if you have Mark of the Wild, Arcane Intellect, Power Word: Fortitude, Battle Shout, Blessing of the Bronze or Skyfury up but a party member doesn't, the buff is offered again so one re-cast covers everyone. Party only, and only for members alive, online and in range. Personal buffs like poisons and shields are unchanged.
- **The target health bar steps aside when the queue is docked to the target frame**: docking already puts the game's own target frame beside the queue showing the same health, so JustAC's bar is no longer drawn there and its toggle greys out with a note. Undock and it returns - along with its execute-range colouring, so leave the queue undocked if you rely on that cue.

### Changed
- **The on-the-move marker is now a dot, and shows on defensives too**: previously a small arrow on the offensive queue only. It's now an azure dot in the lower-left - the same corner as the off-global-cooldown marker, so when both apply the dot splits, half azure and half amber, rather than two marks competing in different corners. It also shows on the defensive queue now, on both displays.
- **Both ability markers moved to General -> Shared Behavior**: they used to sit under Offensive -> General, back when they only affected the offensive queue. Your existing choices carry over.

### Fixed
- **Absorb barriers are no longer suggested while the shield is still on you**: Ice Barrier, Blazing Barrier and Prismatic Barrier outlast their own cooldown, so the button came back up while the barrier held and kept being suggested - even though re-casting just replaces the shield and wastes the remaining absorb. They now sink to the back while the barrier holds and return as it runs low, or the moment it drops if its remaining time can't be read mid-fight. Blood's Rune Tap is fixed the same way. Defensives that genuinely stack, like Ironfur and Ignore Pain, are untouched.
- **Interrupt suggestions could go permanently missing**: JustAC partly judges whether a cast can be kicked from whether the cast bar shows that spell's icon - but the icon also hides for unrelated reasons, such as turning the nameplate cast bar's spell icon off in the game's options, or a cast bar addon restyling it. Either made every enemy cast look un-kickable, so in "interrupts only" mode the kick reminder never appeared. Those cases are now told apart from a genuinely un-kickable cast.
- **The enrage cleanse reminder was missing its cooldown sweep**: it looked ready to press when it wasn't. It now shows the same sweep as every other suggested ability.
- **Errors in some instanced content when enemy nameplates appeared**: on certain instance maps JustAC threw an error whenever a nameplate appeared - a stream of them during a busy pull - and the nameplate overlay could stop following your target or fail to recognise a boss as immune to crowd control.

## [4.46.0] - 2026-07-19

### Changed
- **SimC priority now accounts for the resource you actually have**: with the *SimC priority* option on, abilities that need a minimum amount of a point-based resource - combo points, holy power, chi, soul shards or runes - now sink in the queue until you can afford them, instead of sitting up front while you're still building. Spenders surface as you reach the threshold and drop back once you've spent. Where the amount can't be read, ordering is left exactly as it was, so nothing is suggested on a guess.

### Fixed
- **Out-of-combat suggestions no longer interrupt the food or flask you're already using**: a suggested consumable stayed clickable while you were in the middle of consuming it, so a second click restarted your food and reset the timer - costing you the buff you were waiting on. Anything you're currently eating, drinking or casting is now held until it finishes.

## [4.45.0] - 2026-07-19

### Changed
- **SimC priority now follows Blizzard's live recommendation**: with the *SimC priority* option on, the abilities after Blizzard's pick are ordered by how well they match what it's recommending right now - single-target vs. multi-target, and whether you're building or spending resources - with SimulationCraft's priority breaking ties between equally-good options. Because Blizzard's pick reads the combat state we can't, this keeps the queue in step with the situation. It also picks up on burst and proc windows from that pick: when Blizzard recommends a window ability, the rest of that window's abilities line up alongside it - even while the buff itself is hidden mid-combat - and an ability you'd hold until the window passes stays back.

### Fixed
- **Balance Druid: Sunfire no longer stays at the front of the queue while it's already on your target**: Sunfire was never recognized as a damage-over-time you'd already applied, so it kept being suggested in the first slots even with its effect ticking - unlike Moonfire, which correctly moved back. The queue now tracks Sunfire on your target and sinks it until it needs refreshing.
- **SimC priority now points at the ability you actually press**: with the *SimC priority* ordering option on, some abilities were matched to a non-castable version of themselves - a passive, or an older spell sharing the name - so they never surfaced properly (Balance Druid's Moonfire was one). Others were missing outright: hero-talent and form abilities such as Annihilation and Death Sweep in Metamorphosis, Thunder Blast, Tempest and Reaver's Glaive, plus core buttons like Devouring Plague and Survival Hunter's kit. These now resolve to the real ability for your spec and build.
- **SimC priority ordering is tidier**: multi-target abilities no longer bleed into your single-target order (or the reverse); fight-opener and end-of-fight-only casts no longer hold the top spots; and interrupts, defensives, personal cooldowns and movement abilities have been dropped from the ability queue, since each already has its own reminder. What's left stays on your actual damage priority.
- **Emergency Potion now offers your strongest potion**: potions whose healing scales with item level - the current Silvermoon line among them - were being valued from a source that couldn't tell which potion it was being asked about, so they scored far below what they actually heal and a weaker fixed-amount potion could be suggested while a better one sat in your bags. Ranks of the same potion were scored identically too, so the higher-item-level version had no advantage. The tile now reads what each potion really heals for you; its label under Defensives shows which one it picked.
- The Emergency Potion choice could also lock in during login, before your bags had finished loading, leaving the wrong potion selected until you next picked something up. It now re-checks until your bags are readable.

## [4.44.0] - 2026-07-15

### Added
- **On-the-move marker**: a small arrow on suggested abilities you can cast while moving - instants, plus hardcast nukes the moment a proc makes them instant (Hot Streak, Lava Surge, and the like) - so you can grab one at a glance when you need to reposition. Channeled abilities are never marked. Defaults on for ranged and healer specs and off for melee; toggle it under General -> Mark Move-Castable Spells.

### Changed
- **Weapon enhancements now apply in one click**: clicking a suggested oil, whetstone or weightstone out of combat used to just put it on your cursor, leaving you to find and click your weapon. It now goes straight onto your main hand.

### Fixed
- **Defensive suggestions no longer vanish while you're stunned**: being stunned, feared, silenced or otherwise controlled made the game report every spell as uncastable, so the defensive queue emptied out for the duration of the effect and refilled when it broke - right when you most wanted to see what to press. Your defensives now stay put and simply grey out until you regain control, keeping the same order throughout.
- **Druid defensive defaults were missing heals**: Rejuvenation and Heart of the Wild are class talents but weren't suggested. Balance, Feral and Guardian now get Heart of the Wild, and the caster specs get Rejuvenation. Restoration doesn't get Heart of the Wild - it empowers abilities outside your spec, so for a healer it's a damage cooldown rather than a defensive. Existing characters keep their current list; use Restore Defaults under Defensives to pick up the new entries.
- The target health bar now updates the instant you switch targets in combat, instead of briefly showing the previous target's health until it next changed. The pet health bar refreshes the same way when a pet is summoned.

## [4.43.0] - 2026-07-12

### Added
- **Health Top-off** reminder (opt-in): between pulls and out of combat, surface a cheap self-heal at the front of the defensive queue while you're below full - detected from your health-regen activity for the times your exact health can't be read. A critical-health heal (below ~35%) always shows regardless of the setting. Off by default; enable under Defensives -> Pre-combat Buffs.

### Changed
- Defensive suggestion defaults now cover talent-based defensives for every spec - e.g. Frenzied Regeneration on Feral Druid, Dampen Harm across Monk specs, Metamorphosis for Vengeance, Last Stand on Protection Warrior, and many more. Anything you aren't talented into is simply skipped, so the list fills in whatever your build actually has. Use Restore Class Defaults to pick up the additions.
- Options tabs reorganized so settings live where you'd expect them: offensive queue-content options moved from General into the Offensive tab (which now opens with a combined General sub-tab), and defensive frame positioning moved to Standard Queue -> Defensive Display. General keeps only the genuinely shared settings.

### Fixed
- Pre-combat buffs now recognize the latest Midnight consumables. The new feast-line foods (e.g. Warped Wise Wings), alchemy phials, and weapon enhancements are offered again; eating one shows the timing bar and registers as Well Fed so the reminder clears; and food stat preferences (Crit, Haste, Mastery, Versatility) resolve correctly.

## [4.42.0] - 2026-07-11

### Fixed
- Gap-closer abilities (e.g. Infernal Strike, Fel Rush) were silently removed from the offensive queue even with Gap-Closers turned OFF. With the feature off they now flow through the queue like any other ability; with it on, they are reserved for the out-of-range suggestion as before - unless you pin them with the new Always Show option.
- Custom Queue abilities no longer vanish after a talent change: a stored ability whose spell ID belongs to a different talent variant now resolves to the version you currently know instead of silently disappearing from the queue.

### Added
- `/jac why <spell>` explains exactly why an ability is or isn't showing in the queue right now: known, blacklisted, redundant (with the reason), on cooldown (with the source), usable, in range, DoT already running, and whether it simply didn't fit your Max Icons.
- **Always Show** pin per Custom Queue entry: a pinned ability is never hidden by filtering (active buff, running damage-over-time effect) - it stays in the queue and only steps back while on cooldown or out of range.
- The Custom Queue options now warn when your list is longer than Max Icons, since abilities that fall back (cooldown, range, active DoT) may not fit on screen.

## [4.41.0] - 2026-07-11

### Fixed
- Several potential mid-combat errors from protected (secret) combat values: the enrage-cleanse cue on the nameplate overlay, the overlay health and pet health bars, the execute-context target latch, an assisted-combat usability fallback, and `/jac inspect auras` / `/jac inspect castdiag` output.
- Changing the Input Preference (keyboard/gamepad) option now updates displayed hotkeys immediately instead of after the next binding update.
- The Proc Priority toggle no longer appears on lists whose engines ignore it (gap-closers, burst, pet rez), and removing a spell from one of those lists no longer discards the proc-priority setting the same spell has in the defensive or rotation lists.
- A stuck highlight glow on nameplate overlay icons when leaving combat.
- The enrage-cleanse cue now hides together with the nameplate overlay (mounted, visibility rules, or overlay teardown).
- Two damage-over-time spells landing in the same update are now attributed to the right casts.
- The overlay's Defensive Display reset now also resets the resource bar option.
- Burst injection could keep serving the previous spec's spell list in rare spec-switch sequences; talent changes now refresh imported rotation rankings without a reload.
- Empty queue slots no longer keep a stale charge cooldown ring; pet-summon talent variants are now recognized by the redundancy filter; a disabled cooldown-swipe fallback for off-bar spells works again.
- Pre-combat buff suggestions are now strictly tied to the defensive bar: with defensives disabled they never appear, and their options section grays out to make the dependency clear.

### Changed
- Large internal cleanup: duplicated rendering, options, health-bar, and engine logic consolidated and dead code removed (roughly 770 fewer lines). No visual or behavioral changes intended beyond the fixes above.
- `/jac` spell name lookup no longer freezes the game briefly when a name isn't found.

## [4.40.0] - 2026-07-09

- More damage-over-time abilities now step to the back of the queue while already active on your target, returning in time to refresh - Agony, Unstable Affliction, Wither, Immolate, Vampiric Touch, Garrote, Rupture, Phantom Singularity, and other previously missed spec DoTs.
- Abilities whose damage-over-time effect is a minor rider on a direct hit (like Frostfire Bolt) no longer step to the back of the queue after casting.
- The switch-target arrow is now off by default; turn it on in the options if you use it.

## [4.39.0] - 2026-07-08

### Added

- Enrage cleanse reminder: when your target is enraged and you can remove it - Soothe, Tranquilizing Shot, Shiv, and the like - the interrupt slot shows your cleanse with a green glow, its keybind, and the enrage it will remove. While the enrage is still being cast you'll get the interrupt instead (interrupting avoids the enrage); the cleanse takes over the moment it lands, and wins when both apply. Works on the standard queue and the nameplate overlay.
- Nameplate overlay resource bar: the standard queue's optional resource bar is now available on the nameplate overlay too - your primary resource (mana, energy, rage) plus, for specs that use one, a segmented secondary point resource (combo points, runes, chi, and so on) - stacked beyond the overlay health bars and colored by type. Enable it under Nameplate Overlay options; it needs the overlay health bars turned on.
- Priority ordering by SimulationCraft (experimental): the queue's *Context aware* ordering is now a *Context ordering* choice - Off, *Match Blizzard's pick* (the previous behavior), or *SimC priority*. *SimC priority* orders the abilities after Blizzard's pick by SimulationCraft's community priority for your specialization and target count; Blizzard's Assisted Combat still chooses your first ability. Opt-in and off by default, and tuned for end-game - below max level, *Match Blizzard's pick* is the better fit.

### Improved

- Nameplate overlay health bars now match the standard queue's styling - a neutral darkened background with a subtle sheen instead of a flat red - so the two displays read consistently.
- The queue recognizes AoE and cleave more reliably, counting the enemies actually engaged with you, so your multi-target abilities surface when you're fighting more than one target.
- The offensive *Rotation* tab is now named *Priority*, reflecting that it orders a priority queue of suggestions rather than mirroring a fixed rotation.

### Fixed

- The out-of-combat "click" cast helper no longer floats over an empty spot when the icon beneath it is hidden - it only appears on reminders actually shown on screen.
- A proc glow on a queued ability no longer occasionally gets stuck lit after you leave combat.
- A queued ability that transforms into a follow-up - such as Templar Strike becoming Templar Slash - no longer shows a phantom cooldown that isn't on your action bar.

## [4.38.0] - 2026-07-06

### Added

- Resource bar: an optional half-height bar (distinct from the health bar) for your primary resource - mana, energy, rage, runic power, and so on - stacked above your health bar and colored by resource type. Specs with a secondary point resource (combo points, runes, chi, holy power, soul shards, arcane charges, essence) get a second segmented bar stacked flush against the primary, colored to match and shown only in the forms/specs that actually use it - so the pair reads as one health-height bar. Enable it under Standard Queue, Defensive Display. Off by default.
- The target health bar now shifts to a bright execute color when the target drops into execute range, as a glanceable "finish it" cue.

### Fixed

- Suggestions now refresh immediately when you change specialization, so shapeshift-form abilities are no longer briefly evaluated against the previous spec's data.

### Improved

- Reduced idle CPU: the damage-over-time readiness check is skipped entirely when no tracked DoTs are active (for example, on specs that don't maintain them).

## [4.37.0] - 2026-07-06

### Added

- Damage-over-time abilities you have already applied to your target now sink to the back of the queue while the debuff is live, so you are not nudged to re-cast a DoT that is already ticking. Works for maintained DoTs across every class (Rake, Rip, Corruption, Shadow Word: Pain, Moonfire, and many more). The ability reappears in time to refresh (inside its pandemic window), the moment the debuff drops or is dispelled, or when you switch to a target that does not have it. Multi-stack DoTs are left alone so you can keep building stacks. New diagnostic: `/jac inspect dots`.
- Switch-target arrow: when Assisted Combat keeps recommending a damage-over-time ability that is already on your current target, an arrow appears on the first icon as a cue to apply it to another enemy. On by default; toggle in General options.

### Fixed

- Abilities that a talent replaces or renames are now recognized consistently everywhere. Defensive, healing, and crowd-control talent variants no longer occasionally slip into the damage queue, and talent-modified abilities get the correct archetype, priority, and DoT handling.
- DoT tracking stays accurate when entering a raid encounter, Mythic+ run, or PvP match, and adds no measurable background cost when your spec has no tracked DoTs.

## [4.36.1] - 2026-07-06

### Fixed

- A procced execute ability (e.g. Shadow Word: Death) that you cast while its proc glow is still lit no longer stays pinned near the front of the queue while on cooldown. It now sinks to the end with the other cooldowns, keeping its glow, until it is usable again.

## [4.36.0] - 2026-07-05

### Changed
- Whether an ability can be cast right now - form, stance, stealth, talents, and resources - is now read directly from the game instead of from bundled data. Abilities a talent makes usable in another form (for example Frenzied Regeneration in Cat Form via Empowered Shapeshifting) now appear correctly, and suggestions better reflect what you can actually cast.

### Fixed
- The defensive, blacklist, and rotation spell searches now find every spell in your spellbook, including General-tab and class-talent spells that were previously missed (they could be added only by typing the exact spell ID).

## [4.35.0] - 2026-07-05

### Changed
- Defensive suggestion priority is smarter at low health, with stronger emergency actions shown sooner when you are in real danger.
- Buff and cooldown tracking is more reliable when entering or leaving combat.
- New and alternate spell variants are recognized more consistently without extra setup.

### Fixed
- Defensive icons once again show hotkeys correctly out of combat.
- Defensive click-to-cast layers no longer cover icon labels.
- Interrupt recommendations are more reliable, including for empowered casts.
- Defensive item suggestions no longer appear ready after you already used the item.
- Hotkey detection is more consistent across vehicles, special bars, and macro-heavy action bars.
- Nameplate overlay visuals are more stable: glow behavior is corrected, labels no longer bleed through overlapping frames, and held-back emergency suggestions show the correct waiting state.

### Performance
- Out-of-combat performance has been improved with smoother frame pacing and reduced idle update churn.
- Event bursts are now coalesced more aggressively out of combat to reduce unnecessary queue rebuilds.
- Added an in-game performance diagnostics view for coalesced out-of-combat events via `/jac inspect perf`.

## [4.34.0] - 2026-07-05

### Added
- **Your class's own cheap heal is now the preferred out-of-combat top-off:** when you're hurt after a fight, classes with a spammable self-heal (Regrowth, Flash Heal, Vivify, Healing Surge, Flash of Light, Emerald Blossom, Crimson Vial) see it as the glowing click-to-cast suggestion - resources regenerate out of combat, so hardcasting it is free in practice. A procced free heal still comes first, and Recuperate remains the fallback for classes without a cheap heal or when it's on cooldown. Real combat cooldowns (Exhilaration and the like) are never suggested for topping off.

### Fixed
- **Defensive glow flicker and stutter:** the defensive row's two glow update paths could disagree - alternating glows on out-of-combat heal icons, and a stutter on the proc glow whenever you activated an ability in combat. All defensive glows now run through one arbiter with a single priority (proc glow wins, then the green pre-combat glow, then the standard glow) and a short settle time, so momentary state flaps during casts can't blink the animation. A procced heal keeps its proc animation even when it's also offered as an out-of-combat top-off.
- **Recuperate no longer suggested when you're barely scratched or at full health:** in zones where the game hides exact health, the out-of-combat heal offer now requires a sustained run of recovery ticks at genuine regeneration pace - a sliver of missing health, a slow healing passive (Ysera's Gift), or a lingering heal-over-time at full health no longer summons the suggestion.
- **Heals in your defensive list no longer wear the green pre-combat glow at full health:** a spell that is both a regular defensive entry and an out-of-combat top-off (Regrowth) was green-glowing in its defensive slot regardless of health. The green glow now marks only icons actually inserted by the pre-combat suggestion system.

## [4.33.0] - 2026-07-05

### Added
- **Recuperate as a pre-combat buff:** whenever you're hurt out of combat, the new all-classes Recuperate self-heal is offered alongside your other missing buffs, with the same green glow and click-to-cast. It hides while its heal-over-time is running, steps aside when a procced heal is the better top-up, and respects the pre-combat buffs toggle. Works even in zones where the game hides exact health values out of combat - and if a damage-over-time effect interrupts the heal, one click cancels the stale effect and restarts it.
- **State-aware suggestions across all classes:** abilities the game won't let you use right now sink in the queue instead of showing as ready - stealth-only openers while unstealthed (Subterfuge and Shadow Dance respected, procs always exempt), abilities missing their enabling buff (Arcane Missiles without Clearcasting), and Cat/Bear-only Druid abilities while in the wrong form (automatically disabled with Fluid Form, whose attacks shift you on their own). Self-buffs that are already active (Slice and Dice and the like) are now recognized for every class and reappear near expiry when a refresh is actually useful, while stackable buffs are never wrongly suppressed.
- **Built-in base cooldown and charge data:** abilities the addon first sees mid-combat (battle res, spec change, first engage after login) now track their cooldowns and charges correctly instead of always showing as ready, even while the game hides live cooldown values in combat.

### Fixed
- **Cooldown countdowns no longer get stuck in combat:** a hidden in-combat value could poison the cooldown tracker, leaving an ability showing "on cooldown" with a countdown that refused to reset until well after combat ended.
- **Defensive proc glow no longer freezes mid-animation when leaving combat:** it resets cleanly on combat exit - and procced heals now keep their glow animating out of combat, since a free heal is the preferred post-fight top-up.

## [4.32.5] - 2026-07-04

### Performance
- **Much lower idle CPU in crowded areas (cities, hubs):** events for other players' health, auras, and spellcasts are now filtered out by the game engine instead of being received and discarded one by one. Macro keybind data is no longer fully re-scanned when a single action button updates, repeated non-matching macro checks are now remembered instead of re-parsed, and spurious shapeshift-bar updates (no actual form change) no longer trigger a full macro/hotkey rebuild.

### Fixed
- **Defensive queue broken after changing specialization:** switching specs (e.g. on Druid) left the previous spec's defensive spells registered for cooldown tracking and never set up the new spec's list, leaving the defensive queue empty or showing wrong abilities until a UI reload. Spec changes now fully re-initialize defensives, gap closers, and burst injection for the new spec.
- **Shapeshift form changes now refresh the defensive queue immediately** (e.g. bear-only defensives appearing/disappearing when shifting), in and out of combat, instead of waiting for the next health update.

## [4.32.4] - 2026-07-02

### Fixed
- Pre-combat buff and class-buff reminders now stay quiet in PvP instances, where the 12.0.7 game update makes buff data unreadable even out of combat. Previously the addon could re-suggest a flask or food you had already used (and clicking would consume another one) because it couldn't see your active buffs there.

## [4.32.3] - 2026-07-02

### Fixed
- Fixed a flood of "attempted to index a table that cannot be indexed with secret keys" errors after the 12.0.7 game update, which made some buff data unreadable even out of combat. Buff scanning (pre-combat buff reminders, food/eating detection, class-buff refresh timing, the eating progress sweep) now skips unreadable buffs instead of erroring.

## [4.32.2] - 2026-07-02

### Fixed
- Custom queue: abilities that are out of range on your current target now move to the end of the queue - including minimum-range abilities like Heroic Throw while you're in melee. They move back up the moment range is right again; the red range tint on the icon shows why an ability stepped back.

### Changed
- The custom queue's "Cooldowns last" ordering toggle is now "Unavailable last", matching everything it covers: on cooldown, out of charges, unusable (like Execute above its health threshold), and out of range. It handles the hard can't-press-it-now states; the situational reordering (matching Blizzard's pick, melee-range bias) remains separate on the "Context aware" toggle.

## [4.32.1] - 2026-07-02

### Fixed
- Custom queue: abilities the game reports as unusable - Execute above its health threshold, Kill Shot, stealth-only openers - now move to the end of the queue with "Cooldowns last" enabled, instead of holding a front slot they can't be pressed from. Proc highlights still jump to the front (a Sudden Death Execute shows immediately), and abilities that are merely low on rage/energy stay in place.

## [4.32.0] - 2026-07-01

### Added
- Tank defensive queues now follow each tank's playstyle:
  - **Brewmaster Monk**: Purifying Brew joins the default list and jumps to the front (glowing) whenever you have Moderate or Heavy Stagger - even at full health, because stagger is the real danger signal.
  - **Protection Warrior**: Shield Block joins the default list at the top; while its buff is already active it steps to the back of the queue so Ignore Pain and friends take priority.
  - **Vengeance Demon Hunter**: Demon Spikes steps to the back of the queue while its buff is already active.
  - **Protection Paladin**: Divine Shield no longer floats to the top at low health - bubbling as a tank drops your threat mid-pull.
  - Major survival cooldowns (Shield Wall, Survival Instincts, Ardent Defender, Guardian of Ancient Kings, Fortifying Brew, Vampiric Blood, Icebound Fortitude, Fiery Brand) and Soul Cleave now float above filler abilities when you're low, and are held back as emergency buttons while you're healthy.
- The same treatment applies to non-tank damage-reduction cooldowns: Astral Shift, Unending Resolve, Dispersion, Obsidian Scales, and Die by the Sword now float to the top when you're low - your wall comes before a slow-cast heal.
- Fury Warriors now get Enraged Regeneration in the default defensive list (each warrior spec sees its own wall).
- The Emergency Potion tile (enabled by default, auto-picking your strongest owned healing potion or stone) now floats up with the other survival buttons when you're low, instead of staying parked at the bottom of the list.

### Fixed
- Right-clicking a defensive icon out of combat opens the custom-hotkey dialog again (with the panel unlocked). Click-to-cast was swallowing the right-click and casting instead; casting is now left-click only.
- `/jac profile <name>` with a name that doesn't exist now reports "Profile not found" instead of silently creating a fresh profile (which looked like all your settings reset).

### Notes
- Existing characters keep their saved defensive lists. Use "Restore Defaults" in Options → Defensives to pick up the new Shield Block / Purifying Brew entries; the smarter ordering applies either way.

## [4.31.0] - 2026-07-01

### Fixed

- Nameplate overlay: defensive icons could vanish for the rest of combat after
  losing or switching your target.
- Defensive queue: no longer invisible after a UI reload during combat.
- Eating: the progress sweep and "wait" hint now work with foods from every
  expansion, not just the current tier.
- The global-cooldown sweep now shows on queue icons for abilities cast through
  macros or otherwise not directly on a bound action bar slot.
- Weapon enhancements: sharpening stones and weightstones are only suggested when
  they fit your equipped weapon (bladed vs. blunt), and look-alike items (pet
  battle stones, statues) no longer appear as suggestions.

### Improved

- Cooldown tracking: talent-driven cooldown resets and reductions on interrupts,
  defensives, and gap-closers are now detected mid-combat.
- Cooldown tracking: charge abilities snap back to full the moment their last
  charge recovers or is refunded.
- Cooldown tracking: cooldown state survives dying - after a battle resurrection,
  abilities no longer all appear ready.
- Queue ordering: procced spells keep their priority spot even when a talent
  reset their cooldown or refunded a charge.
- Queue ordering: multi-target situations are remembered for a few seconds, so
  the queue no longer flips to single-target ordering while your AoE spells
  recharge.
- Queue ordering: execute abilities stay prioritized for the rest of a target's
  life once it enters execute range.

### Added

- `/jac inspect rank` - shows how the queue reads the current combat situation
  and how each queued ability is ranked.

## [4.30.1] - 2026-07-01

### Added
- **Shamans get a weapon-imbue reminder.** Out of combat, when your weapon has no enchant,
  JustAC reminds you to apply your imbue - Windfury or Flametongue for Enhancement,
  Earthliving for Restoration - as a clickable green buff icon, just like the other
  pre-combat reminders. It won't suggest a weapon oil on top of an imbue you'd rather use.

### Changed
- **Interrupt and crowd-control reminders dim on the global cooldown.** A reminder that's
  briefly unavailable only because the global cooldown is ticking now greys out, so a
  fully-lit icon always means it's ready to press. Interrupts that ignore the global
  cooldown stay lit.

### Fixed
- Fixed an error that could appear when opening the options window.

## [4.30.0] - 2026-07-01

### Added
- **Hide Emergency Heals Until Low Health** (Defensive settings) holds panic buttons,
  including immunity bubbles, big instant heals, and health potions, until your health
  drops below the low-health threshold. Mitigation and filler defensives still show.
  Off by default.

### Changed
- **Smarter queue ordering.** The queue, meaning everything after the Assisted Combat
  slot, now ranks each ability by how closely it matches Assisted Combat's current
  suggestion. Target pattern and builder/spender role rise to the top, so the
  alternatives on offer are the best fit for the current pull. This powers the
  **Context Aware** ordering toggle, which is on by default, and applies to the Custom
  Queue too.
- Damage-over-time and bleed abilities are now recognized across every class and spec.
- The options now call the first icon the **AC slot** and the rest **the queue**.
- **Speed food and flasks now use the Speed stat.** Choosing "Speed" now suggests
  consumables that grant the Speed secondary stat, and plain run-speed foods are no
  longer suggested.

### Fixed
- Defensive icons no longer trigger blocked-action errors when they appear or hide
  during combat while the queue is anchored to the target frame.
- Cooldown swipes now stay on the correct ability when a macro slot changes with
  modifier keys.

## [4.29.1] - 2026-07-01

### Pre-combat buffs
- Every pre-combat buff dropdown now shows **the exact item from your bags** on each option
  - the Flask list tells you which flask "Haste" will actually use, so you can see what
  you'd get (or what you're missing) without guessing.
- **Speed and XP consumables** are now covered. The Food dropdown gains a **Speed** option
  (long-lasting movement-speed foods, for travel and leveling), and XP-boost consumables get
  their own opt-in **XP** dropdown. Both stay off unless you choose them.
- **Weapon enchant** auto-picks the right type for your spec: a weapon oil for casters, a
  sharpening stone or whetstone for physical specs.
- Only **long-lasting buffs (20 minutes or more)** are suggested now, so short snacks and
  quick potions no longer clutter the reminders.

## [4.29.0] - 2026-06-30

### Pre-combat buffs (new)
- Out of combat, the defensive queue now reminds you of the pre-combat buffs you're
  **missing but own** - flask, food, augment rune, weapon enchant - as clickable icons
  with a green glow. Click one to use it right from the queue. Made for buffing up before
  a group or dungeon pull.
- **Class buffs** are covered too: rogue poisons, shaman shields and weapon imbues, and the
  standard party/raid buffs. You're reminded when one is missing or has dropped below half
  its remaining time, and offered the option your rotation already favors - rogues get both
  a lethal and a non-lethal poison.
- While you're **eating or applying** a buff, the whole queue greys out with a channel-style
  progress sweep, so it's clear the buff is on its way.
- Every out-of-combat queue icon now has a **hover highlight and click-to-use**, like an
  action button.

### Defensive queue
- The emergency healing potion now surfaces the **best potion you're actually carrying**,
  ranked by how much it restores - a potion that heals a share of your maximum health can
  out-rank a bigger fixed-amount one, and the reverse. The tile's tooltip explains the pick.

### Health bars
- New **target health bar**: a compact red bar on the far side of the standard queue,
  opposite the player/pet bars. Shows for hostile targets only and hides when you have
  no target. Toggle it under Defensives → Show Health Bars.
- All health bars now share a neutral dark background, so missing health reads clearly
  behind every bar color.

### Interrupts
- The interrupt reminder now overlays the target's cast progress on the kick icon,
  with a highlighted zone over the final stretch - press the interrupt as the bar
  reaches the zone to time it well. Channels drain instead of fill.

### Rotation
- "Cooldowns last" now also sends abilities that are **out of charges** to the back
  of the queue, not just ones on a flat cooldown. Charge abilities (in a custom
  rotation or Blizzard's) that used to linger up front now drop back until a charge
  returns.

### Maintenance
- Internal code cleanup.

## [4.28.1] - 2026-06-29

### Responsiveness
- Ability icons now swap instantly instead of fading, so the rotation queue and
  defensive reminders feel noticeably snappier. The whole-bar fade in/out when the
  UI shows or hides is unchanged.

## [4.28.0] - 2026-06-29

### Rotation
- Renamed the **Fixed Queue** tab to **Rotation**. Position 1 is always Blizzard's
  pick; everything on the tab controls positions 2+ (the abilities shown as coming
  up next).
- New master **Ordering** toggles - **Procs first**, **Context aware**, and
  **Cooldowns last** - apply to positions 2+ of both Blizzard's rotation and your
  Custom Rotation. All on by default; turn them off to show positions 2+ in exact
  source order.
- With **Procs first** on, the per-ability **Proc Priority** toggle now affects the
  main queue: uncheck it to keep a procced ability in place instead of jumping it
  forward (it still glows).

### Interrupts & CC
- Interrupt settings moved to their own **Interrupt** section above Shared Behavior.
- Crowd-control suggestions now draw from a much larger auto-filtered list -
  interrupt-capable hybrid abilities, racials, and pet stuns included - showing only
  what your character actually has.
- Suggestions are now range- and context-aware: a self-centered AoE stun is skipped
  when the target is out of range, and single-target CC is preferred when Blizzard is
  recommending single-target attacks.
- New **Include Fears** toggle (off by default) - fears scatter mobs and break in
  groups, so they're hidden unless you opt in.

### Gap-closer
- Melee-range detection is now reliable across every class, spec, and form
  (including druid forms), read straight from your spellbook rather than your action
  bars.
- The gap-closer appears the moment your target leaves melee and clears promptly when
  you close in, with less flicker on the move.

### Options panel
- Checkbox-heavy sections (General behavior, display options) now lay out in two
  columns.
- Cleaned up option labels. Queue-content toggles read as a set: **Include
  Macro-Hidden**, **Include Spellbook Procs**, **Include Item Abilities**, and
  **Include Procced Defensives**.
- Fixed two checkboxes that shared the name "Insert Procced Abilities"; the offensive
  and defensive proc options are now distinct.
- Standardized position-1 wording to "Blizzard's pick" across the panel.

## [4.27.0] - 2026-06-28

### Pet classes

- Pet rez/summon reminders no longer nag specs that intentionally run without a
  pet (Marksmanship with Lone Wolf, Warlock with a sacrificed pet).
- Pet summon/revive now shows a single icon instead of stacking multiple summon
  buttons - Warlocks see one resummon prompt rather than every demon at once.
- Demonology Warlocks now see Felguard as the suggested resummon.
- Unholy Death Knight ghoul reminder corrected to the permanent-ghoul Raise Dead.

### Fixes

- Fixed an error when running the defensive diagnostic in combat.

## [4.26.0] - 2026-06-28

### Added
- Each blacklist entry now has an **Apply to Position 1** toggle. Leave it on (default) to hide the ability everywhere. Turn it off to hide it from positions 2+ only - the ability still shows at position 1 when Blizzard recommends it, so blacklisting a spell Blizzard wants *right now* no longer stalls the rotation.

### Changed
- **Shift+right-click a queue icon to blacklist** that ability - it's hidden from every position, including position 1 and the nameplate overlay. This matches the icon's "remove from queue" tooltip. (Reordering or removing abilities from positions 2+ is still done in the options tab.)
- Renamed the **Custom Queue** tab to **Fixed Queue**, with a clearer explainer: you choose which abilities can appear in positions 2+, while JustAC still orders them live - procs and abilities matching the moment (AOE / single-target / range) surface first, and abilities on cooldown drop to the back. Your manual order breaks ties. Position 1 is always Blizzard's live pick.

### Fixed
- Corrected burst-injection defaults on several specs so the feature actually fires:
  - Protection Paladin's injected cooldown was attached to the wrong spec and never appeared - now restored.
  - Brewmaster Monk had an injection spell but no burst trigger, so its window never opened - added the missing trigger.
  - Vengeance Demon Hunter, Assassination Rogue, Augmentation Evoker, and Elemental Shaman were each set to "inject" the very cooldown that opens the window (always on cooldown, so nothing happened). The first three now inject a real secondary cooldown; Elemental and Augmentation are left to user choice rather than shipping a no-op.
  - Shadow Priest burst windows now track correctly from Void Eruption and Dark Ascension.
- A blacklisted ability is now also suppressed when it would otherwise be injected at position 1 during a burst window or as a gap-closer (e.g. a stealth gap-closer). Previously the blacklist could be bypassed on those injected suggestions.
- Corrected gap-closer defaults on a few melee specs:
  - Survival Hunter's default gap closer pointed at a melee attack instead of the actual leap-to-target ability, so it never suggested one - now fixed.
  - Unholy Death Knight's out-of-melee-range detection could misfire when talented into a ranged attack; it now reads from a reliable melee ability instead.
  - Havoc Demon Hunter gains a charge-to-target backup gap closer when the default mobility dash isn't available.
- Localization fixes: a Russian color tag that failed to render, and a mistranslated vendor name in Simplified Chinese.

## [4.25.1] - 2026-06-28

### Fixed
- The interrupt suggestion is now correctly hidden on casts that can't be interrupted, on **any** UI setup. Previously, if a cast-bar / nameplate / unit-frame addon replaced or reskinned the Blizzard cast bar, the kick could be wrongly suggested on a non-interruptible (shielded) cast. The icon's visibility is now driven straight from the cast's protected interruptible flag through a display-only path that needs no cast bar, so it works regardless of your UI. (One edge remains: *substituting* a crowd-control ability for a kick on a non-interruptible cast still needs the default cast bar - with a replaced cast bar you simply get no suggestion there instead of a CC, never a wrong kick.)

### Internal
- Added `BlizzardAPI.SetAlphaFromSecretBool` / `ApplyInterruptIconAlpha` helpers wrapping the secret-aware `SetAlphaFromBoolean` display sink, and routed both the standard-queue and nameplate-overlay interrupt icons through them. Documented the interrupt-detection layers at the top of `UI/CastInterruptTracker.lua`; `/jac inspect castdiag` re-validates them.

## [4.25.0] - 2026-06-28

### Changed
- Below the ~35% low-health threshold, the defensive queue now leads with survival buttons - immunity bubbles first (Divine Shield, Ice Block, Aspect of the Turtle, Cloak of Shadows), then big instant heals (Lay on Hands, Death Strike, Renewal, etc.) - ahead of mitigation and small fillers. Above the threshold the order is unchanged: fast/free fillers and procs stay first for routine HP upkeep. Procced spells remain top priority in both cases.

### Internal
- Mapped and documented in-combat interrupt detection (added a `/jac inspect castdiag` diagnostic). The only readable signal is Blizzard's cast-bar icon-hiding on non-interruptible casts, and only on an untainted, Blizzard-driven cast bar; the interruptible flag/barType, cast spellID, shield state, and interruptible/uninterruptible events are all secret or never fire. Removed a dead secret-resolution fallback that could never succeed in combat (no behavior change). Known limitation unchanged: cast-bar / nameplate / unit-frame addons that replace or reskin the cast bar leave no readable signal, so the interrupt logic falls back to fail-open there.

## [4.24.0] - 2026-06-28

### Fixed
- Cooldown swipes on abilities behind modifier-key macros no longer flicker away when the modifier is released. The direct action-bar slot is used while the ability is visible (most accurate); when a modifier hides it, the swipe falls back to JustAC's own cooldown tracking and holds seamlessly. Applies to all icon types (standard, overlay, defensive, interrupt).
- Charge-based abilities now read correctly: ready while any charge remains, greyed out at 0 charges, and at 0 charges the recharge shows the full dark swipe (matching the action bar) instead of only the thin charge ring. Fixes directly-visible spells like Feint showing just the ring.
- Corrected 6 stale entries in the curated defensive/healing/crowd-control lists (audited against current spell data): re-IDed Rage of the Sleeper, Between the Eyes, and Essence Font, and removed three deleted spells (Greater Fade, Cloudburst Totem, Mind Bomb).
- Type-restricted crowd control is no longer suggested against creature types it can't affect - e.g. Repentance won't be offered to interrupt a casting Beast, Elemental, or Mechanical. Fails open when the type is unknown (still suggested); universal stuns/silences are unaffected.
- When only crowd control can stop an uninterruptible cast, a stun-class CC (stops anything) is preferred over a silence-class CC like Strangulate (stops only spellcasting), since the cast may be a physical channel. The silence is still offered if no stun-class CC is available.

### Added
- Queue positions 2+ re-prioritize by combat context: matching the archetype (single-target / cleave / AOE) and range (melee / ranged) of Blizzard's position-1 pick. An AOE pull lifts AOE/cleave spells and sinks single-target ones; melee abilities sink when you're out of range. Range is a hard constraint, archetype a soft preference. Applies to the Custom Queue too, backed by a DB2-generated archetype table covering all classes.
- The player health bar pulses below the ~35% low-health threshold (the only health level readable in combat). Fill color is unchanged for contrast; the pulse is the cue.

### Changed
- Faster suggestions: position-hold and glow-hysteresis cut from 200 ms / 100 ms to 50 ms (worst-case latency ~230 ms → ~80 ms).
- The in-combat update loop is clamped to 20–33 Hz independently of the `assistedCombatIconUpdateRate` CVar, so a slower Blizzard default can't throttle the queue.

### Internal
- Centralized per-frame cooldown/usability refresh throttles into `UIFrameFactory` so one tune applies to all queues.
- Added `Options/Widgets.lua` AceConfig builders and a shared `NotifyChange()` wrapper; migrated the General, Standard Queue, and Nameplate Overlay panels onto them (~150 closures removed). No behavior change.
- Moved inline legacy-key migrations (`defensives` display mode, overlay glow mode) into load-time `NormalizeSavedData`.
- Separated data from logic: curated category tables → `Data/SpellCategories.lua`, generated archetype table → `Data/SpellArchetypes.lua`, with `SpellDB` keeping registration/logic. Added DB2→Lua generator and audit scripts under `tools/` (not shipped) to regenerate per patch.

## [4.23.0] - 2026-06-17

### Fixed
- Defensive queue icons behind modifier-key macros now correctly show the GCD swipe animation. The fix uses the macro slot's action bar cooldown data (all slots share the global GCD timer) when no direct slot is available.
- Off-GCD defensive abilities (Barkskin, Ice Block, Evasion, Cloak of Shadows, etc.) no longer show a spurious GCD swipe. A pre-populated table of 30+ known off-GCD spells as of 12.0.7 is included; the table self-corrects via `SPELL_UPDATE_COOLDOWN` on first cast.
- Defensive spells with long unflagged cooldowns (e.g. Cloak of Shadows, Shadow Blades) could appear ready in the defensive bar in combat. Readiness check now uses `SpellCooldownInfo.isActive` (NeverSecret) as ground truth for the in-combat case.

### Changed
- Interface version updated for WoW 12.0.7 (build 120007).

## [4.22.3] - 2026-06-06

### Fixed
- Blizzard Settings now correctly repopulates the Defensives Priority List after relog/restart instead of showing only the "Restore Class Defaults" control block.
- Dynamic options lists now refresh on specialization change while Blizzard Settings is open, so spec-specific Defensives/Offensive sub-lists stay in sync without needing to close and reopen the panel.

## [4.22.2] - 2026-06-05

### Added
- Localized `WAIT` overlay label in supported locales so resource-wait messaging is translated consistently.

### Changed
- Hotkey normalization and keypress matching are now more consistent across modifier formats, improving flash/match reliability for standard, defensive, interrupt, and nameplate icons.

### Fixed
- Defensive queue deduplication for pet rez/heal suggestions now correctly reuses per-pass tracking in both main and nameplate defensive paths.
- Removed duplicated locale `WAIT` entries that were introduced during localization updates.

## [4.22.1] - 2026-05-19

### Fixed
- Non-Masque queue icon framing: ability artwork now fills correctly without bottom gaps or right-edge bleed. Centralized mask and border geometry into shared `CreateRoundedActionIconMask` / `ApplyActionButtonBorderGeometry` helpers and applied them consistently to standard queue, defensive, interrupt, and nameplate overlay icons including interrupt cast-aura mini-icons.

## [4.22.0] - 2026-05-18

### Changed
- `Options/General.lua` + `Options/Overlay.lua`: Switched remaining display/overlay state setters that affect defensive visibility/layout to `ForceUpdateAll()` so offensive and defensive queues refresh on the same immediate tick after option changes
- `JustAC.lua`: On `PLAYER_REGEN_DISABLED`, now clears spell availability cache before forcing updates to prevent first-engage defensive delay after reload/enable when startup false availability entries were cached
- `JustAC.lua`: `OnSpecChange()` and `OnEquipmentChanged()` now use `ForceUpdateAll()` so defensive queue updates immediately when spec spell sets or equipped defensive items change
- `JustAC.lua` + `Options/General.lua`: Added disabled->enabled warm-start priming (clear spell availability cache + immediate defensive health pass) in `ExitDisabledMode()` and global display-mode transitions from `disabled`, preventing first-target defensive lag after re-enabling
- `Options/Core.lua`: `/jac toggle` resume path now performs warm-start priming (clear spell availability cache + immediate defensive health pass + `ForceUpdateAll`) so first-target defensives are immediate after unpausing
- `Options/StandardQueue.lua` + `Options/Overlay.lua`: re-enabling defensive icon visibility now primes defensives immediately (spell availability cache clear + immediate health pass) before full refresh, preventing first-target delay after turning defensive displays back on
- `build.ps1`: `$coreFiles` now derived from `JustAC.toc` at build time instead of a hardcoded list - new `.lua` files added to the TOC are automatically included in the distribution ZIP
- `UI/UIRenderer.lua`: Extracted `MatchesSpellOrOverride()` helper from duplicated `C_Spell.GetOverrideSpell` check blocks in `MatchActiveCast` and the defensive-icon active-cast detection; no behaviour change
- `BurstInjectionEngine.lua`: Removed the local `GetSpecKey()` wrapper and replaced it with a direct cached `SpellDB.GetSpecKey` function reference at all call sites (nil-safe), reducing indirection without changing behaviour
- `UI/UIFrameFactory.lua` + `UI/UINameplateOverlay.lua`: Added `ApplyTextOverlaySettingsToIcons()` and switched nameplate Masque skin callback to use it, removing duplicated icon-loop text-overlay application logic
- `Options/Core.lua` + `Options/StandardQueue.lua` + `Options/Overlay.lua`: Centralized display-mode disabled predicates in Options/Core (`IsStandardQueueDisabled`, `IsOverlayDisabled`) and wired both tabs to reuse them with local fallback behavior
- `UI/UIRenderer.lua`: `MatchesSpellOrOverride()` now uses `BlizzardAPI.GetDisplaySpellID()` (cached override resolution) and no longer calls `C_Spell.GetOverrideSpell` directly
- `UI/UIRenderer.lua` + `UI/UINameplateOverlay.lua`: Extracted shared player cast/channel-state resolution (`ResolvePlayerCastState`) into UIRenderer and reused it from nameplate overlay to remove duplicate grey-out logic
- `UI/UIFrameFactory.lua`: Standard queue Masque callback now uses `ApplyTextOverlaySettingsToIcons()` for defensive icons, removing the remaining duplicated icon-loop text-overlay block
- Style consistency pass: normalized module/import declaration formatting in `UI/UINameplateOverlay.lua`, cleaned and simplified sub-module declaration/assembly formatting in `Options/Core.lua`, and tightened `build.ps1` TOC path filtering regex for clearer intent

## [4.21.1] - 2026-05-10

### Fixed
- Raise Dead no longer shows for Blood and Frost Death Knights. It is now scoped to Unholy (spec 3) only, since Blood/Frost ghouls are Guardians rather than persistent pets.

### Changed
- Debug command surface consolidated to a single `inspect` namespace. All diagnostic sub-commands now live under `/jac inspect <topic>` and `/jac find [spell]`.

**Removed commands and their replacements:**

| Old command | New command |
|---|---|
| `/jac modules` | `/jac inspect modules` |
| `/jac testcd [spell]` | `/jac inspect cooldown [spell]` |
| `/jac defensive`, `/jac def` | `/jac inspect defensives` |
| `/jac interrupts`, `/jac int` | `/jac inspect interrupts` |
| `/jac burst` | `/jac inspect burst` |
| `/jac poisons`, `/jac poison` | `/jac inspect auras` |
| `/jac perf`, `/jac stats` | `/jac inspect perf [reset]` |
| `/jac diag` (alias) | `/jac inspect <topic>` |
| `/jac config`, `/jac options` | `/jac` (blank) |

**Removed with no replacement** (dead/broken commands): `test`, `formcheck`, `raw`, `testmacro`, `macrostats`.

## [4.21.0] - 2026-05-04

### Performance
- **Options/Overlay.lua**: Narrowed 7 over-broad `ForceUpdateAll()` → `ForceUpdate()` for display-only settings (overlay queue visibility, hide-when-mounted, opacity, offensive glow mode, offensive desaturation, offensive reset, defensive glow mode). Display settings don't require defensive queue rebuild. Two calls retained for `defensiveDisplayMode` change and defensive reset (may affect evaluation timing).
- **Options/GapClosers.lua**: Narrowed all 5 `ForceUpdateAll()` → `ForceUpdate()`. Gap-closers only affect the offensive queue.
- **Options/BurstInjection.lua**: Narrowed all 3 `ForceUpdateAll()` → `ForceUpdate()`. Burst injection only affects the offensive queue.
- **UI/UIRenderer.lua**: Added `changed` guard for state-3 (normal) `SetVertexColor` in `ApplyVisualState()`. Eliminates redundant GPU vertex color calls on every frame for icons that haven't changed visual state.
- **SpellQueue.lua**: Added debug-gated `spellQueueBuildCount` counter. Exposed via `GetBuildStats()` / `ResetBuildStats()`.
- **DefensiveEngine.lua**: Added debug-gated `defensiveBuildCount` counter. Exposed via `GetBuildStats()` / `ResetBuildStats()`.
- **DebugCommands.lua**: Added `/jac perf` command (debug-mode gated) showing offensive/defensive queue build counts and rates since last reset. `/jac perf reset` resets counters.
- **JustAC.lua**: `OnCooldownUpdate` and `OnActionUsableChanged` no longer reset the update timer out of combat. Both events now only set dirty flags OOC, letting the 0.5s idle cycle handle them - previously they called `ForceUpdateAll()` which woke the loop immediately, causing ~2-5% idle CPU from ability cooldowns and usability transitions firing in cities. In combat, timer reset is unchanged for full responsiveness. Reduces OOC CPU usage from ~9-12% to ~7%.
- **KeyPressDetector.lua**: Mouse button poll (`IsMouseButtonDown` × 3) throttled from every frame (~60-144Hz) to 30Hz. Detection latency capped at 33ms, imperceptible for flash feedback.

### Visual
- **UI/UIRenderer.lua**: Icon spell changes now fade in via the existing 100ms `fadeIn` animation instead of instant texture swap. Eliminates the visual pop when the queue shifts at combat start or during rotation.
- **UI/UIFrameFactory.lua**: `POSITION_HOLD_TIME` increased from 150ms to 200ms. Reduces high-frequency queue shuffles causing icons at positions 2+ to flash.

## [4.20.2] - 2026-05-04

### Fixed
- **Stale hotkey display after rearranging action bars**: `ACTIONBAR_SLOT_CHANGED` invalidated `spellHotkeyCacheValid` but left stale entries in `spellHotkeyCache` and `spellSlotCache`. The per-spell stale-refresh throttle (0.25s) then returned the old hotkey text before the full rescan ran. `InvalidateHotkeyCache` now wipes all four caches so the first post-event lookup always does a fresh scan.
- **Stale slot data on bonus bar change**: `InvalidateStateCache` (called on `UPDATE_BONUS_ACTIONBAR`) only wiped `spellHotkeyCache` and `slotMappingCache`, leaving `spellSlotCache`, `slotDirectCache`, and `itemSlotCache` with stale slot numbers from before the bonus bar appeared. `GetSlotForSpell` and the transform fast-path in `GetSpellHotkey` would use those stale slots and re-cache wrong hotkey bindings before a full action bar scan could run.

## [4.20.1] - 2026-05-04

### Internal
- **Consistency / dead-code removal**
  - `DebugCommands.lua`, `JustAC.lua`: Replaced `BlizzardAPI.IsMidnightOrLater()` runtime calls with the pre-computed `BlizzardAPI.IS_MIDNIGHT_OR_LATER` constant.
  - `UI/UIFrameFactory.lua`: Exported `POSITION_HOLD_TIME` (150 ms) and `GLOW_HOLD_TIME` (100 ms) hysteresis constants; `UI/UIRenderer.lua` and `UI/UINameplateOverlay.lua` now read from those exports instead of local duplicates.
- **Refactoring - no behaviour change**
  - `JustAC.lua`: Split `NormalizeSavedData()` into five named migration helpers (`MigrateBlacklist`, `MigrateDefensiveSpecKeys`, `MigrateHotkeyOverrides`, `MigrateLegacySettings`, `MigrateSoundKeys`).
  - `JustAC.lua`: `InvalidateCaches()` if-chain replaced with `CACHE_INVALIDATORS` closure table.
  - `UI/UIAnimations.lua`: Extracted shared `ShowColoredProcGlow` / `HideColoredProcGlow` helpers; interrupt/burst glow functions reduced to one-line delegates.
  - `Options/Core.lua`: Six `Options.UpdateX` wrappers replaced with `FORWARDERS` generation loop; added `Options.RefreshAllDynamic(addon)` batch helper; call sites consolidated.
  - `Options/SpellSearch.lua`: Added `SpellSearch.ClearDynamicArgs(argsTable, staticKeys)` utility; used in `Options/Offensive.lua`, `Options/CustomQueue.lua`, `Options/Defensives.lua` to replace manual two-loop key-clearing.
  - `Options/Defensives.lua`: Extracted `IsPetRezClass()` / `IsPetHealClass()` module-local helpers; six duplicate `hidden` closures reduced to one-line delegates.
  - `UI/UIFrameFactory.lua`: Exported `CreateBaseIcon`; `UI/UINameplateOverlay.lua` replaced its 200-line duplicate icon-creation body with a ~60-line version delegating to `UIFrameFactory.CreateBaseIcon`.
- **Bug fix - charge display in combat**
  - `UI/UIRenderer.lua`: `GetSpellCharges().maxCharges` is NeverSecret (source-verified against WoW 12.0.5). Removed the `GetCachedMaxCharges` fallback that was treating it as secret - the cache could be nil after a spec-change cache wipe before combat started, silently suppressing charge count display. `chargeInfo = result` assignment remains OOC-only since `currentCharges`/`cooldownDuration`/`cooldownStartTime` are still SECRET in combat; `chargeText` now set unconditionally for spells with `maxCharges > 1` (secret value passes through `FontString:SetText` safely).

## [4.20.0] - 2026-04-16

### Added
- **Korean (koKR) locale**: Full translation of all UI strings.
- **Locale sync**: All non-English locales (deDE, esES, esMX, frFR, ptBR, ruRU, zhCN, zhTW) updated with missing keys: Show Usability Tint, Show Range Tint, Show Casting Highlight, Queue Orientation detached desc, Proc Priority, updated Blacklist Info/Warning, Burst Injection section, Custom Queue section, Detached defensive frame section.

## [4.19.4] - 2026-04-14

### Fixed
- **Interrupt/CC CD detection broken - Kick re-recommended while on cooldown**: `IsInterruptOnCooldown()` in `SpellDB.lua` was always fail-open. A file-scope `LibStub("JustAC-BlizzardAPI", true)` captured nil because `SpellDB.lua` loads before `BlizzardAPI.lua` in `JustAC.toc`. Every call hit the nil guard and returned false, making every spell appear ready regardless of actual cooldown state. Fixed with a lazy getter that resolves on first call after all libraries are loaded.
- **`CheckCooldownCompletions` prematurely clearing interrupt/defensive CDs**: Was treating `isOnGCD == true` from `SPELL_UPDATE_COOLDOWN` as "real CD done" for all tracked categories. For unflagged spells (Kick, Blind, defensives etc.), `isOnGCD == true` fires during the GCD window after the cast - not as a CD-expiry signal. Restricted this clear to `"rotation"` category only (the only category that reliably uses Blizzard's flagged `nil → false → nil` CD state machine).
- **`CheckUsabilityFlips` clearing local CDs via `ACTION_USABLE_CHANGED`**: Was wiping `localCooldowns[spellID]` whenever `usable=true` fired for a slot, assuming it meant the CD expired. `IsUsableAction` returns true even while a spell is on cooldown, so energy ticks and target changes were clearing active CDs. Removed flat `localCooldowns` clearing from this path; charge recovery hints preserved.
- **CC-failure learning incorrectly triggered by interrupt spells**: Kick, Wind Shear, Counterspell, and other pure interrupts are in `CROWD_CONTROL_SPELLS` (for DPS rotation exclusion). This caused `NotifyCCCastOnTarget()` to fire on every successful interrupt cast. 0.4 s later `UnitIsCrowdControlled("target")` returns false (interrupts don't apply a CC mechanic), setting `ccFailureObserved = true` and marking the target as CC-immune for the rest of combat - suppressing Blind and all other CC fallbacks. Fixed: added `SpellDB.IsInterruptTypeSpell()` (lazy set from `CLASS_INTERRUPT_DEFAULTS` type="interrupt" entries) and guarded `NotifyCCCastOnTarget()` to skip pure interrupt spells.

### Added
- **`/jac interrupts` command**: Dumps the resolved interrupt/CC list with per-spell CD state (`IsInterruptOnCooldown`, `localCD`, `IsReady`, `usable`, `isOnGCD`), plus target interrupt-worthy, CC-immune, and current interrupt mode. Useful for diagnosing interrupt/CC queue issues in combat.
- **`/jac testcd` extended**: Now includes `C_Spell.GetSpellCooldown` raw `isOnGCD` field, `IsSpellOnLocalCooldown`, `IsSpellReady`, and `IsInterruptOnCooldown` output (section 5 and 6).

## [4.19.3] - 2026-04-14

### Fixed
- **MacroParser - leading `!` prefix on spell names**: Macros using `!Spell` (repeat-cast toggle, e.g. `!Bear Form`, `!Stealth`) were never matched because `DoesSpellMatch` compared the raw `"!bear form"` against `"bear form"`; the `!` is now stripped before comparison (`MacroParser.lua`)
- **MacroParser - condition tokens not lowercased**: `[MOD:SHIFT]`, `[Form:1]`, and `[ mod : shift ]` (spaces around `:`) were silently ignored because `EvaluateConditions` matched condition strings case-sensitively; tokens are now lowercased before pattern matching (`MacroParser.lua`)

## [4.19.2] - 2026-04-14

### Fixed
- **MacroParser v23 - OR-cascade multi-bracket evaluation**: Cascading bracket groups (`[spec:1][spec:2] Spell`, `[cond1][cond2][] Spell`) only evaluated the first group; all groups now iterated in OR-cascade order - first passing group wins, `[]` is unconditional fallback (`MacroParser.lua`)
- **MacroParser v23 - `[stance:N]` / `[nostance:N]` aliases**: Warrior, DK, and Rogue macros using stance aliases instead of `[form:N]`/`[noform:N]` were silently ignored; now evaluated against `FormCache.GetActiveForm()` (`MacroParser.lua`)
- **MacroParser v23 - bare `[form]` / `[noform]`**: Without `:N`, `[form]` always failed and `[noform]` always passed; both corrected. Same fix for `[stance]`/`[nostance]` (`MacroParser.lua`)
- **MacroParser v23 - `/castsequence` detection**: Sequence spell lists were never split - `reset=N` prefixes now stripped, list split by comma; `[condition]` evaluated once and applied to all spells in sequence (`MacroParser.lua`)
- **MacroParser v23 - quality score condition count**: Brackets counted across the entire cast line instead of only the matching clause, inflating scores for multi-clause lines (`MacroParser.lua`)
- **MacroParser v23 - name prefix heuristic**: 2-char prefix match bonus caused false macro-name promotions; raised to 4-char minimum with plain-string matching (`MacroParser.lua`)
- **CC interrupt-fallback list audit**: Evoker had wrong spell ID 357208 (Fire Breath, not Oppressing Roar) in both `CLASS_INTERRUPT_DEFAULTS` and `CROWD_CONTROL_SPELLS` - Fire Breath was excluded from DPS rotation suggestions; real Oppressing Roar (372048) extends CC duration but doesn't apply CC, removed as fallback. Shaman Sundering (197214) removed - incapacitate breaks from auto-attacks immediately. Priest CC order corrected: Psychic Horror (stun) before Mind Bomb before Psychic Scream (`SpellDB.lua`)
- **Interrupt queue - Rogue CC fallback**: Blind (2094) added to `CLASS_INTERRUPT_DEFAULTS.ROGUE` before Kidney Shot - no combo points required, most reliably castable CC when Kick is on cooldown (`SpellDB.lua`)
- **Interrupt queue - Kick CD not tracked after spec change**: `ScanCooldownDurations` now populates `cachedDurations` via tooltip + `GetSpellBaseCooldown` fallback for spells that are currently ready (`cd.duration=0`); previously a spec change wiped the cache and ready spells were skipped, so the first in-combat cast had no duration and local CD was never recorded (`BlizzardAPI/CooldownTracking.lua`)
- **WoW 12.0.5 - aura instance ID re-randomization**: `auraInstanceID` values re-randomize on encounter/M+/PvP entry; `RedundancyFilter`'s instance maps were never flushed mid-session, causing stale IDs to incorrectly mark expired auras as active; `FlushInstanceMaps()` now called on `ENCOUNTER_START`, `CHALLENGE_MODE_START`, `PVP_MATCH_ACTIVE` (`RedundancyFilter.lua`, `JustAC.lua`)
- Nameplate Overlay: DPS/defensive icons now anchor to `HealthBarsContainer` instead of the root nameplate frame, fixing vertical alignment (`UINameplateOverlay.lua`)
- Nameplate Overlay: `NAMEPLATE_GAP` split into left=12 / right=14 to compensate for Blizzard's asymmetric health bar texture (`UINameplateOverlay.lua`)
- Nameplate Overlay: `ClassificationFrame` and `RaidTargetFrame` repositioned to avoid collision with icon clusters; restored to defaults on overlay detach (`UINameplateOverlay.lua`)
- Nameplate Overlay: inter-queue spacing floored at `BAR_SPACING` regardless of the `iconSpacing` setting; gap now uses `iconSpacing` directly (`UIFrameFactory.lua`, `UIHealthBar.lua`)
- Nameplate Overlay: Masque `AddButton`/`RemoveButton` skipped in combat - `Button:GetSize()` returns secret on JustAC frames causing arithmetic crash; pending removals cleaned up on next out-of-combat `Destroy` (`UINameplateOverlay.lua`)
- `BurstInjectionEngine`: injection candidates were not checked with `IsSpellUsable`; spells with insufficient resources no longer injected (`BurstInjectionEngine.lua`)
- `UIAnimations`: `icon:GetWidth()` crashes in 12.0 combat on nameplate overlay icons; `cachedIconSize` stored at creation and used as NeverSecret fallback in glow scale calculations (`UIAnimations.lua`, `UIFrameFactory.lua`, `UINameplateOverlay.lua`)
- `OnUnitAura` aura-cache invalidation throttle reduced from 500ms to 100ms (`JustAC.lua`)
- Options > General > Reset to Defaults wrote `interruptAlertSound = "none"` (lowercase), mismatching schema default `"None"`; "Test Sound" button stayed permanently enabled
- Options > Icon Labels > Nameplate Overlay: text color and anchor changes silently discarded on reload; setters now write to central `profile.textOverlays`
- Schema: added `greyOutWhileCasting` / `greyOutWhileChanneling` to AceDB defaults; removed dead `blacklistPosition1` key

### Performance
- `UnitCastingInfo` / `UnitChannelInfo` removed from render hot-path; replaced with event-driven caching via `UNIT_SPELLCAST_START/STOP` / `UNIT_SPELLCAST_CHANNEL_START/STOP` (`UIRenderer.lua`, `UINameplateOverlay.lua`, `JustAC.lua`)
- `GetQueueDesaturation()` call inlined in `RenderSpellQueue` hot-path (`UIRenderer.lua`)
- `ActionBarScanner`: `currentBarSlots`, `fallbackSlots`, `candidates` hoisted to module-level pre-allocated tables; `modifiers = {}` replaced with shared `EMPTY_MODIFIERS` sentinel (`ActionBarScanner.lua`)
- `RedundancyFilter.PruneExpiredActivations`: `IsRedundancyFilterAvailable()` hoisted out of per-spell loop (`RedundancyFilter.lua`)
- `IsRedundancyFilterAvailable` / `IsProcFeatureAvailable`: force-refreshed on `PLAYER_REGEN_ENABLED` / `PLAYER_REGEN_DISABLED`; `FEATURE_CHECK_INTERVAL` raised from 5s to 30s (`JustAC.lua`, `BlizzardAPI/SecretValues.lua`)

## [4.19.1] - 2026-03-25

### Fixed
- **Burst injection ignoring cooldowns** - Injection spells (e.g., Lunar Beam, Convoke) could be suggested while on cooldown. Lazy-resolve path now seeds pre-existing cooldowns; removed false-positive usability cross-check that immediately cleared local CD timers for unflagged spells.
- **Glow animations at combat exit** - Blue crawl could disappear and proc glow could freeze in the offensive queue, while defensive glows kept animating. Fixed pause/resume to cover both icon pools, use correct animation freeze, and guard the OOC pause timer against stale firing during combat re-entry.

## [4.19.0] - 2026-03-25

### Added
- **Custom Queue** - Define a custom spell/item ordering for positions 2+ (Offensive > Custom Queue). Auto-seeds from Blizzard's rotation on first enable. Unavailable or on-cooldown entries collapse automatically. Per-spec, stored in profile.
- **Custom Queue Item Support** - Trinkets and on-use items can be added to the Custom Queue alongside spells.
- **Stale Queue Detection** - Warning banner when Blizzard's rotation changes (talent swap, patch). "Merge Changes" preserves custom ordering while syncing additions/removals; "Refresh from Rotation" fully resets.

### Changed
- **Burst Injection Pending Detection** - Trigger detection now scans all visible queue positions, not just position 1. Triggers at any position show burst glow. Active phase (aura-based injection) is unchanged.

## [4.18.1] - 2026-03-24

### Fixed
- Fix charge count text disappearing on macro-bound spells during modifier key presses. Spell API charge data now takes priority over slot-based data (which can resolve to the wrong spell when a macro conditional changes). Charge count is now shown consistently, including at max charges.

## [4.18.0] - 2026-03-24

### Added
- Highlight-mode lookahead for blacklisted position 1: when a blacklisted spell is also hidden from action bars (removed or placed behind a modifier macro), JustAC tries Blizzard's visible-button-only suggestion to substitute a better next-cast spell at position 1. Falls back to rotation list if highlight returns nil. (SpellQuery v1, SpellQueue v38)

### Fixed
- Fix cooldown swipe crash on build 66562+ (`ActionButton_ApplyCooldown` no longer accepts secret values from tainted execution). Uses new DurationObject-based rendering path: `C_ActionBar.GetActionCooldownDuration` / `C_Spell.GetSpellCooldownDuration` → `SetCooldownFromDurationObject`. Items use `C_DurationUtil.CreateDuration()`. Pre-66562 builds fall back to `ActionButton_ApplyCooldown`. (BlizzardAPI v35, UIRenderer v23)

## [4.17.1] - 2026-03-19

### Fixed
- Fixed profile panel modifications (description cleanup, spec-switching controls) leaking into other addons' profile tabs via shared AceDBOptions args table

## [4.17.0] - 2026-03-18

### Added
- Per-spell **Proc Priority** toggle in Defensives options - uncheck to keep a procced spell in its configured list position instead of jumping to the front of the queue (it will still glow)
- **LibSharedMedia-3.0** integration for interrupt alert sounds - users can select any sound from installed SharedMedia packs. 14 curated built-in alert sounds registered as "JAC: ..." entries.

### Changed
- Curated interrupt alert sounds from 23 down to 14, focused on alert utility. Added: Night Elf Bell, Raid Emote, Algalon Black Hole, Worgen Transform, Loatheb Aggro, Horseman Laugh. Removed novelty/ambient sounds (Rubber Ducky, Cartoon FX, etc.). Users with removed sounds are migrated to "None".
- Updated defensive spell tables for Midnight 12.0 compatibility

## [4.16.0] - 2026-03-17

### Changed
- **Aura-based burst windows** - Burst injection now activates when the trigger spell's self-buff aura is active on the player (e.g., the full 20s of Avenging Wrath), not just while Blizzard recommends the CD at position 1. Window ends when the aura expires or all injection spells are on cooldown. Trigger spell at position 1 now shows burst glow as a "press to start burst" signal without injecting.
- **Timer fallback for non-aura triggers** - Triggers that don't create a player self-buff (pet summons, target debuffs) fall back to a fixed-duration burst window based on per-spec defaults.
- Removed obsolete Burst Trigger Threshold slider from options (replaced by aura-based detection).
- Cleaned up Burst Injection panel labels - removed verbose/outdated text, removed redundant headers, class defaults now always visible.

### Added
- `/jac burst` now shows aura-based burst window status (active/inactive).
- Fallback Window Duration slider - controls burst window length when the trigger doesn't create a self-buff.

## [4.15.1] - 2026-03-17

### Fixed
- Displaced primary spell (pushed to slot 2 by gap-closer/burst injection) now shows its blue glow immediately instead of delayed by hysteresis debounce.

### Added
- Burst injection purple glow now appears in nameplate overlay (parity with standard queue display).

## [4.15.0] - 2026-03-17

### Added
- **Burst Injection Engine** - Detects burst windows and injects off-cooldown burst abilities at position 1 with purple glow. Curated per-spec trigger defaults with dynamic cooldown tracking.
- **Per-item defensive settings** - Items can be linked to a buff aura and/or hidden during combat. "Hide in Combat" defaults to on when linking an aura.
- **Off-bar spell display** - Cooldown swipes, charge counts, and usability checks now work for spells not on action bars via assisted combat slot fallback.
- **CC/interrupt spell completeness (SpellDB v9)** - Added Strangulate, Typhoon, Bursting Shot, Polymorph variants to CC lists; Strangulate as DK interrupt fallback.

### Changed
- **Cooldown display consolidation** - Single-pass slot resolution, single charge query, unified charge text. Removed redundant API calls and duplicated fallback branches.
- **Improved CDR detection** - Local cooldown timers detect early CD completion via action bar usability cross-checks and `ACTION_USABLE_CHANGED` flip detection. Fixes 5-30s drift after CDR procs.

### Fixed
- Fixed burst injection showing on-cooldown spells - cooldown tracking registrations for burst/gapcloser/interrupt categories no longer wiped on target switch; pre-existing CDs seeded at login/spec-change
- Fixed unselected choice-node talents (e.g. Incarnation vs Convoke) passing spell availability checks - `IsSpellAvailable` now checks `IsSpellKnown`/`IsPlayerSpell` before the spellbook API, which incorrectly returns true for all options in a talent choice row
- Fixed interrupt icon showing kick on cooldown instead of falling back to CC spells
- Fixed "Require Hostile Target" hiding queue when target is out of range
- Fixed rotation cache not invalidating on target change

## [4.14.1] - 2026-03-16

### Changed
- Range tint: out-of-range now shows red hotkey text + slight icon desaturation when hotkey text is visible; full icon red tint reserved for spells with no keybind
- Burst injection: removed time-based window - injection now only occurs while the trigger spell is in position 1; window duration slider removed from options
- Options: moved Queue Visibility and Hide When Mounted above the tabs in Standard Queue and Nameplate Overlay sections
- Options: consistent spec indicators on spell list headers (class-colored) across Blacklist, Gap-Closers, and Burst Injection tabs; fixed unlocalized "Gap-Closers" string
- Cooldown tracking: unified `RegisterSpellForTracking(spellID, category)` API replaces `RegisterDefensiveSpell`/`RegisterRotationSpell` - explicit categories (`"defensive"`, `"rotation"`, `"burst"`, `"gapcloser"`, `"interrupt"`) determine behavior; only `"rotation"` has the 3s CD gate; duration always cached regardless of category; old APIs kept as legacy wrappers

### Fixed
- SpellDB: Guardian Druid burst injection default was Strength of the Wild (236716, PvP ability) instead of Berserk/Incarnation/Convoke - replaced with {50334, 102558, 391528}
- SpellDB: Guardian Druid defensive list referenced removed spell 106922 (Might of Ursoc) instead of Rage of the Sleeper (200851)
- Burst injection: secret values from `GetSpellBaseCooldown` in combat caused threshold comparisons to always pass - now detected and rejected, with base cooldowns pre-cached out of combat
- Burst injection: injection spells now registered for local CD tracking at initialization (OOC) - previously only registered in combat where `RegisterRotationSpell` silently failed
- Cooldown detection: removed CDR cross-check in `IsSpellReady` that cleared local CD timers when `IsUsableAction` returned `true` - `IsUsableAction` returns true even on cooldown, causing local timers to be immediately cleared on every query
- Cooldown detection: removed deceptive `actionUsable == true → return true` fallback from `IsSpellReady` - `IsUsableAction` returns true even on cooldown, so this was indistinguishable from the fail-open default
- Burst injection: Options panel showed empty spell lists when opened via grab tab - `OpenOptionsPanel()` was missing `UpdateBurstInjectionOptions`
- Cooldown detection: SpellQueue and DefensiveEngine now use `IsSpellReady()` - gains `isOnGCD` early-return, CDR cross-check, charge spell handling, and action bar usability fallback

## [4.14.0] - 2026-03-15

### Added
- **Burst Injection**: New feature that injects priority spells (secondary CDs, empowered abilities) into queue position 1 during burst windows. Triggers automatically when Blizzard recommends a spell with a base cooldown ≥ 45s. Configurable trigger threshold, per-spec trigger and injection spell lists. Purple marching-ant glow on injected icons. Options tab under Offensive.
- **Detected Burst Triggers display**: Options panel shows auto-detected trigger spells from the current rotation, so users know what will fire the burst window without manual configuration.
- Burst injection defaults for all 37 DPS/tank specs (13 classes), including the new Devourer Demon Hunter spec (The Hunt, Void-Scarred).

## [4.13.1] - 2026-03-15

### Changed
- Replaced broken `SetAlphaFromBoolean` secret-resolution probe with `TargetFrame.spellbar:IsInterruptable()` attempt in `ResolveSecretBool`. Neither resolves secrets from addon context (barType is tainted), but removes dead `CreateFrame` allocation.
- Cached `LibStub("JustAC-BlizzardAPI")` at file scope in SpellDB.lua for `IsInterruptOnCooldown` hot path (eliminates redundant hash lookup 2-5× per frame during interrupt evaluation)

### Known Issues
- **Non-interruptible cast detection fails with some nameplate replacement addons.** When a third-party addon disables or replaces the Blizzard nameplate cast bar, JustAC cannot distinguish non-interruptible (grey bar) casts from interruptible ones - kicks/CC may be suggested on non-interruptible casts. This is a WoW 12.0 limitation: `notInterruptible` from `UnitCastingInfo()` is secret in combat, and no known addon-accessible API can resolve it. Blizzard's default nameplate cast bar resolves it internally via Icon visibility (`HideIconWhenNotInterruptible`), but addons that disable that bar remove the only working signal. Works correctly with Blizzard default nameplates.

## [4.13.0] - 2026-03-15

### Fixed
- Interrupt detection now works correctly with all nameplate addons - no longer depends on visible cast bar frames to determine interruptibility
- Fixed non-interruptible casts being treated as interruptible when switching targets mid-cast with third-party nameplate addons installed
- Secret `notInterruptible` values (12.0 combat) resolved through `SetAlphaFromBoolean` opaque pipeline instead of `SetShown` (which rejects secrets from addon code); falls back to existing cast bar cascade when probe fails
- **Fixed interrupt cooldown detection for unflagged spells (Kick, Pummel, etc.)** - `isOnGCD` stays `nil` for most interrupt spells even when on cooldown, so the old `isOnGCD == false` check never detected them as on-CD. Now delegates to `BlizzardAPI.IsSpellReady()` (local cooldown tracking via `UNIT_SPELLCAST_SUCCEEDED`). Interrupt spells are registered for local CD tracking at resolve time. This fixes Kick Priority mode not suggesting CC as fallback when the kick is on cooldown.
- **Fixed gap-closer cooldown detection** - Gap-closer spells (Charge, Shadowstep, Fel Rush, etc.) now registered for local cooldown tracking so `IsSpellReady()` can detect their CD state in combat when `isOnGCD` is `nil`.
- **Fixed local CD tracker ignoring cooldown reduction effects** - When passive CDR (Blade of Justice → Wake of Ashes, Anger Management, etc.) shortened a real cooldown below the local timer estimate, `IsSpellReady()` returned false too long because the local timer blocked the action bar usability fallback. Now cross-checks: if the local timer says "on CD" but the action bar shows usable, clears the stale timer and returns ready.

### Changed
- **Interrupt mode rework** - Renamed `Kick + CC` → `Kick Priority` (new default) and `Prefer CC` → `CC Priority` (now includes disclaimer about wasting CC cooldowns). `Kick Priority` kicks interruptible casts first, falls back to CC when kick is on cooldown, and uses CC on shielded (non-interruptible) casts. Previous `ccShielded` saved data automatically migrated.
- Cache `profile.textOverlays` once per render cycle in UIRenderer instead of re-reading 5-8 times per frame

## [4.12.0] - 2026-03-15

### Added
- **Usability tint**: Icons grey out when the spell is unavailable (CD/wrong form) and tint blue when lacking resources. Toggle in General options.
- **Range tint**: Icons tint red when the target is out of range. Toggle in General options.
- **Casting highlight**: White border overlay on the icon while its spell is actively being cast or channeled. Toggle in General options.
- **Wait label**: Nameplate overlay now shows the "WAIT" indicator when Assisted Combat is waiting for resources (parity with standard queue).

### Changed
- Consolidated visual state machine, range checking, casting highlight, and icon clear logic into shared helpers (`UIRenderer.CheckSpellRange`, `ResolveVisualState`, `ApplyVisualState`, `MatchActiveCast`, `UpdateCastingHighlight`, `ClearIconState`). Both standard and nameplate queues now call the same code paths.
- Nameplate overlay now uses slot-based range checking with spell API fallback (previously spell API only), matching standard queue behavior.
- Nameplate overlay icons now include `castingHighlight` and `centerText` widgets (parity with standard queue frames).
- Blue "no resources" tint updated from (0.3, 0.3, 0.8) to (0.4, 0.4, 1.0) across all render paths for consistency.
- Bumped UIRenderer to v21, UIFrameFactory to v14, UINameplateOverlay to v8.

## [4.11.0] - 2026-03-14

### Added
- **ACTION_USABLE_CHANGED event integration** - Event-driven slot usability cache in BlizzardAPI, populated by the batched `ACTION_USABLE_CHANGED` event (NeverSecret per-slot `usable`/`noMana` bools). `GetActionBarUsability()` now checks the event cache before falling back to the live `C_ActionBar.IsUsableAction()` API. Macro modifier effects are handled correctly: the C engine re-fires the event when a modifier key changes the effective spell on a slot, keeping the cache in sync. Cache is invalidated on slot content changes (`ACTIONBAR_SLOT_CHANGED`, page changes, vehicle/possess/override transitions).

### Fixed
- Charge counts no longer disappear from queue icons when the related ability is hidden from the action bar (e.g. by a modifier-conditional macro). Charge text now uses `C_Spell.GetSpellCharges` directly (validated against secret values) for accuracy, falling back to the slot-based `GetActionDisplayCount` in combat.
- Local cooldown duration cache now re-scans on `PLAYER_ENTERING_WORLD` and after talent/specialization changes, in addition to combat exit. This prevents first-combat edge cases where un-talented base cooldowns were used for spells whose durations are modified by talents.

### Changed
- Click-Through mode: grab tabs are now fully hidden, eliminating all dead zones. Hold Alt for 0.4 s to enter icon-drag mode - any queue or defensive icon becomes a drag handle. Brief Alt presses (modifier macros) are ignored by the hold threshold. Releasing Alt or finishing a drag exits icon-drag mode and restores full click-through.

## [4.10.3] - 2026-03-13

### Changed
- Click-Through mode: grab tabs (queue and defensive) are now fully hidden in click-through mode, eliminating the dead zone where clicks could not pass through to the game world. Hold Alt to temporarily reveal the drag handle for repositioning; releasing Alt (or finishing a drag) hides it again.

## [4.10.2] - 2026-03-12

### Changed
- Interrupt icon now uses a dedicated red-tinted proc glow instead of the generic marching-ants highlight
- Proc glow animation freezes out of combat (static frame, no looping flipbook)
- Gap-closer glow gold tint adjusted for better visibility

### Fixed
- LiveSearchPopup.lua missing from local build script
- build.ps1 no longer included in CurseForge package

## [4.10.1] - 2026-03-11

### Fixed
- Queue grab tab now remains draggable when interaction mode is set to Click Through

## [4.10.0] - 2026-03-11

### Added
- **Independent defensive frame** - defensives can now be detached from the main queue into their own draggable frame anchored to UIParent
  - Toggle in General options: "Independent Positioning"
  - Configurable growth direction (Left / Right / Up / Down) via "Detached Orientation" selector
  - Drag handle (grab tab) appears at the trailing edge of the icon cluster; right-click opens options
  - Frame position persists across sessions; "Reset Position" button returns it to center-screen
  - Detached frame stays visible regardless of Display Mode setting; fades in/out as icons appear and disappear

### Fixed
- Interrupt reminder now correctly suppresses CC suggestions in "Kick Only" mode - previously a CC spell could appear as a fallback when the kick was on cooldown
- CC spells in the interrupt reminder now use fail-closed usability checks - previously a CC on cooldown could appear usable in 12.0 combat due to secret value fail-open behaviour
- Defensive icons no longer flash during rebuilds - first-show now skips the fade-in animation
- Detached defensive frame and its grab tab now receive mouse input correctly (were not registering clicks)

### Improved
- Fade animation durations reduced from 150–200 ms to 100 ms across main frame, defensive frame, and individual icons for a snappier feel
- Defensive display options (display mode, max icons, scale, glow, health bars) remain accessible in the Standard Queue options panel when defensives are detached
- Interrupt Reminder option description notes that it does not trigger on training dummies or trivial adds
- Health bars reposition correctly when attached to the detached defensive frame, including vertical orientations with grab tab spacing

## [4.9.1] - 2026-03-10

### Fixed
- Hide standard and overlay queues when the player is in a vehicle or controlling an NPC via override action bar (quest vehicles, NPC possession scenarios)
- Fixed crash in GapCloserEngine when UnitGUID returns a secret value during target cycling macros in combat

## [4.9.0] - 2026-03-10

### Improved
- Cooldown sweeps, charge rings, and usability tinting now use Blizzard's native action bar pipeline for more accurate display
- Items in the defensive queue (potions, healthstones, etc.) now fully integrate with the same icon rendering as spells - cooldowns, hotkeys, tooltips, and proc glows all work consistently
- Internal code consolidation across several modules for better performance and maintainability

### Fixed
- Fixed glow effects not properly stopping or resuming across combat transitions (e.g. proc glow lost after leaving combat)
- Fixed charge-based defensive spells (e.g. Frenzied Regeneration) not greying out when all charges are depleted
- Fixed cooldown sweep occasionally getting stuck at 12 o'clock when a spell comes off cooldown
- Fixed charge recharge ring disappearing on spells placed behind macros
- Fixed resource darkening (blue/purple tint) on queue icons only lasting one frame
- Fixed gap-closer briefly disappearing when using target-cycling macros (e.g. /cleartarget + /targetenemy in a single keybind)

## [4.8.9] - 2026-03-09

### Added
- Item stack quantity display on defensive queue icons (e.g. healing potions show count via the charge text widget); controlled by the existing Count label toggle
- Hotkey override support for items: right-click defensive item icons to set custom hotkey, items searchable in Hotkey Overrides panel
- Hotkey Overrides search now includes items from equipped gear, action bars, and bags (was spells-only)

### Fixed
- Fixed cooldown sweep stuck at 12 o'clock when spell comes off cooldown in combat - `GetSpellCooldownDuration()` returns nil (no active CD) but the legacy `SetCooldown` fallback receives blanket-secreted zeros that addon code cannot evaluate; now handles nil DurationObject explicitly by clearing the sweep
- Same nil-DurationObject fix applied to charge cooldown ring (`GetActionChargeDuration` returning nil)
- Legacy `SetCooldown` path now uses NeverSecret `IsSpellReady()` fallback chain when startTime/duration are secret, instead of assuming the cooldown is active
- Fixed resource darkening (blue/purple tint) on standard queue icons only showing for one frame - vertex color now managed entirely by the visual state machine
- Fixed defensive priority list add/remove/reorder not updating the queue until reload - `updateFunc` now calls `ForceUpdateAll()`
- Fixed gap-closer list add/remove/reorder not updating until next combat event - `updateFunc` now calls `ForceUpdate()` after invalidating engine cache
- Fixed items on cooldown in defensive queue being dropped entirely instead of shown greyed out - `CheckDefensiveItemState` now returns all 3 values and on-CD items route to `unusableBuffer`
- Fixed defensive item icons showing blank/duplicate - `C_Item.GetItemInfo` was treated as returning a table; now uses proper tuple unpacking + `C_Item.GetItemIconByID`
- Fixed item hotkey text showing raw binding (e.g. "3") instead of formatted key (e.g. "+3") - new `GetItemHotkey()` in ActionBarScanner uses proper `GetOptimizedKeybind` + `AbbreviateKeybind` pipeline with macro modifier support
- Fixed item hotkey lookup using wrong binding names for multi-bar slots (`ACTIONBUTTON73` doesn't exist) - now uses cached slot mapping
- Fixed defensive item icon tooltip showing hotkey from wrong pipeline (spell-based `GetSpellHotkey` on cast spell ID) - now uses `GetItemHotkey` with override detection

### Changed
- "Charge Count" label renamed to "Count (Charges / Qty)" to reflect dual purpose
- Hotkey Overrides UI terminology updated: "Select Spell..." → "Select Spell/Item...", descriptions now mention items

## [4.8.8] - 2026-03-09

### Added
- Profiles: new option to use the shared Default profile for new characters instead of auto-creating a character-named profile (stored as a global setting so it applies before per-character data is loaded)

## [4.8.7] - 2026-03-09

### Fixed
- Gap-closer (e.g. Shadowstep) now recommended consistently at all distances outside melee range - removed `pos1InRange` gate in SpellQueue that incorrectly suppressed gap-closer injection when Blizzard's primary recommendation was a ranged filler (Shuriken Toss, etc.) castable at range
- Overlay queue: gap-closer glow now respects the glow mode setting - was bypassing `glowMode` entirely and could show the gold crawl even with glows disabled
- Overlay queue: gap-closer glow now takes priority over proc glow, matching standard queue behaviour
- Overlay queue: spell displaced from position 1 to position 2 by a gap-closer injection now shows the blue assisted glow (standard queue already did this)
- Overlay queue: queue icon desaturation slider now applies immediately when changed - was only re-applying on visual-state transitions, not on slider moves

## [4.8.6] - 2026-03-09

### Fixed
- RedundancyFilter, FormCache, UIRenderer, SpellQuery: Replace all hardcoded English spell/aura name matches with locale-safe equivalents - addon now works correctly on non-English clients
  - `IsPetReviveSpell`: name pattern → spell ID lookup (`{982, 55709}`)
  - `IsStealthSpell`: name pattern → spell ID lookup (`{1784, 1856, 5215, 58984}`); Vanish added
  - `IsPetSummonSpell`: removed; call sites use `IsPetSpell(spellID)` table lookup
  - `IsUniqueAuraSpell` fallback: Form/Stance/Presence/Aspect name patterns → `FormCache.GetFormIDBySpellID`
  - `IsDPSRelevant` fallback: name patterns replaced with `FormCache.GetFormIDBySpellID` + `IsPetReviveSpell`
  - `PruneExpiredActivations` stealth detection: `name:match("Stealth/Vanish")` → `IsStealthSpell(spellID)`
  - `PruneExpiredActivations` mount detection: `name:find("Mount")` → `C_MountJournal.GetMountFromSpell`
  - Mount redundancy check: extracted to `IsMountSpell()` helper (DRY)
  - Form redundancy fallback: English suffix guard removed; kept locale-safe `currentFormName == name` equality check
  - `IsSpellAvailable`: removed `subtext:lower():find("passive")` fallback (redundant; `C_Spell.IsSpellPassive` handles it)
  - `ScanSpellbookForFormSpells`: name pattern pre-filter removed; detection uses only `GetShapeshiftFormInfo`
  - `DetermineSpellFormTarget`: cancel-form name patterns removed; unmapped spells return nil and fail-open
  - "Waiting for resource" overlay: `name:find("^Waiting for")` → `spellInfo.iconID == 134377` (file IDs are locale-invariant)
- UIRenderer: "Waiting for resource" overlay label localised - displays `WAIT/WART/ATT./ESPE/AGRD/ЖДЁМ/대기/等待/ASPT` per client locale instead of hardcoded English `WAIT`

### Performance
- FormCache: `ScanSpellbookForFormSpells` reduced from O(numSpells × numForms) to O(numForms + numSpells) - build form-set once, then do O(1) membership checks per spellbook entry
- FormCache: `GetFormIDBySpellID` now stores a negative cache sentinel for non-form spells, short-circuiting the full fallback chain on repeated calls

## [4.8.5] - 2026-03-08

### Fixed
- RedundancyFilter: Poisons with <10 min remaining were still being filtered out of combat (FALLBACK 2 by-name check bypassed the expiry threshold)
- RedundancyFilter: Maintenance buffs (poisons, imbues, raid buffs, rites) now always filtered in combat - DPS takes priority

### Performance
- RedundancyFilter: Skip full aura scan in combat using `C_Secrets.ShouldAurasBeSecret()` pre-check (avoids 40 pcall iterations when all fields are known secret)
- SecretValues: Short-circuit `TestAuraAccess()` with `C_Secrets.ShouldAurasBeSecret()` (skip 5-aura probe loop in combat)
- StateHelpers: Skip per-value `IsSecretValue()` calls in `GetPlayerHealthPercent()` when `C_Secrets.HasSecretRestrictions()` is false (out-of-combat fast path)

## [4.8.4] - 2026-03-08

### Fixed
- Charge-based abilities no longer show a stationary yellow cooldown sweep - `SetCooldown` with `duration==0` or an already-expired cooldown (stale `startTime+duration` from the last GCD/recharge) parks the sweep at 12 o'clock; both cases now call `Clear()` instead
- Same expiry check applied to the charge-recharge ring (`chargeCooldown` widget)
- Both fixes guard against 12.0 secret values: opaque `startTime`/`duration` are passed through to `SetCooldown` (which handles them internally) rather than being compared
- Fixed cooldown sweep (yellow) getting stuck at 12 o'clock when spell comes off cooldown out of combat - now uses `dur:IsZero()` to detect finished cooldowns and calls `Clear()` instead of `SetCooldownFromDurationObject` with a zero-duration object (applies to both main and charge cooldown paths)
- Fixed `IsZero()` crash in combat - `IsZero()` is secret in combat; gate with `HasSecretValues()` (NeverSecret) to only call `IsZero()` when duration object has no secrets
- Fixed cooldown sweeps bleeding onto wrong icons during queue re-ordering (e.g. combat exit) - proactively `Clear()` stale cooldown widget when the spell identity on a button changes
- Fixed nameplate overlay showing yellow gap-closer crawl instead of blue assisted crawl when Blizzard recommends a gap-closer spell at position 1 - overlay now matches standard queue behavior (only synthetically injected spells get gap-closer glow)
- Fixed gap-closer priority not iterating to lower-tier spells when a higher-tier gap closer is out of range - all gap-closer candidates now validate range so out-of-range spells fall through (e.g. Shadowstep out of 25yd range → Sprint)
- Fixed gap-closer spells in macros (e.g. Sprint in `/use [mod]Item;Sprint`) never being suggested - simplified TryGapCloserCandidate to known + cooldown + range only; removed action-bar-slot gate and fail-closed usability check that rejected valid spells (especially in combat with secret values)
- Fixed gap-closer injection overriding Blizzard's #1 recommendation when the primary spell is already in range (e.g. AoE abilities with no range check) - now checks IsActionInRange on the primary spell's slot before injecting

## [4.8.3] - 2026-03-08

### Added
- Live-search popup (persistent floating frame) for all spell/item selection panels - replaces the broken AceConfig `input+select` pattern that lost EditBox focus on every keystroke
- Items (trinkets, on-use gear, bag items) now searchable in the Offensive blacklist, consistent with defensive spell lists
- Spellbook cache invalidated automatically on specialization change and `SPELLS_CHANGED`

### Changed
- Spellbook cache pre-computes `nameLower` and `idStr` at build time - eliminates per-keystroke string allocations during search
- Search popup uses `TOOLTIP` frame strata to always render above the WoW Settings panel
- Shared spell-search logic extracted into a private helper - `GetFilteredResults` and `GetFilteredSpellbookSpells` no longer duplicate the scan loop
- Removed dead options code: `filterState` table, unused `previewState` entries, `LookupSpellByName`, `CreateAddSpellInput`, orphaned `AceConfigRegistry` reference in SpellSearch

## [4.8.2] - 2026-03-07

### Added
- Sound Test button next to the Interrupt Alert sound dropdown - preview the selected sound without leaving the options panel

## [4.8.1] - 2026-03-07

### Fixed
- Overlay Reset to Defaults now correctly resets expansion direction to "down" (was incorrectly set to "out")
- Locales: Removed 30 dead/orphaned keys from all 8 non-English locale files
- Locales: Added 7–12 missing translation keys per locale (Grey Out While Casting/Channeling, Queue Visibility, Settings, Reset desc keys)
- Locales: All 9 locale files now have exactly 230 keys with 0 dead and 0 missing

## [4.8.0] - 2026-03-07

### Added
- Nameplate Overlay: First Icon Scale setting (scale the primary icon independently)
- Nameplate Overlay: Queue Icon Desaturation setting (desaturate non-primary icons)
- Nameplate Overlay: Show Pet Health Bar toggle (parity with Standard Queue)
- General tab: Offensive Queue section (Include Macro-Hidden Abilities, Insert Procced Abilities, Allow Item Abilities)
- General tab: Defensive Queue section (Insert Procced Defensives, Allow Items in Spell Lists, Auto-Insert Health Potions)

### Changed
- Nameplate Overlay: Max offensive/defensive icons increased from 5 to 7 (slider instead of dropdown)
- Options: Moved 6 cross-queue content toggles from Offensive/Defensives tabs to General tab
- Options: Removed Queue Content sub-tabs from Offensive and Defensives tabs
- Options: Defensives tab no longer uses sub-tab layout (flattened to single page)
- Options: Unified setting names across Standard Queue and Overlay (Icon Size, Max Icons, Queue Visibility, etc.)
- Options: "Enable Defensive Suggestions" renamed to "Show Defensive Icons" for consistency
- Options: Moved Icon Labels and Hotkey Overrides into General as sub-tabs (Settings, Icon Labels, Hotkeys)
- Options: Top-level tab count reduced from 7 to 5 (General, Standard Queue, Overlay, Offensive, Defensives)
- Locales: Cleaned up 10 orphaned locale keys, added Show Defensive Icons and Defensive Queue translations

### Removed
- Overlay-only fallback: standard queue no longer force-shows when overlay can't find a nameplate (was causing standard queue to persist permanently in overlay-only mode)

## [4.7.5] - 2026-03-07

### Fixed
- Defensive icon proc glow now re-evaluated every frame (was only set on queue rebuild, causing 0.1–0.5s stagnation)
- Defensive icon hotkeys now refresh when bindings change and retry empty results for proc override propagation (was only set once on queue rebuild)
- Defensive icon cooldown swipes now polled at the same 0.08s cadence as offensive icons, so CD resets from talent procs clear promptly
- Removed dead `UpdateDefensiveCooldowns()` comment that claimed it was called externally (it was never called)
- Range check (out-of-range red text) now updates per-frame instead of every 0.08s across all queues (main panel offensive, interrupt, and nameplate overlay)
- Usability/resource tinting (blue desaturated state) now updates per-frame instead of every 0.08s across all queues (main panel offensive, interrupt, and nameplate overlay)
- Position stabilization: offensive queue positions 2+ now hold their spell for 150ms before allowing replacement, preventing rapid icon cycling from proc/CD re-categorization (position 1 always passes through the Blizzard assistant suggestion immediately)
- Glow hysteresis: glow animations on positions 2+ require 100ms of stable desired state before switching, preventing jarring animation restarts from transient proc toggles (main panel, nameplate overlay, and defensive icons)

## [4.7.4] - 2026-03-07

### Added
- **Grey Out While Casting** option (General tab, on by default) - queue icons desaturate during hardcasts. The spell being cast stays full color. Applies to both standard queue and nameplate overlay.
- **Grey Out While Channeling** option (General tab, on by default) - the previously hardcoded channeling grey-out is now toggleable. The channeled spell stays full color with a fill animation.

### Changed
- Early ungrey threshold reduced from 200ms to 100ms - icons regain color closer to the end of a cast/channel for tighter timing.

## [4.7.3] - 2026-03-07

### Fixed
- Interrupt reminder now works correctly when third-party nameplate/target frame addons hide or replace the Blizzard cast bar. Previously, non-interruptible casts could incorrectly show the interrupt icon because the interruptibility check depended on visually inspecting the Blizzard cast bar's shield widget. The event tracker now reads `notInterruptible` directly from the API at cast start, making it self-sufficient.
- Cast aura icon on interrupt reminder now falls back to UnitCastingInfo/UnitChannelInfo when the Blizzard cast bar is hidden by third-party addons (both standard queue and overlay).
- Overlay interrupt icon in horizontal mode no longer overlaps the nameplate - now pops out above the first DPS icon instead of inline.
- Overlay defensive queue now rebuilds on periodic checks (every 0.5s) instead of only updating cooldown swipes. Icons for "always" and "combatOnly" display modes now appear promptly when cooldowns expire.
- Overlay defensive queue now includes pet rez/summon and pet heal spells (parity with main panel).
- Overlay hotkey caches now invalidate on binding changes (parity with main panel).
- Overlay defensive icons in "always" mode now appear and disappear instantly (no fade animation), matching DPS icon behavior. State-driven modes ("combatOnly", "healthBased") retain the fade-in/out for smooth transitions.
- Overlay health bar no longer re-anchors every tick - only repositions when the visible defensive icon count changes, eliminating visual flicker in vertical orientations.
- Overlay health bar in vertical expansion modes no longer starts at the wrong position (above icons) and jumps to the correct side position - it now always appears at the correct expansion-aware position immediately.
- Overlay health bar now shows immediately with correct health values when a nameplate appears - no longer requires a subsequent update tick to fill in.
- Overlay defensive icons in "always" mode no longer appear ~500ms later than DPS icons when targeting a mob out of combat for the first time.
- Overlay defensive icons no longer lag behind DPS icons by 1+ frames - defensive overlay now refreshes on the same update tick as the offensive overlay.

### Added
- Nameplate Overlay **Offensive Display** tab now includes a **Queue Visibility** dropdown ("Always", "In Combat Only", "Require Hostile Target") and a **Hide When Mounted** toggle. These settings are independent from the Standard Queue visibility options.

### Changed
- Unified update cycle architecture: all rendering now flows through a single OnUpdate loop. `ForceUpdate()`/`ForceUpdateAll()` set dirty flags instead of rendering synchronously, eliminating redundant mid-event renders.
- Removed redundant dual-path rendering in `OnProcGlowChange`, `OnTargetChanged`, `OnSpellcastSucceeded`, and `OnCooldownUpdate` - each now uses a single `ForceUpdateAll()` call.
- SpellQueue internal throttle aligned with main loop minimums (combat: 0.03s, OOC: 0.05s) so it never bottlenecks CVar-driven update rates.
- CVar `assistedCombatIconUpdateRate` changes now take effect immediately (invalidate cached rate on CVAR_UPDATE).

## [4.7.2] - 2026-03-06

### Fixed
- **Defensive queue hidden on first load after update** - Defensive icons were invisible until the user toggled the setting off/on. Two causes: (1) `SPELLS_CHANGED` didn't mark the defensive queue dirty, so even after spell APIs became available the defensive queue was never rebuilt; (2) the delayed 1-second `ForceUpdateAll` on `PLAYER_ENTERING_WORLD` reused stale spell availability cache entries (spells cached as unavailable during initial load when APIs weren't ready yet). Now `OnSpellsChanged` marks the defensive queue dirty, and the delayed timer clears the availability cache before rebuilding.

## [4.7.1] - 2026-03-05

### Fixed
- **Channeling detection fixed for 12.0** - `PlayerChannelBarFrame` was removed in the Dragonflight UI rework; replaced with `PlayerCastingBarFrame.channeling` (plain Lua boolean on CastingBarMixin). Icons now properly grey out during channeling.
- **Defensive icon visual parity with offensive queue** - Extracted `UIRenderer.UpdateDefensiveVisualState()` - a shared function handling channeling + usability states (channeling/no-resources/on-cooldown/normal). Called per-frame from both `RenderSpellQueue` and `UINameplateOverlay.Render`, giving defensives the same instant responsiveness as offensive queue icons. Previously defensives updated on a 0.5s timer, causing visible lag.
- **Overlay queue icons show no-resource blue tint** - Nameplate overlay queue icons now show the blue tint for insufficient resources (matching the standard queue), in addition to channeling grey-out.
- **Interrupt icon stays fully colored during channeling** - Interrupts are urgent actions the player may want to cancel a channel to use. Removed channeling desaturation from interrupt icons on both standard queue and overlay.
- **Early ungrey 200ms before channel ends** - Icons ungrey ~200ms before a channel finishes, letting the player see their next ability before the GCD unlocks. Uses `PlayerCastingBarFrame.value` (NeverSecret countdown timer) with secret-value safety guard.
- **Channeling fill animation on active spell** - When the player is channeling, the queue icon matching the channeled spell shows Blizzard's channel-fill animation (sliding atlas texture, same as action bar buttons) instead of desaturation. Identified via `UnitChannelInfo` spellID + `C_Spell.GetOverrideSpell` matching (resolves base→override spellID chain, e.g. Drain Life 689→234153). Works on both offensive and defensive queue icons. Other icons still grey out.

## [4.7.0] - 2026-03-05

### Fixed
- **Defensive defaults restore fixed** - "Restore Class Defaults" in the defensives panel did nothing and defensive spell lists were empty after profile reset. Root cause: Lua's `and` operator truncates multiple return values, so `return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()` dropped the second return value (`playerClass`), making it always `nil`. Every function that needed `playerClass` (RestoreDefensiveDefaults, InitializeDefensiveSpells, MigrateDefensiveSpellsToClassSpells, GetClassSpellList) bailed out early. Fixed `DefensiveEngine.GetDefensiveSpecKey()` and `GapCloserEngine.ResolveMeleeReference()` to use `if/then/return` pattern that preserves both return values.

### Changed
- **Gap-closer glow now on by default** - New profiles and "Reset Gap-Closer Settings" now enable the glow overlay on gap-closer icons, so users can immediately see when the addon recommends a movement ability.

### Code Cleanup & Consolidation

#### Dead Code Removal
- **Remove 7 dead `CLASS_*_DEFAULTS` assignments** - `CLASS_SELFHEAL_DEFAULTS` and `CLASS_COOLDOWN_DEFAULTS` tables were populated but never read after SpellDB took over spell list management. Removed assignments and stale header comment from `JustAC.lua`.
- **Remove 3 unused BlizzardAPI functions** - `GetCharData()`, `GetSpellCooldownValues()`, and `IsSpellOnGCD()` in `SpellQuery.lua` had zero callers. Removed ~63 lines.
- **Remove 2 dead addon wrappers** - `JustAC:IsSpellBlacklisted()` and `JustAC:GetBlacklistedSpells()` forwarded to SpellQueue but were never called. Removed from `JustAC.lua`.
- **Remove `verboseDebugMode` dead flag** - `MacroParser.lua` and `ActionBarScanner.lua` each had a `local verboseDebugMode = false` that was never set to `true`. Removed the variables and all guarded debug-print blocks (~20 lines in ActionBarScanner).
- **Remove unused `_interfaceVersion` local** - `SecretValues.lua` cached `BlizzardAPI._interfaceVersion` but never used it. Removed.
- **Remove `PERSONAL_AURA_SPELLS` table** - `RedundancyFilter.lua` maintained a 12-entry spell ID table that was only consumed by the third return value of `IsAuraSpell()`. No caller used the third value. Removed the table and simplified `IsAuraSpell()` to return 2 values `(isAura, isUniqueAura)`.
- **Remove unused `GetDebugMode` wrapper** - `FormCache.lua` defined a `GetDebugMode()` function that was never called. Removed.
- **Remove redundant `defensiveIcon` (singular) checks** - `self.defensiveIcon` was a backward-compat alias for `self.defensiveIcons[1]` (set/cleared together in UIFrameFactory). Three uses in `JustAC.lua` were redundant with the plural array loop or already covered by `defHidden` logic. Removed.

#### Wrapper Consolidation
- **Consolidate spec key computation** - `GapCloserEngine.GetGapCloserSpecKey()` and `DefensiveEngine.GetDefensiveSpecKey()` each reimplemented `UnitClass + GetSpecialization + concat`. Both now delegate to `SpellDB.GetSpecKey()`. Inline computations in `ResolveMeleeReference()` and `ResolveGapCloserSpells()` also replaced.
- **Consolidate `GetCachedSpellInfo` access** - `SpellQueue.GetCachedSpellInfo()` and `RedundancyFilter.GetCachedSpellInfo()` were thin wrappers around `BlizzardAPI.GetCachedSpellInfo()`. Removed both; all callers (SpellQueue, UIRenderer, UINameplateOverlay) now reference `BlizzardAPI.GetCachedSpellInfo` directly.
- **Fix `GetDebugMode` in MacroParser** - Was returning a dead `false` local instead of delegating to `BlizzardAPI.GetDebugMode()`. Now correctly returns the live debug mode state.
- **Extract shared `GetActionBarUsability` helper** - `SpellQuery.IsSpellUsable()` and `SecretValues.IsSpellReady()` both had identical 6-line inline patterns for action bar usability fallback. Extracted to `BlizzardAPI.GetActionBarUsability(spellID)` in `BlizzardAPI.lua`; both callers now delegate.
- **Consolidate tooltipMode migration** - Three `OnEnter` handlers in `UIFrameFactory.lua` each had an 8-line inline migration block converting legacy `showTooltips`/`tooltipsInCombat` to `tooltipMode`. Migration now runs once in `NormalizeSavedData()`; handlers read `profile.tooltipMode` directly.

#### Simplification
- **Simplify `CheckDefensiveSpellState` return values** - Was returning 5 values `(isUsable, isKnown, isRedundant, onCooldown, isProcced)` where `isKnown` was only used to gate `isUsable` (already encoded) and `onCooldown` was always `false`. Now returns 3 values `(isUsable, isRedundant, isProcced)`. Both callers in `DefensiveEngine.lua` updated.
- **Cache LibStub module references** - `JustAC.lua` had 11 inline `LibStub("JustAC-*")` re-fetches for modules already cached as upvalues in `LoadModules()`. Added `SpellDB` to upvalue list and `LoadModules()`; replaced all re-fetches with upvalue references. Also removed 2 unnecessary `LibStub and LibStub(...)` guards (LibStub is always available).
- **Remove duplicate `FormCache.OnPlayerLogin()` call** - `PLAYER_ENTERING_WORLD` called `FormCache.OnPlayerLogin()` immediately after `InitializeCaches()`, which already calls it. Removed the duplicate.

#### Module Separation & Consistency
- **Move `IsSpellReady()` from SecretValues → CooldownTracking** - Core cooldown readiness evaluator (46 lines) was in the wrong submodule. Now lives alongside the local cooldown tracking state it depends on (`IsLocalCooldownActive`, `cachedMaxCharges`), eliminating a backward dependency. Uses local references instead of `BlizzardAPI.*` for same-module state.
- **Move health/pet functions from SpellQuery → StateHelpers** - `GetPlayerHealthPercent()`, `GetPetHealthPercent()`, and `GetPetStatus()` moved to consolidate all health-related queries with `GetPlayerHealthPercentSafe()` and `GetLowHealthState()`.
- **Fix duplicate `GetAddon` in SecretValues** - `RefreshFeatureAvailability()` was calling `LibStub("AceAddon-3.0"):GetAddon(...)` directly instead of the cached `BlizzardAPI.GetAddon()`.
- **Standardize LibStub declaration style** - Convert 4 files using `MAJOR/MINOR` variable pattern to inline style (`LibStub:NewLibrary("name", N)`), matching the 22 other files: DefensiveEngine, GapCloserEngine, Options/Overlay, Options/Labels.
- **Standardize hot path cache labels** - All modules now use `-- Hot path cache` consistently. Changed from `-- Cached globals` (UIFrameFactory, DefensiveEngine, TargetFrameAnchor), `-- Hot path cached globals` (KeyPressDetector), and unlabeled (UINameplateOverlay).
- **Fix UIFrameFactory mixed profile access** - 5 occurrences of `addon.db.profile` converted to `addon:GetProfile()`, matching the file's other 13 uses. Eliminates mixed access pattern within the same file.
- **Consolidate `ForceUpdate`/`ForceUpdateAll`** - `ForceUpdate(includeDefensives)` is now the single implementation; `ForceUpdateAll()` delegates to `ForceUpdate(true)`. Eliminates 3 duplicate lines.
- **Clarify UINameplateOverlay bar constants** - Comment `BAR_HEIGHT` and `BAR_SPACING` to document they intentionally differ from `UIHealthBar` equivalents (5 vs 6, 2 vs 3).

## [4.6.1] - 2026-03-05

### Changed
- **Quest indicator replacement is now always active** when the nameplate overlay is enabled. Previously it was a separate toggle, but disabling it caused visual overlap between Blizzard's engine-rendered quest circles and the icon queue. The option has been removed; the replacement activates automatically with the overlay and restores the original CVar on disable.

## [4.6.0] - 2026-03-05

### Changed
- **Blacklist is now per-profile, per-spec.** Previously stored per-character (`db.char`), so switching profiles/specs kept the same blacklist. Now stored in `db.profile.blacklistedSpells["CLASS_N"]`, matching how defensive spell lists, gap-closers, and hotkey overrides work. Existing character blacklists are automatically migrated into the current spec's profile on first load.
- **Defensive spell lists are now per-spec.** Previously keyed per-class (`classSpells["WARRIOR"]`), so all specs shared one defensive list. Now keyed per-spec (`classSpells["WARRIOR_3"]`), allowing tank specs to have different defensive priorities than DPS specs. Existing per-class lists are automatically copied to all specs of that class on migration.
- **Spec-specific defensive defaults** for tanks and notable spec outliers: Blood DK, Vengeance DH, Guardian Druid, Feral Druid, Brewmaster Monk, Windwalker Monk, Protection Paladin, Shadow Priest, Protection Warrior. All other specs continue to use class-level fallback defaults.
- Blacklist tab and defensive spell list headers now show the active spec name for clarity.
- All spell lists (blacklist, defensives, gap-closers, hotkey overrides) now consistently live in `db.profile` and travel with profile switches/copies/resets.

## [4.5.8] - 2026-03-04

### Added
- **Input Preference setting** - New "Input Preference" dropdown (Auto-Detect / Keyboard / Gamepad) in General options. When both keyboard and controller bindings exist for the same action, the addon now selects the appropriate one based on this setting. "Auto-Detect" (default) uses controller glyphs when a gamepad is connected and keyboard text when disconnected. Handles `GAME_PAD_CONNECTED` / `GAME_PAD_DISCONNECTED` events for live hot-plug switching.

### Fixed
- Fixed keybind display always showing keyboard bindings even when a controller was connected, because `GetBindingKey()` returns multiple values but only the first was captured.

## [4.5.7] - 2026-03-03

### Removed
- **Single-Button Assistant warning**: Removed the startup warning requiring the Single-Button Assistant to be placed on an action bar. `C_AssistedCombat.GetRotationSpells()` and `GetNextCastSpell()` work regardless of button placement; the warning was unnecessary.

## [4.5.6] - 2026-03-03

### Changed
- **Overlay interrupt positioning**: Interrupt icon now anchors inline at "position 0" (between icon 1 and the nameplate edge) instead of perpendicular (above icon 1). Mirrors the standard queue's `CreateInterruptIcon` pattern. Queue icons 1+ never shift when the interrupt appears/hides. Cast aura direction adapts to expansion mode ("up" → below interrupt, otherwise above).

### Added
- **Replace Quest Indicator** (Overlay): Suppresses the engine-rendered quest exclamation mark (`!`) on nameplates and renders our own version above the nameplate center, preventing overlap with the icon queue. Uses `UnitIsQuestBoss()` for detection and `SetCVar("ShowQuestUnitCircles", "0")` for suppression. Original CVar restored on disable/unload. Enabled by default; toggle in Overlay → Layout.

### Fixed
- **RedundancyFilter v40**: NeverSecret aura timing data (duration, expirationTime) was always zero in combat. `GetAuraTiming` used `Unsecret()` which trusts `issecretvalue()` - returns `true` even for NeverSecret fields (generic marking). Switched to pcall arithmetic bypass (`auraData.duration + 0`) matching the pattern already used for spellId. Fixes long-duration buff expiration reminders (raid buffs, rogue poisons) not appearing when buffs near expiry.

## [4.5.5] - 2026-03-03

### Added
- **Instance-level CC immunity cache**: Mobs identified as CC-immune (bosses, certain elites) are now remembered by NPC ID for the duration of the instance. Repeat pulls of the same mob no longer re-learn CC immunity from scratch. The cache resets on zone change (`PLAYER_ENTERING_WORLD`). NPC IDs are extracted from `UnitGUID` out of combat and backfilled at combat end.

### Changed
- **Options panel reorganized**: Centralized per-surface display settings for better coherence.
  - **Standard Queue** now has 4 sub-tabs: Layout, Offensive Display, Defensive Display, Appearance.
    - **Offensive Display** sub-tab absorbs `maxIcons`, `firstIconScale`, `glowMode` from the Offensive tab.
    - **Defensive Display** sub-tab absorbs `enabled`, `displayMode`, `maxIcons`, `iconScale`, `glowMode`, `showHealthBar`, `showPetHealthBar` from the Defensives tab.
  - **Offensive** tab renamed its settings sub-tab to "Queue Content" (only content settings remain: `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities`).
  - **Defensives** tab renamed its settings sub-tab to "Queue Content" (only content settings remain: `showProcs`, `allowItems`, `autoInsertPotions`).
  - Tab order updated: General(1) → Standard Queue(2) → Overlay(3) → Offensive(4) → Defensives(5) → Labels(6) → Hotkeys(7) → Profiles(8).
- **Overlay defensive display mode**: Added "When Health Low" (`healthBased`) option for feature parity with the standard queue panel.
- **Overlay restructured into sub-tabs**: Layout, Offensive Display, Defensive Display - matching the Standard Queue's organization. Each sub-tab has its own scoped reset button.
- **Overlay glow modes split**: Offensive and defensive overlay icons now have independent Highlight Mode settings (`npo.glowMode` for offensive, `npo.defensiveGlowMode` for defensive), matching Standard Queue parity. Existing users' offensive glow setting is preserved; defensive defaults to "All Glows".

### Fixed
- **Overlay respects shared `showProcs` setting**: The nameplate overlay defensive queue previously hardcoded `showProcs=true`, ignoring the user's "Insert Procced Defensives" setting. Now correctly reads `profile.defensives.showProcs`.
- **Overlay-only fallback**: When `displayMode` is set to "Overlay Only" and the target's nameplate is not rendered (too far, culled by stacking limits, hidden by nameplate addon), the main panel now shows as a fallback so users never lose their combat queue. Applies to both the offensive queue (UIRenderer) and the defensive queue (DefensiveEngine). As soon as the nameplate reappears, the overlay takes over and the main panel hides again.
- **Disabled-function corrections** (7 settings):
  - `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities` - No longer grayed out in overlay-only mode (SpellQueue feeds both surfaces).
  - `glowMode` (offensive) - Now correctly grayed out in overlay-only mode (only UIRenderer uses it).
  - `defensives.showProcs`, `defensives.allowItems`, `defensives.autoInsertPotions` - Now available when either surface's defensives are enabled (standard panel or overlay), not just the standard panel.

## [4.5.4] - 2026-03-03

### Changed
- **UIRenderer v17**: Cooldown display now uses `SetCooldownFromDurationObject` (12.0+ opaque pipeline) when available. Bypasses secret value handling entirely for cooldown sweep animations. Falls back to legacy `SetCooldown` on pre-12.0 clients. Charge cooldowns also use `GetActionChargeDuration` → `SetCooldownFromDurationObject` when an action bar slot is resolved.
- **RedundancyFilter v39**: Added NeverSecret aura whitelist (Meorawr/Blizzard hotfix data, ~50 spells). Auras gained during combat that are on the whitelist can be resolved directly via pcall without instance-map lookup - covers raid buffs, rogue poisons, shaman imbues, exhaustion debuffs, and more.
- **RedundancyFilter v39**: Wrapped `GetAuraDataByIndex` loop in pcall for crash resilience. If the API throws (compound token issues, hotfix changes), the loop breaks gracefully and falls back to the trusted out-of-combat cache.
- **GapCloserEngine v2**: Uses `C_ActionBar.EnableActionRangeCheck(slot, true)` to opt the melee reference slot into push-based `ACTION_RANGE_CHECK_UPDATE` events. Properly disables range check on old slots when the reference changes or the cache is invalidated.

## [4.5.3] - 2026-03-02

### Fixed
- "When Health Low" defensive display mode now works correctly in combat - was showing defensives at all health levels because secret-health fallback bypassed the threshold check. LowHealthFrame (~35%) is NeverSecret and properly gates the queue.

## [4.5.2] - 2026-03-02

### Changed
- **Merged defensive spell lists:** Self-heals and major cooldowns are now a single "Defensive Priority List" instead of two separate lists. Self-heals appear first by default (natural priority). Existing per-class customizations are automatically migrated (old keys preserved for safe downgrade).
- Auto-insert potions now triggers at the unified low-health threshold instead of requiring a separate "critical" health level.
- Removed `cooldownThreshold` setting and "Ignore Health Priority" toggle (unified list makes both obsolete).

### Fixed
- Defensive spells on cooldown (e.g. Crimson Vial) now deprioritized to end of queue instead of showing at full priority.
- Charge-based spells (e.g. Crimson Vial with 2 charges) excluded from local cooldown tracking - `IsSpellUsable` handles charge depletion correctly.
- `UpdateButtonCooldowns` wrapped in pcall; charge display no longer flickers off when `GetSpellCharges` returns nil in combat.

## [4.5.1] - 2026-03-02

### Fixed
- Keybind not showing on primary icon when a spell procs (e.g. Infernal Bolt, Ruination for Demo Lock) - empty hotkey cache was never retried due to Lua truthiness of empty string
- Gap-closer glow on nameplate overlay defaulted to ON instead of matching main panel (OFF by default)
- DefensiveEngine `showProcs` override precedence (Lua and/or short-circuit with false values)

### Changed
- **Centralized shared settings across Standard Queue and Nameplate Overlay:**
  - **Interrupt Mode** - now a single setting in the Offensive tab, applied to both surfaces
  - **Key Press Flash** - now a single toggle in the Offensive tab, applied to both surfaces
  - **Highlight Mode** - offensive and defensive queues now share one `glowMode` (overlay keeps its own)
  - **Icon Labels** - show toggle is shared; font scale, color, and anchor are independently configurable per surface via mirrored sub-groups within each label type
  - **Health Bars** - removed confusing fallback toggles from the General tab; the Defensives tab is now the sole owner
- Reduced update pipeline latency for faster rotation display after casting (debounce timers halved across SpellQueue, UIRenderer, UINameplateOverlay, and OnUpdate)
- Shortened interrupt mode dropdown labels across all locales
- Defensive health thresholds in combat (12.0 secret health adaptation):
  - Self-heal tier now always active in combat (configurable threshold undetectable when UnitHealth is secret)
  - Cooldown tier triggers at LowHealthFrame "low" signal (~35%) instead of waiting for "critical" (~20%)
  - Out-of-combat thresholds unchanged

### Added
- Defensive queue usability visuals: icons grey out while channeling, blue-tint when lacking resources, desaturate when on cooldown (mirrors offensive queue behavior)
- Defensive queue usability-aware sorting: unusable spells deprioritized to the bottom so castable abilities appear first

### Improved
- DefensiveEngine single-pass iteration and pooled table sorting (reduces GC pressure)

## [4.5.0] - 2026-03-02

### Added
- **Third-party nameplate cast bar discovery chain (UIRenderer v16):** Interrupt detection now cascades through the Blizzard cast bar and the common third-party replacements via `FindVisibleCastBar()`. Previously only worked with Blizzard's default nameplate cast bar, so anyone using a nameplate addon that replaces it got no interrupt suggestions. Source-verified paths: `nameplate.UnitFrame.castBar` (capital U), `nameplate.unitFrame.castBar` (lowercase u), child `.Castbar` (capital C).
- **API fallback for interrupt detection when nameplates disabled:** `IsTargetCastInterruptible()` falls back to `UnitCastingInfo`/`UnitChannelInfo` with `issecretvalue()` guard and fail-open design when no cast bar frame is available (nameplates off + addon target frame).
- **Event-driven interrupt interruptibility tracking (StateHelpers v2):** `UNIT_SPELLCAST_INTERRUPTIBLE` / `NOT_INTERRUPTIBLE` events on `"target"` now provide a definitive real boolean for interruptibility (never secret). Used as the preferred signal before frame field inspection or API fallback. Pattern learned from how unit-frame and nameplate libraries track the same state.
- **`ResetTargetCastState()` on target change (JustAC.lua):** Clears stale event-driven interruptibility state when target changes, preventing carry-over from previous target's cast.

### Changed
- **Unified `IsTargetCastInterruptible()` replaces three functions:** `IsCastBarInterruptible()`, `IsTargetCastingFallback()`, and redundant `GetTargetCastInterruptState()` calls merged into a single `IsTargetCastInterruptible(nameplate)` → `(isCasting, isInterruptible, castBar)`. Event tracker queried once instead of independently in two functions.
- **Single-pass spell selection in `EvaluateInterrupt()`:** Two separate loops (CC-prefer pass + fallback pass) merged into one loop with inline `fallbackID` tracking. Fewer iterations when `preferCC` is false (immediate break on first usable).
- **Dead `importantOnly` interrupt mode removed:** `ImportantCastIndicator` pcall chain and `importantOnly` mode guard were entirely unreachable (all signals SECRET in 12.0, mode retired). ~12 lines removed from `EvaluateInterrupt()`.
- **Comment cleanup - "why not how":** ~180 lines of "how" comments removed or shortened across UIRenderer.lua. Retained all gotcha/safety comments (secret values, case sensitivity, race conditions, ordering constraints). Deduplicated repeated "widget handles secret values" explanations (was 6×, now once at function header).

### Refactor
- Split `BlizzardAPI.lua` (1 719 lines) into four cohesive submodules under `BlizzardAPI\`:
  - `CooldownTracking.lua` - local CD event frame, tooltip probe, charge cache
  - `SecretValues.lua` - feature availability, secret value utilities, secrecy API wrappers, C_Secrets namespace
  - `SpellQuery.lua` - addon access, spell info/usability/proc cache, rotation API, item detection, availability, health helpers
  - `StateHelpers.lua` - defensive/item state helpers, LowHealthFrame detection, target CC immunity, shapeshift form wrappers
- Root `BlizzardAPI.lua` reduced to 14 lines (LibStub registration + version constants); public API surface unchanged for all 17 consumers
- Each submodule uses its own LibStub identity (`JustAC-BlizzardAPI-*`) for reload safety
- Extracted `ResolveSpellID` from `DefensiveEngine` and `GapCloserEngine` into `BlizzardAPI.ResolveSpellID` (single canonical implementation)
- Renamed `lib` → `DefensiveEngine` / `GapCloserEngine` in respective module exports for clarity
- Moved shapeshift Safe* wrappers (`SafeGetNumShapeshiftForms`, `SafeGetShapeshiftFormInfo`) from `FormCache` into `BlizzardAPI.GetNumShapeshiftForms` / `BlizzardAPI.GetShapeshiftFormInfo`
- Reduced `GetDefensiveSpellQueue` from 8 parameters to 6 by consolidating override flags into an `overrides` table
- Added `ApplyMainPanelQueue` / `ApplyOverlayQueue` helpers in `DefensiveEngine` to decouple UI dispatch from queue resolution logic

## [4.4.7] - 2026-02-27

### Fixed
- **Custom hotkey overrides with full-word modifiers were silently corrupted:** `NormalizeHotkey` matched the single-letter abbreviated patterns (e.g. `^S%-?`) against full words like `"SHIFT-2"`, capturing `"HIFT-2"` and producing `"SHIFT-HIFT-2"`. Flash/press detection never matched so the icon never flashed. Full-word patterns (`SHIFT`, `CTRL`, `ALT` and two-word combos) now run first and are fully consumed before the abbreviated patterns are checked.
- **`+` separator not accepted in custom hotkey overrides:** User-typed `"Shift+2"` was stored as-is and normalized to `"SHIFT+2"`, which never matched `"SHIFT-2"` from the keybind scan. Full-word patterns now accept both `-` and `+` as separator, so `"Shift+2"`, `"Shift-2"`, and `"S-2"` all resolve to `"SHIFT-2"` and match correctly.

## [4.4.6] - 2026-02-27

### Fixed
- **Proc glow lingering on empty offensive slot:** When a procced spell left a slot, the slot-clear path set `hasProcGlow = false` and wiped state but forgot to call `UIAnimations.HideProcGlow()` - the animation frame stayed visible until another spell filled the slot. Now calls `HideProcGlow` alongside `StopAssistedGlow` and `StopGapCloserGlow` in the empty-slot branch.
- **`HideDefensiveIcon` left `normalizedHotkey` populated:** After a defensive slot was hidden, `normalizedHotkey` and `previousNormalizedHotkey` retained the previous spell's hotkey. Harmless (gated by `IsShown()`), but inconsistent with the offensive-slot clear path which always nils both fields. Now cleared in `HideDefensiveIcon`.
- **`isWaitingSpell` could be `nil` instead of `false`:** `spellInfo.name and name:find(…) or false` returns `nil` when `spellInfo.name` is `nil` (Lua `and`/`or` semantics). Changed to explicit `~= nil` comparisons so the flag is always a proper boolean.
- **`GetCurrentSpellQueue` returned pooled table on full build (SpellQueue v37):** The full-build code path `return recommendedSpells` returned the pooled table that is `wipe()`d at the start of every queue build - any caller holding the reference across frames would see an empty table. Early-exit paths correctly returned the stable `lastSpellIDs` copy; the full-build path now matches them. Callers can safely hold the returned reference.
- **Duplicate interrupt debounce state between UIRenderer and UINameplateOverlay:** Both renderers maintained separate `lastInterruptUsedTime` / `lastInterruptShownID` / `lastCCAppliedTime` debounce locals. When the player used an interrupt, only the evaluating renderer debounced; the other could fire a redundant suggestion on the same frame. Interrupt evaluation is now consolidated in `UIRenderer.EvaluateInterrupt()`, cached per 0.015 s and keyed on `interruptMode`, called by both renderers - one player, one debounce timer. `UINameplateOverlay.NotifyCCApplied()` now delegates to `UIRenderer.NotifyCCApplied()` and `JustAC.lua` no longer needs a second call.

### Changed
- **`rotationFilterCache` split from `filterResultCache` (SpellQueue):** `PassesRotationFilters()` was keying its cache with `"r_" .. spellID` - a string concatenation on every rotation-spell evaluation in the hot path. Now uses a dedicated `rotationFilterCache` table keyed by the plain integer `spellID`. Both tables are wiped together at the start of each queue build. No behaviour change; eliminates ~N string allocations per update cycle where N = rotation list length.
- **Dead `cachedNormalizedHotkey` field removed (UIRenderer):** The field was assigned in three places (hotkey normalized, hotkey cleared, slot emptied) but never read anywhere - `normalizedHotkey` (the live field read by `KeyPressDetector`) was always set alongside it. All three assignments removed.
- **Visibility predicate unified via `SpellQueue.ShouldShowQueue()` (SpellQueue v37, UIRenderer v15):** UIRenderer previously re-evaluated all four visibility conditions (out-of-combat, healer spec, mounted, hostile target) every render frame, duplicating the logic already in `SpellQueue.GetCurrentSpellQueue()`. `GetCurrentSpellQueue()` now caches the final verdict in `lastShouldShowQueue` and exposes it via `SpellQueue.ShouldShowQueue()`. UIRenderer reads the cached result - one evaluation per queue build instead of one per render frame.
- **Glow state resolved via `ResolveGlowState()` enum (UIRenderer v15):** Six cascading boolean locals (`isSyntheticProc`, `isGapCloser`, `isRealProc`, `wantProcGlow`, `wantGapCloserGlow`, `shouldShowAssisted`) per icon per frame replaced with a single `ResolveGlowState(position, spellID, …)` call returning a `GLOW_NONE / GLOW_ASSISTED / GLOW_PROC / GLOW_GAP_CLOSER` integer. Application uses a clear 4-branch structure - easier to extend with new glow types.
- **`UnitAffectingCombat` call count reduced in hot path:** `GetQueueThrottleInterval()` function removed; `inCombat` is now computed once at the top of `GetCurrentSpellQueue()` and reused for both the throttle interval and all four visibility checks. `ShowDefensiveIcon` no longer calls `UnitAffectingCombat` per icon per update - uses the module-level `isInCombat` maintained by `SetCombatState()` on PLAYER_REGEN events. Net reduction: ~2 + N redundant calls per update cycle (N = visible defensive icons).

## [4.4.5] - 2026-02-27

### Fixed
- **Key-press flash broken when a proc moves to position 1:** `normalizedHotkey` was not cleared when a slot went empty, so when a proc refilled it the stale value was written to `previousNormalizedHotkey`, corrupting the grace-period flash logic (regression since 4.4.0 three-tier sort).
- **Gamepad glyphs reverting to keyboard text after a few minutes:** `UPDATE_BINDINGS` immediately wiped `spellHotkeyCache`, causing the next render frame to cache keyboard text before WoW's gamepad bindings had fully committed. Full cache invalidation now deferred to the existing 0.3s settle timer; only the raw binding-key cache is cleared immediately.

## [4.4.4] - 2026-02-25

### Changed
- **Interrupt Reminder dropdown** - The old `Show Interrupt Reminder` toggle + `Prefer CC on Regular Mobs` toggle have been consolidated into a single `Interrupt Reminder` dropdown with three modes:
  - **Disabled** - No interrupt reminders
  - **Interrupt Only** - Shows on all interruptible casts, always suggests your interrupt
  - **Prefer CC on Trash** - Shows on all interruptible casts, prefers crowd control on non-boss mobs (previous default behavior)
- **Important Casts Only mode reserved** - `importantOnly` option removed from UI. All important-cast detection signals (`isHighlightedImportantCast`, `C_Spell.IsSpellImportant()`, `ImportantCastIndicator:IsShown()`, `IsPlaying()`) return secret booleans in 12.0 - unusable for branching logic. Detection code kept in place for future re-enablement. Stale saved data gracefully falls back to `kickOnly`.
- **Interruptibility detection hardened** - Uses `castBar.Icon:IsShown()` (NeverSecret, verified 2026-02-25) on nameplate castbars with `HideIconWhenNotInterruptible=true`. Falls back to `BorderShield:IsShown()` on castbars without icon hiding.
- **Settings migration** - `showInterrupt=true` + `ccRegularMobs=true` → `"ccPrefer"`, `showInterrupt=true` + `ccRegularMobs=false` → `"kickOnly"`, `showInterrupt=false` → `"disabled"`. Legacy keys cleaned from saved data after migration.

## [4.4.3] - 2026-02-25

### Changed
- **Extracted GapCloserEngine from DefensiveEngine** - Gap-closer system moved to its own `GapCloserEngine.lua` module. Gap closers inject into the offensive queue and had no coupling with defensive spell evaluation. DefensiveEngine reduced to its actual scope: health-based defensive queue, proc detection, potions.

## [4.4.2] - 2026-02-25

### Fixed
- **Gap-closer glow missing after leaving combat:** `PauseAllGlows` (fired on `PLAYER_REGEN_ENABLED`) hid the gap-closer crawl frame and stopped its animation, but did not reset the renderer's `hasGapCloserGlow` tracking flag. Removed gap-closer glow from `PauseAllGlows`; added stale-flag guard in UIRenderer as defensive fallback.
- **Shadowstrike gap-closer not suggesting in stealth:** Shadowstrike (185438) was not in Sub Rogue gap-closer defaults, and the melee range reference (Backstab) transforms to Shadowstrike on the action bar in stealth, changing range from 5yd to 25yd. Added Shadowstrike as first entry; stealth-only gap closers now evaluate before the melee range gate using their own slot range.
- **Melee range reference stability audit (Rogue):** Fixed unstable backup references - `ROGUE_2` changed from Between the Eyes (20yd ranged) to Kidney Shot (5yd melee); `ROGUE_3` changed from Shadowstrike (25yd) to Kidney Shot. All other class/spec references verified stable.
- **Druid gap-closer disabled after form change:** `OnShapeshiftFormChanged` did not invalidate the melee range reference cache. Now invalidates gap closer cache + range state on `UPDATE_SHAPESHIFT_FORM`.
- **IsSpellReady() cooldown detection in 12.0 combat:** Now uses full `isOnGCD` three-state: `true`=GCD only (ready), `false`=real CD (flagged spells), `nil`=ambiguous (falls back to local CD tracking + charge checks + action bar usability). Fixes DefensiveEngine suggesting spells on cooldown.
- **GetSpellCooldownValues() `isOnRealCooldown`:** Now checks `isOnGCD == false` (definitive for flagged spells), then local CD tracking for unflagged spells. Returns `nil` (unknown) instead of `false` when ambiguous.
- **Nameplate overlay invisible without enemy nameplates:** Now auto-enables `nameplateShowEnemies` CVar when display mode is "Overlay" or "Both", restores original setting on disable/unload.
- **Mouse hotkey flash detection:** Added `OnUpdate` polling via `IsMouseButtonDown` for mouse button down-transitions (M3/M4/M5, with or without modifiers).
- **Mouse hotkey normalization mismatch:** Added reverse mouse abbreviations (`M%d` → `BUTTON%d`, `MWU` → `MOUSEWHEELUP`, `MWD` → `MOUSEWHEELDOWN`) so normalized hotkeys match WoW binding format.

### Changed
- Updated all `isOnGCD` documentation to reflect verified three-state behavior
- Updated `UnitHealth("player")` documentation: confirmed SECRET in open world combat
- Updated `UnitPower("player")` documentation: per-type secrecy - continuous resources SECRET, discrete resources NeverSecret
- Corrected `GetComboPoints()` from SECRET to NeverSecret
- Added `isEnabled`, `modRate`, `activeCategory` fields to cooldown signal reference (all SECRET)
- Documented `LuaDurationObject` API, `C_Secrets.ShouldSpellCooldownBeSecret()`, `SecrecyLevel` enum
- **CheckCooldownCompletions() now uses SPELL_UPDATE_COOLDOWN spellID payload** - O(1) lookup when event fires with non-nil spellID; falls back to full scan on nil
- **PassesRotationFilters() comment corrected** - accurately documents isOnGCD three-state behavior
- **Central maxCharges cache in BlizzardAPI** - `GetCachedMaxCharges(spellID)` replaces per-button state; proactive scan on combat exit
- **UIRenderer per-button `_cachedMaxCharges` removed** - replaced with central `BlizzardAPI.GetCachedMaxCharges()` lookups

### Added
- **New combat-safe signals discovered and verified:** `C_ActionBar.IsActionInRange()`, `IsInterruptAction()`, `C_Spell.IsExternalDefensive()`, `C_CooldownViewer` category/info APIs, `C_UnitAuras.GetCooldownAuraBySpellID()`, `ACTION_RANGE_CHECK_UPDATE`, `ACTION_USABLE_CHANGED`, `IsAttackAction()`, `IsCurrentAction()`, `GetSessionDurationSeconds()`
- **SPELL_UPDATE_COOLDOWN spellID is NeverSecret** - per-spell CD state change events with `startRecoveryCategory` (133=GCD, 0=own CD)
- **UnitPower secrecy mapped per-type** - continuous primary resources SECRET, discrete secondary resources NeverSecret, `UnitPowerMax`/`UnitPowerType` always NeverSecret
- **C_Spell.IsSpellUsable, GetSpellPowerCost, IsCurrentSpell verified NeverSecret** in combat
- **C_Spell.GetSpellCharges ALL SECRET** (including maxCharges) - must cache out of combat
- **C_Spell.IsSpellInRange verified NeverSecret** - existing range check code confirmed correct
- **LossOfControl API documented from source** - `locType`, `priority`, `displayType`, `auraInstanceID` NeverSecret
- **DB2 tables catalogued** - `CooldownSet`/`CooldownSetSpell`, `SpellActivationOverlay`, `AssistedCombat`/`AssistedCombatRule`/`AssistedCombatStep`, `LossOfControlType`
- **Event-driven CD tracking potential identified** - `SPELL_UPDATE_COOLDOWN` spellID + `isOnGCD` state machine could replace timer-based local CD tracking

### Documentation
- Updated `Documentation/12.0_COMPATIBILITY.md` combat-safe signal reference with all Session 2/2b/2c/2d findings
- Updated `AGENTS.md` NeverSecret sections with verified API behaviors

## [4.4.1] - 2026-02-24

### Performance
- Gap-closer engine: early exit when no melee range reference spell resolves (skips target/range/spell checks for ranged specs and melee specs without a reference spell on the action bar)
- Inlined range check in `GetGapCloserSpell` to reuse the already-resolved slot from `ResolveMeleeReference`

### UI
- Removed dead "Bar Position" (healthBarPosition) dropdown from Overlay tab - setting was stored and read but never applied to health bar anchoring
- Gap-Closers options tab: show soft notice for non-melee specs ("No default gap-closers for this specialization") instead of hiding controls
- **Show Pet Health Bar** - New standalone toggle in General tab, mirrors "Show Health Bar". Lets users show a pet health bar (offensive queue width) even when the Defensive Queue is disabled. When defensives are enabled, the existing defensive-section toggle takes over. UIHealthBar v7.
- **Overlay pet health bar** - "Show Health Bars" toggle in Overlay tab now creates both player and pet health bars above the defensive cluster. Pet bar uses warm yellow color, auto-hides when no pet exists. Both bars gated by "Show Defensive Icons". UINameplateOverlay v2.
- **Cross-section naming consistency** - Aligned option labels across all tabs: Overlay "Offensive Slots"/"Defensive Slots" → "Max Icons" (matches Standard Queue), Defensives "Display Mode" → "Defensive Visibility" (matches Overlay, avoids collision with General "Display Mode"), "Key Press Flash" → "Show Key Press Flash" (matches all other "Show X" toggles). Added 6 missing `desc` tooltips to Overlay controls. Removed dead `L["Nameplate Show Health Bar"]` singular keys from all 9 locale files. Updated all 8 translations.

### Investigated
- **Rotation queue cooldown filtering** - `isOnGCD` returns `nil` (not `false`) for real cooldowns outside `SPELL_UPDATE_COOLDOWN` events; `GetActionCooldown` start/duration fully secreted in 12.0 combat; `C_ActionBar.GetActionCharges` also secreted; `IsUsableAction` returns true even on cooldown; `cooldown:IsShown()` includes GCD (can't distinguish)

### Changed
- **Rotation queue cooldown de-prioritization** - Spells with base CD > 3s are tracked locally via `UNIT_SPELLCAST_SUCCEEDED` + `GetSpellBaseCooldown()` (not secret). On-cooldown spells are moved to the end of the queue (below procced and normal spells) rather than filtered out. Fail-open: untracked spells show normally.
- **Tooltip cooldown parsing** - `RegisterRotationSpell()` now scans the spell tooltip for talent-modified cooldown values (e.g., "30 sec cooldown" for Bestial Wrath with Beast Within). Falls back to `GetSpellBaseCooldown` only if tooltip parsing fails. Tooltip is re-scanned on talent/spec changes via natural re-registration flow.
- **Blacklist position 1 option** - New toggle in Offensive > Blacklist: "Apply to Position 1". Off by default. When enabled, blacklisted spells are also hidden from position 1 (Blizzard's primary suggestion). Warning in tooltip about rotation stalling.
- **BlizzardAPI v32**: Added `ParseTooltipCooldown()` for traited cooldown detection; `GetBestCooldownDuration()` now uses 3-tier fallback (observed cast → tooltip → base API); `RegisterRotationSpell()` pre-caches traited duration
- **SpellQueue v36**: Three-tier rotation sort (procced → normal → on-cooldown), auto-registers rotation spells on list fetch, clears registrations on cache invalidation

## [4.4.0] - 2026-02-24

### Fixed
- **SpellDB audit** - full classification review of all spell IDs (SpellDB v7→v8)
  - **CRITICAL:** Removed Storm Elemental (192249) from defensives - DPS cooldown for Elemental Shaman
  - **CRITICAL:** Removed Deathbolt (264106) from defensives - offensive damage ability
  - **CRITICAL:** Removed Mirror Image (55342) from defensives - DPS cooldown for Fire/Frost
  - **CRITICAL:** Moved Holy Word: Chastise (88625) from healing → crowd control (damage + incapacitate)
  - Moved Wind Rush Totem (192077), Mana Tide Totem (16191), Ice Floes (108839) from defensives → utility
  - Moved Wild Charge (102401) from healing → utility (movement ability)
  - Moved Cleanse Toxins (213644) from healing → utility (dispel, consistent with other class dispels)
  - Moved Blistering Scales (360827) from healing → defensive (shield + thorns, not a heal)
  - Removed stale entries: Hand of the Protector (213652, merged into WoG), Greater Heal (289666, not learnable), Soul Harvester (386997, hero talent tree name not a spell), Earthwarden (203974, passive talent), Feral Charge (16979, removed from game)
- **Gap-closer audit** - fixed spell lists and added usability check
  - Removed Vengeful Retreat from DH Havoc (jumps backward, not a gap closer)
  - Added Shadowstrike (185438) as priority 1 for Sub Rogue (teleport gap closer in stealth)
  - Added Grappling Hook (195457) for Outlaw Rogue between Shadowstep and Sprint
  - Added `IsSpellUsable` check to gap-closer evaluation so stealth-only spells only show when actually usable
  - Added action bar slot check to gap-closer evaluation: spells not on any bar (e.g. Shadowstrike out of stealth) are skipped, falling through to the next candidate (e.g. Shadowstep)
- **Melee range detection overhaul** - replaced broad per-slot `slotRangeState` tracking with a fixed per-spec melee reference spell
  - Old system tracked all 120 action bar slots; any out-of-range event (including ranged abilities) could trigger false-positive gap-closer insertion
  - New system uses a priority chain: user override → SpellDB default[1] → SpellDB default[2]; first spell found on the action bar wins
  - Two hardcoded candidates per spec (e.g. Backstab + Shadowstrike for Sub Rogue); primary shown in options, backup is hidden
  - New **Melee Range Reference** group in Gap-Closers options: shows current default, allows user override via spell ID input
  - `OnActionRangeUpdate` now only triggers queue rebuilds when the melee reference slot changes range (not every slot)
  - `SeedRangeState()` loop over 120 slots eliminated - replaced by direct `IsActionInRange(slot)` check on the single reference slot
- **Gap-closer OOC visibility** - fixed gap closer not always appearing out of combat
  - `IsPrimarySpellOutOfRange` replaced by `IsMeleeTargetOutOfRange` (uses fixed reference spell instead of queue position 1)
  - `OnActionRangeUpdate` now calls `SpellQueue.ForceUpdate()` on melee reference slot range transitions so the queue rebuilds immediately
- **Gap-closer position-1 dedup** - when Blizzard's Assisted Combat suggests a gap closer (e.g. Charge) as the primary spell at position 1, JustAC no longer injects a second gap closer at position 2
  - New `DefensiveEngine.IsGapCloserSpell()` checks both base IDs and talent overrides
- **SpellQueue dead code cleanup** (v34→v35) - removed dead stabilization code, fixed `lastSpellIDs` aliasing bug, removed unused functions/variables

### Added
- **Gap-Closer System** - suggests gap-closing abilities (Charge, Shadowstep, Fel Rush, etc.) when the target is out of melee range
  - Appears at position 2, before spellbook procs (highest priority after Blizzard's primary suggestion)
  - Uses `ACTION_RANGE_CHECK_UPDATE` (NeverSecret) for range detection via a fixed per-spec melee reference spell - fully combat-safe under 12.0 secret value system
  - Uses `isOnGCD` (NeverSecret) for cooldown readiness checks
  - 150ms debounce on hide path to prevent flicker during kiting; show path is instant
  - Spec-aware defaults for all melee specs (Warrior, Rogue, DK, DH, Feral/Guardian Druid, Survival Hunter, WW/BM Monk, Ret/Prot Paladin, Enhancement Shaman)
  - Per-spec spell list stored in profile (`gapClosers.classSpells[CLASS_SPECINDEX]`)
  - New **Gap-Closers** options tab with priority list management, restore defaults, and spell search
  - Red emphasis glow (same tint as interrupts) on gap-closer icons, with independent toggle (`showGlow`) separate from the proc glow dropdown
  - Gap-closer and interrupt icons now use red-tinted marching ants crawl instead of red proc glow - proc glow is reserved for actual spell procs
  - Gap-closer crawl animates even out of combat (unlike other crawls which pause OOC)
- `BlizzardAPI.IsTargetInterruptWorthy()` - combat-safe check to suppress interrupt/CC suggestions on trivial targets
  - `"minus"` classification mobs (swarm adds, Explosive orbs) - not worth a kick CD
  - `UnitIsMinion()` targets (pets, totems, treants, guardians) - combat-safe replacement for secreted `UnitCreatureType()` Mechanical/Totem check
- Interrupt guard in both UIRenderer and UINameplateOverlay - skips cast bar processing entirely for unworthy targets

### Documentation
- New "Combat-Safe Signal Reference" section in `Documentation/12.0_COMPATIBILITY.md` - authoritative matrix of all APIs tested in 12.0 combat with verification dates
- Updated `AGENTS.md` NeverSecret section with newly verified target APIs

## [4.3.1] - 2026-02-24

### Fixed
- **Standard queue cast aura ("to interrupt" icon) not showing:** `castBar` variable was scoped inside the debounce block, making it nil when the cast aura rendering code ran - hoisted to outer scope in both UIRenderer and UINameplateOverlay
- **Nameplate overlay interrupt icon shifted entire DPS queue:** Interrupt icon now positions perpendicular to icon 1 (above for horizontal queues, outside for vertical) instead of displacing it inline - dpsIcons[1] stays fixed
- **Standard queue cast aura overlapped icon 1 in UP orientation:** Aura now anchors below the interrupt icon when queue grows upward (away from queue) instead of always above

### Changed
- Nameplate overlay interrupt icon now includes cast aura (enemy spell icon), consistent with standard queue - always positioned above the interrupt icon
- Removed redundant dpsIcons[1] re-anchor dance in nameplate overlay Render() - no longer needed since interrupt is perpendicular to queue

## [4.3.0] - 2026-02-24

### Refactored
- Split monolithic `Options.lua` (3316 lines) into 9 modular files in `Options/` subfolder: SpellSearch, General, Offensive, Overlay, Defensives, Labels, Hotkeys, Profiles, Core
- Moved 5 UI modules to `UI/` subfolder: UIHealthBar, UIAnimations, UIFrameFactory, UIRenderer, UINameplateOverlay
- Extracted `TargetFrameAnchor.lua` and `KeyPressDetector.lua` from `JustAC.lua` into standalone modules

### Fixed
- **Hotkey text hidden after update:** Legacy migration (`defensives.showHotkeys = false`) was incorrectly hiding all hotkeys including offensive queue; now only migrates `showOffensiveHotkeys`
- **Nameplate overlay defensive hotkeys ignoring Labels tab toggle:** Was reading legacy `npo.showHotkey` instead of `npo.textOverlays.hotkey.show`
- **General tab "Reset to Defaults" set Target Frame Anchor to TOP instead of DISABLED** and did not reset sidebar position

## [4.2.2] - 2026-02-24

### Fixed
- **Long buffs (poisons, Mark of the Wild) shown as active when about to expire at combat start:** Stop filtering a long-duration buff (≥10 min) when less than 5 minutes remain. Three-layer fix: IsInPandemicWindow applies a 5-minute absolute floor for long buffs, trusted-cache combat merge skips re-adding expiring long buffs, CountActivePoisonBuffs skips counting expiring poisons.

## [4.2.1] - 2026-02-23

### Added
- Text overlays (hotkey, cooldown timer, charge count) are now individually configurable - toggle each on/off, adjust font scale, color, and anchor position. Settings apply across all icon types: main queue, nameplate overlay, defensives, and interrupt icon
- Long-duration buffs (poisons, Mark of the Wild, weapon imbues) now show a recast suggestion when less than 5 minutes remain - previously they were suppressed as "active" right up until expiry, leaving queue slot 1 stuck at the start of combat
- 4-second hold after a CC lands before suggesting another, giving the game time to register the target's crowd-controlled state
- Spell queue and defensive icons now hidden when controlling a vehicle or possessing an NPC (Mind Control, siege engines, questline vehicles) - your normal action bars are replaced in these states

### Changed
- Mechanical and Totem mob types now recognized as CC-immune (in addition to worldbosses and dungeon bosses)

### Fixed
- Fixed a second CC spell briefly flashing immediately after the first one was cast

## [4.2.0] - 2026-02-22

### Added
- Cast aura indicator above interrupt icon: shows the enemy's casting spell icon so you can see what you're interrupting (standard queue + nameplate overlay)
- Nameplate overlay: channeling grey-out - interrupt and DPS icons now desaturate when the player is mid-channel, matching the main panel behavior
- Nameplate overlay: out-of-range detection - interrupt and DPS hotkey text turns red when the target is beyond spell range, matching the main panel behavior

### Changed
- **Interrupt options consolidated into single dropdown** - replaced separate "Interrupt Mode" dropdown + "CC Non-Important Casts" checkbox with one 5-option dropdown: Off, Important Only, Important + CC, All + Smart CC, All Casts. Existing saved settings are preserved automatically.
- Interrupt/CC reminders now only trigger on casts with 0.8s+ duration (important/dangerous casts bypass the filter and trigger immediately); when cast duration is a secret value (12.0 combat), falls back to elapsed-time measurement
- **"All + Smart CC" mode falls back to kick** - non-important casts prefer CC but fall back to your interrupt if no CC is available; "Important + CC" intentionally does NOT fall back (saves interrupt lockout for dangerous casts)

### Fixed
- Interrupt icon for RIGHT/UP orientations now anchors adjacent to icon 1 instead of beyond the grab tab (was causing ~17px gap vs expected ~3px)
- Standalone health bar for UP/DOWN orientations now goes to the side of the queue (perpendicular) instead of above it, matching how horizontal bars are perpendicular to horizontal queues
- **CC/interrupt spells now correctly detected as off-cooldown in combat** - WoW 12.0 blanket-secrets `duration`/`startTime` from `C_Spell.GetSpellCooldown()` even when zero; now uses `isOnGCD` (NeverSecret) three-state field: `true`=GCD only (ready), `false`=real cooldown, `nil`=no cooldown (ready)
- **Aura detection now works in combat via auraInstanceID mapping** - WoW 12.0 secrets `spellId`/`name` in combat but `auraInstanceID` is NeverSecret and stable; builds instanceID→spellID map out of combat, resolves auras in combat using the map; UNIT_AURA addedAuras/removedAuraInstanceIDs keep the map current; trustedOutOfCombatCache used as fallback only for truly unmapped auras (RedundancyFilter v37→v38)
- **Buff removal now detected in combat** - removing a buff (e.g., right-clicking MOW off) now immediately shows the spell in queue; tracks removed spellIDs via `combatRemovedSpellIDs` to prevent trusted cache merge from re-adding them; non-DPS filter gate now uses `hasSecrets` (instance-map-aware) instead of raw `auraAPIBlocked`
- **Buff recast in combat now correctly filtered** - recasting a buff (e.g., MOW) after removal in combat is now hidden from the queue again; IsInPandemicWindow returns false when inCombatActivations shows a fresh cast with no timing data
- **Multi-cycle remove/reapply tracking in combat** - pending activation queue bridges UNIT_SPELLCAST_SUCCEEDED → UNIT_AURA addedAuras (2s FIFO window) to map new aura instance IDs when spellId is secret; supports unlimited remove/recast cycles within a single combat; filters harmful auras (debuffs) from consuming pending activation entries
- **Interrupt list now refreshes on spec/talent changes** - `resolvedInterrupts` was only built during frame creation; now re-resolved in `OnSpellsChanged` and `OnSpecChange` so talent-gated CC/interrupt spells appear immediately; deferred to out-of-combat to prevent `IsSpellAvailable()` secret restrictions from wiping the list
- **Channeling check now secret-safe** - replaced `UnitChannelInfo("player") ~= nil` with `PlayerChannelBarFrame:IsShown()` (NeverSecret visual frame) to avoid potential taint from secret return values
- **Elapsed-time fallback now secret-safe** - the short-cast duration filter's `castBar.spellID` comparison is now pcall-wrapped; in PvP contexts where spellID is secret, prevents taint crash from secret boolean in control flow

## [4.1.1] - 2026-02-22

### Changed
- Default `targetFrameAnchor` changed from `"TOP"` to `"DISABLED"` - new/reset profiles no longer snap to the target frame by default
- Dragging the panel now auto-disables the target frame anchor so the frame stays where you put it
- Frame is now only draggable via the grab tab - prevents accidental repositioning when interacting with icons

### Fixed
- Fixed frame snapping to right side of screen after update or profile reset (target frame anchor was re-applied on every drag stop)
- Fixed inability to reposition the panel when target frame anchor was enabled - dragging would immediately snap the frame back
- Added detection for an unavailable or replaced TargetFrame (unit-frame addons) - anchoring gracefully falls back to saved position
- Added off-screen safety check on load - if saved position is outside screen bounds (resolution/scale change), frame resets to center
- Fixed update-freeze-during-drag not working (`isDragging` was set on grab tab but checked on addon object)
- Fixed SavePosition saving garbage coordinates when frame was anchored to TargetFrame (now skips save when anchored)
- Removed unnecessary ForceUpdate from SavePosition (saving coords shouldn't rebuild spell queue)

## [4.1.0] - 2026-02-21

### Added
- **DefensiveEngine module**: Extracted ~855 lines of defensive spell logic from JustAC.lua into `DefensiveEngine.lua` (LibStub `JustAC-DefensiveEngine` v1) - health-based queue, proc detection, potion subsystem, cooldown polling. JustAC.lua retains thin wrapper methods that delegate to the new module.
- **CC Non-Important Casts option**: New toggle under Interrupt Reminder (both standard queue and nameplate overlay). When enabled, uses crowd-control abilities (stuns, incapacitates) to interrupt non-important casts on CC-able (non-boss) mobs, while saving true interrupt lockout for important/lethal casts. Ideal for open-world combat efficiency.

### Changed
- **Frame rebuild consistency**: All frame-affecting settings now route through a single `UpdateFrameSize()` path
  - `UpdateFrameSize()` now calls `ForceUpdateAll()` instead of `ForceUpdate()`, ensuring `OnHealthChanged` fires and `ResizeToCount` runs immediately after any frame rebuild - fixes health bar width not shrinking until next `UNIT_HEALTH` event
  - Removed redundant trailing `ForceUpdate()` from `RefreshConfig` (already handled by `UpdateFrameSize`)
  - Simplified 4 defensive Options setters (enabled, maxIcons, iconScale, position) from inline `CreateSpellIcons + UpdateSize + UpdatePetSize + ForceUpdateAll` to single `UpdateFrameSize()` call
  - Simplified defensive health bar toggle setters (showHealthBar, showPetHealthBar) from inline destroy/create to `UpdateFrameSize()`
  - Simplified General "Reset to Defaults" button: removed redundant `UpdateTargetFrameAnchor()` and `ForceUpdate()` calls
- **Defensive "Reset to Defaults" button**: Synced hardcoded defaults with JustAC.lua profile defaults
  - `showHealthBar`: `false` → `true`
  - `showPetHealthBar`: `false` → `true`
  - `glowMode`: `"procOnly"` → `"all"`
  - `maxIcons`: `3` → `4`
  - `allowItems`: `false` → `true`
  - `displayMode`: `"combatOnly"` → `"always"`
  - Now uses `UpdateFrameSize()` instead of manual destroy/create/ForceUpdateAll

### Fixed
- **Health bars not scaling after reset**: `UpdateFrameSize` now triggers `OnHealthChanged` → `ResizeToCount`, so health bar width matches actual visible defensive icon count immediately after any configuration change or profile reset
- **Dynamic transform hotkeys missing** (e.g. Templar Strike → Templar Slash): ActionBarScanner v35
  - Pass `onlyKnown=false` to `C_Spell.GetOverrideSpell()` - default `true` filtered out aura-driven combat transforms that aren't in the spellbook
  - Added `FindSpellOverrideByID` fallback in `SearchSlots` for talent/aura overrides that `C_Spell.GetOverrideSpell` may miss (separate native lookup path)
  - Empty hotkey cache results (`""`) no longer use the fast-path, falling through to 0.25s stale-refresh so transforms self-correct within frames
  - Added forward override scan in `GetSpellHotkey` - checks if any previously-cached slot's spell currently overrides to the target, catching dynamic transforms where `FindBaseSpellByID` returns nil
- **Interrupt icon missing tooltip & click handlers**: `CreateInterruptIcon` was passing `isClickable=false` to `CreateBaseIcon`, disabling mouse input entirely. Now passes `true` and adds full interactive behavior matching DPS/defensive icons:
  - Tooltip (`OnEnter`/`OnLeave`): spell info, hotkey display, custom hotkey hint - respects `tooltipMode` setting
  - Right-click: opens hotkey override dialog
  - Drag to move: repositions the frame (delegates to mainFrame, same as DPS icons)
  - Masque skinning: registered with MasqueGroup so interrupt icon matches custom button skins
  - Out-of-range red hotkey: hotkey text turns red when target is beyond interrupt range (throttled, secret-safe)
  - Channeling grey-out: icon desaturates when player is channeling (can't interrupt during own channel)
  - `HideInterruptIcon` now resets `cachedOutOfRange`, `lastOutOfRange`, `lastVisualState`, and clears desaturation

## [4.0.0] - 2026-02-21

### Added

- **Interrupt Reminder System** - Detects interruptible casts on your target via nameplate cast bar state and shows your best available interrupt as a "position 0" icon before the DPS queue. Works in both Standard Queue and Nameplate Overlay modes.
  - **Interrupt Mode** dropdown: Important Only (shows for lethal/must-interrupt casts via `C_Spell.IsSpellImportant`), All Casts (any interruptible cast), or Off
  - **CC Non-Important Casts** toggle (on by default): Uses stuns/incapacitates to interrupt non-important casts on CC-able (non-boss) mobs, saving your true interrupt lockout for dangerous casts
  - Per-class interrupt + CC spell lists in SpellDB with automatic override resolution
  - Boss-aware filtering: CC abilities automatically skipped against CC-immune targets
  - De-duplication: interrupt icon hidden when it matches DPS queue position 1
  - Secret-safe: all cast bar visibility checks wrapped in pcall for 12.0 combat taint
  - Red interrupt glow distinguishes from normal DPS/proc glows
- **Nameplate Overlay: Icon Spacing** - New "Spacing" slider (0–10 px, default 2) controls the gap between successive icons in the cluster for both DPS and defensive rows. Applies to horizontal and vertical expansion modes. Replaces the hardcoded 2 px constant.
- **Nameplate Overlay: Opacity** - New "Frame Opacity" slider (0.1–1.0) for the overlay cluster. Applies to DPS icons, defensive icons (respects fade-in animation), and the health bar independently of the main panel opacity.
- **Nameplate Overlay: Show Key Press Flash** - New toggle to enable/disable key-press flash feedback on overlay DPS icons, independently of the main panel flash setting.
- **Nameplate Overlay: Options reorganized** - Overlay tab now structured in three logical sections: shared settings at top (anchor, expansion, health bar position, icon size, spacing, opacity, highlight mode, hotkeys, flash), then an "Offensive Queue" section (offensive slots), then a "Defensive Suggestions" section (enable, visibility, defensive slots, health bar).
- **DefensiveEngine module** - Extracted ~855 lines of defensive spell logic from JustAC.lua into `DefensiveEngine.lua` (LibStub `JustAC-DefensiveEngine` v1) for maintainability. Core addon retains thin wrapper methods.

### Changed

- **BlizzardAPI v30**: Removed dead code - `GetBypassFlags()`, `IsCooldownFeatureAvailable()`, `IsDefensivesFeatureAvailable()`, `TestCooldownAccess()` all had no external consumers. Feature availability struct simplified from 5 fields to 3.
- **SpellQueue v34**: `GetRotationSpells()` result is now cached and only refreshed on `RotationSpellsUpdated` event (was called ~10/sec in combat). Replaced `GetBypassFlags()` table allocation with direct `IsProcFeatureAvailable()` call.
- Default icon size changed from 36 to 42 for new profiles
- Default defensive icon scale changed from 1.2 to 1.0 for new profiles

### Fixed

- **Dynamic transform hotkeys missing** (e.g. Templar Strike → Templar Slash): ActionBarScanner v35 - pass `onlyKnown=false` to `C_Spell.GetOverrideSpell()`, added `FindSpellOverrideByID` fallback and forward override scan for aura-driven combat transforms
- **Frame rebuild consistency**: All frame-affecting Options setters unified through single `UpdateFrameSize()` path; health bar width now updates immediately on config changes
- **Defensive "Reset to Defaults"**: Synced hardcoded reset values with actual profile defaults (health bar, glow mode, icon count, items, display mode were all mismatched)
- **BlizzardAPI**: `TestProcAccess()` accessed `spells[1].spellId` but `GetRotationSpells()` returns a flat array of numbers - secret-value detection for procs was dead code (fail-open masked the bug). Now correctly uses `spells[1]`.
- **BlizzardAPI**: `GetActionInfo()` filtered Assisted Combat placeholder slots by checking `id == "assistedcombat"` but Blizzard's canonical filter is `subType == "assistedcombat"`. Now checks both `subType` and `id` for robustness.
- Nameplate Overlay: "Show Hotkeys" and "Show Flash" settings now apply to defensive overlay icons as well as DPS icons (both now pass their own override to ShowDefensiveIcon instead of reading the main panel's defensives profile)
- Nameplate Overlay: key-press flash for defensive overlay icons was gated on the main panel's `defensives.showFlash` setting instead of the overlay's own `showFlash`

### Removed

- Nameplate Overlay: "Show Procced Defensives" toggle removed - procced spells always appear in the overlay defensive queue; the Highlight Mode dropdown controls whether they receive special highlighting

## [3.26.2] - 2026-02-20

### Added

- **Nameplate Overlay** - Independent queue cluster that attaches directly to the target's nameplate. Fully separate from the main panel; either or both can be active at once. Includes DPS queue icons, defensive queue icons (opposite side), and a compact player health bar. Configurable anchor side, expansion direction (horizontal or vertical), icon count, icon size, glow mode, hotkey display, and per-section visibility. Overlay defensives operate independently of the main Defensive Suggestions setting.
- **Items in defensive queue** - Spell lists now accept equipped items (`-itemID` or `item:ID` syntax). Items display with an `[Item]` tag and correct icon/name in the editor. Auto-deduplication against hardcoded health potions.
- **Reset to Defaults buttons** - Each major options tab (General, Offensives, Overlay, Defensives) now has a section-scoped reset button. Spell lists and the blacklist are never affected.

### Changed

- Defensive suggestions enabled by default on new profiles
- BlizzardAPI library version bumped to v29

### Fixed

- Defensive icons remaining visible when "Enable Defensive Suggestions" is turned off (early-exit paths in OnHealthChanged bypassed the hide logic)
- Charge-based ability cooldown sweep bleeding outside icon border (SetDrawSwipe disabled on chargeCooldown; edge ring now matches Blizzard's own rendering)
- Target frame anchor not re-applied after loading screens or combat lockdown (UpdateTargetFrameAnchor now called on PLAYER_ENTERING_WORLD and PLAYER_REGEN_ENABLED)
- DPS icons invisible after icon refactor (alpha not reset on slot reuse)
- Defensive spells on cooldown permanently hidden in combat - cooldown swipe is now the visual indicator; visibility is no longer gated on cooldown state
- Rotation list positions 2+ permanently hiding spells on cooldown
- Cooldown swipe not re-shown when an icon slot is reused
- Icon background corner-clipping (rounded mask now applied to background as well as texture)
- Disabled spec profile not applied on login/reload until the user manually switched specs
- Defensive queue item deduplication: same item in multiple spell lists (selfheal + cooldown) could appear twice - cross-call check used negative key but callers marked positive key
- Defensive queue showing same ability twice when a talent replaces a base spell (e.g. Impending Victory replacing Victory Rush) - both the base ID and the talent ID passed availability checks and both appeared; fixed by resolving talent overrides via FindSpellOverrideByID in GetUsableDefensiveSpells and the ActionBarScanner proc injection path, so both share the same tracking key and only the active (talent) version is shown
- Options: Profiles tab had same `order = 4` as Defensives tab (undefined tab ordering)
- Options: Nameplate Overlay health bar was incorrectly gated on "Show Defensives" - users could not enable it independently
- Options: Standard queue settings (icon size, spacing, orientation, anchor, tooltips, opacity, fade, panel interaction) had no disabled state when Display Mode was Overlay-only or Disabled
- Options: Offensive settings had no disabled state when Display Mode was Overlay-only or Disabled

## [3.26.0] - 2026-02-20

### Added

- **Nameplate overlay: expansion direction setting** - New "Expansion Direction" dropdown: Horizontal (Out) chains icons away from the nameplate (original behaviour), Vertical Up stacks slot 2 above slot 1, Vertical Down stacks them downward. Anchor dropdown is now LEFT/RIGHT only (TOP/BOTTOM were mis-implemented as above/below the nameplate and have been removed).
- **Nameplate overlay: vertical health bar** - For Vertical Up/Down expansion the health bar renders as a thin vertical strip beside the icon column, spanning the full cluster height (26 px × 1 icon, 54 px × 2 icons, 82 px × 3 icons). Orientation is VERTICAL so fill direction matches the icon stack.
- **Nameplate overlay defensive display mode** - New "Defensive Visibility" dropdown in the Nameplate Overlay options: "In Combat Only" (default) or "Always". Previously the overlay defensives inherited the main defensive panel's `displayMode`. The overlay now has its own independent setting and calls `GetDefensiveSpellQueue` with an `overrideDisplayMode`.
- **Items in defensive queue** - Negative numbers in spell lists represent items (-itemID).
  - `BlizzardAPI.CheckDefensiveItemState(itemID, profile)` - validates item count and cooldown.
  - Options UI accepts `-itemID` or `item:ID` syntax in the manual input field.
  - Items display with `[Item]` tag and correct icon/name in the spell list editor.
  - `GetUsableDefensiveSpells` handles mixed spell/item lists, deduplicates with hardcoded potions.
  - `GetBestDefensiveSpell` returns `itemID, true` for item entries.
  - Backward compatible: existing positive-only spell lists work unchanged.

### Changed

- BlizzardAPI library bumped to v29.
- **Health bar color** - Overlay health bar now uses pure bright green `(0, 1, 0)` instead of the previous murky `(0.1, 0.8, 0.1)`, matching Blizzard's nameplate health bar saturation.
- **Health bar inset formula** - Replaced asymmetric `iconSize * 1.8 + (n-2)*spacing` with symmetric `clusterWidth - 2*inset` so both outer edges have equal inset.
- **healthBarPosition option** - Disabled when expansion is "out" (horizontal) instead of when anchor is LEFT/RIGHT. Only meaningful for vertical expansion.

### Fixed

- **Defensive overlay invisible after option change** - `UINameplateOverlay.Create` now calls `ForceUpdateAll()` after anchoring so icons render immediately without requiring a re-target.
- **DPS queue invisible after CreateBaseIcon refactor** - `CreateBaseIcon` was setting `button:SetAlpha(0)` at init; the DPS renderer only calls `icon:Show()` (not `fadeIn:Play()`), so icons were permanently invisible. Removed the alpha reset from `CreateBaseIcon`; defensive icons set alpha=0 themselves before playing fadeIn.
- **Defensive queue permanently hides spells on cooldown** - `CheckDefensiveSpellState` was calling `IsSpellOnRealCooldown` and returning `isUsable=false` for spells on CD. In combat cooldown duration is secret so we can never reliably detect expiry. Removed the gate; all known non-redundant defensives now appear with the cooldown swipe as the visual indicator.
- **Rotation list (positions 2+) permanently hides spells on cooldown** - Added `PassesRotationFilters` in SpellQueue.lua that checks availability and redundancy but skips `IsSpellUsable`/cooldown filtering. The rotation list now uses this function.
- **Cooldown swipe not re-shown when icon slot is reused** - `HideDefensiveIcon` and the DPS slot-clear path were calling `cooldown:Hide()` without resetting `_cooldownShown` / `_chargeCooldownShown` / `_cachedMaxCharges`. All three flags now reset in both clear paths.
- **Icon background corner-clipping** - `iconMask` was only applied to `iconTexture`, not `slotBackground`. Added `slotBackground:AddMaskTexture(iconMask)` so the background is also clipped.
- **Disabled spec profile not applied on login/reload** - `PLAYER_ENTERING_WORLD` now calls `OnSpecChange()` to apply the spec profile (including disabled state) on world entry.
- **Defensive icons/health bar could re-appear while spec-disabled** - `OnHealthChanged` now guards on `isDisabledMode` so live health changes can't undo the hide performed by `EnterDisabledMode`.

## [3.25.1] - 2026-02-17

### Fixed

- Critical: Crash on addon load caused by variable scoping error in defensive spell initialization (`defensiveAlreadyAdded` declared after use)
- Critical: Combat crash when spell procs are active (restored `IsImportantSpell` stub accidentally removed during cleanup)
- Suppressed single-button assistant warning when current spec is set to DISABLED in options

### Changed

- Internal: Unified spell info caching in BlizzardAPI (eliminated duplicate caches in SpellQueue and RedundancyFilter, ~35 lines consolidated)
- Internal: Removed ~90 lines of dead code and redundant abstractions (self-assignment exports, unused texture allocations, legacy stubs)
- Internal: Simplified proc sorting logic (removed unused "important proc" categorization, ~20 lines)
- Internal: Optimized defensive spell registration with table-driven iteration (4 loops → 1 loop)

## [3.25.0] - 2026-02-14

### Added

- Per-class defensive spell lists: profiles now store spell lists under `classSpells[playerClass]` so one profile works across all classes
- Class-colored header in Defensives options panel showing which class's spells are being edited
- Migration: existing flat spell lists (`selfHealSpells`/`cooldownSpells`/`petHealSpells`) automatically migrated to new structure on first load
- `GetClassSpellList(listKey)` helper for clean per-class spell access
- `/jac defensive` now shows current class name and pet heal count
- **Pet rez/summon system**: High-priority defensive icon when pet is dead (`UnitIsDead`) or missing (`!UnitExists`) - reliable in combat (not secret)
- `CLASS_PET_REZ_DEFAULTS` in SpellDB: Hunter (Revive Pet, Heart of the Phoenix, Call Pet 1), Warlock (all summon demons), Death Knight (Raise Dead)
- `BlizzardAPI.GetPetStatus()`: returns "dead", "missing", or "alive" using combat-safe APIs
- **Pet health bar**: Teal-colored StatusBar mirroring player health bar style, independently toggleable via `showPetHealthBar`
  - Auto-hides when no pet is active, shows red dead overlay when pet is dead
  - StatusBar accepts secret values - renders pet health visually even when exact % is hidden
  - Stacks above player health bar when both enabled, defensive icons offset correctly for both bars
- Pet Rez/Summon and Pet Heal priority list sections in Options panel (hidden for non-pet classes)
- `/jac defensive` now shows pet status, pet health %, pet rez spell count
- `AddSpellToList` nil guard for safety

### Changed

- Defensive spell lists are no longer stored at `profile.defensives.selfHealSpells` - they live under `profile.defensives.classSpells[CLASS].selfHealSpells`
- Profile copy/share now transfers visual settings (thresholds, icon count, display mode) while each class auto-populates its own defensive spells on first login
- Pet heal suggestions now require pet to be alive (dead/missing triggers rez spells instead)
- Pet heal threshold is best-effort: pet health is secret in combat, heals only suggested when health is readable
- Added inline code comments throughout explaining 12.0 secret limitations: thresholds are out-of-combat only, pet heals are out-of-combat only, pet rez/summon works in combat via UnitIsDead/UnitExists
- UIFrameFactory defensive icon offset accounts for both player and pet health bars when stacked

### Fixed

- Fixed duplicate spells in defensive queue: pet rez/heal now shares `defensiveAlreadyAdded` with player defensives (prevents e.g. Exhilaration appearing twice for Hunters)
- Fixed `petHealThreshold` fallback using wrong default (70 instead of profile default 50)
- Added `issecretvalue` guard in UIHealthBar `UpdatePet()` for consistency with `GetPetStatus()`

## [3.24.1] - 2026-02-12

### Changed

- RedundancyFilter: `GetCachedSpellInfo` now routes through SpellQueue's cache (avoids ~12 uncached `C_Spell.GetSpellInfo` calls per redundancy check)
- ActionBarScanner: Reuse `BlizzardAPI.GetAddon()` instead of duplicate `cachedAddon` local
- Updated "Show Hotkeys" tooltip descriptions in all 9 locales (removed stale "skips hotkey detection" claim)

### Removed

- Deleted deprecated root `Locale.lua` (only `Locales/*.lua` files are loaded)

## [3.24.0] - 2026-02-12

### Added

- Separate "Key Press Flash" toggles for offensive and defensive queues

### Changed

- ActionBarScanner: Extract `CacheHotkey` helper in `GetSpellHotkey` (reduces code duplication)
- ActionBarScanner: `ClearAllCaches` now also clears `abbreviatedKeyCache` (fixes stale gamepad icons on style change)
- ActionBarScanner: Minor code cleanup (cached addon lookup, remove unused upvalues, remove shadowed locals, remove redundant debug function)

### Fixed

- Gamepad modifier keys showing "S" prefix instead of trigger icons when used with shoulder buttons

## [3.23.0] - 2026-02-12

### Added

- Simplified Chinese (zhCN) and Traditional Chinese (zhTW) locale support
- 56+ missing translation keys added to all existing locales (deDE, frFR, ruRU, esES, esMX, ptBR) covering gamepad icons, spell search UI, panel interaction, defensive display modes, visibility toggles, and profile switching

### Changed

- Split single Locale.lua into per-language files under Locales/ folder for easier maintenance and community contributions

### Fixed

- Removed dead/outdated locale keys (Cooldown Threshold, Debug Mode, About, Slash Commands) from older translations
- Removed duplicate key definitions within locale sections
- Added missing `UI Scale` translation to esMX and ptBR
- Added missing `Clear All` translation to zhCN

## [3.22.0] - 2026-02-11

### Added

- **Target Frame Anchor:** New option to attach the spell queue to the default target frame (Top/Bottom/Left/Right). Anchor persists even when target frame is hidden. Dragging detaches, re-enable in General → Icon Layout. Localized in all 7 languages.

## [3.21.7] - 2026-02-11

### Fixed

- **Fix crash opening hotkey override dialog**: `OpenHotkeyOverrideDialog` was calling `addon:GetCachedSpellInfo()` (doesn't exist) instead of `SpellQueue.GetCachedSpellInfo()` - right-clicking a spell icon to set a custom hotkey caused an error
- **Fix glow animations not pausing/resuming on combat state change**: `PauseAllGlows` and `ResumeAllGlows` were called without the required `addon` argument at 4 call sites, so they silently did nothing

## [3.21.6] - 2026-02-11

### Changed

- **Removed section summaries from Offensives/Defensives tabs**: Info descriptions at top of each tab removed - settings are self-explanatory
- **Compact About panel**: Replaced verbose feature list with concise one-liner; removed console command instructions (assisted combat is on by default in 12.0)
- **About version now reads from TOC**: Uses `C_AddOns.GetAddOnMetadata` instead of stale `db.global.version` default

### Removed

- Console command references from About panel and debug output (`assistedMode`, `assistedCombatHighlight` CVars are on by default in 12.0)
- Stale `db.global.version = "2.6"` default (was never updated, About panel now reads TOC version)
- CVar validation from `BlizzardAPI.ValidateSetup()` and "Quick Fix Commands" from `/jac test` output

## [3.21.5] - 2026-02-11

### Changed

- **Defensive queue and health bar disabled by default**: New profiles start with defensives off and health bar hidden - enable in Defensives tab if desired
- **Clear All buttons for blacklist and hotkey overrides**: Both panels now show a "Clear All" button (with confirmation) when entries exist
- **Removed health bar color gradient**: Bar stays green with red background showing missing health (gradient didn't work with secret health values)

### Fixed

- **Fix `IsShown` crash in `HideDefensiveIcon`**: Was passing addon object (`self`) instead of defensive icon frame - caused 57+ errors per second during health updates
- **Fix `ShowDefensiveIcon` silently failing**: Two call sites were missing the required `defensiveIcon` frame parameter, so defensive icons never displayed when health dropped or hotkey overrides changed
- **Fix health bar toggle in options**: Was calling nonexistent `UIHealthBar.DestroyHealthBar()` instead of `UIHealthBar.Destroy()` - toggling health bar off in settings had no effect
- **Fix default mismatches in Options panel**: `maxIcons` fallback was 5 (should be 4), `iconSpacing` fallback was 2 (should be 1), causing options sliders to show wrong values on fresh profiles
- **Fix profile migration on profile switch**: `RefreshConfig` now calls `NormalizeSavedData()` so switching to an older profile properly migrates string-keyed spell IDs, profile-level blacklists, and `panelLocked` boolean
- **Fix profile reset wiping character data**: `OnProfileReset` no longer clears blacklist and hotkey overrides, which are character-specific and should persist across profile operations

### Removed

- Dead variable `defensivePosition` in `UIHealthBar.CreateHealthBar` (assigned but never read)
- `BlizzardAPI` import from `UIHealthBar` (only used by removed gradient code)
- **Threshold sliders from Defensives options**: Self-heal, cooldown, and pet heal threshold settings hidden from UI (health values are secret in 12.0+, making user-configured thresholds non-functional); defaults still used internally

## [3.21.4] - 2026-02-11

### Added

- **Highlight Mode Dropdown**: Replaced `Highlight Primary Spell` toggle with a dropdown offering granular glow control
  - Both Offensive and Defensive tabs now have independent `Highlight Mode` dropdowns
  - Options: All Glows (default), Primary Only, Proc Only, No Glows
  - "Insert Procced Abilities/Defensives" toggles remain separate (control queue content, not visuals)
  - Backwards compatible: existing `focusEmphasis = false` migrates to "Proc Only" mode

### Changed

- **Code Cleanup**: Removed orphaned locale strings and deduplicated spell data
  - Deduplicated `RAID_BUFF_SPELLS` from `UNIQUE_AURA_SPELLS` in RedundancyFilter (programmatic merge instead of manual copy)
  - Fixed locale bug: "Restore Defaults" button for cooldowns was showing self-heal description (duplicate key overwrite)
  - Removed 9 orphaned locale keys across all 7 languages (Display Behavior, Visual Effects, Stabilization Window, etc.)

- **Options Reorganization**: Moved `Max Icons` from General tab to Offensives Display section (it only affects the offensive queue)

- **SpellDB Reclassification**: Removed 5 DPS abilities from `DEFENSIVE_SPELLS` so they appear in the offensive queue
  - Blooddrinker (Blood DK damage channel), Fel Devastation (Vengeance DH core rotational AoE)
  - Seraphim (Prot Paladin DPS cooldown), Odyn's Fury and Thunderous Roar (Warrior damage CDs)
  - None of these were in `CLASS_SELFHEAL_DEFAULTS` or `CLASS_COOLDOWN_DEFAULTS`, so defensive sidebar is unaffected

### Fixed

- **Major Performance Fix (SpellQueue v31)**: Reduced in-combat CPU usage from ~34% to near-zero
  - Added early-exit checks in `GetCurrentSpellQueue()` when frame should be hidden (mounted, out of combat with hideQueueOutOfCombat enabled, etc.)
  - Removed expensive `IsSpellOnRealCooldown` check from `IsSpellUsable()` - was doing 8+ API calls per spell, multiplied by 20-30 spells per update = 200+ API calls every 0.1s
  - Added `filterResultCache` to cache `PassesSpellFilters()` results per update cycle - prevents re-checking the same spell multiple times
  - Cooldown visibility now relies solely on the cooldown swipe (visual indicator) instead of pre-filtering

- **GC Pressure Reduction**: Pooled frequently allocated tables to reduce garbage collection stutter
  - `OnHealthChanged`: Added 100ms throttle for defensive queue updates (UNIT_HEALTH fires multiple times per second in combat)
  - `SpellQueue.GetCurrentSpellQueue()`: Pooled `addedSpellIDs` and `recommendedSpells` tables (previously allocated every 30-150ms)
  - `GetDefensiveSpellQueue()`: Pooled `alreadyAdded` and `dpsQueueExclusions` tables

- **Architectural Optimizations**: Reduced redundant work through caching and dirty flags
  - Increased aura cache duration from 0.2s to 0.5s (60% fewer aura API calls, UNIT_AURA events still invalidate)
  - Removed repeated LibStub lookups in hot path defensive functions (use module-level cached refs)
  - Added dirty flag system: OnUpdate uses longer intervals (0.5s) when idle, immediate updates on events
  - Events (proc, target change, spellcast) now mark queues dirty for responsive updates

- **Advanced Optimizations**: Eliminated closure creation and reduced string operations
  - Key press detector: Inlined hotkey matching (was creating closure on every keypress)
  - OnUpdate early exit: Skips all work when UI is completely hidden (saves CPU when mounted)
  - Gamepad check: Quick "PAD" substring pre-check avoids 11 string.find() calls for keyboard binds

- **OnUpdate Loop Optimization**: Reduced per-frame overhead significantly
  - Fast path: Early exit at top of OnUpdate when within throttle interval (most common case)
  - Cached `assistedCombatIconUpdateRate` CVar lookup (was calling GetCVar every frame, now every 5s)
  - Pre-cached function references at frame creation time to avoid table lookups in hot path
  - `StartAssistedGlow`/`StartDefensiveGlow`: Skip redundant setup work when already in correct state
  - `IsSpellProcced`: Added per-update cache to avoid redundant API calls across multiple icons

- **UIRenderer Throttling (v10)**: Major reduction in per-frame API calls while preserving responsiveness
  - Added `COOLDOWN_UPDATE_INTERVAL = 0.15s` throttle for cooldown updates (6-7x/sec instead of 33x/sec)
  - Cooldown swipe animates smoothly once `SetCooldown` is called - no need to update every frame
  - Throttled `C_Spell.IsSpellInRange` checks - range rarely changes faster than 0.15s
  - Cached hotkey normalization - string operations (upper, gsub) only run when hotkey actually changes
  - Proc glows check every frame (cheap cache lookup) for instant feedback when abilities proc
  - Resource/usability checks synced with cooldown throttle (0.15s) for responsive blue tint

- **BlizzardAPI Caching (v27)**: Reduced redundant API calls in SpellQueue and UIRenderer
  - `GetDisplaySpellID`: Now caches `C_Spell.GetOverrideSpell` results per update cycle (was called 10-20+ times per update with no caching)
  - Override cache cleared with proc cache each update cycle

- **Gamepad Keybind Optimization (ActionBarScanner v33)**: Fixed ~100% CPU overhead when gamepad mode enabled
  - `CalculateKeybindHash()` was iterating through all binding strings and hashing each character on EVERY cache validation check
  - With gamepad enabled, binding strings are longer ("SHIFT-PAD1" vs "1"), causing O(n*m) overhead where n=bindings, m=string length
  - Now computes hash ONCE when rebuilding binding cache, stores result in `cachedBindingHash`
  - Reduces per-lookup cost from O(bindings * avg_length) to O(1)
  - `AbbreviateKeybind()` caching already in place - this fixes the validation path
  - Gamepad CPU overhead reduced from ~8% to near-zero

- **Hotkey Lookup Rate-Limiting**: Eliminated expensive action bar scanning on every frame
  - `GetSpellHotkey()` now returns cached values immediately, even when cache marked "invalid"
  - Full lookups (`FindSpellInActions` iterating 100+ slots) rate-limited to max 4x/sec
  - Stale hotkey values are usually correct anyway (keybinds rarely change mid-combat)
  - Reduces per-icon CPU from O(100 slots) to O(1) for 99% of frames

- **UIRenderer Visual State Caching**: Eliminated per-frame UI API calls
  - Cached `SetTextColor` for range indicator - only updates when out-of-range state changes
  - Cached `SetDesaturation`/`SetVertexColor` for icon tinting - only updates when visual state changes (channeling/no-resources/normal)
  - Reduced UI API calls from ~100/frame to ~5/frame during stable combat

### Removed

- **Mobility Feature**: Removed the gap closer feature entirely
  - `C_Spell.IsSpellInRange()` returns secret values in WoW 12.0+ combat, making range detection unreliable
  - Feature's value was primarily in combat where range detection doesn't work
  - Removed: Options tab, profile settings, locale strings, SpellQueue insertion, RedundancyFilter check
  - Removed: `CLASS_MOBILITY_DEFAULTS`, `CLASS_PETMOBILITY_DEFAULTS`, `IsMobilitySpell()`, `IsInMeleeRange()`

## [3.21.2] - 2026-02-05

### Fixed

- **Flash animation scaling bug**: Fixed OnUpdate handler stacking that caused spell flash to grow uncontrollably on rapid key presses (sentinel value pattern prevents re-wrapping)
- **Spec change cache invalidation**: Profile switch via spec change now properly invalidates spell, macro, and hotkey caches (early return was skipping cache clears)
- **Health bar in disabled mode**: Health bar now hides when entering disabled mode and restores when exiting

### Changed

- **Options panel reorganization**: Offensive and Defensive tabs now mirror each other with parallel section structure (Queue Content → Display → unique sections)
- **Gamepad Icon Style**: Moved from Icon Layout to Appearance section in General tab (visual setting, not spatial layout)

## [3.21.1] - 2026-02-04

### Fixed
- **Aura filtering consistency (RedundancyFilter v36)**: Fixed aura recast suggestions appearing during long combat
  - Adaptive cache expiration: Recent validation (<5 min) uses actual expiration time; older validation uses conservative 80% threshold
  - Prevents hour-long buffs (poisons, imbues) from reappearing mid-combat during persistent boss fights
  - All duration calculations done out of combat to avoid arithmetic on WoW 12.0 secret values

## [3.21.0] - 2026-02-04

### Added
- **Key press flash**: Icons flash gold when their hotkey is pressed for visual feedback
- **Separate hotkey toggles**: Individual "Show Hotkeys" options for Offensive and Defensives sections
  - Performance benefit: disabling skips hotkey detection for that section only
- **Insert Procced Defensives option**: Toggle to control procced defensives (Victory Rush, free heals) at any health

### Changed
- **Options reorganization**: Moved "Primary Spell Scale" from General to Offensive section (offensive-only setting)
- **Threshold note shortened**: More concise threshold fallback description
- **Options preservation**: Fixed threshold settings and new toggles being removed during dynamic updates

### Fixed
- **Profile switching**: Fixed queue appearing when switching to healer spec marked as "DISABLED"
- **Flash animation growth**: Fixed key press flash growing larger over time due to cumulative scale bug
- **Critical timer allocation fix**: Fixed `C_Timer.After` being called every frame in glow animations, causing massive GC pressure
- **Major performance fix**: Reduced in-combat CPU usage from ~34% to near-zero
  - Early-exit checks when frame hidden (mounted, out of combat, etc.)
  - Removed expensive `IsSpellOnRealCooldown` check (200+ API calls per update)
  - Added `filterResultCache` to prevent re-checking same spell multiple times
  - Pooled frequently allocated tables to reduce GC stutter
- **Gamepad keybind optimization**: Fixed ~100% CPU overhead when gamepad mode enabled
  - `CalculateKeybindHash()` now computed once instead of every validation check
- **Hotkey lookup rate-limiting**: Eliminated expensive action bar scanning (100+ slots) on every frame
  - Full lookups rate-limited to max 4x/sec, cached values returned immediately
- **UIRenderer throttling**: Major reduction in per-frame API calls
  - Added 0.15s throttle for cooldown updates (cooldown swipe animates smoothly once set)
  - Throttled range checks, cached hotkey normalization
  - Visual state caching (tinting, desaturation) - only updates when state changes

### Removed
- **Mobility feature**: Gap closer feature removed entirely
  - `C_Spell.IsSpellInRange()` returns secret values in WoW 12.0+ combat, making it unreliable
  - Removed Options tab, profile settings, locale strings, SpellQueue integration

## [3.2] - 2026-01-31

### Added
- **Gamepad keybind support**: Full gamepad/controller button display using native WoW atlas textures
  - D-pad, face buttons (PAD1-6), shoulders/triggers, stick clicks + directions, paddles, system buttons
  - **New option "Gamepad Icon Style"** in General settings: Generic (1/2/3/4), Xbox (A/B/X/Y), PlayStation (Cross/Circle/Square/Triangle)
  - Uses `_64` atlas with proper button outline matching WoW's default keybind display
  - Pixel-perfect positioning with 1px right/down offset

- **Extended keyboard keybind abbreviations**:
  - Numpad special keys: NUMPADDIVIDE→N/, NUMPADMULTIPLY→N*, NUMPADMINUS→N-, NUMPADPLUS→N+, etc.
  - Arrow keys, navigation keys, punctuation (TAB, ENTER, PAUSE, brackets, etc.)

### Changed
- **ActionBarScanner v32**: Extended keybind abbreviation with full keyboard and gamepad support
- **UIRenderer v10**: Enhanced hotkey normalization for flash animation matching on all key types
- **Delayed keybind refresh**: Added 0.3s follow-up invalidation to catch late-committed gamepad binding changes

## [3.199] - 2026-01-31

### Added
- **Options:** "Require Hostile Target" checkbox is now disabled when "Hide Out of Combat" is enabled
  - These options are redundant together since hideQueueOutOfCombat hides the frame before the hostile target check runs
  - Description updated to explain the relationship

### Changed
- **UIRenderer v10**: Optimized rendering loop when auto-hide features are active
  - Skips expensive rendering operations (hotkey lookups, icon updates, glow animations) when frame is hidden
  - Still processes queue building and cache updates to ensure instant response when frame becomes visible
  - Maintains warm caches for redundancy filter, aura tracking, and spell info
  - Applies to: hideQueueOutOfCombat, hideQueueForHealers, hideQueueWhenMounted, requireHostileTarget

### Fixed
- **UIRenderer v10**: Fixed large highlight frame bug appearing over backup abilities when auto-hide features are enabled
  - Now properly stops all glow animations (assisted, proc, defensive) when frame should be hidden
  - Prevents highlight frames from scaling incorrectly during auto-hide transitions
  - Skips icon updates entirely when `shouldShowFrame = false` to avoid frame state inconsistencies

## [3.198] - 2026-01-30

### Changed
- **UIRenderer v34**: CPU optimization improvements for high icon counts
  - Eliminated redundant IsSpellProcced calls to ActionBarScanner
  - Replaced pcall closures with direct issecretvalue checks (cooldown, charge display)
  - Cached "Waiting for" pattern on spellChanged instead of every frame
  - Throttled IsSpellUsable per-icon to 0.25s interval (reduced from 60fps)
  - Track panelLocked state to skip RegisterForClicks when unchanged
  - Removed duplicate defensive icon cooldown updates
  - Added explicit secret value handling for range detection (C_Spell.IsSpellInRange)

- **RedundancyFilter v36**: Edge-case safety for in-combat logins
  - Add fail-open behavior when trusted cache unavailable (no pre-combat snapshot)
  - Only filter non-DPS spells if cache exists; allow through if no trusted data
  - Prevents false negatives during combat login scenarios

- **SpellDB v18**: Spell classification accuracy sweep
  - Remove damage/hybrid spells from HEALING_SPELLS: Cone of Cold, Purge the Wicked, Death Strike, Drain Life, Grimoire of Sacrifice, Penance, Soul Cleave, Immolation Aura, Reaver, Fracture, Expel Harm
  - Remove pet maintenance from HEALING_SPELLS: Mend Pet, Revive Pet (now offensive, DPS-critical)
  - Remove DPS gap closer from UTILITY_SPELLS: Shadowstep (now offensive)
  - Remove damage-dealing spells from CROWD_CONTROL_SPELLS: Rake (bleed DoT), Holy Word: Chastise variants
  - Remove speed-boosting ability from UTILITY_SPELLS: Chi Torpedo

## [3.197] - 2026-01-29

### Added
- **Per-Spec Profile Selection**: Automatic profile switching based on specialization
  - Enable/disable via "Auto-switch profile by spec" toggle in Profiles section
  - Assign different profiles to each spec, or set to "(Disabled)" to hide addon for that spec
  - Healer specs are automatically set to "disabled" by default on first run
  - Profile switching occurs when changing specs or logging in

### Changed
- **Options.lua**: Removed verbose instructions from Profiles section to save vertical space
  - Clear description fields for desc, descreset, choosedesc, copydesc, deldesc, resetdesc
  - Maintains functionality while reducing UI clutter

## [3.195] - 2026-01-29

### Changed
- **RedundancyFilter v35**: Add alternate aura IDs from 12.0 Midnight Exclusion Whitelist
  - Add alternate IDs for group buffs: Mark of the Wild (264778), Power Word: Fortitude (264764), Battle Shout (264761)
  - Fix mislabeled 264761 (Battle Shout alternate, not Blessing of the Bronze)
  - Add Frostbrand Weapon (196834) and Earthliving Weapon (382021) to shaman imbues
  - Clean up poison buff IDs to match whitelist exactly

## [3.194] - 2026-01-29

### Changed
- **RedundancyFilter v34**: Poison detection - cast-based inference for 12.0 compatibility
  - Use UNIT_SPELLCAST_SUCCEEDED for primary detection (not aura API)
  - Poisons are hour-long buffs (Category A) - safe for cast-based inference
  - Include both cast IDs and possible buff IDs for fallback detection
  - Preserve trusted aura cache in combat (don't wipe on UNIT_AURA)
  - Three-tier detection: cast tracking > aura cache by ID > aura cache by name

### Changed
- **DebugCommands.lua**: Updated poison detection debugging commands
  - Enhanced `/jac poison` command for testing cast-based inference

## [3.15] - 2026-01-27

### Added
- **BlizzardAPI v26**: API-specific secret helpers for incremental 12.0 compatibility
  - `GetCooldownForDisplay(spellID)` - Returns start, duration (nil if secret)
  - `IsSpellReady(spellID)` - Boolean usability check, fail-open if secret  
  - `GetAuraTiming(unit, index, filter)` - Returns duration, expiration (field-level checks)
  - `GetSpellCharges(spellID)` - Returns current, max charges (field-level checks)
  - Purpose-specific helpers check only needed fields as Blizzard releases API access incrementally

- **MacroParser v21**: [stealth] and [combat] conditional evaluation
  - Implemented `[stealth]`, `[nostealth]`, `[combat]`, `[nocombat]` conditional checks
  - Fixes Rogue/Druid keybind detection for macros like `/cast [stealth] Cheap Shot; Sinister Strike`

### Changed
- **UIRenderer v9**: Migrated to centralized secret handling and Blizzard's cooldown logic
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using API-specific helpers for field-level granularity (30+ call sites simplified)
  - Refactored to use Blizzard's ActionButtonTemplate cooldown logic (mimics ActionButton_UpdateCooldown)
  - Removed manual GCD/cooldown management, now using C_Spell APIs directly like Blizzard

- **RedundancyFilter v25**: Migrated to centralized secret handling  
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using `GetAuraTiming()` for field-level aura access
  - Allows partial aura data when some fields are secret (best-effort processing)

- **Options.lua**: Migrated to centralized secret handling and added configurable health thresholds
  - Cooldown display now uses `BlizzardAPI.IsSecretValue()`
  - All spell info lookups use `BlizzardAPI.GetSpellInfo()` for consistent secret handling
  - Removed redundant LibStub lookups inside functions
  - Added configurable health thresholds: selfHealThreshold, cooldownThreshold, petHealThreshold

- **DebugCommands.lua**: Migrated to centralized secret handling
  - Health API status now uses `BlizzardAPI.IsSecretValue()`

- **UIFrameFactory v10**: Refactored cooldown frames to match Blizzard's ActionButtonTemplate
  - Separate cooldown and chargeCooldown frames (matching Blizzard's structure)
  - Smaller, more transparent countdown numbers to avoid overlapping hotkey text

- **JustAC.lua**: Added configurable health thresholds for defensive spells
  - Self-heal threshold (default 80%), cooldown threshold (default 60%), pet heal threshold (default 50%)
  - Uses exact health when available, falls back to LowHealthFrame overlay when secret

### Removed
- **Code consolidation**: Removed duplicate `SafeGetSpellInfo` implementations (-18 lines)
  - Deleted from MacroParser.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - Deleted from FormCache.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - All spell info access consolidated through BlizzardAPI for consistent secret handling

- **RedundancyFilter**: Removed unused debug variables (-3 lines)
  - Deleted unused `lastDebugPrintTime` table
  - Deleted unused `DEBUG_THROTTLE_INTERVAL` constant

### Fixed
- **MacroParser v21**: Removed dead code (-12 lines)
  - Deleted `SafeIsMounted()` - defined but never called
  - Deleted `SafeIsOutdoors()` - defined but never called

### Performance
- **Comment cleanup**: Condensed verbose comments across 4 core modules (-80 lines)
  - Removed multi-line explanations that restated obvious code
  - Kept all operational guidance and critical API compatibility notes
  - MacroParser, BlizzardAPI, UIRenderer, RedundancyFilter now more concise

## [3.14] - 2026-01-26

### Added
- **Multiple Defensive Icons**: Can now display 1-3 defensive spells simultaneously
  - New `defensives.maxIcons` setting (1-3, default 1) controls how many icons to show
  - Icons layout horizontally for SIDE1/SIDE2 positions (along queue direction)
  - Icons stack perpendicular for LEADING position
  - Each icon has full visual parity: glow, cooldown, hotkey, tooltips
- **Defensive Icon Scale**: New independent scaling option for defensive icons
  - `defensives.iconScale` (1.0-2.0, default 1.2) works like Primary Spell Scale
  - All defensive icons scale uniformly with this setting
  - No longer tied to DPS queue's firstIconScale
- **12.0 Local Cooldown Tracking**: When `C_Spell.GetSpellCooldown()` returns secrets in combat, defensive spell cooldowns are now tracked locally using `UNIT_SPELLCAST_SUCCEEDED` events and `GetSpellBaseCooldown()` (which is NOT secret in 12.0)
  - Duration caching: When spells are cast out of combat, actual modified duration is captured and cached for in-combat use
  - Cached durations cleared on talent/spec changes
  - `BlizzardAPI.RegisterDefensiveSpell()`, `ClearTrackedDefensives()`, `IsSpellOnLocalCooldown()`
  - `JustAC:RegisterDefensivesForTracking()` registers all configured defensive spells
- **In-Combat Activation Tracking**: RedundancyFilter now tracks spell casts during combat via `UNIT_SPELLCAST_SUCCEEDED`
  - Works reliably even with 12.0 combat log restrictions (mirrors proc detection system)
  - Filters out redundant suggestions for spells cast during combat (forms, poisons, long buffs)
  - Toggle detection: Automatically detects when toggleable auras canceled mid-combat via non-secret APIs (forms, stealth, pets, mounts)
  - Cleared on leaving combat
- **Charge Count Display**: Shows current charges for charge-based spells on both defensive and DPS icons
  - Displayed in bottom-right corner at 85% of hotkey font size
  - Only shown for multi-charge spells (Fire Blast, Frenzied Regen, Roll, etc.)
  - Handles 12.0 secret values properly

### Changed
- **BlizzardAPI v25**: Enhanced cooldown detection system
  - `IsSpellOnRealCooldown()` now uses 3-tier fallback: Native API → Local cooldown tracking → Action bar usability check
  - Added charge detection for charge-based spells (filters when depleted)
  - Secret value handling improvements
- **RedundancyFilter v24**: In-combat activation tracking with toggle detection
- **UIRenderer v6**: Simplified cooldown overlay handling
  - Cooldown widget auto-expires naturally (no manual hiding on 0,0 data)
  - Minimal change detection prevents flicker while handling secrets correctly
  - Fixed cooldown overlays not updating reliably during combat
- **UIFrameFactory v8**: Added charge text display to both defensive and DPS icons
- **Defensive Spell Defaults Redesigned for 12.0**: Streamlined spell lists with fewer, better choices
  - Removed cast-time spells and spec-specific deep talents
  - Reordered for priority: instant heals > absorbs > damage reduction
  - Self-heals: ~2-3 spells per class (reduced from 3-4)
  - Cooldowns: ~2-3 big defensives per class
- **SpellDB**: Added Word of Glory (85673) to HEALING_SPELLS for Divine Purpose proc detection

### Fixed
- **Cooldown Overlay Display**: Fixed cooldowns not updating reliably during combat with secret values
  - Cooldown widget now expires naturally instead of being manually hidden
  - Properly handles transitions between secret and non-secret cooldown states
- **Defensive Proc Detection**: Fixed proc'd defensives showing gold glow even after proc ended
  - `IsSpellProcced()` now checks both spell ID and override ID
  - Validates procs are still active via API instead of trusting cached events
  - Automatic cleanup of stale proc entries
- **Multi-Defensive Icon Queue**: Fixed queue disappearing with maxIcons > 1
  - `GetUsableDefensiveSpells` now uses local table instead of modifying caller's table
- **Charge-Based Spell Filtering**: Fixed charge spells staying in queue when depleted
  - `IsSpellOnRealCooldown()` now checks `C_Spell.GetSpellCharges()` for zero charges
- **Secret Value Handling**: Fixed comparison errors with secret charge counts
  - Check for secrets on both `maxCharges` and `currentCharges` before comparing

### Technical Notes
- Verified in-game on WoW 12.0.0 (build 65560):
  - `GetSpellBaseCooldown()` is NOT secret in combat ✅
  - `C_Spell.GetSpellCooldown()` is SECRET in combat ❌
  - `C_Spell.GetSpellCharges()` is SECRET in combat ❌
- Out-of-combat casts capture actual modified duration for later use
- In-combat uses cached duration if available, otherwise base cooldown
- Base cooldown ignores haste/talent modifiers (conservative approach)

## [3.13] - 2026-01-25

### Added
- **Health Bar Display**: Optional compact health bar above main queue
  - Green → Yellow → Red gradient based on health percentage
  - Enable via Defensive Queue settings: "Show Health Bar"
  - Supports edge-to-edge display for single icon mode, 25% inset for multiple icons
  - New module: `UIHealthBar.lua` with StatusBar widget approach
- **Custom Hotkeys**: Right-click defensive icon to set custom keybinds for spells
  - Immediately visible without reload
  - Tooltips show "(custom)" indicator for overridden hotkeys
- **Tooltip Support**: Defensive icon now respects tooltip settings (showTooltips/tooltipsInCombat)

### Changed
- **Animation System**: Unified all glows on marching ants animations with color tinting
  - DPS queue: White marching ants (regular), Gold (proc)
  - Defensive icon: Green marching ants (regular), Gold (proc)
  - Removed 370 lines of old unused animation code
  - No more blue tint on position 1
- **Position System Refactor**: Renamed defensive icon positions for clarity across orientations
  - ABOVE → SIDE1 (health bar side)
  - BELOW → SIDE2 (opposite perpendicular)
  - LEFT → LEADING (opposite grab tab)
  - Health bar always appears on SIDE1 regardless of queue orientation
- **Default Settings**: Updated profile defaults for better user experience
  - Tooltips in combat: enabled by default
  - Defensive position: LEADING (opposite grab tab)
  - Defensive visibility: always visible (not just in combat)
  - First icon scale: standardized to 1.2 across all components

### Fixed
- **Defensive Icon Visibility**: Fixed icon disappearing when changing queue orientation
  - Now preserves state (id, isItem, isShown) across recreations
- **Defensive Icon Spacing**: Fixed spacing when health bar toggled on/off
- **Health Bar Sizing**: Fixed health bar not edge-to-edge in single icon mode
  - Single icon: full width with 0 offset
  - Multiple icons: 25% inset for visual balance
- **Health Bar Gradient**: Fixed color gradient not updating (was stuck on green)

## [3.12] - 2026-01-25

### Added
- `ActionBarScanner.GetSlotForSpell(spellID)` - Returns action bar slot for a spell (v30)
- `/jac defensive` command - Diagnose defensive icon system (DebugCommands v7)

### Changed
- **12.0 Resource Detection**: When `C_Spell.IsSpellUsable()` returns secret values, now falls back to checking `C_ActionBar.IsUsableAction()` on the action bar slot for that spell - this uses the visual icon state (desaturation) which is not secret (BlizzardAPI v21)
- **12.0 Defensive Health Detection**: Defensive system now uses `GetPlayerHealthPercentSafe()` which tries exact health first, then falls back to visual overlay when secrets block the API. When using the visual overlay, "low" = overlay showing (~35%), "critical" = high alpha (~20%)
- **Simplified Defensive Priority System**: Redesigned defensive spell selection: procs at any health; low (~35%) → big heals; critical (~20%) → cooldowns > potions > heals
- **GCD Swipe**: Removed fragile `anyIconOnGCD` detection loop - GCD now always propagates when active (uses dummy spell 61304 for accurate state)
- **Cooldown Caching**: Uses tolerance-based comparison (50ms threshold) to prevent flickering on repeated same-spell casts
- **Debug Logging Throttled**: Reduced log spam in debug mode - form redundancy, non-DPS spell filter, and macro parser messages now throttled

### Fixed
- **Defensive Icon Not Showing**: Fixed critical bug where `addon.defensiveIcon` was never assigned after creation - the defensive icon frame was created but not exposed to UIManager, causing all defensive suggestions to silently fail (UIFrameFactory v2)
- **Defensive Spells Filtered by DPS-Relevance**: In 12.0 when aura API is restricted (instances), the DPS-relevance filter incorrectly filtered out self-heal spells like Regrowth. Added `isDefensiveCheck` parameter to `IsSpellRedundant()` to bypass this filter for defensive spell selection
- Fixed GCD swipe not showing when repeatedly casting the same ability (e.g., spamming Shred)
- Fixed GCD swipe flickering caused by floating-point comparison on every frame
- Fixed cooldown swipe inset gap - cooldowns now fill icon exactly (`SetAllPoints(iconTexture)`), matching the standard action-button pattern
- Fixed icon mask not filling button properly - now uses `SetAllPoints(button)` instead of explicit sizing
- Fixed asymmetric frame sizing (was `actualIconSize + 1` width, `actualIconSize` height) - all textures now symmetric and centered
- Fixed flash/highlight textures using TOPLEFT anchor with 0.5px offset compensation - now properly centered
- **Debug Log Now Shows Spell Name**: "Non-DPS spell" filter message now includes spell name and ID for easier debugging

## [3.11] - 2026-01-25

### Fixed

- **Blue marching ants animation**: Fixed assisted combat glow (marching ants) not animating in combat
  - UIRenderer module was never loaded via LibStub in JustAC.lua
  - Added proper module loading and combat state propagation
  - Animation now correctly plays in combat, freezes out of combat
- **Secret value handling improvements**:
  - Fixed GCD cooldown detection with secret values in WoW 12.0+
  - Split GetSpellCooldown into raw (for UI widgets) and sanitized (for logic) versions
  - Fixed cooldown flicker by tracking lastCooldownWasSecret flag
  - Cooldown widgets handle secrets internally, Lua code uses sanitized values
- **Options blacklist persistence**: Fixed blacklistedSpells table not being initialized properly
- **Debug mode usability**: Removed extremely spammy macro parsing traces
  - Removed per-spell, per-command, and per-entry parsing debug messages
  - Kept useful messages: macro match results and specificity scores
  - Debug mode now much more readable while still showing important information

### Changed

- **Flash brightness**: Increased flash animation brightness (1.5, 1.2, 0.3 vertex color for ADD blend)

## [3.10] - 2026-01-25

### WoW 12.0 Midnight Compatibility Release

Major update for full WoW 12.0 (Midnight) compatibility with comprehensive secret value handling and modernized spell classification.

### Added

- **SpellDB.lua**: Native spell classification database replacing LibPlayerSpells-1.0
  - ~330 spell IDs across 4 categories: DEFENSIVE, HEALING, CROWD_CONTROL, UTILITY
  - Fail-open design: unknown spells assumed offensive (correct for DPS filtering)
  - Covers all classes including Evoker/Augmentation support
- **Out-of-range indicator**: Hotkey text turns red when queue spells are out of range
- **C_Secrets namespace wrappers**: `ShouldSpellCooldownBeSecret()`, `ShouldSpellAuraBeSecret()`, `ShouldUnitSpellCastBeSecret()` for proactive secrecy testing
- **Enhanced `/jac formcheck`**: Shows spell ID → form ID mappings and redundancy check results

### Changed

- **Module architecture**: Split UIManager.lua (2025 lines) into focused modules:
  - `UIAnimations.lua` (451 lines) - Animation/visual effects
  - `UIFrameFactory.lua` (881 lines) - Frame creation and layout
  - `UIRenderer.lua` (962 lines) - Rendering and update logic
  - `UIManager.lua` (154 lines) - Thin orchestrator
- **Resource coloring**: Now uses Blizzard's standard blue tint (0.5, 0.5, 1.0) when not enough mana/resources
- **Flash layering**: Flash (+6) > Proc Glow (+5) > Marching Ants (+4) for better visibility
- **Priest defensives**: Reorganized - Desperate Prayer moved to cooldowns, Vampiric Embrace added to self-heals

### Fixed

- **Icon artwork bleeding outside frame**: Icons now use 1px inset, SetTexCoord edge crop, and MaskTexture for beveled corners
- **Proc glow not showing**: Fixed combat state bug in UIRenderer (was checking never-updated variable)
- **Dead Priest spell ID**: Replaced Greater Fade (213602, removed in 10.0.0) with Desperate Prayer
- **Secret value crashes**: Hardened all API wrappers to handle 12.0 secret values gracefully
- **Best-effort aura detection**: Now skips individual secret auras instead of abandoning all remaining
- **Form redundancy check**: Now runs before secret bypass, using always-safe stance bar APIs
- **Raid buffs filtered**: Mark of the Wild, Fortitude, Battle Shout, Arcane Intellect, Blessing of the Bronze now hidden when active
- **Usability filtering**: Queue positions 2+ now filter spells on cooldown (>2s) or lacking resources

### Removed

- **LibPlayerSpells-1.0**: Removed entirely (outdated since Shadowlands, missing all modern spells)
- **Duplicate cooldown filtering**: Consolidated to SpellQueue only
- **Unused functions**: `HasBuffByIcon()`, `HasSameNameBuff()`, `IsRaidBuff()`

## [3.03] - 2025-12-15

### Added

- **Keybind abbreviations**: Long keybinds now display with compact abbreviations for better fit
  - Mouse buttons: BUTTON4→M4, BUTTON5→M5, MOUSEWHEELUP→MwU, MOUSEWHEELDOWN→MwD
  - Numpad: NUMPAD1→N1, NUMPAD0→N0
  - Navigation: PAGEUP→PgU, PAGEDOWN→PgD, HOME→Hm, END→End
  - Special: SPACE→Spc, ESCAPE→Esc, BACKSPACE→BkSp, CAPSLOCK→Caps
  - Editing: INSERT→Ins, DELETE→Del
  - Combined examples: CTRL-BUTTON4→CM4, SHIFT-NUMPAD5→SN5

### Changed

- **Keypress flash improvements**: Enhanced visual feedback for button presses
  - Flash now uses strobe/toggle behavior (like Blizzard's action buttons) for high visibility
  - Added short scale pulse (1.12x → 1.0 over 120ms) for emphasis
  - Flash centered on button and sized to match icon exactly
  - Flash positioned below marching ants/proc glow layers (proper z-ordering)
  - Single flash texture instead of doubled layers (cleaner visuals)
- **Empty slots visibility**: Empty slots now visible when abilities are filtered
  - Shows action bar background and border for unused positions up to maxIcons
- **Grab tab fade**: Now fades in/out on mouse hover for cleaner appearance
- **Grab tab persistence**: Stays visible during drag (won't disappear on fast cursor movement)
- **Drag improvements**: Drag from anywhere on icons or main frame when unlocked
- **Frame positioning**: Frame follows cursor precisely during drag with no offset
- **Context menu**: Right-click on icons/empty areas for options menu access

### Fixed

- **Critical**: Flash timing bug causing flash to run 2x faster than intended (double elapsed subtraction)
- **Critical**: Flash overlay staying visible after keypress (OnUpdate handler conflict)
- **Performance**: Optimized keypress detector hot-path (eliminated redundant string concatenations)
- **Visual**: Removed accidental duplicate flash texture on defensive icon
- **Code quality**: Centralized bypass flag logic to eliminate duplication across modules
- **Maintainability**: Added GetBypassFlags() helper in BlizzardAPI for consistent feature detection

## [3.02] - 2025-12-09

### Added

- **Version detection infrastructure**: Prepare for WoW 12.0 compatibility fixes
- Added `BlizzardAPI.GetInterfaceVersion()` - Returns current WoW version (110207, 120000, etc.)
- Added `BlizzardAPI.IsMidnightOrLater()` - Check if running 12.0+
- Created `Documentation/VERSION_CONDITIONALS.md` - Patterns for adding version-specific code
- Ready to accept 12.0 error reports and add conditional fixes

### Changed

- **UI**: Empty slots now visible when abilities are filtered (on cooldown, blacklisted, etc.) - shows action bar background and border for unused icon positions up to maxIcons setting
- **Cooldown filter prep window**: Increased from 2s to 5s before abilities appear
- Abilities now show when ≤5s remaining on cooldown (was 2s)
- Provides more preparation time for abilities coming off cooldown
- Reduces queue flickering from short cooldowns
- **Cooldown-aware filtering enabled always**: Hide abilities on cooldown >5s, show when coming off CD
- Applies to both main DPS queue and defensive queue
- Reduces queue clutter from abilities on long cooldowns
- Keeps queue focused on immediately available or soon-ready abilities
- **Whitelist approach for WoW 12.0**: When aura detection is blocked, only show DPS-relevant spells in queue
- Automatically filters out forms, pets, raid buffs, and utility abilities when can't verify their state
- Uses LibPlayerSpells flags (HARMFUL, BURST, COOLDOWN, IMPORTANT) to identify rotation-critical abilities
- Keeps queue focused on offensive rotation when addon can't access buff information
- Automatically hide raid buffs (Battle Shout, Arcane Intellect, etc.) from queue when WoW 12.0 blocks aura detection
- Uses LibPlayerSpells RAIDBUFF flag to identify long-duration maintenance buffs
- Reduces queue clutter when addon can't verify if buffs are already active
- Forms, pets, and rotation abilities still show normally (don't require aura API)
- Updated Interface version to 120000 for WoW 12.0 (Midnight) beta compatibility
- **Code simplification pass**: Removed duplicate logic in RedundancyFilter module
- Removed duplicate cooldown check (was checked twice in same function)
- Consolidated duplicate secret detection checks into single unified block
- Improved code maintainability without affecting functionality

### Fixed

- **WoW 12.0 raid buff filtering**: Hide Mark of the Wild and other raid buffs when aura API blocked
- Added hardcoded list of common raid buffs (Mark of the Wild, Power Word: Fortitude, Battle Shout, Arcane Intellect)
- These buffs now properly filtered when secrets prevent checking if already active
- Prevents queue clutter from suggesting buffs that may already be active
- **WoW 12.0 compatibility**: Fix Settings.OpenToCategory error when opening options panel
- 12.0 path: Use AceConfigDialog:Open() directly (Settings API changed signature)
- Pre-12.0 path: Keep Settings.OpenToCategory() with string parameter
- Fixes error: "bad argument #1 to 'OpenSettingsPanel' (outside of expected range)"
- Fixed nil reference crash in defensive proc glow animation when switching between proc and non-proc states
- Removed references to deleted ProcStartFlipbook and ProcStartAnim frame elements (cleaned up after earlier animation refactor)
- Added defensive null checks for Flipbook.Anim frame transitions

## [3.0] - 2025-12-08

### Added

- Feature Availability system to detect 12.0+ "secret" values (health/aura/cooldown/proc APIs) and gracefully degrade features when blocked
- Manual blacklist and hotkey override inputs in the Options panel for easier configuration

### Changed

- UI visual improvements: brighter marching ants glow, enhanced keypress flash (stacked ADD layers and slightly larger), and hotkeys always render on top
- GCD swipe removes gold edge (now only used for full ability cooldowns)

### Fixed

- Fix: activation flash appearing on the wrong slot when spells move in the queue

## [2.98] - 2025-12-07

### Added

- Important procs now display before regular procs in the queue
- `/jac lps <spellID>` debug command to view spell classification info

### Changed

- Activation flash is now brighter and lasts longer for better visibility
- Improved hotkey detection when spells change rapidly
- Removed stabilization window setting (no longer needed)

### Fixed

- Slot 1 now stays stable when holding modifier keys (requires Single-Button Assistant placed on any action bar)

## [2.97] - 2025-12-07

### Added

- Brazilian Portuguese (ptBR) translation - 127 strings
- Total coverage increased to ~40-42% of non-English player base

## [2.96] - 2025-12-07

### Added

- Full localization support via AceLocale-3.0
- German (deDE) translation - 127 strings
- French (frFR) translation - 127 strings
- Russian (ruRU) translation - 127 strings
- Spanish-Spain (esES) translation - 127 strings
- Spanish-Mexico (esMX) translation - 127 strings
- Total coverage: ~32% of non-English Western WoW retail player base

### Changed

- All UI strings in Options panel now use localization keys
- Improved terminology consistency (e.g., German now uses "Cooldown" consistently)
- Spell examples use localized names (e.g., "Fel Blade" → "Teufelsklinge" in German)

## [2.95] - 2025-12-07

### License Update

- License updated from MIT to GPL-3.0-or-later for LibPlayerSpells-1.0 compatibility
- Added SPDX license identifiers to all source files
- Updated README.md with GPL v3 license information
