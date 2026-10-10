local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Tooltips through Blizzard's tooltip data callbacks (the same way Questdon
-- adds its unit lines):
-- items: "Item level 18" when the game's tooltip has no item level line,
--        plus the difference to what you wear in that slot;
-- players: their average item level, when Geardon knows it.
---------------------------------------------------------------------------
local stats = { items = 0, levelAdded = 0, gameLevel = 0, compare = 0, units = 0 }
ns.tooltipStats = stats

local ITEM_TOOLTIPS = { GameTooltip = "full", ItemRefTooltip = "full", ShoppingTooltip1 = "level", ShoppingTooltip2 = "level" }

local function Kind(tooltip)
  for name, kind in pairs(ITEM_TOOLTIPS) do
    if rawget(_G, name) == tooltip then return kind end
  end
  return nil
end

local function LineType()
  local e = Enum and Enum.TooltipDataLineType
  return e and ns.Num(e.ItemLevel) or 31
end

-- Does the game's tooltip already show the item level?
local function HasLevelLine(data, level)
  local lines = type(data) == "table" and data.lines
  if type(lines) ~= "table" then return false end
  local t = LineType()
  local pattern = ns.Str(rawget(_G, "ITEM_LEVEL"))
  pattern = pattern and ("^" .. pattern:gsub("%%d", "(%%d+)"):gsub("%%s", "(.+)"))
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      if line.type == t then return true end
      local text = ns.Str(line.leftText)
      if text and pattern and text:match(pattern) then return true end
    end
  end
  return false
end

local function Rgb(key)
  local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS[key]
  if c then return c[1], c[2], c[3] end
  return 1, 1, 1
end

local function DiffText(diff)
  local r = math.floor(diff * 10 + 0.5) / 10
  if r > 0 then return "|cff66cc73+" .. ns.FormatLevel(r) .. "|r" end
  if r < 0 then return "|cffeb5952-" .. ns.FormatLevel(-r) .. "|r" end
  return "|cff9ea3ad=|r"
end

-- (1.2.0, Daniel 10.10.) Why an item that is higher than yours has no arrow,
-- and why an arrow is the yellow "check" one.
local BLOCK_TEXT = {
  level = "No arrow: you cannot wear it yet.",
  wear = "Your character cannot use it.",
  twohand = "No arrow: it would take your two-hand weapon away.",
  weapon = "No arrow: not a weapon type you use.",
  armor = "No arrow: not your best armor type.",
  stats = "No arrow: none of your class's main stats.",
}
local CHECK_TEXT = {
  quality = "Lower quality than yours: compare the stats.",
  set = "Replaces a piece of your set: you may lose the set bonus.",
}

local function OnItem(tooltip, data)
  local kind = Kind(tooltip)
  if not kind then return end
  local ok, _, link = pcall(tooltip.GetItem, tooltip)
  link = ok and ns.Str(link)
  if not link then return end
  local info = ns.ItemInfo(link)
  if not ns.IsGear(info) then return end
  stats.items = stats.items + 1
  local hasLine = HasLevelLine(data, info.level)
  if hasLine then stats.gameLevel = stats.gameLevel + 1 end
  local showLevel = ns.db.tooltipLevel and not hasLine
  local v
  if kind == "full" and ns.db.tooltipCompare then
    v = ns.Judge(info)
    -- an item you wear (either ring, trinket or weapon slot) is not compared
    for _, name in ipairs(ns.TargetSlots(info.equipLoc) or {}) do
      local eq = ns.Equipped()[name]
      if eq and eq.link == link then v = nil end
    end
  end
  local diff, slot, eqLevel = v and v.diff, v and v.slot, v and v.eqLevel
  local split = kind == "full" and ns.db.tooltipStatSplit and ns.StatSplitText(ns.ItemStats(info, type(data) == "table" and data.lines))
  if not showLevel and not diff and not split then return end
  local nr, ng, nb = 1, 0.82, 0 -- Blizzard's yellow for item level
  local sr, sg, sb = Rgb("textSecondary")
  if showLevel or diff then
    local left = showLevel and L["Item level %s"]:format(ns.FormatLevel(info.level)) or " "
    if diff then
      local where = (eqLevel and eqLevel > 0)
        and L["%s vs. %s (%s)"]:format(DiffText(diff), ns.SlotLabel(slot), ns.FormatLevel(eqLevel))
        or L["%s, %s slot empty"]:format(DiffText(diff), ns.SlotLabel(slot))
      if not showLevel then left = L["Item level"] end
      tooltip:AddDoubleLine(left, where, nr, ng, nb, sr, sg, sb)
      stats.compare = stats.compare + 1
    else
      tooltip:AddLine(left, nr, ng, nb)
    end
    if showLevel then stats.levelAdded = stats.levelAdded + 1 end
  end
  if split then
    tooltip:AddLine(split, sr, sg, sb)
    stats.split = (stats.split or 0) + 1
  end
  if v then
    local wr, wg, wb = Rgb("warning")
    if v.check then
      for key in v.check:gmatch("[^+]+") do
        if CHECK_TEXT[key] then tooltip:AddLine(L[CHECK_TEXT[key]], wr, wg, wb, true) end
      end
    elseif v.note == "quality" then
      tooltip:AddLine(L["Higher quality than yours: compare the stats."], wr, wg, wb, true)
    elseif v.block and BLOCK_TEXT[v.block] and diff and diff > 0 then
      local hr, hg, hb = Rgb("textHint")
      tooltip:AddLine(L[BLOCK_TEXT[v.block]], hr, hg, hb, true)
    end
  end
end

-- (1.2.0, Daniel 10.10.) What our post-call saw on the player tooltip last:
-- the player's GUID and whether the item level line is in it. A result that
-- arrives while that tooltip is still open goes in right away, once.
local unitShown = { guid = nil, line = false }

local function AddUnitLine(tooltip, level)
  -- Blizzard's yellow for the label (like the item level in item tooltips
  -- and on the character frame), the value in white
  tooltip:AddDoubleLine(L["Item level"], ns.FormatAverage(level), 1, 0.82, 0, 1, 1, 1)
  unitShown.line = true
end

local function OnUnit(tooltip, data)
  if not ns.db.unitTooltip or tooltip ~= rawget(_G, "GameTooltip") then return end
  unitShown.guid, unitShown.line = nil, false
  local guid = type(data) == "table" and data.guid or nil
  if not (type(guid) == "string" and ns.Usable(guid)) then return end
  if not guid:find("^Player%-") then return end
  unitShown.guid = guid
  -- known value (also in combat, where nothing new is asked); else the line
  -- comes when the inspect answers (ns.UnitTooltipLevelArrived), no placeholder
  local level = ns.LevelOf and ns.LevelOf(guid)
  if not level then return end
  stats.units = stats.units + 1
  AddUnitLine(tooltip, level)
end

-- The open player tooltip still shows this player (same GUID) and has no
-- line yet: add it and let the tooltip resize (Show on the shown tooltip).
function ns.UnitTooltipLevelArrived(guid)
  local tt = rawget(_G, "GameTooltip")
  if not (tt and ns.db.unitTooltip and guid and unitShown.guid == guid and not unitShown.line) then return end
  if ns.Method(tt, "IsShown") ~= true then return end
  local _, unit = ns.Results(tt.GetUnit, tt)
  if type(unit) ~= "string" or not ns.Usable(unit) or ns.Value(UnitGUID, unit) ~= guid then return end
  local level = ns.LevelOf and ns.LevelOf(guid)
  if not level then return end
  AddUnitLine(tt, level)
  pcall(tt.Show, tt)
  stats.live = (stats.live or 0) + 1
end

ns.OnInit(function()
  local T = TooltipDataProcessor
  local E = Enum and Enum.TooltipDataType
  if not (T and T.AddTooltipPostCall and E) then stats.hooked = "missing" return end
  local ok1 = pcall(T.AddTooltipPostCall, E.Item, ns.Guard("tooltip:item", OnItem))
  local ok2 = pcall(T.AddTooltipPostCall, E.Unit, ns.Guard("tooltip:unit", OnUnit))
  stats.hooked = (ok1 and "item " or "") .. (ok2 and "unit" or "")
end)
