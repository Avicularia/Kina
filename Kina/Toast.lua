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
  f:SetSize(360, 86); f:SetPoint("TOP", UIParent, "TOP", 0, -140); f:SetFrameStrata("HIGH")
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
function T.Payment(r, myXP, theirXP)
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
  local gains = string.format("You %s+%d XP|r  %s·|r  %s %s+%d XP|r", GREEN, myXP or 0, GREY, who, GREEN, theirXP or 0)
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
  end
  T.CheckLevel = check
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
