local _, C = ...
-- Kina: the welcome tour's steps (0.9.1). Plain data: edit freely.
--  * order here = order in the tour; delete a block to drop a step; copy one to add one
--  * title / body / rules are what the card says (|cff...|r colours work)
--  * target returns the frame to light up (nil = a card in the middle of the screen)
--  * open gets the screen ready (open a window, show a sample); close puts it back
-- The engine is Tour.lua. Numbers in the rules match Rep.lua / Payout.lua / Vouch.lua:
-- change them here too if a rule changes.
local T = C.Tour
if not T then return end
local G, GR, R, W = "|cffffd100", "|cff9d9d9d", "|cffff6a50", "|r"

local function widget(part, part2)
  return function()
    if C.ShowWidget then C.ShowWidget(true) end
    local P = C.Widget and C.Widget.Part
    if not P then return nil end
    return P(part), part2 and P(part2) or nil
  end
end
local function mainTab(tab, view)
  return function()
    if C.UI then if view then C.UI.youView = view end end
    if C.Toggle then C.Toggle(tab) end
  end
end
local function mainFrame() return C.UI and C.UI.frame end
local function hideMain() if C.UI and C.UI.frame then C.UI.frame:Hide() end end

local STEPS = {
  { id = "welcome", title = "Welcome to Kina",
    body = "Kina is your farming partner for WoW Forever.\n\n"
      .. "When you farm with other Kina users, every Kina keeps the " .. G .. "same record|r of the loot, splits it evenly, "
      .. "and keeps track of who owes whom until it's paid.\n\n"
      .. "Pay your share and be a good partner, and your " .. G .. "Kina level|r and " .. G .. "standing|r grow, for everyone to see.\n\n"
      .. GR .. "This tour shows you every part of Kina. It takes about two minutes.|r" },

  { id = "minimap", title = "Your Kina button",
    body = "Click the Kina coin on your minimap to open the Kina window. Drag it to move it around the minimap.\n\n"
      .. "You can also type " .. G .. "/kina|r.",
    target = function() return _G.KinaMinimapButton end },

  { id = "widget", title = "The farm widget",
    body = "Your farm at a glance: gold per hour, the farm clock, and the group's totals, live.\n\n"
      .. "Drag it by the iron bar to put it anywhere. Hide or show it in Settings, or with " .. G .. "/kina widget|r.",
    target = widget("frame"), side = "RIGHT" },

  { id = "start", title = "Start and stop a farm",
    body = "Press " .. G .. "Start|r when you begin farming. If other Kina users are in your group, they get an invite, "
      .. "and everyone who joins shares " .. G .. "one farm log|r: every widget shows the same numbers.\n\n"
      .. "Press " .. G .. "Stop|r when you're done. It stops the farm for everyone.",
    rules = "- A farm counts for Kina level and standing after " .. G .. "15 minutes|r (paused time doesn't count).\n"
      .. "- If anyone in the farm is " .. R .. "under level 10|r, the farm gives no progression. The split still works.\n"
      .. "- A farm stops itself " .. G .. "an hour after its last kill|r, and counts as ending at that kill.",
    target = widget("go") },

  { id = "tiles", title = "The numbers",
    body = G .. "NET|r  everything the group made.\n"
      .. G .. "COIN|r  gold looted (the game already splits coin).\n"
      .. G .. "LOOT|r  items, each at its best price: auction house, vendor or disenchant.\n"
      .. G .. "KILLS|r  every mob the group killed.\n\n"
      .. "Everyone in the farm sees the same numbers, from the same log.",
    target = widget("tNet", "tKills") },

  { id = "pay", title = "Pay and Ask",
    body = "When a group farm ends, Kina works out the even split. Whoever looted more owes the others their share.\n\n"
      .. "If you owe, this button says " .. G .. "Pay|r: stand next to them and click it. Kina opens a trade with the exact amount. "
      .. "If you're owed, it says " .. G .. "Ask|r. Right-click it for the Debts page: pay by mail, ask for more time, or forgive.",
    rules = "- You have " .. G .. "2 hours of play time|r to pay (the clock only runs while one of you is online).\n"
      .. "- Ask once for more time: the person owed can give 2 more hours (4 at most).\n"
      .. "- Paying earns XP and standing; paying soon after the farm earns more XP.\n"
      .. "- A debt that runs out costs " .. R .. "-50 standing|r. You can still pay it late from Collections for up to 80% of the XP and standing, instead of losing all of it.\n"
      .. "- Offered the full amount and they didn't take it? Then the debt can't count against you.",
    target = widget("pay"),
    open = function()
      local b = C.Widget and C.Widget.Part and C.Widget.Part("pay")
      if b then b:SetText("Pay Triforce " .. (C.Money and C.Money(124000) or "12g 40s")); b:Enable(); b:Show() end
    end,
    close = function() if C.RefreshWidget then pcall(C.RefreshWidget) end end },

  { id = "sound", title = "Sound",
    body = "Kina plays a few short sounds: farm start and stop, payments, level ups, and its theme when a farm ends. "
      .. "Click the speaker for a volume slider; slide to the bottom to mute.\n\n"
      .. GR .. "While the theme plays, the game's music pauses, then comes back.|r",
    target = widget("snd") },

  { id = "party", title = "Your party",
    body = "In a group, your party shows under the widget: each portrait in its owner's standing ring, with their Kina level.\n\n"
      .. "Click a portrait to open that player's Kina profile.",
    target = function()
      local s = C.Widget and C.Widget.Part and C.Widget.Part("strip")
      if s and s:IsShown() then return s end
      return C.Widget and C.Widget.Part and C.Widget.Part("frame")
    end },

  { id = "price", title = "Price the loot",
    body = "When a group farm with debts ends, Kina asks every Kina user to " .. G .. "scan the auction house|r, "
      .. "so the split uses today's prices, not old ones.",
    rules = "- The debts wait until every Kina user in the farm answers.\n"
      .. "- If anyone scans, the farm leader re-prices the loot and everyone gets the same new split.\n"
      .. "- If everyone skips, the split stands as it was. After a day it goes ahead anyway.\n"
      .. "- You can turn the question off in Settings > Farming.",
    target = function() return C.PriceHold and C.PriceHold.Preview and C.PriceHold.Preview(true) end,
    close = function() if C.PriceHold and C.PriceHold.Preview then C.PriceHold.Preview(false) end end },

  { id = "commend", title = "Commendations",
    body = "At the end of a qualifying farm, this window asks how your partners did. "
      .. "Give a " .. G .. "thumbs up|r to the ones who made it great, and a " .. R .. "thumbs down|r if someone was a problem.\n\n"
      .. "It stays open until you press Done; then that farm's commendations are closed.",
    rules = "- Up to " .. G .. "2 thumbs up per farm|r: +10 standing each.\n"
      .. "- Thumbs down for as many as deserve one: " .. R .. "-10 standing|r each. Never both to the same person.\n"
      .. "- Never to yourself or your own characters.\n"
      .. "- With positive standing, " .. R .. "10 thumbs down in 48 hours, or 15 in 7 days|r, drops you straight to -99. "
      .. "Kina warns you at 5 and at 10.",
    target = function()
      if C.Vouch and C.Vouch.ShowPrompt then C.Vouch.ShowPrompt(true) end
      return _G.KinaCommend
    end,
    close = function() if _G.KinaCommend then _G.KinaCommend:Hide() end end },

  { id = "session", title = "The Session page",
    body = "Your farm in detail: every kill and item in the shared log, who looted it, and what it's worth.\n\n"
      .. "Right-click a partner's item to " .. G .. "leave it out|r of the farm, or " .. G .. "dispute|r its price.",
    rules = "- You can't leave out your own loot: it would change what you owe. A partner can.\n"
      .. "- A dispute counts the item at its vendor price for everyone, and it's logged.",
    open = mainTab("Session"), target = mainFrame, close = hideMain },

  { id = "ledger", title = "The Ledger",
    body = "Every farm you've done, with its split. " .. G .. "Debts & Credits|r shows what's open, "
      .. "and " .. G .. "Collections|r keeps every debt that was settled, forgiven or ran out.\n\n"
      .. "A debt that ran out can still be paid late from Collections.",
    open = mainTab("Ledger"), target = mainFrame, close = hideMain },

  { id = "you", title = "Your profile",
    body = "Your Kina " .. G .. "level|r (I to XX), your " .. G .. "standing|r, and your record: best and lowest standing, "
      .. "days positive and negative. The Commendations and Farm stats pages show who you farm with most.\n\n"
      .. "Other players' profiles look the same: click a party portrait or a name.",
    rules = "Kina level comes from XP:\n"
      .. "- Farming: 1 XP a minute (farms of 15 minutes or more).\n"
      .. "- Paying a debt: 40 XP plus 10 per gold, up to 200 (more when paid quickly). Being paid: 10.\n"
      .. "- Forgiving a debt: 15. Giving more time: 5. A thumbs up given: 5.",
    open = mainTab("You", "you"), target = mainFrame, close = hideMain },

  { id = "standing", title = "Standing",
    body = "Standing is your reputation as a partner. Everyone you farm with can see it.\n\n"
      .. GR .. "Unproven 0  ·  Vouched 100  ·  Reliable 300  ·  Trusted 600  ·  Honored 1000  ·  Revered 1600  ·  Exalted 2500|r\n"
      .. R .. "Delinquent below 0  ·  Disgraced -100  ·  Oathbreaker -300  ·  Blacklisted -1000|r",
    rules = "- Earn: paying a debt (10 + 2 per gold, up to 40; +5 if paid in full within 2 hours), being paid (the same), "
      .. "a qualifying farm (+5), a thumbs up (+10).\n"
      .. "- Lose: a thumbs down (-10), a debt that runs out (-50), turning down a full payment that then runs out (-50; -100 if again within 30 days).\n"
      .. "- Below 0, gains are " .. R .. "halved|r. At -1000 you're " .. R .. "Blacklisted|r: gains count 1/4, your portrait is crossed out, "
      .. "and your profile keeps a permanent mark.\n"
      .. "- Back at 0 or above, gains count " .. G .. "x3|r until you reach your best ever.\n"
      .. "- The first fall below 0 offers a " .. G .. "one-time pardon|r: back to 1, gains x3 until your best.\n"
      .. "- 7+ days with no farm: positive standing loses 100 a week (not below 0); negative gains 50 a week (25 Blacklisted), up to -20.",
    open = mainTab("You", "you"), target = mainFrame, close = hideMain },

  { id = "settings", title = "Settings",
    body = "Switches for everything: data sharing with your group, farm options (the AH scan question, farm stats posted to party chat), "
      .. "sounds, the widget, and item tooltips.",
    rules = "- Keep Kina up to date. When someone in your group runs a newer Kina, yours stops earning XP and standing "
      .. "until you update and /reload. It never happens in the middle of a farm.",
    open = mainTab("Settings"), target = mainFrame, close = hideMain },

  { id = "tooltip", title = "Item tooltips",
    body = "Kina adds a price block to the top of item tooltips: auction, vendor and disenchant values, "
      .. "and the best way to turn the item into gold.\n\n"
      .. "Turn it off, or show only Kina's part, in Settings > Item tooltips.",
    target = function()
      if not (GameTooltip and GameTooltip.SetOwner) then return nil end
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:ClearAllPoints(); GameTooltip:SetPoint("CENTER", UIParent, "CENTER", -220, 40)
      -- (0.9.2: an item from your own bags, which the game always has loaded; an item the
      -- game hasn't seen this session gives an empty tooltip that hides itself)
      local done = false
      local CC = C_Container
      if CC and CC.GetContainerNumSlots and CC.GetContainerItemID and GameTooltip.SetBagItem then
        for bag = 0, 4 do
          for slot = 1, (CC.GetContainerNumSlots(bag) or 0) do
            local id = CC.GetContainerItemID(bag, slot)
            local sell = id and C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
            if id and (sell or 0) > 0 and not done then done = pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot) end
          end
        end
      end
      if not done and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:2589") end
      GameTooltip:Show()
      return GameTooltip
    end,
    close = function() if GameTooltip then GameTooltip:Hide() end end },

  { id = "help", title = "Help, any time",
    body = "The " .. G .. "Help|r tab explains every rule in plain words, and can replay this tour.\n\n"
      .. "Commands: " .. G .. "/kina|r opens Kina, " .. G .. "/kina tour|r replays this, " .. G .. "/kina help|r opens Help.",
    open = mainTab("Help"),
    target = function() return C.UI and C.UI.tabButtons and C.UI.tabButtons.Help end,
    beside = mainFrame, close = hideMain },

  { id = "done", title = "You're ready",
    -- 0.9.2 (Taylor): the reward is a surprise: only this last page mentions it
    body = function() return "1.  Group up with other Kina users.\n"
      .. "2.  Press " .. G .. "Start|r and farm together for 15 minutes or more.\n"
      .. "3.  Press " .. G .. "Stop|r, and scan the auction house when asked.\n"
      .. "4.  " .. G .. "Pay|r what you owe, or " .. G .. "Ask|r for what you're owed.\n"
      .. "5.  Commend the partners who made it great.\n\n"
      .. "Good hunting!"
      .. ((T.Rewarded and not T.Rewarded()) and ("\n\n" .. G .. "One more thing: finishing the tour earns you " .. ((C.Rep and C.Rep.TOUR_XP) or 50)
        .. " XP and " .. ((C.Rep and C.Rep.TOUR_REP) or 20) .. " standing. Press Finish to claim it!|r") or "") end },
}

for _, s in ipairs(STEPS) do T.Add(s) end
