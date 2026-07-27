local _, Addon = ...

-- ============================================================
-- Buff Tracker options — migrated to the DaseekiUI flow API
-- (Daseeki-Core commit 1d7d942). One build(flow) lays out three
-- sections in a single scroll+clip pane at a computed running
-- cursor: Profiles (List + CRUD), Frame Settings, and Tracked
-- Buffs (custom scroll list + EditorCard).
--
-- The old panel hand-placed two absolute-offset columns and, in the
-- inline editor, stacked the item-search and macro-search rows at the
-- SAME y=-92 toggled by visibility (overlap-by-design). That pattern is
-- gone: a SegmentedChoice (Item / Macro) now drives which field is
-- visible, and the field rows collapse to zero height with no leftover
-- gap via the flow's condRow re-layout (matching Armory's approach).
--
-- No caller-supplied y-offsets, no hardcoded colors (theme tokens only).
-- Feature set and SavedVariables schema are unchanged from v2.0.0
-- (profiles CRUD, tracked-buff list with drag-to-reorder, add/edit/
-- remove, spell-ID identification fields, export/import v4, frame
-- settings). options.lua is the only file changed.
-- ============================================================

-- ── Icon getters for each search type (Buff Tracker specific) ──────────────────
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

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ── Named layout metrics (single source; no magic literals in the code below) ──
local ICON_SZ        = 20   -- list-row + preview icon size
local PREV_SZ        = 22   -- buff icon preview beside the search box
local BUFF_ROW_H     = 26   -- tracked-buff list row height
local BUFFLIST_H     = 260  -- tracked-buff list viewport height
local LIST_INSET     = 4    -- scroll viewport inset
local EDGE           = 2    -- row inner edge inset
local GAP            = 4    -- small horizontal gap
local ACT_W          = 64   -- action column width
local FACT_W         = 56   -- faction column width
local REMOVE_W       = 22   -- remove button width
local PROFILE_LIST_H = 140  -- profile List viewport height
local LBL_BUFF_W     = 40   -- "Buff:"/"Alt:" label column width
local LBL_USE_W      = 64   -- "Use Item:"/"Macro:" label width
local LBL_FACT_W     = 58   -- "Faction:" label width
local TAG_W          = 84   -- alt-buff tag width
local TAG_H          = 20   -- alt-buff tag height
local TAG_GAP        = 4    -- gap between alt-buff tags

local function rowGap() return (DaseekiUI.Token and DaseekiUI.Token("rowGap")) or 10 end

-- Add a caller-built custom frame to a flow's pane as one full-width block.
local function addBlock(flow, frame, arrange, topGap)
    flow.pane:AddBlock(frame, arrange, topGap or rowGap(), 0)
end

-- Append a caller-built widget onto an existing row (Armory's pattern for custom
-- leading/trailing widgets). `pin == "right"` right-aligns it.
local function addCustom(row, w, pin)
    row._items[#row._items + 1] = { w = w, pin = pin }
    return w
end

-- A flow row that collapses to zero height (and swallows its top gap) when not
-- applicable, so a hidden editor field leaves NO leftover gap. This is what kills
-- the old overlap-by-design pattern: item/macro rows are just condRows toggled by
-- the SegmentedChoice, reflowed by pane:Layout() — never stacked at one y.
local function condRow(flow)
    local row = flow:AddRow()
    local blk = flow.pane.blocks[#flow.pane.blocks]
    row._blk, row._baseGap = blk, blk.topGap
    local origArrange = blk.arrange
    blk.arrange = function(width)
        if row._applicable == false then row:Hide(); return 0 end
        row:Show(); return origArrange(width)
    end
    function row:SetApplicable(on)
        self._applicable = on and true or false
        self._blk.topGap = self._applicable and self._baseGap or 0
    end
    return row
end

-- Same collapse behavior for a caller-built custom block (used by the alt-tag bar).
local function condBlock(flow, frame, arrange, topGap)
    flow.pane:AddBlock(frame, function(width)
        if frame._applicable == false then frame:Hide(); return 0 end
        frame:Show(); return arrange(width)
    end, topGap or rowGap(), 0)
    local blk = flow.pane.blocks[#flow.pane.blocks]
    blk._baseGap = blk.topGap
    function frame:SetApplicable(on)
        self._applicable = on and true or false
        blk.topGap = self._applicable and blk._baseGap or 0
    end
    return frame
end

-- Module state (the flow's build runs once; helpers read this).
local bt = { itemRows = {}, selectedProfileName = nil, selectedItemIndex = nil }
-- Editor field references + working state (mirrors the old `ed` table).
local E = { _buffNames = {} }

-- ============================================================
-- Tracked-buff list (custom token-skinned scroll block)
-- Columns: icon | name (truncate+tooltip) | action | faction | remove.
-- Drag-to-reorder by cursor-position polling — same technique the old
-- panel and the merged Armory migration use.
-- ============================================================
local function BuildBuffList(flow)
    local UI = DaseekiUI
    local host = UI.FlatFrame(flow.pane.child, "inset", "border")
    host.uiHeight, host._fillWidth = BUFFLIST_H, true

    local scroll = CreateFrame("ScrollFrame", "DaseekiBTBuffScroll", host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", LIST_INSET, -LIST_INSET)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur  = self:GetVerticalScroll()
        local maxs = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - delta * 24)))
    end)
    bt.listChild, bt.listScroll = child, scroll

    -- Drop indicator + drag ticker (cursor-position polling).
    local dropBar = child:CreateTexture(nil, "OVERLAY")
    dropBar:SetHeight(2); dropBar:Hide()
    UI.Skin(dropBar, function(self) self:SetColorTexture(UI.Color("accent")) end)
    bt.dropBar = dropBar

    local dragTick = CreateFrame("Frame"); dragTick:Hide()
    bt._dragTick = dragTick
    dragTick:SetScript("OnUpdate", function()
        if not bt._dragSourceIdx then dragTick:Hide(); return end
        local mx, my = GetCursorPosition()
        local scale  = UIParent:GetEffectiveScale()
        mx, my = mx / scale, my / scale

        if not IsMouseButtonDown("LeftButton") then
            dragTick:Hide(); dropBar:Hide()
            if bt._dragging and bt._dragDropLine then
                local profileName = bt.selectedProfileName
                local prof = profileName and Addon.db.profiles[profileName]
                if prof and prof.items then
                    local item = tremove(prof.items, bt._dragSourceIdx)
                    local insertAt = bt._dragDropLine
                    if insertAt > bt._dragSourceIdx then insertAt = insertAt - 1 end
                    insertAt = math.max(1, math.min(#prof.items + 1, insertAt))
                    tinsert(prof.items, insertAt, item)
                    bt.selectedItemIndex = insertAt
                    Addon:RefreshItemList()
                    Addon:UpdateFrame()
                end
            end
            bt._dragging, bt._dragSourceIdx, bt._dragDropLine = false, nil, nil
            return
        end

        if not bt._dragging then
            local dx, dy = mx - (bt._dragClickX or mx), my - (bt._dragClickY or my)
            if dx * dx + dy * dy < 25 then return end
            bt._dragging = true
        end

        local childTop = child:GetTop()
        if not childTop then return end
        local profileName = bt.selectedProfileName
        local prof = profileName and Addon.db.profiles[profileName]
        local n = prof and prof.items and #prof.items or 0
        if n == 0 then return end

        local relY = childTop - my
        local hRow = math.floor(relY / BUFF_ROW_H)
        local frac = relY - hRow * BUFF_ROW_H
        local line = (frac < BUFF_ROW_H / 2) and (hRow + 1) or (hRow + 2)
        bt._dragDropLine = math.max(1, math.min(n + 1, line))

        dropBar:ClearAllPoints()
        dropBar:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -(bt._dragDropLine - 1) * BUFF_ROW_H)
        dropBar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(bt._dragDropLine - 1) * BUFF_ROW_H)
        dropBar:Show()
    end)

    host.arrange = function(width)
        host:SetWidth(width)
        child:SetWidth(math.max(1, width - 2 * LIST_INSET))
        return BUFFLIST_H
    end
    return host
end

-- Build a single tracked-buff row (relative anchoring so columns reflow with the
-- pane width; the name truncates and shows a tooltip when it overflows).
local function BuildBuffRow(i)
    local UI = DaseekiUI
    local row = CreateFrame("Button", nil, bt.listChild)
    row:SetHeight(BUFF_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints(); row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    UI.Skin(hl, function(self) self:SetColorTexture(UI.Color("accent", 0.10)) end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SZ, ICON_SZ)
    row.icon:SetPoint("LEFT", row, "LEFT", GAP, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.removeBtn = UI.MakeButton(row, { text = "X", width = REMOVE_W, height = 20, variant = "danger" })
    row.removeBtn:ClearAllPoints()
    row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -EDGE, 0)

    row.condText = row:CreateFontString(nil, "OVERLAY")
    row.condText:SetFontObject(UI.fonts.small)
    row.condText:SetWidth(FACT_W); row.condText:SetJustifyH("CENTER")
    row.condText:SetPoint("RIGHT", row.removeBtn, "LEFT", -GAP, 0)

    row.actionText = row:CreateFontString(nil, "OVERLAY")
    row.actionText:SetFontObject(UI.fonts.small)
    row.actionText:SetWidth(ACT_W); row.actionText:SetJustifyH("CENTER")
    row.actionText:SetPoint("RIGHT", row.condText, "LEFT", -GAP, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY")
    row.nameText:SetFontObject(UI.fonts.body)
    row.nameText:SetJustifyH("LEFT"); row.nameText:SetWordWrap(false)
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", GAP, 0)
    row.nameText:SetPoint("RIGHT", row.actionText, "LEFT", -GAP, 0)

    UI.Skin(row, function()
        row.bg:SetColorTexture(UI.Color(i % 2 == 0 and "raised" or "panel", 0.7))
        row.sel:SetColorTexture(UI.Color("accent", 0.28))
        row.condText:SetTextColor(UI.Color("muted"))
        row.actionText:SetTextColor(UI.Color("muted"))
    end)

    -- Truncate-with-tooltip: only when the name overflows its column.
    row:SetScript("OnEnter", function(self)
        if self._fullName and self.nameText:GetStringWidth() > self.nameText:GetWidth() + 1 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._fullName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- ============================================================
-- Buff editor (EditorCard) — SegmentedChoice(Item/Macro) drives which
-- action field is visible via condRow collapse (no overlap, no gap).
-- ============================================================
local PopulateEditor, AutoSave, updateEditorVis, updateAltTags

-- Text-search EditBox on a row, with the auto-refresh (OnShow) clobber disabled so
-- the field text is managed manually. Returns the frame + its raw EditBox.
local function searchBox(row, width, maxLetters)
    local f = row:EditBox({ width = width, get = function() return "" end })
    f:SetScript("OnShow", nil)
    f.editBox:SetMaxLetters(maxLetters or 128)
    return f, f.editBox
end

local function BuildEditor(flow)
    local UI = DaseekiUI
    local DS = _G.DaseekiSuite
    local AttachSearchDropdown = DS.AttachSearchDropdown

    local card = UI.MakeEditorCard(flow.pane.child, { title = "Buff Editor" })
    bt.editorCard = card
    local cflow = card.flow

    -- Card participates as a dynamic-height block: it lays out its inner flow, then
    -- sizes itself to the content so mode-switch collapses reflow the outer pane.
    card.arrange = function(width)
        card:SetWidth(width)
        card.pane:Layout()
        local h = card.pane.child:GetHeight() or 0
        if h < 2 then
            if not card._deferred then
                card._deferred = true
                C_Timer.After(0, function()
                    card._deferred = false
                    if bt.pane and bt.pane.Layout then bt.pane:Layout() end
                end)
            end
            h = card._lastH or 44
        else
            card._lastH = h
        end
        card:SetHeight(h)
        return h
    end

    -- Empty-state hint (shown when no buff is selected).
    E.hintRow = condRow(cflow)
    local hint = E.hintRow:Label("Click a buff row to edit, or Add Buff for a new entry.", { muted = true })
    hint.uiWidth = 420; hint:SetWidth(420)

    -- Row 1: Buff search + icon preview (pinned right).
    E.buffRow = condRow(cflow)
    local bl = E.buffRow:Label("Buff:"); bl.uiWidth = LBL_BUFF_W; bl:SetWidth(LBL_BUFF_W)
    local _, ebBuff = searchBox(E.buffRow, 220, 128); E.ebBuff = ebBuff
    local prev = CreateFrame("Frame", nil, E.buffRow)
    prev:SetSize(PREV_SZ, PREV_SZ)
    prev.uiWidth, prev.uiHeight = PREV_SZ, PREV_SZ
    E.prevTex = prev:CreateTexture(nil, "ARTWORK")
    E.prevTex:SetAllPoints(); E.prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    E.prevTex:SetTexture(QUESTION)
    addCustom(E.buffRow, prev, "right")

    AttachSearchDropdown(E.ebBuff, 300,
        function(q) return Addon:SearchBuffDB(q) end, "label", "buffName",
        function(result)
            if result.weaponSlot then
                E._weaponSlot, E._spellID, E._buffNames = result.weaponSlot, nil, {}
                E.ebBuff:SetText("[" .. result.weaponSlot .. " enchant]")
                E.ebBuff:SetEnabled(false); E.ebAltBuff:SetEnabled(false)
                E.weaponLabel._label:SetText("Weapon: " .. result.weaponSlot)
            elseif result.bySpell then
                -- Spell-ID-identified buff (e.g. Mageblood vs Nightfin): lock the
                -- field to the label; matching is by spell ID, not the typed name.
                E._weaponSlot, E._spellID, E._displayLabel = nil, result.spellID, result.label
                E._buffNames = { result.buffName }
                E.ebBuff:SetText(result.label)
                E.ebBuff:SetEnabled(false); E.ebAltBuff:SetEnabled(false)
            else
                E._weaponSlot, E._spellID = nil, nil
                E._buffNames[1] = result.buffName
                E.ebBuff:SetEnabled(true); E.ebAltBuff:SetEnabled(true)
            end
            E.prevTex:SetTexture(BuffIconGetter(result))
            updateEditorVis()
            AutoSave()
        end,
        BuffIconGetter)

    E.ebBuff:SetScript("OnEnterPressed", function(self)
        local txt = strtrim(self:GetText())
        E._buffNames[1] = txt ~= "" and txt or nil
        self:ClearFocus()
        AutoSave()
    end)

    -- Row 2: Alt buff search + Add Alt button.
    E.altRow = condRow(cflow)
    local al = E.altRow:Label("Alt:"); al.uiWidth = LBL_BUFF_W; al:SetWidth(LBL_BUFF_W)
    local _, ebAlt = searchBox(E.altRow, 180, 128); E.ebAltBuff = ebAlt

    local function AddAltBuff()
        local name = strtrim(E.ebAltBuff:GetText())
        if name == "" then return end
        for _, existing in ipairs(E._buffNames) do
            if existing == name then E.ebAltBuff:SetText(""); return end
        end
        if #E._buffNames < 4 then
            E._buffNames[#E._buffNames + 1] = name
            E.ebAltBuff:SetText("")
            updateEditorVis()
            AutoSave()
        end
    end
    E.altRow:Button({ text = "Add Alt", width = 66, pin = "right", onClick = AddAltBuff })

    AttachSearchDropdown(E.ebAltBuff, 200,
        function(q) return Addon:SearchBuffDB(q) end, "label", "buffName",
        nil, BuffIconGetter)
    E.ebAltBuff:SetScript("OnEnterPressed", function(self) AddAltBuff(); self:ClearFocus() end)

    -- Row 3: removable alt-buff tags (buffNames[2..4]).
    local tagHost = CreateFrame("Frame", nil, cflow.pane.child)
    tagHost._fillWidth = true
    E.altTags = {}
    for i = 1, 3 do
        local tag = UI.FlatFrame(tagHost, "raised", "borderLite")
        tag:SetSize(TAG_W, TAG_H)
        tag:Hide()
        tag.lbl = tag:CreateFontString(nil, "OVERLAY")
        tag.lbl:SetFontObject(UI.fonts.small)
        tag.lbl:SetPoint("LEFT", tag, "LEFT", GAP, 0)
        tag.lbl:SetWidth(TAG_W - REMOVE_W - GAP); tag.lbl:SetJustifyH("LEFT")
        tag.lbl:SetWordWrap(false)
        tag.xBtn = UI.MakeButton(tag, { text = "x", width = 16, height = TAG_H, variant = "danger" })
        tag.xBtn:ClearAllPoints()
        tag.xBtn:SetPoint("RIGHT", tag, "RIGHT", 0, 0)
        tag.xBtn:SetScript("OnClick", function()
            tremove(E._buffNames, i + 1)
            updateEditorVis()
            AutoSave()
        end)
        E.altTags[i] = tag
    end
    tagHost.arrange = function(width)
        tagHost:SetWidth(width)
        local x = 0
        for i = 1, 3 do
            local tag = E.altTags[i]
            if E._buffNames[i + 1] then
                tag:ClearAllPoints()
                tag:SetPoint("TOPLEFT", tagHost, "TOPLEFT", x, 0)
                tag:Show()
                x = x + TAG_W + TAG_GAP
            else
                tag:Hide()
            end
        end
        return TAG_H
    end
    E.altTagsHost = condBlock(cflow, tagHost, tagHost.arrange)

    updateAltTags = function()
        for i = 1, 3 do
            local tag = E.altTags[i]
            local name = E._buffNames[i + 1]
            if name then tag.lbl:SetText(name) end
        end
    end

    -- Row 4: Clickable toggle.
    E.clickRow = condRow(cflow)
    E.cbClickable = E.clickRow:Checkbox({
        label = "Clickable",
        get = function() return E._clickable end,
        set = function(v) E._clickable = v and true or false; updateEditorVis(); AutoSave() end,
    })

    -- Row 5: Action type — SegmentedChoice replaces the two overlapping radio rows.
    E.actionRow = condRow(cflow)
    local actLbl = E.actionRow:Label("Action:"); actLbl.uiWidth = LBL_USE_W; actLbl:SetWidth(LBL_USE_W)
    E.seg = E.actionRow:SegmentedChoice({
        choices = { { value = "item", text = "Item" }, { value = "macro", text = "Macro" } },
        get = function() return E._actionType or "item" end,
        set = function(v) E._actionType = v; updateEditorVis(); AutoSave() end,
    })

    -- Row 6a: Item search (visible only when clickable + Item mode).
    E.itemRow = condRow(cflow)
    local il = E.itemRow:Label("Use Item:"); il.uiWidth = LBL_USE_W; il:SetWidth(LBL_USE_W)
    local _, ebItem = searchBox(E.itemRow, 280, 128); E.ebItem = ebItem
    E._selectedItemID = 0
    AttachSearchDropdown(E.ebItem, 300,
        function(q) return Addon:SearchItemDB(q) end, "itemName", "itemName",
        function(result) E._selectedItemID = result.itemID; AutoSave() end,
        ItemIconGetter)

    -- Row 6b: Macro search (visible only when clickable + Macro mode).
    E.macroRow = condRow(cflow)
    local mlab = E.macroRow:Label("Macro:"); mlab.uiWidth = LBL_USE_W; mlab:SetWidth(LBL_USE_W)
    local _, ebMacro = searchBox(E.macroRow, 280, 64); E.ebMacro = ebMacro
    AttachSearchDropdown(E.ebMacro, 300,
        function(q) return Addon:SearchMacros(q) end, "macroName", "macroName",
        function() AutoSave() end, MacroIconGetter)
    E.ebMacro:SetScript("OnEnterPressed", function(self) self:ClearFocus(); AutoSave() end)

    -- Row 7: Faction + Cancel.
    E.factionRow = condRow(cflow)
    local fl = E.factionRow:Label("Faction:"); fl.uiWidth = LBL_FACT_W; fl:SetWidth(LBL_FACT_W)
    E.factionDD = E.factionRow:Dropdown({
        width = 110, choices = { "Both", "Alliance", "Horde", "None" },
        get = function() return E._faction or "Both" end,
        set = function(v) E._faction = v; AutoSave() end,
    })
    E.factionRow:Button({ text = "Cancel", width = 72, pin = "right", onClick = function()
        bt.selectedItemIndex = nil
        E._weaponSlot, E._spellID = nil, nil
        for _, r in ipairs(bt.itemRows) do if r:IsShown() then r.sel:Hide() end end
        updateEditorVis()
    end })

    -- Row 8: weapon-slot info (weapon-enchant entries only).
    E.weaponRow = condRow(cflow)
    E.weaponLabel = E.weaponRow:Label("", { muted = true })
    E.weaponLabel.uiWidth = 240; E.weaponLabel:SetWidth(240)

    addBlock(flow, card, card.arrange, rowGap())
end

-- Reflow the editor: inner pane applies condRow collapses, outer pane re-measures.
local function relayoutEditor()
    if bt.editorCard then bt.editorCard:Relayout() end
    if bt.pane then bt.pane:Layout() end
end

updateEditorVis = function()
    local hasSel    = bt.selectedItemIndex ~= nil
    local clickable = E._clickable and true or false
    local isWeapon  = E._weaponSlot and E._weaponSlot ~= ""
    local mode      = E._actionType or "item"

    E.hintRow:SetApplicable(not hasSel)
    E.buffRow:SetApplicable(hasSel)
    E.altRow:SetApplicable(hasSel)
    E.altTagsHost:SetApplicable(hasSel and #E._buffNames > 1)
    E.clickRow:SetApplicable(hasSel)
    E.actionRow:SetApplicable(hasSel and clickable)
    E.itemRow:SetApplicable(hasSel and clickable and mode == "item")
    E.macroRow:SetApplicable(hasSel and clickable and mode == "macro")
    E.factionRow:SetApplicable(hasSel)
    E.weaponRow:SetApplicable(hasSel and isWeapon)

    if updateAltTags then updateAltTags() end
    relayoutEditor()
end

AutoSave = function()
    local profileName = bt.selectedProfileName
    local idx = bt.selectedItemIndex
    if not profileName or not idx then return end

    -- The buff field is free-text only for name-matched entries. Weapon-enchant and
    -- spell-ID entries have a locked, label-showing field, so don't derive the
    -- primary aura name from the box text for them.
    if not E._weaponSlot and not E._spellID then
        local primaryText = strtrim(E.ebBuff:GetText())
        if primaryText == "" or primaryText:sub(1, 1) == "[" then primaryText = nil end
        E._buffNames[1] = primaryText
    end

    local buffNames = {}
    for _, n in ipairs(E._buffNames) do
        if n and n ~= "" then buffNames[#buffNames + 1] = n end
    end

    local primaryBuff = buffNames[1]
    local displayName
    if E._weaponSlot and E._weaponSlot ~= "" then
        displayName = E._weaponSlot == "mainhand" and "Mainhand Enchant" or "Offhand Enchant"
    elseif E._spellID then
        displayName = E._displayLabel or primaryBuff
    else
        displayName = primaryBuff
        if primaryBuff and Addon.BuffDB and Addon.BuffDB[primaryBuff] then
            displayName = Addon.BuffDB[primaryBuff].label or primaryBuff
        end
        if #buffNames > 1 then displayName = (displayName or "") .. " / ..." end
    end

    local clickable  = E._clickable and true or false
    local actionType = E._actionType == "macro" and "macro" or "item"

    local itemID = 0
    if actionType == "item" then itemID = E._selectedItemID or 0 end

    local macroName = nil
    if actionType == "macro" then
        local m = strtrim(E.ebMacro:GetText())
        macroName = m ~= "" and m or nil
    end

    local factionSel = E._faction
    local faction = (factionSel == "Both") and "" or (factionSel or "")

    local def = {
        buffNames   = buffNames,
        buffName    = nil,
        spellID     = E._spellID,
        displayName = displayName,
        clickable   = clickable,
        actionType  = actionType,
        itemID      = itemID,
        macroName   = macroName,
        conditions  = { faction = faction ~= "" and faction or nil },
        enabled     = true,
        weaponSlot  = E._weaponSlot,
        cachedIcon  = nil,
    }

    Addon:UpdateItemInProfile(profileName, idx, def)
    -- UpdateItemInProfile merges keys (pairs skips nils), so explicitly reconcile
    -- the identity fields that may need CLEARING when switching entry types.
    local prof = Addon.db.profiles[profileName]
    if prof and prof.items and prof.items[idx] then
        prof.items[idx].spellID    = E._spellID or nil
        prof.items[idx].weaponSlot = E._weaponSlot or nil
    end

    Addon:RefreshItemList()
    Addon:UpdateFrame()
end

PopulateEditor = function(item, idx)
    if not item then
        bt.selectedItemIndex = nil
        updateEditorVis()
        return
    end
    bt.selectedItemIndex = idx

    E._weaponSlot     = item.weaponSlot
    E._spellID        = item.spellID
    E._displayLabel   = item.displayName
    E._selectedItemID = item.itemID or 0

    local names = Addon:GetBuffNames(item)
    E._buffNames = {}
    for i, n in ipairs(names) do E._buffNames[i] = n end

    if item.weaponSlot then
        E.ebBuff:SetText("[" .. item.weaponSlot .. " enchant]")
        E.ebBuff:SetEnabled(false); E.ebAltBuff:SetEnabled(false)
        E.weaponLabel._label:SetText("Weapon: " .. item.weaponSlot)
    elseif item.spellID then
        E.ebBuff:SetText(item.displayName or E._buffNames[1] or "")
        E.ebBuff:SetEnabled(false); E.ebAltBuff:SetEnabled(false)
    else
        E.ebBuff:SetText(E._buffNames[1] or "")
        E.ebBuff:SetEnabled(true); E.ebAltBuff:SetEnabled(true)
    end
    E.ebAltBuff:SetText("")

    E.prevTex:SetTexture(Addon:GetBuffIcon(item))

    E._clickable = item.clickable ~= false
    E.cbClickable:Refresh()

    E._actionType = item.actionType == "macro" and "macro" or "item"
    E.seg.Refresh()

    if item.itemID and item.itemID > 0 then
        E.ebItem:SetText(Addon:GetItemName(item.itemID) or tostring(item.itemID))
    else
        E.ebItem:SetText("")
    end
    E.ebMacro:SetText(item.macroName or "")

    E._faction = (item.conditions and item.conditions.faction) or "Both"
    E.factionDD.Refresh()

    updateEditorVis()
end

-- ============================================================
-- Tracked-buff list refresh (repopulate rows from the selected profile).
-- ============================================================
local function SelectItemRow(idx)
    bt.selectedItemIndex = idx
    for i, row in ipairs(bt.itemRows) do
        if row:IsShown() then row.sel:SetShown(i == idx) end
    end
end

function Addon:RefreshItemList()
    if not bt.listChild then return end
    local profileName = bt.selectedProfileName
    local profile = profileName and Addon.db.profiles[profileName]
    local items = (profile and profile.items) or {}

    for _, row in ipairs(bt.itemRows) do row:Hide() end

    for i, item in ipairs(items) do
        local row = bt.itemRows[i]
        if not row then row = BuildBuffRow(i); bt.itemRows[i] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  bt.listChild, "TOPLEFT",  0, -(i - 1) * BUFF_ROW_H)
        row:SetPoint("TOPRIGHT", bt.listChild, "TOPRIGHT", 0, -(i - 1) * BUFF_ROW_H)
        row:Show()

        local ci = i
        row:SetScript("OnClick", function()
            SelectItemRow(ci)
            local p  = bt.selectedProfileName
            local it = p and Addon.db.profiles[p] and Addon.db.profiles[p].items and Addon.db.profiles[p].items[ci]
            PopulateEditor(it, ci)
        end)
        row:SetScript("OnMouseDown", function(self, btn2)
            if btn2 ~= "LeftButton" then return end
            bt._dragSourceIdx = ci; bt._dragging = false
            local mx, my = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            bt._dragClickX, bt._dragClickY = mx / sc, my / sc
            if bt._dragTick then bt._dragTick:Show() end
        end)

        row.icon:SetTexture(Addon:GetBuffIcon(item))

        local primaryName = Addon:GetBuffNames(item)[1]
        local displayName = item.displayName or primaryName or item.name or "Unnamed"
        if item.weaponSlot then
            displayName = item.weaponSlot == "mainhand" and "Mainhand Enchant" or "Offhand Enchant"
        end
        row._fullName = displayName
        row.nameText:SetText(displayName)

        if item.weaponSlot then
            if not item.clickable then row.actionText:SetText("Passive")
            elseif item.actionType == "macro" then row.actionText:SetText("Macro")
            else row.actionText:SetText("Item") end
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
            if bt.selectedItemIndex == ci2 then
                bt.selectedItemIndex = nil
                updateEditorVis()
            end
            Addon:RemoveItemFromProfile(cp, ci2)
            Addon:RefreshItemList(); Addon:UpdateFrame()
        end)
    end

    bt.listChild:SetHeight(math.max(#items * BUFF_ROW_H, BUFFLIST_H))
    if bt.selectedItemIndex and bt.selectedItemIndex > #items then
        bt.selectedItemIndex = nil
        updateEditorVis()
    end
    SelectItemRow(bt.selectedItemIndex)
end

-- ============================================================
-- Profiles refresh
-- ============================================================
local function RefreshProfiles()
    local active = Addon:GetActiveProfile()
    if not bt.selectedProfileName or not Addon.db.profiles[bt.selectedProfileName] then
        bt.selectedProfileName = active
    end
    if bt.profileList then bt.profileList:SetSelected(bt.selectedProfileName) end
end

-- ============================================================
-- Build everything into the hub-provided flow.
-- ============================================================
function Addon:BuildOptions(flow)
    if bt.built then return end
    bt.built = true

    local UI = DaseekiUI
    local DS = _G.DaseekiSuite
    local ShowNameInputDialog = DS.ShowNameInputDialog
    local ShowTextDialog      = DS.ShowTextDialog

    bt.pane = flow.pane
    Addon.optionsPanel = flow.pane   -- main.lua checks optionsPanel:IsShown()
    bt.selectedProfileName = Addon:GetActiveProfile()

    -- ── Section: Profiles ─────────────────────────────────────────────────────
    flow:AddSection("Profiles")
    flow:Hint("Select a profile to edit its tracked buffs. Set Active applies it to the on-screen tracker.")

    bt.profileList = flow:List({
        height = PROFILE_LIST_H,
        selected = bt.selectedProfileName,
        items = function()
            local out = {}
            local active = Addon:GetActiveProfile()
            for _, name in ipairs(Addon:GetProfileNames()) do
                out[#out + 1] = {
                    text   = name:sub(1, 1):upper() .. name:sub(2):lower(),
                    value  = name,
                    status = (name == active) and "ok" or "faint",
                }
            end
            return out
        end,
        onSelect = function(name)
            bt.selectedProfileName = name
            bt.selectedItemIndex = nil
            Addon:RefreshItemList()
            updateEditorVis()
        end,
    })

    local crud = flow:AddRow()
    crud:Button({ text = "New", width = 84, onClick = function()
        ShowNameInputDialog("New Profile", "", function(name)
            local ok, err = Addon:CreateProfile(name)
            if ok then bt.selectedProfileName = name; RefreshProfiles(); Addon:RefreshItemList()
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end })
    crud:Button({ text = "Clone", width = 84, onClick = function()
        local s = bt.selectedProfileName; if not s then return end
        ShowNameInputDialog("Clone Profile", s .. " Copy", function(name)
            local ok, err = Addon:CloneProfile(s, name)
            if ok then bt.selectedProfileName = name; RefreshProfiles(); Addon:RefreshItemList()
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end })
    crud:Button({ text = "Rename", width = 84, onClick = function()
        local s = bt.selectedProfileName; if not s then return end
        ShowNameInputDialog("Rename Profile", s, function(name)
            local ok, err = Addon:RenameProfile(s, name)
            if ok then bt.selectedProfileName = name; RefreshProfiles(); Addon:RefreshItemList()
            else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
        end)
    end })
    crud:Button({ text = "Delete", width = 84, variant = "danger", onClick = function()
        local s = bt.selectedProfileName; if not s then return end
        local ok, err = Addon:DeleteProfile(s)
        if ok then bt.selectedProfileName = Addon:GetActiveProfile(); RefreshProfiles(); Addon:RefreshItemList()
        else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
    end })

    local pio = flow:AddRow()
    pio:Button({ text = "Set Active", width = 110, onClick = function()
        local s = bt.selectedProfileName; if not s then return end
        Addon:SetActiveProfile(s)
        RefreshProfiles()
    end })
    pio:Button({ text = "Export", width = 90, onClick = function()
        local s = bt.selectedProfileName; if not s then return end
        local str, err = Addon:ExportProfile(s)
        if str then ShowTextDialog("Export: " .. s, str, true)
        else print("|cffff4444[DaseekiBT]|r " .. (err or "Error")) end
    end })
    pio:Button({ text = "Import", width = 90, onClick = function()
        ShowTextDialog("Import Profile (paste string below)", "", false, function(txt)
            local ok, result = Addon:ImportProfile(txt)
            if ok then
                print("|cff00ccff[DaseekiBT]|r Imported: " .. result)
                bt.selectedProfileName = result; RefreshProfiles(); Addon:RefreshItemList()
            else print("|cffff4444[DaseekiBT]|r Import failed: " .. (result or "?")) end
        end)
    end })

    -- ── Section: Frame Settings ───────────────────────────────────────────────
    flow:AddSection("Frame Settings")

    flow:AddChecklist({
        { label = "Lock",
          get = function() return Addon.db.settings.locked end,
          set = function(v) Addon.db.settings.locked = v; Addon:UpdateFrameLock() end },
        { label = "Tooltips",
          get = function() return Addon.db.settings.showTooltip end,
          set = function(v) Addon.db.settings.showTooltip = v end },
    })

    local hudRow = flow:AddRow()
    local hudLbl = hudRow:Label("Show HUD:"); hudLbl.uiWidth = 70; hudLbl:SetWidth(70)
    hudRow:SegmentedChoice({
        choices = { { value = "always", text = "Always" }, { value = "raid", text = "In Raid" } },
        get = function() return Addon.db.settings.showCondition or "always" end,
        set = function(v) Addon.db.settings.showCondition = v; Addon:UpdateFrame() end,
    })

    flow:Slider({
        label = "Scale", width = 220, min = 0.5, max = 2.0, step = 0.05,
        get = function() return Addon.db.settings.scale end,
        set = function(v) Addon.db.settings.scale = v; if Addon.mainFrame then Addon.mainFrame:SetScale(v) end end,
        format = function(v) return string.format("%.2f", v) end,
    })
    flow:Slider({
        label = "Spacing", width = 220, min = 0, max = 20, step = 1,
        get = function() return Addon.db.settings.iconSpacing end,
        set = function(v) Addon.db.settings.iconSpacing = v; Addon:UpdateFrame() end,
        format = function(v) return tostring(v) end,
    })
    flow:Slider({
        label = "Per Row", width = 220, min = 1, max = 16, step = 1,
        get = function() return Addon.db.settings.iconsPerRow end,
        set = function(v) Addon.db.settings.iconsPerRow = v; Addon:UpdateFrame() end,
        format = function(v) return tostring(v) end,
    })

    bt.anchorDD = flow:AddRow():Dropdown({
        label = "Anchor", width = 120, choices = { "Right", "Left" },
        get = function()
            local a = Addon.db.settings.anchor or "RIGHT"
            return a:sub(1, 1) .. a:sub(2):lower()
        end,
        set = function(v) Addon:SetAnchor(v:upper()) end,
    })

    -- ── Section: Tracked Buffs ────────────────────────────────────────────────
    flow:AddSection("Tracked Buffs")

    local hdr = flow:AddRow()
    local h1 = hdr:Label("Buff", { muted = true });    h1.uiWidth = 200; h1:SetWidth(200)
    local h2 = hdr:Label("Action", { muted = true });  h2.uiWidth = ACT_W; h2:SetWidth(ACT_W)
    hdr:Label("Faction", { muted = true })

    local listHost = BuildBuffList(flow)
    addBlock(flow, listHost, listHost.arrange, rowGap())

    flow:AddRow():Button({ text = "Add Buff", width = 90, onClick = function()
        local sel = bt.selectedProfileName
        if not sel then print("|cffff4444[DaseekiBT]|r Select a profile first"); return end
        local blank = {
            buffNames = {}, displayName = "New Entry",
            clickable = true, actionType = "item", itemID = 0,
            enabled = true, conditions = {}, weaponSlot = nil,
        }
        Addon:AddItemToProfile(sel, blank)
        Addon:RefreshItemList()
        local prof = Addon.db.profiles[sel]
        local newIdx = prof and prof.items and #prof.items or 1
        bt.selectedItemIndex = newIdx
        if bt.itemRows[newIdx] then bt.itemRows[newIdx].sel:Show() end
        PopulateEditor(blank, newIdx)
        E.ebBuff:SetText(""); E.ebBuff:SetFocus()
    end })

    BuildEditor(flow)

    -- First paint.
    RefreshProfiles()
    Addon:RefreshItemList()
    updateEditorVis()
end

-- ============================================================
-- Refresh: sync controls + lists (called each time the section is shown).
-- ============================================================
function Addon:RefreshOptionsPanel()
    if not bt.built then return end
    RefreshProfiles()
    Addon:RefreshItemList()
    if bt.anchorDD and bt.anchorDD.Refresh then bt.anchorDD.Refresh() end
    updateEditorVis()

    -- Pre-cache item icons for all BuffDB entries so they appear without delay.
    if Addon.BuffDB then
        for _, data in pairs(Addon.BuffDB) do
            if data.itemID then GetItemInfo(data.itemID) end
        end
    end
    -- Same for spell-ID-identified source items (Mageblood, Nightfin) so their icons
    -- render immediately instead of a question mark until GET_ITEM_INFO_RECEIVED.
    if Addon.BuffSpellDB then
        for _, e in ipairs(Addon.BuffSpellDB) do
            if e.itemID then GetItemInfo(e.itemID) end
        end
    end
end

-- ============================================================
-- Register the Buff Tracker section with the Daseeki Core hub.
-- `flow = true` opts this addon into the new DaseekiUI flow renderer
-- (Core now defaults registrations to the legacy raw-panel path).
-- ============================================================
function Addon:RegisterOptions()
    if not _G.DaseekiSuite then return end
    DaseekiSuite:RegisterAddon({
        id    = "bufftracker",
        title = "Buff Tracker",
        icon  = "Interface\\Icons\\INV_Potion_32",  -- Elixir of the Mongoose
        order = 30,
        flow  = true,
        sections = {
            {
                id      = "main",
                title   = "Buff Tracker",
                build   = function(flow) Addon:BuildOptions(flow) end,
                refresh = function() Addon:RefreshOptionsPanel() end,
            },
        },
    })
end
