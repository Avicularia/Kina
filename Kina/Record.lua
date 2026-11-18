-- Kina: a player's record and Kina high score (1.0.5, Taylor's mock approved Nov 16).
-- Taylor: "When I click on someone's profile, I can't see if they have any derogatory votes
-- or collections... Scarlet lost her proven rank today and I don't know why."
-- Each Kina tells others who open its user's profile (asked for, never broadcast):
--   * standing now, bad votes received (a count; never who gave them), debts that ran
--     out (count and when the last one did), what they owe now and when it's due, open
--     disputes, commends received
--   * the last 5 standing changes, each with its reason
--   * their Kina high score: the best gold-per-hour farm (15 min or longer), with its stats
-- What OTHERS owe them is never shared. All of it is what their Kina reports (unverified).
-- It travels as a hidden debt-note-style message ("T" rqr / rec): group, or the guild.
local _, C = ...
local REC = {}
C.Record = REC

local function b36(n)
  n = math.floor(math.abs(tonumber(n) or 0)); local s, d = "", "0123456789abcdefghijklmnopqrstuvwxyz"
  repeat local r = n % 36; s = d:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) until n == 0
  return s
end
local function n36(s) return tonumber(s or "", 36) end
local asked = {}
local function first(n) return C.FirstName and C.FirstName(n) or (n and n:match("^([^%s%-]+)")) end
local function clean(s, max) s = tostring(s or ""):gsub("[|;:,=#~]", " "); return s:sub(1, max or 24) end

------------------------------------------------------------------ mine
-- the farm with the best gold per hour (15 minutes or longer)
function REC.MyHighScore()
  local best, bs
  for _, s in ipairs(C.db.sessions or {}) do
    if s.stop and s.start and (s.stop - s.start) >= 900 then
      local ok, sum = pcall(C.SessionSummary, s)
      if ok and sum and sum.secs and sum.secs >= 900 and (sum.perHour or 0) > 0 and (not best or sum.perHour > best.perHour) then best, bs = sum, s end
    end
  end
  if not best then return nil end
  return { gph = math.floor(best.perHour), total = math.floor(best.total or 0), secs = math.floor(best.secs), kills = best.kills or 0,
    label = bs.label or bs.zone or "farm", t = bs.start, s = bs }
end

local REASON = { lapsed = "a debt ran out", unlapsed = "a lapsed debt was cleared", farm = "group farm", pay = "paid a debt",
  receipt = "a debt was paid to them", forgive = "forgave a debt", vouched = "commended", decay = "a week with no farms",
  jail = "a fresh start", extend = "more time on a debt", short = "paid part of a debt", refused = "a payment refused",
  breakpoint = "too many bad votes", vouchgave = "commended someone", tour = "finished the tour" }
REC.REASON = REASON

function REC.Mine()
  local r = { stand = C.Share and C.Share.MyStanding and C.Share.MyStanding() or 0 }
  local good, _, bad = 0, nil, 0
  if C.Vouch and C.Vouch.Counts then good, _, bad = C.Vouch.Counts() end
  r.good, r.bad = good or 0, bad or 0
  r.lapses, r.lastLapse = 0, nil
  local ev = {}
  if C.Rep and C.Rep.History then
    local ok, gains = pcall(C.Rep.History)
    for _, g in ipairs(ok and gains or {}) do
      if g.kind == "lapsed" then r.lapses = r.lapses + 1; r.lastLapse = g.t end
      if g.kind == "unlapsed" then r.lapses = math.max(0, r.lapses - 1) end
      local rep = math.floor((g.rep or 0) + 0.5)
      if rep ~= 0 then ev[#ev + 1] = { t = g.t, rep = rep, kind = (g.kind == "vouched" and rep < 0) and "badvote" or g.kind } end
    end
  end
  r.recent = {}
  for i = #ev, math.max(1, #ev - 4), -1 do r.recent[#r.recent + 1] = ev[i] end
  r.owe, r.oweN = 0, 0
  for _, d in ipairs(C.Debts and C.Debts() or {}) do
    if d.dir == "owe" then r.owe = r.owe + (d.amt or 0); r.oweN = r.oweN + 1 end
  end
  r.disputes = 0
  for _, p in ipairs(C.db.forgive and C.db.forgive.pending or {}) do if p.kind == "dsp" then r.disputes = r.disputes + 1 end end
  for _ in pairs(C.db.forgive and C.db.forgive.asks or {}) do r.disputes = r.disputes + 1 end
  r.hs = REC.MyHighScore()
  return r
end

-- s=stand;g=good;b=bad;l=lapses,last;o=owe,n;d=disputes;h=gph,total,secs,kills,label,t;e=t:rep:kind,...
function REC.Encode(r)
  local p = {}
  p[#p + 1] = "s=" .. (r.stand < 0 and "-" or "") .. b36(r.stand)
  p[#p + 1] = "g=" .. b36(r.good) .. ";b=" .. b36(r.bad)
  p[#p + 1] = "l=" .. b36(r.lapses) .. "," .. b36(r.lastLapse or 0)
  p[#p + 1] = "o=" .. b36(r.owe) .. "," .. b36(r.oweN)
  p[#p + 1] = "d=" .. b36(r.disputes)
  if r.hs then
    p[#p + 1] = "h=" .. table.concat({ b36(r.hs.gph), b36(r.hs.total), b36(r.hs.secs), b36(r.hs.kills), clean(r.hs.label, 20), b36(r.hs.t or 0) }, ",")
  end
  local e = {}
  for _, x in ipairs(r.recent or {}) do e[#e + 1] = b36(x.t or 0) .. ":" .. (x.rep < 0 and "-" or "") .. b36(x.rep) .. ":" .. clean(x.kind, 10) end
  if #e > 0 then p[#p + 1] = "e=" .. table.concat(e, ",") end
  return table.concat(p, ";")
end
function REC.Decode(s)
  local r = { recent = {} }
  for k, v in tostring(s or ""):gmatch("(%a)=([^;]*)") do
    if k == "s" then local neg, n = v:match("^(%-?)(%w+)$"); r.stand = (n36(n) or 0) * (neg == "-" and -1 or 1)
    elseif k == "g" then r.good = n36(v) or 0
    elseif k == "b" then r.bad = n36(v) or 0
    elseif k == "l" then local a, b = v:match("^(%w+),(%w+)$"); r.lapses = n36(a) or 0; r.lastLapse = (n36(b) or 0) > 0 and n36(b) or nil
    elseif k == "o" then local a, b = v:match("^(%w+),(%w+)$"); r.owe = n36(a) or 0; r.oweN = n36(b) or 0
    elseif k == "d" then r.disputes = n36(v) or 0
    elseif k == "h" then
      local a, b, c, d, lab, t = v:match("^(%w+),(%w+),(%w+),(%w+),([^,]*),(%w+)$")
      if a then r.hs = { gph = n36(a), total = n36(b), secs = n36(c), kills = n36(d), label = lab, t = n36(t) } end
    elseif k == "e" then
      for t, neg, rep, kind in v:gmatch("(%w+):(%-?)(%w+):(%a+)") do
        r.recent[#r.recent + 1] = { t = n36(t), rep = (n36(rep) or 0) * (neg == "-" and -1 or 1), kind = kind }
      end
    end
  end
  return r
end

------------------------------------------------------------------ asking and answering
local function store() C.db.records = C.db.records or {}; return C.db.records end
function REC.Request(name)
  local who = first(name)
  if not who or (C.IsMyChar and C.IsMyChar(who)) then return end
  if asked[who] and C.Now() - asked[who] < 30 then return end
  asked[who] = C.Now()
  if C.Share and C.Share.SendForgive then pcall(C.Share.SendForgive, who, 0, "", "rqr") end
end
local lastSent = {}
function REC.OnRequest(from)
  from = first(from)
  if lastSent[from] and C.Now() - lastSent[from] < 20 then return end
  lastSent[from] = C.Now()
  local ok, r = pcall(REC.Mine)
  if not ok or not r then return end
  if C.Share and C.Share.SendForgive then pcall(C.Share.SendForgive, from, 0, REC.Encode(r), "rec") end
end
function REC.OnRecord(from, label)
  local r = REC.Decode(label)
  r.at = C.Now()
  store()[first(from) or "?"] = r
  if C.Refresh then pcall(C.Refresh) end
  if REC.panel and REC.panel:IsShown() and REC.panel.who == first(from) then REC.Show(from) end
end
function REC.Of(name)
  local who = first(name)
  if C.IsMyChar and C.IsMyChar(who) then local ok, r = pcall(REC.Mine); return ok and r or nil end
  return store()[who or ""]
end

------------------------------------------------------------------ wording
local GOLD, GREY, GREEN, RED, ORANGE = "|cffffc54a", "|cff9d9d9d", "|cff6ee678", "|cffff5a50", "|cffff9646"
local function day(t) return t and date and date("%b %d", t) or "?" end
function REC.HighScoreText(r)
  if not (r and r.hs and r.hs.gph) then return GREY .. "no farm yet|r" end
  return GOLD .. C.Money(r.hs.gph) .. "/hr|r  " .. GREY .. clean(r.hs.label, 20) .. "|r"
end
-- 1.0.5 (Taylor: "asking their Kina" never changed): say why there's no record yet.
-- Kina 1.0.4 and older can't answer, and an answer needs them in your group or online
-- in your guild.
local function verNum(v) local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)"); return a and (tonumber(a) * 10000 + tonumber(b) * 100 + (tonumber(c) or 0)) or nil end
function REC.Waiting(name)
  local who = first(name)
  local pr = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(who)
  local v = pr and verNum(pr.ver)
  if v and v < 10005 then return "needs Kina 1.0.5", "Their Kina (" .. tostring(pr.ver) .. ") can't share a record yet. It shows once they update." end
  if asked[who] and C.Now() - asked[who] > 15 then return "no answer yet", "Their Kina answers when they're in your group or online in your guild. Kina asks again next time you open this." end
  return "asking their Kina...", "Waiting for their Kina to answer."
end
function REC.Summary(r, who)
  if not r then return GREY .. (who and REC.Waiting(who) or "asking their Kina...") .. "|r" end
  local bits = {}
  bits[#bits + 1] = (r.bad or 0) > 0 and (RED .. r.bad .. " bad vote" .. (r.bad == 1 and "" or "s") .. "|r") or (GREEN .. "no bad votes|r")
  if (r.lapses or 0) > 0 then bits[#bits + 1] = RED .. r.lapses .. " ran out|r" end
  if (r.owe or 0) >= 1 then bits[#bits + 1] = ORANGE .. "owes " .. C.Money(math.floor(r.owe)) .. "|r" end
  return table.concat(bits, GREY .. "  ·  |r")
end

------------------------------------------------------------------ the record window
function REC.Show(name)
  local who = first(name)
  local r = REC.Of(who)
  local f = REC.panel
  if not f then
    f = CreateFrame("Frame", "KinaRecordPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(640, 360); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(120); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if C.Skin and C.Skin.Panel then C.Skin.Panel(f) elseif f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0.07, 0.055, 0.04, 0.97); f:SetBackdropBorderColor(0.6, 0.45, 0.2)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 18, -16)
    if C.Cos and C.Cos.Font then C.Cos.Font(f.title, 20, "") end
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOPLEFT", 18, -44)
    f.L, f.R, f.E = {}, {}, {}
    for i = 1, 7 do
      local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 18, -74 - (i - 1) * 26)
      local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); v:SetPoint("TOPLEFT", 190, -74 - (i - 1) * 26)
      f.L[i], f.R[i] = l, v
    end
    f.eh = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.eh:SetPoint("TOPLEFT", 360, -74)
    for i = 1, 5 do
      local e = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); e:SetPoint("TOPLEFT", 360, -100 - (i - 1) * 24); e:SetWidth(270); e:SetJustifyH("LEFT")
      f.E[i] = e
    end
    f.hsB = CreateFrame("Button", nil, f); f.hsB:SetSize(160, 22); f.hsB:SetPoint("TOPLEFT", f.R[7], "TOPLEFT", 0, 4)
    f.hsB:SetScript("OnClick", function() REC.ShowHighScore(f.who) end)
    f.hsB:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.note:SetPoint("BOTTOMLEFT", 18, 14); f.note:SetWidth(600); f.note:SetJustifyH("LEFT")
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)
    tinsert(UISpecialFrames, "KinaRecordPanel")
    REC.panel = f
  end
  f.who = who
  f.title:SetText(GOLD .. tostring(who) .. "'s record|r")
  f.sub:SetText(GREY .. "What their Kina reports (unverified). Bad votes are a count only. What others owe them isn't shared.|r")
  local rows
  if not r then
    rows = {}
  else
    local nextName, nextAt
    if C.Rep and C.Rep.StandingOf then local _, _, na, nn = C.Rep.StandingOf(r.stand or 0); nextAt, nextName = na, nn end
    rows = {
      { "Standing now", tostring(r.stand or 0) .. ((nextAt and nextName) and (GREY .. "  (" .. (nextAt - (r.stand or 0)) .. " until " .. nextName .. ")|r") or "") },
      { "Bad votes received", ((r.bad or 0) > 0 and RED or GREEN) .. (r.bad or 0) .. "|r" },
      { "Debts run out", ((r.lapses or 0) > 0 and (RED .. r.lapses .. "|r" .. (r.lastLapse and (RED .. "   last: " .. day(r.lastLapse) .. "|r") or "")) or (GREEN .. "0|r")) },
      { "Owes now", (r.owe or 0) >= 1 and (ORANGE .. C.Money(math.floor(r.owe)) .. " to " .. (r.oweN or 1) .. " player" .. ((r.oweN or 1) == 1 and "" or "s") .. "|r") or (GREEN .. "nothing|r") },
      { "Disputes open", ((r.disputes or 0) > 0 and ORANGE or GREY) .. (r.disputes or 0) .. "|r" },
      { "Commends received", GREEN .. (r.good or 0) .. "|r" },
      { "Kina high score", REC.HighScoreText(r) .. (r.hs and (GOLD .. "  ›|r") or "") },
    }
  end
  for i = 1, 7 do
    local x = rows[i]
    f.L[i]:SetText(x and (GREY .. x[1] .. "|r") or ""); f.R[i]:SetText(x and x[2] or "")
  end
  f.hsB:SetShown(r and r.hs and true or false)
  if not f.wait then
    f.wait = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.wait:SetPoint("TOPLEFT", 18, -80); f.wait:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.wait:SetJustifyH("LEFT"); if f.wait.SetWordWrap then f.wait:SetWordWrap(true) end
  end
  if not r then
    local head, why = REC.Waiting(who)
    f.wait:SetText(GOLD .. head:gsub("^%l", string.upper) .. "|r\n\n" .. GREY .. why .. "|r"); f.wait:Show()
  else f.wait:Hide() end
  f.eh:SetText(r and (GOLD .. "Recent standing changes|r") or "")
  for i = 1, 5 do
    local e = r and r.recent and r.recent[i]
    f.E[i]:SetText(e and string.format("%s%s|r  %s%s%d|r  %s", GREY, day(e.t), e.rep < 0 and RED or GREEN, e.rep > 0 and "+" or "", e.rep,
      e.kind == "badvote" and "a bad vote" or (REASON[e.kind] or e.kind)) or ((i == 1 and r) and (GREY .. "none yet|r") or ""))
  end
  f.note:SetText(r and r.at and (GREY .. "Heard " .. math.floor((C.Now() - r.at) / 60) .. " min ago.|r") or "")
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  f:Show(); f:Raise()
  if not r or not r.at or C.Now() - r.at > 60 then REC.Request(who) end
end

-- their best farm, in a small window (yours opens the farm itself)
function REC.ShowHighScore(name)
  local who = first(name)
  if C.IsMyChar and C.IsMyChar(who) then
    local hs = REC.MyHighScore()
    if hs and hs.s and C.OpenFarmLog then return C.OpenFarmLog(hs.s) end
  end
  local r = REC.Of(who)
  local hs = r and r.hs
  if not hs then C.Print("no high score from " .. tostring(who) .. " yet."); return end
  local anchor = (REC.panel and REC.panel:IsShown() and REC.panel.hsB) or (C.Profile and C.Profile.hsAnchor)
  if GameTooltip and anchor then
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText(tostring(who) .. "'s Kina high score", 1, 0.78, 0.29)
    GameTooltip:AddDoubleLine("Gold per hour", C.Money(hs.gph), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Farm", clean(hs.label, 20) .. "  (" .. day(hs.t) .. ")", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Total", C.Money(hs.total or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Length", math.floor((hs.secs or 0) / 60) .. " min", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Kills", tostring(hs.kills or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddLine("Their best gold-per-hour farm of 15 minutes or longer, as their Kina reports it.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  else
    C.Print(string.format("%s's Kina high score: %s/hr on %s (%s): %s in %d min, %d kills.", tostring(who), C.Money(hs.gph), clean(hs.label, 20),
      day(hs.t), C.Money(hs.total or 0), math.floor((hs.secs or 0) / 60), hs.kills or 0))
  end
end
