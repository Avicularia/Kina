local ADDON, C = ...
-- 1.4.0: Kina's cosmetics (Taylor's Scenario art, Nov 6): standing rings around the
-- portrait, the level plate, Mentor Star / starter leaf, profession emblems, forged XP and
-- standing bar frames, and the KINA title in the Cinzel font.
local K = {}
C.Cos = K
local P = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Cos\\"
K.FONT = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Fonts\\Cinzel-Bold.ttf"
local RING = { Unproven = "ring_base", Vouched = "ring_vouched", Reliable = "ring_reliable", Trusted = "ring_trusted",
  Honored = "ring_honored", Revered = "ring_revered", Exalted = "ring_exalted",
  Delinquent = "ring_disgraced", Disgraced = "ring_disgraced", Oathbreaker = "ring_disgraced" }
local PROF = { Mining = "prof_mining", Herbalism = "prof_herbalism", Skinning = "prof_skinning", Enchanting = "prof_enchanting" }
function K.Tex(name) return P .. name end
function K.RingFor(standing) return P .. (RING[standing or "Unproven"] or "ring_base") end
function K.ProfIcon(prof) return P .. (PROF[prof] or "prof_generic") end
function K.StarFor(recruits)
  recruits = tonumber(recruits) or 0
  if recruits >= 50 then return P .. "star_50", true end
  if recruits >= 20 then return P .. "star_20" end
  if recruits >= 10 then return P .. "star_10" end
  if recruits >= 5 then return P .. "star_5" end
  if recruits >= 1 then return P .. "star_1" end
end
function K.Font(fs, size, flags)
  if fs and fs.SetFont then
    local ok = pcall(fs.SetFont, fs, K.FONT, size, flags or "OUTLINE")
    if not ok then fs:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE") end
  end
end

-- the portrait: a round portrait inside the standing ring (with a glow from Honored
-- up, a slow pulse at Exalted), the badge crowning the ring, the level plate at its foot
local COLOR = { Unproven = "|cffbfbfbf", Vouched = "|cffd8d8d8", Reliable = "|cffd9a35a", Trusted = "|cffe0b060",
  Honored = "|cffe8d8a0", Revered = "|cfff2e6b8", Exalted = "|cffffd34d", Delinquent = "|cffff6040", Disgraced = "|cffff4030", Oathbreaker = "|cffd02020" }
function K.StandingColor(st) return COLOR[st or "Unproven"] or "|cffbfbfbf" end
local GLOW = { Honored = { 0.9, 0.85, 0.6, 0.30 }, Revered = { 1, 0.95, 0.75, 0.40 }, Exalted = { 1, 0.80, 0.25, 0.55 },
  Delinquent = { 0.8, 0.15, 0.1, 0.30 }, Disgraced = { 0.8, 0.1, 0.05, 0.40 }, Oathbreaker = { 0.7, 0.05, 0.05, 0.5 } }
function K.Portrait(box, portrait)
  local o = {}
  if portrait.SetMask then pcall(portrait.SetMask, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  portrait:ClearAllPoints(); portrait:SetPoint("TOPLEFT", 4, -4); portrait:SetPoint("BOTTOMRIGHT", -4, 4)
  local W = box:GetWidth() or 80
  o.glow = box:CreateTexture(nil, "BACKGROUND", nil, -2)
  o.glow:SetPoint("CENTER", portrait, "CENTER"); o.glow:SetSize(W * 1.45, W * 1.45); o.glow:SetBlendMode("ADD")
  o.ring = box:CreateTexture(nil, "OVERLAY", nil, 2)
  o.ring:SetPoint("CENTER", portrait, "CENTER", 0, 0); o.ring:SetSize(W * 1.30, W * 1.30)
  o.plate = box:CreateTexture(nil, "OVERLAY", nil, 4)
  o.plate:SetSize(36, 36); o.plate:SetPoint("CENTER", o.ring, "BOTTOM", 0, 4)
  o.plate:SetTexture(P .. "level_plate")
  o.num = box:CreateFontString(nil, "OVERLAY")
  K.Font(o.num, 12, "OUTLINE"); o.num:SetPoint("CENTER", o.plate, "CENTER", 0, 1); o.num:SetTextColor(1, 0.86, 0.45)
  o.badge = box:CreateTexture(nil, "OVERLAY", nil, 5)
  o.badge:SetPoint("CENTER", o.ring, "TOP", 0, 2)
  local t = 0
  local pulser = CreateFrame("Frame", nil, box)
  pulser:SetScript("OnUpdate", function(_, el)
    if not o.pulse then return end
    t = t + el
    o.glow:SetAlpha(0.35 + 0.25 * math.sin(t * 2.2))
  end)
  return o
end
function K.UpdatePortrait(o, standing, level, recruits, starter)
  if not o then return end
  o.ring:SetTexture(K.RingFor(standing))
  local g = GLOW[standing or ""]
  if g then o.glow:SetTexture(K.RingFor(standing)); o.glow:SetVertexColor(g[1], g[2], g[3]); o.glow:SetAlpha(g[4]); o.glow:Show() else o.glow:Hide() end
  o.pulse = standing == "Exalted"
  o.num:SetText(C.Rep and C.Rep.Roman and C.Rep.Roman(level or 1) or tostring(level or 1))
  local star, wide = K.StarFor(recruits)
  if starter then o.badge:SetTexture(P .. "leaf"); o.badge:SetSize(30, 30); o.badge:Show()
  elseif star then o.badge:SetTexture(star); if wide then o.badge:SetSize(72, 36) else o.badge:SetSize(32, 32) end; o.badge:Show()
  else o.badge:Hide() end
end
-- a forged frame over a status bar
-- (1.4.2: hugs the bar: the art's own bounds, only 7 px wider and 4 px taller each side)
local CROP = { xp_bar = { 14 / 64, 49 / 64 }, standing_bar = { 8 / 64, 55 / 64 } }
function K.BarFrame(bar, which)
  local t = bar:CreateTexture(nil, "OVERLAY", nil, 3)
  t:SetTexture(P .. which)
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", -7, 4); t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 7, -4)
  local c = CROP[which] or { 0, 1 }
  t:SetTexCoord(2 / 512, 510 / 512, c[1], c[2])
  return t
end

------------------------------------------------------------------ test pickers
-- 1.4.2 (Taylor): try every cosmetic in place. A small "Try" button next to each piece
-- opens a list; picking one shows it right away (preview only, nothing is saved).
K.preview = {}
local menu
function K.OpenList(anchor, label, options, onPick, style)
  if menu and menu:IsShown() and menu.owner == anchor then menu:Hide(); return end
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true)
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menu:SetBackdropColor(0.06, 0.05, 0.04, 0.96); menu:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    menu.rows = {}
  end
  menu.owner = anchor
  for _, r in ipairs(menu.rows) do r:Hide() end
  local title = menu.title or menu:CreateFontString(nil, "OVERLAY", "GameFontNormal"); menu.title = title
  title:SetPoint("TOPLEFT", 10, -8); title:SetText(label)
  for i, opt in ipairs(options) do
    local r = menu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, menu); r:SetSize(230, 18)
      r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 6, 0)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints()
      menu.rows[i] = r
    end
    r:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 18)
    -- 1.5.2: "bad" lists (bad commendations) are red: red border, red tint, red highlight
    if style == "bad" then r.hl:SetColorTexture(1, 0.15, 0.1, 0.30) else r.hl:SetColorTexture(1, 0.85, 0.4, 0.16) end
    r.t:SetText(opt[1])
    r:SetScript("OnClick", function() menu:Hide(); onPick(opt[2]) end)
    r:Show()
  end
  menu:SetSize(244, 34 + #options * 18)
  if menu.SetBackdropBorderColor then
    if style == "bad" then menu:SetBackdropColor(0.22, 0.03, 0.02, 0.97); menu:SetBackdropBorderColor(1, 0.18, 0.12, 1)
    else menu:SetBackdropColor(0.06, 0.05, 0.04, 0.96); menu:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end
  end
  menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
end
function K.Picker(parent, label, options, onPick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(46, 18); b:SetText("Try"); b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
  local fs = b:GetFontString(); if fs then fs:SetFont(STANDARD_TEXT_FONT, 10, "") end
  b:SetScript("OnClick", function(self) K.OpenList(self, label, options, onPick) end)
  return b
end

------------------------------------------------------------------ standing glow on windows
-- 1.5.0: the Kina window and the farm widget take on your standing: a soft golden edge
-- glow from Honored up (brighter at Revered, slowly pulsing at Exalted), a dull red one
-- when your standing is below 0. Nothing below Honored, so it means something.
local EDGE = { Honored = { 0.95, 0.85, 0.55, 0.35 }, Revered = { 1, 0.92, 0.70, 0.50 }, Exalted = { 1, 0.80, 0.25, 0.65 },
  Delinquent = { 0.8, 0.15, 0.1, 0.35 }, Disgraced = { 0.8, 0.1, 0.05, 0.45 }, Oathbreaker = { 0.7, 0.05, 0.05, 0.55 } }
local glows = {}
local function edge(f, p1, p2, w, h, x1, y1, x2, y2, horiz, flip)
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetBlendMode("ADD")
  t:SetPoint(p1, f, p1, x1, y1); t:SetPoint(p2, f, p2, x2, y2)
  if w then t:SetWidth(w) end; if h then t:SetHeight(h) end
  t.horiz, t.flip = horiz, flip
  return t
end
local function paint(t, c, a)
  local inner, outer = a, 0
  if t.flip then inner, outer = outer, inner end
  local o = t.horiz and "HORIZONTAL" or "VERTICAL"
  if CreateColor and t.SetGradient then
    pcall(t.SetGradient, t, o, CreateColor(c[1], c[2], c[3], inner), CreateColor(c[1], c[2], c[3], outer))
  elseif t.SetGradientAlpha then
    pcall(t.SetGradientAlpha, t, o, c[1], c[2], c[3], inner, c[1], c[2], c[3], outer)
  else t:SetVertexColor(c[1], c[2], c[3], a * 0.5) end
end
function K.Glow(f, size)
  if not f or glows[f] then return end
  size = size or 14
  local g = {
    edge(f, "BOTTOMLEFT", "BOTTOMRIGHT", nil, size, -size, 0, size, 0, false, false),   -- top band, above the frame
    edge(f, "TOPLEFT", "TOPRIGHT", nil, size, -size, 0, size, 0, false, true),          -- bottom band
    edge(f, "TOPRIGHT", "BOTTOMRIGHT", size, nil, 0, 0, 0, 0, true, true),              -- left band
    edge(f, "TOPLEFT", "BOTTOMLEFT", size, nil, 0, 0, 0, 0, true, false),               -- right band
  }
  g[1]:ClearAllPoints(); g[1]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -size, 0); g[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", size, 0)
  g[2]:ClearAllPoints(); g[2]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -size, 0); g[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", size, 0)
  g[3]:ClearAllPoints(); g[3]:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0); g[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
  g[4]:ClearAllPoints(); g[4]:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0); g[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
  glows[f] = g
  K.UpdateGlows()
end
local pulse, t0 = false, 0
function K.UpdateGlows(standing)
  if not standing then
    local ok, m = pcall(function() return C.Rep and C.Rep.Mine and C.Rep.Mine() end)
    standing = (K.preview and K.preview.ring) or (ok and m and m.standing) or "Unproven"
  end
  local c = EDGE[standing]
  pulse = standing == "Exalted"
  for _, g in pairs(glows) do
    for _, t in ipairs(g) do
      if c then paint(t, c, c[4]); t:Show() else t:Hide() end
    end
  end
end
local pf = CreateFrame("Frame")
local acc = 0
pf:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc > 60 then acc = 0; pcall(K.UpdateGlows) end -- standing can change
  if pulse then
    t0 = t0 + el
    local a = 0.6 + 0.4 * math.sin(t0 * 2)
    for _, g in pairs(glows) do for _, t in ipairs(g) do t:SetAlpha(a) end end
  end
end)
