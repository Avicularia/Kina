local _, C = ...
-- Kina: Partners. 0.9.18 (Taylor: "Add an exp and rep bonus of 10% when selecting someone
-- as a Partner, bring back the old dialogue but revamp it so that if someone wants to
-- partner up with someone for a long time, there's incentive to do so.")
-- How it works:
--   - One partner at a time, and it takes both of you: one asks, the other accepts (or
--     you both ask). Each Kina writes "partner|on|Name" in its own log.
--   - Partners earn +10% Kina XP and standing on farms you do together (your partner in
--     the farm when it ends) and on payments between you.
--   - The bond grows: +1% more for every 5 qualifying farms together, up to +20% at 50.
--     The bond is kept per person: going back to an old partner picks up where you left.
--   - When a Kina user joins your party and you have no partner, Kina asks once (the old
--     partner popup, revamped). "Not now" leaves that player alone for 7 days.
--   - Either of you can end it (their profile page, or /kina partner end).
-- Messages (Share.lua kind "D"): D|uid|op|target, op = ask / yes / no / end.
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
local function me() return first(UnitName and UnitName("player")) end
local function db()
  C.db.pair = C.db.pair or {}
  local d = C.db.pair
  d.snooze = d.snooze or {}
  return d
end

-- the partner, from the log (the log is the record; this is only a read of it)
function P.Partner()
  local m = C.Rep and C.Rep.Mine and C.Rep.Mine()
  return m and m.partner or nil
end
function P.Bonus(name)
  local m = C.Rep and C.Rep.Mine and C.Rep.Mine()
  if not m or not m.partner then return 0, 0 end
  if name and first(name) ~= m.partner then return 0, 0 end
  return m.pairBonus or 0, m.bondFarms or 0
end
function P.IsPartner(name) local p = P.Partner(); return p ~= nil and first(name) == p end

local function send(op, target)
  local S = C.Share
  if not (S and S.Send and S.UID) then return false end
  local msg = table.concat({ "D", S.UID(), op, target }, "|")
  local ch = S.GroupChannel and S.GroupChannel()
  if ch and C.InGroupName and C.InGroupName(target) then return S.Send(msg, ch) end
  local full = C.GroupMemberName and C.GroupMemberName(target)
  return S.Send(msg, "WHISPER", full or target)
end

local function pct(b) return math.floor((b or 0) * 100 + 0.5) end

local function begin(name)
  local cur = P.Partner()
  if cur == name then return end
  if cur then C.Log("partner", "off", cur) end
  C.Log("partner", "on", name)
  local b = P.Bonus()
  C.Print(string.format("%s%s is your Kina Partner.|r Farms and payments together earn +%d%% XP and standing; the bond grows the longer you stay partners (up to +%d%%).",
    GREEN, name, pct(b), pct(C.Rep.PAIR_MAX)))
  if C.Refresh then pcall(C.Refresh) end
end
local function finish(name, quiet)
  if P.Partner() ~= name then return end
  C.Log("partner", "off", name)
  if not quiet then C.Print(string.format("you and %s are no longer partners. Your bond is kept if you partner up again.", name)) end
  if C.Refresh then pcall(C.Refresh) end
end

------------------------------------------------------------------ asking
local pending = {} -- [name] = GetTime() I asked them
function P.Ask(name)
  name = first(name)
  if not name or name == me() or C.IsMyChar(name) then return false end
  if P.Partner() == name then C.Print(name .. " is already your partner."); return false end
  if not (C.InGroupName and C.InGroupName(name)) then C.Print("partner up with someone in your party."); return false end
  pending[name] = GetTime and GetTime() or 0
  send("ask", name)
  C.Print(string.format("asked %s to be your Kina Partner.", name))
  return true
end
function P.End(name)
  local cur = P.Partner()
  if not cur or (name and first(name) ~= cur) then C.Print("you don't have a partner."); return false end
  send("end", cur)
  finish(cur)
  return true
end

local function bondText(name)
  local bonds = C.Rep and C.Rep.BondOf and C.Rep.BondOf(name) or 0
  return bonds > 0 and string.format("\n\nYou already have a bond of %d farm%s together: it picks up where you left off.", bonds, bonds == 1 and "" or "s") or ""
end
local function popups()
  if not StaticPopupDialogs or StaticPopupDialogs.KINA_PAIR then return end
  local why = "Partners earn |cff33ff66+10%% Kina XP and standing|r on farms and payments together, and the bond grows with every 5 farms you do together (up to |cff33ff66+20%%|r)."
  StaticPopupDialogs.KINA_PAIR = {
    text = "%s runs Kina.\n\nMake them your Kina Partner?\n\n" .. why .. "%s",
    button1 = "Partner up", button2 = "Not now",
    timeout = 90, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, d) if d then P.Ask(d) end end,
    OnCancel = function(_, d, reason) if d and reason == "clicked" then db().snooze[d] = C.Now() end end,
  }
  StaticPopupDialogs.KINA_PAIR_ASK = {
    text = "%s wants you as their Kina Partner.\n\n" .. why .. "%s",
    button1 = "Accept", button2 = "No thanks",
    timeout = 120, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, d) if d then send("yes", d); begin(d) end end,
    OnCancel = function(_, d) if d then send("no", d) end end,
  }
end

local function onPair(from, rest)
  local uid, op, target = rest:match("^(%x+)|(%a+)|([^|]*)$")
  if not uid or uid == (C.Share and C.Share.UID()) or first(target) ~= me() then return end
  local who = first(from)
  if not who or C.IsMyChar(who) then return end
  local now = GetTime and GetTime() or 0
  if op == "ask" then
    if P.Partner() == who then send("yes", who); return end
    if pending[who] and now - pending[who] < 300 then pending[who] = nil; send("yes", who); begin(who); return end
    popups()
    local cur = P.Partner()
    local extra = bondText(who) .. (cur and ("\n\n|cffff9933This ends your partnership with " .. cur .. ".|r") or "")
    C.ShowPopup("KINA_PAIR_ASK", who, extra, who)
  elseif op == "yes" then
    if pending[who] and now - pending[who] < 300 then pending[who] = nil; begin(who) end
  elseif op == "no" then
    if pending[who] then pending[who] = nil; C.Print(who .. " said no thanks to partnering up.") end
  elseif op == "end" then
    if P.Partner() == who then finish(who, true); C.Print(string.format("%s ended your Kina partnership. Your bond is kept if you partner up again.", who)) end
  end
end

------------------------------------------------------------------ the revamped dialog
local offered = {}
function P.OnKinaMate(name)
  local who = first(name)
  if not who or who == me() or C.IsMyChar(who) or offered[who] then return end
  offered[who] = true
  local cur = P.Partner()
  if cur == who then
    local b, n = P.Bonus()
    C.Print(string.format("%syour partner %s is here:|r +%d%% XP and standing on what you do together (%d farm%s of bond).", GREEN, who, pct(b), n, n == 1 and "" or "s"))
    return
  end
  if cur then return end -- one partner at a time: no nagging
  if C.settings and C.settings.noPairAsk then return end
  local sn = db().snooze[who]
  if sn and C.Now() - sn < SNOOZE then return end
  popups()
  C.ShowPopup("KINA_PAIR", who, bondText(who), who)
end

C.On("INIT", function()
  if C.Share and C.Share.kinds then C.Share.kinds.D = onPair end
end)
C.On("GROUP_ROSTER_UPDATE", function()
  for n in pairs(offered) do if not (C.InGroupName and C.InGroupName(n)) then offered[n] = nil end end
end)

-- the line under the record heading on the You page
function P.Line()
  local cur = P.Partner()
  if not cur then return GREY .. "No partner yet: partner up with a Kina user in your party for +10%.|r" end
  local b, n = P.Bonus()
  local nextAt = (math.floor(n / 5) + 1) * 5
  return string.format("%sPartner: %s|r  %s+%d%%|r%s", GOLD, cur, GREEN, pct(b),
    GREY .. string.format("  ·  %d farm%s together", n, n == 1 and "" or "s")
    .. (b < (C.Rep.PAIR_MAX or 0.2) and string.format(", +1%% more at %d", nextAt) or ", full bond") .. "|r")
end
