# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.03

### Changes Since 3.03

#### Internal Architecture (v3.04 prep)

**Module Restructuring:**
- Broke up massive UIManager.lua (2025 lines → 154 lines orchestrator + 3 focused modules):
  - `UIAnimations.lua` (451 lines) - All animation/visual effects (marching ants, proc glow, flash)
  - `UIFrameFactory.lua` (881 lines) - Frame creation and layout (main frame, grab tab, spell icons, defensive icon)
  - `UIRenderer.lua` (962 lines) - Rendering and update logic (RenderSpellQueue, defensive icon show/hide, hotkey dialogs)
  - `UIManager.lua` (154 lines) - Thin orchestrator coordinating submodules + Masque integration
- Improved maintainability: Clear separation of concerns, smaller focused files easier to navigate
- Load order: `SpellQueue → UIAnimations → UIFrameFactory → UIRenderer → UIManager`
- Backward compatible: All existing public APIs preserved as delegation wrappers

**Code Cleanup:**
- Removed dead casting animation references and comments
- Fixed queue icon flash atlas (`UI-HUD-ActionBar-IconFrame-Mouseover` → `UI-HUD-ActionBar-IconFrame-Flash`)
- Fixed queue icon flash frame level (+4 → +6 for proper layering above ants/proc glow)
- Removed 8 excessive comments explaining well-understood Blizzard behavior

#### Added
- **Out-of-range indicator**: Hotkey text turns red when queue spells are out of range
  - Provides immediate visual feedback about positioning/mobility needs
  - Uses Blizzard's standard red (1, 0, 0) coloring on hotkey text
  - Applied to all queue icons
  
#### Changed
- **Resource coloring**: Now uses Blizzard's standard blue tint (0.5, 0.5, 1.0) when not enough mana/resources
  - Previously used full desaturation (grey) which was less informative
  - Blue tint makes it clear the issue is resources, not cooldown or range
  - Still uses desaturation for channeling (to emphasize don't interrupt)
  
- **Flash atlas**: Fixed to use proper `UI-HUD-ActionBar-IconFrame-Flash` instead of mouseover atlas
  - Flash now matches default action bar brightness
  
- **Flash layering**: Flash now above marching ants for better visibility
  - Immediate keypress feedback is now most prominent visual element
  - Layering: Flash (+6) > Proc Glow (+5) > Marching Ants (+4)

#### Fixed  
- **Icon artwork bleeding outside frame**: Icon textures now inset 1px from button edges, use `SetTexCoord(0.07, 0.93, 0.07, 0.93)` to crop edges, and apply `UI-HUD-ActionBar-IconFrame-Mask` MaskTexture to clip corners to the beveled frame shape
- **Syntax errors**: Fixed missing comment markers on lines 524 and 966
- **Avoid Lua errors when API returns secret values**: Added `BlizzardAPI.GetSafeSpellCooldown` and secrecy wrappers (`GetSpellCooldownSecrecy`, `GetSpellAuraSecrecy`, `GetSpellCastSecrecy`, `ShouldUnitHealthMaxBeSecret`). Hardened `RedundancyFilter` to skip cooldown filtering when values are secret or inaccessible (fixes crash when `start` is a secret value).
- **Best-effort aura detection in 12.0**: Changed `RefreshAuraCache()` to skip individual secret auras instead of abandoning all remaining auras. Now processes all non-secret auras and checks each field individually for secrets, maximizing detection coverage while avoiding Lua errors.
- **Form redundancy check moved before secret bypass**: Form/stance detection now runs first in `IsSpellRedundant()`, before any aura secret checks. Forms use stance bar APIs (always safe), so Cat Form etc. are now properly filtered even when aura secrets are active.
- **Raid buffs now filtered when active**: Added Mark of the Wild, Fortitude, Battle Shout, Arcane Intellect, and Blessing of the Bronze to `UNIQUE_AURA_SPELLS` table. These buffs are now properly hidden from the queue when already active on the player.
- **Usability filtering for queue positions 2+**: Added `IsSpellUsable()` check to filter out spells that are on cooldown (>2s remaining) or lack resources. Spells coming off cooldown soon (≤2s) still shown for preparation.

#### Code Cleanup
- **Removed duplicate cooldown filtering**: RedundancyFilter had a 5s cooldown check that duplicated SpellQueue's 2s check. Consolidated to SpellQueue only (stricter threshold).
- **Updated legacy LibPlayerSpells terminology**: Changed debug tags from `[LPS:*]` to descriptive names like `[UNIQUE_AURA]`, `[PERSONAL_AURA]`, etc.
- **Cleaned up dead code**: Removed reference to non-existent `info.flags` in `/jac lps` output. Updated help text to say "spell classification" instead of "LibPlayerSpells".
- **Removed unused functions**: `HasBuffByIcon()`, `HasSameNameBuff()`, `IsRaidBuff()` were defined but never called. Also removed unused `bit_band` and `pairs` hot path caches.
- **Simplified legacy aliases**: `GetLPSInfo()` and `IsLibPlayerSpellsAvailable()` retained for backwards compat but marked as legacy.
- **Consolidated proc detection**: UIRenderer now uses `BlizzardAPI.IsSpellProcced()` instead of direct API calls with duplicated secret value handling. Removes ~10 lines of duplicate code.

- **Form spell ID matching by name and override**: `FormCache.GetFormIDBySpellID()` now tries spell override lookup (`C_Spell.GetOverrideSpell`) and name-based fallback matching when direct spell ID lookup fails. Fixes Cat Form (768) not being filtered when stance bar uses a different spell ID for the same form.
- **Enhanced `/jac formcheck`**: Now shows spell ID → form ID mappings for common form spells and redundancy check results to diagnose form filtering issues.
- **Pet detection hardened for 12.0**: `IsPetAlive()` now checks if `UnitIsDead` result is secret and fails-open (assumes alive). `BlizzardAPI.GetPetHealthPercent()` handles secret UnitIsDead and UnitHealth.
- **Spell usability hardened for 12.0**: `BlizzardAPI.IsSpellUsable()` now checks for secret return values and fails-open (assumes usable) to prevent Lua errors.
- **Added C_Secrets namespace wrappers**: New `ShouldSpellCooldownBeSecret()`, `ShouldSpellAuraBeSecret()`, `ShouldUnitSpellCastBeSecret()` for proactive secrecy testing.

#### 12.0 Defensive Queue Audit
- **Fixed dead Priest spell ID**: Replaced Greater Fade (213602), which was removed in patch 10.0.0, with Desperate Prayer (19236) in CLASS_COOLDOWN_DEFAULTS
- **Reorganized Priest defensives**: Desperate Prayer moved from self-heals to cooldowns (it's a major defensive); Vampiric Embrace added to self-heals for Shadow
- **Added Evoker 12.0 notes**: Documented that Renewing Blaze folds into Obsidian Scales passive in Midnight
- **Verified all spell IDs**: Cross-checked CLASS_COOLDOWN_DEFAULTS and CLASS_SELFHEAL_DEFAULTS against WoW 12.0 Midnight data
- **SpellDB already complete**: Confirmed SpellDB.lua has good Evoker/Augmentation coverage including Spatial Paradox (406732), Time Dilation (357170), Ebon Might (395152), Prescience (409311)

#### Removed
- **LibPlayerSpells-1.0 dependency**: Removed entirely for full 12.0 Midnight compatibility. The library hasn't been updated since Shadowlands (patch 9.x) and is missing all Dragonflight, TWW, and Midnight spells/talents. Replaced with native spell classification:
  - **SpellDB.lua** (new file): Native spell classification database with ~90 spell IDs across 3 categories
  - **DEFENSIVE_SPELLS**: Major defensives per class (Shield Wall, Barkskin, Icebound Fort, etc.)
  - **HEALING_SPELLS**: All healing abilities that shouldn't appear in DPS queue
  - **CROWD_CONTROL_SPELLS**: Stuns, fears, roots, incapacitates, interrupts
  - Fail-open design: Unknown spells assumed offensive (correct for DPS filtering)
  - RedundancyFilter still uses its own native tables for form/buff/pet detection
- BlizzardAPI v19: `IsOffensiveSpell()`, `IsDefensiveSpell()`, `IsCrowdControlSpell()` now use SpellDB
- Deleted `Libs/LibPlayerSpells-1.0/` folder (~17 files, 6000+ lines of outdated spell data)
- Updated README.md and JustAC.toc to remove library references

---

**Instructions:**
- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction
