# NotchCat

A tasks and focus-timer dashboard that lives in your MacBook's notch. Hover the notch (or press **⌥N**) and a tray grows out of it with your tasks and a pomodoro timer. Close it and a slim dot-matrix countdown stays docked beside the notch.

Native macOS app, SwiftUI + AppKit, SQLite storage. Local-first: your data never leaves your Mac.

## Features

- **Notch-anchored tray.** The black shape starts as the notch itself and grows into the dashboard, then retracts straight back up. Driven by Core Animation springs that never overshoot.
- **Workspace cards.** Tasks, Focus timer, Notepad and Events & reminders. Show or hide each one and reorder them in Settings; the tray resizes to fit.
- **Tasks.** Quick add, completion counter, drag to reorder, Today / Tomorrow. Unfinished tasks roll over to the next day.
  - Row menu: Focus, Mark as Done, Rename, Set Time Limit, **Remind Me**, Move to Tomorrow, Duplicate, Delete.
- **Remind Me.** Presets (30 min, 1 hour, this evening, tomorrow morning) or a custom date and time. When it fires, the notch drops a card with the task, **zZ snooze** and **✓ Done**. If the tray is already open it appears as a banner instead.
- **Focus timer.** Seven-segment clock, Start / Pause / Reset, and a duration popover. **Focus** on a task attaches the session to it. The timer pauses while the Mac sleeps.
- **Menu-bar pill.** With a session running and the tray closed, a dot-matrix countdown sits on the right shoulder of the notch. When time is up, the notch drops a "Time's up" card with **+5 min** and **Done**.
- **Notepad.** One note per day, autosaved, with a word count. **⌘↵** turns the line under the cursor into a task and marks it ✓.
- **Events.** Today's Apple Calendar events (read-only) merged with your timed reminders, with "Happening now". Calendar access is optional and only requested when you press Connect.
- **Week.** The next seven days as columns. Drag a task onto any day to re-plan it, or add one in place.
- **Insights.** "Momentum is building" summary, tasks completed vs planned, focus time, and a 7-day stacked bar chart (Tasks / Focus toggle, step back through earlier weeks, tap a bar for details).
- **Settings.** Card visibility and order, Week / Insights tabs, countdown pill, default focus length, sounds, "Time's up" card, reminders and snooze length, hover-to-open, the ⌥N shortcut, paper grain, open at login, database backup, and quit.
- Works on Macs without a notch (the tray opens top-center), though this is less tested.

## Install

NotchCat is open source and not notarized (that needs a paid Apple Developer account), so macOS warns the first time you open a downloaded build. This is expected for an unsigned app.

**Download a build**

1. Grab `NotchCat.dmg` from the [latest release](https://github.com/shimijallores/notchcat/releases/latest).
2. Open it and drag NotchCat onto the Applications shortcut.
3. Launch it from Applications. macOS says it can't verify the developer.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the NotchCat message. Confirm once.

If that option doesn't appear, run this in Terminal, then open the app:

```bash
xattr -dr com.apple.quarantine /Applications/NotchCat.app
```

**Build it yourself** (no warning, since it's built on your own Mac): see [Build and run](#build-and-run).

## Requirements

- macOS 14 or later, Apple silicon
- Xcode 15+ or the Swift toolchain (developed with Xcode 27 / Swift 6.4)

## Build and run

Build a standalone app (release, ad-hoc signed):

```bash
./scripts/build-app.sh
open build/NotchCat.app
```

The app has no Dock icon. Look for the cat in the menu bar. On first launch from Finder you may need to right-click → Open, since it is not notarized.

**From Xcode:** open `Package.swift`, choose the **NotchCat** scheme with **My Mac**, and press ⌘R. Stop that run before launching the packaged app, otherwise two copies compete for ⌥N and each shows a menu-bar cat. Connecting Calendar only works in the packaged app, because macOS needs the usage text from its `Info.plist`; elsewhere the Events card says so and still shows your reminders.

**Build a DMG** to share:

```bash
./scripts/make-dmg.sh   # produces build/NotchCat.dmg
```

Pushing a `v*` tag builds the DMG on a macOS runner and attaches it to a GitHub Release (see `.github/workflows/release.yml`). The build is unsigned either way.

## Using it

| Action | How |
| --- | --- |
| Open the tray | Hover the notch, press **⌥N**, click the pill, or use the menu-bar cat |
| Keep it open | Click anywhere inside it (hover-opened trays close when the pointer leaves) |
| Close it | Click outside, press **Esc**, or press **⌥N** again |
| Quit | Settings → Quit NotchCat, or the menu-bar cat |

Hover opening needs no special permissions. ⌥N is registered through Carbon and also needs none. If another app already owns ⌥N, the hotkey will not register.

## Data

Everything is stored in one SQLite database (WAL mode, no third-party packages):

```
~/Library/Application Support/NotchCat/notchcat.sqlite
```

| Table | Holds |
| --- | --- |
| `tasks` | Title, done state, day, original planned day, order, time limit, reminder |
| `focus_sessions` | Each finished or abandoned session with the seconds it was really running |
| `notes` | One note per day |
| `settings` | App settings as JSON |

Schema changes are versioned migrations (`PRAGMA user_version`, see `Database.swift`). If you used v1, its `state.json` is imported once and kept as `state.json.imported`. **Settings → Back up database** writes a consistent copy to Downloads. A running timer is not persisted across launches.

You can inspect it with `sqlite3 ~/Library/Application\ Support/NotchCat/notchcat.sqlite`.

## Project layout

```
Sources/NotchCat/
  App/      main.swift, AppDelegate (hotkey, menu-bar item, dev flags)
  Data/     Database (SQLite wrapper + migrations), Repositories, DemoData (dev only)
  Models/   TaskStore, NoteStore, FocusTimer, AppSettings, ReminderScheduler,
            CalendarStore (EventKit), InsightsModel
  Notch/    NotchController (hover / click-away / islands / sizing), NotchGeometry,
            NotchPanels, DropContainerView (Core Animation silhouette), HotKey
  Views/    RootView (tabs, workspace, banner, modals), TasksCard, TimerCard, NotepadCard,
            EventsCard, WeekView, InsightsView, SettingsView, IslandView,
            FocusDurationModal, DotMatrix (pill), SevenSegment, Theme
Resources/  Info.plist (menu-bar agent, calendar usage text)
brand/      zi-mascot.png
scripts/    build-app.sh, make-icon.swift
REFERENCE.md  design/behaviour spec this app was built from
```

How the animation works: the SwiftUI tree is laid out once at full size and is not re-rendered while the tray moves. `DropContainerView` animates only a mask (the silhouette, pinned to the top edge) and a transform/opacity on the content, which Core Animation runs off the main thread. Window frames are rounded to whole points so the top edge sits exactly on the screen edge.

## Developer flags

Pass these to `build/NotchCat.app/Contents/MacOS/NotchCat`. Set `NOTCHCAT_DB=/tmp/test.sqlite` to run against a throwaway database; the flags that create data refuse to run without it.

| Flag | Effect |
| --- | --- |
| `--open` / `--open-hover` | Open the tray at launch (pinned / as if hovered) |
| `--tab NAME` / `--tab-after S NAME` | Start on a tab, or switch after S seconds |
| `--demo` / `--demo-secs N` | Start a 25-minute / N-second timer |
| `--close-after S` | Close the tray after S seconds |
| `--seed-demo` | Fill the test database with two weeks of sample history |
| `--remind-in S` | Add a task with a reminder S seconds out |
| `--snapshot DIR` | Render each tab, the modal and the pill to PNGs, then quit |
| `--selftest-note`, `--selftest-settings` | Run non-UI checks and quit |
| `--log-frames` | Log window and mask geometry per frame (stderr) |

## Not built yet

Voice input, MCP / AI-agent integration, and Apple Reminders sync. See `REFERENCE.md` for the full target.

## License

[MIT](LICENSE). The bundled mascot artwork is a project trademark and is not covered by the MIT license.
