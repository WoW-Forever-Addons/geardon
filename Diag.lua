local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- /gd diag: what Geardon found and did, for bug reports and the first
-- in-game tests (game functions, frames, item level sources, group).
---------------------------------------------------------------------------
local APIS = {
  "C_Item.GetDetailedItemLevelInfo", "C_Item.GetCurrentItemLevel", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant",
  "C_Item.GetItemQualityColor", "C_Item.RequestLoadItemDataByID", "C_PlayerInfo.CanUseItem",
  "C_PaperDollInfo.GetInspectItemLevel", "GetAverageItemLevel", "NotifyInspect", "CanInspect", "ClearInspectPlayer",
  "C_ChatInfo.SendAddonMessage", "TooltipDataProcessor.AddTooltipPostCall", "C_Container.GetContainerItemLink",
  "GetLootSlotLink", "GetQuestItemLink", "GetQuestLogItemLink", "ItemLocation.CreateFromEquipmentSlot",
  -- (1.2.0)
  "C_Item.GetItemStats", "GetItemStats", "C_Item.IsBound", "ItemLocation.CreateFromBagAndSlot", "C_TooltipInfo.GetBagItem",
  "C_TooltipInfo.GetInventoryItem", "C_EquipmentSet.GetEquipmentSetIDs", "C_EquipmentSet.GetItemIDs", "IsPlayerSpell",
  "C_Map.GetMapInfo", "C_Container.GetContainerNumSlots",
}

local function Lookup(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    local ok, nv = pcall(function() return v[part] end)
    if not ok then return nil end
    v = nv
  end
  return v
end

local function Kv(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. tostring(t[k]) end
  return table.concat(out, ", ")
end

function ns.DiagLines()
  local out = {}
  local build, _, _, iface = ns.Results(GetBuildInfo)
  out[#out + 1] = ("Geardon %s, client %s, interface %s, locale %s"):format(ns.Version(), tostring(build), tostring(iface),
    tostring(ns.Value(GetLocale)))
  local missing = {}
  for _, path in ipairs(APIS) do
    if type(Lookup(path)) ~= "function" then missing[#missing + 1] = path end
  end
  out[#out + 1] = "missing functions: " .. (#missing > 0 and table.concat(missing, ", ") or "none")

  -- own average: the game's number next to Geardon's formula
  local game1, game2 = ns.Results(GetAverageItemLevel)
  local own, have, weakest = ns.Average(ns.Equipped())
  local withRanged
  do
    local eq, sum, n = ns.Equipped(), 0, 0
    for _, name in ipairs(ns.AVG_SLOTS) do if eq[name] and eq[name].level then sum, n = sum + eq[name].level, n + 1 end end
    if eq.RangedSlot and eq.RangedSlot.level then sum = sum + eq.RangedSlot.level end
    withRanged = sum / (ns.AVG_COUNT + 1)
  end
  out[#out + 1] = ("average: game %s / %s, Geardon %s (%d slots, weakest %s), with ranged /17 %s"):format(
    tostring(ns.Num(game1) and ns.FormatLevel(game1)), tostring(ns.Num(game2) and ns.FormatLevel(game2)),
    tostring(own and ns.FormatLevel(own)), have or 0, tostring(weakest), ns.FormatLevel(withRanged))
  local eqParts = {}
  for _, name in ipairs(ns.SLOT_ORDER) do
    local e = ns.Equipped()[name]
    if e then eqParts[#eqParts + 1] = ("%s=%s%s"):format(name:gsub("Slot", ""), tostring(e.level), e.pending and "?" or "") end
  end
  out[#out + 1] = "equipped: " .. (#eqParts > 0 and table.concat(eqParts, " ") or "nothing")
  out[#out + 1] = "slot ids: ranged " .. tostring(ns.SLOT.RangedSlot) .. ", tabard " .. tostring(ns.SLOT.TabardSlot)

  local n, on = ns.CountOverlays()
  out[#out + 1] = ("overlays: %d, showing %d; %s"):format(n, on, Kv(ns.overlayStats))
  out[#out + 1] = "character: " .. Kv(ns.characterStats)
  out[#out + 1] = "inspect: " .. Kv(ns.inspectStats)
  out[#out + 1] = "bags: " .. Kv(ns.bagStats)
  out[#out + 1] = "loot: " .. Kv(ns.lootStats)
  out[#out + 1] = "flyout, merchant: " .. Kv(ns.flyoutStats)
  out[#out + 1] = "tooltip: " .. Kv(ns.tooltipStats)
  out[#out + 1] = "items: " .. Kv(ns.itemStats)
  out[#out + 1] = "group: " .. (ns.GroupDiag and ns.GroupDiag() or "?")
  -- (1.2.0)
  out[#out + 1] = ("upgrade: class %s, best armour %s; %s"):format(tostring(ns.PlayerClass and ns.PlayerClass()),
    tostring(ns.BestArmorSubclass and ns.BestArmorSubclass()), Kv(ns.upgradeStats))
  out[#out + 1] = "bag addons: " .. Kv(ns.bagAddonStats)
  out[#out + 1] = ("gear check: %s; dungeons %s; chat %s"):format(Kv(ns.checkStats), Kv(ns.dungeonStats), Kv(ns.changeStats))
  local watchers = {}
  for key in pairs(ns.Watchers()) do watchers[#watchers + 1] = key end
  table.sort(watchers)
  out[#out + 1] = "watching: " .. table.concat(watchers, ", ")

  local errors = ns.Errors()
  if #errors == 0 then
    out[#out + 1] = "errors: none"
  else
    for _, e in ipairs(errors) do out[#out + 1] = ("error [%s] x%d: %s"):format(e.context, e.count, e.msg) end
    if ns.droppedErrors then out[#out + 1] = ("more errors not listed: %d"):format(ns.droppedErrors) end
  end
  return out
end

function ns.PrintDiag()
  ns.Print(L["Diagnostics:"])
  for _, line in ipairs(ns.DiagLines()) do print("  " .. line) end
end

---------------------------------------------------------------------------
-- Window with a report to copy (Ctrl+A, Ctrl+C)
---------------------------------------------------------------------------
local panel, report

local function Store()
  if type(ns.db.diagWindow) ~= "table" then ns.db.diagWindow = {} end
  return ns.db.diagWindow
end

local function Build()
  local Style = ns.Style
  panel = Style.Panel("GeardonDiagPanel", UIParent, {
    title = Style.Wordmark("Gear", "don") .. "  " .. Style.Colorize(L["Diagnostics"], "textSecondary"),
    width = 380, close = true, closeTooltip = L["Close"],
    get = function(key) return Store()[key] end,
    set = function(key, value) Store()[key] = value end,
    defaultPoint = { "CENTER", "CENTER", 0, 80 },
    strata = "DIALOG",
  })
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetWidth(330)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnTextChanged", function(self, user) if user and self._text then self:SetText(self._text) end end)
  scroll:SetScrollChild(box)
  report = { scroll = scroll, box = box }
end

function ns.ShowDiag()
  if not (ns.Style and ns.Style.Panel and ns.Style.Content) then return ns.PrintDiag() end
  if not panel then Build() end
  panel:ClearRows()
  ns.Style.Header(panel, L["Report to copy"])
  report.box._text = table.concat(ns.DiagLines(), "\n")
  report.box:SetText(report.box._text)
  ns.Style.Content(panel, report.scroll, 220)
  ns.Style.Row(panel):SetText(L["/gd diag chat prints everything to the chat. In the report: Ctrl+A, Ctrl+C copies it."], "textHint")
  panel:FadeIn()
end

ns.OnInit(function()
  if ns.Style then ns.Style.onError = function(where, err) ns.RecordError("kit:" .. tostring(where), err) end end
end)
