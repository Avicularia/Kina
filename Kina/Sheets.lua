-- Kina: the You tab (a character sheet) and the Ledger's Debts page (1.2.0).
-- Both are panels inside the main window, shown instead of the row list: a tab's
-- builder returns opts.panel = "you" / "debts" and UI.lua's Refresh calls C.ShowPanel.
-- Real buttons (iron look), not clickable text.
local _, C = ...

local panels, builders = {}, {}
local GOLD, GREY, GREEN, ORANGE = "|cffffd100", "|cff9d9d9d", "|cff7CFC00", "|cffff8040"

local function ui() return C.UI end
local function money(v) return (v and v >= 1) and C.Money(math.floor(v + 0.5)) or (GREY .. "-|r") end
local function text(parent, font, justify)
  local fs = C.Text(parent, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
local function iron() return C.Skin and C.Skin.On() end

-- a framed area: the iron tile, or a faint box in the classic look
local function box(parent)
  local f = CreateFrame("Frame", nil, parent)
  if iron() then C.Skin.Panel(f, 6)
  else local t = f:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.05) end
  return f
end

-- a progress bar: a dark tray with a coloured fill and a centred label
local function bar(parent, r, g, b)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(18)
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
  local fill = f:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMLEFT", 2, 2)
  fill:SetColorTexture(r, g, b, 0.85)
  if fill.SetGradient and CreateColor then pcall(fill.SetGradient, fill, "VERTICAL", CreateColor(r * 0.55, g * 0.55, b * 0.55, 0.9), CreateColor(r, g, b, 0.9)) end
  local edge = {}
  for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.85, 0.66, 0.25, 0.8)
    t:SetPoint(p[1]); t:SetPoint(p[2]); if p[3] then t:SetHeight(1) else t:SetWidth(1) end
    edge[#edge + 1] = t
  end
  f.label = text(f, "GameFontHighlightSmall", "CENTER"); f.label:SetPoint("CENTER", 0, 0)
  function f:Set(frac, label)
    frac = math.max(0, math.min(1, frac or 0))
    local w = (self:GetWidth() or 100) - 4
    if frac <= 0.001 then fill:Hide() else fill:Show(); fill:SetWidth(math.max(1, w * frac)) end
    self.label:SetText(label or "")
  end
  return f
end

local function heading(parent, s)
  local t = text(parent, "GameFontNormal")
  t:SetText(s)
  return t
end

function C.ShowPanel(name)
  local u = ui()
  if not (u and u.frame) then return end
  if name and not panels[name] and builders[name] then
    local p = CreateFrame("Frame", nil, u.frame)
    p:SetPoint("TOPLEFT", u.frame, "TOPLEFT", 16, -(u.panelTop or 92))
    p:SetPoint("BOTTOMRIGHT", u.frame, "BOTTOMRIGHT", -16, 44)
    builders[name](p)
    panels[name] = p
  end
  for n, p in pairs(panels) do
    if n == name then
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", u.frame, "TOPLEFT", 16, -(u.panelTop or 92))
      p:SetPoint("BOTTOMRIGHT", u.frame, "BOTTOMRIGHT", -16, 44)
      p:Show(); if p.refresh then pcall(p.refresh) end
    else p:Hide() end
  end
end

------------------------------------------------------------------ You: a character sheet
builders.you = function(p)
  -- left: who you are
  -- 1.4.4: a proper character card: a big ringed portrait (the standing ring, its title
  -- and glow), the Mentor Star or leaf crowning it, the Kina level plate at its foot
  local TOP_H = C.Cos and 170 or 128
  local idBox = box(p); idBox:SetPoint("TOPLEFT", 0, 0); idBox:SetSize(300, TOP_H)
  local portraitBox = CreateFrame("Frame", nil, idBox)
  if C.Cos then portraitBox:SetPoint("TOPLEFT", 30, -44); portraitBox:SetSize(80, 80) else portraitBox:SetPoint("TOPLEFT", 12, -12); portraitBox:SetSize(80, 80) end
  if iron() and not C.Cos then C.Skin.Tile(portraitBox, 6) end
  local portrait = portraitBox:CreateTexture(nil, "ARTWORK"); portrait:SetPoint("TOPLEFT", 7, -7); portrait:SetPoint("BOTTOMRIGHT", -7, 7)
  local cos -- 1.4.0: standing ring, level plate, star/leaf (built on first refresh)
  local name = text(idBox, "GameFontNormalLarge"); name:SetPoint("TOPLEFT", portraitBox, "TOPRIGHT", C.Cos and 30 or 12, 6); name:SetWidth(150)
  local line = text(idBox, "GameFontHighlight"); line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5); line:SetWidth(150)
  local standT = text(idBox, "GameFontNormal"); standT:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -6); standT:SetWidth(150)
  local lvl = text(idBox, "GameFontNormalLarge"); lvl:SetPoint("TOPLEFT", standT, "BOTTOMLEFT", 0, -6); lvl:SetWidth(150)
  local share = text(idBox, "GameFontHighlightSmall")
  if C.Cos then share:SetPoint("BOTTOMLEFT", idBox, "BOTTOMLEFT", 140, 12); share:SetWidth(150) else share:SetPoint("BOTTOMLEFT", 14, 14); share:SetWidth(272) end

  -- middle: Kina level and standing
  local prog = box(p); prog:SetPoint("TOPLEFT", idBox, "TOPRIGHT", 12, 0); prog:SetPoint("RIGHT", p, "RIGHT", 0, 0); prog:SetHeight(TOP_H)
  -- heading and bar on one line each: "Kina level  I" [bar]
  local h1 = heading(prog, "Kina level"); h1:SetPoint("TOPLEFT", 16, -14)
  local xpBar = bar(prog, 0.85, 0.65, 0.15); xpBar:SetPoint("TOPLEFT", 16, -34); xpBar:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local xpNote = text(prog, "GameFontHighlightSmall"); xpNote:SetPoint("TOPLEFT", xpBar, "BOTTOMLEFT", 0, -7); xpNote:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local h2 = heading(prog, "Standing"); h2:SetPoint("TOPLEFT", 16, -72)
  local stBar = bar(prog, 0.30, 0.62, 0.95); stBar:SetPoint("TOPLEFT", 16, -92); stBar:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local stNote = text(prog, "GameFontHighlightSmall"); stNote:SetPoint("TOPLEFT", stBar, "BOTTOMLEFT", 0, -7); stNote:SetPoint("RIGHT", prog, "RIGHT", -16, 0)

  -- bottom left: professions
  local profBox = box(p); profBox:SetPoint("TOPLEFT", idBox, "BOTTOMLEFT", 0, -12); profBox:SetWidth(300); profBox:SetPoint("BOTTOM", p, "BOTTOM", 0, 0)
  local h3 = heading(profBox, "Professions"); h3:SetPoint("TOPLEFT", 16, -14)
  local profBars = {}
  for i = 1, 4 do
    local ic = profBox:CreateTexture(nil, "ARTWORK"); ic:SetSize(26, 26); ic:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 30)
    local lb = text(profBox, "GameFontHighlightSmall"); lb:SetPoint("TOPLEFT", 44, -36 - (i - 1) * 30); lb:SetWidth(240)
    local b = bar(profBox, 0.35, 0.75, 0.30); b:SetPoint("TOPLEFT", lb, "BOTTOMLEFT", 0, -3); b:SetWidth(240); b:SetHeight(14)
    profBars[i] = { lb, b, ic }
  end
  local profNone = text(profBox, "GameFontHighlightSmall"); profNone:SetPoint("TOPLEFT", 16, -38); profNone:SetWidth(268)

  -- bottom right: your record
  local rec = box(p); rec:SetPoint("TOPLEFT", profBox, "TOPRIGHT", 12, 0); rec:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  local h4 = heading(rec, "Your record"); h4:SetPoint("TOPLEFT", 16, -14)
  -- 1.5.0: vouch for someone from a recent farm
  local vb = CreateFrame("Button", nil, rec, "UIPanelButtonTemplate"); vb:SetSize(130, 22); vb:SetPoint("TOPRIGHT", -14, -10)
  vb:SetText("Commend someone"); vb:SetScript("OnClick", function(self) if C.Vouch then C.Vouch.Picker(self) end end)
  -- 1.5.1: look at someone else's Kina profile (your party first)
  local pb = CreateFrame("Button", nil, rec, "UIPanelButtonTemplate"); pb:SetSize(110, 22); pb:SetPoint("RIGHT", vb, "LEFT", -6, 0)
  pb:SetText("Party profiles"); pb:SetScript("OnClick", function(self) if C.Profile then C.Profile.Picker(self) end end)
  -- two columns of four, so the record fits the smallest window
  local recL, recR = {}, {}
  local colA = CreateFrame("Frame", nil, rec); colA:SetPoint("TOPLEFT", 16, -36); colA:SetPoint("BOTTOMRIGHT", rec, "BOTTOM", -10, 10)
  local colB = CreateFrame("Frame", nil, rec); colB:SetPoint("TOPLEFT", rec, "TOP", 10, -36); colB:SetPoint("BOTTOMRIGHT", -16, 10)
  for i = 1, 10 do -- 1.5.0: two columns of five (labels were being cut off)
    local col = i <= 5 and colA or colB
    local y = -((i - 1) % 5) * 24
    local l = text(col, "GameFontHighlightSmall"); l:SetPoint("TOPLEFT", 0, y)
    local r = text(col, "GameFontHighlight", "RIGHT"); r:SetPoint("TOPRIGHT", 0, y)
    l:SetPoint("RIGHT", r, "LEFT", -6, 0)
    recL[i], recR[i] = l, r
  end

  p.refresh = function()
    local me = C.YouProfile and C.YouProfile() or { name = UnitName("player"), level = UnitLevel("player"), class = "?", profs = {} }
    if SetPortraitTexture then pcall(SetPortraitTexture, portrait, "player") end
    name:SetText(me.name or "You")
    line:SetText(string.format("Level %s %s", tostring(me.level or "?"), me.className or "?"))
    local m = C.Rep and C.Rep.Mine() or { level = 1, xp = 0, ok = true }
    lvl:SetText(m.ok and (GOLD .. "Kina " .. C.Rep.Roman(m.level) .. "|r") or (ORANGE .. "Kina log damaged|r"))
    if C.Cos then
      if not cos then
        cos = C.Cos.Portrait(portraitBox, portrait); C.Cos.Font(lvl, 17, "OUTLINE"); C.Cos.Font(name, 19, "OUTLINE")
        cos.xpF = C.Cos.BarFrame(xpBar, "xp_bar"); cos.stF = C.Cos.BarFrame(stBar, "standing_bar")
        -- 1.4.2: test pickers beside the pieces (preview only)
        local pv = C.Cos.preview
        local function redo() if p.refresh then p.refresh() end end
        local rings = {}
        for _, st in ipairs({ "Unproven", "Vouched", "Reliable", "Trusted", "Honored", "Revered", "Exalted", "Delinquent" }) do rings[#rings + 1] = { st .. (st == "Delinquent" and " / Disgraced" or ""), st } end
        table.insert(rings, 1, { "(my real standing)", false })
        local opts = {}
        for _, x in ipairs(rings) do opts[#opts + 1] = { "Ring: " .. x[1], { "ring", x[2] } } end
        for _, x in ipairs({ { "(real)", false }, { "none", "none" }, { "Starter leaf", "leaf" }, { "Mentor Star I", 1 }, { "Mentor Star II", 5 }, { "Mentor Star III", 10 }, { "Mentor Star IV", 20 }, { "Mentor Star V (wings)", 50 } }) do
          opts[#opts + 1] = { "Badge: " .. x[1], { "badge", x[2] } }
        end
        for _, x in ipairs({ { "(real)", false }, { "I", 1 }, { "XII", 12 }, { "XX", 20 } }) do opts[#opts + 1] = { "Level: " .. x[1], { "level", x[2] } } end
        local pr = C.Cos.Picker(idBox, "Try cosmetics", opts, function(v) pv[v[1]] = v[2] or nil; if v[1] == "ring" and C.Cos.UpdateGlows then C.Cos.UpdateGlows() end; redo() end)
        pr:SetPoint("TOPRIGHT", idBox, "TOPRIGHT", -8, -8)
        local pf = C.Cos.Picker(prog, "Bar frames", { { "on", "on" }, { "off", "off" } }, function(v) pv.bars = v; redo() end)
        pf:SetPoint("TOPRIGHT", prog, "TOPRIGHT", -14, -10)
      end
      local pv = C.Cos.preview
      local mm = C.Rep.Mine and C.Rep.Mine() or {}
      local rec = C.YouRecord and C.YouRecord() or {}
      local starter = (rec.farms or 0) == 0 or ((rec.farms or 0) == 1 and ((rec.oweNow or 0) >= 1 or (rec.owedNow or 0) >= 1))
      local recruits = 0
      if pv.badge == "leaf" then starter = true elseif pv.badge == "none" then starter = false
      elseif type(pv.badge) == "number" then starter, recruits = false, pv.badge end
      C.Cos.UpdatePortrait(cos, pv.ring or mm.standing, pv.level or m.level, recruits, starter)
      local stName = pv.ring or mm.standing or "Unproven"
      local vn, _, vbad = 0, nil, 0
      if C.Vouch then vn, _, vbad = C.Vouch.Counts() end
      standT:SetText(C.Cos.StandingColor(stName) .. stName .. "|r" .. GREY .. "  " .. (mm.rep or 0) .. " rep|r"
        .. (vn > 0 and ("  |T" .. C.Vouch.UP_ICON .. ":14|t|cffffd100" .. vn .. "|r") or "")
        .. ((vbad or 0) > 0 and ("  |T" .. C.Vouch.DOWN_ICON .. ":14|t" .. C.Vouch.RED .. vbad .. "|r") or ""))
      -- (1.4.5: frames off by default, Taylor's call; Try > Bar frames still shows them)
      if pv.bars == "on" then cos.xpF:Show(); cos.stF:Show() else cos.xpF:Hide(); cos.stF:Hide() end
    end
    share:SetText("Data sharing: " .. ((C.ShareData and C.ShareData()) and (GREEN .. "on|r") or (ORANGE .. "off: your Kina level is paused|r")))
    -- XP toward the next level
    local R = C.Rep
    local lo, hi = R.XPFor(m.level), R.XPFor(math.min(R.MAX_LEVEL, m.level + 1))
    if m.level >= R.MAX_LEVEL then xpBar:Set(1, m.xp .. " XP (top level)")
    else xpBar:Set((m.xp - lo) / math.max(1, hi - lo), string.format("%d / %d XP", m.xp, hi)) end
    xpNote:SetText(m.level >= R.MAX_LEVEL and "" or (GREY .. "to level " .. R.Roman(m.level + 1) .. ": pay what you owe and share farms of 15+ minutes" .. "|r"))
    -- standing: not counted yet (it comes with the creditor actions and two-sided logs)
    -- 1.3.0: standing points and title
    local m = C.Rep and C.Rep.Mine and C.Rep.Mine() or {}
    local pts, at, nxt = m.rep or 0, m.standingAt or 0, m.standingNext
    if nxt then stBar:Set(math.max(0, math.min(1, (pts - at) / math.max(1, nxt - at))), string.format("%s  %d / %d", m.standing or "Unproven", pts, nxt))
    else stBar:Set(pts < 0 and 0 or 1, string.format("%s  %d", m.standing or "Unproven", pts)) end
    stNote:SetText(GREY .. (pts < 0 and "Pay what you owe on time to climb back. " or "Pay debts fast, farm together (+5), get vouched (+15). A lapsed debt costs 50.") .. "|r")
    -- professions
    local list = {}
    for n, sk in pairs(me.profs or {}) do if C.TradeSkill and C.TradeSkill(n) then list[#list + 1] = { n, sk } end end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i, pb in ipairs(profBars) do
      local x = list[i]
      if x then
        pb[1]:SetText(string.format("%s  %s%d / 300|r", x[1], GREY, x[2])); pb[1]:Show(); pb[2]:Show(); pb[2]:Set(x[2] / 300, "")
        if pb[3] and C.Cos then pb[3]:SetTexture(C.Cos.ProfIcon(x[1])); pb[3]:Show() elseif pb[3] then pb[3]:Hide() end
      else pb[1]:Hide(); pb[2]:Hide(); if pb[3] then pb[3]:Hide() end end
    end
    if #list == 0 then profNone:SetText(ORANGE .. "None read yet: open your professions (skills) window once.|r"); profNone:Show() else profNone:Hide() end
    -- record
    local r = C.YouRecord and C.YouRecord() or {}
    local rows = {
      { "Shared farms", tostring(r.farms or 0) .. (r.hours and r.hours > 0 and (GREY .. string.format("  (%.1f h)", r.hours) .. "|r") or "") },
      { "XP/h this week", (C.GameXPWeek and C.GameXPWeek()) and (BreakUpLargeNumbers and BreakUpLargeNumbers(C.GameXPWeek()) or tostring(C.GameXPWeek())) or (GREY .. "none yet|r") },
      { "Your share of farms", money(r.share) },
      { "Debts you paid", tostring(r.paid or 0) .. (r.paidAmt and r.paidAmt > 0 and (GREY .. " (" .. C.Money(math.floor(r.paidAmt)) .. ")|r") or "") },
      { "Paid to you", tostring(r.recv or 0) .. (r.recvAmt and r.recvAmt > 0 and (GREY .. " (" .. C.Money(math.floor(r.recvAmt)) .. ")|r") or "")
        .. ((r.recvExtra or 0) >= 1 and (GREY .. " +" .. C.Money(math.floor(r.recvExtra)) .. " extra|r") or "") },
      { "Waiting to confirm", ((r.paidPend or 0) + (r.recvPend or 0)) > 0 and (ORANGE .. string.format("%d paid, %d to you", r.paidPend or 0, r.recvPend or 0) .. "|r") or (GREEN .. "none|r") },
      { "Debts you forgave", tostring(r.forgaveN or 0) },
      { "Forgiven for you", tostring(r.forgivenN or 0) },
      { "Open now", (r.oweNow or 0) >= 1 and (ORANGE .. "you owe " .. C.Money(math.floor(r.oweNow)) .. "|r") or ((r.owedNow or 0) >= 1 and (GOLD .. "owed " .. C.Money(math.floor(r.owedNow)) .. "|r") or (GREEN .. "all settled|r")) },
      { "Farmed with", r.partners or (GREY .. "nobody yet|r") },
    }
    for i = 1, #recL do
      local x = rows[i]
      recL[i]:SetText(x and (GREY .. x[1] .. "|r") or ""); recR[i]:SetText(x and x[2] or "")
    end
  end
end

------------------------------------------------------------------ Debts: people on the left, one card on the right
builders.debts = function(p)
  -- 1.2.3: keep the page live (due dates, payments and answers arriving while it's open)
  local tick = 0
  p:SetScript("OnUpdate", function(_, el)
    tick = tick + el; if tick < 2 then return end; tick = 0
    if InCombatLockdown and InCombatLockdown() then return end
    if p.refresh then pcall(p.refresh) end
  end)
  local left = box(p); left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(250)
  local lh = heading(left, "People"); lh:SetPoint("TOPLEFT", 16, -14)
  local people = {}
  for i = 1, 9 do
    local b = CreateFrame("Button", nil, left)
    b:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 40); b:SetSize(230, 36)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
    b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(); b.sel:SetColorTexture(0.85, 0.66, 0.25, 0.16); b.sel:Hide()
    b.name = text(b, "GameFontNormal"); b.name:SetPoint("TOPLEFT", 8, -3); b.name:SetWidth(214)
    b.sub = text(b, "GameFontHighlightSmall"); b.sub:SetPoint("TOPLEFT", 8, -20); b.sub:SetWidth(214)
    b:SetScript("OnClick", function(self) p.selected = self.who; p.refresh() end)
    people[i] = b
  end
  local empty = text(left, "GameFontHighlightSmall"); empty:SetPoint("TOPLEFT", 16, -40); empty:SetWidth(220)
  if empty.SetWordWrap then empty:SetWordWrap(true) end

  local card = box(p); card:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0); card:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  -- 1.4.0: their profile: portrait in a ring, level, class, professions, Kina level
  local cPortF = CreateFrame("Frame", nil, card); cPortF:SetSize(40, 40); cPortF:SetPoint("TOPLEFT", 16, -10)
  local cPort = cPortF:CreateTexture(nil, "ARTWORK"); cPort:SetAllPoints()
  local cRing = cPortF:CreateTexture(nil, "OVERLAY"); cRing:SetPoint("CENTER"); cRing:SetSize(52, 52)
  if cPort.SetMask then pcall(cPort.SetMask, cPort, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  local cName = text(card, "GameFontNormalLarge"); cName:SetPoint("TOPLEFT", 66, -14)
  local cPick
  if C.Cos and C.Cos.Picker then
    local opts = { { "(their real standing)", false } }
    for _, st in ipairs({ "Unproven", "Vouched", "Reliable", "Trusted", "Honored", "Revered", "Exalted", "Delinquent" }) do opts[#opts + 1] = { st, st } end
    cPick = C.Cos.Picker(card, "Their ring", opts, function(v) C.Cos.preview.theirRing = v or nil; if p.refresh then p.refresh() end end)
    cPick:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -36)
  end
  local cSub = text(card, "GameFontHighlightSmall"); cSub:SetPoint("TOPLEFT", cName, "BOTTOMLEFT", 0, -4)
  local cBal = text(card, "GameFontHighlight", "RIGHT"); cBal:SetPoint("TOPRIGHT", -18, -16); cBal:SetWidth(300)
  local lines = {}
  local B = C.UIButton
  for i = 1, 6 do
    local l = CreateFrame("Frame", nil, card)
    l:SetPoint("TOPLEFT", 14, -62 - (i - 1) * 62); l:SetPoint("RIGHT", card, "RIGHT", -14, 0); l:SetHeight(56)
    local sep = l:CreateTexture(nil, "BACKGROUND"); sep:SetPoint("BOTTOMLEFT", 0, 0); sep:SetPoint("BOTTOMRIGHT", 0, 0); sep:SetHeight(1); sep:SetColorTexture(0.85, 0.66, 0.25, 0.25)
    l.what = text(l, "GameFontHighlight"); l.what:SetPoint("TOPLEFT", 4, -4); l.what:SetWidth(380)
    l.status = text(l, "GameFontHighlightSmall"); l.status:SetPoint("TOPLEFT", l.what, "BOTTOMLEFT", 0, -4); l.status:SetWidth(380)
    l.amt = text(l, "GameFontNormal", "RIGHT"); l.amt:SetPoint("TOPRIGHT", -4, -4); l.amt:SetWidth(140)
    l.btns = {}
    for k = 1, 3 do
      local b = B(l, "", 120, function(self) if self.act then self.act() end end)
      b:SetHeight(24)
      l.btns[k] = b
    end
    -- buttons right to left along the bottom of the line
    l.btns[1]:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", -2, 6)
    l.btns[2]:SetPoint("RIGHT", l.btns[1], "LEFT", -6, 0)
    l.btns[3]:SetPoint("RIGHT", l.btns[2], "LEFT", -6, 0)
    lines[i] = l
  end
  local note = text(card, "GameFontHighlightSmall"); note:SetPoint("BOTTOMLEFT", 18, 14); note:SetPoint("RIGHT", card, "RIGHT", -18, 0)
  if note.SetWordWrap then note:SetWordWrap(true) end

  local function setBtn(b, label, act, width)
    if not label then b:Hide(); b.act = nil; return end
    b:SetText(label); b.act = act; b:SetWidth(width or 120); b:Show()
  end

  p.refresh = function()
    -- every open debt, grouped by person
    local byWho, order = {}, {}
    for _, d in ipairs(C.Debts()) do
      local who = C.Books.Name(d.who)
      if not byWho[who] then byWho[who] = { who = who, debts = {}, owe = 0, owed = 0 }; order[#order + 1] = who end
      local x = byWho[who]
      x.debts[#x.debts + 1] = d
      if d.dir == "owe" then x.owe = x.owe + d.amt else x.owed = x.owed + d.amt end
    end
    table.sort(order)
    if C.debtsWant then
      for k in pairs(byWho) do if tostring(k):lower():match("^[^%-]+") == tostring(C.debtsWant):lower():match("^[^%-]+") then p.selected = k end end
      C.debtsWant = nil
    end
    if not (p.selected and byWho[p.selected]) then p.selected = order[1] end
    for i, b in ipairs(people) do
      local x = byWho[order[i] or ""]
      if x then
        b.who = x.who
        b.name:SetText(x.who)
        local parts = {}
        if x.owe >= 1 then parts[#parts + 1] = ORANGE .. "you owe " .. C.Money(math.floor(x.owe)) .. "|r" end
        if x.owed >= 1 then parts[#parts + 1] = GOLD .. "owes you " .. C.Money(math.floor(x.owed)) .. "|r" end
        b.sub:SetText(table.concat(parts, "  "))
        if x.who == p.selected then b.sel:Show() else b.sel:Hide() end
        b:Show()
      else b:Hide() end
    end
    if #order == 0 then
      empty:SetText(GREEN .. "Nothing open.|r\n\nWhen a shared farm's split leaves someone owing, they show up here with Pay, Ask, more time and Forgive.")
      empty:Show()
    else empty:Hide() end

    local x = byWho[p.selected or ""]
    if not x then
      cName:SetText(""); cSub:SetText(""); cBal:SetText("")
      for _, l in ipairs(lines) do l:Hide() end
      note:SetText(GREY .. "Debts from shared farms, with the person you owe or who owes you. Paying, asking for more time and forgiving all close on both sides.|r")
      return
    end
    cName:SetText(x.who)
    local rep = C.Rep and C.Rep.Of and C.Rep.Of(x.who)
    local ch = C.Share and C.Share.CharOf and C.Share.CharOf(x.who)
    local bits = {}
    if ch then
      bits[#bits + 1] = "Level " .. tostring(ch.level or "?") .. " " .. tostring(ch.class or ""):lower():gsub("^%l", string.upper)
      local pl = {}
      for pn, sk in pairs(ch.profs or {}) do pl[#pl + 1] = pn .. " " .. sk end
      table.sort(pl)
      if #pl > 0 then bits[#bits + 1] = table.concat(pl, ", ") end
    end
    bits[#bits + 1] = (rep and rep.lv and rep.lv > 0) and ("Kina " .. C.Rep.Roman(rep.lv) .. " (unverified)") or "Kina level unknown"
    cSub:SetText(GREY .. table.concat(bits, "  ·  ") .. "|r")
    cPort:SetTexture(nil)
    local unit
    for _, u in ipairs({ "party1", "party2", "party3", "party4", "target" }) do
      if UnitName and UnitExists and UnitExists(u) and (UnitName(u) or ""):lower() == tostring(x.who):lower():match("^[^%-]+") then unit = u end
    end
    if unit and SetPortraitTexture then pcall(SetPortraitTexture, cPort, unit) else cPort:SetColorTexture(0.1, 0.1, 0.1, 1) end
    local theirPts = C.Share and C.Share.StandingOf and C.Share.StandingOf(x.who)
    local theirSt = theirPts and C.Rep.StandingOf(theirPts) or "Unproven"
    if theirPts then cSub:SetText(cSub:GetText() .. GREY .. "  ·  " .. theirSt .. " (" .. theirPts .. ", unverified)|r") end
    if C.Cos then cRing:SetTexture(C.Cos.RingFor(C.Cos.preview.theirRing or theirSt)) end
    local net = x.owed - x.owe
    cBal:SetText(net >= 1 and (GOLD .. x.who .. " owes you " .. C.Money(math.floor(net)) .. "|r") or (net <= -1 and (ORANGE .. "You owe " .. x.who .. " " .. C.Money(math.floor(-net)) .. "|r") or ""))
    for i, l in ipairs(lines) do
      local d = x.debts[i]
      if d then
        local farm = (d.farm or "farm") .. (d.t and (GREY .. "  " .. date("%m/%d", d.t) .. "|r") or "")
        l.what:SetText((d.dir == "owe" and "You owe for " or "Owed to you for ") .. farm)
        local sp = d.s and d.s.split or {}
        local st = d.topup and (GREY .. "an auction sale paid more than the split counted|r") or (C.DueText and C.DueText(d) or "")
        if d.dir == "owe" and sp.plea and sp.plea[d.key] then st = st .. GREY .. "   (you asked for more time)|r" end
        if d.dir == "owed" and sp.pleaFrom and sp.pleaFrom[d.key] then st = st .. GOLD .. "   asks for more time|r" end
        l.status:SetText(st)
        l.amt:SetText((d.dir == "owe" and ORANGE or GOLD) .. C.Money(math.floor(d.amt)) .. "|r")
        if d.dir == "owe" then
          setBtn(l.btns[1], "Pay " .. C.Money(math.floor(d.amt)), function()
            if C.PayStart then C.PayStart({ to = d.who, amt = math.floor(d.amt), s = d.s }) end end, 150)
          setBtn(l.btns[2], (not d.topup and not (sp.plea and sp.plea[d.key])) and "Ask for more time" or nil, function() C.AskForTime(d); p.refresh() end, 150)
          setBtn(l.btns[3], nil)
        else
          setBtn(l.btns[1], "Forgive", function()
            if StaticPopupDialogs and StaticPopup_Show then
              StaticPopupDialogs["KINA_FORGIVE"] = StaticPopupDialogs["KINA_FORGIVE"] or {
                text = "Forgive %s?\n\nThe debt closes for both of you and can't be reopened.",
                button1 = "Forgive", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                OnAccept = function(_, y) if y and C.Forgive then C.Forgive(y) end end }
              StaticPopup_Show("KINA_FORGIVE", x.who .. " the " .. C.Money(math.floor(d.amt)), nil, d)
            else C.Forgive(d) end
          end, 100)
          setBtn(l.btns[2], (sp.pleaFrom and sp.pleaFrom[d.key]) and ("Give " .. C.EXTEND_HOURS .. " more hours") or nil, function() C.ExtendDebt(d); p.refresh() end, 150)
          setBtn(l.btns[3], "Ask to pay", function()
            if C.RequestSettle then C.RequestSettle({ from = d.who, amt = math.floor(d.amt), s = d.s }) end end, 110)
        end
        l:Show()
      else l:Hide() end
    end
    note:SetText(GREY .. "Pay opens a trade (stand next to them) and puts the money in; at a mailbox Kina can also pay by mail. Both Kinas confirm every payment.|r")
  end
end

------------------------------------------------------------------ You > Commendations and You > Farm stats (1.5.2)
-- Taylor: "which vouches I got and how many, who vouched for me (click a name to see what
-- they gave me), a top 5 of who vouched for me most, and top 5 farm stats: which of my
-- characters farmed and who with, with time". Two pages beside the overview, each a few
-- clean boxes; everything is worked out from the event log and the farm history.
local RED = "|cffff4030"
local function first(n) return n and (tostring(n):match("^([^%-]+)") or tostring(n)) or "?" end
local function hrs(secs)
  secs = secs or 0
  if secs < 3600 then return string.format("%d min", math.floor(secs / 60 + 0.5)) end
  return string.format("%.1f h", secs / 3600)
end
local function icon(bad, size) return "|T" .. (bad and C.Vouch.DOWN_ICON or C.Vouch.UP_ICON) .. ":" .. (size or 14) .. "|t" end
local function dateOf(t) return (date and date("%b %d", t)) or "" end

-- every commendation in the log (the log is kept for good; the vouch list is pruned)
function C.VouchStats()
  local st = { got = 0, gotBad = 0, gave = 0, gaveBad = 0, byKind = {}, from = {}, list = {} }
  local lines = C.db and C.db.log and C.db.log.lines or {}
  local isBad = C.Vouch and C.Vouch.IsBad or function() return false end
  for _, line in ipairs(lines) do
    local e = line.e or ""
    if e:find("|vouch|", 1, true) then
      local f = {}
      for v in (e .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
      local t, k = tonumber(f[1]) or 0, tonumber(f[5]) or 1
      if f[3] == "got" then
        local who = first(f[4])
        local bad = isBad(k)
        if bad then st.gotBad = st.gotBad + 1 else st.got = st.got + 1 end
        st.byKind[k] = (st.byKind[k] or 0) + 1
        local p = st.from[who]
        if not p then p = { who = who, good = 0, bad = 0, items = {} }; st.from[who] = p; st.list[#st.list + 1] = p end
        if bad then p.bad = p.bad + 1 else p.good = p.good + 1 end
        table.insert(p.items, 1, { t = t, kind = k, rep = tonumber(f[7]) or 0 })
        p.last = math.max(p.last or 0, t)
      elseif f[3] == "gave" then
        if isBad(k) then st.gaveBad = st.gaveBad + 1 else st.gave = st.gave + 1 end
      end
    end
  end
  table.sort(st.list, function(a, b)
    if a.good ~= b.good then return a.good > b.good end
    return (a.last or 0) > (b.last or 0)
  end)
  return st
end

-- farm totals per character of mine and per partner
function C.FarmStats()
  local chars, partners, cl, pl = {}, {}, {}, {}
  local tot = { farms = 0, secs = 0, share = 0 }
  local gains = C.Rep and C.Rep.History and C.Rep.History() or {}
  local bySid = {}
  for _, s in ipairs(C.db and C.db.sessions or {}) do
    if type(s) == "table" and s.start and s.stop then
      local secs = (s.result and s.result.secs) or math.max(0, s.stop - s.start - (s.pausedSecs or 0))
      local share = 0
      local ok, fr = pcall(C.Books.Farm, s, gains, bySid)
      if ok and fr then share = fr.share or 0 end
      if share <= 0 and not s.sync and s.result then share = s.result.total or 0 end
      -- which of my characters: recorded since 1.5.2, else the one of mine in the split
      local mine = s.char and first(s.char)
      local inc = s.split and s.split.incomes or {}
      if not mine then for n in pairs(inc) do if C.IsMyChar and C.IsMyChar(n) then mine = first(n) end end end
      mine = mine or "(not recorded)"
      local c = chars[mine]
      if not c then c = { who = mine, farms = 0, secs = 0, share = 0, class = s.class }; chars[mine] = c; cl[#cl + 1] = c end
      c.farms, c.secs, c.share = c.farms + 1, c.secs + secs, c.share + share
      c.class = c.class or s.class
      tot.farms, tot.secs, tot.share = tot.farms + 1, tot.secs + secs, tot.share + share
      for n in pairs(inc) do
        if not (C.IsMyChar and C.IsMyChar(n)) then
          local k = first(n)
          local p = partners[k]
          if not p then p = { who = k, farms = 0, secs = 0 }; partners[k] = p; pl[#pl + 1] = p end
          p.farms, p.secs = p.farms + 1, p.secs + secs
        end
      end
      if not tot.best or (s.result and (s.result.perHour or 0) > (tot.best.perHour or 0)) then
        if s.result and (s.result.perHour or 0) > 0 then tot.best = { label = s.label, perHour = s.result.perHour } end
      end
    end
  end
  table.sort(cl, function(a, b) return a.secs > b.secs end)
  table.sort(pl, function(a, b) return a.secs > b.secs end)
  return cl, pl, tot
end

-- a ranked row: rank, name, value on the right, and a thin bar under it
local function rankRow(parent, i, w, clickable)
  local r = CreateFrame(clickable and "Button" or "Frame", nil, parent)
  r:SetSize(w, 34)
  r.rank = text(r, "GameFontNormalLarge", "CENTER"); r.rank:SetPoint("LEFT", 0, 2); r.rank:SetWidth(22)
  if C.Cos then C.Cos.Font(r.rank, 15, "OUTLINE") end
  r.name = text(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 28, -3)
  r.val = text(r, "GameFontHighlight", "RIGHT"); r.val:SetPoint("TOPRIGHT", -4, -3)
  r.sub = text(r, "GameFontHighlightSmall", "RIGHT"); r.sub:SetPoint("TOPRIGHT", r.val, "BOTTOMRIGHT", 0, -2)
  local tray = r:CreateTexture(nil, "BACKGROUND"); tray:SetPoint("BOTTOMLEFT", 28, 3); tray:SetPoint("BOTTOMRIGHT", -4, 3); tray:SetHeight(3)
  tray:SetColorTexture(1, 1, 1, 0.06)
  r.fill = r:CreateTexture(nil, "ARTWORK"); r.fill:SetPoint("BOTTOMLEFT", 28, 3); r.fill:SetHeight(3); r.fill:SetColorTexture(0.95, 0.75, 0.3, 0.85)
  r.barW = w - 32
  if clickable then
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.4, 0.08)
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, -1); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.85, 0.66, 0.25, 0.16); r.sel:Hide()
  end
  function r:Bar(frac) if frac and frac > 0 then self.fill:Show(); self.fill:SetWidth(math.max(2, self.barW * math.min(1, frac))) else self.fill:Hide() end end
  return r
end
local RANK = { "|cffffd100", "|cffd9d9d9", "|cffd08a4a", "|cff9d9d9d", "|cff9d9d9d" }

builders.youVouch = function(p)
  -- left: totals and every kind
  local L = box(p); L:SetPoint("TOPLEFT", 0, 0); L:SetPoint("BOTTOMLEFT", 0, 0); L:SetWidth(300)
  local h = heading(L, "Commendations received"); h:SetPoint("TOPLEFT", 16, -14)
  local big = text(L, "GameFontNormalHuge"); big:SetPoint("TOPLEFT", 16, -40)
  if C.Cos then C.Cos.Font(big, 26, "OUTLINE") end
  local bigSub = text(L, "GameFontHighlightSmall"); bigSub:SetPoint("TOPLEFT", 16, -96) -- (1.5.3: clear of the big icons)
  local kindRows = {}
  for i = 1, 8 do
    local y = -124 - (i - 1) * 26 - (i > 4 and 12 or 0)
    local l = text(L, "GameFontHighlight"); l:SetPoint("TOPLEFT", 16, y)
    local n = text(L, "GameFontHighlight", "RIGHT"); n:SetPoint("TOPRIGHT", -16, y)
    kindRows[i] = { l, n }
  end
  local gaveT = text(L, "GameFontHighlightSmall"); gaveT:SetPoint("BOTTOMLEFT", 16, 14); gaveT:SetPoint("RIGHT", L, "RIGHT", -16, 0)

  -- middle: top 5 who commended you (click one)
  local M = box(p); M:SetPoint("TOPLEFT", L, "TOPRIGHT", 12, 0); M:SetPoint("BOTTOMLEFT", L, "BOTTOMRIGHT", 12, 0); M:SetWidth(300)
  local h2 = heading(M, "Who commended you most"); h2:SetPoint("TOPLEFT", 16, -14)
  local h2s = text(M, "GameFontHighlightSmall"); h2s:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -3); h2s:SetText(GREY .. "click a name to see what they gave you|r")
  local top = {}
  for i = 1, 5 do
    local r = rankRow(M, i, 10, true); r:SetPoint("TOPLEFT", 16, -56 - (i - 1) * 40); r:SetPoint("RIGHT", M, "RIGHT", -16, 0); top[i] = r
  end
  local more = text(M, "GameFontHighlightSmall"); more:SetPoint("BOTTOMLEFT", 16, 14)
  local empty = text(M, "GameFontHighlightSmall"); empty:SetPoint("TOPLEFT", 16, -60); empty:SetWidth(290)
  if empty.SetWordWrap then empty:SetWordWrap(true) end

  -- right: what the selected person gave you
  local R = box(p); R:SetPoint("TOPLEFT", M, "TOPRIGHT", 12, 0); R:SetPoint("BOTTOMRIGHT", 0, 0)
  local h3 = heading(R, ""); h3:SetPoint("TOPLEFT", 16, -14)
  local h3s = text(R, "GameFontHighlightSmall"); h3s:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -3)
  local prof = CreateFrame("Button", nil, R, "UIPanelButtonTemplate"); prof:SetSize(96, 20); prof:SetPoint("TOPRIGHT", -12, -10); prof:SetText("Profile")
  local items = {}
  for i = 1, 12 do
    local y = -56 - (i - 1) * 22
    local d = text(R, "GameFontHighlightSmall"); d:SetPoint("TOPLEFT", 16, y); d:SetWidth(52)
    local k = text(R, "GameFontHighlight"); k:SetPoint("TOPLEFT", 70, y + 1)
    local rp = text(R, "GameFontHighlightSmall", "RIGHT"); rp:SetPoint("TOPRIGHT", -16, y)
    k:SetPoint("RIGHT", rp, "LEFT", -6, 0)
    items[i] = { d, k, rp }
  end

  p.refresh = function()
    local st = C.VouchStats()
    local V = C.Vouch
    big:SetText(icon(false, 26) .. " |cffffd100" .. st.got .. "|r     " .. icon(true, 26) .. " " .. RED .. st.gotBad .. "|r")
    bigSub:SetText(GREY .. "from " .. #st.list .. (#st.list == 1 and " player" or " players") .. "|r")
    for i = 1, 8 do
      local bad = V.IsBad(i)
      local n = st.byKind[i] or 0
      kindRows[i][1]:SetText(icon(bad) .. " " .. (bad and (RED .. V.KINDS[i] .. "|r") or V.KINDS[i]))
      kindRows[i][2]:SetText(n > 0 and ((bad and RED or GOLD) .. n .. "|r") or (GREY .. "0|r"))
    end
    gaveT:SetText(GREY .. "You've given " .. st.gave .. " " .. icon(false, 12) .. "  and  " .. st.gaveBad .. " " .. icon(true, 12) .. "|r")
    -- top 5
    local maxN = 1
    for _, x in ipairs(st.list) do maxN = math.max(maxN, x.good) end
    if not p.sel or not st.from[p.sel] then p.sel = st.list[1] and st.list[1].who end
    for i = 1, 5 do
      local r, x = top[i], st.list[i]
      if x then
        r:Show()
        r.barW = (r:GetWidth() or 268) - 32
        r.rank:SetText(RANK[i] .. i .. "|r"); r.name:SetText(x.who)
        r.val:SetText(GOLD .. x.good .. "|r " .. icon(false, 13) .. (x.bad > 0 and ("  " .. RED .. x.bad .. "|r " .. icon(true, 13)) or ""))
        r.sub:SetText(GREY .. "last " .. dateOf(x.last) .. "|r")
        r:Bar(x.good / maxN)
        if x.who == p.sel then r.sel:Show() else r.sel:Hide() end
        r:SetScript("OnClick", function() p.sel = x.who; p.refresh() end)
      else r:Hide() end
    end
    more:SetText(#st.list > 5 and (GREY .. "+" .. (#st.list - 5) .. " more players|r") or "")
    empty:SetText(#st.list == 0 and (GREY .. "No commendations yet. When a group farm ends, the people you farmed with can commend you.|r") or "")
    -- the selected person
    local x = p.sel and st.from[p.sel]
    if x then
      h3:SetText("From " .. x.who); h3s:SetText(GOLD .. x.good .. "|r " .. icon(false, 12) .. (x.bad > 0 and ("   " .. RED .. x.bad .. "|r " .. icon(true, 12)) or "") .. GREY .. "   newest first|r")
      prof:Show(); prof:SetScript("OnClick", function() if C.Profile then C.Profile.Show(x.who) end end)
    else h3:SetText("From ..."); h3s:SetText(""); prof:Hide() end
    for i = 1, 12 do
      local it = x and x.items[i]
      local row = items[i]
      if it then
        local bad = V.IsBad(it.kind)
        row[1]:SetText(GREY .. dateOf(it.t) .. "|r")
        row[2]:SetText(icon(bad) .. " " .. (bad and (RED .. (V.KINDS[it.kind] or "?") .. "|r") or (V.KINDS[it.kind] or "?")))
        row[3]:SetText(it.rep ~= 0 and ((it.rep > 0 and ("|cff4fc3f7+" .. it.rep) or (RED .. it.rep)) .. " rep|r") or "")
      else row[1]:SetText(""); row[2]:SetText(""); row[3]:SetText("") end
    end
  end
end

builders.youFarms = function(p)
  local S = box(p); S:SetPoint("TOPLEFT", 0, 0); S:SetPoint("TOPRIGHT", 0, 0); S:SetHeight(64)
  local sums = {}
  for i = 1, 4 do
    local v = text(S, "GameFontNormalLarge"); if C.Cos then C.Cos.Font(v, 18, "OUTLINE") end
    local l = text(S, "GameFontHighlightSmall")
    sums[i] = { v, l }
  end
  local L = box(p); L:SetPoint("TOPLEFT", S, "BOTTOMLEFT", 0, -12); L:SetPoint("BOTTOMLEFT", 0, 0); L:SetPoint("RIGHT", p, "CENTER", -6, 0)
  local hl = heading(L, "Your characters"); hl:SetPoint("TOPLEFT", 16, -14)
  local hls = text(L, "GameFontHighlightSmall"); hls:SetPoint("TOPLEFT", hl, "BOTTOMLEFT", 0, -3); hls:SetText(GREY .. "by time farmed|r")
  local R = box(p); R:SetPoint("TOPLEFT", S, "BOTTOM", 6, -12); R:SetPoint("BOTTOMRIGHT", 0, 0)
  local hr = heading(R, "Farmed with most"); hr:SetPoint("TOPLEFT", 16, -14)
  local hrs_ = text(R, "GameFontHighlightSmall"); hrs_:SetPoint("TOPLEFT", hr, "BOTTOMLEFT", 0, -3); hrs_:SetText(GREY .. "by time together  ·  click for their profile|r")
  local cRows, pRows = {}, {}
  for i = 1, 5 do
    local a = rankRow(L, i, 10, false); a:SetPoint("TOPLEFT", 16, -56 - (i - 1) * 44); a:SetPoint("RIGHT", L, "RIGHT", -16, 0); cRows[i] = a
    local b = rankRow(R, i, 10, true); b:SetPoint("TOPLEFT", 16, -56 - (i - 1) * 44); b:SetPoint("RIGHT", R, "RIGHT", -16, 0); pRows[i] = b
  end
  local note = text(L, "GameFontHighlightSmall"); note:SetPoint("BOTTOMLEFT", 16, 14); note:SetPoint("RIGHT", L, "RIGHT", -16, 0)
  local pnote = text(R, "GameFontHighlightSmall"); pnote:SetPoint("BOTTOMLEFT", 16, 14)
  p.refresh = function()
    local cl, pl, tot = C.FarmStats()
    local w = (S:GetWidth() or 1000) - 32
    local vals = {
      { tostring(tot.farms), "farms" }, { hrs(tot.secs), "farmed" }, { money(tot.share), "your share" },
      { tot.best and (C.Money(math.floor(tot.best.perHour)) .. GREY .. "/h|r") or (GREY .. "-|r"), "best farm" .. (tot.best and tot.best.label and (": " .. tot.best.label) or "") },
    }
    for i, s in ipairs(sums) do
      s[1]:ClearAllPoints(); s[1]:SetPoint("TOPLEFT", 16 + (i - 1) * (w / 4), -12); s[1]:SetText(GOLD .. vals[i][1] .. "|r")
      s[2]:ClearAllPoints(); s[2]:SetPoint("TOPLEFT", s[1], "BOTTOMLEFT", 0, -4); s[2]:SetText(GREY .. vals[i][2] .. "|r"); s[2]:SetWidth(w / 4 - 12)
    end
    local function fill(rows, list, isChar)
      local maxS = 1
      for _, x in ipairs(list) do maxS = math.max(maxS, x.secs) end
      for i = 1, 5 do
        local r, x = rows[i], list[i]
        if x then
          r:Show()
          r.barW = (r:GetWidth() or 300) - 32
          r.rank:SetText(RANK[i] .. i .. "|r")
          local cc = isChar and x.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[x.class]
          r.name:SetText(cc and string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, x.who) or x.who)
          r.val:SetText(hrs(x.secs))
          r.sub:SetText(GREY .. x.farms .. (x.farms == 1 and " farm" or " farms") .. (isChar and ("  ·  " .. money(x.share)) or "") .. "|r")
          r:Bar(x.secs / maxS)
          if not isChar then r:SetScript("OnClick", function() if C.Profile then C.Profile.Show(x.who) end end) end
        else r:Hide() end
      end
    end
    fill(cRows, cl, true); fill(pRows, pl, false)
    local unrec = false
    for _, c in ipairs(cl) do if c.who == "(not recorded)" then unrec = true end end
    note:SetText(unrec and (GREY .. "(not recorded): solo farms from before 1.5.2, when Kina didn't note the character.|r") or "")
    pnote:SetText(#pl == 0 and (GREY .. "No group farms yet.|r") or (#pl > 5 and (GREY .. "+" .. (#pl - 5) .. " more|r") or ""))
  end
end
