local _, Addon = ...

local EXPORT_VERSION = "v3"

function Addon:GetProfileNames()
    local names = {}
    for name in pairs(Addon.db.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function Addon:ProfileExists(name)
    return name ~= nil and Addon.db.profiles[name] ~= nil
end

function Addon:CreateProfile(name)
    name = strtrim(name or "")
    if name == "" then return false, "Name cannot be empty" end
    if Addon:ProfileExists(name) then return false, "Profile already exists" end
    Addon.db.profiles[name] = { items = {} }
    return true
end

function Addon:CloneProfile(srcName, dstName)
    dstName = strtrim(dstName or "")
    if not Addon:ProfileExists(srcName) then return false, "Source not found" end
    if dstName == "" then return false, "Name cannot be empty" end
    if Addon:ProfileExists(dstName) then return false, "Name already taken" end
    Addon.db.profiles[dstName] = Addon:DeepCopy(Addon.db.profiles[srcName])
    return true
end

function Addon:DeleteProfile(name)
    local names = Addon:GetProfileNames()
    if #names <= 1 then return false, "Cannot delete the last profile" end
    if not Addon:ProfileExists(name) then return false, "Profile not found" end
    Addon.db.profiles[name] = nil
    local fallback = next(Addon.db.profiles)
    for charKey, profileName in pairs(Addon.db.charProfiles) do
        if profileName == name then
            Addon.db.charProfiles[charKey] = fallback
        end
    end
    if Addon:GetActiveProfile() == nil then
        Addon:SetActiveProfile(fallback)
    end
    return true
end

function Addon:RenameProfile(oldName, newName)
    newName = strtrim(newName or "")
    if not Addon:ProfileExists(oldName) then return false, "Profile not found" end
    if newName == "" then return false, "Name cannot be empty" end
    if Addon:ProfileExists(newName) then return false, "Name already taken" end
    Addon.db.profiles[newName] = Addon.db.profiles[oldName]
    Addon.db.profiles[oldName] = nil
    for charKey, name in pairs(Addon.db.charProfiles) do
        if name == oldName then Addon.db.charProfiles[charKey] = newName end
    end
    return true
end

-- v3 format: buffNames(|sep),displayName,clickable,actionType,itemID,macroName,faction,weaponSlot,enabled
function Addon:ExportProfile(name)
    local profile = Addon.db.profiles[name]
    if not profile then return nil, "Profile not found" end
    local lines = { "DaseekiCT:" .. EXPORT_VERSION .. ":" .. name }
    for _, item in ipairs(profile.items or {}) do
        -- Collect buff names (support both buffNames array and legacy buffName string)
        local names = Addon:GetBuffNames(item)
        local buffNamesStr = table.concat(names, "|"):gsub(",", "\xef\xbc\x8c")
        local dispName   = (item.displayName or item.name or ""):gsub(",", "\xef\xbc\x8c")
        local macroName  = (item.macroName   or ""):gsub(",", "\xef\xbc\x8c")
        local faction    = (item.conditions and item.conditions.faction) or ""
        local weaponSlot = item.weaponSlot or ""
        lines[#lines + 1] = table.concat({
            buffNamesStr,
            dispName,
            (item.clickable ~= false) and "1" or "0",
            item.actionType or "item",
            tostring(item.itemID or 0),
            macroName,
            faction,
            weaponSlot,
            (item.enabled ~= false) and "1" or "0",
        }, ",")
    end
    return table.concat(lines, "\n")
end

local function SplitCSV(line, n)
    local parts = {}
    local remaining = line
    for _ = 1, n - 1 do
        local part, rest = remaining:match("^([^,]*),(.*)")
        if not part then break end
        parts[#parts + 1] = part
        remaining = rest
    end
    parts[#parts + 1] = remaining
    return parts
end

function Addon:ImportProfile(str)
    if not str or strtrim(str) == "" then return false, "Empty string" end
    local lines = {}
    for line in str:gmatch("[^\n]+") do
        lines[#lines + 1] = strtrim(line)
    end
    if #lines < 1 then return false, "Invalid format" end

    local prefix, version, profileName = lines[1]:match("^(DaseekiCT):([^:]+):(.+)$")
    if not prefix then return false, "Invalid format (expected DaseekiCT:vN:Name header)" end

    local finalName = profileName
    if Addon:ProfileExists(finalName) then
        local i = 2
        while Addon:ProfileExists(finalName .. " (" .. i .. ")") do i = i + 1 end
        finalName = finalName .. " (" .. i .. ")"
    end

    local items = {}
    for i = 2, #lines do
        local line = lines[i]
        if line ~= "" then
            if version == "v3" then
                -- buffNames(|sep),displayName,clickable,actionType,itemID,macroName,faction,weaponSlot,enabled
                local p = SplitCSV(line, 9)
                local buffNamesRaw = p[1] and p[1]:gsub("\xef\xbc\x8c", ",") or ""
                local buffNames = {}
                for n in (buffNamesRaw .. "|"):gmatch("([^|]*)|") do
                    if n ~= "" then buffNames[#buffNames + 1] = n end
                end
                local dispName  = p[2] and p[2]:gsub("\xef\xbc\x8c", ",") or ""
                local macroName = p[6] and p[6]:gsub("\xef\xbc\x8c", ",") or ""
                items[#items + 1] = {
                    buffNames   = buffNames,
                    displayName = dispName ~= "" and dispName or (buffNames[1] or ""),
                    clickable   = p[3] == "1",
                    actionType  = (p[4] ~= "" and p[4]) or "item",
                    itemID      = tonumber(p[5]) or 0,
                    macroName   = macroName ~= "" and macroName or nil,
                    conditions  = { faction = (p[7] ~= "" and p[7]) or nil },
                    weaponSlot  = (p[8] ~= "" and p[8]) or nil,
                    enabled     = p[9] ~= "0",
                }
            elseif version == "v2" then
                -- buffName,displayName,clickable,actionType,itemID,macroName,faction,weaponSlot,enabled
                local p = SplitCSV(line, 9)
                local buffName  = p[1] and p[1]:gsub("\xef\xbc\x8c", ",") or ""
                local dispName  = p[2] and p[2]:gsub("\xef\xbc\x8c", ",") or ""
                local macroName = p[6] and p[6]:gsub("\xef\xbc\x8c", ",") or ""
                items[#items + 1] = {
                    buffNames   = buffName ~= "" and { buffName } or {},
                    displayName = dispName ~= "" and dispName or buffName,
                    clickable   = p[3] == "1",
                    actionType  = (p[4] ~= "" and p[4]) or "item",
                    itemID      = tonumber(p[5]) or 0,
                    macroName   = macroName ~= "" and macroName or nil,
                    conditions  = { faction = (p[7] ~= "" and p[7]) or nil },
                    weaponSlot  = (p[8] ~= "" and p[8]) or nil,
                    enabled     = p[9] ~= "0",
                }
            elseif version == "v1" then
                -- legacy: itemID,required,clickAction,macroName,faction,buffName,enabled,weaponSlot,name
                local p = SplitCSV(line, 9)
                local itemID = tonumber(p[1])
                if itemID then
                    local buffName  = (p[6] ~= "" and p[6]) or nil
                    local itemName  = (p[9] or ("Item " .. itemID)):gsub("\xef\xbc\x8c", ",")
                    local macroName = (p[4] ~= "" and p[4]) or nil
                    local oldAction = p[3] or "use"
                    items[#items + 1] = {
                        buffName    = buffName,
                        displayName = itemName,
                        clickable   = true,
                        actionType  = oldAction == "macro" and "macro" or "item",
                        itemID      = itemID,
                        macroName   = macroName,
                        conditions  = { faction = (p[5] ~= "" and p[5]) or nil },
                        weaponSlot  = (p[8] ~= "" and p[8]) or nil,
                        enabled     = p[7] == "1",
                    }
                end
            else
                return false, "Unsupported version: " .. version
            end
        end
    end

    Addon.db.profiles[finalName] = { items = items }
    return true, finalName
end

-- Item list management
function Addon:AddItemToProfile(profileName, itemDef)
    local profile = Addon.db.profiles[profileName]
    if not profile then return false end
    profile.items = profile.items or {}
    itemDef.enabled = itemDef.enabled ~= false
    table.insert(profile.items, itemDef)
    return true
end

function Addon:UpdateItemInProfile(profileName, index, itemDef)
    local profile = Addon.db.profiles[profileName]
    if not profile or not profile.items or not profile.items[index] then return false end
    for k, v in pairs(itemDef) do
        profile.items[index][k] = v
    end
    return true
end

function Addon:RemoveItemFromProfile(profileName, index)
    local profile = Addon.db.profiles[profileName]
    if not profile or not profile.items then return false end
    table.remove(profile.items, index)
    return true
end

function Addon:MoveItemInProfile(profileName, index, direction)
    local profile = Addon.db.profiles[profileName]
    if not profile or not profile.items then return false end
    local items = profile.items
    local newIndex = index + direction
    if newIndex < 1 or newIndex > #items then return false end
    items[index], items[newIndex] = items[newIndex], items[index]
    return true
end
