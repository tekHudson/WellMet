# WellMet

One key buffs the next nearby player who needs it. Built for **WoW Forever** (Interface 16001).

> **Beta.** This is an early test release (0.1.0-beta.1). It only works on the WoW Forever beta client.

Stand at a campfire or run through town, press the key, and your buff goes on someone nearby who
doesn't have it. Press again and it moves on to the next person.

WellMet is for classes that buff **other players**: **Paladin** (Blessing of Might / Wisdom, one per class), **Mage**
(Arcane Intellect, plus optional Dampen / Amplify Magic, ticked per class), **Druid** (Mark of the Wild, optionally
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
- Macro: `/click WellMetCast` buffs you and your group. **Strangers need the bound key**: the game won't run the
  targeting macro WellMet uses for them from inside another macro.
- WellMet is quiet by default. If a press does nothing and you want to know why, turn on `/wellmet debug`: it
  shows messages like "Nobody nearby needs ..." and records the log that `/wellmet log` shows.
- `/wellmet` (or `/well`, `/wmet`) settings · `/wellmet log` copyable report · `/wellmet forget` · `/wellmet debug`

## How it picks

You first, then your group, then everyone else (your target and friendly nameplates), nearest first.
It skips people who already have the buff, are out of range, dead, or that it just tried.
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
