-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Labels - Icon label settings (hotkey text, cooldown text, charge count / item qty)
-- Builds inline groups consumed by the Display tab's Shared Behavior panel.

local Labels = LibStub:NewLibrary("JustAC-OptionsLabels", 5)
if not Labels then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local HOTKEY_ANCHORS = {"TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOMRIGHT", "BOTTOMLEFT"}
local CHARGE_ANCHORS = {"BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM"}

local rebuildNPO = W.rebuildNPO

-- Build a single inline group for one label type. Show/color/anchor are central
-- (profile.textOverlays) and shared by every surface; only the nameplate font
-- scales below are per-surface.
local function BuildLabelInlineGroup(addon, key, groupName, order, defaultAlpha, anchorValues, anchorSorting, defaultAnchor)
    local hasAnchor = (anchorValues ~= nil)

    local function getBlock()
        local ov = addon.db.profile.textOverlays
        return ov and ov[key]
    end
    local function onSet()
        addon:UpdateFrameSize()
        rebuildNPO(addon)
    end

    return {
        type = "group",
        inline = true,
        name = groupName,
        order = order,
        args = {
            show = {
                type = "toggle",
                name = L["Show"],
                order = 1,
                width = "full",
                get = function()
                    local b = getBlock()
                    return not b or b.show ~= false
                end,
                set = function(_, val)
                    addon.db.profile.textOverlays[key].show = val
                    onSet()
                end,
            },
            fontScale = {
                type = "range",
                name = L["Font Scale"],
                desc = L["Font Scale desc"],
                min = 0.5, max = 3.0, step = 0.05,
                order = 2,
                width = "normal",
                get = function()
                    local b = getBlock()
                    return (b and b.fontScale) or 1.0
                end,
                set = function(_, val)
                    addon.db.profile.textOverlays[key].fontScale = val
                    onSet()
                end,
            },
            color = {
                type = "color",
                name = L["Text Color"],
                desc = L["Text Color desc"],
                hasAlpha = true,
                order = 3,
                width = "normal",
                get = function()
                    local b = getBlock()
                    local c = b and b.color
                    return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or defaultAlpha
                end,
                set = function(_, r, g, b, a)
                    local blk = addon.db.profile.textOverlays[key]
                    if not blk.color then blk.color = {} end
                    blk.color.r, blk.color.g, blk.color.b, blk.color.a = r, g, b, a
                    onSet()
                end,
            },
            anchor = hasAnchor and {
                type = "select",
                name = L["Text Anchor"],
                desc = key == "hotkey" and L["Hotkey Anchor desc"] or L["Charge Anchor desc"],
                order = 4,
                width = "normal",
                values = anchorValues,
                sorting = anchorSorting,
                get = function()
                    local b = getBlock()
                    return (b and b.anchor) or defaultAnchor
                end,
                set = function(_, val)
                    addon.db.profile.textOverlays[key].anchor = val
                    onSet()
                end,
            } or nil,
        },
    }
end

-- Nameplate icons render smaller, so each label type keeps its own font scale
-- there; everything else is the shared central setting above.
local function BuildOverlayScale(addon, key, name, order)
    return {
        type = "range",
        name = name,
        desc = L["Font Scale desc"],
        min = 0.5, max = 3.0, step = 0.05,
        order = order,
        width = "normal",
        get = function()
            local npo = addon.db.profile.nameplateOverlay
            local b = npo and npo.textOverlays and npo.textOverlays[key]
            return (b and b.fontScale) or 1.0
        end,
        set = function(_, val)
            local npoOv = addon.db.profile.nameplateOverlay.textOverlays
            if not npoOv[key] then npoOv[key] = {} end
            npoOv[key].fontScale = val
            rebuildNPO(addon)
        end,
    }
end

--- Inject the label controls into `args` starting at `baseOrder`: an Icon Labels
--- header, the three shared label groups, and the nameplate font-scale group.
function Labels.AddLabelArgs(addon, args, baseOrder)
    local hotkeyAnchorValues = {
        TOPRIGHT    = L["Top Right"],
        TOPLEFT     = L["Top Left"],
        TOP         = L["Top Center"],
        CENTER      = L["Center"],
        BOTTOMRIGHT = L["Bottom Right"],
        BOTTOMLEFT  = L["Bottom Left"],
    }
    local chargeAnchorValues = {
        BOTTOMRIGHT = L["Bottom Right"],
        BOTTOMLEFT  = L["Bottom Left"],
        BOTTOM      = L["Bottom Center"],
    }

    args.labelsHeader = {
        type = "header",
        name = L["Icon Labels"],
        order = baseOrder,
    }
    args.hotkeyGroup   = BuildLabelInlineGroup(addon, "hotkey",   L["Hotkey Text"],   baseOrder + 1, 1.0, hotkeyAnchorValues, HOTKEY_ANCHORS, "TOPRIGHT")
    args.cooldownGroup = BuildLabelInlineGroup(addon, "cooldown", L["Cooldown Text"], baseOrder + 2, 0.5, nil, nil, nil)
    args.chargesGroup  = BuildLabelInlineGroup(addon, "charges",  L["Charge Count"],  baseOrder + 3, 1.0, chargeAnchorValues, CHARGE_ANCHORS, "BOTTOMRIGHT")
    args.overlayScales = {
        type = "group",
        inline = true,
        name = L["Nameplate Font Scale"],
        order = baseOrder + 4,
        disabled = function()
            return LibStub("JustAC-Options", true).IsOverlayDisabled(addon)
        end,
        args = {
            note = {
                type = "description",
                name = L["Overlay Labels Shared desc"],
                order = 0,
            },
            hotkey   = BuildOverlayScale(addon, "hotkey",   L["Hotkey Text"],   1),
            cooldown = BuildOverlayScale(addon, "cooldown", L["Cooldown Text"], 2),
            charges  = BuildOverlayScale(addon, "charges",  L["Charge Count"],  3),
        },
    }
end

--- Reset every label setting to defaults; called from the Shared panel's reset.
function Labels.ResetToDefaults(addon)
    addon.db.profile.textOverlays = {
        hotkey   = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="TOPRIGHT" },
        cooldown = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=0.5} },
        charges  = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="BOTTOMRIGHT" },
    }
    if addon.db.profile.nameplateOverlay then
        addon.db.profile.nameplateOverlay.textOverlays = {
            hotkey   = { fontScale = 1.0 },
            cooldown = { fontScale = 1.0 },
            charges  = { fontScale = 1.0 },
        }
    end
    addon:UpdateFrameSize()
    rebuildNPO(addon)
end
