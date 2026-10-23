local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Inspected players: item level per slot and average. Blizzard's Forever
-- inspect frame shows neither. Used by the inspect frame and the group scan.
---------------------------------------------------------------------------
local stats = { updates = 0, incomplete = 0, gameAvg = 0, ownAvg = 0 }
ns.inspectStats = stats

-- slotName -> { level, quality, equipLoc, link }; second value: number of
-- slots that have an item whose data is not there yet.
function ns.ReadInspect(unit)
  local levels, missing = {}, 0
  for _, name in ipairs(ns.SLOT_ORDER) do
    local id = ns.SLOT[name]
    if id and name ~= "ShirtSlot" and name ~= "TabardSlot" then
      local link = ns.Str(ns.Call(GetInventoryItemLink, unit, id))
      if link then
        local info = ns.ItemInfo(link)
        if info and info.level then
          levels[name] = { level = info.level, quality = info.quality, equipLoc = info.equipLoc, link = link }
        else
          missing = missing + 1
        end
      elseif ns.Call(GetInventoryItemTexture, unit, id) ~= nil then
        missing = missing + 1 -- an item is there, its link not yet
      end
    end
  end
  return levels, missing
end

-- Average item level of an inspected unit: the game's number when it has
-- one, else ours from the slots. Returns avg, complete, levels, and the
-- number of slots whose item is still loading.
function ns.InspectAverage(unit)
  local levels, missing = ns.ReadInspect(unit)
  local game = C_PaperDollInfo and ns.Num(ns.Call(C_PaperDollInfo.GetInspectItemLevel, unit))
  if game and game > 0 then
    stats.gameAvg = stats.gameAvg + 1
    return game, true, levels, missing
  end
  local own = ns.Average(levels)
  stats.ownAvg = stats.ownAvg + 1
  return own, missing == 0, levels, missing
end

---------------------------------------------------------------------------
-- Inspect frame
---------------------------------------------------------------------------
local avgFrame

-- The average as one line of text inside the top of the model area, with
-- room to the border (Overlay.lua, ns.Plate).
local function AvgText()
  if avgFrame then return avgFrame end
  local parent = ns.Frame("InspectPaperDollFrame")
  if not parent then return nil end
  avgFrame = ns.Plate(parent)
  -- below Blizzard's talents button (the level line and the button sit at the top)
  local talents = ns.Frame("InspectPaperDollFrame.InspectTalents")
  local anchor = ns.Frame("InspectPaperDollFrame.LevelTextWrapper") or ns.Frame("InspectLevelText")
  if talents then
    avgFrame:SetPoint("TOP", talents, "BOTTOM", 0, -16)
  elseif anchor then
    avgFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -28)
  else
    avgFrame:SetPoint("TOP", parent, "TOP", 0, -72)
  end
  return avgFrame
end

local function SetAvg(f, avg, complete)
  ns.SetPlate(f, avg, not complete and L["loading"] or nil)
end

local function InspectUnit()
  local frame = ns.Frame("InspectFrame")
  local unit = frame and rawget(frame, "unit")
  if type(unit) == "string" and ns.Usable(unit) then return unit end
  return nil
end

local retry = 0
local PLACE = { place = "character" }
local function Update(self)
  stats.updates = stats.updates + 1
  local unit = InspectUnit()
  local on = ns.db.showInspect
  local avg, complete, levels, missing
  if unit and on then avg, complete, levels, missing = ns.InspectAverage(unit) end
  levels = levels or {}
  for _, name in ipairs(ns.SLOT_ORDER) do
    local button = ns.Frame("Inspect" .. name)
    if button then
      local e = levels[name]
      local grey = e and e.quality == 0 and not ns.db.showGrey
      if on and e and e.level and e.level > 1 and not grey and ns.QualityShown(e.quality) then
        ns.ShowLevel(button, e.level, e.quality, PLACE)
      else
        ns.HideLevel(button)
      end
    end
  end
  local f = AvgText()
  if f then
    if on and avg then
      SetAvg(f, avg, complete)
      f:Show()
    else
      f:Hide()
    end
  end
  -- items still loading: look again soon (up to 10 times per inspect)
  if on and unit and (not complete or (missing or 0) > 0) and retry < 10 then
    retry = retry + 1
    stats.incomplete = stats.incomplete + 1
    ns.After(0.4, function() ns.Dirty("inspect") end)
  end
  if unit and avg and ns.RememberLevel then
    local guid = ns.Value(UnitGUID, unit)
    if guid and complete then
      local _, _, weak = ns.Average(levels or {})
      local w = weak and levels[weak]
      ns.RememberLevel(guid, avg, "inspect", unit, weak, w and w.level)
    end
  end
end
ns.UpdateInspect = Update

ns.OnAddon("Blizzard_InspectUI", function()
  local parent = ns.Frame("InspectPaperDollFrame")
  stats.parent = parent and "InspectPaperDollFrame" or "missing"
  if parent then
    local w = ns.Watch("inspect", parent, Update, 2)
    if w then w:HookScript("OnShow", function() retry = 0 end) end
  end
end)

ns.On("INSPECT_READY", function(_, guid)
  local unit = InspectUnit()
  if unit and ns.Usable(guid) and ns.Value(UnitGUID, unit) == guid then
    retry = 0
    ns.Dirty("inspect")
  end
end)
