# WellMet: one key, many buffs

Bind one key. Each press buffs **you**, then the **next person nearby who needs it**. Press again and it moves on. No target-clicking, no raid frames, no tracking window. It only answers "who needs what right now?" when you press.

**Built for WoW Forever (Interface 16001).**

## Who it's for

| Class | What it buffs | Extra for yourself |
|---|---|---|
| **Paladin** | An ordered list of blessings per class (up to five slots, set per section): Might, Wisdom, Kings, Salvation or Light (those two for you and your group only, not strangers). The key casts the first one you've learned that they don't already have from someone else | Aura (Devotion by default), optional Righteous Fury |
| **Mage** | Arcane Intellect, optional Dampen or Amplify Magic (group and you only) | Armor (best Frost/Ice Armor you've learned, or Mage Armor) |
| **Druid** | Mark of the Wild, optional Thorns | none |
| **Priest** | Power Word: Fortitude, Divine Spirit, optional Shadow Protection | Inner Fire |

Everything in the middle column can go on **you, your group and strangers**, and each of those three has its own choices (see below). The last column is only for yourself.

The group versions (Prayer of Fortitude, Gift of the Wild, Arcane Brilliance and so on) count as already having the buff.

**Warlock, Warrior, Hunter, Shaman and Rogue:** WellMet does not load. With nothing to cast on other players, a keybind of your own spell does the job.

## Three sections, each on its own

- **Self**: your own buffs. Works by itself if the other two are off.
- **Party / Raid**: your group, with its own radius and its own buff choices per class.
- **Others**: strangers nearby, found through friendly nameplates. Off until you turn it on.

Tick the sections you want on the main settings page, and each one gets its own page. Every choice is an icon dropdown, and spells you haven't learned are shown greyed out with an "Unknown" tooltip.

## Optional extras

The extras live on two settings pages under WellMet: **Priority** and **Group tools**.

- **Set all classes**: on the Party / Raid and Others pages, click a buff icon to give it to every class, or click it again to clear them all.
- **Buff reminder**: two small icons, Self and Group, that glow when someone still needs a buff. Off by default (settings, *Buff reminder*); Shift-drag to move.
- **Refresh running-out buffs** (on by default at 20%): once nobody nearby is missing a buff, the key recasts buffs that have the chosen share of their time left or less (slider, 10% to 90%). Someone missing a buff always comes first, then the most urgent refresh. It works on anyone's buffs, with one exception for Paladins: on you and your group only your own blessings are refreshed (a recast would replace another Paladin's), but on strangers anyone's blessing is.
- **Buff back first** (on by default): when another player puts a new buff on you, they go to the front of the list for 10 seconds. A key press in that time buffs them first, if they need a buff. Casters the game doesn't name are ignored, and nothing is tracked in combat.
- **Buff my target** (on by default): target someone yourself and press the key, and they are buffed first whatever time their buff has left. A Paladin replaces another's blessing this way, with the class's main blessing. The reminder icons ignore this.
- **Don't buff PvP-flagged players, unless I'm flagged** (General settings, on by default): while you are not PvP flagged, anyone in your group or nearby who is flagged is skipped, because buffing them would flag you too. Once you are flagged yourself, they are buffed as usual. You are never skipped, and the reminder icons follow the same rule.
- **Low-level targets**: a player too low level for your highest rank of a buff gets a lower rank, the way the spellbook does it. Nothing to set. If the game still refuses, the next press tries one rank further down.
- **Buff requests**: players say `!bom`, `!fort`, `!ai` ... (or `!none`, `!default`) in party or raid chat, or whisper you, and the key buffs them with that instead of their class default. It is remembered until they change it or you clear it. On by default (untick it in the settings to stop listening). The game hides chat during encounters, Mythic+ and PvP matches, so new requests only arrive outside them. *Announce to group* (button, `/wellmet announce` or Ctrl-click on the minimap button) tells the group how to ask; where the game won't let addons send chat, the line is put in your chat box for you to send.
- **Minimap button**: left-click settings, right-click show / hide the reminder icons, Ctrl-click announce, Shift-click log.
- The settings pages scroll.

## Setting it up

1. Open the settings, **WellMet**, and bind your key. The button jumps straight to it in Key Bindings.
2. Choose the sections and buffs you want.
3. Optional: **Create macro** puts a `/click WellMetCast` macro on your cursor. It buffs you and your group. Strangers need the key, because the game won't run that from inside a macro.

Commands: `/wellmet` (settings), `/wellmet self`, `party`, `others`, `/wellmet macro`, `/wellmet strip`, `/wellmet announce`, `/wellmet requests`, `/wellmet log`, `/wellmet ranks`, `/wellmet debug`.

## Good to know

- **Out of combat only.** Forever hides other players' buff information in combat, so WellMet can't tell who needs a buff there.
- **Quiet by default.** One line at login, nothing else. Turn on **Debug** to see why a press did nothing and to record a log you can copy.
- Distances for strangers come in 10 and 28 yard steps, because the game doesn't give more.
- Pressing the key on a stranger targets them first, and leaves them targeted.

## Test status

Paladin (blessings), Mage (armor, Arcane Intellect), Druid and Priest (Power Word: Fortitude) are tested in game. **Built but not yet tried in game:** Priest's Divine Spirit, Shadow Protection and Inner Fire, Mage Dampen and Amplify Magic, Paladin auras beyond Devotion, and Righteous Fury. Bug reports are welcome: [GitHub issues](https://github.com/tekHudson/WellMet/issues).

## Credits and license

MIT license. The lettering in the icon is rendered in IM Fell English SC (SIL Open Font License).
