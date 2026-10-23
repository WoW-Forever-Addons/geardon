local _, ns = ...

---------------------------------------------------------------------------
-- Character frame: item level on every equipped slot and your average (the
-- Forever character frame shows neither); the weakest counted slot is
-- shown in the warning colour.
---------------------------------------------------------------------------
local stats = { updates = 0, slots = 0, behind = 0 }
ns.characterStats = stats

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) "Behind your level": an equipped item whose item
-- level is below your character level minus behindLevels (default 8, set in
-- the options). The number shows in the critical colour; the plate's tooltip
-- and the gear check (/gd check) list these slots.
---------------------------------------------------------------------------
local BEHIND_SLOTS = {}
for _, name in ipairs(ns.AVG_SLOTS) do BEHIND_SLOTS[#BEHIND_SLOTS + 1] = name end
BEHIND_SLOTS[#BEHIND_SLOTS + 1] = "RangedSlot"

-- Item level under which an item is "behind"; nil when the marker is off or the level is unknown.
function ns.BehindLimit()
  if not (ns.db and ns.db.behindMarker) then return nil end
  local level = ns.Num(ns.Value(UnitLevel, "player"))
  if not level then return nil end
  return level - (tonumber(ns.db.behindLevels) or 8)
end

-- { { slot, level }, ... } lowest first, and the number of empty counted slots.
function ns.BehindSlots()
  local list, empty = {}, 0
  local limit = ns.BehindLimit()
  local eq = ns.Equipped()
  local mh = eq.MainHandSlot
  for _, name in ipairs(BEHIND_SLOTS) do
    local e = eq[name]
    if e and e.level then
      if limit and e.level < limit then list[#list + 1] = { slot = name, level = e.level } end
    elseif not e and name ~= "RangedSlot" and not (name == "SecondaryHandSlot" and mh and mh.equipLoc == "INVTYPE_2HWEAPON") then
      empty = empty + 1
    end
  end
  table.sort(list, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.slot < b.slot end)
  return list, empty
end

local function Update()
  stats.updates = stats.updates + 1
  local on = ns.db.showCharacter
  local eq = ns.Equipped()
  local _, _, weakest = ns.Average(eq)
  local limit = ns.BehindLimit()
  local shown, behind = 0, 0
  for _, name in ipairs(ns.SLOT_ORDER) do
    local button = ns.Frame("Character" .. name)
    if button then
      local e = eq[name]
      local info = e and ns.ItemInfo(e.link)
      local grey = info and info.quality == 0 and not ns.db.showGrey
      if on and e and e.level and e.level > 1 and name ~= "ShirtSlot" and name ~= "TabardSlot" and not grey
        and ns.QualityShown(e.quality) then
        local isBehind = limit and e.level < limit or false
        if isBehind then behind = behind + 1 end
        ns.ShowLevel(button, e.level, e.quality, { weak = ns.db.markWeakest and name == weakest, behind = isBehind,
          place = "character" })
        shown = shown + 1
      else
        ns.HideLevel(button)
      end
    end
  end
  stats.slots, stats.behind = shown, behind
  ns.UpdateCharacterAverage()
end

-- Your average as two centred lines of text in the free bottom left corner. Blizzard's Forever character frame does not show it. Empty slots
-- count as 0, like the game counts them; the plate says how many are empty.
local plate, placed

-- Edges of a frame (left, right, top, bottom), nil while not laid out.
local function Edges(frame)
  if not frame then return nil end
  local l = ns.Num(ns.Method(frame, "GetLeft"))
  local r = ns.Num(ns.Method(frame, "GetRight"))
  local t = ns.Num(ns.Method(frame, "GetTop"))
  local b = ns.Num(ns.Method(frame, "GetBottom"))
  if l and r and t and b then return l, r, t, b end
end

-- Bottom left: the free corner below the last left slot (wrist) and left of
-- the main hand, the same for every class (the ammo slot exists only for
-- some). Centred in that corner, so the space around is even.
local function Place(host)
  local pane = ns.Frame("CharacterFrameLeftPaneHost") or ns.Frame("CharacterModelScene")
  local wrist = ns.Frame("CharacterWristSlot")
  local mainHand = ns.Frame("CharacterMainHandSlot")
  local pl, _, _, pb = Edges(pane)
  local _, _, _, wb = Edges(wrist)
  local ml = Edges(mainHand)
  plate:ClearAllPoints()
  if pl and pb and wb and ml and ml > pl and wb > pb then
    local cx, cy = (pl + ml) / 2, (wb + pb) / 2
    plate:SetPoint("CENTER", pane, "BOTTOMLEFT", cx - pl, cy - pb)
    placed = true
  elseif mainHand then
    plate:SetPoint("RIGHT", mainHand, "LEFT", -12, 0)
  else
    plate:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 16, 16)
  end
  local level = ns.Num(ns.Method(mainHand or host, "GetFrameLevel"))
  plate:SetFrameLevel((level or 5) + 5)
end

local function EmptySlots()
  local eq, empty = ns.Equipped(), 0
  local mh = eq.MainHandSlot
  for _, name in ipairs(ns.AVG_SLOTS) do
    if not eq[name] and not (name == "SecondaryHandSlot" and mh and mh.equipLoc == "INVTYPE_2HWEAPON") then
      empty = empty + 1
    end
  end
  return empty
end

-- (1.2.0) The plate's tooltip: slots behind your level, empty slots, the
-- weakest slot and the dungeons for your level; a click opens the gear check.
local function PlateTooltip(self)
  local L = ns.L
  local lines = {}
  local list, empty = ns.BehindSlots()
  if ns.BehindLimit() then
    lines[#lines + 1] = { header = L["Behind your level"] }
    if #list == 0 then
      lines[#lines + 1] = L["No slot is far behind your level."]
    else
      for _, b in ipairs(list) do lines[#lines + 1] = { ns.SlotLabel(b.slot), ns.FormatLevel(b.level), "critical" } end
    end
  end
  if empty > 0 then lines[#lines + 1] = { L["Empty slots"], ("%d"):format(empty), "warning" } end
  local _, _, weak = ns.Average(ns.Equipped())
  local w = weak and ns.Equipped()[weak]
  if w and w.level then lines[#lines + 1] = { L["Weakest slot"], ("%s (%s)"):format(ns.SlotLabel(weak), ns.FormatLevel(w.level)), "warning" } end
  if ns.DungeonsForLevel then
    local dungeons = ns.DungeonsForLevel()
    if #dungeons > 0 then
      lines[#lines + 1] = { header = L["Dungeons for your level"] }
      for i = 1, math.min(3, #dungeons) do
        local d = dungeons[i]
        lines[#lines + 1] = { d.name, ns.LevelRangeText(d.min, d.max) }
      end
    end
  end
  ns.Style.Tooltip(self, L["Item level"] .. " " .. ns.FormatAverage(ns.PlayerAverage()), lines, L["Click: gear check (/gd check)"], "auto")
end

local function MakeInteractive(f)
  if not (ns.Style and ns.Style.Tooltip) or not f.EnableMouse then return end
  f:EnableMouse(true)
  f:SetScript("OnEnter", ns.Guard("plate:enter", PlateTooltip))
  f:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)
  f:SetScript("OnMouseUp", ns.Guard("plate:click", function() if ns.ShowCheck then ns.ShowCheck() end end))
end

function ns.UpdateCharacterAverage()
  local host = ns.Frame("PaperDollItemsFrame") or ns.Frame("PaperDollFrame")
  if not plate and host then
    plate = ns.Plate(host, nil, true)
    MakeInteractive(plate)
  end
  if not plate then return end
  -- slot positions are known once the frame is laid out: place until it worked
  if not placed then Place(host) end
  local avg = ns.db.showAverage and ns.PlayerAverage()
  if avg then
    local empty = EmptySlots()
    -- short label: the plate has to fit between the ammo slot and the trinkets
    ns.SetPlate(plate, avg, empty > 0 and ns.L["%d empty"]:format(empty) or nil, ns.L["Item level (short)"])
    plate:Show()
  else
    plate:Hide()
  end
  stats.average = avg and ns.FormatAverage(avg) or "off"
end
ns.UpdateCharacter = Update

ns.OnInit(function()
  local parent = ns.Frame("PaperDollItemsFrame") or ns.Frame("PaperDollFrame") or ns.Frame("CharacterFrame")
  stats.parent = parent and (ns.Method(parent, "GetName") or "?") or "missing"
  if parent then ns.Watch("character", parent, Update, 2) end
end)

ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Dirty("character") end)
ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", function() ns.Dirty("character") end)
ns.On("GET_ITEM_INFO_RECEIVED", function() ns.Dirty() end)
local function LevelChanged() ns.ClearItemCache() ns.MarkEquippedDirty() ns.Dirty() end
ns.On("PLAYER_LEVEL_UP", LevelChanged)
ns.On("PLAYER_LEVEL_CHANGED", LevelChanged)
ns.On("SKILL_LINES_CHANGED", function() ns.Dirty() end)
