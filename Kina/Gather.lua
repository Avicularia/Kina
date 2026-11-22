-- Kina 2.0.6: gathering on the Hot Farms page.
-- Taylor: "if kina sees my mining at 175, it checks every mineable material below that and
-- if any of them have a sudden meaningful spike in price point, it tells me which nodes to
-- farm, what material is hot, and the estimated drop rate of that material from that node.
-- If it's 3 iron ore per hit, then that would read Iron Ore: 300%. This should be nearly
-- the same formula for any materials from any mob."
-- So a node is scored like a mob: every material it gives x how many per gather (300% =
-- 3 per node) x its price (the same AH rules as hot mobs, H.ItemValue), and a material
-- whose price today is 1.5x its own two-week median (H.Spike) makes the node HOT.
-- Yields come from your own gathering (Kina records every node you loot, Loot.lua) once a
-- node has 3+ gathers; before that, a typical Classic yield, marked "est.".
local _, C = ...
local G = {}
C.Gather = G

-- Classic node object IDs: name, profession, skill to gather, main material
G.NODES = {
  [1731] = { "Copper Vein", "Mining", 1, 2770 }, [1732] = { "Tin Vein", "Mining", 65, 2771 },
  [1733] = { "Silver Vein", "Mining", 75, 2775 }, [1610] = { "Incendicite Mineral Vein", "Mining", 65, 3340 },
  [2653] = { "Lesser Bloodstone Deposit", "Mining", 75, 4278 }, [1735] = { "Iron Deposit", "Mining", 125, 2772 },
  [19903] = { "Indurium Mineral Vein", "Mining", 150, 5833 }, [1734] = { "Gold Vein", "Mining", 155, 2776 },
  [2040] = { "Mithril Deposit", "Mining", 175, 3858 }, [2047] = { "Truesilver Deposit", "Mining", 230, 7911 },
  [165658] = { "Dark Iron Deposit", "Mining", 230, 11370 }, [324] = { "Small Thorium Vein", "Mining", 245, 10620 },
  [175404] = { "Rich Thorium Vein", "Mining", 275, 10620 },
  [73940] = { "Ooze Covered Silver Vein", "Mining", 75, 2775 }, [73941] = { "Ooze Covered Gold Vein", "Mining", 155, 2776 },
  [123308] = { "Ooze Covered Mithril Deposit", "Mining", 175, 3858 }, [123309] = { "Ooze Covered Truesilver Deposit", "Mining", 230, 7911 },
  [123310] = { "Ooze Covered Thorium Vein", "Mining", 245, 10620 }, [177388] = { "Ooze Covered Rich Thorium Vein", "Mining", 275, 10620 },
  [1618] = { "Peacebloom", "Herbalism", 1, 2447 }, [3724] = { "Peacebloom", "Herbalism", 1, 2447 },
  [1617] = { "Silverleaf", "Herbalism", 1, 765 }, [3725] = { "Silverleaf", "Herbalism", 1, 765 },
  [1619] = { "Earthroot", "Herbalism", 15, 2449 }, [3726] = { "Earthroot", "Herbalism", 15, 2449 },
  [1620] = { "Mageroyal", "Herbalism", 50, 785 }, [3727] = { "Mageroyal", "Herbalism", 50, 785 },
  [1621] = { "Briarthorn", "Herbalism", 70, 2450 }, [3729] = { "Briarthorn", "Herbalism", 70, 2450 },
  [2045] = { "Stranglekelp", "Herbalism", 85, 3820 }, [1622] = { "Bruiseweed", "Herbalism", 100, 2453 },
  [3730] = { "Bruiseweed", "Herbalism", 100, 2453 }, [1623] = { "Wild Steelbloom", "Herbalism", 115, 3355 },
  [1624] = { "Kingsblood", "Herbalism", 125, 3356 }, [2041] = { "Liferoot", "Herbalism", 150, 3357 },
  [2042] = { "Fadeleaf", "Herbalism", 160, 3818 }, [2046] = { "Goldthorn", "Herbalism", 170, 3821 },
  [2043] = { "Khadgar's Whisker", "Herbalism", 185, 3358 }, [2044] = { "Wintersbite", "Herbalism", 195, 3819 },
  [2866] = { "Firebloom", "Herbalism", 205, 4625 }, [142140] = { "Purple Lotus", "Herbalism", 210, 8831 },
  [142141] = { "Arthas' Tears", "Herbalism", 220, 8836 }, [142142] = { "Sungrass", "Herbalism", 230, 8838 },
  [142143] = { "Blindweed", "Herbalism", 235, 8839 }, [142144] = { "Ghost Mushroom", "Herbalism", 245, 8845 },
  [142145] = { "Gromsblood", "Herbalism", 250, 8846 }, [176583] = { "Golden Sansam", "Herbalism", 260, 13464 },
  [176584] = { "Dreamfoil", "Herbalism", 270, 13463 }, [176586] = { "Mountain Silversage", "Herbalism", 280, 13465 },
  [176587] = { "Plaguebloom", "Herbalism", 285, 13466 }, [176588] = { "Icecap", "Herbalism", 290, 13467 },
  [176589] = { "Black Lotus", "Herbalism", 300, 13468 },
}
-- typical materials per gather in Classic, used until you've gathered a node 3 times
G.TYPICAL = { Mining = 2.5, Herbalism = 2 }
G.MIN_OWN = 3

local function skillOf(prof)
  local p = C.char and C.char.prof
  return p and tonumber(p[prof]) or nil
end

-- what one gather of this node gives: { [itemID] = per gather }, measured or estimated
function G.Yield(oid)
  local node = G.NODES[oid]
  local own = C.db and C.db.nodes and C.db.nodes[oid]
  if type(own) == "table" and (own.n or 0) >= G.MIN_OWN and own.items then
    local out = {}
    for id, c in pairs(own.items) do out[id] = c / own.n end
    return out, "your gathers", own.n
  end
  if not node then return nil end
  return { [node[4]] = G.TYPICAL[node[2]] or 2 }, "est.", own and own.n or 0
end

-- your gathering pace: nodes per hour from your farms (nil = not enough yet)
function G.Pace()
  local n, secs = 0, 0
  for _, s in ipairs(C.db and C.db.sessions or {}) do
    if (s.nodes or 0) > 0 and s.start and (s.stop or s.last) then
      n = n + s.nodes
      secs = secs + math.max(0, (s.stop or s.last) - s.start - (s.pausedSecs or 0))
    end
  end
  if n < 10 or secs < 1800 then return nil, n end
  return n / (secs / 3600), n
end

-- every node you can gather now (each profession you have, at or below your skill),
-- scored: { oid, name, prof, skill, value per gather, mats = { {id, per, price, value, spike} },
-- hot = the material on a streak or nil, how }
function G.List()
  local H = C.Hot
  if not H then return {} end
  local out = {}
  for oid, node in pairs(G.NODES) do
    local sk = skillOf(node[2])
    local own = C.db and C.db.nodes and C.db.nodes[oid]
    -- Ooze Covered nodes (Un'Goro, a few dungeons) only once you've gathered one
    if sk and sk >= node[3] and (not node[1]:find("^Ooze") or (type(own) == "table" and (own.n or 0) > 0)) then
      local y, how, n = G.Yield(oid)
      local mats, total = {}, 0
      for id, per in pairs(y or {}) do
        local v, route, sold, listed = H.ItemValue(id)
        local sp = H.Spike and H.Spike(id)
        mats[#mats + 1] = { id = id, per = per, price = v, value = per * v, route = route, sold = sold, listed = listed, spike = sp }
        total = total + per * v
      end
      table.sort(mats, function(a, b) return a.value > b.value end)
      local hot
      for _, m in ipairs(mats) do
        if m.route == "AH" and m.spike and m.spike >= H.SPIKE and total > 0 and m.value / total >= H.SPIKE_SHARE and (not hot or m.spike > hot.spike) then hot = m end
      end
      out[#out + 1] = { oid = oid, name = node[1], prof = node[2], skill = node[3], your = sk, value = total, mats = mats,
        hot = hot, how = how, gathers = n or 0 }
    end
  end
  -- the same node type under two object IDs: keep the one you've gathered more
  local best = {}
  for _, r in ipairs(out) do
    local k = r.name
    if not best[k] or r.gathers > best[k].gathers then best[k] = r end
  end
  local list = {}
  for _, r in pairs(best) do list[#list + 1] = r end
  table.sort(list, function(a, b)
    if (a.hot ~= nil) ~= (b.hot ~= nil) then return a.hot ~= nil end
    return a.value > b.value
  end)
  return list
end

-- "Iron Ore: 300%"
function G.MatText(m, name)
  return string.format("%s: %d%%", name or ("item " .. m.id), math.floor(m.per * 100 + 0.5))
end
