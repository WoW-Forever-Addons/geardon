local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (26.11.2026, Daniel: "für das Auktionshaus wäre es gut, wenn man da sehen könnte, mit einem Blick, wie viel Prozent das
-- Item denn besser ist als das jetzige getragene ... welche Brustplatte im AH die meisten Prozente hat"; chosen: Blizzard's
-- buy list, "Prozent plus Pfeil") On every gear row of Blizzard's auction house lists (the browse results and the offers
-- of one item: AuctionHouseFrame.BrowseResultsFrame.ItemList, AuctionHouseFrame.ItemBuyFrame.ItemList) the upgrade arrow
-- on the item's icon and the percent against what you wear in that slot at the right end of the name: green better, red
-- worse, grey when you cannot wear it. Own frames on the rows, mouse off, nothing of Blizzard's table is changed or hooked
-- (a column of its own would be a change in Blizzard's table: not done). The row's item from its data: an item link
-- where the row has one, else the link of its item key (C_TooltipInfo.GetItemKey, the same tooltip the row shows).
-- Option showAuction (on).
---------------------------------------------------------------------------
local stats = { updates = 0, rows = 0, shown = 0, lists = 0 }
ns.auctionStats = stats
if type(ns.defaults) == "table" and ns.defaults.showAuction == nil then ns.defaults.showAuction = true end

local keyLinks, keyLinksN = {}, 0
local function KeyLink(key)
  if type(key) ~= "table" then return nil end
  local id = ns.Num(key.itemID)
  if not id then return nil end
  local k = id .. ":" .. tostring(key.itemLevel or 0) .. ":" .. tostring(key.itemSuffix or 0)
  local link = keyLinks[k]
  if link ~= nil then return link or nil end
  local tip = C_TooltipInfo and C_TooltipInfo.GetItemKey
  if type(tip) == "function" then
    local ok, data = pcall(tip, id, key.itemLevel or 0, key.itemSuffix or 0)
    link = ok and type(data) == "table" and ns.Str(data.hyperlink) or nil
  end
  if not link then return "item:" .. id end -- not kept: the tooltip data may come later
  if keyLinksN >= 300 then keyLinks, keyLinksN = {}, 0 end
  keyLinks[k], keyLinksN = link, keyLinksN + 1
  return link
end
ns.AuctionKeyLink = KeyLink

local marks = setmetatable({}, { __mode = "k" })
local function Mark(row)
  local m = marks[row]
  if m then return m end
  m = CreateFrame("Frame", nil, row)
  m:SetAllPoints(row)
  if m.EnableMouse then m:EnableMouse(false) end
  local level = ns.Num(ns.Method(row, "GetFrameLevel"))
  if level then m:SetFrameLevel(level + 3) end
  m.text = m:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  m.text:SetJustifyH("RIGHT")
  m.arrow = ns.NewArrow(m, 14)
  marks[row] = m
  return m
end

local function Rgb(key, fallback)
  local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS[key]
  if c then return c[1], c[2], c[3] end
  return fallback[1], fallback[2], fallback[3]
end

-- the text and colour for a row's item; nil for anything that is not gear
local function Verdict(link)
  local ok, info = pcall(ns.ItemInfo, link)
  if not ok or type(info) ~= "table" or not ns.IsGear(info) then return nil end
  local pct, up, uncertain, wearable, empty, soon = ns.UpgradePercent(info)
  local text, r, g, b
  if empty then
    text = L["Empty slot"]
  elseif pct then
    text = ("%+d%%"):format(pct)
  end
  if not wearable then
    r, g, b = Rgb("textHint", { 0.55, 0.57, 0.6 })
  elseif empty or (pct and pct > 0) then
    r, g, b = Rgb("good", { 0.4, 0.8, 0.45 })
  elseif pct and pct < 0 then
    r, g, b = Rgb("critical", { 0.92, 0.35, 0.32 })
  else
    r, g, b = 1, 1, 1
  end
  local arrow = wearable and (up or soon) and ns.db and ns.db.upgradeArrow
  return text, r, g, b, arrow, (not up and soon and "soon") or (uncertain and true or false)
end

-- the icon and the name cell of a row, where Blizzard's cell has them
local function Cells(row)
  local cells = rawget(row, "cells")
  local first = type(cells) == "table" and cells[1] or nil
  local icon = first and (rawget(first, "Icon") or rawget(first, "icon"))
  return first, icon
end

local function UpdateRow(row)
  local data = rawget(row, "rowData")
  if data == nil and type(row.GetElementData) == "function" then
    local ok, d = pcall(row.GetElementData, row)
    data = ok and d or nil
  end
  local m = marks[row]
  local link = ns.db.showAuction and type(data) == "table" and (ns.Str(data.itemLink) or KeyLink(data.itemKey)) or nil
  local text, r, g, b, arrow, check
  if link then text, r, g, b, arrow, check = Verdict(link) end
  if not (text or arrow) then
    if m then m:Hide() end
    return false
  end
  m = m or Mark(row)
  local first, icon = Cells(row)
  m.text:ClearAllPoints()
  if first then m.text:SetPoint("RIGHT", first, "RIGHT", -4, 0) else m.text:SetPoint("LEFT", row, "LEFT", 190, 0) end
  m.text:SetText(text or "")
  m.text:SetTextColor(r or 1, g or 1, b or 1)
  if arrow then
    m.arrow:SetPoint("TOPLEFT", icon or row, "TOPLEFT", -3, 3)
    m.arrow:Look(check)
  end
  m.arrow:SetShown(arrow)
  m:Show()
  return true
end

local function UpdateList(list)
  stats.updates = stats.updates + 1
  local box = rawget(list, "ScrollBox")
  if type(box) ~= "table" or type(box.ForEachFrame) ~= "function" then return end
  local rows = {}
  pcall(box.ForEachFrame, box, function(row) rows[#rows + 1] = row end)
  local n = 0
  for _, row in ipairs(rows) do
    if UpdateRow(row) then n = n + 1 end
  end
  stats.rows, stats.shown = #rows, n
end

local function Attach()
  local f = ns.Frame("AuctionHouseFrame")
  if not f then return end
  local n = 0
  for key, path in pairs({ ahBrowse = "BrowseResultsFrame", ahItem = "ItemBuyFrame" }) do
    local part = rawget(f, path)
    local list = type(part) == "table" and rawget(part, "ItemList")
    if type(list) == "table" then
      n = n + 1
      ns.Watch(key, list, function() UpdateList(list) end, 0.5)
    end
  end
  stats.lists = n
end
ns.On("AUCTION_HOUSE_SHOW", function() Attach() ns.Dirty("ahBrowse") ns.Dirty("ahItem") end)
for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "GET_ITEM_INFO_RECEIVED" }) do
  ns.On(e, function() ns.Dirty("ahBrowse") ns.Dirty("ahItem") end)
end
ns.OnInit(Attach) -- (a reload while the auction house is open)
