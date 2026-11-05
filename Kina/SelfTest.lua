-- Kina: /kina selftest. A few seconds in game that answer "does Kina work on this
-- client?": the game functions it relies on, addon messages (to yourself, and to every
-- Kina in your group, with their versions), your saved data and event log, how trades
-- have been completing, anything the game blocked, and errors Kina caught.
-- Prints PASS / WARN / FAIL lines; the result is also kept in the saved data.
local _, C = ...
local T = {}
C.SelfTest = T

local PREFIX = "KinaTest"
local function reg() if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end end
reg()
local function send(msg, ch, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch, target)
  return ok and r ~= false
end
local function me() return UnitName and UnitName("player") end

-- (name, needed for)
local NEEDS = {
  { "C_ChatInfo.SendAddonMessage", "sharing with other Kina users" },
  { "GetServerTime", "the farm log and Kina level" },
  { "IsInGroup", "shared farms" }, { "GetNumGroupMembers", "shared farms" },
  { "InitiateTrade", "the Pay button" }, { "SetTradeMoney", "the Pay button putting the money in" },
  { "AcceptTrade", "the Accept popup" }, { "GetPlayerTradeMoney", "seeing what a trade paid" },
  { "GetTargetTradeMoney", "seeing what a trade paid" },
  { "SendMail", "paying by mail" }, { "SetSendMailMoney", "paying by mail" },
  { "GetInboxHeaderInfo", "seeing money mail" }, { "GetInboxNumItems", "seeing money mail" },
  { "GetNumLootItems", "loot tracking" }, { "GetLootSlotLink", "loot tracking" }, { "GetLootSourceInfo", "which mob dropped what" },
  { "C_Container.GetContainerNumSlots", "counting your bags" }, { "C_Container.GetContainerItemInfo", "counting your bags" },
  { "UnitIsDead", "kill counting" }, { "UnitIsTapDenied", "kill counting (other players' mobs)" },
  { "StaticPopup_Show", "Kina's popups (invites, Accept)" },
  { "C_Spell.GetSpellInfo", "knowing when you mine, herb, skin, fish or disenchant" },
  { "C_Item.GetItemInfo", "item names and prices" },
}
local function exists(path)
  local t, k = path:match("^([%w_]+)%.([%w_]+)$")
  if t then local tab = _G[t]; return type(tab) == "table" and type(tab[k]) == "function" end
  return type(_G[path]) == "function"
end

local pongs, selfPing
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, from)
  if prefix ~= PREFIX or type(msg) ~= "string" then return end
  local kind, rest = msg:match("^(%a+)|?(.*)$")
  if kind == "ping" then
    local short = from and from:match("^[^%-]+")
    if short == me() then if selfPing then selfPing.back = GetTime() end; return end
    -- another Kina asked: answer with our version (whisper, so only they hear it)
    send("pong|" .. tostring(C.version), "WHISPER", from)
  elseif kind == "pong" and pongs then
    pongs[(from and from:match("^[^%-]+")) or "?"] = rest ~= "" and rest or "?"
  end
end)

local function line(state, text)
  local col = state == "PASS" and "|cff7CFC00" or (state == "WARN" and "|cffffd100" or "|cffff4040")
  C.Print(col .. state .. "|r " .. text)
  return { state, text }
end

function T.Run()
  local out = {}
  local function add(state, text) out[#out + 1] = line(state, text) end
  C.Print("|cffffd100self-test|r (version " .. tostring(C.version) .. ")")
  -- 1. game functions
  local missing = {}
  for _, n in ipairs(NEEDS) do if not exists(n[1]) then missing[#missing + 1] = n[1] .. " (" .. n[2] .. ")" end end
  if #missing == 0 then add("PASS", "all " .. #NEEDS .. " game functions Kina needs are there")
  else
    for _, m in ipairs(missing) do
      -- 1.0.10: Forever removed SetTradeMoney; Kina fills the trade's gold box instead
      if m:find("^SetTradeMoney") and MoneyInputFrame_SetCopper then
        add("WARN", "SetTradeMoney is gone on this client: Pay opens the trade and tells you the exact amount to type; Kina offers Accept once it matches")
      else add("FAIL", "missing: " .. m) end
    end
  end
  if not ERR_TRADE_COMPLETE then add("WARN", "the game has no 'trade complete' text: Kina will settle trades from the gold that moved")
  else add("PASS", "trade complete text: \"" .. tostring(ERR_TRADE_COMPLETE) .. "\"") end
  -- 2. saved data and the event log
  local ok, bad = C.EventLog and C.EventLog.Verify()
  if ok then add("PASS", string.format("event log checks out (%d lines)", #(C.db.log and C.db.log.lines or {})))
  else add("FAIL", "event log broken at line " .. tostring(bad) .. " (Kina XP counts as 0)") end
  if C.dataRepaired then add("WARN", "saved data was damaged and cleaned up at login (" .. C.dataRepaired .. " entries" ..
    ((C.repairPaths and C.repairPaths[1]) and (": " .. C.repairPaths[1]) or "") .. ")") end
  local m = C.Rep and C.Rep.Mine()
  if m then add("PASS", string.format("Kina level %s, %d XP; data sharing %s", C.Rep.Roman(m.level), m.xp, (C.ShareData and C.ShareData()) and "on" or "OFF (paused)")) end
  -- 3. how trades have gone on this client
  local st = C.db.tradeStats
  if type(st) == "table" and ((st.complete or 0) + (st.missed or 0)) > 0 then
    if (st.missed or 0) > 0 then
      add("WARN", string.format("%d trade(s) finished without the 'complete' message (settled from the gold instead); last messages: %s",
        st.missed, table.concat(st.msgs or {}, " / ")))
    else add("PASS", string.format("%d trade(s) seen completing normally", st.complete)) end
  else add("WARN", "no trade seen yet: trade a partner 1 copper, then run the self-test again") end
  -- 4. blocked actions and errors
  local blocked = C.db.blocked or {}
  if #blocked == 0 then add("PASS", "the game hasn't blocked anything Kina did")
  else
    for i = 1, math.min(3, #blocked) do add("FAIL", "blocked by the game: " .. tostring(blocked[i].func) .. " (" .. tostring(blocked[i].stage) .. ")") end
  end
  local errs = C.db.errlog or {}
  local mine = 0
  for _, e in ipairs(errs) do if e.v == C.version then mine = mine + 1 end end
  if mine == 0 then add("PASS", "no errors caught in this version")
  else add("FAIL", mine .. " error(s) caught in this version (they're in your saved data: send Kina.lua to Claude)") end
  -- 5. addon messages: to yourself now, to your group in 3 seconds
  selfPing = { at = GetTime() }
  local sent = send("ping", "WHISPER", me())
  pongs = {}
  local g = IsInGroup and IsInGroup() and ((IsInRaid and IsInRaid()) and "RAID" or "PARTY") or nil
  if g then send("ping", g) end
  if not sent then add("FAIL", "couldn't send an addon message") end
  C.After(3, function()
    local res = {}
    if sent then
      if selfPing.back then res[#res + 1] = line("PASS", string.format("addon messages work (%.1f s)", selfPing.back - selfPing.at))
      elseif next(pongs or {}) then
        -- WoW Forever doesn't echo a message you send to yourself; your group answering proves messages work
        res[#res + 1] = line("PASS", "addon messages work (your group answered; this client doesn't echo messages to yourself)")
      else res[#res + 1] = line("WARN", "an addon message to yourself never came back (normal on WoW Forever: join a group and run this again)") end
    end
    if g then
      local names = {}
      for who, v in pairs(pongs) do
        local stale = v ~= tostring(C.version)
        names[#names + 1] = who .. " " .. v .. (stale and " (different version)" or "")
      end
      table.sort(names)
      if #names > 0 then res[#res + 1] = line("PASS", "Kina in your group answered: " .. table.concat(names, ", "))
      else res[#res + 1] = line("WARN", "nobody in your group answered (no other Kina, or messages aren't getting through)") end
    end
    for _, r in ipairs(res) do out[#out + 1] = r end
    C.db.selftest = { t = C.Now(), v = C.version, lines = out }
    local fails = 0
    for _, r in ipairs(out) do if r[1] == "FAIL" then fails = fails + 1 end end
    C.Print(fails == 0 and "|cff7CFC00self-test done: nothing failed.|r" or ("|cffff4040self-test done: " .. fails .. " failed.|r"))
  end)
  return out
end
