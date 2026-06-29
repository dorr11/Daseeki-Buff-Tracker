local _, Addon = ...

-- Buff entry: tracks one or more active buffs. buffNames[1] = primary (icon source).
-- If ANY buff in the list is active the icon hides; if the best remaining is ≤ 2 min,
-- icon shows with countdown. Useful for mutually exclusive buffs (e.g. Zanza / R.O.I.D.S.).
local function Buff(buffName, itemID, displayName)
    return {
        buffNames   = { buffName },
        displayName = displayName or buffName,
        clickable   = true,
        actionType  = "item",
        itemID      = itemID,
        macroName   = nil,
        conditions  = {},
        enabled     = true,
        weaponSlot  = nil,
    }
end

-- Multi-buff entry: monitors multiple aura names for mutual-exclusion groups.
local function MultiBuff(buffNamesList, itemID, displayName)
    return {
        buffNames   = buffNamesList,
        displayName = displayName,
        clickable   = true,
        actionType  = "item",
        itemID      = itemID,
        macroName   = nil,
        conditions  = {},
        enabled     = true,
        weaponSlot  = nil,
    }
end

-- Weapon enchant entry: no buff to check, uses GetWeaponEnchantInfo() instead.
local function WeaponEnchant(slot, displayName)
    return {
        buffNames   = {},
        displayName = displayName,
        clickable   = false,
        actionType  = nil,
        itemID      = 0,
        macroName   = nil,
        conditions  = {},
        enabled     = true,
        weaponSlot  = slot,  -- "mainhand" | "offhand"
    }
end

-- Warrior profile mirrors "Psy's Warrior Buffs & Consumes (Classic) v2.0".
-- Buff names are the exact aura names returned by UnitBuff().
Addon.ClassDefaults = {
    ["WARRIOR"] = {
        items = {
            Buff("Flask of the Titans",     13510),
            MultiBuff({ "Spirit of Zanza", "Rage of Ages" }, 20079, "Zanza / Rage of Ages"),
            Buff("Elixir of the Mongoose",  13452),
            Buff("Juju Power",              12451),
            Buff("Winterfall Firewater",    12820),
            Buff("Smoked Desert Dumplings", 20452),
            WeaponEnchant("offhand", "Offhand Enchant"),
        }
    },
    ["PALADIN"]  = { items = {} },
    ["HUNTER"]   = { items = {} },
    ["ROGUE"]    = { items = {} },
    ["PRIEST"]   = { items = {} },
    ["SHAMAN"]   = { items = {} },
    ["MAGE"]     = { items = {} },
    ["WARLOCK"]  = { items = {} },
    ["DRUID"]    = { items = {} },
}
