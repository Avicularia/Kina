-- Kina 2.0.20: the Leaderboard (Taylor, Nov 23: "it should list everyone that everyone else
-- has seen ever, and the last stats they saw it at. That should propagate the data pretty
-- nicely." Trust: yes, opt out: yes, ranking: yes).
--
-- Every Kina keeps a book of every Kina player it has heard of, with their season numbers
-- (Renown, best gold per hour, gold farmed) and when those numbers were true. It learns
-- them three ways:
--   * a player's own Kina says them on the Kina network (LB, every 10 minutes): direct
--   * group and guild hellos (Share.lua) carry the same numbers: direct
--   * other Kinas pass on what they know (LD, a few entries every 10 minutes): relayed,
--     marked "via <who told us>"
-- The newest numbers for a player always win. Anyone with data sharing off says so (o=1),
-- which hides them everywhere it spreads.
local _, C = ...
local B = {}
C.Board = B

local SEASON_TAG = function() return (C.Season and C.Season.id) or "S1" end
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do local r = n % 36; s = DIG:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) end
  return s
end
local function n36(s, max)
  local v = s and s ~= "" and tonumber(s, 36)
  if not v or v < 0 or v ~= v then return nil end
  if max and v > max then return nil end
  return v
end
B._b36, B._n36 = b36, n36

-- sane limits: anything past these is a broken or made-up report and is ignored
local MAX_RENOWN = 5000000
local MAX_GPH = 10000 * 10000   -- copper an hour (10,000 gold an hour)
local MAX_GOLD = 100000000      -- gold farmed, in hundredths of a gold (1,000,000 gold)
local MAX_BOOK = 1000
local SEND_EVERY = 600          -- your own numbers, every 10 minutes
local GOSSIP_EVERY = 600        -- what you know of others, every 10 minutes
local GOSSIP_PER = 6            -- entries per message
local GOSSIP_MSGS = 3           -- messages per round

local function first(n)
  n = tostring(n or ""):match("^([^%-%s]+)") or ""
  return n
end
local function key(n) return first(n):lower() end
-- a real character name: letters only (accents allowed), 2 to 12 characters
local function okName(n)
  n = first(n)
  if #n < 2 or #n > 24 then return false end
  return not n:find("[%d%p%s]")
end
B.OkName = okName

function B.Book()
  local d = C.db
  if type(d.board) ~= "table" then d.board = {} end
  return d.board
end

local function me() return first(UnitName and UnitName("player")) end

-- my own numbers, now
function B.Mine()
  local P = C.Progress
  if not (P and P.State) then return nil end
  local st = P.State()
  local gph = (P.BestGph and P.BestGph() or 0) * 10000
  local _, cls = UnitClass and UnitClass("player")
  return { n = me(), r = math.floor(st.renown or 0), g = math.floor(gph), f = math.floor((st.gold or 0) * 100),
    t = C.Now(), v = C.version, c = cls, o = (C.ShareData and not C.ShareData()) and 1 or nil }
end

-- one report into the book; via = who told us (nil = the player's own Kina). Newest wins,
-- and a report as new as the one we have only replaces it when it comes first-hand.
function B.Note(e, via)
  if type(e) ~= "table" or not okName(e.n) then return false end
  local k = key(e.n)
  if k == key(me()) or (C.IsMyChar and C.IsMyChar(e.n)) then return false end
  local r, g, f, t = tonumber(e.r), tonumber(e.g), tonumber(e.f), tonumber(e.t)
  if not (r and g and f and t) then return false end
  if r < 0 or r > MAX_RENOWN or g < 0 or g > MAX_GPH or f < 0 or f > MAX_GOLD then return false end
  if t > C.Now() + 600 then t = C.Now() end -- (a clock running ahead)
  local book = B.Book()
  local have = book[k]
  if have then
    if t < (have.t or 0) then return false end
    if t == (have.t or 0) and (via or not have.via) then return false end
  end
  local x = have or {}
  x.n = first(e.n):sub(1, 1):upper() .. first(e.n):sub(2)
  x.r, x.g, x.f, x.t = math.floor(r), math.floor(g), math.floor(f), math.floor(t)
  x.via = via and first(via) or nil
  x.o = (e.o == 1 or e.o == "1" or e.o == true) and 1 or nil
  -- 2.1.3: no gold per hour from their Kina (older than 2.0.13); a report that has one
  -- clears it
  if e.ng then x.ng = 1 elseif g > 0 then x.ng = nil end
  if e.v and tostring(e.v):match("^%d+%.%d+") then x.v = tostring(e.v):sub(1, 12) end
  if e.c and tostring(e.c):match("^%u+$") then x.c = tostring(e.c) end
  x.h = C.Now() -- when we last heard anything about them
  book[k] = x
  B.Trim()
  return true
end

function B.Trim()
  local book = B.Book()
  local n, oldest, ok = 0, nil, nil
  for k, x in pairs(book) do
    n = n + 1
    if not oldest or (x.t or 0) < oldest then oldest, ok = x.t or 0, k end
  end
  if n > MAX_BOOK and ok then book[ok] = nil end
end

------------------------------------------------------------------ the wire
local function entryOut(x)
  return table.concat({ first(x.n), b36(x.r), b36(x.g), b36(x.f), b36(x.t), x.o and "1" or "" }, ",")
end
local function entryIn(s)
  local n, r, g, f, t, o = s:match("^([^,]+),(%w+),(%w+),(%w+),(%w+),?(%w*)$")
  if not n then return nil end
  return { n = n, r = n36(r), g = n36(g), f = n36(f), t = n36(t), o = (o == "1") and 1 or nil }
end
B._entryOut, B._entryIn = entryOut, entryIn

-- your own numbers on the network
function B.SendMine()
  local N = C.Net
  if not (N and N.Broadcast and N.Enabled and N.Enabled()) then return end
  local m = B.Mine()
  if not m then return end
  N.Broadcast(table.concat({ "LB", SEASON_TAG(), entryOut(m), tostring(C.version or ""), m.c or "" }, "|"))
end

-- what you know of others: the ones passed on longest ago first, so the whole book goes
-- round in turn
local gossipAt = {}
function B.Gossip()
  local N = C.Net
  if not (N and N.BroadcastBulk and N.Enabled and N.Enabled()) then return end
  local list = {}
  for k, x in pairs(B.Book()) do
    if type(x) == "table" and x.t and C.Now() - x.t < 60 * 86400 then list[#list + 1] = { k = k, x = x } end
  end
  table.sort(list, function(a, b) return (gossipAt[a.k] or 0) < (gossipAt[b.k] or 0) end)
  local i = 1
  for _ = 1, GOSSIP_MSGS do
    local parts = {}
    local msg = "LD|" .. SEASON_TAG() .. "|"
    while list[i] and #parts < GOSSIP_PER do
      local p = entryOut(list[i].x)
      if #msg + #p + 1 > 250 then break end
      parts[#parts + 1] = p; msg = msg .. (#parts > 1 and ";" or "") .. p
      gossipAt[list[i].k] = C.Now()
      i = i + 1
    end
    if #parts == 0 then break end
    N.BroadcastBulk(msg)
  end
end

local function onLB(from, f)
  if f[2] ~= SEASON_TAG() then return end
  local e = entryIn(f[3] or "")
  if not e or key(e.n) ~= key(from) then return end -- (your own numbers only: no speaking for others)
  e.v, e.c = f[4], f[5]
  B.Note(e, nil)
end
local function onLD(from, f)
  if f[2] ~= SEASON_TAG() then return end
  for part in tostring(f[3] or ""):gmatch("[^;]+") do
    local e = entryIn(part)
    -- someone's own numbers come first-hand (LB); passed-on reports never speak for the teller
    if e and key(e.n) ~= key(from) then B.Note(e, from) end
  end
end

-- (group and guild hellos feed the book too: Share.lua calls B.Note with what they carry)

------------------------------------------------------------------ reading it
-- everyone, ranked: { n, r, g, f, t, via, rank, me } (with you in it); opted-out hidden
function B.Ranked(by)
  local out = {}
  for _, x in pairs(B.Book()) do if type(x) == "table" and not x.o then out[#out + 1] = x end end
  local m = B.Mine()
  if m and not m.o then m.me = true; m.via = nil; out[#out + 1] = m end
  local field = by or "r"
  table.sort(out, function(a, b)
    if (a[field] or 0) ~= (b[field] or 0) then return (a[field] or 0) > (b[field] or 0) end
    return tostring(a.n) < tostring(b.n)
  end)
  for i, x in ipairs(out) do x.rank = i end
  return out
end
-- their season numbers, for a profile page when no hello has come from them
function B.SeasonOf(name)
  local x = B.Book()[key(name)]
  if not x or x.o then return nil end
  return { renown = x.r or 0, gph = (x.g or 0) / 10000, gold = (x.f or 0) / 100, t = x.t, via = x.via }
end
function B.Ago(t)
  local s = math.max(0, C.Now() - (t or 0))
  if s < 120 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " d ago"
end

------------------------------------------------------------------ start
local function start()
  local N = C.Net
  if not (N and N.On) then return end
  N.On("LB", onLB)
  N.On("LD", onLD)
  if C.After then
    C.After(45, function() pcall(B.SendMine) end)
    C.After(330, function() pcall(B.Gossip) end)
  end
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(SEND_EVERY, function() pcall(B.SendMine) end)
    C_Timer.NewTicker(GOSSIP_EVERY, function() pcall(B.Gossip) end)
  end
end
start()
-- a farm just ended: your numbers moved, say them
local origEnded = C.FarmEnded
C.FarmEnded = function(s, ...)
  if origEnded then pcall(origEnded, s, ...) end
  if C.After then C.After(20, function() pcall(B.SendMine) end) end
end
