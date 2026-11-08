-- Kina: the iron look (1.1.0). Draws Kina's windows, buttons, tiles, tabs and chips
-- with the LOCKED UI pieces (handoff Revs 58-64): A-30 window frame, A-31 buttons
-- (4 states), A-32 stat tile, A-33 header bar, A-34 tabs, A-35 chip, A-36 row.
-- The art is only resized for the game (Media/UI/*.tga, SkinData.lua), never redrawn.
-- 9-slice rules (Rev 59): corners kept whole, edges TILED from the middle 30-70% of
-- each side (never stretched), centre stretched. Settings > "Kina iron look" turns it
-- off (the classic look); the switch applies after a /reload.
local _, C = ...
local S = {}
C.Skin = S

local PATH = "Interface\\AddOns\\Kina\\Media\\UI\\"

function S.On()
  return C.settings ~= nil and C.settings.look ~= "classic" and C.SkinData ~= nil and C.SkinData.frame ~= nil
end

------------------------------------------------------------------ 9-slice
local Nine = {}
Nine.__index = Nine

-- piece: a SkinData name. border: in-game size of the top edge (or, for a strip with
-- no top/bottom inset, the strip's height). opts: layer, sub, outset, noCenter, alpha,
-- owner (the frame that holds the textures, when it isn't the one they're measured on:
-- so a strip can sit under its window's text)
function S.Nine(parent, piece, border, opts)
  local n = setmetatable({ parent = parent, piece = piece, border = border, opts = opts or {}, pool = {}, used = 0 }, Nine)
  if parent.HookScript then
    parent:HookScript("OnSizeChanged", function() n:Layout() end)
    parent:HookScript("OnShow", function() n:Layout() end)
  end
  n:Layout()
  return n
end

function Nine:get()
  self.used = self.used + 1
  local t = self.pool[self.used]
  if not t then
    t = (self.opts.owner or self.parent):CreateTexture(nil, self.opts.layer or "BACKGROUND", nil, self.opts.sub or 0)
    self.pool[self.used] = t
  end
  t:ClearAllPoints()
  t:SetTexture(PATH .. self.piece)
  if self.opts.alpha then t:SetAlpha(self.opts.alpha) end
  t:Show()
  return t
end

-- x, y from the top-left of the drawn area (in game units); u/v in texture pixels
function Nine:place(x, y, w, h, u0, u1, v0, v1)
  if w <= 0.01 or h <= 0.01 then return end
  local d, o = C.SkinData[self.piece], self.opts.outset or 0
  local t = self:get()
  t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x - o, -(y - o))
  t:SetSize(w, h)
  t:SetTexCoord(u0 / d.tw, u1 / d.tw, v0 / d.th, v1 / d.th)
end

-- a run of tiles along an edge: copies of the source's middle 30-70%, the last one cut short
function Nine:run(horiz, from, to, fixedPos, thick, a0, a1, b0, b1, k)
  -- the tiled part: the middle 30-70% of the edge, or the piece's own clean range (mid)
  local d = C.SkinData[self.piece]
  local m0, m1 = 0.3, 0.7
  if d and d.mid then m0, m1 = d.mid[1], d.mid[2] end
  local srcLen = (a1 - a0) * (m1 - m0)
  local s0 = a0 + (a1 - a0) * m0
  local seg = srcLen * k
  if seg < 1 then return end
  local pos = from
  local guard = 0
  while pos < to - 0.01 and guard < 200 do
    guard = guard + 1
    local len = math.min(seg, to - pos)
    local frac = len / seg
    if horiz then self:place(pos, fixedPos, len, thick, s0, s0 + srcLen * frac, b0, b1)
    else self:place(fixedPos, pos, thick, len, b0, b1, s0, s0 + srcLen * frac) end
    pos = pos + len
  end
end

function Nine:Layout()
  local d = C.SkinData and C.SkinData[self.piece]
  if not d then return end
  local o = self.opts.outset or 0
  local W = (self.parent:GetWidth() or 0) + 2 * o
  local H = (self.parent:GetHeight() or 0) + 2 * o
  -- nothing changed since the last layout: keep it (buttons are shown and hidden a lot)
  local key = self.piece .. ":" .. math.floor(W * 4 + 0.5) .. ":" .. math.floor(H * 4 + 0.5) .. ":" .. o
  if key == self.key then return end
  self.key = key
  self.used = 0
  if W > 1 and H > 1 then
    if not d.inset then
      -- stretched whole (the oval chip)
      self:place(0, 0, W, H, 0, d.w, 0, d.h)
    else
      local l, r, t, b = d.inset[1], d.inset[2], d.inset[3], d.inset[4]
      local k
      if t == 0 and b == 0 then k = H / d.h
      elseif l == 0 and r == 0 then k = W / d.w
      else k = self.border / math.max(t, b) end
      local cl, cr, ct, cb = l * k, r * k, t * k, b * k
      -- never let the corners overlap on a small frame
      if cl + cr > W then local f = W / (cl + cr); cl, cr = cl * f, cr * f end
      if ct + cb > H then local f = H / (ct + cb); ct, cb = ct * f, cb * f end
      local x1, x2, y1, y2 = l, d.w - r, t, d.h - b
      local midW, midH = W - cl - cr, H - ct - cb
      if l == 0 and r == 0 then
        -- a vertical strip (the scrollbar track): end caps whole, middle tiled
        self:place(0, 0, W, ct, 0, d.w, 0, y1)
        self:place(0, H - cb, W, cb, 0, d.w, y2, d.h)
        self:run(false, ct, H - cb, 0, W, y1, y2, 0, d.w, k)
      elseif t > 0 then
        self:place(0, 0, cl, ct, 0, x1, 0, y1)
        self:place(W - cr, 0, cr, ct, x2, d.w, 0, y1)
        self:run(true, cl, W - cr, 0, ct, x1, x2, 0, y1, k)
      end
      if b > 0 and not (l == 0 and r == 0) then
        self:place(0, H - cb, cl, cb, 0, x1, y2, d.h)
        self:place(W - cr, H - cb, cr, cb, x2, d.w, y2, d.h)
        self:run(true, cl, W - cr, H - cb, cb, x1, x2, y2, d.h, k)
      end
      if l == 0 and r == 0 then
        -- (vertical strip: done above)
      elseif t == 0 and b == 0 then
        -- a horizontal strip: end caps whole, middle tiled
        self:place(0, 0, cl, H, 0, x1, 0, d.h)
        self:place(W - cr, 0, cr, H, x2, d.w, 0, d.h)
        self:run(true, cl, W - cr, 0, H, x1, x2, 0, d.h, k)
      else
        self:run(false, ct, H - cb, 0, cl, y1, y2, 0, x1, k)
        self:run(false, ct, H - cb, W - cr, cr, y1, y2, x2, d.w, k)
        if not self.opts.noCenter then self:place(cl, ct, midW, midH, x1, x2, y1, y2) end
      end
    end
  end
  for i = self.used + 1, #self.pool do self.pool[i]:Hide() end
end

function Nine:SetPiece(piece)
  if piece == self.piece then return end
  local a, b = C.SkinData[self.piece], C.SkinData[piece]
  self.piece = piece
  if a and b and a.tw == b.tw and a.th == b.th and a.w == b.w and a.h == b.h and self.key then
    -- same size and slices (the 4 button states, the 3 tabs): just swap the texture
    for i = 1, self.used do self.pool[i]:SetTexture(PATH .. piece) end
    self.key = piece .. self.key:match("(:.*)$")
    return
  end
  self:Layout()
end

function Nine:Show(on) for i = 1, self.used do if on then self.pool[i]:Show() else self.pool[i]:Hide() end end end

------------------------------------------------------------------ pieces
-- the window frame: drawn on its own frame above the content (clicks pass through);
-- the gold trim sits just inside the window's edge
function S.Frame(f, border, bg)
  if not S.On() or f.kinaFrame then return end
  if bg ~= false then
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    -- 1.5.5: a textured dark background (leather and stone), still solid
    fill:SetTexture("Interface\\AddOns\\Kina\\Media\\Cos\\bg_texture"); fill:SetVertexColor(1, 1, 1, 1)
    f.kinaFill = fill
  end
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints(f)
  holder:SetFrameLevel(f:GetFrameLevel() + 30)
  if holder.EnableMouse then holder:EnableMouse(false) end
  f.kinaFrame = S.Nine(holder, "frame", border, { layer = "ARTWORK", outset = math.floor(border * 0.7), noCenter = true })
  return f.kinaFrame
end

local function hideRegions(b)
  for _, k in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
    if b[k] and b[k].SetAlpha then b[k]:SetAlpha(0) end
  end
  for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
    local tex = b[get] and b[get](b)
    if tex and tex.SetAlpha then tex:SetAlpha(0) end
  end
end

-- a button: 4 states (normal / hover / pressed / disabled)
-- 1.5.5 (Taylor: "all bars and buttons get the same pass"): one look everywhere: a dark
-- bronze fill with a soft vertical gradient, a fine gold rim, a light top edge; brighter
-- on hover, gold-filled when selected (tabs and page buttons), dim when disabled.
local BTN = { normal = { 0.13, 0.10, 0.06, 0.07, 0.055, 0.035 }, over = { 0.22, 0.17, 0.09, 0.12, 0.09, 0.05 },
  down = { 0.06, 0.05, 0.03, 0.10, 0.08, 0.045 }, sel = { 0.36, 0.27, 0.10, 0.20, 0.15, 0.06 } }
local function grad(t, c)
  if t.SetGradient and CreateColor then
    pcall(t.SetGradient, t, "VERTICAL", CreateColor(c[4], c[5], c[6], 0.96), CreateColor(c[1], c[2], c[3], 0.96))
  else t:SetColorTexture(c[1], c[2], c[3], 0.96) end
end
function S.Button(b, border)
  if not S.On() or not b or b.kinaSkin then return end
  hideRegions(b)
  local fill = b:CreateTexture(nil, "BACKGROUND", nil, 1); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
  fill:SetTexture("Interface\\Buttons\\WHITE8X8")
  local rim = {}
  for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = b:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.82, 0.59, 0.19, 0.95)
    t:SetPoint(p[1]); t:SetPoint(p[2]); if p[3] then t:SetHeight(1) else t:SetWidth(1) end
    rim[i] = t
  end
  local shine = b:CreateTexture(nil, "BORDER", nil, 1); shine:SetPoint("TOPLEFT", 2, -2); shine:SetPoint("TOPRIGHT", -2, -2); shine:SetHeight(1)
  shine:SetColorTexture(1, 0.83, 0.49, 0.22)
  b.kinaSkin = { fill = fill, rim = rim }
  local function state()
    hideRegions(b)
    local c = BTN.normal
    if b.kinaSel then c = BTN.sel elseif b.kinaDown then c = BTN.down elseif b.kinaOver then c = BTN.over end
    grad(fill, c)
    local bright = (b.kinaOver or b.kinaSel) and 1 or 0.8
    for _, t in ipairs(rim) do t:SetColorTexture(1 * bright, 0.72 * bright, 0.21 * bright, 0.95) end
    local fs = b.GetFontString and b:GetFontString()
    local off = b.IsEnabled and not b:IsEnabled()
    b:SetAlpha(off and 0.45 or 1)
    if fs then if b.kinaSel then fs:SetTextColor(1, 0.74, 0.19) else fs:SetTextColor(0.97, 0.83, 0.56) end end
  end
  b.kinaState = state
  b:HookScript("OnEnter", function() b.kinaOver = true; state() end)
  b:HookScript("OnLeave", function() b.kinaOver = false; b.kinaDown = false; state() end)
  b:HookScript("OnMouseDown", function() b.kinaDown = true; state() end)
  b:HookScript("OnMouseUp", function() b.kinaDown = false; state() end)
  pcall(b.HookScript, b, "OnEnable", state)
  pcall(b.HookScript, b, "OnDisable", state)
  if hooksecurefunc then
    pcall(hooksecurefunc, b, "LockHighlight", function() b.kinaSel = true; state() end)
    pcall(hooksecurefunc, b, "UnlockHighlight", function() b.kinaSel = nil; state() end)
  end
  b:HookScript("OnShow", state)
  state()
end

-- 1.2.0: a big panel: the tray's iron border (A-32) on a flat dark fill (its recessed
-- centre only works small; stretched to a panel it looked like a pit)
function S.Panel(f, border)
  if not S.On() or f.kinaSkin then return end
  -- 1.5.5: a dark glass panel over the textured window, fine gold rim, light top line
  local fill = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
  fill:SetColorTexture(0.035, 0.03, 0.025, 0.66)
  for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.49, 0.37, 0.14, 1)
    t:SetPoint(p[1]); t:SetPoint(p[2]); if p[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  local top = f:CreateTexture(nil, "BORDER", nil, 1); top:SetPoint("TOPLEFT", 8, -2); top:SetPoint("TOPRIGHT", -8, -2); top:SetHeight(1)
  top:SetColorTexture(0.89, 0.66, 0.25, 0.55)
  f.kinaSkin = { fill = fill }
end

-- a stat tile (the recessed tray)
function S.Tile(t, border)
  if not S.On() or t.kinaSkin then return end
  t.kinaSkin = S.Nine(t, "tile", border or 6, { layer = "BACKGROUND", sub = 2 })
end

-- a horizontal bar (header A-33, row divider A-36) across a frame
-- (the textures belong to the parent, so its text stays on top; the holder only sizes them)
function S.Strip(parent, piece, height, layer)
  if not S.On() then return end
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(height)
  if holder.EnableMouse then holder:EnableMouse(false) end
  holder.nine = S.Nine(holder, piece, height, { layer = layer or "BORDER", owner = parent })
  return holder
end

-- the oval status chip: the colour moves from the background to the text
function S.Chip(chip)
  if not S.On() or chip.kinaSkin then return end
  chip.kinaSkin = S.Nine(chip, "chip", chip:GetHeight() or 18, { layer = "BACKGROUND" })
  if chip.bg then chip.bg:Hide() end
end
function S.ChipColor(chip, r, g, b)
  if not (chip and chip.kinaSkin) then return false end
  -- lighten the state colour so it reads on dark iron
  local function up(v) return math.min(1, 0.35 + v * 1.6) end
  if chip.text then chip.text:SetTextColor(up(r), up(g), up(b)) end
  return true
end

-- a tab: active (raised, bright) or inactive (dimmed, 4 px lower)
function S.Tab(b)
  if not S.On() or b.kinaTab then return end
  hideRegions(b)
  b.kinaTab = S.Nine(b, "tab_dim", 9, { layer = "BACKGROUND" })
  b:HookScript("OnShow", function() hideRegions(b) end)
end
function S.TabActive(b, on)
  if not (b and b.kinaTab) then return end
  b.kinaTab:SetPiece(on and "tab_active" or "tab_dim")
  b.kinaTab.opts.outset = on and 2 or 0
  b.kinaTab:Layout() -- (the layout key includes the outset)
end

-- the Blizzard window template's own art, hidden under the iron frame
function S.HideTemplate(f)
  if not S.On() then return end
  for _, k in ipairs({ "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "Inset" }) do
    local r = f[k]
    if r then if r.Hide then r:Hide() end end
  end
  if f.Inset then f.Inset:Hide() end
end

-- 1.1.1: the corner resize grip as an iron knob (A-37), no gold box
function S.Grip(grip)
  if not S.On() then return false end
  grip:SetSize(18, 18)
  -- inside the frame's corner, above the frame (which is drawn over the window's edge)
  local p = grip:GetParent()
  if p then
    -- 1.2.0: on the frame's bottom-right rivet (grab the rivet to resize), clear of the buttons
    grip:ClearAllPoints(); grip:SetPoint("CENTER", p, "BOTTOMRIGHT", 3, -3)
    grip:SetFrameLevel(p:GetFrameLevel() + 40)
  end
  local t = grip:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(); t:SetTexture(PATH .. "scroll_knob")
  local d = C.SkinData.scroll_knob
  t:SetTexCoord(0, d.w / d.tw, 0, d.h / d.th)
  t:SetAlpha(0.75)
  grip.kinaKnob = t
  grip:HookScript("OnEnter", function() t:SetAlpha(1) end)
  grip:HookScript("OnLeave", function() t:SetAlpha(0.75) end)
  return true
end

-- 1.1.1: a vertical scrollbar (A-37 track and knob). onScroll(value) gets whole steps.
function S.Scrollbar(parent, onScroll)
  local sb = CreateFrame("Slider", nil, parent)
  sb:SetWidth(16)
  if sb.SetOrientation then sb:SetOrientation("VERTICAL") end
  sb:SetMinMaxValues(0, 0); sb:SetValue(0)
  if sb.SetValueStep then sb:SetValueStep(1) end
  if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(true) end
  local thumb = sb:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(18, 18)
  if S.On() then
    sb.track = S.Nine(sb, "scroll_track", 16, { layer = "BACKGROUND" })
    thumb:SetTexture(PATH .. "scroll_knob")
    local d = C.SkinData.scroll_knob
    thumb:SetTexCoord(0, d.w / d.tw, 0, d.h / d.th)
  else
    local bg = sb:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
    thumb:SetColorTexture(1, 0.71, 0.15, 0.85); thumb:SetSize(12, 24)
  end
  if sb.SetThumbTexture then sb:SetThumbTexture(thumb) end
  sb:SetScript("OnValueChanged", function(self, v)
    if self.kinaQuiet then return end
    onScroll(math.floor((v or 0) + 0.5))
  end)
  -- set range and position without calling back
  function sb:KinaSet(maxV, v)
    self.kinaQuiet = true
    self:SetMinMaxValues(0, math.max(0, maxV))
    self:SetValue(math.max(0, math.min(maxV, v)))
    self.kinaQuiet = false
    if maxV > 0 then self:Show() else self:Hide() end
  end
  return sb
end

-- 1.1.1: strip a Blizzard window template down to nothing: every texture it made and
-- every child frame except the close button (called before Kina adds its own parts)
function S.StripTemplate(f)
  if not S.On() then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then r:Hide() end
  end
  for _, ch in ipairs({ f:GetChildren() }) do
    if ch ~= f.CloseButton then ch:Hide() end
  end
  if f.TitleText then f.TitleText:Hide() end
end
