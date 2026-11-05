-- Kina: main window and detail panels.
-- Every tab: click a column header to sort (again to reverse), type in the search
-- box to filter. Left-click a row for details, right-click for actions,
-- Shift-click an item to link it in chat.
local _, C = ...
local ROWS, ROW_H = 19, 18   -- ROWS = rows at the default size; more appear when you enlarge it
local MAX_ROWS = 50
local W, H = 900, 520        -- default size; drag the bottom-right corner to resize
local ui = { sort = {}, search = {}, w = W, h = H, visible = ROWS }
C.UI = ui -- 1.2.0: Sheets.lua (You tab, Debts page) works inside this window
local fitWidths -- defined with the layout code below
C.ui = ui

local function itemName(id)
  local r = C.Item(id)
  return (r and r.name) or ("item " .. tostring(id))
end
local function qualityColor(id)
  local r = C.Item(id)
  local c = r and r.q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.q]
  return c and c.hex or "|cffffffff"
end
local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- Loose search: case, punctuation and word order don't matter; every word you type
-- must appear somewhere ("fang druid", "gloves fang", "druidofthefang" all work).
local function norm(s) return (plain(s):lower():gsub("[^%w]+", " ")) end
function C.LooseMatch(query, hay)
  local q = norm(query or "")
  if not q:find("%S") then return true end
  local h = " " .. norm(hay or "") .. " "
  local squashedH, squashedQ = h:gsub("%s", ""), q:gsub("%s", "")
  if squashedH:find(squashedQ, 1, true) then return true end
  for word in q:gmatch("%S+") do
    if not h:find(word, 1, true) then return false end
  end
  return true
end
local function itemCell(id, extra) return qualityColor(id) .. itemName(id) .. "|r" .. (extra or "") end

------------------------------------------------------------------ tab builders
-- Each returns: header text, column titles, column x positions, rows.
-- A row: { cols = {display...}, sort = {raw values...}, id = itemID?, npc = npcID?, tip = text? }
local tabs = {}
-- 0.15.7: Deals folded into Hot; Invest, Vendor, Crafts, Plan and Favor removed from the window
-- (their code stays: Hot still uses the craft and deal maths)
-- 0.16.1: every tab is back (Deals, Invest, Vendor, Crafts, Plan, Favor, Bags); Hot keeps
-- its deals, recipe advice, Show filter and Options too
-- Private Kina: only what the duo needs. Where to make money (Dungeons, Farms, Hot),
-- how to level the professions cheaply (Skill up), the farm log (Session), Settings.
-- (The other tabs' code and data are kept, just not shown.)
local tabOrder = { "Dungeons", "Farms", "Hot", "Skill up", "Session", "Settings" }
-- Public Kina: the farm log with debts and payments, the ledger, and settings. The
-- advice tabs (and the data behind them) come back in a later public version.
if C.PUBLIC then tabOrder = { "Session", "Ledger", "You", "Settings" } end -- 1.2.0: You (character sheet)
local HOME = tabOrder[1] == "Session" and "Session" or "Hot"
local TAB_OK = {}
for _, t in ipairs(tabOrder) do TAB_OK[t] = true end

tabs.Bags = function()
  local rows, totals = C.AdviseBags()
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = { id = r.id, cols = { itemCell(r.id, " x" .. r.count), r.action, C.Money(r.unit), C.Money(r.total), r.why },
      sort = { itemName(r.id), r.action, r.unit or 0, r.total or 0, r.why } }
  end
  local head = string.format("Sell now %s   Sell %s   Disenchant %s   Vendor %s   Hold %s",
    C.Money(totals["SELL NOW"] or 0), C.Money((totals["SELL"] or 0) + (totals["SELL (can wait)"] or 0)),
    C.Money(totals["DISENCHANT"] or 0), C.Money(totals["VENDOR"] or 0), C.Money(totals["HOLD"] or 0))
  return head, { "Item", "Do this", "Each", "Total", "Why" }, { 0, 290, 410, 500, 590 }, out
end

-- Level range for farms: from the "From" box (default 1) up to the "To" box
-- (default your level + 2). Type your own numbers into the boxes on the Farms tab.
function C.FarmBand()
  local L = (UnitLevel and UnitLevel("player")) or 1
  local lo = C.settings.farmLo or math.max(1, L - 3)
  local hi = C.settings.farmHi or math.min(60, L + 2)
  if hi < lo then lo, hi = hi, lo end
  return lo, hi
end
local function shiftFarmHi(d)
  local lo, hi = C.FarmBand()
  C.settings.farmHi = math.max(lo, math.min(60, hi + d))
end

local FARM_SHOW = {
  { key = "all", label = "All farms" },
  { key = "kill", label = "Kill farms", kinds = { Kill = true, ["Pick+Kill"] = true, Camp = true } },
  { key = "camps", label = "Camps", kinds = { Camp = true } },
  { key = "favs", label = "Favorite camps", kinds = { Camp = true }, fav = true },
  { key = "pockets", label = "Pockets", rogue = true, kinds = { Pick = true, ["Pick+Kill"] = true, Junkbox = true } },
  { key = "locks", label = "Locks and boxes", rogue = true, kinds = { Lockpick = true, Service = true, Junkbox = true } },
  { key = "stealth", label = "Stealth runs", kinds = { ["Chest run"] = true, ["Stealth nodes"] = true } },
  { key = "druid", label = "Druid routes", druid = true, kinds = { ["Underwater herbs"] = true, Underwater = true, ["Niche herb"] = true, ["Chest run"] = true, ["Stealth nodes"] = true } },
}
C.FarmShow = FARM_SHOW
local KIND_COLOR = { Camp = "|cff7CFC00", Kill = "|cffffffff", ["Pick+Kill"] = "|cffffd100", Pick = "|cffffd100", Junkbox = "|cffffd100",
  Lockpick = "|cff9fc5ff", Service = "|cff9fc5ff", ["Chest run"] = "|cffc69cff", ["Stealth nodes"] = "|cffc69cff",
  ["Underwater herbs"] = "|cff60e0c0", Underwater = "|cff60e0c0", ["Niche herb"] = "|cff60e0c0" }

local function planText(plan)
  if #plan == 0 then return "No farm data for these levels yet: kill, pick and loot and it fills in. Type the level range in the boxes above." end
  local parts = {}
  for i, r in ipairs(plan) do
    local what = r.kind == "Lockpick" and ("lockpicking at " .. r.name) or r.name
    local val = (C.settings.farmMetric == "hour" and r.perHour and r.perHour > 0) and (C.Money(r.perHour) .. "/h")
      or (r.per and r.per > 0 and (C.Money(r.per) .. "/kill")) or (r.perText or "")
    parts[#parts + 1] = string.format("|cffffd100%d|r %s%s|r %s", i, KIND_COLOR[r.kind] or "", what, val)
  end
  return "Now: " .. table.concat(parts, "   ") .. "   |cff9d9d9d(click #1)|r"
end

-- Where a farm row's waypoint is: { map, x, y } (0-1), cached (spots don't move)
local spotCache = {}
local function rowSpot(r)
  local key = (r.camp and ("c" .. tostring(r.camp.key))) or (r.npc and ("n" .. r.npc)) or ("r" .. tostring(r.name))
  local hit = spotCache[key]
  if hit and not r.camp then return hit[1], hit[2], hit[3] end -- camps can get a new pin, so always fresh
  local m, x, y
  if r.camp and C.CampCenter then m, x, y = C.CampCenter(r.camp) end
  local rt = r.route
  if not m and rt and rt.map and rt.x then m, x, y = rt.map, rt.x / 100, rt.y / 100 end
  if not m and r.npc then
    local own = C.LootRecord and C.LootRecord(r.npc) or C.db.loot[r.npc]
    if own and own.locs then
      local best
      for map, p in pairs(own.locs) do if not best or p.n > best.n then m, best = map, p end end
      if best then x, y = best.x, best.y end
    end
    if not m then
      local f = C.NPCFacts and C.NPCFacts(r.npc)
      local p = f and C.Nearest(f.spawns)
      if p then m, x, y = p[1], p[2], p[3] end
    end
  end
  if m and x then spotCache[key] = { m, x, y } end
  return m, x, y
end
-- yards from you to the row's waypoint (nil = unknown; math.huge = another continent)
local function worldPos(map, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not ok or not pos then return nil end
  return cont, pos.x, pos.y
end
local function rowDistance(r)
  local m, x, y = rowSpot(r)
  if not m then return nil end
  local pm, px, py = C.PlayerPos()
  if not (pm and px) then return nil end
  local c1, ax, ay = worldPos(m, x, y)
  local c2, bx, by = worldPos(pm, px, py)
  if c1 and c2 then
    if c1 ~= c2 then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
  end
  return nil
end
local function distText(d)
  if not d then return "|cff9d9d9d?|r" end
  if d == math.huge then return "|cff9d9d9dother continent|r" end
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d + 0.5))
end

tabs.Farms = function()
  local lo, hi = C.FarmBand()
  local kind = ui.farmKind or "world"
  local mode = C.ClassMode and C.ClassMode() or nil
  -- typing in the search box looks through EVERY mob Kina knows (any level, elites
  -- too), by mob name or by the name of anything it drops
  local q = ui.search.Farms
  local searching = q and q:find("%S") and true or false
  local function match(name, npc)
    if C.LooseMatch(q, name) then return true end
    local pool = C.FarmPool and C.FarmPool()[npc]
    local own = C.LootRecord and C.LootRecord(npc)
    for _, src in ipairs({ pool and pool.items or {}, own and own.items or {} }) do
      for id in pairs(src) do local r = C.Item(id); if r and r.name and C.LooseMatch(q, r.name) then return true end end
    end
    return false
  end
  local rows, pending = C.ClassFarmRows({ lo = lo, hi = hi, kind = kind, mode = mode, all = searching, match = searching and match or nil })
  if searching then
    local kept = {}
    for _, r in ipairs(rows) do if (r.npc and match(r.name or "", r.npc)) or (not r.npc and C.LooseMatch(q, r.name or "")) then kept[#kept + 1] = r end end
    rows = kept
  end
  if pending > 0 and (ui.nameRetries or 0) < 5 then
    ui.nameRetries = (ui.nameRetries or 0) + 1
    C.After(1.5, function() if ui.tab == "Farms" then C.Refresh() end end)
  elseif pending == 0 then ui.nameRetries = 0 end
  local show = C.settings.farmShow or "all"
  local filter
  local favOnly
  for _, f in ipairs(FARM_SHOW) do if f.key == show then filter = f.kinds; favOnly = f.fav end end
  local out = {}
  for _, r in ipairs(rows) do
    if (not filter or filter[r.kind]) and (not favOnly or r.fav) then
      local per = r.per and (C.Money(r.per) .. ((r.kind == "Pick" or r.kind == "Pick+Kill") and "" or "")) or (r.perText or "-")
      if r.kind == "Pick+Kill" and r.pick then per = C.Money(r.per) .. " |cffaaaaaa(pick " .. C.Money(r.pick) .. ")|r" end
      if r.perText and r.per then per = r.perText end
      local okd, dist = pcall(rowDistance, r)
      if not okd then dist = nil end
      out[#out + 1] = { npc = r.npc, farm = r.farm, route = r, id = (not r.npc) and r.item or nil, cols = {
        (r.fav and "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t " or "") .. r.name .. (r.level and (" (" .. r.level .. ")") or ""),
        (KIND_COLOR[r.kind] or "") .. r.kind .. "|r",
        per,
        r.perCommon and C.Money(r.perCommon) or "-",
        (r.perHour and r.perHour > 0) and (r.perHourIsEstimate and ("|cff9d9d9d~" .. C.Money(r.perHour) .. "|r") or C.Money(r.perHour)) or "|cff9d9d9dtime it|r",
        r.evidence or "", distText(dist), r.where or "" },
        sort = { r.name, (C.FarmKindOrder[r.kind] or 9), r.per or -1, r.perCommon or -1, r.perHour or -1, r.evidenceN or -1, dist or 2e9, r.where or "" },
        tip = (r.note or (r.route and r.route.note) or "") .. (r.farm and string.format("%sPer kill is your share%s. %s",
          (r.note or (r.route and r.route.note)) and "\n" or "",
          (r.farm.group or 1) > 1 and string.format(" (%s per kill / %d in your group)", C.Money(r.farm.perKillTotal or 0), r.farm.group) or "",
          r.farm.rate and string.format("Gold/hour from %d timed farm%s %s.", r.farm.rate.n, r.farm.rate.n == 1 and "" or "s", r.farm.rate.label)
            or "Gold/hour: 0 until you time a farm here (start the farm widget at the flight path, stop it back at the AH).") or "") }
    end
  end
  local plan = C.FarmPlan(rows)
  local head = planText(plan) .. (pending > 0 and ("  (" .. pending .. " names loading)") or "")
  local group = C.GroupSize and C.GroupSize() or 1
  local metricCol = ({ kill = 3, common = 4, hour = 5 })[C.settings.farmMetric or "kill"] or 3
  if not ui.sort.Farms or ui.sort.Farms.auto then ui.sort.Farms = { col = metricCol, desc = true, auto = true } end
  local yours = group > 1 and " (yours)" or ""
  if searching then head = "|cffffd100Search:|r every mob Kina knows (any level), by name or by what it drops. Clear the box to go back to your level range." end
  return head, { "Farm (level)", "Type", "Per kill" .. yours, "No rare" .. yours, "Gold/hour" .. yours, "Evidence", "Distance", "Where" },
    { 0, 200, 270, 360, 450, 540, 650, 730 }, out,
    { top = 22, farms = true, searched = searching, headClick = plan[1] and function() C.ShowFarmRow(plan[1]) end }
end

-- Every buy opportunity, ranked by the deal score (Econ.lua): expected profit after
-- the cut, deposit risk and your time, sped up by how fast it sells. Click a column
-- to sort by it; "Best deal" puts the ranking back.
local guardCell, guardTip, minSellCell, minSellSort
local function roiText(roi) return roi and string.format("%.0f%%", roi * 100) or "-" end
-- Deals: what you can verify on screen right now. Buy price now vs. a vendor price
-- or today's cheapest material listings. No forecasts here (see Investments).
-- Guardian: chance of ending up with less gold than you paid, for the number you'd buy
local function lossColor(p) return p <= 0.05 and "|cff7CFC00" or (p <= 0.3 and "|cffffd100" or "|cffff6060") end
-- The lowest price to list each material at and still not lose money on what you
-- paid: every material's price scaled down by the same share (paid / worth now).
local function minPrices(d)
  if d.kind ~= "Disenchant" or not d.mats or not d.sell or d.sell <= 0 then return nil end
  local f = (d.cost or 0) / d.sell
  local out = {}
  for mat in pairs(d.mats) do
    local now = C.Econ.MatNow(mat)
    if now then
      local listNow = now / (1 - C.settings.ahCut)
      out[#out + 1] = { mat = mat, min = math.ceil(listNow * f), now = math.floor(listNow + 0.5) }
    end
  end
  table.sort(out, function(a, b) return a.min > b.min end)
  return out
end
local function shortName(id) local n = itemName(id); return (n:gsub(" Essence", " Ess."):gsub(" Shard", " Sh.")) end
minSellCell = function(d)
  if d.kind ~= "Disenchant" then return C.Money(d.sell) .. " |cff9d9d9d(vendor pays)|r" end
  local m = minPrices(d)
  if not m or #m == 0 then return C.Money(d.sell) .. " |cff9d9d9d(mats)|r" end
  local parts = {}
  for _, x in ipairs(m) do parts[#parts + 1] = shortName(x.mat) .. " " .. C.Money(x.min) end
  return table.concat(parts, ", ")
end
minSellSort = function(d)
  local m = d.kind == "Disenchant" and minPrices(d)
  return (m and m[1] and m[1].min) or d.sell or 0
end
local function minSellTip(d)
  local m = minPrices(d)
  if not m or #m == 0 then return "" end
  local lines = {}
  for _, x in ipairs(m) do lines[#lines + 1] = string.format("   %s: list at %s or more (cheapest now %s)", itemName(x.mat), C.Money(x.min), C.Money(x.now)) end
  return "\n|cffffd100Sell at least|r (to get back what you paid, after the 5% cut):\n" .. table.concat(lines, "\n")
end
guardCell = function(d)
  if not d.loss then return "-" end
  return lossColor(d.loss) .. string.format("%.0f%%", d.loss * 100) .. "|r |cff9d9d9d(" .. (d.lossN or d.units) .. ")|r"
end
guardTip = function(d)
  if not d.lossGrid then return d.kind == "AH->Vendor" and "\n|cffffd100Guardian 0%:|r a vendor pays a fixed price, no luck involved." or "" end
  local parts, ks = {}, {}
  for k in pairs(d.lossGrid) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do parts[#parts + 1] = string.format("%d: %s%.0f%%|r", k, lossColor(d.lossGrid[k]), d.lossGrid[k] * 100) end
  return string.format("\n|cffffd100Guardian:|r chance you get back less than you paid if you buy %d (what your gold covers)%s.\n   bought: %s%s",
    d.lossN or d.units, d.lossN ~= d.units and (", Kina counts " .. d.units) or "", table.concat(parts, "   "),
    d.safeN and string.format("\n   Safe from about %d bought (5%% or less).", d.safeN) or "\n   No sample size here is safe: the average depends on rare drops.")
end
tabs.Deals = function()
  local E = C.Econ
  local passive = ui.dealView == "passive"
  local out = {}
  local gold = (GetMoney and GetMoney()) or 0
  local list = E.Deals(passive)
  ui.affordHidden = 0
  if C.settings.dealAfford then
    local keep = {}
    for _, d in ipairs(list) do
      if (d.maxEach or d.buy or 0) + (d.deposits or 0) / math.max(1, d.units or 1) <= gold then keep[#keep + 1] = d end
    end
    ui.affordHidden = #list - #keep; list = keep
  end
  for _, d in ipairs(list) do
    local col = d.worth and "" or "|cff808080"
    local age = d.stale and (" |cffff8040(" .. (d.priceAge >= 60 and (math.floor(d.priceAge / 60) .. "h") or (d.priceAge .. "m")) .. " old)|r") or ""
    out[#out + 1] = { id = d.id, roi = d.roi, worth = d.worth, deal = d,
      cols = { itemCell(d.id), col .. d.kind .. (d.tooHigh and (" (Ench " .. d.needSkill .. ")") or "") .. "|r" .. age,
        C.Money(d.maxEach or d.buy), (d.available and d.available > d.units) and (d.units .. " |cff9d9d9dof " .. d.available .. "|r") or tostring(d.units),
        d.deposits > 0 and C.Money(d.deposits) or "|cff7CFC00none|r",
        (d.short and "|cffff6060" or "") .. C.Money(d.cash) .. (d.short and "|r" or ""),
        (d.expected >= 0 and "|cff7CFC00" or "|cffff6060") .. C.Money(d.expected) .. "|r", roiText(d.roi),
        guardCell(d), minSellCell(d) },
      sort = { itemName(d.id), d.kind, d.maxEach or d.buy, d.units, d.deposits, d.cash, d.expected, d.roi or 0, d.loss or 0, minSellSort(d), d.score },
      tip = string.format("|cffffd100Sniper:|r max price each %s, how many %d, spend up to %s\n"
        .. "|cffffd100Cash needed:|r %s = %s to buy + %s deposits\n"
        .. "Average paid %s, %s %s each: %s profit per item (ROI %s), %s total after %s for your time.\n%s%s",
        C.Money(d.maxEach or d.buy), d.units, C.Money(d.capital),
        C.Money(d.cash), C.Money(d.capital), C.Money(d.deposits),
        C.Money(d.cost), d.kind == "Disenchant" and "materials sell now for" or "a vendor pays", C.Money(d.sell),
        C.Money(d.profit), roiText(d.roi), C.Money(d.expected), C.Money(d.overhead), d.note or "",
        d.stale and string.format("\nThese prices are %d min old (from %s): check the live listings.", d.priceAge or 0,
          d.priceFrom and ((Ambiguate and Ambiguate(d.priceFrom, "short") or d.priceFrom) .. "'s scan") or "your last scan") or "") .. guardTip(d) .. minSellTip(d) }
  end
  if not ui.sort.Deals or ui.sort.Deals.auto then ui.sort.Deals = { col = 11, desc = true, auto = true } end
  local age = C.ScanAgeMinutes()
  local head = string.format("%s Buy at or under Max each (sniper settings). Your time: %s per trade. Scan %s. Gold %s.",
    passive and "|cff7CFC00Passive (nothing lost waiting):|r" or "|cffffd100Deals right now:|r vendor flips and disenchants at today's prices.",
    C.Money(E.Overhead()), age and (age .. " min ago") or "none yet", C.Money(gold))
    .. ((C.market.quick and C.market.quick.complete and (C.market.quick.t or 0) > (C.market.scanTime or 0))
      and string.format(" |cff7CFC00Quick scan %ds ago: deals checked against it.|r", C.Now() - C.market.quick.t) or "")
  -- nothing to show: say why, and what to do about it
  local empty
  if #out == 0 then
    local parts = {}
    if not age then
      parts[1] = "No AH scan yet. Open the auction house and click Scan AH (bottom right)."
    else
      local n = 0; for _ in pairs(C.market.items) do n = n + 1 end
      parts[#parts + 1] = string.format("No deals right now. Kina checked %d items from your scan %d min ago.", n, age)
      parts[#parts + 1] = "- AH->Vendor: nothing is listed under what a merchant pays for it. These are rare and get bought fast; scan again later."
      local who = C.DisenchanterText and C.DisenchanterText()
      if not who then
        parts[#parts + 1] = "- Disenchant deals are off: Kina doesn't know anyone who can disenchant for you. Group with your enchanter once (Kina remembers their skill for 3 days), "
          .. "or type their skill in Settings > Friend's Enchanting skill."
      else
        parts[#parts + 1] = "- Disenchant: no gear is listed under what its materials sell for. Disenchanter: " .. who .. "."
      end
      if passive then parts[#parts + 1] = "- You're on View: passive income (no-deposit deals only). Click it for every deal." end
    end
    empty = table.concat(parts, "\n")
  end
  return head, { "Item", "Type", "Max each", "Units", "Deposits", "Cash needed", "Profit", "ROI", "Guardian", "Sell at least" },
    { 0, 175, 285, 350, 405, 475, 560, 635, 680, 765 }, out, { deals = true, empty = empty }
end

tabs.Invest = function()
  local E = C.Econ
  local passive = false
  local out = {}
  local gold = (GetMoney and GetMoney()) or 0
  local function conf(d)
    local c = d.confidence or 1
    local col = c >= 0.8 and "|cff7CFC00" or (c >= 0.4 and "|cffffd100" or "|cffff6060")
    return col .. string.format("%.0f%%", c * 100) .. (d.measured and "" or "~") .. "|r"
  end
  local list = E.Investments()
  ui.affordHidden = 0
  if C.settings.dealAfford then
    local keep = {}
    for _, d in ipairs(list) do
      if (d.maxEach or d.buy or 0) + (d.deposits or 0) / math.max(1, d.units or 1) <= gold then keep[#keep + 1] = d end
    end
    ui.affordHidden = #list - #keep; list = keep
  end
  for _, d in ipairs(list) do
    local col = d.worth and "" or "|cff808080"
    out[#out + 1] = { id = d.id, roi = d.roi, worth = d.worth, deal = d,
      cols = { itemCell(d.id), col .. d.kind .. (d.stale and (" |cffff8040(" .. (d.priceAge and d.priceAge >= 60 and (math.floor(d.priceAge / 60) .. "h") or ((d.priceAge or 0) .. "m")) .. " old)|r") or "") .. "|r",
        C.Money(d.maxEach or d.buy), (d.available and d.available > d.units) and (d.units .. " |cff9d9d9dof " .. d.available .. "|r") or tostring(d.units),
        d.deposits > 0 and C.Money(d.deposits) or "|cff7CFC00none|r",
        (d.short and "|cffff6060" or "") .. C.Money(d.cash) .. (d.short and "|r" or ""),
        (d.expected >= 0 and "|cff7CFC00" or "|cffff6060") .. C.Money(d.expected) .. "|r",
        roiText(d.roi), conf(d), E.Hours(d.hours) },
      sort = { itemName(d.id), d.kind, d.maxEach or d.buy, d.units, d.deposits, d.cash, d.expected, d.roi or 0,
        d.confidence or 1, d.hours or 0, passive and d.passiveScore or d.score },
      tip = string.format("|cffffd100Sniper:|r max price each %s, how many %d, spend up to %s\n"
        .. "|cffffd100Cash needed:|r %s = %s to buy + %s deposits to list %s\n"
        .. "Average paid %s, receive %s each after the cut: %s profit per item (ROI %s).\n"
        .. "Expected: %s after %s of relist deposits and %s for your time.\n"
        .. "|cffffd100Confidence %s|r that everything sells within the time the profit lasts; sold out in about %s.%s\n"
        .. "   = buyers in time %s x price holds above break-even %s%s\n%s%s",
        C.Money(d.maxEach or d.buy), d.units, C.Money(d.capital),
        C.Money(d.cash), C.Money(d.capital), C.Money(d.deposits), d.kind == "Disenchant" and "the materials" or "them",
        C.Money(d.cost), C.Money(d.sell), C.Money(d.profit), roiText(d.roi),
        C.Money(d.expected), C.Money(d.depositsLost or 0), C.Money(d.overhead),
        string.format("%.0f%%", (d.confidence or 1) * 100), E.Hours(d.hours),
        d.measured and "" or " (~ = demand estimated: a few more scans measure it)",
        string.format("%.0f%%", (d.demand or 1) * 100), string.format("%.0f%%", (d.priceOK or 1) * 100),
        (d.available and d.available > d.units) and string.format("\n   Only %d of the %d listed (%s) reach your %d%% confidence: buying all of them is riskier.",
          d.units, d.available, C.Money(d.availableCost or 0), C.settings.minConfidence or 75) or "",
        d.note or "", d.stale and string.format("\nThese prices are %d min old (from %s): check the live price; the detail panel works out profit at any price.", d.priceAge or 0, d.priceFrom and ((Ambiguate and Ambiguate(d.priceFrom, "short") or d.priceFrom) .. "'s scan") or "your last scan") or "") }
  end
  if not ui.sort.Invest or ui.sort.Invest.col == 9 and ui.sort.Invest.auto then ui.sort.Invest = { col = 11, desc = true, auto = true } end
  -- how much history there is so far
  local ready, total = 0, 0
  for id in pairs(C.market.items) do total = total + 1; if C.Econ.DataStatus(id) then ready = ready + 1 end end
  local head = string.format("|cffffd100Investments|r (resale, merchant->AH): only items with %d+ days and %d+ scans of history where Kina has SEEN them sell. %d of %d items qualify so far%s",
    C.settings.investDays or 7, C.settings.investScans or 10, ready, total,
    ready == 0 and ": scan regularly (and share with your party) and this fills in." or ". Confidence and timing come from that history.")
  local empty
  if #out == 0 then
    local maxDays, maxScans, sold = 0, 0, 0
    for id in pairs(C.market.items) do
      local _, d, sc, sales = C.Econ.DataStatus(id)
      if d > maxDays then maxDays = d end
      if sc > maxScans then maxScans = sc end
      if sales then sold = sold + 1 end
    end
    local needD, needS = C.settings.investDays or 7, C.settings.investScans or 10
    empty = string.format("Nothing here yet: this tab only lists items with enough history to predict a resale (it ignores today's asking prices, which can be fake).\n\n"
      .. "Your history so far: %d of %d days, %d of %d scans, sales seen on %d items.\n"
      .. "Scan every time you're at the AH (Scan AH keeps rescanning every 15 min while it's open), and group with your partner so your scans pool. "
      .. "The first items qualify in about %d more day%s.\n\n"
      .. "In a hurry? Settings > Investments: days of history / scans of history lowers the bar (less reliable).",
      maxDays, needD, maxScans, needS, sold, math.max(0, needD - maxDays), (needD - maxDays == 1) and "" or "s")
    if ready > 0 then empty = string.format("%d items have enough history, but none is a profitable buy right now at your confidence target (Settings > Confidence I need, now %d%%).",
      ready, C.settings.minConfidence or 75) end
  end
  return head,
    { "Item", "Type", "Max each", "Units", "Deposits", "Cash needed", "Exp. profit", "ROI", "Confidence", "Sells in" },
    { 0, 190, 285, 350, 392, 462, 545, 628, 680, 760 }, out, { empty = empty }
end

tabs.Vendor = function()
  local out = {}
  for i, f in ipairs(C.VendorFlips()) do
    if i > 250 then break end
    local hours, odds = C.Econ.SellTime(f.id, f.ah)
    local ev = C.Econ.Evaluate({ cost = f.buy, sell = f.ah * (1 - C.settings.ahCut), units = 1, deposit = C.Econ.DepositFor(f.id, 1), odds = odds, hours = hours })
    out[#out + 1] = { id = f.id, vendorItem = true, roi = f.margin, worth = ev.worth, cols = { itemCell(f.id), C.Money(f.buy), C.Money(f.ah),
      C.Money(f.net), string.format("%.0f%%", f.margin * 100), f.listed .. " / " .. f.sellers .. (f.stock and (" (stock " .. f.stock .. ")") or ""),
      (f.who or "?") .. ", " .. (f.where or "?") },
      sort = { itemName(f.id), f.buy, f.ah, f.net, f.margin, f.listed, f.where or "" } }
  end
  return "Buy from a merchant, sell on the AH (net after 5% cut). Right-click: waypoint to the nearest vendor.",
    { "Item", "Merchant", "AH", "Net each", "ROI", "Listed / sellers", "Where" }, { 0, 250, 340, 430, 520, 590, 710 }, out
end

local SHOW_LABEL = { all = "All recipes", learned = "Learned", unlearned = "Not learned" }
local COLOR_HEX = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", grey = "|cff808080" }
local function statusCell(r)
  if r.status == "learned" then
    return (COLOR_HEX[r.color] or "|cffffffff") .. "Learned|r"
  elseif r.status == "can" then return "|cff40ff40Can learn|r"
  elseif r.status == "find" then return "|cffffcc00Find pattern|r"
  elseif r.status == "low" then return string.format("|cffff4040Skill %d|r", r.l or 0)
  end
  return "|cff808080No prof.|r"
end
C.RecipeStatusCell = statusCell
local STATUS_ORDER = { learned = 1, can = 2, find = 2.5, low = 3, none = 4 }

local function suggestionText(ready, goal)
  local parts = {}
  local function money(r) return C.Money(r.profit) .. "/craft" end
  if ready then
    parts[#parts + 1] = string.format("|cff40ff40Suggested: %s|r (%s) %s vs your best %s - learn now: %s%s",
      ready.name, ready.prof, money(ready), C.Money(ready.beats), ready.trainer and "trainer" or (ready.learn or "-"),
      (ready.learnCost and ready.profit > 0) and string.format(", pays back in %d crafts", math.ceil(ready.learnCost / ready.profit)) or "")
  end
  if goal then
    parts[#parts + 1] = string.format("|cffff4040%s: %s|r %s - needs %s %d (you %d)",
      ready and "Next goal" or "Better at higher skill", goal.name, money(goal), goal.prof, goal.l or 0, goal.skill or 0)
  end
  if #parts == 0 then return "No unlearned recipe beats what you already craft at today's prices." end
  return table.concat(parts, "   |   ") .. "   |cff9d9d9d(click)|r"
end

tabs.Crafts = function()
  local st = C.settings
  if st.craftMine == nil then st.craftMine = true end
  local prof, show = st.craftProf or "ALL", st.craftShow or "all"
  if st.craftMine and prof ~= "ALL" and not C.MySkill(prof) then prof = "ALL"; st.craftProf = "ALL" end
  local all = C.CraftRows({ prof = prof, mine = st.craftMine })
  local ready, goal = C.SuggestRecipe(all)
  ui.suggest = ready or goal
  local out = {}
  for _, r in ipairs(all) do
    local want = show == "all" or (show == "learned" and r.status == "learned") or (show == "unlearned" and r.status ~= "learned")
    if want then
      local worth
      if r.profit then worth = r.profit >= C.Econ.Overhead() end
      out[#out + 1] = { id = r.out, recipe = r, roi = r.roi, worth = worth, cols = { itemCell(r.out, (r.n or 1) > 1 and (" x" .. r.n) or ""), r.prof or "?",
        statusCell(r), r.value and (C.Money(r.value) .. (r.viaVendor and " (v)" or "")) or "-",
        r.cost and (C.Money(r.cost) .. (r.est and "~" or "")) or ((r.partCost and r.partCost > 0) and (C.Money(r.partCost) .. " +?") or "?"),
        r.profit and C.Money(r.profit) or "-", r.vsMats and C.Money(r.vsMats) or "-", r.learn or "-" },
        sort = { r.name or itemName(r.out), r.prof or "", (STATUS_ORDER[r.status] or 5) + (r.l or 0) / 1000, r.value or -1, r.cost or -1,
          r.profit or -math.huge, r.vsMats or -math.huge, r.learn or "" },
        tip = (r.merchant and string.format("A merchant sells this for %s: AH buyers only pay more for convenience, so sell small batches.", C.Money(r.merchant)))
          or (r.status == "low" and string.format("Needs %s %d; you have %d.", r.prof, r.l or 0, r.skill or 0))
          or (r.status == "find" and "Your skill is high enough, but this pattern only drops (or comes from a quest).") or nil }
    end
  end
  local note = ""
  if prof ~= "ALL" and C.MySkill(prof) and not C.KnowsBookOf(prof) then
    note = "  |cffffcc00Open your " .. prof .. " window once so Kina knows which recipes you have.|r"
  end
  return suggestionText(ready, goal) .. note,
    { "Recipe", "Profession", "Status", "Sells for", "Reagents", "Profit", "Vs mats", "Learn from" },
    { 0, 220, 320, 400, 480, 560, 640, 720 }, out, { top = 22, crafts = true, headClick = (ready or goal) and function() C.ShowRecipe(ready or goal) end }
end

-- Hot's type filter: All / Crafts / Buy & vendor / Buy & disenchant / Sell yours
local HOT_TYPES = { { key = nil, label = "All" }, { key = "craft", label = "Crafts" }, { key = "vendor", label = "Buy & vendor" },
  { key = "de", label = "Buy & disenchant" }, { key = "sell", label = "Sell yours" } }
-- a short, plain tooltip right above a button
local function btnTip(btn, title, text)
  btn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
C.ButtonTip = btnTip
local HOT_KEY_TIPS = {
  vendor = "Items listed on the AH for less than a vendor pays. Buy them and sell them to any vendor for a sure profit.",
  de = "Gear listed for less than its disenchanted materials are worth on average. Buy, disenchant, sell the mats. Needs an enchanter, and each disenchant is a gamble.",
  sell = "Things you already own whose price jumped well above normal. Selling now beats waiting.",
}
-- Hot options window: a switch per kind of money (each profession's crafts,
-- buy & vendor, buy & disenchant, sell yours). Off = never shown on Hot.
local hotOpt
function C.ShowHotOptions()
  local function place(f)
    f:ClearAllPoints()
    if ui.frame and ui.frame:IsShown() then
      f:SetPoint("TOPLEFT", ui.frame, "TOPRIGHT", 4, 0)
      f:SetFrameStrata(ui.frame:GetFrameStrata())
      f:SetFrameLevel((ui.frame:GetFrameLevel() or 1) + 50)
    else f:SetPoint("CENTER") end
    if f.Raise then f:Raise() end
  end
  if hotOpt then if hotOpt:IsShown() then hotOpt:Hide() else place(hotOpt); hotOpt:Show(); hotOpt.refresh() end; return end
  local keys = {}
  local profs = {}
  for _, p in pairs(C.Data.profs or {}) do if type(p) == "string" then profs[p] = true end end
  local list = {}
  for p in pairs(profs) do list[#list + 1] = p end
  table.sort(list)
  for _, p in ipairs(list) do keys[#keys + 1] = { key = "craft:" .. p, label = "Crafts: " .. p } end
  keys[#keys + 1] = { key = "vendor", label = "Buy & vendor (cheap listings a vendor pays more for)" }
  keys[#keys + 1] = { key = "de", label = "Buy & disenchant" }
  keys[#keys + 1] = { key = "sell", label = "Sell yours (things you own that spiked)" }
  local f = CreateFrame("Frame", "KinaHotOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(380, 60 + #keys * 24); if f.SetToplevel then f:SetToplevel(true) end
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  local title = C.Text(f, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10); title:SetText("Hot: what to show")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 0, 0)
  local boxes = {}
  for i, k in ipairs(keys) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 24)
    local t = C.Text(cb, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("LEFT", cb, "RIGHT", 4, 0); t:SetText(k.label)
    local prof = k.key:match("^craft:(.+)$")
    btnTip(cb, k.label, prof and ("Things you can make with " .. prof .. " that sell for more than their materials cost right now. Untick to never see " .. prof .. " on Hot.")
      or ((HOT_KEY_TIPS[k.key] or "") .. " Untick to hide these from Hot."))
    cb:SetScript("OnClick", function(self)
      C.settings.hotHide = C.settings.hotHide or {}
      C.settings.hotHide[k.key] = (not self:GetChecked()) or nil
      ui.offset = 0; C.Refresh()
    end)
    boxes[k.key] = cb
  end
  f.refresh = function()
    local hide = C.settings.hotHide or {}
    for key, cb in pairs(boxes) do cb:SetChecked(not hide[key]) end
  end
  f.refresh()
  if UISpecialFrames then table.insert(UISpecialFrames, "KinaHotOptions") end
  hotOpt = f
  place(f)
end

function C.HotTypeLabel()
  for _, t in ipairs(HOT_TYPES) do if t.key == ui.hotType then return t.label end end
  return "All"
end
function C.HotTypeNext()
  local i = 1
  for j, t in ipairs(HOT_TYPES) do if t.key == ui.hotType then i = j end end
  ui.hotType = HOT_TYPES[(i % #HOT_TYPES) + 1].key
end

tabs.Hot = function()
  local out = {}
  local rows = C.Hot and C.Hot.Rows() or {}
  for _, r in ipairs(rows) do
    local spike = r.spike and ((r.spike >= 2 and "|cffff8040" or (r.spike >= 1.3 and "|cffffd100" or "|cff9d9d9d")) .. string.format("%.1fx", r.spike) .. "|r") or "-"
    if r.kind == "Craft" then
      local who
      if r.status == "learned" then who = "|cff7CFC00you can make it|r"
      elseif r.status == "can" then who = "|cffffd100learn it (" .. (r.learn or "?") .. ")|r"
      elseif r.status == "low" then who = string.format("|cffff8040needs %s %d (you %d)|r", r.prof, r.need or 0, r.skill or 0)
      else who = string.format("|cff9d9d9dneeds %s %d%s|r", r.prof, r.need or 1, r.learnCost and (", " .. C.Money(r.learnCost)) or "") end
      out[#out + 1] = { hot = "craft", hotKey = "craft:" .. tostring(r.prof), id = r.id, roi = (r.cost and r.cost > 0) and r.profit / r.cost or nil, cols = { itemCell(r.id, (r.n or 1) > 1 and (" x" .. r.n) or ""), "make " .. (r.prof or ""),
        C.Money(r.profit), C.Money(r.sell), string.format("%d", math.floor(r.rate + 0.5)), "|cff7CFC00" .. C.Money(r.gph) .. "|r", spike, who },
        sort = { r.name or itemName(r.id), r.prof or "", r.profit, r.sell, r.rate, r.gph, r.spike or 0, r.status },
        tip = string.format("Sells for %s each after the AH cut (cheapest-20 price now); reagents cost %s per item now. "
          .. "%d listed; about %d disappear per hour (sales, cancels or expiries: an estimate), you'd get about half. "
          .. "Gold/hour = profit x that, at most 300 crafts an hour.%s",
          C.Money(r.sell), C.Money(r.cost), r.listed or 0, math.floor(r.rate + 0.5),
          (r.spike and r.spike >= 2) and " SPIKE: today's price is far above its week median. It can crash fast: sell in small batches." or "") }
    else
      out[#out + 1] = { hot = "sell", id = r.id, cols = { itemCell(r.id), "|cffff8040sell yours|r", "-", C.Money(r.sell),
        r.rate and string.format("%d", math.floor(r.rate + 0.5)) or "-", C.Money(r.total) .. " total", spike, "you have " .. r.held },
        sort = { r.name or itemName(r.id), "sell", 0, r.sell, r.rate or 0, r.total, r.spike or 0, "" },
        tip = "You own these and today's price is " .. string.format("%.1fx", r.spike) .. " its week median. Selling now beats waiting." }
    end
  end
  -- deals (folded in from the old Deals tab): buy cheap listings and vendor or
  -- disenchant them. One-time gold, shown as "now" in the Gold/hour column.
  local okd, vd, dd = pcall(C.Deals)
  if okd then
    for _, d in ipairs(vd or {}) do
      local each = (d.vendor or 0) - (d.unit or 0)
      out[#out + 1] = { hot = "vendor", id = d.id, roi = (d.unit and d.unit > 0) and each / d.unit or nil,
        cols = { itemCell(d.id), "|cff40c0ffbuy & vendor|r", C.Money(each), C.Money(d.vendor) .. " (v)", "-", "|cff7CFC00" .. C.Money(d.profit) .. " now|r", "-", "buy " .. (d.units or 0) },
        sort = { itemName(d.id), "deal", each, d.vendor or 0, 0, d.profit or 0, 0, "" },
        tip = "Listings under what a vendor pays: buy them and sell to any vendor. One-time profit, available now." }
    end
    for _, d in ipairs(dd or {}) do
      local each = (d.ev or 0) - (d.unit or 0)
      out[#out + 1] = { hot = "de", id = d.id, roi = (d.unit and d.unit > 0) and each / d.unit or nil,
        cols = { itemCell(d.id), "|cffc080ffbuy & disenchant|r", C.Money(each), "DE " .. C.Money(d.ev or 0), "-", "|cff7CFC00" .. C.Money(d.profit) .. " now|r", "-", "buy " .. (d.count or 0) .. ", needs an enchanter" },
        sort = { itemName(d.id), "deal", each, d.ev or 0, 0, d.profit or 0, 0, "" },
        tip = "Gear listed under its average disenchant value: buy, disenchant, sell the mats. One-time profit, available now; disenchanting is a gamble per item." }
    end
  end
  -- Hot options: kinds you switched off never show (e.g. all Blacksmithing)
  local hide = C.settings.hotHide or {}
  local kept = {}
  for _, row in ipairs(out) do
    if not hide[row.hotKey or row.hot] and (not ui.hotType or row.hot == ui.hotType) then kept[#kept + 1] = row end
  end
  out = kept
  local age = C.ScanAgeMinutes and C.ScanAgeMinutes()
  -- the recipe to learn next (from the old Crafts tab), then the scan age
  local okS, ready, goal = pcall(function()
    local st = C.settings
    return C.SuggestRecipe(C.CraftRows({ prof = "ALL", mine = st.craftMine ~= false }))
  end)
  if not okS then ready, goal = nil, nil end
  ui.suggest = ready or goal
  local head = suggestionText(ready, goal)
    .. (age and string.format("   |cff9d9d9dscan %d min old%s|r", age, age > 45 and ": |cffff8040scan again|r" or "") or "")
  local empty = (#out == 0) and "Nothing yet: Hot needs two scans at least 12 minutes apart (it measures how fast things leave the AH). Scan, wait, scan again." or nil
  if not ui.sort.Hot then ui.sort.Hot = { col = 6, desc = true } end
  return head, { "Item", "What", "Profit each", "Sells for", "Gone/hr", "Gold/hour", "vs week", "Who can" },
    { 0, 220, 320, 400, 480, 540, 640, 700 }, out,
    { empty = empty, headClick = (ready or goal) and function() C.ShowRecipe(ready or goal) end }
end

-- Private Kina: duo dungeons for a hunter + druid (Brain.lua)
tabs.Dungeons = function()
  local list, lvl = C.Brain.Dungeons()
  local _, me, partner = C.Brain.DuoLevel()
  local out = {}
  for _, d in ipairs(list) do
    out[#out + 1] = { cols = {
        d.zone .. " |cff9d9d9d(" .. d.levels .. ")|r", d.verdict,
        d.elites > 0 and (d.elites .. " |cff9d9d9d(to " .. d.eliteMax .. ")|r") or "0",
        C.Money(d.run),
        d.measured > 0 and C.Money(d.gph) or ("|cff9d9d9d~" .. C.Money(d.gph) .. "|r"),
        d.measured > 0 and string.format("%d (%s/h)", d.measured, C.Money(d.measHour or 0)) or "-",
        d.best, d.why },
      sort = { d.zone, d.score, d.elites, d.run, d.gph, d.measured, d.best, d.why },
      tip = string.format("%s\nOne clear is estimated at ~%d min (about 25 s per elite kill plus walking). Per run = every mob's drops, coin, skins and disenchant value at today's prices.%s%s",
        d.why, math.floor(d.estSecs / 60 + 0.5),
        d.skins > 0 and ("\nSkinning adds about " .. C.Money(d.skins) .. " a run.") or "",
        d.measured > 0 and string.format("\nYour %d timed run%s here made %s an hour; Kina trusts that more with every run.", d.measured, d.measured == 1 and "" or "s", C.Money(d.measHour or 0))
          or "\nNo timed runs yet: start the farm widget at the entrance, stop it when you're out. Kina learns your real clear time and income.") }
  end
  if not ui.sort.Dungeons then ui.sort.Dungeons = { col = 5, desc = true } end
  local head = string.format("|cffffd100Duo dungeons|r for your hunter + druid at level %d%s. |cff9d9d9d~ = estimate at today's prices; your timed runs take over as you play.|r",
    lvl, partner and string.format(" (you %d, partner %d)", me, partner) or "")
  return head, { "Where (levels)", "Duo?", "Elites", "Per run", "Gold/hour", "Your runs", "Best", "Why" },
    { 0, 190, 290, 360, 440, 520, 610, 760 }, out, { empty = (#out == 0) and "No dungeon or elite data near your level yet." or nil }
end
-- Private Kina: cheapest way to level your crafting professions right now
tabs["Skill up"] = function()
  local rows = C.Brain.SkillUp()
  local out, firstOf, perProf = {}, {}, {}
  for _, s in ipairs(rows) do
    perProf[s.prof] = (perProf[s.prof] or 0) + 1
    if perProf[s.prof] <= 10 then
      if not firstOf[s.prof] then firstOf[s.prof] = s end
      local col = ({ orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040" })[s.r.color or ""] or ""
      out[#out + 1] = { id = s.r.out, cols = {
          itemCell(s.r.out), s.prof .. " " .. s.skill, col .. string.format("%d%%", math.floor(s.p * 100 + 0.5)) .. "|r",
          C.Money(s.cost), s.value and C.Money(s.value) or "-",
          s.perPoint < 0 and ("|cff7CFC00earns " .. C.Money(-s.perPoint) .. "|r") or C.Money(s.perPoint),
          s.learn > 0 and ("learn " .. C.Money(s.learn)) or (s.r.status == "learned" and "|cff9d9d9dknown|r" or "-") },
        sort = { itemName(s.r.out), s.prof, s.p, s.cost, s.value or 0, s.perPoint, s.learn },
        tip = string.format("Skill-up chance %d%% at %s %d (orange always, then it fades to grey at %d). Mats cost %s now; the crafted item sells for %s (counted at 70%%: leveling items don't all sell). Cost per skill point = what one point really costs you.",
          math.floor(s.p * 100 + 0.5), s.prof, s.skill, s.r.x or 0, C.Money(s.cost), s.value and C.Money(s.value) or "nothing") }
    end
  end
  local parts = {}
  for prof, s in pairs(firstOf) do
    parts[#parts + 1] = string.format("%s %d: |cff7CFC00%s|r (%s)", prof, s.skill, s.r.name or itemName(s.r.out),
      s.perPoint < 0 and ("earns " .. C.Money(-s.perPoint) .. "/point") or (C.Money(s.perPoint) .. "/point"))
  end
  local head = #parts > 0 and ("|cffffd100Cheapest now|r  " .. table.concat(parts, "   |   ")) or "Open each profession window once so Kina knows your skills and recipes."
  if not ui.sort["Skill up"] then ui.sort["Skill up"] = { col = 6 } end
  return head, { "Make", "Profession", "Skill-up", "Mats cost", "Sells for", "Cost per point", "Learn" },
    { 0, 220, 330, 410, 490, 580, 690 }, out, { empty = (#out == 0) and "No priced recipes yet: scan the AH, and open your profession windows." or nil }
end

tabs.Favor = function()
  local out = {}
  for _, r in ipairs(C.FavorRows()) do
    out[#out + 1] = { id = r.id, cols = { r.name .. " (" .. r.favor .. ")", r.crate and C.Money(r.crate) or "none",
      r.bundleID and (r.bundleQty .. " " .. itemName(r.bundleID)) or "-", r.bundleCost and C.Money(r.bundleCost) or "-",
      r.perFavor and C.Money(r.perFavor) or "-", r.crateNet and C.Money(r.crateNet) or "-" },
      sort = { r.name, r.crate or 0, r.bundleID and itemName(r.bundleID) or "", r.bundleCost or 0, r.perFavor or math.huge, r.crateNet or 0 },
      tip = r.ownMatsValue and ("Your own mats for this bundle would sell for " .. C.Money(r.ownMatsValue) .. ".") or nil }
  end
  return "Merchant's Favor crates. Gold/Favor = crate + cheapest bundle. Sell looted = what a looted crate nets on the AH.",
    { "Crate (Favor)", "Crate on AH", "Cheapest bundle", "Bundle cost", "Gold/Favor", "Sell looted" }, { 0, 220, 330, 520, 620, 720 }, out
end

tabs.Track = function()
  local out = {}
  for _, r in ipairs(C.StockRows()) do
    local tr = r.trend and string.format("%+.0f%%/day", r.trend * 100) or "-"
    out[#out + 1] = { id = r.id, cols = { itemCell(r.id), r.low and C.Money(r.low) or "-", r.week and C.Money(r.week) or "-", tr,
      tostring(r.qty or 0), tostring(r.have or 0),
      (r.s.buyUnder and ("buy<" .. C.Money(r.s.buyUnder)) or "") .. (r.s.sellAt and (" sell>" .. C.Money(r.s.sellAt)) or "") ..
      (r.under > 0 and ("  |cff7CFC00" .. r.under .. " under target|r") or "") },
      sort = { itemName(r.id), r.low or 0, r.week or 0, r.trend or 0, r.qty or 0, r.have or 0, r.under } }
  end
  return "Tracked items. Right-click any item in any tab to track it. Set alert/hold prices on the Settings tab (Stockpile target).",
    { "Item", "Lowest now", "7-day median", "Trend", "Listed", "In bags", "Targets" }, { 0, 250, 350, 450, 540, 610, 680 }, out
end

-- Ledger: audit your trades. One row per item you bought to flip, with what came
-- of it; the header totals profit and gold per hour of trading.
local STEP = { ahbuy = "bought on AH", vendorbuy = "bought from vendor", disenchant = "disenchanted", vendorsale = "sold to vendor",
  ahsale = "sold on AH", post = "posted", expired = "expired" }
local function stepText(e)
  local when = date and date("%a %H:%M", e.t) or ""
  if e.kind == "disenchant" then
    local parts = {}
    for id, n in pairs(e.out or {}) do parts[#parts + 1] = n .. " " .. itemName(id) end
    return string.format("%s  disenchanted 1 -> %s", when, table.concat(parts, ", "))
  elseif e.kind == "craftuse" then
    return string.format("%s  used %d to craft %s (cost %s moved to it)", when, e.qty or 1, itemName(e.out), C.Money(e.total or 0))
  elseif e.kind == "craft" then
    return string.format("%s  crafted %d (cost of the mats)", when, e.qty or 1)
  elseif e.kind == "post" then
    return string.format("%s  posted %d at %s each (deposit %s)", when, e.qty or 1, C.Money(e.each or 0), C.Money(e.deposit or 0))
  end
  return string.format("%s  %s %d for %s%s", when, STEP[e.kind] or e.kind, e.qty or 1, C.Money(math.abs(e.total or 0)),
    e.assumed and " |cff9d9d9d(marked by you: vendor price)|r" or "")
end

tabs.Ledger = function()
  local out = {}
  local flips = C.LedgerFlips(ui.ledgerDays)
  local profit, spent, holding, holdValue, n = 0, 0, 0, 0, 0
  local realized, unsoldMats = 0, 0
  for _, r in ipairs(flips) do
    local status
    if r.left == 0 then status = "|cff7CFC00done|r"
    elseif r.done == 0 then status = "|cffffd100holding " .. r.left .. "|r"
    else status = "|cffffd100" .. r.done .. " done, " .. r.left .. " held|r" end
    if r.done > 0 then profit = profit + r.result; spent = spent + r.avg * r.done; n = n + 1
      realized = realized + (r.realized or 0); unsoldMats = unsoldMats + (r.matsEstimate or 0) end
    if r.left > 0 then holding = holding + r.left; holdValue = holdValue + r.avg * r.left end
    local lines = {}
    for _, e in ipairs(r.events) do lines[#lines + 1] = stepText(e) end
    out[#out + 1] = { id = r.id, flip = r, roi = r.roi, cols = { itemCell(r.id), tostring(r.bought), C.Money(r.paid),
      r.done > 0 and (C.Money(r.got) .. ((r.de > 0) and " |cff9d9d9d(mats now)|r" or "")) or "-",
      (r.deposits or 0) > 0 and C.Money(r.deposits) or "|cff9d9d9d-|r",
      r.done > 0 and (((r.result >= 0) and "|cff7CFC00+" or "|cffff6060-") .. C.Money(math.abs(r.result)) .. "|r") or "-",
      r.roi and string.format("%.0f%%", r.roi * 100) or "-", status },
      sort = { itemName(r.id), r.bought, r.paid, r.got, r.deposits or 0, r.done > 0 and r.result or -math.huge, r.roi or -math.huge, r.left, r.last },
      tip = table.concat(lines, "\n")
        .. (r.de > 0 and ("\nMaterials are valued at today's cheapest listing after the cut (" .. C.Money(r.matsNow) .. (r.matsKnown and "" or ", some unpriced") .. ").") or "")
        .. (r.left > 0 and string.format("\n%d still held (paid %s each): not counted until you sell or disenchant them.", r.left, C.Money(r.avg)) or "") }
  end
  local hours = C.TradeHours(flips)
  local span = ui.ledgerDays and ("last " .. ui.ledgerDays .. " days") or "all time"
  local head = string.format("|cffffd100Trading, %s:|r %s%s|r profit on %d flips (ROI %s)   |cffffd100%s / hour|r over %s of trading%s",
    span, profit >= 0 and "|cff7CFC00+" or "|cffff6060-", C.Money(math.abs(profit)), n,
    spent > 0 and string.format("%.0f%%", profit / spent * 100) or "-",
    hours > 0 and C.Money(profit / hours) or "-",
    hours >= 1 and string.format("%.1f h", hours) or string.format("%d min", math.floor(hours * 60 + 0.5)),
    holding > 0 and string.format("   |cff9d9d9dholding %d items (%s paid)|r", holding, C.Money(holdValue)) or "")
    .. (unsoldMats > 0 and string.format("\n   cash actually back: %s%s|r; the rest is disenchant materials at today's prices (%s), not sold yet",
      realized >= 0 and "|cff7CFC00+" or "|cffff6060-", C.Money(math.abs(realized)), C.Money(unsoldMats)) or "")
  local empty = #out == 0 and ("No flips yet. Buy something on the AH to resell or disenchant, and Kina records it here: what you paid, what came of it, "
    .. "and your profit and gold per hour from trading.") or nil
  if not ui.sort.Ledger or (ui.sort.Ledger.col or 0) > 9 then ui.sort.Ledger = { col = 9, desc = true } end
  return head, { "Item", "Bought", "Paid", "Got back", "Deposits", "Profit", "ROI", "Status" }, { 0, 220, 280, 370, 510, 590, 680, 740 }, out, { empty = empty }
end

-- One farm, line by line: how its Net is made up, and every event it counted.
local CAT = { coin = "coin looted", pickpocket = "pickpocket coin", vendor = "sold to a vendor", mail = "gold from mail",
  other = "other gold in", spent = "gold spent" }
local CTX = { corpse = "looted", skin = "skinned", pick = "pickpocketed", node = "gathered", box = "opened box", other = "looted", fish = "fished", unknown = "looted (mob unsure)" }
local function signedMoney(cp)
  if not cp then return "-" end
  return (cp < 0 and "|cffff6060-" or "|cff7CFC00+") .. C.Money(math.abs(cp)) .. "|r"
end
local function npcName(id)
  local r = C.LootRecord and C.LootRecord(id)
  if r and r.nm then return r.nm end
  local m = C.DropSnapshot and C.DropSnapshot().mobs[id]
  if m then return m.nm end
  local i = C.NPCInfo and C.NPCInfo(id)
  return (i and i.nm) or ("NPC " .. tostring(id))
end
local function farmLog(s, live)
  local out = {}
  local sum = C.SessionSummary(s)
  local logIndex, syncSeq
  local function row(when, what, detail, count, value, id)
    local n = #out + 1
    out[n] = { id = id, cols = { when, what, detail, count or "", value or "" }, sort = { n, n, n, n, n },
      logRef = logIndex and { s = s, i = logIndex } or nil, syncRef = syncSeq }
  end
  local gf = C.GroupFarm and C.GroupFarm(s)
  local grouped = gf and (gf.synced or (s.party and #s.party > 0) or (not s.stop and C.GroupSize and C.GroupSize() > 1))
  if grouped and (gf.synced or (s.g and (next(s.g.loot) or s.g.coin > 0))) then
    row("", "|cffffd100Group total|r", "everything the group looted (loot lines) + coin, what the widget shows", "", signedMoney(gf.net))
    -- each player's line has their own consumables taken out, so it's the admin view only
    if C.Admin() or (gf.used or 0) == 0 then
      for who, v in pairs(gf.byLooter) do row("", "   " .. who, ((gf.used or 0) > 0) and "looted, minus what they used" or "looted", "", signedMoney(v)) end
    end
    row("", "   coin", "", "", signedMoney(gf.coin))
    if (gf.used or 0) > 0 then row("", "   consumables used", C.Admin() and "potions, food, bandages... taken off (each player's share is in their line above)"
      or "potions, food, bandages... by the whole group, shared evenly", "", signedMoney(-gf.used)) end
    -- the split: half each (or a share each), from the loot lines; coin is already split by the game
    -- the leader's numbers when we have them (final at Stop, running while farming)
    local live = not gf.synced and not s.gsplit and not s.stop and C.groupLive and C.Now and (GetTime and GetTime() or 0) - C.groupLive.t < 60 and C.groupLive
    local by = s.gsplit and s.gsplit.by or (live and live.by) or gf.byLooter
    if gf.synced and s.sync and C.FarmSync and C.FarmSync.Totals(s.sync).noSplit then
      row("", "|cffffd100Split|r", "no split: this farm only shares its numbers (chosen at Start)", "", "")
    elseif C.Settle and next(by) then
      local total, each, transfers = C.Settle(by)
      local lead = C.FarmLeader and select(1, C.FarmLeader()) or "the leader"
      row("", "|cffffd100Split|r", s.gsplit and ("what each looted, " .. tostring(s.gsplit.from) .. "'s prices (coin is already split by the game)")
        or (s.stop and ("|cffff8040NOT FINAL: at your prices. Waiting for " .. tostring(lead) .. "'s split; theirs is the one to pay.|r"))
        or (live and ("so far, " .. tostring(live.from) .. "'s numbers (final at Stop)"))
        or ("so far (the final split comes from " .. tostring(lead) .. "'s Kina at Stop)"), "", "")
      row("", "   each gets", "", "", C.Money(each))
      if #transfers == 0 then row("", "   nobody owes anything", "", "", "") end
      for _, t in ipairs(transfers) do row("", "   |cff7CFC00" .. t.from .. " pays " .. t.to .. "|r", "", "", C.Money(t.amt)) end
    end
  end
  if sum.income then
    -- P1.0.2: a farm = what you looted. Buying, selling, crafting, the bank and the mailbox don't count.
    row("", "|cffffd100Your net|r", "coin you looted + items you looted (today's price) - consumables you used", "", signedMoney(sum.total))
    row("", "   coin looted", ((s.money.pickpocket or 0) > 0) and ("incl. " .. C.Money(s.money.pickpocket) .. " pick pocketed") or "", "", signedMoney(sum.cash))
    row("", "   items looted", "every drop, skin and pick at today's farm price (rolls at their own price)", "", signedMoney(sum.items))
    if (sum.used or 0) > 0 then row("", "   consumables used", "", "", signedMoney(-sum.used)) end
    if s.excl and ((s.excl.coin or 0) > 0 or next(s.excl.items)) then
      row("", "   |cff9d9d9dleft out (paused or right-clicked)|r", "coin " .. C.Money(s.excl.coin or 0) .. ", items " .. C.Money(C.ExcludedItemValue(s)), "", "")
    end
    local list = {}
    for id, n in pairs(s.items or {}) do if n > 0 then list[#list + 1] = { id = id, n = n, v = ((C.FarmValue and C.FarmValue(id)) or 0) * n } end end
    table.sort(list, function(x, y) return x.v > y.v end)
    for i = 1, math.min(#list, 40) do
      local it = list[i]
      row("", "      " .. itemCell(it.id), "", "x" .. it.n, C.Money(it.v), it.id)
    end
    local other = 0
    for _, k in ipairs({ "vendor", "mail", "other", "spent" }) do other = other + math.abs(s.money[k] or 0) end
    if other > 0 then
      row("", "|cff9d9d9dNot counted|r", "|cff9d9d9dvendor " .. C.Money(s.money.vendor or 0) .. ", mail " .. C.Money(s.money.mail or 0)
        .. ", other " .. C.Money(s.money.other or 0) .. ", spent " .. C.Money(-(s.money.spent or 0)) .. " (trading and errands, not farming)|r", "", "")
    end
  else
  row("", "|cffffd100Your net|r", "your gold change + your items change (below)", "", signedMoney(sum.total))
  row("", "|cffffd100Gold|r", "your gold now minus your gold at Start", "", signedMoney(sum.cash))
  local parts = 0
  for _, k in ipairs({ "coin", "pickpocket", "vendor", "mail", "other", "spent" }) do
    local v = s.money and s.money[k]
    if v and v ~= 0 then row("", "   " .. CAT[k], "", "", signedMoney(v)); parts = parts + v end
  end
  if s.excl and ((s.excl.coin or 0) > 0 or next(s.excl.items)) then
    row("", "   |cff9d9d9dleft out (looted while paused)|r", "coin " .. C.Money(s.excl.coin or 0) .. ", items " .. C.Money(C.ExcludedItemValue(s)), "", "")
    parts = parts + (s.excl.coin or 0)
  end
  if sum.cash and math.abs(parts - sum.cash) > 1 then
    row("", "   |cffff8040not explained|r", "gold that changed while Kina wasn't watching (e.g. a /reload)", "", signedMoney(sum.cash - parts))
  end
  row("", "|cffffd100Items|r", "bags + bank + AH listings: count now minus count at Start, x price each", "", signedMoney(sum.items))
  local changes = (live and s.startCounts and C.ItemChanges(s.startCounts, C.Holdings())) or s.itemChanges or {}
  for i = 1, math.min(#changes, 60) do
    local c = changes[i]
    row("", "   " .. itemCell(c[1]), string.format("%d -> %d, %s each", c[2], c[3], C.Money(c[4])), string.format("%+d", c[3] - c[2]), signedMoney(c[5]), c[1])
  end
  if not live and not s.itemChanges then row("", "   |cff9d9d9d(item list not kept for farms before 0.11.4)|r", "", "", "") end
  end
  -- a shared farm: the log every widget computes from, entry by entry
  if s.sync then
    local ex = C.FarmSync and C.FarmSync.Excluded(s.sync) or {}
    local seqText = string.format("%d entries, fingerprint %s", s.sync.head or 0, tostring(s.sync.hash))
    row("", "|cffffd100Shared log|r", "the same on every Kina in this farm (" .. seqText .. "); right-click an entry to leave it out or count it again", "", "")
    -- newest first; whether each entry fell in a pause is worked out oldest-first
    local pausedAt, pz = {}, false
    for i, ev in ipairs(s.sync.chain) do if ev.kind == "P" then pz = ev.data == "1" end; pausedAt[i] = pz end
    for ci = #s.sync.chain, 1, -1 do
      local ev = s.sync.chain[ci]
      local paused = pausedAt[ci]
      local t = string.format("%d:%02d", math.floor((ev.t or 0) / 60), (ev.t or 0) % 60)
      syncSeq = nil
      local out_ = ex[ev.seq] and " |cffff8040out|r" or ""
      local k = ev.kind
      if k == "L" then
        local id, n, suf, v = ev.data:match("^(%d*):(%d*):([^:]*):(%-?%d*)$")
        id, n, v = tonumber(id), tonumber(n) or 1, tonumber(v) or 0
        syncSeq = ev.seq
        row(t .. out_, paused and "|cff9d9d9dlooted (paused)|r" or "looted", ev.origin .. ": " .. (id and itemCell(id, (suf ~= "" and (" " .. suf)) or nil) or "?"), "x" .. n, C.Money(n * v), id)
      elseif k == "C" then syncSeq = ev.seq; row(t .. out_, "coin", ev.origin, "", C.Money(tonumber(ev.data) or 0))
      elseif k == "K" then syncSeq = ev.seq; row(t .. out_, "kill", ev.origin .. ": " .. npcName(tonumber(ev.data:match("^(%d+)")) or 0), "", "")
      elseif k == "U" then
        local id, n, v = ev.data:match("^(%d*):(%d*):(%-?%d*)$")
        id, n, v = tonumber(id), tonumber(n) or 1, tonumber(v) or 0
        syncSeq = ev.seq
        if C.Admin() then row(t .. out_, "used", ev.origin .. ": " .. (id and itemCell(id) or "?"), "x" .. n, signedMoney(-n * v), id) end
      elseif k == "P" then paused = ev.data == "1"; row(t, paused and "paused" or "resumed", ev.origin, "", "")
      elseif k == "J" then row(t, "joined", ev.origin, "", "")
      elseif k == "Q" then row(t, "left", ev.origin, "", "")
      elseif k == "E" then
        local q, on = ev.data:match("^(%d+):(%d)$")
        row(t, "edit", ev.origin .. (on == "1" and " left out entry " or " counted entry ") .. tostring(q), "", "")
      elseif k == "S" then row(t, "stopped", ev.origin, "", "") end
    end
    syncSeq = nil
    row("", "", "", "", "")
  end
  row("", "|cffffd100Events|r", "newest first. Right-click a kill or drop to leave it out (|cffff8040out|r) or count it again: " .. (s.log and #s.log or 0) .. " recorded" .. ((s.log and #s.log >= 600) and " (oldest dropped)" or ""), "", "")
  if not s.log then row("", "   |cff9d9d9d(events are recorded from 0.11.4 on)|r", "", "", "") end
  local logList = s.log or {}
  for li = #logList, 1, -1 do -- newest first
    local e = logList[li]
    local t = string.format("%d:%02d", math.floor(e[1] / 60), e[1] % 60)
    local k = e[2]
    logIndex = (k == "kill" or k == "loot" or k == "gloot") and li or nil
    if e[7] then t = t .. " |cffff8040out|r" end
    if k == "kill" then row(t, "kill", npcName(e[3]) .. (e[4] == 1 and " |cff9d9d9d(group member saw it)|r" or ""), "", "")
    elseif k == "opened" then row(t, "opened", tostring(e[4] or ("object " .. tostring(e[3]))), "", "")
    elseif k == "loot" then
      local each = (C.FarmValue and C.FarmValue(e[3], e[8])) or 0
      row(t, CTX[e[5]] or "looted", itemCell(e[3], e[8] and (" " .. e[8]) or nil) .. (e[6] and (" from " .. npcName(e[6])) or ""), "x" .. (e[4] or 1), C.Money(each * (e[4] or 1)), e[3])
    elseif k == "gold" then row(t, CAT[e[4]] or tostring(e[4]), "", "", signedMoney(e[3]))
    elseif k == "post" then row(t, "listed on the AH", itemCell(e[3]), "x" .. (e[4] or 1), "|cff9d9d9dstill yours|r", e[3])
    elseif k == "listing gone" then row(t, "AH listing sold or expired", itemCell(e[3]), "", "", e[3])
    elseif k == "gloot" then
      local each = (C.FarmValue and C.FarmValue(e[3], e[6])) or 0
      row(t, "group loot", tostring(e[5] or "?") .. ": " .. itemCell(e[3], e[6] and (" " .. e[6]) or nil), "x" .. (e[4] or 1), C.Money(each * (e[4] or 1)), e[3])
    elseif k == "used" then
      local each = (C.FarmValue and C.FarmValue(e[3])) or 0
      if C.Admin() then row(t, "used", tostring(e[5] or "?") .. ": " .. itemCell(e[3]), "x" .. (e[4] or 1), signedMoney(-each * (e[4] or 1)), e[3]) end
    elseif k == "gcoin" then row(t, "group coin", (e[4] or 1) > 1 and ("your share x " .. e[4] .. " players") or "", "", signedMoney(e[3]))
    elseif k == "pause" or k == "resume" then row(t, k == "pause" and "paused" or "resumed", "", "", "")
    elseif k == "excluded loot" then row(t, "|cff9d9d9dnot counted (paused)|r", itemCell(e[3]), "x" .. (e[4] or 1), "", e[3])
    elseif k == "excluded kill" then row(t, "|cff9d9d9dkill not counted (paused)|r", npcName(e[3]), "", "")
    elseif k == "excluded coin" then row(t, "|cff9d9d9dcoin not counted (paused)|r", "", "", C.Money(e[3] or 0))
    elseif k == "edit" then row(t, "|cff9d9d9dchanged by " .. tostring(e[6] or "?") .. "|r", (e[5] == "k" and "kill " or "loot ") .. (e[4] == 1 and "counted" or "left out"), "", "")
    elseif k == "start" then row(t, "Start", "gold " .. C.Money(e[3] or 0), "", "")
    elseif k == "stop" then row(t, "Stop", "gold " .. C.Money(e[3] or 0), "", "") end
  end
  return out, sum
end
------------------------------------------------------------------ public ledger
-- Public Kina: the Ledger is the books. Farms (one row each, click for details),
-- Gold flow (in and out), and XP (history and what's still waiting). Numbers from Books.lua.
if C.PUBLIC then
  local GREY, GOLDC, GREEN, ORANGE = "|cff9d9d9d", "|cffffd100", "|cff7CFC00", "|cffff8040"
  local function money(v) return (v and v ~= 0) and C.Money(math.floor(v + 0.5)) or (GREY .. "-|r") end
  local function day(t) return t and date("%m/%d", t) or "" end
  local function period() return ui.ledgerDays and (ui.ledgerDays .. " days") or "all time" end
  local VIEWS = { "farms", "debts", "flow", "xp" }
  local VIEWNAME = { farms = "Farms", debts = "Debts", flow = "Gold flow", xp = "XP" }
  ui.LEDGER_VIEWS, ui.LEDGER_VIEWNAME = VIEWS, VIEWNAME
  C.LedgerViewName = function() return VIEWNAME[ui.ledgerView or "farms"] end
  C.NextLedgerView = function()
    local v = ui.ledgerView or "farms"
    for i, x in ipairs(VIEWS) do if x == v then ui.ledgerView = VIEWS[i % #VIEWS + 1] end end
    ui.bookOf = nil; ui.offset = 0; ui.sort.Ledger = nil
  end
  local function back() ui.bookOf = nil; ui.offset = 0; C.Refresh() end

  local function detail(s)
    local r = C.Books.Farm(s)
    local out = {}
    local function row(a, b, c, d) out[#out + 1] = { cols = { a or "", b or "", c or "", d or "" }, sort = { #out, 0, 0, 0 } } end
    row(GOLDC .. "Farm|r", string.format("%s, %s, %d min, %d player%s", r.label, day(r.t), math.floor((r.secs or 0) / 60), r.players, r.players > 1 and "s" or ""))
    local res = s.result or {}
    row(GOLDC .. "Gold|r", "coin you looted", money((res.coin or 0) + (res.pickpocket or 0)))
    row("", "items you looted (at the farm's prices)", money(res.items))
    if (res.used or 0) > 0 then row("", "consumables used", money(-(res.used or 0))) end
    row("", "your farm total", money(res.total))
    if r.unshared then
      row(GOLDC .. "Split|r", "not a shared farm: your partner's loot wasn't counted, so there was no split", "", GREY .. "nothing owed|r")
    elseif s.split and s.split.transfers then
      row(GOLDC .. "Split|r", "the group farmed (net: coin + loot - consumables)", money(r.farmed))
      if r.groupCoin then
        row("", "coin, split evenly by the game", money(r.groupCoin))
        row("", "loot, split by Kina (after each looter's consumables)", money(r.lootSplit))
      end
      local names = {}
      for who in pairs(s.split.incomes or {}) do names[#names + 1] = who end
      table.sort(names)
      for _, who in ipairs(names) do row("", who .. " looted", money(s.split.incomes[who])) end
      if r.coinShare then row("", "your share: coin from the game + loot share", money(r.coinShare) .. " + " .. money(r.lootShare) .. " = " .. money(r.share))
      else row("", "fair share each", money(r.share)) end
      if s.noSplit then row("", "no split (chosen at Start)", "", GREEN .. "nothing owed|r")
      elseif #s.split.transfers == 0 then row("", "everyone was even", "", GREEN .. "nothing owed|r") end
      for _, t in ipairs(s.split.transfers) do row("", t.from .. " pays " .. t.to, money(t.amt)) end
      row(GOLDC .. "Debts|r", "", "", "")
      for _, d in ipairs(r.debts) do
        local left = d.amt - d.done
        local st = left < 1 and (GREEN .. "paid|r") or (d.done > 0 and (ORANGE .. money(left) .. " left|r") or (ORANGE .. "unpaid|r"))
        local forgiven = s.split.forgiven and s.split.forgiven[d.who]
        if forgiven then st = GREEN .. "forgiven|r" end
        -- the live debt (with its due date), if it's still open
        local od
        for _, x in ipairs(C.Debts()) do if x.s == s and x.key == d.who and x.dir == d.dir then od = x end end
        if od and not forgiven and C.DueText then st = st .. "  " .. GREY .. C.DueText(od) .. "|r" end
        row("", (d.dir == "owe" and "you owe " or "owes you: ") .. d.who, money(d.amt), st)
        -- 1.2.0: the buttons (Pay, more time, Forgive) are on the Ledger's Debts page
        if od and left >= 1 and not forgiven then
          out[#out + 1] = { cols = { "", GREY .. "   Pay, more time or Forgive: the Debts button above|r", "", "" }, sort = { #out, 0, 0, 0 } }
        end
      end
      if #r.debts == 0 then row("", "nothing between you and the group", "", "") end
    end
    if #r.payments > 0 then
      row(GOLDC .. "Payments|r", "", "", "")
      for _, p in ipairs(r.payments) do
        local rec = p.rec
        local conf = rec.conf and (GREEN .. "confirmed by both|r") or (C.Now() - (rec.t or 0) < 600 and (ORANGE .. "waiting for their Kina|r") or (ORANGE .. "not confirmed|r"))
        row(day(rec.t), string.format("%s %s by %s", p.dir == "owe" and "paid" or "received from", C.Books.Name(rec.who), rec.via), money(p.amt), conf)
      end
    end
    row(GOLDC .. "XP|r", "", "", "")
    if r.farmGain then
      local g = r.farmGain
      row("", string.format("shared farm, %d min", math.floor((g.secs or 0) / 60)), "", g.paused and (ORANGE .. "0 (sharing was off)|r") or ("+" .. g.xp .. (g.xp < g.want and (GREY .. " (daily cap)|r") or "")))
    elseif s.minLvl and s.minLvl > 0 and s.minLvl < (C.PROG_MIN_LEVEL or 10) then row("", "someone in the farm was under level 10", "", GREY .. "no Kina XP or standing|r")
    elseif s.sync and r.shortWhy == "gold" then row("", "the farm made less than its gold target (" .. C.Money(C.Rep.FarmNeeds(s.maxLvl, s.groupN)) .. ")", "", GREY .. "no farm XP|r")
    elseif s.sync then row("", "shared farm under 15 minutes", "", GREY .. "no farm XP|r")
    else row("", "solo farm", "", GREY .. "no XP (farm with Kina users)|r") end
    for _, p in ipairs(r.payments) do
      if p.gain and p.counted then row("", (p.dir == "owe" and "paying " or "being paid by ") .. C.Books.Name(p.rec.who), "", "+" .. p.gain.xp) end
    end
    local waiting = false
    for _, d in ipairs(r.debts) do
      local left = d.amt - d.done
      if left >= 1 then
        if not waiting then row(GOLDC .. "XP waiting|r", "", "", ""); waiting = true end
        if d.dir == "owe" then row("", "pay " .. d.who .. " " .. C.Money(math.floor(left)), "", GREEN .. "+" .. C.Rep.PayXP(left) .. "|r")
        else row("", d.who .. " pays you " .. C.Money(math.floor(left)), "", GREEN .. "+" .. C.Rep.RECV_XP .. "|r") end
      end
    end
    return string.format("%sFarm details: %s|r   %s(click here to go back)|r", GOLDC, r.label, GREY),
      { "", "What", "Amount", "Status / XP" }, { 0, 110, 430, 610 }, out, { headClick = back }
  end

  tabs.Ledger = function()
    if type(ui.bookOf) == "table" then return detail(ui.bookOf) end
    ui.bookOf = nil
    local view = ui.ledgerView or "farms"
    local out = {}
    if view == "debts" then
      -- 1.2.0: a page of its own: people on the left, one person's debts with buttons on the right
      return GOLDC .. "Debts|r " .. GREY .. "between you and the people you farmed with|r", {}, {}, {}, { panel = "debts" }
    end
    if view == "flow" then
      local inn, outg = C.Books.Flow(ui.ledgerDays)
      local tin, tout = 0, 0
      local function row(a, b, v, sign)
        out[#out + 1] = { cols = { a, b, money(v) }, sort = { #out, 0, v or 0 } }
        if sign == 1 then tin = tin + (v or 0) elseif sign == -1 then tout = tout + (v or 0) end
      end
      row(GREEN .. "In|r", "coin looted on farms", inn.coin, 1)
      if inn.pickpocket > 0 then row("", "pick pocket coin", inn.pickpocket, 1) end
      row("", "items looted on farms (value, not sold yet)", inn.items, 1)
      row("", "vendor sales during farms", inn.vendor, 1)
      row("", "auction sales (after the AH cut)", inn.ahSales, 1)
      row("", "payments received", inn.received, 1)
      row(ORANGE .. "Out|r", "payments made", outg.paid, -1)
      row("", "consumables used on farms", outg.used, -1)
      row("", "auction house cut", outg.ahCut, 0)
      row("", "postage for settle mail", outg.postage, -1)
      row(GOLDC .. "Net|r", "in minus out", tin - tout, 0)
      return string.format("%sGold flow, %s|r (as seen by Kina)   %s|r", GOLDC, period(), GREY),
        { "", "What", "Amount" }, { 0, 110, 470 }, out, {}
    elseif view == "xp" then
      local gains, rolled = C.Rep.History()
      local m = C.Rep.Mine()
      for _, w in ipairs(C.Books.Waiting()) do
        out[#out + 1] = { cols = { GREEN .. "waiting|r", w.what, w.why or "", w.xp > 0 and ((w.paused and GREY or GREEN) .. "+" .. w.xp .. "|r") or "" }, sort = { 0, w.what, "", w.xp } }
      end
      for i = #gains, 1, -1 do
        local g = gains[i]
        if not ui.ledgerDays or C.Now() - g.t <= ui.ledgerDays * 86400 then
          local what
          if g.kind == "farm" then what = string.format("shared farm %s, %d min", g.label or "", math.floor((g.secs or 0) / 60))
          elseif g.kind == "short" then
            local why = g.why == "under10" and "someone under level 10" or (g.why == "gold" and "made less than its gold target" or "needs 15")
            what = string.format("shared farm %s, %d min (%s)", g.label or "", math.floor((g.secs or 0) / 60), why)
          elseif g.kind == "pay" then what = string.format("paid %s %s (%s, confirmed)", C.Books.Name(g.who), C.Money(g.paidOff), g.via)
          else what = string.format("%s paid you %s (%s, confirmed)", C.Books.Name(g.who), C.Money(g.cameIn), g.via) end
          local note = g.paused and (ORANGE .. "sharing off|r") or (g.xp < g.want and (GREY .. "daily cap|r") or "")
          out[#out + 1] = { cols = { day(g.t), what, note, g.xp > 0 and ("+" .. g.xp) or (GREY .. "0|r") }, sort = { g.t, what, "", g.xp } }
        end
      end
      if rolled > 0 then out[#out + 1] = { cols = { GREY .. "older|r", "rolled up after 90 days", "", "+" .. rolled }, sort = { 0, "", "", rolled } } end
      return string.format("%sXP:|r Kina level %s, %d XP %s(unverified)|r%s", GOLDC, C.Rep.Roman(m.level), m.xp, GREY, ""),
        { "When", "What", "Note", "XP" }, { 0, 70, 560, 700 }, out, {}
    end
    local rows, tot = C.Books.Farms(ui.ledgerDays)
    for _, r in ipairs(rows) do
      local st = (#r.debts == 0) and (GREY .. "even|r") or (r.open and (ORANGE .. "open|r") or (GREEN .. "settled|r"))
      out[#out + 1] = { book = r.s, cols = { day(r.t), r.label .. "  " .. st, tostring(r.players), money(r.farmed), money(r.share), money(r.collected),
        r.toCollect >= 1 and (ORANGE .. money(r.toCollect) .. "|r") or money(0), money(r.paid), r.owe >= 1 and (ORANGE .. money(r.owe) .. "|r") or money(0),
        r.xp > 0 and ("+" .. r.xp) or (GREY .. "-|r") },
        sort = { r.t or 0, r.label, r.players, r.farmed, r.share, r.collected, r.toCollect, r.paid, r.owe, r.xp } }
    end
    local head = string.format("%sFarms, %s:|r farmed %s, collected %s, %sto collect %s|r, paid %s, %syou owe %s|r, XP +%d (%d waiting)   %s(click a farm for its details)|r",
      GOLDC, period(), money(tot.farmed), money(tot.collected), ORANGE, money(tot.toCollect), money(tot.paid), ORANGE, money(tot.owe), tot.xp, tot.waiting, GREY)
    return head, { "Date", "Farm", "Players", "Farmed", "Your share", "Collected", "To collect", "Paid", "You owe", "XP" },
      { 0, 46, 210, 260, 345, 430, 515, 600, 680, 760 }, out,
      { empty = "No farms yet. Press Start on the Kina widget when you farm; every farm shows up here with its gold, debts and XP." }
  end
end

function C.OpenFarmLog(s)
  ui.logOf = s or (C.session and "current") or C.db.sessions[1]
  ui.offset = 0; ui.sort.Session = nil
  C.Toggle("Session")
end

tabs.Session = function()
  if ui.logOf then
    local live = ui.logOf == "current"
    local s = live and C.session or (type(ui.logOf) == "table" and ui.logOf) or nil
    if s then
      local out = farmLog(s, live)
      return string.format("|cffffd100Farm log: %s|r%s   |cff9d9d9d(click here to go back to all farms)|r", s.label or "farm", live and " (running)" or ""),
        { "When", "What", "Details", "Count", "Value" }, { 0, 60, 240, 620, 690 }, out,
        { headClick = function() ui.logOf = nil; ui.offset = 0; C.Refresh() end }
    end
    ui.logOf = nil
  end
  local out = {}
  local function add(label, r, live, ref)
    out[#out + 1] = { slog = ref, cols = { (live and "|cff7CFC00" or "") .. label .. (live and "|r" or ""), string.format("%d min", math.floor(r.secs / 60)),
      C.Money(r.total), C.Money(r.perHour), string.format("coin %s, pickpocket %s, vendor %s, items %s", C.Money(r.coin),
      C.Money(r.pickpocket), C.Money(r.vendor), C.Money(r.items)), tostring(r.kills) },
      sort = { label, r.secs, r.total, r.perHour, r.coin + r.pickpocket, r.kills } }
  end
  local s = C.SessionSummary()
  if s then add("Current", s, true, "current") end
  for i = 1, math.min(#C.db.sessions, 50) do
    local ss = C.db.sessions[i]
    if ss.result then add((ss.label or "?") .. (ss.why and ss.why ~= "stopped" and (" (" .. ss.why .. ")") or ""), ss.result, false, ss) end
  end
  return "Start/Stop on the farm widget before and after farming. |cff7CFC00Click a farm to see its log:|r how its Net adds up, and every kill, loot and gold change it counted.",
    { "Session", "Length", "Total", "Per hour", "Breakdown", "Kills" }, { 0, 220, 300, 400, 500, 790 }, out
end

------------------------------------------------------------------ column help
-- Hover a column title: what it means and an example of using it.
-- { meaning, example } per column title (colour codes and sort arrows ignored).
local COL_TIPS = {}
local DEAL = {
  ["Item"] = { "The item to buy. Click the row for its details: every cheap listing, and a live calculator that shows the profit at any price you type.",
    "Click a row, type the price you see on the AH into Live price, and Kina says what one item makes at that price." },
  ["Type"] = { "How the money is made. AH->Vendor: buy on the AH, sell to any merchant. Disenchant: buy, disenchant, sell the materials on the AH. Orange '(25m old)' = the price is from a scan over 20 minutes old.",
    "AH->Vendor pays the moment you reach a vendor, with nothing to post. Disenchant needs an enchanter and an AH listing for the materials." },
  ["Max each"] = { "The most to pay for ONE item and still make about 10% after the 5% AH cut. It is not break-even: break-even is Sells for (each).",
    "Max each 1g 00s, Sells for 1g 10s: buy every listing at or under 1g (put 1g in your sniper's max price). A listing at 1g 08s still doesn't lose money, but it isn't worth your time." },
  ["Units"] = { "How many listings are at or under Max each right now. 'N of M': Kina counts only N, so your disenchant materials don't outnumber what's listed today (or, in the passive view, what your gold pays for).",
    "'12 of 30': buy 12. Buying all 30 would flood the material market and drag today's price down." },
  ["Deposits"] = { "Gold the AH holds while you post what you resell. You get it back when it sells and lose it if the auction expires. Kina counts 5% of the vendor price (0 when there is none).",
    "'none' on an AH->Vendor row: nothing to post, nothing at risk." },
  ["Cash needed"] = { "All the gold the whole deal ties up: buying every unit plus the deposits. Red = more than you're carrying.",
    "Cash needed 25g with 18g on you: buy fewer units, or do a cheaper deal first." },
  ["Profit"] = { "What the whole deal makes at today's listing prices: (what each turns into - what you pay for it) for every unit, minus your time per trade. It uses the real listing prices, usually below Max each.",
    "Profit 3g 20s on 12 units = about 26s each. If the cheap ones sell before you get there, the profit shrinks but stays positive as long as you pay no more than Max each." },
  ["Guardian"] = { "Protection against bad luck: the chance you get back LESS than you paid, for the number in brackets (what your gold covers). Disenchanting is random: a deal can be profitable on average only because of a rare shard, and a small batch may never see one. Hover a row for the chance at other amounts. Green 5% or less, yellow up to 30%, red above. AH->Vendor is always 0%.",
    "'80% (20)': buying 20 loses money 4 times out of 5. If the row says 40: 20% and 50: 0%, buy 50 or skip it." },
  ["ROI"] = { "Profit per gold spent.",
    "ROI 40%: every 1g you spend comes back as 1g 40s. Type a number in the Min ROI box to hide anything lower." },
  ["Sell at least"] = { "The lowest price to list each disenchant material at and still get back what you paid (after the 5% cut). Every material is scaled down by the same share, so the list keeps today's price balance between them. AH->Vendor rows show what the vendor pays. Hover a row for today's cheapest price next to each minimum.",
    "'Soul Dust 38s, Greater Astral Ess. 1g 10s': undercutting down to those prices still breaks even; anything above is profit." },
}
COL_TIPS.Deals = DEAL
COL_TIPS.Invest = setmetatable({
  ["Max each"] = { "The most to pay for ONE item and still make about 10%, measured against the price Kina expects it to sell for (from its sales history, not today's asking prices).",
    "Max each 2g, expected sale 2g 30s: buy at or under 2g, list it, and wait for buyers." },
  ["Units"] = { "How many to buy. Kina lowers this until buying that many reaches your confidence target (Settings: Confidence I need). 'N of M' = only N of the M cheap listings pass.",
    "'3 of 10': three will very likely sell in time; all ten probably won't." },
  ["Exp. profit"] = { "Profit if things sell as expected: after the 5% cut, minus deposits lost to relisting and your time.",
    "Exp. profit 5g at 80% confidence: most of the time you make about 5g; sometimes less, or you wait longer." },
  ["Confidence"] = { "The chance every unit sells at a profit within your wait time (Settings: Most days I'll wait), from the sales Kina has seen and how much the price swings. '~' = demand is still estimated.",
    "85%: about 1 time in 7 they won't all sell in time. Set Confidence I need to 90 to see only safer buys." },
  ["Sells in"] = { "About how long until all the units sell, from how fast listings vanished between scans.",
    "'Sells in 2d': your gold is tied up about two days; fine for a passive flip, bad if you need the gold tonight." },
}, { __index = DEAL })
COL_TIPS.Vendor = {
  ["Merchant"] = { "What the merchant charges for one.", "Merchant 20s, AH 45s: buy from the vendor, list on the AH." },
  ["AH"] = { "The cheapest listing on the AH at your last scan.", "If AH is barely above Merchant, other players are already doing this flip." },
  ["Net each"] = { "What you keep per item: AH price after the 5% cut, minus the merchant price.", "Net each 21s 75c x 20 bought = about 4g 35s if they all sell." },
  ["ROI"] = { "Net each per gold spent at the merchant.", "ROI 100%: you double your money on each one that sells." },
  ["Listed / sellers"] = { "How many are listed now and by how many players. (stock N) = the merchant only has N.", "'40 / 1': one seller holds the market and can undercut you; '3 / 3' is a thin, easy market." },
  ["Where"] = { "The merchant and zone. Right-click the row for a waypoint.", "Right-click > Vendor waypoint puts a TomTom arrow on the nearest one." },
}
COL_TIPS.Bags = {
  ["Do this"] = { "Kina's advice for this stack: SELL NOW (AH), SELL (can wait), DISENCHANT, VENDOR or HOLD.", "VENDOR on a green = the AH and disenchanting both pay less than a merchant." },
  ["Each"] = { "What one is worth by the advised route.", "Each 45s on a SELL row = about what you'll get per item after the cut." },
  ["Total"] = { "Each x how many you carry.", "Sort by Total to deal with your most valuable stacks first." },
  ["Why"] = { "The numbers behind the advice.", "'AH 1g vs vendor 20s' tells you why it says SELL." },
}
COL_TIPS.Farms = {
  ["Farm (level)"] = { "The mob, route or service, with its level. Click for details (loot, skins, pickpocket, verdict).", "Click a row, then right-click it for a waypoint." },
  ["Type"] = { "Kill, Pick (pickpocket), Pick+Kill, Lockpick, Chest run and so on.", "Pick+Kill rows add pickpocket gold before each kill." },
  ["Gold/hour"] = { "Expected gold per hour from Kina's loot records at today's prices, after town trips. '*' = Kina's own estimate (kills per hour, coin per kill and nodes per hour have no Forever source), until your farm sessions measure it.", "Farm the top row for an hour with Start/Stop farm running and Kina replaces the estimate with your real rate." },
  ["Gold/h each"] = { "Duo mode: gold per hour per person (the total split two ways).", "Gold/h each 3g = 6g/hour for the pair." },
  ["Per kill / pick"] = { "Average value of one kill (or one pickpocket).", "Per kill 12s at 60 kills/hour = about 7g 20s/hour before town trips." },
  ["Evidence"] = { "How much data stands behind the number: your kills / everyone's kills, picks, or the source.", "'3 / 400 kills' is solid; '0 / 0' rows are guesses." },
  ["Distance"] = { "How far you are from this farm's waypoint, in yards (straight line).", "Click the header to sort nearest first." },
  ["Where"] = { "Zone or area.", "Sort by Where to plan a route through one zone." },
}
COL_TIPS.Crafts = {
  ["Recipe"] = { "What the recipe makes. Click for reagents and where to learn it.", "Click, then Search AH: result to check the live price." },
  ["Status"] = { "Learned (colour = skill-up chance), Can learn, Find pattern, or the skill needed.", "Sort by Status to see what you can learn right now." },
  ["Sells for"] = { "What the result sells for (AH after cut; (v) = to a vendor).", "Sells for 1g with Reagents 60s = 40s per craft." },
  ["Reagents"] = { "What the reagents cost to buy now. '~' = estimated; '+?' = some reagents have no price.", "Reagents '45s +?': at least 45s, one reagent unpriced." },
  ["Profit"] = { "Sells for minus Reagents, per craft.", "Profit 40s x 20 crafts = 8g." },
  ["Vs mats"] = { "Profit compared with just selling the reagents instead of crafting.", "Vs mats negative: sell the mats, don't craft." },
  ["Learn from"] = { "Trainer, vendor or drop that teaches it. The recipes are from Forever's game data, but trainer and vendor LOCATIONS partly come from Classic (Questie) data and are not confirmed for Forever.", "If a waypoint leads to the wrong NPC, the location changed in Forever." },
}
COL_TIPS.Plan = {
  ["Adds"] = { "Extra gold per hour this profession adds on your best farms.", "Skinning +2g/h: worth training before your next farm." },
  ["Now"] = { "Your current skill (or none).", "'-' = you don't have it yet." },
  ["How it was worked out"] = { "Which farms and prices the estimate comes from.", "Hover a row for the full working." },
}
COL_TIPS.Favor = {
  ["Crate on AH"] = { "Cheapest listing of the crate.", "If it's cheap, buy the crate instead of turning in a bundle." },
  ["Cheapest bundle"] = { "The cheapest set of goods to turn in for this crate.", "Buy that bundle on the AH and hand it in." },
  ["Gold/Favor"] = { "Gold per Favor point through the cheapest route.", "Lower is better: sort by it." },
  ["Sell looted"] = { "What a looted crate nets on the AH after the cut.", "Compare with opening it." },
  ["Bundle cost"] = { "What the cheapest bundle costs to buy on the AH right now.", "Bundle cost 2g for a crate worth 3g on the AH: buy and turn in." },
  ["Crate (Favor)"] = { "The Merchant's Favor crate and the Favor it costs.", "Click a row for the crate's details." },
}
COL_TIPS.Track = {
  ["Lowest now"] = { "Cheapest listing at your last scan.", "Under your buy target = it's highlighted green in Targets." },
  ["7-day median"] = { "The middle price over the last week.", "Lowest now well under the median = a good time to buy." },
  ["Trend"] = { "Average daily price change.", "-5%/day: wait before buying; +5%/day: sell soon." },
  ["Listed"] = { "How many are on the AH.", "A thin market (few listed) moves fast." },
  ["In bags"] = { "How many you're carrying.", "" },
  ["Targets"] = { "Your buy-under and sell-at prices (Settings > Stockpile target).", "'4 under target': four listings are below your buy price." },
}
COL_TIPS.Ledger = {
  ["Bought"] = { "How many you bought to flip (on the AH, or from a vendor and then listed on the AH).", "Hover a row for every step: when you bought, disenchanted, posted and sold." },
  ["Paid"] = { "Total gold you paid for them.", "" },
  ["Got back"] = { "Gold from selling them (AH after the cut, or a vendor) plus disenchant materials valued at today's cheapest listing after the cut.", "Mats you haven't sold yet count at today's price." },
  ["Profit"] = { "Got back minus what those items cost you. Items still held aren't counted until you sell or disenchant them.", "+1g 20s: that flip made money (if the mats sell at today's price)." },
  ["ROI"] = { "Profit per gold spent on the items you've used so far.", "" },
  ["Status"] = { "done = every unit sold or disenchanted; holding = still in your bags or on the AH.", "" },
}
COL_TIPS.Session = {
  ["Length"] = { "How long the farm ran.", "" },
  ["Total"] = { "Everything earned: coin, pickpockets, vendor value and items at today's prices.", "" },
  ["Per hour"] = { "Total per hour.", "Compare farms by this, not by Total." },
  ["Breakdown"] = { "Where the gold came from.", "Mostly items? Their value depends on selling them." },
  ["Kills"] = { "Kills during the session.", "" },
}
COL_TIPS.any = {
  ["Item"] = { "The item. Click the row for details, right-click for actions (track, search the AH, waypoint), shift-click to link it in chat.", "" },
  ["Recipe"] = { "What the recipe makes. Click for reagents and where to learn it.", "" },
  ["Who"] = { "You, or your farming partner.", "" },
  ["Profession"] = { "The profession.", "" },
  ["Session"] = { "Farm session name (green = running now).", "" },
}
local function colTip(tab, title)
  local key = plain(title):gsub(" [v%^]$", "")
  local t = (COL_TIPS[tab] and COL_TIPS[tab][key]) or COL_TIPS.any[key]
  return key, t
end
C.ColTip = colTip

------------------------------------------------------------------ widgets
local function button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22); b:SetText(text); b:SetScript("OnClick", onClick)
  if b.GetFontString and b:GetFontString() and C.Font then b:GetFontString():SetFontObject(C.Font("GameFontNormal")) end
  if C.Skin then C.Skin.Button(b) end
  return b
end
C.UIButton = button

-- tiny right-click menu
local menu
local function showMenu(items)
  if not menu then
    menu = CreateFrame("Frame", "KinaMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true)
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      menu:SetBackdropColor(0.05, 0.05, 0.08, 0.95); menu:SetBackdropBorderColor(0.3, 0.76, 0.97, 0.9)
    end
    menu.buttons = {}
    menu:EnableMouse(true)
    menu:SetScript("OnLeave", function(self) C.After(0.8, function() if not self:IsMouseOver() then self:Hide() end end) end)
  end
  for _, b in ipairs(menu.buttons) do b:Hide() end
  for i, it in ipairs(items) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetSize(180, 18); b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
      b.text = C.Text(b, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 6, 0)
      menu.buttons[i] = b
    end
    b.text:SetText(it[1])
    b:SetScript("OnClick", function() menu:Hide(); it[2]() end)
    b:Show()
  end
  menu:SetSize(188, #items * 18 + 8)
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 10, y / s + 10)
  menu:Show()
end

------------------------------------------------------------------ actions
function C.ItemLink(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return id and select(2, fn(id))
end

-- Search the auction house for an item (Auctionator if loaded, else the Blizzard box).
function C.SearchAH(id)
  local name = itemName(id)
  if not C.ahOpen then C.Print("open the auction house first, then search " .. name .. "."); return end
  -- 1) ForeverForge's auction window, when it's the one showing: its Browse page
  local ffa = rawget(_G, "ForeverForgeAuction")
  local w = type(ffa) == "table" and ffa.Window
  if w and w.frame and w.frame.IsShown and w.frame:IsShown() then
    local ok, done = pcall(function()
      if w.Current and w:Current() ~= "browse" and w.Select then w:Select("browse") end
      local page = w.pages and w.pages.browse
      if page and page.view and page.view.SearchFor then page.view:SearchFor(name); return true end
    end)
    if ok and done then return end
  end
  -- 2) Blizzard's auction window: fill the box and press Search
  local ah = AuctionHouseFrame
  local bar = ah and ah.SearchBar
  if ah and ah.IsVisible and ah:IsVisible() and bar and bar.SearchBox and bar.SearchBox.SetText then
    if ah.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
      pcall(ah.SetDisplayMode, ah, AuctionHouseFrameDisplayMode.Buy)
    end
    bar.SearchBox:SetText(name)
    local ok = bar.StartSearch and pcall(bar.StartSearch, bar)
    if not ok and bar.SearchButton and bar.SearchButton.Click then ok = pcall(bar.SearchButton.Click, bar.SearchButton) end
    if ok then return end
  end
  -- 3) Auctionator
  local atr = rawget(_G, "Auctionator")
  if type(atr) == "table" and atr.API and atr.API.v1 and atr.API.v1.MultiSearchExact then
    if pcall(atr.API.v1.MultiSearchExact, "Kina", { name }) then return end
  end
  C.Print("search for: " .. name)
end

local function itemMenu(id, row)
  local items = {
    { "Details and price history", function() C.ShowItem(id) end },
    { "Search on auction house", function() C.SearchAH(id) end },
    { C.IsTracked(id) and "Stop tracking" or "Track this item", function() C.ToggleTrack(id); C.Refresh() end },
  }
  if C.NearestVendor(id) then items[#items + 1] = { "Waypoint to nearest vendor", function() C.WaypointToVendor(id) end } end
  items[#items + 1] = { "Link in chat", function() local l = C.ItemLink(id); if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end end }
  showMenu(items)
end

local function mobWaypoint(npc, name)
  local own = C.LootRecord and C.LootRecord(npc) or C.db.loot[npc]
  if own and own.locs then
    local bestMap, best
    for map, p in pairs(own.locs) do if not best or p.n > best.n then bestMap, best = map, p end end
    if best then return C.Waypoint(bestMap, best.x, best.y, name) end
  end
  local f = C.NPCFacts(npc)
  local p = f and C.Nearest(f.spawns)
  if p then return C.Waypoint(p[1], p[2], p[3], name) end
  C.Print("no location known for " .. tostring(name) .. ".")
end

local function mobMenu(row)
  showMenu({
    { "Mob details", function() C.ShowMob(row.npc, row.farm) end },
    { "Waypoint (TomTom arrow)", function() mobWaypoint(row.npc, row.farm and row.farm.name) end },
  })
end

-- an invisible strip over a template title bar: grabbing it always drags the window
local function titleStrip(f)
  local h = CreateFrame("Frame", nil, f)
  h:SetPoint("TOPLEFT", 4, -2); h:SetPoint("TOPRIGHT", -28, -2); h:SetHeight(20)
  h:SetFrameLevel(f:GetFrameLevel() + 20)
  return h
end

------------------------------------------------------------------ detail panel
local detail
local function buildDetail()
  -- A child of the main window, drawn above everything in it, with a solid
  -- background, so table text can never show through it.
  detail = CreateFrame("Frame", "KinaDetail", ui.frame, "BasicFrameTemplateWithInset")
  detail:SetSize(380, H)
  -- always on top: other addons (ForeverForge) sit at high stratas
  detail:SetFrameStrata("FULLSCREEN_DIALOG"); detail:SetToplevel(true); detail:SetFrameLevel(100)
  detail:EnableMouse(true) -- clicks on the panel never fall through to rows underneath
  local solid = detail:CreateTexture(nil, "BACKGROUND", nil, -8)
  solid:SetPoint("TOPLEFT", 2, -2); solid:SetPoint("BOTTOMRIGHT", -2, 2); solid:SetColorTexture(0.06, 0.06, 0.08, 1)
  if detail.TitleText then detail.TitleText:SetText("Details") end
  -- drag it by its title bar; once moved it stays where you put it (/kina reset re-docks it)
  C.MakeDraggable(detail, "detailPos", titleStrip(detail))
  detail.lines = {}
  detail.graph = CreateFrame("Frame", nil, detail)
  detail.graph:SetSize(340, 130); detail.graph:SetPoint("TOPLEFT", 20, -250)
  local bg = detail.graph:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
  detail.graph.bars, detail.graph.dots = {}, {}
  detail.graph.caption = detail.graph:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail.graph.caption:SetPoint("TOPLEFT", detail.graph, "BOTTOMLEFT", 0, -4); detail.graph.caption:SetWidth(340); detail.graph.caption:SetJustifyH("LEFT")
  -- live price calculator: "1g2s50c", "12s" or plain copper
  detail.calcLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail.calcLabel:SetPoint("BOTTOMLEFT", 20, 92); detail.calcLabel:SetText("Live price")
  detail.calc = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
  detail.calc:SetSize(90, 18); detail.calc:SetPoint("LEFT", detail.calcLabel, "RIGHT", 10, 0); detail.calc:SetAutoFocus(false)
  detail.calcOut = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail.calcOut:SetPoint("BOTTOMLEFT", 20, 72); detail.calcOut:SetWidth(344); detail.calcOut:SetJustifyH("LEFT")
  detail.calc:SetScript("OnTextChanged", function(self)
    local p = C.ParseMoney(self:GetText())
    detail.calcOut:SetText(detail.calcID and p and C.ProfitAtText(detail.calcID, p) or "")
  end)
  detail.calc:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  detail.calc:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if C.ScaleGrip then C.ScaleGrip(detail, "detailScale") end
  detail.buttons = {}
  for i = 1, 8 do
    local b = button(detail, "", 170, function() end)
    b:SetPoint("BOTTOMLEFT", 16 + ((i - 1) % 2) * 178, 14 + math.floor((i - 1) / 2) * 26)
    detail.buttons[i] = b
  end
end

-- Beside the main window when the screen has room, otherwise over the right side
-- of the table (above the bottom buttons).
local function placeDetail()
  local f = ui.frame
  detail:ClearAllPoints()
  local right, screen = f:GetRight(), UIParent:GetRight()
  local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local g = detail.graph
  g:ClearAllPoints()
  if C.settings.pos.detailPos then
    detail:SetHeight(H); C.RestorePos(detail, "detailPos", "CENTER", UIParent, "CENTER", 0, 0)
    g:SetScale(1); g:SetPoint("TOPLEFT", detail, "TOPLEFT", 20, -250)
  elseif right and screen and (right + 384) * scale <= screen then
    detail:SetHeight(H); detail:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    g:SetScale(1); g:SetPoint("TOPLEFT", detail, "TOPLEFT", 20, -250)
  else
    -- shorter panel: shrink the chart so it clears the buttons
    detail:SetHeight(H - 66); detail:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -26)
    g:SetScale(0.8); g:SetPoint("TOPLEFT", detail, "TOPLEFT", 20 / 0.8, -250 / 0.8)
  end
end

local function setLines(lines)
  if detail.calc then detail.calc:Hide(); detail.calcLabel:Hide(); detail.calcOut:Hide(); detail.calc:ClearFocus() end
  for i, text in ipairs(lines) do
    local fs = detail.lines[i]
    if not fs then
      fs = detail:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormalLarge" or "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", 18, -32 - (i - 1) * 16); fs:SetWidth(344); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
      detail.lines[i] = fs
    end
    fs:SetText(text); fs:Show()
  end
  for i = #lines + 1, #detail.lines do detail.lines[i]:Hide() end
end

local function setButtons(list)
  for i, b in ipairs(detail.buttons) do
    local it = list[i]
    if it then b:SetText(it[1]); b:SetScript("OnClick", it[2]); b:Show() else b:Hide() end
  end
end

-- 30-day chart: bars = daily median, dots = daily lowest price
local function drawGraph(id)
  local g = detail.graph
  local h = C.market.history[id] or {}
  local today = math.floor(C.Now() / 86400)
  local maxV = 0
  for d = today - 29, today do
    local p = h[d]; if p then maxV = math.max(maxV, p[2] or 0, p[1] or 0) end
  end
  local points = 0
  for i = 0, 29 do
    local d = today - 29 + i
    local p = h[d]
    local bar = g.bars[i + 1]
    if not bar then bar = g:CreateTexture(nil, "ARTWORK"); bar:SetColorTexture(0.3, 0.76, 0.97, 0.55); g.bars[i + 1] = bar end
    local dot = g.dots[i + 1]
    if not dot then dot = g:CreateTexture(nil, "OVERLAY"); dot:SetColorTexture(1, 0.82, 0, 1); dot:SetSize(5, 5); g.dots[i + 1] = dot end
    bar:Hide(); dot:Hide()
    if p and maxV > 0 then
      points = points + 1
      local x = 4 + i * 11
      local mh = math.max(1, (p[2] or p[1] or 0) / maxV * 120)
      bar:ClearAllPoints(); bar:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x, 4); bar:SetSize(8, mh); bar:Show()
      if p[1] then
        dot:ClearAllPoints(); dot:SetPoint("CENTER", g, "BOTTOMLEFT", x + 4, 4 + p[1] / maxV * 120); dot:Show()
      end
    end
  end
  g.caption:SetText(points > 0 and string.format("Last 30 days: bars = median, dots = lowest. Top of chart = %s. %d day(s) of data.", C.Money(maxV), points)
    or "No price history yet: every full scan adds a point for the day.")
  g:Show()
end

-- What each way out pays per unit after the cut: the most you can pay and still profit.
local function exits(id)
  local r = C.Item(id) or {}
  local list = {}
  -- resale is an investment: only once there is history showing the item sells
  local rn = C.Econ.DataStatus(id) and C.Econ.ResaleNet(id)
  if rn and rn > 0 and not (r.bind == 1 or r.bind == 4) then list[#list + 1] = { "resale", rn } end
  if C.CanDEFor(id) then
    local ev = C.Econ.DEValueNow(id)
    if ev and ev > 0 then list[#list + 1] = { "disenchant", ev } end
  end
  local v = C.VendorPrice(id)
  if v and v > 0 then list[#list + 1] = { "vendor", v } end
  return list
end

-- "At 13s: resale +2s 10c (16%), disenchant -1s 05c, vendor -6s 41c"
function C.ProfitAtText(id, price)
  if not price or price <= 0 then return "" end
  local parts = {}
  for _, e in ipairs(exits(id)) do
    local p = e[2] - price
    parts[#parts + 1] = string.format("%s %s%s|r (%.0f%%)", e[1], p >= 0 and "|cff7CFC00+" or "|cffff6060-", C.Money(math.abs(p)), 100 * p / price)
  end
  if #parts == 0 then return "no way to sell it is known yet" end
  return "At " .. C.Money(price) .. ": " .. table.concat(parts, ", ")
end

function C.ShowItem(id)
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local r = C.Item(id) or {}
  local mi = C.MarketItem(id)
  local route, unit, det = C.BestRoute(id, 1)
  local vend = C.VendorPrice(id)
  local buyAt = C.MerchantPrice and C.MerchantPrice(id)
  local dv = C.CanDE(id) == true and C.DEValue(id)
  local trend = C.Trend(id, 5)
  local nv = C.NearestVendor(id)
  local lines = {
    qualityColor(id) .. (r.name or ("item " .. id)) .. "|r",
    (function()
      -- the actual cheapest listings: medians/averages of a thin book are meaningless
      local parts = {}
      for i, st in ipairs(mi and mi.l or {}) do if i <= 4 then parts[#parts + 1] = C.Money(st[1]) .. " x" .. st[2] end end
      local _, who, t = C.MarketItem(id)
      local src = mi and (who and ((Ambiguate and Ambiguate(who, "short") or who) .. "'s scan") or "your scan") or ""
      return "Cheapest: " .. (#parts > 0 and table.concat(parts, ", ") or "not listed") ..
        (t and string.format("  |cff9d9d9d(%s, %d min ago)|r", src, math.floor((C.Now() - t) / 60)) or "")
    end)(),
    string.format("Listed %s units by %s sellers   7-day median %s", mi and mi.q or 0, mi and mi.n or 0, C.WeekMedian(id) and C.Money(C.WeekMedian(id)) or "-"),
    string.format("Trend %s   Vendor pays %s   Merchant sells at %s", trend and string.format("%+.0f%%/day", trend * 100) or "-", vend and C.Money(vend) or "-", buyAt and C.Money(buyAt) or "-"),
    dv and string.format("Disenchant: %s expected (worst %s, best %s)", C.Money(dv.ev), C.Money(dv.lo), C.Money(dv.hi)) or "Disenchant: not applicable",
    string.format("Best use: %s at %s each", route or "-", C.Money(unit or 0)),
    nv and string.format("Nearest vendor: %s, %s %.0f, %.0f", nv.name, nv.zone or "?", nv.x * 100, nv.y * 100) or "Nearest vendor: none known",
  }
  -- per-item profit: the most you can pay, and what buying at today's lowest makes
  local ex = exits(id)
  do
    local ok, days, scans, sales, nd, ns = C.Econ.DataStatus(id)
    if ok then
      local net, target, why = C.Econ.ResaleTarget(id)
      lines[#lines + 1] = net and string.format("|cff9d9d9dInvestment:|r relist at %s, you keep %s (%s)", C.Money(target), C.Money(net), why)
        or ("|cff9d9d9dInvestment:|r no resale (" .. (why or "no market") .. ")")
    else
      lines[#lines + 1] = string.format("|cff9d9d9dInvestment: collecting history (%d/%d days, %d/%d scans, sales seen: %s)|r",
        days, nd, scans, ns, sales and "yes" or "not yet")
    end
  end
  if #ex > 0 then
    local pay = {}
    for _, e in ipairs(ex) do pay[#pay + 1] = e[1] .. " " .. C.Money(e[2]) end
    lines[#lines + 1] = "|cffffd100Pay at most|r (break-even): " .. table.concat(pay, ", ")
    if mi and mi.m then lines[#lines + 1] = C.ProfitAtText(id, mi.m) .. " |cff9d9d9d(scan)|r" end
  end
  do
    local sigma, mu, n, swing, real = C.Econ.Volatility(id)
    if real and swing then
      lines[#lines + 1] = string.format("Price moved %.0f%% high-to-low over the last %d scans (%s%.1f%%/day trend)",
        swing * 100, n, mu >= 0 and "+" or "", (math.exp(mu * 24) - 1) * 100)
    else
      lines[#lines + 1] = "|cff9d9d9dVolatility: needs 3+ scans of this item|r"
    end
  end
  lines[#lines + 1] = "|cff9d9d9dType the live price below to see the profit per item.|r"
  if C.IsTracked(id) then lines[#lines + 1] = "|cff7CFC00Tracked|r" end
  setLines(lines)
  detail.calcID = id
  detail.calc:SetText("")
  detail.calcOut:SetText("")
  detail.calc:Show(); detail.calcLabel:Show(); detail.calcOut:Show()
  drawGraph(id)
  setButtons({
    { "Search AH", function() C.SearchAH(id) end },
    { C.IsTracked(id) and "Untrack" or "Track", function() C.ToggleTrack(id); C.ShowItem(id); C.Refresh() end },
    { "Vendor waypoint", function() C.WaypointToVendor(id) end },
    { "Link in chat", function() local l = C.ItemLink(id); if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end end },
  })
  if not nv then detail.buttons[3]:Hide() end
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

function C.ShowMob(npc, farm)
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local own = C.LootRecord and C.LootRecord(npc) or C.db.loot[npc]
  local q = C.NPCFacts(npc)
  local info = C.NPCInfo(npc) or {}
  local name = (q and q.nm) or (own and own.nm) or info.nm or ("NPC " .. npc)
  local minL = (q and q.minLvl) or (own and own.lvl) or info.lvl
  local maxL = (q and q.maxLvl) or info.maxLvl or minL
  local rankName = (q and q.rankName) or info.rankName or ((own and own.elite) and "Elite") or (info.elite and "Elite") or "Normal"
  local ctype = (own and own.type) or info.type or "?"
  local zone, spawnCount = own and own.zone, q and #q.spawns or 0
  if not zone and q and q.spawns[1] then zone = C.MapName(q.spawns[1][1]) end
  zone = zone or (farm and farm.zone)
  local label, color, notes = C.Difficulty(minL, rankName, ctype, zone)
  local lines = {
    name .. (q and q.sub and q.sub ~= "" and (" <" .. q.sub .. ">") or ""),
    string.format("Level %s%s   %s   %s", tostring(minL or "?"), (maxL and maxL ~= minL) and ("-" .. maxL) or "", rankName, ctype),
    string.format("Difficulty for you: |cff%s%s|r", color, label),
    string.format("Where: %s%s%s", zone or "unknown", own and own.subzone and (" (" .. own.subzone .. ")") or "",
      spawnCount > 0 and string.format(", %d spawn points", spawnCount) or ""),
  }
  for _, n in ipairs(notes) do lines[#lines + 1] = "- " .. n end
  if farm then
    local g = farm.group or 1
    lines[#lines + 1] = string.format("|cffffd100Per kill: %s|r   no rare (<%s%%): %s   per hour: %s%s",
      C.Money(farm.perKill), tostring(C.settings.rareRate or 2.5), C.Money(farm.perKillCommon or 0),
      farm.rate and C.Money(farm.rate.rate) or "0", g > 1 and string.format("   (yours: totals / %d in group)", g) or "")
    lines[#lines + 1] = string.format("   coin %s (%s)   skins %s%s", C.Money(farm.coin), farm.coinBasis == "prior" and "level estimate until you loot 10" or farm.coinBasis,
      C.Money(farm.skins or 0), farm.skinBasis == "estimate" and " (leather estimate)" or "")
    if farm.snapLoots then
      local q = farm.snapQ or {}
      lines[#lines + 1] = string.format("   this mob's drops %s  (Wowhead Forever, %d loots: the same for everyone)", C.Money(farm.mobVal or 0), farm.snapLoots)
      lines[#lines + 1] = string.format("   world drops %s  (it drops greens %.1f%%, blues %.2f%%, recipes %.2f%% of kills; which one: level %s pool)",
        C.Money(farm.worldVal or 0), (q[2] or 0) / farm.snapLoots * 100, (q[3] or 0) / farm.snapLoots * 100, (q[9] or 0) / farm.snapLoots * 100, tostring(farm.level or "?"))
    else
      lines[#lines + 1] = string.format("   drops %s  (only your group's %d kills: not in the Wowhead snapshot)", C.Money(farm.mobVal or 0), farm.ownKills or 0)
    end
    if farm.gatherFarms then
      lines[#lines + 1] = string.format("   gathering %s per kill (%.0f nodes per 60 kills, from %d timed farm%s)", C.Money(farm.gather or 0),
        farm.nodes60 or 0, farm.gatherFarms, farm.gatherFarms == 1 and "" or "s")
    else
      lines[#lines + 1] = "   gathering: not measured yet (run the farm widget here and Kina counts the nodes you pick)"
    end
    if farm.rate then
      lines[#lines + 1] = string.format("|cffffd100Gold/hour (yours): %s|r  from %d timed farm%s %s (%.1f h)", C.Money(farm.rate.rate),
        farm.rate.n, farm.rate.n == 1 and "" or "s", farm.rate.label, farm.rate.hours)
    else
      lines[#lines + 1] = "|cffffd100Gold/hour: 0|r  no timed farm here with this group yet (farm widget: start at the flight path, stop back at the AH)"
    end
    local rg = farm.rogue
    if rg then
      lines[#lines + 1] = string.format("|cffffd100Rogue extras per kill %s|r%s: pockets coin %s, pocket items %s, junkboxes %s",
        C.Money(rg.total), rg.estimated and " (estimate)" or "", C.Money(rg.coin), C.Money(rg.items), C.Money(rg.boxes))
      if rg.boxHow then lines[#lines + 1] = "   junkboxes valued: " .. rg.boxHow end
      local pct = (farm.perKill or 0) > 0 and rg.total / farm.perKill * 100 or 0
      local verdict = pct >= 15 and "|cff7CFC00worth it|r" or (pct >= 5 and "|cffffd100small gain|r" or "|cffff6060not worth the time|r")
      lines[#lines + 1] = string.format("Picking adds %s per kill (%+.0f%%) %s", C.Money(rg.total), pct, verdict)
    end
  end
  if not farm and C.ClassMode and C.ClassMode() == "ROGUE" and C.PickBreakdown then
    local pk = C.PickBreakdown(npc)
    if pk then
      local pph = C.settings.picksPerHour or 120
      lines[#lines + 1] = string.format("|cffffd100Pick only, per pick %s|r: coin %s, items %s, junkboxes %s",
        C.Money(pk.total), C.Money(pk.coin), C.Money(pk.items), C.Money(pk.boxes))
      if pk.boxHow then lines[#lines + 1] = "   junkboxes valued: " .. pk.boxHow end
      lines[#lines + 1] = string.format("Per hour at %d picks/hour: %s (no kills)", pph, C.Money(pk.total * pph))
    end
  end
  -- top drops: chance x price = value per kill (the same numbers the ranking uses)
  local drops = {}
  local ROUTE = { AUCTION = "AH after cut", SELL = "AH after cut", VENDOR = "vendor", DISENCHANT = "disenchant", KEEP = "kept",
    thin = "few listings: safe price", affix = "random affix: cheapest roll" }
  local function addDrop(id, rate, world)
    local v, route, f
    if not world and farm and farm.kph0 and C.CappedValue then v, route, f = C.CappedValue(id, rate * farm.kph0) else v, route = C.FarmValue(id) end
    v = v or 0
    if rate > 0 and v > 0 then drops[#drops + 1] = { id = id, rate = rate, price = v, route = route, value = rate * v, world = world, share = f } end
  end
  if farm then
    for id, rate in pairs(farm.mobRates or {}) do addDrop(id, rate, false) end
    local _, _, wrates = C.SnapWorld(farm.npc)
    for id, rate in pairs(wrates or {}) do addDrop(id, rate, true) end
  end
  table.sort(drops, function(a, b) return a.value > b.value end)
  if #drops > 0 then lines[#lines + 1] = "Top drops: chance x price = per kill" end
  for i = 1, math.min(5, #drops) do
    local d = drops[i]
    local how = ROUTE[d.route] or (d.route or "?"):lower()
    if d.share and d.share < 1 then
      how = string.format("AH buys ~%d%% of what you'd loot, rest vendored", math.floor(d.share * 100 + 0.5))
    end
    lines[#lines + 1] = string.format("  %s%s  %.2f%% x %s (%s) = %s", itemCell(d.id), d.world and " |cff9d9d9d(world)|r" or "",
      d.rate * 100, C.Money(d.price), how, C.Money(d.value))
    -- random-affix gear: which rolls are listed, and how many
    local mi = C.MarketItem(d.id)
    if mi and mi.sl and #mi.sl > 0 then
      local parts, n = {}, mi.n or 0
      for k, e in ipairs(mi.sl) do n = n + (e[3] or 1); if k <= 4 then parts[#parts + 1] = (e[4] or "a roll") .. " " .. C.Money(e[1]) end end
      lines[#lines + 1] = string.format("     |cff9d9d9drolls listed: %s (%d listing%s in all)|r", table.concat(parts, ", "), n, n == 1 and "" or "s")
    end
  end
  if C.Pockets and C.ClassMode and C.ClassMode() == "ROGUE" then
    local first = true
    C.Pockets.TooltipLines(npc, function(l, r)
      if first then lines[#lines + 1] = ""; first = false end
      lines[#lines + 1] = l .. "   " .. (r or "")
    end)
  end
  while #lines > 25 do table.remove(lines) end
  setLines(lines)
  detail.graph:Hide()
  setButtons({
    { "Waypoint (TomTom)", function() mobWaypoint(npc, name) end },
    { "Close", function() detail:Hide() end },
  })
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

-- A ledger row: everything that happened to one item you bought, and what it made.
function C.ShowFlip(r)
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local lines = { qualityColor(r.id) .. itemName(r.id) .. "|r",
    string.format("Bought %d for %s (%s each)", r.bought, C.Money(r.paid), C.Money(r.avg)),
    r.done > 0 and string.format("|cffffd100Result on %d done: got back %s, %s%s|r profit", r.done, C.Money(r.got),
      r.result >= 0 and "|cff7CFC00+" or "|cffff6060-", C.Money(math.abs(r.result))) or "Nothing sold or disenchanted yet." }
  if r.left > 0 then lines[#lines + 1] = string.format("%d still held (%s each): counted once you sell or disenchant them.", r.left, C.Money(r.avg)) end
  if r.de > 0 then
    lines[#lines + 1] = string.format("|cffffd100Disenchanted %d:|r materials worth %s today, after the AH cut%s", r.de, C.Money(r.matsNow),
      r.matsKnown and "" or " (some unpriced)")
    local mats = {}
    for m, n in pairs(r.mats) do mats[#mats + 1] = { m, n } end
    table.sort(mats, function(a, b) return a[2] > b[2] end)
    for _, m in ipairs(mats) do
      local u = C.Econ and C.Econ.MatNow and C.Econ.MatNow(m[1])
      lines[#lines + 1] = string.format("   %d x %s  %s", m[2], itemCell(m[1]), u and (C.Money(u * m[2]) .. "  (" .. C.Money(u) .. " each)") or "no price yet")
    end
  end
  if r.vendorN > 0 then lines[#lines + 1] = string.format("Sold %d to a vendor for %s", r.vendorN, C.Money(r.vendor)) end
  if r.ahN > 0 then lines[#lines + 1] = string.format("Sold %d on the AH for %s (after the cut)", r.ahN, C.Money(r.ah)) end
  if r.deposits > 0 then lines[#lines + 1] = string.format("Deposits paid: %s", C.Money(r.deposits)) end
  lines[#lines + 1] = "|cffffd100What happened|r"
  for _, e in ipairs(r.events) do
    if #lines >= 25 then break end
    lines[#lines + 1] = "  " .. stepText(e) .. (e.fixed and " |cff9d9d9d(item corrected by the purchase mail)|r" or "")
      .. ((e.guess and not e.mailed) and " |cffff8040(item guessed: waiting for the purchase mail)|r" or "")
  end
  setLines(lines)
  detail.graph:Hide()
  setButtons({
    { "Item details", function() C.ShowItem(r.id) end },
    { "Close", function() detail:Hide() end },
  })
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

------------------------------------------------------------------ farms controls and route details
function C.RefreshFarmBar()
  local fb = ui.farmBar
  local lo, hi = C.FarmBand()
  fb.kind:SetText((ui.farmKind == "dungeon") and "Dungeons & elites" or "Open world")
  local g = C.GroupSize and C.GroupSize() or 1
  local LBL = { kill = "per kill", common = "per kill, no rare", hour = "per hour" }
  fb.mode:SetText("Rank: |cff7CFC00" .. (LBL[C.settings.farmMetric or "kill"] or "per kill") .. "|r")
  if fb.rare and not fb.rare:HasFocus() then fb.rare:SetText(tostring(C.settings.rareRate or 2.5)) end
  if not fb.lo:HasFocus() then fb.lo:SetText(tostring(lo)) end
  if not fb.hi:HasFocus() then fb.hi:SetText(tostring(hi)) end
  fb.uniq:SetText((C.settings.showUnique and "|cff40ff40[x]|r" or "[  ]") .. " Rare spawns")
  fb.enemy:SetText((C.settings.showEnemy and "|cff40ff40[x]|r" or "[  ]") .. " Enemy zones")
  local mode, cls = C.ClassMode()
  if cls == "ROGUE" or cls == "DRUID" then
    local nice = cls == "ROGUE" and "Rogue" or "Druid"
    fb.cls:SetText(mode and ("|cff40ff40[x]|r " .. nice .. " farms") or ("[  ] " .. nice .. " farms")); fb.cls:Show()
  else fb.cls:Hide() end
  local cur = "All farms"
  for _, o in ipairs(FARM_SHOW) do if o.key == (C.settings.farmShow or "all") then cur = o.label end end
  fb.show:SetText("Show: " .. cur .. "  v")
  local bits = { ((UnitName and UnitName("player")) or "?") .. " " .. ((UnitLevel and UnitLevel("player")) or "?") }
  if cls == "ROGUE" then
    bits[#bits + 1] = "Lockpicking " .. tostring(C.char.lockpicking or 0)
    local P = C.Pockets
    if P then
      local _, today = P.HaulStores()
      bits[#bits + 1] = string.format("pockets today %d (%s)%s", today.picks, C.Money(today.copper + today.value),
        P.standby and " via Kaydee's" or "")
    end
  elseif cls == "DRUID" then
    local h = C.char.prof and C.char.prof.Herbalism
    if h then bits[#bits + 1] = "Herbalism " .. h end
  end
  -- grouped: is the partner's Kina feeding this list?
  if C.GroupSize and C.GroupSize() > 1 then
    local pt = C.Partner and C.Partner()
    table.insert(bits, 1, (pt and pt.live) and ("|cff7CFC00synced with " .. pt.name .. "|r") or "|cffff8040group NOT synced|r")
  end
  fb.info:SetText(table.concat(bits, " | "))
end

local function rowWaypoint(r)
  local rt = r.route
  if rt and rt.map and rt.x then return C.Waypoint(rt.map, rt.x / 100, rt.y / 100, rt.name) end
  local P = C.Pockets
  local e = r.npc and P and P.Combined(r.npc)
  if e and e.locs then
    local best
    for _, l in ipairs(e.locs) do if not best or (l.n or 1) > (best.n or 1) then best = l end end
    if best then return C.Waypoint(best.m, best.x, best.y, r.name) end
  end
  if r.npc then return mobWaypoint(r.npc, r.name) end
  C.Print("no location for " .. tostring(r.name) .. ".")
end

function C.FarmRowMenu(r)
  if r.camp then return C.ShowCamp(r) end
  local items = { { "Details", function() C.ShowFarmRow(r) end }, { "Waypoint (TomTom)", function() rowWaypoint(r) end } }
  if r.item then items[#items + 1] = { "Search AH for " .. itemName(r.item), function() C.SearchAH(r.item) end } end
  showMenu(items)
end

-- A camp: its mob types, how each counts, and where the numbers come from.
-- Rename a camp (blank name = Kina's name again)
local RENAME = {
  text = "New name for this camp (leave it empty for Kina's name):",
  button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 40, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self, data)
    local eb = self.editBox or self.EditBox
    if eb and data then eb:SetText(C.CampName(data.camp)); eb:HighlightText() end
  end,
  OnAccept = function(self, data)
    local eb = self.editBox or self.EditBox
    local name = eb and eb:GetText() or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("|", "")
    C.CampEdit(data.camp, true).name = (name ~= "" and name ~= data.camp.name) and name or nil
    C.Refresh()
    for _, row in ipairs(C.CampRows({ all = true })) do if row.camp == data.camp then C.ShowCamp(row) end end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent(); local b = p.button1 or (p.GetButton1 and p:GetButton1()); if b then b:Click() end
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
function C.RenameCamp(r)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs["KINA_RENAME_CAMP"] = RENAME
  StaticPopup_Show("KINA_RENAME_CAMP", nil, nil, { camp = r.camp })
end

-- Edit mobs: take a mob out of a camp, add one you killed while farming it,
-- mark a beast as not skinnable, unpin the center, or reset to Kina's list.
function C.CampMobMenu(r)
  local c = r.camp
  local items, cur = {}, {}
  local function redo() if C.Refresh then C.Refresh() end; for _, row in ipairs(C.CampRows({ all = true })) do if row.camp == c then C.ShowCamp(row) end end end
  for _, id in ipairs(C.CampMobs(c)) do
    cur[id] = true
    items[#items + 1] = { "|cffff8040Take out:|r " .. npcName(id), function()
      local e = C.CampEdit(c, true)
      if e.add[id] then e.add[id] = nil else e.drop[id] = true end
      redo()
    end }
  end
  -- candidates: mobs killed in farms of this camp (or in its zone)
  local seen = {}
  for _, s in ipairs(C.db.sessions or {}) do
    if s.camp == c.key or (not s.camp and s.zone == c.zone) then
      for npc, k in pairs(s.byNpc or {}) do if not cur[npc] then seen[npc] = (seen[npc] or 0) + k end end
    end
  end
  if C.session and (C.session.camp == c.key) then for npc, k in pairs(C.session.byNpc or {}) do if not cur[npc] then seen[npc] = (seen[npc] or 0) + k end end end
  local cands = {}
  for npc, k in pairs(seen) do cands[#cands + 1] = { npc, k } end
  table.sort(cands, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(6, #cands) do
    local id = cands[i][1]
    items[#items + 1] = { "|cff7CFC00Add:|r " .. npcName(id) .. " (" .. cands[i][2] .. " killed)", function()
      local e = C.CampEdit(c, true)
      if e.drop[id] then e.drop[id] = nil else e.add[id] = true end
      redo()
    end }
  end
  for _, p in ipairs(r.campParts or {}) do
    if p.row and p.row.type == "Beast" then
      local no = C.NoSkin(p.npc)
      items[#items + 1] = { (no and "Can be skinned: " or "Can't be skinned: ") .. npcName(p.npc), function()
        C.db.noSkin = C.db.noSkin or {}
        C.db.noSkin[p.npc] = not no
        if C.InvalidateFarms then C.InvalidateFarms() end
        redo()
      end }
    end
  end
  local e = C.CampEdit(c)
  if e and e.pin then items[#items + 1] = { "Unpin the center", function() e.pin = nil; redo() end } end
  if e then items[#items + 1] = { "Reset to Kina's list", function() C.db.campEdits[c.key] = nil; redo() end } end
  showMenu(items)
end

function C.ShowCamp(r)
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local c = r.camp
  local ce0 = C.CampEdit(c)
  local lines = { (ce0 and ce0.fav and "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t " or "") .. "|cff7CFC00Camp:|r " .. C.CampName(c)
    .. ((C.CampName(c) ~= c.name) and (" |cff9d9d9d(" .. c.name .. ")|r") or ""), string.format("%s, levels %d-%d   %s", c.zone, c.lo, c.hi,
    c.src == "C" and "|cffff8040source: Classic guide (Forever may differ)|r" or "source: WoW Forever guide") }
  if c.note then lines[#lines + 1] = c.note end
  lines[#lines + 1] = string.format("|cffffd100Per kill: %s|r   no rare: %s   per hour: %s", C.Money(r.per or 0), C.Money(r.perCommon or 0),
    (r.perHour and r.perHour > 0) and (C.Money(r.perHour) .. " (" .. (r.rateFarms or 0) .. " timed farm" .. ((r.rateFarms or 0) == 1 and "" or "s") .. ")") or "time it")
  lines[#lines + 1] = r.measuredMix and "Mix: your kills here (timed farms)" or "Mix: equal share per mob type until you time a farm here"
  lines[#lines + 1] = "|cffffd100Mob types|r  (share x per kill)"
  table.sort(r.campParts, function(a, b) return (a.w or 0) > (b.w or 0) end)
  local wsum = 0
  for _, p in ipairs(r.campParts) do wsum = wsum + (p.w or 0) end
  local skin, beasts = 0, 0
  for _, p in ipairs(r.campParts) do
    lines[#lines + 1] = string.format("  %s (%s)  %d%% x %s  (no rare %s)", p.name or ("NPC " .. p.npc), tostring(p.level or "?"),
      math.floor((p.w or 0) / math.max(wsum, 1e-9) * 100 + 0.5), C.Money(p.per or 0), C.Money(p.common or 0))
    if p.beast then beasts = beasts + (p.w or 0); skin = skin + (p.w or 0) * (p.skins or 0) end
  end
  if beasts > 0 then
    local avg = skin / math.max(wsum, 1e-9)
    lines[#lines + 1] = avg > 0 and string.format("  |cffffd100Skinning|r  %s per kill on average (included above)", C.Money(avg))
      or "  |cffffd100Skinning|r  not counted: nobody in your group has Skinning (or Kina doesn't know it yet)"
  end
  -- (called directly: "f and f()" would keep only the first of its five results)
  local ok, map, x, y, n, all, pinned = pcall(C.CampCenter, c)
  if not ok or not (map and x and y) then map = nil end
  lines[#lines + 1] = (map and pinned) and string.format("Center: %.0f, %.0f  |cff7CFC00(pinned by you)|r", x * 100, y * 100)
    or map and string.format("Center: %.0f, %.0f  (%d of %d spawn points in %s around it)", x * 100, y * 100, n, all, c.zone)
    or "Center: no spawn points known for these mobs (needs the ForeverVendors NPC data)"
  local ed = C.CampEdit(c)
  if ed and (next(ed.add or {}) or next(ed.drop or {})) then lines[#lines + 1] = "|cff7CFC00Mobs edited by you|r (Edit mobs to change or reset)" end
  lines[#lines + 1] = "|cff7CFC00Farm this camp|r starts the farm widget for this camp, so the farm counts here."
  setLines(lines)
  detail.graph:Hide()
  setButtons({
    { "Farm this camp", function()
      if C.session then C.StopSession() end
      C.StartSession(C.CampName(c), false, c.key); C.ShowWidget(true)
    end },
    { "Waypoint (TomTom)", function()
      if map then C.Waypoint(map, x, y, "Camp: " .. c.name) else C.Print("no spawn points known for this camp.") end
    end },
    { "Pin center here", function()
      local pm, px, py = C.PlayerPos and C.PlayerPos()
      if not (pm and px and py) then C.Print("can't read your position here."); return end
      if C.MapName and C.MapName(pm) ~= c.zone then C.Print("you're not in " .. c.zone .. "; go to the camp first."); return end
      C.CampEdit(c, true).pin = { pm, px, py }
      C.Print(string.format("%s: center pinned at %.0f, %.0f.", c.name, px * 100, py * 100))
      C.ShowCamp(r)
    end },
    { "Edit mobs", function() C.CampMobMenu(r) end },
    { (ce0 and ce0.fav) and "Unfavorite" or "Favorite", function()
      local e = C.CampEdit(c, true); e.fav = (not e.fav) or nil
      C.Refresh(); C.ShowCamp(r)
    end },
    { "Rename", function() C.RenameCamp(r) end },
    { "Close", function() detail:Hide() end },
  })
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

function C.ShowFarmRow(r)
  if r.camp then return C.ShowCamp(r) end
  if r.farm and r.kind ~= "Pick" then return C.ShowMob(r.npc, r.farm) end
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local rt = r.route or {}
  local lines = {
    (KIND_COLOR[r.kind] or "") .. r.name .. "|r",
    string.format("%s   levels %s%s   %s", r.kind, tostring(rt.lo or r.level or "?"), rt.hi and ("-" .. rt.hi) or "", r.where or ""),
    "Druid: " .. (r.druid or "-"),
  }
  if rt.skill and rt.kind == "Lockpick" then
    lines[#lines + 1] = string.format("Lockpicking %d to %d (you have %d)", rt.skill, rt.skillTo or 300, C.char.lockpicking or 0)
  elseif rt.skill then
    lines[#lines + 1] = string.format("Needs skill %d", rt.skill)
  end
  if rt.note then lines[#lines + 1] = rt.note end
  if r.note and r.note ~= rt.note then lines[#lines + 1] = r.note end
  if r.item then
    local mi = C.MarketItem(r.item)
    lines[#lines + 1] = string.format("%s on the AH: %s (%s listed)", itemName(r.item), mi and C.Money(mi.m) or "not listed", mi and mi.q or 0)
  end
  if r.perHour and r.perHour > 0 then
    lines[#lines + 1] = string.format("Estimate: %s per pick x %d picks/hour = %s/hour (change on the Settings tab)",
      C.Money(r.per or 0), C.settings.picksPerHour or 120, C.Money(r.perHour))
  end
  local P = C.Pockets
  if r.npc and P then
    lines[#lines + 1] = ""
    P.TooltipLines(r.npc, function(l, rr) lines[#lines + 1] = l .. "   " .. (rr or "") end)
  end
  if rt.src then lines[#lines + 1] = "|cff9d9d9dSource: " .. rt.src .. "|r" end
  setLines(lines)
  if r.item then drawGraph(r.item) else detail.graph:Hide() end
  setButtons({
    { "Waypoint (TomTom)", function() rowWaypoint(r) end },
    { "Search AH", function() if r.item then C.SearchAH(r.item) end end },
    { "Close", function() detail:Hide() end },
  })
  if not r.item then detail.buttons[2]:Hide() end
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

------------------------------------------------------------------ crafts controls and recipe details
function C.RefreshCraftBar()
  local bar, st = ui.craftBar, C.settings
  local prof = st.craftProf or "ALL"
  local mine = st.craftMine ~= false
  bar.prof:SetText("Profession: " .. (prof == "ALL" and (mine and "all mine" or "all") or prof) .. "  v")
  bar.mine:SetText(mine and "|cff40ff40[x]|r My professions" or "[  ] My professions")
  bar.show:SetText("Show: " .. SHOW_LABEL[st.craftShow or "all"])
  local parts = {}
  for p, sk in pairs(C.char.prof or {}) do parts[#parts + 1] = p .. " " .. sk end
  table.sort(parts)
  bar.info:SetText(((UnitName and UnitName("player")) or "") .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "no professions yet"))
end

local function learnWaypoint(r)
  if r.trainer then
    local t = C.RecipeTrainer(r.prof, r.l)
    if t then return C.Waypoint(t.map, t.x, t.y, t.name .. " (" .. r.prof .. " trainer)") end
  elseif r.src then
    local v = C.RecipeVendor(r.src)
    if v then return C.Waypoint(v.map, v.x, v.y, (v.name or "Vendor") .. " (" .. itemName(r.src) .. ")") end
  end
  C.Print("no trainer or vendor location known for " .. tostring(r.name) .. ".")
end

function C.RecipeMenu(r)
  local items = {
    { "Recipe details", function() C.ShowRecipe(r) end },
    { "Search AH for " .. itemName(r.out), function() C.SearchAH(r.out) end },
  }
  if r.status ~= "learned" then items[#items + 1] = { "Waypoint: where to learn it", function() learnWaypoint(r) end } end
  if r.src then items[#items + 1] = { "Search AH for the pattern", function() C.SearchAH(r.src) end } end
  items[#items + 1] = { C.IsTracked(r.out) and "Stop tracking result" or "Track result", function() C.ToggleTrack(r.out); C.Refresh() end }
  showMenu(items)
end

function C.ShowRecipe(r)
  if not ui.frame then C.Toggle() end
  if not detail then buildDetail() end
  placeDetail()
  local skill = r.skill or C.MySkill(r.prof)
  local mi = C.MarketItem(r.out)
  local lines = {
    qualityColor(r.out) .. (r.name or itemName(r.out)) .. "|r",
    statusCell(r) .. string.format("   %s: needs %d, you %s", r.prof or "?", r.l or 0, skill and tostring(skill) or "-"),
    (r.y and r.y > 0) and string.format("Skill-ups: |cffff8040orange|r to %d, |cffffff00yellow|r to %d, |cff40c040green|r to %d, then grey", r.y, r.g, r.x) or "",
    string.format("Makes %s x%d: sells %s (listed %s)", itemName(r.out), r.n or 1, r.value and C.Money(r.value) or "-", mi and mi.q or 0),
    string.format("Reagents %s   Profit %s   Vs selling mats %s", r.cost and C.Money(r.cost) or "-", r.profit and C.Money(r.profit) or "-", r.vsMats and C.Money(r.vsMats) or "-"),
  }
  local k = 0
  for mat, q in pairs(r.reagents or {}) do
    k = k + 1
    if k <= 5 then
      local c, where = C.BuyCost(mat)
      lines[#lines + 1] = string.format("   %d x %s  %s%s", q, itemCell(mat), c and C.Money(c) or "?", where and (" (" .. where .. ")") or "")
    end
  end
  if r.trainer then
    local t = C.RecipeTrainer(r.prof, r.l)
    lines[#lines + 1] = "Learn: trainer" .. (t and string.format(" - %s, %s", t.name, t.zone or "?") or "")
  elseif r.src then
    local v = C.RecipeVendor(r.src)
    local pm = C.MarketItem(r.src)
    lines[#lines + 1] = string.format("Learn: %s%s", itemName(r.src), pm and pm.m and (" - AH " .. C.Money(pm.m)) or "")
    if v then lines[#lines + 1] = string.format("   Sold by %s, %s (Classic vendor data)", v.name or "?", v.zone or "?") end
    if pm and pm.m and r.profit and r.profit > 0 then
      lines[#lines + 1] = string.format("   Pays for itself after %d crafts", math.ceil(pm.m / r.profit))
    end
  end
  setLines(lines)
  drawGraph(r.out)
  setButtons({
    { "Search AH: result", function() C.SearchAH(r.out) end },
    { r.status == "learned" and "Track result" or "Waypoint: learn it", function()
      if r.status == "learned" then C.ToggleTrack(r.out); C.Refresh() else learnWaypoint(r) end end },
    { "Search AH: pattern", function() C.SearchAH(r.src) end },
    { "Close", function() detail:Hide() end },
  })
  if not r.src then detail.buttons[3]:Hide() end
  detail:Show(); if C.RaiseKina then C.RaiseKina() else detail:Raise() end
end

------------------------------------------------------------------ auction house dock
-- With the auction house open, the window sits at a fixed offset from the AH's
-- top-right corner (default: 6 px to its right, tops level). Drag it while the
-- AH is open and that new offset is remembered. Uses only positions read from the
-- AH frame; nothing is anchored to (or changed on) Blizzard's frame.
local function ahFrame()
  local ah = rawget(_G, "AuctionHouseFrame")
  if ah and ah.IsShown and ah:IsShown() and ah:GetRight() and ah:GetTop() then return ah end
end

local function ahCorner(f, ah)
  local s = ah:GetEffectiveScale() / f:GetEffectiveScale()
  return ah:GetRight() * s, ah:GetTop() * s
end

function C.DockToAH()
  local f, ah = ui.frame, ahFrame()
  if not (f and ah) or C.settings.dockAH == false then return false end
  local ax, ay = ahCorner(f, ah)
  local d = C.settings.ahDock
  if type(d) ~= "table" then
    d = { dx = 6, dy = 0 }
    -- first time: keep the spot you already dragged it to, if it is beside the AH
    local p = C.settings.pos.main
    if type(p) == "table" and p[1] == "BOTTOMLEFT" and p[2] == "BOTTOMLEFT" then
      local dx, dy = p[3] - ax, (p[4] + H) - ay
      if dx >= -20 and dx <= 80 and math.abs(dy) <= 120 then d = { dx = math.floor(dx + 0.5), dy = math.floor(dy + 0.5) } end
    end
    C.settings.ahDock = d
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ax + d.dx, ay + d.dy)
  return true
end

local function rememberDock(f)
  local ah = ahFrame()
  if not ah then return end
  local ax, ay = ahCorner(f, ah)
  local l, t = f:GetLeft(), f:GetTop()
  if l and t then C.settings.ahDock = { dx = math.floor(l - ax + 0.5), dy = math.floor(t - ay + 0.5) } end
end

------------------------------------------------------------------ scan progress bar
local PHASE_TEXT = { request = "Asking the auction house for a full scan", read = "Reading listings",
  items = "Analyzing items", done = "Market updated", noreply = "No scan allowed yet (15-min limit)",
  stopped = "Scan stopped: auction house closed" }

-- "prices: Vellaura's scan 3m ago (yours 14m)": the newest scan in use, live
function C.ScanSourceText()
  local list = C.Share and C.Share.Sources and C.Share.Sources() or {}
  if not list[1] then return "no scan yet" end
  local function ago(t) local m = math.floor((C.Now() - (t or 0)) / 60); return m < 1 and "just now" or (m < 60 and (m .. "m ago") or (math.floor(m / 60) .. "h ago")) end
  local top = list[1]
  local text = "prices: " .. (top.name and ((Ambiguate and Ambiguate(top.name, "short") or top.name) .. "'s") or "your") .. " scan " .. ago(top.t)
  if top.name then
    for _, s in ipairs(list) do if not s.name then text = text .. " (yours " .. ago(s.t) .. ")"; break end end
  end
  return text
end

local function buildScanBar(f)
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetSize(430, 16); bar:SetPoint("BOTTOMLEFT", 16, 14)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1); bar:SetValue(0)
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
  local function edge(p1, p2, horiz)
    local t = bar:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(0.96, 0.78, 0.30, 0.7)
    t:SetPoint(p1, -1, 1); t:SetPoint(p2, 1, -1)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
  -- a bright block that sweeps back and forth while waiting for the server
  bar.sweep = bar:CreateTexture(nil, "ARTWORK"); bar.sweep:SetSize(60, 14); bar.sweep:SetColorTexture(0.3, 0.76, 0.97, 0.8)
  bar.text = C.Text(bar, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER"); bar.text:SetWidth(422); if bar.text.SetWordWrap then bar.text:SetWordWrap(false) end
  bar:EnableMouse(true)
  bar:SetScript("OnMouseUp", function() if C.ahOpen then C.StartScanLoop() end end)
  bar:SetScript("OnEnter", function(self)
    C.TipOwner(self)
    GameTooltip:AddLine("Auction house scan", 1, 0.82, 0)
    GameTooltip:AddLine("Click to scan. Kina then scans again every 15 minutes (the game's limit) while the auction house stays open. Closing the AH stops it.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local acc = 0
  bar:SetScript("OnUpdate", function(self, el)
    acc = acc + el; if acc < 0.05 then return end; acc = 0
    local sc = C.scan or { phase = "idle" }
    local now = GetTime and GetTime() or 0
    local since = now - (sc.t or now)
    if sc.phase == "request" and since > 45 then C.ScanPhase("noreply"); sc = C.scan end
    if (sc.phase == "done" and since > 12) or ((sc.phase == "noreply" or sc.phase == "stopped") and since > 20) then
      sc.phase = "idle"
    end
    self.sweep:Hide()
    local p = sc.phase
    if p == "request" then
      self:SetStatusBarColor(0.3, 0.76, 0.97); self:SetValue(0)
      local x = (math.sin(since * 2.4) + 1) / 2 * (430 - 62)
      self.sweep:ClearAllPoints(); self.sweep:SetPoint("LEFT", self, "LEFT", 1 + x, 0); self.sweep:Show()
      self.text:SetText(string.format("%s... %ds", PHASE_TEXT.request, since))
    elseif p == "read" or p == "items" then
      local frac = (sc.total or 0) > 0 and math.min(1, (sc.done or 0) / sc.total) or 0
      if p == "read" then self:SetStatusBarColor(0.3, 0.76, 0.97) else self:SetStatusBarColor(0.96, 0.78, 0.30) end
      -- reading is step 1 of 2 (0-70%), analysis step 2 (70-100%)
      self:SetValue(p == "read" and frac * 0.7 or 0.7 + frac * 0.3)
      self.text:SetText(string.format("%s %s / %s  (%d%%)", PHASE_TEXT[p], BreakUpLargeNumbers and BreakUpLargeNumbers(sc.done or 0) or (sc.done or 0),
        BreakUpLargeNumbers and BreakUpLargeNumbers(sc.total or 0) or (sc.total or 0), math.floor((p == "read" and frac * 70 or 70 + frac * 30) + 0.5)))
    elseif p == "done" then
      self:SetStatusBarColor(0.3, 0.85, 0.35); self:SetValue(1)
      self.text:SetText(string.format("%s: %d items, %d listings", PHASE_TEXT.done, sc.items or 0, sc.rows or 0))
    elseif p == "noreply" or p == "stopped" then
      self:SetStatusBarColor(0.85, 0.3, 0.3); self:SetValue(1)
      self.text:SetText(PHASE_TEXT[p] .. (p == "noreply" and " (another addon may have scanned; limit 15 min)" or ""))
    else
      -- idle: the bar fills as the 15-minute limit runs out
      local left = C.ScanCooldown and C.ScanCooldown() or 0
      local ageText = C.ScanSourceText and C.ScanSourceText() or "no scan yet"
      local sync = C.Share and C.Share.SyncStatus and C.Share.SyncStatus() or ""
      if sync ~= "" then ageText = ageText .. "  |  syncing: " .. sync end
      self:SetStatusBarColor(0.45, 0.45, 0.5); self:SetValue(1 - left / 900)
      local loop = C.scanLoop and C.ahOpen
      if left > 0 then
        self.text:SetText(string.format("%s  |  %s %d:%02d", ageText, loop and "auto-scan in" or "scan allowed in", math.floor(left / 60), left % 60))
      elseif C.ahOpen then
        self.text:SetText(ageText .. "  |  " .. (loop and "auto-scan: scanning..." or "click to scan (then every 15 min)"))
      else
        self.text:SetText(ageText .. "  |  open the AH, then click to scan")
      end
    end
  end)
  return bar
end

------------------------------------------------------------------ plan tab
-- Which professions pay for you (and your partner), in gold/hour on your farms.
tabs.Plan = function()
  local best, mine, mate, pf = C.ProfessionPlan()
  local out = {}
  local function add(who, vals, picked)
    local list = {}
    for p, v in pairs(vals) do list[#list + 1] = v end
    table.sort(list, function(a, b) return a.value > b.value end)
    for _, v in ipairs(list) do
      local isPick = picked and (picked[1] == v.prof or picked[2] == v.prof)
      local have = (who.profs or {})[v.prof]
      out[#out + 1] = { cols = { who.name or "?", (isPick and "|cff7CFC00" or "") .. v.prof .. (isPick and "  (pick)|r" or ""),
          C.Money(v.value) .. "/h", have and ("skill " .. have) or "-", v.how or "" },
        sort = { who.name or "", v.prof, v.value, have or 0, v.how or "" },
        tip = v.prof == "Enchanting" and "Disenchanting greens/blues you'd otherwise sell or vendor, plus time saved: gear takes a bag slot each, materials stack, so you go to town less." or nil }
    end
  end
  add(pf.me, mine, best and best.me)
  if mate then add(pf.partner, mate, best and best.partner) end
  local head
  if best and mate then
    head = string.format("|cff7CFC00Best pair:|r you %s + %s, %s %s + %s = ~%s/h each (no profession doubled). Estimates: farm more to sharpen them.",
      best.me[1], best.me[2], pf.partner.name or "partner", best.partner[1], best.partner[2], C.Money(best.value))
  elseif best then
    head = string.format("|cff7CFC00Best for you:|r %s + %s = ~%s/h on your best farms. Add a partner on the Settings tab to plan as a pair.",
      best.me[1], best.me[2], C.Money(best.value))
  else head = "Not enough data yet: scan the AH and farm a little." end
  if not ui.sort.Plan then ui.sort.Plan = { col = 3, desc = true } end
  return head, { "Who", "Profession", "Adds", "Now", "How it was worked out" }, { 0, 110, 260, 350, 420 }, out
end

------------------------------------------------------------------ settings tab
-- Every option that used to need a slash command, as switches, boxes and buttons.
tabs.You = function() return "", {}, {}, {}, { panel = "you" } end

tabs.Settings = function()
  return "Settings: click a switch to flip it, type in a box and press Enter. Everything is saved per account.",
    {}, {}, {}, { settings = true }
end

local function buildSettings(f)
  -- scrolls (mouse wheel or the bar on the right) when the options don't fit
  local sf = CreateFrame("ScrollFrame", "KinaSettingsScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -74); sf:SetPoint("BOTTOMRIGHT", -34, 62); sf:Hide()
  local bg = sf:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03)
  local outer = CreateFrame("Frame", nil, sf); outer:SetSize(ui.w - 50, 800)
  sf:SetScrollChild(outer)
  ui.settingsContent = outer
  local controls = {}
  -- "You" box (read-only): what Kina believes about you, so a wrong profile is obvious
  local YOU_H = C.PUBLIC and 0 or 64 -- 1.2.0: public Kina shows you on the You tab instead
  if not C.PUBLIC then
    local box = CreateFrame("Frame", nil, outer)
    box:SetPoint("TOPLEFT", 4, -4); box:SetPoint("TOPRIGHT", -4, -4); box:SetHeight(YOU_H - 8)
    local t = box:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(0.3, 0.76, 0.97, 0.08)
    local hd = C.Text(box, "OVERLAY", "GameFontNormal"); hd:SetPoint("TOPLEFT", 6, -4); hd:SetText("You (what Kina knows, read-only)")
    local l1 = C.Text(box, "OVERLAY", "GameFontHighlightSmall"); l1:SetPoint("TOPLEFT", 6, -22); l1:SetPoint("RIGHT", box, "RIGHT", -6, 0); l1:SetJustifyH("LEFT")
    local l2 = C.Text(box, "OVERLAY", "GameFontHighlightSmall"); l2:SetPoint("TOPLEFT", 6, -38); l2:SetPoint("RIGHT", box, "RIGHT", -6, 0); l2:SetJustifyH("LEFT")
    if l1.SetWordWrap then l1:SetWordWrap(false); l2:SetWordWrap(false) end
    controls[#controls + 1] = function() local a, b = C.YouLines(); l1:SetText(a); l2:SetText(b) end
  end
  local p = CreateFrame("Frame", nil, outer); p:SetPoint("TOPLEFT", 0, -YOU_H); p:SetPoint("TOPRIGHT", 0, -YOU_H); p:SetHeight(800)
  local maxY = 0
  local COLW, ROWH = 280, 23
  local col, y = 0, 0
  local function at(w)
    return function(region) region:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + col * COLW, -6 - y) end
  end
  local function column(n) maxY = math.max(maxY, y); col, y = n, 0 end
  local function header(text)
    local fs = C.Text(p, "OVERLAY", "GameFontNormal"); at()(fs); fs:SetText(text)
    y = y + ROWH
  end
  local function note(getText)
    local fs = C.Text(p, "OVERLAY", "GameFontDisableSmall"); at()(fs); fs:SetWidth(COLW - 14); fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    controls[#controls + 1] = function() fs:SetText(getText() or "") end
    y = y + 16
  end
  local function toggle(label, get, set, tip)
    local b = button(p, "", COLW - 14, function() set(not get()); C.RefreshSettings(); C.Refresh() end)
    at()(b)
    local fs = b:GetFontString(); if fs then fs:SetJustifyH("LEFT"); fs:ClearAllPoints(); fs:SetPoint("LEFT", 8, 0) end
    if tip then
      b:SetScript("OnEnter", function(self) C.TipOwner(self); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    controls[#controls + 1] = function() b:SetText((get() and "|cff40ff40[x]|r " or "[  ] ") .. label) end
    y = y + ROWH
  end
  local function action(label, fn, w, sameRow)
    local b = button(p, label, w or (COLW - 14), function() fn(); C.RefreshSettings(); C.Refresh() end)
    if sameRow then b:SetPoint("LEFT", sameRow, "RIGHT", 6, 0) else at()(b); y = y + ROWH end
    return b
  end
  -- label + box; get() returns the box text, set(text) applies it
  local function box(label, get, set, w, tip)
    local fs = C.Text(p, "OVERLAY", "GameFontHighlightSmall"); at()(fs); fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(w or 70, 18); eb:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + col * COLW + (COLW - 14) - (w or 70), -6 - y + 2); eb:SetAutoFocus(false)
    local function apply(self) set(self:GetText() or ""); self:ClearFocus(); C.RefreshSettings(); C.Refresh() end
    eb:SetScript("OnEnterPressed", apply)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); C.RefreshSettings() end)
    eb:SetScript("OnEditFocusLost", function(self) if self.dirty then self.dirty = false; apply(self) end end)
    eb:SetScript("OnTextChanged", function(self, user) if user then self.dirty = true end end)
    if tip then
      eb:SetScript("OnEnter", function(self) C.TipOwner(self); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
      eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    controls[#controls + 1] = function() if not eb:HasFocus() then eb:SetText(get() or "") end end
    y = y + ROWH
    return eb
  end
  local st = C.settings
  local function money(v) return v and C.Money(v):gsub(" ", "") or "" end
  local function num(t, lo, hi) local n = tonumber(t); if n then return math.max(lo or -math.huge, math.min(hi or math.huge, n)) end end

  if C.PUBLIC then
  column(0)
  header("Kina level")
  for i = 1, 4 do note(function() return (C.RepDetail and C.RepDetail() or {})[i] or "" end) end
  y = y + 4
  header("Data sharing")
  toggle("Share drop data and auction prices", function() return C.ShareData() end, function(v) C.SetShareData(v) end,
    "Kina collects which mobs drop what and the auction prices you see, and shares them with other Kina users. You don't see this data yet: it builds the farm and price features of a future Kina. Your Kina level only grows while this is on. Nothing about you, your chat or other players is collected.")
  note(function() return C.ShareData() and "on: your Kina level can grow" or "|cffff8040off: your Kina level is paused|r" end)
  toggle("Also share with my guild", function() return C.Share.DB().opts.guild end, function(v) C.Share.DB().opts.guild = v end,
    "Guild members who run Kina also see your Kina level and get your shared data.")
  y = y + 4
  header("Check Kina")
  action("Run self-test", function() if C.SelfTest then C.SelfTest.Run() end end)
  note(function() return "checks Kina works on this client (results in chat)" end)
  else
  -------------------------------------------------- column 1: auction house and money
  column(0)
  header("Auction house")
  toggle("Open Kina with the auction house", function() return st.autoOpen ~= false end, function(v) st.autoOpen = v end)
  toggle("Keep scanning every 15 min after I click Scan", function() return st.autoScan ~= false end, function(v) st.autoScan = v; if not v then C.scanLoop = false end end,
    "One full scan per 15 minutes is the game's limit. Kina also reads scans ForeverForge starts.")
  toggle("Prices on item tooltips", function() return st.tooltip ~= false end, function(v) st.tooltip = v end)
  action("Scan the AH now", function() C.StartScanLoop() end)
  local durB = action("", function() st.postDuration = ((st.postDuration or 1) % 3) + 1 end)
  controls[#controls + 1] = function()
    local hrs = ({ 2, 8, 24 })[st.postDuration or 1]
    durB:SetText("I post auctions for: " .. hrs .. " hours")
  end
  box("Investments: days of history", function() return tostring(st.investDays or 7) end,
    function(t) local n = num(t, 1, 60); if n then st.investDays = n end end, 40,
    "An item shows on the Invest tab only after Kina has seen it on this many days (and seen it sell).")
  box("Investments: scans of history", function() return tostring(st.investScans or 10) end,
    function(t) local n = num(t, 2, 200); if n then st.investScans = n end end, 40)
  box("Confidence I need (%)", function() return tostring(st.minConfidence or 75) end,
    function(t) local n = num(t, 5, 99); if n then st.minConfidence = n end end, 40,
    "Kina lowers the number it tells you to buy until buying that many reaches this confidence of selling them all at a profit.")
  box("Most days I'll wait for sales", function() return tostring(st.maxWaitDays or 3) end,
    function(t) local n = num(t, 0.5, 30); if n then st.maxWaitDays = n end end, 40,
    "Confidence = the chance a deal's units all sell within this many days (sooner if deposits or a falling price would eat the profit first).")
  note(function()
    local r, src = C.Econ.DepositRatio()
    return string.format("deposit = %.1f%% of vendor price (%s); no vendor price = 0%%", r * 100, src)
  end)
  y = y + 4
  header("Deals and profit")
  box("Min ROI % (every tab)", function() return tostring(st.minROI or 0) end,
    function(t) st.minROI = num(t, 0) or 0; if _G.KinaMinROI then _G.KinaMinROI:SetText(tostring(st.minROI)) end end, 50)
  toggle("Hide trades not worth my time", function() return st.worthOnly end, function(v) st.worthOnly = v end)
  box("Min profit per trade", function() return st.minProfit and money(st.minProfit) or "" end,
    function(t) if t == "" or t:lower() == "auto" then st.minProfit = nil else st.minProfit = C.ParseMoney(t) or (t == "0" and 0) or st.minProfit end end, 70,
    "Leave empty for automatic: what 2 minutes of your farming gold/hour is worth.")
  note(function() return "now " .. C.Money(C.Econ.Overhead()) .. (st.minProfit and " (yours)" or " (automatic)") end)
  box("Friend's Enchanting skill", function() return st.deFriend and tostring(st.deFriend) or "" end,
    function(t) st.deFriend = num(t, 1, 300) end, 50,
    "Someone who disenchants for you. Leave empty if nobody does: disenchanting then only counts when you or an alt can do it.")
  toggle("Count enchanters who share with me", function() return st.shareEnchanters ~= false end, function(v) st.shareEnchanters = v end,
    "Kina users who shared their data with you in the last 3 days count as your disenchanter, even when you're not grouped right now.")
  note(function() local who = C.DisenchanterText and C.DisenchanterText(); return who and ("disenchanter: " .. who) or "no disenchanter: disenchant deals hidden" end)
  toggle("Disenchant values from my own results", function() return st.deMine end, function(v) st.deMine = v end,
    "Off: the disenchant table (e.g. 75% Soul Dust, 20% Greater Astral Essence, 5% Large Glimmering Shard). On: your own average replaces it once you have 100+ disenchants in that band. The tooltip shows your results either way.")
  toggle("Price materials at the cheapest listing", function() return st.matLowest end, function(v) st.matLowest = v end,
    "Like ForeverForge: dust, essences and shards at today's cheapest listing. Off (cautious): the price of the 20 cheapest or the week's median, whichever is lower.")

  end
  -------------------------------------------------- column 2: farming, windows, stockpile
  column(1)
  header("Farming")
  toggle("Show the farm widget", function() return st.hudShown ~= false end, function(v) C.ShowWidget(v) end)
  toggle("Show the minimap button", function() return not st.minimapHide end, function(v) C.ShowMinimapButton(v) end)
  if not C.PUBLIC then
  toggle("HOT alerts in chat after a scan", function() return st.hotAlerts ~= false end, function(v) st.hotAlerts = v end,
    "A chat line when a craft spikes to 2x+ its week price and is worth 1g+/hour, or something you own spiked.")
  end
  toggle("Count kills from nameplates", function() return st.plateKills ~= false end, function(v) st.plateKills = v end,
    "Counts mobs that died near you without being your target (AoE, pets) so drop rates are not too good. In a group they count for the farm only. Needs the dead mob's nameplate to be visible.")
  toggle("Kina iron look (after /reload)", function() return st.look ~= "classic" end, function(v) st.look = (not v) and "classic" or nil
    C.Print("the " .. (v and "iron" or "classic") .. " look applies after a /reload.") end,
    "The forged iron frames, buttons and tiles. Off: Kina's plain classic look.")
  toggle("Split the loot in group farms", function() return st.farmNoSplit ~= true end, function(v) st.farmNoSplit = not v; if C.RefreshWidget then C.RefreshWidget() end end,
    "Off: group farms you start still share their numbers, but nobody owes anyone (for questing apart while grouped). The person who presses Start decides.")
  toggle("Start/stop fanfares", function() return st.farmSound ~= false end, function(v) st.farmSound = v; if C.RefreshWidget then C.RefreshWidget() end end)
  box("Farm timer (hours, 0 = none)", function() return tostring((st.farmPreset or 0) / 3600) end,
    function(t) local h = num(t, 0, 24); if h then st.farmPreset = math.floor(h * 3600) end; if C.RefreshWidget then C.RefreshWidget() end end, 50)
  if not C.PUBLIC then
  box("Kills per hour (default)", function() return tostring(st.killsPerHour or 60) end,
    function(t) local n = num(t, 1, 1000); if n then st.killsPerHour = n end end, 50)
  box("Picks per hour (pick-only)", function() return tostring(st.picksPerHour or 120) end,
    function(t) local n = num(t, 1, 2000); if n then st.picksPerHour = n end end, 50)
  box("Free bag slots", function() return tostring(st.bagSlots or 70) end,
    function(t) local n = num(t, 10, 200); if n then st.bagSlots = n end end, 40, "Used to work out how often a farm sends you to town.")
  box("Minutes per town trip", function() return tostring(st.tripMinutes or 8) end,
    function(t) local n = num(t, 1, 60); if n then st.tripMinutes = n end end, 40)
  toggle("Count skinning even if I don't have it", function() return st.assumeSkinning end, function(v) st.assumeSkinning = v end,
    "Shows what beast farms would pay if you (or your partner) skinned them.")
  end
  action("Start / stop a farm", function() if C.session then C.StopSession() else C.StartSession() end end)
  y = y + 4
  if not C.PUBLIC then
  header("Stockpile target")
  local stockItem = box("Item (shift-click it)", function() return "" end, function() end, 150)
  ui.stockItemBox = stockItem
  local stockBuy = box("Alert when listed under", function() return "" end, function() end, 70)
  local stockSell = box("Hold until it sells at", function() return "" end, function() end, 70)
  local function stockID() local t = stockItem:GetText() or ""; return C.ItemIDFromLink(t) or tonumber(t:match("^%s*(%d+)")) end
  local saveB = action("Save target", function()
    local id = stockID()
    if not id then C.Print("put an item in the Item box first (shift-click it from your bags)."); return end
    C.db.stock[id] = { buyUnder = C.ParseMoney(stockBuy:GetText()), sellAt = C.ParseMoney(stockSell:GetText()), note = "", added = C.Now() }
    if C.db.stockRemoved then C.db.stockRemoved[id] = nil end
    C.Print("stockpile target saved for " .. ((C.Item(id) or {}).name or id) .. ".")
    stockItem:SetText(""); stockBuy:SetText(""); stockSell:SetText("")
  end, 132)
  y = y - ROWH
  action("Remove", function()
    local id = stockID(); if not id then return end
    C.db.stock[id] = nil; C.db.stockRemoved = C.db.stockRemoved or {}; C.db.stockRemoved[id] = true
    C.Print("stopped tracking " .. ((C.Item(id) or {}).name or id) .. ".")
  end, 132, saveB)
  y = y + ROWH + 4
  end
  header("Window")
  -- Text size: drag and Kina's text resizes as you go (70% to 150%)
  do
    local lbl = C.Text(p, "OVERLAY", "GameFontHighlightSmall"); at()(lbl)
    local sl = CreateFrame("Slider", "KinaTextScaleSlider", p)
    sl:SetOrientation("HORIZONTAL"); sl:SetSize(150, 16)
    sl:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + col * COLW + (COLW - 14) - 150, -6 - y + 1)
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 4, 0); track:SetPoint("RIGHT", -4, 0); track:SetHeight(6); track:SetColorTexture(1, 1, 1, 0.18)
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    sl:SetMinMaxValues(0.7, 1.5); sl:SetValueStep(0.05)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl:EnableMouseWheel(true)
    local function show(v) lbl:SetText(string.format("Text size: %d%%", math.floor(v * 100 + 0.5))) end
    sl:SetValue(C.TextScale()); show(C.TextScale())
    sl:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v * 20 + 0.5) / 20
      show(v)
      if math.abs(v - C.TextScale()) > 0.001 then C.ApplyTextScale(v) end
    end)
    sl:SetScript("OnMouseWheel", function(self, d) self:SetValue(math.max(0.7, math.min(1.5, self:GetValue() + d * 0.05))) end)
    sl:SetScript("OnEnter", function(self) C.TipOwner(self)
      GameTooltip:AddLine("Size of Kina's text in the main window (tables, headers, settings). Drag, or scroll the mouse wheel over it. The details panel and farm widget have their own size grip in the corner.", 1, 1, 1, true)
      GameTooltip:Show() end)
    sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y + ROWH
    action("Text size: back to 100%", function() sl:SetValue(1); C.ApplyTextScale(1) end)
  end
  action("Put every Kina window back", function() C.ResetWindows() end)
  toggle("Debug messages", function() return C.debug end, function(v) C.debug = v end)

  if not C.PUBLIC then
  -------------------------------------------------- column 3: partner, sharing and pickpocketing
  column(2)
  header("Farming partner")
  local CLASSES = { "NONE", "DRUID", "HUNTER", "PRIEST", "PALADIN", "SHAMAN", "WARRIOR", "MAGE", "WARLOCK", "ROGUE" }
  local function nice(c) return c == "NONE" and "none" or (c:sub(1, 1) .. c:sub(2):lower()) end
  local function after() C.RefreshSettings(); C.Refresh() end
  -- class: drop-down
  local pcls = action("", function()
    local items = {}
    for _, c in ipairs(CLASSES) do items[#items + 1] = { nice(c), function() st.partnerClass = c; after() end } end
    showMenu(items)
  end)
  controls[#controls + 1] = function()
    local live = C.Partner and C.Partner()
    if live and live.live then
      local ps = {}
      for p, sk in pairs(live.profs or {}) do ps[#ps + 1] = p .. " " .. sk end
      table.sort(ps)
      pcls:SetText("|cff7CFC00Synced:|r " .. live.name .. " " .. (live.class and (live.class:sub(1, 1) .. live.class:sub(2):lower()) or "") .. " " .. (live.level or "")
        .. (#ps > 0 and (", " .. table.concat(ps, ", ")) or ""))
      pcls:Disable()
    else pcls:Enable(); pcls:SetText("Partner class: " .. nice(st.partnerClass or "NONE") .. "  v") end
  end
  box("Partner level", function() return st.partnerLevel and tostring(st.partnerLevel) or "" end,
    function(t) st.partnerLevel = num(t, 1, 63) end, 40)
  -- two professions: drop-down + skill box each (saved as "Enchanting 50, Alchemy 25")
  local PROFS = { "None", "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring" }
  local function slots()
    if not st.partnerSlots then
      st.partnerSlots = {}
      local parsed = {}
      for name, sk in pairs(C.ParseProfs(st.partnerProfs or "")) do parsed[#parsed + 1] = { name, sk } end
      table.sort(parsed, function(a, b) return a[1] < b[1] end)
      for i = 1, 2 do st.partnerSlots[i] = parsed[i] or { "None", 1 } end
    end
    return st.partnerSlots
  end
  local function save()
    local parts = {}
    for _, sl in ipairs(slots()) do if sl[1] ~= "None" then parts[#parts + 1] = sl[1] .. " " .. (sl[2] or 1) end end
    st.partnerProfs = table.concat(parts, ", ")
  end
  for i = 1, 2 do
    local pb = action("", function()
      local items = {}
      for _, name in ipairs(PROFS) do items[#items + 1] = { name, function() slots()[i][1] = name; save(); after() end } end
      showMenu(items)
    end, COLW - 72)
    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(40, 18); eb:SetPoint("LEFT", pb, "RIGHT", 10, 0); eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(3)
    local function apply(self) slots()[i][2] = math.max(1, math.min(300, tonumber(self:GetText()) or 1)); save(); self:ClearFocus(); after() end
    eb:SetScript("OnEnterPressed", apply)
    eb:SetScript("OnEditFocusLost", function(self) if self.dirty then self.dirty = false; apply(self) end end)
    eb:SetScript("OnTextChanged", function(self, user) if user then self.dirty = true end end)
    eb:SetScript("OnEnter", function(self) C.TipOwner(self); GameTooltip:AddLine("Skill level in this profession (1-300).", 1, 1, 1, true); GameTooltip:Show() end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- synced from the partner's own Kina: the typed values aren't used, so lock them
    controls[#controls + 1] = function()
      local lv = C.Partner and C.Partner()
      if lv and lv.live then pb:Disable(); eb:Disable() else pb:Enable(); eb:Enable() end
    end
    controls[#controls + 1] = function()
      local sl = slots()[i]
      pb:SetText("Profession " .. i .. ": " .. sl[1] .. "  v")
      if not eb:HasFocus() then eb:SetText(sl[1] == "None" and "" or tostring(sl[2] or 1)) end
    end
  end
  note(function() return "type the skill in the box; filled in while grouped with a Kina user" end)
  y = y + 4
  local S = C.Share
  header("Share data with other Kina users")
  toggle("Share with my party / raid", function() return S.DB().opts.enabled end, function(v) S.DB().opts.enabled = v; S.InvalidateMarket() end,
    "Pools AH scans, mob loot, vendor and merchant prices with group members who run Kina.")
  toggle("Also share with my guild", function() return S.DB().opts.guild end, function(v) S.DB().opts.guild = v end)
  toggle("Say in chat when data arrives", function() return S.DB().opts.verbose end, function(v) S.DB().opts.verbose = v end)
  action("Sync with my group now", function()
    if C.ResetSyncAsks then C.ResetSyncAsks() end
    S.Announce(true)
    C.Print("sync: hello sent to your group. Kina users in it will offer to sync, and data starts flowing (progress shows on the scan bar).")
  end)
  note(function() local s = S.SyncStatus and S.SyncStatus() or ""; return s ~= "" and ("syncing: " .. s) or "nothing syncing right now" end)
  local syncB = action("Sync now", function() S.Command("now") end, 132)
  action("Forget shared data", function() S.DB().authors = {}; S.InvalidateMarket(); C.Print("share: forgot data from other players.") end, 132, syncB)
  note(function()
    local a, scans, mobs = 0, 0, 0
    for _, x in pairs(S.DB().authors) do
      a = a + 1
      if x.market and C.Now() - (x.market.t or 0) < 3 * 86400 then scans = scans + 1 end
      for _ in pairs(x.loot and x.loot.npcs or {}) do mobs = mobs + 1 end
    end
    return string.format("%d players, %d current scans, %d mob records", a, scans, mobs)
  end)
  y = y + 4
  header("Pickpocketing (rogues)")
  local P = C.Pockets
  local function o() return P and P.DB and P.DB().opts or {} end
  local function relayout() if P and P.Relayout then P.Relayout() end; if P and P.RefreshPins then pcall(P.RefreshPins) end end
  toggle("Pockets on this character", function() return P and P.Active and P.Active() end,
    function(v) C.char.pockets = v; if P and P.Start then P.Start() end end)
  toggle("Badges on mobs", function() return o().badges end, function(v) o().badges = v; relayout() end)
  toggle("On nameplates", function() return o().plates end, function(v) o().plates = v; relayout() end)
  toggle("On my target", function() return o().target end, function(v) o().target = v; relayout() end)
  toggle("Pocket loot in mob tooltips", function() return o().tooltip end, function(v) o().tooltip = v; relayout() end)
  toggle("Map pins", function() return o().pins end, function(v) o().pins = v; relayout() end)
  local modeB = action("", function()
    local nxt = { icon = "text", text = "both", both = "icon" }
    o().mode = nxt[o().mode or "both"] or "both"; relayout()
  end)
  controls[#controls + 1] = function() modeB:SetText("Badge style: " .. (o().mode or "both")) end
  toggle("Share pocket data", function() return o().shareLoot end, function(v) o().shareLoot = v end)
  local ppSync = action("Sync pockets", function() if P and P.SyncNow then P.SyncNow() end end, 132)
  action("New haul session", function() if P and P.HaulReset then P.HaulReset(); C.Print("new pocket haul session.") end end, 132, ppSync)

  end
  maxY = math.max(maxY, y)
  p:SetHeight(maxY + 20); outer:SetHeight(maxY + 20 + YOU_H)
  ui.settingsPanel = sf
  function C.RefreshSettings() for _, fn in ipairs(controls) do pcall(fn) end end
  -- shift-click an item while the Item box has focus puts its link there
  if hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if ui.stockItemBox and ui.stockItemBox:HasFocus() and link then ui.stockItemBox:SetText(link) end
    end)
  end
end

------------------------------------------------------------------ main window
local function build()
  local f = CreateFrame("Frame", "KinaFrame", UIParent, "BasicFrameTemplateWithInset")
  -- 1.1.1 iron look: remove the template's own art first, before Kina adds its parts
  if C.Skin and C.Skin.On() then C.Skin.StripTemplate(f) end
  -- never bigger than the screen (a saved size from a broken drag is shrunk back)
  local screenW, screenH = (UIParent:GetWidth() or 1900) - 20, (UIParent:GetHeight() or 1200) - 20
  local MINW, MINH = 780, 420
  local saved = C.settings.pos.mainSize
  if type(saved) == "table" and saved[1] then
    ui.w = math.max(MINW, math.min(screenW, saved[1])); ui.h = math.max(MINH, math.min(screenH, saved[2]))
  end
  f:SetSize(ui.w, ui.h); C.RestorePos(f, "main", "LEFT", UIParent, "LEFT", 40, 40)
  -- drag the bottom-right corner to resize; columns stretch, more rows show. The
  -- top-left corner stays pinned and the window stops at the screen's edge.
  local grip = CreateFrame("Button", nil, f)
  grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetFrameLevel(f:GetFrameLevel() + 20)
  C.StyleGrip(grip, "Drag to resize the window (more rows and wider columns).")
  grip:SetScript("OnMouseDown", function(self)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return end
    local eff = f:GetEffectiveScale()
    self.l, self.t, self.w0, self.h0 = l, t, f:GetWidth(), f:GetHeight()
    local cx, cy = GetCursorPosition()
    self.cx, self.cy, self.eff = cx, cy, eff
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    self:SetScript("OnUpdate", function(g)
      local x, y = GetCursorPosition()
      local maxW = math.max(MINW, (UIParent:GetRight() or screenW) - g.l - 4)
      local maxH = math.max(MINH, g.t - 4)
      local w = math.max(MINW, math.min(maxW, g.w0 + (x - g.cx) / g.eff))
      local h = math.max(MINH, math.min(maxH, g.h0 + (g.cy - y) / g.eff))
      if math.abs(w - f:GetWidth()) >= 1 or math.abs(h - f:GetHeight()) >= 1 then f:SetSize(w, h) end
    end)
  end)
  local function stop(self)
    if not self:GetScript("OnUpdate") then return end
    self:SetScript("OnUpdate", nil)
    C.settings.pos.mainSize = { math.floor(ui.w + 0.5), math.floor(ui.h + 0.5) }
    C.SavePos(f, "main")
  end
  grip:SetScript("OnMouseUp", stop)
  grip:SetScript("OnHide", stop)
  f:SetScript("OnSizeChanged", function(_, w, h)
    ui.w, ui.h = w, h
    fitWidths()
    if f:IsShown() then C.Refresh() end
  end)
  C.MakeDraggable(f, "main", titleStrip(f), rememberDock)
  f:SetFrameStrata("DIALOG")
  -- 1.1.0 iron look: the template's art hidden, the A-30 frame (24 px, Rev 59), the A-33 header
  if C.Skin and C.Skin.On() then
    -- 1.1.1: the template's art is all removed (it showed as grey stone and an extra
    -- bar over the title); the title sits on the frame's top band, above everything
    local fr = C.Skin.Frame(f, 24)
    local holder = fr and fr.parent
    if holder then
      local title = C.Text(holder, "OVERLAY", "GameFontNormal")
      title:SetPoint("TOP", f, "TOP", 0, 9); title:SetText("Kina " .. C.version)
      if title.SetShadowOffset then title:SetShadowOffset(1, -1) end
      ui.ironTitle = title
    end
    -- the shelf the tabs stand on (A-36), so they don't float
    local shelf = C.Skin.Strip(f, "row", 8)
    if shelf then shelf:SetPoint("TOPLEFT", 8, -51); shelf:SetPoint("TOPRIGHT", -8, -51) end
    if f.CloseButton then f.CloseButton:ClearAllPoints(); f.CloseButton:SetPoint("TOPRIGHT", 2, 6); f.CloseButton:SetFrameLevel(f:GetFrameLevel() + 40) end
  end
  if f.TitleText and not ui.ironTitle then f.TitleText:SetText("Kina " .. C.version) end
  if UISpecialFrames then table.insert(UISpecialFrames, "KinaFrame") end
  ui.frame = f
  ui.tabButtons = {}
  local x = 10
  for _, name in ipairs(tabOrder) do
    local b = button(f, name, 54, function() ui.tab = name; ui.offset = 0; C.Refresh() end)
    b:SetPoint("TOPLEFT", x, -28); x = x + 56
    if C.Skin and C.Skin.On() then
      -- iron tabs instead of buttons: wider, so the name sits inside the 9 px border
      if b.kinaSkin then b.kinaSkin:Show(false); b.kinaSkin.Layout = function() end end
      b:SetSize(70, 24); x = x + 18
      C.Skin.Tab(b)
    end
    ui.tabButtons[name] = b
  end
  -- search box (filters the current tab)
  local sb = CreateFrame("EditBox", "KinaSearch", f, "InputBoxTemplate")
  sb:SetSize(130, 20); sb:SetPoint("TOPRIGHT", -16, -30); sb:SetAutoFocus(false)
  sb:SetScript("OnTextChanged", function(self) ui.search[ui.tab or "Hot"] = self:GetText(); ui.offset = 0; C.Refresh() end)
  sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local sl = C.Text(f, "OVERLAY", "GameFontDisableSmall"); sl:SetPoint("RIGHT", sb, "LEFT", -6, 0); sl:SetText("Search")
  ui.searchBox = sb
  -- bottom bar
  local scan = button(f, "Scan AH", 80, function() C.StartScanLoop() end); scan:SetPoint("BOTTOMRIGHT", -32, 10)
  local kindB = button(f, "World/Dungeon", 110, function()
    ui.farmKind = (ui.farmKind == "dungeon") and "world" or "dungeon"; ui.tab = "Farms"; C.Refresh() end)
  kindB:SetPoint("RIGHT", scan, "LEFT", -6, 0)
  local nextB = button(f, ">", 26, function() shiftFarmHi(1); ui.tab = "Farms"; C.Refresh() end)
  nextB:SetPoint("RIGHT", kindB, "LEFT", -6, 0)
  local prevB = button(f, "<", 26, function() shiftFarmHi(-1); ui.tab = "Farms"; C.Refresh() end)
  prevB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
  local sess = button(f, "Start/Stop farm", 130, function() if C.session then C.StopSession() else C.StartSession() end; C.Refresh() end)
  sess:SetPoint("RIGHT", prevB, "LEFT", -6, 0)
  local days = button(f, "Ledger: all time", 120, function(self)
    ui.ledgerDays = (ui.ledgerDays == nil) and 7 or (ui.ledgerDays == 7 and 30 or nil)
    self:SetText(ui.ledgerDays and ("Ledger: " .. ui.ledgerDays .. " days") or "Ledger: all time"); ui.tab = "Ledger"; C.Refresh() end)
  days:SetPoint("RIGHT", sess, "LEFT", -6, 0)
  days:Hide() -- Private Kina: no Ledger tab
  ui.ledgerDaysButton = days
  ui.scanBar = buildScanBar(f)
  -- Public Kina: no scan button, scan bar or farm-advice buttons (those tabs are hidden);
  -- prices from auction scans other addons make are still read in the background
  if C.PUBLIC then
    -- 1.1.0: the Scan AH button and the scan bar are back (who scanned, when, what it's doing)
    for _, b in ipairs({ kindB, nextB, prevB }) do b:Hide() end
    sess:ClearAllPoints(); sess:SetPoint("RIGHT", scan, "LEFT", -6, 0)
  end
  buildSettings(f)
  -- ROI filter row (every tab): rows below the typed ROI %, and with the switch on,
  -- rows that don't pay for your time, are hidden. They are still calculated.
  local rb = CreateFrame("Frame", nil, f); rb:SetSize(W - 28, 22); rb:SetPoint("BOTTOMLEFT", 14, 36)
  local rl = C.Text(rb, "OVERLAY", "GameFontHighlightSmall"); rl:SetPoint("LEFT", 2, 0); rl:SetText("Min ROI %"); rb.roiLabel = rl
  local roi = CreateFrame("EditBox", "KinaMinROI", rb, "InputBoxTemplate")
  roi:SetSize(44, 18); roi:SetPoint("LEFT", rl, "RIGHT", 8, 0); roi:SetAutoFocus(false); roi:SetNumeric(true); roi:SetMaxLetters(5)
  roi:SetText(tostring(C.settings.minROI or 0)); rb.roiBox = roi
  local function applyROI(self)
    C.settings.minROI = tonumber(self:GetText()) or 0; self:ClearFocus(); ui.offset = 0; C.Refresh()
  end
  roi:SetScript("OnEnterPressed", applyROI)
  roi:SetScript("OnEditFocusLost", applyROI)
  roi:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  roi:SetScript("OnTextChanged", function(self, user) if user then C.settings.minROI = tonumber(self:GetText()) or 0; ui.offset = 0; C.Refresh() end end)
  rb.worth = button(rb, "", 190, function()
    C.settings.worthOnly = not C.settings.worthOnly; ui.offset = 0; C.Refresh() end)
  rb.worth:SetPoint("LEFT", roi, "RIGHT", 10, 0)
  rb.best = button(rb, "Sort: best deal", 110, function()
    local t = ui.tab or "Hot"
    ui.sort[t] = (t == "Deals") and { col = 11, desc = true, auto = true } or ((t == "Invest") and { col = 11, desc = true, auto = true } or nil)
    ui.offset = 0
    C.Print("sorted by best deal: profit after the chance of losing money" .. (t == "Invest" and ", confidence and time to sell" or "") .. ". Click a column title to sort by that instead.")
    C.Refresh() end)
  rb.view = button(rb, "", 150, function()
    ui.dealView = (ui.dealView == "passive") and "best" or "passive"; ui.sort.Deals = nil; ui.offset = 0; C.Refresh() end)
  rb.view:SetPoint("LEFT", rb.best, "RIGHT", 6, 0)
  rb.afford = button(rb, "", 170, function()
    C.settings.dealAfford = not C.settings.dealAfford; ui.offset = 0; C.Refresh() end)
  rb.afford:SetPoint("LEFT", rb.view, "RIGHT", 6, 0)
  rb.hotType = button(rb, "Show: All", 170, function() C.HotTypeNext(); ui.offset = 0; C.Refresh() end)
  rb.hotOpt = button(rb, "Options", 80, function() C.ShowHotOptions() end)
  btnTip(rb.hotOpt, "Hot options", "Choose which kinds of money-making Hot shows. Switch off a profession or a kind of deal you never want to see.")
  btnTip(rb.worth, "Hide not worth my time", "Hides trades whose profit is too small to be worth the time it takes (buying, posting, waiting). They're still calculated, just not shown.")
  btnTip(roi, "Min ROI %", "Return on what you spend. Type 40 to hide anything that returns less than 40% (spend 1g, get back less than 1g 40s). 0 shows everything.")
  rb.hotType:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Click to show one kind of money at a time: crafts, buy & vendor, buy & disenchant, or selling what you own.", 1, 1, 1, true)
    GameTooltip:Show() end)
  rb.hotType:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rb.quick = button(rb, "Quick scan", 190, function() if C.Quick then C.Quick.Click() end; C.Refresh() end)
  rb.quick:SetPoint("LEFT", rb.afford, "RIGHT", 6, 0)
  rb.quick:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Fresh cheapest price of every item on the AH in seconds (no 15-minute wait), and what's listed under vendor price right now. "
      .. "The full scan still runs for price ladders and history.", 1, 1, 1, true); GameTooltip:Show() end)
  rb.quick:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rb.held = button(rb, "Fix held items", 130, function() if C.LedgerFixHeld then C.LedgerFixHeld() end end)
  rb.held:SetPoint("LEFT", rb.worth, "RIGHT", 6, 0)
  rb.held:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Ledger says you still hold items you've already sold to a vendor? This lists the ones you no longer have (bags, bank, AH) and asks before marking them sold at vendor price.", 1, 1, 1, true); GameTooltip:Show() end)
  rb.held:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rb.best:SetPoint("LEFT", rb.worth, "RIGHT", 6, 0)
  rb.info = C.Text(rb, "OVERLAY", "GameFontDisableSmall")
  rb.info:SetPoint("LEFT", rb.best, "RIGHT", 342, 0); rb.info:SetWidth(math.max(120, W - 806)); rb.info:SetJustifyH("LEFT")
  ui.roiBar = rb
  -- Crafts tab controls: profession dropdown, "my professions" toggle, learned filter
  local bar = CreateFrame("Frame", nil, f); bar:SetSize(W - 28, 22); bar:SetPoint("TOPLEFT", 12, -52); bar:Hide()
  bar.prof = button(bar, "Profession: All", 200, function(self)
    local mine = C.settings.craftMine ~= false
    local items = { { mine and "All my professions" or "All professions", function() C.settings.craftProf = "ALL"; C.Refresh() end } }
    for _, p in ipairs(C.RecipeProfessions(false)) do
      local label = p[2] and string.format("|cff40ff40%s|r (%d)", p[1], p[2]) or p[1]
      items[#items + 1] = { label, function() C.settings.craftProf = p[1]; C.Refresh() end }
    end
    showMenu(items)
  end)
  bar.prof:SetPoint("LEFT", 0, 0)
  bar.mine = button(bar, "", 150, function()
    C.settings.craftMine = (C.settings.craftMine == false); C.Refresh() end)
  bar.mine:SetPoint("LEFT", bar.prof, "RIGHT", 6, 0)
  bar.show = button(bar, "", 150, function()
    local nxt = { all = "learned", learned = "unlearned", unlearned = "all" }
    C.settings.craftShow = nxt[C.settings.craftShow or "all"]; C.Refresh() end)
  bar.show:SetPoint("LEFT", bar.mine, "RIGHT", 6, 0)
  bar.info = C.Text(bar, "OVERLAY", "GameFontDisableSmall")
  bar.info:SetPoint("LEFT", bar.show, "RIGHT", 10, 0); bar.info:SetWidth(W - 560); bar.info:SetJustifyH("LEFT")
  if bar.info.SetWordWrap then bar.info:SetWordWrap(false) end
  ui.craftBar = bar
  -- Farms tab controls: world/dungeon, level band, class farms (per character), filter
  local fb = CreateFrame("Frame", nil, f); fb:SetSize(W - 28, 22); fb:SetPoint("TOPLEFT", 12, -52); fb:Hide()
  fb.kind = button(fb, "", 120, function() ui.farmKind = (ui.farmKind == "dungeon") and "world" or "dungeon"; C.Refresh() end)
  fb.kind:SetPoint("LEFT", 0, 0)
  -- level range: type From and To (Enter or click away to apply)
  local lvlLabel = C.Text(fb, "OVERLAY", "GameFontHighlightSmall")
  lvlLabel:SetPoint("LEFT", fb.kind, "RIGHT", 8, 0); lvlLabel:SetText("Levels")
  local function levelBox(key, anchor, dx)
    local eb = CreateFrame("EditBox", nil, fb, "InputBoxTemplate")
    eb:SetSize(28, 18); eb:SetPoint("LEFT", anchor, "RIGHT", dx, 0); eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(2)
    local function apply(self)
      local v = tonumber(self:GetText())
      if v then C.settings[key] = math.max(1, math.min(60, v)) else C.settings[key] = nil end
      self:ClearFocus(); C.Refresh()
    end
    eb:SetScript("OnEnterPressed", apply)
    eb:SetScript("OnEditFocusLost", function(self) local v = tonumber(self:GetText()); if v ~= C.settings[key] then apply(self) end end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
  end
  fb.lo = levelBox("farmLo", lvlLabel, 8)
  local dash = C.Text(fb, "OVERLAY", "GameFontHighlightSmall"); dash:SetPoint("LEFT", fb.lo, "RIGHT", 2, 0); dash:SetText("to")
  fb.hi = levelBox("farmHi", dash, 8)
  fb.nxt = fb.hi
  fb.cls = button(fb, "", 150, function()
    local _, cls = C.ClassMode()
    if cls ~= "ROGUE" and cls ~= "DRUID" then C.Print("class farms are for rogues and druids."); return end
    C.char.classFarms = (C.char.classFarms == false); C.Refresh() end)
  fb.cls:SetPoint("LEFT", fb.nxt, "RIGHT", 10, 0)
  fb.show = button(fb, "", 150, function()
    local mode = C.ClassMode()
    local items = {}
    for _, o in ipairs(FARM_SHOW) do
      if (not o.rogue or mode == "ROGUE") and (not o.druid or mode == "DRUID") then
        items[#items + 1] = { o.label, function() C.settings.farmShow = o.key; C.Refresh() end }
      end
    end
    showMenu(items)
  end)
  fb.show:SetPoint("LEFT", fb.cls, "RIGHT", 6, 0)
  fb.mode = button(fb, "", 150, function()
    local nxt = { kill = "common", common = "hour", hour = "kill" }
    C.settings.farmMetric = nxt[C.settings.farmMetric or "kill"] or "kill"
    ui.sort.Farms = nil; ui.offset = 0; C.Refresh() end)
  fb.mode:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Rank farms by: gold per kill (everything), gold per kill without rare drops (anything under the Rare % box), or gold per hour (your timed farms only).", 1, 1, 1, true)
    GameTooltip:Show() end)
  fb.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
  fb.mode:SetPoint("LEFT", fb.show, "RIGHT", 6, 0)
  local rl = C.Text(fb, "OVERLAY", "GameFontHighlightSmall"); rl:SetPoint("LEFT", fb.mode, "RIGHT", 8, 0); rl:SetText("Rare <")
  fb.rare = CreateFrame("EditBox", nil, fb, "InputBoxTemplate")
  fb.rare:SetSize(34, 18); fb.rare:SetPoint("LEFT", rl, "RIGHT", 6, 0); fb.rare:SetAutoFocus(false); fb.rare:SetMaxLetters(5)
  local function applyRare(self)
    local v = tonumber(((self:GetText() or ""):gsub(",", "."))) -- (gsub returns 2 values: keep 1)
    if v and v >= 0 and v <= 100 then C.settings.rareRate = v end
    self:SetText(tostring(C.settings.rareRate or 2.5)); self:ClearFocus(); C.Refresh()
  end
  fb.rare:SetScript("OnEnterPressed", applyRare)
  fb.rare:SetScript("OnEditFocusLost", applyRare)
  fb.rare:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  fb.rare:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Drops rarer than this (in %) are left out of the 'No rare' column. Type a number and press Enter.", 1, 1, 1, true); GameTooltip:Show() end)
  fb.rare:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local pct = C.Text(fb, "OVERLAY", "GameFontHighlightSmall"); pct:SetPoint("LEFT", fb.rare, "RIGHT", 2, 0); pct:SetText("%")
  fb.uniq = button(fb, "", 120, function() C.settings.showUnique = not C.settings.showUnique; ui.offset = 0; C.Refresh() end)
  fb.uniq:SetPoint("LEFT", pct, "RIGHT", 8, 0)
  fb.uniq:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Named rares and quest mobs with only 1-2 spawn points can't be farmed, so they're hidden. Tick to show them.", 1, 1, 1, true); GameTooltip:Show() end)
  fb.uniq:SetScript("OnLeave", function() GameTooltip:Hide() end)
  fb.enemy = button(fb, "", 130, function() C.settings.showEnemy = not C.settings.showEnemy; ui.offset = 0; C.Refresh() end)
  fb.enemy:SetPoint("LEFT", fb.uniq, "RIGHT", 6, 0)
  fb.enemy:SetScript("OnEnter", function(self) C.TipOwner(self)
    GameTooltip:AddLine("Zones and dungeons that belong to the other faction are hidden. Tick to show them anyway.", 1, 1, 1, true); GameTooltip:Show() end)
  fb.enemy:SetScript("OnLeave", function() GameTooltip:Hide() end)
  fb.info = C.Text(fb, "OVERLAY", "GameFontDisableSmall")
  fb.info:SetPoint("LEFT", fb.enemy, "RIGHT", 10, 0); fb.info:SetWidth(math.max(100, W - 1150)); fb.info:SetJustifyH("LEFT")
  if fb.info.SetWordWrap then fb.info:SetWordWrap(false) end
  ui.farmBar = fb
  ui.headButton = CreateFrame("Button", nil, f)
  ui.headButton:SetPoint("TOPLEFT", 12, -76); ui.headButton:SetSize(W - 24, 16); ui.headButton:Hide()
  local hhl = ui.headButton:CreateTexture(nil, "HIGHLIGHT"); hhl:SetAllPoints(); hhl:SetColorTexture(1, 1, 1, 0.08)
  ui.headButton:SetScript("OnClick", function() if ui.headClick then ui.headClick() end end)
  ui.head = C.Text(f, "OVERLAY", "GameFontHighlightSmall")
  ui.head:SetPoint("TOPLEFT", 14, -56); ui.head:SetWidth(W - 28); ui.head:SetJustifyH("LEFT")
  -- 1.2.0: the Ledger's views (Farms, Debts, Gold flow, XP) as real buttons
  if C.PUBLIC and ui.LEDGER_VIEWS then
    local vb = CreateFrame("Frame", nil, f); vb:SetSize(420, 24); vb.btns = {}
    local prev
    for i = #ui.LEDGER_VIEWS, 1, -1 do
      local v = ui.LEDGER_VIEWS[i]
      local b = button(vb, ui.LEDGER_VIEWNAME[v], v == "flow" and 96 or 76, function()
        ui.ledgerView = v; ui.bookOf = nil; ui.offset = 0; ui.sort.Ledger = nil; C.Refresh() end)
      b:SetHeight(24)
      if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("RIGHT", vb, "RIGHT", 0, 0) end
      prev = b; vb.btns[v] = b
    end
    vb:SetFrameLevel(f:GetFrameLevel() + 12)
    vb:Hide(); ui.viewBar = vb
  end
  if ui.head.SetWordWrap then ui.head:SetWordWrap(false) end
  -- sortable column headers
  ui.headers = {}
  for i = 1, 10 do
    local hb = CreateFrame("Button", nil, f)
    hb:SetSize(100, 16)
    hb.text = C.Text(hb, "OVERLAY", "GameFontNormalSmall"); hb.text:SetPoint("LEFT", 0, 0)
    local hl = hb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    hb:SetScript("OnClick", function()
      local tab = ui.tab or "Hot"
      local s = ui.sort[tab]
      if s and s.col == i then s.desc = not s.desc else ui.sort[tab] = { col = i, desc = (i ~= 1) } end
      C.Refresh()
    end)
    hb:SetScript("OnEnter", function(self)
      local tab = ui.tab or "Hot"
      local title = ui.colNames and ui.colNames[i]
      if not title or title == "" then return end
      local key, t = colTip(tab, title)
      C.TipOwner(self)
      GameTooltip:AddLine(key, 1, 0.82, 0)
      if t then
        GameTooltip:AddLine(t[1], 1, 1, 1, true)
        if t[2] and t[2] ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine("Example: " .. t[2], 0.6, 0.9, 0.6, true) end
      end
      GameTooltip:AddLine(" "); GameTooltip:AddLine("Click to sort by this column (again to reverse).", 0.5, 0.8, 1, true)
      GameTooltip:Show()
    end)
    hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.headers[i] = hb
  end
  -- shown in the middle of the list when a tab has nothing to show, saying why
  ui.empty = C.Text(f, "OVERLAY", "GameFontHighlight")
  ui.empty:SetPoint("TOP", f, "TOP", 0, -130); ui.empty:SetWidth(W - 160); ui.empty:SetJustifyH("LEFT")
  if ui.empty.SetWordWrap then ui.empty:SetWordWrap(true) end
  ui.empty:Hide()
  ui.rows = {}
  for r = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(W - 24, ROW_H); row:SetPoint("TOPLEFT", 12, -94 - (r - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    row.cells = {}
    for i = 1, 10 do
      local t = C.Text(row, "OVERLAY", "GameFontHighlightSmall")
      t:SetJustifyH("LEFT"); t:SetJustifyV("TOP"); t:SetWordWrap(true)
      if t.SetMaxLines then t:SetMaxLines(3) end
      row.cells[i] = t
    end
    row:SetScript("OnEnter", function(self)
      local d = self.data
      if not d then return end
      C.TipOwner(self)
      if d.id and GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) end
      if d.tip then GameTooltip:AddLine(d.tip, 1, 1, 1, true) end
      GameTooltip:AddLine(d.npc and "Click: details   Right-click: waypoint" or "Click: details   Right-click: actions   Shift-click: link", 0.5, 0.8, 1)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, btn)
      local d = self.data
      if not d then return end
      if d.route and (d.route.route or d.route.kind ~= "Kill") and not (d.route.kind == "Pick+Kill") then
        if btn == "RightButton" then C.FarmRowMenu(d.route) else C.ShowFarmRow(d.route) end
      elseif d.npc then
        if btn == "RightButton" then mobMenu(d) else C.ShowMob(d.npc, d.farm) end
      elseif d.syncRef and btn == "RightButton" and C.FarmSync then
        local seq = d.syncRef
        local ex = C.FarmSync.Excluded(C.session and C.session.sync)
        showMenu({ { ex[seq] and "Count it in this farm (everyone)" or "Leave it out of this farm (everyone)", function() C.FarmSync.ToggleEntry(seq) end } })
      elseif d.logRef and btn == "RightButton" then
        local e = d.logRef.s.log[d.logRef.i]
        local list = { { (e and e[7]) and "Count it in this farm" or "Leave it out of this farm", function() C.FarmEditEntry(d.logRef.s, d.logRef.i) end } }
        local ck = d.logRef.s.camp
        if e and e[2] == "kill" and ck then
          for _, c in ipairs(C.Data.camps or {}) do
            if c.key == ck then
              local inIt = false
              for _, id in ipairs(C.CampMobs(c)) do if id == e[3] then inIt = true end end
              list[#list + 1] = { (inIt and "Take " or "Add ") .. npcName(e[3]) .. (inIt and " out of the camp" or " to the camp"), function()
                local ed = C.CampEdit(c, true)
                if inIt then if ed.add[e[3]] then ed.add[e[3]] = nil else ed.drop[e[3]] = true end
                else if ed.drop[e[3]] then ed.drop[e[3]] = nil else ed.add[e[3]] = true end end
                C.Print(npcName(e[3]) .. (inIt and " taken out of " or " added to ") .. c.name .. ".")
                if C.Refresh then C.Refresh() end
              end }
            end
          end
        end
        showMenu(list)
      elseif d.slog then
        ui.logOf = d.slog; ui.offset = 0; ui.sort.Session = nil; C.Refresh()
      elseif d.debtAct then
        local kind, od = d.debtAct[1], d.debtAct[2]
        if kind == "plea" and C.AskForTime then C.AskForTime(od) elseif kind == "ext" and C.ExtendDebt then C.ExtendDebt(od) end
      elseif d.forgive then
        local od = d.forgive
        StaticPopupDialogs["KINA_FORGIVE"] = StaticPopupDialogs["KINA_FORGIVE"] or {
          text = "Forgive %s?\n\nThe debt closes for both of you and can't be reopened.",
          button1 = "Forgive", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
          OnAccept = function(_, x) if x and C.Forgive then C.Forgive(x) end end }
        StaticPopup_Show("KINA_FORGIVE", C.Books.Name(od.who) .. " the " .. C.Money(math.floor(od.amt)), nil, od)
      elseif d.book then
        ui.bookOf = d.book; ui.offset = 0; C.Refresh()
      elseif d.flip and not (IsShiftKeyDown and IsShiftKeyDown()) then
        if btn == "RightButton" then itemMenu(d.id, d) else C.ShowFlip(d.flip) end
      elseif d.recipe and not (IsShiftKeyDown and IsShiftKeyDown()) then
        if btn == "RightButton" then C.RecipeMenu(d.recipe) else C.ShowRecipe(d.recipe) end
      elseif d.id then
        if btn == "RightButton" then itemMenu(d.id, d)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
          local l = C.ItemLink(d.id); if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end
        else C.ShowItem(d.id) end
      end
    end)
    ui.rows[r] = row
  end
  fitWidths()
  -- 1.1.1: a scrollbar for long lists (the farm log got very long)
  if C.Skin and C.Skin.Scrollbar then
    ui.scroll = C.Skin.Scrollbar(f, function(v)
      if v ~= (ui.offset or 0) then ui.offset = v; C.Draw() end
    end)
    ui.scroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -104)
    ui.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 70)
    ui.scroll:Hide()
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    ui.offset = math.max(0, math.min((ui.count or 0) - ui.visible, (ui.offset or 0) - delta * 3)); C.Draw()
  end)
  f:Hide()
end

local function layout(colX, top)
  top = top or 0
  ROW_H = math.max(14, math.floor(18 * C.TextScale() + 0.5))
  -- columns stretch with the window; rows fill its height
  local sx = (ui.w - 30) / (W - 30)
  local X = {}
  for i, x in ipairs(colX) do X[i] = math.floor(x * sx) end
  local right = ui.w - 30
  ui.visible = math.max(5, math.min(MAX_ROWS, math.floor((ui.h - 94 - top - 70) / ROW_H)))
  ui.top = top
  for r, row in ipairs(ui.rows) do
    row:ClearAllPoints()
    if r == 1 then row:SetPoint("TOPLEFT", 12, -94 - top) else row:SetPoint("TOPLEFT", ui.rows[r - 1], "BOTTOMLEFT", 0, 0) end
    row:SetSize(ui.w - 24, ROW_H)
  end
  for i, hb in ipairs(ui.headers) do
    local x = X[i]
    if x then
      hb:ClearAllPoints(); hb:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 16 + x, -76 - top)
      hb:SetSize(((X[i + 1] or right) - x) - 4, math.max(16, ROW_H - 2)); hb:Show()
    else hb:Hide() end
  end
  for _, row in ipairs(ui.rows) do
    for i, t in ipairs(row.cells) do
      local x = X[i]
      if x then
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", row, "TOPLEFT", 4 + x, -3)
        t:SetWidth(((X[i + 1] or right) - x) - 6); t:Show()
      else t:Hide() end
    end
  end
end

-- Keep the bars and header text as wide as the window.
fitWidths = function()
  local w = ui.w
  if ui.head then ui.head:SetWidth(w - 28) end
  if ui.headButton then ui.headButton:SetWidth(w - 24) end
  for _, b in ipairs({ ui.farmBar, ui.craftBar, ui.roiBar }) do if b then b:SetWidth(w - 28) end end
  if ui.farmBar and ui.farmBar.info then ui.farmBar.info:SetWidth(math.max(60, w - 880)) end
  if ui.craftBar and ui.craftBar.info then ui.craftBar.info:SetWidth(math.max(60, w - 560)) end
  if ui.roiBar and ui.roiBar.info then ui.roiBar.info:SetWidth(math.max(60, w - 630)) end
  if ui.settingsContent then ui.settingsContent:SetWidth(w - 50) end
end

-- Long text wraps (up to 3 lines) and the row grows to fit; rows fill the window.
function C.Draw()
  local data = ui.data or {}
  ui.count = #data
  local avail = ui.h - 94 - (ui.top or 0) - 70
  local used, shown, full = 0, 0, false
  for r = 1, MAX_ROWS do
    local row, d = ui.rows[r], (not full) and data[(ui.offset or 0) + r] or nil
    local h = ROW_H
    for i = 1, #row.cells do
      local t = row.cells[i]
      t:SetText(d and d.cols[i] or "")
      if d and t:IsShown() then
        local sh = t.GetStringHeight and t:GetStringHeight() or 0
        if sh and sh + 6 > h then h = sh + 6 end
      end
    end
    h = math.floor(h + 0.5)
    if d and shown > 0 and used + h > avail then d, full = nil, true end
    row.data = d
    if d then row:SetHeight(h); row:Show(); used = used + h; shown = shown + 1 else row:Hide() end
  end
  ui.visible = math.max(1, shown)
  if ui.scroll and ui.scroll.KinaSet then ui.scroll:KinaSet((ui.count or 0) - ui.visible, ui.offset or 0) end
end

local function sortRows(data, s)
  if not s then return end
  table.sort(data, function(a, b)
    local x, y = a.sort and a.sort[s.col], b.sort and b.sort[s.col]
    if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
    if x == nil then return false end
    if y == nil then return true end
    if type(x) == "string" then x, y = x:lower(), y:lower() end
    if x == y then return false end
    if s.desc then return x > y else return x < y end
  end)
end

local function filterRows(data, query)
  if not query or not query:find("%S") then return data end
  local out = {}
  for _, d in ipairs(data) do
    local hay = ""
    for _, c in ipairs(d.cols) do hay = hay .. " " .. plain(c) end
    if C.LooseMatch(query, hay) then out[#out + 1] = d end
  end
  return out
end

function C.Refresh()
  if not ui.frame or not ui.frame:IsShown() then return end
  if C.dragging then C.refreshAfterDrag = true; return end -- re-laying hundreds of rows mid-drag makes the window stutter
  if ui.tab and not TAB_OK[ui.tab] then ui.tab = HOME end -- a removed tab (old link or saved state)
  local tab = ui.tab or HOME
  local ok, head, cols, colX, data, opts = pcall(tabs[tab])
  if not ok then
    if C.LogError then C.LogError("tab " .. tostring(tab), head) end
    head, cols, colX, data = "error: " .. tostring(head), {}, { 0 }, {}
  end
  opts = opts or {}
  -- 1.2.0: breathing room under the tab shelf in the iron look
  if C.Skin and C.Skin.On() then opts.top = (opts.top or 0) + 10 end
  ui.panelTop = 82 + (opts.top or 0)
  if C.ShowPanel then pcall(C.ShowPanel, opts.panel) end
  -- the Ledger's views as buttons
  if ui.viewBar then
    if tab == "Ledger" then
      ui.viewBar:Show()
      for v, b in pairs(ui.viewBar.btns) do
        local on = (ui.ledgerView or "farms") == v and not ui.bookOf
        if on then b:LockHighlight() else b:UnlockHighlight() end
        local fs = b.GetFontString and b:GetFontString()
        if fs then if on then fs:SetTextColor(1, 0.85, 0.3) else fs:SetTextColor(0.85, 0.85, 0.85) end end
      end
      ui.viewBar:ClearAllPoints(); ui.viewBar:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -16, -52 - (opts.top or 0))
    else ui.viewBar:Hide() end
  end
  -- the header line leaves room for the view buttons on the Ledger
  if ui.head then ui.head:SetWidth(math.max(200, ui.w - ((tab == "Ledger" and ui.viewBar) and 470 or 28))) end
  layout(colX, opts.top or 0)
  ui.head:ClearAllPoints(); ui.head:SetPoint("TOPLEFT", 14, -56 - (opts.top or 0))
  if ui.headButton then ui.headButton:ClearAllPoints(); ui.headButton:SetPoint("TOPLEFT", 12, -54 - (opts.top or 0)) end
  ui.head:SetText(head)
  ui.headClick = opts.headClick
  -- public Ledger: the period button (7 days / 30 days / all time) only on the Ledger list
  if C.PUBLIC and ui.ledgerDaysButton then
    if tab == "Ledger" and not ui.bookOf then ui.ledgerDaysButton:Show() else ui.ledgerDaysButton:Hide() end
    if ui.roiBar and ui.roiBar.held then ui.roiBar.held:Hide() end
  end
  if ui.headButton then if opts.headClick then ui.headButton:Show() else ui.headButton:Hide() end end
  if ui.craftBar then
    if opts.crafts then ui.craftBar:Show(); C.RefreshCraftBar() else ui.craftBar:Hide() end
  end
  if ui.farmBar then
    if opts.farms then ui.farmBar:Show(); C.RefreshFarmBar() else ui.farmBar:Hide() end
  end
  if ui.settingsPanel then
    if opts.settings then ui.settingsPanel:Show(); C.RefreshSettings() else ui.settingsPanel:Hide() end
  end
  ui.colNames = cols
  local s = ui.sort[tab]
  for i, hb in ipairs(ui.headers) do
    local t = cols[i] or ""
    if s and s.col == i then t = t .. (s.desc and " v" or " ^") end
    hb.text:SetText(t)
  end
  if not opts.searched then data = filterRows(data, ui.search[tab]) end
  -- ROI / worth-it filter: only rows that carry an ROI or a worth flag are affected
  local minROI = (C.settings.minROI or 0) / 100
  local hidden, has = 0, false
  local roiTab = false
  for _, d in ipairs(data) do if d.roi ~= nil or d.worth ~= nil then roiTab = true; break end end
  if minROI > 0 or C.settings.worthOnly then
    local kept = {}
    for _, d in ipairs(data) do
      if d.roi ~= nil or d.worth ~= nil then has = true end
      local hide = (minROI > 0 and d.roi ~= nil and d.roi < minROI) or (C.settings.worthOnly and d.worth == false)
      if hide then hidden = hidden + 1 else kept[#kept + 1] = d end
    end
    data = kept
  end
  if ui.roiBar then
    local rb = ui.roiBar
    rb.worth:SetText(C.settings.worthOnly and "|cff40ff40[x]|r Hide not worth my time" or "[  ] Hide not worth my time")
    if tab == "Deals" then rb.best:Show(); rb.view:Show() elseif tab == "Invest" then rb.best:Show(); rb.view:Hide() else rb.best:Hide(); rb.view:Hide() end
    if tab == "Deals" or tab == "Invest" then rb.afford:Show() else rb.afford:Hide() end
    -- the ROI box and the worth switch only on a tab whose rows have an ROI
    for _, w in ipairs({ rb.roiLabel, rb.roiBox, rb.worth }) do if w then if roiTab then w:Show() else w:Hide() end end end
    if tab == "Deals" then
      rb.quick:Show(); rb.quick:SetText(C.Quick and C.Quick.ButtonText() or "Quick scan")
      rb.quick:ClearAllPoints(); rb.quick:SetPoint("LEFT", rb.afford, "RIGHT", 6, 0)
      rb.hotType:Hide(); rb.hotOpt:Hide()
    elseif tab == "Hot" then
      rb.quick:Show(); rb.quick:SetText(C.Quick and C.Quick.ButtonText() or "Quick scan")
      rb.quick:ClearAllPoints()
      if roiTab then rb.quick:SetPoint("LEFT", rb.worth, "RIGHT", 6, 0) else rb.quick:SetPoint("LEFT", rb, "LEFT", 2, 0) end
      rb.hotType:Show(); rb.hotType:ClearAllPoints(); rb.hotType:SetPoint("LEFT", rb.quick, "RIGHT", 6, 0)
      rb.hotType:SetText((ui.hotType and "|cff7CFC00" or "") .. "Show: " .. C.HotTypeLabel() .. (ui.hotType and "|r" or ""))
      rb.hotOpt:Show(); rb.hotOpt:ClearAllPoints(); rb.hotOpt:SetPoint("LEFT", rb.hotType, "RIGHT", 6, 0)
      local off = 0; for _ in pairs(C.settings.hotHide or {}) do off = off + 1 end
      rb.hotOpt:SetText(off > 0 and ("|cff7CFC00Options (" .. off .. " off)|r") or "Options")
    else rb.quick:Hide(); rb.hotType:Hide(); rb.hotOpt:Hide() end
    if tab == "Ledger" and not C.PUBLIC then rb.held:Show() else rb.held:Hide() end
    rb.info:ClearAllPoints()
    local anchor = (tab == "Hot" and rb.hotOpt) or (tab == "Deals" and rb.quick) or (tab == "Invest" and rb.afford) or (tab == "Ledger" and rb.held) or (roiTab and rb.worth) or nil
    if anchor then rb.info:SetPoint("LEFT", anchor, "RIGHT", 10, 0) else rb.info:SetPoint("LEFT", rb, "LEFT", 2, 0) end
    rb.afford:SetText((C.settings.dealAfford and "|cff40ff40[x]|r" or "[  ]") .. " Only what I can afford"
      .. ((C.settings.dealAfford and (ui.affordHidden or 0) > 0) and (" (" .. ui.affordHidden .. " hidden)") or ""))
    local cur = ui.sort[tab]
    rb.best:SetText((cur and cur.auto) and "|cff40ff40Sorted: best deal|r" or "Sort: best deal")
    rb.view:SetText(ui.dealView == "passive" and "|cff7CFC00View: passive income|r" or "View: best deals")
    rb.info:SetText(hidden > 0 and string.format("%d hidden by the filter (a trade must clear %s of your time)", hidden, C.Money(C.Econ.Overhead()))
      or "")
  end
  sortRows(data, s)
  ui.data = data
  if ui.empty then
    local msg = (#data == 0) and opts.empty or nil
    if #data == 0 and hidden > 0 and not msg then
      msg = string.format("All %d rows are hidden by your filters (bottom bar).", hidden)
        .. (C.settings.worthOnly and "\n\n'Hide not worth my time' hides the grey rows: deals your enchanter can't do yet (needs higher Enchanting), "
          .. "deals likely to lose money (Guardian 50%+), and trades that make less than your time is worth. Click it again to see them." or "")
        .. ((C.settings.minROI or 0) > 0 and ("\n\nMin ROI is " .. C.settings.minROI .. "%: lower it to see more.") or "")
    elseif msg and hidden > 0 then msg = msg .. string.format("\n\n%d rows are hidden by Min ROI or 'Hide not worth my time' (bottom bar).", hidden) end
    if msg then ui.empty:SetWidth(math.max(300, ui.w - 160)); ui.empty:SetText(msg); ui.empty:Show() else ui.empty:Hide() end
  end
  if ui.searchBox and ui.searchBox:GetText() ~= (ui.search[tab] or "") then ui.searchBox:SetText(ui.search[tab] or "") end
  for name, b in pairs(ui.tabButtons) do
    if name == tab then b:LockHighlight() else b:UnlockHighlight() end
    if C.Skin then C.Skin.TabActive(b, name == tab) end
  end
  C.Draw()
end

function C.Toggle(tab)
  if tab and not TAB_OK[tab] then tab = HOME end
  if not ui.frame then build() end
  if tab then ui.tab = tab end
  if ui.frame:IsShown() and not tab then ui.frame:Hide()
  else
    if not ui.frame:IsShown() then C.DockToAH() end
    ui.frame:Show(); if C.RaiseKina then C.RaiseKina() end; C.Refresh()
  end
end

-- 1.1.1: open one farm's Ledger details (from the widget's Pay / Ask button)
function C.OpenLedgerFarm(s)
  if not ui.frame then build() end
  -- 1.2.0: debts are handled on the Debts page (its buttons), not in the farm details
  ui.bookOf = nil; ui.ledgerView = "debts"; ui.offset = 0
  C.Toggle("Ledger")
end

C.OnMarket(function() C.Refresh() end)
-- Settings > Text size: re-lay the rows to fit the new size while you drag
function C.OnTextScale()
  if ui.frame and ui.frame:IsShown() then C.Refresh() end
end
-- 1.2.3: only while the window is open, and never in combat (a hunter's arrows fire this
-- every shot; rebuilding the hidden window in combat was the suspect for UNKNOWN() blocks)
local bagDirty = false
C.On("BAG_UPDATE_DELAYED", function()
  if not (ui.frame and ui.frame:IsShown() and ui.tab == "Bags") then return end
  if InCombatLockdown and InCombatLockdown() then bagDirty = true return end
  C.Refresh()
end)
C.On("PLAYER_REGEN_ENABLED", function() if bagDirty then bagDirty = false; if ui.frame and ui.frame:IsShown() then C.Refresh() end end end)
-- open beside the auction house (turn off with /kina auto)
C.On("AUCTION_HOUSE_SHOW", function()
  if not C.PUBLIC and C.settings.autoOpen ~= false then
    if not ui.frame then build() end
    if not ui.frame:IsShown() then ui.frame:Show(); ui.autoOpened = true; C.Refresh() end
  end
  -- beside the AH; again a moment later, after the game has placed the AH window
  if ui.frame and ui.frame:IsShown() then
    C.DockToAH()
    C.After(0.2, function() if ui.frame:IsShown() then C.DockToAH() end end)
  end
end)


-- opened by the auction house: close with it (a window you opened yourself stays)
C.On("AUCTION_HOUSE_CLOSED", function()
  if ui.autoOpened and ui.frame and ui.frame:IsShown() then ui.frame:Hide() end
  ui.autoOpened = nil
end)

-- /kina reset: every window back to its default spot
function C.ResetWindows()
  wipe(C.settings.pos); C.settings.ahDock = nil
  if ui.frame then ui.frame:SetSize(W, H) end
  if detail then detail:SetScale(1) end
  local wdg = _G.KinaWidget; if wdg then wdg:SetScale(1) end
  if ui.frame and not C.DockToAH() then ui.frame:ClearAllPoints(); ui.frame:SetPoint("LEFT", UIParent, "LEFT", 40, 40) end
  if C.ResetWidget then C.ResetWidget() end
  C.Print("window positions reset.")
end
