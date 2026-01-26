-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Manager Module (Orchestrator)
-- Coordinates between UIAnimations, UIFrameFactory, and UIRenderer modules
local UIManager = LibStub:NewLibrary("JustAC-UIManager", 28)
if not UIManager then return end

-- Import submodules
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local UIRenderer = LibStub("JustAC-UIRenderer", true)

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local LSM = LibStub("LibSharedMedia-3.0")

-- Masque support
local Masque = LibStub("Masque", true)
local MasqueGroup = nil
local MasqueDefensiveGroup = nil

if Masque then
    MasqueGroup = Masque:Group("JustAssistedCombat", "Spell Queue")
    MasqueDefensiveGroup = Masque:Group("JustAssistedCombat", "Defensive")
end

-- Initialize UIFrameFactory with Masque accessors
if UIFrameFactory then
    UIFrameFactory.InitializeMasqueAccessors(
        function() return MasqueGroup end,
        function() return MasqueDefensiveGroup end
    )
end

-- Masque API access (for external consumers)
function UIManager.GetMasqueGroup()
    return MasqueGroup
end

function UIManager.GetMasqueDefensiveGroup()
    return MasqueDefensiveGroup
end

function UIManager.IsMasqueEnabled()
    return Masque ~= nil
end

-- Invalidate hotkey cache (call when action bars or bindings change)
function UIManager.InvalidateHotkeyCache()
    if UIRenderer then
        UIRenderer.InvalidateHotkeyCache()
    end
end

-- Freeze/unfreeze all glow animations (delegate to UIAnimations)
function UIManager.FreezeAllGlows(addon)
    if UIAnimations then
        UIAnimations.PauseAllGlows()
    end
end

function UIManager.UnfreezeAllGlows(addon)
    if UIAnimations then
        UIAnimations.ResumeAllGlows()
    end
end

-- Re-export UIAnimations functions
function UIManager.HideAllGlows()
    if UIAnimations then
        return UIAnimations.HideAllGlows()
    end
end

function UIManager.PauseAllGlows()
    if UIAnimations then
        return UIAnimations.PauseAllGlows()
    end
end

function UIManager.ResumeAllGlows()
    if UIAnimations then
        return UIAnimations.ResumeAllGlows()
    end
end

-- Flash animations (delegate to UIAnimations)
UIManager.StartFlash = UIAnimations and UIAnimations.StartFlash or nil
UIManager.StopFlash = UIAnimations and UIAnimations.StopFlash or nil
UIManager.UpdateFlash = UIAnimations and UIAnimations.UpdateFlash or nil

-- Re-export UIFrameFactory functions
function UIManager.CreateMainFrame(addon)
    if UIFrameFactory then
        return UIFrameFactory.CreateMainFrame(addon)
    end
end

function UIManager.CreateGrabTab(addon)
    if UIFrameFactory then
        return UIFrameFactory.CreateGrabTab(addon)
    end
end

function UIManager.CreateSpellIcons(addon)
    if UIFrameFactory then
        return UIFrameFactory.CreateSpellIcons(addon)
    end
end

function UIManager.CreateSingleSpellIcon(addon, index, offset, profile)
    if UIFrameFactory then
        return UIFrameFactory.CreateSingleSpellIcon(addon, index, offset, profile)
    end
end

function UIManager.UpdateFrameSize(addon)
    if UIFrameFactory then
        UIFrameFactory.UpdateFrameSize(addon)
    end
end

function UIManager.SavePosition(addon)
    if UIFrameFactory then
        UIFrameFactory.SavePosition(addon)
    end
end

-- Re-export UIRenderer functions
function UIManager.RenderSpellQueue(addon, spellIDs)
    if UIRenderer then
        return UIRenderer.RenderSpellQueue(addon, spellIDs)
    end
end

function UIManager.ShowDefensiveIcon(addon, id, isItem)
    if not addon or not addon.defensiveIcon then return end
    if UIRenderer then
        return UIRenderer.ShowDefensiveIcon(addon, id, isItem, addon.defensiveIcon)
    end
end

function UIManager.HideDefensiveIcon(addon)
    if not addon or not addon.defensiveIcon then return end
    if UIRenderer then
        UIRenderer.HideDefensiveIcon(addon.defensiveIcon)
    end
end

function UIManager.OpenHotkeyOverrideDialog(addon, spellID)
    if UIRenderer then
        UIRenderer.OpenHotkeyOverrideDialog(addon, spellID)
    end
end
