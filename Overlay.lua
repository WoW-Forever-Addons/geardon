local _, ns = ...

---------------------------------------------------------------------------
-- The item level number (and the green upgrade arrow) on an item button.
-- Each overlay is our own frame, a child of the button, with mouse off:
-- clicks, drag and tooltips stay Blizzard's. Nothing of the button itself is
-- changed, hooked or read beyond its size and frame level.
---------------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })
local stats = { created = 0, shown = 0, skipped = 0 }
ns.overlayStats = stats

local function SetArrow(tex)
  local ok, res = false, nil
  if tex.SetAtlas then ok, res = pcall(tex.SetAtlas, tex, "bags-greenarrow", false) end
  if not ok or res == false then
    tex:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
    tex:SetTexCoord(0, 1, 1, 0) -- the stream arrow points down; flipped up
  end
end

-- (1.2.0, Daniel 10.10.) Green arrow, or the same arrow in the warning colour
-- when the upgrade is not sure (other quality, a set bonus at stake).
local function ArrowLook(tex, check)
  if tex._check == check then return end
  tex._check = check
  if check then
    if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, true) end
    local w = ns.Style and ns.Style.COLORS and ns.Style.COLORS.warning or { 0.95, 0.75, 0.25 }
    if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, w[1], w[2], w[3]) end
  else
    if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, false) end
    if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, 1, 1, 1) end
  end
end

-- (1.2.0) Position and size per place: "character" (character frame, inspect
-- frame, equipment flyout), "bags" (bags, bank, bag addons; the old keys) and
-- "other" (loot, quest rewards, merchants).
local PLACE_KEYS = {
  character = { "numberPositionChar", "numberSizeChar" },
  bags = { "numberPosition", "numberSize" },
  other = { "numberPositionOther", "numberSizeOther" },
}
function ns.PlaceLook(place)
  local db = ns.db or ns.defaults
  local keys = PLACE_KEYS[place or "bags"] or PLACE_KEYS.bags
  local size = math.max(8, math.min(18, tonumber(db[keys[2]]) or 12))
  return db[keys[1]] or "BOTTOM", size
end

local function ApplyFont(o)
  local pos, size = ns.PlaceLook(o._place)
  if o._size ~= size then
    local path = o.text:GetFont()
    if not path then
      local base = rawget(_G, "NumberFontNormal")
      path = base and base.GetFont and base:GetFont()
    end
    if path then pcall(o.text.SetFont, o.text, path, size, "OUTLINE") end
    o._size = size
  end
  if o._pos ~= pos then
    o.text:ClearAllPoints()
    if pos == "TOP" then
      o.text:SetPoint("TOP", o, "TOP", 0, -2)
    elseif pos == "CENTER" then
      o.text:SetPoint("CENTER", o, "CENTER", 0, 0)
    else
      o.text:SetPoint("BOTTOM", o, "BOTTOM", 0, 2)
    end
    o._pos = pos
  end
end

local function Get(button)
  local o = overlays[button]
  if o then return o end
  o = CreateFrame("Frame", nil, button)
  -- wide buttons (quest rewards: icon left, name right): on the icon
  local icon = rawget(button, "Icon") or rawget(button, "icon")
  if type(icon) == "table" and icon.GetObjectType and button ~= icon and rawget(button, "objectType") ~= nil then
    o:SetAllPoints(icon)
  else
    o:SetAllPoints(button)
  end
  if o.EnableMouse then o:EnableMouse(false) end
  local level = ns.Num(ns.Method(button, "GetFrameLevel"))
  if level then o:SetFrameLevel(level + 4) end
  o.text = o:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  o.text:SetJustifyH("CENTER")
  o.arrow = o:CreateTexture(nil, "OVERLAY")
  o.arrow:SetSize(14, 14)
  o.arrow:SetPoint("TOPLEFT", o, "TOPLEFT", 1, -1)
  SetArrow(o.arrow)
  o.arrow:Hide()
  overlays[button] = o
  stats.created = stats.created + 1
  return o
end

-- (1.2.0) Small "BoE" in the top right corner, made when first needed.
local function SetBoE(o, on)
  if not on then
    if o.boe then o.boe:Hide() end
    return
  end
  if not o.boe then
    o.boe = o:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    local path = o.boe:GetFont()
    if path then pcall(o.boe.SetFont, o.boe, path, 9, "OUTLINE") end
    o.boe:SetPoint("TOPRIGHT", o, "TOPRIGHT", -1, -2)
    local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS.accent or { 0.25, 0.66, 0.96 }
    o.boe:SetTextColor(c[1], c[2], c[3])
  end
  o.boe:SetText(ns.L["BoE"])
  o.boe:Show()
end

local function Rgb(key, fallback)
  local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS[key]
  if c then return c[1], c[2], c[3] end
  return fallback[1], fallback[2], fallback[3]
end

-- (1.2.0) Colour by the gap to your average: above it good (green), down to
-- "behind" levels below it white, further below in the warning colour.
local function GapColor(level)
  local avg = ns.PlayerAverage()
  if not (avg and level) then return 1, 1, 1 end
  local gap = level - avg
  if gap > 0.05 then return Rgb("good", { 0.4, 0.8, 0.45 }) end
  local behind = tonumber(ns.db and ns.db.behindLevels) or 8
  if gap < -behind then return Rgb("warning", { 0.95, 0.75, 0.25 }) end
  return 1, 1, 1
end

-- opts: upgrade (arrow), check (yellow arrow), weak (warning colour), behind
-- (critical colour), place ("character", "bags", "other"), boe (BoE mark).
-- level may be nil when only the BoE mark is shown.
function ns.ShowLevel(button, level, quality, opts)
  level = ns.Num(level)
  local boe = opts and opts.boe
  if type(button) ~= "table" or not (level or boe) then return ns.HideLevel(button) end
  local o = Get(button)
  local place = opts and opts.place or "bags"
  if o._place ~= place then o._place, o._size, o._pos = place, nil, nil end
  ApplyFont(o)
  o.text:SetText(level and ns.FormatLevel(level) or "")
  local r, g, b = 1, 1, 1
  if opts and opts.behind then
    r, g, b = Rgb("critical", { 0.92, 0.35, 0.32 })
  elseif opts and opts.weak then
    local w = ns.Style and ns.Style.COLORS and ns.Style.COLORS.warning
    if w then r, g, b = w[1], w[2], w[3] end
  elseif ns.db and ns.db.numberColor == "gap" then
    r, g, b = GapColor(level)
  elseif ns.db and ns.db.numberColor == "quality" then
    -- a bit lighter than the border: blue on a blue (rare) border is hard to read
    r, g, b = ns.QualityColor(quality)
    r, g, b = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
  end
  o.text:SetTextColor(r, g, b)
  local arrow = level and opts and opts.upgrade and ns.db and ns.db.upgradeArrow and true or false
  if arrow then ArrowLook(o.arrow, opts.check and true or false) end
  o.arrow:SetShown(arrow)
  SetBoE(o, boe and true or false)
  if not o:IsShown() then o:Show() end
  o._on = true
end

function ns.HideLevel(button)
  local o = type(button) == "table" and overlays[button]
  if o then
    o._link = nil
    if o._on then
      o:Hide()
      o._on = nil
    end
  end
end

-- (1.2.0) Filter "only Uncommon and above" for the numbers on icons.
function ns.QualityShown(quality)
  if ns.db and ns.db.minQualityUncommon then return (ns.Num(quality) or 1) >= 2 end
  return true
end

-- Shows the number for an item link on a button (bags, bank, loot, rewards).
-- Returns true when a number is shown, "pending" while the item loads.
-- Unchanged item and version: nothing to do (bags are polled every second).
-- (1.2.0) place: see ns.ShowLevel; bag, slot: where the item is (BoE mark).
local opts = {} -- reused: ShowLevel does not keep it
function ns.ShowItemLevel(button, link, arrow, place, bag, slot)
  if not link then ns.HideLevel(button) return false end
  local o = overlays[button]
  if o and o._link == link and o._ver == ns.version and o._arrowWanted == arrow and o._bag == bag and o._slot == slot then
    stats.skipped = stats.skipped + 1
    return o._result
  end
  local info = ns.ItemInfo(link)
  if not info then ns.HideLevel(button) return "pending" end
  local result = false
  local boe = bag and slot and ns.db and ns.db.boeMarker and ns.IsBoE and ns.IsBoE(info, bag, slot) or false
  if ns.IsGear(info) and ns.QualityShown(info.quality) then
    local up, check = false, false
    if arrow then up, check = ns.IsUpgrade(info) end
    opts.upgrade, opts.check, opts.place, opts.boe = up, check, place, boe
    ns.ShowLevel(button, info.level, info.quality, opts)
    stats.shown = stats.shown + 1
    result = true
  elseif boe then
    opts.upgrade, opts.check, opts.place, opts.boe = false, false, place, true
    ns.ShowLevel(button, nil, info.quality, opts)
  else
    ns.HideLevel(button)
  end
  o = overlays[button]
  if o then o._link, o._ver, o._arrowWanted, o._result, o._bag, o._slot = link, ns.version, arrow, result, bag, slot end
  return result
end

-- Font, size and position changed in the options.
function ns.RestyleOverlays()
  ns.BumpVersion()
  for _, o in pairs(overlays) do
    o._size, o._pos = nil, nil
    if o._on then ApplyFont(o) end
  end
end

function ns.CountOverlays()
  local n, on = 0, 0
  for _, o in pairs(overlays) do
    n = n + 1
    if o._on then on = on + 1 end
  end
  return n, on
end

---------------------------------------------------------------------------
-- Watching a Blizzard frame without touching it: a hidden helper frame of
-- ours is a child of it, so its OnShow and OnHide follow the Blizzard frame.
-- While shown, fn runs at once, after events (ns.Dirty) and every `poll`
-- seconds (buttons that Blizzard reuses for other items).
---------------------------------------------------------------------------
local watchers = {}

function ns.Watch(key, parent, fn, poll)
  if watchers[key] or type(parent) ~= "table" then return watchers[key] end
  local w = CreateFrame("Frame", nil, parent)
  w:SetSize(1, 1)
  w:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  if w.EnableMouse then w:EnableMouse(false) end
  w.key, w.fn, w.poll, w.elapsed = key, ns.Guard("watch:" .. key, fn), poll or 1, 0
  w:SetScript("OnShow", function(self) self.dirty = true end)
  w:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.dirty and self.elapsed >= 0.05 or self.elapsed >= self.poll then
      self.dirty, self.elapsed = false, 0
      self.fn()
    end
  end)
  w.dirty = true
  watchers[key] = w
  return w
end

-- Run a watcher on its next frame (if its Blizzard frame is shown).
function ns.Dirty(key)
  if key then
    local w = watchers[key]
    if w then w.dirty = true end
    return
  end
  for _, w in pairs(watchers) do w.dirty = true end
end

function ns.Watchers() return watchers end

---------------------------------------------------------------------------
-- Average display: text only, in Blizzard's own look ("Item level" in the
-- gold label font, the value larger in white, a note in grey). Own frame,
-- mouse off. twoLine: label above the value (narrow places, e.g. right of
-- the ammo slot).
---------------------------------------------------------------------------
function ns.Plate(parent, height, twoLine)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(160, height or (twoLine and 34 or 20))
  f.twoLine = twoLine
  if f.EnableMouse then f:EnableMouse(false) end
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.note:SetTextColor(0.62, 0.64, 0.68)
  f.note:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 5, 1)
  for _, fs in ipairs({ f.label, f.text, f.note }) do
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
  end
  if twoLine then
    -- both lines centred; the value line is moved by SetPlate
    f.label:SetPoint("TOP", f, "TOP", 0, 0)
    f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  else
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
  end
  return f
end

-- Width follows the text (label, value and an optional grey note).
function ns.SetPlate(f, avg, note, label)
  f.label:SetText(label or ns.L["Item level"])
  f.text:SetText(ns.FormatAverage(avg))
  f.note:SetText(note or "")
  local lw = ns.Num(ns.Method(f.label, "GetStringWidth")) or 60
  local tw = ns.Num(ns.Method(f.text, "GetStringWidth")) or 40
  if note then tw = tw + 5 + (ns.Num(ns.Method(f.note, "GetStringWidth")) or 40) end
  if f.twoLine then
    local w = math.max(lw, tw)
    f:SetWidth(math.floor(w + 0.5))
    f.text:ClearAllPoints()
    f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", math.floor((w - tw) / 2 + 0.5), 0)
  else
    f:SetWidth(math.floor(lw + 6 + tw + 0.5))
  end
end
