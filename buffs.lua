local _, Addon = ...

-- ================================================================================
-- THE CATALOG IS KEYED BY THE AURA NAME, NOT BY THE ITEM NAME.
--
-- This is the single rule the file exists to hold, and breaking it is invisible
-- until a player reports "the addon does not see my flask". UnitBuff() returns the
-- AURA's name, which for a great many Classic Era consumables is NOT the name of
-- the item that applied it: Flask of Supreme Power puts up "Supreme Power",
-- Flask of Distilled Wisdom puts up "Distilled Wisdom", Elixir of Shadow Power
-- puts up "Shadow Power", R.O.I.D.S. puts up "Rage of Ages". A catalog entry keyed
-- by the ITEM name in those cases can NEVER match, and the reminder icon stays lit
-- with the buff visibly on the player's bar. That was the shipped 2.1.1 defect for
-- Distilled Wisdom and Chromatic Resistance.
--
-- Fields:
--   [key]  = the exact aura name UnitBuff() returns. THIS is what is matched.
--   label  = human-readable name shown in search results — the ITEM name, so the
--            player can still find "Flask of Distilled Wisdom" by typing it.
--   itemID = icon lookup when the buff is not currently active on the player.
--   spellID= the AURA's spell ID. Matching tries this FIRST (see
--            Addon:GetNamedBuffExpiry in main.lua) and only then the name, so a
--            non-English client — or a name that drifts — still resolves.
--
-- ── PROVENANCE, and why every row carries one ────────────────────────────────
-- The 2.1.1 catalog stated its keys as fact with no record of which had ever been
-- read off a live buff bar. Two of them had never matched anything. So each row
-- now declares EXACTLY ONE of:
--
--   nameSrc = <token>   the key is a CONFIRMED aura name, from:
--     "spec"    the suite's Room-1 world-buff behavioural spec §1.2, whose buff
--               table lists aura name + spell ID together
--     "nexus"   Daseeki-Nexus tracker.lua, whose live matcher runs these exact
--               names and IDs against real auras every session
--     "rename"  this addon's own 2.0.0 BUFF_RENAMES correction — each of those
--               right-hand values was a name read off a live bar after the
--               original key failed to match
--     "owner"   the owner's in-game screenshot
--     "repo"    a "confirmed Classic Era" identification already carried in this
--               repo (see Addon.BuffSpellDB below)
--     "spell"   the entry IS a player-cast buff spell and its spellID is the aura
--               itself, so the key is that spell's own name by construction
--
--   verify  = <token>   the key is NOT confirmed. It needs ONE in-game read, and
--                       `/dbt auras` prints name + spell ID for everything on the
--                       player right now so the owner can settle a row in seconds.
--     "assumed" the key equals the item/spell name and nothing contradicts it
--     "suspect" a sibling in this same family DOES diverge, so this one may too —
--               these are the rows most likely to be silently broken
--
-- A guessed name is worse than an admitted unknown: a guess that is wrong looks
-- exactly like a correct entry the player has not buffed yet. Nothing here was
-- re-keyed on recollection; only on a source named above. Where no source could be
-- found, the row is flagged rather than "fixed".
-- ================================================================================
Addon.BuffDB = {
    -- ----------------------------------------------------------------
    -- Flasks
    --
    -- Three of the four apply an aura named for the EFFECT, not the flask. The
    -- spec's §1.2 table lists all four names against 17626/17627/17628/17629, and
    -- the owner's screenshot independently confirms 17627 = "Distilled Wisdom".
    -- ----------------------------------------------------------------
    ["Flask of the Titans"]     = { label = "Flask of the Titans",           itemID = 13510, spellID = 17626, nameSrc = "spec" },
    ["Distilled Wisdom"]        = { label = "Flask of Distilled Wisdom",     itemID = 13511, spellID = 17627, nameSrc = "spec+owner" },
    ["Supreme Power"]           = { label = "Flask of Supreme Power",        itemID = 13512, spellID = 17628, nameSrc = "spec+rename" },
    ["Chromatic Resistance"]    = { label = "Flask of Chromatic Resistance", itemID = 13513, spellID = 17629, nameSrc = "spec" },

    -- ----------------------------------------------------------------
    -- Battle Elixirs
    --
    -- A MIXED family, which is why every unconfirmed member here is "suspect" and
    -- not "assumed": "Elixir of the Mongoose" really does keep its full item name
    -- (confirmed by the 2.0.0 rename), while Shadow Power / Fire Power / Greater
    -- Firepower all drop the "Elixir of" prefix. There is no rule to extrapolate
    -- from — each one has to be read.
    -- ----------------------------------------------------------------
    ["Elixir of the Mongoose"]  = { label = "Elixir of the Mongoose",        itemID = 13452, nameSrc = "rename" },
    ["Greater Arcane Elixir"]   = { label = "Greater Arcane Elixir",         itemID = 13454, verify = "suspect" },
    ["Elixir of Brute Force"]   = { label = "Elixir of Brute Force",         itemID = 13453, verify = "suspect" },
    -- itemID + item name corrected from the suite item DBs (Daseeki-Raid-Prep
    -- defaults.lua and Daseeki-Conduit rules.lua both carry 9206 = "Elixir of
    -- Giants"). The 2.1.1 key "Elixir of the Giants" was not even the item's name,
    -- so it could not have matched under any theory; legacy alias below.
    ["Elixir of Giants"]        = { label = "Elixir of Giants",              itemID = 9206,  verify = "suspect" },
    ["Elixir of Greater Agility"] = { label = "Elixir of Greater Agility",   itemID = 9187,  verify = "suspect" },
    ["Elixir of Agility"]       = { label = "Elixir of Agility",             itemID = 8949,  verify = "suspect" },
    ["Elixir of Strength"]      = { label = "Elixir of Strength",            itemID = 3388,  verify = "suspect" },
    ["Elixir of Ogre's Strength"] = { label = "Elixir of Ogre's Strength",   itemID = 3391,  verify = "suspect" },
    -- itemID corrected 11351 -> 9224 (Raid-Prep + Conduit agree). Icon-only field.
    ["Elixir of Demonslaying"]  = { label = "Elixir of Demonslaying",        itemID = 9224,  verify = "suspect" },
    ["Shadow Power"]            = { label = "Elixir of Shadow Power",        itemID = 9264,  verify = "assumed" },
    ["Fire Power"]              = { label = "Elixir of Fire Power",          itemID = 6373,  verify = "assumed" },
    ["Greater Firepower"]       = { label = "Elixir of Greater Fire Power",  itemID = 21546, spellID = 26276, nameSrc = "rename" },
    ["Elixir of the Sages"]     = { label = "Elixir of the Sages",           itemID = 13447, verify = "suspect" },

    -- ----------------------------------------------------------------
    -- Guardian Elixirs
    -- ----------------------------------------------------------------
    ["Elixir of Fortitude"]     = { label = "Elixir of Fortitude",           itemID = 3825,  verify = "suspect" },
    ["Greater Stoneshield"]     = { label = "Greater Stoneshield Potion",    itemID = 13455, verify = "assumed" },
    -- itemID corrected 13445 -> 9233 (Raid-Prep + Conduit agree). Icon-only field.
    ["Elixir of Superior Defense"] = { label = "Elixir of Superior Defense", itemID = 9233,  verify = "suspect" },
    ["Elixir of Greater Defense"] = { label = "Elixir of Greater Defense",   itemID = 8951,  verify = "suspect" },

    -- ----------------------------------------------------------------
    -- Juju (Winterspring)
    --
    -- No member of this family is known to diverge, so these are "assumed" rather
    -- than "suspect" — still unread, but with nothing pointing against them.
    -- The Juju Power spell ID is inherited from 2.0.0 with no recorded source; it
    -- is kept because ID-first matching falls back to the name when an ID misses,
    -- so a stale ID costs nothing and a correct one buys localization safety.
    -- ----------------------------------------------------------------
    ["Juju Power"]              = { label = "Juju Power",                    itemID = 12451, spellID = 16323, verify = "assumed" },
    ["Juju Might"]              = { label = "Juju Might",                    itemID = 12460, verify = "assumed" },
    ["Juju Ember"]              = { label = "Juju Ember",                    itemID = 12455, verify = "assumed" },
    ["Juju Chill"]              = { label = "Juju Chill",                    itemID = 12457, verify = "assumed" },
    ["Juju Flurry"]             = { label = "Juju Flurry",                   itemID = 12464, verify = "assumed" },
    ["Juju Guile"]              = { label = "Juju Guile",                    itemID = 12462, verify = "assumed" },

    -- ----------------------------------------------------------------
    -- Zanza Bijous (Zul'Gurub)
    --
    -- Sheen is the one the spec's §1.2 table names outright (with 24417); its two
    -- siblings follow the same "<X> of Zanza" shape and nothing contradicts them.
    -- ----------------------------------------------------------------
    ["Spirit of Zanza"]         = { label = "Spirit of Zanza",               itemID = 20079, verify = "assumed" },
    ["Sheen of Zanza"]          = { label = "Sheen of Zanza",                itemID = 20080, spellID = 24417, nameSrc = "spec" },
    ["Swiftness of Zanza"]      = { label = "Swiftness of Zanza",            itemID = 20081, verify = "assumed" },

    -- ----------------------------------------------------------------
    -- Silithus / Felwood consumables
    -- ----------------------------------------------------------------
    ["Winterfall Firewater"]    = { label = "Winterfall Firewater",          itemID = 12820, nameSrc = "rename" },

    -- ----------------------------------------------------------------
    -- Dire Maul Tribute consumables
    --
    -- "suspect", and for a concrete reason: the one member of this family whose
    -- aura HAS been read — R.O.I.D.S. — does not match its item name at all
    -- ("Rage of Ages"). The other four are keyed by item name on nothing more than
    -- the shape of the words.
    -- ----------------------------------------------------------------
    ["Rage of Ages"]            = { label = "Rage of Ages (R.O.I.D.S.)",     itemID = 8410,  nameSrc = "rename" },
    ["Ground Scorpok Assay"]    = { label = "Ground Scorpok Assay",          itemID = 8412,  verify = "suspect" },
    ["Cerebral Cortex Compound"] = { label = "Cerebral Cortex Compound",     itemID = 8423,  verify = "suspect" },
    ["Lung Juice Cocktail"]     = { label = "Lung Juice Cocktail",           itemID = 8411,  verify = "suspect" },
    ["Gizzard Gum"]             = { label = "Gizzard Gum",                   itemID = 8413,  verify = "suspect" },

    -- ----------------------------------------------------------------
    -- Food
    --
    -- THE HIGHEST-RISK SECTION IN THE FILE, and the reason is sitting inside it:
    -- two of its own rows are aura-style names ("Well Fed", "Increased Stamina")
    -- while the rest are item names, and one of those pairs shares an item ID with
    -- an item-named row. Classic Era food buffs are widely generic, and the repo
    -- has already CONFIRMED one of them diverging (Nightfin Soup -> "Mana
    -- Regeneration", see Addon.BuffSpellDB) — that entry is gone from this table
    -- and migrated to its spell ID instead.
    --
    -- The remaining duplicate pairs are left BOTH in place, deliberately:
    --   "Well Fed" (20452)          vs "Smoked Desert Dumplings" (20452)
    --   "Increased Stamina" (21023) vs "Dirge's Kickin' Chimaerok Chops" (21023)
    -- One half of each pair is dead weight, but which half is a question only a
    -- live read answers, and deleting the wrong one takes a working entry off a
    -- player. Flagged, not guessed.
    -- ----------------------------------------------------------------
    ["Well Fed"]                = { label = "Well Fed (food buff)",          itemID = 20452, verify = "suspect" },
    ["Increased Stamina"]       = { label = "Increased Stamina (Dirge's)",   itemID = 21023, verify = "suspect" },
    ["Smoked Desert Dumplings"] = { label = "Smoked Desert Dumplings",       itemID = 20452, verify = "suspect" },
    ["Grilled Squid"]           = { label = "Grilled Squid",                 itemID = 13928, verify = "suspect" },
    ["Tender Wolf Steak"]       = { label = "Tender Wolf Steak",             itemID = 18045, verify = "suspect" },
    ["Mightfish Steak"]         = { label = "Mightfish Steak",               itemID = 13851, verify = "suspect" },
    ["Blessed Sunfruit"]        = { label = "Blessed Sunfruit",              itemID = 13810, verify = "suspect" },
    ["Blessed Sunfruit Juice"]  = { label = "Blessed Sunfruit Juice",        itemID = 13813, verify = "suspect" },
    ["Runn Tum Tuber Surprise"] = { label = "Runn Tum Tuber Surprise",       itemID = 18254, verify = "suspect" },
    ["Baked Salmon"]            = { label = "Baked Salmon",                  itemID = 13929, verify = "suspect" },
    ["Dirge's Kickin' Chimaerok Chops"] = { label = "Dirge's Kickin' Chimaerok Chops", itemID = 21023, verify = "suspect" },
    ["Monster Omelet"]          = { label = "Monster Omelet",                itemID = 12218, verify = "suspect" },

    -- ----------------------------------------------------------------
    -- Potions (trackable buff duration)
    --
    -- These are already keyed effect-style (the potion word is dropped), which is
    -- the pattern that holds for protection potions in Classic; "assumed".
    -- Free Action Potion's itemID corrected 5506 -> 5634 (Raid-Prep + Conduit).
    -- ----------------------------------------------------------------
    ["Free Action"]             = { label = "Free Action Potion",            itemID = 5634,  verify = "assumed" },
    ["Limited Invulnerability"] = { label = "Limited Invulnerability Potion", itemID = 3387, verify = "assumed" },
    ["Greater Fire Protection"]   = { label = "Greater Fire Protection Potion",   itemID = 13457, verify = "assumed" },
    ["Greater Frost Protection"]  = { label = "Greater Frost Protection Potion",  itemID = 13456, verify = "assumed" },
    ["Greater Nature Protection"] = { label = "Greater Nature Protection Potion", itemID = 13458, verify = "assumed" },
    ["Greater Shadow Protection"] = { label = "Greater Shadow Protection Potion", itemID = 13459, verify = "assumed" },
    ["Greater Arcane Protection"] = { label = "Greater Arcane Protection Potion", itemID = 13461, verify = "assumed" },
    ["Greater Holy Protection"]   = { label = "Greater Holy Protection Potion",   itemID = 13460, verify = "assumed" },

    -- ----------------------------------------------------------------
    -- World Buffs
    --
    -- The best-evidenced block in the file: every name and ID below is run against
    -- live auras by Daseeki-Nexus tracker.lua every session, and the same pairs
    -- appear in the world-buff spec's §1.2 duration table.
    --
    -- Note the reissue IDs (355363/355365/355366) that Nexus also matches are NOT
    -- carried here: an ID that misses falls through to the name, which is correct
    -- for all three, and a second ID per row has nowhere to live in this shape.
    -- ----------------------------------------------------------------
    ["Rallying Cry of the Dragonslayer"] = { label = "Rallying Cry of the Dragonslayer", spellID = 22888, nameSrc = "spec+nexus" },
    ["Warchief's Blessing"]     = { label = "Warchief's Blessing",           spellID = 16609, nameSrc = "spec+nexus" },
    ["Spirit of Zandalar"]      = { label = "Spirit of Zandalar",            spellID = 24425, nameSrc = "spec+nexus" },
    ["Fengus' Ferocity"]        = { label = "Fengus' Ferocity",              spellID = 22817, nameSrc = "spec+nexus" },
    ["Slip'kik's Savvy"]        = { label = "Slip'kik's Savvy",              spellID = 22820, nameSrc = "spec+nexus" },
    ["Mol'dar's Moxie"]         = { label = "Mol'dar's Moxie",               spellID = 22818, nameSrc = "spec+nexus" },
    ["Songflower Serenade"]     = { label = "Songflower Serenade",           spellID = 15366, nameSrc = "spec+nexus" },
    -- Darkmoon Faire — Sayge's Dark Fortunes. All eight spell IDs match the Nexus
    -- matcher's set exactly; Nexus matches these by the "sayge's dark fortune"
    -- PREFIX only, so the prefix is confirmed and the ID is confirmed — which,
    -- with ID-first matching, is everything that decides a match. The suffix after
    -- "of" is the only unconfirmed part and it is now load-bearing on nothing.
    ["Sayge's Dark Fortune of Damage"]       = { label = "Sayge's Dark Fortune of Damage",       spellID = 23768, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Resistance"]   = { label = "Sayge's Dark Fortune of Resistance",   spellID = 23769, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Agility"]      = { label = "Sayge's Dark Fortune of Agility",      spellID = 23736, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Intelligence"] = { label = "Sayge's Dark Fortune of Intelligence", spellID = 23766, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Spirit"]       = { label = "Sayge's Dark Fortune of Spirit",       spellID = 23738, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Strength"]     = { label = "Sayge's Dark Fortune of Strength",     spellID = 23735, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Stamina"]      = { label = "Sayge's Dark Fortune of Stamina",      spellID = 23737, nameSrc = "spec+nexus" },
    ["Sayge's Dark Fortune of Armor"]        = { label = "Sayge's Dark Fortune of Armor",        spellID = 23767, nameSrc = "spec+nexus" },

    -- ----------------------------------------------------------------
    -- Raid / Party Buffs
    --
    -- "spell": these are player-cast buffs whose spellID IS the aura, so the key is
    -- that spell's own name by construction — there is no item name to diverge
    -- from. What DOES diverge is the RANK: the IDs below are the max rank, and a
    -- lower-rank cast carries a different ID (Daseeki-Armory's mana-regen tables
    -- enumerate six Blessing of Wisdom ranks and four Mana Spring ranks for exactly
    -- this reason). That is precisely why matching is ID-FIRST and not ID-ONLY —
    -- a rank-5 Arcane Intellect misses 10157 and is then caught by the name.
    -- ----------------------------------------------------------------
    ["Power Word: Fortitude"]   = { label = "Power Word: Fortitude",         spellID = 10938, nameSrc = "spell" },
    ["Prayer of Fortitude"]     = { label = "Prayer of Fortitude",           spellID = 21564, nameSrc = "spell" },
    ["Arcane Intellect"]        = { label = "Arcane Intellect",              spellID = 10157, nameSrc = "spell" },
    ["Arcane Brilliance"]       = { label = "Arcane Brilliance",             spellID = 23028, nameSrc = "spell" },
    ["Mage Armor"]              = { label = "Mage Armor",                    spellID = 6117,  nameSrc = "spell" },
    ["Mark of the Wild"]        = { label = "Mark of the Wild",              spellID = 9885,  nameSrc = "spell" },
    ["Gift of the Wild"]        = { label = "Gift of the Wild",              spellID = 21850, nameSrc = "spell" },
    ["Thorns"]                  = { label = "Thorns",                        spellID = 9756,  nameSrc = "spell" },
    ["Blessing of Kings"]       = { label = "Blessing of Kings",             spellID = 20217, nameSrc = "spell" },
    ["Blessing of Might"]       = { label = "Blessing of Might",             spellID = 25291, nameSrc = "spell" },
    ["Greater Blessing of Might"] = { label = "Greater Blessing of Might",   spellID = 25782, nameSrc = "spell" },
    ["Blessing of Wisdom"]      = { label = "Blessing of Wisdom",            spellID = 25290, nameSrc = "spell" },
    ["Greater Blessing of Wisdom"] = { label = "Greater Blessing of Wisdom", spellID = 25894, nameSrc = "spell" },
    ["Blessing of Salvation"]   = { label = "Blessing of Salvation",         spellID = 1038,  nameSrc = "spell" },
    ["Greater Blessing of Salvation"] = { label = "Greater Blessing of Salvation", spellID = 25895, nameSrc = "spell" },
    ["Blessing of Sanctuary"]   = { label = "Blessing of Sanctuary",         spellID = 20911, nameSrc = "spell" },
    ["Greater Blessing of Sanctuary"] = { label = "Greater Blessing of Sanctuary", spellID = 25899, nameSrc = "spell" },
    ["Battle Shout"]            = { label = "Battle Shout",                  spellID = 25289, nameSrc = "spell" },
    ["Trueshot Aura"]           = { label = "Trueshot Aura",                 spellID = 19506, nameSrc = "spell" },
    ["Shadow Protection"]       = { label = "Shadow Protection",             spellID = 10958, nameSrc = "spell" },
    ["Prayer of Shadow Protection"] = { label = "Prayer of Shadow Protection", spellID = 27683, nameSrc = "spell" },
    ["Divine Spirit"]           = { label = "Divine Spirit",                 spellID = 27841, nameSrc = "spell" },
    ["Prayer of Spirit"]        = { label = "Prayer of Spirit",              spellID = 27681, nameSrc = "spell" },
    -- Paladin Auras
    ["Devotion Aura"]           = { label = "Devotion Aura",                 spellID = 10293, nameSrc = "spell" },
    ["Retribution Aura"]        = { label = "Retribution Aura",              spellID = 10301, nameSrc = "spell" },
    ["Concentration Aura"]      = { label = "Concentration Aura",            spellID = 19746, nameSrc = "spell" },
    ["Sanctity Aura"]           = { label = "Sanctity Aura",                 spellID = 20218, nameSrc = "spell" },
    ["Fire Resistance Aura"]    = { label = "Fire Resistance Aura",          spellID = 19900, nameSrc = "spell" },
    ["Frost Resistance Aura"]   = { label = "Frost Resistance Aura",         spellID = 19898, nameSrc = "spell" },
    ["Shadow Resistance Aura"]  = { label = "Shadow Resistance Aura",        spellID = 19896, nameSrc = "spell" },
    -- Shaman Totems. These are the ONE place in this block where key and label
    -- deliberately differ: the totem is cast, but the aura it drops on the party
    -- is named without the word "Totem". That divergence is the same shape as the
    -- flask bug, which is why these cannot claim "spell" — the ID may be the
    -- totem's rather than the aura's. Mana Spring's 10497 IS the aura ID (it is
    -- what Daseeki-Armory reads off UnitAura for its MP5 maths); the other three
    -- are unread, and harmless either way because a missed ID falls back to name.
    ["Strength of Earth"]       = { label = "Strength of Earth Totem",       spellID = 25361, verify = "assumed" },
    ["Grace of Air"]            = { label = "Grace of Air Totem",            spellID = 25359, verify = "assumed" },
    ["Windfury Totem"]          = { label = "Windfury Totem",                spellID = 10613, verify = "assumed" },
    ["Mana Spring"]             = { label = "Mana Spring Totem",             spellID = 10497, verify = "assumed" },
    ["Mana Tide"]               = { label = "Mana Tide Totem",               spellID = 16190, verify = "assumed" },
    -- Hunter
    ["Aspect of the Hawk"]      = { label = "Aspect of the Hawk",            spellID = 25296, nameSrc = "spell" },
    -- Druid
    ["Innervate"]               = { label = "Innervate",                     spellID = 29166, nameSrc = "spell" },
}

-- Buffs that must be identified by spell ID because several sources share the same
-- aura NAME (e.g. Mageblood Potion and Nightfin Soup both apply "Mana Regeneration").
-- Selecting one of these stores item.spellID; matching is then by spell ID ONLY —
-- never by name, because the name is exactly what cannot tell them apart. That
-- strictness is enforced in Addon:GetItemExpiry (main.lua) via
-- Addon:IsAmbiguousAuraSpell, so the ID-first/name-fallback rule that everything
-- else gets is deliberately NOT extended to these.
Addon.BuffSpellDB = {
    -- Mageblood Potion: item 20007 applies aura spell 24363 (confirmed Classic Era).
    { label = "Mageblood Potion", aura = "Mana Regeneration", spellID = 24363, itemID = 20007 },
    -- Nightfin Soup: item 13931 applies the mp5 aura spell 18194 (confirmed Classic Era).
    { label = "Nightfin Soup",    aura = "Mana Regeneration", spellID = 18194, itemID = 13931 },
}

-- ── Legacy key -> current key. THIS TABLE IS THE MIGRATION. ──────────────────────
--
-- Re-keying the catalog is only half a fix: a player whose profile already tracks
-- "Flask of Distilled Wisdom" must keep tracking it, and must not have to notice
-- anything happened. Every key this file has ever renamed is listed here, and it is
-- used TWICE:
--
--   1. main.lua Init() rewrites saved profiles through it, once, on login.
--   2. Addon:GetNamedBuffExpiry consults it at MATCH time as well, so a name that
--      arrives without ever passing through Init() — an imported profile string, a
--      hand-typed old name — still resolves to the right aura and spell ID.
--
-- (2) is the belt to (1)'s braces and costs one table lookup on a miss. Nothing is
-- ever removed from this table: an entry retired here is a player's tracker
-- silently going dead.
Addon.BuffAliases = {
    -- 2.0.0: names read off a live buff bar after the original key never matched.
    ["Mongoose"]                        = "Elixir of the Mongoose",
    ["Firewater"]                       = "Winterfall Firewater",
    ["R.O.I.D.S."]                      = "Rage of Ages",
    ["Mageblood"]                       = "Mana Regeneration",
    ["Greater Fire Power"]              = "Greater Firepower",
    ["Flask of Supreme Power"]          = "Supreme Power",
    -- 2.1.2: the rest of the flask family, keyed by ITEM name in 2.1.1 and so
    -- unable to match the aura the player actually had up.
    ["Flask of Distilled Wisdom"]       = "Distilled Wisdom",
    ["Flask of Chromatic Resistance"]   = "Chromatic Resistance",
    -- 2.1.2: was not the item's name either — the item is "Elixir of Giants".
    ["Elixir of the Giants"]            = "Elixir of Giants",
}

-- ── Legacy key -> an AMBIGUOUS-aura identity (spell ID + display name). ─────────
--
-- A plain alias is the wrong migration when the target aura name is shared by more
-- than one source: rewriting "Nightfin Soup" to the bare name "Mana Regeneration"
-- would make the entry light up for a Mageblood Potion too. These entries are
-- upgraded to the precise spell ID instead — the same shape the 2.0.0 Mageblood
-- upgrade used, and the reason Addon.BuffSpellDB exists.
Addon.BuffSpellUpgrades = {
    ["Nightfin Soup"] = { spellID = 18194, aura = "Mana Regeneration", displayName = "Nightfin Soup" },
}

local WEAPON_ENCHANT_ENTRIES = {
    { buffName = "", label = "Mainhand Enchant", weaponSlot = "mainhand" },
    { buffName = "", label = "Offhand Enchant",  weaponSlot = "offhand"  },
}

-- Returns a sorted list of {buffName, label, itemID, spellID, weaponSlot} entries matching a keyword query.
--
-- The query is also matched against the LEGACY keys, so a player who still thinks
-- of the entry as "Flask of Distilled Wisdom" and types that finds the re-keyed
-- row. Without this, re-keying the catalog would make an entry unfindable by the
-- only name the player knows it by.
function Addon:SearchBuffDB(query)
    query = (query or ""):lower()
    local results = {}
    for _, e in ipairs(WEAPON_ENCHANT_ENTRIES) do
        if query == "" or e.label:lower():find(query, 1, true) then
            results[#results + 1] = e
        end
    end
    -- legacy key -> the current key it now lives under, for the search below
    local legacyFor = {}
    for old, new in pairs(Addon.BuffAliases or {}) do
        legacyFor[new] = legacyFor[new] or {}
        table.insert(legacyFor[new], old:lower())
    end
    for buffName, data in pairs(Addon.BuffDB) do
        local label = data.label or buffName
        local hit = (query == "")
            or buffName:lower():find(query, 1, true) ~= nil
            or label:lower():find(query, 1, true) ~= nil
        if not hit then
            for _, old in ipairs(legacyFor[buffName] or {}) do
                if old:find(query, 1, true) then hit = true; break end
            end
        end
        if hit then
            results[#results + 1] = { buffName = buffName, label = label, itemID = data.itemID, spellID = data.spellID }
        end
    end
    -- Spell-ID-identified buffs (same aura name, different sources)
    for _, e in ipairs(Addon.BuffSpellDB or {}) do
        if query == "" or e.label:lower():find(query, 1, true) or e.aura:lower():find(query, 1, true) then
            results[#results + 1] = { buffName = e.aura, label = e.label, itemID = e.itemID, spellID = e.spellID, bySpell = true }
        end
    end
    table.sort(results, function(a, b) return a.label < b.label end)
    return results
end

-- ── The catalog's own audit, as data. ───────────────────────────────────────────
--
-- Pure: no WoW API, so the harness drives the REAL function rather than restating
-- the table. Returns rows sorted by key, plus a count per status, so a gate can
-- assert "every entry declares its provenance" instead of trusting a comment.
--   status = "verified" (nameSrc present) | "assumed" | "suspect" | "undeclared"
function Addon:AuditBuffDB()
    local rows, counts = {}, { verified = 0, assumed = 0, suspect = 0, undeclared = 0 }
    for key, data in pairs(Addon.BuffDB or {}) do
        local status
        if type(data.nameSrc) == "string" and data.nameSrc ~= "" then
            status = "verified"
        elseif data.verify == "assumed" or data.verify == "suspect" then
            status = data.verify
        else
            status = "undeclared"
        end
        counts[status] = counts[status] + 1
        rows[#rows + 1] = {
            key     = key,
            label   = data.label or key,
            spellID = data.spellID,
            itemID  = data.itemID,
            status  = status,
            source  = data.nameSrc,
        }
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    return rows, counts
end
