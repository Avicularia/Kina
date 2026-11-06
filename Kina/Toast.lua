local ADDON, C = ...
-- 1.2.6: a payment fanfare. When both Kinas confirm a payment, a toast shows who paid
-- whom and what each side earned ("You +5 XP · Tri +44 XP"); a debt that closes gets a
-- bigger "Debt settled!". Only confirmed payments against a real open debt count; tiny
-- part payments that earn nothing get a chat line instead; one toast per person per
-- 5 minutes (more merge into it); never in combat (it waits); follows the fanfare setting.
local T = {}
C.Toast = T
local GOLD, GREEN, GREY = "|cffffd100", "|cff7CFC00", "|cff9d9d9d"
local frame, last, waiting = nil, {}, {}

local function build()
  if frame then return frame end
  local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(380, 104); f:SetPoint("TOP", UIParent, "TOP", 0, -140); f:SetFrameStrata("HIGH")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.92); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
  end
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  f.title = f:CreateFontString(nil, "OVERLAY"); f.title:SetFont(font, 17, "OUTLINE"); f.title:SetPoint("TOP", 0, -10)
  f.line1 = f:CreateFontString(nil, "OVERLAY"); f.line1:SetFont(font, 13, ""); f.line1:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
  f.line2 = f:CreateFontString(nil, "OVERLAY"); f.line2:SetFont(font, 12, ""); f.line2:SetPoint("TOP", f.line1, "BOTTOM", 0, -4)
  f:Hide()
  local t = 0
  f:SetScript("OnUpdate", function(self, el)
    t = t + el
    if t > 6 then self:SetAlpha(math.max(0, 1 - (t - 6))) end
    if t > 7 then self:Hide() end
  end)
  f:SetScript("OnShow", function(self) t = 0; self:SetAlpha(1) end)
  f:EnableMouse(true); f:SetScript("OnMouseDown", function(self) self:Hide() end)
  frame = f
  return f
end

local function show(p)
  if InCombatLockdown and InCombatLockdown() then waiting[#waiting + 1] = p; return end
  local f = build()
  f.title:SetText(p.closed and (GREEN .. "Debt settled!|r") or (GOLD .. p.head .. "|r"))
  f.line1:SetText(p.closed and p.head or p.sub)
  f.line2:SetText(p.gains)
  f:Hide(); f:Show()
  if C.PlayCue then C.PlayCue(p.closed and "settled" or "paid") end
end
C.On("PLAYER_REGEN_ENABLED", function()
  local q = waiting; waiting = {}
  if q[1] then
    local p = q[#q]
    if #q > 1 then p.sub = p.sub .. GREY .. " (" .. #q .. " payments)|r" end
    show(p)
  end
end)

-- r = the confirmed settle record; myXP / theirXP = what each side earned
function T.Payment(r, myXP, theirXP, myRep, theirRep)
  if not r then return end
  local who = C.Books and C.Books.Name and C.Books.Name(r.who) or r.who
  local paid = (r.paidOff or 0) >= 1
  local amt = paid and r.paidOff or (r.cameIn or 0)
  if amt < 1 then return end -- not against a debt: no fanfare
  local still = 0
  for _, d in ipairs(C.Debts and C.Debts() or {}) do
    if (d.who or ""):match("^[^%-]+") == (r.who or ""):match("^[^%-]+") then still = still + d.amt end
  end
  local closed = still < 1
  local function part(xp, rp)
    local s = string.format("%s+%d XP|r", GREEN, xp or 0)
    if (rp or 0) > 0 then s = s .. string.format(" %s+%d rep|r", "|cff4fc3f7", rp) end
    return s
  end
  local gains = string.format("You %s  %s·|r  %s %s", part(myXP, myRep), GREY, who, part(theirXP, theirRep))
  if (myRep or 0) > 0 and C.Rep and C.Rep.Mine then
    local ok, m = pcall(C.Rep.Mine)
    if ok and m then gains = gains .. string.format("\n%sYour standing: %d%s  %s|r", GREY, m.rep or 0, m.standingNext and (" / " .. m.standingNext) or "", m.standing or "") end
  end
  local head = paid and ("You paid " .. who .. " " .. C.Money(amt)) or (who .. " paid you " .. C.Money(amt))
  if (myXP or 0) + (theirXP or 0) < 1 and not closed then
    C.Print(head .. GREY .. " (a small part payment: no XP)|r")
    return
  end
  local key = (r.who or ""):match("^[^%-]+") or "?"
  local now = GetTime and GetTime() or 0
  local l = last[key]
  if l and now - l.t < 300 and not closed then
    l.n = l.n + 1; l.amt = l.amt + amt; l.t = now
    C.Print(string.format("%s %s(%d payments, %s in all)|r", head, GREY, l.n, C.Money(l.amt)))
    return
  end
  last[key] = { t = now, n = 1, amt = amt }
  show({ head = head, sub = C.Money(amt) .. (still >= 1 and (GREY .. "  ·  " .. C.Money(math.floor(still)) .. " still open|r") or ""), gains = gains, closed = closed })
end

-- 1.2.9: Kina level-up: a toast and the level-up sound (checked now and then; cheap enough)
do
  local function check()
    if not (C.Rep and C.Rep.Mine and C.settings) then return end
    local ok, m = pcall(C.Rep.Mine)
    if not ok or not m then return end
    local lv = m.level or 1
    local was = tonumber(C.settings.lastKinaLv)
    C.settings.lastKinaLv = lv
    if was and lv > was then
      show({ head = "Kina level " .. (C.Rep.Roman and C.Rep.Roman(lv) or lv) .. "!", sub = GREY .. "keep paying fast and farming together|r", gains = GREEN .. m.xp .. " XP|r" })
      if C.PlayCue then C.PlayCue("level") end
    end
    -- 1.3.0: a new standing title
    local stWas = C.settings.lastStanding
    C.settings.lastStanding = m.standing
    if stWas and m.standing and stWas ~= m.standing and (m.rep or 0) > 0 then
      local up = false
      for i, x in ipairs(C.Rep.STANDING) do if x[2] == m.standing then for j = 1, i - 1 do if C.Rep.STANDING[j][2] == stWas then up = true end end end end
      if up then
        show({ head = "Standing: " .. m.standing .. "!", sub = GREY .. "people can see you settle your debts|r", gains = "|cff4fc3f7" .. m.rep .. " rep|r" })
        if C.PlayCue then C.PlayCue("standing") end
      end
    end
    -- 1.3.0: debts you owe: a warning 15 minutes before the due time, and a lapse after it
    T.CheckDue()
  end
  T.CheckLevel = check
  local warned = {}
  function T.CheckDue()
    if not (C.Debts and C.DebtDue) then return end
    for _, d in ipairs(C.Debts()) do
      if d.dir == "owe" and d.amt >= 1 and d.s and not d.topup then
        local due = C.DebtDue(d)
        local sp = d.s.split or {}
        local key = tostring(d.s.start or 0) .. (d.key or "")
        if due and C.Now() > due and sp.offered and sp.offered[d.key] then
          sp.lapsed = sp.lapsed or {}
          if not sp.lapsed[d.key] then
            sp.lapsed[d.key] = true
            if C.Log then C.Log("offered", d.who, math.floor(d.amt), (d.s.sync and d.s.sync.sid) or ("t" .. tostring(d.s.start or 0))) end
            C.Print(string.format("%s's debt time ran out after you offered the full %s: no standing lost.", C.Books and C.Books.Name(d.who) or d.who, C.Money(math.floor(d.amt))))
          end
        elseif due and C.Now() > due then
          sp.lapsed = sp.lapsed or {}
          if not sp.lapsed[d.key] then
            sp.lapsed[d.key] = true
            if C.Log then C.Log("lapsed", d.who, math.floor(d.amt), (d.s.sync and d.s.sync.sid) or ("t" .. tostring(d.s.start or 0))) end
            show({ head = "Debt lapsed: " .. (C.Books and C.Books.Name(d.who) or d.who), sub = C.Money(math.floor(d.amt)) .. GREY .. " (" .. (d.farm or "farm") .. ") was not paid in time|r", gains = "|cffff4040" .. C.Rep.LAPSE_REP .. " rep|r" .. GREY .. "  (paying it still earns XP and rep back)|r" })
            if C.PlayCue then C.PlayCue("warning") end
          end
        elseif due and due - C.Now() < 900 and not warned[key] then
          warned[key] = true
          C.Print(string.format("|cffff8040%s to %s is due in %d min.|r Pay now (widget Pay button) or ask for more time.", C.Money(math.floor(d.amt)), C.Books and C.Books.Name(d.who) or d.who, math.max(1, math.floor((due - C.Now()) / 60))))
          if C.PlayCue then C.PlayCue("warning") end
        end
      elseif d.dir == "owed" and d.amt >= 1 and d.s and not d.topup then
        -- the creditor's side: time ran out on a debt whose full payment I turned down
        local due = C.DebtDue(d)
        local sp = d.s.split or {}
        if due and C.Now() > due and sp.refusedSeen and sp.refusedSeen[d.key] then
          sp.lapsed = sp.lapsed or {}
          if not sp.lapsed[d.key] then
            sp.lapsed[d.key] = true
            if C.Log then C.Log("refused", d.who, math.floor(d.amt), (d.s.sync and d.s.sync.sid) or ("t" .. tostring(d.s.start or 0))) end
            show({ head = "Payment refused: " .. (C.Books and C.Books.Name(d.who) or d.who), sub = GREY .. "they offered the full amount and the time ran out|r", gains = "|cffff4040standing lost|r" })
            if C.PlayCue then C.PlayCue("warning") end
          end
        end
      end
    end
  end
  local t = 0
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function(_, el) t = t + el; if t >= 30 then t = 0; if not (InCombatLockdown and InCombatLockdown()) then check() end end end)
end

-- 1.2.9: the group ad. During a shared farm the farm leader's Kina posts one line to
-- party/raid chat every 15 minutes (never Say or channels; never in combat; not in the
-- farm's first 15 minutes or while it earns nothing). Setting: Settings > "Post farm
-- stats to group chat" (on unless turned off).
do
  local nextAt
  local function post()
    if C.settings.groupAd == false or not SendChatMessage then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local s = C.session
    if not (s and s.sync and C.FarmView) then nextAt = nil; return end
    local v, group, leader = C.FarmView()
    if not (v and group) then return end
    local me = UnitName and UnitName("player")
    if not leader or (leader:match("^[^%-]+") ~= me) then return end
    local secs = math.max(1, v.secs or 0)
    if secs < 900 or (v.net or 0) < 1 then return end
    local n = 0; for _ in pairs(v.members or {}) do n = n + 1 end
    local gph = v.net * 3600 / secs
    local function plain(c)
      c = math.floor(c); local g, sv = math.floor(c / 10000), math.floor((c % 10000) / 100)
      return (g > 0 and (g .. "g ") or "") .. sv .. "s"
    end
    local where = (GetInstanceInfo and select(2, IsInInstance()) ~= "none" and GetInstanceInfo()) or (GetRealZoneText and GetRealZoneText()) or ""
    local msg = string.format("Kina Addon - %d %s - %s per hour - %d XP/h - %s", n, n == 1 and "user" or "users", plain(gph), math.min(60, math.floor(secs / 60 * 3600 / secs)), where)
    local chan = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    pcall(SendChatMessage, msg, chan)
  end
  local f = CreateFrame("Frame")
  local t = 0
  f:SetScript("OnUpdate", function(_, el)
    t = t + el; if t < 5 then return end; t = 0
    local now = GetTime and GetTime() or 0
    if not (C.session and C.session.sync) then nextAt = nil; return end
    if not nextAt then nextAt = now + 900; return end
    if now >= nextAt then nextAt = now + 900; post() end
  end)
end

-- 1.3.1 (Taylor, Nov 6): the disenchant call on item tooltips. Kina ranks vendor, safe AH
-- and the average disenchant result; disenchant needs a 10% edge, +5% while Forever's
-- odds aren't confirmed, +5% when a bad roll is really bad (worst likely result under
-- half the alternative), never more than 20%. All three numbers are always shown.
do
  local added = setmetatable({}, { __mode = "k" })
  local function line(tip)
    if tip ~= GameTooltip or added[tip] or (InCombatLockdown and InCombatLockdown()) then return end
    if C.settings and C.settings.deTip == false then return end
    if not (tip.GetItem and C.DEValue and C.BestRoute) then return end
    local _, link = tip:GetItem()
    if not link or (issecretvalue and issecretvalue(link)) then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local dv = C.DEValue(id)
    if not dv or dv.ev < 1 then return end
    added[tip] = true
    local _, _, det = C.BestRoute(id, 1)
    local vend = (C.VendorPrice and C.VendorPrice(id)) or 0
    local ah = det and det.ah or 0
    local alt = math.max(vend, ah)
    local worst
    local top
    for _, o in ipairs(dv.outcomes or {}) do if not top or o.p > top.p then top = o end end
    if top then worst = 0; for mat, qty in pairs(top.mats) do worst = worst + (C.MatExit(mat) or 0) * ((top.lo or qty)) end end
    local edge = 0.10 + 0.05 -- odds not yet confirmed on Forever
    if worst and alt > 0 and worst < alt * 0.5 then edge = edge + 0.05 end
    edge = math.min(edge, 0.20)
    local pct = alt > 0 and math.floor((dv.ev / alt - 1) * 100) or 100
    local call
    if dv.ev >= alt * (1 + edge) then call = "|cff7CFC00disenchant|r"
    elseif ah > vend then call = "|cffb083ffauction house|r" else call = "|cff8ecfffvendor|r" end
    tip:AddLine(string.format("Kina: vendor %s · AH %s · DE %s avg (%s%d%%) -> %s", C.Money(vend), ah > 0 and C.Money(ah) or "-", C.Money(dv.ev), pct >= 0 and "+" or "", pct, call), 0.85, 0.85, 0.85)
    tip:Show()
  end
  local function safe(tip) pcall(line, tip) end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safe)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", safe)
  end
  if GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript("OnTooltipCleared", function(self) added[self] = nil end) end
end

-- 1.4.1 (Taylor's idea, Nov 6): the Kina theme, once, when you open the Ledger within
-- 10 minutes of a farm ending. Off by default (Settings > "Play the Kina theme after a
-- farm"); it plays on the Music channel and stops when the window closes.
do
  local handle, playedFor
  function T.ThemeOnLedger()
    if not (C.settings and C.settings.themeMusic == true and PlaySoundFile) then return end
    local last = C.db and C.db.sessions and C.db.sessions[1]
    if not (last and last.stop and C.Now() - last.stop < 600) or playedFor == last.stop then return end
    playedFor = last.stop
    local ok, will, h = pcall(PlaySoundFile, "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\kina_theme.ogg", "Music")
    if ok and will then handle = h end
  end
  function T.ThemeStop() if handle and StopSound then pcall(StopSound, handle, 1500) end; handle = nil end
end
