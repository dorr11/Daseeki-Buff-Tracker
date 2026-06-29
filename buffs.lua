local _, Addon = ...

-- Common Classic Era buff names keyed by the exact aura name UnitBuff() returns.
-- label  = human-readable name shown in search results (no stat text)
-- itemID = used for icon lookup when the buff is not currently active on the player;
--          world buffs / raid spells with no item fall back to GetSpellInfo() for their icon.
Addon.BuffDB = {
    -- ----------------------------------------------------------------
    -- Flasks
    -- ----------------------------------------------------------------
    ["Flask of the Titans"]              = { label = "Flask of the Titans",              itemID = 13510 },
    ["Flask of Distilled Wisdom"]        = { label = "Flask of Distilled Wisdom",        itemID = 13511 },
    ["Flask of Supreme Power"]           = { label = "Flask of Supreme Power",           itemID = 13512 },
    ["Flask of Chromatic Resistance"]    = { label = "Flask of Chromatic Resistance",    itemID = 13513 },

    -- ----------------------------------------------------------------
    -- Battle Elixirs
    -- ----------------------------------------------------------------
    ["Elixir of the Mongoose"]           = { label = "Elixir of the Mongoose",           itemID = 13452 },
    ["Greater Arcane Elixir"]            = { label = "Greater Arcane Elixir",            itemID = 13454 },
    ["Elixir of Brute Force"]            = { label = "Elixir of Brute Force",            itemID = 13453 },
    ["Elixir of the Giants"]             = { label = "Elixir of the Giants",             itemID = 9206  },
    ["Elixir of Greater Agility"]        = { label = "Elixir of Greater Agility",        itemID = 9187  },
    ["Elixir of Agility"]                = { label = "Elixir of Agility",                itemID = 8949  },
    ["Elixir of Strength"]               = { label = "Elixir of Strength",               itemID = 3388  },
    ["Elixir of Ogre's Strength"]        = { label = "Elixir of Ogre's Strength",        itemID = 3391  },
    ["Elixir of Demonslaying"]           = { label = "Elixir of Demonslaying",           itemID = 11351 },
    ["Shadow Power"]                     = { label = "Elixir of Shadow Power",           itemID = 9264  },
    ["Fire Power"]                       = { label = "Elixir of Fire Power",             itemID = 6373  },
    ["Elixir of the Sages"]              = { label = "Elixir of the Sages",              itemID = 13447 },

    -- ----------------------------------------------------------------
    -- Guardian Elixirs
    -- ----------------------------------------------------------------
    ["Elixir of Fortitude"]              = { label = "Elixir of Fortitude",              itemID = 3825  },
    ["Greater Stoneshield"]              = { label = "Greater Stoneshield Potion",       itemID = 13455 },
    ["Elixir of Superior Defense"]       = { label = "Elixir of Superior Defense",       itemID = 13445 },
    ["Elixir of Greater Defense"]        = { label = "Elixir of Greater Defense",        itemID = 8951  },
    ["Mageblood"]                        = { label = "Mageblood Potion",                 itemID = 20007 },

    -- ----------------------------------------------------------------
    -- Juju (Winterspring)
    -- ----------------------------------------------------------------
    ["Juju Power"]                       = { label = "Juju Power",                       itemID = 12451, spellID = 16323 },
    ["Juju Might"]                       = { label = "Juju Might",                       itemID = 12460 },
    ["Juju Ember"]                       = { label = "Juju Ember",                       itemID = 12455 },
    ["Juju Chill"]                       = { label = "Juju Chill",                       itemID = 12457 },
    ["Juju Flurry"]                      = { label = "Juju Flurry",                      itemID = 12464 },
    ["Juju Guile"]                       = { label = "Juju Guile",                       itemID = 12462 },

    -- ----------------------------------------------------------------
    -- Zanza Bijous (Zul'Gurub)
    -- ----------------------------------------------------------------
    ["Spirit of Zanza"]                  = { label = "Spirit of Zanza",                  itemID = 20079 },
    ["Sheen of Zanza"]                   = { label = "Sheen of Zanza",                   itemID = 20080 },
    ["Swiftness of Zanza"]               = { label = "Swiftness of Zanza",               itemID = 20081 },

    -- ----------------------------------------------------------------
    -- Silithus / Felwood consumables
    -- ----------------------------------------------------------------
    ["Winterfall Firewater"]             = { label = "Winterfall Firewater",             itemID = 12820 },

    -- ----------------------------------------------------------------
    -- Dire Maul Tribute consumables
    -- ----------------------------------------------------------------
    ["Rage of Ages"]                     = { label = "Rage of Ages (R.O.I.D.S.)",        itemID = 8410  },
    ["Ground Scorpok Assay"]             = { label = "Ground Scorpok Assay",             itemID = 8412  },
    ["Cerebral Cortex Compound"]         = { label = "Cerebral Cortex Compound",         itemID = 8423  },
    ["Lung Juice Cocktail"]              = { label = "Lung Juice Cocktail",              itemID = 8411  },
    ["Gizzard Gum"]                      = { label = "Gizzard Gum",                      itemID = 8413  },

    -- ----------------------------------------------------------------
    -- Food
    -- ----------------------------------------------------------------
    ["Well Fed"]                         = { label = "Well Fed",                         itemID = 20452 },
    ["Increased Stamina"]                = { label = "Increased Stamina (Dirge's)",      itemID = 21023 },
    ["Smoked Desert Dumplings"]          = { label = "Smoked Desert Dumplings",          itemID = 20452 },
    ["Grilled Squid"]                    = { label = "Grilled Squid",                    itemID = 13928 },
    ["Tender Wolf Steak"]                = { label = "Tender Wolf Steak",                itemID = 18045 },
    ["Mightfish Steak"]                  = { label = "Mightfish Steak",                  itemID = 13851 },
    ["Blessed Sunfruit"]                 = { label = "Blessed Sunfruit",                 itemID = 13810 },
    ["Blessed Sunfruit Juice"]           = { label = "Blessed Sunfruit Juice",           itemID = 13813 },
    ["Runn Tum Tuber Surprise"]          = { label = "Runn Tum Tuber Surprise",          itemID = 18254 },
    ["Nightfin Soup"]                    = { label = "Nightfin Soup",                    itemID = 13931 },
    ["Baked Salmon"]                     = { label = "Baked Salmon",                     itemID = 13929 },
    ["Dirge's Kickin' Chimaerok Chops"]  = { label = "Dirge's Kickin' Chimaerok Chops", itemID = 21023 },
    ["Monster Omelet"]                   = { label = "Monster Omelet",                   itemID = 12218 },

    -- ----------------------------------------------------------------
    -- Potions (trackable buff duration)
    -- ----------------------------------------------------------------
    ["Free Action"]                      = { label = "Free Action Potion",               itemID = 5506  },
    ["Limited Invulnerability"]          = { label = "Limited Invulnerability Potion",   itemID = 3387  },
    ["Greater Fire Protection"]          = { label = "Greater Fire Protection Potion",   itemID = 13457 },
    ["Greater Frost Protection"]         = { label = "Greater Frost Protection Potion",  itemID = 13456 },
    ["Greater Nature Protection"]        = { label = "Greater Nature Protection Potion", itemID = 13458 },
    ["Greater Shadow Protection"]        = { label = "Greater Shadow Protection Potion", itemID = 13459 },
    ["Greater Arcane Protection"]        = { label = "Greater Arcane Protection Potion", itemID = 13461 },
    ["Greater Holy Protection"]          = { label = "Greater Holy Protection Potion",   itemID = 13460 },

    -- ----------------------------------------------------------------
    -- World Buffs
    -- ----------------------------------------------------------------
    ["Rallying Cry of the Dragonslayer"] = { label = "Rallying Cry of the Dragonslayer", spellID = 22888 },
    ["Warchief's Blessing"]              = { label = "Warchief's Blessing",               spellID = 16609 },
    ["Spirit of Zandalar"]               = { label = "Spirit of Zandalar",                spellID = 24425 },
    ["Fengus' Ferocity"]                 = { label = "Fengus' Ferocity",                  spellID = 22817 },
    ["Slip'kik's Savvy"]                 = { label = "Slip'kik's Savvy",                  spellID = 22820 },
    ["Mol'dar's Moxie"]                  = { label = "Mol'dar's Moxie",                   spellID = 22818 },
    ["Songflower Serenade"]              = { label = "Songflower Serenade",               spellID = 15366 },
    -- Darkmoon Faire — Sayge's Dark Fortunes
    ["Sayge's Dark Fortune of Damage"]       = { label = "Sayge's Dark Fortune of Damage",       spellID = 23768 },
    ["Sayge's Dark Fortune of Resistance"]   = { label = "Sayge's Dark Fortune of Resistance",   spellID = 23769 },
    ["Sayge's Dark Fortune of Agility"]      = { label = "Sayge's Dark Fortune of Agility",      spellID = 23736 },
    ["Sayge's Dark Fortune of Intelligence"] = { label = "Sayge's Dark Fortune of Intelligence", spellID = 23766 },
    ["Sayge's Dark Fortune of Spirit"]       = { label = "Sayge's Dark Fortune of Spirit",       spellID = 23738 },
    ["Sayge's Dark Fortune of Strength"]     = { label = "Sayge's Dark Fortune of Strength",     spellID = 23735 },
    ["Sayge's Dark Fortune of Stamina"]      = { label = "Sayge's Dark Fortune of Stamina",      spellID = 23737 },
    ["Sayge's Dark Fortune of Armor"]        = { label = "Sayge's Dark Fortune of Armor",        spellID = 23767 },

    -- ----------------------------------------------------------------
    -- Raid / Party Buffs
    -- ----------------------------------------------------------------
    ["Power Word: Fortitude"]            = { label = "Power Word: Fortitude",         spellID = 10938 },
    ["Prayer of Fortitude"]              = { label = "Prayer of Fortitude",            spellID = 21564 },
    ["Arcane Intellect"]                 = { label = "Arcane Intellect",               spellID = 10157 },
    ["Arcane Brilliance"]                = { label = "Arcane Brilliance",              spellID = 23028 },
    ["Mark of the Wild"]                 = { label = "Mark of the Wild",               spellID = 9885  },
    ["Gift of the Wild"]                 = { label = "Gift of the Wild",               spellID = 21850 },
    ["Thorns"]                           = { label = "Thorns",                         spellID = 9756  },
    ["Blessing of Kings"]                = { label = "Blessing of Kings",              spellID = 20217 },
    ["Blessing of Might"]                = { label = "Blessing of Might",              spellID = 25291 },
    ["Greater Blessing of Might"]        = { label = "Greater Blessing of Might",      spellID = 25782 },
    ["Blessing of Wisdom"]               = { label = "Blessing of Wisdom",             spellID = 25290 },
    ["Greater Blessing of Wisdom"]       = { label = "Greater Blessing of Wisdom",     spellID = 25894 },
    ["Blessing of Salvation"]            = { label = "Blessing of Salvation",          spellID = 1038  },
    ["Greater Blessing of Salvation"]    = { label = "Greater Blessing of Salvation",  spellID = 25895 },
    ["Blessing of Sanctuary"]            = { label = "Blessing of Sanctuary",          spellID = 20911 },
    ["Greater Blessing of Sanctuary"]    = { label = "Greater Blessing of Sanctuary",  spellID = 25899 },
    ["Battle Shout"]                     = { label = "Battle Shout",                   spellID = 25289 },
    ["Trueshot Aura"]                    = { label = "Trueshot Aura",                  spellID = 19506 },
    ["Shadow Protection"]                = { label = "Shadow Protection",              spellID = 10958 },
    ["Prayer of Shadow Protection"]      = { label = "Prayer of Shadow Protection",    spellID = 27683 },
    ["Divine Spirit"]                    = { label = "Divine Spirit",                  spellID = 27841 },
    ["Prayer of Spirit"]                 = { label = "Prayer of Spirit",               spellID = 27681 },
    -- Paladin Auras
    ["Devotion Aura"]                    = { label = "Devotion Aura",                  spellID = 10293 },
    ["Retribution Aura"]                 = { label = "Retribution Aura",               spellID = 10301 },
    ["Concentration Aura"]               = { label = "Concentration Aura",             spellID = 19746 },
    ["Sanctity Aura"]                    = { label = "Sanctity Aura",                  spellID = 20218 },
    ["Fire Resistance Aura"]             = { label = "Fire Resistance Aura",           spellID = 19900 },
    ["Frost Resistance Aura"]            = { label = "Frost Resistance Aura",          spellID = 19898 },
    ["Shadow Resistance Aura"]           = { label = "Shadow Resistance Aura",         spellID = 19896 },
    -- Shaman Totems
    ["Strength of Earth"]                = { label = "Strength of Earth Totem",        spellID = 25361 },
    ["Grace of Air"]                     = { label = "Grace of Air Totem",             spellID = 25359 },
    ["Windfury Totem"]                   = { label = "Windfury Totem",                 spellID = 10613 },
    ["Mana Spring"]                      = { label = "Mana Spring Totem",              spellID = 10497 },
    ["Mana Tide"]                        = { label = "Mana Tide Totem",                spellID = 16190 },
    -- Hunter
    ["Aspect of the Hawk"]               = { label = "Aspect of the Hawk",             spellID = 25296 },
    -- Druid
    ["Innervate"]                        = { label = "Innervate",                      spellID = 29166 },
}

local WEAPON_ENCHANT_ENTRIES = {
    { buffName = "", label = "Mainhand Enchant", weaponSlot = "mainhand" },
    { buffName = "", label = "Offhand Enchant",  weaponSlot = "offhand"  },
}

-- Returns a sorted list of {buffName, label, itemID, spellID, weaponSlot} entries matching a keyword query.
function Addon:SearchBuffDB(query)
    query = (query or ""):lower()
    local results = {}
    for _, e in ipairs(WEAPON_ENCHANT_ENTRIES) do
        if query == "" or e.label:lower():find(query, 1, true) then
            results[#results + 1] = e
        end
    end
    for buffName, data in pairs(Addon.BuffDB) do
        local label = data.label or buffName
        if query == "" or buffName:lower():find(query, 1, true) or label:lower():find(query, 1, true) then
            results[#results + 1] = { buffName = buffName, label = label, itemID = data.itemID, spellID = data.spellID }
        end
    end
    table.sort(results, function(a, b) return a.label < b.label end)
    return results
end
