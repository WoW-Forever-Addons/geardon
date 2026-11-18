local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) Gear check (/gd check): one window of our own with
-- these sections (1.3.0: Upgrades in your bags first; 02.11.2026 DonCore's kit, see Window below):
--   Behind your level: slots far below your level (Character.lua);
--   Dungeons for your level: where to look for better gear (Dungeons.lua);
--   Bag cleanup: bag items that are worse than what you wear or that you
--     cannot use. Items of Blizzard equipment sets are kept off the list.
-- The window only lists. Nothing is sold, moved, equipped or deleted.
---------------------------------------------------------------------------
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
-- (02.11.2026, StyleKit 2 step 4, docs/layout_2026-11-02/geardon/, Daniel: "Freigeben wie gezeigt") built from DonCore's
-- kit only: Kit.Window (flat head, cog, grip, footer), 340x360 to 760x900, place and size in GeardonDB.checkWin;
-- Kit.Hero (level and class, your item level, the weakest slot); a Kit.List with four sections to fold (Kit.GroupHeader
-- with the count; folded ones kept in checkWin.closed), item rows with the item symbol in its quality edge, shift-click
-- links; colour marks green wearable, yellow unsure, grey soon, red behind your level, blue a dungeon. From 640 px a focus
-- card (Kit.Detail) on the right for the chosen row (Daniel: "Ja, ab 640 px"); narrower the tooltip says the same. The
-- window never changes its size by itself: more height = more rows, every text one line (cut, whole text in the tooltip).
---------------------------------------------------------------------------
local LOGO = "Interface\\Icons\\INV_Chest_Plate06"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local DETAIL_FROM, DETAIL_W = 640, 280
local W, selKey
-- (16.11.2026, Blizzard look, Daniel: "Sollte Standart sein") the window takes its blocks from UI: the Kit, or with the
-- option blizzLook the same blocks from the game's own templates (ns.LookKit). Picked when the window is built
-- (PickUI); a build that fails with the game's blocks is done again with the Kit. ns.CheckLook() says which and why.
local UI, lookNote = nil, "not built"
local BLIZZ_W, BLIZZ_H = 400, 500 -- the Kit's windows show at 80 %, the game's frame at 100 %: about the same size

local function GetKit() return LibStub("DonCore-1.0"):Get("Kit", 5) end

local function ItemName(link)
  return link:match("|h%[(.-)%]|h") or link
end

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

local function Icon(itemID)
  local get = (C_Item and C_Item.GetItemIconByID) or rawget(_G, "GetItemIcon")
  return itemID and ns.Value(get, itemID) or QUESTION
end

local function Plus(v) return "+" .. ns.FormatLevel(math.floor(v * 10 + 0.5) / 10) end

local function Wear(slot, level)
  return ns.SlotLabel(slot) .. " · " .. L["you wear %s"]:format(ns.FormatLevel(level or 0))
end

-- the sections, each with its rows; a folded section only its header
local function Items()
  local Kit = GetKit()
  local C = Kit.C
  local closed = type(Store().closed) == "table" and Store().closed or {}
  local items = {}
  local function Group(key, text, count, right)
    local g = { kind = "group", key = key, text = text, count = count, right = right, collapsed = closed[key] or nil }
    items[#items + 1] = g
    return not g.collapsed
  end
  local function Note(text, color, right)
    items[#items + 1] = { kind = "note", text = text, color = color or C.muted, right = right }
  end
  local level = ns.Num(ns.Value(UnitLevel, "player"))

  -- (1.3.0) Upgrades in your bags
  local ups = ns.BagUpgrades()
  if Group("ups", L["Upgrades in your bags"], #ups) then
    if #ups == 0 then Note(L["No upgrade in your bags."], C.quiet) end
    for _, e in ipairs(ups) do
      local v = e.v
      local it = { key = "ups:" .. e.link, title = ItemName(e.link), quality = e.info.quality, itemID = e.info.itemID,
        icon = Icon(e.info.itemID), rightWidth = 124 } -- "from level 25" in ptBR and frFR needs more than the usual 96
      if v.pairGain then it.sub = L["both hands +%s"]:format(ns.FormatLevel(math.floor(v.pairGain * 10 + 0.5) / 10))
      elseif v.diff and v.diff > 0 then it.sub = Wear(v.slot, v.eqLevel)
      else it.sub = L["%s, better stats"]:format(ns.SlotLabel(v.slot)) end
      if v.soon then
        it.status, it.right, it.rightColor = "grey", L["from level %d"]:format(v.soon), C.muted
      elseif v.check then
        it.status, it.right, it.rightColor = "yellow", L["not sure"], C.yellow
      else
        it.status, it.rightColor = "green", C.green
        it.right = (v.pairGain and Plus(v.pairGain)) or (v.diff and v.diff > 0 and Plus(v.diff)) or nil
      end
      it.tip = function()
        local lines = { { L["Item level"], ns.FormatLevel(e.info.level) },
          { ns.SlotLabel(v.slot), ns.FormatLevel(v.eqLevel or 0) } }
        if v.soon then lines[#lines + 1] = L["An upgrade from level %d."]:format(v.soon)
        elseif v.partner then lines[#lines + 1] = L["Together with %s instead of your two-hand weapon."]:format(v.partner)
        elseif v.check then lines[#lines + 1] = L["Not sure: the item's tooltip says why."] end
        return ItemName(e.link), lines, L["To wear it: right-click it in your bags."]
      end
      items[#items + 1] = it
    end
  end

  -- Behind your level
  local list, empty = ns.BehindSlots()
  local on = ns.BehindLimit()
  if Group("behind", L["Behind your level"], on and #list or nil) then
    if not on then Note(L["The marker is off (options, Item level page)."], C.quiet)
    elseif #list == 0 then Note(L["No slot is far behind your level."], C.quiet) end
    for _, b in ipairs(on and list or {}) do
      local eq = ns.Equipped()[b.slot]
      local id = eq and ItemID(eq.link)
      items[#items + 1] = { key = "behind:" .. b.slot, title = ns.SlotLabel(b.slot), sub = eq and eq.link and ItemName(eq.link) or nil,
        itemID = id, icon = Icon(id), quality = eq and eq.quality, titleColor = C.title, status = "red",
        level = ns.FormatLevel(b.level), levelStatus = "red", badgeRight = true,
        tip = function()
          return ns.SlotLabel(b.slot), {
            { L["Item level"], ns.FormatLevel(b.level) },
            { L["Your level"], level and ("%d"):format(level) or "?" },
            L["Behind: item level more than %d below your level."]:format(tonumber(ns.db.behindLevels) or 8),
          }
        end }
    end
    if empty > 0 then Note(L["Empty slots"], C.yellow, ("%d"):format(empty)) end
  end

  -- Dungeons for your level
  local dungeons = ns.DungeonsForLevel(level)
  if Group("dungeons", L["Dungeons for your level"], #dungeons) then
    if #dungeons == 0 then
      local first = ns.FirstDungeonLevel()
      Note(first and L["No dungeon fits your level yet; the first starts at level %d."]:format(first)
        or L["No dungeon fits your level."], C.quiet)
    end
    for _, d in ipairs(dungeons) do
      items[#items + 1] = { key = "dungeon:" .. tostring(d.name), title = d.name, iconKind = "step_dungeon", iconPlain = true,
        status = "blue", right = ns.LevelRangeText(d.min, d.max), rightColor = C.yellow,
        tip = function()
          return d.name, { { L["Level range"], ns.LevelRangeText(d.min, d.max) },
            L["A dungeon for your level. Which items drop there, and for which slot, Geardon does not know."] }
        end }
    end
    local src = ns.dungeonStats and ns.dungeonStats.source == "Questdon" and "Questdon" or "warcrafttavern.com"
    Note(L["Level ranges: %s"]:format(src), C.quiet)
  end

  -- Bag cleanup
  local bag, kept = ns.CleanupList()
  local worth = 0
  for _, e in ipairs(bag) do worth = worth + (e.info.sellPrice or 0) end
  if Group("cleanup", L["Bag cleanup"], #bag, worth > 0 and Kit.Money(worth) or nil) then
    if #bag == 0 then Note(L["Nothing to clean up: no gear in your bags is worse than yours or unusable."], C.quiet) end
    for _, e in ipairs(bag) do
      local v = e.reason ~= "unusable" and ns.Judge(e.info) or nil
      local it = { key = "bag:" .. e.link .. ":" .. e.bag .. ":" .. e.slot, title = ItemName(e.link), quality = e.info.quality,
        itemID = e.info.itemID, icon = Icon(e.info.itemID),
        right2 = (e.info.sellPrice or 0) > 0 and Kit.Money(e.info.sellPrice) or nil }
      if e.reason == "unusable" then
        it.status, it.sub, it.right, it.rightColor = "red", L["Your character cannot use it."], L["not usable"], C.red
      else
        it.status, it.rightColor = "grey", C.muted
        it.sub = v and v.slot and Wear(v.slot, v.eqLevel) or nil
        it.right = ("%s (%s)"):format(ns.FormatLevel(e.info.level), "-" .. ns.FormatLevel(-e.diff))
      end
      it.tip = function()
        local lines = {}
        if e.reason == "unusable" then
          lines[#lines + 1] = L["Your character cannot use it."]
        else
          local j = ns.Judge(e.info)
          if j and j.slot then
            lines[#lines + 1] = { L["Item level"], ns.FormatLevel(e.info.level) }
            lines[#lines + 1] = { ns.SlotLabel(j.slot), ns.FormatLevel(j.eqLevel or 0) }
          end
          lines[#lines + 1] = L["Lower item level than what you wear, not of a higher quality."]
        end
        if (e.info.sellPrice or 0) > 0 then lines[#lines + 1] = { L["Vendor price"], Kit.Money(e.info.sellPrice) } end
        return ItemName(e.link), lines, L["Geardon only lists; nothing is sold or deleted."]
      end
      items[#items + 1] = it
    end
    if kept > 0 then Note(L["%d kept off the list: in an equipment set."]:format(kept), C.quiet) end
  end
  for _, it in ipairs(items) do
    if it.tip then it.tooltipFn = function() return it.tip() end end
  end
  return items, worth
end

-- the focus card: the chosen row (or the first item row) with what its tooltip says
local function Focus(items)
  local first
  for _, it in ipairs(items) do
    if it.tip then
      if it.key == selKey then return it end
      first = first or it
    end
  end
  return first
end

local function FillDetail(it)
  local Kit = GetKit()
  local C = Kit.C
  local d = W.detail
  local title, lines, hint = it.tip()
  d:SetHead({ icon = it.icon ~= QUESTION and it.icon or nil, title = title or it.title,
    titleColor = it.quality and Kit.QualityColor(it.quality) or C.hero, meta = it.sub })
  d:Begin()
  local COL = { warning = C.yellow, critical = C.red, good = C.green }
  for _, line in ipairs(lines or {}) do
    if type(line) == "table" then d:Line(line[1], C.body, line[2], COL[line[3]] or C.title)
    else d:Para(line, C.muted) end
  end
  if hint and hint ~= "" then d:Space() d:Para(hint, C.quiet) end
  d:End()
end

local function Place()
  if not (W and W.built) then return end
  local w, h = W.bw or 400, W.bh or 500
  W.hero:ClearAllPoints()
  W.hero:SetPoint("TOPLEFT", W.body, "TOPLEFT", 0, 0)
  W.hero:Layout(w)
  local top = W.hero:GetHeight() or 64
  local wide = w >= DETAIL_FROM and W.focus ~= nil and not W.noDetail
  local dw = wide and DETAIL_W or 0
  W.list:ClearAllPoints()
  W.list:SetPoint("TOPLEFT", W.body, "TOPLEFT", 0, -top)
  W.list:Resize(w - dw, math.max(40, h - top))
  if wide then
    W.detail:ClearAllPoints()
    W.detail:SetPoint("TOPRIGHT", W.body, "TOPRIGHT", 0, -top)
    W.detail:Layout(dw, math.max(60, h - top))
    W.detail:Show()
  else
    W.detail:Hide()
  end
  -- the foot: what Geardon does on the left, the vendor worth on the right
  local Kit = GetKit()
  local rw = 0
  if W.footRight:GetText() and W.footRight:GetText() ~= "" then
    rw = math.min(math.floor(w * 0.5), Kit.TextWidth and Kit.TextWidth(W.footRight) or 160)
    W.ui.Fit(W.footRight, rw)
  end
  if W.status then W.ui.Fit(W.status, math.max(40, w - 40 - (rw > 0 and rw + 8 or 0))) end
end

local function Draw()
  if not (W and W.built and W:IsShown()) then return end
  stats.fills = stats.fills + 1
  local Kit = GetKit()
  local items, worth = Items()
  W.items = items
  W.list:SetItems(items)
  W.focus = Focus(items)
  W.list.selected = nil
  if W.focus and W.focus.key == selKey then W.list:Select(W.focus) else W.list:Draw() end
  -- the head: level and class, your item level, the weakest slot
  local level = ns.Num(ns.Value(UnitLevel, "player"))
  local className = ns.Str(ns.Results(UnitClass, "player"))
  local lvWord = type(rawget(_G, "LEVEL")) == "string" and _G.LEVEL or L["Your level"]
  local avg = ns.PlayerAverage()
  local _, _, weak = ns.Average(ns.Equipped())
  local e = weak and ns.Equipped()[weak]
  W.hero:SetData({
    kicker = (level and (lvWord .. " " .. level) or "") .. (className and ((level and " · " or "") .. className) or ""),
    title = L["Item level"],
    value = avg and ns.FormatAverage(avg) or "?",
    label = (e and e.level) and L["Weakest slot: %s (%s)"]:format(ns.SlotLabel(weak), ns.FormatLevel(e.level)) or nil,
  })
  -- the foot: what the cleanup list brings at a vendor (that Geardon only lists, the rows' tooltips say)
  W:SetStatus(worth > 0 and L["Worth at a vendor"] or "")
  W.footRight:SetText(worth > 0 and Kit.Money(worth) or "")
  if W.focus and W.bw and W.bw >= DETAIL_FROM then FillDetail(W.focus) end
  Place()
end

local function Build()
  local Kit = GetKit()
  local C = Kit.C
  local blizz = UI ~= Kit
  W = UI.Window(blizz and "GeardonCheckPanelBlizz" or "GeardonCheckPanel", { title = "Geardon", subtitle = L["Gear check"], logo = LOGO,
    options = "Geardon", hint = "/gd", footer = true, store = Store(), width = blizz and BLIZZ_W or 440, height = blizz and BLIZZ_H or 560,
    min = { 340, 360 }, max = blizz and { 700, 840 } or { 760, 900 },
    onLayout = function(win, w, h)
      win.bw, win.bh = w, h
      if win.built then
        if w >= DETAIL_FROM and win.focus and not win.noDetail then FillDetail(win.focus) end
        Place()
      end
    end })
  W.ui, W.blizzLook = UI, blizz or nil
  W:Hide()
  W:SetScript("OnShow", function() Draw() end)
  W.hero = UI.Hero(W.body, { height = 64, column = 200 })
  W.list = UI.List(W.body, {
    onClick = function(it)
      if not it.tip then return end
      selKey, W.noDetail = it.key, nil
      Draw()
    end,
    onToggle = function(it)
      if type(Store().closed) ~= "table" then Store().closed = {} end
      Store().closed[it.key] = it.collapsed or nil
      Draw()
    end })
  W.detail = UI.Detail(W.body, { onClose = function() W.noDetail = true Place() end })
  W.detail:Hide()
  -- the worth on the right of the foot (the game's frame: DonCore Blizz f.footer over the strip, already clear of the grip)
  W.footRight = UI.Text(W.footer, "sub", C.body, "RIGHT")
  W.footRight:SetPoint("RIGHT", blizz and -4 or -24, 0)
  W.built = true
  W:Layout()
end

local said
local function SayLook()
  if said then return end
  said = true
  ns.Print(L["The gear check could not be built in the game's look, it opens in the Don look. /gd diag says why."])
end

local function PickUI()
  local Kit = GetKit()
  UI, lookNote = Kit, "kit"
  if not (ns.db and ns.db.blizzLook) then return end
  local Bz = LibStub("DonCore-1.0"):Get("Blizz", 5)
  -- (the option is on by default: a client that lacks the templates keeps the Don look without a word; only a build
  -- that fails speaks up, Create)
  if not Bz then lookNote = "kit (no DonCore Blizz)" return end
  local kit, miss = Bz.Kit()
  if not kit then lookNote = "kit (missing: " .. tostring(miss) .. ")" return end
  UI, lookNote = kit, "blizzard"
end

local function Create()
  PickUI()
  if UI == GetKit() then Build() return end
  -- the game's blocks: any error while building leaves the half-built window hidden and the Kit builds it
  local ok, err = pcall(Build)
  if ok then return end
  if W and W.Hide then pcall(W.Hide, W) end
  W = nil
  UI, lookNote = GetKit(), "kit (error: " .. tostring(err) .. ")"
  ns.RecordError("gear check blizz look", err)
  SayLook()
  Build()
end

local function Update()
  queued = false
  Draw()
end

-- Bags or gear changed: once per moment, only while the window is open.
function ns.UpdateCheck()
  if queued or not (W and W:IsShown()) then return end
  queued = true
  ns.After(0.3, Update)
end

function ns.ShowCheck()
  if not GetKit() then return ns.Print(L["Gear check"] .. ": DonCore Kit?") end
  if W and W:IsShown() then W:Hide() return end
  if not W then Create() end
  W:Show()
  Draw()
end

function ns.ResetCheckWindow()
  local st = Store()
  st.point, st.relPoint, st.x, st.y, st.w, st.h = nil, nil, nil, nil, nil, nil
  st.bz = nil -- the game's frame keeps its place and size there (DonCore Blizz)
  if W then
    W:ClearAllPoints()
    W:SetPoint("CENTER", UIParent, "CENTER", 260, 60)
    if W.blizzLook then W:SetSize(BLIZZ_W, BLIZZ_H) else W:SetSize(440, 560) end
  end
end

-- the window shown now, whichever look it was built in
function ns.CheckShown() return W ~= nil and W:IsShown() and true or false end
function ns.CheckFrame() return W end -- (tests)
-- "blizzard" or "kit", with the reason when the option is on and the Kit had to build (diag)
function ns.CheckLook() return lookNote end
-- the option blizzLook changed: the window is built again in the other look the next time it opens (it was open: now)
function ns.CheckReset()
  if not W then return end
  local open = W:IsShown()
  W:Hide()
  W = nil
  if open then ns.ShowCheck() end
end

ns.On("BAG_UPDATE_DELAYED", function() ns.UpdateCheck() end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.UpdateCheck() end)
ns.On("PLAYER_LEVEL_UP", function() ns.UpdateCheck() end)
ns.On("GET_ITEM_INFO_RECEIVED", function() ns.UpdateCheck() end)
