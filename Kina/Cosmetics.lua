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
  Delinquent = "ring_delinquent", Disgraced = "ring_disgraced", Oathbreaker = "ring_oathbreaker", Blacklisted = "ring_oathbreaker" }
local PROF = { Mining = "prof_mining", Herbalism = "prof_herbalism", Skinning = "prof_skinning", Enchanting = "prof_enchanting" }
function K.Tex(name) return P .. name end
function K.RingFor(standing) return P .. (RING[standing or "Unproven"] or "ring_base") end
function K.ProfIcon(prof) return P .. (PROF[prof] or "prof_generic") end
function K.StarFor(recruits)
  recruits = tonumber(recruits) or 0
  if recruits >= 50 then return P .. "star_50" end -- 0.9.9: square, gem-set like the rings
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
  Honored = "|cffe8d8a0", Revered = "|cfff2e6b8", Exalted = "|cffffd34d", Delinquent = "|cffff6040", Disgraced = "|cffff4030", Oathbreaker = "|cffd02020", Blacklisted = "|cff8a1010" }
function K.StandingColor(st) return COLOR[st or "Unproven"] or "|cffbfbfbf" end
-- 0.9.7 (Taylor, mocks approved): every tier's look, in one family. Round soft halos
-- (no more blurry copies of the ring), getting bigger and warmer as you climb; Trusted
-- adds a glint that runs round the rim; Honored adds two circling sparks and rising
-- embers; Revered a violet-and-gold double halo, turning rays and more embers; Exalted
-- all of it, brightest. Dishonour is deliberately NOT pretty: no glow, a grey portrait,
-- dimmed or broken rings, and at Oathbreaker and Blacklisted a dark red shadow that
-- throbs in from the edge.
--  halo  = { r, g, b, size (x portrait), alpha, breathe depth, breathe speed }
--  halo2 = an inner second halo (same fields); rays = { alpha, r, g, b }
--  sparks / sparkTint, embers (at full size) / emberTints, glint = true
local FX = {
  Vouched  = { halo = { 0.95, 0.70, 0.45, 1.55, 0.20, 0, 0 } },
  Reliable = { halo = { 0.55, 0.95, 0.60, 1.60, 0.26, 0.15, 0.9 } },
  Trusted  = { halo = { 0.59, 0.75, 1.00, 1.75, 0.34, 0.05, 0.8 }, glint = true },
  Honored  = { halo = { 1.00, 0.77, 0.35, 2.15, 0.62, 0.18, 1.6 }, sparks = 2, sparkTint = { 1, 0.80, 0.42 },
               embers = 16, emberTints = { { 1, 0.80, 0.42 } } },
  Revered  = { halo = { 0.67, 0.43, 1.00, 2.40, 0.55, 0.15, 1.8 }, halo2 = { 1.00, 0.80, 0.43, 1.55, 0.45, 0.15, 1.8 },
               rays = { 0.42, 0.95, 0.75, 1.00 }, sparks = 2, sparkTint = { 0.85, 0.60, 1.00 },
               embers = 20, emberTints = { { 0.85, 0.60, 1.00 }, { 1, 0.80, 0.42 } } },
  Exalted  = { halo = { 1.00, 0.76, 0.30, 2.60, 0.75, 0.20, 2.4 }, halo2 = { 1.00, 0.95, 0.78, 1.60, 0.50, 0.20, 2.4 },
               rays = { 0.55, 1.00, 0.82, 0.40 }, sparks = 2, sparkTint = { 1, 0.95, 0.80 }, glint = true,
               embers = 26, emberTints = { { 1, 0.80, 0.42 }, { 1, 0.95, 0.80 } } },
}
-- grey portrait (Delinquent half grey), how dark the portrait gets, the ring's dimming,
-- and the creeping red shadow (alpha) for the worst
local SHAME = { Delinquent = 0.5, Disgraced = 1, Oathbreaker = 1, Blacklisted = 1 }
local DARK = { Delinquent = 0.9, Disgraced = 0.85, Oathbreaker = 0.62, Blacklisted = 0.5 }
local RINGDIM = { Delinquent = 0.85, Disgraced = 0.78, Oathbreaker = 0.72, Blacklisted = 0.6 }
local VIGNETTE = { Oathbreaker = 0.8, Blacklisted = 1 }
function K.Portrait(box, portrait)
  local o = {}
  if portrait.SetMask then pcall(portrait.SetMask, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  portrait:ClearAllPoints(); portrait:SetPoint("TOPLEFT", 4, -4); portrait:SetPoint("BOTTOMRIGHT", -4, 4)
  o.portrait = portrait
  local W = box:GetWidth() or 80
  o.W = W
  local function addTex(layer, sub, file, size)
    local t = box:CreateTexture(nil, layer, nil, sub); t:SetPoint("CENTER", portrait, "CENTER"); t:SetSize(size, size)
    t:SetTexture(P .. file); t:SetBlendMode("ADD"); t:Hide(); return t
  end
  o.halo = addTex("BACKGROUND", -5, "fx_round", W * 2)
  o.halo2 = addTex("BACKGROUND", -4, "fx_round", W * 1.5)
  o.rays = addTex("BACKGROUND", -3, "fx_rays", W * 1.95)
  o.glow = addTex("BACKGROUND", -2, "fx_round", W) -- (kept for older callers; unused)
  o.ring = box:CreateTexture(nil, "OVERLAY", nil, 2)
  o.ring:SetPoint("CENTER", portrait, "CENTER", 0, 0); o.ring:SetSize(W * 1.30, W * 1.30)
  o.vig = box:CreateTexture(nil, "OVERLAY", nil, 1); o.vig:SetAllPoints(portrait); o.vig:SetTexture(P .. "fx_vignette"); o.vig:Hide()
  o.glint = addTex("OVERLAY", 3, "fx_glint", W * 1.30)
  o.sparks = {}
  for i = 1, 2 do o.sparks[i] = addTex("OVERLAY", 6, "fx_spark", W * 0.32) end
  o.embers = {}
  o.plate = box:CreateTexture(nil, "OVERLAY", nil, 4)
  o.plate:SetSize(36, 36); o.plate:SetPoint("CENTER", o.ring, "BOTTOM", 0, 4)
  o.plate:SetTexture(P .. "level_plate")
  o.num = box:CreateFontString(nil, "OVERLAY")
  K.Font(o.num, 12, "OUTLINE"); o.num:SetPoint("CENTER", o.plate, "CENTER", 0, 1); o.num:SetTextColor(1, 0.86, 0.45)
  o.badge = box:CreateTexture(nil, "OVERLAY", nil, 5)
  o.badge:SetPoint("CENTER", o.ring, "TOP", 0, 2)
  o.badgeGlow = box:CreateTexture(nil, "OVERLAY", nil, 4); o.badgeGlow:SetPoint("CENTER", o.badge, "CENTER")
  o.badgeGlow:SetTexture(P .. "fx_spark"); o.badgeGlow:SetBlendMode("ADD"); o.badgeGlow:SetVertexColor(0.35, 1, 0.35); o.badgeGlow:Hide()
  local t = 0
  local pulser = CreateFrame("Frame", nil, box)
  pulser:SetScript("OnUpdate", function(_, el)
    if not box:IsVisible() then return end
    if el > 0.2 then el = 0.2 end
    t = t + el
    local fx = o.fx
    if fx then
      local function breathe(h, tex) if h then tex:SetAlpha(math.max(0, math.min(1, h[5] * (1 + h[6] * math.sin(t * (h[7] > 0 and h[7] or 1)))))) end end
      breathe(fx.halo, o.halo); breathe(fx.halo2, o.halo2)
      if fx.rays and o.rays.SetRotation then pcall(o.rays.SetRotation, o.rays, t * 0.12); o.rays:SetAlpha(fx.rays[1] * (0.8 + 0.2 * math.sin(t * 1.3))) end
      for i = 1, (fx.sparks or 0) do
        local sp = o.sparks[i]
        local a = t * 0.9 + (i - 1) * math.pi
        local rr = W * 0.57
        sp:ClearAllPoints(); sp:SetPoint("CENTER", o.ring, "CENTER", math.cos(a) * rr, math.sin(a) * rr)
        sp:SetAlpha(0.55 + 0.45 * math.sin(t * 3 + i))
      end
      if fx.glint and o.glint.SetRotation then
        -- a glint runs a quarter of the way round the rim every 4.2 s
        local k = (t % 4.2) / 1.0
        if k <= 1 then
          pcall(o.glint.SetRotation, o.glint, math.pi * 0.75 - k * math.pi * 0.5)
          o.glint:SetAlpha(math.sin(k * math.pi)); o.glint:Show()
        else o.glint:Hide() end
      end
      for _, p in ipairs(o.embers) do
        if p.on then
          p.life = p.life + el * p.speed
          if p.life >= 1 then p.life = 0; p.x = math.random() * 1.1 - 0.55; p.size = 0.05 + math.random() * 0.06 end
          local s = W * p.size * (1 - p.life * 0.5)
          p.tex:SetSize(s, s); p.tex:ClearAllPoints()
          p.tex:SetPoint("CENTER", portrait, "CENTER", p.x * W + math.sin(p.life * 6 + p.wob) * W * 0.03, -W * 0.35 + p.life * W * 1.1)
          p.tex:SetAlpha(math.sin(p.life * math.pi) * 0.85)
        end
      end
    end
    if o.vigOn then o.vig:SetAlpha(o.vigOn * (0.8 + 0.2 * math.sin(t * 0.7))) end
    if o.badgeGlow:IsShown() then o.badgeGlow:SetAlpha(0.55 + 0.25 * math.sin(t * 1.5)) end
  end)
  return o
end
local function setHalo(tex, h, W)
  if not h then tex:Hide(); return end
  tex:SetVertexColor(h[1], h[2], h[3]); tex:SetSize(W * h[4], W * h[4]); tex:SetAlpha(h[5]); tex:Show()
end
function K.UpdatePortrait(o, standing, level, recruits, starter)
  if not o then return end
  o.ring:SetTexture(K.RingFor(standing))
  local fx = FX[standing or ""]
  o.fx = fx
  local W = o.W or 80
  setHalo(o.halo, fx and fx.halo, W); setHalo(o.halo2, fx and fx.halo2, W)
  o.glow:Hide()
  if fx and fx.rays then o.rays:SetVertexColor(fx.rays[2], fx.rays[3], fx.rays[4]); o.rays:Show() else o.rays:Hide() end
  for i = 1, 2 do
    local on = fx and (fx.sparks or 0) >= i
    if on then local c = fx.sparkTint or { 1, 0.95, 0.8 }; o.sparks[i]:SetVertexColor(c[1], c[2], c[3]); o.sparks[i]:Show() else o.sparks[i]:Hide() end
  end
  if not (fx and fx.glint) then o.glint:Hide() end
  -- embers: fewer on small portraits (the party strip)
  local want = fx and fx.embers or 0
  if W < 120 then want = math.floor(want * W / 160) end
  for i = 1, want do
    local p = o.embers[i]
    if not p then
      local tx = o.portrait:GetParent():CreateTexture(nil, "OVERLAY", nil, 7); tx:SetTexture(P .. "fx_spark"); tx:SetBlendMode("ADD")
      p = { tex = tx, x = math.random() * 1.1 - 0.55, life = math.random(), speed = 0.18 + math.random() * 0.25, size = 0.05 + math.random() * 0.06, wob = math.random() * 6.28 }
      o.embers[i] = p
    end
    local c = fx.emberTints[(i - 1) % #fx.emberTints + 1]
    p.tex:SetVertexColor(c[1], c[2], c[3]); p.tex:Show(); p.on = true
  end
  for i = want + 1, #o.embers do o.embers[i].on = false; o.embers[i].tex:Hide() end
  -- dishonour: grey, darker portrait; dimmed or broken ring; the red shadow
  local sh = SHAME[standing or ""]
  if o.portrait then
    if o.portrait.SetDesaturation then pcall(o.portrait.SetDesaturation, o.portrait, sh or 0)
    elseif o.portrait.SetDesaturated then pcall(o.portrait.SetDesaturated, o.portrait, sh ~= nil) end
    local dk = DARK[standing or ""] or 1
    o.portrait:SetVertexColor(dk, dk * (sh and 0.96 or 1), dk * (sh and 0.92 or 1))
  end
  local rd = RINGDIM[standing or ""] or 1
  o.ring:SetVertexColor(rd, rd * (sh and 0.95 or 1), rd * (sh and 0.9 or 1))
  o.vigOn = VIGNETTE[standing or ""]
  if o.vigOn then o.vig:Show() else o.vig:Hide() end
  o.num:SetText(C.Rep and C.Rep.Roman and C.Rep.Roman(level or 1) or tostring(level or 1))
  local star, wide = K.StarFor(recruits)
  -- 1.5.3 (Taylor: the mentor star was tiny): sized from the portrait, and bigger
  -- 0.9.7 (Taylor): the new player leaf is bright green with a soft green glow
  o.badgeGlow:Hide()
  if starter then
    o.badge:SetTexture(P .. "leaf_green"); o.badge:SetSize(W * 0.48, W * 0.48); o.badge:Show()
    o.badgeGlow:SetSize(W * 1.0, W * 1.0); o.badgeGlow:Show()
  elseif star then o.badge:SetTexture(star); if wide then o.badge:SetSize(W * 1.25, W * 0.62) else o.badge:SetSize(W * 0.6, W * 0.6) end; o.badge:Show()
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
    r:SetScript("OnClick", function()
      menu:Hide()
      -- (0.9.2: a choice that fails is logged, so it can be found)
      local ok, err = pcall(onPick, opt[2])
      if not ok and C.LogError then C.LogError("list " .. tostring(label), err) end
    end)
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
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(b) end
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

------------------------------------------------------------------ the KINA plaque's life
-- 1.5.5 (Taylor): a breathing gold halo around the nameplate, a light sweep across the
-- plate every few seconds, and gold sparks drifting up off it. Runs only while shown.
function K.PlaqueFX(plate, w, h, count)
  local halo = plate:CreateTexture(nil, "BACKGROUND", nil, -3)
  halo:SetTexture(P .. "fx_halo"); halo:SetBlendMode("ADD"); halo:SetVertexColor(1, 0.72, 0.25)
  halo:SetPoint("CENTER", plate, "CENTER", 0, 0); halo:SetSize(w * 1.22, h * 1.75)
  local clip = CreateFrame("Frame", nil, plate); clip:SetPoint("CENTER", plate, "CENTER", 0, 0); clip:SetSize(w * 0.74, h * 0.62)
  if clip.SetClipsChildren then clip:SetClipsChildren(true) end
  clip:SetFrameLevel(plate:GetFrameLevel() + 2)
  local sweep = clip:CreateTexture(nil, "OVERLAY"); sweep:SetTexture(P .. "fx_sweep"); sweep:SetBlendMode("ADD")
  sweep:SetSize(h * 0.5, h); sweep:SetVertexColor(1, 0.95, 0.8); sweep:SetAlpha(0)
  local fx = CreateFrame("Frame", nil, plate); fx:SetAllPoints(plate); fx:SetFrameLevel(plate:GetFrameLevel() + 3)
  local sparks = {}
  count = count or 22
  for i = 1, count do
    local s = fx:CreateTexture(nil, "OVERLAY"); s:SetTexture(P .. "fx_spark"); s:SetBlendMode("ADD"); s:SetVertexColor(1, 0.80, 0.42)
    sparks[i] = { tex = s, x = math.random() * w * 0.9 - w * 0.45, life = math.random(), speed = 0.25 + math.random() * 0.35,
      size = 4 + math.random() * 7, wob = math.random() * 6.28 }
  end
  local t, nextSweep, sweepT = 0, 2, nil
  local flashT -- 0.9.3: a quick flare (a new tab opened)
  fx:SetScript("OnUpdate", function(_, el)
    if el > 0.2 then el = 0.2 end
    t = t + el
    local boost = 0
    if flashT then
      flashT = flashT + el
      if flashT >= 0.45 then flashT = nil else boost = math.sin(flashT / 0.45 * math.pi) * 0.45 end
    end
    halo:SetAlpha(math.min(1, 0.55 + 0.30 * math.sin(t * 1.6) + boost))
    -- the sweep: across the plate in 0.9 s, every 5-7 s
    if not sweepT and t >= nextSweep then sweepT = 0 end
    if sweepT then
      sweepT = sweepT + el
      local f = sweepT / 0.9
      if f >= 1 then sweepT = nil; nextSweep = t + 5 + math.random() * 2; sweep:SetAlpha(0)
      else
        sweep:ClearAllPoints(); sweep:SetPoint("CENTER", clip, "CENTER", (f - 0.5) * (w * 0.9), 0)
        sweep:SetAlpha(math.sin(f * math.pi) * 0.55)
      end
    end
    -- sparks rise from the plate and fade
    for _, p in ipairs(sparks) do
      p.life = p.life + el * p.speed
      if p.life >= 1 then p.life = 0; p.x = math.random() * w * 0.9 - w * 0.45; p.size = 4 + math.random() * 7 end
      local yy = -h * 0.30 + p.life * h * 1.05
      local xx = p.x + math.sin(p.life * 6 + p.wob) * 4
      local s = p.size * (1 - p.life * 0.4)
      p.tex:SetSize(s, s); p.tex:ClearAllPoints(); p.tex:SetPoint("CENTER", fx, "CENTER", xx, yy)
      p.tex:SetAlpha(math.sin(p.life * math.pi) * 0.9)
    end
  end)
  -- (returned, not stored on the frame) flash(): the halo flares and a sweep runs now
  return { frame = fx, flash = function() flashT = 0; if not sweepT then sweepT = 0 end end }
end
