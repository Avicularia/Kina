-- Kina: reputation. Earned only from things two players' Kina both saw:
--   * paying what you owe (the other player's Kina confirmed the same money moved)
--   * shared farms of 15 minutes or more with other Kina users
-- It is worked out fresh from the event log (Log.lua) every time, never stored as a
-- number, so it is exactly as trustworthy as the log: if the log's chain is broken
-- (the saved file was edited), reputation shows as "log damaged" and counts as 0.
-- Until the Kina server checks both players' logs, everyone's level is "unverified".
-- Positive only: nothing is ever shown about debts someone hasn't paid.
-- Reputation only grows while data sharing is on (Settings > Data sharing): the drop
-- data and auction prices players share are what future Kina versions are built on.
local _, C = ...
local R = {}
C.Rep = R

local DAY = 86400
local PAY_BASE, PAY_PER_GOLD, PAY_MAX = 40, 10, 200 -- per confirmed payment you made
local RECV_XP = 10                                   -- per confirmed payment you received
local FARM_MIN_SECS, FARM_MAX = 900, 120             -- 1 XP per minute of a shared farm
local PARTNER_DAY_CAP = 300                          -- XP per partner per day
local FARM_DAY_CAP = 480                             -- farm XP per day

-- 1.3.0 (Taylor, Nov 5-6): STANDING, the trust ladder, in points. It rises from paying
-- what you owe (10 + 2 per gold of the debt, max 40, part payments their share; +5 when
-- paid before the due time), from qualifying group farms (+5) and later commendations;
-- it falls when a debt you owe lapses unpaid (-50). Worked out from the log like XP.
R.STANDING = {
  { -300, "Oathbreaker" }, { -100, "Disgraced" }, { -1, "Delinquent" },
  { 0, "Unproven" }, { 100, "Vouched" }, { 300, "Reliable" }, { 600, "Trusted" },
  { 1000, "Honored" }, { 1600, "Revered" }, { 2500, "Exalted" },
}
function R.StandingOf(pts)
  pts = tonumber(pts) or 0
  local name, at, nextAt, nextName = "Unproven", 0, nil, nil
  if pts < 0 then
    name = "Delinquent"; at = -1
    if pts <= -100 then name, at = "Disgraced", -100 end
    if pts <= -300 then name, at = "Oathbreaker", -300 end
    return name, at, 0, "Unproven"
  end
  for i = 4, #R.STANDING do
    if pts >= R.STANDING[i][1] then name, at = R.STANDING[i][2], R.STANDING[i][1]; nextAt = R.STANDING[i + 1] and R.STANDING[i + 1][1]; nextName = R.STANDING[i + 1] and R.STANDING[i + 1][2] end
  end
  return name, at, nextAt, nextName
end
function R.PayRep(totalCopper)
  if not totalCopper or totalCopper < 1 then return 0 end
  return math.min(40, 10 + math.floor(totalCopper / 10000) * 2)
end
R.EARLY_REP, R.FARM_REP, R.LAPSE_REP = 5, 5, -50
R.FORGIVE_XP, R.EXTEND_XP, R.LEAD_XP = 15, 5, 10

-- Kina level (experience): I to XX, shown in Roman numerals. Standing (trust) is a
-- separate, later system; it never changes the level.
R.MIN_LEVEL, R.MAX_LEVEL = 1, 20
local ROMAN = { { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
function R.Roman(n)
  n = math.max(R.MIN_LEVEL, math.min(R.MAX_LEVEL, math.floor(tonumber(n) or 1)))
  local out = ""
  for _, p in ipairs(ROMAN) do while n >= p[1] do out = out .. p[2]; n = n - p[1] end end
  return out
end

function C.ShareData() return not (C.settings and C.settings.shareData == false) end
function C.SetShareData(on)
  on = on and true or false
  if C.ShareData() == on then return end
  C.settings.shareData = on
  if C.Log then C.Log("share", on and "on" or "off") end
  if C.Share and C.Share.InvalidateMarket then C.Share.InvalidateMarket() end
  C.Print(on and "data sharing on: your Kina level grows again." or
    "data sharing off: Kina stops collecting and sharing drop data and auction prices. Your Kina level is kept, but won't grow until you turn it back on.")
  if C.RefreshWidget then C.RefreshWidget() end
end

-- total XP needed for a level: I = 0, II = 350, III = 1,400, V = 5,600, X = 28,350, XX = 126,350
-- (XX takes about as long as the old level 50 did)
function R.XPFor(level) return 350 * (math.max(1, level) - 1) ^ 2 end
function R.LevelOf(xp)
  local L = R.MIN_LEVEL
  while L < R.MAX_LEVEL and xp >= R.XPFor(L + 1) do L = L + 1 end
  return L
end

local function day(t) return math.floor((tonumber(t) or 0) / DAY) end
local function fields(e)
  local f = {}
  for v in (e .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
  return f
end

-- Replays log lines on top of a state { xp, share, cap = { [key] = xp } }.
-- gains (optional): every XP gain is added to it as { t, xp, want, kind, who, sid, label, paidOff, cameIn, via, paused }
function R.Replay(lines, st, gains)
  st = st or { xp = 0, share = true, cap = {} }
  st.cap = st.cap or {}
  st.rep = st.rep or 0
  local function capped(key, limit, want)
    local used = st.cap[key] or 0
    local give = math.max(0, math.min(want, limit - used))
    st.cap[key] = used + give
    return give
  end
  for _, line in ipairs(lines) do
    local f = fields(line.e)
    local t, kind = tonumber(f[1]) or 0, f[2]
    if kind == "share" then st.share = (f[3] ~= "off")
    elseif kind == "confirmed" and f[9] == "nx" then
      -- a payment that only covered under-level-10 farms: no XP (1.0.10)
      if gains then gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = (tonumber(f[7]) or 0) >= 1 and "pay" or "receipt", who = f[4] or "?",
        paidOff = tonumber(f[7]) or 0, cameIn = tonumber(f[8]) or 0, via = f[3], noProg = true } end
    elseif kind == "confirmed" then
      -- t|confirmed|via|who|gave|got|paidOff|cameIn
      local who, paidOff, cameIn = f[4] or "?", tonumber(f[7]) or 0, tonumber(f[8]) or 0
      local want = 0
      if f[10] and f[10] ~= "" then
        -- 1.2.3: the XP was worked out from the whole debt when it was confirmed
        want = (tonumber(f[10]) or 0) + (tonumber(f[11]) or 0)
      else
        if paidOff >= 1 then want = math.min(PAY_MAX, PAY_BASE + math.floor(paidOff / 10000) * PAY_PER_GOLD) end
        if cameIn >= 1 then want = want + RECV_XP end
      end
      local got = 0
      if want > 0 and st.share then got = capped(who .. ":" .. day(t), PARTNER_DAY_CAP, want); st.xp = st.xp + got end
      -- 1.3.0: standing from paying (logged at confirm time; older lines by the formula)
      local rp = 0
      if f[12] and f[12] ~= "" then rp = tonumber(f[12]) or 0
      elseif paidOff >= 1 then rp = R.PayRep(paidOff) end
      if rp > 0 then st.rep = st.rep + capped("rep:" .. who .. ":" .. day(t), 120, rp) end
      if want > 0 and gains then gains[#gains + 1] = { t = t, xp = got, want = want, kind = paidOff >= 1 and "pay" or "receipt", who = who,
        paidOff = paidOff, cameIn = cameIn, via = f[3], gave = tonumber(f[5]) or 0, got = tonumber(f[6]) or 0, paused = not st.share or nil } end
    elseif kind == "forgive" and f[3] == "gave" then
      -- 1.3.0: forgiving earns a little XP (3 a day count)
      local got = st.share and capped("forgive:" .. day(t), R.FORGIVE_XP * 3, R.FORGIVE_XP) or 0
      st.xp = st.xp + got
      if gains and got > 0 then gains[#gains + 1] = { t = t, xp = got, want = R.FORGIVE_XP, kind = "forgive", who = f[4] or "?" } end
    elseif kind == "extend" and f[3] == "gave" then
      local got = st.share and capped("extend:" .. day(t), R.EXTEND_XP * 3, R.EXTEND_XP) or 0
      st.xp = st.xp + got
      if gains and got > 0 then gains[#gains + 1] = { t = t, xp = got, want = R.EXTEND_XP, kind = "extend", who = f[4] or "?" } end
    elseif kind == "vouch" and f[3] == "got" then
      -- 1.5.0: someone vouched for me (the rep was set when it arrived)
      local rp = tonumber(f[7]) or 0
      st.rep = st.rep + rp
      if gains then gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = "vouched", who = f[4] or "?", rep = rp, vk = tonumber(f[5]) } end
    elseif kind == "vouch" and f[3] == "gave" then
      local got = st.share and capped("vouch:" .. day(t), 15, 5) or 0
      st.xp = st.xp + got
      if gains and got > 0 then gains[#gains + 1] = { t = t, xp = got, want = 5, kind = "vouchgave", who = f[4] or "?" } end
    elseif kind == "refused" then
      -- 1.3.0: I turned down a full payment and the debt ran out: -50, -100 if again within 30 days
      local hit = (st.lastRefused and t - st.lastRefused < 30 * DAY) and -100 or -50
      st.lastRefused = t
      st.rep = st.rep + hit
      if gains then gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = "refused", who = f[3] or "?", rep = hit } end
    elseif kind == "lapsed" then
      -- 1.3.0: a debt you owed passed its due time unpaid
      st.rep = st.rep + R.LAPSE_REP
      if gains then gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = "lapsed", who = f[3] or "?", rep = R.LAPSE_REP } end
    elseif kind == "farmend" then
      -- t|farmend|label|sid|head|hash|secs|total|kills|mates[|minLvl|maxLvl|net|players] (1.0.10)
      local sid, secs, mates = f[4] or "", tonumber(f[7]) or 0, tonumber(f[10]) or 0
      local why = R.Unqualified(f)
      if why then
        if sid ~= "" then st.noProg = st.noProg or {}; st.noProg[sid] = true end
        if gains and sid ~= "" and mates >= 1 then
          gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = "short", why = why, sid = sid, label = f[3], secs = secs }
        end
      elseif sid ~= "" and mates >= 1 and secs >= FARM_MIN_SECS then
        local want = math.min(FARM_MAX, math.floor(secs / 60))
        local got = 0
        if st.share then got = capped("farm:" .. day(t), FARM_DAY_CAP, want); st.xp = st.xp + got end
        st.rep = st.rep + capped("repfarm:" .. day(t), 40, R.FARM_REP)
        if gains then gains[#gains + 1] = { t = t, xp = got, want = want, kind = "farm", sid = sid, label = f[3], secs = secs, paused = not st.share or nil } end
      elseif gains and sid ~= "" and mates >= 1 then
        gains[#gains + 1] = { t = t, xp = 0, want = 0, kind = "short", sid = sid, label = f[3], secs = secs }
      end
    end
  end
  -- caps only matter for recent days: keep the state small
  local today = day(C.Now())
  for k in pairs(st.cap) do
    local d = tonumber(k:match(":(%d+)$"))
    if d and today - d > 2 then st.cap[k] = nil end
  end
  return st
end

-- 1.0.10: the gold a farm needs for Kina progression, in copper.
-- base(L) = 20 ^ ((L - 10) / 50) gold for the highest level L in the group (L10 1g, L30 3g30s,
-- L60 20g), times (1 + 0.5 x (players - 1)), counting players who don't run Kina.
function R.FarmNeeds(maxLvl, players)
  local L = math.max(10, tonumber(maxLvl) or 10)
  local base = 10000 * 20 ^ ((L - 10) / 50)
  return math.floor(base * (1 + 0.5 * (math.max(1, tonumber(players) or 1) - 1)) + 0.5)
end
-- why a finished farm gives no progression ("under10", "gold"), or nil. Farms logged
-- before 1.0.10 (no level fields) keep the old rule.
function R.Unqualified(f)
  local minL, maxL, net, players = tonumber(f[11]), tonumber(f[12]), tonumber(f[13]), tonumber(f[14])
  if not minL then return nil end
  if minL > 0 and minL < (C.PROG_MIN_LEVEL or 10) then return "under10" end
  -- (1.1.1: the gold target is gone, Taylor's call after the first long farm; 15 minutes is the rule)
  return nil
end

-- every XP gain still in the log (older ones were rolled up), oldest first
function R.History()
  local log = C.db and C.db.log
  local gains = {}
  if not log then return gains end
  local st = { xp = 0, share = true, cap = {} }
  if log.repState then
    st.xp, st.share, st.rep = log.repState.xp or 0, log.repState.share ~= false, log.repState.rep or 0
    for k, v in pairs(log.repState.cap or {}) do st.cap[k] = v end
  end
  R.Replay(log.lines or {}, st, gains)
  return gains, log.repState and log.repState.xp or 0
end
-- 1.4.5: XP per hour of farming, honestly: every XP gained in the last `days` days
-- (farms, payments, forgiving...) divided by the hours of shared farming in those days.
-- (The old figure divided ALL XP ever by all hours, and a long farm's XP caps at 120.)
function R.XPPerHour(days)
  local gains = R.History()
  local since = C.Now() - (days or 7) * DAY
  local xp, secs = 0, 0
  for _, g in ipairs(gains) do
    if g.t >= since then
      xp = xp + (g.xp or 0)
      if (g.kind == "farm" or g.kind == "short") and g.secs then secs = secs + g.secs end
    end
  end
  if secs < 600 then return nil end
  return math.floor(xp * 3600 / secs)
end
-- XP a payment of this size would give (before the daily cap per partner)
function R.PayXP(copper)
  if not copper or copper < 1 then return 0 end
  return math.min(PAY_MAX, PAY_BASE + math.floor(copper / 10000) * PAY_PER_GOLD)
end
R.RECV_XP, R.FARM_MIN_SECS, R.FARM_MAX = RECV_XP, FARM_MIN_SECS, FARM_MAX

-- Your reputation now: { xp, level, title, next, share, ok }
function R.Mine()
  local log = C.db and C.db.log
  if not log then return { xp = 0, level = 1, title = "", next = R.XPFor(2), share = C.ShareData(), ok = true } end
  local ok = C.EventLog and C.EventLog.Verify() or false
  local st = { xp = 0, share = true, cap = {} }
  if log.repState then
    st.xp, st.share, st.rep = log.repState.xp or 0, log.repState.share ~= false, log.repState.rep or 0
    for k, v in pairs(log.repState.cap or {}) do st.cap[k] = v end
  end
  st = R.Replay(log.lines or {}, st)
  local xp = ok and st.xp or 0
  local lv = R.LevelOf(xp)
  local rp = ok and (st.rep or 0) or 0
  local sname, sat, snext, snextName = R.StandingOf(rp)
  return { xp = xp, level = lv, title = "", next = R.XPFor(math.min(R.MAX_LEVEL, lv + 1)),
    rep = rp, standing = sname, standingAt = sat, standingNext = snext, standingNextName = snextName,
    share = C.ShareData(), ok = ok }
end

-- what Kina tells other Kina users (in its hello): level, or -1 if the log is damaged
function R.Announce()
  local m = R.Mine()
  return m.ok and m.level or -1
end

-- for the widget and Settings
function C.RepLine()
  local m = R.Mine()
  if not m.ok then return "|cffff8040Rep -|r" end
  return "|cffffd100Lv " .. R.Roman(m.level) .. "|r"
end
function C.RepDetail()
  local m = R.Mine()
  local out = {}
  if not m.ok then
    out[1] = "|cffff8040Your Kina log doesn't check out (the saved file was changed), so your Kina XP counts as 0.|r"
    return out
  end
  if m.level >= R.MAX_LEVEL then out[1] = string.format("Kina level %s: %d XP (top level).", R.Roman(m.level), m.xp)
  else out[1] = string.format("Kina level %s: %d / %d XP to level %s.", R.Roman(m.level), m.xp, m.next, R.Roman(m.level + 1)) end
  out[2] = "Earn it by paying what you owe and farming with Kina users (15+ min)."
  out[3] = "Unverified until the Kina server checks both players' logs."
  if not m.share then out[4] = "|cffff8040Paused: turn data sharing on to keep earning.|r" end
  return out
end

-- another Kina user's reputation, as their Kina announced it (nil if unknown)
function R.Of(name)
  local S = C.Share and C.Share.DB and C.Share.DB()
  if not (S and S.authors and name) then return nil end
  local want = C.FirstName and C.FirstName(name) or name
  local best
  for _, a in pairs(S.authors) do
    if a.rep and a.name and (C.FirstName and C.FirstName(a.name) or a.name) == want then
      if not best or (a.seen or 0) > (best.seen or 0) then best = a end
    end
  end
  return best and best.rep
end

-- player tooltips: "Kina rep 7 (unverified)" for Kina users
-- 1.2.8: in combat the game hands tooltips "secret" unit values that addons may not
-- touch (UnitIsPlayer on one raised an error every tooltip, 264 times). Skip those, and
-- keep the "already added" mark in Kina's own table instead of on Blizzard's tooltip.
local added = setmetatable({}, { __mode = "k" })
local function onUnitSafe(tip)
  if tip ~= GameTooltip or not tip.GetUnit or added[tip] then return end
  local _, unit = tip:GetUnit()
  if unit == nil then return end
  if issecretvalue and issecretvalue(unit) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
  added[tip] = true
  local name = UnitName(unit)
  local lv
  if UnitIsUnit and UnitIsUnit(unit, "player") then lv = R.Announce() else
    local r = R.Of(name); lv = r and r.lv
  end
  if not lv then return end
  if lv < 0 then tip:AddLine("Kina: level unavailable", 0.6, 0.6, 0.6)
  else tip:AddLine(string.format("Kina %s |cff888888(unverified)|r", R.Roman(lv)), 0.31, 0.76, 0.97) end
  tip:Show()
end
local function onUnit(tip) pcall(onUnitSafe, tip) end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", onUnit)
end
if GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipCleared", function(self) added[self] = nil end)
end

-- level-up message
local lastLevel
C.On("PLAYER_LOGIN", function() lastLevel = R.Mine().level end)
function R.Check()
  local m = R.Mine()
  if lastLevel and m.ok and m.level > lastLevel then
    C.Print("|cffffd100Kina level " .. R.Roman(m.level) .. "!|r")
    if C.PlayCue then pcall(C.PlayCue, "start") end
  end
  lastLevel = m.level
end

-- first login: say plainly what is collected and offer the switch right there
C.On("PLAYER_LOGIN", function()
  if C.settings.dataNoticeSeen or not StaticPopupDialogs then return end
  StaticPopupDialogs.KINA_DATA_NOTICE = StaticPopupDialogs.KINA_DATA_NOTICE or {
    text = "Welcome to Kina!\n\nKina collects which mobs drop what and the auction prices you see, and shares them with other Kina users to build the farm and price features of a future version. Nothing about you, your chat or other players is collected.\n\nYour Kina level only grows while sharing is on. You can change this any time in Settings.",
    button1 = "Keep sharing", button2 = "Turn it off", timeout = 0, whileDead = true, hideOnEscape = false,
    OnAccept = function() C.settings.dataNoticeSeen = C.Now() end,
    OnCancel = function(_, _, reason)
      if reason == "clicked" then C.settings.dataNoticeSeen = C.Now(); C.SetShareData(false) end
    end }
  C.After(8, function() if not C.settings.dataNoticeSeen then StaticPopup_Show("KINA_DATA_NOTICE") end end)
end)
