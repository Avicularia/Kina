local ADDON, C = ...
-- Kina: the Help tab, "How Kina works" (0.9.1). Topics down the left, the words on the
-- right. Plain data: edit TOPICS to change, add or remove a topic. The numbers match
-- Rep.lua / Payout.lua / Vouch.lua / Rules.lua: change them here too if a rule changes.
local G, GR, R = "|cffffc54a", "|cff9d9d9d", "|cffff6a50"
local function H(s) return "\n" .. G .. s .. "|r\n" end

local TOPICS = {
  { "What Kina is",
    "Kina is a gold companion for WoW Forever. It does four things:\n\n"
    .. G .. "Hot mobs.|r The Hot Farms tab lists the mobs worth far more per kill than anything else at their level. "
    .. "They carry a grey logo on their nameplates that lights up for you at 30 kills, with what they pay you.\n\n"
    .. G .. "Your gold per hour.|r Press Start and the widget tracks gold, loot, kills and XP per hour, "
    .. "every item at its best price, with AH prices shared by every Kina on the realm.\n\n"
    .. G .. "Farming with friends.|r Kina users who join a farm share one log, and everyone gets credit for the whole "
    .. "group's loot. Kina shows each player's fair share.\n\n"
    .. G .. "Your name.|r Your " .. G .. "Kina level|r (I to XX) and " .. G .. "Renown|r rank grow as you farm with other "
    .. "Kinas. Both are on your profile, with your title and the cosmetics you've earned.\n\n"
    .. GR .. "Kina is free. It never asks for money and never sells anything.|r" },

  { "Hot mobs",
    H("The list") .. "Hot mobs are chosen by the Kina team and change as often as the market does. Hot Farms shows "
    .. "where each spawns; click one for a waypoint to the thickest spot.\n"
    .. H("Lighting one up") .. "A hot mob's logo stays grey until you've killed it " .. G .. "30 times|r. Then it lights up, "
    .. "with your own gold per kill on its nameplate.\n"
    .. H("The archive") .. "Mobs that come off the list wait in Hot Farms > Archive with your kills, gold per kill, "
    .. "total gold and card. Cards only level up while the mob is hot.\n"
    .. H("Why it's hot") .. "The list shows the drop that pays most and its " .. G .. "drop chance|r (\"Tiger Meat: 57% drop chance\"). "
    .. "Click a mob for the full story, including " .. G .. "What changed|r: when it became hot, the top drop's price today "
    .. "against its usual price over the last two weeks (a " .. G .. "price spike|r, or a steady price), and the recipes it's used in.\n"
    .. H("The nameplate badge") .. "Hot mobs carry the Kina logo beside their name. It works with Blizzard's nameplates and with "
    .. "nameplate addons such as Threat Plates, and finds its place again when you hover or target the mob. Turn it off in Settings." },

  { "AH prices",
    "Kina prices every item from auction house scans: yours, your group's and guild's, and every Kina on the realm.\n\n"
    .. "- A realm-wide price only counts when " .. G .. "several Kinas agree|r, so one bad scan can't move it.\n"
    .. "- Scan by opening the AH and clicking the bar at the bottom of Kina. The game allows one scan every 15 minutes.\n"
    .. "- Hover the bar to see whose scans Kina has and what's syncing.\n"
    .. "- Turn off sharing in Settings: \"Share AH prices with every Kina\"." },

  { "Farming together",
    H("Starting") .. "Press Start on the widget. Kina users in your group get an invite: Join or No thanks. Nobody is put in a farm "
    .. "without clicking Join. A roster shows who's in, who said no and who hasn't answered. Everyone who joins shares one "
    .. "farm log, so every widget shows the same numbers. Anyone in the farm can end it for everyone.\n"
    .. "- Said no? Your widget doesn't track the group's farm, and you can't start your own until it ends.\n"
    .. H("What counts") .. "- A farm counts for Kina level and Renown after " .. G .. "15 minutes|r. Paused time doesn't count.\n"
    .. "- If anyone in the farm is " .. R .. "under level 10|r at any point, the farm gives no progression. The split still works.\n"
    .. "- A solo farm runs until you press Stop (time logged off doesn't count). A group farm stops itself "
    .. G .. "an hour after its last kill|r, and counts as ending at that kill.\n"
    .. H("Leaving and coming back") .. "Leave the group, reload, or disconnect mid-farm and you stay in the farm. Back in the group, "
    .. "your widget shows " .. G .. "SYNCING|r while it catches up, then the same numbers as everyone else. What you looted while "
    .. "out counts once. If you were away " .. G .. "2+ minutes|r, loot from that time isn't shared either way. If whoever started "
    .. "the farm leaves, the next player takes over and nothing is lost.\n"
    .. H("Fixing the log") .. "Right-click a partner's item on the Session page to leave it out, or to dispute its price "
    .. "(it then counts at its vendor price for everyone; disputes are logged). You can't leave out your own loot: a partner can." },

  { "The split",
    "When a group farm ends, Kina shows each player's fair share of what the group looted, so you can split it however "
    .. "you like. Nobody owes anybody: Kina doesn't keep debts.\n\n"
    .. "Each item counts at its best price: auction house, vendor or disenchant. Coin isn't part of it: the game already "
    .. "splits coin.\n"
    .. H("Your credit") .. "Everyone in the farm gets credit for " .. G .. "everything the group looted|r: Renown, "
    .. "gold farmed, card kills and the leaderboards all count the whole group's loot." },

  { "Commendations",
    "At the end of a qualifying farm a window asks how your partners did. It stays until you press Done; then that farm's "
    .. "commendations are closed.\n\n"
    .. "- Up to " .. G .. "2 thumbs up|r per farm. Each one gives that player " .. G .. "+10% Renown|r for that farm.\n"
    .. "- " .. R .. "Thumbs down|r for as many as deserve one. They show on the player's profile.\n"
    .. "- Never both to the same person, never to yourself or your own characters.\n"
    .. "- Only players who were in that farm with you can commend you for it." },

  { "Renown",
    "Renown come from farming with other Kinas. A farm counts only when another Kina confirmed it: "
    .. "solo farms track your gold but earn nothing.\n"
    .. H("Earning") .. "- " .. G .. "10 points a minute|r while you're active (a kill, loot or gather in the last 3 minutes).\n"
    .. "- Times your " .. G .. "pace|r: the group's gold per person per hour against the usual for your level, 0.5x to 3x.\n"
    .. "- Plus your bonuses, which all add up: party (+5% per other Kina, up to +20%), streak (+2% a day in a row, up to "
    .. "+20%), campfire (+10% while Camp Benefits is on you), +1% for every track level this season, and +10% for each "
    .. "commendation for that farm.\n"
    .. "- Quest gold, quest XP and quest items never count.\n"
    .. H("Streak") .. "Miss a day and it's halved; miss the next one too and it's gone. Two days in a row at half brings it back. "
    .. "Your streak carries into every new season: a season never resets it.\n"
    .. H("Ranks") .. "Ten ranks from the Wanderer to the Everlasting, each a title in its quality color. Each season starts "
    .. "every track and its bonus over; your cosmetics and titles stay." },

  { "Season 1 Cosmetics", "", guide = true },
  -- 1.0.6: write to the developer (Feedback.lua builds the page)
  { "Feedback", "", feedback = true },

  -- 1.0.6
  { "Controller",
    "Turn on gamepad mode in the game's options and Kina's windows work with the controller too.\n\n"
    .. H("In a Kina window") .. "D-pad: move between buttons (lists and long pages scroll along).   A: press.   B: back / close.\n"
    .. "X: show what pointing the mouse at it would show.   Y: the right-click action.   LB / RB: previous / next tab.\n"
    .. "On a slider, D-pad left / right changes it.\n\n"
    .. H("Outside Kina") .. "Kina only takes the controller while one of its windows is open and you're out of combat. "
    .. "A fight starting hands every button straight back to the game.\n\n"
    .. H("Key bindings") .. "Options > Key Bindings > Kina: open / close Kina, Start / stop farm, Scan the auction house, "
    .. "Open Hot Farms, and a waypoint to the nearest hot mob. Put them on controller buttons.\n\n"
    .. H("Window size") .. "Settings has Window size buttons, so you never have to drag the corner. "
    .. "Turn the controller part off in Settings if you use another controller addon." },

  { "Your rank",
    "Your rank is your Renown rank, 1 to 10: it's the number on the plate under your portrait ring and the title after your name. "
    .. "Renown never goes down and comes from farms another Kina confirmed: 10 a minute while you're active, "
    .. "times your pace for your level, plus your bonuses. See Renown for the details." },

  { "Profiles",
    "Your profile (the You tab) shows your portrait in your ring (its number is your Renown rank), your rank title, the gold plate "
    .. "and your farming record. Commendations and Farm stats show who you farm with most.\n\n"
    .. "Click a party portrait under the widget, or any name, for that player's profile: the same layout, with "
    .. "what their Kina last told yours.\n\n"
    .. H("One profile per realm") .. "Each realm is its own community, so each has its own Kina profile: Kina level, Renown "
    .. "and record. All your characters on a realm share it. On a new realm you start fresh; your other realm's profile "
    .. "is kept and comes back when you play there.\n"
    .. H("Installs shared") .. "When a new player installs Kina because of you, it counts on your profile and earns you a "
    .. G .. "mentor star|r (1, 5, 10, 20 and 50 installs). It counts once their Kina has done its first farm of "
    .. G .. "15 minutes|r or more. To share Kina, press " .. G .. "Share Kina|r on the You tab (or " .. G .. "/kina share|r): the download "
    .. "link goes to party chat and a box opens with the link ready to copy (" .. G .. "/kina link|r any time). Players in your party "
    .. "without Kina show a plain rim and a Kina " .. G .. "+|r coin under the widget: click one to share Kina with them. When a new "
    .. "player's Kina first meets Kina users, it asks them " .. G .. "who showed them Kina|r: they pick from the Kina users in their "
    .. "party and those they met in the last 7 days (whoever shared the link is highlighted). Your own characters never count, "
    .. "and each new player counts once.\n"
    .. H("Tracker only") .. "Just want the gold-per-hour tracker? Turn on " .. G .. "Tracker only|r in Settings. Kina still tracks "
    .. "every farm, but you don't join group farms, so you earn no Renown. Every Kina in your group "
    .. "is told.\n"
    .. H("Partners") .. "Pick one Kina user as your Partner (it takes both of you: one asks, the other accepts). Partners earn "
    .. G .. "+10% Renown|r on farms together (your partner in the farm when it ends). "
    .. "The bond grows with the " .. G .. "gold you farm together|r (scaled to your level, longer farms count a bit extra), up to " .. G .. "+20%|r. Your partner's portrait shows a bond crest: Uncommon, Rare, Epic, then Legendary, with 1 to 5 gems for the level (20 levels, +0.5% each). Your bond with each person is "
    .. "kept, so going back to an old partner picks up where you left off. Kina asks when a Kina user joins your party and you have "
    .. "no partner; end it from their profile or " .. G .. "/kina partner end|r.\n\n"
    .. GR .. "Other players' Renown is what their Kina reports. If someone's Kina level ever goes DOWN, their record was "
    .. "wiped or swapped, and their profile says so.|r" },

  { "Your record",
    "The Record box on your profile. Hover a row for the details.\n"
    .. H("Your name") .. "Profiles and the leaderboard show full WoW Forever names, " .. G .. "first name and surname|r. Kina learns "
    .. "yours the first time your Kina hears itself on the Kina network, and other players' from their Kina messages; until then "
    .. "it shows the first name.\n"
    .. H("Hours farmed") .. "Every farm of " .. G .. "15 minutes|r or more that Kina logged, clock time minus pauses: all time, "
    .. "and this season in brackets. Hover it for group and solo hours.\n"
    .. H("Gold per hour") .. "One number: " .. G .. "your own share|r (what you looted and were paid) per hour, on your best farm "
    .. "of 15+ minutes this season. It's the banner's number too.\n"
    .. H("Kina high score") .. "Your best farm ever, marked " .. G .. "(solo)|r or " .. G .. "(group)|r. Click it to open that farm.\n"
    .. H("Bonus now") .. "The Renown bonus you have right now: your streak plus +1% per track level. Hover it for the full list, "
    .. "including the bonuses a farm adds (party, campfire, your Kina Partner, commendations).\n"
    .. H("Track levels") .. "Levels reached across every track this season, out of the total (\"12 / 28\"). Every one is +1% "
    .. "Renown; all of them earns the season's " .. G .. "Master of Coin|r title." },

  { "Professions",
    "Hover a profession on your profile to see what it has earned: all time, this season, how many farms and your best farm.\n\n"
    .. "Kina counts what " .. G .. "gathering|r brings in during your farms: mining, herbalism, skinning, fishing, lockpicking "
    .. "and pick pocketing, at today's prices. Crafting isn't counted yet.\n\n"
    .. "Each farm has its own split: the " .. G .. "Professions|r column on the Session tab, and a line per profession in "
    .. "the farm's log. Type a profession in the search box to find every farm it earned in." },

  { "Leaderboard",
    "You > " .. G .. "Leaderboard|r lists every Kina player any Kina has heard of, with the last numbers seen for them: "
    .. "Renown, gold per hour and gold farmed this season.\n"
    .. H("How it fills in") .. "Every Kina says its own numbers on the Kina network every 10 minutes, and passes on a few "
    .. "it knows about others. So players you've never met still show up, and the newest numbers always win.\n"
    .. H("Who said it") .. "\"Numbers from\" says how old they are and where they came from: " .. G .. "their Kina|r (first-hand) "
    .. "or " .. G .. "via|r another player (passed on). Passed-on numbers can't be checked.\n"
    .. H("Using it") .. "Click a column title to rank by it. Type a name or title in the search box. Click a row for "
    .. "that player's profile.\n"
    .. H("Leaving it") .. "Turn data sharing off in Settings and your Kina tells the others to hide you." },

  { "Prices",
    "The Prices window is an auction house browser that works anywhere, from every Kina's latest scan. "
    .. "Open it with the Prices button, or type " .. G .. "/kp|r. " .. G .. "/kp copper ore|r (or /kp and a shift-clicked item) "
    .. "opens it searching for that. It always opens in front of Kina's window.\n\n"
    .. GR .. "Kaydee's Pockets also uses /kp. Kina takes it over when you log in; Kaydee's Pockets keeps /pockets.|r" },

  { "Shared drop data",
    "Every Kina records what each mob drops for its player (kills, coin, every item, skins) and shares it with every other "
    .. "Kina: with your party and guild, and realm-wide on the " .. G .. "Kina network|r. Kina adds everyone's kills together, "
    .. "and passes on what it heard, so you get data from players who were never online with you.\n"
    .. H("What it changes") .. "Once a mob has 100+ looted kills between all Kina players, the hot list uses those drop chances "
    .. "instead of Wowhead's; a mob with no Wowhead data is ranked from 30.\n"
    .. H("Which drops count") .. "Materials and other drops count toward a mob's gold per kill at an " .. G .. "8%+|r drop chance. "
    .. "Recipes count at " .. G .. "2%+|r, or at 1.5%+ when the recipe is worth 10 gold or more. Gear and crates never count. "
    .. "Mobs where a recipe matters say " .. G .. "recipe|r in \"Why it's hot\".\n"
    .. GR .. "Turn data sharing off in Settings and Kina neither records nor shares your drops.|r" },

  { "Two auction houses",
    "WoW Forever has two auction houses: your faction's (Stormwind, Ironforge) and the cross-faction one in " .. G .. "Booty Bay|r "
    .. "(Gadgetzan and Everlook count as the same one). Kina keeps their prices apart: a scan goes into the book of the house "
    .. "you scanned at, and Kinas share Booty Bay scans on the Kina network too.\n"
    .. H("Which price counts") .. "While a Booty Bay scan is under " .. G .. "30 minutes|r old, an item's auction price everywhere "
    .. "(tooltips, the widget, farms) is the better of the two houses, after each house's cut. After that, your faction's house "
    .. "only. Booty Bay takes 15% (until a sale shows otherwise), so Kina counts a sale there " .. G .. "10% lower|r.\n"
    .. H("Tooltips") .. G .. "Auction price (Booty Bay)|r or " .. G .. "(Stormwind)|r: what a sale keeps at the winning house, "
    .. "after its cut and the deposit you'd lose if it doesn't sell." },

  { "My bags",
    "Prices > " .. G .. "My bags|r lists everything in your bags with your faction's AH, Booty Bay's AH, the vendor and "
    .. "disenchanting side by side. The best one is " .. G .. "green|r. A gold line says when an item is worth carrying to the "
    .. "other house (\"buy up to 1s 09c in SW > BB\"). The button at the top switches between one house and both.\n"
    .. H("Selling") .. "At an auctioneer, press " .. G .. "Sell to Stormwind|r (or " .. G .. "Sell to Booty Bay|r at Booty Bay), "
    .. "then " .. G .. "Post next|r. Kina asks the auction house for the item's lowest price right now and posts at exactly "
    .. "that, then moves down the list. Click any row to start there. Type in the box to post fewer than you have. "
    .. "2h, 8h and 24h set how long it's listed.\n"
    .. H("Safe by design") .. "Kina never posts an item for less than the vendor or disenchanting would pay; it says "
    .. "\"won't post\" and moves on. Every post is your click.\n"
    .. GR .. "ForeverForge Auction also posts through the auction house window, so use one or the other: Settings > Auction "
    .. "house selling turns Kina's off.|r" },

  { "Transport",
    "When both houses have a scan under 30 minutes old (yours or another Kina's), Kina says " .. G .. "Transport tab available|r. "
    .. "Prices > " .. G .. "Transport|r then lists what's worth carrying from one house to the other: \"Copper Ore  SW > BB  buy "
    .. "under 1s 09c\". Hover a line for the details.\n"
    .. H("Buy under") .. "The most to pay and still make 10% after the other house's cut.\n"
    .. H("Only a few worth it") .. "Fewer than 20 are listed cheaply enough; hover to see each price step and where it stops paying.\n"
    .. H("Sells slowly") .. "Items that make money on paper but sell under 1.5 an hour there are kept on their own list.\n"
    .. H("How long") .. "The tab stays open for 30 minutes from the older of the two scans. Scanning both again keeps it open." },

  { "The window",
    "Drag Kina's " .. G .. "right edge|r to make it wider and its " .. G .. "bottom edge|r to make it taller: everything stays "
    .. "the same size and you see more (long text stops being cut off). The corner grip still scales everything together. "
    .. "Kina remembers the size.\n"
    .. H("The farm widget") .. "Settings > Window > " .. G .. "Widget opacity|r makes the widget see-through (20% to 100%). "
    .. "It turns solid while your mouse is over it." },

  { "Staying up to date",
    "When a newer Kina is out, the widget shows " .. G .. "Update available|r. Click it for the link.\n\n"
    .. "When someone in your group runs a newer Kina, yours stops earning XP and Renown until you update "
    .. "and /reload. It never happens in the middle of a farm.\n\n"
    .. "To update: update Kina in the CurseForge app (or download it from CurseForge and replace the Kina folder in "
    .. "Interface\\AddOns), then /reload." },

  { "Fair play",
    "Kina only believes what it can check:\n"
    .. "- A commendation only counts from someone who was in that farm with you.\n"
    .. "- Only the farm leader can re-price a farm.\n"
    .. "- A farm only earns Renown when another Kina confirmed it.\n"
    .. "- Shared auction prices that are far from your own scan are ignored.\n"
    .. "- An edited or damaged Kina file shows Kina level I.\n\n"
    .. GR .. "No add-on can be completely cheat-proof. Renown on other players' profiles is what their Kina reports.|r" },

  { "Commands",
    G .. "/kina|r  open or close Kina\n"
    .. G .. "/kina tour|r  replay the welcome tour\n"
    .. G .. "/kina help|r  this page\n"
    .. G .. "/kina widget|r  show or hide the widget\n"
    .. G .. "/kina profile Name|r  someone's Kina profile\n"
    .. G .. "/kina pardon|r  the one-time pardon, if you put it off\n"
    .. G .. "/kina share|r  post Kina's download link in party chat\n"
    .. G .. "/kina partner|r  your Kina Partner (name to ask, end to stop)\n"
    .. G .. "/kina start|r, " .. G .. "/kina stop|r  start or stop a farm\n"
    .. G .. "/kina scan|r  scan the auction house\n"
    .. G .. "/kp|r  open Prices (" .. G .. "/kp name|r to search)" },
}
C.HelpTopics = TOPICS

if not C.RegisterPanel then return end
C.RegisterPanel("help", function(p)
  local K = C.SheetKit
  local nav = K.box(p); nav:SetPoint("TOPLEFT", 0, 0); nav:SetPoint("BOTTOMLEFT", 0, 0); nav:SetWidth(190)
  local page = K.box(p); page:SetPoint("TOPLEFT", nav, "TOPRIGHT", 10, 0); page:SetPoint("BOTTOMRIGHT", 0, 0)
  local head = K.text(nav, "GameFontNormal"); head:SetPoint("TOPLEFT", 14, -12)
  if C.Cos and C.Cos.Font then C.Cos.Font(head, 15, "") end
  head:SetTextColor(1, 0.78, 0.34); head:SetText("How Kina works")
  local sel = 1
  local btns = {}
  local title = K.heading(page, "")
  title:SetPoint("TOPLEFT", 16, -14)
  local sf = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -48); sf:SetPoint("BOTTOMRIGHT", -30, 12)
  local child = CreateFrame("Frame", nil, sf); child:SetSize(400, 400); sf:SetScrollChild(child)
  local body = C.Text(child, "OVERLAY", "GameFontHighlight"); body:SetPoint("TOPLEFT", 0, 0)
  body:SetJustifyH("LEFT"); body:SetJustifyV("TOP"); if body.SetSpacing then body:SetSpacing(3) end
  if body.SetWordWrap then body:SetWordWrap(true) end
  local function show(i)
    sel = i
    for j, b in ipairs(btns) do if j == i then b:LockHighlight() else b:UnlockHighlight() end end
    title:SetText(TOPICS[i][1])
    local w = math.max(300, (page:GetWidth() or 560) - 60)
    child:SetWidth(w); body:SetWidth(w)
    if not TOPICS[i].feedback and C.Feedback then C.Feedback.Hide() end
    if TOPICS[i].feedback and C.Feedback then
      if C.SeasonGuide then C.SeasonGuide.Hide() end
      body:SetText(""); body:Hide()
      local ok, h = pcall(C.Feedback.Show, child, w)
      child:SetHeight((ok and h or 300) + 20)
    elseif TOPICS[i].guide and C.SeasonGuide then
      body:SetText(""); body:Hide()
      local ok, h = pcall(C.SeasonGuide.Show, child, w)
      child:SetHeight((ok and h or 300) + 20)
    else
      if C.SeasonGuide then C.SeasonGuide.Hide() end
      body:Show(); body:SetText(TOPICS[i][2])
      child:SetHeight((body:GetStringHeight() or 300) + 20)
    end
    if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
  end
  for i, t in ipairs(TOPICS) do
    local b = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(b) end
    b:SetSize(162, 22); b:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 26); b:SetText(t[1])
    b:SetScript("OnClick", function() show(i) end)
    btns[i] = b
    if t.guide then
      -- 1.0.8 (Taylor: the same glow the Exalted ring has): a warm gold halo that breathes
      local P = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Cos\\"
      local h1 = nav:CreateTexture(nil, "BACKGROUND"); h1:SetTexture(P .. "fx_halo"); h1:SetBlendMode("ADD")
      h1:SetVertexColor(1, 0.76, 0.30, 0.75); h1:SetPoint("CENTER", b, "CENTER"); h1:SetSize(162 * 1.35, 22 * 2.6)
      local h2 = nav:CreateTexture(nil, "BACKGROUND"); h2:SetTexture(P .. "fx_halo2"); h2:SetBlendMode("ADD")
      h2:SetVertexColor(1, 0.95, 0.78, 0.5); h2:SetPoint("CENTER", b, "CENTER"); h2:SetSize(162 * 1.15, 22 * 1.7)
      local tk = 0
      b:HookScript("OnUpdate", function(_, el)
        tk = tk + el
        local a = 0.75 + 0.25 * math.sin(tk * 2 * math.pi / 2.4)
        h1:SetAlpha(a); h2:SetAlpha(a)
      end)
    end
    if t.feedback then p.fbBtn = b end
  end
  local tour = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(tour) end
  tour:SetSize(162, 26); tour:SetPoint("BOTTOMLEFT", 14, 14); tour:SetText("Replay the tour")
  tour:SetScript("OnClick", function() if C.Tour then C.Tour.Start() end end)
  -- 1.0.5: what's new in the latest big update, any time
  local wn = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(wn) end
  wn:SetSize(162, 26); wn:SetPoint("BOTTOMLEFT", tour, "TOPLEFT", 0, 6); wn:SetText("What's new")
  wn:SetScript("OnClick", function() if C.WhatsNew then C.WhatsNew.Show() end end)
  p.refresh = function()
    -- 1.0.6: the Feedback button says when the developer is online, or that an answer waits
    if p.fbBtn and C.Net and C.Feedback then
      local unread = C.Feedback.Unread()
      p.fbBtn:SetText(unread > 0 and ("|cffff4040*|r Feedback (" .. unread .. ")")
        or (C.Net.DevOnline() and not C.Net.IAmDeveloper() and "Feedback |cff3fd03f(dev online)|r" or "Feedback"))
    end
    if C.helpWant then
      for i, t in ipairs(TOPICS) do if t[1] == C.helpWant then sel = i end end
      C.helpWant = nil
    end
    show(sel)
  end
  p.show = show
end)
-- open Help at a topic by its title
function C.ShowHelpTopic(name) C.helpWant = name; if C.Refresh then C.Refresh() end end
