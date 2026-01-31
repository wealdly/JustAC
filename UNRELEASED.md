# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.198

**Instructions:**
- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

## Performance Improvements
- **UIRenderer:** Optimized rendering loop when auto-hide features are active
  - Skips expensive rendering operations (hotkey lookups, icon updates, glow animations) when frame is hidden
  - Still processes queue building and cache updates to ensure instant response when frame becomes visible
  - Maintains warm caches for redundancy filter, aura tracking, and spell info
  - Applies to: hideQueueOutOfCombat, hideQueueForHealers, hideQueueWhenMounted, requireHostileTarget

## UI Improvements
- **Options:** "Require Hostile Target" checkbox is now disabled when "Hide Out of Combat" is enabled
  - These options are redundant together since hideQueueOutOfCombat hides the frame before the hostile target check runs
  - Description updated to explain the relationship

## Bug Fixes
- **UIRenderer:** Fixed large highlight frame bug appearing over backup abilities when "Hide icons while mounted" or other auto-hide features are enabled
  - Now properly stops all glow animations (assisted, proc, defensive) when frame should be hidden
  - Prevents highlight frames from scaling incorrectly during auto-hide transitions
  - Skips icon updates entirely when `shouldShowFrame = false` to avoid frame state inconsistencies
