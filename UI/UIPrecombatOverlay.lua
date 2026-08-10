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

local PrecombatOverlay = LibStub:NewLibrary("JustAC-PrecombatOverlay", 3)
if not PrecombatOverlay then return end

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local POOL_SIZE = 8    -- defensive queue only (<=7) + headroom; the DPS row is keybind-only
local container
local layers = {}
local placedCount = 0   -- layers currently seated over an icon (layers[1..placedCount])
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
            elseif mouseButton == "LeftButton" and not down and self.isWeaponEnchant
                and not self.disarmed then
                -- (disarmed = mid-eat: no secure action fired, so nothing was applied - don't
                -- latch the enchant as in-flight or the suggestion would vanish for nothing.)
                -- The enchant is in flight; the weapon still reads unenchanted for a beat.
                -- Latch it applied now so the suggestion clears before a second click can
                -- spend another stone. See PrecombatEngine.NoteWeaponEnchantApplied.
                local PE = LibStub("JustAC-PrecombatEngine", true)
                if PE and PE.NoteWeaponEnchantApplied then PE.NoteWeaponEnchantApplied() end
                PrecombatOverlay.Refresh()
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

-- Bind the secure action for `icon` onto `layer` (out of combat only) using the item/spell
-- attributes by ID - the proven path. The action type is bound to "type1" so only left-click
-- resolves a secure action (a left-click-only macro turned out not to activate reliably);
-- right-click falls through to the PostClick forwarder above. The data attributes stay
-- unsuffixed - secure lookup falls back from "spell1"/"item1" to "spell"/"item".
--
-- Deliberately touches no geometry. That separation is the whole point: the common case is
-- the queue rotating a new ability into a slot that hasn't moved, and rebinding that needs
-- nothing from the layout - so it can happen on the spot instead of waiting for the deferred
-- pass, leaving no window where the layer is still armed with the previous suggestion.
local function ArmLayer(layer, icon, busy)
    layer.icon = icon
    -- What this layer is armed with, so a later pass can tell when it has gone stale.
    layer.armedID = icon.isItem and icon.itemID or icon.spellID
    layer.isWeaponEnchant = nil  -- pooled: clear before the branches below re-decide
    local SDB = LibStub("JustAC-SpellDB", true)
    local recupName
    if icon.spellID and SDB and icon.spellID == SDB.RECUPERATE and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(icon.spellID)
        recupName = info and info.name
    end
    if icon.isItem and icon.itemID then
        -- Weapon enhancements (oil / whetstone / weightstone) are a two-step use: the item
        -- only ARMS an "apply to which item?" cursor - the enchant lands when a weapon slot
        -- is used while that cursor is held. A plain "item" action performs step one and
        -- leaves the player holding the cursor, hunting for their weapon, so chain both
        -- halves into the one click. "/use 16" is INVSLOT_MAINHAND: the slash parser routes
        -- a bare number to UseInventoryItem, which consumes the armed cursor.
        -- Main hand only, matching the missing-enchant detection in PrecombatEngine (it
        -- reads GetWeaponEnchantInfo's main-hand return and nothing else).
        -- ponytail: off-hand would need the detection side to grow an off-hand check first.
        layer.isWeaponEnchant = SDB and SDB.GetPrecombatBuffCategory
            and SDB.GetPrecombatBuffCategory(icon.itemID) == "weaponEnchant" or nil
        if layer.isWeaponEnchant then
            layer:SetAttribute("type1", "macro")
            layer:SetAttribute("macrotext", "/use item:" .. icon.itemID .. "\n/use 16")
        else
            layer:SetAttribute("type1", "item")
            layer:SetAttribute("item", "item:" .. icon.itemID)
        end
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
    -- Mid-application, ANY click breaks what's in progress - and re-clicking the food itself
    -- restarts the eat, burning a second one and resetting the ~10s wait for Well Fed. The
    -- layer stays visible so the icon (and the "wait" hint below) keeps telling you what
    -- you're waiting on, but no secure action is bound, so the click resolves nothing.
    -- Attributes are only ever set out of combat (this function is OOC-only), so clearing
    -- them is safe.
    layer.disarmed = busy or nil
    if busy then
        layer:SetAttribute("type1", nil)
        layer:SetAttribute("macrotext", nil)
        layer:SetAttribute("item", nil)
        layer:SetAttribute("spell", nil)
    end
    if layer.clickHint then
        -- Mid-application, clicking anything breaks it, so the hint says "wait".
        if icon.isPrecombatBuff == true then
            layer.clickHint:SetText(busy and "wait" or "click")
            -- Anchored to the ICON, not the layer: the layer is absolutely placed
            -- (see SeatLayer) and only re-seated once the layout settles, so while
            -- the frame is being dragged the clickable region lags behind - fine
            -- for an invisible hitbox, wrong for visible text. A FontString is not
            -- a protected object, so unlike anchoring the layer itself this puts
            -- no combat geometry protection on the icon; and it stays the layer's
            -- child, so the [combat] hide driver still removes it instantly.
            layer.clickHint:ClearAllPoints()
            layer.clickHint:SetPoint("CENTER", icon, "CENTER")
            layer.clickHint:Show()
        else
            layer.clickHint:Hide()
        end
    end
    return true
end

-- Place an armed layer over its icon and show it. Unlike arming, this reads the icon's rect,
-- so it needs a settled layout - which is why coverage changes go through the deferred pass
-- rather than happening inline.
--
-- Absolute placement, never SetAllPoints(icon): anchoring a secure button to the icon
-- makes the icon - and everything its rect depends on, up through the main frame -
-- geometry-protected in combat. Anchor dependencies aren't suspended even while the
-- layer is hidden, so insecure SetPoint/SetSize/Show on those frames mid-fight get
-- blocked ("Interface action failed"). Copy the icon's rect into UIParent-relative
-- coordinates instead (scale-corrected); the icons stay insecure, as the module
-- header promises. This function only ever runs out of combat.
local function SeatLayer(layer, icon)
    local left, bottom, width, height = icon:GetRect()
    if not left or not width or width == 0 then return false end
    local s = icon:GetEffectiveScale() / layer:GetEffectiveScale()
    layer:ClearAllPoints()
    layer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
    layer:SetSize(width * s, height * s)
    -- Match the icon's strata and stay below its hotkey frame so keybind text remains visible.
    layer:SetFrameStrata(icon:GetFrameStrata())
    layer:SetFrameLevel(icon:GetFrameLevel() + 1)
    -- Remembered so a later pass can tell "the ability changed" (rebind in place) from
    -- "the slot moved" (needs re-seating, and so needs the layout to settle first). The
    -- scale ratio rides along because a UI-scale change moves the layer without touching
    -- the icon's own rect - the one way the slot can move with these three unchanged.
    layer.seatLeft, layer.seatBottom, layer.seatWidth = left, bottom, width
    layer.seatScale = s
    layer:Show()
    return true
end

local function ConfigureLayer(layer, icon, busy)
    return ArmLayer(layer, icon, busy) and SeatLayer(layer, icon)
end

local function CoverageEnabled(addon)
    local p = addon and addon.GetProfile and addon:GetProfile()
    if p and p.clickToCastOOC == false then return false end
    return not (p and p.panelInteraction == "clickthrough")
end

-- Mid-application (eating, or casting/channelling a poison, imbue, oil): the suggestions stay
-- on screen - you are still out of combat, and the icon is what tells you what you're waiting
-- on - but nothing may be clickable, because ANY click cancels the application. One shared
-- answer with the engine that decides what to suggest, so the two can't disagree.
local function IsBusyApplying()
    local PE = LibStub("JustAC-PrecombatEngine", true)
    return PE and PE.IsBusyApplying and PE.IsBusyApplying() or false
end

--- Which icons a layer may cover. Kept in one place so the full pass and the in-place
--- resync below can never disagree about what should be covered.
local function IsCoverable(icon)
    -- IsVisible (not IsShown): an icon whose parent frame is hidden still reports
    -- IsShown()==true, which would strand a "click" layer floating over empty space.
    -- The alpha-0 hide path clears spellID/isPrecombatBuff, so this only adds the
    -- hidden-ancestor case.
    return icon and icon:IsVisible() and (icon.spellID or (icon.isItem and icon.itemID)) and true or false
end

--- Lay click layers over every shown defensive-queue icon out of combat (the DPS rotation is
--- keybind-only). Yields in click-through mode and when click-to-cast is disabled.
function PrecombatOverlay.OverlayClickLayers(addon)
    addon = addon or ownerAddon
    if not addon or InCombatLockdown() then return end
    if not EnsurePool() then return end

    local placed = 0
    if CoverageEnabled(addon) then
        local busy = IsBusyApplying()
        local function cover(icons)
            if not icons then return end
            for i = 1, #icons do
                local icon = icons[i]
                if placed < POOL_SIZE and IsCoverable(icon) then
                    if ConfigureLayer(layers[placed + 1], icon, busy) then placed = placed + 1 end
                end
            end
        end
        -- Defensive queue only: it holds the inserted pre-combat buffs and utility/defensive
        -- suggestions. The DPS rotation is keybind-driven and never click-to-cast.
        cover(addon.defensiveIcons)
    end
    for i = placed + 1, POOL_SIZE do layers[i]:Hide(); layers[i].icon = nil end
    placedCount = placed
end

local function ScheduleUpdate()
    if updateScheduled then return end
    updateScheduled = true
    C_Timer.After(0.1, function()
        updateScheduled = false
        PrecombatOverlay.OverlayClickLayers()
    end)
end

-- A bound action must never outlive the icon it belongs to: the queue rotates a new ability
-- into a slot, and until the layers catch up a click fires the previous suggestion - a second
-- food, a second weapon stone.
--
-- Almost always the slots themselves haven't moved, only what they offer, and rebinding that
-- needs nothing from the layout - so do it here and now, and the mismatch never exists. That
-- leaves the deferred pass for what actually needs a settled layout: slots appearing,
-- vanishing or moving. Returns true when everything was handled in place.
local function ResyncInPlace(addon)
    if not CoverageEnabled(addon) then return placedCount == 0 end
    local icons = addon.defensiveIcons
    if not icons then return placedCount == 0 end
    local busy = IsBusyApplying()
    local n = 0
    for i = 1, #icons do
        local icon = icons[i]
        if IsCoverable(icon) then
            n = n + 1
            local layer = n <= placedCount and layers[n]
            if not layer or layer.icon ~= icon or not layer:IsShown() then return false end
            local left, bottom, width = icon:GetRect()
            if left ~= layer.seatLeft or bottom ~= layer.seatBottom or width ~= layer.seatWidth
                or icon:GetEffectiveScale() / layer:GetEffectiveScale() ~= layer.seatScale then
                return false  -- the slot moved: only a re-seat can follow it
            end
            local id = icon.isItem and icon.itemID or icon.spellID
            if id ~= layer.armedID or busy ~= (layer.disarmed or false) then
                if not ArmLayer(layer, icon, busy) then return false end
            end
        end
    end
    return n == placedCount
end

-- Fallback for the cases ResyncInPlace hands back: withdraw any layer that no longer matches
-- what it was armed for, so nothing stays clickable through the wait. Layers still sitting
-- correctly over their own icon keep working - there's no reason to blink them out.
local function WithdrawStale()
    for i = 1, POOL_SIZE do
        local layer = layers[i]
        if layer and layer:IsShown() then
            local icon = layer.icon
            local id = icon and (icon.isItem and icon.itemID or icon.spellID)
            if not IsCoverable(icon) or id ~= layer.armedID then layer:Hide() end
        end
    end
end

--- Called after the queues render, and on combat-end / login.
function PrecombatOverlay.Refresh()
    -- Strictly an out-of-combat feature: in combat, do nothing and schedule
    -- nothing - the old reschedule here span a no-op timer closure ~10x/sec for
    -- the whole fight. PLAYER_REGEN_ENABLED re-arms the overlay on combat exit.
    if InCombatLockdown() then return end
    local addon = ownerAddon
    if not container or not addon then return ScheduleUpdate() end
    if ResyncInPlace(addon) then return end
    WithdrawStale()
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
