# Changelog

All notable changes to WellMet are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]
### Added
- First pass (Paladin): one key / `/click WellMetCast` buffs the next nearby player who lacks
  Blessing of Might or Blessing of Wisdom; press again for the next person.
- Mage: Arcane Intellect (Arcane Brilliance counts as having it) on mana classes by default, plus optional
  Dampen Magic / Amplify Magic (they replace each other); a checkbox dropdown per target class in settings.
- Your own buffs on the same key, cast on you before anyone else: Paladin aura (Devotion by default) and optional
  Righteous Fury, Mage armor (Frost/Ice "best learned", or Mage Armor), Priest Inner Fire. Spell names checked against
  the Forever spellbook (no Sanctity Aura).
- Priest: Power Word: Fortitude on every class by default, Divine Spirit on mana classes, optional Shadow Protection
  (Prayer of Fortitude / Spirit / Shadow Protection count as already having them), plus Inner Fire on yourself.
- Druid: Mark of the Wild on every class by default (Gift of the Wild counts as having it), and optional Thorns per
  class. (Omen of Clarity is a passive on Forever, so there is nothing to cast.)
- Settings rewritten as a main page plus three sections (Self, Party / Raid, Others), each with its own switch and
  choices; Others is off by default. A button on the main page writes the `/click WellMetCast` macro. Settings from earlier builds
  are migrated.
- `/wellmet probe` (temporary): finds out whether party and raid chat can be read and sent from the addon.
- Classes that can't buff other players (Warlock, Warrior, Hunter, Shaman, Rogue) get no WellMet at all: nothing is
  created or printed.
- Settings show a buff you haven't learned greyed out, with its own icon and an "Unknown" tooltip.
- Candidates: you, your group, your target, and friendly-player nameplates (strangers).
  Order: you, then group, then everyone else; nearest first; arrival order breaks ties.
- Settings: key, search radius (cast range / 28 yd / 10 yd), include strangers, group first, buff myself,
  mounted behavior, and which blessing goes on which target class (a person whose class can't be read is skipped).
- Remembers who it just tried (so the next press moves on), skips people it couldn't reach
  (out of range / line of sight) and people who already have a stronger buff.
- Slash commands `/wellmet`, `/well` and `/wmet` (not `/wm`: that is Blizzard's world-marker command).
- `/wellmet log` (alias `why`): a copyable report of everyone it can see and why each was picked or
  skipped, plus diagnostics and an event log.
- Out of combat only (aura info is unreadable in combat on Forever); says why whenever it does nothing.
