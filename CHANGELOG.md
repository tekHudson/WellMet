# Changelog

All notable changes to WellMet are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]
### Added
- Paladin: **Blessing of Kings**, **Blessing of Salvation** and **Blessing of Light** (with Might and Wisdom, the five
  blessings you keep up for an hour on Forever). One blessing per target class, since a Paladin can only have one
  blessing on a target at a time; the Greater versions count as already having it. Blessing of Protection, Freedom and
  Sacrifice last only 10 to 30 seconds and are left out. Forever has no Sanctuary.
- Salvation, Dampen Magic and Amplify Magic say "party member", so they are offered for your group (and for yourself)
  and never for strangers: they are left out of the Others settings, and refused if one is ever set for a stranger.
- The "Nobody nearby needs ..." message names only the buffs that are assigned somewhere.

### Fixed
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
