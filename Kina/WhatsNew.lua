-- Kina: "What's new" (1.0.5, Taylor). After an update that changes something big or adds a
-- major feature, a short tour of what's new shows once: after 5 minutes of play, or the
-- first time you press Start farm, whichever comes first. Never in combat. A brand-new
-- install gets the full tour instead (Tour.lua), not this.
-- To add one: put the version in MAJOR with its pages. Small builds get no entry.
local _, C = ...
local W = {}
C.WhatsNew = W
W.AFTER = 300 -- seconds of play

local GOLD, GREY = "|cffffc54a", "|cff9d9d9d"
W.MAJOR = {
  { ver = "1.0.5", pages = {
    { "Hot Farms", "A new tab on the far left: the mobs worth far more per kill than anything else at their level. They burn on their nameplates (grey until Kina users have 30 kills of them). Click one for where it spawns and a waypoint to the thickest spot.", tab = "Hot Farms" },
    { "Hot mobs while you quest", "Following a guide? When a hot mob is close, a small line under your quest tracker says what it pays per kill, how far and which way, next to what your own last kills were worth. Click it for a waypoint. Never in combat, dungeons or cities; turn it off in Settings." },
    { "Disputes that arrive", "Pressing Dispute now pops a Confirm / Decline box on the other player's Kina. If they're offline, guildmates' Kina carry it to them, and anything still waiting shows at your mailbox." },
    { "Records and high scores", "Profiles show a player's record (standing changes, bad votes, debts that ran out) and their Kina high score, their best gold per hour farm. Click either one. Both players need Kina 1.0.5." },
    { "Season 1 Cosmetics", "Help > Season 1 Cosmetics: every ring, star and crest you can earn this season, what each takes, and how close you are. Each progress bar has Details with the exact rules.", help = "Season 1 Cosmetics" },
    { "A window that fits", "Make the Kina window bigger and its pages grow with it; smaller and they shrink to fit. Scrollbars can be dragged again." },
  } },
}

local function verNum(v) local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)"); return a and (tonumber(a) * 10000 + tonumber(b) * 100 + (tonumber(c) or 0)) or 0 end
-- the newest major update you haven't seen, or nil
function W.Pending()
  local st = C.settings
  if not st then return nil end
  local seen = verNum(st.whatsNewSeen)
  local cur = verNum(C.version)
  local best
  for _, m in ipairs(W.MAJOR) do
    local v = verNum(m.ver)
    if v > seen and v <= cur and (not best or v > verNum(best.ver)) then best = m end
  end
  return best
end
local function markSeen() if C.settings then C.settings.whatsNewSeen = C.version end end

------------------------------------------------------------------ the window
local f, page, cur
local function draw()
  local p = cur and cur.pages[page]
  if not p then return end
  f.title:SetText(GOLD .. p[1] .. "|r")
  f.body:SetText(p[2])
  f.count:SetText(GREY .. page .. " / " .. #cur.pages .. "|r")
  f.back:SetShown(page > 1)
  f.next:SetText(page < #cur.pages and "Next" or "Done")
  f.show:SetShown(p.tab ~= nil or p.help ~= nil)
end
local function build()
  if f then return f end
  f = CreateFrame("Frame", "KinaWhatsNew", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(440, 230); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
  f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if C.Skin and C.Skin.Panel then C.Skin.Panel(f) elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.07, 0.055, 0.04, 0.97); f:SetBackdropBorderColor(0.6, 0.45, 0.2)
  end
  local logo = f:CreateTexture(nil, "ARTWORK"); logo:SetSize(34, 34); logo:SetPoint("TOPLEFT", 16, -14)
  logo:SetTexture("Interface\\AddOns\\Kina\\Media\\KinaLogo")
  f.head = C.Text(f, "OVERLAY", "GameFontNormal"); f.head:SetPoint("LEFT", logo, "RIGHT", 10, 8)
  f.title = C.Text(f, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
  if C.Cos and C.Cos.Font then C.Cos.Font(f.title, 20, "") end
  f.body = C.Text(f, "OVERLAY", "GameFontHighlight"); f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8); f.body:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  f.body:SetJustifyH("LEFT"); if f.body.SetWordWrap then f.body:SetWordWrap(true) end
  f.count = C.Text(f, "OVERLAY", "GameFontHighlightSmall"); f.count:SetPoint("BOTTOMLEFT", 18, 18)
  local function btn(label, w)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); if C.Skin and C.Skin.Button then C.Skin.Button(b) end
    b:SetSize(w, 22); b:SetText(label); return b
  end
  f.next = btn("Next", 80); f.next:SetPoint("BOTTOMRIGHT", -16, 14)
  f.back = btn("Back", 70); f.back:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
  f.show = btn("Show me", 90); f.show:SetPoint("RIGHT", f.back, "LEFT", -6, 0)
  f.next:SetScript("OnClick", function() if cur and page < #cur.pages then page = page + 1; draw() else f:Hide() end end)
  f.back:SetScript("OnClick", function() if page > 1 then page = page - 1; draw() end end)
  f.show:SetScript("OnClick", function()
    local p = cur and cur.pages[page]
    if not p then return end
    if p.tab and C.Toggle then C.Toggle(p.tab)
    elseif p.help and C.Toggle then
      C.Toggle("Help")
      if C.ShowHelpTopic then pcall(C.ShowHelpTopic, p.help) end
    end
  end)
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)
  tinsert(UISpecialFrames, "KinaWhatsNew")
  f:Hide()
  return f
end

function W.Show(m)
  m = m or W.Pending() or W.MAJOR[#W.MAJOR]
  if not m then return false end
  if InCombatLockdown and InCombatLockdown() then W.waiting = true; return false end
  build()
  cur, page = m, 1
  f.head:SetText(GOLD .. "What's new in Kina " .. m.ver .. "|r")
  draw()
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  f:Show(); f:Raise()
  markSeen()
  return true
end

------------------------------------------------------------------ when
local played, armed = 0, false
local function trigger()
  if not armed then return end
  local m = W.Pending()
  if not m then armed = false; return end
  if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then W.waiting = true; return end
  armed = false
  W.Show(m)
end
W.Trigger = trigger
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(_, el)
  if not armed then return end
  played = played + el
  if played >= W.AFTER then pcall(trigger) end
end)
C.On("PLAYER_LOGIN", function()
  local st = C.settings
  if not st then return end
  -- a brand-new install sees the full tour, not "what's new"
  if not st.tourSeen and not st.whatsNewSeen and not (C.db and C.db.sessions and #C.db.sessions > 0) then markSeen(); return end
  armed = W.Pending() ~= nil
end)
C.On("PLAYER_REGEN_ENABLED", function() if W.waiting then W.waiting = nil; if C.After then C.After(2, function() if armed then trigger() end end) end end end)
-- the first Start farm after the update
do
  local start = C.StartSession
  if type(start) == "function" then
    C.StartSession = function(...)
      local a, b, c = start(...)
      if armed and C.After then C.After(3, function() pcall(trigger) end) end
      return a, b, c
    end
  end
end
