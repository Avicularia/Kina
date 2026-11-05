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
  local TOP_H = 128
  local idBox = box(p); idBox:SetPoint("TOPLEFT", 0, 0); idBox:SetSize(300, TOP_H)
  local portraitBox = CreateFrame("Frame", nil, idBox); portraitBox:SetPoint("TOPLEFT", 12, -12); portraitBox:SetSize(80, 80)
  if iron() then C.Skin.Tile(portraitBox, 6) end
  local portrait = portraitBox:CreateTexture(nil, "ARTWORK"); portrait:SetPoint("TOPLEFT", 7, -7); portrait:SetPoint("BOTTOMRIGHT", -7, 7)
  local name = text(idBox, "GameFontNormalLarge"); name:SetPoint("TOPLEFT", portraitBox, "TOPRIGHT", 12, -4); name:SetWidth(170)
  local line = text(idBox, "GameFontHighlight"); line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6); line:SetWidth(170)
  local lvl = text(idBox, "GameFontNormalLarge"); lvl:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -12); lvl:SetWidth(170)
  local share = text(idBox, "GameFontHighlightSmall"); share:SetPoint("BOTTOMLEFT", 14, 14); share:SetWidth(272)

  -- middle: Kina level and standing
  local prog = box(p); prog:SetPoint("TOPLEFT", idBox, "TOPRIGHT", 12, 0); prog:SetPoint("RIGHT", p, "RIGHT", 0, 0); prog:SetHeight(TOP_H)
  -- heading and bar on one line each: "Kina level  I" [bar]
  local h1 = heading(prog, "Kina level"); h1:SetPoint("TOPLEFT", 16, -14)
  local xpBar = bar(prog, 0.85, 0.65, 0.15); xpBar:SetPoint("TOPLEFT", 16, -34); xpBar:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local xpNote = text(prog, "GameFontHighlightSmall"); xpNote:SetPoint("TOPLEFT", xpBar, "BOTTOMLEFT", 0, -3); xpNote:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local h2 = heading(prog, "Standing"); h2:SetPoint("TOPLEFT", 16, -72)
  local stBar = bar(prog, 0.30, 0.62, 0.95); stBar:SetPoint("TOPLEFT", 16, -92); stBar:SetPoint("RIGHT", prog, "RIGHT", -16, 0)
  local stNote = text(prog, "GameFontHighlightSmall"); stNote:SetPoint("TOPLEFT", stBar, "BOTTOMLEFT", 0, -3); stNote:SetPoint("RIGHT", prog, "RIGHT", -16, 0)

  -- bottom left: professions
  local profBox = box(p); profBox:SetPoint("TOPLEFT", idBox, "BOTTOMLEFT", 0, -12); profBox:SetWidth(300); profBox:SetPoint("BOTTOM", p, "BOTTOM", 0, 0)
  local h3 = heading(profBox, "Professions"); h3:SetPoint("TOPLEFT", 16, -14)
  local profBars = {}
  for i = 1, 4 do
    local lb = text(profBox, "GameFontHighlightSmall"); lb:SetPoint("TOPLEFT", 16, -36 - (i - 1) * 30); lb:SetWidth(268)
    local b = bar(profBox, 0.35, 0.75, 0.30); b:SetPoint("TOPLEFT", lb, "BOTTOMLEFT", 0, -3); b:SetWidth(268); b:SetHeight(14)
    profBars[i] = { lb, b }
  end
  local profNone = text(profBox, "GameFontHighlightSmall"); profNone:SetPoint("TOPLEFT", 16, -38); profNone:SetWidth(268)

  -- bottom right: your record
  local rec = box(p); rec:SetPoint("TOPLEFT", profBox, "TOPRIGHT", 12, 0); rec:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  local h4 = heading(rec, "Your record"); h4:SetPoint("TOPLEFT", 16, -14)
  -- two columns of four, so the record fits the smallest window
  local recL, recR = {}, {}
  local colA = CreateFrame("Frame", nil, rec); colA:SetPoint("TOPLEFT", 16, -36); colA:SetPoint("BOTTOMRIGHT", rec, "BOTTOM", -10, 10)
  local colB = CreateFrame("Frame", nil, rec); colB:SetPoint("TOPLEFT", rec, "TOP", 10, -36); colB:SetPoint("BOTTOMRIGHT", -16, 10)
  for i = 1, 8 do
    local col = i <= 4 and colA or colB
    local y = -((i - 1) % 4) * 24
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
    share:SetText("Data sharing: " .. ((C.ShareData and C.ShareData()) and (GREEN .. "on|r") or (ORANGE .. "off: your Kina level is paused|r")))
    -- XP toward the next level
    local R = C.Rep
    local lo, hi = R.XPFor(m.level), R.XPFor(math.min(R.MAX_LEVEL, m.level + 1))
    if m.level >= R.MAX_LEVEL then xpBar:Set(1, m.xp .. " XP (top level)")
    else xpBar:Set((m.xp - lo) / math.max(1, hi - lo), string.format("%d / %d XP", m.xp, hi)) end
    xpNote:SetText(m.level >= R.MAX_LEVEL and "" or (GREY .. "to level " .. R.Roman(m.level + 1) .. ": pay what you owe and share farms of 15+ minutes" .. "|r"))
    -- standing: not counted yet (it comes with the creditor actions and two-sided logs)
    stBar:Set(0, "Unproven")
    stNote:SetText(GREY .. "Standing starts counting in a later version. Everyone shows as unverified until the Kina server checks both players' logs.|r")
    -- professions
    local list = {}
    for n, sk in pairs(me.profs or {}) do if C.TradeSkill and C.TradeSkill(n) then list[#list + 1] = { n, sk } end end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i, pb in ipairs(profBars) do
      local x = list[i]
      if x then
        pb[1]:SetText(string.format("%s  %s%d / 300|r", x[1], GREY, x[2])); pb[1]:Show(); pb[2]:Show(); pb[2]:Set(x[2] / 300, "")
      else pb[1]:Hide(); pb[2]:Hide() end
    end
    if #list == 0 then profNone:SetText(ORANGE .. "None read yet: open your professions (skills) window once.|r"); profNone:Show() else profNone:Hide() end
    -- record
    local r = C.YouRecord and C.YouRecord() or {}
    local rows = {
      { "Shared farms", tostring(r.farms or 0) .. (r.hours and r.hours > 0 and (GREY .. string.format("  (%.1f h)", r.hours) .. "|r") or "") },
      { "Your share of farms", money(r.share) },
      { "Debts you paid", tostring(r.paid or 0) .. (r.paidAmt and r.paidAmt > 0 and (GREY .. "  (" .. C.Money(math.floor(r.paidAmt)) .. ")|r") or "") },
      { "Paid to you", tostring(r.recv or 0) .. (r.recvAmt and r.recvAmt > 0 and (GREY .. "  (" .. C.Money(math.floor(r.recvAmt)) .. ")|r") or "") },
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
  local cName = text(card, "GameFontNormalLarge"); cName:SetPoint("TOPLEFT", 18, -14)
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
    cSub:SetText(rep and rep.lv and rep.lv > 0 and (GREY .. "Kina " .. C.Rep.Roman(rep.lv) .. " (unverified)|r") or (GREY .. "Kina level unknown|r"))
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
          setBtn(l.btns[2], (sp.pleaFrom and sp.pleaFrom[d.key]) and ("Give " .. C.EXTEND_DAYS .. " more days") or nil, function() C.ExtendDebt(d); p.refresh() end, 150)
          setBtn(l.btns[3], "Ask to pay", function()
            if C.RequestSettle then C.RequestSettle({ from = d.who, amt = math.floor(d.amt), s = d.s }) end end, 110)
        end
        l:Show()
      else l:Hide() end
    end
    note:SetText(GREY .. "Pay opens a trade (stand next to them) and puts the money in; at a mailbox Kina can also pay by mail. Both Kinas confirm every payment.|r")
  end
end
