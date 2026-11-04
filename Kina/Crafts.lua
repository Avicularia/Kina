-- Kina: craft margins on recipes your characters know.
-- Recipes are captured when you open your own profession window (same calls
-- Kina Scout used on Forever), and Kina Scout's earlier captures are read once.
local _, C = ...
local profOpen = false
local captureJob = false

local function parse(id, info, s)
  if not (info and s) or info.isEnchantingRecipe then return nil end
  local count = s.quantityMin
  if not count or count <= 0 or (s.quantityMax and s.quantityMax ~= count) then return nil end
  local out = s.outputItemID
  if not out or out <= 0 then return nil end
  local reagents = {}
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local r = slot.reagents and slot.reagents[1]
    if not (r and r.itemID and slot.quantityRequired) then return nil end
    -- skip optional/finishing slots instead of rejecting the whole recipe
    if slot.required ~= false then reagents[r.itemID] = (reagents[r.itemID] or 0) + slot.quantityRequired end
  end
  if not next(reagents) then return nil end
  return { name = info.name, out = out, n = count, reagents = reagents }
end

local function capture()
  local t = C_TradeSkillUI
  if captureJob or not (t and t.GetAllRecipeIDs and t.GetRecipeSchematic and t.GetRecipeInfo) then return end
  if t.IsTradeSkillLinked and t.IsTradeSkillLinked() then return end
  local ids = t.GetAllRecipeIDs()
  if type(ids) ~= "table" or #ids == 0 then return end
  local prof = t.GetBaseProfessionInfo and t.GetBaseProfessionInfo()
  local profName = prof and prof.professionName or "?"
  captureJob = true
  C.char.knownProf = C.char.knownProf or {}
  C.char.knownProf[profName] = C.Now()
  local i = 1
  C.Job(function()
    if not profOpen then captureJob = false; return true end
    for _ = 1, 20 do
      local id = ids[i]; i = i + 1
      if not id then captureJob = false; return true end
      local info = t.GetRecipeInfo(id)
      if info and info.learned then
        C.char.known = C.char.known or {}
        C.char.known[id] = true
        local ok, s = pcall(t.GetRecipeSchematic, id, false)
        local r = ok and parse(id, info, s)
        if r then
          r.prof = profName
          C.db.recipes = C.db.recipes or {}
          local have = C.db.recipes[id]
          r.owners = have and have.owners or {}
          r.owners[C.charKey] = true
          C.db.recipes[id] = r
        end
      end
    end
  end)
end
C.On("TRADE_SKILL_SHOW", function() profOpen = true end)
C.On("TRADE_SKILL_CLOSE", function() profOpen = false end)
C.On("TRADE_SKILL_LIST_UPDATE", function() if profOpen then capture() end end)

-- Classic-style profession windows (GetTradeSkillInfo; Enchanting uses the Craft
-- window). Marks which recipes this character knows, matched by recipe link or name.
local function captureClassic(kind)
  local craft = kind == "craft"
  local num, line
  if craft then
    if not GetNumCrafts then return end
    num = GetNumCrafts()
    line = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetCraftName and GetCraftName())
  else
    if not GetNumTradeSkills then return end
    if IsTradeSkillLinked and IsTradeSkillLinked() then return end
    num = GetNumTradeSkills()
    line = GetTradeSkillLine and GetTradeSkillLine()
  end
  if not num or num == 0 or type(line) ~= "string" or line == "UNKNOWN" then return end
  local byName = {}
  for spell, c in pairs(C.RecipeCatalog()) do if c.name and c.prof == line then byName[c.name] = spell end end
  C.char.known = C.char.known or {}
  C.char.knownProf = C.char.knownProf or {}
  C.char.knownProf[line] = C.Now()
  local found = 0
  for i = 1, num do
    local name, typ
    if craft then local n, _, t = GetCraftInfo(i); name, typ = n, t
    else name, typ = GetTradeSkillInfo(i) end
    if name and typ ~= "header" and typ ~= "subheader" then
      local link = craft and (GetCraftRecipeLink and GetCraftRecipeLink(i)) or (not craft and GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
      local spell = type(link) == "string" and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)")) or nil
      if not (spell and C.RecipeCatalog()[spell]) then spell = byName[name] end
      if spell then C.char.known[spell] = true; found = found + 1 end
    end
  end
  if found > 0 and C.Refresh then C.After(0.2, C.Refresh) end
end
local classic = CreateFrame("Frame")
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(classic.RegisterEvent, classic, ev) -- an event this client lacks is simply skipped
end
classic:SetScript("OnEvent", function(_, ev)
  if not C.ready then return end
  pcall(captureClassic, ev:find("^CRAFT") and "craft" or "trade")
end)

-- One-time read of Kina Scout's learned recipe captures (never written to).
local function importKinaScout()
  C.char.guid = UnitGUID and UnitGUID("player") or C.char.guid
  local ks = rawget(_G, "KinaScoutDB")
  if type(ks) ~= "table" or type(ks.contexts) ~= "table" then return end
  C.db.recipes = C.db.recipes or {}
  local n = 0
  for _, ctx in pairs(ks.contexts) do
    if type(ctx) == "table" and type(ctx.recipes) == "table" then
      for id, r in pairs(ctx.recipes) do
        if type(id) == "number" and type(r) == "table" and r.learned and r.owner and r.owner == C.char.guid then
          C.char.known = C.char.known or {}
          C.char.known[id] = true
        end
        if type(id) == "number" and type(r) == "table" and r.learned and type(r.output) == "number"
            and type(r.reagents) == "table" and not C.db.recipes[id] then
          C.db.recipes[id] = { name = r.name, out = r.output, n = r.count or 1, reagents = r.reagents,
            prof = r.profession, owners = { ["from Kina Scout"] = true } }
          n = n + 1
        end
      end
    end
  end
  if n > 0 then C.Print(n .. " recipes imported from Kina Scout (read-only).") end
end
C.On("PLAYER_LOGIN", function() pcall(importKinaScout) end)

-- Cheapest way to GET one unit of a reagent: AH (depth price) or a merchant.
function C.BuyCost(id)
  local mi = C.MarketItem(id)
  local ah = mi and (mi.d or mi.m)
  local vend = C.MerchantPrice and C.MerchantPrice(id)
  if ah and vend then return math.min(ah, vend), (vend <= ah) and "vendor" or "ah" end
  if vend then return vend, "vendor" end
  if ah then return ah, "ah" end
  -- never seen on a merchant or the AH: plain supplies (vials, thread, rods, dyes)
  -- cost about 4x what a vendor pays for them. Marked as an estimate.
  local r = C.Item(id)
  if r and r.vend and r.vend > 0 and r.vend <= 50 and (r.q or 1) <= 1 and not C.IsGear(r) then return r.vend * 4, "est" end
  return nil
end

------------------------------------------------------------------ recipe model
-- Every Forever recipe (RecipeData.lua, built from your Forever Guide) plus any
-- recipe your characters captured from the game (the game's reagents win).
local catalog
function C.RecipeCatalog()
  if catalog then return catalog end
  catalog = {}
  local D = C.Data
  for spell, r in pairs(D.recipes or {}) do
    local reag = {}
    for k = 1, #r[10], 2 do reag[r[10][k]] = (reag[r[10][k]] or 0) + r[10][k + 1] end
    catalog[spell] = { spell = spell, prof = D.profs[r[1]], out = r[2], n = r[3], l = ((r[4] or 0) > 0) and r[4] or r[5], y = r[5], g = r[6], x = r[7], -- l: 93 recipes have no learn skill (0): the first craft skill is the real one
      trainer = r[8] == 1, src = r[9] > 0 and r[9] or nil, reagents = reag, name = r[11] }
  end
  for spell, r in pairs(C.db.recipes or {}) do
    local c = catalog[spell]
    if c then c.reagents, c.n, c.out = r.reagents, r.n, r.out
    else catalog[spell] = { spell = spell, prof = r.prof, out = r.out, n = r.n, reagents = r.reagents, name = r.name } end
  end
  return catalog
end
function C.ResetRecipeCatalog() catalog = nil end
C.On("TRADE_SKILL_CLOSE", function() catalog = nil end)

function C.MySkill(prof) return C.char.prof and C.char.prof[prof] end

-- Your main crafting professions (the two you picked), not Cooking/First Aid/Fishing.
C.PRIMARY = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
  Leatherworking = true, Tailoring = true, Mining = true, Jewelcrafting = true, Inscription = true }
function C.MyPrimary(prof) return C.PRIMARY[prof] and C.MySkill(prof) or nil end

function C.IsKnown(spell)
  if C.char.known and C.char.known[spell] then return true end
  local r = C.db.recipes and C.db.recipes[spell]
  return r and r.owners and r.owners[C.charKey] and true or false
end

-- Have we seen this character's recipe book for that profession yet?
function C.KnowsBookOf(prof)
  if C.char.knownProf and C.char.knownProf[prof] then return true end
  for spell in pairs(C.char.known or {}) do
    local c = C.RecipeCatalog()[spell]
    if c and c.prof == prof then return true end
  end
  return false
end

-- skill-up colour at your current skill
function C.SkillColor(r, skill)
  if not (skill and r.y and r.y > 0) then return nil end
  if skill < r.y then return "orange" elseif skill < r.g then return "yellow" elseif skill < r.x then return "green" end
  return "grey"
end

-- Professions with recipes, yours first: { name, skill or nil }
function C.RecipeProfessions(mineOnly)
  local seen, out = {}, {}
  for _, c in pairs(C.RecipeCatalog()) do if c.prof then seen[c.prof] = true end end
  for prof in pairs(seen) do
    local sk = C.MySkill(prof)
    if sk or not mineOnly then out[#out + 1] = { prof, sk } end
  end
  table.sort(out, function(a, b)
    if (a[2] ~= nil) ~= (b[2] ~= nil) then return a[2] ~= nil end
    return a[1] < b[1]
  end)
  return out
end

-- Where the recipe is learned, as text plus a place to go.
local function trainerRank(skill) return (skill or 0) <= 50 and 1 or (skill <= 125 and 2 or (skill <= 200 and 3 or 4)) end
local function myFaction() return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A" end

function C.RecipeTrainer(prof, skill)
  local pts, need, fac = {}, trainerRank(skill), myFaction()
  for _, t in ipairs((C.Data.trainers or {})[prof] or {}) do
    if t[6]:find(fac, 1, true) and (t[7] or 1) >= need then pts[#pts + 1] = { t[3], t[4], t[5], npc = t[1], name = t[2] } end
  end
  local p, same = C.Nearest(pts)
  if p and not same then
    -- not in a trainer's zone: send you to your faction's capitals first
    local caps = fac == "A" and { 1453, 1455, 1457 } or { 1454, 1458, 1456 }
    for _, cap in ipairs(caps) do
      local hit
      for _, q in ipairs(pts) do if q[1] == cap then hit = q; break end end
      if hit then p = hit; break end
    end
  end
  return p and { name = p.name, map = p[1], x = p[2], y = p[3], zone = C.MapName(p[1]), sameZone = same } or nil
end

function C.RecipeVendor(item)
  local pts, fac = {}, myFaction()
  for _, npc in ipairs((C.Data.recipeVendors or {})[item] or {}) do
    local v = C.Data.recipeNPCs[npc]
    if v and v[5]:find(fac, 1, true) then pts[#pts + 1] = { v[2], v[3], v[4], name = v[1] } end
  end
  local p, same = C.Nearest(pts)
  if p then return { name = p.name, map = p[1], x = p[2], y = p[3], zone = C.MapName(p[1]), sameZone = same } end
  local v = C.NearestVendor and C.NearestVendor(item)
  return v
end

function C.LearnSource(r)
  if r.trainer then return "Trainer", "trainer" end
  if r.src then
    local mi = C.MarketItem(r.src)
    if mi and mi.m then return "Pattern " .. C.Money(mi.m) .. " (AH)", "ah", mi.m end
    if (C.Data.recipeVendors or {})[r.src] then return "Pattern (vendor)", "vendor" end
    return "Pattern (drop/quest)", "drop"
  end
  return "-", nil
end

-- Margin for one craft: output sold on the AH vs buying every reagent,
-- and vs SELLING the reagents instead (what crafting your own mats earns).
local function price(r)
  local outItem = C.Item(r.out)
  local bound = outItem and (outItem.bind == 1 or outItem.bind == 4)
  local sell = (not bound) and C.AHNet(r.out, r.n) or nil
  local vend = C.VendorPrice(r.out, true) or 0
  local each = math.max(sell or 0, vend)
  local cost, matsSell, missing, est = 0, 0, 0, false
  for mat, q in pairs(r.reagents) do
    local c, how = C.BuyCost(mat)
    if c then cost = cost + c * q; if how == "est" then est = true end
    else missing = missing + 1 end
    matsSell = matsSell + (select(2, C.BestRoute(mat, q)) or 0) * q
  end
  -- still show the recipe when a reagent has no price yet: cost reads "?"
  local value = each * r.n
  local known = missing == 0
  return { value = each > 0 and value or nil, cost = known and cost or nil, partCost = cost, missing = missing, est = est,
    profit = (known and each > 0) and (value - cost) or nil, vsMats = each > 0 and (value - matsSell) or nil,
    viaVendor = (sell or 0) < vend, bound = bound, listed = C.MarketItem(r.out) and C.MarketItem(r.out).q or 0,
    roi = (known and cost > 0 and each > 0) and (value - cost) / cost or nil }
end

-- opts: prof ("ALL" or a profession), mine (only your professions), show ("all" | "learned" | "unlearned")
-- status: learned | can (skill high enough) | low (skill too low) | none (you lack the profession)
local cache = {}
function C.CraftRows(opts)
  opts = opts or {}
  local key = table.concat({ tostring(C.market.scanTime), tostring(opts.prof), tostring(opts.mine), C.charKey,
    tostring(C.char.known and next(C.char.known)), tostring(C.ScanAgeMinutes and C.ScanAgeMinutes()) }, "|")
  if cache.key == key and cache.t and (GetTime and GetTime() or 0) - cache.t < 10 then return cache.rows end
  local out = {}
  for spell, r in pairs(C.RecipeCatalog()) do
    local skill = r.prof and C.MySkill(r.prof)
    local mineOK = not opts.mine or (opts.prof ~= nil and opts.prof ~= "ALL" and skill) or C.MyPrimary(r.prof)
    if r.prof and (opts.prof == nil or opts.prof == "ALL" or opts.prof == r.prof) and mineOK then
      local status
      if C.IsKnown(spell) then status = "learned"
      elseif not skill then status = "none"
      elseif skill >= (r.l or 0) then status = "can"
      else status = "low" end
      local m = price(r)
      -- a merchant sells the product: nobody pays more than that on the AH, so a
      -- "sells for" above the merchant's price is a profit that can't happen. Hidden.
      local mp = C.MerchantPrice and C.MerchantPrice(r.out)
      local fake = mp and m and m.value and m.value / math.max(1, r.n or 1) > mp
      -- (a merchant also sells it: still shown, flagged; players do pay more on the AH
      -- for convenience)
      if (m or status == "learned" or opts.mine) then
        local row = m or {}
        row.merchant = fake and mp or nil
        row.id, row.spell, row.out, row.n, row.prof, row.name = spell, spell, r.out, r.n, r.prof, r.name
        row.l, row.y, row.g, row.x, row.src, row.trainer, row.reagents = r.l, r.y, r.g, r.x, r.src, r.trainer, r.reagents
        row.status, row.skill = status, skill
        row.color = (status == "learned" or status == "can") and C.SkillColor(r, skill) or nil
        row.learn, row.learnKind, row.learnCost = C.LearnSource(r)
        -- skill is high enough but the pattern only drops: you have to find it first
        if status == "can" and row.learnKind == "drop" then row.status = "find" end
        row.obtainable = row.learnKind == "trainer" or row.learnKind == "ah" or row.learnKind == "vendor"
        out[#out + 1] = row
      end
    end
  end
  table.sort(out, function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end)
  cache = { key = key, rows = out, t = GetTime and GetTime() or 0 }
  return out
end

-- Best recipe you do NOT have that beats everything you do have.
-- Returns: ready (learnable now) and goal (better still, but your skill is too low).
function C.SuggestRecipe(rows)
  local best = {}
  for _, r in ipairs(rows) do
    if r.status == "learned" and r.profit then best[r.prof] = math.max(best[r.prof] or 0, r.profit) end
  end
  local ready, goal, goalAny
  for _, r in ipairs(rows) do -- rows are sorted by profit, best first
    if r.profit and r.profit > 0 and r.profit > (best[r.prof] or 0) and (r.listed or 0) > 0 then
      -- ready: learnable today (trainer, pattern on the AH or at a vendor)
      if r.status == "can" and r.obtainable and not ready then ready = r end
      -- goal: prefer one you will be able to get when your skill gets there
      if r.status == "low" and r.obtainable and not goal then goal = r end
      if r.status == "low" and not goalAny then goalAny = r end
    end
  end
  goal = goal or goalAny
  if goal and ready and goal.profit < ready.profit * 1.25 then goal = nil end
  if ready then ready.beats = best[ready.prof] or 0 end
  if goal then goal.beats = best[goal.prof] or 0 end
  return ready, goal
end
