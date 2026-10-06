# WellMet

One key buffs the next nearby player who needs it. Built for **WoW Forever** (Interface 16001).

Stand at a campfire or run through town, press the key, and your buff goes on someone nearby who
doesn't have it. Press again and it moves on to the next person.

**This first pass is Paladin only** (Blessing of Might / Blessing of Wisdom). Priest, Mage and Druid
are planned.

## Use

- Set the key in the game's own **Key Bindings** window, under **WellMet** (`/wellmet` has an *Open Key Bindings*
  button). The settings panel shows which key is bound.
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
