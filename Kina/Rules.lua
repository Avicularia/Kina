local _, C = ...
-- 1.5.4 (Taylor, Nov 7): the standing rules made visible. The numbers live in Rep.lua
-- (worked out from the log); this file shows the windows that explain them, writes the
-- "jail" (one-time pardon), "decay" (idle weeks) and "frozen" (out of date) log lines,
-- and draws the Blacklisted / out-of-date covers.
local U = {}
C.Rules = U
local DAY, WEEK = 86400, 7 * 86400
local RED, GREY, GOLD = "|cffff4030", "|cff9d9d9d", "|cffffd100"

------------------------------------------------------------------ the rules window
local win
local function window()
  if win then return win end
  win = CreateFrame("Frame", "KinaRules", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(460, 330); win:SetPoint("CENTER", 0, 80); win:SetFrameStrata("FULLSCREEN_DIALOG"); win:SetToplevel(true)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    win:SetBackdropColor(0.06, 0.05, 0.04, 0.97); win:SetBackdropBorderColor(0.7, 0.2, 0.15, 1)
  end
  win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); win.title:SetPoint("TOP", 0, -16)
  if C.Cos then C.Cos.Font(win.title, 20, "OUTLINE") end
  win.body = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); win.body:SetPoint("TOPLEFT", 22, -52); win.body:SetPoint("RIGHT", win, "RIGHT", -22, 0)
  win.body:SetJustifyH("LEFT"); win.body:SetJustifyV("TOP"); if win.body.SetSpacing then win.body:SetSpacing(3) end
  win.ok = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(win.ok) end; win.ok:SetSize(200, 26); win.ok:SetPoint("BOTTOM", 0, 16)
  win.no = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(win.no) end; win.no:SetSize(120, 26)
  return win
end
-- (no Escape: these are read and answered)
function U.Show(title, body, okText, onOk, noText, onNo)
  local w = window()
  w.title:SetText(title); w.body:SetText(body)
  w.ok:SetText(okText or "I understand"); w.ok:SetScript("OnClick", function() w:Hide(); if onOk then onOk() end end)
  if noText then
    w.ok:ClearAllPoints(); w.ok:SetPoint("BOTTOMRIGHT", w, "BOTTOM", -6, 16)
    w.no:ClearAllPoints(); w.no:SetPoint("BOTTOMLEFT", w, "BOTTOM", 6, 16); w.no:SetText(noText)
    w.no:SetScript("OnClick", function() w:Hide(); if onNo then onNo() end end); w.no:Show()
  else w.ok:ClearAllPoints(); w.ok:SetPoint("BOTTOM", 0, 16); w.no:Hide() end
  local h = (w.body:GetStringHeight() or 200) + 120
  w:SetHeight(math.max(240, h)); w:Show()
end

local TEXT = {
  jail = "Your standing has fallen below zero: you are now %s.\n\n"
    .. "This happens when debts go unpaid or your farm partners give you thumbs down.\n\n"
    .. GOLD .. "One time only, Kina offers you a clean slate:|r your standing goes back to 1, and every gain counts "
    .. "3x until you're back to your best ever (%d).\n\n"
    .. "Accept only if you agree to pay your debts and be a good partner. " .. RED .. "There is never a second pardon.|r "
    .. "If you fall again, gains are halved until you're positive.",
  fall = "Your standing has fallen below zero: you are now %s.\n\n"
    .. "- While below zero, " .. RED .. "every XP and standing gain is halved|r.\n"
    .. "- Back at zero or above, gains count " .. GOLD .. "3x|r until you reach your best ever (%d).\n"
    .. "- Penalties always count in full.\n"
    .. "- At -1000 you are " .. RED .. "Blacklisted|r: gains count 1/4 until you're positive, and your profile keeps a permanent mark.\n\n"
    .. "Pay what you owe and play fair to climb back.",
  black = RED .. "You are Blacklisted.|r\n\n"
    .. "Your standing reached -1000. Until it is positive again:\n"
    .. "- every XP and standing gain counts " .. RED .. "1/4|r\n"
    .. "- your portrait is crossed out for everyone who sees your Kina profile\n\n"
    .. "When you climb back above zero the cross goes, but your profile will always show that you were once Blacklisted.",
  warn5 = "You have received " .. RED .. "5 thumbs down|r in the last 48 hours.\n\n"
    .. "If you reach 10 in 48 hours, or 15 in 7 days, your standing drops straight to -99 (Delinquent), whatever it is now.\n\n"
    .. "Each thumbs down counts toward this for exactly 7 days from when you got it.",
  warn10 = "You have received " .. RED .. "10 thumbs down|r in the last 7 days.\n\n"
    .. "At 15 in 7 days (or 10 in 48 hours), your standing drops straight to -99 (Delinquent), whatever it is now.\n\n"
    .. "Each thumbs down counts toward this for exactly 7 days from when you got it.",
}

------------------------------------------------------------------ watching the numbers
local seen = {}
function U.Check()
  if not (C.Rep and C.Rep.Mine and C.settings) then return end
  local ok, m = pcall(C.Rep.Mine)
  if not ok or not m or not m.ok then return end
  local st = C.settings
  -- fell below zero (or the thumbs-down breakpoint did it)
  if (m.fell or 0) > (st.rulesFell or 0) then
    st.rulesFell = m.fell
    if m.rep < 0 then
      local nm = (C.Cos and C.Cos.StandingColor(m.standing) or "") .. m.standing .. "|r"
      if not m.jailUsed and (m.fell or 0) == 1 then
        U.Show("A second chance", string.format(TEXT.jail, nm, m.best or 0), "I agree: pay my debts, play fair",
          function() if C.Log then C.Log("jail", "accept") end; if C.Refresh then pcall(C.Refresh) end end, "Not now")
      else
        U.Show("Dishonored", string.format(TEXT.fall, nm, m.best or 0), "I understand")
      end
    end
  end
  if m.black and not st.rulesBlack then st.rulesBlack = true; U.Show("Blacklisted", TEXT.black, "I understand")
  elseif not m.black then st.rulesBlack = nil end
  -- thumbs-down warnings (positive standing only, where the breakpoint applies)
  if m.rep > 0 then
    if (m.bad48 or 0) >= 5 and (seen.b48 or 0) < 5 and not st.rulesWarn5 then st.rulesWarn5 = C.Now(); U.Show("Warning", TEXT.warn5) end
    if (m.bad7 or 0) >= 10 and (seen.b7 or 0) < 10 and not st.rulesWarn10 then st.rulesWarn10 = C.Now(); U.Show("Final warning", TEXT.warn10) end
  end
  if st.rulesWarn5 and C.Now() - st.rulesWarn5 > 2 * DAY and (m.bad48 or 0) < 5 then st.rulesWarn5 = nil end
  if st.rulesWarn10 and C.Now() - st.rulesWarn10 > WEEK and (m.bad7 or 0) < 10 then st.rulesWarn10 = nil end
  seen.b48, seen.b7 = m.bad48, m.bad7
end
-- a jail card the player put off ("Not now") is still there: /kina pardon
function U.OfferPardon()
  local ok, m = pcall(C.Rep.Mine)
  if ok and m and m.rep < 0 and not m.jailUsed then
    C.settings.rulesFell = (m.fell or 1) - 1; U.Check()
  else C.Print("no pardon available.") end
end

------------------------------------------------------------------ idle weeks
-- worked out the next time Kina is used (window opened, farm started) after 7+ days
-- with no farm on any character
function U.Decay()
  if not (C.Rep and C.Rep.Mine and C.Log and C.settings) then return end
  local ok, m = pcall(C.Rep.Mine)
  if not ok or not m or not m.ok or m.frozen or not m.lastFarmT then return end
  local st = C.settings
  if st.decayFrom ~= m.lastFarmT then st.decayFrom, st.decayWeeks = m.lastFarmT, 0 end
  local weeks = math.floor((C.Now() - m.lastFarmT) / WEEK)
  local new = weeks - (st.decayWeeks or 0)
  if new <= 0 then return end
  st.decayWeeks = weeks
  local amt = 0
  if m.rep > 0 then amt = -100 * new
  elseif m.rep < -20 then amt = (m.black and 25 or 50) * new end
  if amt ~= 0 then C.Log("decay", amt) end
end

------------------------------------------------------------------ out of date
-- someone's Kina told mine it is a newer version: no XP or standing can be gained or
-- lost here until I update (a /reload checks again). Never during a farm.
function U.Outdated() return (C.Share and C.Share.newestBuild and C.Share.newestBuild > (C.BUILD or 0)) or false end
function U.FreezeCheck()
  if not (C.Rep and C.Log) then return end
  local ok, m = pcall(C.Rep.Mine)
  if not ok or not m then return end
  local out = U.Outdated()
  if out and not m.frozen and not C.session then
    C.Log("frozen", "on")
    C.Print(RED .. "A newer Kina (" .. tostring(C.Share.newestVer or "?") .. ") is out: update Kina to keep earning XP and standing.|r")
    if C.Refresh then pcall(C.Refresh) end
  elseif not out and m.frozen then
    C.Log("frozen", "off")
  end
end

------------------------------------------------------------------ covers
-- Blacklisted: a dark square with a blood-red X over the portrait.
-- Out of date: the same over the whole profile, with the reason in big red letters.
local covers = setmetatable({}, { __mode = "k" })
function U.Cover(parent, on, text)
  local c = covers[parent]
  if not on then if c then c:Hide() end; return end
  if not c then
    c = CreateFrame("Frame", nil, parent); c:SetAllPoints(parent); c:SetFrameLevel(parent:GetFrameLevel() + 50)
    local bg = c:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.03, 0.02, 0.02, 0.82)
    c.x = c:CreateTexture(nil, "ARTWORK"); c.x:SetPoint("CENTER"); c.x:SetTexture(C.Cos and C.Cos.Tex("blood_x") or nil)
    c.t = c:CreateFontString(nil, "OVERLAY"); c.t:SetPoint("CENTER"); c.t:SetWidth(400)
    if C.Cos then C.Cos.Font(c.t, 22, "OUTLINE") end
    c.t:SetTextColor(1, 0.15, 0.1)
    covers[parent] = c
  end
  local s = math.min(parent:GetWidth() or 100, parent:GetHeight() or 100)
  c.x:SetSize(s * 0.95, s * 0.95)
  c.t:SetText(text or ""); c.t:SetWidth(math.max(120, (parent:GetWidth() or 400) - 40))
  c:Show()
end

------------------------------------------------------------------ when
C.On("PLAYER_LOGIN", function()
  if C.After then
    C.After(8, function() pcall(U.FreezeCheck); pcall(U.Check) end)
  end
  local f = CreateFrame("Frame"); local acc = 0
  f:SetScript("OnUpdate", function(_, el)
    acc = acc + el; if acc < 15 then return end; acc = 0
    if InCombatLockdown and InCombatLockdown() then return end
    pcall(U.FreezeCheck); pcall(U.Check)
  end)
end)
