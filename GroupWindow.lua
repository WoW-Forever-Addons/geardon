local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Group window (Style kit): one row per member, highest item level first,
-- group average at the bottom. (1.2.0, Daniel 10.10.) Opens only by hand
-- (/gd group, the tool in the options), no longer by itself in a group or
-- raid; it stays open until closed. The group values are still collected
-- (Group.lua): the player tooltips use them.
---------------------------------------------------------------------------
local WIDTH = 230
local panel
local forced = false
local queued = false

local function Store()
  local db = ns.db
  if type(db.groupWin) ~= "table" then db.groupWin = {} end
  return db.groupWin
end

local function ClassColor(class)
  if not class then return nil end
  if C_ClassColor and C_ClassColor.GetClassColor then
    local c = ns.Call(C_ClassColor.GetClassColor, class)
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
  end
  local t = rawget(_G, "RAID_CLASS_COLORS")
  local c = type(t) == "table" and t[class]
  if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
  return nil
end

local function Ago(t)
  local s = math.max(0, (ns.Num(ns.Value(GetTime)) or 0) - (t or 0))
  if s < 60 then return L["just now"] end
  return L["%d min ago"]:format(math.floor(s / 60))
end

local function RowTooltip(m)
  return function()
    local lines = {}
    local weak, weakLevel = m.weak, m.weakLevel
    if m.src == "self" then
      local _, _, w = ns.Average(ns.Equipped())
      local e = w and ns.Equipped()[w]
      weak, weakLevel = w, e and e.level
    end
    if m.src == "addon" then
      lines[#lines + 1] = { L["Source"], L["sent by Geardon"] }
      lines[#lines + 1] = { L["Updated"], Ago(m.t) }
    elseif m.src == "inspect" then
      lines[#lines + 1] = { L["Source"], L["inspected"] }
      lines[#lines + 1] = { L["Updated"], Ago(m.t) }
    elseif m.src == "self" then
      lines[#lines + 1] = { L["Source"], L["your character"] }
    elseif m.waiting then
      lines[#lines + 1] = L["Being inspected right now."]
    else
      lines[#lines + 1] = L["Not known yet. Players are inspected out of combat when they are close enough to be seen."]
    end
    if m.level and weak and weakLevel then
      lines[#lines + 1] = { L["Weakest slot"], ("%s (%s)"):format(ns.SlotLabel(weak), ns.FormatLevel(weakLevel)), "warning" }
    end
    return m.name, lines, nil
  end
end

local function Build()
  local Style = ns.Style
  panel = Style.Panel("GeardonGroupPanel", UIParent, {
    title = Style.Wordmark("Gear", "don") .. "  " .. Style.Colorize(L["Group"], "textSecondary"),
    width = WIDTH,
    close = true,
    collapse = true,
    get = function(key) return Store()[key] end,
    set = function(key, value) Store()[key] = value end,
    defaultPoint = { "LEFT", "LEFT", 260, 120 },
    closeTooltip = { L["Hide window"], nil, L["/gd group shows it again."] },
    collapseTooltip = { L["Collapse / expand"], nil, nil },
    onClose = function() forced = false if panel then panel:FadeOut() end end,
    buttons = { { kind = "options", key = "options", tooltip = { L["Options"], nil, L["Opens the Geardon options."] },
      onClick = function() ns.OpenOptions() end } },
  })
  return panel
end

local function Fill()
  local Style = ns.Style
  panel:ClearRows()
  local list = ns.GroupLevels()
  table.sort(list, function(a, b)
    if (a.level ~= nil) ~= (b.level ~= nil) then return a.level ~= nil end
    if a.level and b.level and a.level ~= b.level then return a.level > b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  local sum, n = 0, 0
  for _, m in ipairs(list) do
    local row = Style.Row(panel)
    local value, color
    if m.level then
      value, color = ns.FormatAverage(m.level), "textPrimary"
      sum, n = sum + m.level, n + 1
    elseif m.waiting then
      value, color = L["inspecting"], "textHint"
    else
      value, color = "?", "textHint"
    end
    row:SetText(m.name, "textPrimary")
    local cc = ClassColor(m.class)
    if cc then row:SetTextColor(cc) end
    row:SetValue(value, color)
    row:SetActive(m.src == "self")
    row:SetTooltip(RowTooltip(m))
  end
  if n > 0 then
    local avg = Style.KeyValue(panel, L["Group average"], ns.FormatAverage(sum / n) ..
      (n < #list and (" |cff9ea3ad(" .. L["%d of %d"]:format(n, #list) .. ")|r") or ""), "accent")
    if avg then avg:SetGapBefore(Style.SPACING.section) end
  end
end

local function Wanted() return forced end

local function Update()
  queued = false
  local want = Wanted()
  if want and not panel then Build() end
  if not panel then return end
  if want then
    Fill()
    if not panel:IsShown() then panel:FadeIn() end
  elseif panel:IsShown() then
    panel:FadeOut()
  end
end

-- Many events at once (roster, received levels): one update per frame.
function ns.UpdateGroupWindow()
  if queued then return end
  queued = true
  ns.After(0.1, Update)
end

function ns.ToggleGroupWindow()
  if panel and panel:IsShown() then
    forced = false
    panel:FadeOut()
  else
    forced = true
    if (ns.Num(ns.Value(GetNumGroupMembers)) or 0) <= 1 then ns.Print(L["You are not in a group; the window shows only you."]) end
    Update()
  end
end

function ns.ResetGroupWindow()
  if panel then panel:ResetPosition() else Store().pos = nil end
end

ns.On("GROUP_LEFT", function() ns.UpdateGroupWindow() end)
ns.On("GROUP_JOINED", function() ns.UpdateGroupWindow() end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.UpdateGroupWindow() end)
ns.OnInit(function() ns.NewTicker(5, function() if panel and panel:IsShown() then ns.UpdateGroupWindow() end end) end)
