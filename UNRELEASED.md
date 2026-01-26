# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.12

### Changes Since 3.12

#### Features
- **Health Bar Display**: Optional compact health bar (5px tall) above main queue
  - Uses `StatusBar:SetValue()` which accepts WoW 12.0 secret values directly
  - Green → Yellow → Red gradient based on health percentage (when not secret)
  - No numeric percentage display (avoids secret arithmetic restrictions)
  - Enable via Defensive Queue settings: "Show Health Bar"
  - Positioned between defensive icon (when ABOVE) and main queue for compact layout

#### Technical
- `UIHealthBar.lua` completely rewritten to use StatusBar widget approach
- `UIManager` v29: Added health bar management functions
- `UIFrameFactory` v3: Defensive icon accounts for health bar height when positioned ABOVE
- Health bar updates on `UNIT_HEALTH` event with 0.1s throttle

---

**Instructions:**
- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction
