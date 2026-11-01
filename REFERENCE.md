# NotchCat — Reference Spec

Derived from a reference screen recording and its product website. This is the
design/behavior target. "NotchCat" is the app name (mascot: `brand/zi-mascot.png`).

## Product in one line
A macOS notch-anchored productivity dashboard: hover the notch (or press a hotkey) to pull
down a floating card shelf with tasks, a focus timer, a notepad, and calendar/reminders.
Collapsed, a running timer lives as a dot-matrix pill beside the notch. Local-first.

## The shell
- Single continuous dark/near-black rounded housing, anchored under the notch, horizontally centered.
- Expanded: ~60–70% of screen width, ~30–35% of screen height. Lower two-thirds of desktop stays visible.
- Compact (tasks only): tight ~400–450px centered box; widens as cards are added.
- Inside the housing: separate pastel inset cards, 8–12px dark gaps, each its own color + subtle paper/grain texture.

## Cards & palette
- Tasks        → muted mint green
- Focus timer  → soft lavender
- Notepad      → olive / sand
- Events       → dusty slate blue
- Insights     → green summary card + lavender chart card

## Top bar
Left: mascot icon + "NotchCat" + "Open app" shortcut.
Right: Workspace | Insights | Settings (later revisions: "Customize" + a "Week" tab).

## Window states
1. Expanded — full dashboard; pulls straight down from the notch.
2. Collapsed + timer running — black rounded capsule docked to the RIGHT SHOULDER of the
   notch, inline with menu-bar height (NOT under the notch). White retro dot-matrix digits
   counting down (e.g. 24:58 → 00:00). No task title / ring / hover buttons in the pill.
3. Idle — pill fully invisible; only the hardware notch shows.

## Dynamic-Island style events
- Reminder fires → notch expands to a compact card: mascot avatar, reminder title,
  "zZ 5 min" snooze button, orange "✓ Done" button.
- Timer hits 00:00 → reopening shows a lavender "Time's up" card with inline "+ Add 5 min".

## Animation
- Expand ~250–300ms, fast ease-out damping, firm stop, NO bounce/overshoot.
- Slides straight down out of the notch; retracts straight back up behind the bezel.

## Workspace — Tasks card
- Quick entry: "+ What needs doing?" (Enter appends).
- Completion counter e.g. 0/2.
- Drag-to-reorder with handles; footer "Drag to reorder" + active date (e.g. Wed, 16 Sep).
- Per-task context menu (three dots): Focus, Mark as Done, Rename…, Set Time Limit…,
  Remind Me ▸ (In 30 Minutes / In 1 Hour / This Evening / Tomorrow Morning / Custom…),
  Move to Tomorrow, Duplicate, Delete.
- Choosing a reminder adds a time badge under the task AND mirrors into the Events card.
- Voice input: circular mic button by "+ Add a task…" → "🎙 Listening…" + waveform →
  live transcription → saves to the list.

## Workspace — Focus timer card (lavender)
- Large seven-segment style countdown (default 25:00).
- Status text: Ready / Remaining.
- Start/Pause toggle; "Set time" button with analog-clock icon.
- "Set Time Limit…" opens a "Focus duration" modal: presets 15m / 25m / 45m / 60m + custom stepper + Save.
- Starting focus sets the timer (e.g. 45:00) and shows an "Active session" pulse badge on the task.

## Workspace — Notepad card (olive/sand)
- Current date header; placeholder "Write something down…"; live word counter ("0 words").
- (Website) ⌘-Return turns the current line into a task. (Not shown in video.)

## Workspace — Events & Reminders card (slate blue)
- Upcoming blocks (e.g. "Testing 4:00 PM – 5:00 PM", "Happening now").
- Synced reminders. Corner "Connected" indicator.

## Insights tab
- Left card (green): "Momentum is building" — "33 tasks done, up from 20 the week before,
  with 7h 50m focused". Big metric 33 (of 42 planned). Secondary: Focus time 7h 50m, Active days.
- Right card (lavender): segmented toggle Tasks | Focus; date range (e.g. 23 Oct – 29 Oct);
  Y-axis 0–8; 7-day stacked bar chart (Completed darker / Planned lighter top); "Select a day".

## Settings / Customize
- Never opened on camera. Known from site: AI agents section with one-click Connect for
  Claude Code / Claude app / Cursor; Reminders sync toggle; license; JSON export.

## MCP (shown via terminal)
- `claude` shows the app's MCP server as connected.
- Prompt "plan my afternoon: call mom at 5pm, gym after work (high)" → Claude calls the
  app's `add_tasks` tool → tasks appear in the list in real time.

## Platform / constraints (from site)
- macOS 14+, Apple silicon. Local-first; offline after activation. Optional EventKit
  (Calendar read-only, Reminders read/write) and on-device Speech. One-time license.
- No-notch fallback (top-center panel + full dashboard) stated on site but NOT in any video.
