-- Kina: Help > Season 1 Cosmetics (1.0.5, Taylor's mock approved Nov 16).
-- Every cosmetic you can earn this season, never greyed out: names still to earn in red,
-- "Earned" in green, and "1600 standing (557 standing until unlock)". Standing rings (and
-- the dishonour rings), mentor stars (with a "How do I earn stars?" flyout), bond crests
-- with their gems and a meter each, and "Your progress": standing, recruits and bond XP
-- in the forged bar frames, each with a Details flyout of the exact rules.
-- The numbers come from Rep.lua / Mentor.lua / Pair.lua: change them there, not here.
local ADDON, C = ...
local G = {}
C.SeasonGuide = G

local P = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Cos\\"
local GOLD, GREY, GREEN, RED, PALE, BLUE = "|cffffc54a", "|cff9d9d9d", "|cff6ee678", "|cffff5a50", "|cffe8d6a0", "|cff78beff"
local GOOD = { { "Unproven", 0 }, { "Vouched", 100 }, { "Reliable", 300 }, { "Trusted", 600 }, { "Honored", 1000 }, { "Revered", 1600 }, { "Exalted", 2500 } }
local BAD = { { "Delinquent", -1 }, { "Disgraced", -100 }, { "Oathbreaker", -300 } }
local STARS = { 1, 5, 10, 20, 50 }
local TIERS = { { "Uncommon", { 0.27, 0.75, 0.33 }, "|cff46be55" }, { "Rare", { 0.27, 0.57, 0.94 }, "|cff4691f0" },
  { "Epic", { 0.67, 0.35, 0.92 }, "|cffaa5aeb" }, { "Legendary", { 1, 0.65, 0.2 }, "|cffffa532" } }
local GEMPOS = { { -0.19, -0.17 }, { 0.19, -0.17 }, { 0, -0.02 }, { -0.19, 0.13 }, { 0.19, 0.13 } }

local function fs(parent, size, font)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if size then local f, _, fl = t:GetFont(); if f then t:SetFont(f, size, fl) end end
  t:SetJustifyH("CENTER")
  return t
end
local function serif(t, size) if C.Cos and C.Cos.Font then C.Cos.Font(t, size, "") end; t:SetTextColor(1, 0.78, 0.34) end

------------------------------------------------------------------ my numbers
local function bondCU(level) local R = C.Rep; return 100 * R.BOND_FULL * (math.max(0, level) / 20) ^ (1 / R.BOND_CURVE) end
function G.Numbers()
  local n = { stand = 0, recruits = 0, bondCU = 0, bondWith = nil }
  local ok, m = pcall(function() return C.Rep and C.Rep.Mine and C.Rep.Mine() end)
  if ok and m then n.stand = m.rep or 0 end
  n.recruits = C.Mentor and C.Mentor.Count and C.Mentor.Count() or 0
  local pn = C.Pair and C.Pair.PartnerName and C.Pair.PartnerName()
  if pn and C.Rep and C.Rep.BondOf then n.bondWith, n.bondCU = pn, C.Rep.BondOf(pn) or 0 end
  return n
end

------------------------------------------------------------------ flyouts
local fly
local function flyout(anchor, title, lines)
  if not fly then
    fly = CreateFrame("Frame", "KinaGuideFlyout", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    fly:SetFrameStrata("TOOLTIP"); fly:SetClampedToScreen(true); fly:EnableMouse(true)
    if C.Skin and C.Skin.Panel then C.Skin.Panel(fly) elseif fly.SetBackdrop then
      fly:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      fly:SetBackdropColor(0.11, 0.08, 0.055, 0.98); fly:SetBackdropBorderColor(0.86, 0.66, 0.27)
    end
    fly.t = fs(fly, 14, "GameFontNormal"); fly.t:SetPoint("TOPLEFT", 14, -12); fly.t:SetJustifyH("LEFT")
    fly.rows = {}
    local x = CreateFrame("Button", nil, fly, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -2, -2); x:SetSize(24, 24)
    tinsert(UISpecialFrames, "KinaGuideFlyout")
  end
  if fly:IsShown() and fly.anchor == anchor then fly:Hide(); return end
  fly.anchor = anchor
  fly.t:SetText(GOLD .. title .. "|r")
  local wL, wR = 10, 10
  for i, l in ipairs(lines) do
    local r = fly.rows[i]
    if not r then
      r = { fs(fly, 12), fs(fly, 12) }; r[1]:SetJustifyH("LEFT"); r[2]:SetJustifyH("LEFT")
      fly.rows[i] = r
    end
    r[1]:SetText(l[1]); r[2]:SetText(l[2] or ""); r[1]:Show(); r[2]:Show()
    wL = math.max(wL, r[1]:GetStringWidth() or 0); wR = math.max(wR, r[2]:GetStringWidth() or 0)
  end
  for i = #lines + 1, #fly.rows do fly.rows[i][1]:Hide(); fly.rows[i][2]:Hide() end
  for i, r in ipairs(fly.rows) do
    r[1]:ClearAllPoints(); r[1]:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 18)
    r[2]:ClearAllPoints(); r[2]:SetPoint("TOPLEFT", 14 + wL + 16, -36 - (i - 1) * 18)
  end
  fly:SetSize(math.max(260, 14 + wL + 16 + wR + 16, (fly.t:GetStringWidth() or 0) + 50), 48 + #lines * 18)
  fly:ClearAllPoints(); fly:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
  fly:Show(); fly:Raise()
end
G.RULES = {
  standing = { "Standing: the exact rules", {
    { "Pay a debt", GREEN .. "+10, plus 2 per gold paid (up to +40)|r" }, { "Paid before it was due", GREEN .. "+5 more|r" },
    { "Qualifying group farm (15+ min)", GREEN .. "+5|r" }, { "Thumbs up from a farm-mate", GREEN .. "+10|r" },
    { "Thumbs down", RED .. "-10|r" }, { "A debt you owe runs out", RED .. "-50|r" },
    { "A week with no farms", RED .. "-100 (only while above 0)|r" }, { "Below 0", GREY .. "gains x0.5; back above 0: x3 to your best|r" },
    { "Your Kina Partner", GREEN .. "+10% to +20% on farms and payments together|r" } } },
  recruits = { "Recruits: the exact rules", {
    { "A recruit", PALE .. "a player whose Kina names you when it asks \"Who showed you Kina?\"|r" },
    { "When they're asked", PALE .. "once, at their first farm with a Kina user|r" },
    { "It counts", PALE .. "once their Kina has farmed 15+ minutes and told yours|r" },
    { "Each player", PALE .. "counts once, for one mentor only|r" },
    { "Stars", GOLD .. "1, 5, 10, 20 and 50 recruits|r" } } },
  bond = { "Bond XP: the exact rules", {
    { "Bond XP from a farm", PALE .. "your share of the gold / the usual gold per hour at your level, x100|r" },
    { "Time spent", PALE .. "+1% per minute of the farm|r" },
    { "Levels", PALE .. "20 (4 tiers of 5 gems); the last levels need the most|r" },
    { "Full bond", PALE .. "about 20 hours of usual farming together|r" },
    { "What it gives", GREEN .. "+10% XP and standing together, +0.5% per bond level|r" } } },
}

------------------------------------------------------------------ the page
local page
local function cell(parent, w)
  local c = CreateFrame("Frame", nil, parent); c:SetSize(w, 150)
  c.name = fs(c, 13, "GameFontNormal"); c.name:SetPoint("TOP", c, "TOP", 0, -96); c.name:SetWidth(w)
  c.l1 = fs(c, 11); c.l1:SetPoint("TOP", c.name, "BOTTOM", 0, -2); c.l1:SetWidth(w)
  c.l2 = fs(c, 10); c.l2:SetPoint("TOP", c.l1, "BOTTOM", 0, -1); c.l2:SetWidth(w)
  return c
end
local function status(c, name, earned, need, unit, color)
  c.name:SetText((earned and (color or "|cffffffff") or RED) .. name .. "|r")
  if earned then c.l1:SetText(GREEN .. "Earned|r"); c.l2:SetText("")
  else c.l1:SetText(PALE .. need[1] .. "|r"); c.l2:SetText(RED .. "(" .. need[2] .. " " .. unit .. " until unlock)|r") end
end
local function header(parent, y, title, sub, w)
  local t = fs(parent, nil, "GameFontNormal"); serif(t, 17); t:SetJustifyH("LEFT"); t:SetPoint("TOPLEFT", 4, y)
  t:SetText(title)
  local rule = parent:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetColorTexture(0.52, 0.35, 0.11, 0.9)
  rule:SetPoint("TOPLEFT", 0, y + 6); rule:SetWidth(w)
  if sub then
    local s = fs(parent, 11, "GameFontHighlightSmall"); s:SetJustifyH("LEFT"); s:SetPoint("TOPLEFT", 4, y - 24); s:SetWidth(w - 8)
    s:SetText(GREY .. sub .. "|r")
  end
  return y - (sub and 48 or 30)
end

local function build(parent, w)
  local f = CreateFrame("Frame", nil, parent); f:SetWidth(w)
  f.parts = {}
  local K = C.SheetKit
  local cols = math.max(3, math.floor(w / 118))
  local cw = w / cols
  local y = -6
  local n = G.Numbers()
  -- standing rings
  y = header(f, y, "Standing rings", "The ring around your portrait. Pay what you owe (sooner is better) and farm in groups to climb.", w)
  local function ringCell(i, st, pts, bad, yRow)
    local col = (i - 1) % cols
    local c = cell(f, cw); c:SetPoint("TOPLEFT", col * cw, yRow)
    local box = CreateFrame("Frame", nil, c); box:SetSize(78, 78); box:SetPoint("TOP", 0, -8)
    local tex = box:CreateTexture(nil, "ARTWORK")
    if SetPortraitTexture then pcall(SetPortraitTexture, tex, "player") end
    if C.Cos and C.Cos.Portrait then
      local o = C.Cos.Portrait(box, tex, {}); C.Cos.UpdatePortrait(o, st, 20, 0, false)
      if C.Cos.SetFounder then C.Cos.SetFounder(o, false) end
      if o.plate then o.plate:Hide() end; if o.num then o.num:Hide() end
    end
    if bad then
      c.name:SetText("|cffdc463c" .. st .. "|r")
      c.l1:SetText(PALE .. (pts == -1 and "below 0 standing" or (pts .. " standing")) .. "|r")
      c.l2:SetText(GREEN .. "you're " .. math.max(0, n.stand - (pts == -1 and 0 or pts)) .. " above it|r")
    else
      status(c, st, n.stand >= pts, { pts .. " standing", pts - n.stand }, "standing", "|cffffffff")
    end
    return c
  end
  local rows = math.ceil(#GOOD / cols)
  for i, r in ipairs(GOOD) do ringCell(i, r[1], r[2], false, y - math.floor((i - 1) / cols) * 150) end
  y = y - rows * 150 - 4
  local dn = fs(f, 11, "GameFontHighlightSmall"); dn:SetJustifyH("LEFT"); dn:SetPoint("TOPLEFT", 4, y); dn:SetWidth(w - 8)
  dn:SetText(GREY .. "Dishonour: what a debt left unpaid does to your ring (-50 standing each time). Climb back above 0 and it's gone.|r")
  y = y - 22
  for i, r in ipairs(BAD) do ringCell(i, r[1], r[2], true, y - math.floor((i - 1) / cols) * 150) end
  y = y - math.ceil(#BAD / cols) * 150 - 6
  -- mentor stars
  y = header(f, y, "Mentor stars", "The star on your portrait: players who started using Kina because of you.", w)
  local how = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(how) end
  how:SetSize(170, 22); how:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y + 46); how:SetText("How do I earn stars? >")
  how:SetScript("OnClick", function(self) flyout(self, G.RULES.recruits[1], G.RULES.recruits[2]) end)
  for i, need in ipairs(STARS) do
    local col = (i - 1) % cols
    local c = cell(f, cw); c:SetPoint("TOPLEFT", col * cw, y - math.floor((i - 1) / cols) * 150)
    local t = c:CreateTexture(nil, "ARTWORK"); t:SetTexture(C.Cos and C.Cos.StarFor(need) or (P .. "star_1"))
    if need >= 50 then t:SetSize(96, 48) else t:SetSize(64, 64) end
    t:SetPoint("TOP", 0, -18)
    status(c, need .. " recruit" .. (need == 1 and "" or "s"), n.recruits >= need, { "", need - n.recruits }, need - n.recruits == 1 and "recruit" or "recruits")
    if n.recruits < need then c.l1:SetText(RED .. "(" .. (need - n.recruits) .. " recruit" .. (need - n.recruits == 1 and "" or "s") .. "|r"); c.l2:SetText(RED .. "until unlock)|r") end
  end
  y = y - math.ceil(#STARS / cols) * 150 - 6
  -- bond crests
  local R = C.Rep
  local lvl = (R and R.BondLevel) and R.BondLevel(n.bondCU) or 0
  y = header(f, y, "Bond crests", "Your crest with your Kina Partner. Gold you earn together (and a little for time spent) fills it. 4 tiers, 5 gems each: 20 levels.", w)
  local ccols = math.min(4, cols)
  local ccw = w / ccols
  for i, t in ipairs(TIERS) do
    local col = (i - 1) % ccols
    local c = CreateFrame("Frame", nil, f); c:SetSize(ccw, 170); c:SetPoint("TOPLEFT", col * ccw, y - math.floor((i - 1) / ccols) * 170)
    local S = 96
    local sh = c:CreateTexture(nil, "ARTWORK"); sh:SetTexture(P .. "bond_shield_" .. i); sh:SetSize(S, S); sh:SetPoint("TOP", 0, -4)
    if i == 4 then
      -- 1.0.8 (Taylor: the square glow looked terrible): a glow in the shield's own shape,
      -- breathing slowly like the Exalted ring
      local glow = c:CreateTexture(nil, "BACKGROUND"); glow:SetTexture(P .. "bond_shield_glow"); glow:SetBlendMode("ADD")
      glow:SetVertexColor(1, 0.59, 0.16, 0.85); glow:SetSize(S * 2, S * 2); glow:SetPoint("CENTER", sh, "CENTER", 0, 0)
      local tk = 0
      c:SetScript("OnUpdate", function(_, el) tk = tk + el; glow:SetAlpha(0.7 + 0.3 * math.sin(tk * 2 * math.pi / 2.4)) end)
    end
    local Hs = S / 1.2; local gs = Hs * 0.8085 * 0.25 * (64 / 44)
    for _, gp in ipairs(GEMPOS) do
      local g = c:CreateTexture(nil, "OVERLAY"); g:SetTexture(P .. "bond_gem_" .. i); g:SetSize(gs, gs)
      g:SetPoint("CENTER", sh, "CENTER", gp[1] * Hs, -gp[2] * Hs)
    end
    local lo, hi = (i - 1) * 5 + 1, i * 5
    local nm = fs(c, 13, "GameFontNormal"); nm:SetPoint("TOP", sh, "BOTTOM", 0, -4)
    nm:SetText(((lvl >= lo) and t[3] or RED) .. t[1] .. "|r")
    local b = K.bar(c, t[2][1], t[2][2], t[2][3]); b:SetSize(math.min(150, ccw - 20), 12); b:SetPoint("TOP", nm, "BOTTOM", 0, -4)
    b:Set(math.max(0, math.min(1, (lvl - (lo - 1)) / 5)), "")
    local st = fs(c, 10); st:SetPoint("TOP", b, "BOTTOM", 0, -3); st:SetWidth(ccw - 6)
    -- 1.0.8 (Taylor: "level 2 of 1-5 sounds off"): the tier you're on says how far along it is
    -- and what's left; the others say where they're earned
    if lvl >= hi then st:SetText(GREEN .. "Earned|r")
    elseif lvl >= lo then st:SetText(PALE .. "Level " .. lvl .. " of " .. hi .. "|r\n" .. GOLD .. (hi - lvl) .. " more to earn it|r")
    else st:SetText(GREY .. "Levels " .. lo .. " to " .. hi .. "\nEarned at level " .. hi .. "|r") end
  end
  y = y - math.ceil(#TIERS / ccols) * 170 - 6
  -- your progress
  y = header(f, y, "Your progress", nil, w)
  local nextStand
  for _, r in ipairs(GOOD) do if r[2] > n.stand then nextStand = r; break end end
  local prevStand = 0; for _, r in ipairs(GOOD) do if r[2] <= n.stand then prevStand = r[2] end end
  local nextStar, prevStar = nil, 0
  for _, s in ipairs(STARS) do if s > n.recruits then nextStar = s; break end; prevStar = s end
  local cuLo, cuHi = bondCU(lvl), bondCU(math.min(20, lvl + 1))
  local rowsP = {
    { "Standing", (C.Rep and C.Rep.StandingOf(n.stand) or "") .. "  " .. n.stand, n.stand, prevStand, nextStand and nextStand[2],
      nextStand and (nextStand[2] - n.stand .. " standing until " .. nextStand[1] .. " (" .. nextStand[2] .. ")") or "Exalted: the top ring", "standing_bar", { 1, 0.69, 0.2 }, "standing" },
    { "Recruits", n.recruits .. " player" .. (n.recruits == 1 and "" or "s"), n.recruits, prevStar, nextStar,
      nextStar and ((nextStar - n.recruits) .. " recruit" .. (nextStar - n.recruits == 1 and "" or "s") .. " until the " .. nextStar .. "-recruit star") or "every star earned", "xp_bar", { 0.92, 0.55, 0.27 }, "recruits" },
    { "Bond XP", n.bondWith and ((R.BondText and R.BondText(n.bondCU) or ("level " .. lvl))) or "no partner yet", math.floor(n.bondCU), math.floor(cuLo), lvl < 20 and math.floor(cuHi) or nil,
      n.bondWith and (lvl < 20 and (math.ceil(cuHi - n.bondCU) .. " bond XP until level " .. (lvl + 1)) or "bond full") or "partner up with someone you farm with (their profile: Partner up)", "xp_bar", { 0.27, 0.55, 0.96 }, "bond" },
  }
  for _, r in ipairs(rowsP) do
    local nm = fs(f, nil, "GameFontNormal"); serif(nm, 15); nm:SetJustifyH("LEFT"); nm:SetPoint("TOPLEFT", 6, y)
    nm:SetText(r[1])
    local val = fs(f, 12); val:SetJustifyH("LEFT"); val:SetPoint("LEFT", nm, "RIGHT", 10, 0); val:SetText(PALE .. r[2] .. "|r")
    if r[9] == "bond" and n.bondWith then
      local lk = CreateFrame("Button", nil, f); lk:SetSize(120, 16); lk:SetPoint("LEFT", val, "RIGHT", 8, 0)
      local lt = fs(lk, 12, "GameFontNormal"); lt:SetPoint("LEFT"); lt:SetJustifyH("LEFT"); lt:SetText(GREY .. "with |r" .. BLUE .. n.bondWith .. " >|r")
      lk:SetScript("OnClick", function() if C.Profile and C.Profile.Show then C.Profile.Show(n.bondWith) end end)
    end
    local num = fs(f, 12, "GameFontNormal"); num:SetJustifyH("RIGHT"); num:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
    num:SetText("|cffffffff" .. (r[5] and (r[3] .. " / " .. r[5]) or tostring(r[3])) .. "|r")
    local b = K.bar(f, r[8][1], r[8][2], r[8][3]); b:SetPoint("TOPLEFT", 14, y - 24); b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y - 24); b:SetHeight(16)
    if C.Cos and C.Cos.BarFrame then C.Cos.BarFrame(b, r[7]) end
    b:Set(r[5] and math.max(0, math.min(1, (r[3] - r[4]) / math.max(1, r[5] - r[4]))) or 1, "")
    local need = fs(f, 11); need:SetJustifyH("LEFT"); need:SetPoint("TOPLEFT", 14, y - 48); need:SetText((r[5] and RED or GREEN) .. r[6] .. "|r")
    local det = CreateFrame("Button", nil, f); det:SetSize(70, 16); det:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y - 46)
    local dt = fs(det, 12, "GameFontNormal"); dt:SetPoint("RIGHT"); dt:SetText(BLUE .. "Details >|r")
    local key = r[9]
    det:SetScript("OnClick", function(self) flyout(self, G.RULES[key][1], G.RULES[key][2]) end)
    y = y - 76
  end
  f:SetHeight(-y + 10)
  return f
end

-- Help.lua calls this when the topic is picked: (re)builds the page in the scroll child
function G.Show(child, w)
  if page then page:Hide(); page:SetParent(nil) end
  page = build(child, w)
  page:SetPoint("TOPLEFT", 0, 0)
  page:Show()
  return page:GetHeight()
end
function G.Hide() if page then page:Hide() end; if fly then fly:Hide() end end
