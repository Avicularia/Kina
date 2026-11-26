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
  { ver = "1.0.6", pages = {
    { "Hot mobs for everyone", "Hot mobs now show for every Kina user: a grey logo on their nameplates. Kill one 30 times and it lights up for you, with what it pays you per kill. Mobs that come off the hot list wait in Hot Farms > Archive with what they gave you.", tab = "Hot Farms" },
    { "Talk to the developer", "When the developer is online, their badge shows beside the Kina nameplate. Click it to send a bug, idea or request; you get a notice when they answer. If they're offline, it waits and sends when they're back." },
    { "Play Kina with a controller", "With gamepad mode on, Kina's windows work with the controller: D-pad moves, A presses, B goes back, X shows info, Y is right-click, LB / RB change tabs. Kina only takes the controller while its window is open and you're out of combat.", help = "Controller" },
    { "Key bindings", "Options > Key Bindings > Kina: open Kina, Start / stop farm, Scan the AH, Hot Farms and a waypoint to the nearest hot mob. Settings also has Window size buttons, so there's no corner to drag." },
  } },
  { ver = "1.0.7", pages = {
    { "AH prices from every Kina", "Kina now shares AH prices with every Kina user on the realm, not just your group or guild. A price only counts when several Kinas agree, so one bad scan can't move it. Turn it off in Settings." },
    { "Group farms ask first", "Nobody is put in a farm without clicking Join. Start shows everyone's answer: a green check, a red X or a yellow question mark. Said no? You can't start your own farm until the group's ends. Anyone in the farm can end it for everyone." },
    { "Feedback, front and center", "A Feedback button now sits on the bottom bar of every tab, and the Kina button pulses green when an answer is waiting." },
    { "Updates and scans", "When a newer Kina is out, the widget shows Update available. The scan bar now says whose AH scan is coming in, how far along it is and about how long is left." },
  } },
  { ver = "1.0.8", pages = {
    { "Dungeon farms fixed", "Walking into a dungeon mid-farm now ends the old farm properly (split, commendations) before the new one starts, and your partners get into the new one." },
    { "See the Kina network", "Settings > Network log (or /kina net) shows what Kina sends and receives, who it's talking to and which AH scans came in." },
  } },
  { ver = "1.0.9", pages = {
    { "The Kina network works", "AH scans now reach every Kina on the realm, on every layer, including people who log in later. Your scan plus one other Kina is enough for a shared price. See it live: /kina net." },
    { "No more debts", "Splits now just show each player's fair share of what the group looted. Nobody owes anybody, and there's nothing to pay or chase." },
  } },
  { ver = "2.0.0", pages = {
    { "Kina 2.0: Renown", "Farm with other Kinas to earn Renown: ten ranks from the Wanderer to the Everlasting, each a title in its quality color. Everyone in the farm gets credit for the whole group's loot." },
    { "Bonuses that stack", "Party, daily streak, campfire (Camp Benefits), your season track levels and +10% for every commendation all add up. Solo farms and quest gold don't count." },
    { "Your gold plate", "Your profile shows gold farmed under your portrait. Click it to switch to gold per hour." },
    { "Net worth", "Your You page shows your account's net worth: every character's gold plus the items in their bags and bank that aren't soulbound, at today's prices. Log in on each character (and open its bank once) to count it." },
    { "Commendations pay", "Each commendation adds 10% of that farm's Renown, and its toast shows how much. One that arrives before Kina has scored the farm waits for it." },
    { "Hot Farms, live", "The hot list now rebuilds from live prices near your level: a drop on a price streak (selling 1.5x its usual) makes a mob HOT. Gold per kill always shows, and a mob's page explains why: worth per kill, per hour at your pace, levelling fit, the market, and how sure Kina is. The logo and cards still light up with your own kills." },
    { "Gathering", "Hot Farms > Gathering lists every node your Mining or Herbalism can gather, each material per gather (Iron Ore: 300% = 3 a node) and what a gather is worth, with HOT when a material's price spikes." },
    { "Missed farms paid", "Farms from the 2.0 betas that never paid their Renown are scored again once, and paid." },
    { "Prices, anywhere", "The Prices button (bottom bar) or /kina prices opens an auction house browser that works away from the AH: search, level and rarity filters, categories, sortable columns, and each item's cheapest listings, from your last scan and other Kinas'. Research only." },
    { "Two big boxes", "The widget now shows Net looted (everything you gained: loot, coin and quests) and XP / hour in two big boxes, so it stays readable scaled right down (drag its corner; it now goes to 40%)." },
    { "A smaller widget", "The - button by the widget's X shrinks it to the rate, timer and four boxes (right-click it for Start, Pause, Log, Kina). The party portraits can be hidden or resized." },
    { "A stronger network", "When the Kina channel is too busy to let you in, Kina moves to a backup channel, and relays pass news between the channels, so every Kina still hears every other. /kina net shows which channel you're on." },
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
  f:SetSize(440, 230); f:SetFrameStrata("FULLSCREEN_DIALOG"); if f.SetToplevel then f:SetToplevel(true) end; f:SetFrameLevel(120); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
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
