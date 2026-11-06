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
  local star = K.StarFor(recruits)
  if starter then o.badge:SetTexture(P .. "leaf"); o.badge:SetSize(26, 26); o.badge:Show()
  elseif star then o.badge:SetTexture(star); o.badge:SetSize(30, 30); o.badge:Show()
  else o.badge:Hide() end
end
-- a forged frame over a status bar
function K.BarFrame(bar, which)
  local t = bar:CreateTexture(nil, "OVERLAY", nil, 3)
  t:SetTexture(P .. which)
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", -10, 9); t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 10, -9)
  t:SetTexCoord(0, 1, 0.22, 0.78)
  return t
end
