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
  -- (1.3.0)
  local db = ns.db or {}
  out[#out + 1] = ("1.3.0: soon %s (%s levels), pair %s, chat upgrade %s, inspect mine %s"):format(tostring(db.arrowSoon),
    tostring(db.soonLevels), tostring(db.arrowPair), tostring(db.chatUpgrade), tostring(db.inspectMine))
  out[#out + 1] = ("gear check: %s; dungeons %s; chat %s"):format(Kv(ns.checkStats), Kv(ns.dungeonStats), Kv(ns.changeStats))
  -- (Leistungsrunde 6) kept judgements: computed, taken from the memo, not kept (data missing), DonData notices
  out[#out + 1] = ("judge: %s; kept now %s; DonData notices %s"):format(Kv(ns.judgeStats), tostring(ns.JudgeMemoOK and ns.JudgeMemoOK()),
    tostring(ns.donDataNotices or 0))
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
-- (02.11.2026, StyleKit 2 step 4, docs/layout_2026-11-02/geardon/) DonCore's one copy window (Kit.ShowCopy, the same as
-- Leveldon's export) instead of a panel with an edit box of our own.
---------------------------------------------------------------------------
function ns.ShowDiag()
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  if not (Kit and Kit.ShowCopy) then return ns.PrintDiag() end
  return Kit.ShowCopy("Geardon · " .. L["Diagnostics"], L["Ctrl+A, Ctrl+C copies the report."],
    table.concat(ns.DiagLines(), "\n"), { selectAll = L["Select all"], close = L["Close"] })
end

ns.OnInit(function()
  -- the kit is shared (DonCore): keep the handler of an addon loaded earlier and call it as well
  if ns.Style then
    local before = ns.Style.onError
    ns.Style.onError = function(where, err)
      ns.RecordError("kit:" .. tostring(where), err)
      if before then pcall(before, where, err) end
    end
  end
  -- (02.11.2026) the Kit's windows (gear check, copy window) report their errors the same way
  local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
  if Kit then
    local before = Kit.onError
    Kit.onError = function(where, err)
      ns.RecordError("kit:" .. tostring(where), err)
      if before then pcall(before, where, err) end
    end
  end
end)
