local AddonName, Addon = ...
DaseekiCT = Addon

local DEFAULT_SETTINGS = {
    locked         = false,
    scale          = 1.0,
    iconSize       = 36,
    iconSpacing    = 2,
    iconsPerRow    = 8,
    orientation    = "HORIZONTAL",
    showTooltip    = true,
    anchor         = "RIGHT",
    point          = "TOPRIGHT",  -- collapse corner; saved verbatim from GetPoint
    relPoint       = "CENTER",
    posX           = -300,
    posY           = -200,
    showCondition  = "always",  -- "always" | "raid"
}

function Addon:GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function Addon:DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and Addon:DeepCopy(v) or v
    end
    return copy
end

local DB_VERSION = 3  -- bump to force profile reset when data model changes

function Addon:Init()
    DaseekiCTDB = DaseekiCTDB or {}
    local db = DaseekiCTDB

    -- Wipe profiles when the data model has been updated
    if (db.dbVersion or 1) < DB_VERSION then
        db.profiles       = nil
        db.charProfiles   = nil
        db.charInitialized = nil
        db.dbVersion      = DB_VERSION
        print("|cff00ccff[DaseekiBT]|r Profiles reset for v3 multi-buff model.")
    end

    if not db.settings then db.settings = {} end
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    if not db.profiles then db.profiles = {} end
    for className, profileData in pairs(Addon.ClassDefaults) do
        if not db.profiles[className] then
            db.profiles[className] = Addon:DeepCopy(profileData)
        end
    end

    if not db.charProfiles    then db.charProfiles    = {} end
    if not db.charInitialized then db.charInitialized = {} end

    -- Migrate buff names that didn't match the actual UnitBuff() aura name, and
    -- clear stale cachedIcon values (e.g. from the count-as-icon bug).
    local BUFF_RENAMES = {
        ["Mongoose"]   = "Elixir of the Mongoose",
        ["Firewater"]  = "Winterfall Firewater",
        ["R.O.I.D.S."] = "Rage of Ages",
    }
    for _, profile in pairs(db.profiles or {}) do
        for _, item in ipairs(profile.items or {}) do
            if item.buffName and BUFF_RENAMES[item.buffName] then
                item.buffName = BUFF_RENAMES[item.buffName]
            end
            if item.buffNames then
                for i, n in ipairs(item.buffNames) do
                    if BUFF_RENAMES[n] then item.buffNames[i] = BUFF_RENAMES[n] end
                end
            end
            if type(item.cachedIcon) ~= "string" then item.cachedIcon = nil end
        end
    end

    Addon.db = db
end

function Addon:OnLogin()
    local charKey = Addon:GetCharKey()
    local db = Addon.db
    local _, class = UnitClass("player")

    if not db.charInitialized[charKey] then
        db.charInitialized[charKey] = true
        if db.profiles[class] then
            db.charProfiles[charKey] = class
        else
            db.charProfiles[charKey] = next(db.profiles)
        end
    end

    local saved = db.charProfiles[charKey]
    if not saved or not db.profiles[saved] then
        db.charProfiles[charKey] = next(db.profiles)
    end

    Addon:InitFrame()
    Addon:RegisterOptions()
    Addon:Refresh()

    print("|cff00ccffDaseeki Buff Tracker|r loaded. Profile: |cffffffff" .. (Addon:GetActiveProfile() or "none") .. "|r  /dbt for options.")
end

function Addon:GetActiveProfile()
    return Addon.db.charProfiles[Addon:GetCharKey()]
end

function Addon:SetActiveProfile(name)
    Addon.db.charProfiles[Addon:GetCharKey()] = name
    Addon:UpdateFrame()
    Addon:Refresh()
end

function Addon:GetProfileItems()
    local profileName = Addon:GetActiveProfile()
    local profile = Addon.db.profiles[profileName]
    return (profile and profile.items) or {}
end

function Addon:GetPlayerFaction()
    return UnitFactionGroup("player")
end

function Addon:CountItemInBags(itemID)
    local count = 0
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                count = count + (info.stackCount or 1)
            end
        end
    end
    return count
end

function Addon:HasWeaponEnchant(slot)
    local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
    if slot == "mainhand" then return hasMH == true end
    if slot == "offhand"  then return hasOH == true end
    return false
end

function Addon:GetWeaponEnchantSecondsRemaining(slot)
    local hasMH, mhExpiry, _, _, hasOH, ohExpiry = GetWeaponEnchantInfo()
    if slot == "mainhand" and hasMH then
        return mhExpiry and (mhExpiry / 1000) or math.huge
    end
    if slot == "offhand" and hasOH then
        return ohExpiry and (ohExpiry / 1000) or math.huge
    end
    return nil
end

-- Returns the effective list of buff names for an item (supports legacy single buffName).
function Addon:GetBuffNames(item)
    if item.buffNames and #item.buffNames > 0 then
        return item.buffNames
    elseif item.buffName and item.buffName ~= "" then
        return { item.buffName }
    end
    return {}
end

-- Returns the BEST (maximum) remaining seconds across all buff names in the list.
-- nil = none are active; math.huge = at least one is permanent.
function Addon:GetMultiBuffExpiry(buffNames)
    local best = nil
    for _, name in ipairs(buffNames) do
        local secs = Addon:GetBuffExpiry(name)
        if secs ~= nil then
            if best == nil then
                best = secs
            elseif secs == math.huge or best == math.huge then
                best = math.huge
            else
                best = math.max(best, secs)
            end
        end
    end
    return best
end

-- Returns seconds remaining if buff is present (math.huge if permanent), nil if missing.
function Addon:GetBuffExpiry(buffName)
    if not buffName or buffName == "" then return nil end
    for i = 1, 40 do
        -- Classic Era UnitBuff: name, icon, count, dispelType, duration, expirationTime, source, ...
        local name, _, _, _, _, expirationTime = UnitBuff("player", i)
        if not name then break end
        if name == buffName then
            if expirationTime and expirationTime > 0 then
                return expirationTime - GetTime()
            end
            return math.huge  -- permanent / no expiry
        end
    end
    return nil  -- not present
end

-- Returns the icon texture for a buff entry.
-- Priority: active UnitBuff scan → BuffDB by primary buff name → GetSpellInfo by name → stored itemID → question mark.
-- BuffDB is checked before stored itemID so changing the primary buff name always produces the correct icon.
function Addon:GetBuffIcon(item)
    if item.weaponSlot and item.weaponSlot ~= "" then
        local invSlot = item.weaponSlot == "offhand" and 17 or 16
        return GetInventoryItemTexture("player", invSlot)
            or "Interface\\Icons\\INV_Stone_SharpeningStone05"
    end
    if item.cachedIcon and type(item.cachedIcon) == "string" then return item.cachedIcon end
    item.cachedIcon = nil  -- clear any stale non-string value
    local primaryBuff = Addon:GetBuffNames(item)[1]
    -- 1. Active buff scan — most accurate and caches for this session
    if primaryBuff and primaryBuff ~= "" then
        for i = 1, 40 do
            local name, icon = UnitBuff("player", i)
            if not name then break end
            if name == primaryBuff then
                item.cachedIcon = icon
                return icon
            end
        end
    end
    -- 2. BuffDB lookup by primary buff name — correct icon regardless of stored itemID
    if primaryBuff and Addon.BuffDB then
        local dbEntry = Addon.BuffDB[primaryBuff]
        if dbEntry then
            if dbEntry.itemID then
                local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(dbEntry.itemID)
                if tex then return tex end
            end
            if dbEntry.spellID then
                local _, _, icon = GetSpellInfo(dbEntry.spellID)
                if icon then return icon end
            end
        end
    end
    -- 3. GetSpellInfo by name (works if player knows the spell)
    if primaryBuff and primaryBuff ~= "" then
        local _, _, icon = GetSpellInfo(primaryBuff)
        if icon then return icon end
    end
    -- 4. Stored itemID fallback
    if item.itemID and item.itemID > 0 then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(item.itemID)
        if tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local MAX_ACCOUNT_MACROS = 120

-- Returns all account and character macros as {macroName, texture, isChar}.
function Addon:GetMacroList()
    local list = {}
    local numAccount, numChar = GetNumMacros()
    for i = 1, numAccount do
        local name, texture = GetMacroInfo(i)
        if name and name ~= "" then
            list[#list + 1] = { macroName = name, texture = texture, isChar = false }
        end
    end
    for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numChar do
        local name, texture = GetMacroInfo(i)
        if name and name ~= "" then
            list[#list + 1] = { macroName = name, texture = texture, isChar = true }
        end
    end
    return list
end

function Addon:SearchMacros(query)
    query = (query or ""):lower()
    local all = Addon:GetMacroList()
    if query == "" then return all end
    local list = {}
    for _, m in ipairs(all) do
        if m.macroName:lower():find(query, 1, true) then
            list[#list + 1] = m
        end
    end
    return list
end

function Addon:SearchItemDB(query)
    query = (query or ""):lower()
    local list = {}
    local db = DaseekiPrep and DaseekiPrep.ItemDB
    if db then
        for id, name in pairs(db) do
            if query == "" or name:lower():find(query, 1, true) then
                list[#list + 1] = { itemID = id, itemName = name }
            end
        end
        table.sort(list, function(a, b) return a.itemName < b.itemName end)
    end
    return list
end

function Addon:GetItemName(itemID)
    if DaseekiPrep and DaseekiPrep.ItemDB and DaseekiPrep.ItemDB[itemID] then
        return DaseekiPrep.ItemDB[itemID]
    end
    local name = GetItemInfo(itemID)
    return name
end

function Addon:ShouldShow()
    local cond = Addon.db and Addon.db.settings and Addon.db.settings.showCondition or "always"
    if cond == "raid" then
        local _, instanceType, _, _, maxPlayers = GetInstanceInfo()
        return instanceType == "raid" and (maxPlayers == 20 or maxPlayers == 40)
    end
    return true
end

function Addon:Refresh()
    if Addon.mainFrame then
        Addon:UpdateIcons()
    end
end

-- Events
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- combat end: do the deferred reflow

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == AddonName then Addon:Init() end
    elseif event == "PLAYER_LOGIN" then
        Addon:OnLogin()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Addon.mainFrame then Addon:UpdateFrame() end  -- re-layout + restore secure attributes
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then Addon:Refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if Addon.mainFrame then Addon:Refresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if Addon.mainFrame then Addon:UpdateFrame() end
        local panel = Addon.optionsPanel
        if panel and panel:IsShown() and Addon.RefreshItemList then Addon:RefreshItemList(panel) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if Addon.mainFrame then Addon:UpdateFrame() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if Addon.mainFrame then Addon:UpdateFrame() end
    end
end)

-- Slash commands
SLASH_DASEEKIBT1 = "/dbt"
SLASH_DASEEKIBT2 = "/daseekibt"
SlashCmdList["DASEEKIBT"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "" or msg == "options" or msg == "config" then
        if _G.DaseekiSuite then
            DaseekiSuite:Open("bufftracker")
        else
            print("|cff00ccff[DaseekiBT]|r Install Daseeki Core for the options window.")
        end
    elseif msg == "toggle" then
        local f = Addon.mainFrame
        if f then
            if f:IsShown() then f:Hide() else f:Show() end
        end
    elseif msg == "lock" then
        Addon.db.settings.locked = not Addon.db.settings.locked
        Addon:UpdateFrameLock()
        print("|cff00ccff[DaseekiBT]|r Frame " .. (Addon.db.settings.locked and "locked" or "unlocked"))
    elseif msg == "reset" then
        Addon.db.settings.point    = DEFAULT_SETTINGS.point
        Addon.db.settings.relPoint = DEFAULT_SETTINGS.relPoint
        Addon.db.settings.posX     = DEFAULT_SETTINGS.posX
        Addon.db.settings.posY     = DEFAULT_SETTINGS.posY
        Addon:PositionFrame()
        print("|cff00ccff[DaseekiBT]|r Frame position reset.")
    else
        print("|cff00ccff[DaseekiBT]|r /dbt [options|toggle|lock|reset]")
    end
end
