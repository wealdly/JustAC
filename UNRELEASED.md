## [Unreleased]

### Improved
- The priority list is now a proper list: one line per ability, showing what each one waits for, with a fixed top row making it clear that the first slot belongs to the game. Tabs switch between the game's own order, the theorycraft order and your own, and picking a tab switches the queue to it, so editing your list changes what you see straight away.
- Your own list starts from one of the others. Export copies the order you are looking at, and once you have a list, Merge adds anything that order has and yours does not, leaving your own order alone.
- Rows are dragged into the order you want, and an ability's settings open under that ability rather than below the whole table, with an undo for the last ten changes.
- One setting decides who leads the queue: the game, which is the default, or the queue filling the gaps where the game has nothing to recommend, or your own list replacing the pick. The two that are not the game are marked as such.
- Every row says how far the other order would move that ability, the same number whichever tab you read it from, and the tooltip says when the ability is used, including which cooldown it waits for.
- More of the queue is timed by the addon rather than handed back to the game. Abilities that wait for a cooldown, and abilities whose conditions have an "or" in them, are now understood instead of being given up on.
- The theorycraft priorities are freshly imported, and three specs picked up tuning changes.
- Poisons, weapon imbues and similar upkeep abilities are kept out of the queue and out of priority lists. They stalled the queue, because the game offers them one at a time and waits for each; the pre-combat reminder offers them instead.
- Clearer wording: "Include Hidden" says what it does (abilities with no visible button, whether behind a macro or off your bars), and the burst-ready cue now sits with the burst triggers it belongs to.

### Fixed
- An ability a talent has turned passive no longer appears in the queue.
- Area abilities no longer show up on a single target. Some rotations describe the
  enemy count in a way the theorycraft priorities were not reading, so a few specs were
  offered their multi-target abilities in a duel. Those same specs now get a proper
  multi-target order as well.
- Cooldowns held back for enemy waves that only ever happen in a raid simulation are no longer held back in your fights. Three abilities had lost their ordering to this.
- An ability's settings no longer appear twice, and the confirmation for clearing a list opens in front of the panel instead of behind it.
