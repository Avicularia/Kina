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
  if C.settings and C.settings.farmSound ~= false and PlaySoundFile then
    pcall(PlaySoundFile, "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\" .. (p.closed and "ksc-city-cheers.ogg" or "ksc-gates-open.ogg"), "Master")
  end
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
