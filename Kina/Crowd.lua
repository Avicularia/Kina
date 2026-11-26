-- Kina 2.1.1: drop data shared realm-wide (Taylor, Nov 24: "wrap in kina data as well, which
-- should always be happening either way ... that is one of the founding principles for Kina").
--
-- Every Kina already shares its loot records (kills, coin, every drop, skins) with Kinas in
-- its party and guild (Share.lua), and passes on what it got from others. This does the same
-- on the realm-wide Kina network, so every Kina player's kills reach every Kina:
--   LX|uid|who|time|npc|kills:looted:coin:coinLoots:pp:ppCoin:skins:lvl:elite:rare|items|skins|name
-- uid = the Kina install that recorded it (the same id as in party/guild sharing, so the same
-- player is never counted twice), who = its character name, time = when the record was made.
-- items / skins = id.count,id.count (the biggest counts, and every recipe, that fit).
-- Records are whole totals, not additions: a newer record from the same uid replaces the old.
-- Each Kina sends its own changed records every 10 minutes, and passes on a few records
-- (its own and others') in turn, so players who weren't online still get everything.
local _, C = ...
-- a drop chance as text: "57%", "4.5%", "0.62%" (recipes are rare: whole percents would show 0%)
function C.Pct(rate)
  local p = (rate or 0) * 100
  if p >= 10 then return math.floor(p + 0.5) .. "%" end
  if p >= 1 then return string.format("%.1f%%", p) end
  return string.format("%.2f%%", p)
end
local CR = {}
C.Crowd = CR

local SEND_EVERY = 600
local OWN_PER_ROUND = 20
local RELAY_PER_ROUND = 6
local MIN_LOOTED = 3
local MAX_LOOTED = 1000000

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
  if not v or v < 0 or v ~= v or (max and v > max) then return nil end
  return v
end
local function clean(s) return (tostring(s or ""):gsub("[|;,:]", ""):sub(1, 24)) end
local function now() return C.Now() end
local function Net() return C.Net end
local function enabled()
  local N = Net()
  return N and N.Enabled and N.Enabled() and not (C.ShareData and not C.ShareData())
end
local function myUid() return C.db and C.db.share and C.db.share.uid end

function CR.Store()
  C.db.crowd = type(C.db.crowd) == "table" and C.db.crowd or {}
  return C.db.crowd
end
local function isRecipe(id)
  local r = C.Item and C.Item(id)
  return r and r.cls == 9
end

------------------------------------------------------------------ the wire
-- the item list that fits: every recipe first, then the biggest counts
local function itemList(t, room)
  local list = {}
  for id, n in pairs(t or {}) do if type(id) == "number" and (n or 0) > 0 then list[#list + 1] = { id, n, isRecipe(id) and 1 or 0 } end end
  table.sort(list, function(a, b) if a[3] ~= b[3] then return a[3] > b[3] end return a[2] > b[2] end)
  local out, len = {}, 0
  for _, x in ipairs(list) do
    local p = b36(x[1]) .. "." .. b36(x[2])
    if len + #p + 1 > room then break end
    out[#out + 1] = p; len = len + #p + 1
  end
  return table.concat(out, ",")
end
function CR.Encode(uid, who, t, npc, r)
  local nums = table.concat({ b36(r.kills), b36(r.looted), b36(r.coin), b36(r.coinLoots), b36(r.pp), b36(r.ppCoin),
    b36(r.skins), b36(r.lvl), r.elite and "1" or "0", r.rare and "1" or "0" }, ":")
  local head = table.concat({ "LX", uid, clean(who), b36(t), b36(npc), nums }, "|")
  local nm = clean(r.nm)
  local room = 250 - #head - #nm - 4
  local items = itemList(r.items, math.floor(room * 0.75))
  local skins = itemList(r.skinItems, room - #items)
  return head .. "|" .. items .. "|" .. skins .. "|" .. nm
end
local function itemsIn(s, looted)
  local t = {}
  for id, n in tostring(s or ""):gmatch("(%w+)%.(%w+)") do
    id, n = n36(id, 10000000), n36(n, (looted or 0) * 20 + 20)
    if id and n then t[id] = n end
  end
  return t
end
function CR.Decode(f)
  -- f = { "LX", uid, who, time, npc, nums, items, skins, name }
  local uid, who, t, npc = f[2], f[3], n36(f[4]), n36(f[5], 10000000)
  if not (uid and uid:match("^%x+$") and t and npc and f[6]) then return nil end
  local n = {}
  for x in (f[6] .. ":"):gmatch("([^:]*):") do n[#n + 1] = x end
  local looted = n36(n[2], MAX_LOOTED)
  if not looted then return nil end
  local r = { kills = n36(n[1], MAX_LOOTED) or 0, looted = looted, coin = n36(n[3], 1e12) or 0, coinLoots = n36(n[4], MAX_LOOTED) or 0,
    pp = n36(n[5], MAX_LOOTED) or 0, ppCoin = n36(n[6], 1e12) or 0, skins = n36(n[7], MAX_LOOTED) or 0, lvl = n36(n[8], 100),
    elite = n[9] == "1" or nil, rare = n[10] == "1" or nil, nm = (f[9] and f[9] ~= "") and f[9] or nil, t = t }
  r.items = itemsIn(f[7], looted); r.skinItems = itemsIn(f[8], r.skins)
  return uid, who, npc, r
end

------------------------------------------------------------------ receiving
local function onLX(from, f)
  local uid, who, npc, r = CR.Decode(f)
  if not uid or uid == myUid() then return end
  if r.t > now() + 600 then r.t = now() end
  local s = CR.Store()
  local u = s[uid] or { npcs = {} }
  u.who = (who and who ~= "") and who or u.who
  local have = u.npcs[npc]
  if have and (have.t or 0) >= r.t then return end
  u.npcs[npc] = r
  u.heard = now()
  s[uid] = u
  CR.dirty = true
end

------------------------------------------------------------------ sending
local relayAt = {}
function CR.Round()
  if not enabled() then return end
  local N = Net()
  local uid = myUid()
  if not uid then return end
  local who = (UnitName and UnitName("player")) or "?"
  C.db.crowdSent = type(C.db.crowdSent) == "table" and C.db.crowdSent or {}
  local sent = C.db.crowdSent
  -- 1) my records that changed since I last sent them
  local n = 0
  for npc, r in pairs(C.db.loot or {}) do
    if n >= OWN_PER_ROUND then break end
    if type(npc) == "number" and type(r) == "table" then
      local k = math.max(r.looted or 0, r.pp or 0, r.kills or 0)
      if k >= MIN_LOOTED and (sent[npc] or 0) ~= k then
        N.BroadcastBulk(CR.Encode(uid, who, now(), npc, r))
        sent[npc] = k; relayAt["me:" .. npc] = now(); n = n + 1
      end
    end
  end
  -- 2) a few records in turn (mine and others'), the ones passed on longest ago first
  local pool = {}
  for npc, r in pairs(C.db.loot or {}) do
    if type(npc) == "number" and type(r) == "table" and (r.looted or 0) >= MIN_LOOTED then pool[#pool + 1] = { key = "me:" .. npc, uid = uid, who = who, npc = npc, r = r, t = now() } end
  end
  for u, rec in pairs(CR.Store()) do
    for npc, r in pairs(rec.npcs or {}) do
      if (r.looted or 0) >= MIN_LOOTED then pool[#pool + 1] = { key = u .. ":" .. npc, uid = u, who = rec.who, npc = npc, r = r, t = r.t } end
    end
  end
  table.sort(pool, function(a, b) return (relayAt[a.key] or 0) < (relayAt[b.key] or 0) end)
  for i = 1, math.min(RELAY_PER_ROUND, #pool) do
    local p = pool[i]
    N.BroadcastBulk(CR.Encode(p.uid, p.who or "?", p.t, p.npc, p.r))
    relayAt[p.key] = now()
  end
end

------------------------------------------------------------------ pooling
-- C.LootRecord / C.LootNPCs (Share.lua) pool your record with party and guild sharing;
-- network records join them, skipping any install already shared through party or guild.
local baseRecord, baseNPCs
local function addInto(dst, src) for id, n in pairs(src or {}) do dst[id] = (dst[id] or 0) + n end end
local function authorsHave(uid, npc)
  local a = C.db.share and C.db.share.authors and C.db.share.authors[uid]
  return a and a.loot and a.loot.npcs and a.loot.npcs[npc] and true or false
end
local function pooled(npc)
  local r = baseRecord(npc)
  local extra
  for uid, rec in pairs(CR.Store()) do
    local e = rec.npcs and rec.npcs[npc]
    if e and uid ~= myUid() and not authorsHave(uid, npc) then extra = extra or {}; extra[#extra + 1] = e end
  end
  if not extra then return r end
  local out = { kills = 0, looted = 0, coin = 0, coinLoots = 0, pp = 0, ppCoin = 0, skins = 0, items = {}, ppItems = {}, skinItems = {}, sharedKills = 0 }
  if r then
    for k, v in pairs(r) do if type(v) ~= "table" then out[k] = v end end
    addInto(out.items, r.items); addInto(out.ppItems, r.ppItems); addInto(out.skinItems, r.skinItems)
    out.locs = r.locs
  end
  for _, e in ipairs(extra) do
    local k = math.max(e.looted or 0, e.pp or 0)
    out.kills = out.kills + k; out.sharedKills = (out.sharedKills or 0) + k
    out.looted = out.looted + (e.looted or 0)
    out.coin = out.coin + (e.coin or 0); out.coinLoots = out.coinLoots + (e.coinLoots or 0)
    out.pp = out.pp + (e.pp or 0); out.ppCoin = out.ppCoin + (e.ppCoin or 0); out.skins = out.skins + (e.skins or 0)
    addInto(out.items, e.items); addInto(out.skinItems, e.skinItems)
    out.nm = out.nm or e.nm; out.lvl = out.lvl or e.lvl
    if out.elite == nil then out.elite = e.elite end
    out.rare = out.rare or e.rare
  end
  out.networkKills = 0
  for _, e in ipairs(extra) do out.networkKills = out.networkKills + (e.looted or 0) end
  return out
end
local function hook()
  if baseRecord or not C.LootRecord then return end
  baseRecord, baseNPCs = C.LootRecord, C.LootNPCs
  C.LootRecord = pooled
  C.LootNPCs = function()
    local set = baseNPCs and baseNPCs() or {}
    for _, rec in pairs(CR.Store()) do for npc in pairs(rec.npcs or {}) do set[npc] = true end end
    return set
  end
end
-- how many Kina players and looted kills the network has given you
function CR.Summary()
  local players, mobs, kills = 0, {}, 0
  for _, rec in pairs(CR.Store()) do
    players = players + 1
    for npc, e in pairs(rec.npcs or {}) do mobs[npc] = true; kills = kills + (e.looted or 0) end
  end
  local m = 0
  for _ in pairs(mobs) do m = m + 1 end
  return players, m, kills
end

------------------------------------------------------------------ start
local started
local function start()
  if started then return end
  started = true
  hook()
  local N = Net()
  if N and N.On then N.On("LX", onLX) end
  if C.After then C.After(90, function() pcall(CR.Round) end) end
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(SEND_EVERY, function() pcall(CR.Round) end)
    -- the hot list rebuilds with what arrived
    C_Timer.NewTicker(120, function()
      if CR.dirty then CR.dirty = nil; if C.Hot and C.Hot.Invalidate then pcall(C.Hot.Invalidate) end end
    end)
  end
end
C.On("PLAYER_LOGIN", start)
hook()
