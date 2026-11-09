-- Kina: the event log. An append-only record of what Kina saw between Kina users:
-- farms (start, pause, stop, who was in them, the split), money that moved to settle
-- a debt (trade or mail), and the other player's Kina confirming it. Each line carries
-- a hash of the line before it, so a line changed or removed later breaks the chain.
-- (This doesn't stop someone editing their own file; it makes it show. Trust comes from
-- two players' logs agreeing.) Nothing about strangers or chat is ever written here.
-- After 90 days, old lines are rolled up into counts.
local _, C = ...
local L = {}
C.EventLog = L

local KEEP = 90 * 86400
local MAX = 5000

local function db()
  local d = C.db.log
  if type(d) ~= "table" then d = {}; C.db.log = d end
  if type(d.lines) ~= "table" then d.lines = {} end
  if type(d.base) ~= "string" then d.base = "0" end
  if type(d.summary) ~= "table" then d.summary = {} end
  return d
end
local function hash(s) return C.SyncCore and C.SyncCore.Hash and C.SyncCore.Hash(s) or "0" end
local function field(v)
  if v == nil then return "" end
  if type(v) == "number" then return tostring(math.floor(v + 0.5)) end
  return (tostring(v):gsub("[|\n]", " "))
end

-- C.Log(kind, ...): add one line. Returns the line.
function C.Log(kind, ...)
  if not C.db then return end
  local d = db()
  local parts = { tostring(C.Now()), field(kind) }
  for i = 1, select("#", ...) do parts[#parts + 1] = field((select(i, ...))) end
  local e = table.concat(parts, "|")
  local prev = d.lines[#d.lines]
  local line = { e = e, h = hash((prev and prev.h or d.base) .. "|" .. e) }
  d.lines[#d.lines + 1] = line
  if #d.lines > MAX then L.Prune(true) end
  if C.Rep and C.Rep.Check and kind ~= "login" then pcall(C.Rep.Check) end
  return line
end

-- 0.9.1 (security): the rolled-up state (repState) is part of the chain too: its hash
-- is kept with it, so editing the numbers in it breaks the chain like editing a line.
function L.StateHash(st)
  if type(st) ~= "table" then return "0" end
  local keys = {}
  for k in pairs(st) do if type(st[k]) ~= "table" then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do local v = st[k]; parts[#parts + 1] = k .. "=" .. (type(v) == "number" and string.format("%.0f", v) or tostring(v)) end
  for _, bt in ipairs(type(st.badTimes) == "table" and st.badTimes or {}) do parts[#parts + 1] = string.format("%.0f", tonumber(bt) or 0) end
  return hash(table.concat(parts, ";"))
end
-- Checks the chain. Returns true, or false and the first line that doesn't match.
function L.Verify()
  local d = db()
  if d.repState then
    -- (a save from before 0.9.1 has no hash yet: stamp it once)
    if not d.repHash then d.repHash = hash(d.base .. "|" .. L.StateHash(d.repState)) end
    if d.repHash ~= hash(d.base .. "|" .. L.StateHash(d.repState)) then return false, 0 end
  end
  local prev = d.base
  for i, line in ipairs(d.lines) do
    if hash(prev .. "|" .. line.e) ~= line.h then return false, i end
    prev = line.h
  end
  return true
end

-- Old lines become counts per kind; the chain continues from the last removed line.
function L.Prune(force)
  local d = db()
  local now = C.Now()
  local cut = 0
  for i, line in ipairs(d.lines) do
    local t = tonumber(line.e:match("^(%d+)")) or now
    if now - t > KEEP or (force and #d.lines - i >= MAX * 0.8) then cut = i else break end
  end
  if cut == 0 then return end
  -- reputation earned in the lines being rolled up is kept as a starting state
  if C.Rep and C.Rep.Replay and L.Verify() then
    local cutLines = {}
    for i = 1, cut do cutLines[i] = d.lines[i] end
    local st = d.repState and { xp = d.repState.xp, share = d.repState.share, cap = d.repState.cap, rep = d.repState.rep, lastRefused = d.repState.lastRefused, badTimes = d.repState.badTimes } or nil
    if st then for _, k in ipairs(C.Rep.STATE_KEYS) do st[k] = d.repState[k] end end
    d.repState = C.Rep.Replay(cutLines, st)
  end
  for i = 1, cut do
    local k = d.lines[i].e:match("^%d+|([^|]*)") or "?"
    d.summary[k] = (d.summary[k] or 0) + 1
  end
  d.base = d.lines[cut].h
  if d.repState then d.repHash = hash(d.base .. "|" .. L.StateHash(d.repState)) end
  local keep = {}
  for i = cut + 1, #d.lines do keep[#keep + 1] = d.lines[i] end
  d.lines = keep
end

------------------------------------------------------------------ what gets logged
-- farm start / pause / resume / stop (from the farm's own log)
local farmKinds = { start = true, pause = true, resume = true, stop = true }
local origSessionLog = C.SessionLog
if origSessionLog then
  C.SessionLog = function(k, ...)
    origSessionLog(k, ...)
    local s = C.session
    if s and farmKinds[k] then
      local sid = s.sync and s.sync.sid or ""
      local who = {}
      for _, m in ipairs(s.party or {}) do who[#who + 1] = C.FirstName and C.FirstName(m.name) or m.name end
      C.Log("farm", k, s.label, sid, s.byParty and "joined" or "own", table.concat(who, ","))
    end
  end
end

-- the farm's result and the debts its split created (once per farm, whenever the
-- split is known: at stop for a shared farm, a little later for an older-style group)
local function logEnd(s)
  if not s or s.logged then return end
  local sync = s.sync
  local r = s.result or {}
  -- 1.0.10 adds: lowest level, highest level, the group's NET, players in the group
  local net = (s.gview and s.gview.net) or r.total or 0
  local f = { C.Now(), "farmend", s.label, sync and sync.sid or "", sync and sync.head or 0, sync and sync.hash or "",
    s.stop and s.start and (s.stop - s.start - (s.pausedSecs or 0)) or 0, r.total or 0, r.kills or s.kills or 0, #(s.party or {}),
    s.minLvl or 0, s.maxLvl or 0, math.floor(net), math.max(s.groupN or 1, #(s.party or {}) + 1) }
  -- 0.9.18: "p" when your Kina Partner was in this farm at the end (the partner bonus)
  local partner = C.Pair and C.Pair.Partner and C.Pair.Partner()
  local withPartner = false
  if partner then
    -- 0.9.19: any character on your partner's account
    for _, m in ipairs(s.party or {}) do
      if C.Share and C.Share.UIDOf and C.Share.UIDOf(m.name) == partner then withPartner = true end
    end
  end
  if withPartner then f[15] = "p" end
  C.Log(unpack(f, 2, withPartner and 15 or 14))
  if withPartner and sync then
    local b = C.Pair.Bonus()
    C.Print(string.format("|cff33ff66Partner bonus:|r +%d%% XP and standing for farming with %s.", math.floor(b * 100 + 0.5), C.Pair.PartnerName() or "your partner"))
  end
  s.logged = true
  -- 0.9.10: a new player's first qualifying farm gives their mentor the install credit
  if C.Mentor and C.Mentor.OnFarmEnd then
    local ok, err = pcall(C.Mentor.OnFarmEnd, s, f)
    if not ok and C.LogError then C.LogError("mentor", err) end
  end
end
local function logSplit(s)
  if not (s and s.split) or s.splitLogged then return end
  s.splitLogged = true
  local sid = s.sync and s.sync.sid or ""
  C.Log("split", sid, s.split.total or 0, s.split.each or 0, #(s.split.transfers or {}))
  for _, t in ipairs(s.split.transfers or {}) do
    if (t.amt or 0) > 0 then C.Log("debt", sid, C.FirstName and C.FirstName(t.from) or t.from, C.FirstName and C.FirstName(t.to) or t.to, t.amt) end
  end
end
local origEnded = C.FarmEnded
C.FarmEnded = function(s)
  if origEnded then origEnded(s) end
  pcall(logEnd, s); pcall(logSplit, s)
end
for _, name in ipairs({ "ShowGroupSplit", "TrySettle" }) do
  local orig = C[name]
  if orig then
    C[name] = function(s, ...)
      local r = orig(s, ...)
      if s and s.stop then pcall(logSplit, s) end
      return r
    end
  end
end

-- joining someone's shared farm
if C.FarmSync and C.FarmSync.Accept then
  local orig = C.FarmSync.Accept
  C.FarmSync.Accept = function(sid, leader, ...)
    orig(sid, leader, ...)
    C.Log("join", sid, C.FirstName and C.FirstName(leader) or leader)
  end
end

C.On("PLAYER_LOGIN", function()
  -- 0.9.1 (security): a fresh Kina file on a character that remembers a negative
  -- standing (or the Blacklisted scar) starts from that, not from a clean slate
  local d = db()
  if #d.lines == 0 and not d.repState and type(KinaMark) == "table" and ((tonumber(KinaMark.rep) or 0) < 0 or KinaMark.black) then
    C.Log("carry", math.min(0, tonumber(KinaMark.rep) or 0), KinaMark.black and "b" or "")
  end
  L.Prune()
  local ok, bad = L.Verify()
  C.Log("login", C.version, ok and "chain ok" or ("chain broken at " .. tostring(bad)))
end)
