local _, C = ...
-- Kina: the welcome tour (0.9.1). Shown once on a first install, and any time from
-- /kina tour or the Help page. It walks through Kina one feature at a time: the
-- feature lights up, the rest of the screen dims, and a card beside it says what it is,
-- how to use it, and the rules that go with it.
--
-- The engine lives here; the steps are plain data in TourSteps.lua. To change the tour,
-- edit that file: add, remove or reorder steps, or change their words. Each step is
--   { id = "widget", title = "...", body = "...", rules = "..." (optional),
--     target = function() return someFrame end   (nil = a card in the middle; return two
--                                                  frames to light up both and the space between),
--     open = function() ... end                    (get the screen ready),
--     close = function() ... end,                  (put it back),
--     side = "RIGHT" | "LEFT" | "TOP" | "BOTTOM"    (optional: where the card goes),
--     beside = function() return frame end         (optional: put the card beside this
--                                                  bigger frame, level with the lit one) }
-- Tour.Add(step, beforeId) and Tour.Remove(id) change it from other files too.
local T = {}
C.Tour = T
T.steps = {}

function T.Add(step, beforeId)
  for i, s in ipairs(T.steps) do
    if beforeId and s.id == beforeId then table.insert(T.steps, i, step); return end
  end
  T.steps[#T.steps + 1] = step
end
function T.Remove(id)
  for i, s in ipairs(T.steps) do if s.id == id then table.remove(T.steps, i); return true end end
end
function T.Find(id) for i, s in ipairs(T.steps) do if s.id == id then return i, s end end end

local GOLD, GREY, RED = "|cffffc54a", "|cff9d9d9d", "|cffff6a50"
local CARD_W = 360
local ov, card, idx, current

------------------------------------------------------------------ the dim and the light
-- Four dark panes around the feature (the feature itself stays bright and clickable),
-- a gold frame that breathes around it, and a short gold line from the card to it.
local function overlay()
  if ov then return ov end
  ov = CreateFrame("Frame", "KinaTourShade", UIParent)
  ov:SetAllPoints(UIParent); ov:SetFrameStrata("FULLSCREEN_DIALOG"); ov:SetFrameLevel(1)
  ov.pane = {}
  for i = 1, 4 do local t = ov:CreateTexture(nil, "BACKGROUND"); t:SetColorTexture(0, 0, 0, 0.62); ov.pane[i] = t end
  ov.ring = CreateFrame("Frame", nil, ov); ov.ring:SetFrameLevel(5)
  ov.edge = {}
  for i = 1, 4 do local t = ov.ring:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(1, 0.66, 0.14, 1); ov.edge[i] = t end
  ov.glow = ov.ring:CreateTexture(nil, "ARTWORK")
  local halo = C.Cos and C.Cos.Tex and C.Cos.Tex("fx_halo")
  if halo then ov.glow:SetTexture(halo); if ov.glow.SetBlendMode then ov.glow:SetBlendMode("ADD") end
  else ov.glow:SetColorTexture(1, 0.62, 0.04, 0.15) end
  ov.glow:SetVertexColor(1, 0.64, 0.1, 0.9)
  ov.link = ov:CreateTexture(nil, "OVERLAY"); ov.link:SetColorTexture(1, 0.66, 0.14, 0.9)
  ov.dot = ov:CreateTexture(nil, "OVERLAY"); ov.dot:SetSize(7, 7); ov.dot:SetColorTexture(1, 0.75, 0.36, 1)
  local acc = 0
  ov:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    local a = 0.55 + 0.45 * math.abs(math.sin(acc * 2.2))
    for _, t in ipairs(ov.edge) do t:SetAlpha(a) end
    ov.glow:SetAlpha(0.35 + 0.4 * a)
  end)
  return ov
end

-- a frame's box on the screen, in UIParent's units
local function rectOf(f)
  if not (f and f.GetLeft and f:IsVisible()) then return nil end
  local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  if not (l and r and t and b) then return nil end
  local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return l * k, r * k, t * k, b * k
end

local function light(target, target2)
  local o = overlay()
  local W, H = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
  local l, r, t, b = rectOf(target)
  -- a second frame widens the light to cover both (e.g. a row of tiles)
  local l2, r2, t2, b2 = rectOf(target2)
  if l and l2 then l, r, t, b = math.min(l, l2), math.max(r, r2), math.max(t, t2), math.min(b, b2) end
  local p = o.pane
  for _, x in ipairs(p) do x:ClearAllPoints() end
  if not l then
    -- no feature: dim everything
    p[1]:SetAllPoints(o); for i = 2, 4 do p[i]:Hide() end; p[1]:Show()
    o.ring:Hide(); o.link:Hide(); o.dot:Hide()
    return nil
  end
  local pad = 6
  l, r, t, b = l - pad, r + pad, t + pad, b - pad
  for _, x in ipairs(p) do x:Show() end
  p[1]:SetPoint("TOPLEFT", o, "TOPLEFT", 0, 0); p[1]:SetPoint("BOTTOMRIGHT", o, "TOPRIGHT", 0, -(H - t))           -- above
  p[2]:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, b); p[2]:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, 0)           -- below
  p[3]:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, t); p[3]:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", l, b)            -- left
  p[4]:SetPoint("TOPLEFT", o, "BOTTOMLEFT", r, t); p[4]:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, b)           -- right
  local ring = o.ring
  ring:ClearAllPoints(); ring:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", l, b); ring:SetSize(r - l, t - b); ring:Show()
  local e = o.edge
  for _, x in ipairs(e) do x:ClearAllPoints() end
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(2)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(2)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(2)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(2)
  o.glow:ClearAllPoints(); o.glow:SetPoint("TOPLEFT", ring, "TOPLEFT", -24, 24); o.glow:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", 24, -24)
  return l, r, t, b
end

------------------------------------------------------------------ the card
local function btn(parent, label, w, fn)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 24); b:SetText(label)
  if C.Skin and C.Skin.Button then C.Skin.Button(b) end
  b:SetScript("OnClick", fn)
  return b
end
local function makeCard()
  if card then return card end
  card = CreateFrame("Frame", "KinaTourCard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  card:SetFrameStrata("FULLSCREEN_DIALOG"); card:SetFrameLevel(30); card:SetToplevel(true)
  card:SetWidth(CARD_W); card:EnableMouse(true); card:SetClampedToScreen(true)
  if C.Skin and C.Skin.Panel then C.Skin.Panel(card, 6)
  elseif card.SetBackdrop then
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    card:SetBackdropColor(0.07, 0.06, 0.05, 0.97); card:SetBackdropBorderColor(0.94, 0.6, 0.1, 1)
  end
  card.step = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.step:SetPoint("TOPLEFT", 18, -14)
  card.step:SetTextColor(0.78, 0.62, 0.33)
  card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); card.title:SetPoint("TOPLEFT", 18, -30); card.title:SetWidth(CARD_W - 36)
  card.title:SetJustifyH("LEFT")
  if C.Cos and C.Cos.Font then C.Cos.Font(card.title, 19, "") end
  card.title:SetTextColor(1, 0.78, 0.34)
  card.rule = card:CreateTexture(nil, "ARTWORK"); card.rule:SetHeight(1); card.rule:SetColorTexture(0.52, 0.35, 0.11, 1)
  card.rule:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8); card.rule:SetWidth(CARD_W - 36)
  card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); card.body:SetPoint("TOPLEFT", card.rule, "BOTTOMLEFT", 0, -10)
  card.body:SetWidth(CARD_W - 36); card.body:SetJustifyH("LEFT"); card.body:SetJustifyV("TOP")
  if card.body.SetSpacing then card.body:SetSpacing(3) end
  -- the rules box: darker, with a red-gold "RULES" tab
  card.rbox = CreateFrame("Frame", nil, card)
  card.rbox.bg = card.rbox:CreateTexture(nil, "BACKGROUND"); card.rbox.bg:SetAllPoints(); card.rbox.bg:SetColorTexture(0.16, 0.05, 0.03, 0.85)
  card.rbox.bar = card.rbox:CreateTexture(nil, "ARTWORK"); card.rbox.bar:SetPoint("TOPLEFT"); card.rbox.bar:SetPoint("BOTTOMLEFT"); card.rbox.bar:SetWidth(3)
  card.rbox.bar:SetColorTexture(0.85, 0.3, 0.2, 1)
  card.rbox.head = card.rbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.rbox.head:SetPoint("TOPLEFT", 12, -8)
  card.rbox.head:SetText(RED .. "THE RULES|r")
  card.rbox.text = card.rbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.rbox.text:SetPoint("TOPLEFT", 12, -24)
  card.rbox.text:SetWidth(CARD_W - 60); card.rbox.text:SetJustifyH("LEFT"); card.rbox.text:SetJustifyV("TOP")
  if card.rbox.text.SetSpacing then card.rbox.text:SetSpacing(2) end
  card.back = btn(card, "Back", 76, function() T.Go(idx - 1) end)
  card.next = btn(card, "Next", 96, function() T.Go(idx + 1) end)
  card.next:SetPoint("BOTTOMRIGHT", -16, 14); card.back:SetPoint("RIGHT", card.next, "LEFT", -6, 0)
  card.skip = CreateFrame("Button", nil, card); card.skip:SetSize(90, 20); card.skip:SetPoint("BOTTOMLEFT", 14, 16)
  card.skip.t = card.skip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.skip.t:SetAllPoints(); card.skip.t:SetJustifyH("LEFT")
  card.skip.t:SetText(GREY .. "Skip the tour|r")
  card.skip:SetScript("OnEnter", function(self) self.t:SetText("|cffe8d6a0Skip the tour|r") end)
  card.skip:SetScript("OnLeave", function(self) self.t:SetText(GREY .. "Skip the tour|r") end)
  card.skip:SetScript("OnClick", function() T.Stop(true) end)
  -- progress pips along the bottom
  card.pips = {}
  return card
end

local function layoutCard(step)
  local c = makeCard()
  c.step:SetText(string.format("KINA TOUR  ·  %d OF %d", idx, #T.steps))
  c.title:SetText(step.title or "")
  -- (title, body and rules can be functions, worked out when the card shows)
  local function val(v) if type(v) == "function" then local ok, r = pcall(v); return ok and r or "" end; return v end
  c.title:SetText(val(step.title) or "")
  c.body:SetText(val(step.body) or "")
  local rules = val(step.rules)
  local h = 30 + (c.title:GetStringHeight() or 20) + 19 + (c.body:GetStringHeight() or 40)
  if rules and rules ~= "" then
    c.rbox.text:SetText(rules)
    local rh = (c.rbox.text:GetStringHeight() or 30) + 32
    c.rbox:ClearAllPoints(); c.rbox:SetPoint("TOPLEFT", c.body, "BOTTOMLEFT", 0, -12); c.rbox:SetSize(CARD_W - 36, rh); c.rbox:Show()
    h = h + 12 + rh
  else c.rbox:Hide() end
  -- pips
  for i = 1, math.max(#T.steps, #c.pips) do
    local p = c.pips[i]
    if not p and i <= #T.steps then p = c:CreateTexture(nil, "OVERLAY"); p:SetSize(6, 6); c.pips[i] = p end
    if p then
      if i <= #T.steps then
        p:ClearAllPoints(); p:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 18 + (i - 1) * 9, 44); p:Show()
        if i == idx then p:SetColorTexture(1, 0.66, 0.14, 1) elseif i < idx then p:SetColorTexture(0.66, 0.44, 0.13, 1) else p:SetColorTexture(0.33, 0.28, 0.2, 1) end
      else p:Hide() end
    end
  end
  h = h + 72
  c:SetHeight(h)
  if idx <= 1 then c.back:Disable() else c.back:Enable() end
  c.next:SetText(idx >= #T.steps and "Finish" or (idx == 1 and "Show me" or "Next"))
end

-- the card goes on the side of the feature with the most room
local function placeCard(step, l, r, t, b, bl, br, bt, bb)
  local c = card
  local W, H = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
  local cw, ch = c:GetWidth(), c:GetHeight()
  c:ClearAllPoints()
  local o = ov
  if not l then
    c:SetPoint("CENTER", UIParent, "CENTER", 0, 40); o.link:Hide(); o.dot:Hide(); return
  end
  -- (beside: the card goes next to a bigger frame, its top level with the lit feature)
  local tl, tr_, tt, tb = l, r, t, b
  if bl then l, r, t, b = bl, br, bt, bb end
  local room = { RIGHT = W - r, LEFT = l, TOP = H - t, BOTTOM = b }
  local side = step.side
  if not side or room[side] < ((side == "LEFT" or side == "RIGHT") and cw + 40 or ch + 40) then
    side = "RIGHT"
    for _, sd in ipairs({ "RIGHT", "LEFT", "BOTTOM", "TOP" }) do
      local need = (sd == "LEFT" or sd == "RIGHT") and cw + 40 or ch + 40
      if room[sd] >= need then side = sd; break end
    end
  end
  local gap = 34
  local cx, cy = (l + r) / 2, (t + b) / 2
  local x, y
  local ly = bl and (tt + 30) or (cy + ch / 2)
  if side == "RIGHT" then x, y = r + gap, ly
  elseif side == "LEFT" then x, y = l - gap - cw, ly
  elseif side == "BOTTOM" then x, y = cx - cw / 2, b - gap
  else x, y = cx - cw / 2, t + gap + ch end
  x = math.max(8, math.min(W - cw - 8, x)); y = math.max(ch + 8, math.min(H - 8, y))
  c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  -- the gold line from the card's edge to the feature
  if bl then l, r, t, b = tl, tr_, tt, tb; cx, cy = (l + r) / 2, (t + b) / 2 end
  o.link:ClearAllPoints(); o.dot:ClearAllPoints()
  local my = math.max(y - ch + 12, math.min(y - 12, cy))
  local mx = math.max(x + 12, math.min(x + cw - 12, cx))
  if side == "RIGHT" then o.link:SetPoint("TOPLEFT", o, "BOTTOMLEFT", r, my + 1); o.link:SetSize(math.max(1, x - r), 2); o.dot:SetPoint("CENTER", o, "BOTTOMLEFT", r, my)
  elseif side == "LEFT" then o.link:SetPoint("TOPLEFT", o, "BOTTOMLEFT", x + cw, my + 1); o.link:SetSize(math.max(1, l - x - cw), 2); o.dot:SetPoint("CENTER", o, "BOTTOMLEFT", l, my)
  elseif side == "BOTTOM" then o.link:SetPoint("TOPLEFT", o, "BOTTOMLEFT", mx - 1, b); o.link:SetSize(2, math.max(1, b - y)); o.dot:SetPoint("CENTER", o, "BOTTOMLEFT", mx, b)
  else o.link:SetPoint("TOPLEFT", o, "BOTTOMLEFT", mx - 1, y - ch); o.link:SetSize(2, math.max(1, (y - ch) - t)); o.dot:SetPoint("CENTER", o, "BOTTOMLEFT", mx, t) end
  o.link:Show(); o.dot:Show()
end

------------------------------------------------------------------ running it
local function leave()
  if current and current.close then pcall(current.close) end
  current = nil
end

function T.Go(i)
  if i < 1 then return end
  if i > #T.steps then T.Stop(false, true); return end
  leave()
  idx = i
  local step = T.steps[i]
  current = step
  if step.open then local ok, err = pcall(step.open); if not ok and C.debug then C.Print("tour: " .. tostring(err)) end end
  local target, target2
  if step.target then local ok, f, f2 = pcall(step.target); if ok then target, target2 = f, f2 end end
  overlay():Show()
  layoutCard(step)
  local l, r, t, b = light(target, target2)
  local bl, br, bt, bb
  if l and step.beside then local ok, bf = pcall(step.beside); if ok then bl, br, bt, bb = rectOf(bf) end end
  placeCard(step, l, r, t, b, bl, br, bt, bb)
  card:Show()
  -- some features only get their size a moment after they show (a tooltip filling in):
  -- light them again shortly after
  if C.After and step.target then
    C.After(0.3, function()
      if not (T.active and current == step) then return end
      local ok, f, f2 = pcall(step.target)
      if not ok then return end
      local l2, r2, t2, b2 = light(f, f2)
      local xl, xr, xt, xb
      if l2 and step.beside then local ok2, bf = pcall(step.beside); if ok2 then xl, xr, xt, xb = rectOf(bf) end end
      placeCard(step, l2, r2, t2, b2, xl, xr, xt, xb)
    end)
  end
end

-- 0.9.2 (Taylor): finishing the tour the first time earns 50 XP and 20 standing. It's a
-- surprise: only the last page says so (TourSteps.lua, "done").
function T.Rewarded() return C.settings and C.settings.tourRewarded or false end
function T.Reward()
  if T.Rewarded() or not C.Log then return end
  C.settings.tourRewarded = true
  C.Log("tour", "done")
  local R = C.Rep or {}
  C.Print(string.format("|cffffc54aTour complete: +%d XP and +%d standing.|r Welcome to Kina!", R.TOUR_XP or 50, R.TOUR_REP or 20))
  if C.PlayCue then pcall(C.PlayCue, "settled") end
  if C.Refresh then pcall(C.Refresh) end
  if C.RefreshWidget then pcall(C.RefreshWidget) end
end

-- what the screen looked like before, put back at the end
local saved
function T.Start(at)
  if InCombatLockdown and InCombatLockdown() then C.Print("the Kina tour starts when you leave combat."); T.pending = true; return end
  if #T.steps == 0 then return end
  saved = { widget = C.settings and C.settings.hudShown, main = C.UI and C.UI.frame and C.UI.frame:IsShown(), tab = C.UI and C.UI.tab }
  T.active = true
  local i = 1
  if type(at) == "string" then i = T.Find(at) or 1 elseif type(at) == "number" then i = at end
  T.Go(i)
end
function T.Stop(skipped, finished)
  leave()
  if ov then ov:Hide() end
  if card then card:Hide() end
  T.active = false
  if C.settings then C.settings.tourSeen = C.version or true end
  if saved then
    if C.ShowWidget and saved.widget ~= nil then pcall(C.ShowWidget, saved.widget) end
    if C.UI and C.UI.frame then
      if saved.tab then C.UI.tab = saved.tab end
      if saved.main then C.UI.frame:Show() else C.UI.frame:Hide() end
    end
  end
  saved = nil
  -- 0.9.10: a new player is asked once who told them about Kina
  if finished and not T.Rewarded() then T.Reward(); return end
  if skipped then C.Print("tour skipped. Replay it any time: " .. GOLD .. "/kina tour|r, or the Help tab.")
  else C.Print("that's Kina! Replay the tour any time with " .. GOLD .. "/kina tour|r; the Help tab has every rule.") end
end
function T.Current() return idx, current end

-- first install: once, a little after logging in, out of combat
C.On("PLAYER_LOGIN", function()
  if not C.After then return end
  C.After(7, function()
    if C.settings and not C.settings.tourSeen and not C.settings.tourOff then T.Start() end
  end)
end)
C.On("PLAYER_REGEN_ENABLED", function() if T.pending then T.pending = nil; C.After(1, function() T.Start() end) end end)
