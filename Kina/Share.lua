-- Kina: data sharing with other Kina users in your party/raid
-- (and optionally your guild). Pools everyone's observations for more coverage:
--   * AH scan prices   - every member's latest scan; per item the freshest wins
--   * mob loot records - kills, coin, drops, pickpockets, skins, farm spots
--   * vendor prices    - real merchant payouts learned from buyback lists
-- Each player shares only what THEY observed (never re-sends what they received),
-- and a receiver stores it per author, replacing that author's older copy, so the
-- same kill is never counted twice no matter how often you sync.
--
-- Protocol (prefix "KinaShare", fields separated by "|", numbers base 36):
--   H|uid|ver|name|mkey|scanT|lootV|vendT|offT   hello: what I hold (group/guild)
--   O|uid|id:each:t:who:where;...         merchant offers (what merchants SELL, e.g. vials)
--   Q|uid|what|base                         send me your <what> newer than base (whisper)
--   B|uid|what|ver|base                     dump begins
--   M|uid|id:m:d:q:n;...                    market rows
--   L|uid|npc|kills:looted:coin:coinLoots:pp:ppCoin:skins:lvl:elite:rare|name
--   I|uid|npc|k|id:n;...                    k = c corpse, p pickpocket, s skin
--   P|uid|npc|map:x:y:n;...                 average farm spot per map (x,y in 1/1000)
--   V|uid|id:p:t;...                        vendor payouts
--   E|uid|what|ver|count                    dump complete: commit it
--   F|uid|start|stop|income                 my group farm ended: what I gathered (for the split)
--   C|uid|npc:kills:id.n,id.n;...           community drop data (ForeverGuide pool), so a group ranks farms alike
local ADDON, C = ...
local PREFIX = "KinaShare"
local PROTO = 2  -- 0.10.1: hello carries the community-data stamp
local MAX_LEN = 250
local MAX_AUTHORS = 200
local MARKET_MAX_AGE = 3 * 86400   -- shared scans older than 3 days are ignored for prices
local REPLY_COOLDOWN = 60
local HELLO_EVERY = 300            -- re-announce to the group every 5 min

local S = {}
C.Share = S

------------------------------------------------------------------ helpers
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIG:sub(r + 1, r + 1) .. s
    n = (n - r) / 36
  end
  return s
end
local function n36(s, max)
  local v = s and tonumber(s, 36)
  if not v or v < 0 or v ~= v then return nil end
  if max and v > max then return nil end
  return v
end
S._b36, S._n36 = b36, n36

local function clean(s) return (tostring(s or ""):gsub("[|;:,]", " "):sub(1, 40)) end

local function db()
  local d = C.db.share
  if type(d) ~= "table" then d = {}; C.db.share = d end
  d.opts = d.opts or {}
  if d.opts.enabled == nil then d.opts.enabled = true end
  if d.opts.guild == nil then d.opts.guild = false end
  if not d.uid then
    -- random id, stable per character: lets peers keep your data apart from others'
    d.uid = string.format("%06x%06x", math.random(0, 0xffffff), math.random(0, 0xffffff))
  end
  d.authors = d.authors or {}      -- [uid] = { name, seen, market = {mkey, t, items}, loot = {ver, npcs}, vend = {t} }
  d.lootVer = d.lootVer or 0
  d.lootStamp = d.lootStamp or {}  -- [npc] = lootVer when it last changed
  d.lootSig = d.lootSig or {}      -- [npc] = signature at last stamp
  return d
end
S.DB = db

local function myName()
  local n, r = UnitName and UnitName("player"), GetRealmName and GetRealmName()
  return (n or "?") .. "-" .. ((r or "?"):gsub("%s", ""))
end

local function short(name) return (Ambiguate and name and Ambiguate(name, "short")) or name end

local function isMe(from)
  if not from then return true end
  local me = UnitName and UnitName("player")
  return from == me or from == myName() or short(from) == me
    or (C.FirstName and me and not (C.GroupMemberName and C.GroupMemberName(from)) and C.FirstName(from) == C.FirstName(me) and not from:find("-"))
end

local function groupChannel()
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

------------------------------------------------------------------ sending
-- Token bucket under the client's per-prefix limit; big dumps wait out combat.
local queue = {}
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local tokens, tick = 6, 0
S.dumping = {}   -- [what] = true while that dump is still queued
local function enqueue(msg, channel, target, urgent)
  if #msg > 255 then return end
  -- the same message already waiting: don't queue it twice (a re-ask while the first
  -- answer is still queued would otherwise snowball)
  for _, q in ipairs(queue) do if q.msg == msg and q.channel == channel and q.target == target then return end end
  local it = { msg = msg, channel = channel, target = target, urgent = urgent }
  -- urgent messages jump the queue but keep their own order (first in, first out);
  -- pushing each one to the very front sent them newest-first and starved the oldest
  if urgent then
    local pos = 1
    while queue[pos] and queue[pos].urgent do pos = pos + 1 end
    table.insert(queue, pos, it)
  else queue[#queue + 1] = it end
  if S.sender then S.sender:Show() end
end
S._queue = queue
-- 1.2.6: how a scan transfer is going, for the scan bar ("sending your scan 40%",
-- "getting Tri's scan 40%")
local peakQ = 0
function S.Progress()
  local now = GetTime and GetTime() or 0
  local best
  for _, b in pairs(S._incoming or {}) do
    if b.what == "M" and now - (b.last or b.time or 0) < 60 then
      local n = 0; for _ in pairs(b.rows or {}) do n = n + 1 end
      local exp = (b.expect and b.expect > 0) and b.expect or nil
      best = { dir = "in", who = b.from, pct = exp and math.min(99, math.floor(n * 100 / exp)) or nil, n = n }
    end
  end
  if best then return best end
  local q = #queue
  if q == 0 then peakQ = 0; return nil end
  if S.dumping and S.dumping.M then
    if q > peakQ then peakQ = q end
    return { dir = "out", pct = peakQ > 0 and math.floor((peakQ - q) * 100 / peakQ) or 0 }
  end
end

local sender = CreateFrame("Frame")
S.sender = sender
sender:Hide()
sender:SetScript("OnUpdate", function(self, dt)
  tick = tick + dt
  if tick >= 1 then tick = 0; tokens = math.min(6, tokens + 1) end
  if #queue == 0 then self:Hide(); return end
  if tokens < 1 then return end
  if InCombatLockdown and InCombatLockdown() then
    -- in dungeons and raids nothing goes out during combat (sent when combat ends);
    -- in the open world only the small hello, kill, farm-control and farm-view notes do
    local inst = IsInInstance and IsInInstance()
    local k = queue[1].msg:sub(1, 1)
    if inst or not (k == "H" or k == "K" or k == "Z" or k == "W" or k == "X" or k == "U" or k == "G" or k == "R" or k == "S" or k == "T") then return end
  end
  local it = table.remove(queue, 1)
  tokens = tokens - 1
  local k, what = it.msg:match("^(%u)|%x+|(%u)")
  if k == "E" and what then S.dumping[what] = nil end
  S.sent = (S.sent or 0) + 1
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  C.lastSend = { k = it.msg:sub(1, 1) .. (it.msg:match("^S|[^|]*|[^|]*|(%u)") or ""), t = GetTime and GetTime() or 0 }
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, it.msg, it.channel, it.target)
  if ok and THROTTLED and result == THROTTLED then table.insert(queue, 1, it); tokens = 0 end
end)

-- Pack "head" + items separated by sep into as few messages as fit.
local function packed(head, parts, sep, channel, target)
  local msg = head
  local fresh = true
  for _, p in ipairs(parts) do
    if #msg + #p + 1 > MAX_LEN and not fresh then
      enqueue(msg, channel, target); msg = head; fresh = true
    end
    msg = msg .. (fresh and "" or sep) .. p
    fresh = false
  end
  if not fresh then enqueue(msg, channel, target) end
end

------------------------------------------------------------------ my versions
-- Loot changes all the time; stamp npcs whose counts moved so peers can ask for
-- only what changed since the version they already have.
local function lootSig(r)
  local n = (r.kills or 0) + (r.looted or 0) * 7 + (r.pp or 0) * 13 + (r.skins or 0) * 17
    + math.floor(r.coin or 0) + math.floor(r.ppCoin or 0)
  for _, t in ipairs({ r.items, r.ppItems, r.skinItems }) do
    if t then for _, q in pairs(t) do n = n + q end end
  end
  return n
end

function S.StampLoot()
  local d = db()
  local bumped = false
  for npc, r in pairs(C.db.loot) do
    if type(r) == "table" then
      local sig = lootSig(r)
      if d.lootSig[npc] ~= sig then
        if not bumped then d.lootVer = d.lootVer + 1; bumped = true end
        d.lootSig[npc] = sig; d.lootStamp[npc] = d.lootVer
      end
    end
  end
  return d.lootVer
end

local function offerTime()
  local t = 0
  for _, o in pairs(C.db.offers or {}) do if type(o) == "table" and (o.t or 0) > t then t = o.t end end
  return t
end

local function vendorTime()
  local t = 0
  for _, v in pairs(C.db.vendor) do if type(v) == "table" and (v.t or 0) > t then t = v.t end end
  return t
end

------------------------------------------------------------------ hello
local lastHello = {}
local function hello(channel, target, force)
  local d = db()
  if not d.opts.enabled then return false end
  local key = channel .. (target or "")
  local now = GetTime and GetTime() or 0
  if not force and lastHello[key] and now - lastHello[key] < 30 then return false end
  lastHello[key] = now
  -- who I am, for the duo farm and profession planner: class, level, professions
  local profs = {}
  for p, sk in pairs(C.char.prof or {}) do
    local n = tostring(p):gsub("[^%a ]", "")
    if n ~= "" and #profs < 8 then profs[#profs + 1] = n .. "=" .. b36(sk) end
  end
  local cls = (UnitClass and select(2, UnitClass("player"))) or "?"
  -- with data sharing off, Kina offers none of its drop/price data (and asks for none)
  local share = not C.ShareData or C.ShareData()
  local rep = C.Rep and C.Rep.Announce and C.Rep.Announce() or 0
  local msg = table.concat({ "H", d.uid, b36(PROTO), clean(myName()), clean(C.MarketKey()),
    b36(share and C.market.scanTime or 0), b36(share and S.StampLoot() or 0), b36(share and vendorTime() or 0), b36(share and offerTime() or 0),
    (cls:gsub("%A", "")), b36((UnitLevel and UnitLevel("player")) or 0), table.concat(profs, ","), b36(S.CommStamp()),
    rep >= 0 and b36(rep) or "x", (tostring(C.version or ""):gsub("[^%d%.]", "")), tostring(S.MyStanding and S.MyStanding() or ""), S.MyFlags and S.MyFlags() or "", tostring(C.BUILD or 0) }, "|")
  if #msg > 250 then msg = msg:sub(1, 250):gsub("|[^|]*$", "") end
  enqueue(msg, channel, target, true)
  return true
end

function S.Announce(force)
  local used = {}
  if not db().opts.enabled then return used end
  local g = groupChannel()
  if g and hello(g, nil, force) then used[#used + 1] = g:lower() end
  if db().opts.guild and IsInGuild and IsInGuild() and hello("GUILD", nil, force) then used[#used + 1] = "guild" end
  return used
end

------------------------------------------------------------------ dumps (outgoing)
local lastReply = {}
local ladderOut
-- the cheapest 8 price steps of a listing ladder: "price.qty.count,price.qty.count,..."
ladderOut = function(L)
  if not L or not L[1] then return "" end
  local out = {}
  for i = 1, math.min(8, #L) do
    local st = L[i]
    out[i] = b36(math.ceil(st[1])) .. "." .. b36(st[2] or 1) .. "." .. b36(st[3] or 1)
  end
  return table.concat(out, ",")
end
local function ladderIn(s)
  if not s or s == "" then return nil end
  local L = {}
  for p, q, c in s:gmatch("(%w+)%.(%w+)%.(%w+)") do
    p = n36(p, 1e11)
    if p and p > 0 and #L < 8 then L[#L + 1] = { p, n36(q, 1e7) or 1, n36(c, 1e6) or 1 } end
  end
  return L[1] and L or nil
end
S.LadderIn = ladderIn
local function sendMarket(ch, to, uid)
  local m = C.market
  local parts = {}
  for id, mi in pairs(m.items or {}) do
    if mi.m or mi.sl then
      -- listings only where Kina's math uses them: gear (disenchant / resale) gets 8
      -- price levels, trade goods 3 (material prices), anything else only the levels
      -- under what a vendor pays (AH->Vendor flips). Keeps a full scan quick to send.
      local r = C.Item(id)
      local n = 0
      if r and C.IsGear(r) and (r.q or 0) >= 2 then n = 8
      elseif r and r.cls == 7 then n = 3
      else
        local v = C.VendorPrice and C.VendorPrice(id, true) or 0
        for _, st in ipairs(mi.l or {}) do if v and v > 0 and st[1] < v then n = n + 1 end end
      end
      local L = n > 0 and mi.l or nil
      local trimmed = L and {} or nil
      if L then for i = 1, math.min(n, #L) do trimmed[i] = L[i] end end
      parts[#parts + 1] = table.concat({ b36(id), b36(mi.m or 0), b36(mi.d or mi.m or 0), b36(mi.q or 0), b36(mi.n or 0),
        ladderOut(trimmed), (n == 8) and ladderOut(mi.sl) or "" }, ":")
    end
  end
  local ver = m.scanTime or 0
  S.dumping.M = true
  enqueue(table.concat({ "B", uid, "M", b36(ver), b36(#parts) }, "|"), ch, to)
  packed("M|" .. uid .. "|", parts, ";", ch, to)
  enqueue(table.concat({ "E", uid, "M", b36(ver), b36(#parts) }, "|"), ch, to)
end

local function itemParts(t)
  local parts = {}
  for id, n in pairs(t or {}) do
    n = math.floor(n + 0.5)
    if n > 0 then parts[#parts + 1] = b36(id) .. ":" .. b36(n) end
  end
  return parts
end

local function sendLoot(ch, to, uid, base)
  local d = db()
  local ver = S.StampLoot()
  local count = 0
  enqueue(table.concat({ "B", uid, "L", b36(ver), b36(base) }, "|"), ch, to)
  for npc, r in pairs(C.db.loot) do
    if type(r) == "table" and (d.lootStamp[npc] or 0) > base and ((r.kills or 0) + (r.looted or 0) + (r.pp or 0)) > 0 then
      count = count + 1
      local nums = table.concat({ b36(r.kills), b36(r.looted), b36(r.coin), b36(r.coinLoots), b36(r.pp),
        b36(r.ppCoin), b36(r.skins), b36(r.lvl), r.elite and "1" or "0", r.rare and "1" or "0" }, ":")
      enqueue(table.concat({ "L", uid, b36(npc), nums, clean(r.nm) }, "|"), ch, to)
      for k, t in pairs({ c = r.items, p = r.ppItems, s = r.skinItems }) do
        local parts = itemParts(t)
        if #parts > 0 then packed(table.concat({ "I", uid, b36(npc), k, "" }, "|"), parts, ";", ch, to) end
      end
      if r.locs then
        local parts = {}
        for map, p in pairs(r.locs) do
          parts[#parts + 1] = table.concat({ b36(map), b36(p.x * 1000), b36(p.y * 1000), b36(p.n) }, ":")
        end
        if #parts > 0 then packed(table.concat({ "P", uid, b36(npc), "" }, "|"), parts, ";", ch, to) end
      end
    end
  end
  enqueue(table.concat({ "E", uid, "L", b36(ver), b36(count) }, "|"), ch, to)
end

local function sendOffers(ch, to, uid, base)
  local parts, ver = {}, 0
  for id, o in pairs(C.db.offers or {}) do
    if type(o) == "table" and o.each and (o.t or 0) > base and not (o.who or ""):find("Kina Scout") then
      parts[#parts + 1] = table.concat({ b36(id), b36(o.each * 100), b36(o.t or 0), clean(o.who):sub(1, 20), clean(o.where):sub(1, 20) }, ":")
      if (o.t or 0) > ver then ver = o.t end
    end
  end
  enqueue(table.concat({ "B", uid, "O", b36(ver), b36(base) }, "|"), ch, to)
  packed("O|" .. uid .. "|", parts, ";", ch, to)
  enqueue(table.concat({ "E", uid, "O", b36(ver), b36(#parts) }, "|"), ch, to)
end

local function sendVendor(ch, to, uid, base)
  local parts = {}
  local ver = 0
  for id, v in pairs(C.db.vendor) do
    if type(v) == "table" and v.p and (v.t or 0) > base then
      parts[#parts + 1] = table.concat({ b36(id), b36(v.p), b36(v.t or 0) }, ":")
      if (v.t or 0) > ver then ver = v.t end
    end
  end
  enqueue(table.concat({ "B", uid, "V", b36(ver), b36(base) }, "|"), ch, to)
  packed("V|" .. uid .. "|", parts, ";", ch, to)
  enqueue(table.concat({ "E", uid, "V", b36(ver), b36(#parts) }, "|"), ch, to)
end

-- A requester in my group gets the dump on the group channel, so one dump serves
-- every member who is missing it (receivers only keep data newer than theirs).
local function inMyGroup(name)
  return C.InGroupName and C.InGroupName(name) or false
end
-- 1.4.0: standing points told to the group in the hello (shown "unverified" on their card)
-- 1.5.4: flags others see on my profile: b = was Blacklisted once (the scar)
function S.MyFlags()
  local ok, m = pcall(function() return C.Rep and C.Rep.Mine and C.Rep.Mine() end)
  return (ok and m and m.everBlack) and "b" or ""
end
local standCache, standAt = nil, 0
function S.MyStanding()
  if GetTime and GetTime() - standAt < 60 and standCache then return standCache end
  local ok, m = pcall(function() return C.Rep and C.Rep.Mine and C.Rep.Mine() end)
  standCache, standAt = (ok and m and m.ok and m.rep) or 0, GetTime and GetTime() or 0
  return standCache
end
function S.StandingOf(name)
  local d = db()
  local want = tostring(name or ""):lower():match("^[^%-]+")
  for _, a in pairs(d.authors or {}) do
    if a.stand and a.name and tostring(a.name):lower():match("^[^%-]+") == want then return a.stand end
  end
end
-- 1.4.0: what a Kina user told us about their character (class, level, professions)
-- 1.5.1: everything their Kina last told mine, for their profile card
function S.ProfileOf(name)
  local d = db()
  local want = tostring(name or ""):lower():match("^[^%-]+")
  local best
  for _, a in pairs(d.authors or {}) do
    local nm = (a.char and a.char.from) or a.name
    if nm and tostring(nm):lower():match("^[^%-]+") == want and (not best or (a.seen or 0) > (best.seen or 0)) then best = a end
  end
  if not best then return nil end
  return { stand = best.stand, kinaLv = best.rep and best.rep.lv, seen = best.seen, char = best.char, ver = best.ver, build = best.build, scar = best.flags and best.flags:find("b") and true or nil }
end
function S.CharOf(name)
  local d = db()
  local want = tostring(name or ""):lower():match("^[^%-]+")
  local best
  for _, a in pairs(d.authors or {}) do
    local ch = a.char
    if ch and ch.from and tostring(ch.from):lower():match("^[^%-]+") == want and (not best or (ch.t or 0) > (best.t or 0)) then best = ch end
  end
  return best
end
-- 1.2.9: does a Kina user in my group (seen in the last 30 min) have this profession?
function S.GroupHasProf(prof)
  local d = db()
  for _, a in pairs(d.authors or {}) do
    local ch = a.char
    if ch and ch.profs and ch.profs[prof] and ch.from and inMyGroup(ch.from) and C.Now() - (ch.t or 0) < 1800 then return ch.from end
  end
end

local function onQuery(from, rest)
  local uid, what, base = rest:match("^(%x+)|(%u)|(%w+)$")
  local d = db()
  if not uid or uid ~= d.uid then return end
  base = n36(base) or 0
  local channel, target = "WHISPER", from
  local g = groupChannel()
  if g and inMyGroup(from) then channel, target = g, nil end
  if S.dumping[what] then return end -- already on its way to the group
  if what ~= "C" and C.ShareData and not C.ShareData() then return end -- data sharing is off
  local key = (target or channel) .. what .. base
  local now = GetTime and GetTime() or 0
  if lastReply[key] and now - lastReply[key] < REPLY_COOLDOWN then return end
  lastReply[key] = now
  if what == "M" then sendMarket(channel, target, uid)
  elseif what == "L" then sendLoot(channel, target, uid, base)
  elseif what == "V" then sendVendor(channel, target, uid, base)
  elseif what == "C" then S.SendComm(channel, target, uid)
  elseif what == "O" then sendOffers(channel, target, uid, base) end
end

------------------------------------------------------------------ hello (incoming)
local requested = {}
local function authorOf(uid, create)
  local d = db()
  local a = d.authors[uid]
  if a or not create then return a end
  local n = 0; for _ in pairs(d.authors) do n = n + 1 end
  if n >= MAX_AUTHORS then
    -- forget whoever we heard from least recently
    local oldest, ot
    for u, x in pairs(d.authors) do if not ot or (x.seen or 0) < ot then oldest, ot = u, x.seen or 0 end end
    if oldest then d.authors[oldest] = nil end
  end
  a = {}; d.authors[uid] = a
  return a
end

local incoming
local function ask(from, uid, what, base)
  local key = uid .. what
  local b = incoming and incoming[from .. uid .. what]
  if b and (GetTime and GetTime() or 0) - (b.last or b.time or 0) < 90 then return end -- still arriving
  local now = GetTime and GetTime() or 0
  if requested[key] and now - requested[key] < 120 then return end
  requested[key] = now
  enqueue(table.concat({ "Q", uid, what, b36(base) }, "|"), "WHISPER", from)
end

local function onHello(from, rest, channel)
  local f = {}
  for v in (rest .. "|"):gmatch("([^|]*)|") do f[#f + 1] = v end
  local uid, proto, name, mkey, scanT, lootV, vendT, offT = f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
  local d = db()
  if not (uid and uid:match("^%x+$") and scanT and lootV and vendT) or uid == d.uid or n36(proto) ~= PROTO then return end
  local a = authorOf(uid, true)
  a.name, a.seen = name, C.Now()
  if S.syncHeard then S.syncHeard[from] = true end
  if f[15] and f[15]:match("^%-?%d+$") then a.stand = tonumber(f[15]) end
  if f[14] and f[14]:match("^%d+%.%d+%.%d+$") then a.ver = f[14] end
  -- 1.5.4/0.9.0: the newest Kina anyone runs, by build number (older Kinas sent none:
  -- they are older than this one). An older Kina stops earning until it updates.
  a.build = tonumber(f[17]) or a.build
  if a.build and a.build > (S.newestBuild or C.BUILD or 0) then S.newestBuild = a.build; S.newestVer = a.ver end
  a.flags = f[16] or a.flags
  -- 1.2.6: someone in my group runs a newer Kina: say so once per session
  if f[14] and f[14]:match("^%d+%.%d+%.%d+$") and inMyGroup(from) and (tonumber(f[17]) or 0) > (C.BUILD or 0) then
    S.newerSeen = S.newerSeen or {}
    if not S.newerSeen[f[14]] then
      S.newerSeen[f[14]] = true
      C.Print(string.format("|cffffd100%s is on Kina %s, you're on %s: update Kina|r (download the new zip, replace the Kina folder, /reload).", C.Books and C.Books.Name and C.Books.Name(from) or from, f[14], tostring(C.version)))
    end
  end
  if C.FarmSync and C.FarmSync.Upgrade and inMyGroup(from) then pcall(C.FarmSync.Upgrade) end
  -- their character: class, level, professions (for duo farming and profession plans)
  if f[9] and f[9]:match("^%u+$") then
    local profs = {}
    for pn, sk in (f[11] or ""):gmatch("([%a ]+)=(%w+)") do profs[pn] = n36(sk, 1000) end
    a.char = { class = f[9], level = n36(f[10], 100), profs = profs, from = from, t = C.Now() }
    if C.OnKinaMate then pcall(C.OnKinaMate, name or from, a.char) end
  end
  -- their Kina reputation (unverified until the Kina server exists)
  if f[13] == "x" then a.rep = { lv = -1, t = C.Now() }
  elseif f[13] and f[13] ~= "" then a.rep = { lv = math.min(n36(f[13]) or 0, (C.Rep and C.Rep.MAX_LEVEL) or 50), t = C.Now() } end
  if C.ShareData and not C.ShareData() then
    if channel ~= "WHISPER" and channel ~= "GUILD" then hello(channel, nil, false) end
    return
  end
  scanT, lootV, vendT = n36(scanT) or 0, n36(lootV) or 0, n36(vendT) or 0
  if mkey == clean(C.MarketKey()) and scanT > ((a.market and a.market.t) or 0)
     and C.Now() - scanT < MARKET_MAX_AGE then
    ask(from, uid, "M", 0)
  end
  if lootV > ((a.loot and a.loot.ver) or 0) then ask(from, uid, "L", (a.loot and a.loot.ver) or 0) end
  if vendT > ((a.vend and a.vend.t) or 0) then ask(from, uid, "V", (a.vend and a.vend.t) or 0) end
  offT = n36(offT) or 0
  if offT > ((a.off and a.off.t) or 0) then ask(from, uid, "O", (a.off and a.off.t) or 0) end
  local commV = n36(f[12]) or 0
  if commV > 0 and commV ~= ((a.comm and a.comm.v) or 0) and inMyGroup(from) then ask(from, uid, "C", 0) end
  -- someone new in a group channel: let them know what we hold too
  if channel ~= "WHISPER" and channel ~= "GUILD" then hello(channel, nil, false)
  elseif channel == "GUILD" then hello("WHISPER", from, false) end
end

------------------------------------------------------------------ dumps (incoming)
incoming = {}   -- [from..uid..what] = buffer
S._incoming = incoming
local function buf(from, uid, what)
  local b = incoming[from .. uid .. what]
  if b then b.last = GetTime and GetTime() or 0 end -- still arriving
  return b
end

local function onBegin(from, rest)
  local uid, what, ver, base = rest:match("^(%x+)|(%u)|(%w+)|(%w+)$")
  if what and what ~= "C" and C.ShareData and not C.ShareData() then return end -- data sharing is off
  if not uid or uid == db().uid then return end
  local old = incoming[from .. uid .. what]
  if old and old.ver == (n36(ver) or 0) and (GetTime and GetTime() or 0) - (old.last or old.time or 0) < 90 then return end
  incoming[from .. uid .. what] = { what = what, ver = n36(ver) or 0, base = n36(base) or 0, expect = (what == "M") and n36(base) or nil,
    rows = {}, npcs = {}, time = GetTime and GetTime() or 0, from = from }
end

local function onMarket(from, rest)
  local uid, list = rest:match("^(%x+)|(.*)$")
  local b = uid and buf(from, uid, "M")
  if not b then return end
  b.last = GetTime and GetTime() or 0
  for part in list:gmatch("[^;]+") do
    local id, m, dd, q, n, L, SL = part:match("^(%w+):(%w+):(%w+):(%w+):(%w+):?([%w%.,]*):?([%w%.,]*)$")
    id, m = n36(id, 10000000), n36(m, 1e11)
    if id and m then
      local row = { m = (m > 0) and m or nil, d = n36(dd, 1e11) or m, q = n36(q, 1e7) or 0, n = n36(n, 1e6) or 0,
        l = ladderIn(L) or {}, sl = ladderIn(SL) }
      if row.m or row.sl then b.rows[id] = row end
    end
  end
end

local function npcBuf(b, npc)
  local e = b.npcs[npc]
  if not e then e = { items = {}, ppItems = {}, skinItems = {} }; b.npcs[npc] = e end
  return e
end

local function onLoot(from, rest)
  local uid, npc, nums, name = rest:match("^(%x+)|(%w+)|([%w:]+)|(.*)$")
  local b = uid and buf(from, uid, "L")
  npc = n36(npc, 10000000)
  if not (b and npc) then return end
  local f = {}
  for v in nums:gmatch("[^:]+") do f[#f + 1] = v end
  local e = npcBuf(b, npc)
  e.kills, e.looted, e.coin, e.coinLoots = n36(f[1], 1e7) or 0, n36(f[2], 1e7) or 0, n36(f[3], 1e12) or 0, n36(f[4], 1e7) or 0
  e.pp, e.ppCoin, e.skins = n36(f[5], 1e7) or 0, n36(f[6], 1e12) or 0, n36(f[7], 1e7) or 0
  local lvl = n36(f[8], 100); if lvl and lvl > 0 then e.lvl = lvl end
  e.elite = f[9] == "1"; e.rare = (f[10] == "1") or nil
  if name and name ~= "" then e.nm = name end
end

local function onItems(from, rest)
  local uid, npc, k, list = rest:match("^(%x+)|(%w+)|(%l)|(.*)$")
  local b = uid and buf(from, uid, "L")
  npc = n36(npc, 10000000)
  if not (b and npc) then return end
  local e = npcBuf(b, npc)
  local t = (k == "p" and e.ppItems) or (k == "s" and e.skinItems) or e.items
  for id, n in list:gmatch("(%w+):(%w+)") do
    id, n = n36(id, 10000000), n36(n, 1e7)
    if id and n and n > 0 then t[id] = n end
  end
end

local function onPlaces(from, rest)
  local uid, npc, list = rest:match("^(%x+)|(%w+)|(.*)$")
  local b = uid and buf(from, uid, "L")
  npc = n36(npc, 10000000)
  if not (b and npc) then return end
  local e = npcBuf(b, npc)
  e.locs = e.locs or {}
  for map, x, y, n in list:gmatch("(%w+):(%w+):(%w+):(%w+)") do
    map, x, y, n = n36(map, 100000), n36(x, 1000), n36(y, 1000), n36(n, 1000)
    if map and x and y then e.locs[map] = { x = x / 1000, y = y / 1000, n = math.max(1, n or 1) } end
  end
end

local function onVendor(from, rest)
  local uid, list = rest:match("^(%x+)|(.*)$")
  local b = uid and buf(from, uid, "V")
  if not b then return end
  for id, p, t in list:gmatch("(%w+):(%w+):(%w+)") do
    id, p, t = n36(id, 10000000), n36(p, 1e10), n36(t, 4e9)
    if id and p and p > 0 then b.rows[id] = { p = p, t = t or 0 } end
  end
end

local function onOffers(from, rest)
  local uid, list = rest:match("^(%x+)|(.*)$")
  local b = uid and buf(from, uid, "O")
  if not b then return end
  for id, each, t, who, where in list:gmatch("(%w+):(%w+):(%w+):([^:;]*):([^:;]*)") do
    id, each, t = n36(id, 10000000), n36(each, 1e12), n36(t, 4e9)
    if id and each and each > 0 then b.rows[id] = { each = each / 100, t = t or 0, who = who, where = where } end
  end
end
S._onOffers = onOffers

local received = {}   -- this session: [uid] = { name, M = rows, L = npcs, V = rows }
S.received = received

local function onEnd(from, rest)
  local uid, what, ver = rest:match("^(%x+)|(%u)|(%w+)|(%w+)$")
  local key = uid and (from .. uid .. what)
  local b = key and incoming[key]
  if not b then return end
  incoming[key] = nil; requested[uid .. what] = nil
  ver = n36(ver) or 0
  local a = authorOf(uid, true)
  a.seen = C.Now()
  local count = 0
  if what == "M" then
    for _ in pairs(b.rows) do count = count + 1 end
    if count > 0 and ver > ((a.market and a.market.t) or 0) then
      a.market = { mkey = C.MarketKey(), t = ver, items = b.rows }
      S.InvalidateMarket()
      C.Print(string.format("share: got %s's scan (%d prices). Kina uses the newest scan in your group.", C.Books and C.Books.Name and C.Books.Name(from) or from, count))
    end
  elseif what == "L" then
    a.loot = a.loot or { ver = 0, npcs = {} }
    if b.base > 0 and (a.loot.ver or 0) < b.base then return end -- a gap: next hello fetches all
    if b.base == 0 then a.loot.npcs = {} end
    for npc, e in pairs(b.npcs) do a.loot.npcs[npc] = e; count = count + 1 end
    a.loot.ver = ver
  elseif what == "V" then
    -- vendor payouts are facts about the server: merge, newest observation wins
    for id, v in pairs(b.rows) do
      local mine = C.db.vendor[id]
      if not mine or (mine.t or 0) < v.t then
        local r = C.Item(id)
        C.db.vendor[id] = { p = v.p, t = v.t, c = r and r.vend, from = a.name }
        count = count + 1
      end
    end
    a.vend = { t = math.max(ver, (a.vend and a.vend.t) or 0) }
  elseif what == "C" then
    for _ in pairs(b.rows) do count = count + 1 end
    if count > 0 then a.comm = { v = ver, t = C.Now(), npcs = b.rows } end
  elseif what == "O" then
    -- merchant prices: keep the cheapest known source, like your own captures
    C.db.offers = C.db.offers or {}
    for id, o in pairs(b.rows) do
      local mine = C.db.offers[id]
      if not mine or o.each < mine.each or ((mine.t or 0) < o.t and mine.who == o.who) then
        C.db.offers[id] = { each = o.each, pack = 1, cost = o.each, stock = "unlimited", where = o.where,
          who = (o.who ~= "" and o.who or "?") .. " (via " .. short(a.name or from) .. ")", t = o.t }
        count = count + 1
      end
    end
    a.off = { t = math.max(ver, (a.off and a.off.t) or 0) }
  end
  local rec = received[uid] or { name = a.name }
  received[uid] = rec
  rec[what] = (rec[what] or 0) + count
  if count > 0 and db().opts.verbose then
    local label = (what == "M" and "AH prices") or (what == "L" and "mob loot records") or (what == "O" and "merchant prices") or (what == "C" and "community mob records") or "vendor prices"
    C.Print(string.format("share: %d %s from %s.", count, label, short(a.name or from)))
  end
  if count > 0 and C.Refresh then pcall(C.Refresh) end
end

------------------------------------------------------------------ using shared data
-- Prices: own scan plus every author's scan from the same realm/faction within
-- MARKET_MAX_AGE; for each item the freshest snapshot that lists it wins.
local snapshots
function S.InvalidateMarket() snapshots = nil end
local function buildSnapshots()
  local list = {}
  if C.market.items and C.market.scanTime then
    list[#list + 1] = { t = C.market.scanTime, items = C.market.items, own = true }
  end
  local mk, now = C.MarketKey(), C.Now()
  local d = db()
  for _, a in pairs(d.opts.enabled and d.authors or {}) do
    local m = a.market
    if m and m.mkey == mk and m.items and now - (m.t or 0) < MARKET_MAX_AGE then
      list[#list + 1] = { t = m.t, items = m.items, name = a.name }
    end
  end
  table.sort(list, function(x, y) return x.t > y.t end)
  list.ownT = C.market.scanTime
  snapshots = list
  return list
end

-- Returns the item row, the name of who scanned it (nil = you) and the scan time.
function S.MarketItem(id)
  if snapshots and snapshots.ownT ~= C.market.scanTime then snapshots = nil end
  for _, s in ipairs(snapshots or buildSnapshots()) do
    local mi = s.items[id]
    if mi then return mi, s.name, s.t end
  end
end
-- Every price lookup in Kina (tooltips, bag advice, crafts, disenchant values)
-- goes through C.MarketItem, so shared scans fill gaps everywhere.
C.MarketItem = S.MarketItem

-- Loot: your record plus every other author's, summed. Other players' kills are
-- counted by corpses they looted, so a mob you killed and a partner looted is not
-- counted as two kills on both sides.
local function addInto(dst, src)
  for id, n in pairs(src or {}) do dst[id] = (dst[id] or 0) + n end
end

function S.LootRecord(npc)
  local own = C.db.loot[npc]
  local d = C.db.share
  local others
  if d and d.opts and d.opts.enabled ~= false and d.authors then
    for _, a in pairs(d.authors) do
      local e = a.loot and a.loot.npcs and a.loot.npcs[npc]
      if e then others = others or {}; others[#others + 1] = e end
    end
  end
  if not others then return own end
  local r = { kills = 0, looted = 0, coin = 0, coinLoots = 0, pp = 0, ppCoin = 0, skins = 0,
    items = {}, ppItems = {}, skinItems = {}, sharedKills = 0, sharedAuthors = #others }
  if own then
    for k, v in pairs(own) do if type(v) ~= "table" then r[k] = v end end
    addInto(r.items, own.items); addInto(r.ppItems, own.ppItems); addInto(r.skinItems, own.skinItems)
    if own.locs then r.locs = {}; for map, p in pairs(own.locs) do r.locs[map] = { x = p.x, y = p.y, n = p.n } end end
  end
  for _, e in ipairs(others) do
    local k = math.max(e.looted or 0, e.pp or 0)
    r.kills = r.kills + k; r.sharedKills = r.sharedKills + k
    r.looted = r.looted + (e.looted or 0)
    r.coin = r.coin + (e.coin or 0); r.coinLoots = r.coinLoots + (e.coinLoots or 0)
    r.pp = r.pp + (e.pp or 0); r.ppCoin = r.ppCoin + (e.ppCoin or 0); r.skins = r.skins + (e.skins or 0)
    addInto(r.items, e.items); addInto(r.ppItems, e.ppItems); addInto(r.skinItems, e.skinItems)
    r.nm = r.nm or e.nm; r.lvl = r.lvl or e.lvl
    if r.elite == nil then r.elite = e.elite end
    r.rare = r.rare or e.rare
    for map, p in pairs(e.locs or {}) do
      r.locs = r.locs or {}
      local q = r.locs[map]
      if not q then r.locs[map] = { x = p.x, y = p.y, n = p.n }
      else
        local n = q.n + p.n
        q.x = (q.x * q.n + p.x * p.n) / n; q.y = (q.y * q.n + p.y * p.n) / n; q.n = n
      end
    end
  end
  return r
end

C.LootRecord = S.LootRecord

-- Every npc with data from anyone.
function S.LootNPCs()
  local set = {}
  for npc in pairs(C.db.loot) do set[npc] = true end
  local d = C.db.share
  if d and d.opts and d.opts.enabled ~= false and d.authors then
    for _, a in pairs(d.authors) do
      for npc in pairs(a.loot and a.loot.npcs or {}) do set[npc] = true end
    end
  end
  return set
end
C.LootNPCs = S.LootNPCs

------------------------------------------------------------------ events
local frame = CreateFrame("Frame")
local groupSize = 0
frame:SetScript("OnEvent", function(_, event, ...)
  if not C.ready or not db().opts.enabled then return end
  if event == "CHAT_MSG_ADDON" then
    local prefix, text, channel, from = ...
    if prefix ~= PREFIX or type(text) ~= "string" or isMe(from) then return end
    -- Forever sends "First Surname" with no realm: use the group member's Name-Realm
    if type(from) == "string" and from:find(" ") then from = (C.GroupMemberName and C.GroupMemberName(from)) or from:match("^(%S+)") end
    if channel == "GUILD" and not db().opts.guild then return end
    local kind, rest = text:match("^(%u)|(.*)$")
    if not kind then return end
    do local u = rest:match("^(%x+)"); local a = u and db().authors and db().authors[u]; if a then a.seen = C.Now() end end
    local ok, err = pcall(function()
      if kind == "H" then onHello(from, rest, channel)
      elseif kind == "Q" then onQuery(from, rest)
      elseif kind == "B" then onBegin(from, rest)
      elseif kind == "M" then onMarket(from, rest)
      elseif kind == "L" then onLoot(from, rest)
      elseif kind == "I" then onItems(from, rest)
      elseif kind == "P" then onPlaces(from, rest)
      elseif kind == "V" then onVendor(from, rest)
      elseif kind == "O" then onOffers(from, rest)
      elseif kind == "E" then onEnd(from, rest)
      elseif kind == "C" then S._onComm(from, rest)
      elseif kind == "T" then
        local uid, to, action, amt, label = rest:match("^(%x+)|([^|]*)|(%a+)|(%d+)|(.*)$")
        local mine = C.FirstName and C.FirstName(UnitName and UnitName("player"))
        if uid and uid ~= db().uid and action == "req" and C.FirstName and C.FirstName(to) == mine and C.OnSettleRequest then
          C.OnSettleRequest(from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and action == "cnf" and C.FirstName and C.FirstName(to) == mine and C.OnSettleConfirm then
          C.OnSettleConfirm(from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and action == "fgv" and C.FirstName and C.FirstName(to) == mine and C.OnForgiven then
          C.OnForgiven(from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and action == "fga" and C.FirstName and C.FirstName(to) == mine and C.OnForgiveAck then
          C.OnForgiveAck(from, label)
        elseif uid and uid ~= db().uid and (action == "plea" or action == "ext") and C.FirstName and C.FirstName(to) == mine and C.OnDebtNote then
          C.OnDebtNote(action, from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and (action == "prh" or action == "prs") and C.PriceHold then
          C.PriceHold.OnMessage(from, action, tonumber(amt), label)
        elseif uid and uid ~= db().uid and action == "clk" and C.FirstName and C.FirstName(to) == mine and C.OnDebtClock then
          C.OnDebtClock(from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and action == "vch" and C.FirstName and C.FirstName(to) == mine and C.Vouch then
          C.Vouch.OnVouch(from, tonumber(amt), label)
        elseif uid and uid ~= db().uid and (action == "pla" or action == "exa") and C.FirstName and C.FirstName(to) == mine and C.OnForgiveAck then
          C.OnForgiveAck(from, label, action == "pla" and "plea" or "ext")
        end
      elseif kind == "S" then
        local uid, payload_to, payload = rest:match("^(%x+)|([^|]*)|(.*)$")
        local to = payload_to
        if uid and uid ~= db().uid and C.FarmSync then
          local mine = C.FarmSync.First(UnitName and UnitName("player"))
          if to == "" or to == mine then C.FarmSync.Receive(from, payload) end
        end
      elseif kind == "Z" and C.session and C.session.sync then
        -- an older Kina's farm command: can't join a shared farm
        if not S.warnedOld then S.warnedOld = true; C.Print(tostring(from) .. " runs an older Kina: group farms need Kina 0.15 or newer on both sides.") end
      elseif kind == "Z" then
        local uid, cmd, label, campKey = rest:match("^(%x+)|(%a+)|?([^|]*)|?(.*)$")
        if uid and uid ~= db().uid and C.InGroupName and C.InGroupName(from) then
          if cmd == "start" and not C.session then C.StartSession(label ~= "" and label or nil, true, campKey ~= "" and campKey or nil)
          elseif cmd == "stop" and C.session then C.StopSession(nil, "group stopped", false, true)
          elseif cmd == "pause" then C.PauseSession(true, true)
          elseif cmd == "resume" then C.PauseSession(true, false) end
          C.lastSync = { t = C.Now(), cmd = cmd, from = from, ok = true }
        elseif uid and uid ~= db().uid then
          C.lastSync = { t = C.Now(), cmd = cmd, from = from, ok = false }
          C.Print("ignored a farm " .. tostring(cmd) .. " from " .. tostring(from) .. ": Kina can't find them in your group. Tell Claude.")
        end
      elseif kind == "X" then
        local uid, k, id, n, on, who = rest:match("^(%x+)|(%a)|(%w+)|(%w+)|(%d)|?(.*)$")
        if uid and uid ~= db().uid and C.OnFarmEdit and C.InGroupName and C.InGroupName(from) then
          C.OnFarmEdit(k, n36(id), n36(n), who, on == "1", (from:match("^([^%-]+)") or from))
        end
      elseif kind == "W" then
        local uid, secs, net, coin, items, kills, paused = rest:match("^(%x+)|(%w+)|(%w+)|(%w+)|(%w+)|(%w+)|(%d)")
        local used = n36(rest:match("^%x+|%w+|%w+|%w+|%w+|%w+|%d|(%w+)") or "0", 1e11) or 0
        if uid and uid ~= db().uid then
          C.groupView = { from = (from:match("^([^%-]+)") or from), secs = n36(secs), net = (n36(net, 1e11) or 0) - used, coin = n36(coin, 1e11),
            items = n36(items, 1e11), used = used, kills = n36(kills), paused = paused == "1", t = GetTime and GetTime() or 0 }
          if C.RefreshWidget then C.RefreshWidget() end
        end
      elseif kind == "K" then
        local uid, guid = rest:match("^(%x+)|(.+)$")
        if uid and uid ~= db().uid and C.session and C.countKill then C.countKill(guid, true) end
      elseif kind == "U" then
        local uid, id, n = rest:match("^(%x+)|(%w+)|(%w+)$")
        if uid and uid ~= db().uid and C.OnFarmUse and C.InGroupName and C.InGroupName(from) then C.OnFarmUse(from, n36(id), n36(n) or 1) end
      elseif kind == "Y" then
        local uid, list = rest:match("^(%x+)|(.*)$")
        if uid and uid ~= db().uid and C.OnGroupSplit and C.InGroupName and C.InGroupName(from) then
          local by = {}
          for who, sg, v in list:gmatch("([^;=]+)=(%-?)(%w+)") do by[who] = (n36(v, 1e11) or 0) * (sg == "-" and -1 or 1) end
          C.OnGroupSplit(by, (from:match("^([^%-]+)") or from))
        end
      elseif kind == "G" then
        local uid, list = rest:match("^(%x+)|(.*)$")
        if uid and uid ~= db().uid and C.InGroupName and C.InGroupName(from) then
          local by = {}
          for who, sg, v in list:gmatch("([^;=]+)=(%-?)(%w+)") do by[who] = (n36(v, 1e11) or 0) * (sg == "-" and -1 or 1) end
          C.groupLive = { by = by, from = (from:match("^([^%-]+)") or from), t = GetTime and GetTime() or 0 }
        end
      elseif kind == "R" then
        local uid = rest:match("^(%x+)")
        local last = C.db.sessions and C.db.sessions[1]
        if uid and uid ~= db().uid and C.InGroupName and C.InGroupName(from) and last and last.gsplit and last.gsplit.mine
          and last.stop and C.Now() - last.stop < 1800 then S.SendSplit(last.gsplit.by) end
      elseif kind == "F" then
        local uid, st, sp, inc = rest:match("^(%x+)|(%w+)|(%w+)|(%w+)$")
        if uid and uid ~= db().uid and C.OnPartnerFarm then C.OnPartnerFarm(from, n36(st), n36(sp), n36(inc, 1e11) or 0) end
      end
    end)
    if not ok and (C.debug or kind == "Z" or kind == "F" or kind == "Y" or kind == "G" or kind == "R" or kind == "S" or kind == "U" or kind == "W" or kind == "X" or kind == "K") then
      C.Print("group farm message (" .. tostring(kind) .. ") from " .. tostring(from) .. " failed: " .. tostring(err) .. ". Tell Claude.")
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    local size = GetNumGroupMembers and GetNumGroupMembers() or 0
    if size > groupSize then C.After(4, function() S.Announce(true) end) end
    groupSize = size
  end
end)

------------------------------------------------------------------ community drop data
-- Each PC's ForeverGuide holds a different slice of the community's loot reports.
-- Grouped Kina users swap theirs (mobs with 20+ kills), and the farm ranking uses the
-- biggest sample for each mob, so everyone in the group sees the same numbers.
function S.CommStamp()
  do return 0 end -- 0.11.0: community data replaced by the shared drop snapshot
  local pool = C.ForeverGuidePool and C.ForeverGuidePool() or {}
  local k = 0
  for _, p in pairs(pool) do if p.kills >= 20 then k = k + p.kills end end
  return k
end
function S.SendComm(ch, to, uid)
  local pool = C.ForeverGuidePool and C.ForeverGuidePool() or {}
  local parts = {}
  for npc, p in pairs(pool) do
    if p.kills >= 20 then
      local it = {}
      for id, n in pairs(p.items) do it[#it + 1] = b36(id) .. "." .. b36(n) end
      -- one mob per part; long item lists are cut to fit a message
      local part = b36(npc) .. ":" .. b36(p.kills) .. ":" .. table.concat(it, ",")
      if #part > 200 then part = part:sub(1, 200):gsub(",[^,]*$", "") end
      parts[#parts + 1] = part
    end
  end
  S.dumping.C = true
  enqueue(table.concat({ "B", uid, "C", b36(S.CommStamp()), "0" }, "|"), ch, to)
  packed("C|" .. uid .. "|", parts, ";", ch, to)
  enqueue(table.concat({ "E", uid, "C", b36(S.CommStamp()), b36(#parts) }, "|"), ch, to)
end
local function onComm(from, rest)
  local uid, list = rest:match("^(%x+)|(.*)$")
  local b = uid and buf(from, uid, "C")
  if not b then return end
  b.last = GetTime and GetTime() or 0
  for part in list:gmatch("[^;]+") do
    local npc, k, items = part:match("^(%w+):(%w+):([%w%.,]*)$")
    npc, k = n36(npc, 1e7), n36(k, 1e7)
    if npc and k and k > 0 then
      local it = {}
      for id, n in (items or ""):gmatch("(%w+)%.(%w+)") do id, n = n36(id, 1e7), n36(n, 1e6); if id and n then it[id] = n end end
      b.rows[npc] = { kills = k, items = it }
    end
  end
end
S._onComm = onComm
-- Every grouped (or recent) Kina user's community data: { name, npcs = { [npc] = {kills, items} } }
function S.CommPools()
  local out = {}
  local d = db()
  for _, a in pairs(d.opts.enabled and d.authors or {}) do
    if a.comm and a.comm.npcs and C.Now() - (a.comm.t or 0) < 3 * 86400 then out[#out + 1] = { name = a.name, npcs = a.comm.npcs } end
  end
  return out
end

-- What's arriving right now and from whom (for the scan bar / Settings)
function S.SyncStatus()
  local LABEL = { M = "AH prices", L = "mob loot", C = "community drops", V = "vendor prices", O = "merchant prices" }
  local parts = {}
  for _, b in pairs(incoming) do
    if (GetTime and GetTime() or 0) - (b.last or b.time or 0) < 120 then
      local n = 0
      for _ in pairs(b.rows) do n = n + 1 end
      for _ in pairs(b.npcs) do n = n + 1 end
      parts[#parts + 1] = string.format("%s from %s %d%s", LABEL[b.what] or b.what, short(b.from or "?"), n, b.expect and ("/" .. b.expect) or "")
    end
  end
  local out = 0
  for _ in pairs(queue) do out = out + 1 end
  if #queue > 0 then parts[#parts + 1] = string.format("sending %d messages", #queue) end
  return table.concat(parts, ", ")
end

-- Tell the group what your farm gathered (Group.lua settles it).
-- A kill you saw during a group farm: the group's farm widgets count it too.
function S.SendKill(guid)
  local ch = groupChannel()
  if not ch or not db().opts.enabled or type(guid) ~= "string" then return end
  enqueue("K|" .. db().uid .. "|" .. guid, ch, nil, true)
end

-- Group farm control: one Start / Pause / Stop runs every Kina farm in the group.
function S.SendFarmCmd(cmd, label, campKey)
  local ch = groupChannel()
  if not ch or not db().opts.enabled or not (C.GroupSize and C.GroupSize() > 1) then return end
  enqueue(table.concat({ "Z", db().uid, cmd, ((label or ""):gsub("|", "")), campKey or "" }, "|"), ch, nil, true)
end
-- The group's farm numbers from the leader's Kina, so every widget shows the same.
function S.SendGroupView(v)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  -- net goes as before costs ("gross") plus the costs, so it can't go below zero on the wire
  enqueue(table.concat({ "W", db().uid, b36(v.secs), b36(math.max(0, v.net + (v.used or 0))), b36(math.max(0, v.coin)), b36(math.max(0, v.items)),
    b36(v.kills or 0), v.paused and "1" or "0", b36(math.max(0, v.used or 0)) }, "|"), ch, nil, true)
end
-- The leader's running split (what each has looted minus used), so every log matches.
function S.SendLiveSplit(by)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  local parts = {}
  for who, v in pairs(by) do parts[#parts + 1] = (who:gsub("[|;=]", "")) .. "=" .. (v < 0 and "-" or "") .. b36(math.floor(math.abs(v) + 0.5)) end
  enqueue("G|" .. db().uid .. "|" .. table.concat(parts, ";"), ch, nil, true)
end
-- ask the leader to send the final split again
function S.AskSplit()
  local ch = groupChannel()
  if ch and db().opts.enabled then enqueue("R|" .. db().uid, ch, nil, true) end
end
-- The shared farm log (FarmSync.lua): "S|uid|to|payload" (to = "" for everyone).
function S.SendSync(payload, to)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  enqueue(table.concat({ "S", db().uid, to or "", payload }, "|"), ch, nil, true)
end
-- settle request: "T|uid|to|action|amount|label"
function S.SendSettle(action, to, amt, label)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  enqueue(table.concat({ "T", db().uid, to or "", action, tostring(math.floor(amt or 0)), ((tostring(label or "")):gsub("|", "")) }, "|"), ch, nil, true)
end
-- 1.0.10 forgive: "T|uid|to|fgv|amount|farmref" and its answer "fga" (group channel)
function S.SendForgive(to, amt, ref, kind)
  if not db().opts.enabled then return end
  local ch = groupChannel()
  local msg = table.concat({ "T", db().uid, to or "", kind or "fgv", tostring(math.floor(amt or 0)), ((tostring(ref or "")):gsub("|", "")) }, "|")
  if ch then enqueue(msg, ch, nil, true) end -- not grouped: re-sent when you group up again
end
-- 0.9.0: the post-farm price hold: my answer (1 scanned, 2 skipped) and the leader's
-- re-priced incomes ("Name=copper,...")
function S.SendHold(action, n, label, members)
  if not db().opts.enabled then return end
  local msg = table.concat({ "T", db().uid, "", action, tostring(math.floor(n or 0)), ((tostring(label or "")):gsub("|", "")) }, "|")
  local ch = groupChannel()
  if ch then enqueue(msg, ch, nil, true)
  else for _, who in ipairs(members or {}) do enqueue(msg, "WHISPER", who) end end
end
-- 1.5.4: how long my Kina has counted on our debt (the play-time clock)
function S.SendClock(to, secs, ref)
  if not db().opts.enabled then return end
  local ch = groupChannel()
  if not ch then return end
  enqueue(table.concat({ "T", db().uid, to or "", "clk", tostring(math.floor(secs or 0)), ((tostring(ref or "")):gsub("|", "")) }, "|"), ch, nil, false)
end
-- 1.5.0: a vouch (kind 1-4) for someone in a recent farm; answered with "vca"
function S.SendVouch(to, kind, ref)
  if not db().opts.enabled then return end
  local ch = groupChannel()
  local msg = table.concat({ "T", db().uid, to or "", "vch", tostring(math.floor(kind or 1)), ((tostring(ref or "")):gsub("|", "")) }, "|")
  if ch then enqueue(msg, ch, nil, true) else enqueue(msg, "WHISPER", to) end
end
function S.SendForgiveAck(to, ref, kind)
  if not db().opts.enabled then return end
  local ch = groupChannel()
  -- the answer names what it answers: fga (forgive), pla (plea), exa (extension)
  local ack = ({ plea = "pla", ext = "exa" })[kind or ""] or "fga"
  local msg = table.concat({ "T", db().uid, to or "", ack, "0", ((tostring(ref or "")):gsub("|", "")) }, "|")
  if ch then enqueue(msg, ch, nil, true) end
end
-- a consumable you used during the group farm
function S.SendUse(id, n)
  local ch = groupChannel()
  if not ch or not db().opts.enabled or not (C.GroupSize and C.GroupSize() > 1) then return end
  enqueue(table.concat({ "U", db().uid, b36(id), b36(n or 1) }, "|"), ch, nil, true)
end

function S.SendFarmEdit(kind, id, n, who, on)
  local ch = groupChannel()
  if not ch or not db().opts.enabled or not (C.GroupSize and C.GroupSize() > 1) then return end
  enqueue(table.concat({ "X", db().uid, kind, b36(id), b36(n or 1), on and "1" or "0", who or "" }, "|"), ch, nil, true)
end

-- The leader's split at Stop: what each player looted, in copper.
function S.SendSplit(by)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  local parts = {}
  for who, v in pairs(by) do parts[#parts + 1] = (who:gsub("[|;=]", "")) .. "=" .. (v < 0 and "-" or "") .. b36(math.floor(math.abs(v) + 0.5)) end
  enqueue("Y|" .. db().uid .. "|" .. table.concat(parts, ";"), ch)
end

function S.SendFarm(s)
  local ch = groupChannel()
  if not ch or not db().opts.enabled then return end
  enqueue(table.concat({ "F", db().uid, b36(s.start or 0), b36(s.stop or 0), b36(math.max(0, s.myIncome or 0)) }, "|"), ch)
end

-- Whose scans Kina is using: newest first { {name = nil (you) | "Vellaura", t = time, items = n} }
function S.Sources()
  if snapshots and snapshots.ownT ~= C.market.scanTime then snapshots = nil end
  local out = {}
  for _, s in ipairs(snapshots or buildSnapshots()) do
    local n = 0
    for _ in pairs(s.items) do n = n + 1 end
    out[#out + 1] = { name = s.name, t = s.t, items = n }
  end
  return out
end

C.On("INIT", function()
  db()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  frame:RegisterEvent("CHAT_MSG_ADDON")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  -- a fresh scan of your own: tell the group right away
  if C.OnMarket then C.OnMarket(function() S.InvalidateMarket(); S.Announce(true) end) end
  C.After(15, function() S.Announce(true) end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(HELLO_EVERY, function() S.InvalidateMarket(); S.Announce(false) end)
    C_Timer.NewTicker(120, function()
      local now = GetTime()
      for key, b in pairs(incoming) do if now - b.time > 600 then incoming[key] = nil end end
    end)
  end
end)

------------------------------------------------------------------ commands
function S.Command(rest)
  local d = db()
  local cmd = (rest or ""):lower():match("^(%S*)")
  if cmd == "on" or cmd == "off" then
    d.opts.enabled = (cmd == "on"); S.InvalidateMarket()
    C.Print("sharing with other Kina users: " .. (d.opts.enabled and "on" or "off"))
  elseif cmd == "guild" then
    d.opts.guild = not d.opts.guild
    C.Print("share with guild too: " .. (d.opts.guild and "on" or "off"))
  elseif cmd == "verbose" then
    d.opts.verbose = not d.opts.verbose
    C.Print("announce received data in chat: " .. (d.opts.verbose and "on" or "off"))
  elseif cmd == "now" or cmd == "sync" then
    wipe(lastReply); wipe(requested)
    local used = S.Announce(true)
    C.Print(#used == 0 and "share: not in a group" .. (d.opts.guild and " or guild" or "") .. ", nobody to sync with."
      or ("share: asking " .. table.concat(used, " and ") .. " for new data."))
    -- 1.2.6: say who answered, so you know it did something
    if #used > 0 then
      S.syncHeard = {}
      C.After(15, function()
        local names = {}
        for nm in pairs(S.syncHeard or {}) do names[#names + 1] = C.Books and C.Books.Name and C.Books.Name(nm) or nm end
        S.syncHeard = nil
        if #names == 0 then C.Print("share: nobody answered. Is data sharing on for them (Kina > Settings)?")
        else
          local p = S.Progress and S.Progress()
          C.Print("share: " .. table.concat(names, ", ") .. " answered." .. (p and (p.dir == "in" and " Getting a newer scan now, watch the scan bar." or " Sending your scan now, watch the scan bar.") or " Prices are already up to date."))
        end
      end)
    end
  elseif cmd == "forget" then
    d.authors = {}; S.InvalidateMarket()
    C.Print("share: forgot all data received from other players.")
  else
    local authors, scans, mobs, sessionFrom = 0, 0, 0, 0
    local mk, now = C.MarketKey(), C.Now()
    for _, a in pairs(d.authors) do
      authors = authors + 1
      if a.market and a.market.mkey == mk and now - (a.market.t or 0) < MARKET_MAX_AGE then scans = scans + 1 end
      for _ in pairs(a.loot and a.loot.npcs or {}) do mobs = mobs + 1 end
    end
    for _ in pairs(received) do sessionFrom = sessionFrom + 1 end
    C.Print(string.format("sharing %s%s: data from %d players (%d current AH scans, %d mob records); %d players synced this session. %d messages queued.",
      d.opts.enabled and "on" or "off", d.opts.guild and " (+guild)" or "", authors, scans, mobs, sessionFrom, #queue))
    C.Print("sharing options are on the Settings tab.")
  end
end
