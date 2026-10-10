# WellMet: one key, the next buff

Bind one key. Each press buffs **you**, then the **next person nearby who needs it**. Press again and it moves on. No target-clicking, no raid frames, no tracking window. It only answers "who needs what right now?" when you press.

**Built for WoW Forever (Interface 16001).**

## Who it's for

| Class | What it buffs | Extra for yourself |
|---|---|---|
| **Paladin** | One blessing per class: Might, Wisdom, Kings, Salvation (group and you only) or Light. For strangers, an optional secondary blessing when someone else already gave them your primary | Aura (Devotion by default), optional Righteous Fury |
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

## Setting it up

1. Open the settings, **WellMet**, and bind your key. The button jumps straight to it in Key Bindings.
2. Choose the sections and buffs you want.
3. Optional: **Create macro** puts a `/click WellMetCast` macro on your cursor. It buffs you and your group. Strangers need the key, because the game won't run that from inside a macro.

Commands: `/wellmet` (settings), `/wellmet self`, `party`, `others`, `/wellmet macro`, `/wellmet strip`, `/wellmet announce`, `/wellmet requests`, `/wellmet log`, `/wellmet debug`.

## Good to know

- **Out of combat only.** Forever hides other players' buff information in combat, so WellMet can't tell who needs a buff there.
- **Quiet by default.** One line at login, nothing else. Turn on **Debug** to see why a press did nothing and to record a log you can copy.
- Distances for strangers come in 10 and 28 yard steps, because the game doesn't give more.
- Pressing the key on a stranger targets them first, and leaves them targeted.

## Test status

Paladin (blessings), Mage (armor, Arcane Intellect), Druid and Priest (Power Word: Fortitude) are tested in game. **Built but not yet tried in game:** Priest's Divine Spirit, Shadow Protection and Inner Fire, Mage Dampen and Amplify Magic, Paladin auras beyond Devotion, and Righteous Fury. Bug reports are welcome: [GitHub issues](https://github.com/tekHudson/WellMet/issues).

## Credits and license

MIT license. The lettering in the icon is rendered in IM Fell English SC (SIL Open Font License).
