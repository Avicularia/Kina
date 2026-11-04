-- Kina: Merchant's Favor crates (Azeroth Commerce Authority /
-- Durotar Supply and Logistics). Crates drop in the world and trade on the AH;
-- a crate is filled with ONE bundle from its list and handed in for Favor.
-- Bundle lists: Wowhead Forever item tooltips (Oct 16 2026).
-- Favor per crate: wow-professions.com beta guide (may change at launch).
local _, C = ...

-- [crateID] = { name, favor, bundles = { {itemID, qty}, ... } }
C.Data.crates = {
  [248682] = { "Apprentice Herbs", 5, { {2447, 20}, {765, 20}, {2449, 10}, {785, 10}, {2450, 10} } },
  [248683] = { "Apprentice Ore", 5, { {2770, 20}, {2771, 20} } },
  [248684] = { "Apprentice Textiles", 5, { {2589, 40}, {2318, 20} } },
  [248685] = { "Apprentice Curiosities", 5, { {10940, 20}, {10939, 4}, {10978, 6}, {11084, 2} } },
  [248703] = { "Apprentice Ingots", 5, { {2840, 20}, {3576, 20}, {2841, 10} } },
  [248704] = { "Apprentice Parts", 5, { {4359, 16}, {4361, 16}, {4363, 4} } },
  [248702] = { "Apprentice Fabrics", 5, { {4231, 2}, {2996, 20} } },
  [248686] = { "Journeyman Herbs", 10, { {3820, 10}, {2453, 10}, {3355, 10}, {3369, 10}, {3356, 10} } },
  [248687] = { "Journeyman Ore", 10, { {2775, 10}, {2772, 20} } },
  [248688] = { "Journeyman Textiles", 10, { {2592, 20}, {4306, 40}, {2319, 20} } },
  [248689] = { "Journeyman Curiosities", 10, { {11083, 20}, {11082, 4}, {11138, 6}, {11139, 2} } },
  [248705] = { "Journeyman Fabrics", 20, { {2997, 6}, {4305, 10}, {4233, 2} } },
  [248706] = { "Journeyman Ingots", 10, { {2842, 10}, {3575, 20} } },
  [248707] = { "Journeyman Parts", 10, { {4371, 8}, {4375, 7}, {4382, 4}, {4404, 45} } },
  [248690] = { "Earthly Expert Herbs", 15, { {3357, 20}, {3818, 10}, {3821, 10}, {3358, 10} } },
  [248691] = { "Flowering Expert Herbs", 15, { {3819, 10}, {4625, 10}, {8831, 20}, {8836, 10} } },
  [248692] = { "Expert Ore", 15, { {2776, 10}, {3858, 20} } },
  [248693] = { "Expert Textiles", 15, { {4338, 40}, {4234, 20} } },
  [248694] = { "Expert Curiosities", 15, { {11137, 20}, {11135, 4}, {11177, 6}, {11178, 2} } },
  [248708] = { "Expert Fabrics", 30, { {4339, 8}, {4236, 2} } },
  [248709] = { "Expert Ingots", 30, { {3860, 20}, {3859, 15}, {3577, 10} } },
  [248710] = { "Expert Parts", 30, { {4387, 8}, {10559, 5}, {10560, 12}, {10561, 5} } },
}

-- For each crate: AH price, cheapest bundle (bought), and gold per Favor point.
function C.FavorRows()
  local out = {}
  for crateID, c in pairs(C.Data.crates) do
    local name, favor, bundles = c[1], c[2], c[3]
    local mi = C.MarketItem(crateID)
    local cratePrice = mi and (mi.d or mi.m)
    local best, bestCost, bestOwnValue
    for _, b in ipairs(bundles) do
      local unit = C.BuyCost(b[1])
      if unit then
        local cost = unit * b[2]
        if not bestCost or cost < bestCost then
          best, bestCost = b, cost
          bestOwnValue = (select(2, C.BestRoute(b[1], b[2])) or 0) * b[2]
        end
      end
    end
    local total = (cratePrice or 0) + (bestCost or 0)
    out[#out + 1] = {
      id = crateID, name = name, favor = favor, crate = cratePrice, crateNet = cratePrice and math.floor(cratePrice * (1 - C.settings.ahCut)),
      bundleID = best and best[1], bundleQty = best and best[2], bundleCost = bestCost, ownMatsValue = bestOwnValue,
      perFavor = (cratePrice and bestCost) and (total / favor) or nil,
      listed = mi and mi.q or 0,
    }
  end
  table.sort(out, function(a, b)
    if a.perFavor and b.perFavor then return a.perFavor < b.perFavor end
    return a.perFavor ~= nil
  end)
  return out
end

-- Is this item a Waylaid Crate? (used to explain crate drops in farm rows)
function C.IsCrate(id) return C.Data.crates[id] ~= nil end
