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

-- the portrait: a round portrait inside the standing ring, the Kina level plate below it
function K.Portrait(box, portrait)
  local o = {}
  if portrait.SetMask then pcall(portrait.SetMask, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  o.ring = box:CreateTexture(nil, "OVERLAY", nil, 2)
  o.ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  o.ring:SetSize((box:GetWidth() or 80) + 18, (box:GetHeight() or 80) + 18)
  o.plate = box:CreateTexture(nil, "OVERLAY", nil, 4)
  o.plate:SetSize(34, 34); o.plate:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 10, -10)
  o.plate:SetTexture(P .. "level_plate")
  o.num = box:CreateFontString(nil, "OVERLAY")
  K.Font(o.num, 12, "OUTLINE"); o.num:SetPoint("CENTER", o.plate, "CENTER", 0, 1); o.num:SetTextColor(1, 0.86, 0.45)
  o.badge = box:CreateTexture(nil, "OVERLAY", nil, 4)
  o.badge:SetSize(30, 30); o.badge:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -10, -10)
  return o
end
function K.UpdatePortrait(o, standing, level, recruits, starter)
  if not o then return end
  o.ring:SetTexture(K.RingFor(standing))
  o.num:SetText(C.Rep and C.Rep.Roman and C.Rep.Roman(level or 1) or tostring(level or 1))
  local star, wide = K.StarFor(recruits)
  if starter then o.badge:SetTexture(P .. "leaf"); o.badge:SetSize(26, 26); o.badge:Show()
  elseif star then o.badge:SetTexture(star); if wide then o.badge:SetSize(60, 30) else o.badge:SetSize(30, 30) end; o.badge:Show()
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
function K.Picker(parent, label, options, onPick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(46, 18); b:SetText("Try"); b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
  local fs = b:GetFontString(); if fs then fs:SetFont(STANDARD_TEXT_FONT, 10, "") end
  b:SetScript("OnClick", function(self)
    if menu and menu:IsShown() and menu.owner == self then menu:Hide(); return end
    if not menu then
      menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
      menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true) -- (1.4.3: above the Kina window, which sits at FULLSCREEN_DIALOG)
      if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        menu:SetBackdropColor(0.06, 0.05, 0.04, 0.96); menu:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
      end
      menu.rows = {}
    end
    menu.owner = self
    for _, r in ipairs(menu.rows) do r:Hide() end
    local title = menu.title or menu:CreateFontString(nil, "OVERLAY", "GameFontNormal"); menu.title = title
    title:SetPoint("TOPLEFT", 10, -8); title:SetText(label)
    for i, opt in ipairs(options) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu); r:SetSize(170, 18)
        r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 6, 0)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        menu.rows[i] = r
      end
      r:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 18)
      r.t:SetText(opt[1])
      r:SetScript("OnClick", function() menu:Hide(); onPick(opt[2]) end)
      r:Show()
    end
    menu:SetSize(184, 34 + #options * 18)
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end)
  return b
end
