-- Kina: reference data. Classic values are PRIORS: the engine uses them
-- until your own observations replace them, and always labels which one it used.
local _, C = ...
local D = {}
C.Data = D

-- Disenchanting, uncommon (green) gear, by REQUIRED level (the "Requires Level"
-- line). Source: wow-professions.com/forever/disenchanting-guide (WoW Forever).
-- Odds per that guide: armor 75% dust / 20% essence / shard "rarely (3-5%)";
-- weapons the other way round. Kina uses 5% (dust + essence = 95%). Levels 1-10
-- give no shard, so their 75/20 is scaled to 80/20.
-- {lo, hi, dust, essence, shard, dustMin, dustMax, essMin, essMax, armorPct{dust,ess,shard}, weaponPct{...}}
D.deSource = "Forever guide table"
D.deGreen = {
  {1, 10,  10940, 10938, nil,   1, 2, 1, 2, {.80, .20, 0},   {.21, .79, 0}},   -- Strange Dust, Lesser Magic Essence
  {11, 15, 10940, 10939, 10978, 2, 3, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Greater Magic Essence, Small Glimmering Shard
  {16, 20, 10940, 10998, 10978, 4, 6, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Lesser Astral Essence
  {21, 25, 11083, 11082, 11084, 1, 2, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Soul Dust, Greater Astral, Large Glimmering
  {26, 30, 11083, 11134, 11138, 2, 5, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Lesser Mystic, Small Glowing
  {31, 35, 11137, 11135, 11139, 1, 2, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Vision Dust, Greater Mystic, Large Glowing
  {36, 40, 11137, 11174, 11177, 2, 5, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Lesser Nether, Small Radiant
  {41, 45, 11176, 11175, 11178, 1, 2, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Dream Dust, Greater Nether, Large Radiant
  {46, 50, 11176, 16202, 14343, 2, 5, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Lesser Eternal, Small Brilliant
  {51, 55, 16204, 16203, 14344, 1, 2, 1, 2, {.75, .20, .05}, {.20, .75, .05}}, -- Illusion Dust, Greater Eternal, Large Brilliant
  {56, 63, 16204, 16203, 14344, 2, 5, 1, 3, {.75, .20, .05}, {.20, .75, .05}}, -- (Nexus Crystal also possible: not counted)
}
-- Rare (blue), by REQUIRED level: the guide says "Shard 100%; Crystal about 0.5%",
-- the shard being the one in the green table's band. Levels 1-10 have no shard in
-- that table: Kina uses Small Glimmering (the lowest shard).
-- {lo, hi, shard, pShard, nexus, pNexus}
D.deRare = {
  {1, 20, 10978, 1}, {21, 25, 11084, 1}, {26, 30, 11138, 1}, {31, 35, 11139, 1},
  {36, 40, 11177, 1}, {41, 45, 11178, 1}, {46, 50, 14343, 1}, {51, 63, 14344, .995, 20725, .005},
}
-- Epic (purple), by ITEM level. The Forever guide only says "level 50 and below:
-- shard 100%, high level: crystal 100%" with no amounts: the amounts here are
-- Classic's (shown as "Classic table" in tooltips). {lo, hi, material, min, max}
D.deEpic = {
  {40, 45, 11177, 2, 4}, {46, 50, 11178, 2, 4}, {51, 55, 14343, 2, 4}, {56, 60, 20725, 1, 1}, {61, 65, 20725, 1, 2},
}
-- Enchanting skill needed to disenchant, by item level: TBC and later only. Forever
-- (like original Classic) has no gate, per the Forever disenchanting guide, so
-- deSkillGate is off and this table is unused.
D.deSkillGate = false
D.deSkill = { {20, 1}, {25, 25}, {30, 50}, {35, 75}, {40, 100}, {45, 125}, {50, 150}, {55, 175}, {60, 200}, {65, 225} }

-- Known undisenchantable gear (crafted enchanter wands). Kina also LEARNS
-- this list: whenever the game refuses a disenchant, that item is added.
D.noDE = { [11287] = true, [11288] = true, [11289] = true, [11290] = true, [5387] = true, [4614] = true }

-- Coin per kill prior for humanoids by mob level (copper). Rough Classic shape;
-- replaced by your own looted coin as soon as you have 20+ kills of a mob.
function D.CoinPrior(level, creatureType)
  if not level or level < 1 then return 0 end
  if creatureType and creatureType ~= "Humanoid" and creatureType ~= "Undead" and creatureType ~= "Demon" then
    return 0
  end
  return math.floor(0.30 * level * level + 2 * level)
end

-- (Launch price decay removed in 0.9.5: it came from Classic launches, not Forever.)
D.launchDecay = {}

-- Seed stockpile ideas (editable with /kina stock). Prices in copper.
D.stockSeeds = {
  [249428] = { buyUnder = 600, sellAt = 9000,
    note = "Pristine Hide: unusable until Leatherworking 175-225; dumped near vendor price early, needed by every LW leveling the Merchant's Favor sets." },
}

-- Forever "Scarce" materials (icy-veins.com/wow-forever news; warcrafttavern.com/forever
-- herbalism and skinning guides): a bonus chance when gathering or skinning. No source
-- gives a drop rate, so Kina does not add them to profession values; they are listed
-- here for highlighting. Also named by those guides (IDs not known yet): Rosecap,
-- Stranglevine (herbs), Pristine Scale, Fel Hide, Fel Leather (skinning), Bauxite
-- and Pitchblende (datamined, mining); new herbs Marefoil, Demonsage, Death Lotus.
D.scarce = { [249427] = "Pristine Leather", [249428] = "Pristine Hide", [249399] = "Frilled Lichen", [249391] = "Pyrite" }

-- Spells used to classify loot windows.
D.pickPocket = { [921] = true }
D.skinning = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
D.disenchant = { [13262] = true }
