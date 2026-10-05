local addonName, ns = ...
local L = ns.L

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
  showBags = true,
  showBank = true,
  showLoot = true,
  showRewards = true,
  showFlyout = true,          -- equipment flyout of the character frame
  showMerchant = true,        -- merchant and buyback
  -- look of the numbers on item buttons
  numberPosition = "BOTTOM",  -- "BOTTOM", "TOP", "CENTER"
  numberColor = "quality",    -- "quality", "white"
  numberSize = 12,
  showGrey = false,           -- also on poor (grey) items
  upgradeArrow = true,        -- green arrow on bags, bank, loot and rewards
  -- tooltips
  tooltipLevel = true,        -- "Item level 18" when the game does not show it
  tooltipCompare = true,      -- "+3 over equipped (Head 15)"
  unitTooltip = true,         -- average item level on player tooltips
  -- group
  groupScan = true,           -- inspect group members out of combat
  groupShare = true,          -- send and receive item level with Geardon users
  groupWindow = true,         -- window with the group's item level, in a party
  groupWindowRaid = false,    -- also in a raid
}

ns.SCHEMA = 1
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

function ns.SafeCall(context, fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
    pcall(Record, context, err)
    return err
  end)
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

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event) -- unknown events throw
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  return true
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

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      GeardonDB = type(GeardonDB) == "table" and GeardonDB or {}
      ns.firstRun = next(GeardonDB) == nil
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
    local list = listeners[event]
    if list and ns.db then
      for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
    end
    return
  end
  if not ns.db then return end
  local list = listeners[event]
  if list then
    for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
  end
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
