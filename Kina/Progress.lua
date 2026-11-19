-- Kina 1.1.0: progression. Renown and Kina XP from farming: active minutes, the group's
-- gold, and gold per hour for your level. Only farms confirmed by at least one other
-- Kina count (Taylor: "solo farming does not add to your track, it must handshake with
-- at least one other Kina"). Every number comes from Season.lua.
--
--   per farm:  base   = perMinute x active minutes x pace
--              pace   = (group's loot / people) per hour / target for your level, 0.5x-3x
--              bonus  = party + streak + campfire share + track levels (all add up)
--              earned = base x (1 + bonus); each commendation later adds base x 10%
--   Quest gold, quest XP and quest items never count (they're on the widget and Ledger).
local _, C = ...
local P = {}
C.Progress = P
local function S() return C.Season end
local DAY = 86400

------------------------------------------------------------------ state
-- per season, so a new season starts every track (and its bonus) at zero
function P.State(id)
  id = id or (S() and S().id) or "S1"
  C.db.prog = C.db.prog or {}
  local st = C.db.prog[id]
  if not st then
    st = { renown = 0, xp = 0, hours = 0, gold = 0, kills = {}, farms = {},
      streak = { days = 0, half = false, halfRun = 0, last = nil }, best = {} }
    C.db.prog[id] = st
  end
  st.kills = st.kills or {}; st.farms = st.farms or {}; st.best = st.best or {}
  st.streak = st.streak or { days = 0, half = false, halfRun = 0 }
  return st
end

------------------------------------------------------------------ ladders
function P.Rank(renown)
  local ranks = S().ranks
  local r = 1
  for i, t in ipairs(ranks) do if (renown or 0) >= t.at then r = i end end
  return r, ranks[r], ranks[r + 1]
end
function P.Level(xp)
  local lv = 1
  for i, at in ipairs(S().levels) do if (xp or 0) >= at then lv = i end end
  return lv, S().levels[lv], S().levels[lv + 1]
end
local function tierOf(v, tiers)
  local n = 0
  for _, t in ipairs(tiers) do if (v or 0) >= t then n = n + 1 end end
  return n
end
P.TierOf = tierOf

-- the season's card mobs (a fixed list; the hot list stands in until it's picked)
function P.CardMobs()
  local s = S()
  if s.cardMobs then return s.cardMobs end
  local out = {}
  local list = C.Data and C.Data.hotList and C.Data.hotList.mobs
  if type(list) == "table" then for id in pairs(list) do out[#out + 1] = tonumber(id) end end
  table.sort(out)
  return out
end

-- every track: its level, its tier count, and exactly what's needed for the next tier
function P.Tracks(st)
  st = st or P.State()
  local out = {}
  for _, tr in ipairs(S().tracks) do
    local e = { id = tr.id, name = tr.name }
    if tr.id == "ring" then
      local r = P.Rank(st.renown)
      e.level, e.of = r, #S().ranks
      local nx = S().ranks[r + 1]
      e.next = nx and { need = nx.at - st.renown, what = "renown", to = "Rank " .. (r + 1) } or nil
    elseif tr.id == "stars" then
      local n = (C.Mentor and C.Mentor.Count and C.Mentor.Count()) or 0
      e.level, e.of = tierOf(n, tr.tiers), #tr.tiers
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - n, what = (nx - n == 1) and "recruit" or "recruits" } or nil
    elseif tr.id == "bond" then
      -- the Bond system as it is (Rep.lua), with your current partner
      local lvl = 0
      local n = C.SeasonGuide and C.SeasonGuide.Numbers and select(2, pcall(C.SeasonGuide.Numbers))
      if type(n) == "table" and C.Rep and C.Rep.BondLevel then lvl = C.Rep.BondLevel(n.bondCU or 0) end
      e.level, e.of = lvl, 20
      e.next = lvl < 20 and { need = 1, what = "bond level" } or nil
    elseif tr.id == "cards" then
      local lv, mobs, best = 0, P.CardMobs(), nil
      for _, id in ipairs(mobs) do
        local k = st.kills[id] or 0
        local t = tierOf(k, tr.tiers)
        lv = lv + t
        local nx = tr.tiers[t + 1]
        if nx and (not best or nx - k < best.need) then best = { need = nx - k, what = "kills", mob = id } end
      end
      e.level, e.of, e.next = lv, #mobs * #tr.tiers, best
    elseif tr.id == "banner" then
      e.level, e.of = tierOf(st.hours, tr.tiers), #tr.tiers
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - st.hours, what = "hours" } or nil
    elseif tr.id == "hoard" then
      e.level, e.of = tierOf(st.gold, tr.tiers), #tr.tiers
      local nx = tr.tiers[e.level + 1]
      e.next = nx and { need = nx - st.gold, what = "gold" } or nil
    end
    out[#out + 1] = e
  end
  return out
end
function P.TrackLevels(st)
  local n = 0
  for _, e in ipairs(P.Tracks(st)) do n = n + (e.level or 0) end
  return n
end
-- Master of Coin: every track at its top this season
function P.Complete(st)
  for _, e in ipairs(P.Tracks(st)) do if (e.of or 0) == 0 or (e.level or 0) < e.of then return false end end
  return true
end

------------------------------------------------------------------ streak
-- Taylor: +2% a day in a row (max +20%). Miss a day: half. Miss the next too: gone.
-- Two days in a row while at half: full again.
local function today() return math.floor((C.Now() - (C.DayOffset or 0)) / DAY) end
P.Today = today
function P.StreakBonus(st)
  st = st or P.State()
  local k = st.streak
  if not k.last then return 0 end
  local gap = today() - k.last
  local half = k.half or gap == 2
  if gap > 2 or (k.half and gap >= 2) then return 0 end
  local b = math.min(S().bonus.streakMax, (k.days or 0) * S().bonus.streakDay)
  return half and b / 2 or b
end
function P.NoteDay(st)
  local k, d = st.streak, today()
  if k.last == d then return end
  if not k.last then k.days, k.half, k.halfRun = 1, false, 0
  else
    local gap = d - k.last
    if gap == 1 then
      k.days = k.days + 1
      if k.half then k.halfRun = (k.halfRun or 0) + 1; if k.halfRun >= 2 then k.half, k.halfRun = false, 0 end end
    elseif gap == 2 and not k.half then k.days, k.half, k.halfRun = k.days + 1, true, 1
    else k.days, k.half, k.halfRun = 1, false, 0 end
  end
  k.last = d
end

------------------------------------------------------------------ during a farm
-- every minute: active (a kill, loot or gather in the last 3 minutes)? campfire on?
local lastAct = 0
function P.NoteActivity() lastAct = C.Now() end
function P.HasCampfire()
  local s = S()
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not a then break end
      if a.spellId and s.campfireAuras[a.spellId] then return true end
      local n = type(a.name) == "string" and a.name:lower() or ""
      for _, pat in ipairs(s.campfireNames) do if n:find(pat, 1, true) then return true end end
    end
  elseif UnitBuff then
    for i = 1, 40 do
      local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
      if not name then break end
      if s.campfireAuras[id] then return true end
      local n = name:lower()
      for _, pat in ipairs(s.campfireNames) do if n:find(pat, 1, true) then return true end end
    end
  end
  return false
end
function P.Tick()
  local s = C.session
  if not s or s.paused then return end
  s.prog = s.prog or { act = 0, camp = 0 }
  if C.Now() - lastAct <= S().activeWindow then
    s.prog.act = s.prog.act + 1
    if P.HasCampfire() then s.prog.camp = s.prog.camp + 1 end
  end
end
local function loop() pcall(P.Tick); if C.After then C.After(60, loop) end end
if C.After then C.After(60, loop) end
for _, ev in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "LOOT_OPENED" }) do
  if C.On then C.On(ev, function() P.NoteActivity() end) end
end

------------------------------------------------------------------ at the end of a farm
-- the farm's other Kinas (from its shared log); none = it doesn't count
local function lower(s) return ((tostring(s or "")):match("^([^%-]+)") or tostring(s)):lower() end
function P.Members(s)
  local out, seen = {}, {}
  if not (s and s.sync and s.sync.chain) then return out end
  local others = {}
  for _, ev in ipairs(s.sync.chain) do
    local o = ev.origin and lower(ev.origin)
    if o then
      if ev.kind == "J" and not seen[o] then seen[o] = true; out[#out + 1] = ev.origin end
      others[o] = (others[o] or 0) + 1
    end
  end
  -- handshake: another member's own Kina wrote to the log (not just a join)
  local me = lower(UnitName and UnitName("player") or "")
  local confirmed = 0
  for o, n in pairs(others) do if o ~= me and n >= 2 then confirmed = confirmed + 1 end end
  return out, confirmed
end
function P.Score(s, level)
  local cfg = S()
  local members, confirmed = P.Members(s)
  if confirmed < 1 then return nil, "solo" end
  local mins = (s.prog and s.prog.act) or 0
  if mins < 1 then return nil, "idle" end
  local people = math.max(2, #members)
  -- the whole group's loot (never quest rewards); everyone gets credit for all of it
  local groupLoot = (s.split and s.split.total) or (s.gview and s.gview.net) or 0
  local perHour = groupLoot / people / (mins / 60)
  local pace = perHour / cfg.Target(level or (UnitLevel and UnitLevel("player")) or 1)
  pace = math.max(cfg.pace.min, math.min(cfg.pace.max, pace))
  local base = cfg.perMinute * mins * pace
  local b = cfg.bonus
  local st = P.State()
  local parts = {
    party = math.min(b.partyMax, b.partyEach * (people - 1)),
    streak = P.StreakBonus(st),
    campfire = b.campfire * ((s.prog and s.prog.camp or 0) / mins),
    tracks = b.trackLevel * P.TrackLevels(st),
  }
  local bonus = 0
  for _, v in pairs(parts) do bonus = bonus + v end
  return { base = base, bonus = bonus, parts = parts, earned = math.floor(base * (1 + bonus) + 0.5),
    mins = mins, pace = pace, perHour = perHour, groupLoot = groupLoot, people = people,
    kills = (s.gview and s.gview.kills) or s.kills or 0 }
end

-- credit one finished farm (once). Returns the score, or nil and why it didn't count.
function P.Credit(s)
  if not s or s.progCredited then return nil, "done" end
  local sc, why = P.Score(s)
  s.progCredited = true
  if not sc then s.progWhy = why; return nil, why end
  local st = P.State()
  P.NoteDay(st)
  local before = { rank = P.Rank(st.renown), level = P.Level(st.xp) }
  st.renown = st.renown + sc.earned
  st.xp = st.xp + sc.earned
  st.hours = st.hours + sc.mins / 60
  st.gold = st.gold + sc.groupLoot / 10000
  -- card kills: the group's kills of each card mob in this farm
  for id, n in pairs(s.groupKills or {}) do st.kills[id] = (st.kills[id] or 0) + n end
  local ref = (s.sync and s.sync.sid) or ("t" .. tostring(s.start))
  st.farms[ref] = { base = sc.base, t = C.Now(), commends = 0 }
  -- bests for the leaderboards
  st.best.perHour = math.max(st.best.perHour or 0, sc.perHour)
  st.best.farm = math.max(st.best.farm or 0, sc.groupLoot)
  -- old farm records go after 3 days (commendations come within 2)
  for k, f in pairs(st.farms) do if C.Now() - (f.t or 0) > 3 * DAY then st.farms[k] = nil end end
  sc.rankUp = P.Rank(st.renown) > before.rank and P.Rank(st.renown) or nil
  sc.levelUp = P.Level(st.xp) > before.level and P.Level(st.xp) or nil
  s.prog = s.prog or {}; s.prog.score = sc
  if C.FarmRecap and C.Season.live then pcall(C.FarmRecap, s, sc) end
  return sc
end

-- a commendation for one of your farms: +10% of that farm's base
function P.OnCommend(ref)
  local st = P.State()
  local f = ref and st.farms[ref]
  if not f then return end
  local add = math.floor(f.base * S().bonus.commend + 0.5)
  f.commends = (f.commends or 0) + 1
  st.renown = st.renown + add; st.xp = st.xp + add
  return add
end

-- hooks: farm end, kills of card mobs, commendations
local origEnded = C.FarmEnded
C.FarmEnded = function(s, ...)
  if origEnded then origEnded(s, ...) end
  pcall(P.Credit, s)
end
-- a kill: activity, and (shared farms) the group's card-mob tally
function P.NoteKill(npcId)
  P.NoteActivity()
  local s = C.session
  if not (s and npcId) then return end
  s.groupKills = s.groupKills or {}
  s.groupKills[npcId] = (s.groupKills[npcId] or 0) + 1
end
if C.Vouch and C.Vouch.OnVouch then
  local orig = C.Vouch.OnVouch
  C.Vouch.OnVouch = function(from, kind, ref)
    local d = C.db.vouch and C.db.vouch.got
    local n = d and #d or 0
    local r = orig(from, kind, ref)
    local after = C.db.vouch and C.db.vouch.got
    if after and #after > n and not C.Vouch.IsBad(kind) then pcall(P.OnCommend, ref) end
    return r
  end
end

------------------------------------------------------------------ for the screens
-- big numbers stay short, so the plate never needs updating: 842g, 12.4k, 1.25m
function P.ShortGold(g)
  g = tonumber(g) or 0
  local a = math.abs(g)
  if a < 1000 then return string.format("%dg", math.floor(g + 0.5)) end
  if a < 1e6 then return string.format(a < 1e4 and "%.2fk" or (a < 1e5 and "%.1fk" or "%.0fk"), g / 1e3) end
  if a < 1e9 then return string.format(a < 1e7 and "%.2fm" or (a < 1e8 and "%.1fm" or "%.0fm"), g / 1e6) end
  return string.format("%.2fb", g / 1e9)
end
P.QCOLOR = { poor = "|cff9d9d9d", common = "|cffffffff", uncommon = "|cff1eff00", rare = "|cff0070dd",
  epic = "|cffa335ee", legendary = "|cffff8000", artifact = "|cffe6cc80" }
function P.RankText(st)
  st = st or P.State()
  local r, t = P.Rank(st.renown)
  return (P.QCOLOR[t.q] or "") .. "Rank " .. r .. "  " .. t.title:gsub("^%l", string.upper) .. "|r", r, t
end
function P.PerHour(st)
  st = st or P.State()
  return st.hours > 0.05 and st.gold / st.hours or 0
end
-- the gold plate: gold farmed or gold per hour (the player picks; click the plate)
function P.PlateText(st)
  st = st or P.State()
  local o = C.db.opts or {}
  if o.platePerHour then return P.ShortGold(P.PerHour(st)) .. "/hr", "gold per hour" end
  return P.ShortGold(st.gold), "gold farmed"
end
function P.TogglePlate()
  C.db.opts = C.db.opts or {}
  C.db.opts.platePerHour = not C.db.opts.platePerHour
  if C.Refresh then C.Refresh() end
end
-- the bonus a farm would get right now (party counted when it happens)
function P.BonusNow(st)
  st = st or P.State()
  return P.StreakBonus(st) + S().bonus.trackLevel * P.TrackLevels(st)
end
-- the old standing ring art stands in for each rank until the season art is made
P.RING_ART = { "Unproven", "Unproven", "Vouched", "Vouched", "Reliable", "Trusted", "Honored", "Revered", "Exalted", "Exalted" }

------------------------------------------------------------------ the farm-complete recap
-- Taylor: "give it lots of dopamine". The breakdown of what this farm earned, and a
-- fanfare flyout when it crossed a Kina level or a Renown rank.
local GOLDC, GREYC, GREENC = "|cffffc54a", "|cff9d9d9d", "|cff40ff40"
local function num(v) v = math.floor((v or 0) + 0.5); return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v) end
local recap
local function buildRecap()
  if recap then return recap end
  local f = CreateFrame("Frame", "KinaFarmRecap", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(420, 300); f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(120); f:SetClampedToScreen(true)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.96); f:SetBackdropBorderColor(0.86, 0.6, 0.2, 1)
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOP", 0, -14)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.title, 18, "") end
  f.rows = {}
  for i = 1, 9 do
    local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("TOPLEFT", 18, -44 - (i - 1) * 21); l:SetJustifyH("LEFT")
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r:SetPoint("TOPRIGHT", -18, -44 - (i - 1) * 21); r:SetJustifyH("RIGHT")
    f.rows[i] = { l, r }
  end
  f.banner = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.banner:SetPoint("BOTTOM", 0, 44)
  local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); ok:SetSize(110, 24); ok:SetPoint("BOTTOM", 0, 12); ok:SetText("Nice")
  if C.Skin then C.Skin.Button(ok) end
  ok:SetScript("OnClick", function() f:Hide() end)
  tinsert(UISpecialFrames, "KinaFarmRecap")
  f:Hide()
  recap = f
  return f
end
function C.FarmRecap(s, sc)
  local f = buildRecap()
  f.title:SetText(GOLDC .. "Farm complete" .. (s and s.label and (": " .. s.label) or "") .. "|r")
  local quest = s and s.money and s.money.quest or 0
  local p = sc.parts
  local function pct(v) return "+" .. math.floor(v * 100 + 0.5) .. "%" end
  local rows = {
    { "Active time", string.format("%d h %02d m", math.floor(sc.mins / 60), sc.mins % 60) },
    { "Gold farmed (whole group)", C.Money and C.Money(math.floor(sc.groupLoot)) or num(sc.groupLoot) },
    { "Pace for your level", string.format("x%.1f", sc.pace) },
    { "Bonuses: party " .. pct(p.party) .. ", streak " .. pct(p.streak), "" },
    { "   campfire " .. pct(p.campfire) .. ", tracks " .. pct(p.tracks), GREENC .. pct(sc.bonus) .. "|r" },
    { GREYC .. "Quest gold and XP (not counted)|r", GREYC .. (quest > 0 and C.Money and C.Money(quest) or "-") .. "|r" },
    { GOLDC .. "Renown|r", GREENC .. "+" .. num(sc.earned) .. "|r" },
    { "|cff6fb4ffKina XP|r", GREENC .. "+" .. num(sc.earned) .. "|r" },
    { GREYC .. "Each commendation for this farm adds +10% more.|r", "" },
  }
  for i, row in ipairs(f.rows) do row[1]:SetText(rows[i] and rows[i][1] or ""); row[2]:SetText(rows[i] and rows[i][2] or "") end
  local up = {}
  if sc.levelUp then up[#up + 1] = "KINA LEVEL UP!  " .. (C.Rep and C.Rep.Roman and C.Rep.Roman(sc.levelUp) or sc.levelUp) end
  if sc.rankUp then local t = S().ranks[sc.rankUp]; up[#up + 1] = "NEW RANK: " .. (P.QCOLOR[t.q] or "") .. t.title .. "|r" end
  f.banner:SetText(#up > 0 and ("|cffffe090" .. table.concat(up, "   ") .. "|r") or "")
  f:Show(); if f.Raise then f:Raise() end
  -- the dopamine: a flyout and the fanfare when a level or rank was crossed
  if C.Toast and C.Toast.Show and (sc.levelUp or sc.rankUp) then
    pcall(C.Toast.Show, { head = sc.levelUp and ("Kina " .. C.Rep.Roman(sc.levelUp) .. "!") or "New Renown rank!",
      sub = sc.rankUp and ((P.QCOLOR[S().ranks[sc.rankUp].q] or "") .. "Rank " .. sc.rankUp .. "  " .. S().ranks[sc.rankUp].title .. "|r") or "",
      gains = "|cff40ff40+" .. num(sc.earned) .. " Renown and XP|r" })
  end
  if (sc.levelUp or sc.rankUp) and C.PlayCue then C.PlayCue(sc.levelUp and "level" or "standing") end
  C.Print(string.format("farm complete: +%s Renown and Kina XP (%d min, pace x%.1f, bonus +%d%%).", num(sc.earned), sc.mins, sc.pace, math.floor(sc.bonus * 100 + 0.5)))
end

-- 1.1.0 (Taylor: no debts): once, clear anything still queued about debts. Splits stay in
-- the farm logs as information; nobody owes anybody.
if C.On then C.On("PLAYER_LOGIN", function()
  local d = C.db
  if not d or d.debtsRetired then return end
  d.debtsRetired = C.Now and C.Now() or 0
  if d.forgive then d.forgive.pending = {}; d.forgive.asks = {} end
  if d.share then d.share.courier = {} end
end) end
