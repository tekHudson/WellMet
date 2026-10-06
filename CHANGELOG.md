# Changelog

All notable changes to WellMet are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]
### Added
- First pass (Paladin): one key / `/click WellMetCast` buffs the next nearby player who lacks
  Blessing of Might or Blessing of Wisdom; press again for the next person.
- Candidates: you, your group, your target, and friendly-player nameplates (strangers).
  Order: you, then group, then everyone else; nearest first; arrival order breaks ties.
- Settings: key, search radius (cast range / 28 yd / 10 yd), include strangers, group first, buff myself,
  mounted behavior, and which blessing goes on which target class (plus a default for unreadable classes).
- Remembers who it just tried (so the next press moves on), skips people it couldn't reach
  (out of range / line of sight) and people who already have a stronger buff.
- Slash commands `/wellmet`, `/well` and `/wmet` (not `/wm`: that is Blizzard's world-marker command).
- `/wellmet log` (alias `why`): a copyable report of everyone it can see and why each was picked or
  skipped, plus diagnostics and an event log.
- Out of combat only (aura info is unreadable in combat on Forever); says why whenever it does nothing.
