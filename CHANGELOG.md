# Changes

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
