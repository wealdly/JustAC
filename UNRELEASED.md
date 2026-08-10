## [Unreleased]

### Added
- New Ability Overrides tab: search any spell or item and manage everything about it in one card - visibility (formerly the Blacklist tab), pins, item aura-linking, priority-list membership, and its hotkey label - plus a "Your Customizations" list of every ability you've changed. The Blacklist and Hotkeys tabs are retired; their settings and your existing entries all live on the card
- Healer specs are now enabled by default: the queue suggests your damage rotation - the same one Blizzard's Assisted Combat drives - for soloing, delves, and dungeon downtime, with healing spells kept out of the suggestion slots. Characters where a healer spec was previously auto-disabled keep that choice; a one-time hint points at the new `/jac enable` command to switch it on
- New Caster Filler toggle (DPS Queue tab, healer specs): suppresses melee-weave suggestions - melee abilities and form shifts - for healers who stay at range. When Blizzard's own pick is a melee ability, the queue steps to its next-best suggestion instead
- Filled healing-spell classification gaps across all healer classes (Chain Heal, Earth Shield, Penance-family applicators, Echo, Beacon of Faith, Nourish, and more), so heals no longer slip into damage-queue positions; spells that heal or damage depending on the target (Living Flame, Divine Toll, Convoke the Spirits, Chi Burst) are deliberately left to Assisted Combat's judgment
- Paladin Auras join the pre-combat suggestions: with no Aura active, one is offered (Devotion by default) - like a rogue's poisons or a shaman's shield

### Fixed
- Fixed a crash in the Burst-Ready Cue that froze the entire queue for the whole fight on any spec with no hidden abilities - with the cue now on by default this would have hit everyone, and it explains the queue "sticking" mid-combat for players who had the cue enabled
- Pre-combat poison and shield suggestions now follow Assisted Combat's own picks, in the order it asks for them - so its recommendation can no longer get stuck asking for one poison while you carry another
- The nameplate overlay now reliably moves Blizzard's crowd-control and loss-of-control displays clear of its icons - including in combat and with Reverse Anchor + health bars, where it previously never worked - and a blocked attempt (arena) can no longer leave the elite badge or raid marker misplaced on other nameplates
- Overlay health/resource bars, the enrage cue, and the mitigation slot line up correctly at any Defensive Icon Scale; the mitigation slot no longer draws through the bars in horizontal growth; the pet bar appears and disappears promptly with the pet
- Gap closers no longer double up: after one fires, the suggestion stands down for a few seconds while you travel instead of immediately offering the next one
- Gap closers are no longer suggested when the target is only barely out of melee reach - walk the last couple of steps and keep the cooldown for a real gap. A new "Only Suggest For Real Gaps" toggle turns this off; when the distance can't be determined the suggestion appears either way
- Attaching the queue to the target frame stands down while another addon keeps that frame hidden - no more docking to an invisible frame - and re-attaches on its own when the frame comes back
- Dragging now picks the frame up the instant you press - grab tab and Alt-drag alike. The frame no longer starts moving a beat late and then follows beside the cursor; it stays exactly where you grabbed it. A docked frame no longer jumps across the screen when a drag begins, and a press without movement can't nudge or undock anything
- The pre-combat "click" hint now moves with the frame while you drag it
- More placement fixes: power bars return after leaving disabled-for-this-spec mode; bars keep their configured side when the defensive cluster empties; the detached defensive cluster no longer shifts slightly on reload; the soothe cue's aura icon follows the overlay's growth direction; toggling Maintenance Slot or CC Break re-lays the interrupt display immediately; the dangerous-cast warning clears attached defensive icons; Alt-dragging a docked panel undocks it like the grab tab; a queue attached to the target frame leaves room for the pet and resource bars; no more keypress-detector error after a mid-combat reload
- The Disruption slot now respects range: a melee kick or crowd-control ability is no longer suggested as if usable from across the room - a reachable alternative is preferred, and only when nothing can reach the target does the icon show your interrupt dimmed as a reminder. Area abilities centered on you (Incapacitating Roar, Leg Sweep) are stricter: they only appear when the target is confirmed inside their radius, because pressing one out of reach fires anyway and wastes the cooldown
- Custom hotkey labels on items now survive a reload
- A party or raid member changing their talents no longer resets cooldown tracking mid-fight
- The General tab's Reset to Defaults no longer switches your displays on or off - the display enables belong to the Display tab and stay put
- The Defensive Queue tab has its own Reset to Defaults button covering all its sub-tabs (its settings previously had no reset of their own)
- A nameplate-only setup no longer inherits the Main Queue's visibility conditions: with the main queue disabled, its "In Combat Only" and mounted-hide settings can't invisibly blank the overlay anymore

### Changed
- Substantially lower CPU and memory use in combat: defensive abilities are evaluated once per update instead of up to four times, spell-cast event bursts no longer trigger extra rebuilds, cooldown data refreshes on one shared cadence, and an item defensive without an action-bar keybind no longer rescans the bars continuously
- The options are reorganized around what they hold: one Display tab carries both surfaces (Main Queue / Nameplate Queue) plus the Shared Behavior they follow; DPS Queue and Defensive Queue hold the two suggestion queues; Ability Overrides sits after them; General keeps the Disruption slot, input, and Blizzard UI integration
- Queue ordering is now a single preset - Smart (the default), Match Blizzard's pick, or Fixed source order - with a Customize expander for mixed setups; existing ordering choices are unchanged
- The Display Mode dropdown is gone: each display is enabled with a checkbox at the top of its own page - same choices, asked where you'd look for them
- One shared Highlight Mode lives under Display → Shared Behavior; the defensive and overlay panels follow it by default and can still override it ("Use Shared Setting" is the new default there). Existing glow choices are preserved
- The two grey-out toggles (casting / channeling) are now one "Grey Out While Casting" toggle, and the usability and range tints are one "State Tint" toggle - if you had either half of a pair off, the merged toggle stays off
- Options now grey out controls that can't currently take effect - for example the interrupt alert sound while the Disruption slot is off, or Click to Cast while the panel is click-through
- Options cleanup: the Defensive Queue tab is organized into three sub-tabs (General, Pre-Combat Buffs, Priority Lists); the dangerous-cast warning moved next to the other Disruption settings; the gamepad icon style only shows when gamepad input is in use; the target-frame docking option is now called "Attach To" and sits with the layout controls it constrains; the options window opens a little wider by default
- Nameplate icon labels now clearly share their visibility, color, and position with the main queue (they always did); only the font scales are set separately
- Gap-closer suggestions are now on by default (per-spec defaults; toggle under DPS Queue → Gap-Closers)
- The Burst-Ready Cue (purple glow on your spec's major cooldown when a burst window is called for) is now on by default
- Defensive icons on cooldown use the same grey tint as the rest of the queue
- The nameplate queue's Visibility dropdown drops "Require Hostile Target" - the overlay only ever appears on an attackable target's nameplate, so it was identical to "Always"
- The interrupt alert's separate Test button is gone - the sound picker's speaker icons play the same preview
