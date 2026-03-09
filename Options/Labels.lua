-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Labels - Icon label settings (hotkey text, cooldown text, charge count / item qty)

local Labels = LibStub:NewLibrary("JustAC-OptionsLabels", 4)
if not Labels then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local HOTKEY_ANCHORS = {"TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOMRIGHT", "BOTTOMLEFT"}
local CHARGE_ANCHORS = {"BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM"}

local function rebuildNPO(addon)
    local NPO = LibStub("JustAC-UINameplateOverlay", true)
    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
end

-- Build a single inline group for one label type within a sub-tab.
-- source: "central" (profile.textOverlays) or "overlay" (nameplateOverlay.textOverlays with central fallback)
local function BuildLabelInlineGroup(addon, key, groupName, order, defaultAlpha, anchorValues, anchorSorting, defaultAnchor, source)
    local isOverlay = (source == "overlay")
    local hasAnchor = (anchorValues ~= nil)
    local prefix = isOverlay and "Overlay: " or "Standard: "
    local displayName = prefix .. groupName

    -- Storage accessors
    local function getBlock()
        if isOverlay then
            local npo = addon.db.profile.nameplateOverlay
            return npo and npo.textOverlays and npo.textOverlays[key]
        end
        local ov = addon.db.profile.textOverlays
        return ov and ov[key]
    end
    local function ensureBlock()
        if isOverlay then
            local npoOv = addon.db.profile.nameplateOverlay.textOverlays
            if not npoOv[key] then npoOv[key] = {} end
            return npoOv[key]
        end
        return addon.db.profile.textOverlays[key]
    end
    -- Overlay falls back to central for color/anchor
    local function getCentralBlock()
        local ov = addon.db.profile.textOverlays
        return ov and ov[key]
    end
    local function onSet()
        if isOverlay then rebuildNPO(addon) else addon:UpdateFrameSize() end
    end

    return {
        type = "group",
        inline = true,
        name = displayName,
        order = order,
        args = {
            show = {
                type = "toggle",
                name = L["Show"],
                order = 1,
                width = "full",
                get = function()
                    -- Always read from central (shared)
                    local ov = addon.db.profile.textOverlays
                    return not ov or not ov[key] or ov[key].show ~= false
                end,
                set = function(_, val)
                    addon.db.profile.textOverlays[key].show = val
                    addon:UpdateFrameSize()
                    rebuildNPO(addon)
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
                    local b = ensureBlock()
                    b.fontScale = val
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
                    if not c and isOverlay then
                        local cb = getCentralBlock()
                        c = cb and cb.color
                    end
                    return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or defaultAlpha
                end,
                set = function(_, r, g, b, a)
                    local blk = ensureBlock()
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
                    local a = b and b.anchor
                    if not a and isOverlay then
                        local cb = getCentralBlock()
                        a = cb and cb.anchor
                    end
                    return a or defaultAnchor
                end,
                set = function(_, val)
                    local blk = ensureBlock()
                    blk.anchor = val
                    onSet()
                end,
            } or nil,
        },
    }
end

function Labels.CreateTabArgs(addon)
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

    return {
        type = "group",
        name = L["Icon Labels"],
        order = 6,
        childGroups = "tab",
        args = {
            -- ── SUB-TAB 1: STANDARD QUEUE ───────────────────────────────
            standard = {
                type = "group",
                name = L["Standard Queue"],
                order = 1,
                args = {
                    hotkeyGroup   = BuildLabelInlineGroup(addon, "hotkey",   L["Hotkey Text"],   1, 1.0, hotkeyAnchorValues, HOTKEY_ANCHORS, "TOPRIGHT",    "central"),
                    cooldownGroup = BuildLabelInlineGroup(addon, "cooldown", L["Cooldown Text"], 2, 0.5, nil, nil, nil,                                     "central"),
                    chargesGroup  = BuildLabelInlineGroup(addon, "charges",  L["Charge Count"],  3, 1.0, chargeAnchorValues, CHARGE_ANCHORS, "BOTTOMRIGHT", "central"),
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Icon Labels desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            addon.db.profile.textOverlays = {
                                hotkey   = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="TOPRIGHT" },
                                cooldown = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=0.5} },
                                charges  = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="BOTTOMRIGHT" },
                            }
                            addon:UpdateFrameSize()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },
            -- ── SUB-TAB 2: NAMEPLATE OVERLAY ────────────────────────────
            overlay = {
                type = "group",
                name = L["Nameplate Overlay"],
                order = 2,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
                args = {
                    hotkeyGroup   = BuildLabelInlineGroup(addon, "hotkey",   L["Hotkey Text"],   1, 1.0, hotkeyAnchorValues, HOTKEY_ANCHORS, "TOPRIGHT",    "overlay"),
                    cooldownGroup = BuildLabelInlineGroup(addon, "cooldown", L["Cooldown Text"], 2, 0.5, nil, nil, nil,                                     "overlay"),
                    chargesGroup  = BuildLabelInlineGroup(addon, "charges",  L["Charge Count"],  3, 1.0, chargeAnchorValues, CHARGE_ANCHORS, "BOTTOMRIGHT", "overlay"),
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Icon Labels desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            if addon.db.profile.nameplateOverlay then
                                addon.db.profile.nameplateOverlay.textOverlays = {
                                    hotkey   = { fontScale = 1.0 },
                                    cooldown = { fontScale = 1.0 },
                                    charges  = { fontScale = 1.0 },
                                }
                            end
                            rebuildNPO(addon)
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },
        },
    }
end
