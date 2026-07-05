-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- UIPrecombatOverlay.lua - Out-of-combat click overlay for the defensive queue. A pool of
-- invisible SecureActionButtonTemplate buttons is laid over every shown defensive-queue icon
-- (defensive/utility suggestions plus the inserted pre-combat buffs) so they can be clicked to
-- cast/use the ability out of combat. The DPS rotation is keybind-only and never covered.
--
-- The display icons stay insecure - the queues rebuild and show/hide them every frame, which
-- a secure (protected) frame can't do in combat - so only these transparent layers are
-- secure. They live in an insecure container hidden in combat by RegisterStateDriver([combat]
-- hide), and are only ever (re)configured out of combat.
--
-- Interaction: left-click casts via the button-1-suffixed secure attribute ("type1"), so
-- only left-click fires the action; the layer forwards hover (the icon's rich tooltip) and
-- right-click (the icon's hotkey-override handler, which enforces panel lock) to the icon
-- beneath, and shows an action-bar-style highlight on hover. It yields entirely in
-- click-through mode (clicks still pass to the game world) and when click-to-cast is
-- disabled. Out of combat the panel's own icons aren't draggable (the grab tab moves the
-- frame), so the overlay has nothing else to forward.

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
        -- Right-click resolves no secure action ("type1" is left-click only); forward it to
        -- the icon's OnClick (hotkey override - it enforces panel lock itself) on release,
        -- matching the icons' own RightButtonUp registration.
        b:SetScript("PostClick", function(self, mouseButton, down)
            if mouseButton == "RightButton" and not down then
                local f = self.icon and self.icon:GetScript("OnClick")
                if f then f(self.icon, mouseButton) end
            end
        end)
        -- Faint centered "click" hint, shown only over inserted pre-combat buff icons (which
        -- only exist OOC anyway). FontStrings don't intercept mouse, so clicks still land.
        local hint = b:CreateFontString(nil, "OVERLAY")
        hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        hint:SetTextColor(1, 1, 1, 0.55)
        hint:SetPoint("CENTER")
        hint:SetText("click")
        hint:Hide()
        b.clickHint = hint
        b:Hide()
        layers[i] = b
    end
    return true
end

-- Point a layer at an icon (out of combat only) using the secure item/spell attributes by
-- ID - the proven path. The action type is bound to "type1" so only left-click resolves a
-- secure action (a left-click-only macro turned out not to activate reliably); right-click
-- falls through to the PostClick forwarder above. The data attributes stay unsuffixed -
-- secure lookup falls back from "spell1"/"item1" to "spell"/"item".
local function ConfigureLayer(layer, icon, eating)
    layer.icon = icon
    local SDB = LibStub("JustAC-SpellDB", true)
    local recupName
    if icon.spellID and SDB and icon.spellID == SDB.RECUPERATE and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(icon.spellID)
        recupName = info and info.name
    end
    if icon.isItem and icon.itemID then
        layer:SetAttribute("type1", "item")
        layer:SetAttribute("item", "item:" .. icon.itemID)
    elseif recupName then
        -- Recuperate: a damage tick interrupts the heal-over-time while the 30s
        -- "active" aura (and its animation) keeps running, and the stale aura
        -- blocks a plain re-cast. Chain cancel + re-cast into the one click.
        -- (Fallback if macro chaining ever regresses on these layers: WoW counts
        -- click-DOWN and click-UP as two distinct hardware events, each allowed
        -- its own secure action - RegisterForClicks("AnyDown","AnyUp") with
        -- type1="cancelaura" on the press and typerelease1="spell" on the
        -- release performs both from a single click. See
        -- Documentation/CLICK_HARDWARE_EVENTS.md.)
        layer:SetAttribute("type1", "macro")
        layer:SetAttribute("macrotext", "/cancelaura " .. recupName .. "\n/cast " .. recupName)
    elseif icon.spellID then
        layer:SetAttribute("type1", "spell")
        layer:SetAttribute("spell", icon.spellID)
    else
        return false
    end
    -- Absolute placement, never SetAllPoints(icon): anchoring a secure button to the icon
    -- makes the icon - and everything its rect depends on, up through the main frame -
    -- geometry-protected in combat. Anchor dependencies aren't suspended even while the
    -- layer is hidden, so insecure SetPoint/SetSize/Show on those frames mid-fight get
    -- blocked ("Interface action failed"). Copy the icon's rect into UIParent-relative
    -- coordinates instead (scale-corrected); the icons stay insecure, as the module
    -- header promises. Positions re-sync through the existing OOC refresh paths - this
    -- function only ever runs out of combat.
    local left, bottom, width, height = icon:GetRect()
    if not left or not width or width == 0 then return false end
    local s = icon:GetEffectiveScale() / layer:GetEffectiveScale()
    layer:ClearAllPoints()
    layer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
    layer:SetSize(width * s, height * s)
    -- Match the icon's strata and stay below its hotkey frame so keybind text remains visible.
    layer:SetFrameStrata(icon:GetFrameStrata())
    layer:SetFrameLevel(icon:GetFrameLevel() + 1)
    if layer.clickHint then
        -- Mid-food-channel, clicking anything breaks the eat, so the hint says "wait".
        if icon.isPrecombatBuff == true then
            layer.clickHint:SetText(eating and "wait" or "click")
            layer.clickHint:Show()
        else
            layer.clickHint:Hide()
        end
    end
    layer:Show()
    return true
end

--- Lay click layers over every shown defensive-queue icon out of combat (the DPS rotation is
--- keybind-only). Yields in click-through mode and when click-to-cast is disabled.
function PrecombatOverlay.OverlayClickLayers(addon)
    addon = addon or ownerAddon
    if not addon or InCombatLockdown() then return end
    if not EnsurePool() then return end

    local p = addon.GetProfile and addon:GetProfile()
    local enabled = p and p.clickToCastOOC ~= false
    local clickThrough = p and p.panelInteraction == "clickthrough"
    local placed = 0
    if enabled and not clickThrough then
        local SDB = LibStub("JustAC-SpellDB", true)
        local eating = SDB and SDB.GetActiveEatingAura and SDB.GetActiveEatingAura() ~= nil
        local function cover(icons)
            if not icons then return end
            for i = 1, #icons do
                local icon = icons[i]
                if placed < POOL_SIZE and icon and icon:IsShown()
                    and (icon.spellID or (icon.isItem and icon.itemID)) then
                    if ConfigureLayer(layers[placed + 1], icon, eating) then placed = placed + 1 end
                end
            end
        end
        -- Defensive queue only: it holds the inserted pre-combat buffs and utility/defensive
        -- suggestions. The DPS rotation is keybind-driven and never click-to-cast.
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
