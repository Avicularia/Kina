-- Kina: SyncCore. The shared farm log, built so every Kina in a group farm ends up
-- with exactly the same record, whatever the network does.
--
-- How it works
--  * One player leads the farm (whoever started it). Only the leader adds entries.
--  * Every entry is numbered and carries a fingerprint (hash) of itself chained to
--    the entry before it. Two logs with the same last fingerprint are identical.
--  * Each player reports only what THEY did (their loot, coin, kills seen, potions
--    used) to the leader, numbered per player. The leader files each report once
--    (a re-sent report is recognised, never counted twice) and broadcasts the entry.
--  * Players keep a report until they see it in the log, re-sending it if needed.
--  * Every 10 s the leader announces its last number and fingerprint. A player who
--    is behind asks for the missing entries; one whose fingerprint differs throws its
--    copy away and fetches the leader's.
--  * If the leader leaves the group or goes offline, the next player in line takes over
--    from its own copy, first collecting any entries a teammate has that it lacks.
--  * Everything shown (totals, kills, who looted what, the split) is computed from the
--    log alone, with the prices the leader stamped on each entry, so every widget
--    shows the same numbers.
--
-- This file is pure logic: no WoW calls. Kina plugs in send/clock/price functions
-- (FarmSync.lua), and the test suite plugs in a simulated network.
local _, C = ...
C = C or {}

local Core = {}
Core.__index = Core
C.SyncCore = Core

Core.PROTO = 1
Core.HEARTBEAT = 10
Core.RESEND = 8
Core.LEADER_TIMEOUT = 300
Core.MAX_RESEND = 25

------------------------------------------------------------------ fingerprints
-- Two independent polynomial hashes (exact in double precision), 12 hex digits.
local P1, P2 = 2147483629, 2147483587
local function hash(s)
  local a, b = 7, 11
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 131 + c) % P1
    b = (b * 137 + c) % P2
  end
  return string.format("%06x%06x", a % 16777216, b % 16777216)
end
Core.Hash = hash

local function fp(prev, ev)
  return hash(table.concat({ prev, ev.seq, ev.origin, ev.oseq, ev.kind, ev.t, ev.data }, "|"))
end

local function split(s)
  local out = {}
  for f in (s .. "|"):gmatch("([^|]*)|") do out[#out + 1] = f end
  return out
end
local function clean(s) return (tostring(s or ""):gsub("|", "")) end

------------------------------------------------------------------ node
-- env = { me = name, now = fn() seconds, send = fn(msg, to), price = fn(id, suffix) copper,
--         onChange = fn(node), onInvite = fn(sid, leader, label, camp) }
function Core.new(env)
  return setmetatable({ env = env }, Core)
end
function Core:name() return self.env.me end
function Core:now() return self.env.now() end

-- a fresh session record (also what's saved to disk)
local function newSession(sid, leader)
  return { sid = sid, leader = leader, chain = {}, head = 0, hash = "0", buf = {},
    outbox = {}, oseq = 0, seenOrig = {}, lastHB = 0, closed = false, startAt = 0, lastQ = 0 }
end

function Core:send(msg, to) self.env.send(msg, to) end
function Core:changed() if self.env.onChange then self.env.onChange(self) end end

-- Start a farm as its leader. Returns the session id.
function Core:Start(label, camp)
  local sid = clean(self:name()):sub(1, 6) .. string.format("%x", math.floor(self:now() * 10) % 2147483647)
  local s = newSession(sid, self:name())
  s.startAt = self:now()
  s.label, s.camp = clean(label), clean(camp)
  self.s = s
  self:append(self:name(), 0, "J", "") -- the leader is the first member
  self:send(table.concat({ "I", sid, self:name(), s.label or "", s.camp or "" }, "|"))
  self:changed()
  return sid
end

-- Accept an invite (the player clicked Accept).
function Core:Join(sid, leader)
  local s = newSession(sid, leader)
  self.s = s
  s.lastHB = self:now()
  s.lastJoin = self:now()
  self:send(table.concat({ "J", sid, self:name() }, "|"), leader)
  self:changed()
end

-- Resume after a reload / relog from a saved session.
function Core:Resume(saved)
  self.s = saved
  saved.buf = saved.buf or {}
  saved.lastHB = self:now()
  if saved.leader ~= self:name() then
    if self:Verify() then self:askFrom(saved.head + 1, saved.leader) end
  end
end

function Core:IsLeader() return self.s and self.s.leader == self:name() end

------------------------------------------------------------------ leader: filing entries
function Core:append(origin, oseq, kind, data)
  local s = self.s
  if not s or (s.closed and kind ~= "E") then return end
  local key = origin .. ":" .. oseq
  if oseq > 0 and s.seenOrig[key] then -- a re-sent report: just re-announce it (that is the ack)
    self:broadcast(s.chain[s.seenOrig[key]])
    return
  end
  -- the leader stamps its prices now, so every copy of the log carries the same values
  if (kind == "L" or kind == "U") and self.env.price then
    local f = {}
    for x in (data .. ":"):gmatch("([^:]*):") do f[#f + 1] = x end
    local id = tonumber(f[1])
    local suffix = (kind == "L" and f[3] ~= "") and f[3] or nil
    local v = id and math.floor((self.env.price(id, suffix) or 0) + 0.5) or 0
    if kind == "L" then data = table.concat({ f[1] or "", f[2] or "1", f[3] or "", v }, ":")
    else data = table.concat({ f[1] or "", f[2] or "1", v }, ":") end
  end
  local ev = { seq = s.head + 1, origin = origin, oseq = oseq, kind = kind, data = clean(data),
    t = math.floor(self:now() - (s.startAt or self:now())) }
  -- 1.5.4: a farm that stopped itself after an idle hour ends at its last kill
  if kind == "S" and data == "idle" then
    local lastK
    for _, e in ipairs(s.chain) do if e.kind == "K" then lastK = e.t end end
    if lastK then ev.t = math.min(ev.t, lastK + 60) end
  end
  ev.hash = fp(s.hash, ev)
  s.chain[ev.seq] = ev
  s.head, s.hash = ev.seq, ev.hash
  if oseq > 0 then s.seenOrig[key] = ev.seq end
  if kind == "S" then s.closed = true end
  if kind == "P" and not s.wrapping then
    s.pauses = s.pauses or {}
    local last = s.pauses[#s.pauses]
    if ev.data == "1" and not (last and not last.to) then s.pauses[#s.pauses + 1] = { from = math.floor(self:now()) }
    elseif ev.data == "0" and last and not last.to then last.to = math.floor(self:now()) end
  end
  self:broadcast(ev)
  self:ackOwn(ev)
  self:changed()
  return ev
end

function Core:broadcast(ev, to)
  if not ev then return end
  local s = self.s
  self:send(table.concat({ "E", s.sid, ev.seq, ev.origin, ev.oseq, ev.kind, ev.t, ev.hash, ev.data }, "|"), to)
end

-- A teammate's report, counted by WHEN it happened, not when it arrived: a report
-- delayed past the start of a pause still counts (filed inside a zero-length resume),
-- and one from inside a pause that arrives after the resume is filed and left out.
local COUNTED = { L = true, C = true, K = true, U = true }
function Core:file(origin, oseq, kind, data, at)
  local s = self.s
  if not (at and COUNTED[kind] and oseq > 0) or s.seenOrig[origin .. ":" .. oseq] then
    return self:append(origin, oseq, kind, data)
  end
  local open, inPause
  for _, p in ipairs(s.pauses or {}) do
    if not p.to then open = p end
    if at >= p.from and (not p.to or at < p.to) then inPause = true end
  end
  if open and not inPause and at < open.from then
    s.wrapping = true
    self:append(self:name(), 0, "P", "0")
    local ev = self:append(origin, oseq, kind, data)
    self:append(self:name(), 0, "P", "1")
    s.wrapping = nil
    return ev
  end
  local ev = self:append(origin, oseq, kind, data)
  if ev and inPause and not open then self:append(self:name(), 0, "E", ev.seq .. ":1") end
  return ev
end

-- Is this player in the farm? (joined in the log)
function Core:members()
  local m = {}
  for _, ev in ipairs(self.s and self.s.chain or {}) do
    if ev.kind == "J" then m[ev.origin] = true elseif ev.kind == "Q" then m[ev.origin] = nil end
  end
  return m
end

------------------------------------------------------------------ every player: reporting
-- What you did: kind L (loot "id:n:suffix"), C (coin "copper"), K (kill "key:npc"),
-- U (used "id:n"), K (kill "npc-spawn"), P (pause "1"/"0"), E (edit "seq:1" leave out /
-- "seq:0" count again), S (stop), Q (leave).
function Core:Observe(kind, data)
  local s = self.s
  if not s or s.closed then return end
  s.oseq = s.oseq + 1
  -- Stop: the leader first collects every report still on its way (see beginStop)
  if kind == "S" and self:IsLeader() then s.stopData = data; self:beginStop(); return end
  if self:IsLeader() and s.settleUntil and self:now() < s.settleUntil then
    s.deferred = s.deferred or {}
    s.deferred[#s.deferred + 1] = { self:name(), s.oseq, kind, clean(data) }
  elseif self:IsLeader() then
    self:append(self:name(), s.oseq, kind, data or "")
  else
    s.outbox[s.oseq] = { kind = kind, data = clean(data), t = self:now(), at = math.floor(self:now()) }
    self:sendReport(s.oseq)
  end
end
function Core:sendReport(oseq)
  local s, o = self.s, self.s.outbox[oseq]
  if not o then return end
  o.t = self:now()
  -- (o.at: when it happened, in server time, the same clock on every client)
  self:send(table.concat({ "O", s.sid, self:name(), oseq, o.kind, o.data, o.at or "" }, "|"), s.leader)
end
-- one of your reports made it into the log: stop re-sending it
function Core:ackOwn(ev)
  if ev.origin == self:name() and self.s.outbox[ev.oseq] then self.s.outbox[ev.oseq] = nil end
end

------------------------------------------------------------------ followers: taking entries
-- Throw away our entries from seq on (they disagree with the leader). Our own reports
-- among them go back in the outbox: the leader files each report only once, so
-- nothing we did is lost or counted twice.
function Core:truncate(from)
  local s = self.s
  for i = from, s.head do
    local ev = s.chain[i]
    if ev then
      if ev.origin == self:name() and ev.oseq > 0 and ev.kind ~= "S" then
        local data = ev.data
        if ev.kind == "L" or ev.kind == "U" then data = data:gsub(":%-?%d*$", "") end -- the leader re-prices it
        s.outbox[ev.oseq] = { kind = ev.kind, data = data, t = 0 }
      end
      if ev.oseq > 0 then s.seenOrig[ev.origin .. ":" .. ev.oseq] = nil end
    end
    s.chain[i] = nil
  end
  s.head = from - 1
  s.hash = s.head > 0 and s.chain[s.head].hash or "0"
  s.closed = false
  s.buf = {}
end

function Core:askFrom(from, who)
  local s = self.s
  if not s then return end
  if self:now() - (s.lastQ or 0) < 2 then return end
  s.lastQ = self:now()
  self:send(table.concat({ "Q", s.sid, from, self:name() }, "|"), who or s.leader)
end

function Core:takeEvent(ev)
  local s = self.s
  if ev.seq <= s.head then
    local mine = s.chain[ev.seq]
    if mine and mine.hash ~= ev.hash and not self:IsLeader() then
      -- our copy disagrees with the leader's: drop ours from there and refetch
      self:truncate(ev.seq)
      s.lastQ = 0
      self:askFrom(s.head + 1)
    end
    return
  end
  if ev.seq > s.head + 1 then
    s.buf[ev.seq] = ev
    self:askFrom(s.head + 1)
    return
  end
  if fp(s.hash, ev) ~= ev.hash then
    -- it doesn't chain onto our copy: either the entry is damaged, or our copy went a
    -- different way (after a takeover). Step back 10 entries and fetch the leader's.
    if not self:IsLeader() and s.head > 0 then
      self:truncate(math.max(1, s.head - 9))
      s.lastQ = 0
      self:askFrom(s.head + 1)
    end
    return
  end
  s.chain[ev.seq] = ev
  s.head, s.hash = ev.seq, ev.hash
  if ev.oseq > 0 then s.seenOrig[ev.origin .. ":" .. ev.oseq] = ev.seq end
  if ev.kind == "S" then s.closed = true; s.outbox = {} end -- the farm is over: nothing left to send
  self:ackOwn(ev)
  local nxt = s.buf[s.head + 1]
  s.buf[s.head + 1] = nil
  if nxt then return self:takeEvent(nxt) end
  self:changed()
end

------------------------------------------------------------------ messages in
function Core:Receive(from, msg)
  local f = split(msg)
  local kind, sid = f[1], f[2]
  if kind == "I" then
    if self.env.onInvite and not (self.s and self.s.sid == sid) then self.env.onInvite(sid, f[3], f[4], f[5]) end
    return
  end
  local s = self.s
  if not s or s.sid ~= sid then return end
  if kind == "E" then
    -- entries come from the leader, or from a teammate filling a new leader's gaps;
    -- either way an entry is only kept if its fingerprint chains onto ours
    if from ~= s.leader and not self:members()[from] then return end
    self:takeEvent({ seq = tonumber(f[3]), origin = f[4], oseq = tonumber(f[5]), kind = f[6], t = tonumber(f[7]),
      hash = f[8], data = f[9] or "" })
  elseif kind == "O" and self:IsLeader() then
    local origin = f[3]
    if origin ~= from then return end -- you can only report for yourself
    if not self:members()[origin] then return end -- not in this farm
    if f[5] == "S" then s.stopData = (f[6] == "idle") and "idle" or s.stopData; self:beginStop(); return end
    if s.settleUntil and self:now() < s.settleUntil then
      s.deferred = s.deferred or {}
      s.deferred[#s.deferred + 1] = { origin, tonumber(f[4]) or 0, f[5], f[6] or "", tonumber(f[7]) }
      return
    end
    self:file(origin, tonumber(f[4]) or 0, f[5], f[6] or "", tonumber(f[7]))
  elseif kind == "T" and not self:IsLeader() and from == s.leader then
    -- the leader is stopping: send everything not yet filed, and how many reports we made
    -- (1.4.1: once per 6 s, not on every ask: re-sending the whole outbox every 3 s
    -- jammed the throttled channel and made big farms take ~45 s to stop)
    local now = self:now()
    if not s.tSentAt or now - s.tSentAt >= 6 then
      s.tSentAt = now
      for oseq in pairs(s.outbox) do self:sendReport(oseq) end
    end
    self:send(table.concat({ "M", s.sid, self:name(), s.oseq }, "|"), s.leader)
  elseif kind == "M" and self:IsLeader() then
    if f[3] == from and s.marks then s.marks[from] = tonumber(f[4]) or 0 end
  elseif kind == "J" and self:IsLeader() then
    if f[3] ~= from then return end
    if not self:members()[from] then self:append(from, 0, "J", "") end
    -- send the newcomer the log so far
    self:serve(1, from)
  elseif kind == "Q" then
    local want, who = tonumber(f[3]) or 1, f[4]
    if who ~= from then return end
    if self:IsLeader() or s.serveAll then self:serve(want, from) end
  elseif kind == "H" then
    if from ~= s.leader then
      if not self:members()[from] then return end
      local theirHead = tonumber(f[3]) or 0
      if self:IsLeader() then
        -- two leaders (a takeover that shouldn't have happened): the longer log wins,
        -- ties go to name order. The one that steps down follows the winner; reports
        -- it filed that the winner lacks are re-sent by their owners (see truncate).
        local wins = theirHead > s.head or (theirHead == s.head and from:lower() < self:name():lower())
        if not wins then return end
        for _, d in ipairs(s.deferred or {}) do
          if d[1] == self:name() then s.outbox[d[2]] = { kind = d[3], data = d[4], t = 0 } end
        end
        s.deferred, s.settleUntil, s.stopping, s.announce = nil, nil, nil, nil
        s.leader = from
      elseif f[7] == "L" or self:now() - (s.lastHB or 0) > 25 then
        -- a new leader announcing itself, or ours has gone quiet while this member
        -- leads: follow the one that is actually leading
        s.leader = from
      else return end
    end
    s.lastHB = self:now()
    local head, h = tonumber(f[3]) or 0, f[4]
    s.leaderHead = head
    s.leaderElapsed, s.leaderElapsedAt, s.leaderPaused = tonumber(f[5]) or 0, self:now(), f[6] == "1"
    if head > s.head then self:askFrom(s.head + 1)
    elseif head < s.head and f[7] == "L" then
      -- the new leader is missing entries we have: hand them over
      self:serve(head + 1, from)
    elseif head == s.head and h ~= s.hash then
      -- same length, different log: ours is wrong. Start over from the leader's.
      s.chain, s.head, s.hash, s.buf, s.closed = {}, 0, "0", {}, false
      self:askFrom(1)
    end
  end
end

-- Stopping: ask everyone how many reports they've made, wait until all are filed
-- (or 40 s pass), then close the log. Nothing a player looted is lost to the stop.
function Core:beginStop()
  local s = self.s
  if s.closed or s.stopping then return end
  -- 1.4.1: wait at most 15 s (was 40) for the others' last reports; anything still in
  -- flight is filed by the catch-up after the stop, as before
  s.stopping, s.stopAt, s.marks, s.lastT = true, self:now() + 15, {}, 0
end
function Core:stopReady()
  local s = self.s
  if self:now() >= s.stopAt then return true end
  for name in pairs(self:members()) do
    if name ~= self:name() and not (self.env.leaderGone and self.env.leaderGone(name)) then
      local mark = s.marks[name]
      if not mark then return false end
      for k = 1, mark do if not s.seenOrig[name .. ":" .. k] then return false end end
    end
  end
  return true
end

-- Check our own copy entry by entry (a damaged saved file keeps the last fingerprint,
-- so comparing the last one alone can't see it). Cut at the first bad entry and refetch.
function Core:Verify()
  local s = self.s
  if not s then return true end
  local prev = "0"
  for i = 1, s.head do
    local ev = s.chain[i]
    if not ev or fp(prev, ev) ~= ev.hash then
      if self:IsLeader() then return false end -- the leader's copy is the reference
      s.chain[i] = nil -- the damaged one (its data can't be trusted to re-report)
      self:truncate(i)
      s.seenOrig = {}
      for k = 1, s.head do local e = s.chain[k]; if e.oseq > 0 then s.seenOrig[e.origin .. ":" .. e.oseq] = k end end
      s.lastQ = 0
      self:askFrom(i)
      self:changed()
      return false
    end
    prev = ev.hash
  end
  return true
end

-- send entries from..head to one player (capped; they ask again for the rest)
function Core:serve(from, to)
  local s = self.s
  local last = math.min(s.head, from + Core.MAX_RESEND - 1)
  -- sent to everyone, not just the asker: every member hears group messages anyway,
  -- members who already have an entry ignore it, and when several members ask for the
  -- same entries (a raid joining at once) the send queue keeps one copy of each
  -- instead of one per member (which backed a raid up by minutes)
  for i = from, last do self:broadcast(s.chain[i]) end
end

------------------------------------------------------------------ the clock (call every second)
function Core:Tick()
  local s = self.s
  if not s then return end
  local now = self:now()
  if self:IsLeader() then
    -- after taking over: teammates had a few seconds to hand over entries we lacked
    if s.deferred and not (s.settleUntil and now < s.settleUntil) then
      local list = s.deferred
      s.deferred = nil
      for _, d in ipairs(list) do self:file(d[1], d[2], d[3], d[4], d[5]) end
    end
    -- invites can be lost: repeat them for the first 3 minutes
    if now - (s.startAt or now) < 180 and now - (s.lastInvite or 0) >= 30 then
      s.lastInvite = now
      self:send(table.concat({ "I", s.sid, self:name(), s.label or "", s.camp or "" }, "|"))
    end
    if s.stopping and not s.closed then
      if self:stopReady() then
        s.stopping = nil
        self:append(self:name(), 0, "S", s.stopData or "")
      elseif now - (s.lastT or 0) >= 3 then
        s.lastT = now
        self:send(table.concat({ "T", s.sid }, "|"))
      end
    end
    -- after the stop, keep announcing for 3 minutes so late players see the end
    if s.closed and now - (s.closedAt or now) > 180 then return end
    if s.closed and not s.closedAt then s.closedAt = now end
    if now - (s.lastBeat or 0) >= Core.HEARTBEAT then
      s.lastBeat = now
      self:send(table.concat({ "H", s.sid, s.head, s.hash, math.floor(self:Elapsed()), s.pausedNow and "1" or "0", s.announce and "L" or "" }, "|"))
      if not (s.settleUntil and now < s.settleUntil) then s.announce = nil end
    end
    return
  end
  -- our join request may have been lost: ask again until we're in the log
  if not s.closed and not self:members()[self:name()] and now - (s.lastJoin or 0) >= Core.RESEND then
    s.lastJoin = now
    self:send(table.concat({ "J", s.sid, self:name() }, "|"), s.leader)
  end
  -- check our whole copy once a minute
  if now - (s.lastVerify or 0) >= 60 then s.lastVerify = now; if not self:Verify() then return end end
  -- the leader has been quiet for 25 s: ask whether we missed anything
  if now - (s.lastHB or now) > 25 and now - (s.lastQ or 0) > 25 then self:askFrom(s.head + 1) end
  -- re-send reports the leader hasn't filed yet
  for oseq, o in pairs(s.outbox) do
    if now - (o.t or 0) >= Core.RESEND then self:sendReport(oseq) end
  end
  -- the leader left the group or went offline (the game says so; lost messages never
  -- trigger this, so two players can't both think they lead). Silence for 5 minutes
  -- with no answer from the game counts too.
  -- (the game must say so for 10 s in a row: a roster that's briefly unreadable, e.g.
  -- right after a reload, must never hand the farm to someone else)
  local gone = self.env.leaderGone and self.env.leaderGone(s.leader)
  if gone then s.goneSince = s.goneSince or now else s.goneSince = nil end
  gone = gone and now - s.goneSince >= 10
  if not s.closed and (gone or now - (s.lastHB or now) > Core.LEADER_TIMEOUT) then
    s.goneSince = nil
    local order = {}
    for name in pairs(self:members()) do if name ~= s.leader then order[#order + 1] = name end end
    table.sort(order, function(a, b) return a:lower() < b:lower() end)
    if order[1] == self:name() then
      s.leader = self:name()
      s.announce = true
      s.settleUntil = now + 25
      s.startAt = now - (s.chain[s.head] and s.chain[s.head].t or 0)
      s.lastBeat = 0
      self:changed()
    elseif order[1] then
      s.leader = order[1]
      s.lastHB = now -- give the new leader time to announce itself
    end
  end
end

------------------------------------------------------------------ what the log says
-- Seconds the farm has run (pauses excluded), from the log's own times.
function Core:Elapsed()
  local s = self.s
  if not s then return 0 end
  local secs, pausedAt = 0, nil
  local lastT = 0
  for _, ev in ipairs(s.chain) do
    if ev.kind == "P" then
      if ev.data == "1" and not pausedAt then pausedAt = ev.t
      elseif ev.data == "0" and pausedAt then secs = secs - (ev.t - pausedAt); pausedAt = nil end
    end
    lastT = ev.t
    if ev.kind == "S" then break end
  end
  local endT
  if s.closed then endT = lastT
  elseif self:IsLeader() then endT = self:now() - (s.startAt or self:now())
  else endT = (s.leaderElapsed or lastT) + (s.leaderElapsedAt and not s.leaderPaused and (self:now() - s.leaderElapsedAt) or 0) end
  if pausedAt then endT = pausedAt end
  s.pausedNow = pausedAt ~= nil
  return math.max(0, endT + secs)
end

-- Totals from the log: identical on every copy with the same last fingerprint.
-- { coin, items, used, net, kills, byLooter = {name=copper}, members, paused, closed }
-- reprice (optional, 0.9.0): fn(id, suffix) -> copper each, used instead of the prices
-- stamped when the loot was filed (the post-farm AH scan re-prices the split)
function Core.Totals(s, reprice)
  local out = { coin = 0, items = 0, used = 0, kills = 0, byLooter = {}, coinBy = {}, members = {}, events = 0 }
  if not s then return out end
  local excluded, paused = {}, false
  -- edits first (they can point at any earlier entry)
  for _, ev in ipairs(s.chain) do
    if ev.kind == "E" then
      local seq, on = ev.data:match("^(%d+):(%d)$")
      if seq then excluded[tonumber(seq)] = (on == "1") or nil end
    end
  end
  local kills = {}
  -- 1.3.1: disputed loot lines ("V" = "seq:copper each") count at that value (vendor)
  local disputed = {}
  for _, ev in ipairs(s.chain) do
    if ev.kind == "V" then
      local seq, per = (ev.data or ""):match("^(%d+):(%d+)$")
      if seq then disputed[tonumber(seq)] = tonumber(per) end
    end
  end
  out.disputed = disputed
  -- 1.3.1: the per-unit value each item was counted at (its first loot entry)
  local unitVal = {}
  for _, ev in ipairs(s.chain) do
    if ev.kind == "L" and not excluded[ev.seq] then
      local id, _, sfx, v = (ev.data or ""):match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
      id = tonumber(id)
      if reprice and id then v = reprice(id, sfx ~= "" and sfx or nil) end
      if id and not unitVal[id] then unitVal[id] = tonumber(v) or 0 end
    end
  end
  for _, ev in ipairs(s.chain) do
    out.events = out.events + 1
    local k = ev.kind
    if k == "J" then out.members[ev.origin] = true; out.byLooter[ev.origin] = out.byLooter[ev.origin] or 0
    elseif k == "Q" then out.members[ev.origin] = nil
    elseif k == "P" then paused = ev.data == "1"
    elseif k == "N" then out.noSplit = true -- 1.0.10: a "don't split" farm (set by whoever started it)
    elseif not paused and not excluded[ev.seq] then
      if k == "L" then
        local lid, n, lsfx, v = ev.data:match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
        if reprice and tonumber(lid) then v = reprice(tonumber(lid), lsfx ~= "" and lsfx or nil) end
        if disputed[ev.seq] then v = disputed[ev.seq] end
        local val = (tonumber(n) or 1) * (tonumber(v) or 0)
        out.items = out.items + val
        out.byLooter[ev.origin] = (out.byLooter[ev.origin] or 0) + val
      elseif k == "C" then
        local c = tonumber(ev.data) or 0
        out.coin = out.coin + c
        out.coinBy[ev.origin] = (out.coinBy[ev.origin] or 0) + c
      elseif k == "U" then
        local _, n, v = ev.data:match("^(%d*):(%d*):(%-?%d*)$")
        local val = (tonumber(n) or 1) * (tonumber(v) or 0)
        -- 1.2.8 (Taylor): consumables are each player's own cost; they're still counted
        -- (shown as "used"), but they no longer come off the group split or the Net
        out.used = out.used + val
      elseif k == "D" then
        -- 1.3.1: farm gear that was disenchanted: its looted value comes off (the
        -- materials it became are counted as loot), so the group shares the real outcome
        local gid, gn = (ev.data or ""):match("^(%d+):(%d*)")
        gid = tonumber(gid)
        local per = gid and unitVal[gid]
        if per then
          local val = per * (tonumber(gn) or 1)
          out.items = out.items - val
          out.byLooter[ev.origin] = (out.byLooter[ev.origin] or 0) - val
          out.deSwaps = (out.deSwaps or 0) + 1
        end
      elseif k == "K" then
        -- the same mob seen by two players is one kill (data = "npc-spawn")
        local key = ev.data
        if key ~= "" and not kills[key] then kills[key] = true; out.kills = out.kills + 1 end
      end
    end
  end
  out.net = out.coin + out.items
  out.paused, out.closed = paused, s.closed
  out.noSplit = out.noSplit or nil
  return out
end

-- Even split: who pays whom so everyone ends with the same share of (loot - used).
-- Coin is left out: the game already splits it.
function Core.Split(by)
  local total, n = 0, 0
  for _, v in pairs(by) do total = total + v; n = n + 1 end
  local each = n > 0 and total / n or 0
  local pay, get = {}, {}
  for who, v in pairs(by) do
    local d = v - each
    if d > 0.5 then pay[#pay + 1] = { who = who, amt = d } elseif d < -0.5 then get[#get + 1] = { who = who, amt = -d } end
  end
  table.sort(pay, function(a, b) return a.amt > b.amt or (a.amt == b.amt and a.who < b.who) end)
  table.sort(get, function(a, b) return a.amt > b.amt or (a.amt == b.amt and a.who < b.who) end)
  local transfers, i, j = {}, 1, 1
  while pay[i] and get[j] do
    local amt = math.min(pay[i].amt, get[j].amt)
    transfers[#transfers + 1] = { from = pay[i].who, to = get[j].who, amt = math.floor(amt + 0.5) }
    pay[i].amt = pay[i].amt - amt; get[j].amt = get[j].amt - amt
    if pay[i].amt <= 0.5 then i = i + 1 end
    if get[j].amt <= 0.5 then j = j + 1 end
  end
  return total, each, transfers
end

return Core
