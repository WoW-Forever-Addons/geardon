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
local stats = { fills = 0, listed = 0, kept = 0, setsApi = "?", indexReads = 0, indexItems = 0, indexPending = 0 }
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

---------------------------------------------------------------------------
-- (1.3.0) Bag index: the gear in your bags, read once per bag change (and
-- again when gear, level or options change the version, or an item that was
-- still loading arrives). The cleanup list, the bag upgrades and the chat
-- line all use it instead of reading the bags each.
---------------------------------------------------------------------------
local index, indexVer, indexDirty = {}, nil, true
local pendingIDs = {}

function ns.MarkBagIndexDirty() indexDirty = true end
-- true when that item is one of the bag items still loading
function ns.BagItemPending(itemID) return pendingIDs[ns.Num(itemID) or 0] == true end
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID) if ns.BagItemPending(itemID) then indexDirty = true end end)

-- A different best one-hand or off-hand item while you wear a two-hand weapon changes the
-- arrows of other bag items: the version goes up so the bags draw them again.
local lastPair = ""
ns.On("BAG_UPDATE_DELAYED", function()
  indexDirty = true
  local sig = ns.PairSignature and ns.PairSignature() or ""
  if sig ~= lastPair then
    local was = lastPair
    lastPair = sig
    if was ~= "" or sig ~= "" then ns.BumpVersion() if ns.BagsDirty then ns.BagsDirty() end end
  end
end)

-- { { link, info, bag, slot }, ... } of every gear item in your bags (bag 0 to the last bag slot).
function ns.BagGear()
  if not indexDirty and indexVer == ns.version then return index end
  -- a new table each time: a loop over the old list (Judge may rebuild it) stays intact
  index = {}
  wipe(pendingIDs)
  local n, pending = 0, 0
  for bag = 0, NumBagSlots() do
    for slot = 1, SlotCount(bag) do
      local link = BagLink(bag, slot)
      local info = link and ns.ItemInfo(link)
      if link and not info then
        pending = pending + 1
        local id = tonumber(link:match("item:(%d+)"))
        if id then pendingIDs[id] = true end
      end
      if info and ns.IsGear(info) then
        n = n + 1
        index[n] = { link = link, info = info, bag = bag, slot = slot }
      end
    end
  end
  indexDirty, indexVer = false, ns.version
  stats.indexReads, stats.indexItems, stats.indexPending = stats.indexReads + 1, n, pending
  return index
end

-- { { link, info, reason = "worse"|"unusable", diff, bag, slot }, ... }, kept (in an equipment set)
function ns.CleanupList()
  local list, kept = {}, 0
  local protected = SetItems()
  local level = ns.Num(ns.Value(UnitLevel, "player")) or 0
  for _, g in ipairs(ns.BagGear()) do
    local info, reason, diff = g.info, nil, nil
    local canUse = C_PlayerInfo and C_PlayerInfo.CanUseItem and ns.Value(C_PlayerInfo.CanUseItem, info.itemID)
    if canUse == false then
      reason = "unusable"
    elseif (info.reqLevel or 0) <= level then
      local v = ns.Judge(info)
      -- worse: a lower item level of the same or a lower quality (a higher quality is not judged)
      if v and v.diff and v.diff < 0 and not v.note and not v.upgrade then reason, diff = "worse", v.diff end
    end
    if reason then
      if protected[info.itemID] then
        kept = kept + 1
      else
        list[#list + 1] = { link = g.link, info = info, reason = reason, diff = diff, bag = g.bag, slot = g.slot }
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
-- (1.3.0) Upgrades in your bags: the best one per slot you would put it in,
-- the ones you can wear now first, then those you can wear in a few levels.
-- { { link, info, v = { diff, slot, eqLevel, check, soon } }, ... }
---------------------------------------------------------------------------
-- Rings, trinkets and (with dual wield) one-hand weapons fill two slots: the best two of them.
local TWO = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }
local function Gain(v) return v.pairGain or v.diff end
function ns.BagUpgrades()
  local best = {}
  for _, g in ipairs(ns.BagGear()) do
    local v = ns.Judge(g.info)
    if v and (v.upgrade or v.soon) and not (v.check and ns.db.arrowUncertain == false) then
      local loc = g.info.equipLoc
      local two = TWO[loc] or (loc == "INVTYPE_WEAPON" and #(ns.TargetSlots(loc) or {}) == 2)
      local key = (two and loc or v.slot) .. (v.partner and ":pair" or "") .. (v.soon and ":soon" or "")
      local e = { link = g.link, info = g.info,
        v = { diff = v.diff, slot = v.slot, eqLevel = v.eqLevel, check = v.check, soon = v.soon, note = v.note,
          partner = v.partner, pairGain = v.pairGain } }
      local b = best[key] or {}
      best[key] = b
      local keep = two and 2 or 1
      if not b[1] or Gain(e.v) > Gain(b[1].v) then table.insert(b, 1, e) elseif keep == 2 and (not b[2] or Gain(e.v) > Gain(b[2].v)) then b[2] = e end
      for i = #b, keep + 1, -1 do b[i] = nil end
    end
  end
  local list = {}
  for _, b in pairs(best) do for _, e in ipairs(b) do list[#list + 1] = e end end
  table.sort(list, function(a, b)
    if (a.v.soon or 0) ~= (b.v.soon or 0) then return (a.v.soon or 0) < (b.v.soon or 0) end
    if Gain(a.v) ~= Gain(b.v) then return Gain(a.v) > Gain(b.v) end
    return a.link < b.link
  end)
  stats.upgrades = #list
  return list
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
  local hdr

  -- (1.3.0) Upgrades in your bags
  Style.Header(panel, L["Upgrades in your bags"])
  local ups = ns.BagUpgrades()
  if #ups == 0 then
    Style.Row(panel):SetText(L["No upgrade in your bags."], "textHint")
  end
  for _, e in ipairs(ups) do
    local row = Style.Row(panel)
    row:SetText("|c" .. QualityHex(e.info.quality) .. ItemName(e.link) .. "|r")
    if e.v.soon then
      row:SetValue(L["from level %d"]:format(e.v.soon), "textSecondary")
    else
      row:SetValue(ns.UpgradeWhat(e.v), e.v.check and "warning" or "good")
    end
    row:SetTooltip(function()
      local lines = { { L["Item level"], ns.FormatLevel(e.info.level) },
        { ns.SlotLabel(e.v.slot), ns.FormatLevel(e.v.eqLevel or 0) } }
      if e.v.soon then lines[#lines + 1] = L["An upgrade from level %d."]:format(e.v.soon)
      elseif e.v.partner then lines[#lines + 1] = L["Together with %s instead of your two-hand weapon."]:format(e.v.partner)
      elseif e.v.check then lines[#lines + 1] = L["Not sure: the item's tooltip says why."] end
      return ItemName(e.link), lines, L["To wear it: right-click it in your bags."]
    end)
  end

  -- Behind your level
  hdr = Style.Header(panel, L["Behind your level"])
  if hdr then hdr:SetGapBefore(Style.SPACING.section) end
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
  hdr = Style.Header(panel, L["Dungeons for your level"])
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
      if (e.info.sellPrice or 0) > 0 then lines[#lines + 1] = { L["Vendor price"], ns.Money(e.info.sellPrice) } end
      return ItemName(e.link), lines, L["Geardon only lists; nothing is sold or deleted."]
    end)
  end
  -- (1.3.0) what the whole list brings at a vendor
  local worth = 0
  for _, e in ipairs(items) do worth = worth + (e.info.sellPrice or 0) end
  if worth > 0 then Style.KeyValue(panel, L["Worth at a vendor"], ns.Money(worth)) end
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
