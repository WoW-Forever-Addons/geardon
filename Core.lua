local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 3) -- shared kit from DonCore (Libs\DonCore\Style.lua)
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns) -- Blizzard options from DonCore (Libs\DonCore\Settings.lua)

---------------------------------------------------------------------------
-- Geardon: item level for WoW Forever. Flat settings keys, registered by
-- SettingsUI.lua directly on ns.db.
---------------------------------------------------------------------------
ns.defaults = {
  -- where the numbers appear
  showCharacter = true,
  markWeakest = true,
  showAverage = true,         -- your average on the character frame
  showInspect = true,
  inspectMine = true,         -- (1.3.0) your own average next to the inspected player's
  showBags = true,
  showBank = true,
  showLoot = true,
  showRewards = true,
  showFlyout = true,          -- equipment flyout of the character frame
  showMerchant = true,        -- merchant and buyback
  bagAddons = true,           -- (1.2.0) Baganator and Bagnon
  boeMarker = true,           -- (1.2.0) "BoE" on bind-on-equip items in bags not yet bound
  behindMarker = true,        -- (1.2.0) slots far below your level in the critical colour
  behindLevels = 8,           -- (1.2.0) "far below": item level < your level - this
  chatChange = true,          -- (1.2.0) chat line when your average changes
  chatUpgrade = true,         -- (1.3.0) chat line when an upgrade comes into your bags
  -- look of the numbers on item buttons; (1.2.0) position and size per place:
  -- bags (bags, bank, bag addons: the old keys), character frame, other windows
  numberPosition = "BOTTOM",  -- "BOTTOM", "TOP", "CENTER"
  numberColor = "quality",    -- "quality", "white", (1.2.0) "gap" (gap to your average)
  numberSize = 12,
  numberPositionChar = "BOTTOM",
  numberSizeChar = 12,
  numberPositionOther = "BOTTOM",
  numberSizeOther = 12,
  showGrey = false,           -- also on poor (grey) items
  minQualityUncommon = false, -- (1.2.0) numbers only on Uncommon (green) and better
  upgradeArrow = true,        -- green arrow on bags, bank, loot and rewards
  arrowUncertain = true,      -- (1.2.0) yellow arrow when unsure (lower quality, set bonus at stake)
  arrowWeaponMatch = true,    -- (1.2.0) arrow only on weapon types you use
  arrowBestArmor = false,     -- (1.2.0) arrow only on your best armour type
  arrowMainStats = true,      -- (1.2.0) no arrow on items with none of your class's main stats
  arrowStatValue = true,      -- (1.2.2) the stat value for your class decides (Questdon's weights)
  arrowPair = true,           -- (1.3.0) one-hand plus off-hand from your bags against your two-hand weapon
  arrowSoon = true,           -- (1.3.0) grey arrow on upgrades you can wear in a few levels
  soonLevels = 3,             -- (1.3.0) "a few": at most this many levels above yours
  -- tooltips
  tooltipLevel = true,        -- "Item level 18" when the game does not show it
  tooltipCompare = true,      -- "+3 over equipped (Head 15)"
  tooltipStatSplit = true,    -- (1.2.0) "Agility 60% · Stamina 40%"
  unitTooltip = true,         -- average item level on player tooltips
  mouseoverLevel = true,      -- (1.2.0) inspect any player you point at or target (out of combat)
  -- group
  groupScan = true,           -- inspect group members out of combat
  groupShare = true,          -- send and receive item level with Geardon users
}

ns.SCHEMA = 2 -- (1.2.0) 2: mouseoverLevel on by default
ns.WORDMARK = "|cff3fa9f5Gear|rdon"

---------------------------------------------------------------------------
-- Error guard: every event handler, timer and UI callback runs protected.
-- The first distinct errors are kept for /gd diag; one chat line per session.
---------------------------------------------------------------------------
local MAX_ERRORS, MAX_MSG = 10, 160
local errors, warned = {}, false

local function Shorten(msg)
  msg = tostring(msg or "?"):gsub("\\", "/")
  msg = msg:gsub("[^%s:]*/([%w_]+%.[lx][um][al])", "%1")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) .. "..." end
  return msg
end

local function Record(context, err)
  local plain = type(err) == "string" and ns.Usable(err)
  if not plain then err = "(unreadable error)" end
  local ok, msg = pcall(Shorten, err)
  if not ok then msg = "(unreadable error)" end
  for _, e in ipairs(errors) do
    if e.msg == msg and e.context == context then
      e.count = e.count + 1
      return
    end
  end
  if #errors < MAX_ERRORS then
    errors[#errors + 1] = { context = context, msg = msg, count = 1 }
  else
    ns.droppedErrors = (ns.droppedErrors or 0) + 1
  end
  if not warned then
    warned = true
    print(ns.WORDMARK .. ": " .. L["an error occurred, /gd diag for details"])
  end
end

function ns.Errors() return errors end
function ns.RecordError(context, err) pcall(Record, context, err) end

-- (D16, 31.10.2026, from Vitaldon/Core.lua) Runs without creating a closure or
-- table per call for up to four arguments (events and tickers come often). The
-- runner reads the upvalues the moment xpcall starts it, so a nested SafeCall
-- cannot change the arguments of the outer one.
local runFn, runA, runB, runC, runD, runContext
local function Runner() return runFn(runA, runB, runC, runD) end
local function Handler(err)
  pcall(Record, runContext, err)
  return err
end

function ns.SafeCall(context, fn, ...)
  local n = select("#", ...)
  if n > 4 then
    local args = { ... }
    local prev = runContext
    runContext = context
    local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, Handler)
    runContext = prev
    if ok then return a, b, c end
    return
  end
  local prev = runContext
  runFn, runA, runB, runC, runD = fn, ...
  runContext = context
  local ok, a, b, c = xpcall(Runner, Handler)
  runFn, runA, runB, runC, runD = nil, nil, nil, nil, nil
  runContext = prev
  if ok then return a, b, c end
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

function ns.NewTicker(interval, fn)
  if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(interval, ns.Guard("timer", fn)) end
end

---------------------------------------------------------------------------
-- Events on our own frame. Several modules may listen to one event.
-- ns.OnAddon(name, fn): fn runs once when that (Blizzard) addon is loaded,
-- right away if it already is.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local listeners, initCallbacks, addonCallbacks = {}, {}, {}
-- (D16, 31.10.2026) Unit events: ns.On(event, fn, units) with units = { token = true, ... }
-- calls fn only for those units (first event argument); other, secret or
-- non-string units are dropped before any protected call. The filter is per
-- listener: a listener without units still gets every unit.
local unitFilters = {} -- event -> { [index of the listener] = units }

function ns.On(event, fn, units)
  if not listeners[event] then
    listeners[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event) -- unknown events throw
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  if type(units) == "table" then
    unitFilters[event] = unitFilters[event] or {}
    unitFilters[event][#listeners[event]] = units
  end
  return true
end

local function Dispatch(event, ...)
  local list = listeners[event]
  if not list then return end
  local filters = unitFilters[event]
  local unit = filters and ...
  local known = filters and type(unit) == "string" and ns.Usable(unit)
  for i = 1, #list do
    local units = filters and filters[i]
    if not units or (known and units[unit]) then ns.SafeCall(event, list[i], event, ...) end
  end
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

function ns.AddOnLoaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local v = ns.Call(fn, name)
  return ns.Usable(v) and v and true or false
end

function ns.OnAddon(name, fn)
  if ns.db and ns.AddOnLoaded(name) then ns.SafeCall("addon:" .. name, fn) return end
  addonCallbacks[name] = addonCallbacks[name] or {}
  table.insert(addonCallbacks[name], fn)
end

local function RunAddon(name)
  local list = addonCallbacks[name]
  if not list then return end
  addonCallbacks[name] = nil
  for _, fn in ipairs(list) do ns.SafeCall("addon:" .. name, fn) end
end

-- (1.2.0, Daniel 10.10.) The old position and size were for every place:
-- they become the start values of the new places (character frame, other windows).
-- Schema 2: the item level of players you point at or target is on by
-- default. A saved "off" from before cannot be told apart from the old default
-- (1.2.0 builds before this had it off), so it is switched on once; a later
-- "off" stays (the schema is 2 then).
-- (1.2.0) The group window opens only by hand now: its auto-show settings are gone.
function ns.MigrateDB(db)
  db.groupWindow, db.groupWindowRaid = nil, nil
  if next(db) ~= nil and (tonumber(db.schema) or 0) < 2 and db.mouseoverLevel == false then
    db.mouseoverLevel = true
  end
  if db.numberPositionChar == nil and type(db.numberPosition) == "string" then
    db.numberPositionChar, db.numberPositionOther = db.numberPosition, db.numberPosition
  end
  if db.numberSizeChar == nil and type(db.numberSize) == "number" then
    db.numberSizeChar, db.numberSizeOther = db.numberSize, db.numberSize
  end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      GeardonDB = type(GeardonDB) == "table" and GeardonDB or {}
      ns.firstRun = next(GeardonDB) == nil
      ns.MigrateDB(GeardonDB)
      for k, v in pairs(ns.defaults) do
        if GeardonDB[k] == nil or type(GeardonDB[k]) ~= type(v) then GeardonDB[k] = v end
      end
      GeardonDB.schema = ns.SCHEMA
      ns.db = GeardonDB
      for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
      -- Blizzard addons that were loaded before us
      local pending = {}
      for n in pairs(addonCallbacks) do pending[#pending + 1] = n end
      for _, n in ipairs(pending) do if ns.AddOnLoaded(n) then RunAddon(n) end end
    elseif ns.db and type(name) == "string" then
      RunAddon(name)
    end
    if ns.db then Dispatch(event, ...) end
    return
  end
  if not ns.db then return end
  Dispatch(event, ...)
end)

---------------------------------------------------------------------------
-- Helpers. Secret values (Midnight rules) never reach comparisons,
-- arithmetic or table keys in our code.
---------------------------------------------------------------------------
function ns.Print(msg) print(ns.WORDMARK .. ": " .. tostring(msg)) end

function ns.Usable(v)
  if type(v) == "nil" then return false end
  if canaccessvalue then
    local ok, r = pcall(canaccessvalue, v)
    if ok then return r and true or false end
    return false
  end
  if issecretvalue then
    local ok, r = pcall(issecretvalue, v)
    if ok then return not r end
    return false
  end
  return true
end

function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

function ns.Str(v)
  if type(v) == "string" and ns.Usable(v) and v ~= "" then return v end
  return nil
end

function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

function ns.Value(fn, ...)
  local v = ns.Call(fn, ...)
  if ns.Usable(v) then return v end
  return nil
end

-- All results of fn(...) or nothing (error or missing function).
function ns.Results(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if not r[1] then return end
  return unpack(r, 2, table.maxn(r))
end

function ns.InCombat()
  return InCombatLockdown and ns.Value(InCombatLockdown) == true or false
end

function ns.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = ns.Value(get, addonName, "Version")
  v = type(v) == "string" and v:gsub("%s", "") or ""
  return v ~= "" and v or "?"
end

-- A frame by global name or path ("BankFrame.BankPanel"), nil if missing.
local function Index(t, k) return t[k] end
function ns.Frame(path)
  local v = _G
  for part in tostring(path):gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    local ok, nv = pcall(Index, v, part)
    if not ok then return nil end
    v = nv
  end
  if type(v) == "table" and v.GetObjectType then return v end
  return nil
end

-- Calls a method of a Blizzard object (read only), nil on error.
function ns.Method(obj, name, ...)
  if type(obj) ~= "table" then return nil end
  local ok, fn = pcall(Index, obj, name)
  if not ok or type(fn) ~= "function" then return nil end
  return ns.Value(fn, obj, ...)
end

function Geardon_OnAddonCompartmentClick()
  if ns.OpenOptions then ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GEARDON1 = "/gd"
SLASH_GEARDON2 = "/geardon"
ns.COMMANDS = {
  { "/gd", "options" },
  { "/gd group", "show or hide the group window" },
  { "/gd scan", "inspect the group again" },
  { "/gd check", "gear check: behind your level, dungeons, bag cleanup" },
  { "/gd diag", "diagnostics window" },
  { "/gd diag chat", "diagnostics in chat" },
  { "/gd help", "this list" },
}
local OPEN = { [""] = true, options = true, config = true, optionen = true }

function ns.PrintHelp()
  ns.Print(L["Commands:"])
  for _, c in ipairs(ns.COMMANDS) do print("  |cffebebeb" .. c[1] .. "|r  |cff9ea3ad" .. L[c[2]] .. "|r") end
end

function ns.Slash(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower():gsub("%s+", " ")
  if msg == "diag chat" then
    if ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "diag" then
    if ns.ShowDiag then ns.ShowDiag() elseif ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "group" or msg == "gruppe" then
    if ns.ToggleGroupWindow then ns.ToggleGroupWindow() end
  elseif msg == "check" or msg == "gear" or msg == "bags" then
    if ns.ShowCheck then ns.ShowCheck() end
  elseif msg == "scan" then
    if ns.RescanGroup then ns.RescanGroup(true) end
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  elseif OPEN[msg] then
    if ns.OpenOptions then ns.OpenOptions() end
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end
SlashCmdList.GEARDON = ns.Guard("slash", ns.Slash)
