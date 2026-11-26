-- Kina 2.0.15: the profile card's season art, drawn from WoW's own textures until the
-- painted art is ready (Taylor: "The banner should be a giant banner that takes up the
-- entire profile rectangle. The coin hoard should be an ever growing stack of gold (10
-- levels) that piles in around and behind the profile circle. The title and sub-titles
-- like Founder should have fancy plates they sit on." ... "do the best you can to make it
-- super fancy and high budget, lighting, shadows, realistic ish").
--   Banner(card, tier, text)  the season banner hanging behind the whole card (tier 0-8)
--   Hoard(card, ring, level)  a heap of gold around and behind the portrait ring (0-10)
--   Plate(parent, style)      a plate for a name, title or badge
local _, C = ...
local SC = {}
C.Showcase = SC

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a soft round mask
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local SPARK = "Interface\\Cooldown\\star4"

local function tex(parent, layer, sub, file)
  local t = parent:CreateTexture(nil, layer, nil, sub or 0)
  t:SetTexture(file or WHITE)
  return t
end
local function grad(t, r1, g1, b1, r2, g2, b2)
  -- top colour to bottom colour, on clients with either gradient API
  if t.SetGradient and CreateColor then
    pcall(t.SetGradient, t, "VERTICAL", CreateColor(r2, g2, b2, 1), CreateColor(r1, g1, b1, 1))
  elseif t.SetGradientAlpha then
    pcall(t.SetGradientAlpha, t, "VERTICAL", r2, g2, b2, 1, r1, g1, b1, 1)
  else t:SetVertexColor(r1, g1, b1) end
end

------------------------------------------------------------------ the banner
-- 8 tiers: cloth colour, gold trim from tier 3, a crest at the top tiers
SC.BANNER = {
  { 0.30, 0.24, 0.18, trim = false }, { 0.18, 0.34, 0.16, trim = false },
  { 0.16, 0.26, 0.48, trim = true },  { 0.46, 0.08, 0.08, trim = true },
  { 0.34, 0.12, 0.46, trim = true },  { 0.10, 0.18, 0.52, trim = true, crest = true },
  { 0.12, 0.10, 0.08, trim = true, crest = true }, { 0.40, 0.10, 0.52, trim = true, crest = true, glow = true },
}
function SC.Banner(card, tier, label)
  local b = card.kinaBanner
  if not b then
    b = CreateFrame("Frame", nil, card); b:SetFrameLevel(math.max(0, card:GetFrameLevel()))
    b:SetPoint("TOPLEFT", 14, -10); b:SetPoint("BOTTOMRIGHT", -14, 40)
    b.rod = tex(b, "BORDER", 2); b.rod:SetPoint("TOPLEFT", -6, 0); b.rod:SetPoint("TOPRIGHT", 6, 0); b.rod:SetHeight(8)
    grad(b.rod, 0.55, 0.38, 0.12, 0.98, 0.80, 0.38)
    b.knobL = tex(b, "BORDER", 3, DISC); b.knobL:SetSize(16, 16); b.knobL:SetPoint("CENTER", b.rod, "LEFT", 0, 0); b.knobL:SetVertexColor(0.95, 0.75, 0.3)
    b.knobR = tex(b, "BORDER", 3, DISC); b.knobR:SetSize(16, 16); b.knobR:SetPoint("CENTER", b.rod, "RIGHT", 0, 0); b.knobR:SetVertexColor(0.95, 0.75, 0.3)
    b.shadow = tex(b, "BACKGROUND", 0); b.shadow:SetPoint("TOPLEFT", 16, -10); b.shadow:SetPoint("BOTTOMRIGHT", -8, 26); b.shadow:SetColorTexture(0, 0, 0, 0.45)
    b.cloth = tex(b, "BACKGROUND", 1); b.cloth:SetPoint("TOPLEFT", 10, -6); b.cloth:SetPoint("BOTTOMRIGHT", -10, 34)
    b.tail = tex(b, "BACKGROUND", 1); b.tail:SetPoint("CENTER", b.cloth, "BOTTOM", 0, 0)
    b.fold1 = tex(b, "BACKGROUND", 2); b.fold1:SetPoint("TOP", b.cloth, "TOP", -40, 0); b.fold1:SetPoint("BOTTOM", b.cloth, "BOTTOM", -40, 0); b.fold1:SetWidth(18)
    b.fold2 = tex(b, "BACKGROUND", 2); b.fold2:SetPoint("TOP", b.cloth, "TOP", 40, 0); b.fold2:SetPoint("BOTTOM", b.cloth, "BOTTOM", 40, 0); b.fold2:SetWidth(18)
    b.trimL = tex(b, "BORDER", 1); b.trimL:SetPoint("TOPLEFT", b.cloth, "TOPLEFT", 4, 0); b.trimL:SetPoint("BOTTOMLEFT", b.cloth, "BOTTOMLEFT", 4, 0); b.trimL:SetWidth(3)
    b.trimR = tex(b, "BORDER", 1); b.trimR:SetPoint("TOPRIGHT", b.cloth, "TOPRIGHT", -4, 0); b.trimR:SetPoint("BOTTOMRIGHT", b.cloth, "BOTTOMRIGHT", -4, 0); b.trimR:SetWidth(3)
    b.head = tex(b, "BORDER", 0); b.head:SetPoint("TOPLEFT", b.cloth, "TOPLEFT"); b.head:SetPoint("TOPRIGHT", b.cloth, "TOPRIGHT"); b.head:SetHeight(26)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetPoint("CENTER", b.head, "CENTER", 0, -1)
    if C.Cos and C.Cos.Font then C.Cos.Font(b.text, 12, "OUTLINE") end
    b.crest = tex(b, "BORDER", 4, SPARK); b.crest:SetSize(34, 34); b.crest:SetPoint("CENTER", b.cloth, "BOTTOM", 0, 6); b.crest:SetBlendMode("ADD")
    b.glow = tex(b, "BACKGROUND", 0, DISC); b.glow:SetPoint("TOPLEFT", -30, 20); b.glow:SetPoint("BOTTOMRIGHT", 30, -10); b.glow:SetBlendMode("ADD")
    card.kinaBanner = b
  end
  if not tier or tier < 1 then b:Hide(); return b end
  local t = SC.BANNER[math.min(tier, #SC.BANNER)]
  local w = (b:GetWidth() or 280) - 20
  b.tail:SetSize(w / 1.414, w / 1.414); if b.tail.SetRotation then b.tail:SetRotation(math.pi / 4) end
  -- 2.0.19 (Taylor: "the banner is running off the window"): the cloth ends high enough that
  -- its point (half the banner's width below the cloth) stays inside the card
  local lift = 34 + w / 2
  b.cloth:SetPoint("BOTTOMRIGHT", -10, lift)
  b.shadow:SetPoint("BOTTOMRIGHT", -8, lift - 8)
  grad(b.cloth, t[1] * 1.15, t[2] * 1.15, t[3] * 1.15, t[1] * 0.55, t[2] * 0.55, t[3] * 0.55)
  b.tail:SetVertexColor(t[1] * 0.55, t[2] * 0.55, t[3] * 0.55)
  b.fold1:SetColorTexture(0, 0, 0, 0.18); b.fold2:SetColorTexture(1, 1, 1, 0.05)
  b.head:SetColorTexture(t[1] * 0.6, t[2] * 0.6, t[3] * 0.6, 0.95)
  local trim = t.trim and { 0.95, 0.76, 0.32, 0.9 } or { 0.45, 0.36, 0.24, 0.6 }
  b.trimL:SetColorTexture(unpack(trim)); b.trimR:SetColorTexture(unpack(trim))
  b.text:SetText(label or "")
  if t.crest then b.crest:Show(); b.crest:SetVertexColor(1, 0.82, 0.35, 0.9) else b.crest:Hide() end
  if t.glow then b.glow:Show(); b.glow:SetVertexColor(0.8, 0.45, 1, 0.18) else b.glow:Hide() end
  b:Show()
  return b
end

------------------------------------------------------------------ the coin hoard
-- 10 levels: how wide and tall the heap is and how many coins it holds
SC.HOARD = {
  { w = 70, h = 10, n = 18 }, { w = 100, h = 18, n = 40 }, { w = 130, h = 28, n = 70 }, { w = 160, h = 40, n = 110 },
  { w = 190, h = 54, n = 150 }, { w = 215, h = 70, n = 200 }, { w = 240, h = 86, n = 250 }, { w = 262, h = 104, n = 300 },
  { w = 280, h = 122, n = 350 }, { w = 296, h = 142, n = 400 },
}
local function lcg(seed) local s = seed; return function() s = (s * 16807) % 2147483647; return s / 2147483647 end end
function SC.Hoard(card, ring, level)
  local h = card.kinaHoard
  if not h then
    h = { coins = {}, sparks = {} }
    -- behind the ring: its own frame under the ring's; in front: a frame above it
    h.back = CreateFrame("Frame", nil, card); h.front = CreateFrame("Frame", nil, card)
    h.glow = tex(h.back, "BACKGROUND", 0, DISC); h.glow:SetBlendMode("ADD")
    h.shadow = tex(h.back, "BACKGROUND", 1, DISC); h.shadow:SetVertexColor(0, 0, 0, 0.65)
    card.kinaHoard = h
  end
  local base = ring:GetFrameLevel() or 2
  h.back:SetFrameLevel(math.max(0, base - 1)); h.front:SetFrameLevel(math.max(0, base - 1))
  h.back:SetAllPoints(card); h.front:SetAllPoints(card)
  for _, c in ipairs(h.coins) do c:Hide() end
  for _, s in ipairs(h.sparks) do s:Hide() end
  if not level or level < 1 then h.glow:Hide(); h.shadow:Hide(); h.back:Hide(); h.front:Hide(); h.level = 0; return h end
  h.back:Show(); h.front:Show()
  local L = SC.HOARD[math.min(level, #SC.HOARD)]
  local scale = (ring:GetEffectiveScale() or 1) / (card:GetEffectiveScale() or 1)
  local rw = (ring:GetWidth() or 200) * scale
  local W, H = L.w * rw / 200, L.h * rw / 200
  -- the heap sits on the ring's lower edge
  local cx, cyBase = 0, -(rw * 0.50)
  h.glow:ClearAllPoints(); h.glow:SetPoint("CENTER", ring, "CENTER", 0, cyBase / scale + H * 0.2); h.glow:SetSize(W * 1.4, H * 2 + 50)
  h.glow:SetVertexColor(1, 0.75, 0.25, 0.22); h.glow:Show()
  h.shadow:ClearAllPoints(); h.shadow:SetPoint("CENTER", ring, "CENTER", 0, cyBase / scale - 8); h.shadow:SetSize(W * 1.05, 22); h.shadow:Show()
  local rnd = lcg(level * 7919 + 13)
  local pts = {}
  for i = 1, L.n do
    local u = rnd() * 2 - 1
    local top = H * (1 - u * u) ^ 0.8
    local v = rnd() ^ 0.7
    pts[i] = { u * W / 2 + (rnd() - 0.5) * 6, v * top, v, rnd(), rnd(), rnd() }
  end
  -- back to front: higher coins (further back) first
  table.sort(pts, function(a, b) return a[2] > b[2] end)
  local k = 0
  for _, p in ipairs(pts) do
    -- 2.0.15b (Taylor: the coins were "overlaying on top of the profile photo and ring"):
    -- every coin sits behind the ring and its laurels; the heap shows around and below it
    local behind = true
    k = k + 1
    local c = h.coins[k]
    if not c then c = (behind and h.back or h.front):CreateTexture(nil, "ARTWORK"); c:SetTexture(COIN); h.coins[k] = c end
    if c:GetParent() ~= (behind and h.back or h.front) then c:SetParent(behind and h.back or h.front) end
    local s = (7 + p[4] * 5) * rw / 200
    local edge = p[5] < 0.12
    c:SetSize(s * 2, s * 2 * (edge and 0.3 or (0.45 + p[6] * 0.4)))
    if c.SetRotation then c:SetRotation((p[5] - 0.5) * (edge and 2.4 or 0.8)) end
    -- light from above: coins near the top of the heap bright, the base in shade
    local lit = 0.45 + 0.55 * p[3]
    c:SetVertexColor(lit, lit * 0.92, lit * 0.75)
    c:SetDrawLayer("ARTWORK", math.min(7, math.floor((1 - p[2] / math.max(H, 1)) * 7)))
    c:ClearAllPoints(); c:SetPoint("CENTER", ring, "CENTER", p[1] / scale, (cyBase + p[2]) / scale)
    c:Show()
  end
  -- a few glints on the top of the pile
  for i = 1, math.min(8, 2 + level) do
    local s = h.sparks[i]
    if not s then s = h.back:CreateTexture(nil, "OVERLAY"); s:SetTexture(SPARK); s:SetBlendMode("ADD"); h.sparks[i] = s end
    local p = pts[math.floor(#pts * (i / 9)) + 1] or pts[1]
    s:SetSize(14, 14); s:ClearAllPoints(); s:SetPoint("CENTER", ring, "CENTER", p[1] / scale, (cyBase + p[2] + 2) / scale)
    s.phase = i * 0.77; s:Show()
  end
  if not h.ticker then
    h.ticker = CreateFrame("Frame", nil, h.front)
    h.ticker:SetScript("OnUpdate", function(self, el)
      self.t = (self.t or 0) + el
      for _, s in ipairs(h.sparks) do
        if s:IsShown() then s:SetAlpha(math.max(0, math.sin(self.t * 1.6 + (s.phase or 0))) ^ 3 * 0.9) end
      end
    end)
  end
  h.level = level
  return h
end

------------------------------------------------------------------ plates
-- style: "name" (gold), "title" (quality colour), "badge" (blue)
SC.PLATE = { name = { 0.16, 0.11, 0.05, 0.98, 0.78, 0.32 }, title = { 0.06, 0.12, 0.05, 0.43, 0.9, 0.47 },
  badge = { 0.05, 0.09, 0.16, 0.47, 0.75, 1 } }
-- 2.0.20 (Taylor, on the mock: "i like the plates and rings a little better", but "the new text
-- is harder to read"): a forged plate: a lit metal rim (bronze; silver for the badge) with
-- pointed ends and rivets, an inset face with an inner shadow, and a drop shadow under it.
-- The words keep their bright colour with a soft shadow, not a dark outline.
SC.RIM = { name = { 0.95, 0.74, 0.40, 0.36, 0.20, 0.07 }, title = { 0.95, 0.74, 0.40, 0.36, 0.20, 0.07 },
  badge = { 0.92, 0.95, 0.99, 0.30, 0.34, 0.42 } }
function SC.Plate(parent, style, w, h)
  w, h = w or 220, h or 28
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(w, h)
  local c = SC.PLATE[style] or SC.PLATE.name
  local m = SC.RIM[style] or SC.RIM.name
  local tip = h * 0.72
  -- drop shadow (the plate's shape, a little lower and right)
  p.shadow = tex(p, "BACKGROUND", 0); p.shadow:SetPoint("TOPLEFT", 3, -4); p.shadow:SetPoint("BOTTOMRIGHT", 3, -4)
  p.shadow:SetColorTexture(0, 0, 0, 0.55)
  -- the rim and its pointed ends
  p.rim = tex(p, "BORDER", 0); p.rim:SetAllPoints(); grad(p.rim, m[1], m[2], m[3], m[4], m[5], m[6])
  p.ends = {}
  for i, side in ipairs({ "LEFT", "RIGHT" }) do
    local sh = tex(p, "BACKGROUND", 1); sh:SetSize(tip, tip); sh:SetPoint("CENTER", p, side, 3, -4)
    if sh.SetRotation then sh:SetRotation(math.pi / 4) end
    sh:SetColorTexture(0, 0, 0, 0.5)
    local d = tex(p, "BORDER", 1); d:SetSize(tip, tip); d:SetPoint("CENTER", p, side, 0, 0)
    if d.SetRotation then d:SetRotation(math.pi / 4) end
    grad(d, m[1] * 0.9, m[2] * 0.9, m[3] * 0.9, m[4], m[5], m[6])
    -- a rivet on each point: a lit dome
    local rv = tex(p, "OVERLAY", 3, DISC); rv:SetSize(math.max(6, h * 0.26), math.max(6, h * 0.26))
    rv:SetPoint("CENTER", p, side, side == "LEFT" and -tip * 0.18 or tip * 0.18, 0)
    rv:SetVertexColor(m[4] * 1.3, m[5] * 1.3, m[6] * 1.3)
    local hl = tex(p, "OVERLAY", 4, DISC); hl:SetSize(math.max(3, h * 0.11), math.max(3, h * 0.11))
    hl:SetPoint("CENTER", rv, "CENTER", -1, 1); hl:SetVertexColor(1, 0.97, 0.85, 0.9)
    p.ends[i] = d
  end
  -- the bevel: light along the top of the rim, dark along the bottom
  p.bevelT = tex(p, "BORDER", 2); p.bevelT:SetPoint("TOPLEFT", 0, 0); p.bevelT:SetPoint("TOPRIGHT", 0, 0); p.bevelT:SetHeight(1)
  p.bevelT:SetColorTexture(1, 0.95, 0.8, 0.7)
  p.bevelB = tex(p, "BORDER", 2); p.bevelB:SetPoint("BOTTOMLEFT", 0, 0); p.bevelB:SetPoint("BOTTOMRIGHT", 0, 0); p.bevelB:SetHeight(1)
  p.bevelB:SetColorTexture(0, 0, 0, 0.7)
  -- the inset face, its accent edge and inner shadow
  local inset = math.max(3, math.floor(h * 0.13))
  p.edge = tex(p, "ARTWORK", 0); p.edge:SetPoint("TOPLEFT", inset - 1, -(inset - 1)); p.edge:SetPoint("BOTTOMRIGHT", -(inset - 1), inset - 1)
  p.edge:SetColorTexture(c[4] * 0.55, c[5] * 0.55, c[6] * 0.55, 1)
  p.face = tex(p, "ARTWORK", 1); p.face:SetPoint("TOPLEFT", inset, -inset); p.face:SetPoint("BOTTOMRIGHT", -inset, inset)
  grad(p.face, math.min(1, c[1] * 1.8 + 0.03), math.min(1, c[2] * 1.8 + 0.03), math.min(1, c[3] * 1.8 + 0.03), c[1] * 0.55, c[2] * 0.55, c[3] * 0.55)
  p.inner = tex(p, "ARTWORK", 2); p.inner:SetPoint("TOPLEFT", p.face, "TOPLEFT"); p.inner:SetPoint("TOPRIGHT", p.face, "TOPRIGHT"); p.inner:SetHeight(2)
  p.inner:SetColorTexture(0, 0, 0, 0.55)
  p.sheen = tex(p, "ARTWORK", 3); p.sheen:SetPoint("TOPLEFT", p.face, "TOPLEFT", 0, -2); p.sheen:SetPoint("TOPRIGHT", p.face, "TOPRIGHT", 0, -2)
  p.sheen:SetHeight(math.max(2, (h - 2 * inset) * 0.35)); p.sheen:SetColorTexture(1, 1, 1, 0.05)
  p.lip = tex(p, "ARTWORK", 3); p.lip:SetPoint("BOTTOMLEFT", p.face, "BOTTOMLEFT"); p.lip:SetPoint("BOTTOMRIGHT", p.face, "BOTTOMRIGHT"); p.lip:SetHeight(1)
  p.lip:SetColorTexture(1, 1, 1, 0.1)
  p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.text:SetPoint("LEFT", 10, 0); p.text:SetPoint("RIGHT", -10, 0)
  if p.text.SetWordWrap then p.text:SetWordWrap(false) end
  if p.text.SetShadowOffset then p.text:SetShadowOffset(1, -1); p.text:SetShadowColor(0, 0, 0, 0.9) end
  function p:SetLabel(t2) self.text:SetText(t2 or ""); if t2 and t2 ~= "" then self:Show() else self:Hide() end end
  return p
end
