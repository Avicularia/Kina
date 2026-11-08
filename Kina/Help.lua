local _, C = ...
-- Kina: the Help tab, "How Kina works" (0.9.1). Topics down the left, the words on the
-- right. Plain data: edit TOPICS to change, add or remove a topic. The numbers match
-- Rep.lua / Payout.lua / Vouch.lua / Rules.lua: change them here too if a rule changes.
local G, GR, R = "|cffffd100", "|cff9d9d9d", "|cffff6a50"
local function H(s) return "\n" .. G .. s .. "|r\n" end

local TOPICS = {
  { "What Kina is",
    "Kina is a farming partner for WoW Forever. When Kina users farm together, every Kina keeps the same record of "
    .. "the loot, splits it evenly, and keeps track of who owes whom until it's paid.\n\n"
    .. "Your " .. G .. "Kina level|r (I to XX) shows how much you've farmed and settled with Kina. Your " .. G .. "standing|r "
    .. "shows what kind of partner you are. Both are on your profile, for the people you farm with to see.\n\n"
    .. GR .. "Kina is free. It never asks for money and never sells anything.|r" },

  { "Farming together",
    H("Starting") .. "Press Start on the widget. Kina users in your group get an invite; everyone who joins shares one farm log, "
    .. "so every widget shows the same numbers. Stop ends the farm for everyone.\n"
    .. H("What counts") .. "- A farm counts for Kina level and standing after " .. G .. "15 minutes|r. Paused time doesn't count.\n"
    .. "- If anyone in the farm is " .. R .. "under level 10|r at any point, the farm gives no progression. The split still works.\n"
    .. "- A farm stops itself " .. G .. "an hour after its last kill|r, and counts as ending at that kill.\n"
    .. H("Fixing the log") .. "Right-click a partner's item on the Session page to leave it out, or to dispute its price "
    .. "(it then counts at its vendor price for everyone; disputes are logged). You can't leave out your own loot: a partner can." },

  { "The split",
    "When a group farm ends, Kina adds up what each player looted and works out who pays whom so everyone ends with the same share. "
    .. "Coin isn't part of it: the game already splits coin.\n\n"
    .. "Each item counts at its best price: auction house, vendor or disenchant. Gear that could be disenchanted counts at its "
    .. "auction or vendor value, never a disenchant guess.\n"
    .. H("Price the loot") .. "If the farm has debts, Kina first asks every Kina user to scan the auction house.\n"
    .. "- If anyone scans, the farm leader re-prices the loot and everyone gets the same new split.\n"
    .. "- If everyone skips, the split stands as it was. After a day it goes ahead anyway.\n"
    .. "- Turn the question off in Settings > Farming.\n"
    .. H("Don't split") .. "A farm started as \"don't split\" shares its numbers but nobody owes anything. Once loot is in, "
    .. "only the players who'd be paid can call the split off." },

  { "Debts",
    H("Paying") .. "Stand next to the person you owe and press Pay on the widget: Kina opens a trade with the exact amount. "
    .. "Or pay by mail from the Debts page (Ledger). Both Kinas confirm the money moved.\n"
    .. H("Time to pay") .. "- " .. G .. "2 hours of play time|r: the clock only runs while one of you is online, and the person owed keeps it.\n"
    .. "- Ask once for more time: the person owed can give 2 more hours, 4 at most.\n"
    .. "- The person owed can forgive a debt at any time.\n"
    .. H("When it runs out") .. "- The debt " .. R .. "lapses: -50 standing|r. It moves to Collections, where you can still pay it late "
    .. "(up to 60 days) for 80% of the XP and standing, instead of losing all of it.\n"
    .. "- If you offered the full amount in a trade and they didn't take it, the debt can't count against you. "
    .. "If it then runs out, the person who turned it down loses the standing instead (-50; -100 if again within 30 days).\n"
    .. "- After a turned-down offer there are 5 minutes in which it can still be paid with nobody losing standing." },

  { "Commendations",
    "At the end of a qualifying farm a window asks how your partners did. It stays until you press Done; then that farm's "
    .. "commendations are closed.\n\n"
    .. "- Up to " .. G .. "2 thumbs up|r per farm: +10 standing each.\n"
    .. "- " .. R .. "Thumbs down|r for as many as deserve one: -10 standing each.\n"
    .. "- Never both to the same person, never to yourself or your own characters.\n"
    .. "- Only players who were in that farm with you can commend you for it.\n"
    .. H("The breakpoint") .. "With positive standing, " .. R .. "10 thumbs down in 48 hours, or 15 in 7 days|r, drops your standing "
    .. "straight to -99 (Delinquent). Kina warns you at 5 and at 10. Each thumbs down counts toward this for 7 days." },

  { "Standing",
    G .. "Unproven|r 0   " .. G .. "Vouched|r 100   " .. G .. "Reliable|r 300   " .. G .. "Trusted|r 600   "
    .. G .. "Honored|r 1000   " .. G .. "Revered|r 1600   " .. G .. "Exalted|r 2500\n"
    .. R .. "Delinquent|r below 0   " .. R .. "Disgraced|r -100   " .. R .. "Oathbreaker|r -300   " .. R .. "Blacklisted|r -1000\n"
    .. H("Earning") .. "- Paying a debt: 10 + 2 per gold, up to 40; +5 when paid in full within 2 hours.\n"
    .. "- Being paid: the same as the payer earns.\n"
    .. "- A qualifying farm: +5.   A thumbs up: +10.\n"
    .. H("Losing") .. "- A thumbs down: -10.   A debt that runs out: -50.\n"
    .. "- Turning down a full payment that then runs out: -50 (-100 if again within 30 days).\n"
    .. H("Falling and climbing back") .. "- Below 0, every gain is " .. R .. "halved|r.\n"
    .. "- At -1000 you're " .. R .. "Blacklisted|r: gains count 1/4, your portrait is crossed out, and your profile keeps a "
    .. "permanent mark, even after you climb back.\n"
    .. "- Back at 0 or above, gains count " .. G .. "x3|r until you reach your best ever.\n"
    .. "- The first time you fall below 0, Kina offers a " .. G .. "one-time pardon|r: back to 1, gains x3 until your best. "
    .. "There is never a second one. Put it off? " .. G .. "/kina pardon|r brings it back.\n"
    .. "- Penalties always count in full.\n"
    .. H("Idle weeks") .. "After 7 days with no farm on any of your characters: positive standing loses 100 a week (never below 0); "
    .. "negative standing gains 50 a week (25 while Blacklisted), up to -20." },

  { "Kina level",
    "Kina level goes from I to XX. It comes from XP, and XP never goes down.\n\n"
    .. "- Farming: 1 XP a minute, for farms of 15 minutes or more.\n"
    .. "- Paying a debt: 40 XP + 10 per gold, up to 200 (full within 5 minutes of the farm, half after an hour).\n"
    .. "- Being paid: 10.   Forgiving a debt: 15.   Giving more time: 5.   A thumbs up given: 5.\n\n"
    .. "Below 0 standing, XP gains are halved too (1/4 Blacklisted), and x3 on the way back to your best." },

  { "Profiles",
    "Your profile (the You tab) shows your portrait in your standing ring, your Kina level, standing and record: "
    .. "best and lowest standing, days positive and negative. Commendations and Farm stats show who you farm with most.\n\n"
    .. "Click a party portrait under the widget, or any name, for that player's profile: the same layout, with "
    .. "what their Kina last told yours.\n\n"
    .. GR .. "Other players' standing is what their Kina reports. If someone's Kina level ever goes DOWN, their record was "
    .. "wiped or swapped, and their profile says so.|r" },

  { "Staying up to date",
    "When someone in your group runs a newer Kina, yours stops earning (and losing) XP and standing until you update "
    .. "and /reload. It never happens in the middle of a farm.\n\n"
    .. "To update: download the new Kina, replace the Kina folder in Interface\\AddOns, and /reload." },

  { "Fair play",
    "Kina only believes what it can check:\n"
    .. "- A commendation only counts from someone who was in that farm with you.\n"
    .. "- Only the farm leader can re-price a farm; only your debt partner can change your debt's clock.\n"
    .. "- Loot put in your name that you never looted is spotted, and Kina records no debt for you from that farm.\n"
    .. "- Shared auction prices that are far from your own scan are ignored.\n"
    .. "- An edited or damaged Kina file shows standing 0 at best (lower if it was lower), and Kina level I.\n\n"
    .. GR .. "No add-on can be completely cheat-proof. Standing on other players' profiles is what their Kina reports.|r" },

  { "Commands",
    G .. "/kina|r  open or close Kina\n"
    .. G .. "/kina tour|r  replay the welcome tour\n"
    .. G .. "/kina help|r  this page\n"
    .. G .. "/kina widget|r  show or hide the widget\n"
    .. G .. "/kina profile Name|r  someone's Kina profile\n"
    .. G .. "/kina pardon|r  the one-time pardon, if you put it off\n"
    .. G .. "/kina start|r, " .. G .. "/kina stop|r  start or stop a farm\n"
    .. G .. "/kina scan|r  scan the auction house" },
}
C.HelpTopics = TOPICS

if not C.RegisterPanel then return end
C.RegisterPanel("help", function(p)
  local K = C.SheetKit
  local nav = K.box(p); nav:SetPoint("TOPLEFT", 0, 0); nav:SetPoint("BOTTOMLEFT", 0, 0); nav:SetWidth(190)
  local page = K.box(p); page:SetPoint("TOPLEFT", nav, "TOPRIGHT", 10, 0); page:SetPoint("BOTTOMRIGHT", 0, 0)
  local head = K.text(nav, "GameFontNormal"); head:SetPoint("TOPLEFT", 14, -12)
  if C.Cos and C.Cos.Font then C.Cos.Font(head, 15, "") end
  head:SetTextColor(1, 0.84, 0.43); head:SetText("How Kina works")
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
    body:SetText(TOPICS[i][2])
    child:SetHeight((body:GetStringHeight() or 300) + 20)
    if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
  end
  for i, t in ipairs(TOPICS) do
    local b = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(b) end
    b:SetSize(162, 22); b:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 26); b:SetText(t[1])
    b:SetScript("OnClick", function() show(i) end)
    btns[i] = b
  end
  local tour = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate"); if C.Skin then C.Skin.Button(tour) end
  tour:SetSize(162, 26); tour:SetPoint("BOTTOMLEFT", 14, 14); tour:SetText("Replay the tour")
  tour:SetScript("OnClick", function() if C.Tour then C.Tour.Start() end end)
  p.refresh = function() show(sel) end
  p.show = show
end)
