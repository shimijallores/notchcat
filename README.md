# NotchCat

Tasks and a focus timer that live in your MacBook's notch. Hover the notch (or press **⌥N**) and a tray grows out of it. Close it and a slim countdown stays beside the notch.

Native macOS app (SwiftUI + AppKit) with SQLite storage. Your data stays on your Mac unless you sign in to a sync server.

## Features

- **Notch tray.** Grows out of the notch and retracts back into it.
- **Cards.** Tasks, Focus timer, Notepad, Events & reminders. Show, hide and reorder them in Settings.
- **Tasks.** Quick add, drag to reorder, Today / Tomorrow. Unfinished tasks roll over to the next day. Tasks with a time limit add up to a finish time in the footer, e.g. `5:41pm (1h 40m)`.
- **Remind Me.** Pick a preset or a custom time. The notch drops a card with snooze and Done.
- **Focus timer.** Start, pause and reset. **Focus** on a task attaches the session, and the task is marked done at 00:00. Pauses while the Mac sleeps.
- **Menu-bar pill.** A dot-matrix countdown beside the notch while the tray is closed.
- **Notepad.** One note that never resets. **⌘↵** moves the current line into Today's tasks (⌘Z undoes it).
- **Events.** Today's Apple Calendar events (read-only) and your reminders. Calendar access is optional.
- **Week.** The next seven days as columns. Drag a task to another day.
- **Insights.** Weekly summary, a 7-day chart, and **History**: finished tasks by day, with search and **Restore to Today**.
- **Now Playing** (off by default). Spotify / Apple Music card and an album-art chip beside the notch.
- **Cloud sync** (optional, invite only). Syncs tasks, the notepad, focus sessions and shared settings across devices. Works offline and catches up when you reconnect. See [Cloud sync](#cloud-sync).
- **Fake notch** for Macs without one: a black **Notch** or a floating **Island**. Settings → Appearance.
- **Battery** percentage in the tray header, and an **Update available** button when a newer release is on GitHub. Both can be turned off.

## Install

NotchCat isn't notarized (that needs a paid Apple Developer account), so macOS warns the first time.

1. Download `NotchCat.dmg` from the [latest release](https://github.com/shimijallores/notchcat/releases/latest).
2. Open it and drag NotchCat to Applications.
3. Open it. When macOS says it can't verify the developer, go to **System Settings → Privacy & Security** and click **Open Anyway**.

If that option doesn't appear, run this and open the app again:

```bash
xattr -dr com.apple.quarantine /Applications/NotchCat.app
```

Or [build it yourself](#build). Look for the cat in the menu bar: there's no Dock icon.

## Requirements

- macOS 14 or later, Apple silicon
- Xcode 15+ or the Swift toolchain

## Build

```bash
./scripts/build-app.sh      # build/NotchCat.app
./scripts/make-dmg.sh       # build/NotchCat.dmg
```

From Xcode, open `Package.swift`, pick the **NotchCat** scheme and press ⌘R. Stop that run before launching the packaged app, or both will fight over ⌥N. Calendar access only works in the packaged app.

## Using it

| Action | How |
| --- | --- |
| Open the tray | Hover the notch, press **⌥N**, click the pill, or use the menu-bar cat |
| Keep it open | Click inside it |
| Close it | Click outside, press **Esc**, or press **⌥N** again |
| Quit | Settings → Quit NotchCat, or the menu-bar cat |

## Cloud sync

Settings → Cloud sync has **Sign in** and **Sign up**. Signing up needs an **access key** from the server's owner; after the key is accepted you choose a username and password. The server is the separate [notchcat-server](https://github.com/shimijallores/notchcat-server) project. If the notepad is edited on two devices at once, both versions are kept. Design notes: [docs/SYNC_PLAN.md](docs/SYNC_PLAN.md).

## Now Playing and privacy

Track info comes from notifications Spotify and Music already broadcast, with no permission needed. Nothing is sent to either app until you turn Now Playing on. After that, macOS asks for **Automation** permission the first time you use the controls or load artwork. NotchCat never launches a player and doesn't use private APIs.

## Data

One SQLite database:

```
~/Library/Application Support/NotchCat/notchcat.sqlite
```

| Table | Holds |
| --- | --- |
| `tasks` | Tasks |
| `focus_sessions` | Finished and abandoned focus sessions |
| `notes` | The notepad |
| `settings` | Settings as JSON |
| `task_sync`, `sync_meta` | Cloud sync bookkeeping (the login is in the Keychain) |

Schema changes are versioned migrations. **Settings → Back up database** saves a copy to Downloads. A running timer isn't saved across launches.

## Project layout

```
Sources/NotchCat/
  App/      entry point, AppDelegate (hotkey, menu-bar item, dev flags)
  Data/     SQLite wrapper and migrations, repositories, demo data
  Models/   stores and services (tasks, notes, timer, settings, music, battery, updates)
  Sync/     sync engine, API client, Keychain
  Notch/    tray controller, notch geometry, panels, animation container
  Views/    SwiftUI views and theme
Resources/  Info.plist
scripts/    build-app.sh, make-dmg.sh
```

## Developer flags

Pass these to `build/NotchCat.app/Contents/MacOS/NotchCat`. Set `NOTCHCAT_DB=/tmp/test.sqlite` to use a throwaway database. Flags that create data refuse to run without it.

| Flag | Effect |
| --- | --- |
| `--open` / `--open-hover` | Open the tray at launch |
| `--tab NAME` / `--tab-after S NAME` | Start on a tab, or switch after S seconds |
| `--demo-secs N` | Start an N-second timer |
| `--close-after S` | Close the tray after S seconds |
| `--seed-demo` | Fill the test database with sample data |
| `--remind-in S` | Add a reminder S seconds out |
| `--snapshot DIR` | Render each tab to PNGs, then quit |
| `--selftest-note`, `-settings`, `-music`, `-focus`, `-update`, `-sync` | Run a non-UI check and quit (`-sync` needs a running server) |
| `--fake-music` | Show a fake playing track |
| `--fake-notch off\|notch\|island` | Set the fake notch style |
| `--log-frames` | Log tray geometry per frame |
| `NOTCHCAT_FORCE_NO_NOTCH=1` | Treat the screen as notch-less |
| `NOTCHCAT_NO_APPLESCRIPT=1` | Never send AppleScript to other apps |

## Not built yet

Voice input, MCP / AI-agent integration, Apple Reminders sync. iOS and Windows apps are planned.

## License

[MIT](LICENSE). The bundled mascot artwork is a project trademark and isn't covered by the MIT license.
