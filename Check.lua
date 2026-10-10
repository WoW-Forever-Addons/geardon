local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) Gear check (/gd check): one small window of our own
-- (Style kit) with three sections:
--   Behind your level: slots far below your level (Character.lua);
--   Dungeons for your level: where to look for better gear (Dungeons.lua);
--   Bag cleanup: bag items that are worse than what you wear or that you
--     cannot use. Items of Blizzard equipment sets are kept off the list.
-- The window only lists. Nothing is sold, moved, equipped or deleted.
---------------------------------------------------------------------------
local WIDTH = 300
local MAX_ROWS = 25
local panel
local queued = false
local stats = { fills = 0, listed = 0, kept = 0, setsApi = "?" }
ns.checkStats = stats

local function Store()
  if type(ns.db.checkWin) ~= "table" then ns.db.checkWin = {} end
  return ns.db.checkWin
end

---------------------------------------------------------------------------
-- Bag cleanup list
---------------------------------------------------------------------------
-- itemID -> true for every item in one of Blizzard's equipment sets (by item
-- ID: two copies of an item are both kept, never one too few).
local function SetItems()
  local out = {}
  local E = C_EquipmentSet
  if not (E and type(E.GetEquipmentSetIDs) == "function" and type(E.GetItemIDs) == "function") then
    stats.setsApi = "missing"
    return out
  end
  stats.setsApi = "ok"
  local ids = ns.Value(E.GetEquipmentSetIDs)
  for _, setID in ipairs(type(ids) == "table" and ids or {}) do
    local items = ns.Usable(setID) and ns.Value(E.GetItemIDs, setID)
    if type(items) == "table" then
      for _, itemID in pairs(items) do
        itemID = ns.Num(itemID)
        if itemID and itemID > 0 then out[itemID] = true end
      end
    end
  end
  return out
end

local function NumBagSlots()
  local c = Constants and Constants.InventoryConstants
  return (type(c) == "table" and ns.Num(c.NumBagSlots)) or ns.Num(rawget(_G, "NUM_BAG_SLOTS")) or 4
end

local function SlotCount(bag)
  local get = (C_Container and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
  return ns.Num(ns.Call(get, bag)) or 0
end

local function BagLink(bag, slot)
  local get = (C_Container and C_Container.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
  return ns.Str(ns.Call(get, bag, slot))
end

-- { { link, info, reason = "worse"|"unusable", diff, bag, slot }, ... }, kept (in an equipment set)
function ns.CleanupList()
  local list, kept = {}, 0
  local protected = SetItems()
  local level = ns.Num(ns.Value(UnitLevel, "player")) or 0
  for bag = 0, NumBagSlots() do
    for slot = 1, SlotCount(bag) do
      local link = BagLink(bag, slot)
      local info = link and ns.ItemInfo(link)
      if info and ns.IsGear(info) then
        local reason, diff
        local canUse = C_PlayerInfo and C_PlayerInfo.CanUseItem and ns.Value(C_PlayerInfo.CanUseItem, info.itemID)
        if canUse == false then
          reason = "unusable"
        elseif (info.reqLevel or 0) <= level then
          local v = ns.Judge(info)
          -- worse: a lower item level of the same or a lower quality (a higher quality is not judged)
          if v and v.diff and v.diff < 0 and not v.note then reason, diff = "worse", v.diff end
        end
        if reason then
          if protected[info.itemID] then
            kept = kept + 1
          else
            list[#list + 1] = { link = link, info = info, reason = reason, diff = diff, bag = bag, slot = slot }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.reason ~= b.reason then return a.reason == "unusable" end
    local qa, qb = a.info.quality or 1, b.info.quality or 1
    if qa ~= qb then return qa < qb end
    if a.info.level ~= b.info.level then return a.info.level < b.info.level end
    return a.link < b.link
  end)
  stats.listed, stats.kept = #list, kept
  return list, kept
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function ItemName(link)
  return link:match("|h%[(.-)%]|h") or link
end

local function QualityHex(quality)
  local r, g, b = ns.QualityColor(quality)
  return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function Build()
  local Style = ns.Style
  panel = Style.Panel("GeardonCheckPanel", UIParent, {
    title = Style.Wordmark("Gear", "don") .. "  " .. Style.Colorize(L["Gear check"], "textSecondary"),
    width = WIDTH,
    close = true,
    get = function(key) return Store()[key] end,
    set = function(key, value) Store()[key] = value end,
    defaultPoint = { "CENTER", "CENTER", 260, 60 },
    closeTooltip = L["Close"],
    buttons = { { kind = "options", key = "options", tooltip = { L["Options"], nil, L["Opens the Geardon options."] },
      onClick = function() ns.OpenOptions() end } },
  })
  return panel
end

local function Fill()
  local Style = ns.Style
  stats.fills = stats.fills + 1
  panel:ClearRows()

  -- Behind your level
  Style.Header(panel, L["Behind your level"])
  local list, empty = ns.BehindSlots()
  local level = ns.Num(ns.Value(UnitLevel, "player"))
  if not ns.BehindLimit() then
    Style.Row(panel):SetText(L["The marker is off (options, Item level page)."], "textHint")
  elseif #list == 0 then
    Style.Row(panel):SetText(L["No slot is far behind your level."], "textHint")
  else
    for _, b in ipairs(list) do
      local row = Style.KeyValue(panel, ns.SlotLabel(b.slot), ns.FormatLevel(b.level), "critical")
      row:SetTooltip(function()
        return ns.SlotLabel(b.slot), {
          { L["Item level"], ns.FormatLevel(b.level) },
          { L["Your level"], level and ("%d"):format(level) or "?" },
          L["Behind: item level more than %d below your level."]:format(tonumber(ns.db.behindLevels) or 8),
        }
      end)
    end
  end
  if empty > 0 then Style.KeyValue(panel, L["Empty slots"], ("%d"):format(empty), "warning") end

  -- Dungeons for your level
  local hdr = Style.Header(panel, L["Dungeons for your level"])
  if hdr then hdr:SetGapBefore(Style.SPACING.section) end
  local dungeons = ns.DungeonsForLevel(level)
  if #dungeons == 0 then
    local first = ns.FirstDungeonLevel()
    Style.Row(panel):SetText(first and L["No dungeon fits your level yet; the first starts at level %d."]:format(first)
      or L["No dungeon fits your level."], "textHint")
  else
    for _, d in ipairs(dungeons) do
      local row = Style.KeyValue(panel, d.name, ns.LevelRangeText(d.min, d.max))
      row:SetTooltip(function()
        return d.name, { { L["Level range"], ns.LevelRangeText(d.min, d.max) },
          L["A dungeon for your level. Which items drop there, and for which slot, Geardon does not know."] }
      end)
    end
  end
  local src = ns.dungeonStats and ns.dungeonStats.source == "Questdon" and "Questdon" or "warcrafttavern.com"
  Style.Row(panel):SetText(L["Level ranges: %s"]:format(src), "textHint")

  -- Bag cleanup
  hdr = Style.Header(panel, L["Bag cleanup"])
  if hdr then hdr:SetGapBefore(Style.SPACING.section) end
  local items, kept = ns.CleanupList()
  if #items == 0 then
    Style.Row(panel):SetText(L["Nothing to clean up: no gear in your bags is worse than yours or unusable."], "textHint")
  end
  for i, e in ipairs(items) do
    if i > MAX_ROWS then
      Style.Row(panel):SetText(L["%d more"]:format(#items - MAX_ROWS), "textHint")
      break
    end
    local value, color
    if e.reason == "unusable" then
      value, color = L["not usable"], "critical"
    else
      value, color = ("%s (%s)"):format(ns.FormatLevel(e.info.level), "-" .. ns.FormatLevel(-e.diff)), "textSecondary"
    end
    local row = Style.Row(panel)
    row:SetText("|c" .. QualityHex(e.info.quality) .. ItemName(e.link) .. "|r")
    row:SetValue(value, color)
    row:SetTooltip(function()
      local lines = {}
      if e.reason == "unusable" then
        lines[#lines + 1] = L["Your character cannot use it."]
      else
        local v = ns.Judge(e.info)
        if v and v.slot then
          lines[#lines + 1] = { L["Item level"], ns.FormatLevel(e.info.level) }
          lines[#lines + 1] = { ns.SlotLabel(v.slot), ns.FormatLevel(v.eqLevel or 0) }
        end
        lines[#lines + 1] = L["Lower item level than what you wear, not of a higher quality."]
      end
      return ItemName(e.link), lines, L["Geardon only lists; nothing is sold or deleted."]
    end)
  end
  if kept > 0 then
    Style.Row(panel):SetText(L["%d kept off the list: in an equipment set."]:format(kept), "textHint")
  end
end

local function Update()
  queued = false
  if not (panel and panel:IsShown()) then return end
  Fill()
end

-- Bags or gear changed: once per moment, only while the window is open.
function ns.UpdateCheck()
  if queued or not (panel and panel:IsShown()) then return end
  queued = true
  ns.After(0.3, Update)
end

function ns.ShowCheck()
  if not (ns.Style and ns.Style.Panel) then return end
  if panel and panel:IsShown() then panel:FadeOut() return end
  if not panel then Build() end
  Fill()
  panel:FadeIn()
end

function ns.ResetCheckWindow()
  if panel then panel:ResetPosition() else Store().pos = nil end
end

ns.On("BAG_UPDATE_DELAYED", function() ns.UpdateCheck() end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.UpdateCheck() end)
ns.On("PLAYER_LEVEL_UP", function() ns.UpdateCheck() end)
ns.On("GET_ITEM_INFO_RECEIVED", function() ns.UpdateCheck() end)
