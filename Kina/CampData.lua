-- Kina: farm camps (geographical farms). A camp is one spot with several mob types;
-- the Farms tab shows it as one row whose loot per kill is the mix of its mobs.
-- Spots from WoW Forever guides [F] (games.gg zone guides, IGGM) and a Classic
-- grinding guide [C] (Warcraft Tavern), reviewed by Taylor on 2026-10-17. Mob IDs are
-- from Kina's Wowhead Forever drop data. area = zone ID (for faction territory).
local _, C = ...
C.Data = C.Data or {}
C.Data.camps = {
  { key = "wf-jangolode", name = "Jangolode Mine / Molsen Farm", zone = "Westfall", area = 40, lo = 12, hi = 16, mobs = { 504, 95, 121 }, src = "F",
    note = "\"Best farm for linen and Red Defias Masks; camps respawn fast enough to chain pull\" (games.gg)" },
  { key = "wf-dagger", name = "Dagger Hills Defias", zone = "Westfall", area = 40, lo = 16, hi = 18, mobs = { 122, 121, 449 }, src = "F",
    note = "\"Dense Defias camps\" (games.gg)" },
  { key = "wf-quarry", name = "Gold Coast Quarry / Moonbrook", zone = "Westfall", area = 40, lo = 14, hi = 15, mobs = { 589, 590 }, src = "F" },
  { key = "wf-golems", name = "Saldean's Farm golems", zone = "Westfall", area = 40, lo = 10, hi = 15, mobs = { 114, 36, 480 }, src = "F" },
  { key = "wf-murlocs", name = "Westfall coast murlocs", zone = "Westfall", area = 40, lo = 12, hi = 19, mobs = { 515, 126, 456, 513, 171, 517, 127 }, src = "F",
    note = "Wide level spread: the camp's level is its middle" },
  { key = "wf-riverpaw", name = "Dust Plains gnolls (Riverpaw)", zone = "Westfall", area = 40, lo = 12, hi = 19, mobs = { 117, 500, 123, 501, 124, 452, 98, 453 }, src = "F" },
  { key = "rr-mill", name = "Alther's Mill spiders", zone = "Redridge Mountains", area = 44, lo = 20, hi = 20, mobs = { 505 }, src = "C",
    note = "North of Lake Everstill: Greater Tarantulas (Taylor's farm, 2026-10-17). Use Pin center here at the mill.", near = nil },
  { key = "rr-gnolls", name = "Redridge gnoll camps (west)", zone = "Redridge Mountains", area = 44, lo = 15, hi = 20, mobs = { 712, 423, 424, 426, 430, 446 }, src = "F" },
  { key = "rr-whelps", name = "Black Dragon Whelps", zone = "Redridge Mountains", area = 44, lo = 18, hi = 18, mobs = { 441 }, src = "F",
    note = "\"Respawns fast\" (games.gg)" },
  { key = "rr-blackrock", name = "Blackrock camp (east)", zone = "Redridge Mountains", area = 44, lo = 20, hi = 24, mobs = { 440, 485, 437, 615 }, src = "F" },
  { key = "rr-shadowhide", name = "Shadowhide gnolls", zone = "Redridge Mountains", area = 44, lo = 23, hi = 26, mobs = { 433, 568, 429, 431 }, src = "F",
    note = "Rare Rohh the Silent roams stealthed" },
  { key = "wl-mosshide", name = "Mosshide Fen", zone = "Wetlands", area = 11, lo = 21, hi = 23, mobs = { 1007, 1008, 1009 }, src = "F",
    note = "Farm the outer edge: the center is too dense at 20 (IGGM)" },
  { key = "dw-tranquil", name = "Tranquil Garden Cemetery", zone = "Duskwood", area = 10, lo = 22, hi = 23, mobs = { 48, 203 }, src = "C" },
  { key = "dw-ravenhill", name = "Raven Hill Cemetery", zone = "Duskwood", area = 10, lo = 24, hi = 25, mobs = { 202, 531 }, src = "C" },
  { key = "dw-mistmantle", name = "Manor Mistmantle ghouls", zone = "Duskwood", area = 10, lo = 27, hi = 29, mobs = { 210, 604, 570 }, src = "C" },
  { key = "dw-ogres", name = "Ogre Mound", zone = "Duskwood", area = 10, lo = 26, hi = 31, mobs = { 889, 892, 212 }, src = "C",
    note = "Few recorded loots on Wowhead: rough estimate" },
}
