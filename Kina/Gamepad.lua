-- Kina: controller support (1.0.6, Taylor: "make sure the addon is controller compatible").
-- WoW Forever's gamepad UI moves a focus glow with the D-pad, but only through the game's
-- own windows. This gives Kina's windows the same:
--   D-pad      move between buttons (lists and long pages scroll to follow)
--   A          press        B   back / close        X   show the info a mouse-over shows
--   Y          the right-click action                LB / RB   previous / next tab
--   D-pad left / right on a slider changes it.
-- It only takes the controller while a Kina window is open and you're out of combat;
-- otherwise every button goes to the game as usual. Plus key bindings (Options > Key
-- Bindings > Kina) for opening Kina, Start/Stop farm, Scan AH, Hot Farms and a waypoint
-- to the nearest hot mob, so they can go on controller buttons.
local _, C = ...
local P = {}
C.Pad = P
local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() or false end

------------------------------------------------------------------ bindings
BINDING_HEADER_KINA = "Kina"
BINDING_NAME_KINA_TOGGLE = "Open / close Kina"
BINDING_NAME_KINA_FARM = "Start / stop farm"
BINDING_NAME_KINA_SCAN = "Scan the auction house"
BINDING_NAME_KINA_HOTFARMS = "Open Hot Farms"
BINDING_NAME_KINA_HOTWAY = "Waypoint to the nearest hot mob"
function P.Bind(what)
  if what == "toggle" then C.Toggle()
  elseif what == "farm" then if C.session then C.StopSession() else C.StartSession() end; if C.Refresh then C.Refresh() end
  elseif what == "scan" then if C.StartScanLoop then C.StartScanLoop() end
  elseif what == "hotfarms" then C.Toggle("Hot Farms")
  elseif what == "hotway" then
    local n = C.HotNudge and C.HotNudge.Nearest()
    local npc = n and n.row.npc
    if not npc and C.Hot then local top = C.Hot.Farms(4)[1]; npc = top and top.npc end
    if npc then C.Hot.Waypoint(npc) else C.Print("no hot mob near your level yet.") end
  end
end
function KinaBindings_Run(what) local ok, err = pcall(P.Bind, what); if not ok and C.LogError then C.LogError("binding", err) end end

------------------------------------------------------------------ is a controller in use?
function P.Active()
  if C.settings and C.settings.padOff then return false end
  if C_GamePad and C_GamePad.IsEnabled then
    local ok, on = pcall(C_GamePad.IsEnabled)
    if ok and on then return true end
  end
  if GetCVarBool then local ok, on = pcall(GetCVarBool, "GamePadEnable"); if ok and on then return true end end
  return P.forced or false -- (tests)
end

-- /kina pad: what this game client offers (for checking controller support in game)
function P.Report()
  local f = rawget(_G, "KinaPadCatcher")
  local function yn(b) return b and "|cff3fd03fyes|r" or "|cffff5050no|r" end
  C.Print("controller check:")
  C.Print("  gamepad mode on: " .. yn(P.Active()))
  C.Print("  game lets windows take the controller: " .. yn(f and f.EnableGamePadButton ~= nil))
  C.Print("  Kina's controller part: " .. ((C.settings and C.settings.padOff) and "off in Settings" or "on"))
  C.Print("  Kina window open now: " .. yn(P.Window() ~= nil))
end

------------------------------------------------------------------ which window
-- Kina's windows, topmost first (dialogs over pages over the main window)
local WINDOWS = { "KinaUpdateWindow", "KinaFeedbackPop", "KinaDialog1", "KinaDialog2", "KinaDialog3", "KinaDialog4", "KinaTourCard", "KinaWhatsNew", "KinaWelcomePick",
  "KinaCommend", "KinaSettle", "KinaPriceHold", "KinaRules", "KinaGuideFlyout", "KinaRecordPanel", "KinaProfile",
  "KinaMenu", "KinaHotOptions", "KinaDetail" }
function P.Window()
  for _, n in ipairs(WINDOWS) do
    local f = rawget(_G, n)
    if f and f.IsShown and f:IsShown() then return f end
  end
  local u = C.ui
  if u and u.frame and u.frame:IsShown() then return u.frame end
  return nil
end

------------------------------------------------------------------ what can be focused
local function usable(f)
  if not (f and f.IsVisible and f:IsVisible()) then return false end
  local t = f.GetObjectType and f:GetObjectType()
  if t ~= "Button" and t ~= "CheckButton" and t ~= "Slider" then return false end
  if f.IsEnabled and not f:IsEnabled() then return false end
  if f.IsMouseEnabled and not f:IsMouseEnabled() then return false end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  if w < 4 or h < 4 then return false end
  local al = (f.GetEffectiveAlpha and f:GetEffectiveAlpha()) or (f.GetAlpha and f:GetAlpha()) or 1
  if al < 0.05 then return false end
  return true
end
local function walk(f, out, depth)
  if depth > 14 or not (f and f.IsShown and f:IsShown()) then return end
  if f ~= out.root and usable(f) then out[#out + 1] = f end
  if f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do walk(c, out, depth + 1) end
  end
end
-- the ScrollFrame a frame sits in, if any
local function scrollParent(f)
  local p = f.GetParent and f:GetParent()
  local n = 0
  while p and p ~= UIParent and n < 30 do
    if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then return p end
    local q = p.GetParent and p:GetParent()
    if q == p then break end
    p, n = q, n + 1
  end
end
-- is it on screen inside its window (a ScrollFrame's hidden part counts: it scrolls to it)
local function inView(f, win)
  local l, b, w, h = f:GetRect()
  if not l then return false end
  if scrollParent(f) then return true end
  local wl, wb, ww, wh = win:GetRect()
  if not wl then return true end
  local cx, cy = l + w / 2, b + h / 2
  return cx >= wl and cx <= wl + ww and cy >= wb and cy <= wb + wh
end
function P.Collect(win)
  local out = { root = win }
  walk(win, out, 0)
  local res = {}
  for _, f in ipairs(out) do if inView(f, win) then res[#res + 1] = f end end
  return res
end

------------------------------------------------------------------ moving
-- the best frame from `cur` in direction dx, dy (screen up is +y); pure, for tests
function P.Pick(rects, cur, dx, dy)
  local c = rects[cur]
  if not c then return nil end
  local cx, cy = c.x + c.w / 2, c.y + c.h / 2
  local best, bs
  for k, r in pairs(rects) do
    if k ~= cur then
      local rx, ry = r.x + r.w / 2, r.y + r.h / 2
      local vx, vy = rx - cx, ry - cy
      local along = vx * dx + vy * dy        -- how far in the wanted direction
      if along > 2 then
        local across = math.abs(vx * dy - vy * dx) -- how far off to the side
        local s = along + across * 2.5
        if not bs or s < bs then best, bs = k, s end
      end
    end
  end
  return best
end

local focus, list, win
local glow
local function showGlow(f)
  if not glow then
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("TOOLTIP")
    local function edge(a, b, horiz)
      local t = glow:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(1, 0.78, 0.25, 0.95)
      t:SetPoint(a); t:SetPoint(b)
      if horiz then t:SetHeight(2) else t:SetWidth(2) end
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true); edge("TOPLEFT", "BOTTOMLEFT"); edge("TOPRIGHT", "BOTTOMRIGHT")
    local fill = glow:CreateTexture(nil, "ARTWORK"); fill:SetAllPoints(); fill:SetColorTexture(1, 0.75, 0.25, 0.10)
  end
  if not f then glow:Hide(); return end
  glow:ClearAllPoints(); glow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3); glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
  glow:Show()
end
local function leave(f) if f then local s = f.GetScript and f:GetScript("OnLeave"); if s then pcall(s, f) end end end
-- bring a frame inside a scrolling page into view
local function reveal(f)
  local sf = scrollParent(f)
  if not (sf and sf.GetVerticalScroll) then return end
  local top, bottom = sf:GetTop(), sf:GetBottom()
  local ft, fb = f:GetTop(), f:GetBottom()
  if not (top and bottom and ft and fb) then return end
  local cur, max = sf:GetVerticalScroll() or 0, (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
  if ft > top then sf:SetVerticalScroll(math.max(0, cur - (ft - top) - 8))
  elseif fb < bottom then sf:SetVerticalScroll(math.min(max, cur + (bottom - fb) + 8)) end
end
function P.Focus(f)
  if f == focus then return end
  leave(focus)
  focus = f
  if f then reveal(f) end
  showGlow(f)
end
local function rectsOf(fs)
  local r = {}
  for i, f in ipairs(fs) do
    local l, b, w, h = f:GetRect()
    if l then r[i] = { x = l, y = b, w = w, h = h } end
  end
  return r
end
local function indexOf(fs, f) for i, x in ipairs(fs) do if x == f then return i end end end
-- the Kina list's scrollbar, when moving past the last row
local function scrollList(dir)
  local u = C.ui
  local sb = u and u.scroll
  if not (sb and sb.IsShown and sb:IsShown() and u.frame and win == u.frame) then return false end
  local before = u.offset or 0
  local _, hi = sb:GetMinMaxValues()
  local v = math.max(0, math.min(hi or 0, before + dir * 3))
  if v == before then return false end
  sb:SetValue(v)
  if C.Refresh then C.Refresh() end
  return true
end
function P.Move(dx, dy)
  win = P.Window()
  if not win then return end
  list = P.Collect(win)
  if #list == 0 then P.Focus(nil); return end
  local i = indexOf(list, focus)
  if not i then P.Focus(list[1]); return end
  -- sliders: left / right change the value
  if focus:GetObjectType() == "Slider" and dx ~= 0 then
    local lo, hi = focus:GetMinMaxValues()
    local step = (focus.GetValueStep and focus:GetValueStep()) or 0
    if step <= 0 then step = ((hi or 1) - (lo or 0)) / 20 end
    focus:SetValue(math.max(lo or 0, math.min(hi or 1, (focus:GetValue() or 0) + dx * step)))
    return
  end
  local j = P.Pick(rectsOf(list), i, dx, dy)
  if j then P.Focus(list[j]); return end
  -- nothing further that way: scroll the list and try again
  if dy ~= 0 and scrollList(dy < 0 and 1 or -1) then
    list = P.Collect(win)
    local k = P.Pick(rectsOf(list), indexOf(list, focus) or 1, dx, dy)
    if k then P.Focus(list[k]) end
  end
end
local function press(btn)
  if not (focus and focus:IsVisible()) then return end
  if focus:GetObjectType() == "Slider" then return end
  if focus.Click then focus:Click(btn) end
  -- the press can rebuild the window: keep a valid focus
  if C.After then C.After(0.05, function() if focus and not focus:IsVisible() then P.Focus(nil) end end) end
end
function P.Info()
  if not focus then return end
  local s = focus.GetScript and focus:GetScript("OnEnter")
  if s then pcall(s, focus) end
end
function P.Back()
  local w = P.Window()
  if not w then return end
  P.Focus(nil)
  local u = C.ui
  if u and w == u.frame then C.Toggle() else w:Hide() end
end
function P.Tab(step)
  local u = C.ui
  if not (u and u.frame and u.frame:IsShown() and C.TabOrder) then return end
  local order = C.TabOrder()
  local i = 1
  for k, t in ipairs(order) do if t == u.tab then i = k end end
  i = ((i - 1 + step) % #order) + 1
  P.Focus(nil)
  C.Toggle(order[i])
end

------------------------------------------------------------------ input
-- a frame that takes the controller only while a Kina window is open (out of combat)
local catcher = CreateFrame("Frame", "KinaPadCatcher", UIParent)
catcher:Hide()
local HANDLED = { PADDUP = 1, PADDDOWN = 1, PADDLEFT = 1, PADDRIGHT = 1, PAD1 = 1, PAD2 = 1, PAD3 = 1, PAD4 = 1, PADLSHOULDER = 1, PADRSHOULDER = 1 }
function P.Button(b)
  if b == "PADDUP" then P.Move(0, 1)
  elseif b == "PADDDOWN" then P.Move(0, -1)
  elseif b == "PADDLEFT" then P.Move(-1, 0)
  elseif b == "PADDRIGHT" then P.Move(1, 0)
  elseif b == "PAD1" then press("LeftButton")
  elseif b == "PAD2" then P.Back()
  elseif b == "PAD3" then P.Info()
  elseif b == "PAD4" then press("RightButton")
  elseif b == "PADLSHOULDER" then P.Tab(-1)
  elseif b == "PADRSHOULDER" then P.Tab(1)
  else return false end
  return true
end
if catcher.EnableGamePadButton then
  catcher:SetScript("OnGamePadButtonDown", function(self, b)
    local mine = HANDLED[b] and not inCombat()
    -- (buttons Kina doesn't use go on to the game)
    if self.SetPropagateKeyboardInput and not inCombat() then pcall(self.SetPropagateKeyboardInput, self, not mine) end
    if mine then pcall(P.Button, b) end
  end)
end
local function sync()
  local want = P.Active() and P.Window() ~= nil and not inCombat()
  if want and not catcher:IsShown() then
    catcher:Show()
    if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, true) end
    if not focus then local w = P.Window(); local l = w and P.Collect(w); if l and l[1] then P.Focus(l[1]) end end
  elseif not want and catcher:IsShown() then
    if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, false) end
    catcher:Hide(); P.Focus(nil)
  elseif want and focus and not focus:IsVisible() then
    P.Focus(nil)
  end
end
P.Sync = sync
local t = CreateFrame("Frame")
local acc = 0
t:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.25 then return end
  acc = 0
  if inCombat() then if catcher:IsShown() then catcher:Hide(); P.Focus(nil) end; return end
  pcall(sync)
end)
C.On("PLAYER_REGEN_DISABLED", function()
  -- combat: hand the controller straight back to the game
  if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, false) end
  catcher:Hide(); P.Focus(nil)
end)
