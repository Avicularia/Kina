-- Kina: pockets (pickpocketing), built in. Replaces Kaydee's Pockets.
--   * badge over mobs you can pick right now (nameplates and the target frame)
--   * learns mobs with "no pockets", hides mobs already robbed (yours or your group's)
--   * records every pick: coins, items, where (account-wide, Kaydee's data format)
--   * tooltip: what is in its pockets, valued at today's AH prices
--   * haul: picks and takings per session, today and lifetime, per character
--   * sharing and map bubbles: PocketSync.lua, PocketPins.lua
-- On first login your Kaydee's Pockets data (and sharing identity) is copied in.
-- While Kaydee's Pockets is still enabled, Kina stands by and mirrors its
-- data instead of recording twice; disable Kaydee's and Kina takes over.
-- Events are the same ones Kaydee's Pockets and Kina Scout use on Forever.
local ADDON, C = ...
local P = {}
C.Pockets = P
P.SPELL = 921
P.ICON = "Interface\\Icons\\INV_Misc_Bag_11"
P.picked = {}              -- [guid] = true: robbed this session (respawns get new GUIDs)

local HUMANOID = { Humanoid = true, Humanoide = true, ["Humanoïde"] = true, Umanoide = true,
  ["Гуманоид"] = true, ["인간형"] = true, ["人型生物"] = true, ["人型"] = true }

local function Safe(v) if v ~= nil and issecretvalue and issecretvalue(v) then return nil end; return v end
P.Safe = Safe

local OPTS = { badges = true, mode = "both", size = 16, plates = true, target = true, hidePicked = true,
  tooltip = true, tooltipMax = 6, syncRobbed = true, shareLoot = true, showShared = true, pushAfterPick = true,
  shareName = true, partyInterval = 2, guildInterval = 10, pins = true, pinsShared = true, pinScale = 100 }

function P.DB()
  local d = C.db.pockets
  if not d then d = {}; C.db.pockets = d end
  d.loot = d.loot or {}; d.shared = d.shared or {}; d.noPockets = d.noPockets or {}
  d.haulChars = d.haulChars or {}; d.haulToday = d.haulToday or {}
  d.opts = d.opts or {}
  for k, v in pairs(OPTS) do if d.opts[k] == nil then d.opts[k] = v end end
  if not d.uid then d.uid = string.format("%x%04x", time(), math.random(0, 0xffff)) end
  d.myVer = d.myVer or 0
  return d
end

function P.Log(fmt, ...)
  if not C.debug then return end
  local d = P.DB()
  d.log = d.log or {}
  local ok, msg = pcall(string.format, fmt, ...)
  table.insert(d.log, date("%H:%M:%S") .. " " .. (ok and msg or tostring(fmt)))
  while #d.log > 200 do table.remove(d.log, 1) end
end

function P.NPCID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" then return tonumber(id) end
end

local function isRogue() return UnitClass and select(2, UnitClass("player")) == "ROGUE" end

-- Is Kaydee's Pockets running? Then Kina stands by (mirror only).
function P.KaydeeLoaded()
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return f and f("KaydeesPockets") and true or false
end

-- Active = this character records, badges, tooltips, pins and shares.
function P.Active()
  return P.on == true
end

------------------------------------------------------------------ Kaydee's data
local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}; for k, v in pairs(t) do o[k] = copy(v) end; return o
end

-- Take Kaydee's data as-is (it is the truth while it records).
function P.MirrorKaydee(announce)
  local k = rawget(_G, "KaydeesPocketsDB")
  if type(k) ~= "table" then return false end
  local d = P.DB()
  d.loot = copy(k.loot or {}); d.shared = copy(k.shared or {}); d.noPockets = copy(k.noPockets or {})
  d.haulChars = copy(k.haulChars or {}); d.haulToday = copy(k.haulToday or {})
  -- keep Kaydee's sharing identity so guildmates' copies of your data stay valid
  if k.uid then d.uid = k.uid end
  d.myVer = math.max(d.myVer or 0, k.myVer or 0)
  d.myPicks = k.myPicks
  d.mirrored = time()
  if announce then
    local n, picks = 0, 0
    for _, e in pairs(d.loot) do n = n + 1; picks = picks + (e.picks or 0) end
    local a = 0; for _ in pairs(d.shared) do a = a + 1 end
    C.Print(string.format("pockets: copied Kaydee's Pockets data (%d mobs, %d of your picks, %d shared players).", n, picks, a))
  end
  return true
end

------------------------------------------------------------------ records
local function newEntry() return { picks = 0, items = {}, money = { seen = 0, count = 0, total = 0 } } end
P.NewEntry = newEntry

function P.MarkChanged(e)
  local d = P.DB()
  d.myVer = (d.myVer or 0) + 1
  e.v = d.myVer
end

local function mergeInto(dst, src)
  dst.picks = dst.picks + (src.picks or 0)
  dst.name = dst.name or src.name
  for id, it in pairs(src.items or {}) do
    local x = dst.items[id] or { seen = 0, qty = 0 }
    x.seen = x.seen + (it.seen or 0); x.qty = x.qty + (it.qty or 0); x.link = x.link or it.link
    dst.items[id] = x
  end
  local m, sm = dst.money, src.money
  if sm then
    m.seen = m.seen + (sm.seen or 0); m.count = m.count + (sm.count or 0); m.total = m.total + (sm.total or 0)
    if sm.min then m.min = math.min(m.min or sm.min, sm.min) end
    if sm.max then m.max = math.max(m.max or sm.max, sm.max) end
  end
end

-- Your data plus everyone's shared data for one kind of mob.
-- Returns combined entry or nil, your picks, number of other players, their uids.
function P.Combined(npc)
  local d = P.DB()
  local mine = d.loot[npc]
  local all, others, uids = newEntry(), 0, {}
  if mine then mergeInto(all, mine) end
  if d.opts.showShared then
    for uid, a in pairs(d.shared) do
      local e = uid ~= d.uid and a.npcs and a.npcs[npc]
      if e and (e.picks or 0) > 0 then mergeInto(all, e); others = others + 1; uids[#uids + 1] = uid end
    end
  end
  if all.picks == 0 then return nil, 0, 0, uids end
  return all, mine and mine.picks or 0, others, uids
end

-- What one pick is worth at today's prices (coins + items at their best route).
function P.ValuePerPick(npc, entry)
  local e = entry or P.Combined(npc)
  if not e or (e.picks or 0) == 0 then return nil end
  local v = 0
  local m = e.money
  if m and (m.count or 0) > 0 then v = v + (m.total / m.count) * ((m.seen or m.count) / e.picks) end
  for id, it in pairs(e.items or {}) do
    local _, unit = C.BestRoute(id, 1)
    if not unit or unit == 0 then unit = C.VendorPrice and C.VendorPrice(id) or 0 end
    v = v + (unit or 0) * (it.qty or 0) / e.picks
  end
  return v, e.picks
end

------------------------------------------------------------------ can I pick it?
function P.Candidate(unit)
  if not UnitExists(unit) then return false, "nothing there" end
  if UnitIsPlayer(unit) then return false, "it's a player" end
  if UnitPlayerControlled and UnitPlayerControlled(unit) then return false, "it's a pet or summon" end
  if UnitCanAttack and not UnitCanAttack("player", unit) then return false, "you can't attack it" end
  local ctype = Safe(UnitCreatureType(unit))
  if not ctype then return false, "creature type unknown" end
  if not HUMANOID[ctype] then return false, "it's a " .. ctype .. ", not a Humanoid" end
  local guid = Safe(UnitGUID(unit))
  local id = P.NPCID(guid)
  if id and P.DB().noPockets[id] then return false, "this kind of mob has no pockets" end
  return true, nil, guid, id
end

function P.Check(unit)
  if not P.Active() then return false, "pockets are off on this character" end
  local ok, why, guid = P.Candidate(unit)
  if not ok then return false, why end
  if UnitIsDead and UnitIsDead(unit) then return false, "it's dead" end
  if UnitAffectingCombat and UnitAffectingCombat(unit) then return false, "it's in combat" end
  if P.DB().opts.hidePicked and guid and P.picked[guid] then return false, "you already picked its pockets" end
  return true, "yes, pick away!"
end
local function canPick(unit) local ok, r = pcall(P.Check, unit); return ok and r or false end

------------------------------------------------------------------ badges
local badges, plateBadges, targetBadge = {}, {}, nil
local function layout(b)
  local o = P.DB().opts
  local size = math.floor((o.size or 16) + 0.5) + (b.kind == "target" and 2 or 0)
  b.icon:SetSize(size, size)
  b.icon:ClearAllPoints(); b.text:ClearAllPoints()
  if o.mode == "icon" then b.icon:Show(); b.text:Hide(); b.icon:SetPoint("CENTER"); b:SetSize(size, size)
  elseif o.mode == "text" then b.icon:Hide(); b.text:Show(); b.text:SetPoint("CENTER"); b:SetSize(60, size)
  else b.icon:Show(); b.text:Show(); b.icon:SetPoint("LEFT"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0); b:SetSize(size + 62, size) end
  b:ClearAllPoints(); b:SetPoint("BOTTOM", b.anchorTo, "TOP", 0, 2)
end
local function newBadge(parent, anchorTo, kind)
  local b = CreateFrame("Frame", nil, parent)
  b.kind, b.anchorTo = kind, anchorTo
  b:SetFrameLevel(parent:GetFrameLevel() + 10)
  b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetTexture(P.ICON); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetText("|cffffd100Pockets!|r")
  layout(b); b:Hide()
  badges[#badges + 1] = b
  return b
end
local function updatePlate(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  local b = plateBadges[plate]
  if not b then b = newBadge(plate, plate, "plate"); plateBadges[plate] = b end
  b.unit = unit
  local o = P.DB().opts
  b:SetShown(o.badges and o.plates and canPick(unit))
end
local function removePlate(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
  local b = plate and plateBadges[plate]
  if b then b.unit = nil; b:Hide() end
end
function P.RefreshBadges()
  if not P.Active() then
    for _, b in ipairs(badges) do b:Hide() end
    return
  end
  local o = P.DB().opts
  for _, b in pairs(plateBadges) do if b.unit then b:SetShown(o.badges and o.plates and canPick(b.unit)) end end
  if not targetBadge and TargetFrame then
    local anchor = (TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.Portrait) or TargetFramePortrait or TargetFrame
    targetBadge = newBadge(TargetFrame, anchor, "target")
  end
  if targetBadge then targetBadge:SetShown(o.badges and o.target and canPick("target")) end
end
function P.Relayout() for _, b in ipairs(badges) do layout(b) end; P.RefreshBadges() end

------------------------------------------------------------------ haul
local session = { copper = 0, picks = 0, items = 0, value = 0 }
P.session = session
local function blank() return { copper = 0, picks = 0, items = 0, value = 0 } end
function P.HaulStores()
  local d = P.DB()
  local key = C.charKey
  d.haulChars[key] = d.haulChars[key] or blank()
  local day = date("%Y-%m-%d")
  local today = d.haulToday[key]
  if not today or today.day ~= day then today = blank(); today.day = day; d.haulToday[key] = today end
  return session, today, d.haulChars[key]
end
function P.HaulAdd(copper, picks, items, value)
  if not session.start then session.start = GetTime() end
  for _, s in ipairs({ P.HaulStores() }) do
    s.copper = s.copper + copper; s.picks = s.picks + picks; s.items = s.items + items; s.value = s.value + value
  end
  if C.RefreshWidget then C.RefreshWidget() end
end
function P.HaulReset() session.copper, session.picks, session.items, session.value, session.start = 0, 0, 0, 0, nil end

------------------------------------------------------------------ recording a pick
local pending
local MONEY_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2

-- Loot.lua asks this so pickpocket loot is not counted as a corpse.
-- sourceGUID: the loot window's source; a corpse that isn't the picked mob is not pockets
function C.PocketLootActive(sourceGUID)
  if not (pending and pending.succeeded and (GetTime() - pending.time) < 5) then return false end
  if sourceGUID and pending.guid and sourceGUID ~= pending.guid then return false end
  return true
end

local function myLocation()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local map = Safe(C_Map.GetBestMapForUnit("player"))
  if not map then return end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  x, y = Safe(x), Safe(y)
  if not x or not y or (x == 0 and y == 0) then return end
  return map, x, y
end
local function rememberLocation(e)
  local ok, map, x, y = pcall(myLocation)
  if not ok or not map then return end
  e.locs = e.locs or {}
  x = math.floor(x * 1000 + 0.5) / 1000; y = math.floor(y * 1000 + 0.5) / 1000
  for _, l in ipairs(e.locs) do
    if l.m == map and math.abs(l.x - x) < 0.01 and math.abs(l.y - y) < 0.01 then l.n = (l.n or 1) + 1; return end
  end
  if #e.locs < 25 then e.locs[#e.locs + 1] = { m = map, x = x, y = y, n = 1 } end
end

local function lootIsFrom(guid)
  if not GetLootSourceInfo or not guid then return nil end
  for slot = 1, GetNumLootItems() do
    local src = Safe((GetLootSourceInfo(slot)))
    if src then return src == guid end
  end
  return nil
end

local function onLoot()
  local p = pending
  if not p then return end
  if GetTime() - p.time > 10 then pending = nil; return end
  if not p.succeeded or p.seenLoot or GetTime() - p.time > 3 then return end
  if lootIsFrom(p.guid) == false then return end
  p.seenLoot = true
  local d = P.DB()
  local e = d.loot[p.npc] or newEntry()
  d.loot[p.npc] = e
  if p.name then e.name = p.name end
  local itemCount, itemValue = 0, 0
  for slot = 1, GetNumLootItems() do
    if GetLootSlotType and GetLootSlotType(slot) == MONEY_SLOT then
      p.hadMoney = true
    else
      local link = GetLootSlotLink(slot)
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then
        local qty = GetLootSlotInfo and select(3, GetLootSlotInfo(slot)) or 1
        qty = (qty and qty > 0) and qty or 1
        itemCount = itemCount + qty
        local _, unit = C.BestRoute(id, qty)
        itemValue = itemValue + (unit or 0) * qty
        local it = e.items[id] or { seen = 0, qty = 0 }
        it.link = link; it.seen = it.seen + 1; it.qty = it.qty + qty
        e.items[id] = it
      end
    end
  end
  e.picks = e.picks + 1
  if p.hadMoney then e.money.seen = e.money.seen + 1 end
  d.myPicks = (d.myPicks or 0) + 1
  rememberLocation(e)
  P.MarkChanged(e)
  P.HaulAdd(0, 1, itemCount, itemValue)
  if P.OnNewPick then P.OnNewPick() end
  P.Log("pick recorded: %s (npc %d) items %d money %s", p.name or "?", p.npc, itemCount, tostring(p.hadMoney))
end

-- coins arrive after the loot window: measure the change a moment later
local function onLootClosed()
  local p = pending
  if not p or not p.seenLoot or not p.hadMoney or p.moneyDone then return end
  p.moneyDone = true
  C.After(0.5, function()
    local gained = GetMoney() - p.money
    if gained <= 0 then return end
    local e = P.DB().loot[p.npc]
    if e then
      local m = e.money
      m.count = m.count + 1; m.total = m.total + gained
      m.min = math.min(m.min or gained, gained); m.max = math.max(m.max or gained, gained)
      P.MarkChanged(e)
    end
    P.HaulAdd(gained, 0, 0, 0)
  end)
end

local PICK_NAME
local function isPick(spellID)
  spellID = Safe(spellID)
  if not spellID then return false end
  if spellID == P.SPELL then return true end
  if C_Spell and C_Spell.GetSpellName then
    PICK_NAME = PICK_NAME or C_Spell.GetSpellName(P.SPELL) or "Pick Pocket"
    return C_Spell.GetSpellName(spellID) == PICK_NAME
  end
  return false
end

------------------------------------------------------------------ events (own frame)
local ev = CreateFrame("Frame")
local function onEvent(_, event, ...)
  if not P.Active() then return end
  if event == "UNIT_SPELLCAST_SENT" then
    local _, _, _, spellID = ...
    if isPick(spellID) then
      local guid = Safe(UnitGUID("target"))
      local npc = P.NPCID(guid)
      pending = npc and { guid = guid, npc = npc, name = Safe(UnitName("target")), money = GetMoney(), time = GetTime() } or nil
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    if isPick(spellID) then
      if pending then pending.succeeded = true; pending.time = GetTime() end
      local guid = Safe(UnitGUID("target"))
      if guid then
        P.picked[guid] = true
        if P.SendRobbed then P.SendRobbed(guid) end
      end
      P.RefreshBadges()
    end
  elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
    pcall(onLoot)
  elseif event == "LOOT_CLOSED" then
    pcall(onLootClosed)
  elseif event == "UI_ERROR_MESSAGE" then
    local _, msg = ...
    msg = Safe(msg)
    local guid = Safe(UnitGUID("target"))
    if not (msg and guid) then return end
    if SPELL_FAILED_TARGET_NO_POCKETS and msg == SPELL_FAILED_TARGET_NO_POCKETS then
      local id = P.NPCID(guid)
      if id then
        P.DB().noPockets[id] = true
        C.Print("pockets: " .. (Safe(UnitName("target")) or "this mob") .. " has no pockets (remembered).")
      end
    elseif ERR_ALREADY_PICKPOCKETED and msg == ERR_ALREADY_PICKPOCKETED then
      P.picked[guid] = true
    end
    P.RefreshBadges()
  elseif event == "NAME_PLATE_UNIT_ADDED" then updatePlate(...)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then removePlate(...)
  elseif event == "PLAYER_TARGET_CHANGED" then P.RefreshBadges()
  end
end
ev:SetScript("OnEvent", function(...) local ok, err = pcall(onEvent, ...); if not ok and C.debug then C.Print("pockets: " .. tostring(err)) end end)
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
  acc = acc + el; if acc < 0.25 then return end; acc = 0
  if P.Active() then pcall(P.RefreshBadges) end
end)

local registered = false
local function register()
  if registered then return end
  registered = true
  ev:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
  ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "UI_ERROR_MESSAGE",
      "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
    ev:RegisterEvent(e)
  end
end
local function unregister()
  if not registered then return end
  registered = false
  ev:UnregisterAllEvents()
end

-- Decide this character's mode. Pockets run on rogues unless turned off with /kina pp off.
function P.Start()
  local d = P.DB()
  P.standby = P.KaydeeLoaded()
  if P.standby then
    P.on = false
    unregister()
    P.MirrorKaydee(not P.toldStandby)
    if not P.toldStandby and isRogue() then
      P.toldStandby = true
      C.Print("pockets: Kaydee's Pockets is still enabled, so Kina only mirrors its data. "
        .. "Disable Kaydee's Pockets in the AddOns list and Kina takes over everything it does.")
    end
  else
    if not d.importedKaydee and P.MirrorKaydee(true) then d.importedKaydee = time() end
    P.on = not C.PUBLIC and isRogue() and C.char.pockets ~= false
    if P.on then register() else unregister() end
  end
  P.RefreshBadges()
  if P.OnStart then P.OnStart() end
end

C.On("PLAYER_LOGIN", function() P.Start() end)
-- while standing by, keep the mirror fresh (Kaydee's records as you play)
local mirrorTick = CreateFrame("Frame")
local macc = 0
mirrorTick:SetScript("OnUpdate", function(_, el)
  macc = macc + el; if macc < 60 then return end; macc = 0
  if P.standby then P.MirrorKaydee(false) end
end)

------------------------------------------------------------------ tooltip
local function pct(n, d)
  if d <= 0 then return "?" end
  local p = math.min(1, math.max(0, n / d))
  local r, g = p >= 0.5 and (1 - p) * 2 or 1, p >= 0.5 and 1 or p * 2
  return string.format("|cff%02x%02x59%d%%|r", math.floor((0.35 + r * 0.65) * 255), math.floor((0.35 + g * 0.65) * 255), math.floor(p * 100 + 0.5))
end

local function itemText(id, it)
  local r = C.Item(id)
  local name = (r and r.name) or (it.link and it.link:match("%[(.-)%]")) or ("item " .. id)
  local avg = it.qty / math.max(it.seen, 1)
  return name .. (avg >= 1.5 and string.format(" |cffaaaaaax%.0f|r", avg) or "")
end

function P.TooltipLines(npc, add)
  local d = P.DB()
  if d.noPockets[npc] then add("|T" .. P.ICON .. ":14|t No pockets", "", 0.5, 0.5, 0.5); return true end
  local e, mine, others = P.Combined(npc)
  if not e then return false end
  local v = P.ValuePerPick(npc, e)
  add("|T" .. P.ICON .. ":14|t Pockets: " .. C.Money(v or 0) .. " per pick", string.format("%d picks (you %d%s)", e.picks, mine,
    others > 0 and (", +" .. others .. " players") or ""), 1, 0.82, 0)
  local m = e.money
  if m.seen > 0 then
    local amount = m.count > 0 and ((m.min and m.max and m.min ~= m.max) and (C.Money(m.min) .. " - " .. C.Money(m.max)) or C.Money(m.total / m.count)) or ""
    add("  Coins " .. amount, pct(m.seen, e.picks), 1, 1, 1)
  end
  local list = {}
  for id, it in pairs(e.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.seen > b.it.seen end)
  local max = d.opts.tooltipMax or 6
  for i, x in ipairs(list) do
    if i > max then add("  |cffaaaaaa+" .. (#list - max) .. " more|r", "", 1, 1, 1); break end
    add("  " .. itemText(x.id, x.it), pct(x.it.seen, e.picks), 1, 1, 1)
  end
  return true
end

local function addToTooltip(tip, unit)
  if not (P.Active() and P.DB().opts.tooltip) then return end
  local guid = Safe(UnitGUID(unit))
  local npc = P.NPCID(guid)
  if not npc then return end
  local shown = P.TooltipLines(npc, function(l, r, cr, cg, cb) tip:AddDoubleLine(l, r, cr or 1, cg or 1, cb or 1, 0.9, 0.9, 0.9) end)
  if shown and P.picked[guid] then tip:AddLine("  Already robbed", 0.6, 0.6, 0.6)
  elseif not shown then
    local ok, cand = pcall(P.Candidate, unit)
    if ok and cand then tip:AddLine("|T" .. P.ICON .. ":14|t Pockets: not picked yet", 1, 0.82, 0) end
  end
end
local function onTooltipUnit(tip)
  if tip ~= GameTooltip or not tip.GetUnit or tip.kscPockets then return end
  local _, unit = tip:GetUnit()
  unit = Safe(unit)
  if not unit and UnitExists("mouseover") then unit = "mouseover" end
  if unit then tip.kscPockets = true; pcall(addToTooltip, tip, unit) end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltipUnit)
end
if GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", onTooltipUnit)
end
if GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipCleared", function(t) t.kscPockets = nil end)
  GameTooltip:HookScript("OnHide", function(t) t.kscPockets = nil end)
end

------------------------------------------------------------------ /kina pp
function P.Command(rest)
  local d = P.DB()
  local o = d.opts
  local cmd = (rest or ""):lower()
  local function onoff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end
  if cmd == "" or cmd == "status" then
    local _, today, life = P.HaulStores()
    local mobs = 0; for _ in pairs(d.loot) do mobs = mobs + 1 end
    local a = 0; for uid in pairs(d.shared) do if uid ~= d.uid then a = a + 1 end end
    C.Print(string.format("pockets %s%s. %d mobs recorded, %d shared players. Today %d picks %s, lifetime %d picks %s.",
      P.Active() and "on" or "off", P.standby and " (standing by: Kaydee's Pockets is enabled)" or "", mobs, a,
      today.picks, C.Money(today.copper + today.value), life.picks, C.Money(life.copper + life.value)))
    C.Print("/kina pp check | loot | on | off | badges | plates | target | icon | text | both | tooltip | share | pins | sync | sync now | forget | haul reset | log")
  elseif cmd == "on" or cmd == "off" then
    C.char.pockets = (cmd == "on"); P.Start()
    C.Print("pockets on this character: " .. onoff(P.Active()))
  elseif cmd == "badges" or cmd == "plates" or cmd == "target" or cmd == "tooltip" or cmd == "pins" then
    o[cmd] = not o[cmd]; P.Relayout(); if P.RefreshPins then pcall(P.RefreshPins) end
    C.Print(cmd .. " " .. onoff(o[cmd]))
  elseif cmd == "icon" or cmd == "text" or cmd == "both" then
    o.mode = cmd; P.Relayout()
  elseif cmd == "share" then
    o.shareLoot = not o.shareLoot; C.Print("sharing pocket data with guild and group " .. onoff(o.shareLoot))
  elseif cmd == "check" then
    local ok, _, why = pcall(P.Check, "target")
    C.Print((Safe(UnitName("target")) or "No target") .. ": " .. tostring(ok and why or "can't read target"))
  elseif cmd == "loot" then
    local npc = P.NPCID(Safe(UnitGUID("target")))
    if not npc then C.Print("target a mob first."); return end
    local any = P.TooltipLines(npc, function(l, r) C.Print(l .. "  " .. (r or "")) end)
    if not any then C.Print("nothing recorded for that mob yet.") end
  elseif cmd == "sync" then if P.SyncStatus then P.SyncStatus() end
  elseif cmd == "sync now" then if P.SyncNow then P.SyncNow() end
  elseif cmd == "forget" then wipe(d.noPockets); wipe(P.picked); C.Print("forgot the no-pockets list."); P.RefreshBadges()
  elseif cmd == "haul reset" then P.HaulReset(); C.Print("new pocket haul session.")
  elseif cmd == "log" then
    for i = math.max(1, #(d.log or {}) - 15), #(d.log or {}) do C.Print(d.log[i]) end
    if not C.debug then C.Print("(turn on logging with /kina debug)") end
  else
    P.Command("status")
  end
end
