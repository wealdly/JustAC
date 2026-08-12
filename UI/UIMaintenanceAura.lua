-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: engine-drawn timer and stack count for the defensive maintenance slot.
--
-- Everything here is drawn by the ENGINE off the real aura. We create the widgets, hand them
-- to an aura container, and never write to them again: the container reads the (secret) aura
-- from untainted code and drives them. That retires the two standing compromises in the
-- maintenance slot's display, and neither needs an aura instance any more, because we never
-- identify the aura - the container is told which spell id to watch and matches it itself:
--   * the sweep was our own cast timestamp plus a book duration, which drifts the moment a
--     talent lengthens the buff, and only did better when the Cooldown Manager was configured;
--   * the stack count rendered only on a PROVEN bind, so a player without a Cooldown Manager
--     panel saw no number at all.
--
-- WHY NAMING THE SPELL WORKS HERE AND NOT ON THE SOOTHE CUE: candidate filters by spell id are
-- refused for helpful auras on a unit the player cannot assist (AuraContainerUtil.
-- CanApplyIdentityCandidateFilters) - which is exactly an enemy's enrage, so that cue has to
-- colour a whole filtered set instead. On the PLAYER the test passes and we can name the buff.
--
-- What this does NOT provide is a branch. Every widget the container drives carries a secret
-- aspect, so "is the buff up" remains MaintenanceTracker's question and still drives the glow.
-- This module is the display half only, and the slot renders exactly as it did before whenever
-- Attach declines - the estimate and the projection stay in place as the fallback.
--
-- Registration is the way in for every display here: we never call the engine's setter, we hand
-- it the widget and it makes the call.
local UIMaintenanceAura = LibStub:NewLibrary("JustAC-UIMaintenanceAura", 1)
if not UIMaintenanceAura then return end

local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)

local CreateFrame = CreateFrame
local pcall = pcall

-- Matches CreateBaseIcon's own cooldown inset, so the engine sweep lands exactly where the
-- slot's estimated sweep used to and the two are indistinguishable in size and position.
local SWIPE_INSET = 4

--- Which of the two displays an entry wants from the engine. Both answers come from flags the
--- entries ALREADY carry, so no curated data needed a new field:
---
---   sweep - anything not chargeGated. A chargeGated slot deliberately shows the ABILITY's
---           recharge rather than the buff, so the aura's clock is the wrong one there.
---           NOT gated on `dur`. That was an early mistake here, and it cost Blood its sweep:
---           a missing `dur` means "never fabricate a time-based refresh CUE from a static
---           duration" (Bone Shield's stacks are eaten by damage, not by time), and it governs
---           the glow, via EffectiveDuration. The SWEEP has always been separate - the
---           renderer's own trust ladder already tries the real DurationObject for exactly the
---           entries that do not project, Bone Shield included. Drawing the aura's true
---           remaining time is not a guess, so nothing here needs `dur`'s permission.
---
---   count - `stacks`, and NOT `project`. A projecting entry counts its own casts, which is
---           measured-correct for a buff whose applications land as SEPARATE aura instances
---           (Ironfur: 94 casts produced 94 distinct instance ids). The container can only ever
---           hold one of those, so its number would be one stack's, not the buff's. Bone Shield
---           is the entry that genuinely stacks within a single instance - SpellAuraOptions
---           19756 CumulativeAura=10, against Ironfur's 1 - and it is the one that gains here.
---
--- @return boolean sweep, boolean count
local function Wants(entry)
    return not entry.chargeGated, (entry.stacks and not entry.project) or false
end

--- Mirror one of the slot's own font strings onto its engine-driven twin, so the number appears
--- in the player's configured face, size, colour and corner rather than a default. Copying the
--- RESOLVED look off the live widget, rather than re-reading the profile, means this needs to
--- know nothing about the text-overlay options and cannot drift from them.
--- Anchoring carries only the point names and offsets - the source anchors to a frame that does
--- not exist in our subtree - which is exact, because the slot uses the same point for both
--- sides of every one of these anchors.
--- Every call is pcall'd: registration stamps Text (and for the count, Shown) on the target, and
--- a re-style must never be able to take down text settings for every icon on screen.
local function CopyTextStyle(src, dst)
    if not (src and dst) then return end
    local okF, font, size, flags = pcall(src.GetFont, src)
    if okF and font then pcall(dst.SetFont, dst, font, size, flags) end
    local okC, r, g, b, a = pcall(src.GetTextColor, src)
    if okC and r then pcall(dst.SetTextColor, dst, r, g, b, a) end
    local okJ, jh = pcall(src.GetJustifyH, src)
    if okJ and jh then pcall(dst.SetJustifyH, dst, jh) end
    local okP, pt, _, _, ox, oy = pcall(src.GetPoint, src, 1)
    if okP and pt then
        pcall(dst.ClearAllPoints, dst)
        pcall(dst.SetPoint, dst, pt, dst:GetParent(), pt, ox or 0, oy or 0)
    end
end

--- Re-apply the player's text-overlay settings to whatever the engine is drawing. Called from
--- UIFrameFactory.ApplyTextOverlaySettings, so one hook covers both maintenance surfaces and
--- the engine-drawn text never drifts from the slot's own.
function UIMaintenanceAura.Restyle(icon)
    local ov = icon and icon._maintAura
    if not ov then return end
    CopyTextStyle(icon.chargeText, ov.countText)
    CopyTextStyle(icon.cooldownText, ov.cdText)
end

--- Build the container for one aura id, writing what it manages back into `ov`. Returns nil on
--- any refusal, and every caller treats that as "the slot keeps its own estimate", so a client
--- that cannot do this simply behaves as it did before.
---
--- An aura SLOT, not an aura group. A slot is Blizzard's own primitive for "at most one aura in
--- a stable location", which is exactly this button, and it has two properties a group does not:
--- its frame is created EAGERLY and handed back, so initializeFrame has already run (and already
--- reported success or failure) by the time we return; and slots take no part in the container's
--- flow layout, so we anchor the frame ourselves rather than inheriting a layout pass. A group
--- would instead create a lazy batch of ten frames on first sighting of the aura, leaving nine
--- spare buttons and no reliable moment to read the outcome.
local function Build(icon, entry, ov)
    -- GetWidth() is secret on nameplate-parented frames (see UIFrameFactory's cachedIconSize
    -- note) and one of the two maintenance slots lives on a nameplate, so never measure here.
    local sz = icon.cachedIconSize or 32
    if sz <= 0 then sz = 32 end

    -- An AuraContainer, not a plain Frame: only these carry allowUntaintedCreation, so the
    -- frame does not run in our taint and Blizzard will drive it from secret aura data.
    local okC, cont = pcall(CreateFrame, "AuraContainer", nil, icon, "CustomAuraContainerTemplate")
    if not okC or not cont then return nil end
    -- ONE anchor point, never SetAllPoints: holding only aura slots, the container's layout pass
    -- completes empty and sizes it to zero, which would fight four anchors. Its size does not
    -- matter - it draws nothing itself, and the slot frame below carries its own size - but its
    -- TOP-LEFT does, because that is what the slot frame anchors against.
    cont:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    -- Above the icon's border art (+3) so the sweep is not clipped by the frame, below the
    -- hotkey (+15) so the keybind still reads over it.
    local okL, lvl = pcall(function() return icon:GetFrameLevel() end)
    cont:SetFrameLevel((okL and lvl or 0) + 14)
    pcall(cont.EnableMouse, cont, false)
    if not pcall(cont.SetUnit, cont, "player") then
        pcall(cont.SetParent, cont, nil)
        return nil
    end

    local function Init(button)
        -- Size AND place it: aura frames have no intrinsic size, and a slot takes no part in the
        -- container's layout pass, so a button left as it arrives renders at zero pixels in an
        -- unspecified place - invisible, with every other gate reporting healthy. Anchored to the
        -- CONTAINER, which is the shape Blizzard's own layout uses for group frames; the
        -- container's top-left is the icon's, so this lands exactly over the slot.
        pcall(button.SetSize, button, sz, sz)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", cont, "TOPLEFT", 0, 0)

        if ov.sweep then
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            -- CooldownFrameTemplate anchors all four corners to its parent; clear those before
            -- insetting or they win and the sweep covers the border art.
            cd:ClearAllPoints()
            cd:SetPoint("TOPLEFT",     button, "TOPLEFT",      SWIPE_INSET, -SWIPE_INSET)
            cd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -SWIPE_INSET,  SWIPE_INSET)
            -- Styled BEFORE registration, through the shared styler that owns the slot's blue
            -- sweep - one definition for the estimated sweep and this one, so a player moving
            -- between them sees the same thing. Registration stamps the Cooldown and Shown
            -- aspects on the widget, and writing to a stamped widget is what throws.
            if UIFrameFactory and UIFrameFactory.ApplyMaintenanceSwipeStyle then
                pcall(UIFrameFactory.ApplyMaintenanceSwipeStyle, { cooldown = cd })
            end
            if pcall(button.SetDurationCooldown, button, cd) then
                -- The swipe's countdown numbers are the "true countdown" the player actually
                -- reads, so give them the slot's own styling rather than the template default.
                local region = cd:GetRegions()
                ov.cdText = (region and region.SetFont) and region or nil
                CopyTextStyle(icon.cooldownText, ov.cdText)
            else
                ov.sweep = false        -- hand the sweep back to the slot's own estimate
                cd:Hide()
            end
        end

        if ov.count then
            local fs = button:CreateFontString(nil, "OVERLAY")
            CopyTextStyle(icon.chargeText, fs)
            -- EMPTY options, and NEVER a `formatter` - this is a landmine, not a preference.
            -- The stack count is secret in combat and a formatter userdata cannot hold a
            -- secret, so the formatting call throws INSIDE the container's dirty pass. That
            -- pass owns the dirty-flag latch, which only re-arms on a clean->dirty edge, so
            -- the throw does not merely lose one update - it BRICKS the container for the
            -- rest of the session. Bind-time validation cannot catch it either, because the
            -- validator test-drives the formatter with a non-secret value and passes.
            -- (Cross-checked against another addon driving these same containers, which
            -- reached the identical conclusion independently.)
            -- Duration text is NOT affected: that path goes through the C-side duration
            -- binding, which handles secrets - so a formatter there is safe. Only counts.
            -- With no formatter the engine's own "blank below 2" rule applies, which is the
            -- same threshold the slot's hand-rolled count already used.
            if pcall(button.SetApplicationCount, button, fs, {}) then
                ov.countText = fs
            else
                ov.count = false
                fs:Hide()
            end
        end
    end

    -- ExpirationOnly, so a buff whose applications are separate aura instances shows the one
    -- about to fall off - "when do I lose a stack", which is exactly what the cast projection
    -- aims at by anchoring on the oldest application. Guarded: on a client without the enum the
    -- default comparator also ends in expiration order, which is the same answer here.
    local sortMethod = type(AuraContainerSortMethod) == "table"
                       and AuraContainerSortMethod.ExpirationOnly or nil
    local ok = pcall(cont.AddAuraSlot, cont, "jacMaint", "HELPFUL|PLAYER", {
        sortMethod = sortMethod,
        candidateFilters = { includeSpellIDs = { [entry.aura] = true } },
        initializeFrame = Init,
    })
    if not ok then
        pcall(cont.Hide, cont)
        pcall(cont.SetParent, cont, nil)
        return nil
    end
    return cont
end

--- Arm the engine-drawn displays for `entry` on `icon`. Idempotent and called every render
--- pass; the container is built once per aura id and only shown or hidden after that.
---
--- Returns what the ENGINE now owns, so the renderer can stand down from drawing the same
--- thing itself. Both false means nothing changed and the slot draws exactly as it always has.
--- @return boolean ownsSweep, boolean ownsCount
function UIMaintenanceAura.Attach(icon, entry)
    if not (icon and entry and entry.aura) then return false, false end
    local sweep, count = Wants(entry)
    if not (sweep or count) then
        UIMaintenanceAura.Detach(icon)
        return false, false
    end

    local ov = icon._maintAura
    if ov and ov.aura ~= entry.aura then
        -- A different buff needs a new container: the slot's filter is fixed at AddAuraSlot and
        -- there is no way to retire one, so orphan the old container. Runs on spec change, not
        -- per frame. Guarded on `container` because a remembered REFUSAL stores false here.
        if ov.container then
            pcall(ov.container.Hide, ov.container)
            pcall(ov.container.SetParent, ov.container, nil)
        end
        icon._maintAura, ov = nil, nil
    end
    if not ov then
        -- Built through the table so Init can hand a display back when the engine refuses it;
        -- the renderer re-reads these every pass, so a refusal is picked up on the next frame.
        ov = { aura = entry.aura, sweep = sweep, count = count }
        -- Remembered either way: a client that cannot do this must not be asked to build a
        -- container on every render pass.
        ov.container = Build(icon, entry, ov) or false
        icon._maintAura = ov
    end
    if not ov.container then return false, false end

    if not ov.container:IsShown() then ov.container:Show() end
    return ov.sweep, ov.count
end

--- Stand the engine displays down. Hiding the container is the whole job: it hides its own
--- subtree, and Blizzard drops the UNIT_AURA registration on hide and re-reads every aura on
--- show, so nothing goes stale across a hidden stretch. Widgets are deliberately not blanked -
--- they live inside a container button, where our writes are denied once auras are secret.
function UIMaintenanceAura.Detach(icon)
    local ov = icon and icon._maintAura
    local cont = ov and ov.container
    if cont and cont:IsShown() then cont:Hide() end
end

return UIMaintenanceAura
