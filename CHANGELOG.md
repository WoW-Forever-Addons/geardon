# Changes

## 1.7.0

- **Clear verdict in the tooltip:** the item tooltip now opens with one line against your worn item, for example "Worse than [Bonebiter] (Main Hand)" with the difference beside it, in green when it is better, red when it is worse and grey when it is as good. Below it, item level and value stand next to the worn item's. Rings and trinkets name the slot (1 or 2).
- **One options window per addon:** the options button, the gear icon and `/gd` open only Geardon's own options. The game's AddOns list keeps a single button that leads there.
- **Lists in the game's look:** group headers in lists look like the game's own bars, with plus and minus on the right. Wide tooltips in lists appear beside the mouse and no longer cover the search box.
- **Shorter option names:** names that were too long for the window are shortened in all nine languages.
- **Shared Don library:** updated to the current version of the Don addons.

## 1.6.2

- **One option for the window style:** the switch "Windows in the game's look" is now the choice "Window style" with "Don look" and "Blizzard look", named the same in every Don addon. Your setting stays as it was.
- **Shared Don library:** updated to the current version of the Don addons.

## 1.6.1

- **Group window in the game's look:** the title reads "Geardon · Group" in the game's gold instead of capitals.

## 1.6.0

- **Geardon in the game's look:** the gear check, the group window and the report window now look like the game's own windows: the game's frame, tabs, buttons and lists. The options open in the game's settings (Options > AddOns > Geardon). This is the new default; the Don look is one switch away under Look, "Windows in the game's look".
- **Shared Don library:** updated to the current version of the Don addons.

## 1.5.2

- **Hidden surnames:** with surnames switched off in the game's options, your characters are still told apart correctly and the realm is never taken from the surname.
- **Cleaner text in narrow places:** text that is shrunk to fit keeps one font and size, also after the game window changes its size.

## 1.5.1

- **Surnames on WoW Forever:** names are kept as first name and surname, as the game gives them: the group view shows and finds group members with their surname.

## 1.5.0

- **The Don look:** the group window (`/gd group`) like Questdon's list: class symbol, name in class colour, source and age, the average on the right, the group average below; from 6 members one line each by raid group. The gear check (`/gd check`) is a window you can resize with your item level and weakest slot on top, four sections to fold, item rows with quality border, vendor prices and no limit of 25 rows. Diagnostics in the shared copy window.
- **One options window for all Don addons:** switches, sliders, lists, a picture and an explanation for every option, a search over all Don addons. The gear button and the slash command open it on this addon's section. Blizzard's AddOns page only shows the status and a button. The options show a preview of the number and the arrow.
- **Window size:** all Don windows share one scale, 80 % by default, set from 60 to 110 % under General > Window in the options window. Saved window sizes are reset once, places stay.
- **Addon list:** the addon has its own logo in the game's addon list.
- **Update note:** new files, so restart the game after updating (a /reload is not enough).

## 1.4.0

- **No new required addon.** With **DonData** installed (it comes with Questdon and Leveldon) Geardon uses its gear score; without it Geardon works as before.
- **One gear score with Questdon:** with DonData the upgrade arrow weighs every item, weapons too, by its value for your class and talent tree: the stats, the armor and the weapon damage. Wands go by damage first, ranged weapons of classes other than hunters by their stats. The value line in the tooltip shows this score, and Questdon's reward advice agrees with Geardon's arrow. The option now reads "By stat value for your class".
- **Rings, trinkets and one-hand weapons** compare against the weaker of your two by value.
- **Dungeons for your level** come from DonData, also without Questdon.
- **Lighter:** a tooltip judges an item once and remembers it until your gear, level or talents change; events of units Geardon does not need (nameplates in a crowd) are dropped early; the group timer only runs while there is something to do.
- **Shared base:** options and window style come from DonCore, the common base of the Don addons. Nothing changes for you.

## 1.3.0

- **Wearable soon:** upgrades you can wear in a few levels (3 by default) get a grey arrow, so you keep them; the tooltip names the level.
- **Upgrades in your bags:** a chat line when an upgrade comes into your bags (loot, quest, mail, trade), e.g. "Upgrade in your bags: [Helm] (Head +6)". Once per item, not on login, never for gear you swap. The gear check (/gd check) lists the best upgrade per slot from your bags at the top.
- **One-hand and off-hand:** while you wear a two-hand weapon, a one-hand weapon together with the best shield or off-hand item from your bags (or the other way round) gets a yellow arrow when both hands together are higher. The tooltip names the partner.
- **Unique items:** no arrow on a second copy of a unique ring, trinket or weapon you already wear.
- **Vendor price:** the bag cleanup of the gear check shows the vendor price of each item and what the whole list is worth.
- **Inspect:** your own average next to that of the inspected player.

## 1.2.4

- **Stats for your class:** the upgrade arrow weighs an item's stats for your class and talent tree, the same way Questdon suggests quest rewards. Armor, rings, necks and trinkets get the arrow when their stats are worth more to you than yours, also at a lower item level, and none when they are worth less. The same for the melee weapons and staves of hunters, mages, priests, warlocks and caster druids and shamans; other weapons, ranged weapons and wands still go by item level. The tooltip shows the value against yours.

## 1.2.1

- **Update note:** a new file, so restart the game after updating (a /reload is not enough).
- **For other addons:** Questdon now marks quest rewards that are an upgrade for you (in its pin tooltips, quest list and quest book), using Geardon's judgement.

## 1.2.0

- **Update note:** new files, so restart the game after updating (a /reload is not enough).
- **Baganator and Bagnon:** item level, upgrade arrow and BoE mark in their bags too. Baganator: pick Geardon in its icon corners and as its upgrade plugin.
- **Smarter upgrade arrow:** only on weapon types you use (a bow user gets it on bows, guns and crossbows, not on thrown weapons or other melee types), not on items with none of your class's main stats, and optionally only on your best armor type (mail or plate from level 40).
- **Quality counts:** Forever computes the stats from item level and quality. A higher item level of a lower quality than yours gets a yellow arrow and the tooltip says to compare the stats; the same item level of a higher quality is an upgrade.
- **Set pieces:** yellow arrow and a tooltip warning when an upgrade would replace a piece of a set whose bonus you have.
- **Stat split in tooltips:** e.g. "Agility 60% · Stamina 40%", and the reason when a higher item gets no arrow.
- **Item level of any player:** point at a player or target one and the item level appears in the open tooltip as soon as it is known (on by default, also switched on once for existing settings). Out of combat only, never while the inspect window is open, one player every few seconds; in combat the last known value.
- **Behind your level:** slots far below your level are red on the character frame. The tooltip of your average lists them, with the dungeons for your level; a click opens the gear check.
- **Gear check (/gd check):** slots behind your level, dungeons for your level and a bag cleanup list (gear worse than yours or unusable; items of your equipment sets stay off the list). Only a list: nothing is sold or deleted.
- **Chat line** when your average changes, e.g. "Item level 24.3 -> 25.1 (Head +6)". Not on login, one line for quick swaps.
- **BoE mark** on bind-on-equip items in your bags that are not bound yet.
- **Group window:** no longer opens by itself in a group or raid (its two options are gone). /gd group or the button in the options shows it; the item level of group members is still collected for the player tooltips.
- **Look per place:** position and size of the numbers for the character frame, bags and loot, rewards and merchants each; colour by the gap to your average; numbers only on Uncommon and better (option).

## 1.1.0

- **Translations:** French, Spanish (Spain and Latin America), Brazilian Portuguese, Russian, Korean and Traditional Chinese.
- **Decimal sign:** item level averages use the decimal sign of your game language.

## 1.0.0

First release.

- Item level on every slot of the character frame, the weakest slot marked.
- Item level per slot and average on the inspect frame.
- Item level and upgrade arrow on bags, bank, loot, quest rewards and merchants, item level in the equipment flyout.
- Item level line and comparison with your item in tooltips, item level of group members in player tooltips.
- Group window with every member's item level and weakest slot, sent by Geardon or inspected out of combat.
- English and German.
