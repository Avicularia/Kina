-- Kina: loot recorder, kill counter and session tracker.
-- Records the FULL loot of every mob you kill (coin, greys, cloth, gear, skins,
-- pickpockets) with kill counts, so drop rates come with denominators.
local ADDON, C = ...
local D = C.Data
local tagged = {}      -- [guid] = true once its kill has been counted (the farm)
local localTagged = {} -- [guid] = true once YOU counted it (your drop-rate records)
local credited = {}    -- [guid..context..item] = how many of it Kina already counted
local skinCastAt = 0   -- when you last finished a Skinning cast
local seenLoot = {}    -- [guid..context] = true (count each corpse once per context)
local lootContext, lootOpen = nil, false
-- 0.15.1: fast-loot addons empty the window before most addons can read it, so
-- the chat lines ("You receive loot: ...") are what count your loot. The window,
-- when Kina catches it, only says which mob each item came from.
local winAttr = {}      -- items the window saw, waiting for their chat line: { id, n, ctx, npc, no, t }
local recentKills = {}  -- your own kills, oldest first: { npc, t, key, looted, skinned }
local recentByKey = {}
local castAt = {}       -- [kind] = GetTime() of your last Disenchant / gathering / Fishing cast
local burst             -- the corpse the current run of chat lines came from
local windowRead = false
local readAt = {}       -- [source guid] = GetTime() it was read (a window seen twice counts once)
local merchantOpen, mailOpen = false, false
local lastMoney

------------------------------------------------------------------ npc facts
local scratch = {}
local function npcRecord(id)
  -- data sharing off: drop data isn't gathered (a throwaway record keeps the code simple)
  if C.ShareData and not C.ShareData() then
    scratch[id] = scratch[id] or { kills = 0, looted = 0, coin = 0, coinLoots = 0, pp = 0, ppCoin = 0, skins = 0, items = {}, ppItems = {}, skinItems = {} }
    return scratch[id]
  end
  local r = C.db.loot[id]
  if not r then r = { kills = 0, looted = 0, coin = 0, coinLoots = 0, pp = 0, ppCoin = 0, skins = 0,
    items = {}, ppItems = {}, skinItems = {} }; C.db.loot[id] = r end
  return r
end

local function noteUnit(unit)
  local P = C.Plain
  if not UnitExists(unit) or P(UnitIsPlayer(unit)) then return end
  local id, kind = C.NPCIDFromGUID(P(UnitGUID(unit)))
  if kind ~= "npc" then return end
  local r = npcRecord(id)
  r.nm = P(UnitName(unit)) or r.nm
  -- seen inside a dungeon or raid: never an open-world farm
  local inInst, itype = false, nil
  if IsInInstance then inInst, itype = IsInInstance() end
  if inInst and (itype == "party" or itype == "raid") then r.inst = true end
  local lvl = UnitLevel and P(UnitLevel(unit)); if lvl and lvl > 0 then r.lvl = lvl end
  r.type = UnitCreatureType and P(UnitCreatureType(unit)) or r.type
  local cls = UnitClassification and P(UnitClassification(unit))
  if cls then
    r.elite = (cls == "elite" or cls == "rareelite" or cls == "worldboss")
    r.rare = (cls == "rare" or cls == "rareelite") or nil
  end
  if GetZoneText then r.zone = GetZoneText() end
end

------------------------------------------------------------------ kills
-- WoW Forever forbids several events for addons: COMBAT_LOG_EVENT_UNFILTERED is
-- proven (Kina Scout taint.log, 1.60.1/70338), and unit/spellcast events are not
-- proven safe. Kina registers none of them. Instead a light poll (4x a
-- second, no events) watches your target: a kill counts once when it dies while
-- tapped by you, or when you loot its corpse.
-- fromParty: a group member's Kina saw the kill. It counts for the farm (kills,
-- kills per hour) but not for your drop-rate records, which only hold your loot.
local function killKey(guid)
  -- the same mob can reach two clients with different server fields in its GUID
  -- (cross-realm groups): npc ID + spawn ID identify it everywhere
  local npc, spawn = guid:match("%-(%d+)%-(%x+)$")
  return npc and (npc .. ":" .. spawn) or guid
end
local function countKill(guid, fromParty)
  if not guid then return end
  local key = killKey(guid)
  local id, kind = C.NPCIDFromGUID(guid)
  if kind ~= "npc" then return end
  -- your own drop-rate denominator counts what YOU saw, even if the party's note came first
  if not fromParty and not localTagged[key] then
    localTagged[key] = true; local r = npcRecord(id); r.kills = r.kills + 1
    local k = { npc = id, t = GetTime and GetTime() or 0, key = key }
    recentKills[#recentKills + 1] = k; recentByKey[key] = k
    if #recentKills > 30 then recentByKey[table.remove(recentKills, 1).key] = nil end
  end
  if tagged[key] then return end
  tagged[key] = true
  if C.session and C.session.sync then
    -- 0.9.5: a kill keeps the farm alive (shared farms used to skip this, so they all
    -- stopped themselves an hour after they started, in the middle of farming)
    if not C.session.paused then C.session.lastKill = C.Now() end
    -- shared farm: the log counts kills (the same mob seen by two players is one)
    if not fromParty and not C.session.paused and C.FarmSync then C.FarmSync.Observe("K", (tostring(key):gsub("[:|]", "-"))) end
    return
  end
  if C.session and C.session.paused then
    C.SessionLog("kill", id, fromParty and 1 or 0); C.session.log[#C.session.log][7] = true -- left out (paused)
    return
  end
  if C.session then
    C.session.last = C.Now()
    C.session.lastKill = C.Now() -- 1.5.4: an hour with no kill ends the farm
    C.session.kills = C.session.kills + 1
    C.session.byNpc[id] = (C.session.byNpc[id] or 0) + 1
    C.SessionLog("kill", id, fromParty and 1 or 0)
    if not fromParty and C.Share and C.Share.SendKill and C.GroupSize and C.GroupSize() > 1 then pcall(C.Share.SendKill, guid) end
  end
end
C.countKill = countKill

-- Kills you never targeted (AoE, pets, a mob that died behind your target) were
-- missed, which makes every drop rate look too good. The same no-event poll also
-- looks at the nameplates in range (plain unit tokens, nothing registered): a dead
-- non-player that is not tapped by someone else is a kill for the farm. Alone it
-- is yours (pets and AoE included) and counts for your drop rates too; in a group
-- the plate could be a partner's kill, so it counts for the farm only (as if a
-- partner's Kina reported it), never for your own denominators.
-- Settings > "Count kills from nameplates" turns it off; C.char.plateKills counts
-- how many kills it added, so you can see whether the game shows dead plates.
local PLATES = 40
function C.ScanPlateKills()
  if C.settings.plateKills == false then return end
  local grouped = C.GroupSize and C.GroupSize() > 1
  local P = C.Plain
  for i = 1, PLATES do
    local u = "nameplate" .. i
    -- (one plate the game keeps secret mustn't stop the rest: each is tried alone)
    pcall(function()
      if UnitExists(u) and UnitIsDead and P(UnitIsDead(u)) and not P(UnitIsPlayer(u))
        and not (UnitIsTapDenied and P(UnitIsTapDenied(u))) then
        local guid = P(UnitGUID(u))
        local npc, kind = C.NPCIDFromGUID(guid)
        if kind == "npc" and not tagged[killKey(guid)] then
          countKill(guid, grouped)
          C.char.plateKills = (C.char.plateKills or 0) + 1
        end
      end
    end)
  end
end

local lastTarget
local function watchTarget()
  local P = C.Plain
  local guid = UnitExists("target") and P(UnitGUID("target")) or nil
  if guid ~= lastTarget then lastTarget = guid; if guid then noteUnit("target") end end
  if guid and UnitIsDead and P(UnitIsDead("target")) and not P(UnitIsPlayer("target"))
    and not (UnitIsTapDenied and P(UnitIsTapDenied("target"))) then
    countKill(guid)
  end
end
local poll = CreateFrame("Frame")
local acc, accPlates = 0, 0
C.GuardScript(poll, "OnUpdate", "Loot:154", function(_, elapsed)
  acc = acc + elapsed
  if acc < 0.25 or not C.ready then return end
  accPlates = accPlates + acc
  acc = 0
  if accPlates >= 0.5 then accPlates = 0; pcall(C.ScanPlateKills) end
  -- 0.9.9: this ran unprotected 4 times a second; in a dungeon the target's GUID is
  -- secret, and comparing it raised an error every time ("a large number of errors")
  local ok, err = pcall(watchTarget)
  if not ok then C.LogError("target poll", err) end
end)

------------------------------------------------------------------ loot windows
local function addItem(t, id, n) t[id] = (t[id] or 0) + n end

-- The farm's event log (Session tab > click a farm): every kill, loot, gold change
-- and AH listing the farm counted, so its numbers can be checked line by line.
function C.SessionLog(k, a, b, c, d)
  local s = C.session
  if not s then return end
  s.log = s.log or {}
  if #s.log >= 600 then table.remove(s.log, 2) end -- keep the start line
  s.log[#s.log + 1] = { C.Now() - s.start, k, a, b, c, d }
end
local function sessionItem(id, n, ctx, npc, suffix)
  if not C.session then return end
  local s = C.session
  if s.paused then
    s.excl = s.excl or { coin = 0, items = {} }
    s.excl.items[id] = (s.excl.items[id] or 0) + n
    C.SessionLog("loot", id, n, ctx, npc); s.log[#s.log][7] = true -- left out (paused)
    s.log[#s.log][8] = suffix
    return
  end
  C.session.last = C.Now()
  addItem(C.session.items, id, n)
  if suffix then
    s.sx = s.sx or {}; s.sx[id] = s.sx[id] or {}
    s.sx[id][suffix] = (s.sx[id][suffix] or 0) + n
  end
  C.SessionLog("loot", id, n, ctx, npc); s.log[#s.log][8] = suffix
end
-- what the loot window saw; the chat line that follows counts it
local function attr(id, qty, ctx, npc, noIncome)
  if not id or not qty or qty <= 0 then return end
  winAttr[#winAttr + 1] = { id = id, n = qty, ctx = ctx, npc = npc, no = noIncome, t = GetTime and GetTime() or 0 }
end

-- Skinning is known from its cast (a reopened, not-yet-emptied corpse is not a skin)
local SKIN_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
-- Cast IDs Kina knows directly (rank 1 of each; names cover the other ranks)
local DE_SPELLS, NODE_SPELLS, FISH_SPELLS = { [13262] = true }, { [2575] = true, [2366] = true }, { [7620] = true, [7731] = true }
-- WoW Forever removed the global GetSpellInfo; C_Spell has the replacement
local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
  if C_Spell and C_Spell.GetSpellInfo then local ok, t = pcall(C_Spell.GetSpellInfo, id); if ok and type(t) == "table" and t.name then return t.name end end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return n end end
end
C.SpellName = spellName
local skinName
C.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" then return end
  if not skinName then skinName = spellName(8613) end
  local nm = spellName(spellID)
  if (spellID and SKIN_SPELLS[spellID]) or (nm and skinName and nm == skinName) then skinCastAt = GetTime() end
  -- casts that put loot in your bags without a corpse
  local function is(set, ...)
    if spellID and set[spellID] then return true end
    if not nm then return false end
    for _, id in ipairs({ ... }) do if nm == spellName(id) then return true end end
    return false
  end
  if is(DE_SPELLS, 13262) then castAt.de = GetTime(); C.deGearCache = nil
  elseif is(NODE_SPELLS, 2575, 2366) then castAt.node = GetTime()
  elseif is(FISH_SPELLS, 7620, 7731) then castAt.fish = GetTime() end
end)

local function readLoot()
  if not GetNumLootItems then return end
  local fishing = IsFishingLoot and IsFishingLoot()
  local targetGUID = UnitExists("target") and UnitGUID("target")
  local targetAlive = targetGUID and not (UnitIsDead and UnitIsDead("target"))
  lootContext = "corpse"
  C.pendingMoney = nil
  -- a Pick Pocket just landed (Pockets.lua saw the cast): this window is the
  -- mob's pockets, not a corpse. Count the items as session income only.
  local firstSrc = GetLootSourceInfo and GetNumLootItems() > 0 and GetLootSourceInfo(1) or nil
  if C.PocketLootActive and C.PocketLootActive(firstSrc) then
    lootContext = "pickpocket"
    if firstSrc and readAt[firstSrc] and GetTime() - readAt[firstSrc] < 3 then return end
    if firstSrc then readAt[firstSrc] = GetTime() end
    for slot = 1, GetNumLootItems() do
      local id = C.ItemIDFromLink(GetLootSlotLink and GetLootSlotLink(slot))
      local q = GetLootSlotInfo and select(3, GetLootSlotInfo(slot)) or 1
      if id then attr(id, (q and q > 0) and q or 1, "pick") end
    end
    return
  end
  -- each source's context is decided ONCE for this window, before anything is counted
  -- (marking the corpse looted on slot 1 used to turn slot 2 into "skinning")
  local skinning = GetTime and (GetTime() - skinCastAt) < 5
  local ctxOf = {}
  local function contextFor(guid)
    if ctxOf[guid] then return ctxOf[guid] end
    local ctx = "corpse"
    if fishing then ctx = "fish"
    elseif targetAlive and not (issecretvalue and (issecretvalue(targetGUID) or issecretvalue(guid))) and guid == targetGUID then ctx = "pickpocket"
    elseif skinning and seenLoot[tostring(guid) .. "corpse"] then ctx = "skin" end
    ctxOf[guid] = ctx
    return ctx
  end
  -- a source this window already read (the same window seen at "ready" and "opened")
  local nowT = GetTime and GetTime() or 0
  local stale = {}
  for slot = 1, GetNumLootItems() do
    local src = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
    for i = 1, #src, 2 do
      contextFor(src[i])
      local g = src[i]
      if g and readAt[g] and nowT - readAt[g] < 3 then stale[g] = true end
    end
  end
  for slot = 1, GetNumLootItems() do
    local kind = GetLootSlotType and GetLootSlotType(slot) or 1
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local slotQty = GetLootSlotInfo and select(3, GetLootSlotInfo(slot)) or 1
    local id = C.ItemIDFromLink(link)
    local src = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
    if #src == 0 then src = { "none", slotQty } end
    for i = 1, #src, 2 do
      local guid, qty = src[i], src[i + 1] or slotQty or 1
      if stale[guid] then guid = nil end
      if guid == nil then
        -- already counted
      else
      if guid ~= "none" then readAt[guid] = nowT end
      -- what kind of loot is this? decided per source, without spell events:
      -- a living target = pickpocket; a corpse already looted = skinning
      local ctx = contextFor(guid)
      if ctx == "pickpocket" then lootContext = "pickpocket" end
      local key = tostring(guid) .. ctx
      local oid, okind = C.NPCIDFromGUID(guid)
      if okind == "npc" then
        local r = npcRecord(oid)
        if not seenLoot[key] then
          seenLoot[key] = true
          if ctx == "pickpocket" then r.pp = r.pp + 1
          elseif ctx == "skin" then r.skins = r.skins + 1
            if C.session then C.session.skins = (C.session.skins or 0) + 1 end
            local rk = recentByKey[killKey(guid)]; if rk then rk.skinned = true end
          elseif ctx == "corpse" then
            r.looted = r.looted + 1; countKill(guid)
            local rk = recentByKey[killKey(guid)]; if rk then rk.looted = true end
            -- where you farm it: running average of your position per map
            local map, px, py = C.PlayerPos()
            if map and px then
              r.locs = r.locs or {}
              local p = r.locs[map] or { x = 0, y = 0, n = 0 }
              p.x = (p.x * p.n + px) / (p.n + 1); p.y = (p.y * p.n + py) / (p.n + 1); p.n = math.min(p.n + 1, 200)
              r.locs[map] = p
              if GetSubZoneText and GetSubZoneText() ~= "" then r.subzone = GetSubZoneText() end
            end
          end
        end
        if kind == 2 and src[i + 1] and qty > 0 then
          -- reopened window: the same coin again is not new coin
          local ck = tostring(guid) .. ctx .. "coin"
          local before = credited[ck] or 0
          if qty > before then credited[ck] = qty end
          qty = qty - before
          if qty <= 0 then qty = 0 end
        end
        if kind == 2 and src[i + 1] and qty == 0 then
          -- nothing new
        elseif kind == 2 then -- money: GetLootSourceInfo reports copper per source
          if not src[i + 1] or qty <= 0 then
            -- amount unknown: credited from the next money change (PLAYER_MONEY)
            C.pendingMoney = C.pendingMoney or {}
            table.insert(C.pendingMoney, { r = r, pp = (ctx == "pickpocket") })
          elseif ctx == "pickpocket" then r.ppCoin = r.ppCoin + qty; attr("coin", qty, ctx)
          else r.coin = r.coin + qty; r.coinLoots = r.coinLoots + 1; attr("coin", qty, ctx, oid) end
        elseif id then
          -- a reopened window shows the same items again: count only what's new
          local ck = tostring(guid) .. ctx .. id
          local before = credited[ck] or 0
          if qty > before then credited[ck] = qty end
          qty = qty - before
        end
        if kind ~= 2 and id and qty > 0 then
          if ctx == "pickpocket" then addItem(r.ppItems, id, qty)
          elseif ctx == "skin" then addItem(r.skinItems, id, qty)
            if C.session then C.session.skinItems = C.session.skinItems or {}; addItem(C.session.skinItems, id, qty) end
          else addItem(r.items, id, qty) end
          attr(id, qty, ctx == "pickpocket" and "pick" or ctx, oid)
        end
      elseif type(guid) == "string" and guid:find("^Item%-") and C.NoteBoxLoot then
        -- a disenchant (gear in, materials out) goes to the trade log; otherwise an
        -- opened container (junkbox, lockbox): learn what it holds
        local de = C.NoteDELoot and C.NoteDELoot(guid, kind, id, qty)
        if not de then C.NoteBoxLoot(guid, key, kind, id, qty) end
        if id then attr(id, qty, de and "de" or "box", nil, de and true or nil) end
      elseif okind == "object" then
        local n = C.db.nodes[oid] or { n = 0, items = {} }
        C.db.nodes[oid] = n
        if not seenLoot[key] then
          seenLoot[key] = true; n.n = n.n + 1
          if C.session then C.session.nodes = (C.session.nodes or 0) + 1 end
          -- its name: the tooltip of what you just clicked (chest, vein, herb)
          local nm = GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
          if type(nm) == "string" and not (issecretvalue and issecretvalue(nm)) and nm ~= "" then n.name = nm end
          C.SessionLog("opened", oid, n.name)
        end
        if id then
          addItem(n.items, id, qty); attr(id, qty, "node")
          if C.session then C.session.gather = C.session.gather or {}; addItem(C.session.gather, id, qty) end
        end
      elseif id then
        attr(id, qty, "other")
      end
      end
    end
  end
end
-- read at "ready" (the moment fast-loot addons act) or "opened", whichever has the loot
local function onLootShown()
  lootOpen = true
  if windowRead or not GetNumLootItems or GetNumLootItems() == 0 then return end
  windowRead = true
  local ok, err = pcall(readLoot)
  if not ok then C.LogError("readLoot", err) end
end
C.On("LOOT_READY", onLootShown)
C.On("LOOT_OPENED", onLootShown)
C.On("LOOT_CLOSED", function() lootOpen = false; windowRead = false; lootContext = nil end)

-- Your loot from the chat line, when the window wasn't read: which mob? Only a
-- guess Kina can stand behind: every one of your recent unlooted kills is the
-- same kind of mob. Otherwise the loot still counts for the farm, but not for any
-- mob's drop rates.
local function guessMob(ctx, now)
  local npc, pick
  for i = #recentKills, 1, -1 do
    local k = recentKills[i]
    if now - k.t > 120 then break end
    local open
    if ctx == "skin" then open = k.looted and not k.skinned else open = not k.looted end
    if open then
      if npc and npc ~= k.npc then return nil end
      npc, pick = k.npc, k
    end
  end
  return npc, pick
end
local function chatSource(now)
  if burst and now - burst.t < 0.5 then burst.t = now; return burst end
  local b = { ctx = "corpse", t = now }
  if C.PocketLootActive and C.PocketLootActive() then b.ctx = "pick"
  elseif now - skinCastAt < 5 then b.ctx = "skin"
  elseif now - (castAt.de or -99) < 5 then b.ctx = "de"
  elseif now - (castAt.node or -99) < 5 then b.ctx = "node"
  elseif now - (castAt.fish or -99) < 5 then b.ctx = "fish" end
  if b.ctx == "corpse" or b.ctx == "skin" then
    local npc, k = guessMob(b.ctx, now)
    if k then
      b.npc = npc
      local r = npcRecord(npc)
      if b.ctx == "corpse" then k.looted = true; r.looted = r.looted + 1
      else k.skinned = true; r.skins = r.skins + 1; if C.session then C.session.skins = (C.session.skins or 0) + 1 end end
    end
  end
  burst = b
  return b
end
-- the window's record of this item, if it read one
local function takeWindow(id, now)
  local found
  for i = #winAttr, 1, -1 do
    local a = winAttr[i]
    if now - a.t > 10 then table.remove(winAttr, i)
    elseif a.id == id and not found then found = a end
  end
  if found then
    for i, a in ipairs(winAttr) do if a == found then table.remove(winAttr, i); break end end
  end
  return found
end
local function suffixOf(id, link)
  local full = link and link:match("%[(.-)%]")
  local base = C.db.items and C.db.items[id] and C.db.items[id].name
  if full and base and full ~= base and full:sub(1, #base) == base then return full:sub(#base + 2) end
  if full and not base then return full:match(" (of the %a[%a ]*)$") end
end
-- one of YOUR loot lines: counts for the farm (any kind of farm) and for drop data
local function ownLoot(link, n)
  local id = C.ItemIDFromLink(link)
  if not id then return end
  local now = GetTime and GetTime() or 0
  local suffix = suffixOf(id, link)
  local a = takeWindow(id, now)
  if a then
    if not a.no then sessionItem(id, n, a.ctx, a.npc, suffix) end
    return
  end
  local b = chatSource(now)
  if b.ctx == "de" then return end -- a disenchant: the gear was already counted
  if b.npc then
    local r = npcRecord(b.npc)
    if b.ctx == "skin" then
      addItem(r.skinItems, id, n)
      if C.session then C.session.skinItems = C.session.skinItems or {}; addItem(C.session.skinItems, id, n) end
    else addItem(r.items, id, n) end
  end
  sessionItem(id, n, (b.ctx == "corpse" and not b.npc) and "unknown" or b.ctx, b.npc, suffix)
end
-- your coin from the chat line ("You loot 12 Copper"): the mob's coin record
local function ownCoin(v)
  local now = GetTime and GetTime() or 0
  if not takeWindow("coin", now) then
    local b = chatSource(now)
    if b.npc and b.ctx == "corpse" then local r = npcRecord(b.npc); r.coin = r.coin + v; r.coinLoots = r.coinLoots + 1 end
  end
  -- the farm's coin: counted here, once (the money change it causes is then ignored)
  local s = C.session
  if not (s and s.money) then return end
  C.coinBudget = (C.coinBudget or 0) + v
  C.After(5, function() C.coinBudget = math.max(0, (C.coinBudget or 0) - v) end)
  C.FileLootCoin(s, v)
  s.last = C.Now()
end
function C.FileLootCoin(s, v)
  if s.paused then
    s.excl = s.excl or { coin = 0, items = {} }
    s.excl.coin = (s.excl.coin or 0) + v
    C.SessionLog("excluded coin", v)
  elseif C.PocketLootActive and C.PocketLootActive() then
    s.money.pickpocket = (s.money.pickpocket or 0) + v
    C.SessionLog("gold", v, "pickpocket")
  else
    s.money.coin = (s.money.coin or 0) + v
    C.SessionLog("gold", v, "coin")
  end
end

-- Opened junkboxes: per box type, how many opened, coin and items found.
local boxSeen = {}
function C.NoteBoxLoot(guid, key, kind, id, qty)
  local boxID
  if C_Item and C_Item.GetItemIDByGUID then local ok, v = pcall(C_Item.GetItemIDByGUID, guid); if ok then boxID = v end end
  if not boxID then return end
  local isBox = false
  for _, j in ipairs(C.Data.junkboxes or {}) do if j.id == boxID then isBox = true end end
  if not isBox then return end
  C.db.boxes = C.db.boxes or {}
  local b = C.db.boxes[boxID] or { n = 0, coin = 0, items = {} }
  C.db.boxes[boxID] = b
  if not boxSeen[guid] then boxSeen[guid] = true; b.n = b.n + 1 end
  if kind == 2 and qty and qty > 0 then b.coin = b.coin + qty
  elseif id then b.items[id] = (b.items[id] or 0) + (qty or 1) end
end

------------------------------------------------------------------ money by source
C.On("MERCHANT_SHOW", function() merchantOpen = true end)
C.On("MERCHANT_CLOSED", function() merchantOpen = false end)
C.On("MAIL_SHOW", function() mailOpen = true end)
C.On("MAIL_CLOSED", function() mailOpen = false end)
C.On("PLAYER_MONEY", function()
  local now = GetMoney()
  local delta = now - (lastMoney or now)
  lastMoney = now
  if lootOpen and delta > 0 and C.pendingMoney and #C.pendingMoney > 0 then
    local share = delta / #C.pendingMoney
    for _, p in ipairs(C.pendingMoney) do
      if p.pp then p.r.ppCoin = p.r.ppCoin + share else p.r.coin = p.r.coin + share; p.r.coinLoots = p.r.coinLoots + 1 end
    end
    C.pendingMoney = nil
  end
  local s = C.session
  if not s or delta == 0 then return end
  -- P1.0.2: looted coin is counted ONLY from its chat line ("You loot 12 Copper",
  -- "Your share of the loot is ..."), exactly once. Money changes are just a record of
  -- everything else (vendor, mail, spending), and never count toward the farm.
  local cat
  if merchantOpen and C.MerchantIsOpen() ~= false then cat = (delta > 0) and "vendor" or "spent"
  elseif mailOpen and C.MailIsOpen() ~= false then cat = (delta > 0) and "mail" or "spent"
  elseif delta < 0 then cat = "spent" end
  if cat then
    s.money[cat] = (s.money[cat] or 0) + delta
    C.SessionLog("gold", delta, cat)
    return
  end
  -- money in with no vendor or mailbox: most likely looted coin. Wait a moment for its
  -- chat line; whatever no chat line explains is logged as other gold.
  C.pendingIn = C.pendingIn or {}
  table.insert(C.pendingIn, delta)
  C.After(1.5, function()
    local s2 = C.session
    local list = C.pendingIn or {}
    C.pendingIn = {}
    for _, d in ipairs(list) do
      local b = C.coinBudget or 0
      local take = math.min(b, d)
      C.coinBudget = b - take
      local rest = d - take
      if rest > 0 and s2 and s2.money then
        s2.money.other = (s2.money.other or 0) + rest
        C.SessionLog("gold", rest, "other")
      end
    end
  end)
end)
C.On("PLAYER_ENTERING_WORLD", function() lastMoney = GetMoney and GetMoney() or 0 end)
-- 1.0.2 (Taylor: "Net Gained which includes quest rewards"): gold from a quest turned in
-- while a farm runs. It's the farm's "gained" number only: never part of a split.
C.On("QUEST_TURNED_IN", function(_, _, _, money)
  money = C.Plain and C.Plain(money) or money
  local s = C.session
  if not s or s.paused or type(money) ~= "number" or money <= 0 or money > 1e9 then return end
  s.money = s.money or {}
  s.money.quest = (s.money.quest or 0) + money
end)

------------------------------------------------------------------ sessions
-- A farm session is saved as it runs (C.db.activeSession), so a /reload or a
-- disconnect does not lose it; the gap is trimmed if you were away too long.
local SOUND = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\"
-- One fanfare at a time: a new click stops the one still playing and starts over,
-- so rapid Start/Stop clicks never stack into a louder and louder mess.
-- 1.2.9: every Kina sound is cut from the Kina theme (Taylor's Theme A, locked Nov 6).
-- One at a time (a new one stops the last), through the game's Sound Effects volume.
local cueHandle
local CUES = { start = "farm_start", stop = "farm_stop", paid = "paid", settled = "settled",
  level = "level_up", standing = "standing_up", warning = "warning", repdown = "rep_down" }
-- 1.4.5: the Sound switch gives a plain click, not the farm-start fanfare
function C.PlayClick()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end
-- 1.5.4 (Taylor): a volume slider. The game can't play one addon's sounds quieter, so
-- every Kina sound ships at 100/75/50/25%; the slider picks the file. 0 = muted.
function C.Volume()
  local v = C.settings.kinaVolume
  if v == nil then v = (C.settings.farmSound == false) and 0 or 4 end
  return math.max(0, math.min(4, math.floor(v)))
end
function C.SetVolume(v)
  v = math.max(0, math.min(4, math.floor(v or 4)))
  C.settings.kinaVolume = v
  C.settings.farmSound = v > 0
  if C.Toast and C.Toast.ThemeStop and v == 0 then pcall(C.Toast.ThemeStop) end
end
local VSUF = { "_25", "_50", "_75", "" }
function C.SoundFile(base) return SOUND .. base .. (VSUF[C.Volume()] or "") .. ".ogg" end
-- 0.9.5: when the farm last saw a kill: mine, or (in a shared farm) anyone's in the log
function C.LastKillAt(s)
  local lk = s.lastKill or s.last or s.start or C.Now()
  local sy = s.sync
  if sy and sy.chain and sy.startAt then
    for i = sy.head or #sy.chain, 1, -1 do
      local ev = sy.chain[i]
      if ev and ev.kind == "K" and ev.t then lk = math.max(lk, sy.startAt + ev.t); break end
    end
  end
  return lk
end
-- 0.9.5: shared farms that 0.9.4 and older stopped an hour after they STARTED (a kill
-- didn't keep them alive) get their real end back from their log, once, and their XP
local function repairIdleStops()
  for i = 1, math.min(10, #(C.db.sessions or {})) do
    local s = C.db.sessions[i]
    if s and s.why == "no kills for an hour" and s.sync and s.sync.chain and not s.idleFixed and s.stop and C.Now() - s.stop < 3 * 86400 then
      s.idleFixed = true
      local trueEnd = C.LastKillAt(s) + 60
      if trueEnd > s.stop + 120 and trueEnd <= C.Now() then
        s.stop = trueEnd
        local ok, sum = pcall(C.SessionSummary, s)
        if ok and sum then s.result = sum end
        local secs = math.floor(s.stop - s.start - (s.pausedSecs or 0))
        if C.Log then C.Log("farmfix", s.sync.sid or "", secs) end
        C.Print(string.format("|cffffc54aFixed:|r your %s farm stopped itself by mistake; it now counts as %d minutes.", s.label or "group", math.floor(secs / 60)))
      end
    end
  end
end
C.RepairIdleStops = repairIdleStops
C.On("INIT", function() if C.After then C.After(12, function() pcall(repairIdleStops) end) end end)
function C.PlayCue(which)
  if C.Volume() == 0 or not PlaySoundFile then return end
  if cueHandle and StopSound then pcall(StopSound, cueHandle, 200) end
  cueHandle = nil
  local file = (CUES[which] or "farm_start") .. (VSUF[C.Volume()] or "") .. ".ogg"
  local ok, willPlay, handle = pcall(PlaySoundFile, SOUND .. file, "SFX")
  if ok and willPlay then cueHandle = handle end
end

-- What was looted while paused (kept out of the farm's Net).
function C.ExcludedItemValue(s)
  local v = 0
  for id, n in pairs(s and s.excl and s.excl.items or {}) do v = v + (C.FarmValue and C.FarmValue(id) or 0) * n end
  return v
end

-- Seconds the farm has run, not counting pauses.
function C.SessionSecs(s)
  s = s or C.session
  if not s then return 0 end
  local now = s.stop or C.Now()
  local paused = (s.pausedSecs or 0) + ((s.paused and not s.stop) and (now - (s.pauseAt or now)) or 0)
  return math.max(0, now - s.start - paused)
end
function C.PauseSession(fromParty, want)
  local s = C.session
  if not s then return end
  if want == nil then want = not s.paused end
  if want == (s.paused and true or false) then return end
  if want then s.paused, s.pauseAt = true, C.Now()
  else s.pausedSecs = (s.pausedSecs or 0) + (C.Now() - (s.pauseAt or C.Now())); s.paused, s.pauseAt = nil, nil; s.resumeAt = C.Now() end
  C.SessionLog(want and "pause" or "resume")
  C.Print(want and "farm paused: the clock stops and nothing you kill or loot counts until you resume." or "farm resumed.")
  if s.sync then
    if not fromParty and C.FarmSync then C.FarmSync.Observe("P", want and "1" or "0") end
  elseif not fromParty and C.Share and C.Share.SendFarmCmd then pcall(C.Share.SendFarmCmd, want and "pause" or "resume") end
  if C.OnSessionChange then C.OnSessionChange() end
end

function C.StartSession(label, fromParty, campKey)
  if C.Toast and C.Toast.ThemeStop then pcall(C.Toast.ThemeStop) end -- 1.5.2: a new farm ends the theme
  -- 1.0.2: the group already has a shared farm running: join it, don't start a second one
  if not fromParty and not C.session and C.FarmSync and C.FarmSync.JoinRunning and C.FarmSync.JoinRunning() then return end
  if C.Rules and C.Rules.Decay then pcall(C.Rules.Decay) end -- 1.5.4: idle weeks
  if C.session then C.StopSession() end
  lastMoney = GetMoney()
  local now = C.Now()
  C.session = { start = now, last = now, label = label or (GetZoneText and GetZoneText()) or "session",
    startMoney = lastMoney, startCounts = C.Holdings(true), posted = {}, party = C.GroupMates and C.GroupMates() or {}, kills = 0, byNpc = {}, items = {}, money = {}, zone = GetZoneText and GetZoneText(),
    limit = (C.settings.farmPreset or 0) > 0 and C.settings.farmPreset or nil,
    char = C.charKey, class = UnitClass and select(2, UnitClass("player")) or nil } -- 1.5.2: which of my characters farmed
  C.db.activeSession = C.session
  seenLoot = {}
  C.PlayCue("start")
  C.SessionLog("start", lastMoney)
  pcall(C.TrackLevels, C.session)
  C.session.g = { coin = 0, loot = {} }
  C.session.camp = campKey
  C.session.byParty = fromParty and true or nil
  C.Print("farm started: " .. C.session.label .. (fromParty and " (your group started it)" or ""))
  if C.Consumables then pcall(function() C.session.cons = C.Consumables() end) end
  -- with other Kina users in the group: a shared farm (one log, same numbers everywhere)
  local synced = not fromParty and C.FarmSync and C.FarmSync.Begin(C.session, C.session.label, campKey)
  if not fromParty and not synced and C.Share and C.Share.SendFarmCmd then pcall(C.Share.SendFarmCmd, "start", C.session.label, campKey) end
  if C.OnSessionChange then C.OnSessionChange() end
end

-- Value of everything looted this session at today's prices (copper): the same
-- price the Farms tab uses (thin markets fall back to a safe price).
local function farmValue(id) return C.FarmValue and C.FarmValue(id) or select(2, C.BestRoute(id, 1)) or 0 end
function C.SessionItemValue(s, list)
  local total = 0
  local rolls = not list and s.sx or {}
  for id, n in pairs(list or s.items) do
    -- rolled gear ("of the Eagle") at its own roll's price
    for sfx, k in pairs(rolls[id] or {}) do
      k = math.min(k, n); n = n - k
      total = total + ((C.FarmValue and C.FarmValue(id, sfx)) or farmValue(id) or 0) * k
    end
    total = total + (farmValue(id) or 0) * n
  end
  return total
end

------------------------------------------------------------------ what you own
-- Bags + bank (remembered from your last bank visit) + items you listed on the AH
-- during the farm (still yours until they sell). Worn gear is left out. A farm's
-- result is the gold you gained plus the CHANGE in these counts at today's prices,
-- so a new scan never moves the result by itself, and banking or posting a drop
-- doesn't count as losing it.
local BANK_BAGS = C.BankBags()
local function countBags(list, out)
  local CT = C_Container
  if not (CT and CT.GetContainerNumSlots) then return out end
  for _, bag in ipairs(list) do
    local ok, slots = pcall(CT.GetContainerNumSlots, bag)
    for slot = 1, (ok and slots) or 0 do
      if CT.GetContainerItemInfo then
        local info = CT.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
          out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
          -- 1.0.2: the game itself says which items no merchant will buy
          if C.NoteNoValue and type(info.hasNoValue) == "boolean" then C.NoteNoValue(info.itemID, info.hasNoValue) end
        end
      elseif GetContainerItemInfo then -- older clients: the plain function (count 2nd, id 10th)
        local _, n, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        if id then out[id] = (out[id] or 0) + (n or 1) end
      end
    end
  end
  return out
end
local bankOpen = false
local function saveBank() if bankOpen and C.char then C.char.bank = countBags(BANK_BAGS, {}) end end
C.On("BANKFRAME_OPENED", function() bankOpen = true; saveBank() end)
-- (not read again on close: the bank's contents may already be gone, which would save it
-- as empty; it was saved on open and after every change)
C.On("BANKFRAME_CLOSED", function() bankOpen = false end)
function C.BankOpen() return bankOpen end
C.On("PLAYERBANKSLOTS_CHANGED", saveBank)
C.On("BAG_UPDATE_DELAYED", function() if bankOpen then saveBank() end end)
local holdCache, holdAt = nil, -100
function C.Holdings(fresh)
  local now = GetTime and GetTime() or 0
  if holdCache and not fresh and now - holdAt < 3 then return holdCache end
  local out = countBags(C.PlayerBags(), {})
  for id, n in pairs(C.char and C.char.bank or {}) do out[id] = (out[id] or 0) + n end
  for id, n in pairs(C.session and C.session.posted or {}) do if n > 0 then out[id] = (out[id] or 0) + n end end
  holdCache, holdAt = out, now
  return out
end
-- value of the change between two counts, at today's prices
local function changeValue(from, to)
  local v = 0
  for id, n in pairs(to) do local d = n - (from[id] or 0); if d ~= 0 then v = v + d * farmValue(id) end end
  for id, n in pairs(from) do if to[id] == nil and n ~= 0 then v = v - n * farmValue(id) end end
  return v
end
-- every item whose count changed: { id, from, to, each, value }, biggest first
function C.ItemChanges(from, to)
  local out, seen = {}, {}
  local function add(id)
    if seen[id] then return end
    seen[id] = true
    local a, b = from[id] or 0, to[id] or 0
    if a ~= b then local each = farmValue(id); out[#out + 1] = { id, a, b, each, (b - a) * each } end
  end
  for id in pairs(to) do add(id) end
  for id in pairs(from) do add(id) end
  table.sort(out, function(x, y) return math.abs(x[5]) > math.abs(y[5]) end)
  return out
end

-- the Ledger tells the farm about AH listings (still yours) and their sale/expiry
function C.SessionPosted(id, qty)
  local s = C.session
  if not (s and s.posted and id) then return end
  s.posted[id] = math.max(0, (s.posted[id] or 0) + qty)
  C.SessionLog(qty > 0 and "post" or "listing gone", id, qty > 0 and qty or nil)
end

-- Everything in your bags at today's prices (what Kina would get for it), cached 5s.
local bagCache, bagAt = 0, -100
function C.BagWorth(fresh)
  local now = GetTime and GetTime() or 0
  if fresh or now - bagAt > 5 then
    local ok, rows = pcall(C.AdviseBags)
    local t = 0
    if ok and type(rows) == "table" then for _, r in ipairs(rows) do t = t + (r.total or 0) end end
    bagCache, bagAt = t, now
  end
  return bagCache
end

-- Total = how much richer you are than when you pressed Start: gold now - gold
-- then, plus bag value now - bag value then. Money spent on the AH (flipping,
-- repairs, training) counts against the session; items bought count at their value.
-- P1.0.2: what a farm made = coin you looted + items you looted (at today's farm
-- price, rolls priced as rolls) - consumables you used. Buying, selling, crafting, the
-- bank and the mailbox never move it.
local function myUsedValue(s)
  local me = (UnitName and UnitName("player") or ""):match("^([^%-]+)")
  local v = 0
  for who, list in pairs(s.g and s.g.used or {}) do
    if not me or who == me then for id, n in pairs(list) do v = v + ((C.FarmValue and C.FarmValue(id)) or 0) * n end end
  end
  return v
end
-- 1.0.10: a running shared farm's kills live in the shared log (s.kills fills in at Stop)
local function farmKills(s)
  if s.sync and not s.stop and C.FarmSync then
    local ok, t = pcall(C.FarmSync.Totals, s.sync)
    if ok and t then return math.max(s.kills or 0, t.kills or 0) end
  end
  return s.kills
end
function C.SessionSummary(s)
  s = s or C.session
  if not s then return nil end
  local secs0 = math.max(1, C.SessionSecs(s))
  if s.income or not s.stop then
    if s.income and s.endWorth then
      return { secs = secs0, cash = s.endGold, items = s.endItems, used = s.endUsed or 0, total = s.endWorth, perHour = s.endWorth * 3600 / secs0,
        coin = s.money.coin or 0, pickpocket = s.money.pickpocket or 0, vendor = s.money.vendor or 0, spent = s.money.spent or 0, kills = farmKills(s), net = true, income = true }
    end
    local coin = (s.money.coin or 0) + (s.money.pickpocket or 0)
    local items = C.SessionItemValue(s)
    local used = myUsedValue(s)
    local total = coin + items - used
    return { secs = secs0, cash = coin, items = items, used = used, total = total, perHour = total * 3600 / secs0,
      coin = s.money.coin or 0, pickpocket = s.money.pickpocket or 0, vendor = s.money.vendor or 0, spent = s.money.spent or 0, kills = farmKills(s), net = true, income = true }
  end
  local secs = secs0
  local cash = (s.money.coin or 0) + (s.money.pickpocket or 0) + (s.money.vendor or 0) + (s.money.mail or 0) + (s.money.other or 0)
  local spent = s.money.spent or 0 -- negative
  if s.endGold then
    return { secs = secs, cash = s.endGold, items = s.endItems, total = s.endWorth, perHour = s.endWorth * 3600 / secs,
      coin = s.money.coin or 0, pickpocket = s.money.pickpocket or 0, vendor = s.money.vendor or 0, spent = spent, kills = farmKills(s), net = true }
  elseif s.startCounts and s.startMoney and GetMoney then
    local gold = GetMoney() - s.startMoney - (s.excl and s.excl.coin or 0) - (s.money.mail or 0)
    local items = changeValue(s.startCounts, C.Holdings()) - C.ExcludedItemValue(s)
    return { secs = secs, cash = gold, items = items, total = gold + items, perHour = (gold + items) * 3600 / secs,
      coin = s.money.coin or 0, pickpocket = s.money.pickpocket or 0, vendor = s.money.vendor or 0, spent = spent, kills = farmKills(s), net = true }
  end
  local items = C.SessionItemValue(s)
  local total
  if s.endWorth then total = s.endWorth
  elseif s.startBag and s.startMoney and GetMoney and not s.stop then
    total = (GetMoney() - s.startMoney) + (C.BagWorth() - s.startBag)
  else total = cash + spent + items end
  return { secs = secs, cash = cash + spent, items = total - (cash + spent), total = total, perHour = total * 3600 / secs,
    coin = s.money.coin or 0, pickpocket = s.money.pickpocket or 0, vendor = s.money.vendor or 0,
    spent = spent, kills = farmKills(s), net = s.startBag ~= nil }
end

-- at: when it really ended (idle and timer stops end it in the past); why: shown in history
function C.StopSession(at, why, silent, fromParty)
  local s = C.session
  if not s then return end
  -- shared farm: ask the leader to close the log; everyone's farm ends when it does
  if s.sync and not s.sync.closed and not fromParty and C.FarmSync and C.FarmSync.Active() then
    -- 1.1.1: apart most of the farm (different zones)? ask before splitting
    local apart, together = s.apartTicks or 0, s.togetherTicks or 0
    local noSplitYet = not (C.FarmSync.Totals(s.sync) or {}).noSplit
    if not s.apartAsked and noSplitYet and apart > together and apart >= 6 and StaticPopupDialogs and StaticPopup_Show then
      StaticPopupDialogs["KINA_APART"] = StaticPopupDialogs["KINA_APART"] or {
        text = "You and your group were in different zones for most of this farm.\n\nSplit the loot anyway?",
        button1 = "Split it", button2 = "Don't split", timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
        OnAccept = function() local x = C.session; if x then x.apartAsked = true; C.StopSession() end end,
        OnCancel = function(_, _, why)
          local x = C.session
          if not x or why == "override" then return end
          x.apartAsked = true
          if C.FarmSync then C.FarmSync.Observe("N", "1") end
          C.StopSession()
        end }
      C.ShowPopup("KINA_APART")
      return
    end
    if C.FlushUse then pcall(C.FlushUse, true) end
    C.FarmSync.Observe("S", why == "no kills for an hour" and "idle" or nil)
    C.Print("stopping the group farm: filing the last loot (about 8 seconds)...")
    return
  end
  if s.sync and C.FarmSync then
    local t = C.FarmSync.Totals(s.sync)
    local secs = C.FarmSync.Active() and C.FarmSync.Node():Elapsed() or 0
    s.gview = { secs = secs, net = t.net, coin = t.coin, items = t.items, used = t.used, kills = t.kills }
    local by = {}
    for who, v in pairs(t.byLooter) do by[who] = math.floor(v + 0.5) end
    local total, each, transfers = C.FarmSync.Split(by)
    if t.noSplit then transfers = {}; s.noSplit = true end
    if t.nVotes and not t.noSplit then
      C.Print("|cffffc54a\"Don't split\" only counts when it comes from the players who'd be paid.|r The split stands; they can forgive what they're owed.")
    end
    -- 0.9.1 (security): the log has loot in my name I never looted: record no debts
    if (s.sync.forged or 0) > 0 then
      transfers = {}; s.noSplit = true; s.forged = true
      C.Print("|cffff4030This farm's log was changed by someone else|r (it has loot under your name you never looted): Kina records no debts for you from it.")
    end
    -- 0.9.1 (security): the leader stamps the prices; if mine disagree a lot, say so
    if not t.noSplit and C.SplitValue and s.sync.leader ~= C.FarmSync.First(UnitName and UnitName("player")) then
      local okm, mt = pcall(C.FarmSync.Totals, s.sync, function(id, sfx) return (C.SplitValue(id, sfx)) or 0 end)
      if okm and mt and math.abs((mt.items or 0) - (t.items or 0)) > math.max(10000, 0.25 * math.max(mt.items or 0, t.items or 0)) then
        C.Print(string.format("|cffffc54aHeads up:|r %s's prices put this farm's loot at %s; your prices say %s. Right-click a farm log item to dispute it, or scan the AH when asked.",
          tostring(s.sync.leader), C.Money(t.items or 0), C.Money(mt.items or 0)))
      end
    end
    s.split = { total = total, each = each, incomes = by, transfers = transfers, loot = true }
    s.settled, s.gsplitShown = true, true
    -- 0.9.0 (Taylor): the split waits for fresh AH scans (or everyone skipping)
    if #transfers > 0 and C.PriceHold and C.PriceHold.Begin then pcall(C.PriceHold.Begin, s) end
    s.kills = math.max(s.kills or 0, t.kills)
    if C.RecordFloors then pcall(C.RecordFloors, s) end
    C.Print(string.format("|cffffc54aFarm split|r (%s): the group looted %s, %s each (from the shared log, the same on every widget).",
      s.label or "farm", C.Money(total), C.Money(each)))
    if C.Admin() then
      for who, v in pairs(by) do C.Print(string.format("   %s: %s looted", who, C.Money(v))) end
    end
    if #transfers == 0 then C.Print("   Everyone is even: nobody owes anything.") end
    for _, tr in ipairs(transfers) do C.Print(string.format("   |cff7CFC00%s pays %s %s|r", tr.from, tr.to, C.Money(tr.amt))) end
  end
  if s.paused then s.pausedSecs = (s.pausedSecs or 0) + (C.Now() - (s.pauseAt or C.Now())); s.paused = nil end
  -- the group's numbers as the widgets showed them, so every stopped widget shows the same
  local okv, gv = pcall(function() return C.FarmView and C.FarmView() end)
  if okv and gv then s.gview = { secs = gv.secs, net = gv.net, coin = gv.coin, items = gv.items, used = gv.used, kills = gv.kills } end
  -- the leader freezes what each player looted (its prices) and sends it, so every Kina splits the same
  if s.g and C.FarmLeader and C.GroupSize and C.GroupSize() > 1 and not (C.TrackOnly and C.TrackOnly()) then
    local leader, lead = C.FarmLeader()
    if lead then
      local gf = C.GroupFarm(s)
      local by = {}
      for who, v in pairs(gf and gf.byLooter or {}) do by[who] = math.floor(v + 0.5) end
      s.gsplit = { by = by, from = leader, mine = true }
      if C.Share and C.Share.SendSplit then
        pcall(C.Share.SendSplit, by)
        -- sent again a little later in case a copy is lost (duplicates are ignored)
        if C.After then for _, d in ipairs({ 6, 20 }) do C.After(d, function() pcall(C.Share.SendSplit, by) end) end end
      end
    end
  end
  if not fromParty and C.Share and C.Share.SendFarmCmd then pcall(C.Share.SendFarmCmd, "stop") end
  -- (protected: a bad item record must never leave a farm running after Stop)
  local okEnd, endErr = pcall(function()
  -- P1.0.2: the farm's result is what you looted (see SessionSummary)
  do
    local sumNow = C.SessionSummary(s)
    s.income = true
    s.endGold, s.endItems, s.endUsed, s.endWorth = sumNow.cash, sumNow.items, sumNow.used, sumNow.total
  end
  if s.startCounts and s.startMoney and GetMoney then
    -- gold from the mailbox (AH sales, gifts) isn't farm income (kept apart; a party's
    -- coin share arrives with no window open, so that one still counts)
    local now = C.Holdings(true)
    s.itemChanges = C.ItemChanges(s.startCounts, now) -- kept for the farm's log (bags before/after, for reference)
    C.SessionLog("stop", GetMoney())
    s.startCounts, s.posted = nil, nil -- keep saved data small
  end
  end)
  if not okEnd then C.Print("farm stop: couldn't total your items (" .. tostring(endErr) .. "); the farm still ended. Tell Claude.") end
  s.stop = math.max(s.start + 1, math.min(at or C.Now(), C.Now()))
  s.why = why or "stopped"
  local okSum, sum = pcall(C.SessionSummary, s)
  if not okSum then C.Print("farm stop: summary failed (" .. tostring(sum) .. "). Tell Claude."); sum = { secs = 0, total = 0, perHour = 0, kills = s.kills or 0, cash = 0, items = 0 } end
  s.result = sum
  table.insert(C.db.sessions, 1, s)
  while #C.db.sessions > 50 do table.remove(C.db.sessions) end
  C.session = nil
  C.db.activeSession = nil
  if C.FarmEnded then pcall(C.FarmEnded, s) end
  if not silent and not (C.Toast and C.Toast.ThemeAtFarmEnd and C.Toast.ThemeAtFarmEnd()) then C.PlayCue("stop") end
  -- 1.5.0: a qualifying group farm just ended: remind about vouching
  if not silent and s.sync then
    C.After(4, function()
      if C.Vouch and C.Vouch.ShowPrompt then pcall(C.Vouch.ShowPrompt) end -- 1.5.0: commendation window
    end)
  end
  C.Print(string.format("farm ended (%s): %s total (%s/hour), %d kills.", s.why, C.Money(sum.total), C.Money(sum.perHour), sum.kills))
  if C.OnSessionChange then C.OnSessionChange() end
end

-- Timer and idle limits, checked every few seconds by the farm widget's clock.
-- 1.0.10: the lowest and highest character level seen in the farm's group (you and
-- everyone grouped with you, Kina or not). Anyone under 10 at any point: the farm gives
-- no Kina progression (money still works). The highest level sets the gold a farm needs.
C.PROG_MIN_LEVEL = 10
function C.TrackLevels(s)
  s = s or C.session
  if not (s and UnitLevel) then return end
  local units = { "player" }
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if IsInGroup and IsInGroup() then
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and n or (n - 1) do units[#units + 1] = raid and ("raid" .. i) or ("party" .. i) end
  end
  for _, u in ipairs(units) do
    local ok, lv = pcall(UnitLevel, u)
    if ok and type(lv) == "number" and lv > 0 then
      if not s.minLvl or lv < s.minLvl then s.minLvl = lv end
      if not s.maxLvl or lv > s.maxLvl then s.maxLvl = lv end
    end
  end
  s.groupN = math.max(s.groupN or 1, (IsInGroup and IsInGroup()) and math.max(1, n) or 1)
  -- 1.1.1: were you in the same zone as your group? (asked about at Stop when mostly apart)
  if IsInGroup and IsInGroup() and GetRaidRosterInfo and not s.paused then
    local mine = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText())
    local apart = false
    for i = 1, n do
      local ok, name, _, _, _, _, _, zone, online = pcall(GetRaidRosterInfo, i)
      if ok and name and zone and online ~= false and mine and zone ~= "" and zone ~= mine then apart = true end
    end
    if apart then s.apartTicks = (s.apartTicks or 0) + 1 else s.togetherTicks = (s.togetherTicks or 0) + 1 end
  end
  if s.minLvl and s.minLvl < C.PROG_MIN_LEVEL and not s.lowNoted then
    s.lowNoted = true
    local key = (UnitName and UnitName("player") or "?")
    C.settings.lowLevelSeen = C.settings.lowLevelSeen or {}
    if not C.settings.lowLevelSeen[key] then
      C.settings.lowLevelSeen[key] = true
      C.Print("|cffffc54aNote:|r someone in this farm is under level 10, so it won't give Kina XP or standing. The gold tracking and the split still work. (Shown once per character.)")
    end
  end
end
function C.SessionTick()
  local s = C.session
  if not s then return end
  pcall(C.TrackLevels, s)
  if s.sync and C.FlushUse then pcall(C.FlushUse) end
  local now = C.Now()
  if s.limit and C.SessionSecs(s) >= s.limit then
    C.StopSession(nil, "timer done"); return
  end
  -- 1.5.4 (Taylor): an hour after the last kill (anyone's, in a group farm) the farm
  -- ends, as of that last kill, so the empty hour never counts
  -- 0.9.13: the hour counts from a resume too (a long pause stopped the farm the moment it resumed)
  local lk = math.max(C.LastKillAt(s), s.resumeAt or 0)
  -- 0.9.14 (Taylor): a solo farm never ends by itself; only shared farms stop when idle
  if s.sync and not s.paused and now - lk >= 3600 then C.StopSession(lk + 60, "no kills for an hour"); return end
  -- group farm: the leader tells everyone the group's numbers every 5 seconds
  if s.g and C.GroupSize and C.GroupSize() > 1 and C.FarmLeader then
    local _, lead = C.FarmLeader()
    if lead and C.Share and C.Share.SendGroupView then
      local gf = C.GroupFarm(s)
      pcall(C.Share.SendGroupView, { secs = math.floor(C.SessionSecs(s)), net = gf.net, coin = gf.coin, items = gf.items, used = gf.used, kills = s.kills, paused = s.paused })
      -- the running split, when it changed (or every 30 s)
      local sig = ""
      for who, v in pairs(gf.byLooter or {}) do sig = sig .. who .. math.floor(v) end
      local now = C.Now()
      if C.Share.SendLiveSplit and (sig ~= s.liveSig or now - (s.liveAt or 0) >= 30) then
        s.liveSig, s.liveAt = sig, now
        pcall(C.Share.SendLiveSplit, gf.byLooter or {})
      end
    end
  end
end

-- The numbers a farm widget shows: in a group, the group's (identical on every
-- widget); solo, your own. Returns view, groupMode, leaderName.
function C.FarmView()
  local s = C.session
  if not s then return nil end
  if s.sync and C.FarmSync then
    local v, leader = C.FarmSync.View()
    if v then return v, true, leader end
    return nil, true, s.sync.leader
  end
  if s.g and C.GroupSize and C.GroupSize() > 1 and C.FarmLeader then
    local leader, lead = C.FarmLeader()
    if lead then
      local gf = C.GroupFarm(s)
      return { secs = C.SessionSecs(s), net = gf.net, coin = gf.coin, items = gf.items, used = gf.used, kills = s.kills, paused = s.paused }, true, leader
    end
    local v = C.groupView
    local now = GetTime and GetTime() or 0
    if v and now - v.t < 15 then
      return { secs = v.secs + (v.paused and 0 or (now - v.t)), net = v.net, coin = v.coin, items = v.items, used = v.used, kills = v.kills, paused = v.paused }, true, v.from
    end
    return nil, true, leader
  end
  return nil
end

-- 0.14.0: skinning records before this build mixed in ordinary corpse loot (slot 2+
-- of every corpse was filed as a skin). They can't be separated, so start them over.
C.On("INIT", function()
  if C.db.skinReset0140 then return end
  C.db.skinReset0140 = true
  local n = 0
  for _, r in pairs(C.db.loot or {}) do
    if type(r) == "table" and ((r.skins or 0) > 0 or (r.skinItems and next(r.skinItems))) then r.skins = 0; r.skinItems = {}; n = n + 1 end
  end
  local S = C.Share and C.Share.DB and C.Share.DB()
  for _, a in pairs(S and S.authors or {}) do
    for _, r in pairs(a.loot and a.loot.npcs or {}) do if type(r) == "table" then r.skins = 0; r.skinItems = {} end end
  end
  if n > 0 then C.Print("skinning records reset (" .. n .. " mobs): older ones counted ordinary corpse loot as skins. New skins are counted correctly.") end
end)

C.On("PLAYER_LOGOUT", function()
  local s = C.session
  if s and not s.sync and not s.paused then s.paused, s.pauseAt, s.offPause = true, C.Now(), true end
end)
C.On("INIT", function()
  local s = C.db.activeSession
  if type(s) ~= "table" or not s.start then C.db.activeSession = nil; s = nil end
  -- 0.9.20 (found on Taylor's own save): a farm belongs to the character that farmed it.
  -- Logging in on another character used to pick up that character's farm (a shared farm
  -- then kept reporting to "itself" as leader, over and over). It waits for its own
  -- character now, and that character's waiting farm comes back when you log in on it.
  C.db.parked = type(C.db.parked) == "table" and C.db.parked or {}
  if s and s.char and C.charKey and s.char ~= C.charKey then
    C.db.parked[s.char] = s
    C.db.activeSession = nil
    C.Print(string.format("your farm \"%s\" on %s waits for %s: it carries on when you log in there.", tostring(s.label), tostring(s.char:match("^[^%-]+")), tostring(s.char:match("^[^%-]+"))))
    s = nil
  end
  if not s and C.charKey and type(C.db.parked[C.charKey]) == "table" then
    s = C.db.parked[C.charKey]; C.db.parked[C.charKey] = nil
    C.db.activeSession = s
  end
  if not s then return end
  C.session = s
  s.items = s.items or {}; s.money = s.money or {}; s.byNpc = s.byNpc or {}; s.kills = s.kills or 0
  -- 0.9.14 (Taylor): a solo farm never ends by itself. The time you were logged off
  -- doesn't count (it was paused at logout), and it carries on where you left it.
  if not s.sync then
    if s.offPause then
      s.pausedSecs = (s.pausedSecs or 0) + math.max(0, C.Now() - (s.pauseAt or C.Now()))
      s.paused, s.pauseAt, s.offPause = nil, nil, nil
      s.resumeAt = C.Now()
    end
    C.Print("farm resumed: " .. tostring(s.label))
    return
  end
  -- 1.5.4: everyone logged off and an hour passed since the last kill: it ended there
  local lk = C.LastKillAt(s)
  if C.Now() - lk >= 3600 then
    C.StopSession(lk + 60, "no kills for an hour", true)
  else
    C.Print("farm resumed: " .. tostring(s.label))
  end
end)


------------------------------------------------------------------ group farm totals
-- What the whole group looted, from the game's own loot lines ("Vellaura receives
-- loot: ...", "Your share of the loot is ..."), which every member sees alike. With
-- the kills shared between Kina users, both widgets can show the same numbers.
local function pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end
local LOOT_PATS
local function lootPatterns()
  if LOOT_PATS then return LOOT_PATS end
  LOOT_PATS = {
    { pattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d."), self = true, multi = true },
    { pattern(LOOT_ITEM_SELF or "You receive loot: %s."), self = true },
    { pattern(LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d."), multi = true },
    { pattern(LOOT_ITEM or "%s receives loot: %s.") },
  }
  return LOOT_PATS
end
local function shortName(n) return n and (n:match("^([^%-]+)") or n) end
C.On("CHAT_MSG_LOOT", function(_, text, player)
  local s = C.session
  if type(text) == "string" then
    for _, p in ipairs(lootPatterns()) do
      if p[1] and p.self then
        local a, b = text:match(p[1])
        if a then
          local ok, err = pcall(ownLoot, a, p.multi and tonumber(b) or 1)
          if not ok then C.LogError("ownLoot", err) end
          break
        end
      end
    end
  end
  if s and s.sync and type(text) == "string" then
    -- a disenchant result. 1.3.1 (Taylor): disenchanting FARM gear counts at what it
    -- actually became: the gear's value comes off ("D") and the materials go on, so the
    -- group shares the gain or the loss. Gear from outside the farm: materials ignored.
    local nowDE = GetTime and GetTime() or 0
    if nowDE - (castAt.de or -99) < 5 then
      local gear = C.DEGearNow and C.DEGearNow(s)
      if not gear then return end
      if C.deSwapDone ~= castAt.de and not s.paused and C.FarmSync then
        C.deSwapDone = castAt.de
        C.FarmSync.Observe("D", gear .. ":1")
      end
    end
    for _, p in ipairs(lootPatterns()) do
      if p[1] and p.self then
        local a, b = text:match(p[1])
        if a then
          local id = C.ItemIDFromLink(a)
          if id then
            local n = p.multi and tonumber(b) or 1
            local suffix
            local full = a:match("%[(.-)%]")
            local base = C.db.items and C.db.items[id] and C.db.items[id].name
            if full and base and full ~= base and full:sub(1, #base) == base then suffix = full:sub(#base + 2)
            elseif full and not base then suffix = full:match(" (of the %a[%a ]*)$") end
            if not s.paused and C.FarmSync then C.FarmSync.Observe("L", id .. ":" .. n .. ":" .. (suffix or "")) end
          end
          return
        end
      end
    end
    return
  end
  if not (s and s.g and type(text) == "string") then return end
  if not (C.GroupSize and C.GroupSize() > 1) then return end -- solo: your own loot is counted above
  for _, p in ipairs(lootPatterns()) do
    if p[1] then
      local a, b, c = text:match(p[1])
      if a then
        local who, link, n
        if p.self then who, link, n = UnitName("player"), a, p.multi and tonumber(b) or 1
        else who, link, n = a, b, p.multi and tonumber(c) or 1 end
        local id = C.ItemIDFromLink(link)
        -- someone in the group who doesn't run Kina isn't in this farm
        if id and not p.self and C.IsFarmMate and not C.IsFarmMate(who) then return end
        if id then
          who = shortName(who)
          -- the roll, from the link's name: "[Medicine Staff of the Eagle]" -> "of the Eagle"
          local suffix
          local full = link:match("%[(.-)%]")
          local base = C.db.items and C.db.items[id] and C.db.items[id].name
          if full and base and full ~= base and full:sub(1, #base) == base then suffix = full:sub(#base + 2)
          elseif full and not base then suffix = full:match(" (of the %a[%a ]*)$") end
          if s.paused then
            C.SessionLog("gloot", id, n or 1, who, suffix); s.log[#s.log][7] = true -- left out (paused)
            return
          end
          s.g.loot[who] = s.g.loot[who] or {}
          s.g.loot[who][id] = (s.g.loot[who][id] or 0) + (n or 1)
          if suffix then
            s.g.sx = s.g.sx or {}; s.g.sx[who] = s.g.sx[who] or {}; s.g.sx[who][id] = s.g.sx[who][id] or {}
            s.g.sx[who][id][suffix] = (s.g.sx[who][id][suffix] or 0) + (n or 1)
          end
          C.SessionLog("gloot", id, n or 1, who, suffix)
        end
        return
      end
    end
  end
end)
local function parseCoin(text)
  local function amt(fmt)
    local word = (fmt or ""):gsub("%%d", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if word == "" then return 0 end
    return tonumber(text:match("(%d+)%s*" .. word)) or 0
  end
  return amt(GOLD_AMOUNT or "%d Gold") * 10000 + amt(SILVER_AMOUNT or "%d Silver") * 100 + amt(COPPER_AMOUNT or "%d Copper")
end
C.On("CHAT_MSG_MONEY", function(_, text)
  local s = C.session
  if type(text) == "string" then
    local v = parseCoin(text)
    if v > 0 then local ok, err = pcall(ownCoin, v); if not ok then C.LogError("ownCoin", err) end end
  end
  if s and s.sync and type(text) == "string" then
    -- shared farm: report the coin YOU got (your share); the log adds everyone's
    local v = parseCoin(text)
    if v > 0 and not s.paused and C.FarmSync then C.FarmSync.Observe("C", tostring(v)) end
    return
  end
  if not (s and s.g and type(text) == "string") then return end
  if not (C.GroupSize and C.GroupSize() > 1) then return end
  local v = parseCoin(text)
  if v <= 0 or s.paused then return end
  local split = LOOT_MONEY_SPLIT and text:find((LOOT_MONEY_SPLIT:gsub("%%s.*$", "")), 1, true)
  -- the game split the coin across the whole group; the farm only owns the Kina users' shares
  local mates = C.FarmMates and select(2, C.FarmMates()) or (C.GroupSize and C.GroupSize() or 1)
  local n = split and math.max(1, mates) or 1
  s.g.coin = s.g.coin + v * n
  C.SessionLog("gcoin", v * n, n)
end)
-- { coin, items, net, kills, byLooter = { name = value } }
------------------------------------------------------------------ consumables used
-- Potions, food, bandages, scrolls, poisons and ammo that leave your bags during a
-- farm (not at a vendor, mailbox, bank, trade or the AH) are the farm's costs. Each
-- Kina tells the group what it used; the widget and the split take it off.
local tradeOpen = false
C.On("TRADE_SHOW", function() tradeOpen = true end)
C.On("TRADE_CLOSED", function() tradeOpen = false end)
local function isConsumable(id)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return false end
  local classID = select(6, fn(id))
  return classID == 0 or classID == 6
end
local function consumables()
  local out = {}
  for id, n in pairs(C.Holdings(true)) do if n > 0 and isConsumable(id) then out[id] = n end end
  return out
end
C.Consumables = consumables
-- 1.0.10: uses in a shared farm are batched (a hunter's every arrow was one log entry
-- and one addon message: 550 in an evening). Sent every 30 s out of combat, and
-- straight away when the farm stops.
function C.FlushUse(force)
  local s = C.session
  if not (s and s.sync and s.pendUse and next(s.pendUse)) then return end
  if not force then
    if InCombatLockdown and InCombatLockdown() then return end
    if C.Now() - (s.useFlushAt or 0) < 30 then return end
  end
  s.useFlushAt = C.Now()
  local list = s.pendUse
  s.pendUse = {}
  for id, n in pairs(list) do
    if n > 0 and C.FarmSync then C.FarmSync.Observe("U", id .. ":" .. n) end
  end
end
function C.RecordUse(s, who, id, n, fromParty)
  if s.sync then
    if not fromParty then
      s.pendUse = s.pendUse or {}
      s.pendUse[id] = (s.pendUse[id] or 0) + n
      if not s.useFlushAt then s.useFlushAt = C.Now() end
    end
    C.SessionLog("used", id, n, who)
    return
  end
  s.g.used = s.g.used or {}
  s.g.used[who] = s.g.used[who] or {}
  s.g.used[who][id] = (s.g.used[who][id] or 0) + n
  C.SessionLog("used", id, n, who)
  if not fromParty and C.Share and C.Share.SendUse then pcall(C.Share.SendUse, id, n) end
  if C.RefreshWidget then C.RefreshWidget() end
end
C.On("BAG_UPDATE_DELAYED", function()
  local s = C.session
  if not (s and (s.g or s.sync)) then return end
  local now = consumables()
  local before = s.cons
  s.cons = now
  if not before then return end
  if (merchantOpen and C.MerchantIsOpen() ~= false) or (mailOpen and C.MailIsOpen() ~= false) or tradeOpen or C.ahOpen or (C.BankOpen and C.BankOpen()) or s.paused then return end
  local me = shortName(UnitName("player"))
  for id, n in pairs(before) do
    local gone = n - (now[id] or 0)
    if gone > 0 then C.RecordUse(s, me, id, gone) end
  end
end)
-- a group member used something (from Share.lua)
function C.OnFarmUse(from, id, n)
  local s = C.session
  if s and s.g and not s.paused then C.RecordUse(s, (from:match("^([^%-]+)") or from), id, n, true) end
end
-- what each player used, in copper, keyed like the loot lines (first names matched)
local function usedBy(s, by)
  local total = 0
  for who, list in pairs(s.g.used or {}) do
    local v = 0
    for id, n in pairs(list) do v = v + (C.FarmValue and C.FarmValue(id) or 0) * n end
    total = total + v
    if by then
      local key = who
      for k in pairs(by) do if C.FirstName and C.FirstName(k) == C.FirstName(who) then key = k end end
      by[key] = (by[key] or 0) - v
    end
  end
  return total
end

function C.GroupFarm(s)
  s = s or C.session
  if s and s.sync and C.FarmSync then
    local t = C.FarmSync.Totals(s.sync)
    return { coin = t.coin, items = t.items, used = t.used, net = t.net, kills = t.kills, byLooter = t.byLooter, synced = true }
  end
  if not (s and s.g) then return nil end
  local items, by = 0, {}
  for who, list in pairs(s.g.loot) do
    local v = 0
    local rolls = s.g.sx and s.g.sx[who] or {}
    for id, n in pairs(list) do
      local left = n
      for suf, c in pairs(rolls[id] or {}) do
        local k = math.min(c, left)
        if k > 0 then v = v + (C.SplitValue(id, suf) or 0) * k; left = left - k end
      end
      v = v + (C.SplitValue(id) or 0) * left
    end
    by[who] = v; items = items + v
  end
  -- 1.0.0 (Taylor): consumables are each player's own stat, never part of the split
  -- (the shared farm has worked this way since 1.2.8; now the plain group farm does too)
  local used = usedBy(s, nil)
  return { coin = s.g.coin, items = items, used = used, net = s.g.coin + items, kills = s.kills, byLooter = by }
end


------------------------------------------------------------------ hand edits
-- Right-click a kill or a drop in the farm's log: leave it out of the farm, or count
-- it after all. Group loot and kills are changed on every Kina in the group.
local function applyLoot(s, who, id, n, on)
  local me = shortName(UnitName("player"))
  if s.g then
    s.g.loot[who] = s.g.loot[who] or {}
    s.g.loot[who][id] = math.max(0, (s.g.loot[who][id] or 0) + (on and n or -n))
  end
  if who == me then
    s.excl = s.excl or { coin = 0, items = {} }
    s.excl.items[id] = math.max(0, (s.excl.items[id] or 0) + (on and -n or n))
  end
end
local function applyKill(s, npc, on)
  s.kills = math.max(0, (s.kills or 0) + (on and 1 or -1))
  s.byNpc[npc] = math.max(0, (s.byNpc[npc] or 0) + (on and 1 or -1))
end
function C.FarmEditEntry(s, i)
  local e = s and s.log and s.log[i]
  if not e then return end
  local on = e[7] and true or false -- currently left out: count it
  local k = e[2]
  if k == "gloot" then
    applyLoot(s, e[5], e[3], e[4] or 1, on)
    if C.Share and C.Share.SendFarmEdit then pcall(C.Share.SendFarmEdit, "g", e[3], e[4] or 1, e[5], on) end
  elseif k == "loot" then
    -- 0.9.1 (security): in a group farm your own loot can't be left out by you (it
    -- would lower what you owe); a farm partner can leave it out for everyone
    if not on and (s.g or s.sync or (s.party and #s.party > 0)) then
      C.Print("you can't leave your own loot out of a group farm (it would change what you owe). Ask a farm partner to leave it out.")
      return
    end
    -- your own loot: leaving it out takes it off the farm's items (and back on again)
    s.excl = s.excl or { coin = 0, items = {} }
    local n = e[4] or 1
    s.excl.items[e[3]] = math.max(0, (s.excl.items[e[3]] or 0) + (on and -n or n))
    s.items[e[3]] = math.max(0, (s.items[e[3]] or 0) + (on and n or -n))
    if e[8] and s.sx and s.sx[e[3]] then s.sx[e[3]][e[8]] = math.max(0, (s.sx[e[3]][e[8]] or 0) + (on and n or -n)) end
  elseif k == "kill" then
    applyKill(s, e[3], on)
    if C.Share and C.Share.SendFarmEdit then pcall(C.Share.SendFarmEdit, "k", e[3], 1, "", on) end
  else return end
  e[7] = (not on) or nil
  if C.RefreshWidget then C.RefreshWidget() end
  if C.Refresh then C.Refresh() end
end
-- a group member changed an entry on their Kina
function C.OnFarmEdit(kind, id, n, who, on, from)
  local s = C.session
  if not s then return end
  -- 0.9.1 (security): nobody can leave out their own loot
  if kind == "g" and not on and tostring(who or ""):lower():match("^[^%-]*") == tostring(from or ""):lower():match("^[^%-]*") then return end
  if kind == "g" then applyLoot(s, who, id, n, on) elseif kind == "k" then applyKill(s, id, on) end
  C.SessionLog("edit", id, on and 1 or 0, kind, from)
  if C.RefreshWidget then C.RefreshWidget() end
end

-- 1.2.6: walking into a dungeon or raid offers to start a farm there (or to swap the
-- running farm for one in the instance). Only the group's leader (or a solo player) is
-- asked; everyone else gets the usual farm invite when the leader starts it.
do
  local askedFor
  local function leaderOrSolo()
    if not (IsInGroup and IsInGroup()) then return true end
    return UnitIsGroupLeader and UnitIsGroupLeader("player") and true or false
  end
  if StaticPopupDialogs then StaticPopupDialogs["KINA_INSTANCE_FARM"] = {
    text = "%s", button1 = "Start farm", button2 = "Not now",
    OnAccept = function(_, data)
      if not data then return end
      if C.session and C.StopSession then C.StopSession(nil, "stopped") end
      if C.StartSession then C.StartSession(data) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  } end
  local function check()
    if not (StaticPopup_Show and StaticPopupDialogs) then return end
    if not (IsInInstance) then return end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then askedFor = nil; return end
    local name = GetInstanceInfo and GetInstanceInfo() or (GetRealZoneText and GetRealZoneText()) or "dungeon"
    if askedFor == name or not leaderOrSolo() then return end
    if C.session and C.session.label == name then return end
    askedFor = name
    local text = C.session and string.format("Kina: stop the farm \"%s\" and start one in %s?", tostring(C.session.label or "farm"), name)
      or string.format("Kina: start a farm in %s?", name)
    C.ShowPopup("KINA_INSTANCE_FARM", text, nil, name)
  end
  C.On("PLAYER_ENTERING_WORLD", function() C.After(3, check) end)
  C.On("ZONE_CHANGED_NEW_AREA", function() C.After(2, check) end)
end

-- 1.2.9: "Leave cloth for our tailor" (Settings, off by default). Kina does the looting
-- itself (the game's Auto Loot is switched off while this is on, and put back when it's
-- turned off): it takes everything, except that when a Kina user in the group has
-- Tailoring and you don't, cloth stays on the corpse for them. The split is unchanged:
-- the cloth still counts as farm loot when the tailor loots it.
do
  local CLOTH = { [2589] = true, [2592] = true, [4306] = true, [4338] = true, [14047] = true, [14256] = true }
  function C.SetLeaveCloth(on)
    C.settings.leaveCloth = on and true or false
    if not (GetCVar and SetCVar) then return end
    if on then
      if C.settings.autoLootWas == nil then C.settings.autoLootWas = GetCVar("autoLootDefault") end
      pcall(SetCVar, "autoLootDefault", "0")
      C.Print("Kina now loots for you, leaving cloth for your group's tailor. (The game's Auto Loot is off while this is on.)")
    else
      if C.settings.autoLootWas ~= nil then pcall(SetCVar, "autoLootDefault", C.settings.autoLootWas); C.settings.autoLootWas = nil end
      C.Print("Kina leaves the looting to the game again (your Auto Loot setting is back).")
    end
  end
  local function lootNow()
    if not (C.settings.leaveCloth and GetNumLootItems and LootSlot) then return end
    local leave = not C.TradeSkill("Tailoring") and C.Share and C.Share.GroupHasProf and C.Share.GroupHasProf("Tailoring")
    for i = GetNumLootItems(), 1, -1 do
      local link = GetLootSlotLink and GetLootSlotLink(i)
      local id = link and tonumber(link:match("item:(%d+)"))
      if not (leave and id and CLOTH[id]) then pcall(LootSlot, i) end
    end
  end
  C.On("LOOT_READY", function() if C.settings.leaveCloth then C.After(0.05, lootNow) end end)
end

-- 1.3.1: which farm item a disenchant just used up. Kina counts the farm's looted items
-- in your bags when the cast starts and again when its result arrives; the one that went
-- down by one is the disenchanted item (only items looted in this shared farm count).
do
  local snap
  local function farmIDs(s)
    local ids = {}
    for _, ev in ipairs(s and s.sync and s.sync.chain or {}) do
      if ev.kind == "L" then local id = tonumber((ev.data or ""):match("^(%d+)")); if id then ids[id] = true end end
    end
    return ids
  end
  local function count(ids)
    local out = {}
    local CC = C_Container
    for bag = 0, 4 do
      local n = (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
      for slot = 1, n do
        local id, k
        if CC and CC.GetContainerItemInfo then
          local info = CC.GetContainerItemInfo(bag, slot)
          if info then id, k = info.itemID, info.stackCount end
        elseif GetContainerItemID then id = GetContainerItemID(bag, slot); k = 1 end
        if id and ids[id] then out[id] = (out[id] or 0) + (k or 1) end
      end
    end
    return out
  end
  C.On("UNIT_SPELLCAST_START", function(_, unit, _, spellID)
    if unit ~= "player" or spellID ~= 13262 then return end
    local s = C.session
    if not (s and s.sync) then snap = nil; return end
    local ids = farmIDs(s)
    snap = { ids = ids, n = count(ids), t = GetTime and GetTime() or 0 }
  end)
  function C.DEGearNow(s)
    if not snap or (GetTime() - snap.t) > 12 then return nil end
    if C.deGearCache then return C.deGearCache end
    local now = count(snap.ids)
    for id, k in pairs(snap.n) do
      if (now[id] or 0) < k then C.deGearCache = id; return id end
    end
  end
end

-- 1.4.6 (Taylor): XP per hour means the GAME's experience, not Kina XP. Every farm counts
-- the character XP you gain while it runs (mob kills, quests turned in, across level-ups),
-- shown as XP/h on the widget and in the Session list, and as "XP/h this week" on You.
do
  local lastXP, lastMax, lastLvl
  -- 0.9.21: secret-safe (unit values can be secret in dungeons on Forever)
  local function read()
    local xp, mx, lv = C.Plain(UnitXP and UnitXP("player")), C.Plain(UnitXPMax and UnitXPMax("player")), C.Plain(UnitLevel and UnitLevel("player"))
    if type(xp) ~= "number" or type(mx) ~= "number" or type(lv) ~= "number" then return nil end
    return xp, mx, lv
  end
  local function snapshot() local xp, mx, lv = read(); if xp then lastXP, lastMax, lastLvl = xp, mx, lv end end
  C.On("PLAYER_ENTERING_WORLD", snapshot)
  C.On("PLAYER_XP_UPDATE", function(_, unit)
    if unit and unit ~= "player" then return end
    local xp, mx, lv = read()
    if not xp then return end
    if lastXP then
      local gained = (lv > (lastLvl or lv)) and ((lastMax or 0) - (lastXP or 0) + xp) or (xp - lastXP)
      local s = C.session
      if s and gained > 0 and gained < 1e7 and not s.paused then s.gameXP = (s.gameXP or 0) + gained end
    end
    lastXP, lastMax, lastLvl = xp, mx, lv
  end)
  function C.FmtXPH(n)
    if not n then return "" end
    if n >= 1000 then return string.format("%.1fk XP/h", n / 1000) end
    return string.format("%d XP/h", n)
  end
  function C.GameXPPerHour(s)
    if not s or not s.gameXP then return nil end
    local secs = (s.stop or C.Now()) - (s.start or C.Now()) - (s.pausedSecs or 0)
    if secs < 120 then return nil end
    return math.floor(s.gameXP * 3600 / secs)
  end
  function C.GameXPWeek()
    local xp, secs = 0, 0
    local since = C.Now() - 7 * 86400
    local function add(s)
      if s and s.gameXP and (s.start or 0) >= since then
        xp = xp + s.gameXP
        secs = secs + math.max(0, (s.stop or C.Now()) - (s.start or 0) - (s.pausedSecs or 0))
      end
    end
    for _, s in ipairs(C.db.sessions or {}) do add(s) end
    add(C.session)
    if secs < 600 then return nil end
    return math.floor(xp * 3600 / secs)
  end
end
