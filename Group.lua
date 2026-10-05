local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Item level of your group. Two sources:
--   addon: group members with Geardon send their average themselves
--          (addon message to the group, "G1:<token>:<level x 10>");
--   inspect: everyone else is inspected one by one, only out of combat,
--          never while Blizzard's inspect window is open, with a pause
--          between two inspects and a back-off for players out of range.
-- Shown in a small window (in a party, optional in a raid) and in the
-- player tooltips.
---------------------------------------------------------------------------
local PREFIX = "Geardon"
local FRESH_ADDON = 15 * 60   -- seconds a sent value stays valid
local FRESH_INSPECT = 10 * 60 -- seconds before a player is inspected again
local INSPECT_GAP = 1.5       -- seconds between two inspects
local INSPECT_TIMEOUT = 4
local SEND_GAP = 5            -- seconds between two own messages

local levels = {}   -- guid -> { level, src, t, name, class }
local failed = {}   -- guid -> time until the next try
local pending       -- { guid, unit, t, tries }
local nextInspect, lastSend, sendQueued = 0, 0, false
local token
local stats = { sent = 0, received = 0, requests = 0, inspects = 0, ready = 0, timeouts = 0, foreign = 0 }
ns.groupStats = stats

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Token()
  if not token then token = ("%04x"):format(math.random(0, 65535)) end
  return token
end

-- weak, weakLevel: the player's weakest slot (slot name) and its item level.
function ns.RememberLevel(guid, level, src, unit, weak, weakLevel)
  if type(guid) ~= "string" or not ns.Usable(guid) or not ns.Num(level) then return end
  local e = levels[guid] or {}
  -- a value a player sent wins over an inspect of the same moment
  if e.src == "addon" and src == "inspect" and Now() - (e.t or 0) < 30 then return end
  e.level, e.src, e.t, e.stale = level, src, Now(), nil
  -- a message or inspect without the weakest slot keeps the one known before
  if ns.SLOT[weak or ""] and ns.Num(weakLevel) then e.weak, e.weakLevel = weak, weakLevel end
  if unit then
    e.name = ns.Str(ns.Value(UnitName, unit)) or e.name
    local _, class = ns.Results(UnitClass, unit)
    e.class = ns.Str(class) or e.class
  end
  levels[guid] = e
  failed[guid] = nil
  if ns.UpdateGroupWindow then ns.UpdateGroupWindow() end
end

-- Average item level of a player GUID, if known and not too old.
function ns.LevelOf(guid)
  if type(guid) ~= "string" then return nil end
  local player = ns.Value(UnitGUID, "player")
  if guid == player then return (ns.PlayerAverage()), "self" end
  local e = levels[guid]
  if not e or not e.level then return nil end
  local limit = e.src == "addon" and FRESH_ADDON or FRESH_INSPECT * 3
  if Now() - (e.t or 0) > limit then return nil end
  return e.level, e.src, e.t, e
end

---------------------------------------------------------------------------
-- Known values survive a /reload or a short relog (15 minutes, wall clock).
---------------------------------------------------------------------------
local KEEP = 15 * 60
local function Wall() return ns.Num(ns.Value(time)) or 0 end

local function SaveCache()
  local out, wall, now = {}, Wall(), Now()
  for guid, e in pairs(levels) do
    local age = now - (e.t or 0)
    if e.level and age < KEEP then
      out[guid] = { level = e.level, src = e.src, at = wall - age, name = e.name, class = e.class,
        weak = e.weak, weakLevel = e.weakLevel, stale = e.stale or nil }
    end
  end
  ns.db.groupCache = out
end

local function LoadCache()
  local saved, wall, now = ns.db.groupCache, Wall(), Now()
  if type(saved) ~= "table" then return end
  for guid, s in pairs(saved) do
    local age = type(s) == "table" and ns.Num(s.at) and (wall - s.at)
    if type(guid) == "string" and age and age >= 0 and age < KEEP and ns.Num(s.level) and not levels[guid] then
      levels[guid] = { level = s.level, src = s.src == "addon" and "addon" or "inspect", t = now - age,
        name = s.name, class = s.class, weak = ns.SLOT[s.weak or ""] and s.weak or nil, weakLevel = ns.Num(s.weakLevel),
        stale = s.stale == true or nil }
      stats.restored = (stats.restored or 0) + 1
    end
  end
  ns.db.groupCache = nil
end
ns.LoadGroupCache = LoadCache
ns.OnInit(LoadCache)
ns.On("PLAYER_LOGOUT", SaveCache)

---------------------------------------------------------------------------
-- Group roster
---------------------------------------------------------------------------
function ns.GroupUnits()
  local units = {}
  local n = ns.Num(ns.Value(GetNumGroupMembers)) or 0
  if ns.Value(IsInRaid) == true then
    for i = 1, math.min(n, 40) do units[#units + 1] = "raid" .. i end
  else
    units[#units + 1] = "player"
    for i = 1, math.min(math.max(n - 1, 0), 4) do units[#units + 1] = "party" .. i end
  end
  return units
end

local function InGroup() return (ns.Num(ns.Value(GetNumGroupMembers)) or 0) > 1 end

local function UnitByName(sender)
  if type(sender) ~= "string" then return nil end
  local short = sender:match("^([^%-]+)") or sender
  for _, unit in ipairs(ns.GroupUnits()) do
    local name, realm = ns.Results(UnitName, unit)
    name = ns.Str(name)
    if name then
      realm = ns.Str(realm)
      if (realm and (name .. "-" .. realm) == sender) or name == sender or name == short then return unit end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Addon messages
---------------------------------------------------------------------------
local function Channel()
  if ns.Value(IsInGroup, LE_PARTY_CATEGORY_INSTANCE or 2) == true then return "INSTANCE_CHAT" end
  if ns.Value(IsInRaid) == true then return "RAID" end
  if InGroup() then return "PARTY" end
  return nil
end

local function Send(text)
  local chan = Channel()
  if not chan or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  -- Enum.SendAddonMessageResult: 0 = sent; throttled or locked messages count as not sent
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, chan)
  if not ok or not (res == nil or res == true or res == 0) then
    stats.notSent = (stats.notSent or 0) + 1
    return false
  end
  return true
end

-- Our own average to the group (at most every SEND_GAP seconds).
function ns.SendLevel()
  if not (ns.db.groupShare and InGroup()) then return end
  local now = Now()
  if now - lastSend < SEND_GAP then
    if not sendQueued then
      sendQueued = true -- one retry later
      ns.After(SEND_GAP - (now - lastSend) + 0.1, function() sendQueued = false ns.SendLevel() end)
    end
    return
  end
  local avg = ns.PlayerAverage()
  if not avg then return end
  -- optional tail: weakest slot ID and its item level ("G1:<token>:<avg x 10>:<slot>:<level>")
  local _, _, weak = ns.Average(ns.Equipped())
  local eq = weak and ns.Equipped()[weak]
  local tail = (eq and eq.level and ns.SLOT[weak]) and (":%d:%d"):format(ns.SLOT[weak], math.floor(eq.level + 0.5)) or ""
  if Send(("G1:%s:%d%s"):format(Token(), math.floor(avg * 10 + 0.5), tail)) then
    lastSend = now
    stats.sent = stats.sent + 1
  end
end

local function Request()
  if ns.db.groupShare and InGroup() and Send("G1R:" .. Token()) then stats.requests = stats.requests + 1 end
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
  if prefix ~= PREFIX or not ns.db.groupShare then return end
  if not (ns.Usable(text) and ns.Usable(sender)) or type(text) ~= "string" then return end
  local tok, value, tail = text:match("^G1:(%x%x%x%x):(%d+)(.*)$")
  if tok and (tail == "" or tail:match("^:%d+:%d+") or tail:match("^:")) then
    if tok == Token() then return end -- our own message
    local unit = UnitByName(sender)
    local guid = unit and ns.Value(UnitGUID, unit)
    local level = tonumber(value) / 10
    if guid and level > 0 and level < 2000 then
      stats.received = stats.received + 1
      local slotID, weakLevel = tail:match("^:(%d+):(%d+)")
      ns.RememberLevel(guid, level, "addon", unit, ns.SlotNameByID(tonumber(slotID)), tonumber(weakLevel))
    else
      stats.foreign = stats.foreign + 1
    end
    return
  end
  local req = text:match("^G1R:(%x%x%x%x)$")
  if req and req ~= Token() then ns.SendLevel() end
end)

---------------------------------------------------------------------------
-- Inspect queue
---------------------------------------------------------------------------
local function InspectOpen()
  local f = ns.Frame("InspectFrame")
  return f and ns.Method(f, "IsShown") == true
end

local function NeedsInspect(unit, now)
  local guid = ns.Value(UnitGUID, unit)
  if type(guid) ~= "string" then return nil end
  if ns.Value(UnitIsUnit, unit, "player") == true then return nil end
  if ns.Value(UnitIsPlayer, unit) ~= true or ns.Value(UnitIsConnected, unit) ~= true then return nil end
  if (failed[guid] or 0) > now then return nil end
  local e = levels[guid]
  if e and e.src == "addon" and now - (e.t or 0) < FRESH_ADDON then return nil end
  if e and e.src == "inspect" and not e.stale and now - (e.t or 0) < FRESH_INSPECT then return nil end
  if ns.Value(UnitIsVisible, unit) ~= true then return nil end
  if ns.Value(CanInspect, unit) ~= true then return nil end
  return guid
end

local function FinishPending()
  if pending and not InspectOpen() and ClearInspectPlayer then pcall(ClearInspectPlayer) end
  pending = nil
end

local function Tick()
  local now = Now()
  if pending then
    if now - pending.t > INSPECT_TIMEOUT then
      stats.timeouts = stats.timeouts + 1
      failed[pending.guid] = now + 30
      FinishPending()
    end
    return
  end
  if not ns.db.groupScan or not InGroup() or ns.InCombat() or InspectOpen() then return end
  if now < nextInspect then return end
  -- members without any value first, then the ones that changed gear or got old
  local pick, pickGuid
  for _, unit in ipairs(ns.GroupUnits()) do
    local guid = NeedsInspect(unit, now)
    if guid and (not pick or (not levels[guid] and levels[pickGuid])) then
      pick, pickGuid = unit, guid
      if not levels[guid] then break end
    end
  end
  do
    local unit, guid = pick, pickGuid
    if guid then
      if pcall(NotifyInspect, unit) then
        pending = { guid = guid, unit = unit, t = now, tries = 0 }
        stats.inspects = stats.inspects + 1
      else
        failed[guid] = now + 60
      end
      nextInspect = now + INSPECT_GAP
      return
    end
  end
end

local function ReadPending()
  if not pending then return end
  local unit = pending.unit
  if ns.Value(UnitGUID, unit) ~= pending.guid then FinishPending() return end
  local avg, complete, slots = ns.InspectAverage(unit)
  if (not complete or not avg) and pending.tries < 6 then
    pending.tries = pending.tries + 1
    pending.t = Now() -- items are loading: wait longer
    ns.After(0.4, ReadPending)
    return
  end
  if avg and complete then
    local _, _, weak = ns.Average(slots or {})
    local w = weak and slots[weak]
    ns.RememberLevel(pending.guid, avg, "inspect", unit, weak, w and w.level)
  else
    failed[pending.guid] = Now() + 15 -- items did not load: try again soon
  end
  FinishPending()
end

ns.On("INSPECT_READY", function(_, guid)
  if pending and ns.Usable(guid) and guid == pending.guid then
    stats.ready = stats.ready + 1
    ReadPending()
  end
end)

ns.On("UNIT_INVENTORY_CHANGED", function(_, unit)
  if type(unit) ~= "string" or not ns.Usable(unit) or unit == "player" then return end
  local guid = ns.Value(UnitGUID, unit)
  local e = guid and levels[guid]
  if e and e.src == "inspect" then e.stale = true end -- inspect again, keep showing the old value
end)

function ns.RescanGroup(verbose)
  for _, e in pairs(levels) do if e.src == "inspect" then e.stale = true end end
  wipe(failed)
  nextInspect = 0
  Request()
  if verbose then ns.Print(L["Inspecting your group again (out of combat, one player at a time)."]) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local roster = {}
local function RosterChanged()
  local now, new = {}, false
  for _, unit in ipairs(ns.GroupUnits()) do
    local guid = ns.Value(UnitGUID, unit)
    if type(guid) == "string" then
      now[guid] = true
      if not roster[guid] then new = true end
    end
  end
  roster = now
  if new and InGroup() then
    ns.SendLevel()
    ns.After(2, Request)
    -- give Geardon users time to answer before anyone is inspected
    nextInspect = math.max(nextInspect, Now() + 5)
  end
  if ns.UpdateGroupWindow then ns.UpdateGroupWindow() end
end

ns.OnInit(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    stats.prefix = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) and "ok" or "failed"
  end
  ns.NewTicker(0.5, Tick)
end)
ns.On("GROUP_ROSTER_UPDATE", RosterChanged)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(3, RosterChanged) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.After(2, ns.SendLevel) end)
ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", function() ns.After(2, ns.SendLevel) end)

-- For the window and the diagnostics.
function ns.GroupLevels()
  local list = {}
  for _, unit in ipairs(ns.GroupUnits()) do
    local guid = ns.Value(UnitGUID, unit)
    if type(guid) == "string" then
      local level, src, t, e = ns.LevelOf(guid)
      local _, class = ns.Results(UnitClass, unit)
      list[#list + 1] = {
        unit = unit, guid = guid, level = level, src = src, t = t,
        name = ns.Str(ns.Value(UnitName, unit)) or (levels[guid] and levels[guid].name) or "?",
        class = ns.Str(class), waiting = pending and pending.guid == guid,
        failed = failed[guid] and failed[guid] > Now(),
        weak = e and e.weak, weakLevel = e and e.weakLevel,
      }
    end
  end
  return list
end

function ns.GroupDiag()
  local known = 0
  for _ in pairs(levels) do known = known + 1 end
  return ("restored %d; known %d; sent %d, not sent %d, received %d, requests %d, other senders %d; inspects %d, ready %d, timeouts %d; prefix %s"):format(
    stats.restored or 0, known, stats.sent, stats.notSent or 0, stats.received, stats.requests, stats.foreign, stats.inspects, stats.ready,
    stats.timeouts, tostring(stats.prefix))
end
