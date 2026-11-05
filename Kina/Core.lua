-- Kina: core, saved data, events.
-- Separate addon from Kina Scout: own namespace, own SavedVariables (KinaDB),
-- own slash command (/kina), own frame names. Never writes another addon's data.
local ADDON, C = ...
C.name = "Kina"
C.version = "1.2.0" -- Public Kina
C.PUBLIC = true
-- Your bags: the backpack, 4 bags, and the reagent bag where the client has one
-- (cloth, meat and other reagents go there automatically).
function C.PlayerBags()
  local t = { 0, 1, 2, 3, 4 }
  local B = Enum and Enum.BagIndex
  if B and B.ReagentBag then t[#t + 1] = B.ReagentBag end
  return t
end
function C.BankBags()
  local B = Enum and Enum.BagIndex
  if B and B.BankBag_1 then
    local t = { B.Bank or -1 }
    for i = 1, 7 do if B["BankBag_" .. i] then t[#t + 1] = B["BankBag_" .. i] end end
    if B.Reagentbank then t[#t + 1] = B.Reagentbank end
    return t
  end
  return { -1, 5, 6, 7, 8, 9, 10 }
end
-- Is the mailbox / a vendor really open right now? (the open/close events can be
-- missed, e.g. walking away; a stuck flag filed looted coin as mail)
function C.MailIsOpen() if MailFrame and MailFrame.IsShown then return MailFrame:IsShown() and true or false end end
function C.MerchantIsOpen() if MerchantFrame and MerchantFrame.IsShown then return MerchantFrame:IsShown() and true or false end end
-- Admin view (the private build only): who used which consumables. Public builds show
-- the group total only, so nobody gets blamed for a potion.
function C.Admin() return not C.PUBLIC end
C.SCHEMA = 1

local floor = math.floor

------------------------------------------------------------------ text size
-- Kina's own copies of the game fonts, so the Text size slider can resize Kina's
-- text without touching the rest of the UI. C.Text() makes a font string that
-- uses them and follows the slider live.
C.fonts = {}
local texts = setmetatable({}, { __mode = "k" })
function C.TextScale()
  local s = C.settings and C.settings.textScale or 1
  return math.max(0.7, math.min(1.5, tonumber(s) or 1))
end
function C.Font(name)
  local k = C.fonts[name]
  if k then return k end
  local src = _G[name]
  if not (CreateFont and src and src.GetFont) then return name end
  local file, size, flags = src:GetFont()
  if not file then return name end
  k = CreateFont("Kina" .. name)
  k:CopyFontObject(src)
  k.kinaBase = { file, size, flags or "" }
  k:SetFont(file, size * C.TextScale(), flags or "")
  C.fonts[name] = k
  return k
end
function C.Text(parent, layer, name)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local obj = C.Font(name or "GameFontHighlightSmall")
  if type(obj) == "string" then obj = _G[obj] end
  if obj and fs.SetFontObject then fs:SetFontObject(obj) end
  texts[fs] = obj
  return fs
end
function C.ApplyTextScale(s)
  if s then C.settings.textScale = math.floor(s * 20 + 0.5) / 20 end
  local scale = C.TextScale()
  for _, k in pairs(C.fonts) do
    local b = k.kinaBase
    if b then k:SetFont(b[1], b[2] * scale, b[3]) end
  end
  -- re-apply so every Kina text picks up the new size at once
  for fs, obj in pairs(texts) do if fs.SetFontObject and obj then fs:SetFontObject(obj) end end
  if C.OnTextScale then C.OnTextScale(scale) end
end

------------------------------------------------------------------ utilities
function C.Print(msg)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cff4fc3f7Kina|r: " .. tostring(msg)) end
end

function C.Now() return (GetServerTime and GetServerTime()) or time() end

-- 123456 copper -> "12g 34s 56c" (short form drops zero parts)
function C.Money(cp)
  if type(cp) ~= "number" or cp ~= cp then return "?" end
  local neg = cp < 0; cp = floor(math.abs(cp) + 0.5)
  local g, s, c = floor(cp / 10000), floor(cp / 100) % 100, cp % 100
  local out
  if g > 0 then out = string.format("%dg %02ds", g, s)
  elseif s > 0 then out = string.format("%ds %02dc", s, c)
  else out = string.format("%dc", c) end
  return (neg and "-" or "") .. out
end

function C.Pct(x) return string.format("%.0f%%", (x or 0) * 100) end

function C.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

function C.NPCIDFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id), "npc" end
  if kind == "GameObject" then return tonumber(id), "object" end
  return nil
end

-- Version family: history survives weekly beta builds ("1.60.1/70425" -> "1.60").
function C.VersionFamily()
  local v = GetBuildInfo and select(1, GetBuildInfo()) or "0"
  local major, minor = tostring(v):match("^(%d+)%.(%d+)")
  return major and (major .. "." .. minor) or tostring(v)
end

function C.MarketKey()
  local realm = (GetRealmName and GetRealmName()) or "?"
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
  return realm .. "|" .. faction
end

------------------------------------------------------------------ saved data
local defaults = {
  schema = C.SCHEMA,
  settings = {
    ahCut = 0.05,            -- faction auction houses take 5%
    depositFloor = 100,      -- players report a 1s minimum posting charge
    vendorMargin = 0.10,     -- unlearned vendor prices count 10% lower
    killsPerHour = 60,       -- default until your own sessions measure it
    launchTime = 1793833200, -- Nov 4 2026 15:00 PST (23:00 UTC); /kina launch to change
    minDealProfit = 100,     -- hide deals under 1s
    hudShown = true,
    autoScan = true,         -- full AH scan when the auction house opens (15-min limit respected)
    farmSound = true,        -- start/stop fanfares on the farm widget
    farmPreset = 0,          -- farm timer in seconds (0 = no timer)
    widgetAlpha = 0.80,
    pos = {},                -- saved window positions
    picksPerHour = 120,      -- pick-only circuits: picks per hour for the estimate
    textScale = 1.15,        -- Kina text size (Settings > Window > Text size); 1.2.0: 115% by default
    tooltip = true,          -- vendor / AH / disenchant lines on item tooltips
    minROI = 0,              -- hide rows under this ROI % (0 = show all)
    worthOnly = false,       -- hide trades that don't pay for your time
  },
  markets = {},     -- [marketKey] = { family, scanTime, items = {[id]={...}}, history = {[id]={[day]={min,med,qty}}} }
  items = {},       -- [itemID] = { q, il, rl, cls, sub, eq, vend, name, bind }  (static item facts)
  vendor = {},      -- [itemID] = { p = copper each, t = time, c = client price then }
  noDE = {},        -- [itemID] = time learned (game refused to disenchant)
  loot = {},        -- [npcID] = { nm, lvl, type, kills, looted, coin, pp, ppCoin, items = {[id]=n}, skins, skinItems = {} }
  nodes = {},       -- [objectID] = { nm, n, items = {[id]=n} }
  sessions = {},    -- recent finished sessions (max 50)
  stock = {},       -- [itemID] = { buyUnder, sellAt, note, added }
  chars = {},       -- [name-realm] = { prof = {[name]=rank}, level, class }
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; fill(dst[k], v) else dst[k] = v end
    elseif type(v) == "table" and type(dst[k]) == "table" and k == "settings" then
      fill(dst[k], v)
    end
  end
end

function C.InitDB()
  -- Kina was called Kina Scout C: the old saved data (loaded by the small KinaScoutC
  -- stub that ships with Kina) moves over once, so nothing is lost in the rename.
  if type(KinaDB) ~= "table" or next(KinaDB) == nil then
    if type(KinaScoutCDB) == "table" and next(KinaScoutCDB) ~= nil then
      KinaDB = KinaScoutCDB
      C.migrated = true
    else
      KinaDB = KinaDB or {}
    end
  end
  -- damaged or very old saved data: drop whatever has the wrong shape (Schema.lua)
  if C.Sanitize then
    local n = C.Sanitize(KinaDB)
    if n and n > 0 then
      C.dataRepaired = n
      -- 1.2.0: keep what was dropped, for Claude
      KinaDB.repairs = type(KinaDB.repairs) == "table" and KinaDB.repairs or {}
      table.insert(KinaDB.repairs, 1, { t = (GetServerTime and GetServerTime()) or 0, v = C.version, n = n, paths = C.repairPaths or {} })
      while #KinaDB.repairs > 10 do table.remove(KinaDB.repairs) end
    end
  end
  fill(KinaDB, defaults)
  -- 1.2.0: Kina's text is 15% bigger by default; anyone still on the old 100% moves up once
  if KinaDB.settings and not KinaDB.settings.text115 then
    if KinaDB.settings.textScale == 1 then KinaDB.settings.textScale = 1.15 end
    KinaDB.settings.text115 = true
  end
  C.db = KinaDB
  C.settings = C.db.settings
  local key = C.MarketKey()
  local m = C.db.markets[key]
  if not m then m = { items = {}, history = {} }; C.db.markets[key] = m end
  m.items = m.items or {}; m.history = m.history or {}
  C.market = m
  C.charKey = ((UnitName and UnitName("player")) or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  C.db.chars[C.charKey] = C.db.chars[C.charKey] or { prof = {} }
  C.char = C.db.chars[C.charKey]
end

------------------------------------------------------------------ events
local frame = CreateFrame("Frame", "KinaEventFrame")
C.frame = frame
-- Record any blocked protected call so it can be diagnosed from saved data.
-- Works from the first moment the file loads (buffered until saved data exists).
local early = {}
local function blocked(event, addon, func)
  if addon ~= ADDON then return end
  local rec = { event = event, func = tostring(func), t = C.Now(), stage = C.stage or "?" }
  -- 1.2.0: what Kina was doing, to find the cause of an UNKNOWN() block
  if InCombatLockdown then rec.combat = InCombatLockdown() and true or false end
  if C.lastSend then rec.lastSend = C.lastSend.k; rec.sendAgo = (GetTime and GetTime() or 0) - C.lastSend.t end
  if C.lastAction then rec.lastAction = C.lastAction.what; rec.actAgo = (GetTime and GetTime() or 0) - C.lastAction.t end
  if not C.db then table.insert(early, rec); return end
  C.db.blocked = C.db.blocked or {}
  table.insert(C.db.blocked, 1, rec)
  while #C.db.blocked > 20 do table.remove(C.db.blocked) end
  C.Print("blocked call recorded: " .. rec.func .. " at " .. rec.stage .. " (please tell Claude)")
end
C.FlushBlocked = function() for _, r in ipairs(early) do C.db.blocked = C.db.blocked or {}; table.insert(C.db.blocked, 1, r) end; early = {} end
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
local handlers = {}

function C.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- INIT is internal; never ask the client to register a non-event
    if event ~= "ADDON_LOADED" and event ~= "INIT" then
      C.stage = "registering " .. event
      frame:RegisterEvent(event)
      C.stage = "loading"
    end
  end
  table.insert(handlers[event], fn)
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON then
      C.InitDB()
      C.FlushBlocked()
      C.ready = true
      C.stage = "running"
      -- say which version is running, so an outdated copy is obvious
      C.After(3, function()
        C.Print("version " .. C.version .. " loaded. /kina opens the window.")
        -- first time ever: one line on what Kina is for
        if C.PUBLIC and not C.settings.welcomed then
          C.settings.welcomed = C.Now()
          C.Print("|cffffd100Welcome!|r Press Start on the Kina widget when you farm. Group with other Kina users and everyone's widget shows the same totals, the split and who owes whom; pay with one click and your Kina level grows.")
        end
        if C.dataRepaired then C.Print("|cffff8040some of Kina's saved data was damaged and has been cleaned up (" .. C.dataRepaired .. " entries).|r") end
        if C.migrated then C.Print("your Kina Scout C data was moved over. You can delete the old KinaScoutC folder after this session.") end
      end)
      for _, fn in ipairs(handlers.INIT or {}) do
        local ok, err = pcall(fn)
        if not ok then C.Print("init error: " .. tostring(err)) end
      end
    end
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then blocked(event, ...); return end
  if not C.ready then return end
  local list = handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok then C.LogError(event, err) end
  end
end)
-- Errors are kept in the saved file (Kina.lua > errlog) so Claude can read them after a
-- test, and announced once per session.
local errSaid = false
function C.LogError(where, err)
  if not C.db then return end
  C.db.errlog = C.db.errlog or {}
  local key = tostring(where) .. ": " .. tostring(err)
  for _, e in ipairs(C.db.errlog) do
    if e.msg == key then e.n = (e.n or 1) + 1; e.last = C.Now(); return end
  end
  table.insert(C.db.errlog, 1, { msg = key, n = 1, first = C.Now(), last = C.Now(), v = C.version })
  while #C.db.errlog > 40 do table.remove(C.db.errlog) end
  if C.debug or not errSaid then
    errSaid = true
    C.Print("|cffff8040an error was logged|r (" .. tostring(where) .. "). Play on; send Claude your Kina.lua saved file after the test.")
  end
end


------------------------------------------------------------------ windows
-- Drag any Kina window by its title strip (or any empty part of it); the spot is
-- remembered per window. /kina reset puts every window back.
function C.SavePos(f, key)
  local point, _, rel, x, y = f:GetPoint(1)
  if point then C.settings.pos[key] = { point, rel, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

function C.RestorePos(f, key, ...)
  local p = C.settings.pos[key]
  f:ClearAllPoints()
  if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else f:SetPoint(...) end
end

-- handle: an extra region that also starts a drag (a title strip above child widgets)
function C.MakeDraggable(f, key, handle, onMoved)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  -- Kina saves window spots itself: keep the game's own layout cache out of it, or
  -- the two fight and the window snaps somewhere else
  if f.SetDontSavePosition then pcall(f.SetDontSavePosition, f, true) end
  local function start()
    if InCombatLockdown and InCombatLockdown() and f:IsProtected() then return end
    C.dragging = f
    f:StartMoving()
  end
  local function stop()
    f:StopMovingOrSizing()
    C.dragging = nil
    if C.refreshAfterDrag and C.Refresh then C.refreshAfterDrag = nil; C.Refresh() end
    if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
    -- re-anchor to UIParent so the saved spot is independent of other frames
    local l, b = f:GetLeft(), f:GetBottom()
    if l and b then f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b) end
    C.SavePos(f, key)
    if onMoved then onMoved(f) end
  end
  -- 1.2.0: with the iron look a window with a title band moves only by that band
  -- (grabbing anywhere else did nothing useful and felt broken)
  if handle and C.Skin and C.Skin.On() then
    f:RegisterForDrag(); f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
  else
    f:SetScript("OnDragStart", start); f:SetScript("OnDragStop", stop)
  end
  if handle then
    -- the title bar moves the window from the moment you press, no drag threshold
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then start() end end)
    handle:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" and C.dragging == f then stop() end end)
    handle:SetScript("OnHide", function() if C.dragging == f then stop() end end)
  end
end

-- Corner grip that scales a window (its contents keep their layout): drag the
-- bottom-right corner; the size is remembered. Used by the detail panel and widget.
-- A resize grip people notice: bigger, gold, with a soft backing and a tooltip.
function C.StyleGrip(grip, tip)
  if C.Skin and C.Skin.Grip(grip) then
    grip:HookScript("OnEnter", function(self) if GameTooltip then C.TipOwner(self); GameTooltip:AddLine(tip or "Drag to resize", 1, 1, 1, true); GameTooltip:Show() end end)
    grip:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return
  end
  grip:SetSize(26, 26)
  local bg = grip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(1, 0.82, 0, 0.18)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local n = grip.GetNormalTexture and grip:GetNormalTexture()
  if n and n.SetVertexColor then n:SetVertexColor(1, 0.85, 0.2) end
  grip:SetScript("OnEnter", function(self)
    bg:SetColorTexture(1, 0.82, 0, 0.4)
    if GameTooltip then C.TipOwner(self); GameTooltip:AddLine(tip or "Drag to resize", 1, 1, 1, true); GameTooltip:Show() end
  end)
  grip:SetScript("OnLeave", function() bg:SetColorTexture(1, 0.82, 0, 0.18); if GameTooltip then GameTooltip:Hide() end end)
end

-- Corner grip that scales a window (details panel, farm widget). The window's
-- top-left corner is pinned on screen when you press the grip, and the scale
-- follows how far you drag from that press point: no reading back positions the
-- game hasn't updated yet (that fed back on itself and made windows run away).
local SCALE_MIN, SCALE_MAX = 0.6, 1.5
function C.ScaleGrip(f, key)
  local saved = C.settings.pos[key]
  if type(saved) == "number" then f:SetScale(math.max(SCALE_MIN, math.min(SCALE_MAX, saved))) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetFrameLevel(f:GetFrameLevel() + 20)
  C.StyleGrip(grip, "Drag to make this window bigger or smaller.")
  grip:SetScript("OnMouseDown", function(self)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return end
    local eff = f:GetEffectiveScale()
    -- everything in screen pixels, taken once
    self.pinX, self.pinY = l * eff, t * eff
    self.startX = GetCursorPosition()
    self.startScale = f:GetScale()
    self.width = math.max(100, f:GetWidth()) * eff -- the window's width on screen at the press
    self:SetScript("OnUpdate", function(g)
      local cx = GetCursorPosition()
      local scale = g.startScale * (1 + (cx - g.startX) / g.width)
      scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
      if math.abs(scale - f:GetScale()) < 0.005 then return end
      f:SetScale(scale)
      local parentEff = (f:GetParent() or UIParent):GetEffectiveScale()
      local unit = parentEff * scale -- screen pixels per unit of this window
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.pinX / unit, g.pinY / unit)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    C.settings.pos[key] = math.floor(f:GetScale() * 100 + 0.5) / 100
  end)
  grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  return grip
end

-- Tooltips go where your UI puts tooltips (the default tooltip spot, which UI
-- addons can move), not beside whatever the mouse is over.
function C.TipOwner(owner)
  local tip = GameTooltip
  if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(tip, owner or UIParent)
  else tip:SetOwner(owner or UIParent, "ANCHOR_NONE"); tip:ClearAllPoints(); tip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -95, 110) end
  return tip
end

-- Small cooperative job runner so long work never stalls a frame.
local jobs = {}
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
  local job = jobs[1]
  if not job then self:Hide(); return end
  local ok, done = pcall(job)
  if not ok then
    if C.debug then C.Print("job error: " .. tostring(done)) end
    done = true
  end
  if done then table.remove(jobs, 1) end
end)
function C.Job(fn) table.insert(jobs, fn); runner:Show() end

function C.After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
