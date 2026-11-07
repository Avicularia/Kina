local _, C = ...
-- 1.5.0 (Taylor, Nov 7): VOUCHES (commendations). After a qualifying shared farm (15+
-- minutes, 2+ Kina users) anyone in it can vouch for a groupmate, within 24 hours of the
-- farm ending, once per person per day: Pulled their weight / Great leader / Profession
-- support / Good company. The receiver gains standing: +15 rep, only +3 when the same
-- person vouched for them in the last 7 days, half while their standing is below 0.
-- The giver earns +5 Kina XP (3 a day). Both Kinas log it (the receiver's log carries the
-- rep), the same two-sided way payments are confirmed.
local V = {}
C.Vouch = V
V.KINDS = { "Pulled their weight", "Great leader", "Profession support", "Good company" }
V.REP, V.REPEAT_REP, V.GIVE_XP = 15, 3, 5
local DAY = 86400
local function first(n) return n and (tostring(n):match("^([^%-]+)") or n) or "" end
local function lower(n) return first(n):lower() end

-- the people I farmed with in a qualifying farm that ended in the last 24 hours
function V.Eligible()
  local out, seen = {}, {}
  local me = lower(UnitName and UnitName("player"))
  for _, s in ipairs(C.db.sessions or {}) do
    if s.stop and C.Now() - s.stop <= DAY and s.sync and s.split and s.split.incomes then
      local secs = s.stop - (s.start or s.stop) - (s.pausedSecs or 0)
      local n = 0; for _ in pairs(s.split.incomes) do n = n + 1 end
      if secs >= 900 and n >= 2 then
        for who in pairs(s.split.incomes) do
          local k = lower(who)
          if k ~= me and not seen[k] then seen[k] = true; out[#out + 1] = { who = first(who), ref = (s.sync.sid or ("t" .. tostring(s.start))), farm = s.label } end
        end
      end
    end
  end
  return out
end
local function vdb()
  C.db.vouch = C.db.vouch or { given = {}, got = {} }
  local d = C.db.vouch; d.given = d.given or {}; d.got = d.got or {}
  -- keep 30 days
  for _, t in ipairs({ d.given, d.got }) do for i = #t, 1, -1 do if C.Now() - (t[i].t or 0) > 30 * DAY then table.remove(t, i) end end end
  return d
end
function V.CanVouch(who)
  local k = lower(who)
  local okFarm
  for _, e in ipairs(V.Eligible()) do if lower(e.who) == k then okFarm = e end end
  if not okFarm then return false, "only for someone in a qualifying farm with you in the last 24 hours" end
  for _, g in ipairs(vdb().given) do
    if lower(g.who) == k and C.Now() - g.t < DAY then return false, "you already vouched for them today" end
  end
  return true, okFarm
end
function V.Give(who, kind)
  local ok, e = V.CanVouch(who)
  if not ok then C.Print("can't vouch: " .. e .. "."); return false end
  kind = math.max(1, math.min(#V.KINDS, tonumber(kind) or 1))
  local d = vdb()
  table.insert(d.given, { who = first(who), kind = kind, t = C.Now(), ref = e.ref })
  if C.Log then C.Log("vouch", "gave", first(who), kind, e.ref) end
  if C.Share and C.Share.SendVouch then C.Share.SendVouch(first(who), kind, e.ref) end
  C.Print(string.format("|cff7CFC00you vouched for %s: %s.|r", first(who), V.KINDS[kind]))
  if C.PlayCue then C.PlayCue("paid") end
  return true
end
-- their Kina told mine they vouched for me
function V.OnVouch(from, kind, ref)
  kind = tonumber(kind) or 1
  if not V.KINDS[kind] then return end
  local d = vdb()
  for _, g in ipairs(d.got) do
    if lower(g.who) == lower(from) and C.Now() - g.t < DAY then return end -- one a day per person
  end
  local repeatV = false
  for _, g in ipairs(d.got) do if lower(g.who) == lower(from) and C.Now() - g.t < 7 * DAY then repeatV = true end end
  local rep = repeatV and V.REPEAT_REP or V.REP
  local m = C.Rep and C.Rep.Mine and C.Rep.Mine() or {}
  if (m.rep or 0) < 0 then rep = math.floor(rep / 2) end
  table.insert(d.got, { who = first(from), kind = kind, t = C.Now(), ref = ref, rep = rep })
  if C.Log then C.Log("vouch", "got", first(from), kind, ref or "", rep) end
  if C.Toast and C.Toast.Vouched then C.Toast.Vouched(first(from), V.KINDS[kind], rep) end
end
-- counts for the You tab
function V.Counts()
  local d = vdb()
  local byKind, total = {}, 0
  for _, g in ipairs(d.got) do byKind[g.kind] = (byKind[g.kind] or 0) + 1; total = total + 1 end
  return total, byKind
end

-- the vouch picker: who (from the farms) and what for
local function picker(anchor)
  local list = V.Eligible()
  if #list == 0 then C.Print("vouch: nobody to vouch for. It's for people in a qualifying shared farm with you in the last 24 hours."); return end
  local opts = {}
  for _, e in ipairs(list) do
    for i, k in ipairs(V.KINDS) do opts[#opts + 1] = { e.who .. ": " .. k, { e.who, i } } end
  end
  if C.Cos and C.Cos.OpenList then C.Cos.OpenList(anchor, "Vouch for", opts, function(v) V.Give(v[1], v[2]) end) end
end
V.Picker = picker

------------------------------------------------------------------ end-of-farm commendation window
-- 1.5.0 (Taylor): like Aion 2's commendations, the moment a qualifying farm ends a window
-- pops up with a card for each groupmate: portrait in their standing ring, name, standing,
-- what you're vouching for, and one Commend button. It counts down and closes on its own
-- (hovering it holds the timer). Closing it loses nothing: the You tab button still works
-- for 24 hours.
V.PROMPT_SECS = 45
local pop
local CARD_W, CARD_H, PER_ROW = 150, 196, 4
local function unitFor(name)
  local k = lower(name)
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = raid and ("raid" .. i) or ("party" .. i)
    local ok, un = pcall(UnitName, u)
    if ok and un and not (issecretvalue and issecretvalue(un)) and lower(un) == k then return u end
  end
end
local function makeCard(parent)
  local c = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  c:SetSize(CARD_W, CARD_H)
  if c.SetBackdrop then
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    c:SetBackdropColor(0.10, 0.08, 0.06, 0.92); c:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
  end
  c.box = CreateFrame("Button", nil, c); c.box:SetSize(64, 64); c.box:SetPoint("TOP", 0, -24)
  c.box:SetScript("OnClick", function() if c.who and C.Profile and not c.preview then C.Profile.Show(c.who) end end) -- 1.5.1
  c.portrait = c.box:CreateTexture(nil, "ARTWORK")
  c.cos = C.Cos and C.Cos.Portrait(c.box, c.portrait)
  if c.cos then c.cos.plate:Hide(); c.cos.num:Hide() end
  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); c.name:SetPoint("TOP", c.box, "BOTTOM", 0, -14)
  if C.Cos then C.Cos.Font(c.name, 15, "OUTLINE") end
  c.stand = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.stand:SetPoint("TOP", c.name, "BOTTOM", 0, -3)
  c.kindB = CreateFrame("Button", nil, c, "UIPanelButtonTemplate"); c.kindB:SetSize(CARD_W - 16, 20); c.kindB:SetPoint("BOTTOM", 0, 36)
  local fs = c.kindB:GetFontString(); if fs then fs:SetFont(STANDARD_TEXT_FONT, 10, "") end
  c.go = CreateFrame("Button", nil, c, "UIPanelButtonTemplate"); c.go:SetSize(CARD_W - 16, 24); c.go:SetPoint("BOTTOM", 0, 9)
  return c
end
local function fillCard(c, e)
  c.who, c.kind, c.done = e.who, c.kind or 1, false
  local u = unitFor(e.who)
  if u and SetPortraitTexture then pcall(SetPortraitTexture, c.portrait, u) else c.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
  local stand = C.Share and C.Share.StandingOf and C.Share.StandingOf(e.who)
  local sname = (type(stand) == "number" and C.Rep and C.Rep.StandingOf) and C.Rep.StandingOf(stand) or nil
  if c.cos and C.Cos then C.Cos.UpdatePortrait(c.cos, sname or "Unproven", 1); c.cos.plate:Hide(); c.cos.num:Hide() end
  c.name:SetText(e.who)
  c.stand:SetText(sname and ((C.Cos and C.Cos.StandingColor(sname) or "") .. sname .. "|r") or "|cff9d9d9dno Kina standing yet|r")
  local function paint()
    c.kindB:SetText(V.KINDS[c.kind] .. "  v")
    if c.done then
      c.go:SetText("|cff7CFC00Commended|r"); c.go:Disable(); c.kindB:Disable()
      if c.SetBackdropBorderColor then c:SetBackdropBorderColor(1, 0.82, 0.3, 1) end
    else
      c.go:SetText("Commend"); c.go:Enable(); c.kindB:Enable()
      if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.55, 0.45, 0.25, 1) end
    end
  end
  if not c.preview and not V.CanVouch(e.who) then c.done = true end
  c.kindB:SetScript("OnClick", function(self)
    local opts = {}
    for i, k in ipairs(V.KINDS) do opts[#opts + 1] = { k, i } end
    if C.Cos then C.Cos.OpenList(self, "Commend " .. e.who .. " for", opts, function(i) c.kind = i; paint() end) end
  end)
  c.go:SetScript("OnClick", function()
    if c.preview then c.done = true; paint(); return end
    if V.Give(e.who, c.kind) then c.done = true; paint() end
  end)
  paint()
end
function V.ShowPrompt(preview)
  local open = {}
  if preview then
    open = { { who = "Triforce" }, { who = "Elwyn" }, { who = "Stranger" } }
  else
    for _, e in ipairs(V.Eligible()) do if V.CanVouch(e.who) then open[#open + 1] = e end end
  end
  if #open == 0 then return false end
  if not pop then
    pop = CreateFrame("Frame", "KinaCommend", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pop:SetFrameStrata("DIALOG"); pop:SetClampedToScreen(true); pop:EnableMouse(true); pop:SetMovable(true)
    pop:RegisterForDrag("LeftButton"); pop:SetScript("OnDragStart", pop.StartMoving); pop:SetScript("OnDragStop", pop.StopMovingOrSizing)
    if pop.SetBackdrop then
      pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      pop:SetBackdropColor(0.05, 0.04, 0.03, 0.95); pop:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    pop.title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); pop.title:SetPoint("TOP", 0, -12)
    if C.Cos then C.Cos.Font(pop.title, 20, "OUTLINE") end
    pop.title:SetText("Commend your party"); pop.title:SetTextColor(1, 0.85, 0.45)
    pop.sub = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pop.sub:SetPoint("TOP", pop.title, "BOTTOM", 0, -4)
    pop.close = CreateFrame("Button", nil, pop, "UIPanelCloseButton"); pop.close:SetPoint("TOPRIGHT", -2, -2)
    pop.bar = CreateFrame("StatusBar", nil, pop); pop.bar:SetHeight(6)
    pop.bar:SetPoint("BOTTOMLEFT", 12, 10); pop.bar:SetPoint("BOTTOMRIGHT", -12, 10)
    pop.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); pop.bar:SetStatusBarColor(0.95, 0.75, 0.25)
    pop.bar:SetMinMaxValues(0, V.PROMPT_SECS)
    pop.cards = {}
    pop:SetScript("OnUpdate", function(self, el)
      if self:IsMouseOver() then return end -- hovering holds the timer
      self.left = (self.left or 0) - el
      self.bar:SetValue(math.max(0, self.left))
      if self.left <= 0 then self:Hide() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "KinaCommend") end
  end
  for _, c in ipairs(pop.cards) do c:Hide() end
  local n = math.min(#open, 8)
  local cols = math.min(n, PER_ROW)
  local rows = math.ceil(n / PER_ROW)
  for i = 1, n do
    local c = pop.cards[i] or makeCard(pop); pop.cards[i] = c
    c.kind = 1
    local r, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
    local inRow = math.min(PER_ROW, n - r * PER_ROW)
    local x0 = ((cols - inRow) * (CARD_W + 10)) / 2
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", pop, "TOPLEFT", 14 + x0 + col * (CARD_W + 10), -58 - r * (CARD_H + 10))
    c.preview = preview; fillCard(c, open[i]); c:Show()
  end
  pop.sub:SetText(preview and "|cffff9933Preview: nothing will be sent.|r" or "Good farm? A commendation raises their standing. Missed it? Kina > You works for 24 hours.")
  pop:SetSize(math.max(420, 28 + cols * (CARD_W + 10) - 10), 58 + rows * (CARD_H + 10) + 24)
  pop:ClearAllPoints(); pop:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  pop.left = V.PROMPT_SECS; pop.bar:SetValue(V.PROMPT_SECS)
  pop:Show()
  return true
end
