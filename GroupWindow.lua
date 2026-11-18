local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Group window (Style kit): one row per member, highest item level first,
-- group average at the bottom. (1.2.0, Daniel 10.10.) Opens only by hand
-- (/gd group, the tool in the options), no longer by itself in a group or
-- raid; it stays open until closed. The group values are still collected
-- (Group.lua): the player tooltips use them.
-- (02.11.2026, StyleKit 2 step 4, docs/layout_2026-11-02/geardon/, Daniel: "Freigeben wie gezeigt") the Don look like
-- Questdon's list: per member a Don row with a colour mark (gold you, green known, blue being inspected, grey unknown),
-- the class symbol, the name in its class colour (DonCore's Kit.ClassColor), a second line with source and age and the
-- average on the right; the group average in the foot. From 6 members (a raid) one-line rows of 22 px, the raid groups
-- as a line with their average (Daniel: "einzeilig ab 6"). Every text one line, cut with the whole text in the tooltip.
---------------------------------------------------------------------------
local WIDTH = 260
local COMPACT_FROM = 6
local LOGO = "Interface\\Icons\\INV_Chest_Plate06"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local panel
local forced = false
local queued = false

local function Store()
  local db = ns.db
  if type(db.groupWin) ~= "table" then db.groupWin = {} end
  return db.groupWin
end

local function Kit() return LibStub("DonCore-1.0"):Get("Kit", 4) end

-- colour marks (Kit.C, the same values in Style's Don look)
local function Mark(key)
  local K = Kit()
  local c = K and K.C[key]
  return c and { c[1], c[2], c[3] } or nil
end

local function ClassColor(class)
  local K = Kit()
  local c = class and K and K.ClassColor and K.ClassColor(class)
  return type(c) == "table" and c[1] and { c[1], c[2], c[3] } or nil
end

local function ClassIcon(row, class)
  local K = Kit()
  local tc = class and K and K.ClassCoords and K.ClassCoords(class)
  if type(tc) == "table" and tc[1] then row:SetIcon(CLASS_ICONS, false, tc) else row:SetIcon(nil) end
end

local function Ago(t)
  local s = math.max(0, (ns.Num(ns.Value(GetTime)) or 0) - (t or 0))
  if s < 60 then return L["just now"] end
  return L["%d min ago"]:format(math.floor(s / 60))
end

-- the second line of a member: where the value comes from and how old it is
local function SubLine(m)
  if m.src == "self" then
    local _, _, w = ns.Average(ns.Equipped())
    local e = w and ns.Equipped()[w]
    -- your own row is marked gold already: its second line names the weakest slot
    if w and e and e.level then return L["Weakest slot: %s (%s)"]:format(ns.SlotLabel(w), ns.FormatLevel(e.level)) end
    return L["your character"]
  elseif m.src == "addon" then return "Geardon · " .. Ago(m.t)
  elseif m.src == "inspect" then return L["inspected"] .. " · " .. Ago(m.t)
  elseif m.waiting then return L["inspecting"], "blue"
  end
  return L["not known yet"]
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
  local Style, K = ns.Style, Kit()
  local word = K and K.Upper and K.Upper(L["Group"]) or L["Group"]
  panel = Style.Panel("GeardonGroupPanel", UIParent, {
    look = "don", logo = LOGO,
    title = "GEARDON  " .. (K and K.C.txGold.hex and ("|c" .. K.C.txGold.hex .. word .. "|r") or Style.Colorize(word, "accent")),
    width = WIDTH,
    close = true,
    collapse = true,
    get = function(key) return Store()[key] end,
    set = function(key, value) Store()[key] = value end,
    defaultPoint = { "LEFT", "LEFT", 260, 120 },
    closeTooltip = { L["Hide window"], nil, L["/gd group shows it again."] },
    collapseTooltip = { L["Collapse / expand"], nil, nil },
    onClose = function() forced = false if panel then panel:FadeOut() end end,
    -- (01.11.2026) the cog of every Don addon: Style.Panel takes symbol, click and tooltip from DonCore's Options
    buttons = { { key = "options", donOptions = "Geardon", hint = "/gd", onClick = function() ns.OpenOptions() end } },
  })
  ns.ApplyGroupLook()
  return panel
end

-- (16.11.2026, Blizzard look, Daniel: "Sollte Standart sein") with the option blizzLook the small window in the game's
-- look: Style's game look on a box with the game's tooltip border (DonCore Blizz PanelLook). Switched live with the option.
function ns.ApplyGroupLook()
  if not panel then return end
  local _, blizz, Bz = ns.LookKit()
  if blizz and Bz and Bz.PanelLook then
    Bz.PanelLook(panel, true)
  elseif panel.blizzLook then
    local B = LibStub("DonCore-1.0"):Get("Blizz", 3)
    if B then B.PanelLook(panel, false) end
  end
end
-- "blizzard", "kit" or "not built" (diag)
function ns.GroupLook()
  if not panel then return "not built" end
  return panel.blizzLook and "blizzard" or "kit"
end

-- the raid group (1 to 8) of a raid unit, nil outside a raid
local function Subgroup(unit)
  local i = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$"))
  if not i then return nil end
  local _, _, sub = ns.Results(rawget(_G, "GetRaidRosterInfo"), i)
  return ns.Num(sub)
end

local function Sorted(list)
  table.sort(list, function(a, b)
    if (a.level ~= nil) ~= (b.level ~= nil) then return a.level ~= nil end
    if a.level and b.level and a.level ~= b.level then return a.level > b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end

local function Average(list)
  local sum, n = 0, 0
  for _, m in ipairs(list) do if m.level then sum, n = sum + m.level, n + 1 end end
  return n > 0 and sum / n or nil, n
end

local function AddMember(m, compact)
  local Style = ns.Style
  local row = Style.Row(panel)
  local value, color
  if m.level then
    value, color = ns.FormatAverage(m.level), Mark("txGold") or "accent"
  elseif m.waiting then
    value, color = "…", Mark("blue") or "textHint"
  else
    value, color = "?", Mark("quiet") or "textHint"
  end
  row:SetText(m.name, "textPrimary")
  local cc = ClassColor(m.class)
  if cc then row:SetTextColor(cc) end
  row:SetValue(value, color)
  ClassIcon(row, m.class)
  local mark = m.src == "self" and "goldBright" or m.level and "green" or m.waiting and "blue" or "grey"
  row:SetMark(Mark(mark))
  if compact then
    row:SetSub(nil)
  else
    local sub, subColor = SubLine(m)
    row:SetSub(sub, subColor and Mark(subColor))
  end
  row:SetActive(m.src == "self")
  row:SetTooltip(RowTooltip(m))
end

local function Fill()
  local Style = ns.Style
  panel:ClearRows()
  local list = ns.GroupLevels()
  local compact = #list >= COMPACT_FROM
  -- a raid: its groups in order, each with its average; without the raid's roster one list
  local groups, order = {}, {}
  if compact then
    for _, m in ipairs(list) do
      local g = Subgroup(m.unit)
      if g then
        if not groups[g] then groups[g] = {} order[#order + 1] = g end
        table.insert(groups[g], m)
      end
    end
    table.sort(order)
  end
  if #order > 1 then
    local fmt = type(rawget(_G, "GROUP_NUMBER")) == "string" and _G.GROUP_NUMBER or "Group %d"
    for _, g in ipairs(order) do
      local avg = Average(groups[g])
      local hdr = Style.KeyValue(panel, fmt:format(g), avg and ns.FormatAverage(avg) or "")
      if hdr then hdr:SetMark(Mark("goldMuted")) end
      for _, m in ipairs(Sorted(groups[g])) do AddMember(m, true) end
    end
  else
    for _, m in ipairs(Sorted(list)) do AddMember(m, compact) end
  end
  local avg, n = Average(list)
  if avg then
    local row = Style.KeyValue(panel, L["Group average"] .. (n < #list and (" · " .. L["%d of %d"]:format(n, #list)) or ""),
      ns.FormatAverage(avg), Mark("txGold") or "accent")
    if row then row:SetGapBefore(Style.SPACING.section) end
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
