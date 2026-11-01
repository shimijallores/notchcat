# NotchCat

A tasks and focus-timer dashboard that lives in your MacBook's notch. Hover the notch (or press **⌥N**) and a tray grows out of it with your tasks and a pomodoro timer. Close it and a slim dot-matrix countdown stays docked beside the notch.

Native macOS app, SwiftUI + AppKit. Local-first: your data never leaves your Mac.

## Features (v1)

- **Notch-anchored tray.** The black shape starts as the notch itself and grows into the dashboard, then retracts straight back up. It is driven by Core Animation springs and never overshoots.
- **Tasks.** Quick add, completion counter, drag to reorder, Today / Tomorrow. Unfinished tasks roll over to the next day.
  - Row menu: Focus, Mark as Done, Rename, Set Time Limit, Move to Tomorrow, Duplicate, Delete.
- **Focus timer.** Seven-segment clock, Start / Pause / Reset, and a "Focus duration" popover (15 / 25 / 45 / 60 min or custom). Starting **Focus** on a task attaches the session to it and shows an "Active session" badge. The timer pauses while the Mac sleeps.
- **Menu-bar pill.** With a session running and the tray closed, a black capsule with white dot-matrix digits sits on the right shoulder of the notch. Click it to open the tray. It is invisible when idle and blinks amber at 00:00.
- **Time's up island.** When a session ends, the notch stretches into a compact capsule with **+5 min** and **Done**.
- Works on Macs without a notch (the tray opens top-center), though this is less tested.

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

**From Xcode:** open `Package.swift`, choose the **NotchCat** scheme with **My Mac**, and press ⌘R. Run from the `.app` build to see the real mascot, because running through Xcode launches the bare binary without bundled resources.

## Using it

| Action | How |
| --- | --- |
| Open the tray | Hover the notch, press **⌥N**, click the pill, or use the menu-bar cat |
| Keep it open | Click anywhere inside it (hover-opened trays close when the pointer leaves) |
| Close it | Click outside, press **Esc**, or press **⌥N** again |
| Quit | `⋯` menu in the tray header, or the menu-bar cat |

Hover opening needs no special permissions. ⌥N is registered through Carbon and also needs none. If another app already owns ⌥N, the hotkey will not register.

## Data

Tasks and your default focus length are saved as JSON at:

```
~/Library/Application Support/NotchCat/state.json
```

A running timer is not persisted across launches.

## Project layout

```
Sources/NotchCat/
  App/      main.swift, AppDelegate (hotkey, menu-bar item, dev flags)
  Models/   TaskItem, TaskStore (persistence, rollover), FocusTimer
  Notch/    NotchController (hover / click-away / state), NotchGeometry,
            NotchPanels, DropContainerView (Core Animation silhouette), HotKey
  Views/    RootView, TasksCard, TimerCard, IslandView, FocusDurationModal,
            DotMatrix (pill), SevenSegment, Theme
Resources/  Info.plist (menu-bar agent, LSUIElement)
brand/      zi-mascot.png
scripts/    build-app.sh, make-icon.swift
REFERENCE.md  design/behaviour spec this app was built from
```

How the animation works: the SwiftUI tree is laid out once at full size and is not re-rendered while the tray moves. `DropContainerView` animates only a mask (the silhouette, pinned to the top edge) and a transform/opacity on the content, which Core Animation runs off the main thread. Window frames are rounded to whole points so the top edge sits exactly on the screen edge.

## Developer flags

Pass these to `build/NotchCat.app/Contents/MacOS/NotchCat`:

| Flag | Effect |
| --- | --- |
| `--open` | Open the tray at launch (pinned) |
| `--open-hover` | Open the tray as if hovered |
| `--demo` | Start a 25-minute timer |
| `--demo-secs N` | Start an N-second timer (to see the island) |
| `--close-after S` | Close the tray after S seconds |
| `--snapshot DIR` | Render panel / modal / pill PNGs to DIR, then quit |
| `--log-frames` | Log window and mask geometry per frame |

## Not in v1

Insights, Notepad, Events / Calendar, voice input, Remind Me and reminder notifications, the Week and Settings tabs, and MCP / AI-agent integration. See `REFERENCE.md` for the full target.
