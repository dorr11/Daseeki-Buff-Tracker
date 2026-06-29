local _, Addon = ...

local EXPIRY_WARN_SEC = 120  -- show icon when buff/enchant has ≤ 2 min remaining

-- ============================================================
-- Visibility: icon shows when buff is MISSING or expiring.
-- ============================================================
function Addon:IsItemMissing(item)
    if item.weaponSlot and item.weaponSlot ~= "" then
        if not Addon:HasWeaponEnchant(item.weaponSlot) then return true end
        local secs = Addon:GetWeaponEnchantSecondsRemaining(item.weaponSlot)
        return secs ~= nil and secs <= EXPIRY_WARN_SEC
    end
    local names = Addon:GetBuffNames(item)
    if #names > 0 then
        local best = Addon:GetMultiBuffExpiry(names)
        if best == nil then return true end              -- no buff active
        if best <= EXPIRY_WARN_SEC then return true end  -- best buff expiring soon
        return false
    end
    return false
end

-- Returns seconds remaining when an item is in the "expiring soon" state, nil otherwise.
function Addon:GetItemExpirySeconds(item)
    if item.weaponSlot and item.weaponSlot ~= "" then
        if Addon:HasWeaponEnchant(item.weaponSlot) then
            local secs = Addon:GetWeaponEnchantSecondsRemaining(item.weaponSlot)
            if secs and secs <= EXPIRY_WARN_SEC then return secs end
        end
        return nil
    end
    local names = Addon:GetBuffNames(item)
    if #names > 0 then
        local best = Addon:GetMultiBuffExpiry(names)
        if best and best ~= math.huge and best <= EXPIRY_WARN_SEC then return best end
        return nil
    end
    return nil
end

local function FormatCountdown(secs)
    secs = math.max(0, math.floor(secs))
    if secs < 60 then
        return tostring(secs)
    end
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

function Addon:GetVisibleItems()
    local faction = Addon:GetPlayerFaction()
    local out = {}
    for _, item in ipairs(Addon:GetProfileItems()) do
        local cond = item.conditions or {}
        local factionOK = not cond.faction or cond.faction == faction
        if factionOK and Addon:IsItemMissing(item) then
            out[#out + 1] = item
        end
    end
    return out
end

-- ============================================================
-- ButtonOverlay glow (same glow type as WeakAuras)
-- ============================================================
local function ShowGlow(btn)
    if not ActionButton_ShowOverlayGlow then return end
    ActionButton_ShowOverlayGlow(btn)
    -- Blizzard sizes the glow once with fixed proportions, leaving the bright ring
    -- slightly inside the button edge and not tracking our button size. Re-anchor it
    -- to the current button so it scales with the icon and sits on its border.
    local glow = btn.overlay or btn.SpellActivationAlert or btn.__LBGoverlay
    if glow then
        local w, h = btn:GetSize()
        glow:ClearAllPoints()
        glow:SetSize(w * 1.55, h * 1.55)  -- pushes the glow ring out onto the icon border
        glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end
end

local function HideGlow(btn)
    if ActionButton_HideOverlayGlow then ActionButton_HideOverlayGlow(btn) end
end

-- ============================================================
-- Icon creation
-- ============================================================
local function MakeIcon(index, parent)
    local btn = CreateFrame("Button", "DaseekiCTIcon" .. index, parent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyUp")
    btn:SetFrameLevel(parent:GetFrameLevel() + 1)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0.6)

    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.countText = btn:CreateFontString(nil, "OVERLAY")
    btn.countText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    btn.countText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.countText:SetJustifyH("CENTER")

    btn:SetScript("OnEnter", function(self)
        if Addon.db.settings.showTooltip then
            local it = self._item
            if it and it.itemID and it.itemID > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(it.itemID)
                GameTooltip:Show()
            else
                local names = Addon:GetBuffNames(it)
                if #names > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(it.displayName or names[1], 1, 1, 1)
                    for _, buffN in ipairs(names) do
                        GameTooltip:AddLine("Buff: " .. buffN, 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end
            end
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

-- ============================================================
-- Main frame init
-- ============================================================
-- Anchor corner that matches the collapse direction.
-- RIGHT anchor keeps the right edge fixed (frame grows left) -> anchor by TOPRIGHT.
-- LEFT  anchor keeps the left  edge fixed (frame grows right) -> anchor by TOPLEFT.
local function AnchorCorner(s)
    return (s.anchor or "RIGHT") == "RIGHT" and "TOPRIGHT" or "TOPLEFT"
end

function Addon:InitFrame()
    if Addon.mainFrame then return end
    local s = Addon.db.settings

    -- Migrate / default the saved anchor point fields (DruidBar-style GetPoint storage).
    if not s.point then
        s.point    = AnchorCorner(s)
        s.relPoint = "CENTER"
    end

    local f = CreateFrame("Frame", "DaseekiCTFrame", UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetFrameStrata("MEDIUM")
    f:SetScale(s.scale)
    f:SetPoint(s.point, UIParent, s.relPoint or "CENTER", s.posX, s.posY)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0)

    -- Border shown when unlocked so the frame is visible for repositioning
    local PAD = 3
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetPoint("TOPLEFT",     f, "TOPLEFT",     -PAD,  PAD)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  PAD, -PAD)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    border:Hide()
    f.unlockBorder = border

    -- Re-anchor the frame by its collapse corner (TOPRIGHT/TOPLEFT) to UIParent
    -- CENTER, preserving its current on-screen position. This is needed because
    -- StartMoving leaves the frame anchored by a center-ish point, which would make
    -- SetSize grow symmetrically (collapsing toward center). Computed in screen
    -- pixels then converted to the frame's own units, so it is UI-scale correct.
    local function ReanchorToCorner()
        local corner = AnchorCorner(Addon.db.settings)
        local eff  = f:GetEffectiveScale()
        local ueff = UIParent:GetEffectiveScale()
        local cornerX = ((corner == "TOPRIGHT") and f:GetRight() or f:GetLeft()) * eff
        local cornerY = f:GetTop() * eff
        local ucx, ucy = UIParent:GetCenter()
        ucx, ucy = ucx * ueff, ucy * ueff
        f:ClearAllPoints()
        f:SetPoint(corner, UIParent, "CENTER",
            (cornerX - ucx) / eff,
            (cornerY - ucy) / eff)
    end

    -- Save the frame's exact anchor (DruidBar pattern): store the GetPoint tuple
    -- verbatim and restore it verbatim. Immune to UI scale because the offsets and
    -- the relative point round-trip exactly through SetPoint/GetPoint.
    local function SavePosition()
        local point, _, relPoint, x, y = f:GetPoint()
        local db = Addon.db.settings
        db.point    = point
        db.relPoint = relPoint
        db.posX     = x
        db.posY     = y
    end

    local function BeginDrag()
        if Addon.db.settings.locked then return end
        f._dragging = true
        f:StartMoving()
        f.bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)
    end

    local function EndDrag()
        if not f._dragging then return end
        f._dragging = false
        f:StopMovingOrSizing()
        f.bg:SetColorTexture(0, 0, 0, 0)
        ReanchorToCorner()  -- normalize back to the collapse corner
        SavePosition()
    end

    f.SavePosition      = SavePosition       -- exposed for anchor-change handling
    f.ReanchorToCorner  = ReanchorToCorner

    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then BeginDrag() end
    end)
    f:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then EndDrag() end
    end)

    -- 1-second tick for countdown timers (no repositioning here -- the anchored
    -- corner stays fixed automatically when the frame is resized).
    local _tickAcc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        _tickAcc = _tickAcc + elapsed
        if _tickAcc >= 1 then
            _tickAcc = 0
            Addon:UpdateFrame()
        end
    end)

    -- Move handle: visible when frame is unlocked.
    local mh = CreateFrame("Button", nil, f)
    mh:SetSize(14, 36)
    mh:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
    mh:SetFrameLevel(f:GetFrameLevel() + 5)

    local mhBg = mh:CreateTexture(nil, "BACKGROUND")
    mhBg:SetAllPoints(); mhBg:SetColorTexture(0.15, 0.15, 0.15, 0.88)

    -- 6-dot grip pattern (2 cols × 3 rows)
    for _, pos in ipairs({ {-3,-8},{3,-8}, {-3,0},{3,0}, {-3,8},{3,8} }) do
        local d = mh:CreateTexture(nil, "ARTWORK")
        d:SetSize(3, 3); d:SetColorTexture(0.75, 0.75, 0.75, 1)
        d:SetPoint("CENTER", mh, "CENTER", pos[1], pos[2])
    end

    local mhHl = mh:CreateTexture(nil, "HIGHLIGHT")
    mhHl:SetAllPoints(); mhHl:SetColorTexture(1, 0.82, 0, 0.3)
    mh:SetHighlightTexture(mhHl)

    mh:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then BeginDrag() end
    end)
    mh:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then EndDrag() end
    end)
    mh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    mh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mh:Hide()
    f.moveHandle = mh

    f._dragging = false
    f.icons = {}
    Addon.mainFrame = f

    Addon:UpdateFrame()

    -- Normalize any legacy/centered saved anchor to the proper collapse corner,
    -- preserving the current on-screen position.
    if s.point ~= AnchorCorner(s) then
        ReanchorToCorner()
        SavePosition()
    end
end

-- ============================================================
-- Layout + attribute update
-- ============================================================
function Addon:UpdateFrame()
    local f = Addon.mainFrame
    if not f then return end

    -- DaseekiCTFrame parents secure (SecureActionButtonTemplate) icons, so its OWN
    -- geometry/visibility (SetSize/SetScale/Show/Hide) are protected in combat too.
    local inCombat = InCombatLockdown()

    if not Addon:ShouldShow() then
        if not inCombat then f:Hide() end
        return
    end

    local s      = Addon.db.settings
    local items  = Addon:GetVisibleItems()
    local iSize  = s.iconSize
    local iGap   = s.iconSpacing
    local perRow = s.iconsPerRow
    -- Anchor icons to the fixed collapse corner so position 1 stays put and the
    -- rest fill toward it (WeakAuras-style grow). RIGHT grows left from TOPRIGHT,
    -- LEFT grows right from TOPLEFT.
    local growRight = (s.anchor or "RIGHT") ~= "RIGHT"

    -- The icon buttons are SecureActionButtonTemplate (protected): in combat we
    -- cannot :Hide()/:Show()/:SetPoint()/:SetSize()/:SetAttribute() them. So we use
    -- ALPHA for visibility (allowed in combat) and only do the protected layout /
    -- attribute work out of combat. A full reflow runs again on PLAYER_REGEN_ENABLED.
    local n = #items

    -- Surplus icons: hide via alpha so this works in combat too.
    for i = n + 1, #f.icons do
        local b = f.icons[i]
        if b then
            HideGlow(b)
            b:SetAlpha(0)
            if not inCombat then b:EnableMouse(false) end
        end
    end

    for i, item in ipairs(items) do
        local btn = f.icons[i]
        if not btn then
            if inCombat then
                -- Can't create/show/position a secure button in combat; finish after.
                f._combatDirty = true
                break
            end
            btn = MakeIcon(i, f)
            f.icons[i] = btn
            btn:Show()  -- shown once; visibility is controlled by alpha thereafter
        end

        -- Layout + secure attributes are protected: only touch them out of combat.
        if not inCombat then
            btn:SetSize(iSize, iSize)
            btn:EnableMouse(true)

            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            btn:ClearAllPoints()
            if growRight then
                btn:SetPoint("TOPLEFT", f, "TOPLEFT",
                     col * (iSize + iGap),
                    -row * (iSize + iGap))
            else
                btn:SetPoint("TOPRIGHT", f, "TOPRIGHT",
                    -col * (iSize + iGap),
                    -row * (iSize + iGap))
            end

            -- Click action
            if item.weaponSlot and item.clickable and item.actionType == "macro" and item.macroName then
                local _, _, macroText = GetMacroInfo(item.macroName)
                btn:SetAttribute("type",      "macro")
                btn:SetAttribute("macrotext", macroText or "")
            elseif item.weaponSlot then
                btn:SetAttribute("type", nil)
            elseif item.clickable and item.actionType == "item" and item.itemID and item.itemID > 0 then
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", "item:" .. item.itemID)
            elseif item.clickable and item.actionType == "macro" and item.macroName then
                local _, _, macroText = GetMacroInfo(item.macroName)
                btn:SetAttribute("type",      "macro")
                btn:SetAttribute("macrotext", macroText or "")
            else
                btn:SetAttribute("type", nil)
            end
        end

        btn._item   = item
        btn._itemID = item.itemID

        -- Icon texture, countdown, glow, visibility -- all safe in combat.
        btn.tex:SetTexture(Addon:GetBuffIcon(item))
        local expirySecs = Addon:GetItemExpirySeconds(item)
        if expirySecs then
            btn.countText:SetText(FormatCountdown(expirySecs))
            btn.countText:SetTextColor(1, 1, 1, 1)
        else
            btn.countText:SetText("")
        end
        ShowGlow(btn)
        btn:SetAlpha(1)
    end

    -- f's geometry/visibility are protected in combat (it parents secure icons), so
    -- only resize/show it out of combat. In combat the icons are alpha-toggled in
    -- place (no visible gap, since they anchor to the fixed collapse corner); the
    -- full reflow runs on PLAYER_REGEN_ENABLED.
    if not inCombat then
        local unlocked = not s.locked
        if n == 0 then
            -- Keep a grabbable minimum size when unlocked so the frame can be repositioned
            if unlocked then
                f:SetSize(iSize, iSize)
                f:EnableMouse(true)
            else
                f:SetSize(1, 1)
                f:EnableMouse(false)
            end
        else
            local cols = math.min(n, perRow)
            local rows = math.ceil(n / perRow)
            f:SetSize(
                cols * iSize + math.max(0, cols - 1) * iGap,
                rows * iSize + math.max(0, rows - 1) * iGap
            )
            f:EnableMouse(unlocked)
        end

        if f.moveHandle then f.moveHandle:SetShown(unlocked) end
        if f.unlockBorder then f.unlockBorder:SetShown(unlocked) end

        f:SetScale(s.scale)
        f:Show()
    else
        f._combatDirty = true
    end
end

function Addon:UpdateIcons()
    Addon:UpdateFrame()
end

function Addon:UpdateFrameLock()
    Addon:UpdateFrame()
end

-- Restore the frame to its saved anchor (verbatim GetPoint tuple).
function Addon:PositionFrame()
    local f = Addon.mainFrame
    if not f then return end
    local s = Addon.db.settings
    if not s.point then
        s.point    = AnchorCorner(s)
        s.relPoint = "CENTER"
    end
    f:ClearAllPoints()
    f:SetPoint(s.point, UIParent, s.relPoint or "CENTER", s.posX, s.posY)
end

-- Switch anchor side (RIGHT/LEFT) while keeping the frame visually in place.
function Addon:SetAnchor(newAnchor)
    local f = Addon.mainFrame
    local s = Addon.db.settings
    newAnchor = (newAnchor == "LEFT") and "LEFT" or "RIGHT"
    s.anchor = newAnchor
    if not f then return end

    -- Re-anchor to the new collapse corner at the frame's current position,
    -- save it, then relayout icons toward that corner.
    if f.ReanchorToCorner then f.ReanchorToCorner() end
    if f.SavePosition     then f.SavePosition()     end
    Addon:UpdateFrame()
end
