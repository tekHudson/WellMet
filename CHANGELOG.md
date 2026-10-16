# Changelog

All notable changes to WellMet are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.2.3] - 2026-10-16
### Changed
- Announce, when the game blocks addon chat, now fills your chat box with `ChatFrameUtil.OpenChat`; the old `ChatFrame_OpenChat` name is a deprecated alias that Blizzard says will be removed. The "Can't announce right now" chat message is gone, since the chat box filling in is the sign it worked (it is still in `/wellmet log`).

## [1.2.2] - 2026-10-14
### Changed
- The Self and Group reminder icons now use the same gold glow with a crawling edge that action buttons show for a proc, instead of a plain gold border.

## [1.2.1] - 2026-10-14
### Changed
- The main settings page was getting long, so two pages moved under WellMet: **Priority** (buff back first, refresh running-out buffs and its slider) and **Group tools** (the reminder icons, buff requests). `/wellmet priority` and `/wellmet tools` open them.

## [1.2.0] - 2026-10-14
### Added
- Buff back first (settings > Refresh running-out buffs, on by default): when another player puts a new buff on you, they go to the front of the list for 10 seconds. A key press in that time buffs them first, if they need a buff. Only new buffs count, and only when the game says who cast them (an unknown caster is ignored); nothing is tracked in combat. `/wellmet log` shows who buffed you in the last 10 seconds.
- Refresh running-out buffs (settings > Refresh running-out buffs, on by default at 20%): once nobody nearby is missing a buff, the key recasts buffs that have the chosen share of their time left or less (10% to 90% slider). Someone missing a buff always comes first, then the most urgent refresh. Works for anyone's buffs, strangers included. For a Paladin, only your own blessings are refreshed on you and your group (a recast would replace another Paladin's), but on strangers (Others) anyone's blessing is refreshed. The Self and Group reminder icons count a buff that is running out as needing one, and `/wellmet log` marks refreshes in the eligible list.
- Debug log: a "Buff time left" section lists, for everyone nearby, each of your buffs that is on them, who cast it and how long is left on it (or that the game does not give the time). It is a probe for refreshing buffs that are about to run out.

### Changed
- A line-of-sight or out-of-range failure now gets one free retry: the first one doesn't skip anyone, so the next press tries them again; a second failure within 30 seconds skips them for 5 seconds as before. A cast that lands resets it. "A more powerful spell is already active" still skips for 5 minutes.

### Fixed
- The debug log's "recently tried" line no longer loses the first letter of "Righteous Fury" (the game read the separator as a colour code).

## [1.1.1] - 2026-10-12
### Changed
- Buff requests are on by default for new profiles (a profile saved earlier keeps its choice), and are no longer labelled beta.

## [1.1.0] - 2026-10-11
### Added
- Buff requests (beta; settings > Buff requests, on by default): players say `!bom`, `!bow`, `!fort`, `!ai` ... (or `!none`,
  `!default`) in party or raid chat, or whisper it to you, and the key buffs them with that instead of their class default.
  Requests are remembered per player (and per caster class) until they change it or you clear it (`/wellmet requests clear`,
  or the Clear requests button). Switching the setting off stops listening and ignores saved requests. Chat is hidden by the
  game during encounters, Mythic+ and PvP, so new requests only arrive outside them.
- Announce how to ask: the Announce to group button, `/wellmet announce` or Ctrl-click on the minimap button posts the request
  words to party / raid / instance chat, only when you ask. Where the game does not let addons send chat (some realms, and
  encounters, Mythic+ and PvP matches) the line is put in your chat box for you to send with Enter instead.
- `/wellmet requests` lists the saved requests; the log report has a Buff requests section.
- Debug chat probe: while debug is on, the log records whether WellMet could read each whisper, Battle.net whisper,
  party, raid and raid warning message (text, sender and guid readable or secret, text length, whether it began with
  "!", and the chat-lockdown state). It never records what was said or who said it. `/wellmet log` has a "Chat reading"
  section with per-channel counts. Nothing is listened to while debug is off.
- "Set all classes" on the Party / Raid and Others pages: one icon per buff above the class table. Click a blessing (Paladin)
  to give it to every class, or click it again to clear them all; the red cross skips every class, and Others has a second
  row for the fallback blessing. For Mage, Druid and Priest an icon adds that buff to every class, or removes it when they
  all have it. A count like 4/9 shows when only some classes match, and you can still change any single class afterwards.
- An optional reminder strip (settings > Buff reminder, or `/wellmet strip`): two action-button style icons, Self and Group
  (your party and raid together). An icon glows gold when the key would buff someone in it, goes dark with a green check
  when everyone is covered, and shows a grey ? when the game hides buffs (combat). An icon whose section is switched
  off is not drawn. "Show only when a buff is missing" draws an icon only while it needs one. Shift-drag to move it.
  Off by default.
### Changed
- The settings pages scroll, so nothing is cut off when a page is taller than the window.
- Minimap button: right-click now shows / hides the reminder icons; the log moved to Shift-click.
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
