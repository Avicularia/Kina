# Kina 2.1.4

- Fixed: since Nov 20 WoW Forever reports a blank realm name, which split your Kina data and showed 0 Renown. Kina now finds your realm and folds that data back in.
- Group farms: leave the group, reload or disconnect mid-farm and you stay in it. Catching up after a rejoin takes seconds, the SYNCING chip only shows when you're really behind, and every loot counts exactly once.
- Two auction houses: Booty Bay is scanned and priced separately. Prices has a My bags tab (sell to the Alliance or Booty Bay AH, post at the live lowest price) and a Transport tab for items worth carrying between them.
- Hot mobs: far more mobs, levels 25 to 60. Drops count at 8%+ (recipes at 2%+, or 1.5%+ when worth 10g or more), shown as "drop chance", with why a mob is hot.
- Kina players share what drops from what, so drop chances keep improving.
- Profile: full names with surnames, one gold per hour (your share on your best farm), hours farmed, bonus breakdown, profession income per session.
- New: Leaderboard of every Kina player seen this season.
- /kp opens Kina prices. Widget opacity setting. The main window resizes from its edges.
- The commend prompt opens with the farm-complete window. Your daily streak now carries across seasons.

# Kina 2.0.8

Kina 2.0: farming with other Kinas now earns Renown, Kina XP and a whole season of cosmetics.

- New: Renown and Kina XP, earned by farming with at least one other Kina. Ten ranks, from the Wanderer to the Everlasting. Everyone in the farm gets credit for the whole group's loot.
- Bonuses that stack: party, daily streak, campfire, season track levels, and +10% for every commendation you receive.
- Hot Farms, live: the list rebuilds near your level from live AH prices and Kina players' kills. A drop selling at 1.5x its usual price makes its mob HOT while the streak lasts.
- Every hot mob's page explains why: worth per kill, gold per hour at your own pace, whether it still gives you XP, how full the market is, and how sure Kina is. Gold per kill always shows; the logo still lights up at 30 of your kills.
- New: Gathering on Hot Farms: every Mining and Herbalism node you can gather, what each gather gives ("Iron Ore: 300%" = 3 a node) and what it's worth, with HOT when a material spikes.
- Skins count toward a mob's value once your Skinning is high enough.
- New: Prices, anywhere: an auction house browser that works away from the AH, with Blizzard's own categories (/kina prices).
- New: account net worth on the You page: every character's gold plus unsoulbound bags and bank.
- Prices: a busy market (20+ listed) is valued at today's price, so a material that jumps counts the day it happens.
- AH scans: prices are ready the moment the book is read; item names finish loading in the background.
- Scans shared with your group arrive up to 8 times faster.
- The widget: two big boxes (Net looted and XP / hour), a compact mode, and a party strip you can hide or resize. It scales down to 40%.
- Kina network: a busy channel no longer cuts you off (backup channels and relays), and add-on messages are registered so every Kina hears every other.
- Party post fixed: with no other Kina in the group, the 15-minute post shows your own gold per hour.
- Debts, Oathbreaker and the negative tiers are gone. A thumbs down never costs anything.

# Kina 1.0.9

- Kina network fixed: scans now reach every Kina, on every realm and layer.
- Kinas say hello every 5 minutes, so a newer scan reaches people who logged in later.
- Your scan plus one other Kina is enough for a shared price.
- Kina keeps trying to join the network until it's in, and holds messages until then.
- The scan bar shows when prices come from the Kina network.
- Network log: full names, versions and who's online, with correct labels.
- Debts are gone: splits now just show each player's fair share. Nobody owes anybody.

# Kina 1.0.8

- Fix: walking into a dungeon mid-farm now ends the old farm properly (split, commendations) before the new one starts.
- Fix: your partner gets into the new dungeon farm.
- New: Network log (/kina net or Settings): what Kina sends and receives, and who it's talking to.
- Fix: What's new, Feedback and other windows open on top of Kina, not behind it.
- Fix: the progress bars on Season 1 Cosmetics fill.
- Fix: buttons no longer overlap the scan bar or each other.
- Help: new Hot mobs and AH prices topics; What Kina is rewritten.
- Fix: "you were in different zones" only counts the people in the farm, not the whole group.
- AH scans shared by any Kina on the realm count toward "no new scan needed".
- The farm roster says "Cancel farm" until someone else has joined.
- Settings cleaned up: sharing switches together, fewer redundant buttons.
- Season 1 Cosmetics: a glowing menu button, a new Legendary crest glow, clearer crest levels.

# Kina 1.0.7

- New: AH prices from every Kina on the realm, not just your guild.
- A network price only counts where several Kinas agree; one bad scan can't move it.
- New: Settings switch "Share AH prices with every Kina".
- Network prices are packed small and sent once to everyone: a full scan in about 2 minutes.
- New: "Update available" on the widget (or a window) when a newer Kina is out.
- New: a Feedback button on the bottom bar of every tab, with a green dot when the developer is online.
- The Kina button pulses green when a feedback answer is waiting.
- Group farms: nobody is put in a farm without clicking Join.
- New: a farm roster shows who's in, who said no and who hasn't answered.
- Said no to the group's farm? You can't start your own until it ends.
- Anyone in the farm can end it for everyone.
- Scan bar: shows whose scan is coming in, how far along, and about how long is left.

# Kina 1.0.6

- New: hot mobs for everyone: a grey logo that lights up for you at 30 of your kills.
- A lit hot mob shows your own gold per kill on its nameplate.
- New: Hot Farms > Archive keeps hot mobs taken off the list, with what they gave you.
- New: a "developer online" badge; click it to send feedback and get a notice when answered.
- New: Help > Feedback (or /kina feedback).
- New: controller support in Kina's windows (D-pad, A, B, X, Y, LB / RB).
- New: key bindings for Kina, Start / stop farm, Scan AH, Hot Farms and a hot mob waypoint.
- New: Window size buttons in Settings.
- New: /kina pad checks controller support.

# Kina 1.0.5

- New: Hot Farms tab: the mobs worth the most per kill near your level, with a waypoint to their thickest spawn.
- New: hot mobs burn on their nameplates (grey until Kina users have 30 kills).
- New: a "hot mob nearby" line under your quest tracker while you quest (off switch in Settings).
- New: profiles show a player's record and Kina high score.
- New: Help > Season 1 Cosmetics, with your progress toward each unlock.
- New: a short "What's new" tour after big updates.
- Disputes pop up as Confirm / Decline on the other player's Kina, on any of their characters.
- Undelivered disputes travel through guildmates' Kinas or your mailbox.
- Guild data sharing updates every 2 minutes and catches up at login.
- Pages scale with the window size.
- Fix: disputes did nothing when the other player had sharing off.
- Fix: mailing a player with a surname failed.
- Fix: scrollbars and the text-size slider can be dragged.
- Fix: TomTom waypoints now pin on the minimap and world map.
- Fix: profile Record line no longer says "asking their Kina..." forever.
- The Kina level and standing bars no longer have frames.
- The end-of-farm song ends at its first fade-out.

# Kina 1.0.4 (hotfix)

- Fix: "Kina has been blocked from an action only available to the Blizzard UI" when pressing Escape, opening Kina or closing other windows. Kina's questions now use its own dialog box instead of the game's popup.
- Fix: the Dispute button now shows on lapsed debts in Ledger > Collections.
- Disputes now work even when the other player's Kina has no record of that farm (it asks them).
- New: /kina blocked lists any action the game blocked, to help track down problems.

# Kina 1.0.3

- New: bond crest on your partner's portrait, Uncommon to Legendary with 1-5 gems (20 levels, +10.5% to +20%).
- The partner bond now grows with gold farmed together, scaled to your level (about 20 hours to max).
- New: Dispute a debt that was already paid or forgiven; the person owed can clear it.
- A lapsed debt that gets forgiven or cleared gives back the standing it took.
- New: farm-end line in party chat with time, gold/h, XP/h, kills, best drop and the split.
- The 15-minute chat line shows how many Kina users are in the group.
- Hover an item link in chat to see its tooltip.
- Late joiners only share loot from after they joined; members away 2+ minutes are out of the split until back.
- No AH scan question if anyone scanned in the last 15 minutes; a new farm counts as "skip" for the last one.
- Fix: forgiveness now always lands, even while a farm waits on the AH scan question.
- Fix: no more floating grey boxes at merchants with bag add-ons.
- Fix: Farms table columns no longer overlap.
- Fix: "Who showed you Kina?" only shows once.
- Fix: AH scans are shared with guild members again.
- Needs a full WoW restart once (new art).

# Kina 1.0.2

- Kina only ever exchanges its data with players who are online in your group or whose Kina just spoke to yours. No more "No player named..." lines.
- Group chat stats line: posts every 15 minutes on the dot, shows the same gold per hour as your widget, adds character XP per hour, kills and farm time. The CurseForge tail is gone.
- Fair rewards: paying and being paid earn the same Kina XP and standing, and owing several people no longer earns several times more.
- Ledger: farm details open with "Why you owe" and your biggest drops, plus the farm's top drops and who looted them.
- Item tooltips: a big VENDOR, AUCTION HOUSE or DISENCHANT call above the tooltip.
- At a merchant, bag items that shouldn't be vendored are greyed out (the game's own bags).
- New setting: "This character disenchants". Off means Kina never suggests disenchanting there.
- Widget: Net Looted and Net Gained (with quest reward gold), plus FPS and latency.
- Joining a group that already has a Kina farm running: your widget says so and Start becomes Join.
- Fix: items no merchant buys no longer show a vendor price; trade goods no longer show a disenchant value.
- Fix: paying or asking by mail no longer fails with "enter a character's full name".
- Fix: the Kina theme plays at the end of a farm again (on unless you turn it off).

# Kina 1.0.1

- Fix: closing "Who showed you Kina?" no longer brings it back every few minutes (/kina mentor reopens it).
- Fix: the mentor star reaches the mentor on any of their characters, not only the one they were picked on.

# Kina 1.0.0

- Kina is out of beta.
- Consumables are your own stat; they're no longer part of any split.
- The tour can't be clicked through to Kina's windows, and the data notice waits until it ends.
- The volume slider plays its sound once, after you let go.
- Your Kina Partner is a row in Your record (no more overlapping text).
- "/h" after the gold per hour on the widget.
- The farm stats line posts to party chat for any farm, not only shared ones.

# Kina 0.9.23 (beta)

- The widget shows your character's XP per hour, with kills underneath.
- XP tracking is safe in dungeons.
- The nameplate glow fades out softly instead of ending in a flat line.
- Dungeon safety: no part of Kina can flood errors or slow your game; a failing piece switches itself off.
- Party icons show who has Kina; click someone without it to share Kina in party chat.
- A copy box for Kina's link (/kina link).
- Kina's links now point to its CurseForge page.
- Test builds never freeze other players or announce an update they can't get.
- The Kina Founder laurel for the Kina team.
- New players pick who showed them Kina, with animated rings; that player earns the mentor star.

# Kina 0.9.20 (beta)

- Tracker only (Settings or /kina tracker): track your farms with no splits, debts or Kina XP; your group is told.
- Partners are account to account: any of your characters with any of theirs.
- The bond grows on whichever characters you play together.
- Kina remembers which characters belong to each Kina user.
- Fix: a farm stays with the character that started it; logging in on an alt no longer picks it up.
- The Try preview buttons are off by default.

# Kina 0.9.18 (beta)

- Kina Partners: +10% XP and standing on farms and payments together.
- Partner bonus grows +1% every 5 farms together, up to +20%.
- The partner popup is back: partnering takes both players.
- End a partnership from their profile or /kina partner end.

# Kina 0.9.17 (beta)

- Share Kina: posts the download link in party chat; the first sharer gets the install.
- Other players' profiles show their XP progress.
- Dishonoured portraits keep the moving 3D model, greyed out.
- Fix: "Only Kina" tooltips no longer show double on loot rolls.

# Kina 0.9.16 (beta)

- The widget wears the new nameplate too.
- Stronger banner gold across the interface: tabs, buttons, headings and text.

# Kina 0.9.15 (beta)

- New Kina coin logo and a new nameplate on the Kina window.
- The interface's gold and glows match the new logo.
- 3D portraits use the game's own portrait camera, framed on the face for every race.

# Kina 0.9.14 (beta)

- Solo farms run until you press Stop (time logged off doesn't count).
- No more "farming partner?" popup when a Kina user joins your group.

# Kina 0.9.13 (beta)

- Dishonour breaks your portrait: cracked, then shattered, then snapped in two.
- Kina level sits on a curved nameplate in your ring's colour.
- 3D portraits sit higher in the frame; an empty Ledger welcomes new players.
- Fixes: a long pause no longer ends the farm on resume; Pay pays whoever asked.

# Kina 0.9.12 (beta)

- Profile portraits show your character's live 3D model, sharp at full size.

# Kina 0.9.11 (beta)

- Each realm now has its own Kina profile. A new realm starts fresh; your old realm's profile is kept.

# Kina 0.9.10 (beta)

- Installs shared: new players name who told them about Kina; it counts toward the mentor star after their first 15-minute farm.
- The profile portrait sits lower, clear of the tabs.

# Kina 0.9.9 (beta)

- Fixed the flood of errors in dungeons.
- "Only Kina" item tooltips no longer flicker.
- New gem-set mentor stars to match the rings.

# Kina 0.9.1 (beta)

- Welcome tour on first install: every feature, lit up one at a time, with its rules. `/kina tour` replays it.
- New Help tab: how Kina works, every rule in plain words.
- Security: commendations, re-pricing, debt clocks and the out-of-date lock only accept messages from the right players; leaving out or disputing your own loot no longer lowers what you owe; a quick accept-and-cancel no longer counts as an offered payment; edited save files can't improve standing; wiped files keep a negative standing on that character.
- Kina remembers up to 100 other Kina users, plus anyone notable (negative standing, the Blacklisted mark, or a Kina level that went down).
- Standing is worked out at most every 30 seconds instead of constantly.
