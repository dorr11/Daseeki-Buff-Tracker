local _, Addon = ...

-- ============================================================
-- Buff Tracker options — built into the Daseeki Core hub.
-- The reusable widgets, skin, and dialogs now live in Daseeki-Core
-- (global DaseekiSuite). This file builds the Buff Tracker section
-- into the panel the hub provides.
-- ============================================================

-- Icon getters for each search type (Buff Tracker specific)
local function BuffIconGetter(result)
    if result.weaponSlot then
        local invSlot = result.weaponSlot == "offhand" and 17 or 16
        return GetInventoryItemTexture("player", invSlot)
            or "Interface\\Icons\\INV_Stone_SharpeningStone05"
    end
    if result.spellID then
        local _, _, icon = GetSpellInfo(result.spellID)
        if icon then return icon end
    end
    if result.buffName then
        local _, _, icon = GetSpellInfo(result.buffName)
        if icon then return icon end
    end
    if result.itemID then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(result.itemID)
        if tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ItemIconGetter(result)
    if result.itemID then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(result.itemID)
        if tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function MacroIconGetter(result)
    return result.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ============================================================
-- Item row builder
-- ============================================================
local ROW_HEIGHT = 26
local MAX_ROWS   = 12
local ROW_W      = 438

local function BuildItemRow(scrollChild, i)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(ROW_W, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.12, i % 2 == 0 and 0.12 or 0.08, 0.8)

    row.selTex = row:CreateTexture(nil, "BACKGROUND")
    row.selTex:SetAllPoints()
    row.selTex:SetColorTexture(0.2, 0.4, 0.8, 0.4)
    row.selTex:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.nameText:SetWidth(210); row.nameText:SetJustifyH("LEFT")

    row.actionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.actionText:SetPoint("LEFT", row.nameText, "RIGHT", 6, 0)
    row.actionText:SetWidth(90); row.actionText:SetJustifyH("CENTER")

    row.condText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.condText:SetPoint("LEFT", row.actionText, "RIGHT", 4, 0)
    row.condText:SetWidth(65); row.condText:SetJustifyH("CENTER")

    local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    xBtn:SetFrameLevel(row:GetFrameLevel() + 3)
    xBtn:SetSize(24, 22)
    xBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    xBtn:SetText("X")

    row.removeBtn = xBtn
    return row
end

-- ============================================================
-- Build the Buff Tracker section into the hub-provided panel
-- ============================================================
function Addon:BuildOptions(panel)
    if Addon._optionsBuilt then return end
    Addon._optionsBuilt = true

    local DS = _G.DaseekiSuite
    local MakeSlider           = DS.MakeSlider
    local MakeLabel            = DS.MakeLabel
    local MakeSectionHeader    = DS.MakeSectionHeader
    local MakeButton           = DS.MakeButton
    local MakeEditBox          = DS.MakeEditBox
    local MakeCheckbox         = DS.MakeCheckbox
    local MakeSimpleDropdown   = DS.MakeSimpleDropdown
    local MakeSeparator        = DS.MakeSeparator
    local MakeTableHeader      = DS.MakeTableHeader
    local AttachSearchDropdown = DS.AttachSearchDropdown
    local ShowNameInputDialog  = DS.ShowNameInputDialog
    local ShowTextDialog       = DS.ShowTextDialog

    Addon.optionsPanel = panel
    panel.profRows = {}; panel.selectedProfileName = nil

    -- =========================================================
    -- LEFT PANEL: Profiles
    -- =========================================================
    local LP_X = 14
    MakeSectionHeader(panel, "Profiles", LP_X, 12, 192)

    local profList = CreateFrame("Frame", nil, panel)
    profList:SetPoint("TOPLEFT", panel, "TOPLEFT", LP_X, -38)
    profList:SetWidth(192)
    profList:SetHeight(22)
    panel.profList = profList

    local function RefreshProfileList()
        local names = Addon:GetProfileNames()
        local active = Addon:GetActiveProfile()
        for _, row in ipairs(panel.profRows) do row:Hide() end
        for i, name in ipairs(names) do
            local row = panel.profRows[i]
            if not row then
                row = CreateFrame("Button", nil, profList); row:SetHeight(22)
                row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
                row.bg:SetColorTexture(0.2, 0.4, 0.8, 0)

                row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.cb:SetSize(18, 18)
                row.cb:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.cb:SetScript("OnClick", function(self)
                    local nm = self:GetParent()._name
                    Addon:SetActiveProfile(nm)
                    panel.selectedProfileName = nm
                    RefreshProfileList()
                    Addon:RefreshItemList(panel)
                end)

                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                local _f, _, _fl = row.label:GetFont()
                row.label:SetFont(_f, 11, _fl)
                row.label:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
                row.label:SetWidth(162); row.label:SetJustifyH("LEFT")
                row:SetScript("OnClick", function(self)
                    panel.selectedProfileName = self._name
                    for _, r in ipairs(panel.profRows) do r.bg:SetColorTexture(0.2, 0.4, 0.8, 0) end
                    self.bg:SetColorTexture(0.2, 0.4, 0.8, 0.5)
                    Addon:RefreshItemList(panel)
                end)
                panel.profRows[i] = row
            end
            row:SetWidth(192); row:ClearAllPoints()
            row:SetPoint("TOPLEFT", profList, "TOPLEFT", 0, -(i - 1) * 22)
            row._name = name
            local isActive = name == active
            row.cb:SetChecked(isActive)
            row.label:SetText(name:sub(1,1):upper() .. name:sub(2):lower())
            if isActive then panel.selectedProfileName = name end
            row:Show()
        end
        profList:SetHeight(#names * 22 + 4)
        for _, row in ipairs(panel.profRows) do
            local sel = row._name == panel.selectedProfileName
            row.bg:SetColorTexture(0.2, 0.4, 0.8, sel and 0.5 or 0)
        end
    end
    panel.RefreshProfileList = RefreshProfileList

    local BTN_Y = 268
    MakeButton(panel, "New",    LP_X,      BTN_Y,      92, 22, function()
        ShowNameInputDialog("New Profile", "", function(name)
            local ok, err = Addon:CreateProfile(name)
            if ok then RefreshProfileList(); panel.selectedProfileName = name
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end)
    MakeButton(panel, "Clone",  LP_X + 96, BTN_Y,      92, 22, function()
        local s = panel.selectedProfileName; if not s then return end
        ShowNameInputDialog("Clone Profile", s .. " Copy", function(name)
            local ok, err = Addon:CloneProfile(s, name)
            if ok then RefreshProfileList(); panel.selectedProfileName = name; Addon:RefreshItemList(panel)
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end)
    MakeButton(panel, "Rename", LP_X,      BTN_Y + 26, 92, 22, function()
        local s = panel.selectedProfileName; if not s then return end
        ShowNameInputDialog("Rename Profile", s, function(name)
            local ok, err = Addon:RenameProfile(s, name)
            if ok then panel.selectedProfileName = name; RefreshProfileList(); Addon:RefreshItemList(panel)
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end)
    MakeButton(panel, "Delete", LP_X + 96, BTN_Y + 26, 92, 22, function()
        local s = panel.selectedProfileName; if not s then return end
        local ok, err = Addon:DeleteProfile(s)
        if ok then panel.selectedProfileName = Addon:GetActiveProfile(); RefreshProfileList(); Addon:RefreshItemList(panel)
        else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
    end)
    MakeButton(panel, "Export", LP_X,      BTN_Y + 52, 92, 22, function()
        local s = panel.selectedProfileName; if not s then return end
        local str, err = Addon:ExportProfile(s)
        if str then ShowTextDialog("Export: " .. s, str, true)
        else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
    end)
    MakeButton(panel, "Import", LP_X + 96, BTN_Y + 52, 92, 22, function()
        ShowTextDialog("Import Profile (paste string below)", "", false, function(txt)
            local ok, result = Addon:ImportProfile(txt)
            if ok then
                print("|cff00ccff[DaseekiBT]|r Imported: " .. result)
                panel.selectedProfileName = result; RefreshProfileList(); Addon:RefreshItemList(panel)
            else print("|cffff4444[DaseekiBT]|r Import failed: " .. (result or "?")) end
        end)
    end)

    MakeSeparator(panel, 10, BTN_Y + 84, 196)

    -- =========================================================
    -- Frame Settings (left panel)
    -- =========================================================
    local FS_Y = BTN_Y + 94

    MakeSectionHeader(panel, "Frame Settings", LP_X, FS_Y, 192)

    MakeCheckbox(panel, "Lock",     LP_X,      FS_Y + 22,
        function() return Addon.db.settings.locked end,
        function(v) Addon.db.settings.locked = v; Addon:UpdateFrameLock() end)
    MakeCheckbox(panel, "Tooltips", LP_X + 70, FS_Y + 22,
        function() return Addon.db.settings.showTooltip end,
        function(v) Addon.db.settings.showTooltip = v end)

    MakeLabel(panel, "Show HUD:", nil, LP_X, FS_Y + 56)
    local condAlways, condRaid
    condAlways = MakeCheckbox(panel, "Always",  LP_X,      FS_Y + 68,
        function() return (Addon.db.settings.showCondition or "always") == "always" end,
        function(v)
            if v then
                Addon.db.settings.showCondition = "always"
                Addon:UpdateFrame()
                if condRaid then condRaid:SetChecked(false) end
            end
        end)
    condRaid   = MakeCheckbox(panel, "In Raid", LP_X + 84, FS_Y + 68,
        function() return Addon.db.settings.showCondition == "raid" end,
        function(v)
            if v then
                Addon.db.settings.showCondition = "raid"
                Addon:UpdateFrame()
                if condAlways then condAlways:SetChecked(false) end
            end
        end)

    local scaleSlider = MakeSlider(panel, LP_X + 14, FS_Y + 112, 160, "Scale",
        0.5, 2.0, 0.05,
        function() return Addon.db.settings.scale end,
        function(v) Addon.db.settings.scale = v; if Addon.mainFrame then Addon.mainFrame:SetScale(v) end end,
        function(v) return string.format("%.2f", v) end)

    MakeLabel(panel, "Spacing", nil, LP_X, FS_Y + 148)
    local spacingSlider = MakeSlider(panel, LP_X + 14, FS_Y + 162, 160, nil,
        0, 20, 1,
        function() return Addon.db.settings.iconSpacing end,
        function(v) Addon.db.settings.iconSpacing = v; Addon:UpdateFrame() end)
    MakeLabel(panel, "Per Row", nil, LP_X, FS_Y + 186)
    local perRowSlider = MakeSlider(panel, LP_X + 14, FS_Y + 200, 160, nil,
        1, 16, 1,
        function() return Addon.db.settings.iconsPerRow end,
        function(v) Addon.db.settings.iconsPerRow = v; Addon:UpdateFrame() end)

    MakeLabel(panel, "Anchor", nil, LP_X, FS_Y + 228)
    local anchorDD = MakeSimpleDropdown(panel, LP_X + 52, FS_Y + 224, 90, { "Right", "Left" },
        function(v)
            Addon:SetAnchor(v:upper())
        end)
    panel.anchorDD = anchorDD

    -- =========================================================
    -- Vertical separator (between left and right of the BT section)
    -- =========================================================
    local vSep = panel:CreateTexture(nil, "ARTWORK")
    vSep:SetColorTexture(0.3, 0.3, 0.3, 0.8); vSep:SetWidth(1)
    vSep:SetPoint("TOPLEFT",    panel, "TOPLEFT",    212, -6)
    vSep:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 212,  6)

    -- =========================================================
    -- RIGHT PANEL: Item list
    -- =========================================================
    local RP_X = 224

    do
        local hBuff = MakeTableHeader(panel, "Buff", 210, RP_X + 4, 16)
        hBuff:SetJustifyH("CENTER")
        local hAction = MakeTableHeader(panel, "Action",  90,  RP_X + 244, 16)
        hAction:SetJustifyH("CENTER")
        local hFaction = MakeTableHeader(panel, "Faction", 65,  RP_X + 338, 16)
        hFaction:SetJustifyH("CENTER")
    end
    MakeSeparator(panel, RP_X, 32, nil, 14)

    local itemSF = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    itemSF:SetHeight(MAX_ROWS * ROW_HEIGHT + 2)
    itemSF:SetPoint("TOPLEFT",  panel, "TOPLEFT",  RP_X, -40)
    itemSF:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30,  -40)

    local itemChild = CreateFrame("Frame", nil, itemSF)
    itemChild:SetSize(462, MAX_ROWS * ROW_HEIGHT)
    itemSF:SetScrollChild(itemChild)
    panel.itemChild = itemChild; panel.itemRows = {}; panel.selectedItemIndex = nil

    -- Forward declarations
    local PopulateEditor
    local AutoSave

    -- =========================================================
    -- Drag-to-reorder
    -- =========================================================
    local dragging = false
    local dragSourceIdx, dragDropLine = nil, nil
    local dragClickX, dragClickY = 0, 0

    local dropBar = CreateFrame("Frame", nil, panel)
    dropBar:SetHeight(2)
    dropBar:SetFrameLevel(itemChild:GetFrameLevel() + 10)
    local dropBarTex = dropBar:CreateTexture(nil, "OVERLAY")
    dropBarTex:SetAllPoints(); dropBarTex:SetColorTexture(1, 0.82, 0, 1)
    dropBar:Hide()

    local _dragTick = CreateFrame("Frame"); _dragTick:Hide()
    _dragTick:SetScript("OnUpdate", function()
        if not dragSourceIdx then _dragTick:Hide(); return end
        local mx, my = GetCursorPosition()
        local scale  = UIParent:GetEffectiveScale()
        mx, my = mx / scale, my / scale

        if not IsMouseButtonDown("LeftButton") then
            _dragTick:Hide(); dropBar:Hide()
            if dragging and dragDropLine then
                local profileName = panel.selectedProfileName
                local prof = profileName and Addon.db.profiles[profileName]
                if prof and prof.items then
                    local item = tremove(prof.items, dragSourceIdx)
                    local insertAt = dragDropLine
                    if insertAt > dragSourceIdx then insertAt = insertAt - 1 end
                    insertAt = math.max(1, math.min(#prof.items + 1, insertAt))
                    tinsert(prof.items, insertAt, item)
                    panel.selectedItemIndex = insertAt
                    Addon:RefreshItemList(panel)
                    Addon:UpdateFrame()
                end
            end
            dragging = false; dragSourceIdx = nil; dragDropLine = nil
            return
        end

        if not dragging then
            local dx, dy = mx - dragClickX, my - dragClickY
            if dx * dx + dy * dy < 25 then return end
            dragging = true
        end

        local childTop = itemChild:GetTop()
        if not childTop then return end
        local profileName = panel.selectedProfileName
        local prof = profileName and Addon.db.profiles[profileName]
        local n = prof and prof.items and #prof.items or 0
        if n == 0 then return end

        local relY = childTop - my
        local hRow = math.floor(relY / ROW_HEIGHT)
        local frac = relY - hRow * ROW_HEIGHT
        local line = frac < ROW_HEIGHT / 2 and (hRow + 1) or (hRow + 2)
        dragDropLine = math.max(1, math.min(n + 1, line))

        local barY = -(dragDropLine - 1) * ROW_HEIGHT
        dropBar:ClearAllPoints()
        dropBar:SetPoint("LEFT",  itemChild, "TOPLEFT",  0,   barY)
        dropBar:SetPoint("RIGHT", itemChild, "TOPRIGHT", -20, barY)
        dropBar:Show()
    end)

    -- =========================================================
    -- Inline editor (below the item list)
    -- =========================================================
    local IB_Y = 32 + MAX_ROWS * ROW_HEIGHT + 6
    local ED_Y = IB_Y + 30

    MakeSeparator(panel, RP_X, IB_Y - 4, nil, 14)

    local placeholder = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("TOPLEFT", panel, "TOPLEFT", RP_X + 10, -(ED_Y + 10))
    placeholder:SetText("|cff888888Click a row to edit, or Add Buff for a new entry|r")
    placeholder:Show()

    local ed = CreateFrame("Frame", nil, panel)
    ed:SetPoint("TOPLEFT",  panel, "TOPLEFT",  RP_X + 4, -ED_Y)
    ed:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20,      -ED_Y)
    ed:SetHeight(220)
    ed:Hide()

    ed._buffNames = {}

    -- -------- Row 1: Buff search + icon preview --------
    MakeLabel(ed, "Buff:", nil, 0, 4)
    ed.ebBuff = MakeEditBox(ed, 36, 0, 270)
    ed.ebBuff:SetMaxLetters(128)

    ed.buffIconTex = ed:CreateTexture(nil, "ARTWORK")
    ed.buffIconTex:SetSize(22, 22)
    ed.buffIconTex:SetPoint("LEFT", ed.ebBuff, "RIGHT", 6, 0)
    ed.buffIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ed.buffIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local UpdateEditorVisibility

    AttachSearchDropdown(ed.ebBuff, 300,
        function(q) return Addon:SearchBuffDB(q) end,
        "label",
        "buffName",
        function(result)
            if result.weaponSlot then
                ed._weaponSlot = result.weaponSlot
                ed._buffNames  = {}
                ed.ebBuff:SetText("[" .. result.weaponSlot .. " enchant]")
                ed.ebBuff:SetEnabled(false)
                ed.ebAltBuff:SetEnabled(false)
                ed.weaponSlotLabel:SetText("Weapon: " .. result.weaponSlot)
                ed.weaponSlotLabel:Show()
            else
                ed._weaponSlot = nil
                ed._buffNames[1] = result.buffName
                ed.ebBuff:SetEnabled(true)
                ed.ebAltBuff:SetEnabled(true)
                ed.weaponSlotLabel:Hide()
            end
            ed.buffIconTex:SetTexture(BuffIconGetter(result))
            if UpdateEditorVisibility then UpdateEditorVisibility() end
            if AutoSave then AutoSave() end
        end,
        BuffIconGetter
    )

    ed.ebBuff:SetScript("OnEnterPressed", function(self)
        local txt = strtrim(self:GetText())
        ed._buffNames[1] = txt ~= "" and txt or nil
        self:ClearFocus()
        if AutoSave then AutoSave() end
    end)

    -- -------- Row 2: Alt buff search + Add button + removable tags --------
    MakeLabel(ed, "Alt:", nil, 0, 32)
    ed.ebAltBuff = MakeEditBox(ed, 36, 28, 155)
    ed.ebAltBuff:SetMaxLetters(128)

    AttachSearchDropdown(ed.ebAltBuff, 200,
        function(q) return Addon:SearchBuffDB(q) end,
        "label", "buffName",
        nil,
        BuffIconGetter
    )

    local UpdateAltTags

    local function AddAltBuff()
        local name = strtrim(ed.ebAltBuff:GetText())
        if name == "" then return end
        for _, existing in ipairs(ed._buffNames) do
            if existing == name then ed.ebAltBuff:SetText(""); return end
        end
        if #ed._buffNames < 4 then
            ed._buffNames[#ed._buffNames + 1] = name
            ed.ebAltBuff:SetText("")
            if UpdateAltTags then UpdateAltTags() end
            if AutoSave then AutoSave() end
        end
    end

    MakeButton(ed, "Add Alt", 196, 30, 56, 20, AddAltBuff)
    ed.ebAltBuff:SetScript("OnEnterPressed", function(self) AddAltBuff(); self:ClearFocus() end)

    local TAG_W, TAG_GAP = 66, 4
    local TAG_X_START = 258
    ed.altTags = {}
    for i = 1, 3 do
        local tag = CreateFrame("Frame", nil, ed)
        tag:SetSize(TAG_W, 20)
        tag:SetPoint("TOPLEFT", ed, "TOPLEFT", TAG_X_START + (i - 1) * (TAG_W + TAG_GAP), -28)
        tag:SetFrameLevel(ed:GetFrameLevel() + 2)
        tag:Hide()

        local bg = tag:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.15, 0.25, 0.45, 0.85)

        tag.lbl = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tag.lbl:SetPoint("LEFT", tag, "LEFT", 4, 0)
        tag.lbl:SetWidth(TAG_W - 20); tag.lbl:SetJustifyH("LEFT")
        tag.lbl:SetWordWrap(false)

        tag.xBtn = CreateFrame("Button", nil, tag)
        tag.xBtn:SetSize(16, 20)
        tag.xBtn:SetPoint("RIGHT", tag, "RIGHT", 0, 0)
        tag.xBtn:SetFrameLevel(tag:GetFrameLevel() + 2)
        local xBg = tag.xBtn:CreateTexture(nil, "BACKGROUND")
        xBg:SetAllPoints(); xBg:SetColorTexture(0.45, 0.08, 0.08, 0.8)
        local xHl = tag.xBtn:CreateTexture(nil, "HIGHLIGHT")
        xHl:SetAllPoints(); xHl:SetColorTexture(0.8, 0.2, 0.2, 0.9)
        tag.xBtn:SetHighlightTexture(xHl)
        local xfs = tag.xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        xfs:SetAllPoints(); xfs:SetText("×"); xfs:SetJustifyH("CENTER"); xfs:SetJustifyV("MIDDLE")
        tag.xBtn:SetScript("OnClick", function()
            tremove(ed._buffNames, i + 1)
            if UpdateAltTags then UpdateAltTags() end
            if AutoSave then AutoSave() end
        end)

        ed.altTags[i] = tag
    end

    UpdateAltTags = function()
        for i = 1, 3 do
            local tag = ed.altTags[i]
            local buffName = ed._buffNames[i + 1]
            if buffName then
                tag.lbl:SetText(buffName)
                tag:Show()
            else
                tag:Hide()
            end
        end
    end

    -- -------- Row 3: Clickable + Action type --------
    ed.cbClickable = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    ed.cbClickable:SetSize(24, 24)
    ed.cbClickable:SetPoint("TOPLEFT", ed, "TOPLEFT", 0, -58)
    local clickLbl = ed.cbClickable:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clickLbl:SetPoint("LEFT", ed.cbClickable, "RIGHT", 2, 0); clickLbl:SetText("Clickable")

    ed.actionLabel = MakeLabel(ed, "Action:", nil, 112, 65)

    ed.rbItem = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    ed.rbItem:SetSize(20, 20)
    ed.rbItem:SetPoint("TOPLEFT", ed, "TOPLEFT", 158, -62)
    local rbItemLbl = ed.rbItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rbItemLbl:SetPoint("LEFT", ed.rbItem, "RIGHT", 2, 0); rbItemLbl:SetText("Item")

    ed.rbMacro = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    ed.rbMacro:SetSize(20, 20)
    ed.rbMacro:SetPoint("TOPLEFT", ed, "TOPLEFT", 210, -62)
    local rbMacroLbl = ed.rbMacro:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rbMacroLbl:SetPoint("LEFT", ed.rbMacro, "RIGHT", 2, 0); rbMacroLbl:SetText("Macro")

    ed.cbClickable:SetScript("OnClick", function()
        if UpdateEditorVisibility then UpdateEditorVisibility() end
        if AutoSave then AutoSave() end
    end)
    ed.rbItem:SetScript("OnClick", function(self)
        self:SetChecked(true)
        ed.rbMacro:SetChecked(false)
        if UpdateEditorVisibility then UpdateEditorVisibility() end
        if AutoSave then AutoSave() end
    end)
    ed.rbMacro:SetScript("OnClick", function(self)
        self:SetChecked(true)
        ed.rbItem:SetChecked(false)
        if UpdateEditorVisibility then UpdateEditorVisibility() end
        if AutoSave then AutoSave() end
    end)

    -- -------- Row 4: Item search --------
    ed.itemRow = CreateFrame("Frame", nil, ed)
    ed.itemRow:SetPoint("TOPLEFT",  ed, "TOPLEFT",  0, -92)
    ed.itemRow:SetPoint("TOPRIGHT", ed, "TOPRIGHT", 0, -92)
    ed.itemRow:SetHeight(24)

    MakeLabel(ed.itemRow, "Use Item:", nil, 0, 4)
    ed.ebItem = MakeEditBox(ed.itemRow, 64, 0, 280)
    ed.ebItem:SetMaxLetters(128)
    ed._selectedItemID = 0

    AttachSearchDropdown(ed.ebItem, 300,
        function(q) return Addon:SearchItemDB(q) end,
        "itemName", "itemName",
        function(result)
            ed._selectedItemID = result.itemID
            if AutoSave then AutoSave() end
        end,
        ItemIconGetter
    )

    -- -------- Row 4: Macro search --------
    ed.macroRow = CreateFrame("Frame", nil, ed)
    ed.macroRow:SetPoint("TOPLEFT",  ed, "TOPLEFT",  0, -92)
    ed.macroRow:SetPoint("TOPRIGHT", ed, "TOPRIGHT", 0, -92)
    ed.macroRow:SetHeight(24)

    MakeLabel(ed.macroRow, "Macro:", nil, 0, 4)
    ed.ebMacro = MakeEditBox(ed.macroRow, 64, 0, 280)
    ed.ebMacro:SetMaxLetters(64)

    AttachSearchDropdown(ed.ebMacro, 300,
        function(q) return Addon:SearchMacros(q) end,
        "macroName", "macroName",
        function() if AutoSave then AutoSave() end end,
        MacroIconGetter
    )

    ed.ebMacro:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if AutoSave then AutoSave() end
    end)

    -- -------- Row 5: Faction + weapon slot info + Cancel --------
    ed.factionRow = CreateFrame("Frame", nil, ed)
    ed.factionRow:SetPoint("TOPLEFT",  ed, "TOPLEFT",  0, -124)
    ed.factionRow:SetPoint("TOPRIGHT", ed, "TOPRIGHT", 0, -124)
    ed.factionRow:SetHeight(24)

    MakeLabel(ed.factionRow, "Faction:", nil, 0, 4)
    ed.factionDD = MakeSimpleDropdown(ed.factionRow, 58, 4, 110, { "Both", "Alliance", "Horde", "None" },
        function() if AutoSave then AutoSave() end end)

    ed.weaponSlotLabel = ed.factionRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ed.weaponSlotLabel:SetPoint("TOPLEFT", ed.factionRow, "TOPLEFT", 180, -4)
    ed.weaponSlotLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    ed.weaponSlotLabel:Hide()

    MakeButton(ed.factionRow, "Cancel", 320, 0, 72, 22, function()
        panel.selectedItemIndex = nil; ed._weaponSlot = nil
        ed:Hide(); placeholder:Show()
        for _, r in ipairs(panel.itemRows) do if r:IsShown() then r.selTex:Hide() end end
    end)

    -- -------- Visibility controller --------
    UpdateEditorVisibility = function()
        local clickable = ed.cbClickable:GetChecked()
        local isWeapon  = ed._weaponSlot and ed._weaponSlot ~= ""

        ed.actionLabel:SetShown(clickable)
        ed.rbItem:SetShown(clickable)
        ed.rbMacro:SetShown(clickable)

        local showItem  = clickable and ed.rbItem:GetChecked()
        local showMacro = clickable and ed.rbMacro:GetChecked()
        ed.itemRow:SetShown(showItem)
        ed.macroRow:SetShown(showMacro)

        ed.weaponSlotLabel:SetShown(isWeapon)
    end

    -- -------- AutoSave --------
    AutoSave = function()
        local profileName = panel.selectedProfileName
        local idx = panel.selectedItemIndex
        if not profileName or not idx then return end

        local primaryText = strtrim(ed.ebBuff:GetText())
        if primaryText == "" or primaryText:sub(1, 1) == "[" then primaryText = nil end
        ed._buffNames[1] = primaryText

        local buffNames = {}
        for _, n in ipairs(ed._buffNames) do
            if n and n ~= "" then buffNames[#buffNames + 1] = n end
        end

        local primaryBuff = buffNames[1]
        local displayName
        if ed._weaponSlot and ed._weaponSlot ~= "" then
            displayName = ed._weaponSlot == "mainhand" and "Mainhand Enchant" or "Offhand Enchant"
        else
            displayName = primaryBuff
            if primaryBuff and Addon.BuffDB and Addon.BuffDB[primaryBuff] then
                displayName = Addon.BuffDB[primaryBuff].label or primaryBuff
            end
            if #buffNames > 1 then
                displayName = (displayName or "") .. " / ..."
            end
        end

        local clickable  = ed.cbClickable:GetChecked() and true or false
        local actionType = ed.rbMacro:GetChecked() and "macro" or "item"

        local itemID = 0
        if actionType == "item" then itemID = ed._selectedItemID or 0 end

        local macroName = nil
        if actionType == "macro" then
            local m = strtrim(ed.ebMacro:GetText())
            macroName = m ~= "" and m or nil
        end

        local factionSel = ed.factionDD:GetValue()
        local faction = (factionSel == "Both") and "" or (factionSel or "")

        local def = {
            buffNames   = buffNames,
            buffName    = nil,
            displayName = displayName,
            clickable   = clickable,
            actionType  = actionType,
            itemID      = itemID,
            macroName   = macroName,
            conditions  = { faction = faction ~= "" and faction or nil },
            enabled     = true,
            weaponSlot  = ed._weaponSlot,
            cachedIcon  = nil,
        }

        Addon:UpdateItemInProfile(profileName, idx, def)
        Addon:RefreshItemList(panel)
        Addon:UpdateFrame()
    end

    -- -------- PopulateEditor --------
    PopulateEditor = function(item, idx)
        if not item then ed:Hide(); placeholder:Show(); return end
        placeholder:Hide(); ed:Show()

        ed._weaponSlot     = item.weaponSlot
        ed._selectedItemID = item.itemID or 0
        panel.selectedItemIndex = idx

        local names = Addon:GetBuffNames(item)
        ed._buffNames = {}
        for i, n in ipairs(names) do ed._buffNames[i] = n end

        if item.weaponSlot then
            ed.ebBuff:SetText("[" .. item.weaponSlot .. " enchant]")
            ed.ebBuff:SetEnabled(false)
            ed.ebAltBuff:SetEnabled(false)
            ed.weaponSlotLabel:SetText("Weapon: " .. item.weaponSlot)
        else
            ed.ebBuff:SetText(ed._buffNames[1] or "")
            ed.ebBuff:SetEnabled(true)
            ed.ebAltBuff:SetEnabled(true)
            ed.weaponSlotLabel:Hide()
        end
        ed.ebAltBuff:SetText("")

        UpdateAltTags()

        ed.buffIconTex:SetTexture(Addon:GetBuffIcon(item))

        ed.cbClickable:SetChecked(item.clickable ~= false)

        local isMacro = item.actionType == "macro"
        ed.rbItem:SetChecked(not isMacro)
        ed.rbMacro:SetChecked(isMacro)

        if item.itemID and item.itemID > 0 then
            local name = Addon:GetItemName(item.itemID)
            ed.ebItem:SetText(name or tostring(item.itemID))
        else
            ed.ebItem:SetText("")
        end

        ed.ebMacro:SetText(item.macroName or "")

        ed.factionDD:SetValue((item.conditions and item.conditions.faction) or "Both")

        UpdateEditorVisibility()
    end

    -- =========================================================
    -- Action buttons
    -- =========================================================
    MakeButton(panel, "Add Buff", RP_X, IB_Y, 80, 22, function()
        local sel = panel.selectedProfileName
        if not sel then print("[DaseekiBT] Select a profile first"); return end
        local blank = {
            buffNames = {}, displayName = "New Entry",
            clickable = true, actionType = "item", itemID = 0,
            enabled = true, conditions = {}, weaponSlot = nil,
        }
        Addon:AddItemToProfile(sel, blank)
        Addon:RefreshItemList(panel)
        local prof = Addon.db.profiles[sel]
        local newIdx = prof and prof.items and #prof.items or 1
        panel.selectedItemIndex = newIdx
        if panel.itemRows[newIdx] then panel.itemRows[newIdx].selTex:Show() end
        PopulateEditor(blank, newIdx)
        ed.ebBuff:SetText(""); ed.ebBuff:SetFocus()
    end)

    -- =========================================================
    -- Item list refresh
    -- =========================================================
    local function SelectItemRow(idx)
        panel.selectedItemIndex = idx
        for i, row in ipairs(panel.itemRows) do
            if row:IsShown() then row.selTex:SetShown(i == idx) end
        end
    end

    function Addon:RefreshItemList(w)
        w = w or panel
        local profileName = w.selectedProfileName
        local profile = profileName and Addon.db.profiles[profileName]
        local items = (profile and profile.items) or {}

        for _, row in ipairs(w.itemRows) do row:Hide() end

        for i, item in ipairs(items) do
            local row = w.itemRows[i]
            if not row then
                row = BuildItemRow(w.itemChild, i); w.itemRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", w.itemChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row:Show()

            local ci = i
            row:SetScript("OnClick", function()
                SelectItemRow(ci)
                local p  = w.selectedProfileName
                local it = p and Addon.db.profiles[p] and Addon.db.profiles[p].items and Addon.db.profiles[p].items[ci]
                PopulateEditor(it, ci)
            end)
            row:SetScript("OnMouseDown", function(self, btn)
                if btn ~= "LeftButton" then return end
                dragSourceIdx = ci; dragging = false
                dragClickX, dragClickY = GetCursorPosition()
                local sc = UIParent:GetEffectiveScale()
                dragClickX, dragClickY = dragClickX / sc, dragClickY / sc
                _dragTick:Show()
            end)

            row.icon:SetTexture(Addon:GetBuffIcon(item))

            local primaryName = Addon:GetBuffNames(item)[1]
            local displayName = item.displayName or primaryName or item.name or "Unnamed"
            if item.weaponSlot then
                local slotLabel = item.weaponSlot == "mainhand" and "Mainhand Enchant" or "Offhand Enchant"
                displayName = slotLabel
            end
            row.nameText:SetText(displayName)

            if item.weaponSlot then
                if not item.clickable then
                    row.actionText:SetText("Passive")
                elseif item.actionType == "macro" then
                    row.actionText:SetText("Macro")
                else
                    row.actionText:SetText("Item")
                end
            elseif not item.clickable then
                row.actionText:SetText("passive")
            elseif item.actionType == "macro" then
                row.actionText:SetText("Macro")
            else
                row.actionText:SetText("Item")
            end

            local cond = item.conditions
            local fv = cond and cond.faction
            row.condText:SetText((fv and fv ~= "") and fv or "Both")

            local cp, ci2 = profileName, i
            row.removeBtn:SetScript("OnClick", function()
                if w.selectedItemIndex == ci2 then
                    w.selectedItemIndex = nil; ed:Hide(); placeholder:Show()
                end
                Addon:RemoveItemFromProfile(cp, ci2)
                Addon:RefreshItemList(w); Addon:UpdateFrame()
            end)
        end

        w.itemChild:SetHeight(math.max(#items * ROW_HEIGHT, MAX_ROWS * ROW_HEIGHT))
        if w.selectedItemIndex and w.selectedItemIndex > #items then
            w.selectedItemIndex = nil; ed:Hide(); placeholder:Show()
        end
        SelectItemRow(w.selectedItemIndex)
    end
end

-- ============================================================
-- Refresh: sync controls + lists (called each time the section is shown)
-- ============================================================
function Addon:RefreshOptionsPanel()
    local panel = Addon.optionsPanel; if not panel then return end
    if panel.RefreshProfileList then panel:RefreshProfileList() end
    if Addon.RefreshItemList then Addon:RefreshItemList(panel) end
    if panel.anchorDD then
        local anchor = Addon.db.settings.anchor or "RIGHT"
        panel.anchorDD:SetValue(anchor:sub(1,1) .. anchor:sub(2):lower())
    end
    -- Pre-cache item icons for all BuffDB entries so they appear without delay
    if Addon.BuffDB then
        for _, data in pairs(Addon.BuffDB) do
            if data.itemID then GetItemInfo(data.itemID) end
        end
    end
end

-- ============================================================
-- Register the Buff Tracker section with the Daseeki Core hub
-- ============================================================
function Addon:RegisterOptions()
    if not _G.DaseekiSuite then return end
    DaseekiSuite:RegisterAddon({
        id    = "bufftracker",
        title = "Buff Tracker",
        icon  = "Interface\\Icons\\INV_Potion_32",  -- Elixir of the Mongoose
        order = 30,
        build   = function(panel) Addon:BuildOptions(panel) end,
        refresh = function() Addon:RefreshOptionsPanel() end,
    })
end
