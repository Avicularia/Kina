-- Kina: pocket data sharing with party and guild.
-- Speaks the same "KPockets" addon-message protocol as Kaydee's Pockets, so you
-- keep trading pickpocket data with guildmates who still run it.
--   R|guid                 I robbed this mob (group): hide its badge for everyone
--   V|uid:ver,...          the data versions I hold (guild / group / whisper)
--   Q|uid|base             send me that player's changes since version base (whisper)
--   B|uid|ver|base, A|uid|name, M|uid|npc|v|picks|mSeen|mCount|mTotal|mMin|mMax|name,
--   N|... (old mob line), I|uid|npc|id:seen:qty;..., L|uid|npc|map:x:y:n;..., E|uid|ver
-- Only runs while pockets are active on this character (a rogue, Kaydee's disabled).
local _, C = ...
local P = C.Pockets
local Safe = P.Safe
local PREFIX = "KPockets"
local MAX_LEN, MAX_AUTHORS, MAX_MOBS, MAX_ITEMS = 240, 500, 3000, 60
local PICK_QUIET, PICK_MAX_WAIT, REPLY_COOLDOWN = 30, 90, 60

local queue, requested, incoming, lastReply, lastAnnounce, received = {}, {}, {}, {}, {}, {}
local prefixReady = false
local function ensurePrefix()
  if prefixReady then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  prefixReady = true
end

local function enqueue(msg, channel, target, urgent)
  local it = { msg = msg, channel = channel, target = target, urgent = urgent }
  if urgent then table.insert(queue, 1, it) else queue[#queue + 1] = it end
end

local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local tokens, tokenTimer = 5, 0
local sender = CreateFrame("Frame")
sender:SetScript("OnUpdate", function(_, dt)
  tokenTimer = tokenTimer + dt
  if tokenTimer >= 1 then tokenTimer = 0; tokens = math.min(5, tokens + 1) end
  if tokens < 1 or #queue == 0 then return end
  local it = queue[1]
  if not it.urgent and InCombatLockdown and InCombatLockdown() then return end -- big dumps wait for peace
  table.remove(queue, 1); tokens = tokens - 1
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, it.msg, it.channel, it.target)
  if ok and THROTTLED and result == THROTTLED then table.insert(queue, 1, it); tokens = 0 end
end)

local function groupChannel()
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

------------------------------------------------------------------ robbed
function P.SendRobbed(guid)
  if not (P.Active() and P.DB().opts.syncRobbed) then return end
  local ch = groupChannel()
  if ch then ensurePrefix(); enqueue("R|" .. guid, ch, nil, true) end
end

------------------------------------------------------------------ versions
local function versionOf(uid)
  local d = P.DB()
  if uid == d.uid then return d.myVer or 0 end
  local a = d.shared[uid]
  return a and a.ver or 0
end
local function authorData(uid)
  local d = P.DB()
  if uid == d.uid then return d.loot end
  local a = d.shared[uid]
  return a and a.npcs
end

local function sendVersions(channel, target)
  local d = P.DB()
  local list = {}
  if (d.myVer or 0) > 0 then list[#list + 1] = d.uid .. ":" .. d.myVer end
  for uid, a in pairs(d.shared) do if uid ~= d.uid then list[#list + 1] = uid .. ":" .. (a.ver or 0) end end
  if #list == 0 then return end
  local msg = "V|"
  for _, part in ipairs(list) do
    if #msg + #part + 1 > MAX_LEN then enqueue(msg, channel, target); msg = "V|" end
    msg = msg .. (msg == "V|" and "" or ",") .. part
  end
  if msg ~= "V|" then enqueue(msg, channel, target) end
end

local function announceTo(channel, force)
  local now = GetTime()
  if force or not lastAnnounce[channel] or now - lastAnnounce[channel] > 60 then
    lastAnnounce[channel] = now; sendVersions(channel); return true
  end
end

local function announce(force)
  if not (P.Active() and P.DB().opts.shareLoot) then return {} end
  ensurePrefix()
  local used = {}
  if IsInGuild and IsInGuild() and announceTo("GUILD", force) then used[#used + 1] = "guild" end
  local g = groupChannel()
  if g and announceTo(g, force) then used[#used + 1] = (g == "RAID") and "raid" or "party" end
  return used
end

local pickTimer, firstPendingPick
function P.OnNewPick()
  local o = P.DB().opts
  if not (o.shareLoot and o.pushAfterPick) or not groupChannel() then return end
  local now = GetTime()
  firstPendingPick = firstPendingPick or now
  if pickTimer then pickTimer:Cancel() end
  local delay = PICK_QUIET
  if now - firstPendingPick + delay > PICK_MAX_WAIT then delay = math.max(1, PICK_MAX_WAIT - (now - firstPendingPick)) end
  pickTimer = C_Timer.NewTimer(delay, function()
    pickTimer, firstPendingPick = nil, nil
    local ch = groupChannel()
    if ch and P.Active() then announceTo(ch, true) end
  end)
end

local partyTicker, guildTicker, partyMins, guildMins
local function minutes(v, max) return math.max(1, math.min(max, math.floor((v or 5) + 0.5))) end
function P.RestartSyncTimers()
  local o = P.DB().opts
  local p, g = minutes(o.partyInterval, 60), minutes(o.guildInterval, 120)
  if p ~= partyMins then
    partyMins = p
    if partyTicker then partyTicker:Cancel() end
    partyTicker = C_Timer.NewTicker(p * 60, function()
      local ch = groupChannel()
      if ch and P.Active() and P.DB().opts.shareLoot then announceTo(ch, true) end
    end)
  end
  if g ~= guildMins then
    guildMins = g
    if guildTicker then guildTicker:Cancel() end
    guildTicker = C_Timer.NewTicker(g * 60, function()
      if IsInGuild and IsInGuild() and P.Active() and P.DB().opts.shareLoot then announceTo("GUILD", true) end
    end)
  end
end

local function onVersions(from, body)
  local d = P.DB()
  local theyLack, seen = false, {}
  for uid, ver in body:gmatch("([%x]+):(%d+)") do
    ver = tonumber(ver); seen[uid] = true
    local existing = d.shared[uid]
    local refetch = existing and ver and ver > 0 and ver == existing.ver and (not existing.author or not existing.hasLocs)
      and existing.refetchedVer ~= ver
    if uid ~= d.uid and ver and (ver > versionOf(uid) or refetch) then
      local asked = requested[uid]
      local n = 0; for _ in pairs(d.shared) do n = n + 1 end
      if (not asked or GetTime() - asked > 120) and (existing or n < MAX_AUTHORS) then
        requested[uid] = GetTime()
        local base = (existing and existing.stamped and not refetch) and existing.ver or 0
        enqueue("Q|" .. uid .. "|" .. base, "WHISPER", from)
      end
    elseif ver and ver < versionOf(uid) then
      theyLack = true
    end
  end
  if (d.myVer or 0) > 0 and not seen[d.uid] then theyLack = true end
  if theyLack and (not lastReply[from] or GetTime() - lastReply[from] > REPLY_COOLDOWN) then
    lastReply[from] = GetTime(); sendVersions("WHISPER", from)
  end
end

------------------------------------------------------------------ sending a dump
local sending = {}
local function n(v) return tostring(math.floor(tonumber(v) or 0)) end
local function myName()
  local first, second
  if UnitNameUnmodified then first, second = UnitNameUnmodified("player") end
  first = first or UnitName("player") or "?"
  if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() and type(second) == "string" and second ~= ""
      and not first:find(" ", 1, true) then return first .. " " .. second end
  return first
end
P.MyName = myName

local function sendDump(to, uid, base)
  local key = to .. uid
  if sending[key] then return end
  local data = authorData(uid)
  if not data then return end
  local ver = versionOf(uid)
  if base >= ver then base = 0 end
  sending[key] = true
  enqueue("B|" .. uid .. "|" .. ver .. "|" .. base, "WHISPER", to)
  local d = P.DB()
  local author = (uid == d.uid) and (d.opts.shareName and myName() or nil) or (d.shared[uid] and d.shared[uid].author)
  if author then enqueue("A|" .. uid .. "|" .. author, "WHISPER", to) end
  for npc, e in pairs(data) do
    if (e.picks or 0) > 0 and (base == 0 or (e.v or 0) > base) then
      local m = e.money or {}
      local name = (e.name or ""):gsub("|", ""):sub(1, 60)
      enqueue(table.concat({ "M", uid, n(npc), n(e.v), n(e.picks), n(m.seen), n(m.count), n(m.total), n(m.min), n(m.max), name }, "|"), "WHISPER", to)
      local head = "I|" .. uid .. "|" .. npc .. "|"
      local msg = head
      for id, it in pairs(e.items or {}) do
        local part = n(id) .. ":" .. n(it.seen) .. ":" .. n(it.qty)
        if #msg + #part + 1 > MAX_LEN then enqueue(msg, "WHISPER", to); msg = head end
        msg = msg .. (msg == head and "" or ";") .. part
      end
      if msg ~= head then enqueue(msg, "WHISPER", to) end
      head = "L|" .. uid .. "|" .. npc .. "|"
      msg = head
      for _, l in ipairs(e.locs or {}) do
        local part = n(l.m) .. ":" .. n(l.x * 1000) .. ":" .. n(l.y * 1000) .. ":" .. n(l.n or 1)
        if #msg + #part + 1 > MAX_LEN then enqueue(msg, "WHISPER", to); msg = head end
        msg = msg .. (msg == head and "" or ";") .. part
      end
      if msg ~= head then enqueue(msg, "WHISPER", to) end
    end
  end
  enqueue("E|" .. uid .. "|" .. ver, "WHISPER", to)
  C.After(#queue + 30, function() sending[key] = nil end)
end

------------------------------------------------------------------ receiving a dump
local BIG = 1000000
local function num(v, max)
  v = tonumber(v)
  if not v or v < 0 or v ~= v then return nil end
  return math.min(math.floor(v), max or BIG)
end

local function newMob(d, npc, v, picks, mSeen, mCount, mTotal, mMin, mMax, name)
  npc, picks = num(npc, 10000000), num(picks)
  if not d or not npc or not picks or picks == 0 then return end
  d.count = (d.count or 0) + 1
  if d.count > MAX_MOBS then return end
  local e = P.NewEntry()
  e.v = num(v) or 0; e.picks = picks
  e.name = name ~= "" and name:sub(1, 60) or nil
  local m = e.money
  m.seen = math.min(num(mSeen) or 0, picks); m.count = math.min(num(mCount) or 0, m.seen)
  m.total = num(mTotal, BIG * 100) or 0
  local mn, mx = num(mMin, BIG), num(mMax, BIG)
  if m.count > 0 then
    m.min = (mn and mn > 0) and mn or nil; m.max = (mx and mx > 0) and mx or nil
    if m.total / m.count > 500000 then m.count, m.total, m.min, m.max = 0, 0, nil, nil end -- >50g a pick: nonsense
  else m.total = 0 end
  d.npcs[npc] = e
end

local function sumPicks(npcs)
  local picks, spots = 0, 0
  for _, e in pairs(npcs or {}) do picks = picks + (e.picks or 0); spots = spots + (e.locs and #e.locs or 0) end
  return picks, spots
end

local function onDumpPart(from, kind, rest)
  local db = P.DB()
  if kind == "B" then
    local uid, ver, base = rest:match("^(%x+)|(%d+)|?(%d*)$")
    if uid and uid ~= db.uid then
      incoming[from .. uid] = { ver = tonumber(ver), base = tonumber(base) or 0, npcs = {}, time = GetTime(), stamped = false }
    end
  elseif kind == "A" then
    local uid, name = rest:match("^(%x+)|([^|]+)$")
    local d = uid and incoming[from .. uid]
    if d and name then
      name = name:gsub("[^%a\128-\255' %-]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):sub(1, 40)
      name = name:gsub("(%l)(%u)", "%1 %2")
      if name ~= "" then d.author = name end
    end
  elseif kind == "M" then
    local uid, npc, v, picks, a, b, c, mn, mx, name = rest:match("^(%x+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    local d = uid and incoming[from .. uid]
    if d then d.stamped = true end
    newMob(d, npc, v, picks, a, b, c, mn, mx, name or "")
  elseif kind == "N" then
    local uid, npc, picks, a, b, c, mn, mx, name = rest:match("^(%x+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    newMob(uid and incoming[from .. uid], npc, 0, picks, a, b, c, mn, mx, name or "")
  elseif kind == "I" then
    local uid, npc, list = rest:match("^(%x+)|(%d+)|(.*)$")
    local d = uid and incoming[from .. uid]
    local e = d and d.npcs[tonumber(npc)]
    if not e then return end
    for id, seen, qty in list:gmatch("(%d+):(%d+):(%d+)") do
      id, seen, qty = num(id, 10000000), num(seen), num(qty)
      e.itemCount = e.itemCount or 0
      if id and seen and seen > 0 and e.itemCount < MAX_ITEMS then
        e.itemCount = e.itemCount + 1
        e.items[id] = { seen = math.min(seen, e.picks), qty = math.max(qty or seen, 1) }
      end
    end
  elseif kind == "L" then
    local uid, npc, list = rest:match("^(%x+)|(%d+)|(.*)$")
    local d = uid and incoming[from .. uid]
    local e = d and d.npcs[tonumber(npc)]
    if not e then return end
    e.locs = e.locs or {}
    for m, x, y, cnt in list:gmatch("(%d+):(%d+):(%d+):(%d+)") do
      m, x, y, cnt = num(m, 100000), num(x), num(y), num(cnt)
      if m and m > 0 and x and y and x <= 1000 and y <= 1000 and #e.locs < 25 then
        e.locs[#e.locs + 1] = { m = m, x = x / 1000, y = y / 1000, n = math.max(1, math.min(cnt or 1, e.picks)) }
      end
    end
  elseif kind == "E" then
    local uid, ver = rest:match("^(%x+)|(%d+)$")
    local key = uid and (from .. uid)
    local d = key and incoming[key]
    if not d then return end
    incoming[key] = nil; requested[uid] = nil
    ver = tonumber(ver)
    local existing = db.shared[uid]
    local refill = existing and ver == existing.ver and d.base == 0
    if not ver or uid == db.uid or not (ver > versionOf(uid) or refill) then return end
    local merged
    if d.base > 0 then
      if not existing or (existing.ver or 0) < d.base then return end -- next sync fetches everything
      merged = {}
      for npc, e in pairs(existing.npcs or {}) do merged[npc] = e end
      for npc, e in pairs(d.npcs) do merged[npc] = e end
    else merged = d.npcs end
    local oldPicks = sumPicks(existing and existing.npcs)
    local newPicks, spots = sumPicks(merged)
    local count = 0; for _ in pairs(merged) do count = count + 1 end
    db.shared[uid] = { ver = ver, npcs = merged, updated = time(), author = d.author or (existing and existing.author),
      stamped = d.stamped or (d.base > 0 and existing and existing.stamped) or false, hasLocs = spots > 0, refetchedVer = ver }
    received[uid] = { from = from, mobs = count, spots = spots }
    if newPicks > oldPicks and C.debug then
      C.Print(string.format("pockets: +%d shared picks from %s.", newPicks - oldPicks, Ambiguate and Ambiguate(from, "short") or from))
    end
    if P.RefreshPins then pcall(P.RefreshPins) end
  end
end

------------------------------------------------------------------ incoming
local function isMe(name)
  if not name then return false end
  local short = Ambiguate and Ambiguate(name, "none") or name
  local me = UnitName("player")
  return short == me or name == me or short == myName() or name == myName()
end

local f = CreateFrame("Frame")
local groupSize = 0
f:SetScript("OnEvent", function(_, event, ...)
  if not P.Active() then return end
  if event == "CHAT_MSG_ADDON" then
    local prefix, text, channel, from = ...
    prefix, text, from = Safe(prefix), Safe(text), Safe(from)
    if prefix ~= PREFIX or not text or not from or isMe(from) then return end
    local kind, rest = text:match("^(%u)|(.*)$")
    if not kind then return end
    local o = P.DB().opts
    if kind == "R" then
      if o.syncRobbed and rest:match("^Creature%-") then P.picked[rest] = true; P.RefreshBadges() end
    elseif o.shareLoot then
      if kind == "V" then onVersions(from, rest)
      elseif kind == "Q" then
        local uid, base = rest:match("^(%x+)|?(%d*)$")
        if uid then sendDump(from, uid, tonumber(base) or 0) end
      else onDumpPart(from, kind, rest) end
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    local size = GetNumGroupMembers()
    if size > groupSize then C.After(5, function() announce(false) end) end
    groupSize = size
  end
end)

-- Called by Pockets.lua when this character's mode is decided.
local started = false
P.OnStart = function()
  if not P.Active() then f:UnregisterAllEvents(); return end
  ensurePrefix()
  f:RegisterEvent("CHAT_MSG_ADDON"); f:RegisterEvent("GROUP_ROSTER_UPDATE")
  if started then return end
  started = true
  groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
  C.After(20, function() announce(true) end)
  P.RestartSyncTimers()
  C_Timer.NewTicker(120, function()
    local now = GetTime()
    for key, d in pairs(incoming) do if now - d.time > 600 then incoming[key] = nil end end
  end)
end

function P.SyncNow()
  if not P.Active() then C.Print("pockets are not active on this character."); return end
  wipe(lastReply)
  local used = announce(true)
  C.Print(#used == 0 and "pockets: not in a group or guild, nobody to sync with." or ("pockets: asking " .. table.concat(used, " and ") .. " for new data."))
end

function P.SyncStatus()
  local d = P.DB()
  local authors, mobs, spots = 0, 0, 0
  for uid, a in pairs(d.shared) do
    if uid ~= d.uid then
      authors = authors + 1
      for _, e in pairs(a.npcs or {}) do mobs = mobs + 1; spots = spots + (e.locs and #e.locs or 0) end
    end
  end
  C.Print(string.format("pockets sharing %s: %d players have shared %d mob records and %d map spots with you.",
    d.opts.shareLoot and "on" or "off", authors, mobs, spots))
end

-- for tests
P._onDumpPart, P._onVersions, P._queue = onDumpPart, onVersions, queue
