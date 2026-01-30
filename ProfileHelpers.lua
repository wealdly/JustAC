local LSM = LibStub("LibSharedMedia-3.0")
local ProfileHelpers = LibStub:NewLibrary("JustAC-ProfileHelpers", 1)
local math_floor = math.floor

-- Helper function to set Hotkey to profile variables
function ProfileHelpers.ApplyHotkeyProfile(addon, hotkeyText, button, isFirst)
    local profile = addon:GetProfile()

    local db = profile.hotkeyText
    if not db or not hotkeyText or not button then return end

    -- Font
    local fontPath = LSM:Fetch("font", db.font or "Friz Quadrata TT")
    local fontSize = db.size or 12
    local flags = db.flags or "OUTLINE"

    hotkeyText:SetFont(fontPath, fontSize, flags)

    -- Color
    local c = db.color or { r = 1, g = 1, b = 1, a = 1 }
    hotkeyText:SetTextColor(c.r, c.g, c.b, c.a)

    -- Justification
    hotkeyText:SetJustifyH("RIGHT")

    -- Position
    hotkeyText:ClearAllPoints()

    local xOffset, yOffset
    if isFirst then
        xOffset = db.firstXOffset or -3
        yOffset = db.firstYOffset or -3
        local scale = profile.firstIconScale or 1.3
        fontSize = fontSize * scale
    else
        xOffset = db.queueXOffset or -2
        yOffset = db.queueYOffset or -2
    end

    hotkeyText:SetPoint(
        db.anchorPoint or "TOPRIGHT", -- point on hotkey text
        button,
        db.anchor or "TOPRIGHT",      -- parent anchor
        xOffset,
        yOffset
    )
end

function ProfileHelpers.ApplyChargeTextProfile(addon, hotkeyText, button)
    local profile = addon:GetProfile()

    local db = profile.hotkeyText
    if not db or not hotkeyText or not button then return end

    -- Font
    local fontPath = LSM:Fetch("font", db.font or "Friz Quadrata TT")
    local fontSize = db.size or 12
    local flags = db.flags or "OUTLINE"

    hotkeyText:SetFont(fontPath, math_floor(fontSize * 0.65), flags)

    -- Color
    local c = db.color or { r = 1, g = 1, b = 1, a = 1 }
    hotkeyText:SetTextColor(c.r, c.g, c.b, c.a)

    -- Justification
    hotkeyText:SetJustifyH("RIGHT")

    -- Position
    hotkeyText:ClearAllPoints()

    local xOffset, yOffset = -2,-2

    hotkeyText:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        xOffset,
        yOffset
    )
end