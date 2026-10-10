local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) One chat line when your average item level changes:
-- "Item level 24.3 -> 25.1 (Head +6)" (option chatChange). Quiet on login and
-- loading screens (the first complete read only sets the baseline), and
-- gear swaps in quick succession (an equipment set, several items from a
-- quest) make one line: every change waits DEBOUNCE seconds for the next.
---------------------------------------------------------------------------
local DEBOUNCE = 2
local QUIET_AFTER_LOGIN = 5
local MAX_SLOTS = 3

local base       -- { avg, levels = { slotName = level } }
local gen, quietUntil, tries = 0, 0, 0
local stats = { lines = 0, checks = 0 }
ns.changeStats = stats

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

-- Snapshot of the counted slots (and the ranged slot), nil while an item is still loading.
local function Snapshot()
  local eq = ns.Equipped()
  local levels = {}
  for name, e in pairs(eq) do
    if e.pending then return nil end
    if name ~= "ShirtSlot" and name ~= "TabardSlot" then levels[name] = e.level end
  end
  if next(levels) == nil then return nil end
  local avg = ns.PlayerAverage()
  if not avg then return nil end
  return { avg = avg, levels = levels }
end

local function Signed(diff)
  if diff > 0 then return "+" .. ns.FormatLevel(diff) end
  return "-" .. ns.FormatLevel(-diff)
end

-- "Head +6, Hands -2" (empty slots count as 0), at most MAX_SLOTS, biggest change first.
local function SlotChanges(old, new)
  local list, seen = {}, {}
  for _, name in ipairs(ns.SLOT_ORDER) do
    if not seen[name] and name ~= "ShirtSlot" and name ~= "TabardSlot" then
      seen[name] = true
      local a, b = old[name] or 0, new[name] or 0
      if math.abs(a - b) >= 0.5 then list[#list + 1] = { name = name, diff = b - a } end
    end
  end
  table.sort(list, function(x, y) return math.abs(x.diff) > math.abs(y.diff) end)
  local out = {}
  for i = 1, math.min(MAX_SLOTS, #list) do
    out[#out + 1] = ("%s %s"):format(ns.SlotLabel(list[i].name), Signed(list[i].diff))
  end
  if #list > MAX_SLOTS then out[#out + 1] = "..." end
  return table.concat(out, ", ")
end

local function Check()
  stats.checks = stats.checks + 1
  local snap = Snapshot()
  if not snap then
    -- items still loading: look again (a few times)
    if tries < 5 then tries = tries + 1 ns.After(1, Check) end
    return
  end
  tries = 0
  if not base or Now() < quietUntil then base = snap return end
  local old = base
  base = snap
  local a, b = ns.FormatAverage(old.avg), ns.FormatAverage(snap.avg)
  if a == b or not ns.db.chatChange then return end
  local slots = SlotChanges(old.levels, snap.levels)
  if slots ~= "" then
    ns.Print(L["Item level %s -> %s (%s)"]:format(a, b, slots))
  else
    ns.Print(L["Item level %s -> %s"]:format(a, b))
  end
  stats.lines = stats.lines + 1
end

local function Changed()
  gen = gen + 1
  local mine = gen
  ns.After(DEBOUNCE, function() if mine == gen then Check() end end)
end

ns.On("PLAYER_EQUIPMENT_CHANGED", Changed)
ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", Changed)
ns.On("PLAYER_ENTERING_WORLD", function()
  -- login or loading screen: the next complete read is the new baseline, no line
  quietUntil = Now() + QUIET_AFTER_LOGIN
  base = nil
  Changed()
end)

-- (tests) the current baseline
function ns.ChangeBaseline() return base end
