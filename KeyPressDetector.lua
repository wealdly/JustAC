-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: KeyPressDetector - Flash feedback when a key/mouse press, or a completed cast,
-- matches a visible icon.
--
-- Two signals, one rule: an icon that is SHOWN and shows the pressed key (or the spell
-- just cast) flashes. Both walk the factory's icon registry, so every icon on every
-- surface - queue, defensives, interrupt, Sustain slot, overlay - is covered by
-- construction; nothing here names a surface.
--   * key press  - immediate, catches presses that don't cast (wrong target, on cooldown)
--   * cast done  - covers what no key hook sees: macros, click-casting, mouse buttons 1-2
-- An icon hidden by alpha (defensives at 0, an engine-hidden kick) still counts as shown:
-- its Flash inherits the alpha and draws nothing, and that alpha may be a secret the
-- addon must never compare, so IsShown() is the only visibility read here.
local KPD = LibStub:NewLibrary("JustAC-KeyPressDetector", 3)
if not KPD then return end

local UIAnimations   = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local BlizzardAPI    = LibStub("JustAC-BlizzardAPI", true)
local StartFlash     = UIAnimations and UIAnimations.StartFlash

-- Hot path cache
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local IsMouseButtonDown = IsMouseButtonDown
local wipe = wipe
local GetTime = GetTime
local ipairs = ipairs
local pairs = pairs
local string_sub = string.sub
local string_match = string.match
local issecretvalue = issecretvalue

-- Pooled table for key press flash matching (avoids GC pressure on every key press)
local iconsToFlash = {}

-- Grace period: accept previous hotkey briefly after spell changes
-- (user pressed key for the spell that just got cast, slot shifted)
local HOTKEY_GRACE_PERIOD = 0.20

-- Mouse button polling: detect down-transitions for flash matching.
-- OnKeyDown doesn't fire for mouse buttons, so we poll IsMouseButtonDown each frame.
-- Buttons 1-2 (left/right) are excluded: they fire constantly and are almost never
-- bound to combat spells. Buttons 3-5 cover middle-click and side buttons.
-- Gaming mice with extra buttons (6+) typically remap them to keyboard keys in driver
-- software, so WoW sees them as regular keyboard input handled by OnKeyDown.
local MOUSE_BUTTONS = {
    { api = "MiddleButton", binding = "BUTTON3" },
    { api = "Button4",      binding = "BUTTON4" },
    { api = "Button5",      binding = "BUTTON5" },
}
local prevMouseDown = {}

local function IsAnyModifierDown()
    return IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
end

local function HotkeyMatches(boundHotkey, pressedHotkey, hasAnyModifier)
    if not boundHotkey or not pressedHotkey then return false end
    if boundHotkey == pressedHotkey then return true end

    -- "+X" binds normalize to MOD-X (any modifier + key).
    -- Match when a modifier is held and the key portion matches.
    if hasAnyModifier and string_sub(boundHotkey, 1, 4) == "MOD-" then
        local pressedBase = string_match(pressedHotkey, "^[A-Z%-]+%-(.+)$")
        return pressedBase and string_sub(boundHotkey, 5) == pressedBase
    end

    return false
end

local function FlashEnabled(addon)
    local profile = addon and addon.db and addon.db.profile
    return StartFlash and UIFrameFactory and UIFrameFactory.icons
        and not (profile and profile.showFlash == false)
end

--- Flash one icon and stamp the press time slot-1 renderers hold their display on.
local function Flash(icon, now)
    StartFlash(icon)
    icon.lastPressTime = now
end

--- Flash every shown icon whose key matches the press.
local function MatchAndFlash(addon, normalizedKey, hasAnyModifier)
    if not FlashEnabled(addon) then return end
    wipe(iconsToFlash)
    local now = GetTime()
    -- A spell that just left a slot: the player pressed for the slot they were looking
    -- at, so that slot flashes on its PREVIOUS key (grace window) and the slot the spell
    -- moved into stays quiet.
    local gracedSpellID
    for icon in pairs(UIFrameFactory.icons) do
        if icon:IsShown() then
            local matched = HotkeyMatches(icon.normalizedHotkey, normalizedKey, hasAnyModifier)
            if not matched and icon.previousSpellID and icon.spellChangeTime
               and (now - icon.spellChangeTime) < HOTKEY_GRACE_PERIOD
               and HotkeyMatches(icon.previousNormalizedHotkey, normalizedKey, hasAnyModifier) then
                matched = true
                gracedSpellID = icon.previousSpellID
                icon._flashGraced = true
            end
            if matched then iconsToFlash[#iconsToFlash + 1] = icon end
        end
    end
    for _, icon in ipairs(iconsToFlash) do
        if not (gracedSpellID and icon.spellID == gracedSpellID and not icon._flashGraced) then
            Flash(icon, now)
        end
        icon._flashGraced = nil
    end
end

--- Flash every shown icon that displays the spell the player just cast (any input
--- route). Called from the player's UNIT_SPELLCAST_SUCCEEDED.
function KPD.FlashSpell(addon, spellID)
    if not spellID or (issecretvalue and issecretvalue(spellID)) then return end
    if not FlashEnabled(addon) then return end
    local display = BlizzardAPI and BlizzardAPI.GetDisplaySpellID
        and BlizzardAPI.GetDisplaySpellID(spellID) or spellID
    local now = GetTime()
    for icon in pairs(UIFrameFactory.icons) do
        if icon:IsShown() then
            -- Items: the cast event carries the item's use spell. Spells: either form.
            local id = icon.spellID or (not icon.isItem and icon.currentID) or nil
            local hit = icon.itemCastSpellID == spellID
            if not hit and id and id > 0 then
                hit = id == spellID or id == display
                    or (BlizzardAPI and BlizzardAPI.GetDisplaySpellID
                        and BlizzardAPI.GetDisplaySpellID(id) == spellID)
            end
            if hit then Flash(icon, now) end
        end
    end
end

-------------------------------------------------------------------------------
-- Build modifier key prefix from current keyboard state
-------------------------------------------------------------------------------
local function BuildModifierPrefix()
    local shift = IsShiftKeyDown()
    local ctrl = IsControlKeyDown()
    local alt = IsAltKeyDown()

    if ctrl and shift then
        return "CTRL-SHIFT-"
    elseif shift and alt then
        return "SHIFT-ALT-"
    elseif ctrl and alt then
        return "CTRL-ALT-"
    elseif shift then
        return "SHIFT-"
    elseif ctrl then
        return "CTRL-"
    elseif alt then
        return "ALT-"
    end
    return ""
end

-------------------------------------------------------------------------------
-- Create the key press detector frame
-------------------------------------------------------------------------------
function KPD.Create(addon)
    if addon.keyPressFrame then return end

    local frame = CreateFrame("Frame", "JustACKeyPressFrame", UIParent)
    addon.keyPressFrame = frame
    -- SetPropagateKeyboardInput is PROTECTED in combat (9.1.5+); the keyboard hook
    -- arms together with it further down - see ArmKeyboardHook.

    ---------------------------------------------------------------------------
    -- Keyboard detection (global via SetPropagateKeyboardInput)
    ---------------------------------------------------------------------------
    -- Propagation and the key hook arm TOGETHER: SetPropagateKeyboardInput is a
    -- protected call in combat (9.1.5+), and a /reload mid-fight re-runs OnEnable
    -- under lockdown. Arming the hook without propagation would swallow every
    -- keypress, so under lockdown both wait for combat exit (mouse-button flash
    -- via the OnUpdate poll below works throughout).
    local function ArmKeyboardHook()
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(_, key)
            -- Skip pure modifier keys early
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
                return
            end

            MatchAndFlash(addon, BuildModifierPrefix() .. key:upper(), IsAnyModifierDown())
        end)
    end
    if InCombatLockdown() then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", nil)
            ArmKeyboardHook()
        end)
    else
        ArmKeyboardHook()
    end

    ---------------------------------------------------------------------------
    -- Mouse button detection (poll IsMouseButtonDown for down-transitions)
    -- OnKeyDown never fires for mouse buttons, so we detect state transitions
    -- each frame. Throttled to ~30Hz - max 33ms detection latency, which is
    -- imperceptible for flash feedback (human reaction time ~150-300ms).
    ---------------------------------------------------------------------------
    local mouseUpdateAccum = 0
    local MOUSE_POLL_INTERVAL = 0.033  -- ~30Hz
    frame:SetScript("OnUpdate", function(_, elapsed)
        mouseUpdateAccum = mouseUpdateAccum + elapsed
        if mouseUpdateAccum < MOUSE_POLL_INTERVAL then return end
        mouseUpdateAccum = 0

        for i, btn in ipairs(MOUSE_BUTTONS) do
            local down = IsMouseButtonDown(btn.api)
            if down and not prevMouseDown[i] then
                MatchAndFlash(addon, BuildModifierPrefix() .. btn.binding, IsAnyModifierDown())
            end
            prevMouseDown[i] = down
        end
    end)
end
