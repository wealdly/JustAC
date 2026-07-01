-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- UIPrecombatOverlay.lua - Out-of-combat click overlay for the whole panel. A pool of
-- invisible SecureActionButtonTemplate buttons is laid over every shown queue icon (main
-- rotation + defensive, including the inserted pre-combat buffs) so they can be clicked to
-- cast/use the ability out of combat.
--
-- The display icons stay insecure - the queues rebuild and show/hide them every frame, which
-- a secure (protected) frame can't do in combat - so only these transparent layers are
-- secure. They live in an insecure container hidden in combat by RegisterStateDriver([combat]
-- hide), and are only ever (re)configured out of combat.
--
-- Interaction: left-click casts via a "[button:1]" macro (so ONLY left-click fires the
-- action); the layer forwards hover (the icon's rich tooltip) and right-click (the icon's
-- hotkey-override handler) to the icon beneath, and shows an action-bar-style highlight on
-- hover. It yields entirely in click-through mode (clicks still pass to the game world) and
-- when click-to-cast is disabled. Out of combat the panel's own icons aren't draggable
-- (the grab tab moves the frame), so the overlay has nothing else to forward.

local PrecombatOverlay = LibStub:NewLibrary("JustAC-PrecombatOverlay", 1)
if not PrecombatOverlay then return end

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local POOL_SIZE = 16   -- main queue (<=7) + defensive (<=7) + headroom
local container
local layers = {}
local eventFrame
local updateScheduled = false
local ownerAddon

local function EnsurePool()
    if container then return true end
    if InCombatLockdown() then return false end
    container = CreateFrame("Frame", "JustACClickOverlay", UIParent)
    -- Secure environment hides every layer in combat - taint-free; the display icons revert.
    RegisterStateDriver(container, "visibility", "[combat] hide; show")
    for i = 1, POOL_SIZE do
        local b = CreateFrame("Button", "JustACClickLayer" .. i, container,
            "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyDown", "AnyUp")  -- fire regardless of key-down/up cast CVar
        b:SetFrameStrata("HIGH")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        -- Forward hover to the icon below so its rich tooltip still shows through the layer.
        b:SetScript("OnEnter", function(self)
            local f = self.icon and self.icon:GetScript("OnEnter")
            if f then f(self.icon) end
        end)
        b:SetScript("OnLeave", function(self)
            local f = self.icon and self.icon:GetScript("OnLeave")
            if f then f(self.icon) end
        end)
        b:Hide()
        layers[i] = b
    end
    return true
end

-- Point a layer at an icon (out of combat only) using the secure item/spell attributes by
-- ID - the proven path. Both mouse buttons fire it (a left-click-only macro turned out not
-- to activate reliably); right-click hotkey-override yields to the click while the overlay
-- is up, which only matters in unlocked mode.
local function ConfigureLayer(layer, icon)
    layer.icon = icon
    if icon.isItem and icon.itemID then
        layer:SetAttribute("type", "item")
        layer:SetAttribute("item", "item:" .. icon.itemID)
    elseif icon.spellID then
        layer:SetAttribute("type", "spell")
        layer:SetAttribute("spell", icon.spellID)
    else
        return false
    end
    layer:ClearAllPoints()
    layer:SetAllPoints(icon)
    layer:SetFrameLevel(icon:GetFrameLevel() + 10)
    layer:Show()
    return true
end

--- Lay click layers over every shown queue icon (main + defensive) out of combat. Yields in
--- click-through mode and when click-to-cast is disabled.
function PrecombatOverlay.OverlayClickLayers(addon)
    addon = addon or ownerAddon
    if not addon or InCombatLockdown() then return end
    if not EnsurePool() then return end

    local p = addon.GetProfile and addon:GetProfile()
    local enabled = p and p.clickToCastOOC ~= false
    local clickThrough = p and p.panelInteraction == "clickthrough"
    local placed = 0
    if enabled and not clickThrough then
        local function cover(icons)
            if not icons then return end
            for i = 1, #icons do
                local icon = icons[i]
                if placed < POOL_SIZE and icon and icon:IsShown()
                    and (icon.spellID or (icon.isItem and icon.itemID)) then
                    if ConfigureLayer(layers[placed + 1], icon) then placed = placed + 1 end
                end
            end
        end
        cover(addon.spellIcons)
        cover(addon.defensiveIcons)
    end
    for i = placed + 1, POOL_SIZE do layers[i]:Hide(); layers[i].icon = nil end
end

local function ScheduleUpdate()
    if updateScheduled then return end
    updateScheduled = true
    C_Timer.After(0.1, function()
        updateScheduled = false
        PrecombatOverlay.OverlayClickLayers()
    end)
end

--- Called after the queues render, and on combat-end / login.
function PrecombatOverlay.Refresh()
    ScheduleUpdate()
end

function PrecombatOverlay.Init(addon)
    ownerAddon = addon
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", ScheduleUpdate)
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    EnsurePool()
    PrecombatOverlay.OverlayClickLayers(addon)
end
