-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Soothe (enrage-cleanse) cue - the "enrage interrupt". Rides the interrupt
-- system's construction (the same position-0 slot, the same border/mask/hotkey chrome, a
-- castAura-style pass-through) but is a SEPARATE frame pinned over the interrupt icon: it
-- can NOT be a child of that icon, because the kick hides when there's no cast, whereas
-- soothe must show on the active enrage aura with no cast at all.
--
-- The interrupt icon shows the KICK (branchable). This shows the player's SOOTHE while the
-- target is ENRAGED - and "enraged" is a secret in combat, so we can't branch on it or
-- texture-swap the kick. Instead: enrage == dispel type 9 (C_UnitAuras.GetAuraDispelTypeColor),
-- auraInstanceID is NeverSecret, and the (combat-secret) selector colour sinks straight into
-- each slot texture with no read. One COMPLETE slot per target HELPFUL aura (the OR is done
-- by the container). Each slot is built by the SHARED CreateBaseIcon - the same builder the
-- interrupt and tank-maintenance slots use - so it gets icon, border, mask, slot background
-- and hotkey for free. Whether the cleanse is CASTABLE is not drawn on the slot at all; it
-- decides whether the container is shown in the first place (see Show).
-- Drawn ABOVE the interrupt icon's hotkey (+15), so a shown slot fully replaces the
-- kick (no lingering kick hotkey / missing frame art) and, being on top, wins collisions.
-- ponytail: N complete slots + N idle glows is the cost of the secret-safe OR (can't collapse
-- N secret alphas into one). Bounded to soothe classes with an attackable target + shown frame.
local UISootheCue = LibStub:NewLibrary("JustAC-UISootheCue", 8)
if not UISootheCue then return end

local UIAnimations     = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory   = LibStub("JustAC-UIFrameFactory", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
-- SpellDB is back for one thing only: the cleanse's own cooldown. See Show().
local SpellDB          = LibStub("JustAC-SpellDB", true)
if not (UIAnimations and UIFrameFactory) then return end

local CreateFrame   = CreateFrame
local CreateColor   = CreateColor
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack
local pcall         = pcall
local C_Spell       = C_Spell
local C_CurveUtil   = C_CurveUtil ---@diagnostic disable-line: undefined-global

local MAX_SLOTS       = 5      -- target HELPFUL auras scanned (the OR); enrage past this is missed
-- Selector curves (built once each): transparent everywhere except dispel type 9 (Enrage).
--
-- The curve drives the texture's VERTEX COLOUR, not just its alpha, and it is registered
-- PER TEXTURE - so the colour at point 9 is the tint that texture takes while the target is
-- enraged. That is why there are two: a white one leaves the spell icon its natural colours,
-- and a cyan one tints the glow art. Setting a texture's own vertex colour instead does not
-- work: AddDispelTypeTexture stamps SecretAspect.VertexColor and the curve overwrites it,
-- which is what turned an earlier attempt into a raw yellow box.
--
-- Cyan, not green: this sits on the SAME position-0 slot as the red interrupt glow, and
-- red/green is the most common colour-vision deficiency (see SOOTHE_PROC_* in UIAnimations).
local curves = {}
local function GetSelectorCurve(r, g, b)
    local key = (r or 1) .. "," .. (g or 1) .. "," .. (b or 1)
    local cached = curves[key]
    if cached ~= nil then return cached or nil end
    local cu       = C_CurveUtil
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor) then
        curves[key] = false
        return nil
    end
    local c = cu.CreateColorCurve()
    c:SetType(stepType)
    c:AddPoint(0,  CreateColor(0, 0, 0, 0))
    c:AddPoint(9,  CreateColor(r or 1, g or 1, b or 1, 1))   -- Enrage
    c:AddPoint(10, CreateColor(0, 0, 0, 0))
    curves[key] = c
    return c
end

function UISootheCue.Available()
    -- 12.1.0 no longer lets US call GetAuraDataByIndex / GetAuraDispelTypeColor, so their
    -- presence is no longer the question. The aura container is: it makes both calls on our
    -- behalf from untainted code. The style enum only exists on clients carrying it.
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    return (styles and styles.PreserveAsset ~= nil and GetSelectorCurve() ~= nil) and true or false
end

-- WHAT A SLOT INSIDE A CONTAINER BUTTON CAN AND CANNOT DO - measured 2026-08-11, in this
-- order, each one a separate in-game error:
--   works:  icon texture, hotkey text, border/mask chrome, the cleansed-aura sub-icon
--   blocked: SetScript of any kind      ("cannot replace a forbidden script handler" on the
--                                        container; "blocked by secret aspects" on a descendant)
--   blocked: SetCooldownFromDurationObject ("Attempt to access forbidden object")
-- The proc glow was on the blocked list too, wrongly: what it needed was the SetScript, not
-- the animation. An AnimationGroup is engine-side and needs no handler, and the OnHide it
-- normally carries only stops a loop - so a glow that never stops does not need one. See
-- BuildSlot / UIAnimations.CreateUndrivenProcGlow.
--
-- Everything descended from a container button inherits that button's secret aspects, so we
-- may add CONTENT to the subtree but never BEHAVIOUR. There is therefore no cooldown-swipe
-- driver here: the swipe cannot be drawn at all on these slots, and calling the shared updater
-- only produced nine errors a second. That is the cost of the gate being Blizzard's - the old
-- cue owned its frames outright and could draw anything, but could no longer SEE the enrage.
--
-- So "the cleanse is not castable right now" cannot be drawn INSIDE a slot. It is said one
-- level up instead, by hiding the whole container - see Show(). That state is entirely ours
-- and entirely plain (a player-side cooldown, never a secret), so no sink is needed for it.

-- Build one soothe slot on the container button, using the SHARED CreateBaseIcon so this
-- looks identical to the interrupt icon it sits over - same border, mask, slot background,
-- hotkey font and placement - rather than a hand-rolled lookalike that drifts from it.
--
-- CreateBaseIcon was briefly abandoned here after it rendered an empty frame. That was
-- misdiagnosed: the cause was the container button having NO SIZE (fixed below), which would
-- have broken any construction. What genuinely cannot happen inside a container button is
-- BEHAVIOUR - SetScript and SetCooldownFromDurationObject. Creating a Cooldown widget is
-- harmless; only writing to it throws, so simply never driving it is enough. The proc glow
-- is the same story: drop the OnHide it only needs in order to STOP, and the animation
-- itself is engine-side and perfectly welcome here.
local function BuildSlot(parent, sz, profile)
    -- Size the button FIRST: pooled buttons have no intrinsic size and the group's layout
    -- options are spacing-only, so anything anchored to it renders at zero pixels - invisible,
    -- with every other gate reporting healthy.
    pcall(parent.SetSize, parent, sz, sz)

    -- pcall'd: CreateBaseIcon is a large builder and a single guarded call inside it would
    -- take the whole cue down. The bare-texture fallback below keeps a usable cue if that
    -- ever happens on a future client.
    local ok, slot = pcall(UIFrameFactory.CreateBaseIcon, parent, sz, false, true)
    if ok and slot then
        slot:SetAllPoints(parent)
        slot:EnableMouse(false)
        -- CreateBaseIcon ends with Hide(); visibility is the CONTAINER's to decide here, and
        -- the button it lives in exists only while a matching aura does.
        slot:Show()
        slot:SetAlpha(1)
        -- The SAME animated proc glow the interrupt icon wears, in cyan instead of red: this
        -- slot REPLACES the kick on screen, so it has to speak the same visual language. Its
        -- tint comes from the cue's curve, not from SetVertexColor - the container owns
        -- VertexColor on a registered texture and would overwrite us, which is what produced
        -- a raw yellow box on an earlier attempt. The glow is never driven again after this;
        -- if the flipbook ever stops animating it freezes on the frame CreateProcGlowFrame
        -- primed it to, i.e. degrades to a still glow rather than to nothing.
        local procFrame = UIAnimations.CreateUndrivenProcGlow
                          and UIAnimations.CreateUndrivenProcGlow(slot, "SootheProcGlowFrame", sz / 45)
        slot.glow = procFrame and procFrame.ProcLoopFlipbook
        return slot
    end

    -- Fallback: bare textures on the button. No chrome, but the cue still functions.
    local bare = { button = parent }
    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(sz * 1.6, sz * 1.6)
    glow:SetPoint("CENTER", parent, "CENTER", 0, 0)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetBlendMode("ADD")
    bare.glow = glow
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(sz, sz)
    icon:SetPoint("CENTER", parent, "CENTER", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bare.iconTexture = icon
    local hk = parent:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    hk:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
    bare.hotkeyText = hk
    return bare
end

--- Re-seat every slot's cleansed-aura clone for the OVERLAY's expansion. The slots
--- are built with the STANDARD queue's orientation (BuildSlot above), which put the
--- clone on the wrong side of an "up"-expansion overlay - directly over dpsIcons[1].
--- Mirrors the overlay's own castAura convention (±2, no maintenance shift: the
--- overlay's maintenance slot lives on the defensive cluster and can't collide).
function UISootheCue.ReanchorAuras(cue, expansion)
    if not cue or not cue.slots then return end
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        local aura = slot and slot.auraFrame
        if aura then
            aura:ClearAllPoints()
            if expansion == "up" then
                aura:SetPoint("TOP", slot, "BOTTOM", 0, -2)
            else
                aura:SetPoint("BOTTOM", slot, "TOP", 0, 2)
            end
        end
    end
end

--- Record which soothe the cue is for. Deliberately writes NOTHING to a slot: both of a
--- slot's textures were handed to AddDispelTypeTexture and are forbidden objects now, so the
--- icon is stamped at construction (see Init) and a CHANGED spell rebuilds the container
--- instead. There is no RemoveAuraGroup either, so rebuilding is the only way to re-stamp.
function UISootheCue.SetSpell(cue, sootheSpellID)
    if not cue or cue.spellID == sootheSpellID then return end
    local info   = sootheSpellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sootheSpellID)
    local iconID = info and info.iconID
    if sootheSpellID and not iconID then
        -- Not in the client cache yet (login / spec swap). Do NOT record the id: the
        -- same-spell guard above would block every retry and leave the cue armed over an
        -- icon that never resolved.
        return
    end
    cue.spellID = sootheSpellID
    cue._hotkey = (ActionBarScanner and ActionBarScanner.GetSpellHotkey
                   and ActionBarScanner.GetSpellHotkey(sootheSpellID)) or ""
end

--- Create (once) the cue pinned over `anchorIcon` (the interrupt icon = position 0).
function UISootheCue.Create(anchorIcon, sootheSpellID, iconSize)
    if not (anchorIcon and UISootheCue.Available()) then return nil end
    local cue = anchorIcon.sootheCue
    -- A changed soothe means a NEW container: the slots' textures are forbidden to us now, so
    -- they cannot be re-stamped, and the container has no RemoveAuraGroup. Orphan the old one -
    -- this runs per spec change, not per frame.
    if cue and cue.spellID and cue.spellID ~= sootheSpellID then
        pcall(cue.Hide, cue)
        pcall(cue.SetParent, cue, nil)
        anchorIcon.sootheCue, cue = nil, nil
    end
    if not cue then
        -- GetWidth() is secret on nameplate-parented frames (see UIFrameFactory
        -- cachedIconSize note); never call it here.
        local sz = anchorIcon.cachedIconSize or iconSize or 32
        if sz <= 0 then sz = 32 end
        -- An AuraContainer, not a plain Frame: only these carry allowUntaintedCreation, so the
        -- frame does not run in our taint and Blizzard will drive it from secret aura data.
        local okC
        okC, cue = pcall(CreateFrame, "AuraContainer", nil, anchorIcon:GetParent(),
                         "CustomAuraContainerTemplate")
        if not okC or not cue then return nil end
        cue:SetAllPoints(anchorIcon)                 -- tracks position 0 even when the kick is hidden
        cue:SetFrameStrata(anchorIcon:GetFrameStrata())
        pcall(cue.EnableMouse, cue, false)
        local ok, lvl = pcall(function() return anchorIcon:GetFrameLevel() end)
        cue:SetFrameLevel((ok and lvl or 0) + 16)    -- above the kick's hotkeyFrame (+15) -> full replace
        cue.slots = {}
        local addon = LibStub("AceAddon-3.0", true)
        addon = addon and addon:GetAddon("JustAssistedCombat", true)
        local profile = addon and addon.db and addon.db.profile

        -- One slot per container button, built by initializeFrame during AddAuraGroup. The
        -- filter narrows to auras the player can dispel - which per Blizzard's own comment
        -- includes helpful enrages on enemies - so a button, and therefore a slot, exists ONLY
        -- while the target is enraged. We cannot call that filter ourselves in combat; the
        -- container can. The dispel-type-9 curve is applied per slot below as a second gate.
        pcall(cue.SetUnit, cue, "target")
        -- Resolve the icon BEFORE AddAuraGroup and stamp it inside Init. SetSpell runs AFTER
        -- the group is added, so a slot built at any other moment than that one call would
        -- never receive an icon - the frame renders, empty. Stamping at construction makes it
        -- independent of when Blizzard chooses to build its buttons.
        UISootheCue.SetSpell(cue, sootheSpellID)   -- resolves cue._hotkey before Init runs
        local firstInfo = sootheSpellID and C_Spell and C_Spell.GetSpellInfo
                          and C_Spell.GetSpellInfo(sootheSpellID)
        local firstIcon = firstInfo and firstInfo.iconID

        local function Init(button)
            local slot = BuildSlot(button, sz, profile)
            if not slot then return end
            cue.slots[#cue.slots + 1] = slot
            if firstIcon then slot.iconTexture:SetTexture(firstIcon) end
            slot.hotkeyText:SetText(cue._hotkey or "")

            -- Hand BOTH textures to Blizzard, each with its own curve: they become forbidden
            -- to us afterwards, which is why the icon and hotkey are stamped ABOVE this and
            -- never touched again. Each is opaque only at dispel type 9 (Enrage) - the icon in
            -- its natural colours, the glow tinted cyan.
            local opts = {
                showAlways = true,   -- enrage is not a dispelName; default criteria would suppress it
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            }
            local cyan = UIAnimations.SOOTHE_PROC_COLOR or { r = 0.55, g = 0.90, b = 1.00 }
            opts.customDispelColorCurve = GetSelectorCurve(cyan.r, cyan.g, cyan.b)
            pcall(button.AddDispelTypeTexture, button, slot.glow, opts)

            opts.customDispelColorCurve = GetSelectorCurve(1, 1, 1)
            pcall(button.AddDispelTypeTexture, button, slot.iconTexture, opts)
        end
        if not pcall(cue.AddAuraGroup, cue, "jacSoothe", "HELPFUL|RAID_PLAYER_DISPELLABLE",
                     { maxFrameCount = MAX_SLOTS, initializeFrame = Init }) then
            pcall(cue.AddAuraGroup, cue, "jacSoothe", "HELPFUL",
                  { maxFrameCount = MAX_SLOTS, initializeFrame = Init })
        end

        -- No driver of any kind. The container refreshes itself from UNIT_AURA (its own
        -- OnUpdate is forbidden to us, which is how it does that), and the cooldown swipe -
        -- the only thing our old driver still had to do - cannot be drawn on these slots at
        -- all. See the note above DriveCooldowns' former home.
        cue:Hide()
        anchorIcon.sootheCue = cue
    end
    UISootheCue.SetSpell(cue, sootheSpellID)
    return cue
end

--- Arm the cue - but only while the cleanse is one the player could actually press.
--- Idempotent; called every render pass by both surfaces.
---
--- The container answers exactly one question, "is the target enraged", and it is the only
--- thing here that can. Everything else the old per-tick driver checked is PLAIN - a
--- player-side cooldown, a hostile target - so the AND is done by showing or hiding the
--- whole container, which is ours and unrestricted. Without this the cue sat over the kick
--- for the entire enrage no matter what state the cleanse was in.
---
--- Charge-aware (IsInterruptOnCooldown -> IsSpellReady). The GCD is deliberately NOT part
--- of it: a cue that vanishes on every global would strobe for the whole fight, and the
--- swipe that used to say "wait" cannot be drawn on these slots.
function UISootheCue.Show(cue)
    if not cue then return end
    local onCD = cue.spellID and SpellDB and SpellDB.IsInterruptOnCooldown
                 and SpellDB.IsInterruptOnCooldown(cue.spellID)
    if onCD or not (UnitExists("target") and UnitCanAttack("player", "target")) then
        return UISootheCue.Hide(cue)
    end
    if not cue:IsShown() then cue:Show() end
end

--- Hide the cue. Hiding the container is the whole job: it hides its own subtree, and
--- Blizzard drops the container's UNIT_AURA registration on hide and re-reads every aura
--- on show, so nothing goes stale across a hidden stretch. Slots are deliberately NOT
--- blanked - a slot lives inside a container button, where our writes are denied once
--- auras are secret, and the alpha was never restored on the way back up.
function UISootheCue.Hide(cue)
    if cue and cue:IsShown() then cue:Hide() end
end

return UISootheCue
