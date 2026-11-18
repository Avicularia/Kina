-- Kina: "Update available" (1.0.7, Taylor). Kinas say which version they run on the Kina
-- network (one tiny note at login). When a newer Kina is out, a green glowing "Update
-- available" button sits on the widget; with the widget hidden, a small window says so
-- instead (never in combat). Clicking either shows how to update.
-- A newer version is only believed from the developer, or from 3 different players running
-- it (one modified copy can't nag everyone).
-- WoW doesn't let an addon change its own files or start another program, so Kina can't
-- update itself: the window gives the CurseForge link and the two steps.
local _, C = ...
local U = {}
C.Update = U
U.URL = "https://www.curseforge.com/projects/1793386"
U.NEED_PLAYERS = 3

local function verNum(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
  return a and (tonumber(a) * 10000 + tonumber(b) * 100 + (tonumber(c) or 0)) or 0
end
U.VerNum = verNum
local seen = {}   -- [version] = { [player] = true }
U.newest = nil    -- the newest version believed
local function believe(v)
  if verNum(v) <= verNum(C.version) then return end
  if not U.newest or verNum(v) > verNum(U.newest) then
    U.newest = v
    U.shown = false
    if C.After then C.After(1, function() pcall(U.Notify) end) end
  end
end
function U.Heard(from, v)
  if type(v) ~= "string" or not v:match("^%d+%.%d+") then return end
  if verNum(v) <= verNum(C.version) then return end
  if C.Net and C.Net.IsDeveloper(from) then believe(v); return end
  seen[v] = seen[v] or {}
  seen[v][tostring(from):lower()] = true
  local n = 0
  for _ in pairs(seen[v]) do n = n + 1 end
  if n >= U.NEED_PLAYERS then believe(v) end
end
function U.Available() return U.newest ~= nil and verNum(U.newest) > verNum(C.version) end

------------------------------------------------------------------ the window
local win
local function build()
  win = CreateFrame("Frame", "KinaUpdateWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(420, 210); win:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  win:SetFrameStrata("FULLSCREEN_DIALOG"); win:SetFrameLevel(120); win:SetClampedToScreen(true); win:EnableMouse(true); win:SetMovable(true)
  win:RegisterForDrag("LeftButton"); win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  if C.Skin and C.Skin.On and C.Skin.On() and C.Skin.Frame then C.Skin.Frame(win, 20) elseif win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0.07, 0.055, 0.04, 0.97); win:SetBackdropBorderColor(0.3, 0.85, 0.4)
  end
  local logo = win:CreateTexture(nil, "ARTWORK"); logo:SetSize(40, 40); logo:SetPoint("TOPLEFT", 18, -16)
  logo:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); win.title:SetPoint("LEFT", logo, "RIGHT", 10, 6)
  win.sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -3)
  win.body = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); win.body:SetPoint("TOPLEFT", 20, -70); win.body:SetPoint("RIGHT", win, "RIGHT", -20, 0)
  win.body:SetJustifyH("LEFT"); if win.body.SetWordWrap then win.body:SetWordWrap(true) end
  win.body:SetText("Open the |cffffc54aCurseForge app|r and press |cffffc54aUpdate|r on Kina, then fully restart WoW.\nNo app? Copy the link (Ctrl+C) and download it there.")
  local eb = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
  eb:SetSize(300, 20); eb:SetPoint("BOTTOMLEFT", 26, 44); eb:SetAutoFocus(false)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnTextChanged", function(self) if self:GetText() ~= U.URL then self:SetText(U.URL); self:HighlightText() end end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  win.link = eb
  local ok = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(ok) end
  ok:SetSize(110, 24); ok:SetPoint("BOTTOMRIGHT", -16, 12); ok:SetText("Got it")
  ok:SetScript("OnClick", function() win:Hide() end)
  local copy = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(copy) end
  copy:SetSize(70, 22); copy:SetPoint("LEFT", eb, "RIGHT", 8, 0); copy:SetText("Select")
  copy:SetScript("OnClick", function() eb:SetFocus(); eb:HighlightText() end)
  local x = CreateFrame("Button", nil, win, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)
  tinsert(UISpecialFrames, "KinaUpdateWindow")
  win:Hide()
end
function U.Show()
  if not U.Available() then return false end
  if not win then build() end
  win.title:SetText("|cff3fd03fKina " .. U.newest .. " is out|r")
  win.sub:SetText("|cff9d9d9dYou have " .. tostring(C.version) .. "|r")
  win.link:SetText(U.URL)
  win:Show(); win:Raise()
  return true
end

------------------------------------------------------------------ the widget button
local btn
local function widgetButton()
  local w = rawget(_G, "KinaWidget")
  if not w then return nil end
  if btn then return btn end
  btn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(btn) end
  btn:SetSize(150, 22); btn:SetPoint("BOTTOM", w, "TOP", 0, 4)
  btn:SetText("|cff7CFC00Update available|r")
  local glow = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
  glow:SetPoint("TOPLEFT", -10, 8); glow:SetPoint("BOTTOMRIGHT", 10, -8)
  glow:SetTexture("Interface\\AddOns\\Kina\\Media\\Cos\\fx_round"); glow:SetBlendMode("ADD"); glow:SetVertexColor(0.3, 1, 0.4)
  btn.glow = glow
  btn:SetScript("OnClick", function() U.Show() end)
  btn:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Kina " .. tostring(U.newest) .. " is out")
    GameTooltip:AddLine("Click to see how to update.", 1, 1, 1); GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  btn:Hide()
  return btn
end
local pulse = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, el)
  if not (btn and btn:IsShown()) then return end
  pulse = pulse + el
  btn.glow:SetAlpha(0.35 + 0.35 * math.sin(pulse * 3))
end)
function U.Refresh()
  local b = widgetButton()
  if b then b:SetShown(U.Available()) end
end

------------------------------------------------------------------ telling the player
local function inCombat() return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) end
function U.Notify()
  if not U.Available() then return end
  U.Refresh()
  if U.shown then return end
  local w = rawget(_G, "KinaWidget")
  if w and w:IsShown() then U.shown = true; return end -- the button on the widget does it
  if inCombat() then U.waiting = true; return end
  U.shown = true
  U.Show()
end
C.On("PLAYER_REGEN_ENABLED", function() if U.waiting then U.waiting = nil; if C.After then C.After(2, function() pcall(U.Notify) end) end end end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() pcall(U.Refresh) end) end

------------------------------------------------------------------ hearing versions
-- every Kina says its version once when it logs in (one short note in the Kina room)
C.On("PLAYER_LOGIN", function()
  if C.After then C.After(20, function() if C.Net and C.Net.Broadcast then C.Net.Broadcast("V|" .. tostring(C.version)) end end) end
end)
if C.After then
  C.After(0, function()
    if not C.Net then return end
    C.Net.On("V", function(from, f) U.Heard(from, f[2]) end)
    C.Net.On("O", function(from, f) U.Heard(from, f[2]) end) -- the developer's "online" carries the version
  end)
end
