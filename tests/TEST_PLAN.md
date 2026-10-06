# WellMet — in-game test plan (WoW Forever, build 1.60.1.70205)

Run `luajit tests/run.lua` first (expect `93 passed, 0 failed`). The headless tests prove the logic against
the *documented* API; this plan settles what only the real client can answer.

Setup: addon is symlinked into `_classic_beta_/Interface/AddOns/WellMet`. Use a **Paladin**.
`/console scriptErrors 1` so Lua errors show. After any code change: `/reload`.
Everywhere below, **"paste the log"** = `/wellmet log` → click in the text → Ctrl+A, Ctrl+C → paste to me.

## Questions this plan answers (from the design prompt)

| # | Question | Where |
|---|---|---|
| A1 | Can we read a stranger's class / GUID / name out of combat? | T3 (report: `class=… guid=readable/UNREADABLE`) |
| A2 | Are friendly nameplates available, and how far away do they appear? | T3, T4 |
| A3 | Does `IsSpellInRange` work on stranger nameplate units? | T3 (skip reason "range unknown" vs "out of cast range") |
| A4 | Are strangers' auras readable out of combat? | T3 ("aura info unavailable" vs "already has …") |
| A5 | Does picking in PreClick (same press as the cast) work? | T2 |
| A6 | Does the Key Bindings entry appear and work, and `/click WellMetCast`? | T1, T2 |
| A7 | Real spell names / ids for the blessings | T1 (report: `buff MIGHT … id=…`) |
| A8 | How often does a cast fail after the range check (line of sight)? | T6 |

## T1 — Loads
1. Log in. Expect `WellMet: v0.1.0 loaded.` and **no Lua error**. AddOn list: WellMet not "Incompatible".
2. `/wellmet` opens the settings panel (stock look). `Esc` → Options → Key Bindings → AddOns: a **WellMet**
   section with "Buff the next nearby player".
3. `/wellmet log` → paste. (Check the `buff MIGHT/WISDOM` lines: ids resolved, `known=yes`.)

## T2 — The key press casts (A5, A6)
1. Game menu → Options → **Key Bindings** → **WellMet** → bind "Buff the next nearby player" (e.g. `F8`), or use the
   *Open Key Bindings* button in `/wellmet`. The panel then shows `Key: F8`.
2. Remove your Wisdom/Might buff. Press **F8**: one press should **cast on yourself** (Paladin → Wisdom by default).
   Chat: `Buffed <you> with Blessing of Wisdom.` If it only says "armed" in the log but nothing casts,
   PreClick arming doesn't apply to the same click — paste the log.
3. Try the macro: `/click WellMetCast` in a macro on your bar. It should buff you or a group member; with only
   strangers left it prints that strangers need the bound key (verified 2026-10-06).
4. Press again with nobody else around: expect `Nobody nearby needs Blessing of Might / Blessing of Wisdom.`

## T3 — Strangers via nameplates (A1–A4)
1. Settings: turn on friendly nameplates if the panel shows them OFF (button), keep "Include players outside my group" checked.
2. Stand near other players (city, campfire). **Paste the log without pressing** (the "Right now" section lists
   everyone seen: class readable? guid readable? eligible/skipped and why).

## T4 — Cycling through people (the main feature)
1. Near several unbuffed players press the key repeatedly: each press should buff a **different** person,
   group first, then nearest strangers. Note any press that says nobody needs a buff while people clearly do.
2. After 3–4 presses: paste the log (shows each pick: tier, distance, "tried recently" skips).

## T5 — Settings
- **Radius**: cycle Cast range → 28 → 10 yd; with a stranger ~20 yd away, 10 yd should skip them.
- **Assignments**: set Warrior → Wisdom / Skip; press near a warrior: matches. Set an unreadable-class default.
- **Group first** off, **Buff myself** off: behave as labelled.

## T6 — Failures (A8)
- Stand so a player is behind a wall: the cast fails with line of sight; the **next press must go to someone else**
  (log: `cast failed … skipping <name> for 5s`).
- Someone with a stronger blessing from another paladin: skip for 5 minutes.

## T7 — Guards
In combat (pull a mob): press → "Can't buff in combat." Mounted: "Dismount first" (setting allows it). Flying: refuses.

## What to send back
`/wellmet log` pastes from T1, T3, T4 (and T6 if anything odd), plus any Lua error text and anything that felt wrong.
