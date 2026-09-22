## [Unreleased]

### Improved
- The priority list is now a proper list: one line per ability, showing what each one waits for, with a fixed top row making it clear that the first slot belongs to the game. Tabs switch between the game's own order, the theorycraft order and your own, so you can compare them before choosing, and a list starts as a copy of whichever you are looking at.
- Poisons, weapon imbues and similar upkeep abilities are kept out of the queue and out of priority lists. They stalled the queue, because the game offers them one at a time and waits for each; the pre-combat reminder offers them instead.
- Clearer wording: "Include Hidden" says what it does (abilities with no visible button, whether behind a macro or off your bars), and the burst-ready cue now sits with the burst triggers it belongs to.

### Fixed
- An ability a talent has turned passive no longer appears in the queue.
- Area abilities no longer show up on a single target. Some rotations describe the
  enemy count in a way the theorycraft priorities were not reading, so a few specs were
  offered their multi-target abilities in a duel. Those same specs now get a proper
  multi-target order as well.
