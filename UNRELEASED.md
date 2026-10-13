## [Unreleased]

### Forever DPS queue

- Discover learned damage abilities from the spellbook, including spells only in macros or without action-bar buttons. Supplemental abilities exclude protection, healing, utility, crowd control, taunts, movement/stealth and interrupts with cooldowns over 8 seconds. Damage/healing hybrids, damaging slows or roots, Earth Shock and ranged weapon fillers remain eligible. Imported rotation entries are preserved; custom entries and Always Show remain available.
- Show WAIT when every DPS ability is waiting for resources, cooldowns, range or other requirements, with waiting abilities behind it. Requires Unavailable Last and ranked ordering; out-of-combat previews without a live attackable target are unchanged.
- Keep Throw and other ranged weapon fillers ahead of unavailable melee attacks while the enemy remains beyond melee reach, including between shots with a cooldown swipe. A ready alternative takes over immediately; WAIT still applies when the filler cannot reach or otherwise cannot be used. Melee autoattack also moves behind usable alternatives when out of range, including out of combat.
- Move rear-required attacks such as Backstab and Shred behind usable alternatives when out of stealth and the enemy is targeting you, including during proc or full-energy promotion. Stealth openers, tank-held targets, Dirty Deeds and detected Shred positional-removal bonuses retain their eligibility; unknown targeting leaves the order unchanged.
- Reduce combo-point overkill on normal enemies for variable-point finishers such as Eviscerate: aim for 3 points, 2 below half health, and any affordable amount when nearly dead. Unknown health keeps the 3-point target; elites and bosses retain the rotation's targets.

### Availability and priorities

- With Unavailable Last enabled, proc and full-resource promotion respect confirmed range limits. Confirmed action-bar cast restrictions also keep unusable abilities behind usable alternatives, including spellbook proc suggestions.
- In ranked ordering with Unavailable Last, abilities waiting for regeneration precede those missing their minimum class-resource cost or explicit point hold. Retail's primary pick and exact source-order mode are unchanged.
- Refresh Forever rotations and honor exact enemy-count conditions, including four-target Blizzard and Volley, Mage point-blank AoE, Paladin multi-target attacks and Protection Warrior's Heroic Strike/Cleave selection. Totem upkeep checks live slot presence; Fire Nova no longer gets unconditional single-target priority from an unreadable fight-duration condition.
- Rogues prioritize eligible Backstab over Sinister Strike and Hemorrhage. Assassination and Subtlety fall back to Backstab and Sinister Strike before talent builders are learned.
- Forever's automatic Shaman ordering prefers usable Lightning Bolt before combat rather than spending Earth Shock's cooldown and mana on the pull. No-target previews also prefer the bolt; a selected target must be in range. Combat priorities, custom lists and Retail are unchanged.

### Defensives and buff tracking

- Offer Stoneskin behind urgent healing when its Earth totem slot is empty, preserving active totems rather than repeatedly recommending replacements.
- Add Templar's Bulwark and Elune's Grace to Forever defensive defaults. Unchanged defaults update automatically; customized lists can adopt them with Restore Class Defaults.
- Recognize active Forever weapon imbues such as Rockbiter instead of repeatedly offering them. Retail weapon-enchant tracking is unchanged.
- Stop interrupt suggestions and alerts for friendly or non-attackable targets. Attackable enemies remain eligible out of combat.

### Settings and hotkeys

- Fix missing hotkeys when a character macro shares a name with an account-wide macro. Macro edits now update hotkeys without a reload.
- Fix an error opening Forever options and restore Cooldown Manager add/remove button availability. Its toggle now reflects the game's actual setting and reports refused changes.
