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
--   CORE-GUARD RegisterOptions routes its version check through
--            DaseekiSuite.RequireCore("2.0.0") and degrades safely on an
--            older Core that has no such guard.
--   DRAG     tracked-buff reorder hit-test: the cursor is compared in the
--            LIST'S coordinate space, so a scaled options pane can no longer
--            drift the drop bar away from the pointer (the shipped 2.1.1
--            arithmetic is kept as a red control).
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

-- Per-gate verdict, taken from the DELTA in FAILS across the gate rather than
-- from the running total (the Daseeki-Raid-Prep harness pattern). Every gate
-- below used to print `FAILS == 0`, so one failure anywhere reported every LATER
-- gate as FAIL too — a green gate could be accused of a red one's failure, and
-- the summary block named the wrong culprit. The checks themselves were always
-- honest; only the attribution was not.
local GATE_MARK = 0
local function gateBegin(title) GATE_MARK = FAILS; realprint("=== " .. title .. " ===") end
local function gateEnd(name)
    local verdict = (FAILS == GATE_MARK) and "PASS" or "FAIL"
    realprint("=== GATE " .. name .. ": " .. verdict .. " ===\n")
    return verdict
end

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

gateBegin("GATE 0: toc parse (loadfile every .lua in " .. TOC_FILE .. ")")
local TOC_LUA = readTocLuaFiles(P(TOC_FILE))
if not TOC_LUA or #TOC_LUA == 0 then realprint("  FAIL  cannot read .toc lua list"); os.exit(1) end
for _, rel in ipairs(TOC_LUA) do
    local chunk, err = loadfile(P(rel))
    if chunk then ok("parse " .. rel) else fail("parse " .. rel .. " -> " .. tostring(err)) end
end
if FAILS > 0 then realprint("=== GATE 0: FAIL (a file does not compile) ==="); os.exit(1) end
local V_TOC = gateEnd("0")

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
gateBegin("GATE FW: clean-room firewall")
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
local V_FW = gateEnd("FW")

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
-- AURA / WEAPON-ENCHANT WORLD (data-honesty §5: "ABSENT for the icon path").
--
-- The audit's verdict on this harness was that no GetItemInfo, UnitBuff or
-- C_Container stubs existed at all, so the icon-resolution ladder and cachedIcon
-- were unmodelled -- which is why BT-1 survived. What it asked for: enough of a
-- UnitBuff surface to LEARN an icon, then a rename applied by the BUFF_RENAMES
-- pass, then an assertion that the stale icon did NOT survive it.
--
-- Unkind by default: the rest of the icon ladder (BuffDB, GetSpellInfo,
-- GetItemInfo) answers NOTHING, so what GetBuffIcon returns is decided purely by
-- the aura scan and the cache -- which is the behaviour under test.
----------------------------------------------------------------------
local AURAS = {}                            -- { {name=, icon=, expires=, spellID=}, ... }
local function setAuras(t) AURAS = t or {} end
_G.UnitBuff = function(_, i)
    local a = AURAS[i]
    if not a then return nil end
    return a.name, a.icon, 1, nil, nil, a.expires, nil, nil, nil, a.spellID
end
_G.GetTime = function() return 1000 end
_G.GetSpellInfo = function() return nil end
_G.GetItemInfo  = function() return nil end
_G.GetInventoryItemTexture = function() return nil end

-- GetWeaponEnchantInfo returns hasMH, mhExpiry(ms), mhCharges, mhEnchantID,
-- hasOH, ohExpiry(ms), ... A present enchant whose expiry reads nil is the exact
-- shape BT-2 turned into "this never expires".
local ENCH = { hasMH = false, mhExpiry = nil, hasOH = false, ohExpiry = nil }
local function setEnchant(t) ENCH = t or {} end
_G.GetWeaponEnchantInfo = function()
    return ENCH.hasMH, ENCH.mhExpiry, 0, 0, ENCH.hasOH, ENCH.ohExpiry, 0, 0
end

----------------------------------------------------------------------
-- Load the REAL main.lua into a fresh Addon namespace.
----------------------------------------------------------------------
local Addon = {}
do
    -- buffs.lua FIRST, matching the .toc order. It is no longer optional scenery:
    -- Init()'s rename pass now reads Addon.BuffAliases out of it, and the whole
    -- AURA gate drives the REAL catalog rather than a restatement of it.
    for _, f in ipairs({ "buffs.lua", "main.lua" }) do
        local chunk, err = loadfile(P(f))
        if not chunk then realprint("  FAIL  loadfile " .. f .. " -> " .. tostring(err)); os.exit(2) end
        local success, rerr = pcall(chunk, ADDON_NAME, Addon)
        if not success then realprint("  FAIL  executing " .. f .. " -> " .. tostring(rerr)); os.exit(2) end
    end
end
-- Init seeds class profiles from Addon.ClassDefaults (defined in defaults.lua).
-- The migration proof does not need real class data; stub it empty so the seed
-- loop is a no-op and any surviving profile must be a pre-existing sentinel.
Addon.ClassDefaults = {}

----------------------------------------------------------------------
-- GATE MIG-ALGO: drive the REAL Addon:MigrateDB directly.
----------------------------------------------------------------------
gateBegin("GATE MIG-ALGO: Addon:MigrateDB (stamp / newer / transform / gap-not-wipe)")

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
local V_ALGO = gateEnd("MIG-ALGO")

----------------------------------------------------------------------
-- GATE MIG-INIT: drive the REAL Addon:Init() end to end.
-- A user sitting at v2 with real profiles must keep them across Init().
----------------------------------------------------------------------
gateBegin("GATE MIG-INIT: real Addon:Init() preserves pre-existing data")
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
local V_INIT = gateEnd("MIG-INIT")

----------------------------------------------------------------------
-- GATE CORE-GUARD: Addon:RegisterOptions asks Core for the version.
--
-- The settings page used to hand-roll "requires Daseeki Core v2.0.0" out of a
-- capability probe alone, so it could never name the version a player actually
-- had. It now calls DaseekiSuite.RequireCore("2.0.0", ...) — the suite-wide guard
-- Core 2.2.0 introduced — TYPE-GUARDED, because a Core old enough to fail the
-- check is also old enough to lack the guard itself. Drive the real function
-- through every state a player can be in.
--
-- Loading options.lua LAST is deliberate: it must not perturb the migration
-- gates above, and RegisterAddon is stubbed so no pane is ever built.
----------------------------------------------------------------------
gateBegin("GATE CORE-GUARD: RegisterOptions version guard")
do
    local chunk, err = loadfile(P("options.lua"))
    if not chunk then
        fail("loadfile options.lua -> " .. tostring(err))
    else
        local loaded, lerr = pcall(chunk, ADDON_NAME, Addon)
        ck(loaded, "options.lua loads" .. (loaded and "" or (" -> " .. tostring(lerr))))
        ck(type(Addon.RegisterOptions) == "function", "Addon:RegisterOptions is defined")
    end

    -- Recording print, so we can assert WHO speaks in each state.
    local said = {}
    local swallow = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(parts, " ")
    end

    local asked          -- { minVersion, caller } captured from RequireCore
    local registered     -- the def table RegisterAddon received

    -- opts.requireCore: nil = Core predates the guard | true/false = its verdict
    --                   "raise" = a Core whose guard errors
    -- opts.ui:          truthy = DaseekiUI with a Token (the 2.0.0 toolkit present)
    local function scenario(opts)
        asked, registered, said = nil, nil, {}
        _G.DaseekiUI = opts.ui and { Token = function() end } or nil
        if opts.suite == false then
            _G.DaseekiSuite = nil
        else
            local S = { RegisterAddon = function(_, def) registered = def end }
            if opts.requireCore ~= nil then
                S.RequireCore = function(minVersion, caller)
                    if opts.requireCore == "raise" then error("simulated stale-Core blowup") end
                    asked = { min = minVersion, caller = caller }
                    return opts.requireCore
                end
            end
            _G.DaseekiSuite = S
        end
        return pcall(function() Addon:RegisterOptions() end)
    end

    -- (a) No Core at all: silent no-op, never an error.
    local okRun = scenario({ suite = false })
    ck(okRun, "(a) no DaseekiSuite: does not raise")
    ck(registered == nil, "(a) no DaseekiSuite: nothing registered")

    -- (b) Modern Core that is TOO OLD: Core owns the message, we just stand down.
    okRun = scenario({ requireCore = false, ui = true })
    ck(okRun, "(b) stale Core: does not raise")
    ck(registered == nil, "(b) stale Core: page not registered")
    ck(#said == 0, "(b) stale Core: no duplicate line — Core already spoke")

    -- (c) Modern Core, guard satisfied: the page registers, and it asks for
    --     EXACTLY 2.0.0. This is the anti-inflation pin: nothing on this page
    --     touches the 2.2.0 ledger kit, so requiring 2.2.0 would switch it off
    --     for a Core that runs it perfectly well.
    okRun = scenario({ requireCore = true, ui = true })
    ck(okRun, "(c) current Core: does not raise")
    ck(registered ~= nil and registered.id == "bufftracker", "(c) current Core: page registered")
    ck(asked ~= nil and asked.min == "2.0.0", "(c) minimum asked for is 2.0.0, not inflated")
    ck(asked ~= nil and type(asked.caller) == "string" and asked.caller ~= "",
       "(c) a caller label is passed so Core's line names the feature")

    -- (d) Core PREDATES RequireCore and the toolkit is absent: the capability
    --     probe is the last word and we say it ourselves, once.
    okRun = scenario({ requireCore = nil, ui = false })
    ck(okRun, "(d) pre-RequireCore Core, no DaseekiUI: does not raise")
    ck(registered == nil, "(d) pre-RequireCore Core, no DaseekiUI: page not registered")
    ck(#said == 1, "(d) pre-RequireCore Core: the addon speaks once (Core cannot)")

    -- (e) A Core whose guard ERRORS must not take the addon down with it; the
    --     probe still decides. RequireCore is called through pcall for this.
    okRun = scenario({ requireCore = "raise", ui = true })
    ck(okRun, "(e) erroring RequireCore: does not raise")
    ck(registered ~= nil, "(e) erroring RequireCore: falls through to the probe and registers")

    _G.print = swallow
    _G.DaseekiSuite, _G.DaseekiUI = nil, nil
end
local V_GUARD = gateEnd("CORE-GUARD")

----------------------------------------------------------------------
-- GATE DRAG: tracked-buff reorder hit-test across scale combinations.
--
-- GetCursorPosition() returns RAW screen units; child:GetTop() returns in the
-- scroll child's OWN effective-scale space. The shipped ticker divided the cursor
-- by UIParent's scale and compared the result against child:GetTop() and
-- BUFF_ROW_H, which agrees only while the list's effective scale equals
-- UIParent's.
--
-- Nothing scales the Buff Tracker options pane today, so this was LATENT here —
-- but it is byte-for-byte the shape that broke live in Daseeki-Raid-Prep the week
-- a "List Scale" slider gave the row chain a SetScale (fixed in Raid Prep 1.3.1,
-- reported by a player with a screenshot). The error is PROPORTIONAL to height
-- above the screen's bottom edge, not a constant offset, so the drop bar drifts
-- further the higher up the list you drag.
--
-- The arithmetic lives as a pure seam, Addon.ComputeDropLine in main.lua — the
-- file this harness loads and drives, following the MigrateDB precedent, with
-- options.lua left as the frame-construction file it is. The REAL function is
-- driven below against the SHIPPED 2.1.1 arithmetic kept here as a RED CONTROL,
-- so these checks demonstrate the defect rather than merely assert the fix.
----------------------------------------------------------------------
gateBegin("GATE DRAG: reorder hit-test under list / UI scale divergence")

local V_DRAG
do
    ck(type(Addon.ComputeDropLine) == "function",
       "(a) Addon.ComputeDropLine published as a pure seam")

    local DropLine = Addon.ComputeDropLine
    local ROW_H = 30            -- BUFF_ROW_H
    local TOP   = 500           -- child:GetTop() in the LIST's own space

    -- The SHIPPED 2.1.1 arithmetic, verbatim in spirit: cursor converted with
    -- UIParent's scale, compared against a list-space top edge.
    local function oldDropLine(childTop, rowH, count, cursorY, uiScale)
        local my   = cursorY / uiScale
        local relY = childTop - my
        local hRow = math.floor(relY / rowH)
        local frac = relY - hRow * rowH
        local line = (frac < rowH / 2) and (hRow + 1) or (hRow + 2)
        return math.max(1, math.min(count + 1, line))
    end

    -- What the player is pointing at, derived from the GEOMETRY rather than from
    -- the implementation: rows run downward from childTop at rowH pitch, and the
    -- half of a row the cursor is in decides before/after.
    local function expected(childTop, rowH, count, listSpaceY)
        local relY = childTop - listSpaceY
        local hRow = math.floor(relY / rowH)
        local line = (relY - hRow * rowH < rowH / 2) and (hRow + 1) or (hRow + 2)
        return math.max(1, math.min(count + 1, line))
    end

    -- The client's raw cursor Y for a point the player SEES at `listSpaceY`.
    local function rawFor(listSpaceY, uiScale, paneScale) return listSpaceY * uiScale * paneScale end

    -- THE IEEE754 SAMPLING TRAP (documented in Raid Prep's GATE DRAG): the sweeps
    -- below step in list space from a HALF-INTEGER offset. Row midpoints sit at
    -- integer list-space heights (TOP - 15 - 30k), so a half-integer sample can
    -- never land on one. Sitting exactly on a boundary would make a
    -- multiply-then-divide round trip decide the strict `<` on the last bit of a
    -- float — that tests IEEE754, not the hit-test. The boundary itself is pinned
    -- separately in (g), at scale 1, where the round trip is exact.
    local function sweepNew(ui, pane, count, childTop)
        local bad = 0
        for k = 0, 79 do
            local y = childTop - (0.5 + 3 * k)
            if DropLine(childTop, ROW_H, count, rawFor(y, ui, pane), ui * pane)
               ~= expected(childTop, ROW_H, count, y) then bad = bad + 1 end
        end
        return bad
    end
    local function sweepOld(ui, pane, count, childTop)
        local bad = 0
        for k = 0, 79 do
            local y = childTop - (0.5 + 3 * k)
            if oldDropLine(childTop, ROW_H, count, rawFor(y, ui, pane), ui)
               ~= expected(childTop, ROW_H, count, y) then bad = bad + 1 end
        end
        return bad
    end

    -- (b) BASELINE — everything at parity, which is every Buff Tracker install
    --     TODAY. Old and new must AGREE here, or the fix would be a regression for
    --     the untouched majority. This is the "nothing changed at scale 1" pin.
    ck(sweepNew(1.0, 1.0, 6, TOP) == 0,
       "(b) scale 1 everywhere: every sampled cursor lands on the slot it is over")
    ck(sweepOld(1.0, 1.0, 6, TOP) == 0,
       "(b) at parity the OLD math was right too — this fix changes NOTHING today")
    do
        local same = true
        for k = 0, 79 do
            local y = TOP - (0.5 + 3 * k)
            if DropLine(TOP, ROW_H, 6, y, 1.0) ~= oldDropLine(TOP, ROW_H, 6, y, 1.0) then same = false end
        end
        ck(same, "(b) old and new are the SAME function at scale 1 — a latent fix, not a behaviour change")
    end

    -- (c) THE LATENT DEFECT — the list chain takes a 0.8 SetScale. The old math
    --     must be visibly WRONG here; that is the whole point of keeping it.
    do
        local y    = TOP - 75.5                 -- row 3's lower half at a 30px pitch
        local raw  = rawFor(y, 1.0, 0.8)
        local want = expected(TOP, ROW_H, 6, y)
        ck(want == 4, "(c) fixture sanity: 75.5px down a 30px pitch is row 3's lower half -> line 4")
        ck(DropLine(TOP, ROW_H, 6, raw, 1.0 * 0.8) == want,
           "(c) list scaled to 80%: the seam still returns the slot under the pointer")
        ck(oldDropLine(TOP, ROW_H, 6, raw, 1.0) ~= want,
           "(c) RED CONTROL: the shipped math does NOT return that slot")
        ck(oldDropLine(TOP, ROW_H, 6, raw, 1.0) > want,
           "(c) RED CONTROL: and it errs DOWNWARD — the bar would draw below the mouse")
        ck(sweepNew(1.0, 0.8, 6, TOP) == 0,
           "(c) list scaled to 80%: correct across the whole list, top to bottom")
        ck(sweepOld(1.0, 0.8, 6, TOP) > 0,
           "(c) RED CONTROL: the shipped math is wrong somewhere in that same sweep")
    end

    -- (d) DRIFT, NOT OFFSET — the old error GROWS with height above the screen's
    --     bottom edge. That signature is why Raid Prep's reporter saw the bar
    --     "well below" the mouse near the top of the list and close to it low down.
    do
        local nearTop    = math.abs(oldDropLine(TOP, ROW_H, 40, rawFor(TOP - 5.5, 1.0, 0.8), 1.0)
                                    - expected(TOP, ROW_H, 40, TOP - 5.5))
        local nearBottom = math.abs(oldDropLine(TOP, ROW_H, 40, rawFor(TOP - 200.5, 1.0, 0.8), 1.0)
                                    - expected(TOP, ROW_H, 40, TOP - 200.5))
        ck(nearTop > nearBottom,
           "(d) RED CONTROL: the old error grows with height (drift, not a constant offset)")
    end

    -- (e) UI SCALE ALONE was NEVER the broken case: with the list at 100% the two
    --     spaces coincide at any UI Scale. Pin that the new math keeps it so —
    --     this is the half a careless "fix" would break.
    do
        for _, ui in ipairs({ 0.53, 0.71, 1.0, 1.25 }) do
            ck(sweepNew(ui, 1.0, 6, TOP) == 0, ("(e) UI Scale %.2f, list 100%%: still exact"):format(ui))
            ck(sweepOld(ui, 1.0, 6, TOP) == 0, ("(e) UI Scale %.2f, list 100%%: never broken — pinned"):format(ui))
        end
    end

    -- (f) BOTH off parity: the effective scale COMPOUNDS. Above 100% the old math
    --     drifts the other way, so the bar would draw ABOVE the mouse.
    do
        ck(sweepNew(0.71, 1.25, 6, TOP) == 0, "(f) UI Scale 0.71 x list 125%: compounded scale handled")
        ck(sweepNew(1.35, 0.6,  6, TOP) == 0, "(f) UI Scale 1.35 x list 60%: compounded the other way too")
        local y    = TOP - 75.5
        local want = expected(TOP, ROW_H, 6, y)
        ck(oldDropLine(TOP, ROW_H, 6, rawFor(y, 0.71, 1.25), 0.71) < want,
           "(f) RED CONTROL: above 100% the old math errs UPWARD (bar above the mouse)")
        ck(DropLine(TOP, ROW_H, 6, rawFor(y, 0.71, 1.25), 0.71 * 1.25) == want,
           "(f) the seam is right in both directions")
    end

    -- (g) SCROLLED LIST — SetVerticalScroll moves the scroll child, so childTop is
    --     simply somewhere else. The index must follow the ROWS, not the viewport.
    do
        local scrolledTop = TOP + 3 * ROW_H
        ck(sweepNew(1.0, 0.8, 12, scrolledTop) == 0,
           "(g) list scrolled down three rows at 80%: index follows the rows, not the viewport")
        ck(sweepNew(1.0, 1.0, 12, scrolledTop) == 0, "(g) …and at scale 1 as well")

        -- BOUNDARIES, pinned at scale 1 where the round trip is exact, so the
        -- assertion is about the comparison and not about float representation.
        ck(DropLine(TOP, ROW_H, 5, TOP - 15, 1) == 2,
           "(g) exactly on row 1's midpoint resolves DOWN, once, with no tie")
        ck(DropLine(TOP, ROW_H, 5, TOP - 14.999, 1) == 1,
           "(g) a hair above that midpoint is the slot above — the boundary is where it says")
        ck(DropLine(TOP, ROW_H, 5, TOP, 1) == 1, "(g) exactly on the list's top edge -> the head")
        ck(DropLine(TOP, ROW_H, 5, TOP - 5 * ROW_H, 1) == 6,
           "(g) exactly on the bottom edge of the last row -> past the tail")
    end

    -- (h) CURSOR OUTSIDE THE LIST at five scales: above every row -> the head;
    --     below every row -> one past the tail. Never out of range either way.
    do
        for _, sc in ipairs({ 0.5, 0.8, 1.0, 1.25, 1.5 }) do
            ck(DropLine(TOP, ROW_H, 5, rawFor(9000, 1.0, sc), sc) == 1,
               ("(h) cursor far above the list at scale %d%% -> insert at the head"):format(sc * 100))
            ck(DropLine(TOP, ROW_H, 5, rawFor(-9000, 1.0, sc), sc) == 6,
               ("(h) cursor far below the list at scale %d%% -> insert past the tail"):format(sc * 100))
        end
    end

    -- (i) EMPTY LIST: the only insertion point is 1, at any scale or cursor height.
    ck(DropLine(TOP, ROW_H, 0, 400, 0.8) == 1, "(i) empty list -> insert at 1")
    ck(DropLine(TOP, ROW_H, 0, -9999, 1.0) == 1, "(i) empty list, cursor off-screen low -> 1")
    ck(DropLine(TOP, ROW_H, 0, 99999, 1.35) == 1, "(i) empty list, cursor off-screen high -> 1")

    -- (j) DEGENERATE INPUT never raises and never returns a nil or fractional index.
    do
        local cases = {
            { TOP, ROW_H, 4, 400, nil }, { TOP, ROW_H, 4, 400, 0 },     { TOP, ROW_H, 4, 400, -1 },
            { TOP, ROW_H, 4, nil, 0.8 }, { nil, ROW_H, 4, 400, 0.8 },   { TOP, nil,   4, 400, 0.8 },
            { TOP, 0,     4, 400, 0.8 }, { TOP, ROW_H, nil, 400, 0.8 }, { TOP, ROW_H, -3, 400, 0.8 },
            { TOP, ROW_H, 4, 1 / 0, 0.8 },
        }
        local raised, oor = 0, 0
        for _, c in ipairs(cases) do
            local sok, line = pcall(DropLine, c[1], c[2], c[3], c[4], c[5])
            if not sok then raised = raised + 1
            elseif type(line) ~= "number" or line ~= line or line < 1 or line ~= math.floor(line) then
                oor = oor + 1
            end
        end
        ck(raised == 0, "(j) no degenerate input raises")
        ck(oor == 0,    "(j) every answer is a whole index >= 1")
        ck(DropLine(TOP, ROW_H, 4, 400, nil) == DropLine(TOP, ROW_H, 4, 400, 1),
           "(j) a missing scale falls back to 1, never to a division by zero")
    end

    -- (k) STRUCTURAL — the ticker must decide through the seam, read the SCROLL
    --     CHILD's scale for the hit-test, and keep UIParent's scale for the
    --     movement threshold (which is a screen gesture and was always correct).
    --     The anchor captured in OnMouseDown must stay in that same UIParent
    --     space, or the 5px threshold would compare two different spaces.
    do
        local src = readFile(P("options.lua")) or ""
        ck(src ~= "", "(k) options.lua is readable for the structural pins")
        ck(src:find("Addon.ComputeDropLine(childTop, BUFF_ROW_H, n, cy, listScale)", 1, true) ~= nil,
           "(k) the drag ticker decides through the pure seam")
        ck(src:find("child:GetEffectiveScale()", 1, true) ~= nil,
           "(k) the hit-test reads the SCROLL CHILD's effective scale")

        local block = src:match("dragTick:SetScript%(\"OnUpdate\", function%(%)(.-)\n    end%)") or ""
        ck(block ~= "", "(k) the drag ticker is locatable")
        ck(block:find("UIParent:GetEffectiveScale()", 1, true) ~= nil,
           "(k) UIParent's scale is still read — for the movement threshold")
        ck(block:find("uiMX", 1, true) ~= nil and block:find("uiMY", 1, true) ~= nil,
           "(k) the UIParent-space cursor is named for what it is")
        ck(block:match("ComputeDropLine%([^)]*uiM") == nil,
           "(k) REGRESSION PIN: the UIParent-space cursor never reaches the hit-test")
        ck(block:find("relY", 1, true) == nil,
           "(k) REGRESSION PIN: the old inline midpoint arithmetic is gone from the ticker")

        local anchor = src:match("bt%._dragSourceIdx = ci; bt%._dragging = false(.-)end%)") or ""
        ck(anchor ~= "", "(k) the OnMouseDown anchor capture is locatable")
        ck(anchor:find("UIParent:GetEffectiveScale()", 1, true) ~= nil,
           "(k) the click anchor is captured in UIParent space — the SAME space the threshold reads")
        ck(anchor:find("child:GetEffectiveScale()", 1, true) == nil,
           "(k) …and NOT in the list's space, which would split the threshold across two spaces")
    end
end
V_DRAG = gateEnd("DRAG")

----------------------------------------------------------------------
-- GATE ICON: the persisted icon cache is stamped with what taught it (BT-1).
--
-- `item.cachedIcon` is learned by matching a buff NAME in the live UnitBuff scan,
-- written into the PERSISTED profile, and returned forever. Its only invalidation
-- was a boot-time TYPE check -- and a shape check is not a correctness check. The
-- BUFF_RENAMES pass, in the very same Init() loop, rewrites the aura names the
-- icons were learned under and did not clear a single one, so the icon learned
-- under the old name was kept for good and survived a profile export/import.
-- Two healing passes side by side that did not talk to each other.
--
-- The shipped read is kept as a RED CONTROL.
----------------------------------------------------------------------
gateBegin("GATE ICON: cachedIcon is stamped with the name that taught it (BT-1)")

-- THE RED CONTROL: the shipped 2.1.x read, quoted in shape from main.lua:431.
local function shippedIconRead(item)
    if item.cachedIcon and type(item.cachedIcon) == "string" then return item.cachedIcon end
    return nil
end

local V_ICON
do
    -- (a) LEARN. The aura is up; the icon is learned and stamped with its name.
    local item = { buffNames = { "Greater Fire Power" }, displayName = "Greater Fire Power" }
    setAuras({ { name = "Greater Fire Power", icon = "ICON_OLD" } })
    ck(Addon:GetBuffIcon(item) == "ICON_OLD", "(a) the icon is learned from the live aura scan")
    ck(item.cachedIcon == "ICON_OLD", "(a) ...and cached into the persisted item")
    ck(item.cachedIconFor == "Greater Fire Power",
       "(a) THE FIX: stamped with the aura name that produced it")

    -- (b) The cache is a real cache: it still answers with the aura GONE.
    setAuras({})
    ck(Addon:GetBuffIcon(item) == "ICON_OLD", "(b) a still-valid cache is served without re-scanning")

    -- (c) THE FINDING. Run the REAL Init(), whose BUFF_RENAMES pass rewrites the
    --     very name this icon was learned under.
    _G.DaseekiCTDB = { dbVersion = 3, profiles = { MAGE = { items = { item } } } }
    Addon:Init()
    ck(item.buffNames[1] == "Greater Firepower", "(c) the rename pass rewrote the aura name")
    ck(shippedIconRead(item) == nil,
       "(c) RED CONTROL: the shipped read would have returned the stale icon -- it no longer can")
    ck(item.cachedIcon == nil, "(c) THE FIX: the rename cleared the icon it invalidated")
    ck(item.cachedIconFor == nil, "(c) ...and its stamp")

    -- (d) RE-LEARN under the new name.
    setAuras({ { name = "Greater Firepower", icon = "ICON_NEW" } })
    ck(Addon:GetBuffIcon(item) == "ICON_NEW", "(d) the icon is re-learned under the new name")
    ck(item.cachedIconFor == "Greater Firepower", "(d) ...and re-stamped")

    -- (e) The stamp catches a rename the healing pass knows NOTHING about -- the
    --     player editing the entry in the options pane. This is the half a
    --     clear-at-the-rename-pass fix would have missed entirely.
    item.buffNames[1] = "Elixir of Greater Firepower"
    setAuras({})
    ck(Addon:GetBuffIcon(item) ~= "ICON_NEW",
       "(e) a hand-edited buff name is a disagreement, and a disagreement re-learns")
    ck(item.cachedIcon == nil, "(e) the disagreeing cache is dropped, not latched")

    -- (f) LEGACY PROFILE, name untouched by the rename pass: the cache was learned
    --     under the name the item still carries, so stamping it says something true.
    --     FIXTURE NOTE: this used to use "Nightfin Soup", chosen precisely because
    --     the healing passes did not touch it. 2.1.2 made that false — Nightfin is
    --     now upgraded to its ambiguous-aura spell ID (18194), so it is no longer
    --     an "untouched" name and cannot test one. "Juju Power" is in neither
    --     Addon.BuffAliases nor Addon.BuffSpellUpgrades and carries the property the
    --     fixture needs. What is being asserted is unchanged.
    local legacyOk = { buffNames = { "Juju Power" }, cachedIcon = "ICON_LEGACY" }
    _G.DaseekiCTDB = { dbVersion = 3, profiles = { PRIEST = { items = { legacyOk } } } }
    Addon:Init()
    ck(legacyOk.cachedIcon == "ICON_LEGACY", "(f) an untouched legacy cache is kept")
    ck(legacyOk.cachedIconFor == "Juju Power", "(f) ...and backfilled with the name it carries")
    setAuras({})
    ck(Addon:GetBuffIcon(legacyOk) == "ICON_LEGACY", "(f) ...so it is still served")

    -- (g) LEGACY PROFILE the rename pass DID touch: provably broken provenance.
    --     It is cleared, NOT backfilled with the new name it never saw.
    local legacyBad = { buffNames = { "Mongoose" }, cachedIcon = "ICON_LEGACY" }
    _G.DaseekiCTDB = { dbVersion = 3, profiles = { ROGUE = { items = { legacyBad } } } }
    Addon:Init()
    ck(legacyBad.buffNames[1] == "Elixir of the Mongoose", "(g) the rename applied")
    ck(legacyBad.cachedIcon == nil, "(g) THE FIX: a renamed legacy cache is cleared, not adopted")
    ck(legacyBad.cachedIconFor == nil, "(g) ...and not stamped with a name it never saw")

    -- (h) The old shape check still holds: a non-string cache is still junk.
    local junk = { buffNames = { "Juju Power" }, cachedIcon = 7, cachedIconFor = "Juju Power" }
    _G.DaseekiCTDB = { dbVersion = 3, profiles = { DRUID = { items = { junk } } } }
    Addon:Init()
    ck(junk.cachedIcon == nil, "(h) a non-string cachedIcon is still cleared")

    -- (i) An entry with no buff name at all cannot serve a cache off a nil stamp.
    local nameless = { buffNames = {}, cachedIcon = "ICON_GHOST" }
    setAuras({})
    ck(Addon:GetBuffIcon(nameless) ~= "ICON_GHOST",
       "(i) a nameless entry cannot match a nil stamp against a nil name")

    -- (j) STRUCTURAL: the options editor's save clears the dead cache too, since
    --     UpdateItemInProfile merges with pairs() and cannot see a nil.
    local src = readFile(P("options.lua")) or ""
    ck(src:find("prof.items[idx].cachedIcon    = nil", 1, true) ~= nil,
       "(j) saving the entry editor clears the cache the merge cannot")
    ck(src:find("prof.items[idx].cachedIconFor = nil", 1, true) ~= nil,
       "(j) ...and its stamp")
end
V_ICON = gateEnd("ICON")

----------------------------------------------------------------------
-- GATE ENCH: an unreadable weapon-enchant timer is UNKNOWN, not forever (BT-2).
--
-- `return mhExpiry and (mhExpiry / 1000) or math.huge` reported infinite
-- remaining when the enchant was present but its expiry could not be read --
-- "I could not read it" rendered as "this never expires". The direction is
-- backwards: a temporary enchant about to drop read as permanently fine, and the
-- reminder icon stayed hidden. Unlike GetBuffExpiry/GetSpellExpiry, where
-- expirationTime == 0 genuinely means permanent, GetWeaponEnchantInfo only ever
-- reports TEMPORARY enchants -- there is no permanent case here at all.
--
-- frame.lua is loaded so the CONSUMERS are driven for real, not restated.
----------------------------------------------------------------------
gateBegin("GATE ENCH: an unreadable enchant timer is unknown, not infinite (BT-2)")

local V_ENCH
do
    local chunk, err = loadfile(P("frame.lua"))
    ck(chunk ~= nil, "frame.lua loads" .. (chunk and "" or (" -> " .. tostring(err))))
    if chunk then
        local okRun, rerr = pcall(chunk, ADDON_NAME, Addon)
        ck(okRun, "frame.lua executes" .. (okRun and "" or (" -> " .. tostring(rerr))))
    end

    -- THE RED CONTROL: the shipped 2.1.x fallback.
    local function shippedSecs(hasIt, expiry) return hasIt and (expiry and (expiry / 1000) or math.huge) or nil end

    local mh = { weaponSlot = "mainhand" }

    -- (a) THE FINDING: enchant present, expiry unreadable.
    setEnchant({ hasMH = true, mhExpiry = nil })
    ck(shippedSecs(true, nil) == math.huge,
       "(a) RED CONTROL: the shipped fallback answers math.huge -- 'this never expires'")
    ck(Addon:GetWeaponEnchantSecondsRemaining("mainhand") == nil,
       "(a) THE FIX: no answer is reported as no answer")
    ck(Addon:HasWeaponEnchant("mainhand") == true,
       "(a) ...while the enchant's PRESENCE is still known, so the two are separable")
    ck(Addon:IsItemMissing(mh) == true,
       "(a) THE FIX: the reminder is SHOWN -- under math.huge it stayed hidden")
    ck(Addon:GetItemExpirySeconds(mh) == nil,
       "(a) ...with an empty countdown, not a number nobody read")

    -- (b) A readable enchant is unchanged, on both sides of the warn threshold.
    setEnchant({ hasMH = true, mhExpiry = 300000 })
    ck(Addon:GetWeaponEnchantSecondsRemaining("mainhand") == 300, "(b) 300000ms reads as 300s")
    ck(Addon:IsItemMissing(mh) == false, "(b) five minutes left is not a reminder")
    ck(Addon:GetItemExpirySeconds(mh) == nil, "(b) ...and draws no countdown")

    setEnchant({ hasMH = true, mhExpiry = 60000 })
    ck(Addon:IsItemMissing(mh) == true, "(b) one minute left IS a reminder")
    ck(Addon:GetItemExpirySeconds(mh) == 60, "(b) ...and draws the real number")

    -- (c) No enchant at all is still simply missing.
    setEnchant({ hasMH = false })
    ck(Addon:GetWeaponEnchantSecondsRemaining("mainhand") == nil, "(c) no enchant -> nil")
    ck(Addon:IsItemMissing(mh) == true, "(c) no enchant -> reminder")
    ck(Addon:GetItemExpirySeconds(mh) == nil, "(c) no enchant -> no countdown")

    -- (d) The offhand half behaves identically (it carried the same fallback).
    local oh = { weaponSlot = "offhand" }
    setEnchant({ hasOH = true, ohExpiry = nil })
    ck(Addon:GetWeaponEnchantSecondsRemaining("offhand") == nil, "(d) offhand: no answer -> nil")
    ck(Addon:IsItemMissing(oh) == true, "(d) offhand: unreadable -> reminder shown")
    setEnchant({ hasOH = true, ohExpiry = 90000 })
    ck(Addon:GetWeaponEnchantSecondsRemaining("offhand") == 90, "(d) offhand: 90000ms reads as 90s")

    -- (e) REGRESSION PIN + the deliberate asymmetry: math.huge is gone from the
    --     weapon-enchant reader, and still present where the API really does
    --     report permanence (GetBuffExpiry / GetSpellExpiry).
    local src = readFile(P("main.lua")) or ""
    local block = src:match("function Addon:GetWeaponEnchantSecondsRemaining%(slot%)(.-)\nend") or ""
    ck(block ~= "", "(e) GetWeaponEnchantSecondsRemaining is locatable")
    ck(block:find("math.huge", 1, true) == nil,
       "(e) REGRESSION PIN: no math.huge fallback in the weapon-enchant reader")
    local buffBlock = src:match("function Addon:GetBuffExpiry%(buffName%)(.-)\nend") or ""
    ck(buffBlock:find("math.huge", 1, true) ~= nil,
       "(e) ...and math.huge is KEPT where the API genuinely reports no expiry")
end
V_ENCH = gateEnd("ENCH")

----------------------------------------------------------------------
-- GATE AURA: the catalog is keyed by the AURA name, and says which keys it has
--            actually read (2.1.2).
--
-- THE DEFECT: Addon.BuffDB is matched against the name UnitBuff() returns, but
-- three of its keys were the ITEM's name instead. "Flask of Distilled Wisdom" can
-- never equal "Distilled Wisdom", so the reminder icon stayed lit with the flask
-- visibly on the player's bar — reported by the owner with the aura and its spell
-- ID (17627) on screen. Chromatic Resistance was the same bug, unreported. The
-- shipped "Supreme Power" row proves the correct shape was known and just not
-- applied to its siblings.
--
-- THE SECOND DEFECT, which is why this gate is not four assertions: nothing in the
-- catalog recorded WHICH keys had ever been read off a live bar, so a key that had
-- never matched anything was indistinguishable from one that matched every day.
-- Every row now declares `nameSrc` (confirmed, and by whom) or `verify` (unread —
-- "assumed" or "suspect"). This gate refuses an undeclared row, which is what stops
-- the next entry from being added on a hunch.
--
-- frame.lua is already loaded by GATE ENCH, so IsItemMissing is driven for real.
----------------------------------------------------------------------
gateBegin("GATE AURA: catalog keyed by aura name + provenance declared (2.1.2)")

local V_AURA
do
    local NOW = 1000  -- the GetTime() stub

    -- ── (a) THE FULL CATALOG AUDIT. Every entry, no exceptions. ────────────────
    local rows, counts = Addon:AuditBuffDB()
    ck(#rows > 0, "(a) the catalog audit returns rows")
    ck(counts.undeclared == 0,
       "(a) every entry declares its provenance (undeclared: " .. counts.undeclared .. ")")
    ck(counts.verified + counts.assumed + counts.suspect + counts.undeclared == #rows,
       "(a) the status counts account for every row")

    -- The source token on a verified row must be one we can actually point at.
    local KNOWN_SRC = { spec = true, nexus = true, rename = true, owner = true, repo = true, spell = true }
    local badSrc = {}
    for _, r in ipairs(rows) do
        if r.status == "verified" then
            for tok in tostring(r.source):gmatch("[^+]+") do
                if not KNOWN_SRC[tok] then badSrc[#badSrc + 1] = r.key .. "=" .. tok end
            end
        end
    end
    ck(#badSrc == 0, "(a) every verified row cites a known source (" .. table.concat(badSrc, ", ") .. ")")

    -- A flagged row must carry a spell ID or be reported as having none, so the
    -- owner's in-game list is exhaustive rather than a sample.
    local flaggedNoID, flaggedWithID = 0, 0
    for _, r in ipairs(rows) do
        if r.status == "assumed" or r.status == "suspect" then
            if r.spellID then flaggedWithID = flaggedWithID + 1 else flaggedNoID = flaggedNoID + 1 end
        end
    end
    ck(flaggedNoID + flaggedWithID == counts.assumed + counts.suspect,
       "(a) every flagged row is accounted for with or without a spell ID")

    realprint(("    AUDIT  %d entries: %d verified, %d assumed, %d suspect, %d undeclared")
        :format(#rows, counts.verified, counts.assumed, counts.suspect, counts.undeclared))
    realprint(("    AUDIT  flagged rows: %d with a spell ID, %d with none")
        :format(flaggedWithID, flaggedNoID))
    for _, r in ipairs(rows) do
        realprint(("      %-9s %-36s id=%-7s %s")
            :format(r.status, r.key, tostring(r.spellID or "-"),
                    r.status == "verified" and ("<- " .. tostring(r.source)) or ("[" .. r.label .. "]")))
    end

    -- ── (b) PER-MISMATCH RED/GREEN. Old key misses; new key + ID matches. ──────
    -- The RED CONTROL is Addon:GetBuffExpiry — the shipped 2.1.1 matcher, name and
    -- nothing else. It is quoted here, not reimplemented.
    local MISMATCHES = {
        { old = "Flask of Distilled Wisdom",     new = "Distilled Wisdom",     id = 17627 },
        { old = "Flask of Chromatic Resistance", new = "Chromatic Resistance", id = 17629 },
        { old = "Elixir of the Giants",          new = "Elixir of Giants",     id = nil   },
    }
    for _, m in ipairs(MISMATCHES) do
        setAuras({ { name = m.new, spellID = m.id, expires = NOW + 2340 } })  -- 39m, the screenshot

        ck(Addon.BuffDB[m.old] == nil, "(b) " .. m.old .. ": the item-name key is gone from the catalog")
        ck(Addon.BuffDB[m.new] ~= nil, "(b) " .. m.new .. ": the aura-name key is present")
        ck(Addon.BuffDB[m.new].label == (m.old == "Elixir of the Giants" and "Elixir of Giants" or m.old),
           "(b) " .. m.new .. ": the ITEM name is kept as the label, so it is still findable")
        ck(Addon.BuffDB[m.new].spellID == m.id, "(b) " .. m.new .. ": carries spell ID " .. tostring(m.id))

        ck(Addon:GetBuffExpiry(m.old) == nil,
           "(b) RED CONTROL: the shipped name matcher does NOT see the aura under \"" .. m.old .. "\"")
        ck(Addon:GetBuffExpiry(m.new) ~= nil,
           "(b) GREEN: ...and does see it under \"" .. m.new .. "\"")
        ck(Addon:GetNamedBuffExpiry(m.new) ~= nil, "(b) GREEN: the shipped matcher resolves the new key")

        -- THE FIX IS A REMINDER THAT GOES QUIET. Drive the real consumer.
        ck(Addon:IsItemMissing({ buffNames = { m.new } }) == false,
           "(b) " .. m.new .. ": the tracked entry reads SATISFIED, reminder silent")
        setAuras({})
        ck(Addon:IsItemMissing({ buffNames = { m.new } }) == true,
           "(b) " .. m.new .. ": aura absent -> the reminder fires")
    end

    -- ── (c) ALIAS CONTINUITY: a profile keyed the old way KEEPS WORKING. ───────
    -- The alias map is the migration; this drives the REAL Init() over a profile
    -- shaped exactly like a 2.1.1 player's.
    do
        local legacy = {
            { buffNames = { "Flask of Distilled Wisdom" },     displayName = "Flask of Distilled Wisdom",     itemID = 13511 },
            { buffNames = { "Flask of Chromatic Resistance" }, displayName = "Flask of Chromatic Resistance", itemID = 13513 },
            { buffNames = { "Elixir of the Giants" },          displayName = "Elixir of the Giants",          itemID = 9206  },
            { buffName  = "Flask of Supreme Power",            displayName = "Flask of Supreme Power",        itemID = 13512 },
            { buffNames = { "Nightfin Soup" },                 displayName = "Nightfin Soup",                 itemID = 13931 },
            { buffNames = { "Juju Power" },                    displayName = "Juju Power",                    itemID = 12451 },
        }
        local before = #legacy
        _G.DaseekiCTDB = { dbVersion = 3, profiles = { WARRIOR = { items = legacy } } }
        Addon:Init()
        ck(#legacy == before, "(c) SavedVariables continuity: no entry was dropped by the migration")

        ck(legacy[1].buffNames[1] == "Distilled Wisdom", "(c) \"Flask of Distilled Wisdom\" -> \"Distilled Wisdom\"")
        ck(legacy[1].itemID == 13511, "(c) ...and the rest of the entry is untouched")
        ck(legacy[2].buffNames[1] == "Chromatic Resistance", "(c) \"Flask of Chromatic Resistance\" -> \"Chromatic Resistance\"")
        ck(legacy[3].buffNames[1] == "Elixir of Giants", "(c) \"Elixir of the Giants\" -> \"Elixir of Giants\"")
        ck(legacy[4].buffName == "Supreme Power", "(c) the 2.0.0 aliases still apply (legacy single buffName field)")
        ck(legacy[6].buffNames[1] == "Juju Power", "(c) a name with no alias is left exactly alone")

        -- Nightfin is the one that may NOT take a plain alias: "Mana Regeneration"
        -- is shared with Mageblood Potion, so it is upgraded to the spell ID.
        ck(legacy[5].spellID == 18194, "(c) \"Nightfin Soup\" is upgraded to its ambiguous-aura spell ID")
        ck(legacy[5].buffNames[1] == "Mana Regeneration", "(c) ...with the real aura name recorded")
        ck(legacy[5].displayName == "Nightfin Soup", "(c) ...and the label the player recognises kept")

        -- The migrated entries now actually resolve, which is the whole point.
        setAuras({ { name = "Distilled Wisdom", spellID = 17627, expires = NOW + 2340 } })
        ck(Addon:IsItemMissing(legacy[1]) == false,
           "(c) THE ACCEPTANCE FIXTURE: a 2.1.1 profile entry is satisfied by the live aura after migration")
    end

    -- ── (d) A LEGACY NAME THAT NEVER PASSED THROUGH Init() still resolves. ─────
    -- Imported profile strings and hand-typed old names never see the boot-time
    -- migration, so the alias is consulted at MATCH time too.
    setAuras({ { name = "Distilled Wisdom", spellID = 17627, expires = NOW + 2340 } })
    ck(Addon:GetCatalogSpellID("Flask of Distilled Wisdom") == 17627,
       "(d) a legacy key resolves to the current row's spell ID through the alias")
    ck(Addon:GetNamedBuffExpiry("Flask of Distilled Wisdom") ~= nil,
       "(d) ...so an unmigrated legacy name still matches the live aura")
    ck(Addon:GetBuffExpiry("Flask of Distilled Wisdom") == nil,
       "(d) RED CONTROL: by NAME alone it still cannot — the ID is doing the work")

    -- ── (e) ID-FIRST: a wrong or localized NAME still resolves on the ID. ──────
    do
        -- The aura is up, but the client reports it under a name this catalog has
        -- never seen — a non-English client, or a name Blizzard changed.
        setAuras({ { name = "Weisheitselixier", spellID = 17627, expires = NOW + 2340 } })
        ck(Addon:GetBuffExpiry("Distilled Wisdom") == nil,
           "(e) RED CONTROL: name matching alone fails on a localized aura name")
        ck(Addon:GetNamedBuffExpiry("Distilled Wisdom") ~= nil,
           "(e) THE FIX: the spell ID matches it anyway")
        ck(Addon:IsItemMissing({ buffNames = { "Distilled Wisdom" } }) == false,
           "(e) ...and the reminder stays silent, on a client we cannot read")

        -- And the converse, which is why this is ID-FIRST and not ID-ONLY: the
        -- catalog IDs are max-rank, so a lower-rank cast carries a different ID and
        -- only the NAME can catch it.
        setAuras({ { name = "Arcane Intellect", spellID = 1461, expires = NOW + 1800 } })
        ck(Addon.BuffDB["Arcane Intellect"].spellID == 10157, "(e) the catalog holds the max-rank ID")
        ck(Addon:GetSpellExpiry(10157) == nil, "(e) RED CONTROL: ID-ONLY would miss the lower rank")
        ck(Addon:GetNamedBuffExpiry("Arcane Intellect") ~= nil,
           "(e) THE FIX: the name fallback catches the rank the ID does not")

        -- An entry the catalog knows nothing about is pure name matching, unchanged.
        setAuras({ { name = "Some Custom Buff", expires = NOW + 60 } })
        ck(Addon:GetCatalogSpellID("Some Custom Buff") == nil, "(e) an uncatalogued name has no ID")
        ck(Addon:GetNamedBuffExpiry("Some Custom Buff") ~= nil, "(e) ...and still matches by name")
    end

    -- ── (f) THE AMBIGUOUS AURAS STAY STRICT. ID-first must not leak into them. ─
    do
        local mageblood = { spellID = 24363, buffNames = { "Mana Regeneration" }, displayName = "Mageblood Potion" }
        -- Nightfin is up. Its aura NAME is identical to Mageblood's.
        setAuras({ { name = "Mana Regeneration", spellID = 18194, expires = NOW + 600 } })
        ck(Addon:IsAmbiguousAuraSpell(24363) == true, "(f) Mageblood's aura is known to be ambiguous")
        ck(Addon:GetBuffExpiry("Mana Regeneration") ~= nil,
           "(f) RED CONTROL: a name fallback here WOULD match — the soup answers for the potion")
        ck(Addon:GetItemExpiry(mageblood) == nil,
           "(f) THE RULE: an ambiguous entry stops at its ID and does not fall back to the name")
        ck(Addon:IsItemMissing(mageblood) == true, "(f) ...so the Mageblood reminder correctly still fires")
        -- With the right potion up it resolves, so the strictness is not just "never".
        setAuras({ { name = "Mana Regeneration", spellID = 24363, expires = NOW + 600 } })
        ck(Addon:IsItemMissing(mageblood) == false, "(f) the real Mageblood aura satisfies it")
    end

    -- ── (g) An entry that identifies NOTHING is not a reminder. ────────────────
    setAuras({})
    do
        local secs, tracked = Addon:GetItemExpiry({ buffNames = {} })
        ck(secs == nil and tracked == false, "(g) a nameless, ID-less entry reports itself untracked")
        ck(Addon:IsItemMissing({ buffNames = {} }) == false,
           "(g) ...and draws no reminder (the pre-2.1.2 behaviour, preserved through the new seam)")
    end

    -- ── (h) THE CATALOG AND ITS MIGRATION CANNOT DISAGREE. ────────────────────
    do
        local dangling = {}
        for old, new in pairs(Addon.BuffAliases) do
            ck(Addon.BuffDB[old] == nil,
               "(h) legacy key \"" .. old .. "\" is not ALSO a live catalog key")
            if Addon.BuffDB[new] == nil then
                -- Permitted only when the target is an ambiguous aura, which lives
                -- in BuffSpellDB rather than BuffDB.
                local inSpellDB = false
                for _, e in ipairs(Addon.BuffSpellDB) do if e.aura == new then inSpellDB = true end end
                if not inSpellDB then dangling[#dangling + 1] = old .. " -> " .. new end
            end
        end
        ck(#dangling == 0, "(h) every alias points at a row that exists (" .. table.concat(dangling, ", ") .. ")")

        for old, up in pairs(Addon.BuffSpellUpgrades) do
            ck(Addon.BuffDB[old] == nil,
               "(h) upgraded key \"" .. old .. "\" is gone from the catalog (it could never match)")
            local found = false
            for _, e in ipairs(Addon.BuffSpellDB) do
                if e.spellID == up.spellID and e.aura == up.aura then found = true end
            end
            ck(found, "(h) \"" .. old .. "\" upgrades to a spell ID the ambiguous-aura table knows")
        end

        -- REGRESSION PIN: the aura-name rule itself. No catalog key may be the
        -- label of a DIFFERENT row — that is the shape of "keyed by item name".
        local labelClash = {}
        for key, data in pairs(Addon.BuffDB) do
            for otherKey, other in pairs(Addon.BuffDB) do
                if key ~= otherKey and other.label == key then
                    labelClash[#labelClash + 1] = key .. " is also " .. otherKey .. "'s label"
                end
            end
        end
        ck(#labelClash == 0, "(h) REGRESSION PIN: no key is another row's item label (" ..
           table.concat(labelClash, "; ") .. ")")
    end

    -- ── (i) The old name is still SEARCHABLE, or the fix hides the entry. ──────
    do
        local function findLabel(q, label)
            for _, r in ipairs(Addon:SearchBuffDB(q)) do
                if r.label == label then return r end
            end
            return nil
        end
        local r = findLabel("flask of distilled wisdom", "Flask of Distilled Wisdom")
        ck(r ~= nil, "(i) typing the OLD name still finds the re-keyed entry")
        ck(r and r.buffName == "Distilled Wisdom", "(i) ...and it hands back the AURA name to track")
        ck(r and r.spellID == 17627, "(i) ...with the spell ID")
        ck(findLabel("distilled", "Flask of Distilled Wisdom") ~= nil, "(i) a partial old name works too")
        ck(findLabel("supreme power", "Flask of Supreme Power") ~= nil, "(i) the 2.0.0 precedent is unaffected")
    end

    -- ── (j) STRUCTURAL: the migration map lives with the catalog it migrates. ──
    do
        local m = readFile(P("main.lua")) or ""
        ck(m:find("local BUFF_RENAMES  = Addon.BuffAliases or {}", 1, true) ~= nil,
           "(j) Init() takes its renames from the catalog file, not a private copy")
        ck(m:find("BUFF_RENAMES = {", 1, true) == nil,
           "(j) REGRESSION PIN: no second, drifting copy of the rename map in main.lua")
        local f = readFile(P("frame.lua")) or ""
        ck(f:find("Addon:GetItemExpiry(item)", 1, true) ~= nil,
           "(j) both frame.lua consumers decide through the single expiry seam")
        ck(f:find("Addon:GetMultiBuffExpiry(names)", 1, true) == nil,
           "(j) REGRESSION PIN: frame.lua no longer re-implements the ID-vs-name choice")
        local b = readFile(P("buffs.lua")) or ""
        ck(b:find("Addon.BuffAliases", 1, true) ~= nil, "(j) the alias map ships beside the catalog")
    end
end
V_AURA = gateEnd("AURA")

----------------------------------------------------------------------
-- GATE C9: synchronous in-call dispatch (CLIENT_ASYNC_LESSONS Class 9)
--
-- SIM POSTURE. Buff Tracker performs NO client mutation. Its whole vocabulary is
-- reads — UnitBuff, GetWeaponEnchantInfo, GetItemInfo, GetMacroInfo,
-- C_Container.GetContainerNumSlots / GetContainerItemInfo — and every action it
-- offers is delegated to the client by writing SecureActionButtonTemplate
-- attributes, so the client executes the use and this addon is nowhere in that
-- call stack. There is therefore NO mutation sim to give a synchronous-dispatch
-- posture to, and none has been invented for the sake of the mandate.
--
-- What Buff Tracker DOES own is in-call dispatch of its own making. The reorder
-- commit's redraw (Addon:RefreshItemList + Addon:UpdateFrame) Hides and Shows
-- every list row and the tracker frame, re-arms each row's OnMouseDown, and
-- writes secure attributes — all handlers the client runs to completion inside
-- those calls. The shipped ticker cleared its drag state AFTER that redraw, which
-- is Class 9's "armed too late" exactly: a second pass through the release branch
-- during the window read a source index pointing into the already-reordered list.
--
-- The commit is driven here through the real pure seam (Addon.CommitReorder) and
-- the real latch, with the shipped clear-after ordering kept as a RED CONTROL.
----------------------------------------------------------------------
gateBegin("GATE C9: reorder commit under in-call redraw dispatch")

local V_C9
do
    ck(type(Addon.CommitReorder) == "function",
       "(a) Addon.CommitReorder published as a pure seam")
    ck(type(Addon.BeginReorderCommit) == "function"
       and type(Addon.EndReorderCommit) == "function"
       and type(Addon.InReorderCommit) == "function",
       "(a) the commit latch is published alongside it")

    -- ---- (b) the pure surgery itself -------------------------------------
    local function names(t)
        local out = {}
        for i, v in ipairs(t) do out[i] = v.n end
        return table.concat(out, ",")
    end
    local function list() return { {n="a"}, {n="b"}, {n="c"}, {n="d"} } end

    local L = list()
    ck(Addon.CommitReorder(L, 1, 3) == 2 and names(L) == "b,a,c,d",
       "(b) moving down closes the gap the removal opened (" .. names(L) .. ")")
    L = list()
    ck(Addon.CommitReorder(L, 4, 1) == 1 and names(L) == "d,a,b,c",
       "(b) moving to the head lands at 1 (" .. names(L) .. ")")
    L = list()
    ck(Addon.CommitReorder(L, 2, 5) == 4 and names(L) == "a,c,d,b",
       "(b) the count+1 line means 'after the last row' (" .. names(L) .. ")")
    L = list()
    ck(Addon.CommitReorder(L, 2, 2) == 2 and names(L) == "a,b,c,d",
       "(b) dropping on itself is a no-op, not a duplication")
    ck(Addon.CommitReorder(nil, 1, 2) == nil, "(b) a nil list moves nothing")
    ck(Addon.CommitReorder({}, 1, 1) == nil, "(b) an empty list moves nothing")
    ck(Addon.CommitReorder(list(), 9, 1) == nil, "(b) an out-of-range source moves nothing")
    ck(Addon.CommitReorder(list(), 1, nil) == nil, "(b) a nil drop line moves nothing")

    -- ---- (c) RED CONTROL: the shipped clear-after ordering ----------------
    -- The release branch as it shipped: commit, redraw, THEN clear. The redraw is
    -- modelled by a Show/Hide fan-out that wakes the ticker once, which is exactly
    -- what RefreshItemList's row:Show()/row:Hide() and UpdateFrame's f:Show() do.
    do
        local items = list()
        local drag = { src = 1, line = 3, dragging = true }
        local passes = 0

        local release
        local function redrawShipped()      -- the in-call dispatch
            if drag.src and drag.dragging and drag.line then release() end
        end
        release = function()
            passes = passes + 1
            if passes > 4 then return end   -- stand-in for the stack the client runs out of
            if drag.dragging and drag.line then
                local item = table.remove(items, drag.src)
                local at = drag.line
                if at > drag.src then at = at - 1 end
                at = math.max(1, math.min(#items + 1, at))
                table.insert(items, at, item)
                redrawShipped()                          -- <- state still armed here
            end
            drag.dragging, drag.src, drag.line = false, nil, nil   -- cleared too late
        end
        release()
        ck(passes > 1, ("(c) the shipped ordering re-entered its own commit (%d passes)")
           :format(passes))
        ck(names(items) ~= "b,a,c,d",
           "(c) ...and the list did not land where one drop should have put it ("
           .. names(items) .. ")")
    end

    -- ---- (d) the real ordering: clear + latch BEFORE the redraw -----------
    do
        local items = list()
        local drag = { src = 1, line = 3, dragging = true }
        local commits, woken = 0, 0

        local release
        local function redraw()             -- same in-call dispatch, same wake
            woken = woken + 1
            release()                       -- a row Show/OnMouseDown re-entering
        end
        release = function()
            -- The ticker's own guard, verbatim in shape.
            if Addon:InReorderCommit() then return end
            local from    = drag.src
            local dropped = drag.dragging and drag.line or nil
            drag.dragging, drag.src, drag.line = false, nil, nil
            if dropped and Addon:BeginReorderCommit() then
                pcall(function()
                    local landed = Addon.CommitReorder(items, from, dropped)
                    if not landed then return end
                    commits = commits + 1
                    redraw()
                end)
                Addon:EndReorderCommit()
            end
        end
        release()

        ck(woken >= 1, "(d) the redraw really did wake the ticker from inside the commit")
        ck(commits == 1, ("(d) exactly ONE commit landed (%d)"):format(commits))
        ck(names(items) == "b,a,c,d",
           "(d) the list moved once, to where the drop asked (" .. names(items) .. ")")
        ck(Addon:InReorderCommit() == false, "(d) the latch is down when the sequence returns")
    end

    -- ---- (e) the latch survives an error inside the redraw ----------------
    do
        ck(Addon:BeginReorderCommit() == true, "(e) a fresh sequence can be owned")
        pcall(function() error("a redraw blew up") end)
        Addon:EndReorderCommit()
        ck(Addon:InReorderCommit() == false, "(e) an error does not wedge the latch up")
        ck(Addon:BeginReorderCommit() == true, "(e) ...and the next reorder still works")
        Addon:EndReorderCommit()
    end

    -- ---- (f) options.lua actually uses it, in the right order -------------
    local op = readFile(P("options.lua")) or ""
    ck(#op > 0, "(f) options.lua is readable")
    local rel = op:match('if not IsMouseButtonDown%("LeftButton"%) then(.-)\n            return\n        end') or ""
    ck(rel ~= "", "(f) the release branch is locatable")
    local clearAt  = rel:find("bt._dragging, bt._dragSourceIdx, bt._dragDropLine = false, nil, nil", 1, true)
    local latchAt  = rel:find("Addon:BeginReorderCommit()", 1, true)
    local refreshAt= rel:find("Addon:RefreshItemList()", 1, true)
    local frameAt  = rel:find("Addon:UpdateFrame()", 1, true)
    ck(clearAt and latchAt and refreshAt and frameAt,
       "(f) clear / latch / RefreshItemList / UpdateFrame are all present")
    ck(clearAt and refreshAt and clearAt < refreshAt,
       "(f) the drag state is cleared BEFORE the redraw that dispatches in-call")
    ck(latchAt and refreshAt and latchAt < refreshAt,
       "(f) the commit latch is raised BEFORE it too")
    ck(rel:find("Addon:EndReorderCommit()", 1, true) ~= nil, "(f) and released on the way out")
    ck(rel:find("pcall(", 1, true) ~= nil, "(f) the commit body is pcall-fenced")
    ck(rel:find("tremove(prof.items", 1, true) == nil,
       "(f) REGRESSION PIN: the release branch no longer re-implements the surgery")
    ck(op:find("if Addon:InReorderCommit() then return end", 1, true) ~= nil,
       "(f) the ticker reads the latch and treats what it sees as its own echo")
    local md = op:match('row:SetScript%("OnMouseDown", function%(self, btn2%)(.-)end%)') or ""
    ck(md:find("Addon:InReorderCommit()", 1, true) ~= nil,
       "(f) a row mouse-down woken by the redraw cannot arm a fresh drag")

    -- ---- (g) no client mutation exists to need a mutation sim -------------
    -- Asserted rather than assumed: if a mutating verb ever lands in this addon,
    -- this gate turns red and the sim decision above has to be revisited.
    do
        local MUTATORS = {
            "UseItem", "UseContainerItem", "UseAction", "PickupContainerItem",
            "PickupItem", "SplitContainerItem", "EquipItemByName", "CastSpell",
            "CastSpellByName", "RunMacro", "SendChatMessage", "SendAddonMessage",
            "SetCVar", "BuyMerchantItem", "PutItemInBackpack", "DeleteMacro",
            "CreateMacro", "EditMacro",
        }
        local found = {}
        for _, f in ipairs({ "main.lua", "frame.lua", "options.lua", "buffs.lua",
                             "profiles.lua", "defaults.lua" }) do
            local src = readFile(P(f)) or ""
            for _, verb in ipairs(MUTATORS) do
                if src:find(verb .. "%s*%(") then found[#found + 1] = f .. ":" .. verb end
            end
        end
        ck(#found == 0, "(g) no client-mutating call anywhere in the addon ("
           .. (next(found) and table.concat(found, ", ") or "none") .. ")")
        local fr = readFile(P("frame.lua")) or ""
        ck(fr:find("SecureActionButtonTemplate", 1, true) ~= nil,
           "(g) actions are delegated to the client's own secure handler, as recorded")
    end
end
V_C9 = gateEnd("C9")

----------------------------------------------------------------------
realprint("############################################################")
realprint("# Daseeki-Buff-Tracker migration self-tests")
realprint("#   GATE 0        toc parse          : " .. V_TOC)
realprint("#   GATE FW       clean-room firewall : " .. V_FW)
realprint("#   GATE MIG-ALGO migration runner   : " .. V_ALGO)
realprint("#   GATE MIG-INIT real Init()        : " .. V_INIT)
realprint("#   GATE CORE-GUARD RequireCore      : " .. V_GUARD)
realprint("#   GATE DRAG     reorder hit-test   : " .. V_DRAG)
realprint("#   GATE ICON     stamped icon cache : " .. V_ICON)
realprint("#   GATE ENCH     unreadable ≠ forever: " .. V_ENCH)
realprint("#   GATE AURA     aura-name catalog  : " .. V_AURA)
realprint("#   GATE C9       in-call dispatch   : " .. V_C9)
realprint("#")
realprint("#   RESULT: " .. (FAILS == 0 and "ALL PASS" or (FAILS .. " FAILURE(S) — RED")))
realprint("############################################################")
os.exit(FAILS == 0 and 0 or 1)
