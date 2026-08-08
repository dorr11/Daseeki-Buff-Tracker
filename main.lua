local AddonName, Addon = ...
DaseekiCT = Addon

-- ── Field Ledger chat / type helpers (Core-optional; graceful without Daseeki-Core) ──
-- BRAND_SPEC §2 tokens reach chat/HUD through these; each degrades to a legacy literal
-- when Daseeki-Core (DaseekiUI) is absent, so the standalone HUD keeps working unchanged.

-- Token → "|cffRRGGBB" escape prefix for chat strings; nil when Core is absent.
function Addon:Hex(token)
    local UI = _G.DaseekiUI
    if not (UI and UI.Color) then return nil end
    local r, g, b = UI.Color(token)
    local function b255(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x"):format(b255(r), b255(g), b255(b))
end

-- Wrap `text` in a token color for chat strings; plain text if Core is absent.
function Addon:Wrap(token, text)
    local h = Addon:Hex(token)
    if not h then return tostring(text) end
    return h .. tostring(text) .. "|r"
end

-- Brand-tinted chat identity tag (falls back to the legacy cyan tag without Core).
function Addon:Tag(text)
    text = text or "[DaseekiBT]"
    local h = Addon:Hex("brand")
    if h then return h .. text .. "|r" end
    return "|cff00ccff" .. text .. "|r"
end

-- Apply the telemetry numeral (ARIALN+OUTLINE) font to a FontString when Core present;
-- leaves the caller's existing font otherwise (BRAND_SPEC §3 durations → numeral).
function Addon:TrySetNumeral(fs)
    local UI = _G.DaseekiUI
    if UI and UI.fonts and UI.fonts.numeral then
        fs:SetFontObject(UI.fonts.numeral)
        return true
    end
    return false
end

-- ── Tracked-buff reorder drag: which slot is the cursor pointing at? ──────────
--
-- PURE arithmetic, no WoW API, so the harness drives the REAL function. It lives
-- here rather than in options.lua for the same reason MigrateDB does: main.lua is
-- the file the harness loads and drives, options.lua is a frame-construction file
-- it loads last and only to prove the version guard.
--
-- TWO COORDINATE SPACES MEET IN A REORDER DRAG, and mixing them is the defect
-- this seam exists to end:
--
--   GetCursorPosition()          -> RAW screen units, no scale applied.
--   Frame:GetTop()/GetBottom()   -> the FRAME'S OWN effective-scale space.
--
-- A cursor Y may therefore only be compared against a frame's edges after
-- dividing it by THAT frame's effective scale. The tracked-buff list used to
-- divide by UIParent's instead, which agrees only while the list's effective
-- scale happens to equal UIParent's. Nothing scales the options pane today, so
-- the two spaces coincide and the bug is invisible — but the moment anything in
-- the chain from UIParent down to the scroll child takes a SetScale (a list-scale
-- slider, a themed pane scale, a Core window scale), the comparison reads the
-- cursor as (listScale x) its true height above the screen's bottom edge. That
-- error is PROPORTIONAL to height, not a constant offset, so the drop bar would
-- drift further from the pointer the higher up the list you dragged.
-- Daseeki-Raid-Prep shipped exactly this shape and a player hit it the week a
-- List Scale slider landed (Raid Prep 1.3.1); this is the same defect, fixed
-- before it can bite. NOTE that the HUD's own settings.scale is a different
-- frame entirely (frame.lua) and never touched this list — do not be reassured
-- by that when adding a scale control to the options pane.
--
-- Every row shares one parent — the scroll child — so ONE conversion covers the
-- whole list, which is why the seam takes a single `listScale`.
--
-- Pure inputs: `childTop` is the scroll child's GetTop() in the LIST's own
-- space; `rowH` the row pitch (also list space); `count` how many rows are in
-- play; `cursorY` the RAW GetCursorPosition() Y; `listScale` the scroll child's
-- effective scale. Returns the insertion line, 1..count+1 (count+1 = "after the
-- last row"), always a whole number, never nil.
function Addon.ComputeDropLine(childTop, rowH, count, cursorY, listScale)
    count = tonumber(count)
    count = count and math.floor(count) or 0
    if count < 1 then return 1 end

    childTop, cursorY, rowH = tonumber(childTop), tonumber(cursorY), tonumber(rowH)
    -- An unlaid-out list, a cursor the client has not reported yet, or a zero row
    -- pitch: answer "the head" rather than divide by zero or return nil into an
    -- arithmetic caller.
    if not childTop or not cursorY or not rowH or rowH <= 0 then return 1 end

    -- A scale is never 0 or negative in a live client; refuse to divide by one
    -- anyway rather than propagate an inf/NaN into the comparison.
    listScale = tonumber(listScale)
    if not listScale or listScale <= 0 then listScale = 1 end

    local y    = cursorY / listScale     -- the cursor, in the LIST's space
    local relY = childTop - y            -- how far below the list's top edge
    local hRow = math.floor(relY / rowH) -- rows fully above the cursor
    local frac = relY - hRow * rowH      -- how far into the row under the cursor

    -- Upper half of a row inserts BEFORE it, lower half AFTER it. The comparison
    -- is strict, so a cursor exactly on a row's midpoint resolves one way only and
    -- the drop bar cannot flicker between two slots.
    local line = (frac < rowH / 2) and (hRow + 1) or (hRow + 2)

    if line ~= line then return 1 end    -- NaN in (inf - inf), never out
    if line < 1 then return 1 end
    if line > count + 1 then return count + 1 end
    return line
end

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

local DB_VERSION = 3  -- current data-model version; migrations transform in place, never wipe

-- ── SavedVariables migration chain ───────────────────────────────────────────────
-- Stamp-don't-wipe, generalized from the suite template (Daseeki-ClassHUD store.lua
-- Store.Migrate). The next DB_VERSION bump must TRANSFORM a player's saved data, not
-- erase it. MIGRATIONS[n] upgrades a db stamped dbVersion n up to n+1, in place.
--
-- It is EMPTY today on purpose: every existing user is already at v3 with v3-shaped
-- data, so the chain is a no-op. The runner exists now so the FIRST real data-model
-- change is a transform step here, not the old profile wipe. Note the unconditional
-- BUFF_RENAMES / Mageblood-spellID / cachedIcon healing pass further down in Init()
-- already repairs old-shaped item entries on every login — which is exactly why
-- stamping an unknown version to current WITHOUT converting is safe.
--
-- RENAME-AND-PARK: if a future model change is ever genuinely unconvertible, a
-- migration step must PARK the old table (e.g. db.profiles_v3 = db.profiles) rather
-- than nil it — the data stays recoverable. Never reintroduce a destructive wipe.
Addon.MIGRATIONS = {}

-- Migrate db in place. Returns true when it is safe to proceed onto seeding.
--   absent/unknown dbVersion -> stamp to current, convert nothing (seeding fills gaps)
--   dbVersion NEWER than this build -> leave EXACTLY as-is (never downgrade), report
--   dbVersion OLDER -> run MIGRATIONS steps in order; a MISSING step STOPS and leaves
--                      the data untouched (reported) rather than wiping it.
function Addon:MigrateDB(db)
    local from = tonumber(db.dbVersion)
    if from == nil then
        db.dbVersion = DB_VERSION
        return true
    end
    if from > DB_VERSION then
        print(Addon:Tag("[DaseekiBT]") .. " settings were saved by a newer version; left untouched.")
        return false
    end
    while (db.dbVersion or 0) < DB_VERSION do
        local step = Addon.MIGRATIONS[db.dbVersion]
        if not step then
            print(Addon:Tag("[DaseekiBT]") .. " settings could not be upgraded from v"
                .. tostring(db.dbVersion) .. "; left untouched.")
            return false
        end
        step(db)
        db.dbVersion = db.dbVersion + 1
    end
    return true
end

function Addon:Init()
    DaseekiCTDB = DaseekiCTDB or {}
    local db = DaseekiCTDB

    -- Migrate saved data in place before seeding. Never wipes: an unknown version is
    -- stamped, an older one is transformed step-by-step, a newer one is left as-is.
    Addon:MigrateDB(db)

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
    --
    -- The map itself lives in buffs.lua beside the catalog it migrates, because the
    -- two are one fact: a catalog re-key without its alias is a player's tracker
    -- going quietly dead. Keeping them in the same file is what makes it hard to do
    -- one and forget the other. `or {}` so a stripped install degrades to "rename
    -- nothing" rather than erroring inside the boot path.
    local BUFF_RENAMES  = Addon.BuffAliases or {}
    local BUFF_UPGRADES = Addon.BuffSpellUpgrades or {}
    for _, profile in pairs(db.profiles or {}) do
        for _, item in ipairs(profile.items or {}) do
            -- BT-1: track whether THIS pass rewrote the aura name, because the icon
            -- cache below was learned by matching that name in a live UnitBuff scan.
            -- A rename destroys the cache's entire provenance, and until now the two
            -- healing passes sat in this very loop and did not talk to each other:
            -- an icon learned under "Mageblood" was kept forever under
            -- "Mana Regeneration", and survived a profile export/import.
            local renamed = false

            -- AMBIGUOUS-AURA UPGRADE, before the plain renames. A catalog key whose
            -- real aura name is SHARED by more than one source cannot be migrated
            -- with a plain alias: rewriting "Nightfin Soup" to the bare name
            -- "Mana Regeneration" would make the entry satisfied by a Mageblood
            -- Potion. It is upgraded to the precise spell ID instead — the same
            -- shape the 2.0.0 Mageblood upgrade below uses.
            if not item.spellID and not item.weaponSlot then
                local legacy = (item.buffNames and item.buffNames[1]) or item.buffName
                local up = legacy and BUFF_UPGRADES[legacy]
                if up then
                    -- Only adopt the canned display name when the player has not
                    -- given the entry one of their own; a custom label is theirs.
                    local dn = item.displayName
                    if dn == nil or dn == "" or dn == legacy then item.displayName = up.displayName end
                    item.spellID   = up.spellID
                    item.buffName  = nil
                    item.buffNames = { up.aura }
                    renamed = true
                end
            end

            if item.buffName and BUFF_RENAMES[item.buffName] then
                item.buffName = BUFF_RENAMES[item.buffName]
                renamed = true
            end
            if item.buffNames then
                for i, n in ipairs(item.buffNames) do
                    if BUFF_RENAMES[n] then item.buffNames[i] = BUFF_RENAMES[n]; renamed = true end
                end
            end
            -- Legacy Mageblood tracking was name-only; before Nightfin existed the
            -- only "Mana Regeneration" source was Mageblood, so upgrade it to the
            -- precise spell ID (24363) now that same-name buffs are distinguished.
            -- GATE: only upgrade the actual legacy Mageblood tracker. We must NOT
            -- convert a deliberately-created Nightfin Soup entry (or a user who typed
            -- "Mana Regeneration" meaning Nightfin) into Mageblood. The BUFF_RENAMES
            -- pass above has already rewritten the aura name from "Mageblood" to
            -- "Mana Regeneration", so the only surviving signal of the legacy source is
            -- the displayName, which stays "Mageblood Potion" for the legacy tracker.
            if not item.spellID and not item.weaponSlot then
                -- Handle both the single-string legacy buffName and the buffNames array.
                local primary = (item.buffNames and item.buffNames[1]) or item.buffName
                local dn = (item.displayName or ""):lower()
                if primary == "Mana Regeneration" and dn:find("mageblood", 1, true) then
                    item.spellID     = 24363
                    item.displayName = "Mageblood Potion"
                    item.buffName    = nil
                    item.buffNames   = { "Mana Regeneration" }
                    renamed = true
                end
            end

            -- A shape check is not a correctness check.
            if type(item.cachedIcon) ~= "string" then item.cachedIcon = nil end
            if renamed then
                -- The name it was learned under no longer exists on this item.
                item.cachedIcon, item.cachedIconFor = nil, nil
            elseif item.cachedIcon and item.cachedIconFor == nil then
                -- One-shot backfill for profiles saved before the stamp existed.
                -- The name was NOT rewritten by this pass, so "it was learned under
                -- the name this item still carries" is a true statement about it --
                -- which is exactly why it is only made for the untouched items.
                item.cachedIconFor = (item.buffNames and item.buffNames[1]) or item.buffName
            end
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

    print(Addon:Tag("Daseeki Buff Tracker") .. " loaded. Profile: " .. Addon:Wrap("text", Addon:GetActiveProfile() or "none") .. "  " .. Addon:Wrap("text", "/dbt") .. " for options.")
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

-- BT-2. Returns seconds remaining on a TEMPORARY weapon enchant, or nil.
--
-- nil means one of two things, and the caller is expected to tell them apart with
-- Addon:HasWeaponEnchant: no enchant at all, or an enchant that is there but whose
-- remaining time the client did not answer for. What it must NEVER mean is
-- "forever". This used to fall back to math.huge when the expiry came back nil --
-- rendering "I could not read it" as "this never expires", which is the wrong
-- direction: an unknown read as permanently fine, on a buff that is about to drop.
-- Unlike GetBuffExpiry/GetSpellExpiry, where expirationTime == 0 genuinely means
-- permanent in that API, GetWeaponEnchantInfo only ever reports TEMPORARY enchants
-- -- there is no permanent case here for math.huge to stand for.
function Addon:GetWeaponEnchantSecondsRemaining(slot)
    local hasMH, mhExpiry, _, _, hasOH, ohExpiry = GetWeaponEnchantInfo()
    if slot == "mainhand" and hasMH then
        return mhExpiry and (mhExpiry / 1000) or nil
    end
    if slot == "offhand" and hasOH then
        return ohExpiry and (ohExpiry / 1000) or nil
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

-- ── SPELL-ID-FIRST AURA MATCHING ────────────────────────────────────────────────
--
-- A tracked entry stores an aura NAME, and a name is the weakest identity the game
-- offers: it is localized (a German client's flask is not called "Distilled
-- Wisdom"), and it drifts (three catalog keys in this addon's history turned out
-- never to have matched anything). A spell ID is none of those things.
--
-- So the rule, the same one Daseeki-Nexus's world-buff matcher settled on and for
-- the same reasons: try the catalog's spell ID FIRST, fall back to the name. Not
-- ID-only — ID-only would be a downgrade here, because the IDs in the catalog are
-- max-rank and a rank-5 Arcane Intellect carries a different one. The name catches
-- exactly that case, and entries with no ID at all are unaffected.
--
-- The one deliberate exception is Addon.BuffSpellDB (Mageblood vs Nightfin, both
-- "Mana Regeneration"): those are ID-ONLY, enforced in Addon:GetItemExpiry.

-- True when this spell ID names an aura whose NAME is shared by more than one
-- source, and therefore cannot stand in for the ID.
function Addon:IsAmbiguousAuraSpell(spellID)
    if not spellID then return false end
    for _, e in ipairs(Addon.BuffSpellDB or {}) do
        if e.spellID == spellID then return true end
    end
    return false
end

-- The catalog row for a tracked aura NAME, or nil.
--
-- A legacy key is followed through Addon.BuffAliases on the way, which is what
-- lets a name that never passed through Init()'s migration — an imported profile
-- string, a hand-typed old name — still find its row.
function Addon:GetCatalogEntry(buffName)
    if not buffName or buffName == "" then return nil end
    local db = Addon.BuffDB
    if not db then return nil end
    local e = db[buffName]
    if e then return e end
    local canon = Addon.BuffAliases and Addon.BuffAliases[buffName]
    return canon and db[canon] or nil
end

-- The catalog's aura spell ID for a tracked aura NAME, or nil.
function Addon:GetCatalogSpellID(buffName)
    local e = Addon:GetCatalogEntry(buffName)
    return e and e.spellID or nil
end

-- Seconds remaining for ONE tracked aura name: spell ID first, name second.
-- nil = not present; math.huge = permanent.
function Addon:GetNamedBuffExpiry(buffName)
    local spellID = Addon:GetCatalogSpellID(buffName)
    if spellID then
        local secs = Addon:GetSpellExpiry(spellID)
        if secs ~= nil then return secs end
    end
    return Addon:GetBuffExpiry(buffName)
end

-- Returns the BEST (maximum) remaining seconds across all buff names in the list.
-- nil = none are active; math.huge = at least one is permanent.
function Addon:GetMultiBuffExpiry(buffNames)
    local best = nil
    for _, name in ipairs(buffNames) do
        local secs = Addon:GetNamedBuffExpiry(name)
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

-- Returns seconds remaining if an aura with the given spell ID is present
-- (math.huge if permanent), nil if missing. Used to distinguish buffs that share
-- the same aura name (e.g. Mageblood Potion vs Nightfin Soup = "Mana Regeneration").
function Addon:GetSpellExpiry(spellID)
    if not spellID then return nil end
    for i = 1, 40 do
        -- Classic Era UnitBuff: name, icon, count, dispel, duration, expiration, source, isStealable, nameplate, spellId
        local name, _, _, _, _, expirationTime, _, _, _, auraSpellID = UnitBuff("player", i)
        if not name then break end
        if auraSpellID == spellID then
            if expirationTime and expirationTime > 0 then
                return expirationTime - GetTime()
            end
            return math.huge
        end
    end
    return nil
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

-- ── The ONE place a tracked entry's remaining time is decided. ──────────────────
--
-- Returns (seconds, tracked):
--   tracked = false  the entry names nothing at all — no spell ID, no aura names.
--                    It is not "missing", it is not being tracked, and the caller
--                    must not draw a reminder for it. This is the case the two
--                    frame.lua call sites used to answer with a bare `return
--                    false` and is the reason this returns a second value at all.
--   seconds = nil    tracked, and the aura is ABSENT -> reminder.
--   seconds          remaining, or math.huge when the aura has no expiry.
--
-- Weapon-enchant entries are NOT handled here; they come from
-- GetWeaponEnchantInfo, which is a different API with a different unknown (BT-2),
-- and folding them in would blur two nils that mean different things.
function Addon:GetItemExpiry(item)
    if item.spellID then
        local secs = Addon:GetSpellExpiry(item.spellID)
        if secs ~= nil then return secs, true end
        -- STRICT: an ambiguous-aura entry may not fall back to its name. "Mana
        -- Regeneration" is exactly what cannot tell a Mageblood Potion from a bowl
        -- of Nightfin Soup, so letting the name answer here would report the
        -- Mageblood tracker satisfied by the soup. Stop at the ID.
        if Addon:IsAmbiguousAuraSpell(item.spellID) then return nil, true end
    end
    local names = Addon:GetBuffNames(item)
    if #names > 0 then
        return Addon:GetMultiBuffExpiry(names), true
    end
    -- An entry with a spell ID but no names is still tracked, by that ID alone.
    if item.spellID then return nil, true end
    return nil, false
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
    -- Spell-ID-identified entry: resolve via active aura, then item, then spell.
    if item.spellID then
        for i = 1, 40 do
            local name, icon, _, _, _, _, _, _, _, sid = UnitBuff("player", i)
            if not name then break end
            if sid == item.spellID then return icon end
        end
        -- Prefer an item icon (the click item, else the source item from BuffSpellDB)
        local iconItemID = (item.itemID and item.itemID > 0) and item.itemID or nil
        if not iconItemID and Addon.BuffSpellDB then
            for _, e in ipairs(Addon.BuffSpellDB) do
                if e.spellID == item.spellID then iconItemID = e.itemID; break end
            end
        end
        if iconItemID then
            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(iconItemID)
            if tex then return tex end
        end
        local _, _, sicon = GetSpellInfo(item.spellID)
        if sicon then return sicon end
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local primaryBuff = Addon:GetBuffNames(item)[1]
    -- BT-1: the cache below is learned by matching an aura NAME in a live UnitBuff
    -- scan, and it is PERSISTED into the profile. It is therefore only valid for
    -- the name it was learned under -- so it carries that name as its stamp, and is
    -- served only while the stamp still agrees with the name being resolved now.
    -- A rename (by the healing pass at Init, or by the player editing the entry)
    -- makes the stamp disagree, and a disagreement re-learns rather than latching.
    -- An unstamped cache is one whose provenance we cannot vouch for.
    if type(item.cachedIcon) == "string" and primaryBuff and primaryBuff ~= ""
       and item.cachedIconFor == primaryBuff then
        return item.cachedIcon
    end
    item.cachedIcon, item.cachedIconFor = nil, nil
    -- 1. Active buff scan — most accurate and caches for this session
    if primaryBuff and primaryBuff ~= "" then
        for i = 1, 40 do
            local name, icon = UnitBuff("player", i)
            if not name then break end
            if name == primaryBuff then
                item.cachedIcon    = icon
                item.cachedIconFor = primaryBuff   -- the evidence that produced it
                return icon
            end
        end
    end
    -- 2. BuffDB lookup by primary buff name — correct icon regardless of stored
    --    itemID, and through the legacy alias so a not-yet-migrated name (an
    --    imported profile) still draws the right icon rather than a question mark.
    if primaryBuff then
        local dbEntry = Addon:GetCatalogEntry(primaryBuff)
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

-- ── /dbt auras — settle a flagged catalog row in one line. ─────────────────────
--
-- buffs.lua flags every key whose aura name has never actually been read off a live
-- bar (`verify = "assumed" | "suspect"`). Those rows cannot be resolved by
-- reasoning, only by looking — so this prints exactly what UnitBuff() is returning
-- right now: the aura's NAME, its spell ID, and whether this catalog already knows
-- that name. Drink the consumable, run this, and the row is settled.
--
-- The "(catalog: ...)" column is the whole point of it. A line reading
--   03  Distilled Wisdom  id=17627  (catalog: Flask of Distilled Wisdom)
-- says the entry matches; a line reading
--   03  Distilled Wisdom  id=17627  (catalog: UNKNOWN NAME)
-- is a mismatch caught in one look, which is the defect this addon shipped for two
-- flasks without anyone being able to see it.
function Addon:DumpAuras()
    print(Addon:Tag("[DaseekiBT]") .. " auras on you right now (name / spell ID / catalog):")
    local n = 0
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
        if not name then break end
        n = n + 1
        local entry = Addon:GetCatalogEntry(name)
        local known
        if entry then
            known = entry.label or name
        else
            -- The name is unknown, but the ID may still be catalogued under a
            -- DIFFERENT key — which is precisely the mismatch shape worth naming.
            local byID
            for key, data in pairs(Addon.BuffDB or {}) do
                if spellID and data.spellID == spellID then byID = key; break end
            end
            known = byID and ("UNKNOWN NAME — id is keyed as \"" .. byID .. "\"") or "not in catalog"
        end
        print(("  %02d  %s   id=%s   (catalog: %s)")
            :format(i, tostring(name), tostring(spellID or "?"), known))
    end
    if n == 0 then print("  (no buffs active)") end
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
            print(Addon:Tag("[DaseekiBT]") .. " Install Daseeki Core for the options window.")
        end
    elseif msg == "toggle" then
        local f = Addon.mainFrame
        if f then
            if f:IsShown() then f:Hide() else f:Show() end
        end
    elseif msg == "lock" then
        Addon.db.settings.locked = not Addon.db.settings.locked
        Addon:UpdateFrameLock()
        print(Addon:Tag("[DaseekiBT]") .. " Frame " .. (Addon.db.settings.locked and "locked" or "unlocked"))
    elseif msg == "reset" then
        Addon.db.settings.point    = DEFAULT_SETTINGS.point
        Addon.db.settings.relPoint = DEFAULT_SETTINGS.relPoint
        Addon.db.settings.posX     = DEFAULT_SETTINGS.posX
        Addon.db.settings.posY     = DEFAULT_SETTINGS.posY
        Addon:PositionFrame()
        print(Addon:Tag("[DaseekiBT]") .. " Frame position reset.")
    elseif msg == "auras" then
        Addon:DumpAuras()
    else
        print(Addon:Tag("[DaseekiBT]") .. " /dbt [options|toggle|lock|reset|auras]")
    end
end
