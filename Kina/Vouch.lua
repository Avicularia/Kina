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
V.KINDS = { "Pulled their weight", "Great leader", "Profession support", "Good company",
  -- 1.5.2 (Taylor): bad commendations (5-8), always shown in red with a thumbs down
  "Didn't pull their weight", "Left the group early", "Greedy with loot", "Rude or toxic" }
V.GOOD_N = 4
V.REP, V.REPEAT_REP, V.GIVE_XP = 15, 3, 5
V.BAD_REP, V.BAD_REPEAT_REP, V.BAD_PER_DAY = -10, -3, 3
function V.IsBad(k) return (tonumber(k) or 1) > V.GOOD_N end
V.RED = "|cffff4030"
local UP, DOWN = "Interface\\AddOns\\Kina\\Media\\Cos\\thumb_up", "Interface\\AddOns\\Kina\\Media\\Cos\\thumb_down"
V.UP_ICON, V.DOWN_ICON = UP, DOWN
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
          if k ~= me and not (C.IsMyChar and C.IsMyChar(who)) and not seen[k] then seen[k] = true; out[#out + 1] = { who = first(who), ref = (s.sync.sid or ("t" .. tostring(s.start))), farm = s.label } end
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
function V.CanVouch(who, kind)
  local k = lower(who)
  if C.IsMyChar and C.IsMyChar(who) then return false, "you can't commend yourself or your own characters" end
  local okFarm
  for _, e in ipairs(V.Eligible()) do if lower(e.who) == k then okFarm = e end end
  if not okFarm then return false, "only for someone in a qualifying farm with you in the last 24 hours" end
  for _, g in ipairs(vdb().given) do
    if lower(g.who) == k and C.Now() - g.t < DAY then return false, "you already vouched for them today" end
  end
  if kind and V.IsBad(kind) then
    local n = 0
    for _, g in ipairs(vdb().given) do if V.IsBad(g.kind) and C.Now() - g.t < DAY then n = n + 1 end end
    if n >= V.BAD_PER_DAY then return false, "you've given " .. V.BAD_PER_DAY .. " bad commendations today" end
  end
  return true, okFarm
end
function V.Give(who, kind)
  kind = math.max(1, math.min(#V.KINDS, tonumber(kind) or 1))
  local ok, e = V.CanVouch(who, kind)
  if not ok then C.Print("can't commend: " .. e .. "."); return false end
  local d = vdb()
  table.insert(d.given, { who = first(who), kind = kind, t = C.Now(), ref = e.ref })
  if C.Log then C.Log("vouch", "gave", first(who), kind, e.ref) end
  if C.Share and C.Share.SendVouch then C.Share.SendVouch(first(who), kind, e.ref) end
  if V.IsBad(kind) then
    C.Print(string.format("%syou gave %s a bad commendation: %s.|r", V.RED, first(who), V.KINDS[kind]))
  else
    C.Print(string.format("|cff7CFC00you vouched for %s: %s.|r", first(who), V.KINDS[kind]))
    if C.PlayCue then C.PlayCue("paid") end
  end
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
  if C.IsMyChar and C.IsMyChar(from) then return end -- 1.5.2: never from your own characters
  local bad = V.IsBad(kind)
  local repeatV = false
  for _, g in ipairs(d.got) do if lower(g.who) == lower(from) and V.IsBad(g.kind) == bad and C.Now() - g.t < 7 * DAY then repeatV = true end end
  local rep
  if bad then
    rep = repeatV and V.BAD_REPEAT_REP or V.BAD_REP
    -- a bad commendation from someone who is in bad standing themselves costs nothing
    local theirs = C.Share and C.Share.StandingOf and C.Share.StandingOf(from)
    if type(theirs) == "number" and theirs < 0 then rep = 0 end
  else
    rep = repeatV and V.REPEAT_REP or V.REP
    local m = C.Rep and C.Rep.Mine and C.Rep.Mine() or {}
    if (m.rep or 0) < 0 then rep = math.floor(rep / 2) end
  end
  table.insert(d.got, { who = first(from), kind = kind, t = C.Now(), ref = ref, rep = rep })
  if C.Log then C.Log("vouch", "got", first(from), kind, ref or "", rep) end
  if C.Toast and C.Toast.Vouched then C.Toast.Vouched(first(from), V.KINDS[kind], rep, bad) end
end
-- counts for the You tab
function V.Counts()
  local d = vdb()
  local byKind, total, bad = {}, 0, 0
  for _, g in ipairs(d.got) do
    byKind[g.kind] = (byKind[g.kind] or 0) + 1
    if V.IsBad(g.kind) then bad = bad + 1 else total = total + 1 end
  end
  return total, byKind, bad
end

-- the vouch picker: who (from the farms) and what for
local function picker(anchor)
  local list = V.Eligible()
  if #list == 0 then C.Print("commend: nobody to commend. It's for people in a qualifying shared farm with you in the last 24 hours."); return end
  local opts = {}
  for _, e in ipairs(list) do opts[#opts + 1] = { e.who, e.who } end
  if C.Cos and C.Cos.OpenList then C.Cos.OpenList(anchor, "Commend who?", opts, function(w) if C.Profile then C.Profile.Show(w) end end) end
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
-- 1.5.2: a thumbs up (gold) or thumbs down (red, outlined and filled red) button
function V.ThumbButton(parent, bad, w, h, label)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(w, h)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    if bad then b:SetBackdropColor(0.40, 0.04, 0.03, 0.95); b:SetBackdropBorderColor(1, 0.18, 0.12, 1)
    else b:SetBackdropColor(0.16, 0.12, 0.04, 0.95); b:SetBackdropBorderColor(0.95, 0.75, 0.30, 1) end
  end
  local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(h - 4, h - 4); ic:SetPoint("LEFT", 4, 0); ic:SetTexture(bad and DOWN or UP)
  local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", ic, "RIGHT", 4, 0); t:SetPoint("RIGHT", -4, 0)
  t:SetJustifyH("LEFT"); t:SetText(bad and (V.RED .. (label or "Bad") .. "|r") or ("|cffffd100" .. (label or "Commend") .. "|r"))
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 2, -2); hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(bad and 1 or 1, bad and 0.2 or 0.85, bad and 0.15 or 0.4, 0.18)
  b:SetMotionScriptsWhileDisabled(true)
  return b
end
-- the reasons list for one side (the bad list is red throughout)
function V.OpenReasons(anchor, who, bad, onPick)
  local opts = {}
  for i, k in ipairs(V.KINDS) do
    if V.IsBad(i) == bad then opts[#opts + 1] = { bad and (V.RED .. k .. "|r") or k, i } end
  end
  if C.Cos and C.Cos.OpenList then
    C.Cos.OpenList(anchor, bad and (V.RED .. "Bad commendation for " .. who .. "|r") or ("Commend " .. who .. " for"), opts, onPick, bad and "bad" or nil)
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
  c.up = V.ThumbButton(c, false, CARD_W - 16, 26, "Commend"); c.up:SetPoint("BOTTOM", 0, 40)
  c.down = V.ThumbButton(c, true, CARD_W - 16, 26, "Bad"); c.down:SetPoint("BOTTOM", 0, 9)
  c.result = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.result:SetPoint("BOTTOM", 0, 22); c.result:SetWidth(CARD_W - 12)
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
    if c.done then
      c.up:Hide(); c.down:Hide(); c.result:Show()
      if c.gaveKind and V.IsBad(c.gaveKind) then
        c.result:SetText(V.RED .. "|T" .. DOWN .. ":16|t " .. V.KINDS[c.gaveKind] .. "|r")
        if c.SetBackdropBorderColor then c:SetBackdropBorderColor(1, 0.18, 0.12, 1) end
      else
        c.result:SetText(c.gaveKind and ("|cff7CFC00|T" .. UP .. ":16|t " .. V.KINDS[c.gaveKind] .. "|r") or "|cff9d9d9ddone today|r")
        if c.SetBackdropBorderColor then c:SetBackdropBorderColor(1, 0.82, 0.3, 1) end
      end
    else
      c.up:Show(); c.down:Show(); c.result:Hide()
      if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.55, 0.45, 0.25, 1) end
    end
  end
  c.gaveKind = nil
  if not c.preview and not V.CanVouch(e.who) then c.done = true end
  local function give(i)
    if c.preview or V.Give(e.who, i) then c.done = true; c.gaveKind = i; paint() end
  end
  c.up:SetScript("OnClick", function(self) V.OpenReasons(self, e.who, false, give) end)
  c.down:SetScript("OnClick", function(self) V.OpenReasons(self, e.who, true, give) end)
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
