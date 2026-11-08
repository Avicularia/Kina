local _, C = ...
-- 1.5.1 (Taylor): see someone else's Kina profile. A card with their portrait in their
-- standing ring, Kina level, standing (unverified: it's what their Kina told mine),
-- class and level, professions, and what's between the two of you (farms together, open
-- debts, vouches). Open it from Kina > You > "Party profiles", the commendation window, or
-- /kina profile [Name] (your target when no name).
local P = {}
C.Profile = P
local GREY, ORANGE, GREEN, GOLD = "|cff9d9d9d", "|cffff9933", "|cff7CFC00", "|cffffd100"
local function first(n) return n and (tostring(n):match("^([^%-]+)") or tostring(n)) or "" end
local function lower(n) return first(n):lower() end
local function safe(v) return not (issecretvalue and issecretvalue(v)) end

local function unitFor(name)
  local k = lower(name)
  local function is(u)
    if not (UnitExists and UnitExists(u)) then return false end
    local ok, un = pcall(UnitName, u)
    return ok and un and safe(un) and lower(un) == k
  end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do if is(u) then return u end end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = raid and ("raid" .. i) or ("party" .. i)
    if is(u) then return u end
  end
end
P.UnitFor = unitFor
-- 1.5.4: the best picture we have of someone: their live portrait when they're near,
-- otherwise their class crest (the game can't save a portrait for later)
function P.SetPortrait(tex, name)
  local u = unitFor(name)
  if u and UnitIsVisible and UnitIsVisible(u) and SetPortraitTexture then
    tex:SetTexCoord(0, 1, 0, 1); if pcall(SetPortraitTexture, tex, u) then return end
  end
  local pr = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(name)
  P.ClassIcon(tex, pr and pr.char and pr.char.class)
end
-- 0.9.2: the class crest as its own icon file. (The old one cut a corner out of the
-- game's sheet of all class circles, and a round portrait mask ignores that cut: the
-- widget showed the whole sheet of tiny class icons.)
local CLASS_FILE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  DEATHKNIGHT = "DeathKnight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", MONK = "Monk", DRUID = "Druid",
  DEMONHUNTER = "DemonHunter", EVOKER = "Evoker" }
function P.ClassIcon(tex, cls)
  tex:SetTexCoord(0, 1, 0, 1)
  local f = cls and CLASS_FILE[cls]
  tex:SetTexture(f and ("Interface\\Icons\\ClassIcon_" .. f) or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- people worth listing: your group first (Kina or not), then recent farm partners
function P.People()
  local out, seen = {}, {}
  local me = lower(UnitName and UnitName("player"))
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = raid and ("raid" .. i) or ("party" .. i)
    local ok, un = pcall(UnitName, u)
    if ok and un and safe(un) and lower(un) ~= me and not (C.IsMyChar and C.IsMyChar(un)) and not seen[lower(un)] then
      seen[lower(un)] = true
      out[#out + 1] = { who = first(un), group = true, kina = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(un) ~= nil }
    end
  end
  local sess = C.db and C.db.sessions or {}
  for i = 1, math.min(#sess, 40) do
    local s = sess[i]
    for who in pairs(s and s.split and s.split.incomes or {}) do
      local k = lower(who)
      if k ~= me and not (C.IsMyChar and C.IsMyChar(who)) and not seen[k] then seen[k] = true; out[#out + 1] = { who = first(who), kina = true } end
    end
  end
  return out
end

-- what's between you and them, from your own records
local function between(who)
  local k = lower(who)
  local farms, secs = 0, 0
  for _, s in ipairs(C.db and C.db.sessions or {}) do
    if s.sync and s.split and s.split.incomes then
      for w in pairs(s.split.incomes) do
        if lower(w) == k then farms = farms + 1; secs = secs + math.max(0, (s.stop or C.Now()) - (s.start or C.Now()) - (s.pausedSecs or 0)) end
      end
    end
  end
  local owe, owed = 0, 0
  local ok, list = pcall(function() return C.Debts and C.Debts() or {} end)
  for _, d in ipairs(ok and list or {}) do
    if lower(d.who) == k then if d.dir == "owe" then owe = owe + d.amt else owed = owed + d.amt end end
  end
  local gave, got, gaveBad, gotBad = 0, 0, 0, 0
  local v = C.db and C.db.vouch
  local isBad = C.Vouch and C.Vouch.IsBad or function() return false end
  for _, g in ipairs(v and v.given or {}) do if lower(g.who) == k then if isBad(g.kind) then gaveBad = gaveBad + 1 else gave = gave + 1 end end end
  for _, g in ipairs(v and v.got or {}) do if lower(g.who) == k then if isBad(g.kind) then gotBad = gotBad + 1 else got = got + 1 end end end
  return { farms = farms, hours = secs / 3600, owe = owe, owed = owed, gave = gave, got = got, gaveBad = gaveBad, gotBad = gotBad }
end
P.Between = between

local card
local function row(parent, y)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l:SetPoint("TOPLEFT", 16, y)
  local r = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r:SetPoint("TOPRIGHT", -16, y); r:SetJustifyH("RIGHT")
  return l, r
end
local function build()
  card = CreateFrame("Frame", "KinaProfile", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  card:SetSize(320, 400); card:SetFrameStrata("FULLSCREEN_DIALOG"); card:SetToplevel(true) -- 1.5.3: above the Kina window
  card:SetClampedToScreen(true); card:EnableMouse(true); card:SetMovable(true)
  card:RegisterForDrag("LeftButton"); card:SetScript("OnDragStart", card.StartMoving); card:SetScript("OnDragStop", card.StopMovingOrSizing)
  if card.SetBackdrop then
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    card:SetBackdropColor(0.05, 0.04, 0.03, 0.96); card:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
  end
  local x = CreateFrame("Button", nil, card, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -2, -2)
  local o = { frame = card }
  o.box = CreateFrame("Frame", nil, card); o.box:SetSize(72, 72); o.box:SetPoint("TOPLEFT", 26, -30)
  o.portrait = o.box:CreateTexture(nil, "ARTWORK")
  o.cos = C.Cos and C.Cos.Portrait(o.box, o.portrait)
  o.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); o.name:SetPoint("TOPLEFT", 122, -30)
  if C.Cos then C.Cos.Font(o.name, 19, "OUTLINE") end
  o.line1 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); o.line1:SetPoint("TOPLEFT", o.name, "BOTTOMLEFT", 0, -5)
  o.line2 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); o.line2:SetPoint("TOPLEFT", o.line1, "BOTTOMLEFT", 0, -4)
  o.line3 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); o.line3:SetPoint("TOPLEFT", o.line2, "BOTTOMLEFT", 0, -4)
  o.line3:SetWidth(180); o.line3:SetJustifyH("LEFT")
  local h1 = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h1:SetPoint("TOPLEFT", 16, -132); h1:SetText("Professions")
  o.profs = {}
  for i = 1, 4 do
    local l, r = row(card, -152 - (i - 1) * 18); o.profs[i] = { l, r }
  end
  local h2 = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h2:SetPoint("TOPLEFT", 16, -232); h2:SetText("You and them")
  o.rows = {}
  for i = 1, 4 do local l, r = row(card, -252 - (i - 1) * 20); o.rows[i] = { l, r } end
  o.note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); o.note:SetPoint("BOTTOMLEFT", 16, 44); o.note:SetWidth(288); o.note:SetJustifyH("LEFT")
  -- 1.5.2: thumbs up (commend) and thumbs down (bad commendation, red)
  o.up = C.Vouch.ThumbButton(card, false, 100, 26, "Commend"); o.up:SetPoint("BOTTOMLEFT", 12, 12)
  o.down = C.Vouch.ThumbButton(card, true, 100, 26, "Disgraced"); o.down:SetPoint("LEFT", o.up, "RIGHT", 6, 0)
  o.whisper = CreateFrame("Button", nil, card, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(o.whisper) end; o.whisper:SetSize(82, 24); o.whisper:SetPoint("BOTTOMRIGHT", -12, 13)
  o.whisper:SetText("Whisper")
  if UISpecialFrames then table.insert(UISpecialFrames, "KinaProfile") end
  P.card = o
end

-- 1.5.4 (Taylor): a profile opens as the full You page (same layout as your own), in the
-- main window; P.ShowCard is the old small card (kept for when the window can't open)
function P.Show(name)
  name = first(name)
  name = name:sub(1, 1):upper() .. name:sub(2)
  if name == "" then C.Print("profile: /kina profile Name (or target someone)."); return end
  if C.UI and C.Toggle and not (C.IsMyChar and C.IsMyChar(name)) then
    C.UI.youWho = name; C.UI.youView = "you"
    local ok = pcall(C.Toggle, "You")
    if ok then return true end
  end
  return P.ShowCard(name)
end
function P.ShowCard(name)
  if not P.card then build() end
  local o = P.card
  local pr = C.Share and C.Share.ProfileOf and C.Share.ProfileOf(name)
  local u = unitFor(name)
  local ch = pr and pr.char
  -- portrait: the live one when they're near, else their class icon
  local set = false
  if u and SetPortraitTexture then set = pcall(SetPortraitTexture, o.portrait, u) end
  if not set then
    P.ClassIcon(o.portrait, ch and ch.class)
  else o.portrait:SetTexCoord(0, 1, 0, 1) end
  local stand = pr and pr.stand
  local sname = type(stand) == "number" and C.Rep and C.Rep.StandingOf(stand) or nil
  local klv = pr and pr.kinaLv
  if o.cos and C.Cos then
    C.Cos.UpdatePortrait(o.cos, sname or "Unproven", (klv and klv > 0) and klv or 1)
    if klv and klv > 0 then o.cos.plate:Show(); o.cos.num:Show() else o.cos.plate:Hide(); o.cos.num:Hide() end
  end
  o.name:SetText(name)
  local cls = ch and ch.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[ch.class] or (ch.class:sub(1, 1) .. ch.class:sub(2):lower()))
  local lvl = ch and ch.level
  if (not lvl or not cls) and u then
    local ok1, l = pcall(UnitLevel, u); if ok1 and safe(l) then lvl = lvl or l end
    local ok2, c = pcall(UnitClass, u); if ok2 and safe(c) then cls = cls or c end
  end
  o.line1:SetText((lvl and ("Level " .. lvl .. " ") or "") .. (cls or ""))
  if pr then
    o.line2:SetText(sname and ((C.Cos and C.Cos.StandingColor(sname) or "") .. sname .. "|r  " .. GREY .. stand .. " rep|r") or (GREY .. "standing not shared yet|r"))
    local ago = pr.seen and math.floor((C.Now() - pr.seen) / 60)
    o.line3:SetText(GOLD .. "Kina " .. ((klv == -1) and "|cffff8040log damaged|r" or (C.Rep.Roman((klv and klv > 0) and klv or 1))) .. "|r" .. GREY
      .. (pr.ver and ("   v" .. pr.ver) or "") .. (ago and (ago < 2 and "   seen just now" or (ago < 120 and ("   seen " .. ago .. " min ago") or ("   seen " .. math.floor(ago / 60) .. " h ago"))) or "") .. "|r")
  else
    o.line2:SetText(GREY .. "No Kina heard from them yet|r")
    o.line3:SetText(GREY .. "Their Kina says hello when you group up.|r")
  end
  -- professions
  local list = {}
  for pn, sk in pairs(ch and ch.profs or {}) do list[#list + 1] = { pn, sk } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = 1, 4 do
    local p = list[i]
    o.profs[i][1]:SetText(p and p[1] or (i == 1 and (GREY .. "none shared|r") or ""))
    o.profs[i][2]:SetText(p and (p[2] .. GREY .. " / 300|r") or "")
  end
  -- between you
  local b = between(name)
  local open = (b.owe >= 1 and (ORANGE .. "you owe " .. C.Money(math.floor(b.owe)) .. "|r"))
    or (b.owed >= 1 and (GOLD .. "they owe you " .. C.Money(math.floor(b.owed)) .. "|r")) or (GREEN .. "all settled|r")
  local rows = {
    { "Farms together", b.farms .. (b.hours > 0 and (GREY .. string.format("  (%.1f h)", b.hours) .. "|r") or "") },
    { "Open now", open },
    { "You commended them", tostring(b.gave) .. (b.gaveBad > 0 and ("  " .. C.Vouch.RED .. b.gaveBad .. " bad|r") or "") },
    { "They commended you", tostring(b.got) .. (b.gotBad > 0 and ("  " .. C.Vouch.RED .. b.gotBad .. " bad|r") or "") },
  }
  for i, r in ipairs(rows) do o.rows[i][1]:SetText(GREY .. r[1] .. "|r"); o.rows[i][2]:SetText(r[2]) end
  o.note:SetText(GREY .. "Standing and Kina level are what their Kina reports (unverified until the Kina server checks both logs).|r")
  -- buttons
  o.up:Hide(); o.down:Hide() -- (1.5.4: commending only happens in the end-of-farm window)
  o.whisper:SetScript("OnClick", function()
    if ChatFrame_SendTell then pcall(ChatFrame_SendTell, name) end
  end)
  o.frame:ClearAllPoints(); o.frame:SetPoint("CENTER", UIParent, "CENTER", 260, 60)
  o.frame:Show(); o.frame:Raise()
  return true
end

function P.Picker(anchor)
  local list = P.People()
  if #list == 0 then C.Print("profiles: nobody yet. Group up or farm with someone, or /kina profile Name."); return end
  local opts = {}
  for _, e in ipairs(list) do
    opts[#opts + 1] = { e.who .. (e.group and (e.kina and "  |cff7CFC00(party, Kina)|r" or "  |cff9d9d9d(party, no Kina)|r") or "  |cff9d9d9d(farmed with)|r"), e.who }
    if #opts >= 14 then break end
  end
  if C.Cos and C.Cos.OpenList then C.Cos.OpenList(anchor, "View a profile", opts, function(w) P.Show(w) end) end
end
