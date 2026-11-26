-- Kina 2.1.0: the Prices window's My bags and Transport tabs (Transport.lua has the numbers).
-- My bags (Taylor, Nov 23): every item in your bags with your faction's AH, Booty Bay's AH,
-- the vendor and disenchanting side by side; the winner in green; a gold line when it's worth
-- carrying; a toggle for one house or both; and "Sell items in this tab": Sell to <house>
-- and Post next, posting at the auction house's lowest price right now.
-- Transport: one line per item worth carrying ("SW > BB  buy under 1s 21c"), with a warning
-- when only a few are cheap enough and a Sells slowly list. Open while both houses' scans
-- (anyone's) are under 30 minutes old.
local _, C = ...
local PB = {}
C.PricesBags = PB
local T = function() return C.Transport end
local GOLD, GREY, GREEN = "|cffffc54a", "|cff8a8a8a", "|cff5dff6a"
local ROWS, ROW_H = 14, 24
local CHIP = {
  home = { 0.11, 0.21, 0.31, 0.66, 0.82, 1 }, bb = { 0.23, 0.16, 0.35, 0.84, 0.76, 1 },
  vendor = { 0.23, 0.23, 0.23, 0.88, 0.88, 0.88 }, de = { 0.29, 0.13, 0.25, 1, 0.7, 0.9 },
  warn = { 0.29, 0.16, 0.03, 1, 0.7, 0.35 }, slow = { 0.23, 0.08, 0.08, 1, 0.56, 0.48 },
}
local state = { tab = "browse", mode = 3, sel = 1, offset = 0, sub = "carry", qty = {}, posted = {}, wont = {}, house = nil }
PB.state = state

local function btn(parent, text, w, h, fn)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 22); b:SetText(text)
  if C.Skin and C.Skin.Button then C.Skin.Button(b) end
  b:SetScript("OnClick", fn)
  return b
end
local function fs(parent, font, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  t:SetJustifyH(justify or "LEFT"); if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end
local function chip(parent)
  local c = CreateFrame("Frame", nil, parent); c:SetSize(30, 16)
  c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints()
  c.t = fs(c, "GameFontHighlightSmall", "CENTER"); c.t:SetPoint("CENTER")
  function c:Set(kind, text)
    local k = CHIP[kind]
    if not (k and text) then self:Hide(); return end
    self.bg:SetColorTexture(k[1], k[2], k[3], 1); self.t:SetTextColor(k[4], k[5], k[6]); self.t:SetText(text)
    self:SetWidth(math.max(24, (self.t:GetStringWidth() or 20) + 12)); self:Show()
  end
  c:Hide()
  return c
end
local function panel(f)
  local p = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  p:SetPoint("TOPLEFT", 8, -36); p:SetPoint("BOTTOMRIGHT", -8, 8)
  p:SetFrameLevel(f:GetFrameLevel() + 20)
  local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.035, 0.03, 1)
  p:EnableMouse(true); p:Hide()
  return p
end
local function m(cp) return (cp and cp > 0) and C.Money(math.floor(cp + 0.5)) or (GREY .. "-|r") end
local function now() return C.Now() end

------------------------------------------------------------------ the tabs
local f, bagsP, transP, tabs
local function show(which)
  state.tab = which
  if bagsP then bagsP:SetShown(which == "bags") end
  if transP then transP:SetShown(which == "trans") end
  for k, b in pairs(tabs or {}) do
    local on = k == which
    if on then b:LockHighlight() else b:UnlockHighlight() end
    local t = b.GetFontString and b:GetFontString()
    if t then if on then t:SetTextColor(1, 0.85, 0.4) else t:SetTextColor(0.85, 0.85, 0.85) end end
  end
  PB.Draw()
end
PB.Show = show

------------------------------------------------------------------ My bags
local bagRows = {}
local function buildBags(p)
  local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); head:SetPoint("TOP", 0, -6)
  if C.Cos and C.Cos.Font then C.Cos.Font(head, 22, "") end
  head:SetText(GOLD .. "Sell items in this tab|r")
  p.mode = btn(p, "Both houses", 130, 24, function()
    state.mode = state.mode % 3 + 1; state.house = nil; PB.Draw()
  end)
  p.mode:SetPoint("TOPLEFT", 8, -40)
  p.mode:SetScript("OnEnter", function(self) C.TipOwner(self); GameTooltip:AddLine("Click to switch: your faction's auction house, Booty Bay's, or both (each item's best place).", 1, 1, 1, true); GameTooltip:Show() end)
  p.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.sellHome = btn(p, "Sell to " .. T().HomeName(), 150, 24, function() PB.StartSelling("home") end)
  p.sellHome:SetPoint("LEFT", p.mode, "RIGHT", 10, 0)
  p.sellBB = btn(p, "Sell to Booty Bay", 140, 24, function() PB.StartSelling("bb") end)
  p.sellBB:SetPoint("LEFT", p.sellHome, "RIGHT", 6, 0)
  p.dur = {}
  for i, txt in ipairs({ "2h", "8h", "24h" }) do
    local b = btn(p, txt, 40, 24, function() C.settings.postDur = i; PB.Draw() end)
    b:SetPoint("LEFT", i == 1 and p.sellBB or p.dur[i - 1], "RIGHT", i == 1 and 12 or 2, 0)
    p.dur[i] = b
  end
  p.next = btn(p, "Post next", 130, 28, function() PB.PostNext() end)
  p.next:SetPoint("TOPRIGHT", -8, -38)
  p.status = fs(p, "GameFontHighlightSmall"); p.status:SetPoint("TOPLEFT", 10, -70); p.status:SetPoint("RIGHT", p, "RIGHT", -10, 0)
  -- columns
  local X = { 8, 232, 290, 390, 490, 570, 650 }
  local heads = { "Item", "Qty", nil, nil, nil, nil, "" }
  local hy = -90
  for i, h in ipairs(heads) do if h then local t = fs(p, "GameFontNormalSmall"); t:SetPoint("TOPLEFT", X[i], hy); t:SetText(h) end end
  p.hc = {}
  for i, k in ipairs({ "home", "bb", "vendor", "de" }) do
    local c = chip(p); c:SetPoint("TOPLEFT", X[i + 2], hy + 2)
    c:Set(k, k == "home" and T().HomeName() or (k == "bb" and "Booty Bay" or (k == "vendor" and "Vendor" or "Disenchant")))
    p.hc[k] = c
  end
  for r = 1, ROWS do
    local row = CreateFrame("Button", nil, p)
    row:SetPoint("TOPLEFT", 4, hy - 16 - (r - 1) * ROW_H); row:SetPoint("RIGHT", p, "RIGHT", -4, 0); row:SetHeight(ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints(); row.sel:SetColorTexture(0.55, 0.38, 0.08, 0.45); row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    row.name = fs(row); row.name:SetPoint("LEFT", X[1], 0); row.name:SetWidth(X[2] - X[1] - 6)
    row.qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate"); row.qty:SetSize(40, 18); row.qty:SetPoint("LEFT", X[2] + 4, 0)
    row.qty:SetAutoFocus(false); if row.qty.SetNumeric then row.qty:SetNumeric(true) end
    row.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.qty:SetScript("OnTextChanged", function(self, user)
      if not user or not row.item then return end
      local n = tonumber(self:GetText() or "")
      state.qty[row.item.id] = (n and n > 0 and n < row.item.count) and n or nil
    end)
    row.c = {}
    for i = 1, 4 do row.c[i] = fs(row); row.c[i]:SetPoint("LEFT", X[i + 2], 0); row.c[i]:SetWidth(X[i + 3] and (X[i + 3] - X[i + 2] - 4) or 76) end
    row.note = fs(row); row.note:SetPoint("LEFT", X[7], 0); row.note:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row:SetScript("OnClick", function(self) if self.index then state.sel = self.index; PB.Draw() end end)
    row:SetScript("OnEnter", function(self)
      if not self.item then return end
      C.TipOwner(self)
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item.id) else GameTooltip:SetText(self.item.name) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bagRows[r] = row
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, d)
    local n = #(PB.list or {})
    state.offset = math.max(0, math.min(math.max(0, n - ROWS), state.offset - d * 3)); PB.Draw()
  end)
  p.foot = fs(p, "GameFontDisableSmall"); p.foot:SetPoint("BOTTOMLEFT", 10, 8); p.foot:SetPoint("RIGHT", p, "RIGHT", -10, 0)
end

local KEYS = { "home", "bb", "vendor", "de" }
function PB.DrawBags()
  local p = bagsP
  local Tr = T()
  local list = Tr.BagItems()
  PB.list = list
  p.mode:SetText(({ Tr.HomeName(), "Booty Bay", "Both houses" })[state.mode])
  local fresh = Tr.NeutralFresh()
  for i, b in ipairs(p.dur) do if i == Tr.Duration() then b:LockHighlight() else b:UnlockHighlight() end end
  local selling = Tr.SellingOn()
  for _, b in ipairs({ p.sellHome, p.sellBB, p.next }) do b:SetShown(selling) end
  for _, b in ipairs(p.dur) do b:SetShown(selling) end
  -- which rows belong to the house being sold to
  local house = state.house
  state.sel = math.max(1, math.min(state.sel, #list))
  if state.offset > math.max(0, #list - ROWS) then state.offset = math.max(0, #list - ROWS) end
  -- keep the highlight in view
  if state.sel <= state.offset then state.offset = state.sel - 1 elseif state.sel > state.offset + ROWS then state.offset = state.sel - ROWS end
  for r = 1, ROWS do
    local row = bagRows[r]
    local i = state.offset + r
    local it = list[i]
    row.item, row.index = it, i
    if not it then row:Hide() else
      row:Show()
      local x = it.x
      local w = Tr.Winner(x, state.mode)
      row.sel:SetShown(i == state.sel and house ~= nil)
      row.name:SetText(it.name)
      if not row.qty:HasFocus() then row.qty:SetText(tostring(state.qty[it.id] or it.count)) end
      row.qty:SetShown(selling)
      local vals = { x.homeLow, x.bbLow, x.vendor, x.de }
      for k = 1, 4 do
        local key = KEYS[k]
        local off = (state.mode == 1 and key == "bb") or (state.mode == 2 and key == "home") or (key == "bb" and not x.bbLow)
        local v = vals[k]
        local txt = m(v)
        if key == "bb" and not x.bbLow then txt = GREY .. "none|r" end
        if w == key and v and v > 0 then txt = GREEN .. C.Money(math.floor(v + 0.5)) .. "|r"
        elseif off then txt = GREY .. ((key == "bb" and not x.bbLow) and "none" or C.Money(math.floor(v or 0))) .. "|r" end
        row.c[k]:SetText(txt)
      end
      local note = ""
      if state.posted[it.id] then note = GREEN .. "posted " .. state.posted[it.id] .. "|r"
      elseif state.wont[it.id] then note = "|cffff8f7awon't post: " .. state.wont[it.id] .. "|r"
      elseif state.mode == 3 and fresh and x.carry and not x.carry.slow then
        local c = x.carry
        note = GOLD .. "buy up to " .. C.Money(c.upTo) .. " in " .. Tr.Short(c.from) .. " > " .. Tr.Short(c.to) .. "|r"
      elseif state.mode == 3 and fresh and x.carry and x.carry.slow then note = "|cffff8f7asells slowly at " .. Tr.HouseName(x.carry.to) .. "|r"
      elseif w == "bb" and not fresh then note = GREY .. "Booty Bay scan is over 30 min old|r" end
      row.note:SetText(note)
    end
  end
  -- status and footer
  local _, bt, bwho = Tr.Neutral()
  local ht, hwho = Tr.Home()
  local function age(t, who) return t and (math.floor((now() - t) / 60) .. " min old" .. (who and (", " .. who) or "")) or "none yet" end
  p.foot:SetText(GREY .. Tr.HomeName() .. " prices: " .. age(ht, hwho) .. "   ·   Booty Bay prices: " .. age(bt, bwho)
    .. "   ·   green = the best price   ·   Booty Bay counts 10% less (its cut)|r")
  if not selling then p.status:SetText(GREY .. "Selling from this tab is off (Settings > Auction house selling).|r")
  elseif PB.msg then p.status:SetText(PB.msg)
  elseif Tr.Conflict() then p.status:SetText("|cffff9a3a" .. Tr.Conflict() .. " also posts at the auction house: use one of them (Settings > Auction house selling turns Kina's off).|r")
  else p.status:SetText(GREY .. "At an auctioneer, press Sell to " .. Tr.HomeName() .. " or Sell to Booty Bay, then Post next. Click a row to start there.|r") end
  local okH = Tr.CanSellTo("home"); local okB = Tr.CanSellTo("bb")
  p.sellHome:SetAlpha(okH and 1 or 0.45); p.sellBB:SetAlpha(okB and 1 or 0.45)
  if house then
    local it = list[state.sel]
    local live = it and Tr.post.live[it.id]
    if Tr.post.pending then p.next:SetText("Confirm post")
    elseif it and live and (GetTime() - live.at) < 20 then p.next:SetText("Post " .. (state.qty[it.id] or it.count) .. "x")
    else p.next:SetText("Post next") end
  else p.next:SetText("Post next") end
end

-- is this row one to post at that house? (its winner in the view is that house)
local function eligible(it, house)
  if not it or state.posted[it.id] or state.wont[it.id] then return false end
  local w = T().Winner(it.x, state.mode)
  return w == house
end
local function seek(from, house)
  local list = PB.list or {}
  for i = math.max(1, from), #list do if eligible(list[i], house) then return i end end
  return nil
end
function PB.StartSelling(house)
  local Tr = T()
  local ok, why = Tr.CanSellTo(house)
  if not ok then PB.msg = "|cffff8f7a" .. why .. ".|r"; PB.Draw(); return end
  state.house = house
  PB.list = Tr.BagItems()
  local i = seek(state.sel, house) or seek(1, house)
  if not i then PB.msg = GREY .. "Nothing in your bags sells best at " .. Tr.HouseName(house) .. " in this view.|r"; state.house = nil; PB.Draw(); return end
  state.sel = i
  PB.msg = GOLD .. "Selling to " .. Tr.HouseName(house) .. ".|r Checking " .. PB.list[i].name .. "'s lowest price now..."
  Tr.Ask(PB.list[i].id)
  PB.Draw()
end
function PB.PostNext()
  local Tr = T()
  local house = state.house
  if not house then PB.msg = "|cffff8f7aPress Sell to " .. Tr.HomeName() .. " or Sell to Booty Bay first.|r"; PB.Draw(); return end
  local list = PB.list or Tr.BagItems()
  -- the highlighted row (or the next one for this house below it)
  local i = (eligible(list[state.sel], house) and state.sel) or seek(state.sel, house)
  if not i then PB.msg = GREEN .. "Done: nothing left to post at " .. Tr.HouseName(house) .. ".|r"; state.house = nil; PB.Draw(); return end
  state.sel = i
  local it = list[i]
  local res, info = Tr.Post(it, house, state.qty[it.id] or it.count)
  if res == "asked" then
    PB.msg = "Checking " .. it.name .. "'s lowest price right now... click Post next again to post it."
  elseif res == "confirm" then
    PB.msg = GOLD .. "The auction house wants it confirmed:|r click again to post " .. it.name .. " at " .. C.Money(info.unit) .. " each."
  elseif res == "posted" then
    local unit = info and info.unit
    state.posted[it.id] = unit and (C.Money(unit) .. (info.qty and (" x" .. info.qty) or "")) or ""
    PB.msg = GREEN .. "Posted " .. it.name .. (unit and (" at " .. C.Money(unit) .. " each") or "") .. " for " .. Tr.DurationText() .. ".|r"
    local nx = seek(i + 1, house)
    if nx then state.sel = nx; Tr.Ask(list[nx].id) end
  elseif res == "wont" then
    state.wont[it.id] = info
    PB.msg = "|cffff8f7a" .. it.name .. ": won't post, " .. info .. ".|r Moving on."
    local nx = seek(i + 1, house)
    if nx then state.sel = nx; Tr.Ask(list[nx].id) end
  else
    PB.msg = "|cffff8f7a" .. tostring(info) .. ".|r"
  end
  PB.Draw()
end

------------------------------------------------------------------ Transport
local tRows = {}
local function buildTrans(p)
  p.head = fs(p, "GameFontHighlight"); p.head:SetPoint("TOPLEFT", 10, -10); p.head:SetPoint("RIGHT", p, "RIGHT", -10, 0)
  p.carryB = btn(p, "Carry", 90, 22, function() state.sub = "carry"; state.offset = 0; PB.Draw() end)
  p.carryB:SetPoint("TOPLEFT", 8, -34)
  p.slowB = btn(p, "Sells slowly", 120, 22, function() state.sub = "slow"; state.offset = 0; PB.Draw() end)
  p.slowB:SetPoint("LEFT", p.carryB, "RIGHT", 6, 0)
  for r = 1, 16 do
    local row = CreateFrame("Frame", nil, p)
    row:SetPoint("TOPLEFT", 4, -64 - (r - 1) * 24); row:SetPoint("RIGHT", p, "RIGHT", -4, 0); row:SetHeight(24)
    local line = row:CreateTexture(nil, "BACKGROUND"); line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1); line:SetColorTexture(0.17, 0.13, 0.08, 1)
    row.name = fs(row); row.name:SetPoint("LEFT", 8, 0); row.name:SetWidth(200)
    row.from = chip(row); row.from:SetPoint("LEFT", 214, 0)
    row.arrow = fs(row); row.arrow:SetPoint("LEFT", row.from, "RIGHT", 4, 0); row.arrow:SetText(GREY .. ">|r")
    row.to = chip(row); row.to:SetPoint("LEFT", row.arrow, "RIGHT", 4, 0)
    row.buy = fs(row); row.buy:SetPoint("LEFT", 330, 0); row.buy:SetWidth(200)
    row.flag = chip(row); row.flag:SetPoint("LEFT", 540, 0)
    row.info = fs(row); row.info:SetPoint("LEFT", row.flag, "RIGHT", 8, 0); row.info:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      local x = self.x
      if not x then return end
      local c = x.carry
      C.TipOwner(self); GameTooltip:SetText(x.name or "", 1, 0.82, 0.3)
      GameTooltip:AddDoubleLine("Buy at " .. T().HouseName(c.from), "up to " .. C.Money(c.upTo), 1, 1, 1, 1, 0.82, 0.3)
      GameTooltip:AddDoubleLine("Sell at " .. T().HouseName(c.to), C.Money(c.sell or 0) .. "  (keeps " .. C.Money(c.net) .. ")", 1, 1, 1, 0.4, 1, 0.45)
      if c.steps and #c.steps > 0 then
        GameTooltip:AddLine("Cheap enough now: " .. table.concat(c.steps, " · "), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Above " .. C.Money(math.floor(c.net)) .. ": a loss.", 1, 0.45, 0.4)
      elseif c.depth == nil then GameTooltip:AddLine("How many are cheap enough: needs your own scan of " .. T().HouseName(c.from) .. ".", 0.6, 0.6, 0.6, true) end
      if c.sold then GameTooltip:AddLine(string.format("Sells about %.1f an hour at %s.", c.sold, T().HouseName(c.to)), 0.8, 0.8, 0.8) end
      GameTooltip:AddLine("\"Buy up to\" leaves 10% for the trip, after each house's cut.", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tRows[r] = row
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, d)
    local n = #(PB.tlist or {})
    state.offset = math.max(0, math.min(math.max(0, n - 16), state.offset - d * 3)); PB.Draw()
  end)
end
function PB.DrawTrans()
  local p = transP
  local Tr = T()
  local left, info = Tr.Paired()
  local carry, slow = {}, {}
  if left then carry, slow = Tr.CarryList() end
  local list = state.sub == "slow" and slow or carry
  PB.tlist = list
  p.slowB:SetText("Sells slowly (" .. #slow .. ")")
  if state.sub == "slow" then p.slowB:LockHighlight(); p.carryB:UnlockHighlight() else p.carryB:LockHighlight(); p.slowB:UnlockHighlight() end
  if left then
    local function who(w) return w and (C.Books and C.Books.Name and C.Books.Name(w) or w) or "you" end
    p.head:SetText(string.format("%s scan %d min old (%s)  ·  Booty Bay scan %d min old (%s)  ·  closes in %s%d:%02d|r",
      Tr.HomeName(), math.floor((now() - info.homeT) / 60), who(info.homeWho), math.floor((now() - info.bbT) / 60), who(info.bbWho),
      GREEN, math.floor(left / 60), left % 60))
  else
    local _, bt = Tr.Neutral(); local ht = Tr.Home()
    p.head:SetText(GREY .. "Transport opens when both houses have a scan under 30 minutes old (yours or another Kina's). "
      .. Tr.HomeName() .. ": " .. (ht and (math.floor((now() - ht) / 60) .. " min old") or "none") .. ". Booty Bay: "
      .. (bt and (math.floor((now() - bt) / 60) .. " min old") or "none") .. ".|r")
  end
  state.offset = math.max(0, math.min(state.offset, math.max(0, #list - 16)))
  for r = 1, 16 do
    local row = tRows[r]
    local x = list[state.offset + r]
    row.x = x
    if not x then row:Hide() else
      row:Show()
      local c = x.carry
      row.name:SetText(x.name)
      row.from:Set(c.from, Tr.Short(c.from)); row.to:Set(c.to, Tr.Short(c.to))
      row.buy:SetText(GOLD .. "buy under " .. C.Money(c.upTo) .. "|r")
      if state.sub == "slow" then
        row.flag:Set("slow", "sells slowly")
        row.info:SetText(GREY .. (c.sold and string.format("~%.1f sold an hour at %s", c.sold, Tr.HouseName(c.to)) or "") .. "|r")
      else
        if c.few then row.flag:Set("warn", "only " .. c.depth .. " worth it") else row.flag:Set(nil) end
        row.info:SetText(GREY .. "+" .. C.Money(math.max(0, math.floor(c.each))) .. " each|r")
      end
    end
  end
end

------------------------------------------------------------------ wiring into the Prices window
function PB.Attach(frame)
  if f then return end
  f = frame
  tabs = {}
  local prev
  for _, d in ipairs({ { "browse", "Browse", 80 }, { "bags", "My bags", 90 }, { "trans", "Transport", 100 } }) do
    local b = btn(f, d[2], d[3], 22, function() state.offset = 0; show(d[1]) end)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) end
    tabs[d[1]] = b
    prev = b
  end
  -- right to left: Transport, My bags, Browse (left of the close button)
  tabs.trans:ClearAllPoints(); tabs.trans:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -8)
  tabs.bags:ClearAllPoints(); tabs.bags:SetPoint("RIGHT", tabs.trans, "LEFT", -4, 0)
  tabs.browse:ClearAllPoints(); tabs.browse:SetPoint("RIGHT", tabs.bags, "LEFT", -4, 0)
  for _, b in pairs(tabs) do b:SetFrameLevel(f:GetFrameLevel() + 30) end
  bagsP = panel(f); buildBags(bagsP)
  transP = panel(f); buildTrans(transP)
  show(state.tab or "browse")
  local tick = 0
  f:HookScript("OnUpdate", function(_, el)
    tick = tick + el
    if tick < 1 then return end
    tick = 0
    if state.tab == "trans" then pcall(PB.DrawTrans) end
    if state.tab == "trans" or state.tab == "bags" then
      local paired = T().Paired()
      if tabs.trans.GetFontString and tabs.trans:GetFontString() then tabs.trans:SetAlpha(paired and 1 or 0.6) end
    end
  end)
end
function PB.Draw()
  if not f then return end
  if state.tab == "bags" and bagsP then pcall(PB.DrawBags)
  elseif state.tab == "trans" and transP then pcall(PB.DrawTrans) end
end
-- live prices and posts redraw the bag list
C.Transport.OnChange = function()
  if state.house and PB.list then
    local it = PB.list[state.sel]
    local live = it and C.Transport.post.live[it.id]
    if live and live.at and PB.msg and PB.msg:find("Checking", 1, true) then
      if live.none then PB.msg = "Nobody lists " .. it.name .. " here: click Post next to post it at the last scan's price."
      else PB.msg = GOLD .. it.name .. ": lowest listing now " .. C.Money(live.unit) .. ".|r Click Post next to post " .. (state.qty[it.id] or it.count) .. " at that price." end
    end
  end
  PB.Draw()
end
C.Transport.OnPosted = function() PB.Draw() end
C.On("BAG_UPDATE_DELAYED", function() if state.tab == "bags" then PB.Draw() end end)
C.On("AUCTION_HOUSE_CLOSED", function() state.house = nil; PB.msg = nil; PB.Draw() end)
