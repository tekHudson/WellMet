# Changelog

All notable changes to WellMet are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]
### Added
- "Set all classes" on the Party / Raid and Others pages: one icon per buff above the class table. Click a blessing (Paladin)
  to give it to every class, or click it again to clear them all; the red cross skips every class, and Others has a second
  row for the fallback blessing. For Mage, Druid and Priest an icon adds that buff to every class, or removes it when they
  all have it. A count like 4/9 shows when only some classes match, and you can still change any single class afterwards.
- An optional reminder strip (settings > General, or `/wellmet strip`): three small chips, Self / Party / Raid, that show
  how many people the key would buff right now. Orange with a count means someone needs a buff, a check means everyone is
  covered, a grey "?" means the game is hiding buffs (combat). Party is your own party, Raid is the rest of your raid.
  Shift-drag to move it. Off by default.
### Changed
- Someone out of line of sight is skipped for 5 seconds, the same as out of range (was 20, and 60 on a repeat).

## [1.0.0] - 2026-10-07
### Added
- Paladin: **Blessing of Kings**, **Blessing of Salvation** and **Blessing of Light** (with Might and Wisdom, the five
  blessings you keep up for an hour on Forever). One blessing per target class, since a Paladin can only have one
  blessing on a target at a time; the Greater versions count as already having it. Blessing of Protection, Freedom and
  Sacrifice last only 10 to 30 seconds and are left out. Forever has no Sanctuary.
- Salvation, Dampen Magic and Amplify Magic say "party member", so they are offered for your group (and for yourself)
  and never for strangers: they are left out of the Others settings, and refused if one is ever set for a stranger.
- Paladin, Others section: a **secondary blessing** per target class. A Paladin can have only one blessing on a target,
  so when a stranger already wears your primary (say Kings) from another Paladin, the secondary (say Might) is cast
  instead. If one of your own blessings is already on them nothing is cast, so it never replaces your own. It uses the
  game's "who cast this" information; the debug log says when the secondary was chosen. Self and Party / Raid keep a
  single blessing, since in a group people can agree who casts what.
- Main settings page: a **Debug: On / Off** button that shows the state and flips it, next to a plainer **Open log**
  button. The log overview now names the build, so a stale copy is easy to spot.
- The "Nobody nearby needs ..." message names only the buffs that are assigned somewhere.

### Changed
- The debug log keeps only WellMet's own casts (and any cast event within a few seconds of one of its presses),
  instead of every spell you cast, and no longer lists each error message twice.

### Fixed
- The key button is disarmed after every click, so a press in combat (when the game won't let an addon change the
  button) can no longer repeat the previous cast on the previous unit.
- Mashing the key during the global cooldown no longer spams "Spell is not ready yet" or re-targets for nothing: a press
  does nothing until the cooldown is nearly over (a press in the last 0.4 s still goes through, the game queues it). The
  debug log says "press ignored ... is on cooldown".
- Someone out of line of sight is skipped for 20 seconds instead of 5, and for 60 seconds if the same person fails line
  of sight again within two minutes, so one person behind a wall no longer costs a key press every few seconds. Out of
  range stays at 5 seconds. `/wellmet forget` clears the history.
- Strangers' full names are found whatever the nameplate's text field is called, and when they can't be read the log
  says why (hidden name, hidden plate text, or what the plate showed instead).

## [0.1.0-beta.1] - 2026-10-06
First public test release, for WoW Forever (beta, Interface 16001) only.

### Added
- One key buffs you, then the next nearby player who needs it; press again for the next person. Strangers are
  found through friendly player nameplates.
- Paladin: Blessing of Might or Wisdom, chosen per target class. Your own aura (Devotion by default) and
  optional Righteous Fury.
- Mage: Arcane Intellect on mana classes by default (Arcane Brilliance counts as having it), plus optional Dampen
  Magic / Amplify Magic (they replace each other), ticked per class. Your own armor (best Frost / Ice Armor you
  have learned, or Mage Armor).
- Druid: Mark of the Wild on every class by default (Gift of the Wild counts as having it), and optional Thorns.
- Priest: Power Word: Fortitude on every class by default, Divine Spirit on mana classes, optional Shadow
  Protection (the Prayer versions count as having them), and Inner Fire on yourself.
- Settings as a main page plus three sections (Self, Party / Raid, Others), each with its own on/off and its own
  choices. Tick a section on the main page to show its page. Others is off by default. Every choice is an icon
  dropdown; spells you have not learned are greyed out with an "Unknown" tooltip.
- A button on the main page writes the `/click WellMetCast` macro (`/wellmet macro`). The macro buffs you and your
  group; strangers need the bound key.
- The key is set in the game's own Key Bindings window; "Open Key Bindings" opens it filtered to WellMet.
- Minimap button (left-click settings, right-click log, draggable).
- Slash commands `/wellmet`, `/wmet`, `/well`, plus `self`, `party`, `others`, `macro`, `log`, `debug`, `forget`.
  (`/wm` is not used: it is Blizzard's world-marker command.)
- `/wellmet log`: a copyable report of everyone it can see and why each was picked or skipped. Quiet by default;
  turn on Debug to record the log and see why a press did nothing.
- Remembers who it just tried so the next press moves on, and skips people it could not reach (out of range, line
  of sight) or who already have a stronger buff.

### Notes
- Out of combat only: Forever hides other players' buff information in combat.
- Warlock, Warrior, Hunter, Shaman and Rogue: WellMet does not load, because there is nothing to cast on other
  players.
- Tried in game: Paladin blessings, Mage armor and Arcane Intellect, Druid, the settings pages and the macro button.
  Built but not yet tried: Priest, Mage Dampen / Amplify Magic, Paladin auras other than Devotion, Righteous Fury.
