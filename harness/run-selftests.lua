-- =====================================================================
-- Daseeki-Buff-Tracker headless migration self-test harness (REAL Lua 5.1)
--
-- Follows the Daseeki suite harness pattern (see Daseeki-ClassHUD/harness):
-- stub the minimal WoW API, load the addon under a real Lua interpreter,
-- drive the REAL migration code, assert data is transformed-not-wiped, exit
-- non-zero on any failure.
--
-- Focus: NW-5 — the DB_VERSION gate no longer wipes user profiles on a
-- data-model bump. The proof is driven through the REAL Addon:MigrateDB and
-- the REAL Addon:Init, not a reimplementation.
--
-- Gates:
--   0        TOC PARSE   loadfile (parse only) every .lua the .toc lists.
--   FW       FIREWALL    no third-party addon identifier in the repo's text.
--   MIG-ALGO migration runner: stamp / newer-left / transform / GAP-NOT-WIPE.
--   MIG-INIT integration: real Addon:Init() preserves pre-existing profiles.
--
-- Usage:  lua5.1 run-selftests.lua [BT_DIR]   (exit 0 = ALL PASS)
-- =====================================================================

local realprint = print   -- kept before the addon's print is captured below

local HARNESS_DIR = (arg[0]:match("^(.*)[\\/][^\\/]+$")) or "."
local function slash(p) return (p:gsub("\\", "/")) end
HARNESS_DIR = slash(HARNESS_DIR)
local DIR = slash(arg[1] or (HARNESS_DIR .. "/.."))
local function P(rel) return DIR .. "/" .. rel end

local TOC_FILE   = "Daseeki-Buff-Tracker.toc"
local ADDON_NAME = "Daseeki-Buff-Tracker"

local FAILS = 0
local function fail(m) FAILS = FAILS + 1; realprint("  FAIL  " .. m) end
local function ok(m)   realprint("  ok    " .. m) end
local function ck(cond, m) if cond then ok(m) else fail(m) end end

local function readFile(path)
    local fh = io.open(path, "r"); if not fh then return nil end
    local s = fh:read("*a"); fh:close(); return s
end

----------------------------------------------------------------------
-- GATE 0: TOC PARSE
----------------------------------------------------------------------
local function readTocLuaFiles(tocPath)
    local fh = io.open(tocPath, "r"); if not fh then return nil end
    local out = {}
    for line in fh:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():sub(-4) == ".lua" then
            out[#out + 1] = (line:gsub("\\", "/"))
        end
    end
    fh:close()
    return out
end

realprint("=== GATE 0: toc parse (loadfile every .lua in " .. TOC_FILE .. ") ===")
local TOC_LUA = readTocLuaFiles(P(TOC_FILE))
if not TOC_LUA or #TOC_LUA == 0 then realprint("  FAIL  cannot read .toc lua list"); os.exit(1) end
for _, rel in ipairs(TOC_LUA) do
    local chunk, err = loadfile(P(rel))
    if chunk then ok("parse " .. rel) else fail("parse " .. rel .. " -> " .. tostring(err)) end
end
if FAILS > 0 then realprint("=== GATE 0: FAIL (a file does not compile) ==="); os.exit(1) end
realprint("=== GATE 0: PASS ===\n")

----------------------------------------------------------------------
-- GATE FW: CLEAN-ROOM FIREWALL
--
-- Product identifiers of absorption-target / 3rd-party addons (not generic
-- words). Buff-Tracker is an ORIGINAL Daseeki addon (not a clean-room rebuild
-- from a 3rd-party spec), so unlike ClassHUD it may reference another addon by
-- name as a descriptive UI-pattern analogy. Those specific, human-reviewed
-- pre-existing comment lines are allowlisted below and reported as notes; ANY
-- other hit — especially in files this change authored — is a hard failure.
----------------------------------------------------------------------
local FORBIDDEN = {
    "portalmage", "totemtimers", "druidbar", "pallypower",
    "weakauras", "weakaurassaved", "aura_env",
    "shadownetwork", "novainstancetracker", "novaworldbuffs",
    "bigwigs", "elvui", "bartender4", "dominos",
}
-- file -> tokens verified to appear ONLY as descriptive analogies in
-- pre-existing original code (frame.lua: "DruidBar-style" anchor storage,
-- "WeakAuras-style" grow direction). Reviewed 2026-08-02; no source copied.
local FW_ALLOW = {
    ["frame.lua"] = { druidbar = true, weakauras = true },
}
realprint("=== GATE FW: clean-room firewall ===")
local FW_FILES = { "CHANGELOG.md", "README.md", TOC_FILE, ".pkgmeta" }
for _, rel in ipairs(TOC_LUA) do FW_FILES[#FW_FILES + 1] = rel end
for _, rel in ipairs(FW_FILES) do
    local src = readFile(P(rel))
    if src then
        local lower = src:lower()
        local allow = FW_ALLOW[rel] or {}
        local bad, noted = {}, {}
        for _, tok in ipairs(FORBIDDEN) do
            if lower:find(tok, 1, true) then
                if allow[tok] then noted[#noted + 1] = tok else bad[#bad + 1] = tok end
            end
        end
        if #bad > 0 then
            fail(rel .. " contains: " .. table.concat(bad, ", "))
        elseif #noted > 0 then
            ok(rel .. " (allowlisted analogy: " .. table.concat(noted, ", ") .. ")")
        else
            ok(rel)
        end
    end
end
if FAILS > 0 then realprint("=== GATE FW: FAIL ==="); os.exit(1) end
realprint("=== GATE FW: PASS ===\n")

----------------------------------------------------------------------
-- Minimal WoW stub — only what main.lua touches at LOAD and in Init().
-- main.lua at load: creates one event frame (RegisterEvent/SetScript) and
-- registers a slash command (SlashCmdList). Init uses print + string methods
-- only (no frame creation).
----------------------------------------------------------------------
_G.print = function() end   -- addon chat output: swallow (harness uses realprint)
_G.CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:GetScript() end
    return f
end
_G.SlashCmdList = {}
_G.strfind, _G.strmatch, _G.strsub, _G.format =
    string.find, string.match, string.sub, string.format

----------------------------------------------------------------------
-- Load the REAL main.lua into a fresh Addon namespace.
----------------------------------------------------------------------
local Addon = {}
do
    local chunk, err = loadfile(P("main.lua"))
    if not chunk then realprint("  FAIL  loadfile main.lua -> " .. tostring(err)); os.exit(2) end
    local success, rerr = pcall(chunk, ADDON_NAME, Addon)
    if not success then realprint("  FAIL  executing main.lua -> " .. tostring(rerr)); os.exit(2) end
end
-- Init seeds class profiles from Addon.ClassDefaults (defined in defaults.lua).
-- The migration proof does not need real class data; stub it empty so the seed
-- loop is a no-op and any surviving profile must be a pre-existing sentinel.
Addon.ClassDefaults = {}

----------------------------------------------------------------------
-- GATE MIG-ALGO: drive the REAL Addon:MigrateDB directly.
----------------------------------------------------------------------
realprint("=== GATE MIG-ALGO: Addon:MigrateDB (stamp / newer / transform / gap-not-wipe) ===")

-- (a) absent dbVersion -> stamp to 3, convert nothing, sentinel survives.
do
    local db = { profiles = { WARRIOR = { __sentinel = true } } }
    local r = Addon:MigrateDB(db)
    ck(r == true, "(a) absent version returns true")
    ck(db.dbVersion == 3, "(a) absent version stamped to current (3)")
    ck(db.profiles.WARRIOR.__sentinel == true, "(a) sentinel profile preserved (no wipe on stamp)")
end

-- (b) newer dbVersion -> left exactly as-is, no downgrade.
do
    local db = { dbVersion = 99, profiles = { MAGE = { __sentinel = true } } }
    local r = Addon:MigrateDB(db)
    ck(r == false, "(b) newer version returns false")
    ck(db.dbVersion == 99, "(b) newer version left as-is (not downgraded)")
    ck(db.profiles.MAGE.__sentinel == true, "(b) sentinel profile untouched")
end

-- (c) older dbVersion WITH a migration step -> ordered transform in place,
--     neighbours preserved, version advanced. Proves the chain transforms.
do
    Addon.MIGRATIONS[2] = function(d) d.__stepran = true end
    local db = { dbVersion = 2, profiles = { ROGUE = { __sentinel = true } } }
    local r = Addon:MigrateDB(db)
    ck(r == true, "(c) older-with-step returns true")
    ck(db.__stepran == true, "(c) migration step actually ran (transform in place)")
    ck(db.dbVersion == 3, "(c) version advanced to current (3)")
    ck(db.profiles.ROGUE.__sentinel == true, "(c) neighbour profile preserved through transform")
    Addon.MIGRATIONS[2] = nil  -- restore shipped (empty) chain
end

-- (d) REGRESSION PROOF: older dbVersion with the shipped EMPTY chain (missing
--     step) -> STOP and leave data UNTOUCHED. The old code wiped exactly here.
do
    local db = {
        dbVersion       = 2,
        profiles        = { PRIEST = { __sentinel = true } },
        charProfiles    = { ["Toon-Realm"] = "PRIEST" },
        charInitialized = { ["Toon-Realm"] = true },
    }
    local r = Addon:MigrateDB(db)
    ck(r == false, "(d) missing-step returns false (does not proceed)")
    ck(db.dbVersion == 2, "(d) version left unchanged (not stamped over a gap)")
    ck(db.profiles ~= nil and db.profiles.PRIEST.__sentinel == true,
       "(d) db.profiles NOT wiped (regression proof vs old nil-out)")
    ck(db.charProfiles ~= nil and db.charProfiles["Toon-Realm"] == "PRIEST",
       "(d) db.charProfiles NOT wiped")
    ck(db.charInitialized ~= nil and db.charInitialized["Toon-Realm"] == true,
       "(d) db.charInitialized NOT wiped")
end
realprint("=== GATE MIG-ALGO: " .. (FAILS == 0 and "PASS" or "FAIL") .. " ===\n")

----------------------------------------------------------------------
-- GATE MIG-INIT: drive the REAL Addon:Init() end to end.
-- A user sitting at v2 with real profiles must keep them across Init().
----------------------------------------------------------------------
realprint("=== GATE MIG-INIT: real Addon:Init() preserves pre-existing data ===")
do
    _G.DaseekiCTDB = {
        dbVersion       = 2,  -- pre-bump user
        settings        = { scale = 1.5 },
        profiles        = { WARRIOR = { items = { { buffName = "Mongoose" } }, __sentinel = true } },
        charProfiles    = { ["Hero-Realm"] = "WARRIOR" },
        charInitialized = { ["Hero-Realm"] = true },
    }
    local success, rerr = pcall(function() Addon:Init() end)
    ck(success, "Init() ran without error" .. (success and "" or (" -> " .. tostring(rerr))))
    local db = _G.DaseekiCTDB
    ck(db.profiles ~= nil and db.profiles.WARRIOR ~= nil and db.profiles.WARRIOR.__sentinel == true,
       "profiles preserved across Init (WARRIOR sentinel intact)")
    ck(db.charProfiles ~= nil and db.charProfiles["Hero-Realm"] == "WARRIOR",
       "charProfiles preserved across Init")
    ck(db.charInitialized ~= nil and db.charInitialized["Hero-Realm"] == true,
       "charInitialized preserved across Init")
    ck(db.settings ~= nil and db.settings.scale == 1.5, "existing settings preserved (scale 1.5)")
    -- The unconditional healing pass still runs: legacy "Mongoose" -> full aura name.
    ck(db.profiles.WARRIOR.items[1].buffName == "Elixir of the Mongoose",
       "existing per-item healing pass still applied (Mongoose renamed)")
end
realprint("=== GATE MIG-INIT: " .. (FAILS == 0 and "PASS" or "FAIL") .. " ===\n")

----------------------------------------------------------------------
realprint("############################################################")
realprint("# Daseeki-Buff-Tracker migration self-tests")
realprint("#   GATE 0        toc parse          : PASS")
realprint("#   GATE FW       clean-room firewall : PASS")
realprint("#   GATE MIG-ALGO migration runner   : " .. (FAILS == 0 and "PASS" or "FAIL"))
realprint("#   GATE MIG-INIT real Init()        : " .. (FAILS == 0 and "PASS" or "FAIL"))
realprint("#")
realprint("#   RESULT: " .. (FAILS == 0 and "ALL PASS" or (FAILS .. " FAILURE(S) — RED")))
realprint("############################################################")
os.exit(FAILS == 0 and 0 or 1)
