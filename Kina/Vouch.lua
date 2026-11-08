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
-- 1.5.3 (Taylor): +10 / -10, the same size both ways. Per farm you can commend at most 2
-- people (any number of bad ones), and one or the other per person, never both.
V.REP, V.GIVE_XP = 10, 5
V.BAD_REP = -10
V.GOOD_PER_FARM = 2
function V.IsBad(k) return (tonumber(k) or 1) > V.GOOD_N end
V.RED = "|cffff4030"
local UP, DOWN = "Interface\\AddOns\\Kina\\Media\\Cos\\thumb_up", "Interface\\AddOns\\Kina\\Media\\Cos\\thumb_down"
V.UP_ICON, V.DOWN_ICON = UP, DOWN
local DAY = 86400
local function first(n) return n and (tostring(n):match("^([^%-]+)") or n) or "" end
local function lower(n) return first(n):lower() end

local function vdb()
  C.db.vouch = C.db.vouch or { given = {}, got = {} }
  local d = C.db.vouch; d.given = d.given or {}; d.got = d.got or {}; d.closed = d.closed or {}
  -- 1.5.4: a farm's commendations close with its window (kept a few days)
  for ref, t in pairs(d.closed) do if C.Now() - t > 3 * DAY then d.closed[ref] = nil end end
  -- keep 30 days
  for _, t in ipairs({ d.given, d.got }) do for i = #t, 1, -1 do if C.Now() - (t[i].t or 0) > 30 * DAY then table.remove(t, i) end end end
  return d
end
local function givenIn(ref, who)
  for _, g in ipairs(vdb().given) do if g.ref == ref and lower(g.who) == lower(who) then return g end end
end
function V.GoodLeft(ref)
  local n = 0
  for _, g in ipairs(vdb().given) do if g.ref == ref and not V.IsBad(g.kind) then n = n + 1 end end
  return math.max(0, V.GOOD_PER_FARM - n)
end
-- the people from my qualifying farms (ended in the last 24 hours) I haven't commended
-- for that farm yet, newest farm first
function V.Eligible()
  local out, seen = {}, {}
  local me = lower(UnitName and UnitName("player"))
  local ss = C.db.sessions or {}
  for i = 1, #ss do -- (newest first: farms are stored newest at the front)
    local s = ss[i]
    if s.stop and C.Now() - s.stop <= DAY and s.sync and s.split and s.split.incomes then
      local secs = s.stop - (s.start or s.stop) - (s.pausedSecs or 0)
      local n = 0; for _ in pairs(s.split.incomes) do n = n + 1 end
      if secs >= 900 and n >= 2 then
        local ref = s.sync.sid or ("t" .. tostring(s.start))
        if vdb().closed[ref] then n = 0 end -- (1.5.4) its window was closed: too late
        for who in pairs(n >= 2 and s.split.incomes or {}) do
          local k = lower(who)
          if k ~= me and not (C.IsMyChar and C.IsMyChar(who)) and not seen[k] and not givenIn(ref, who) then
            seen[k] = true; out[#out + 1] = { who = first(who), ref = ref, farm = s.label }
          end
        end
      end
    end
  end
  return out
end
function V.CanVouch(who, kind)
  local k = lower(who)
  if C.IsMyChar and C.IsMyChar(who) then return false, "you can't commend yourself or your own characters" end
  local okFarm
  for _, e in ipairs(V.Eligible()) do if lower(e.who) == k then okFarm = e end end
  if not okFarm then return false, "only for someone in a qualifying farm with you in the last 24 hours (and once per farm)" end
  if kind and not V.IsBad(kind) and V.GoodLeft(okFarm.ref) <= 0 then
    return false, "you've commended " .. V.GOOD_PER_FARM .. " people from this farm already (bad commendations are still open)"
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
-- was this player in my farm `ref` (a qualifying shared farm, ended in the last 2 days)?
function V.FarmMate(from, ref)
  if not ref or ref == "" then return false end
  local k = lower(from)
  for _, s in ipairs(C.db.sessions or {}) do
    local sref = (s.sync and s.sync.sid) or ("t" .. tostring(s.start))
    if sref == ref then
      if not (s.stop and C.Now() - s.stop <= 2 * DAY and s.split and s.split.incomes) then return false end
      if s.stop - (s.start or s.stop) - (s.pausedSecs or 0) < 900 then return false end
      for who in pairs(s.split.incomes) do if lower(who) == k then return true end end
      return false
    end
  end
  return false
end
-- their Kina told mine they vouched for me
function V.OnVouch(from, kind, ref)
  kind = tonumber(kind) or 1
  if not V.KINDS[kind] then return end
  local d = vdb()
  for _, g in ipairs(d.got) do
    -- one per person per farm (older Kinas sent no farm: one a day)
    if lower(g.who) == lower(from) and ((ref and ref ~= "" and g.ref == ref) or ((not ref or ref == "") and C.Now() - g.t < DAY)) then return end
  end
  if C.IsMyChar and C.IsMyChar(from) then return end -- 1.5.2: never from your own characters
  -- 0.9.1 (security): only from someone who was in that farm with me, and only for a
  -- farm that ended in the last 2 days (made-up farm names used to allow endless
  -- thumbs down from anyone)
  if not V.FarmMate(from, ref) then return end
  local bad = V.IsBad(kind)
  -- 1.5.4 (Taylor): +10 / -10 every time, no softening; multipliers are applied to
  -- gains when the standing is worked out (Rep.lua)
  local rep = bad and V.BAD_REP or V.REP
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
    else b:SetBackdropColor(0.16, 0.12, 0.04, 0.95); b:SetBackdropBorderColor(1, 0.62, 0.06, 1) end
  end
  local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(h - 4, h - 4); ic:SetPoint("LEFT", 4, 0); ic:SetTexture(bad and DOWN or UP)
  local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", ic, "RIGHT", 4, 0); t:SetPoint("RIGHT", -4, 0)
  t:SetJustifyH("LEFT"); t:SetText(bad and (V.RED .. (label or "Disgraced") .. "|r") or ("|cffffc54a" .. (label or "Commend") .. "|r"))
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
    c:SetBackdropColor(0.10, 0.08, 0.06, 0.92); c:SetBackdropBorderColor(0.61, 0.42, 0.15, 1)
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
  c.down = V.ThumbButton(c, true, CARD_W - 16, 26, "Disgraced"); c.down:SetPoint("BOTTOM", 0, 9)
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
        if c.SetBackdropBorderColor then c:SetBackdropBorderColor(1, 0.62, 0.04, 1) end
      end
    else
      c.up:Show(); c.down:Show(); c.result:Hide()
      if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.61, 0.42, 0.15, 1) end
      -- 1.5.3: only 2 good commendations per farm; bad ones stay open
      c.upOK = c.preview and ((pop and pop.previewGood or 0) < V.GOOD_PER_FARM) or (not c.preview and V.CanVouch(e.who, 1))
      c.up:SetAlpha(c.upOK and 1 or 0.35)
    end
  end
  c.paint = paint
  c.gaveKind = nil
  if not c.preview and not V.CanVouch(e.who) then c.done = true end
  local function give(i)
    if c.preview or V.Give(e.who, i) then
      if c.preview and not V.IsBad(i) and pop then pop.previewGood = (pop.previewGood or 0) + 1 end
      c.done = true; c.gaveKind = i
      for _, o in ipairs(pop and pop.cards or {}) do if o:IsShown() and o.paint then o.paint() end end
      paint()
    end
  end
  c.up:SetScript("OnClick", function(self)
    if not c.upOK then C.Print("you can commend " .. V.GOOD_PER_FARM .. " people per farm; bad commendations are still open."); return end
    V.OpenReasons(self, e.who, false, give)
  end)
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
    pop:SetFrameStrata("FULLSCREEN_DIALOG"); pop:SetClampedToScreen(true); pop:EnableMouse(true); pop:SetMovable(true)
    pop:RegisterForDrag("LeftButton"); pop:SetScript("OnDragStart", pop.StartMoving); pop:SetScript("OnDragStop", pop.StopMovingOrSizing)
    if pop.SetBackdrop then
      pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      pop:SetBackdropColor(0.05, 0.04, 0.03, 0.95); pop:SetBackdropBorderColor(0.94, 0.58, 0.03, 1)
    end
    pop.title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); pop.title:SetPoint("TOP", 0, -12)
    if C.Cos then C.Cos.Font(pop.title, 20, "OUTLINE") end
    pop.title:SetText("Commend your party"); pop.title:SetTextColor(1, 0.79, 0.36)
    pop.sub = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pop.sub:SetPoint("TOP", pop.title, "BOTTOM", 0, -4)
    -- 1.5.4 (Taylor): this window is the ONLY place to commend. No timer, no Escape:
    -- it stays until you click Done, and then that farm's commendations are closed.
    pop.done = CreateFrame("Button", nil, pop, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(pop.done) end; pop.done:SetSize(120, 24); pop.done:SetPoint("BOTTOM", 0, 10)
    pop.done:SetText("Done")
    pop.done:SetScript("OnClick", function() pop:Hide() end)
    pop:SetScript("OnHide", function(self)
      if self.preview then return end
      local d = vdb()
      for ref in pairs(self.refs or {}) do d.closed[ref] = C.Now() end
    end)
    pop.cards = {}
  end
  for _, c in ipairs(pop.cards) do c:Hide() end
  pop.previewGood = 0
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
  pop.sub:SetText(preview and "|cffff9933Preview: nothing will be sent.|r" or "Thumbs up for up to " .. V.GOOD_PER_FARM .. " people, thumbs down for anyone. This is your only chance: when you click Done, it's closed.")
  pop:SetSize(math.max(460, 28 + cols * (CARD_W + 10) - 10), 58 + rows * (CARD_H + 10) + 34)
  pop:ClearAllPoints(); pop:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  pop.preview = preview
  pop.refs = {}
  for i = 1, n do if open[i].ref then pop.refs[open[i].ref] = true end end
  pop:Show()
  return true
end
