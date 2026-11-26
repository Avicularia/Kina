-- Kina: core, saved data, events.
-- Separate addon from Kina Scout: own namespace, own SavedVariables (KinaDB),
-- own slash command (/kina), own frame names. Never writes another addon's data.
local ADDON, C = ...
C.Dialogs = C.Dialogs or {} -- 1.0.4: Kina's own question definitions (never the game's popup table)
C.name = "Kina"
C.version = "2.1.4"
-- 1.5.5 / 0.9.0 (Taylor): Kina is a beta until its CurseForge launch (1.0.0). Builds are
-- compared by C.BUILD, which only ever goes up (the shown version went back to 0.9).
C.BUILD = 208
-- is version a newer than b? ("1.2.10" > "1.2.9")
function C.VersionNewer(a, b)
  local function parts(v) local t = {}; for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end; return t end
  local x, y = parts(a), parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end -- Public Kina
C.PUBLIC = true
-- 0.9.22 (Taylor: in dungeons Kina could "spaz out" so your inputs barely worked): the
-- safety net for everything that runs every frame, on a timer or in a game hook. Game
-- events were already guarded; these weren't. An error is logged (Kina.lua > errlog),
-- never thrown to the game, and a piece that keeps failing is switched off for the
-- session, so an error can never repeat 60 times a second. /reload brings it back.
local TRIP = 3
local guardSaid = false
local function tripped(name)
  if guardSaid then return end
  guardSaid = true
  if C.Print then pcall(C.Print, "|cffff8040one part of Kina hit an error and was switched off so your game keeps running smoothly (" .. tostring(name) .. ").|r /reload brings it back. Please report it with your Kina version.") end
end
local function note(name, err) if C.LogError then pcall(C.LogError, name, err) end end
-- a function that can never throw; after TRIP errors it does nothing for the session
function C.Safe(name, fn)
  if type(fn) ~= "function" then return fn end
  local errs, off = 0, false
  return function(...)
    if off then return end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    errs = errs + 1; note(name, a)
    if errs >= TRIP then off = true; tripped(name) end
  end
end
-- frame:SetScript(script, fn) with the same net; a script that keeps failing is removed
function C.GuardScript(frame, script, name, fn)
  if not frame then return end
  if type(fn) ~= "function" then return frame:SetScript(script, fn) end
  local errs = 0
  frame:SetScript(script, function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      errs = errs + 1; note(name, err)
      if errs >= TRIP then pcall(frame.SetScript, frame, script, nil); tripped(name) end
    end
  end)
end
-- Your bags: the backpack, 4 bags, and the reagent bag where the client has one
-- (cloth, meat and other reagents go there automatically).
function C.PlayerBags()
  local t = { 0, 1, 2, 3, 4 }
  local B = Enum and Enum.BagIndex
  if B and B.ReagentBag then t[#t + 1] = B.ReagentBag end
  return t
end
function C.BankBags()
  local B = Enum and Enum.BagIndex
  if B and B.BankBag_1 then
    local t = { B.Bank or -1 }
    for i = 1, 7 do if B["BankBag_" .. i] then t[#t + 1] = B["BankBag_" .. i] end end
    if B.Reagentbank then t[#t + 1] = B.Reagentbank end
    return t
  end
  return { -1, 5, 6, 7, 8, 9, 10 }
end
-- Is the mailbox / a vendor really open right now? (the open/close events can be
-- missed, e.g. walking away; a stuck flag filed looted coin as mail)
function C.MailIsOpen() if MailFrame and MailFrame.IsShown then return MailFrame:IsShown() and true or false end end
function C.MerchantIsOpen() if MerchantFrame and MerchantFrame.IsShown then return MerchantFrame:IsShown() and true or false end end
-- Admin view (the private build only): who used which consumables. Public builds show
-- the group total only, so nobody gets blamed for a potion.
function C.Admin() return not C.PUBLIC end
-- 0.9.20 (Taylor): the "Try" previews (cosmetics, bar frames) are off in the release and
-- unlocked by the admin password in Settings. Only a hash of it is kept here (a light
-- lock for preview buttons, not security: nothing it unlocks changes real data).
local ADMIN_KEY = 4138906054
local function keyOf(s)
  local x = 5381
  for i = 1, #s do x = (x * 33 + s:lower():byte(i)) % 4294967296 end
  return x
end
function C.Unlocked() return not C.PUBLIC or (C.settings and C.settings.adminUnlocked == true) or false end
function C.TryUnlock(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  if keyOf(text) == ADMIN_KEY then
    C.settings.adminUnlocked = true
    C.Print("|cff33ff66team code accepted:|r the Try buttons are on (You tab), and this is a dev install: it never freezes other players' Kinas.")
    if C.Share and C.Share.Announce then pcall(C.Share.Announce, true) end
    return true
  end
  if C.settings.adminUnlocked then
    C.settings.adminUnlocked = nil
    if C.Cos and C.Cos.preview then for k in pairs(C.Cos.preview) do C.Cos.preview[k] = nil end end
    C.Print("the Try buttons are off.")
    if C.Share and C.Share.Announce then pcall(C.Share.Announce, true) end
  else C.Print("|cffff8040that code isn't right.|r") end
  return false
end
-- 0.9.8: Kina's confirm popups (Forgive, Pay, Dispute...) are the game's popups, which sit
-- on a lower layer than the Kina window: they opened hidden behind it. Kina steps back
-- first (clicking Kina again brings it forward).
-- 1.0.4: C.ShowPopup is now Kina's own dialog (Dialog.lua), never the game's popup.
C.SCHEMA = 1

local floor = math.floor

------------------------------------------------------------------ text size
-- Kina's own copies of the game fonts, so the Text size slider can resize Kina's
-- text without touching the rest of the UI. C.Text() makes a font string that
-- uses them and follows the slider live.
C.fonts = {}
local texts = setmetatable({}, { __mode = "k" })
function C.TextScale()
  local s = C.settings and C.settings.textScale or 1
  return math.max(0.7, math.min(1.5, tonumber(s) or 1))
end
function C.Font(name)
  local k = C.fonts[name]
  if k then return k end
  local src = _G[name]
  if not (CreateFont and src and src.GetFont) then return name end
  local file, size, flags = src:GetFont()
  if not file then return name end
  k = CreateFont("Kina" .. name)
  k:CopyFontObject(src)
  k.kinaBase = { file, size, flags or "" }
  k:SetFont(file, size * C.TextScale(), flags or "")
  C.fonts[name] = k
  return k
end
function C.Text(parent, layer, name)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local obj = C.Font(name or "GameFontHighlightSmall")
  if type(obj) == "string" then obj = _G[obj] end
  if obj and fs.SetFontObject then fs:SetFontObject(obj) end
  texts[fs] = obj
  return fs
end
function C.ApplyTextScale(s)
  if s then C.settings.textScale = math.floor(s * 20 + 0.5) / 20 end
  local scale = C.TextScale()
  for _, k in pairs(C.fonts) do
    local b = k.kinaBase
    if b then k:SetFont(b[1], b[2] * scale, b[3]) end
  end
  -- re-apply so every Kina text picks up the new size at once
  for fs, obj in pairs(texts) do if fs.SetFontObject and obj then fs:SetFontObject(obj) end end
  if C.OnTextScale then C.OnTextScale(scale) end
end

------------------------------------------------------------------ utilities
function C.Print(msg)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cff4fc3f7Kina|r: " .. tostring(msg)) end
end

function C.Now() return (GetServerTime and GetServerTime()) or time() end

-- 123456 copper -> "12g 34s 56c" (short form drops zero parts)
function C.Money(cp)
  if type(cp) ~= "number" or cp ~= cp then return "?" end
  local neg = cp < 0; cp = floor(math.abs(cp) + 0.5)
  local g, s, c = floor(cp / 10000), floor(cp / 100) % 100, cp % 100
  local out
  if g > 0 then out = string.format("%dg %02ds", g, s)
  elseif s > 0 then out = string.format("%ds %02dc", s, c)
  else out = string.format("%dc", c) end
  return (neg and "-" or "") .. out
end

function C.Pct(x) return string.format("%.0f%%", (x or 0) * 100) end

function C.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

-- 0.9.9: inside dungeons the game hands add-ons "secret" unit values (GUIDs, names,
-- levels) that raise an error when compared or read. C.Plain gives nil for those.
function C.Plain(v)
  if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
  return v
end
function C.NPCIDFromGUID(guid)
  if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id), "npc" end
  if kind == "GameObject" then return tonumber(id), "object" end
  return nil
end

-- Version family: history survives weekly beta builds ("1.60.1/70425" -> "1.60").
function C.VersionFamily()
  local v = GetBuildInfo and select(1, GetBuildInfo()) or "0"
  local major, minor = tostring(v):match("^(%d+)%.(%d+)")
  return major and (major .. "." .. minor) or tostring(v)
end

-- 2.0.19 (Taylor: "Hours farmed doesn't even make sense"): since Nov 20 WoW Forever gives
-- addons a blank realm name, all the time, not just at load. Kina's profile, AH prices and
-- characters were split between the real realm and a blank one, and the step that joins
-- them waited for a name that never came. The realm now comes from the first good answer:
-- the game, then the last good name Kina saw, then the one realm this install already knows.
local function goodRealm(r) return type(r) == "string" and r ~= "" and r ~= "?" end
C.GoodRealm = goodRealm
function C.Realm()
  local r = GetRealmName and GetRealmName()
  local db = KinaDB
  if goodRealm(r) then
    if type(db) == "table" then db.lastRealm = r end
    return r
  end
  if type(db) == "table" then
    if goodRealm(db.lastRealm) then return db.lastRealm end
    local only, n = nil, 0
    local seen = {}
    local function see(x) if goodRealm(x) and not seen[x] then seen[x] = true; only = x; n = n + 1 end end
    if type(db.realms) == "table" then for k in pairs(db.realms) do see(k) end end
    see(db.profileRealm)
    if type(db.markets) == "table" then for k in pairs(db.markets) do see((tostring(k):match("^(.-)|"))) end end
    if n == 1 then db.lastRealm = only; return only end
  end
  local nr = GetNormalizedRealmName and GetNormalizedRealmName()
  if goodRealm(nr) then return nr end
  if UnitFullName then local _, fr = UnitFullName("player"); if goodRealm(fr) then return fr end end
  return r or ""
end
function C.MarketKey()
  local realm = C.Realm()
  if not goodRealm(realm) then realm = "?" end
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
  return realm .. "|" .. faction
end
-- 2.0.16 (found checking Taylor's hot list): when the realm name is blank at load, the AH
-- prices were kept under "|Alliance", apart from the realm's own (and its price history,
-- which hot streaks need). Once the realm is known, Kina folds them into one.
function C.FixMarketKey()
  local d = C.db
  if not (d and type(d.markets) == "table") then return end
  local key = C.MarketKey()
  local realm, faction = key:match("^(.-)|(.*)$")
  if not realm or realm == "" or realm == "?" or faction == "?" then return end
  local good = d.markets[key]
  if type(good) ~= "table" then good = { items = {}, history = {} }; d.markets[key] = good end
  good.items = good.items or {}; good.history = good.history or {}
  local function fold(m)
    if m == good or type(m) ~= "table" then return end
    if (m.scanTime or 0) > (good.scanTime or 0) then
      for k, v in pairs(m) do if k ~= "history" then good[k] = v end end
    end
    for id, days in pairs(m.history or {}) do
      if type(days) == "table" then
        good.history[id] = good.history[id] or {}
        for day, p in pairs(days) do if good.history[id][day] == nil then good.history[id][day] = p end end
      end
    end
  end
  for k, m in pairs(d.markets) do
    local r, f = tostring(k):match("^(.-)|(.*)$")
    if f == faction and (r == "" or r == "?") then fold(m); d.markets[k] = nil end
  end
  if C.market ~= good then fold(C.market); C.market = good end
  -- 2.0.19: characters saved under a blank realm ("Deputize-") join the real one
  if type(d.chars) == "table" then
    for k, ch in pairs(d.chars) do
      local nm = tostring(k):match("^(.-)%-$")
      if nm and nm ~= "" and type(ch) == "table" then
        local gk = nm .. "-" .. realm
        local g = d.chars[gk]
        if type(g) ~= "table" then d.chars[gk] = ch
        else for kk, vv in pairs(ch) do g[kk] = vv end end -- the blank one is the newer
        d.chars[k] = nil
      end
    end
    local ck = ((UnitName and UnitName("player")) or "?") .. "-" .. realm
    if C.charKey ~= ck and d.chars[ck] then C.charKey = ck; C.char = d.chars[ck] end
  end
end
if CreateFrame then
  local mf = CreateFrame("Frame")
  mf:RegisterEvent("PLAYER_ENTERING_WORLD")
  mf:SetScript("OnEvent", function(self) if C.db then pcall(C.FixMarketKey); if C.market then self:UnregisterAllEvents() end end end)
end

------------------------------------------------------------------ saved data
local defaults = {
  schema = C.SCHEMA,
  settings = {
    ahCut = 0.05,            -- faction auction houses take 5%
    depositFloor = 100,      -- players report a 1s minimum posting charge
    vendorMargin = 0.10,     -- unlearned vendor prices count 10% lower
    killsPerHour = 60,       -- default until your own sessions measure it
    launchTime = 1793833200, -- Nov 4 2026 15:00 PST (23:00 UTC); /kina launch to change
    minDealProfit = 100,     -- hide deals under 1s
    hudShown = true,
    autoScan = true,         -- full AH scan when the auction house opens (15-min limit respected)
    farmSound = true,        -- start/stop fanfares on the farm widget
    farmPreset = 0,          -- farm timer in seconds (0 = no timer)
    widgetAlpha = 0.80,
    pos = {},                -- saved window positions
    picksPerHour = 120,      -- pick-only circuits: picks per hour for the estimate
    textScale = 1.15,        -- Kina text size (Settings > Window > Text size); 1.2.2: 115% by default
    tooltip = true,          -- vendor / AH / disenchant lines on item tooltips
    minROI = 0,              -- hide rows under this ROI % (0 = show all)
    worthOnly = false,       -- hide trades that don't pay for your time
  },
  markets = {},     -- [marketKey] = { family, scanTime, items = {[id]={...}}, history = {[id]={[day]={min,med,qty}}} }
  items = {},       -- [itemID] = { q, il, rl, cls, sub, eq, vend, name, bind }  (static item facts)
  vendor = {},      -- [itemID] = { p = copper each, t = time, c = client price then }
  noDE = {},        -- [itemID] = time learned (game refused to disenchant)
  noVend = {},      -- [itemID] = 1: the game says no merchant buys it (1.0.2)
  loot = {},        -- [npcID] = { nm, lvl, type, kills, looted, coin, pp, ppCoin, items = {[id]=n}, skins, skinItems = {} }
  nodes = {},       -- [objectID] = { nm, n, items = {[id]=n} }
  sessions = {},    -- recent finished sessions (max 50)
  stock = {},       -- [itemID] = { buyUnder, sellAt, note, added }
  chars = {},       -- [name-realm] = { prof = {[name]=rank}, level, class }
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; fill(dst[k], v) else dst[k] = v end
    elseif type(v) == "table" and type(dst[k]) == "table" and k == "settings" then
      fill(dst[k], v)
    end
  end
end

-- 0.9.11 (Taylor): each realm has its own Kina profile. A realm is its own community,
-- so moving to a new realm starts a new Kina level, standing, record and debts there;
-- going back to the old realm brings its profile back. What belongs to the profile:
local PROFILE_KEYS = { "log", "sessions", "activeSession", "settles", "forgive", "payout", "vouch",
  "mentor", "mark", "farmIn", "seenMail", "share", "pair", "parked" }
C.PROFILE_KEYS = PROFILE_KEYS
-- 2.0 (Taylor: "it reset all of us back to level 1", farms missing): on Nov 20 the game
-- gave Kina a blank realm name while loading. Kina took that for a new realm, put the whole
-- profile away under the real realm's name and started an empty one. Now a blank name never
-- switches anything (Kina checks again once you're in the world), and a profile made under a
-- blank name is folded back into the real realm's profile, keeping what was done since.
local function blank(r) return r == nil or r == "" or r == "?" end
-- fold what was made under the blank profile (now) into the real one (back)
local function foldBlank(back, now)
  for _, k in ipairs(PROFILE_KEYS) do
    local b, n = back[k], now[k]
    if k == "sessions" and type(b) == "table" and type(n) == "table" then
      local seen, all = {}, {}
      for _, x in ipairs(b) do if type(x) == "table" then seen[x.start or 0] = true; all[#all + 1] = x end end
      for _, x in ipairs(n) do if type(x) == "table" and not seen[x.start or 0] then seen[x.start or 0] = true; all[#all + 1] = x end end
      table.sort(all, function(x, y) return (x.start or 0) > (y.start or 0) end)
      -- 2.0.19: nothing is trimmed here: every farm reaches the farm history first (Progress
      -- HistBackfill, at login); the next farm end trims the list back to 50
      back[k] = all
    elseif k == "log" then
      -- the real profile's record stands (Kina level and record come from it; the blank one
      -- holds only logins since); an empty real record takes the newer one
      if type(b) ~= "table" or type(b.lines) ~= "table" or #b.lines == 0 then back[k] = n end
    elseif type(b) == "table" and type(n) == "table" then
      -- keep everything from both (two levels deep: commendations given and got, mentor lists)
      local function sig(x)
        if type(x) ~= "table" then return tostring(x) end
        return tostring(x.t) .. "|" .. tostring(x.who) .. "|" .. tostring(x.ref) .. "|" .. tostring(x.start) .. "|" .. tostring(x.kind)
      end
      local function mergeInto(dst, src)
        if dst[1] ~= nil or src[1] ~= nil then -- lists (commendations given and got): add the missing ones
          local have = {}
          for _, x in ipairs(dst) do have[sig(x)] = true end
          for _, x in ipairs(src) do if not have[sig(x)] then dst[#dst + 1] = x; have[sig(x)] = true end end
        else
          for k3, v3 in pairs(src) do if dst[k3] == nil then dst[k3] = v3 end end
        end
      end
      for kk, vv in pairs(n) do
        if b[kk] == nil then b[kk] = vv
        elseif type(b[kk]) == "table" and type(vv) == "table" then mergeInto(b[kk], vv) end
      end
    elseif b == nil then back[k] = n end
  end
end
function C.RealmProfile(db, cur)
  cur = cur or C.Realm() or ""
  if type(db.realms) ~= "table" then db.realms = {} end
  if blank(cur) then C.realmPending = true; return end
  C.realmPending = nil
  local was = db.profileRealm
  if type(was) == "string" and blank(was) then
    local back = db.realms[cur]
    if type(back) == "table" then
      local now = {}
      for _, k in ipairs(PROFILE_KEYS) do now[k] = db[k] end
      foldBlank(back, now)
      for _, k in ipairs(PROFILE_KEYS) do db[k] = back[k] end
      db.realms[cur] = nil
      C.realmRestored = true
    end
    db.realms[""] = nil; db.realms["?"] = nil
    db.profileRealm = cur
    return
  end
  if type(was) ~= "string" then
    -- data from before 0.9.11 belongs to the realm it was made on: the one whose auction
    -- house Kina knows best (a brand-new install has none, and simply starts here)
    local best, bn = nil, 0
    for k, m in pairs(type(db.markets) == "table" and db.markets or {}) do
      local r, n = tostring(k):match("^(.-)|"), 0
      if type(m) == "table" and type(m.items) == "table" then for _ in pairs(m.items) do n = n + 1 end end
      if r and n > bn then best, bn = r, n end
    end
    was = best or cur
  end
  if was ~= cur then
    local out = {}
    for _, k in ipairs(PROFILE_KEYS) do out[k] = db[k]; db[k] = nil end
    db.realms[was] = out
    local back = db.realms[cur]
    if type(back) == "table" then
      for _, k in ipairs(PROFILE_KEYS) do db[k] = back[k] end
      db.realms[cur] = nil
    elseif type(out.share) == "table" and type(out.share.opts) == "table" then
      -- a new profile keeps your sharing settings (and nothing else)
      local o = {}; for k, v in pairs(out.share.opts) do o[k] = v end
      db.share = { opts = o }
    end
    C.realmSwitched = { from = was, to = cur, fresh = type(back) ~= "table" }
  end
  db.profileRealm = cur
end

function C.InitDB()
  -- Kina was called Kina Scout C: the old saved data (loaded by the small KinaScoutC
  -- stub that ships with Kina) moves over once, so nothing is lost in the rename.
  if type(KinaDB) ~= "table" or next(KinaDB) == nil then
    if type(KinaScoutCDB) == "table" and next(KinaScoutCDB) ~= nil then
      KinaDB = KinaScoutCDB
      C.migrated = true
    else
      KinaDB = KinaDB or {}
    end
  end
  C.RealmProfile(KinaDB)
  -- 2.0: the realm name wasn't known yet: settle the profile once it is
  if C.realmPending and CreateFrame then
    local rf = CreateFrame("Frame")
    rf:RegisterEvent("PLAYER_LOGIN"); rf:RegisterEvent("PLAYER_ENTERING_WORLD")
    rf:SetScript("OnEvent", function(self)
      if not C.realmPending then self:UnregisterAllEvents(); return end
      C.RealmProfile(KinaDB)
      if C.realmPending then return end
      self:UnregisterAllEvents()
      fill(KinaDB, defaults)
      if C.realmRestored and C.Print then
        C.Print("|cff40ff40your farms and Kina level are back.|r A blank realm name on Nov 20 had hidden them; Kina has put them back with everything since.")
      end
    end)
  end
  -- damaged or very old saved data: drop whatever has the wrong shape (Schema.lua)
  if C.Sanitize then
    local n = C.Sanitize(KinaDB)
    if n and n > 0 then
      C.dataRepaired = n
      -- 1.2.2: keep what was dropped, for Claude
      KinaDB.repairs = type(KinaDB.repairs) == "table" and KinaDB.repairs or {}
      table.insert(KinaDB.repairs, 1, { t = (GetServerTime and GetServerTime()) or 0, v = C.version, n = n, paths = C.repairPaths or {} })
      while #KinaDB.repairs > 10 do table.remove(KinaDB.repairs) end
    end
  end
  fill(KinaDB, defaults)
  -- 1.2.2: Kina's text is 15% bigger by default; anyone still on the old 100% moves up once
  if KinaDB.settings and not KinaDB.settings.text115 then
    if KinaDB.settings.textScale == 1 then KinaDB.settings.textScale = 1.15 end
    KinaDB.settings.text115 = true
  end
  C.db = KinaDB
  C.settings = C.db.settings
  local key = C.MarketKey()
  local m = C.db.markets[key]
  if not m then m = { items = {}, history = {} }; C.db.markets[key] = m end
  m.items = m.items or {}; m.history = m.history or {}
  C.market = m
  C.charKey = ((UnitName and UnitName("player")) or "?") .. "-" .. (C.Realm() or "?")
  C.db.chars[C.charKey] = C.db.chars[C.charKey] or { prof = {} }
  C.char = C.db.chars[C.charKey]
end

------------------------------------------------------------------ events
local frame = CreateFrame("Frame", "KinaEventFrame")
C.frame = frame
-- Record any blocked protected call so it can be diagnosed from saved data.
-- Works from the first moment the file loads (buffered until saved data exists).
local early = {}
local function blocked(event, addon, func)
  if addon ~= ADDON then return end
  local rec = { event = event, func = tostring(func), t = C.Now(), stage = C.stage or "?" }
  -- 1.2.2: what Kina was doing, to find the cause of an UNKNOWN() block
  if InCombatLockdown then rec.combat = InCombatLockdown() and true or false end
  if C.lastSend then rec.lastSend = C.lastSend.k; rec.sendAgo = (GetTime and GetTime() or 0) - C.lastSend.t end
  if C.lastEvent then rec.lastEvent = C.lastEvent end
  if C.lastAction then rec.lastAction = C.lastAction.what; rec.actAgo = (GetTime and GetTime() or 0) - C.lastAction.t end
  if not C.db then table.insert(early, rec); return end
  C.db.blocked = C.db.blocked or {}
  table.insert(C.db.blocked, 1, rec)
  while #C.db.blocked > 20 do table.remove(C.db.blocked) end
  -- 1.2.3: once per session in chat; every block is still saved for Claude
  if not C.blockSaid then
    C.blockSaid = true
    C.Print("the game blocked one of Kina's actions (saved for Claude; you won't see this again until /reload)")
  end
end
C.FlushBlocked = function() for _, r in ipairs(early) do C.db.blocked = C.db.blocked or {}; table.insert(C.db.blocked, 1, r) end; early = {} end
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
local handlers = {}

function C.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- INIT is internal; never ask the client to register a non-event
    if event ~= "ADDON_LOADED" and event ~= "INIT" then
      C.stage = "registering " .. event
      frame:RegisterEvent(event)
      C.stage = "loading"
    end
  end
  table.insert(handlers[event], fn)
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON then
      C.InitDB()
      C.FlushBlocked()
      C.ready = true
      C.stage = "running"
      -- say which version is running, so an outdated copy is obvious
      C.After(3, function()
        C.Print("version " .. C.version .. " loaded. /kina opens the window.")
        -- first time ever: one line on what Kina is for
        if C.PUBLIC and not C.settings.welcomed then
          C.settings.welcomed = C.Now()
          C.Print("|cffffc54aWelcome!|r Press Start on the Kina widget when you farm. Group with other Kina users: everyone's widget shows the same totals and split, and farming together earns Renown.")
        end
        if C.dataRepaired then C.Print("|cffff8040some of Kina's saved data was damaged and has been cleaned up (" .. C.dataRepaired .. " entries).|r") end
        if C.migrated then C.Print("your Kina Scout C data was moved over. You can delete the old KinaScoutC folder after this session.") end
      end)
      for _, fn in ipairs(handlers.INIT or {}) do
        local ok, err = pcall(fn)
        if not ok then C.Print("init error: " .. tostring(err)) end
      end
    end
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then blocked(event, ...); return end
  if not C.ready then return end
  local list = handlers[event]
  if not list then return end
  C.lastEvent = event
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok then C.LogError(event, err) end
  end
end)
-- Errors are kept in the saved file (Kina.lua > errlog) so Claude can read them after a
-- test, and announced once per session.
local errSaid = false
function C.LogError(where, err)
  if not C.db then return end
  C.db.errlog = C.db.errlog or {}
  local key = tostring(where) .. ": " .. tostring(err)
  for _, e in ipairs(C.db.errlog) do
    if e.msg == key then e.n = (e.n or 1) + 1; e.last = C.Now(); return end
  end
  table.insert(C.db.errlog, 1, { msg = key, n = 1, first = C.Now(), last = C.Now(), v = C.version })
  while #C.db.errlog > 40 do table.remove(C.db.errlog) end
  if C.debug or not errSaid then
    errSaid = true
    C.Print("|cffff8040an error was logged|r (" .. tostring(where) .. "). Play on; send Claude your Kina.lua saved file after the test.")
  end
end


------------------------------------------------------------------ windows
-- Drag any Kina window by its title strip (or any empty part of it); the spot is
-- remembered per window. /kina reset puts every window back.
function C.SavePos(f, key)
  local point, _, rel, x, y = f:GetPoint(1)
  if point then C.settings.pos[key] = { point, rel, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

function C.RestorePos(f, key, ...)
  local p = C.settings.pos[key]
  f:ClearAllPoints()
  if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else f:SetPoint(...) end
end

-- handle: an extra region that also starts a drag (a title strip above child widgets)
-- 1.5.2: is this one of my own characters (any I've logged in with Kina on this account)?
function C.IsMyChar(name)
  local want = tostring(name or ""):match("^([^%-]+)")
  if not want or want == "" then return false end
  want = want:lower()
  if UnitName and tostring(UnitName("player") or ""):lower() == want then return true end
  for k in pairs(C.db and C.db.chars or {}) do
    if tostring(k):match("^([^%-]+)"):lower() == want then return true end
  end
  return false
end
local dragFns = setmetatable({}, { __mode = "k" })
-- 1.5.1: another piece of a window that moves it (the KINA banner sits over the title band)
function C.DragBy(f, piece)
  local fn = dragFns[f]
  if not (fn and piece) then return end
  piece:EnableMouse(true)
  piece:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then fn[1]() end end)
  piece:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" and C.dragging == f then fn[2]() end end)
end
function C.MakeDraggable(f, key, handle, onMoved)
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  -- Kina saves window spots itself: keep the game's own layout cache out of it, or
  -- the two fight and the window snaps somewhere else
  if f.SetDontSavePosition then pcall(f.SetDontSavePosition, f, true) end
  local function start()
    if InCombatLockdown and InCombatLockdown() and f:IsProtected() then return end
    C.dragging = f
    f:StartMoving()
  end
  local function stop()
    f:StopMovingOrSizing()
    C.dragging = nil
    if C.refreshAfterDrag and C.Refresh then C.refreshAfterDrag = nil; C.Refresh() end
    if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
    -- re-anchor to UIParent so the saved spot is independent of other frames
    local l, b = f:GetLeft(), f:GetBottom()
    if l and b then f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b) end
    C.SavePos(f, key)
    if onMoved then onMoved(f) end
  end
  -- 1.2.2: with the iron look a window with a title band moves only by that band
  -- (grabbing anywhere else did nothing useful and felt broken)
  if handle and C.Skin and C.Skin.On() then
    f:RegisterForDrag(); f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
  else
    f:SetScript("OnDragStart", start); f:SetScript("OnDragStop", stop)
  end
  dragFns[f] = { start, stop }
  if handle then
    -- the title bar moves the window from the moment you press, no drag threshold
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then start() end end)
    handle:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" and C.dragging == f then stop() end end)
    handle:SetScript("OnHide", function() if C.dragging == f then stop() end end)
  end
  -- 1.2.6: with the iron look the whole iron border moves the window too (four thin
  -- strips along the edges; the bottom-right corner stays the resize grip)
  -- (1.4.1: main window only: on the small widget the strips sat over its Sound and close
  -- buttons, the "layering" Taylor saw)
  if handle and C.Skin and C.Skin.On() and f.GetName and f:GetName() == "KinaFrame" then
    local T, GRIP = 8, 26
    local function strip(p1, p2, x1, y1, x2, y2, w, h)
      local e = CreateFrame("Frame", nil, f)
      e:SetFrameLevel((f:GetFrameLevel() or 1) + 30)
      e:SetPoint(p1, f, p1, x1, y1); e:SetPoint(p2, f, p2, x2, y2)
      if w then e:SetWidth(w) end; if h then e:SetHeight(h) end
      e:EnableMouse(true)
      e:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then start() end end)
      e:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" and C.dragging == f then stop() end end)
      e:SetScript("OnHide", function() if C.dragging == f then stop() end end)
    end
    -- (1.5.1: the iron is drawn ~16 px OUTSIDE the window too; the strips now cover that
    -- outer half as well, so grabbing anywhere on the visible iron moves it)
    local O = 16
    strip("TOPLEFT", "TOPRIGHT", -O, O, -36, O, nil, T + O)          -- top (the close button keeps its corner)
    strip("TOPLEFT", "BOTTOMLEFT", -O, -T, -O, 0, T + O, nil)        -- left
    strip("TOPRIGHT", "BOTTOMRIGHT", O, -36, O, GRIP, T + O, nil)    -- right (stops above the grip)
    strip("BOTTOMLEFT", "BOTTOMRIGHT", T, -O, -GRIP, -O, nil, T + O) -- bottom (stops left of the grip)
  end
end

-- Corner grip that scales a window (its contents keep their layout): drag the
-- bottom-right corner; the size is remembered. Used by the detail panel and widget.
-- A resize grip people notice: bigger, gold, with a soft backing and a tooltip.
function C.StyleGrip(grip, tip)
  if C.Skin and C.Skin.Grip(grip) then
    grip:HookScript("OnEnter", function(self) if GameTooltip then C.TipOwner(self); GameTooltip:AddLine(tip or "Drag to resize", 1, 1, 1, true); GameTooltip:Show() end end)
    grip:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return
  end
  grip:SetSize(26, 26)
  local bg = grip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(1, 0.62, 0, 0.18)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local n = grip.GetNormalTexture and grip:GetNormalTexture()
  if n and n.SetVertexColor then n:SetVertexColor(1, 0.62, 0) end
  grip:SetScript("OnEnter", function(self)
    bg:SetColorTexture(1, 0.62, 0, 0.4)
    if GameTooltip then C.TipOwner(self); GameTooltip:AddLine(tip or "Drag to resize", 1, 1, 1, true); GameTooltip:Show() end
  end)
  grip:SetScript("OnLeave", function() bg:SetColorTexture(1, 0.62, 0, 0.18); if GameTooltip then GameTooltip:Hide() end end)
end

-- Corner grip that scales a window (details panel, farm widget). The window's
-- top-left corner is pinned on screen when you press the grip, and the scale
-- follows how far you drag from that press point: no reading back positions the
-- game hasn't updated yet (that fed back on itself and made windows run away).
local SCALE_MIN, SCALE_MAX = 0.6, 1.5
function C.ScaleGrip(f, key, minScale)
  local SCALE_MIN = minScale or SCALE_MIN
  local saved = C.settings.pos[key]
  if type(saved) == "number" then f:SetScale(math.max(SCALE_MIN, math.min(SCALE_MAX, saved))) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetFrameLevel(f:GetFrameLevel() + 20)
  C.StyleGrip(grip, "Drag to make this window bigger or smaller.")
  grip:SetScript("OnMouseDown", function(self)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return end
    local eff = f:GetEffectiveScale()
    -- everything in screen pixels, taken once
    self.pinX, self.pinY = l * eff, t * eff
    self.startX = GetCursorPosition()
    self.startScale = f:GetScale()
    self.width = math.max(100, f:GetWidth()) * eff -- the window's width on screen at the press
    C.GuardScript(self, "OnUpdate", "Core:582", function(g)
      local cx = GetCursorPosition()
      local scale = g.startScale * (1 + (cx - g.startX) / g.width)
      scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
      if math.abs(scale - f:GetScale()) < 0.005 then return end
      f:SetScale(scale)
      local parentEff = (f:GetParent() or UIParent):GetEffectiveScale()
      local unit = parentEff * scale -- screen pixels per unit of this window
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.pinX / unit, g.pinY / unit)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    C.settings.pos[key] = math.floor(f:GetScale() * 100 + 0.5) / 100
  end)
  grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  return grip
end

-- Tooltips go where your UI puts tooltips (the default tooltip spot, which UI
-- addons can move), not beside whatever the mouse is over.
function C.TipOwner(owner)
  local tip = GameTooltip
  if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(tip, owner or UIParent)
  else tip:SetOwner(owner or UIParent, "ANCHOR_NONE"); tip:ClearAllPoints(); tip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -95, 110) end
  return tip
end

-- Small cooperative job runner so long work never stalls a frame.
local jobs = {}
local urgentSet
local runner = CreateFrame("Frame")
runner:Hide()
-- 2.0.5 (Taylor: the AH scan takes over a minute): steps run for up to 6 ms a frame
-- (not one step a frame), and an urgent job (the scan) goes ahead of the rest
local clock = debugprofilestop
C.GuardScript(runner, "OnUpdate", "Core:615", function(self)
  local t0 = clock and clock() or 0
  local steps = 0
  repeat
    steps = steps + 1
    local job = jobs[1]
    if not job then self:Hide(); return end
    local ok, done = pcall(job)
    if not ok then
      if C.debug then C.Print("job error: " .. tostring(done)) end
      done = true
    end
    if done then table.remove(jobs, 1) end
  until not clock or (clock() - t0) > 6 or steps >= 40 -- (a job that's only waiting can't spin)
end)
function C.Job(fn, urgent)
  if urgent then
    -- ahead of everything but other urgent jobs (they keep their order)
    local pos = 1
    while jobs[pos] and urgentSet and urgentSet[jobs[pos]] do pos = pos + 1 end
    table.insert(jobs, pos, fn)
    urgentSet = urgentSet or setmetatable({}, { __mode = "k" }); urgentSet[fn] = true
  else table.insert(jobs, fn) end
  runner:Show()
end

function C.After(sec, fn)
  -- 0.9.22: a timer can never throw into the game
  local safe = function() local ok, err = pcall(fn); if not ok and C.LogError then pcall(C.LogError, "timer", err) end end
  if C_Timer and C_Timer.After then C_Timer.After(sec, safe) else safe() end
end

-- 0.9.11: say so when this realm's Kina profile is new (or an old one came back)
C.On("PLAYER_LOGIN", function()
  local s = C.realmSwitched
  if not (s and C.After) then return end
  C.After(6, function()
    if s.fresh then
      C.Print(string.format("|cffffc54anew realm, new Kina profile:|r Kina level, standing and record start fresh on %s. Your %s profile is kept for when you play there.", s.to, s.from))
    else
      C.Print(string.format("|cffffc54awelcome back to %s:|r your Kina profile here is back (your %s one is kept).", s.to, s.from))
    end
  end)
end)

-- 1.0.3b (Taylor: "Kina has been blocked from an action only available to the Blizzard
-- UI" when opening Kina): the game names the blocked function in this event. Kina prints
-- it once and keeps the last few (with where they came from) in its saved data, so the
-- cause can be found without a taint log. /kina blocked shows them again.
do
  local seen = {}
  local function note(ev, addon, fn)
    if addon ~= "Kina" then return end
    fn = tostring(fn or "?")
    C.db.blocked = C.db.blocked or {}
    local stack = debugstack and debugstack(3, 6, 0) or ""
    table.insert(C.db.blocked, 1, { t = C.Now and C.Now() or 0, ev = ev, fn = fn, v = C.version, stack = stack:sub(1, 600) })
    while #C.db.blocked > 8 do table.remove(C.db.blocked) end
    if not seen[fn] then
      seen[fn] = true
      if C.Print then C.Print("|cffff8040the game blocked an action:|r " .. fn .. " (" .. ev .. "). Kina saved the details; please tell Taylor.") end
    end
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_ACTION_FORBIDDEN"); f:RegisterEvent("ADDON_ACTION_BLOCKED")
  f:SetScript("OnEvent", function(_, ev, addon, fn) pcall(note, ev, addon, fn) end)
end
