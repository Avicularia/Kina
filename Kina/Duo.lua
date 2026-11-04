-- Kina: who is farming (you, and a partner), and which professions pay.
--
-- Partner: picked up automatically from party sharing (their Kina tells yours their
-- class, level and professions) while you're grouped, or typed on the Settings tab.
--
-- Farm profile: solo or duo. Duo = the pair kills ~1.7x as fast, can take elites a
-- couple of levels higher, gathers with whoever has the profession, and every
-- gold/hour figure is shown PER PERSON (the loot is split two ways).
--
-- Professions: each option is valued in gold/hour on your best farms:
--   Skinning   leather from the beasts you kill (Classic leather by mob level)
--   Herbalism / Mining   nodes passed while farming, at today's prices
--   Enchanting disenchant premium on green/blue drops + fewer town trips (gear
--              turns into stacking mats, so bags fill slower and you stay out longer)
--   Crafting   best margins at your skill, limited by how fast the AH buys them
-- The pair plan never doubles a profession: one gatherer, one enchanter, one crafter
-- of each kind is enough (two would share the same nodes, items or AH demand).
local _, C = ...
local D = C.Data
local floor, max, min = math.floor, math.max, math.min

------------------------------------------------------------------ data (Classic)
-- Skinning: {fromLevel, toLevel, leather, perKill, hide, hideChance}
D.skinTable = {
  { 1, 15, 2318, 1.2, 783, 0.05 },   -- Light Leather / Light Hide
  { 16, 25, 2319, 1.2, 4232, 0.05 }, -- Medium
  { 26, 35, 4234, 1.2, 4235, 0.05 }, -- Heavy
  { 36, 45, 4304, 1.2, 8169, 0.05 }, -- Thick
  { 46, 63, 8170, 1.3, 8171, 0.05 }, -- Rugged
}
-- Herbs and ore by zone level: { fromLevel, toLevel, {itemID, ...} }
D.herbTable = {
  { 1, 15, { 2447, 765 } },                 -- Peacebloom, Silverleaf
  { 15, 25, { 2449, 785, 2450 } },          -- Earthroot, Mageroyal, Briarthorn
  { 25, 35, { 2453, 3355, 3356, 3357 } },   -- Bruiseweed, Wild Steelbloom, Kingsblood, Liferoot
  { 35, 45, { 3818, 3821, 3358, 3819 } },   -- Fadeleaf, Goldthorn, Khadgar's Whisker, Wintersbite
  { 45, 55, { 4625, 8831, 8836, 8838 } },   -- Firebloom, Purple Lotus, Arthas' Tears, Sungrass
  { 55, 63, { 13463, 13464, 13465, 13466 } }, -- Dreamfoil, Golden Sansam, Mountain Silversage, Plaguebloom
}
D.oreTable = {
  { 1, 20, { 2770 } }, { 20, 30, { 2771 } }, { 30, 45, { 2772, 2775 } }, { 40, 50, { 3858 } }, { 50, 63, { 10620 } },
}
-- Rough nodes passed per hour while farming (not a dedicated gathering route)
D.nodesPerHour = { Herbalism = 12, Mining = 8 }

local GATHER = { Skinning = true, Herbalism = true, Mining = true }
local CRAFT = { Leatherworking = true, Alchemy = true, Tailoring = true, Blacksmithing = true, Engineering = true }
D.planProfessions = { "Skinning", "Herbalism", "Mining", "Enchanting", "Leatherworking", "Alchemy", "Tailoring", "Blacksmithing", "Engineering" }

-- Skill needed to skin a mob of this level (Classic)
function C.SkinSkillNeeded(level)
  if level <= 10 then return 1 elseif level <= 20 then return (level - 10) * 10 end
  return level * 5
end

-- Leather value per kill of a skinnable beast (skill = the skinner's skill, or true).
function C.SkinEstimate(level, skill)
  if type(skill) == "number" and skill < C.SkinSkillNeeded(level) then return 0 end
  for _, t in ipairs(D.skinTable) do
    if level >= t[1] and level <= t[2] then
      return floor((C.MatExit(t[3]) or 0) * t[4] + (C.MatExit(t[5]) or 0) * t[6])
    end
  end
  return 0
end

local function bandValue(tbl, level)
  for _, t in ipairs(tbl) do
    if level >= t[1] and level <= t[2] then
      local sum, n = 0, 0
      for _, id in ipairs(t[3]) do local v = C.MatExit(id); if v then sum = sum + v; n = n + 1 end end
      return n > 0 and sum / n or 0
    end
  end
  return 0
end

------------------------------------------------------------------ who is farming
local function myProfile()
  return { class = UnitClass and select(2, UnitClass("player")) or "?", level = UnitLevel and UnitLevel("player") or 1,
    profs = C.char.prof or {}, name = UnitName and UnitName("player") or "You" }
end

-- Partner: grouped Kina user first (newest), else the one typed in Settings.
function C.Partner()
  local best
  local S = C.Share
  if S and S.DB and IsInGroup and IsInGroup() then
    for _, a in pairs(S.DB().authors or {}) do
      local ch = a.char
      local nm = a.name and (a.name:match("^([^%-]+)") or a.name)
      if ch and nm and C.InGroupName(a.name) and (not best or ch.t > best.t) then
        best = { class = ch.class, level = ch.level or 1, profs = ch.profs or {}, name = nm, t = ch.t, live = true }
      end
    end
  end
  if best then return best end
  local st = C.settings
  if st.partnerClass and st.partnerClass ~= "NONE" then
    return { class = st.partnerClass, level = st.partnerLevel or myProfile().level, profs = C.ParseProfs(st.partnerProfs or ""),
      name = "Partner", live = false }
  end
end

-- Settings > You box: two read-only lines of what Kina believes about you.
local function niceClass(c) return c and c ~= "?" and (c:sub(1, 1) .. c:sub(2):lower()) or "?" end
-- only trade skills (the skill-line fallback also catches weapons, languages, Defense...)
local TRADE = { Alchemy = 1, Blacksmithing = 1, Enchanting = 1, Engineering = 1, Herbalism = 1, Leatherworking = 1,
  Mining = 1, Skinning = 1, Tailoring = 1, Cooking = 1, ["First Aid"] = 1, Fishing = 1 }
local function profList(profs)
  local ps = {}
  for n, sk in pairs(profs or {}) do if TRADE[n] then ps[#ps + 1] = n .. " " .. sk end end
  table.sort(ps)
  return ps
end
function C.YouLines()
  local me = myProfile()
  local ps = profList(me.profs)
  local l1 = string.format("|cffffd100%s|r %s %s   |cff9d9d9dprofessions:|r %s", me.name, niceClass(me.class), tostring(me.level or "?"),
    #ps > 0 and table.concat(ps, ", ") or "|cffff8040none read yet (open your skills window once)|r")
  if C.char.lockpicking then
    l1 = l1 .. string.format("   |cff9d9d9dlockpicking:|r %d/%d", C.char.lockpicking, C.char.lockpickingMax or C.char.lockpicking)
  elseif me.class == "ROGUE" then
    l1 = l1 .. "   |cff9d9d9dlockpicking:|r |cffff8040not read yet|r"
  end
  if C.PUBLIC then
    -- public: your reputation and whether you share data (the partner/disenchanter
    -- planning this box shows privately belongs to the hidden advice features)
    local m = C.Rep and C.Rep.Mine and C.Rep.Mine()
    local l2 = m and string.format("|cff9d9d9dKina level:|r %s", m.ok and C.Rep.Roman(m.level) or "|cffff8040log damaged|r") or ""
    l2 = l2 .. "   |cff9d9d9ddata sharing:|r " .. ((C.ShareData and C.ShareData()) and "|cff7CFC00on|r" or "|cffff8040off (Kina level paused)|r")
    return l1, l2
  end
  local de = C.DisenchanterText and C.DisenchanterText()
  local l2 = "|cff9d9d9ddisenchanter:|r " .. (de or "|cffff8040none (disenchant deals hidden)|r")
  local pa = C.Partner()
  if pa then
    local pps = profList(pa.profs)
    l2 = l2 .. string.format("   |cff9d9d9dpartner:|r %s %s %s%s %s", pa.name or "Partner", niceClass(pa.class), tostring(pa.level or "?"),
      #pps > 0 and (", " .. table.concat(pps, ", ")) or "", pa.live and "|cff7CFC00(synced)|r" or "|cff9d9d9d(typed below)|r")
  else
    l2 = l2 .. "   |cff9d9d9dpartner:|r none"
  end
  return l1, l2
end

-- "Herbalism 50, Enchanting 30" -> { Herbalism = 50, Enchanting = 30 }
function C.ParseProfs(text)
  local out = {}
  for name, sk in tostring(text or ""):gmatch("([%a][%a ]-)%s*(%d+)") do
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    out[name] = tonumber(sk)
  end
  return out
end

-- Class priors: kills per hour on normal mobs, on elites, and elites up to how
-- many levels above you. Your measured farm sessions replace these.
local CLASS = {
  HUNTER = { kph = 70, ekph = 22, elite = 0 },    -- pet tanks, kites, solos same-level elites
  WARLOCK = { kph = 60, ekph = 15, elite = -1 },
  MAGE = { kph = 65, ekph = 10, elite = -3 },
  ROGUE = { kph = 60, ekph = 12, elite = -2 },
  DRUID = { kph = 50, ekph = 10, elite = -2 },
  PALADIN = { kph = 45, ekph = 12, elite = -1 },
  WARRIOR = { kph = 50, ekph = 10, elite = -2 },
  PRIEST = { kph = 45, ekph = 8, elite = -3 },
  SHAMAN = { kph = 55, ekph = 12, elite = -1 },
}

-- The profile every farm and plan uses. mode: "solo" | "duo" (default: Settings).
function C.FarmProfile(mode)
  -- grouped with a Kina partner: always the duo profile, so both sides rank alike
  mode = mode or ((C.GroupSize and C.GroupSize() > 1 and C.Partner()) and "duo") or C.settings.farmMode or "solo"
  local me, mate = myProfile(), C.Partner()
  local duo = mode == "duo" and mate ~= nil
  local cm = CLASS[me.class] or { kph = 55, ekph = 10, elite = -2 }
  local base = C.settings.killsPerHour or 60
  local scale = (base ~= 60) and base / 60 or 1 -- you changed kills/hour in Settings: scale the priors
  local function skill(p) return (me.profs[p]) or (duo and mate.profs[p]) or nil end
  local pf = {
    me = me, partner = mate, duo = duo, split = duo and 2 or 1,
    skinner = skill("Skinning") or (C.settings.assumeSkinning and true) or nil,
    herbalist = skill("Herbalism"), miner = skill("Mining"),
    deSkill = max(me.profs.Enchanting or 0, duo and mate.profs.Enchanting or 0, C.settings.deFriend or 0),
    bagSlots = C.settings.bagSlots or 70, tripMin = C.settings.tripMinutes or 8,
  }
  if pf.deSkill == 0 then pf.deSkill = nil end
  local lvl = duo and max(me.level, mate.level) or me.level
  -- a pair takes elites two levels higher than the stronger of you alone
  pf.eliteMax = duo and (lvl + 2) or (cm.elite >= 0 and lvl + cm.elite or nil)
  pf.kph = function(elite)
    local k = (elite and cm.ekph or cm.kph) * scale
    if duo then k = k * 1.7 end
    return k
  end
  return pf
end

-- Partner's Enchanting counts as a disenchanter for routes and deals.
local baseSkill = C.DisenchantSkill
-- Everyone who can disenchant for you: you and your alts, the Friend's Enchanting
-- box, your partner, and any Kina user who shared with you in the last 3 days
-- (you don't have to be grouped right now). Returns { {name, skill}, ... } best first.
function C.Disenchanters()
  local best = {}
  local function add(name, skill)
    if skill and (not best[name] or skill > best[name]) then best[name] = skill end
  end
  for _, ch in pairs(C.db.chars or {}) do add("you", ch.prof and ch.prof.Enchanting) end
  add("friend", C.settings.deFriend)
  local mate = C.Partner()
  if mate and mate.profs then add(mate.name or "partner", mate.profs.Enchanting) end
  local S = C.Share
  if S and S.DB and C.settings.shareEnchanters ~= false then
    local now = C.Now()
    for _, a in pairs(S.DB().authors or {}) do
      local ch = a.char
      local sk = ch and ch.profs and ch.profs.Enchanting
      if sk and now - (ch.t or a.seen or 0) < 3 * 86400 then
        add(a.name and ((Ambiguate and Ambiguate(a.name, "short")) or a.name:match("^[^%-]+")) or "friend", sk)
      end
    end
  end
  local list = {}
  for name, skill in pairs(best) do list[#list + 1] = { name = name, skill = skill } end
  table.sort(list, function(a, b) return a.skill > b.skill end)
  return list
end
function C.DisenchantSkill()
  local s = baseSkill and baseSkill() or nil
  for _, e in ipairs(C.Disenchanters()) do s = max(s or 0, e.skill) end
  return s
end
-- "Vellaura (Enchanting 1)" or nil
function C.DisenchanterText()
  local e = C.Disenchanters()[1]
  if not e then return nil end
  return string.format("%s (Enchanting %d)", e.name == "you" and "you" or e.name, e.skill)
end

------------------------------------------------------------------ profession values
-- Gold/hour each profession adds on the given farms (top rows of a ranking).
local function farmsFor(pf, n)
  local L = pf.me.level
  local rows = C.RankFarms({ lo = max(1, L - 6), hi = min(63, L + 4), kind = "world", profile = pf })
  local top = {}
  for i = 1, min(n or 5, #rows) do top[i] = rows[i] end
  return top, L
end

local function avg(list, f)
  if #list == 0 then return 0 end
  local s = 0
  for _, r in ipairs(list) do s = s + (f(r) or 0) end
  return s / #list
end

-- One player's value for each profession, given a profile (solo or duo).
function C.ProfessionValues(pf, who)
  who = who or pf.me
  local test = {}
  for k, v in pairs(pf) do test[k] = v end
  test.skinner = true; test.deSkill = nil
  local farms, L = farmsFor(test, 5)
  local lvl = who.level or L
  local gph = C.Econ and C.Econ.GoldPerHour() or 0
  local out = {}
  -- skinning: leather per kill on beast farms
  out.Skinning = { value = avg(farms, function(r) return r.ctype == "Beast" and (r.skins or 0) * r.kph or 0 end),
    how = "leather from beasts on your best farms (skins measured where you've skinned; Classic estimate elsewhere)" }
  -- gathering while farming: measured by the farm widget (your timed farms where you
  -- picked that kind of node); until then a rough Classic-rate estimate, marked as such
  local function measured(sub)
    if who ~= pf.me then return nil end
    local v, secs = 0, 0
    for _, s in ipairs(C.db.sessions or {}) do
      if s.gather and s.result and (s.result.secs or 0) >= 300 then
        local sv, any = 0, false
        for id, n in pairs(s.gather) do
          local r = C.Item(id)
          if r and r.cls == 7 and r.sub == sub then sv = sv + (C.FarmValue(id) or 0) * n; any = true end
        end
        if any then v = v + sv; secs = secs + s.result.secs end
      end
    end
    if secs >= 1800 then return v * 3600 / secs, secs / 3600 end
  end
  for prof, sub in pairs({ Herbalism = 9, Mining = 7 }) do
    local m, hours = measured(sub)
    if m then
      out[prof] = { value = m, how = string.format("measured: your timed farms (%.1f h)", hours) }
    else
      local n = D.nodesPerHour[prof]
      out[prof] = { value = n * bandValue(prof == "Herbalism" and D.herbTable or D.oreTable, lvl) * 1.5,
        how = string.format("ESTIMATE: ~%d nodes/hour (Classic rates). Run the farm widget to measure", n) }
    end
  end
  -- enchanting: DE premium + bag/trip savings, on the same farms
  do
    local premium, slotsSaved = 0, 0
    local deSkill = max(who.profs and who.profs.Enchanting or 0, 1)
    for _, r in ipairs(farms) do
      local own = C.LootRecord and C.LootRecord(r.npc) or C.db.loot[r.npc]
      local kills = math.max(1, r.ownKills or 0)
      for id, n in pairs(own and own.items or {}) do
        local ir = C.Item(id)
        if ir and C.IsGear(ir) and ir.q and ir.q >= 2 and ir.q <= 3 and C.CanDE(id) == true then
          local rate = n / kills * r.kph
          local dv = C.DEValue(id)
          local other = math.max(C.AHNet(id, 1) or 0, C.VendorPrice(id, true) or 0)
          if dv then premium = premium + math.max(0, dv.ev - other) * rate end
          slotsSaved = slotsSaved + rate
        end
      end
    end
    premium = premium / math.max(1, #farms); slotsSaved = slotsSaved / math.max(1, #farms)
    local tripsSaved = slotsSaved / (pf.bagSlots or 70)
    local timeValue = tripsSaved * (pf.tripMin or 8) / 60 * gph
    out.Enchanting = { value = premium + timeValue, premium = premium, timeValue = timeValue,
      how = string.format("disenchant premium %s/h + %.1f fewer town trips/h (%s/h of your time)",
        C.Money(premium), tripsSaved, C.Money(timeValue)) }
  end
  -- crafting: top margins at your skill, capped by how fast the AH buys them
  for prof in pairs(CRAFT) do
    local skill = who.profs and who.profs[prof] or 1
    local best, bestName = 0, nil
    for _, r in ipairs(C.CraftRows({ prof = prof, mine = false })) do
      if r.profit and r.profit > 0 and (r.l or 0) <= skill + 50 then
        local v = C.Econ and C.Econ.Velocity(r.out) or 0.1
        local perHour = r.profit * math.min(5, v * 0.5)
        if perHour > best then best, bestName = perHour, r.name end
      end
    end
    out[prof] = { value = best, how = bestName and ("best: " .. bestName .. " (limited by AH demand)") or "no profitable recipe priced yet" }
  end
  for p, v in pairs(out) do v.value = floor(v.value or 0); v.prof = p end
  return out
end

-- Best two professions for you, or for the pair (no doubled gathering/enchanting).
function C.ProfessionPlan()
  local pf = C.FarmProfile(C.Partner() and "duo" or "solo")
  local mine = C.ProfessionValues(pf, pf.me)
  local mate = pf.partner and C.ProfessionValues(pf, pf.partner) or nil
  local list = D.planProfessions
  local function pairsOf()
    local out = {}
    for i = 1, #list do for j = i + 1, #list do out[#out + 1] = { list[i], list[j] } end end
    return out
  end
  -- a profession you already have gets a 10% edge: re-training costs time and gold
  local function worth(vals, p, who)
    local v = vals[p] and vals[p].value or 0
    if who and who.profs and who.profs[p] then v = v * 1.1 end
    return v
  end
  local best
  if not mate then
    for _, a in ipairs(pairsOf()) do
      local v = worth(mine, a[1], pf.me) + worth(mine, a[2], pf.me)
      if not best or v > best.value then best = { value = v, me = a } end
    end
  else
    for _, a in ipairs(pairsOf()) do
      for _, b in ipairs(pairsOf()) do
        local taken, v = {}, 0
        for _, p in ipairs(a) do taken[p] = true; v = v + worth(mine, p, pf.me) end
        for _, p in ipairs(b) do
          -- the same profession twice adds nothing: one gatherer per node/corpse, one
          -- enchanter is enough, and two crafters share the same AH demand
          if not taken[p] then v = v + worth(mate, p, pf.partner) end
        end
        if not best or v > best.value then best = { value = v, me = a, partner = b } end
      end
    end
    -- per person (loot is split)
    best.value = best.value / 2
  end
  return best, mine, mate, pf
end
