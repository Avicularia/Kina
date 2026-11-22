-- Kina 1.1.0: the season. Every number the progression uses lives here, so a new
-- season is a new copy of this file (Taylor: "each season's cosmetics achievable",
-- Season 1 light for adoption, Season 2 bigger). Solved with the balance model
-- (Nov 18, 2026): a player with every bonus maxes everything in ~100 synced hours;
-- an average player ~175 h; no bonuses at all ~415 h.
local _, C = ...
C.Season = {
  id = "S1", name = "Season 1", year = 2026,
  hours = 100,                      -- full-bonus target for the whole season
  masterTitle = "Master of Coin 2026",

  -- Renown: 10 ranks. Titles go after the name ("Deputize the Prospector").
  -- Colors follow item quality, like the Bond crests.
  ranks = {
    { at = 0,      title = "the Wanderer",       q = "poor" },
    { at = 700,    title = "the Scavenger",      q = "common" },
    { at = 3800,   title = "the Forager",        q = "uncommon" },
    { at = 10000,  title = "the Pathfinder",     q = "uncommon" },
    { at = 23100,  title = "the Prospector",     q = "rare" },
    { at = 45700,  title = "the Fortune Seeker", q = "rare" },
    { at = 82300,  title = "the Gilded",         q = "epic" },
    { at = 128000, title = "the Goldwarden",     q = "epic" },
    { at = 181400, title = "the Hoardlord",      q = "legendary" },
    { at = 249100, title = "the Everlasting",    q = "artifact" },
  },
  -- Kina levels I-XX (same points as Renown, faster early levels for the dopamine)
  levels = { 0, 370, 1110, 2230, 3820, 6370, 9980, 14790, 20930, 28530, 37380, 49310,
    63910, 81040, 101560, 125360, 151980, 181440, 213850, 249120 },

  -- earning
  perMinute = 10,                   -- renown and Kina XP per active minute, at pace 1
  activeWindow = 180,               -- a minute is active with a kill/loot/gather in the last 3 min
  pace = { min = 0.5, max = 3 },    -- gold per hour (per person) vs the target for your level
  bonus = {
    partyEach = 0.05, partyMax = 0.20,        -- per other Kina in the farm
    streakDay = 0.02, streakMax = 0.20,       -- days in a row
    campfire = 0.10,                          -- while "Camp Benefits" is on you
    commend = 0.10,                           -- each commendation for that farm
    trackLevel = 0.01,                        -- every level of every track, this season
  },
  campfireAuras = { [1229741] = true },       -- Camp Benefits (as Happy Camper knows it)
  campfireNames = { "camp benefits" },

  -- tracks (each: one number, and a ladder). Gold is in gold, not copper.
  tracks = {
    { id = "ring",   name = "Portrait ring", stat = "renownRank" },
    { id = "stars",  name = "Mentor star",   stat = "recruits", tiers = { 1, 2, 3, 4, 5 } },
    { id = "bond",   name = "Bond crest",    stat = "bondLevel" },
    -- (Hot mob cards: not in Season 1 yet; 30 / 75 / 150 / 300 / 600 kills when they come)
    { id = "banner", name = "Farm banner",   stat = "hours", tiers = { 0.5, 2.5, 7.5, 15, 30, 50, 75, 100 } },
    -- PLACEHOLDER gold amounts until Kina's own farm data sets them (Taylor: normal 1-60,
    -- then steeply higher ranks)
    { id = "hoard",  name = "Coin hoard",    stat = "gold", tiers = { 1, 3, 8, 20, 40, 65, 75, 100, 150, 200 } },
  },
  -- the season's 20 card mobs (a fixed list, so rotating the hot list never strands a
  -- card). Until Taylor picks them, the current hot list stands in.
  cardMobs = nil,
}

-- gold per hour (copper) a typical group earns at a level: the pace target (pace 1.0).
-- Approved Nov 21 (tentative; reviewed every other Friday). Levels 1-44 from Wowhead
-- Forever drop rates priced at the Realm 5 AH, checked against Taylor's 42 hours of farms
-- (212c a kill, about 50 kills an hour): 1004 x level^0.726. No data above 44 yet: level 60
-- is a set 10g/h, and 45-59 rise smoothly to it.
function C.Season.Target(level)
  level = math.max(1, math.min(60, level or 1))
  if level >= 60 then return 100000 end
  if level <= 44 then return math.floor(1004 * level ^ 0.726) end
  local c44 = 1004 * 44 ^ 0.726
  return math.floor(c44 * (100000 / c44) ^ ((level - 44) / 16))
end
