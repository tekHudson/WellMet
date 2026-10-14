# WellMet

One key buffs the next nearby player who needs it. Built for **WoW Forever** (Interface 16001).

> Version 1.1.1. It only works on the WoW Forever client (Interface 16001).

Stand at a campfire or run through town, press the key, and your buff goes on someone nearby who
doesn't have it. Press again and it moves on to the next person.

WellMet is for classes that buff **other players**: **Paladin** (Blessing of Might, Wisdom, Kings, Salvation or Light, one per target class; Salvation is for your group only; for strangers you can also set a secondary blessing that is cast when they already have your primary from another Paladin), **Mage**
(Arcane Intellect, plus optional Dampen / Amplify Magic for your group, ticked per class), **Druid** (Mark of the Wild, optionally
Thorns) and **Priest** (Power Word: Fortitude, Divine Spirit and optionally Shadow Protection, ticked per class; the
group versions count as already having them).

It also keeps **your own buffs** up with the same key, before anyone else: a Paladin's aura (and optionally Righteous
Fury), a Mage's armor, a Priest's Inner Fire. Pick them on the *Self* page; "best learned" uses Ice Armor over Frost Armor.

On a character whose class can't buff other players (Warlock, Warrior, Hunter, Shaman, Rogue) WellMet does not load at
all: no messages, no settings, no minimap button. A single self buff is better served by binding the spell itself.

## Use

- Set the key in the game's own **Key Bindings** window, under **WellMet**. *Open Key Bindings* in the settings
  jumps straight to it.
- Settings has a main page and three sections, customised on their own: **Self** (your own buffs; WellMet is
  just this if the other two are off), **Party / Raid** and **Others** (strangers, off until you turn it on; found
  through friendly nameplates and needs the key). Tick a section on the main page to switch it on and show its
  page under WellMet; untick it and the page goes away. `/wellmet self`, `party` and `others` open each one. The main page has a button that writes the macro for you (`/wellmet macro`).
- **Set all classes**: on the Party / Raid and Others pages, an icon per buff sits above the class table. Click one to give
  that buff to every class, click it again to clear them all (the red cross skips every class). A count like 4/9 shows when
  only some classes match, and you can still change a single class afterwards.
- **Buff reminder** (main page, off by default): two small icons, **Self** and **Group** (party and raid together). An
  icon glows gold when the key would buff someone in it, goes dark with a green check when everyone is covered, and shows
  a grey ? when the game hides buffs (combat). "Show only when a buff is missing" draws an icon only while it needs one.
  Shift-drag moves them; `/wellmet strip` toggles them.
- **Refresh running-out buffs** (main page, on by default at 20%): once nobody nearby is missing a buff, the key recasts buffs that have the chosen share of their time left or less (slider, 10% to 90%). Someone missing a buff always comes first, then the most urgent refresh. It works on anyone's buffs, with one exception for Paladins: on you and your group only your own blessings are refreshed (a recast would replace another Paladin's), but on strangers anyone's blessing is.
- **Buff back first** (main page, on by default): when another player puts a new buff on you, they go to the front of the list for 10 seconds. A key press in that time buffs them first, if they need a buff. Casters the game doesn't name are ignored, and nothing is tracked in combat.
- **Buff requests** (main page, on by default): players say `!bom`, `!bow`, `!bok`, `!bos`, `!bol` (Paladin), `!ai`,
  `!dampen`, `!amp` (Mage), `!motw`, `!thorns` (Druid) or `!fort`, `!spirit`, `!shadow` (Priest) in party or raid chat, or
  whisper it to you, and the key buffs them with that instead of their class default. `!none` means no buff from you and
  `!default` resets. Requests are remembered per player (and per caster class) until they change it or you clear it
  (*Clear requests*, or `/wellmet requests clear`; `/wellmet requests` lists them). The game hides chat during encounters,
  Mythic+ and PvP matches, so new requests only arrive outside them. *Announce to group* (button, `/wellmet announce` or
  Ctrl-click on the minimap button) tells the group how to ask. Where the game doesn't let addons send chat, the line is
  put in your chat box and you press Enter.
- **Minimap button**: left-click settings, right-click show / hide the reminder icons, Ctrl-click announce, Shift-click the log.
- Macro: `/click WellMetCast` buffs you and your group. **Strangers need the bound key**: the game won't run the
  targeting macro WellMet uses for them from inside another macro.
- WellMet is quiet by default. If a press does nothing and you want to know why, turn on `/wellmet debug`: it
  shows messages like "Nobody nearby needs ..." and records the log that `/wellmet log` shows.
- `/wellmet` (or `/well`, `/wmet`) settings · `/wellmet strip` · `/wellmet announce` · `/wellmet requests` · `/wellmet log` copyable report · `/wellmet forget` · `/wellmet debug`

## How it picks

You first, then your group, then everyone else (your target and friendly nameplates), nearest first.
Someone who just buffed you goes first for 10 seconds, and someone missing a buff comes before a refresh. It skips people who already have the buff (unless it is nearly gone, see refresh above), are out of range, dead, or that it just tried. A line-of-sight or range failure gets one free retry before the person is skipped for 5 seconds. A player who asked for a buff in chat gets that one instead of their class default.
Players outside your group are only found through **friendly player nameplates** (the settings panel
has a button to turn them on).

## Limits

- Out of combat only: Forever hides aura information in combat, so WellMet can't tell who needs a buff.
- Strangers' distance is only known roughly (about 10 / 28 yards); group members are exact.

## Install

- **CurseForge:** install WellMet from its CurseForge page with your addon manager.
- **By hand:** download the zip from the [GitHub releases](https://github.com/tekHudson/WellMet/releases) and unzip the
  `WellMet` folder into your Forever `Interface/AddOns` folder.

## Bugs and feedback

Open an [issue](https://github.com/tekHudson/WellMet/issues). Turn on `/wellmet debug`, press the key once, and paste
what `/wellmet log` shows: that makes most problems quick to find.

## Development

The logic is tested without the game: `luajit tests/run.lua` (or `lua tests/run.lua`). The tests prove the logic, not the
live client; `tests/TEST_PLAN.md` lists what has to be checked in game.

## License and credits

[MIT](LICENSE), copyright 2026 Tek Hudson. You are free to use, change and share it, as long as you keep the copyright
notice and the license text.

The "WM" lettering in the icon is rendered in IM Fell English SC (SIL Open Font License); only the rendered image is
included. WellMet's approach to targeting strangers by name was learned from how NearbyBuff behaves in game. No code was
copied.
