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
  local diff, slot, eqLevel
  if kind == "full" and ns.db.tooltipCompare then
    diff, slot, eqLevel = ns.Compare(info)
    -- an item you wear (either ring, trinket or weapon slot) is not compared
    for _, name in ipairs(ns.TargetSlots(info.equipLoc) or {}) do
      local eq = ns.Equipped()[name]
      if eq and eq.link == link then diff = nil end
    end
  end
  if not showLevel and not diff then return end
  local nr, ng, nb = 1, 0.82, 0 -- Blizzard's yellow for item level
  local left = showLevel and L["Item level %s"]:format(ns.FormatLevel(info.level)) or " "
  if diff then
    local where = (eqLevel and eqLevel > 0)
      and L["%s vs. %s (%s)"]:format(DiffText(diff), ns.SlotLabel(slot), ns.FormatLevel(eqLevel))
      or L["%s, %s slot empty"]:format(DiffText(diff), ns.SlotLabel(slot))
    if not showLevel then left = L["Item level"] end
    local sr, sg, sb = Rgb("textSecondary")
    tooltip:AddDoubleLine(left, where, nr, ng, nb, sr, sg, sb)
    stats.compare = stats.compare + 1
  else
    tooltip:AddLine(left, nr, ng, nb)
  end
  if showLevel then stats.levelAdded = stats.levelAdded + 1 end
end

local function OnUnit(tooltip, data)
  if not ns.db.unitTooltip or tooltip ~= rawget(_G, "GameTooltip") then return end
  local guid = type(data) == "table" and data.guid or nil
  if not (type(guid) == "string" and ns.Usable(guid)) then return end
  if not guid:find("^Player%-") then return end
  local level, src = ns.LevelOf and ns.LevelOf(guid)
  if not level then return end
  stats.units = stats.units + 1
  -- Blizzard's yellow for the label (like the item level in item tooltips
  -- and on the character frame), the value in white
  tooltip:AddDoubleLine(L["Item level"], ns.FormatAverage(level), 1, 0.82, 0, 1, 1, 1)
end

ns.OnInit(function()
  local T = TooltipDataProcessor
  local E = Enum and Enum.TooltipDataType
  if not (T and T.AddTooltipPostCall and E) then stats.hooked = "missing" return end
  local ok1 = pcall(T.AddTooltipPostCall, E.Item, ns.Guard("tooltip:item", OnItem))
  local ok2 = pcall(T.AddTooltipPostCall, E.Unit, ns.Guard("tooltip:unit", OnUnit))
  stats.hooked = (ok1 and "item " or "") .. (ok2 and "unit" or "")
end)
