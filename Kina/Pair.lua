local _, C = ...
-- Kina: Partners. 0.9.18 (Taylor: "Add an exp and rep bonus of 10% when selecting someone
-- as a Partner, bring back the old dialogue but revamp it so that if someone wants to
-- partner up with someone for a long time, there's incentive to do so.")
-- 0.9.19 (Taylor): partners are ACCOUNTS, never characters. Every Kina has its own Kina ID
-- (Share.lua's uid, one per account per realm); partners, bonds and these messages all
-- use it, and Kina remembers which characters belong to each Kina ID.
-- How it works:
--   - One partner at a time, and it takes both of you: one asks, the other accepts (or
--     you both ask). Each Kina writes "partner|on|<their Kina ID>|<name>" in its own log.
--   - Partners earn +10% Kina XP and standing on farms together (any character of your
--     partner's in the farm when it ends) and on payments with any of their characters.
--   - The bond grows: +1% more for every 5 qualifying farms together, up to +20% at 50.
--     The bond is kept per account: going back to an old partner picks up where you left.
--   - When a Kina user joins your party and you have no partner, Kina asks once (the old
--     partner popup, revamped). "Not now" leaves that account alone for 7 days.
--   - Either of you can end it (their profile page, or /kina partner end).
-- Messages (Share.lua kind "D"): D|myKinaID|op|theirKinaID, op = ask / yes / no / end.
local P = {}
C.Pair = P
local GOLD, GREEN, GREY = "|cffffc54a", "|cff33ff66", "|cff9d9d9d"
local SNOOZE = 7 * 86400

local function first(n)
  if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return nil end
  local f = n:match("^%s*([^%s%-]+)")
  if not f then return nil end
  return f:sub(1, 1):upper() .. f:sub(2):lower()
end
local function db()
  C.db.pair = C.db.pair or {}
  local d = C.db.pair
  d.snooze = d.snooze or {}
  return d
end
local function S() return C.Share end
local function myID() return S() and S().UID and S().UID() end
local function uidOf(name) return S() and S().UIDOf and S().UIDOf(name) end
local function nameOf(uid) return first(S() and S().NameOf and S().NameOf(uid)) end

-- the partner (a Kina ID), from the log (the log is the record; this only reads it)
local function mine() return C.Rep and C.Rep.Mine and C.Rep.Mine() end
function P.Partner() local m = mine(); return m and m.partner or nil end
function P.PartnerName()
  local m = mine()
  if not (m and m.partner) then return nil end
  return nameOf(m.partner) or m.partnerName
end
function P.IsPartner(name) local p = P.Partner(); return p ~= nil and uidOf(name) == p end
function P.Bonus(name)
  local m = mine()
  if not m or not m.partner then return 0, 0 end
  if name and uidOf(name) ~= m.partner then return 0, 0 end
  return m.pairBonus or 0, m.bondFarms or 0
end

local function send(op, uid)
  local Sh = S()
  if not (Sh and Sh.Send and myID()) or not uid then return false end
  local msg = table.concat({ "D", myID(), op, uid }, "|")
  local who = Sh.NameOf(uid)
  -- whichever of their characters is in my group right now
  if not (who and C.InGroupName and C.InGroupName(who)) and Sh.CharsOf then
    for _, n in ipairs(Sh.CharsOf(uid)) do if C.InGroupName and C.InGroupName(n) then who = n; break end end
  end
  local ch = Sh.GroupChannel and Sh.GroupChannel()
  if ch and who and C.InGroupName and C.InGroupName(who) then return Sh.Send(msg, ch) end
  if not who then return false end
  local full = C.GroupMemberName and C.GroupMemberName(who)
  return Sh.Send(msg, "WHISPER", full or who)
end

local function pct(b) return math.floor((b or 0) * 100 + 0.5) end

local function begin(uid)
  local cur = P.Partner()
  if cur == uid then return end
  if cur then C.Log("partner", "off", cur) end
  C.Log("partner", "on", uid, nameOf(uid) or "?")
  local b = P.Bonus()
  C.Print(string.format("%s%s is your Kina Partner|r (every character on their account). Farms and payments together earn +%d%% XP and standing; the bond grows the longer you stay partners (up to +%d%%).",
    GREEN, P.PartnerName() or "?", pct(b), pct(C.Rep.PAIR_MAX)))
  if C.Refresh then pcall(C.Refresh) end
end
local function finish(uid)
  if P.Partner() ~= uid then return false end
  C.Log("partner", "off", uid)
  if C.Refresh then pcall(C.Refresh) end
  return true
end

------------------------------------------------------------------ asking
local pending = {} -- [Kina ID] = GetTime() I asked them
function P.Ask(name)
  local uid = uidOf(name)
  if not uid or uid == myID() or (C.IsMyChar and C.IsMyChar(name)) then
    if uid ~= myID() and not (C.IsMyChar and C.IsMyChar(name)) then C.Print("no Kina heard from " .. tostring(first(name) or name) .. " yet.") end
    return false
  end
  if P.Partner() == uid then C.Print(tostring(first(name)) .. " is already your partner."); return false end
  if not (C.InGroupName and C.InGroupName(name)) then C.Print("partner up with someone in your party."); return false end
  pending[uid] = GetTime and GetTime() or 0
  send("ask", uid)
  C.Print(string.format("asked %s to be your Kina Partner.", first(name)))
  return true
end
function P.End()
  local cur = P.Partner()
  if not cur then C.Print("you don't have a partner."); return false end
  local nm = P.PartnerName() or "your partner"
  send("end", cur)
  finish(cur)
  C.Print(string.format("you and %s are no longer partners. Your bond is kept if you partner up again.", nm))
  return true
end

local function extraText(uid)
  local t = ""
  local chars = S() and S().CharsOf and S().CharsOf(uid) or {}
  if #chars > 1 then t = t .. "\n\nTheir characters: " .. table.concat(chars, ", ") .. "." end
  local bonds = C.Rep and C.Rep.BondOf and C.Rep.BondOf(uid) or 0
  if bonds > 0 then t = t .. string.format("\n\nYou already have a bond of %d farm%s together: it picks up where you left off.", bonds, bonds == 1 and "" or "s") end
  return t
end
local function popups()
  if not StaticPopupDialogs or StaticPopupDialogs.KINA_PAIR then return end
  local why = "Partners earn |cff33ff66+10%% Kina XP and standing|r on farms and payments together, on any of your characters, and the bond grows with every 5 farms you do together (up to |cff33ff66+20%%|r)."
  StaticPopupDialogs.KINA_PAIR = {
    text = "%s runs Kina.\n\nMake them your Kina Partner?\n\n" .. why .. "%s",
    button1 = "Partner up", button2 = "Not now",
    timeout = 90, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, d) if d then P.Ask(d.name) end end,
    OnCancel = function(_, d, reason) if d and reason == "clicked" then db().snooze[d.uid] = C.Now() end end,
  }
  StaticPopupDialogs.KINA_PAIR_ASK = {
    text = "%s wants you as their Kina Partner.\n\n" .. why .. "%s",
    button1 = "Accept", button2 = "No thanks",
    timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, d) if d then send("yes", d.uid); begin(d.uid) end end,
    OnCancel = function(_, d) if d then send("no", d.uid) end end,
  }
end

local function onPair(from, rest)
  local uid, op, target = rest:match("^(%x+)|(%a+)|(%x+)$")
  if not uid or uid == myID() or target ~= myID() then return end
  -- the sender must be a character that Kina ID has said hello from
  if uidOf(from) ~= uid then return end
  local who = first(from) or "?"
  local now = GetTime and GetTime() or 0
  if op == "ask" then
    if P.Partner() == uid then send("yes", uid); return end
    if pending[uid] and now - pending[uid] < 300 then pending[uid] = nil; send("yes", uid); begin(uid); return end
    popups()
    local cur = P.Partner()
    local extra = extraText(uid) .. (cur and ("\n\n|cffff9933This ends your partnership with " .. (P.PartnerName() or "your partner") .. ".|r") or "")
    C.ShowPopup("KINA_PAIR_ASK", who, extra, { uid = uid, name = who })
  elseif op == "yes" then
    if pending[uid] and now - pending[uid] < 300 then pending[uid] = nil; begin(uid) end
  elseif op == "no" then
    if pending[uid] then pending[uid] = nil; C.Print(who .. " said no thanks to partnering up.") end
  elseif op == "end" then
    if finish(uid) then C.Print(string.format("%s ended your Kina partnership. Your bond is kept if you partner up again.", who)) end
  end
end

------------------------------------------------------------------ the revamped dialog
local offered = {} -- [Kina ID] = true this session
function P.OnKinaMate(name)
  local uid = uidOf(name)
  if not uid or uid == myID() or offered[uid] then return end
  offered[uid] = true
  local cur = P.Partner()
  if cur == uid then
    local b, n = P.Bonus()
    C.Print(string.format("%syour partner %s is here:|r +%d%% XP and standing on what you do together (%d farm%s of bond).", GREEN, first(name) or "?", pct(b), n, n == 1 and "" or "s"))
    return
  end
  if cur then return end -- one partner at a time: no nagging
  if C.TrackOnly and C.TrackOnly() then return end -- 0.9.20: no XP to share while tracker only
  if C.settings and C.settings.noPairAsk then return end
  local sn = db().snooze[uid]
  if sn and C.Now() - sn < SNOOZE then return end
  popups()
  C.ShowPopup("KINA_PAIR", first(name) or "?", extraText(uid), { uid = uid, name = name })
end

-- a character of my partner's account Kina hasn't logged yet: log it (payments with it count)
local function onHello(from, uid, a)
  local cur = P.Partner()
  if not cur or uid ~= cur then return end
  local m = mine()
  local nm = first(a and a.char and a.char.from or from)
  if nm and C.Rep and C.Rep.HasChar and not C.Rep.HasChar(m and m.pchars, uid, nm) then C.Log("pairchar", uid, nm) end
end

C.On("INIT", function()
  local Sh = S()
  if Sh and Sh.kinds then
    Sh.kinds.D = onPair
    local prev = Sh.onHello
    Sh.onHello = function(from, uid, a, channel)
      if prev then prev(from, uid, a, channel) end
      pcall(onHello, from, uid, a)
    end
  end
end)
C.On("GROUP_ROSTER_UPDATE", function()
  for u in pairs(offered) do
    local n = S() and S().NameOf and S().NameOf(u)
    if not (n and C.InGroupName and C.InGroupName(n)) then offered[u] = nil end
  end
end)

-- the line under the record heading on the You page
-- 1.0.0: the short form for the record row ("Kina Partner")
function P.Short()
  local cur = P.Partner()
  if not cur then return GREY .. "none yet|r" end
  local b, n = P.Bonus()
  return string.format("%s%s|r  %s+%d%%|r", GOLD, P.PartnerName() or "?", GREEN, pct(b))
end
function P.Line()
  local cur = P.Partner()
  if not cur then return GREY .. "No partner yet: partner up with a Kina user in your party for +10%.|r" end
  local b, n = P.Bonus()
  local nextAt = (math.floor(n / 5) + 1) * 5
  return string.format("%sYour partner %s|r  %s+%d%%|r%s", GOLD, P.PartnerName() or "?", GREEN, pct(b),
    GREY .. string.format("  ·  %d farm%s together", n, n == 1 and "" or "s")
    .. (b < (C.Rep.PAIR_MAX or 0.2) and string.format(", +1%% more at %d", nextAt) or ", full bond") .. "|r")
end
