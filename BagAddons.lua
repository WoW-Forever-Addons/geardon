local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) Bag addons: Baganator and Bagnon (both have Forever
-- versions). Their own extension points, no Blizzard frame is touched.
--
-- Baganator: its public API (Baganator.API).
--   RegisterCornerWidget(label, id, onUpdate, onInit, defaultPosition, isFast):
--     onInit(itemButton) returns the widget (our own font string on their
--     button), onUpdate(widget, details) gets details.itemLink (and
--     details.itemLocation) and returns true (shown), false (nothing to show)
--     or nil (data not there yet: Baganator asks again).
--   RegisterUpgradePlugin(label, id, callback(itemLink)): true / false / nil
--     (nil = not known yet); the user picks the plugin in Baganator's options.
--   RequestItemButtonsRefresh(reasons): redraw after a gear change.
--   Baganator's source could not be fetched when this was written (GitHub and
--   CurseForge were not reachable from the build machine). The names and the
--   true/false/nil rule come from addons that use the API (ItemTier,
--   SimpleItemLevel issue #44). So every call is feature-checked and
--   protected; /gd diag says what worked.
-- Bagnon: its item class (Bagnon.Item, older Bagnon.ItemSlot). After each of
--   its own updates (UpdateSecondary, the method Bagnon calls for plugins
--   after an item update; else Update) the button gets our number, arrow and
--   BoE mark. A post-hook on a method of a third-party addon's class, never
--   on Blizzard code.
---------------------------------------------------------------------------
local stats = { baganator = "not loaded", bagnon = "not loaded", baganatorUpdates = 0, bagnonUpdates = 0, refreshes = 0 }
ns.bagAddonStats = stats

local function On() return ns.db and ns.db.showBags and ns.db.bagAddons ~= false end

-- A usable item link from anything a bag addon hands over: a full link or a
-- partial one ("item:10515"); a bare item ID becomes "item:<id>".
local function LinkOf(v)
  if type(v) == "number" and ns.Usable(v) then return "item:" .. math.floor(v) end
  local s = ns.Str(v)
  if s and s:find("item:%d+") then return s end
  return nil
end
ns.BagLinkOf = LinkOf

---------------------------------------------------------------------------
-- Baganator
---------------------------------------------------------------------------
local pendingTries = {} -- link -> how often it was not loaded yet
local MAX_TRIES = 20

-- Our font string on Baganator's button: number in the "bags" look.
local function LevelInit(itemButton)
  local fs = itemButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  fs._geardon = true
  return fs
end

local function StyleText(fs, info)
  local _, size = ns.PlaceLook("bags")
  if fs._size ~= size then
    local path = fs:GetFont()
    if path then pcall(fs.SetFont, fs, path, size, "OUTLINE") end
    fs._size = size
  end
  local r, g, b = 1, 1, 1
  if ns.db.numberColor == "quality" then
    r, g, b = ns.QualityColor(info.quality)
    r, g, b = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
  elseif ns.db.numberColor == "gap" then
    local avg = ns.PlayerAverage()
    if avg and info.level > avg + 0.05 then
      local c = ns.Style.COLORS.good r, g, b = c[1], c[2], c[3]
    elseif avg and info.level < avg - (tonumber(ns.db.behindLevels) or 8) then
      local c = ns.Style.COLORS.warning r, g, b = c[1], c[2], c[3]
    end
  end
  fs:SetTextColor(r, g, b)
end

-- nil: not loaded yet (asked again by Baganator, at most MAX_TRIES times per link)
local function InfoFor(details)
  if type(details) ~= "table" then return false end
  local link = LinkOf(details.itemLink) or LinkOf(details.itemID)
  if not link then return false end
  local info = ns.ItemInfo(link)
  if info then pendingTries[link] = nil return info end
  local n = (pendingTries[link] or 0) + 1
  pendingTries[link] = n
  if n > MAX_TRIES then return false end
  return nil
end

local function LevelUpdate(fs, details)
  stats.baganatorUpdates = stats.baganatorUpdates + 1
  if not On() then return false end
  local info = InfoFor(details)
  if not info then return info end -- false or nil
  if not (ns.IsGear(info) and ns.QualityShown(info.quality)) then return false end
  fs:SetText(ns.FormatLevel(info.level))
  StyleText(fs, info)
  return true
end

local function BoEInit(itemButton)
  local fs = itemButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  local path = fs:GetFont()
  if path then pcall(fs.SetFont, fs, path, 9, "OUTLINE") end
  local c = ns.Style.COLORS.accent
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetText(L["BoE"])
  return fs
end

-- Bound or not: Baganator's item location (C_Item.IsBound), else its isBound field.
local function BoEUpdate(fs, details)
  if not (On() and ns.db.boeMarker) then return false end
  local info = InfoFor(details)
  if not info then return info end
  if info.bindType ~= 2 then return false end
  local loc = details.itemLocation
  if type(loc) == "table" and C_Item and type(C_Item.IsBound) == "function" then
    local bound = ns.Value(C_Item.IsBound, loc)
    if bound ~= nil then
      if bound then return false end
      fs:SetText(L["BoE"])
      return true
    end
  end
  if details.isBound == false then fs:SetText(L["BoE"]) return true end
  return false
end

-- Upgrade plugin: Baganator passes the item link (a table with itemLink is accepted too).
local function UpgradeCheck(arg)
  if not On() then return false end
  local link = LinkOf(type(arg) == "table" and arg.itemLink or arg)
  if not link then return false end
  local info = ns.ItemInfo(link)
  if not info then return nil end
  local up = ns.IsUpgrade(info)
  return up and true or false
end

local function Api()
  local b = rawget(_G, "Baganator")
  local api = type(b) == "table" and rawget(b, "API")
  return type(api) == "table" and api or nil
end

local function SetupBaganator()
  local api = Api()
  if not api then stats.baganator = "no API" return end
  local parts = {}
  if type(api.RegisterCornerWidget) == "function" then
    local ok1 = pcall(api.RegisterCornerWidget, L["Geardon: item level"], "geardon_item_level",
      ns.Guard("baganator:level", LevelUpdate), ns.Guard("baganator:init", LevelInit), { corner = "bottom_left", priority = 1 }, true)
    local ok2 = pcall(api.RegisterCornerWidget, L["Geardon: BoE"], "geardon_boe",
      ns.Guard("baganator:boe", BoEUpdate), ns.Guard("baganator:init", BoEInit), { corner = "top_right", priority = 2 }, true)
    parts[#parts + 1] = "corners " .. (ok1 and "ok" or "failed") .. "/" .. (ok2 and "ok" or "failed")
  else
    parts[#parts + 1] = "no corner widgets"
  end
  if type(api.RegisterUpgradePlugin) == "function" then
    local ok = pcall(api.RegisterUpgradePlugin, "Geardon", "geardon", ns.Guard("baganator:upgrade", UpgradeCheck))
    parts[#parts + 1] = "upgrade plugin " .. (ok and "ok" or "failed")
  else
    parts[#parts + 1] = "no upgrade plugins"
  end
  stats.baganator = table.concat(parts, ", ")
end

-- Redraw Baganator's buttons after a gear or option change (at most every half second).
local refreshQueued = false
local function RefreshBaganator()
  local api = Api()
  if not (api and type(api.RequestItemButtonsRefresh) == "function") then return end
  local consts = rawget(rawget(_G, "Baganator") or {}, "Constants")
  local reason = type(consts) == "table" and type(consts.RefreshReason) == "table" and consts.RefreshReason.ItemWidgets
  local ok = reason ~= nil and pcall(api.RequestItemButtonsRefresh, { reason })
  if not ok then ok = pcall(api.RequestItemButtonsRefresh) end
  if ok then stats.refreshes = stats.refreshes + 1 end
end

---------------------------------------------------------------------------
-- Bagnon
---------------------------------------------------------------------------
local bagnonButtons = setmetatable({}, { __mode = "k" })

local function BagnonLink(button)
  local info = rawget(button, "info")
  if type(info) == "table" then
    -- Bagnon's item info; without a link or item ID the slot is empty
    return LinkOf(rawget(info, "hyperlink")) or LinkOf(rawget(info, "link")) or LinkOf(rawget(info, "itemID"))
  end
  local link = LinkOf(ns.Method(button, "GetItem"))
  if link then return link end
  -- a slot of the bags you carry now (not a cached view of another character)
  if ns.Method(button, "IsCached") == true then return nil end
  local bag, slot = ns.Num(ns.Method(button, "GetBag")), ns.Num(ns.Method(button, "GetID"))
  if bag and slot then
    local get = (C_Container and C_Container.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
    return ns.Str(ns.Call(get, bag, slot))
  end
  return nil
end

local function UpdateBagnonButton(button)
  if type(button) ~= "table" then return end
  stats.bagnonUpdates = stats.bagnonUpdates + 1
  bagnonButtons[button] = true
  if not On() then ns.HideLevel(button) return end
  local link = BagnonLink(button)
  local bag, slot
  if link and ns.Method(button, "IsCached") ~= true then
    bag, slot = ns.Num(ns.Method(button, "GetBag")), ns.Num(ns.Method(button, "GetID"))
  end
  ns.ShowItemLevel(button, link, true, "bags", bag, slot)
end

local function SetupBagnon()
  local b = rawget(_G, "Bagnon")
  local class = type(b) == "table" and (rawget(b, "Item") or rawget(b, "ItemSlot"))
  if type(class) ~= "table" then stats.bagnon = "no item class" return end
  local method = type(class.UpdateSecondary) == "function" and "UpdateSecondary" or (type(class.Update) == "function" and "Update")
  if not method or type(hooksecurefunc) ~= "function" then stats.bagnon = "no update method" return end
  local ok = pcall(hooksecurefunc, class, method, ns.Guard("bagnon:item", UpdateBagnonButton))
  stats.bagnon = ok and ("after " .. method) or "failed"
end

-- Gear or options changed: Bagnon's shown buttons get their arrows again.
local function RefreshBagnon()
  for button in pairs(bagnonButtons) do
    if ns.Method(button, "IsVisible") == true then UpdateBagnonButton(button) end
  end
end

local function Refresh()
  refreshQueued = false
  RefreshBaganator()
  RefreshBagnon()
end

function ns.RefreshBagAddons()
  if refreshQueued then return end
  refreshQueued = true
  ns.After(0.5, Refresh)
end

ns.OnAddon("Baganator", SetupBaganator)
ns.OnAddon("Bagnon", SetupBagnon)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.RefreshBagAddons() end)
ns.On("PLAYER_LEVEL_UP", function() ns.RefreshBagAddons() end)
ns.On("SKILL_LINES_CHANGED", function() ns.RefreshBagAddons() end)
