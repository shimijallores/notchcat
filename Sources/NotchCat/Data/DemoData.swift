import AppKit

/// Developer tool (`--seed-demo`): fills a *throwaway* database with a believable fortnight of history
/// so the Week and Insights tabs can be checked. Refuses to run against the real database.
enum DemoData {
    static func seed(into db: Database) {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else {
            NSLog("NotchCat: --seed-demo needs NOTCHCAT_DB so it can't touch real data")
            return
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

        let tasks = TaskRepository(db: db)
        let sessions = SessionRepository(db: db)
        var position = 0
        func add(_ title: String, _ offset: Int, done: Bool = false, limit: Int? = nil,
                 remind: Date? = nil, planned: Int? = nil, completedHour: Int = 14) {
            var t = TaskItem(title: title, day: day(offset), timeLimitMinutes: limit)
            t.plannedDay = day(planned ?? offset)
            t.isDone = done
            if done { t.completedAt = cal.date(bySettingHour: completedHour, minute: 10, second: 0, of: day(offset)) }
            t.remindAt = remind
            t.createdAt = day(min(offset, 0)).addingTimeInterval(-3600)
            tasks.upsert(t, position: position)
            position += 1
        }

        // The last fortnight: a varied number planned and completed each day.
        let history: [(Int, Int)] = [(-13, 3), (-12, 4), (-11, 2), (-10, 5), (-9, 3), (-8, 1), (-7, 4),
                                     (-6, 3), (-5, 5), (-4, 6), (-3, 4), (-2, 6), (-1, 7)]
        for (offset, count) in history {
            for i in 0..<count {
                let doneIt = i < count - (offset % 3 == 0 ? 1 : 0)
                add("Past task \(i + 1)", offset, done: doneIt, completedHour: 9 + i)
            }
            let minutes = [25, 50, 75, 100, 45, 125, 25, 90, 60, 150, 35, 105, 80][history.firstIndex { $0.0 == offset }!]
            sessions.insert(FocusSession(taskID: nil, startedAt: day(offset).addingTimeInterval(10 * 3600),
                                         activeSeconds: minutes * 60, plannedSeconds: minutes * 60, completed: true))
        }

        // Today, tomorrow and the week ahead.
        add("Design the landing page", 0)
        add("Review PR for course enrollment", 0, limit: 45, remind: Date().addingTimeInterval(30 * 60))
        add("Reply to emails", 0, done: true)
        add("Call mom", 0, remind: cal.date(bySettingHour: 17, minute: 0, second: 0, of: today))
        add("Plan the sprint", 1)
        add("Buy flowers", 1)
        add("Gym after work", 2)
        add("Write release notes", 3)
        add("Dentist", 3)
        add("Pay rent", 5)
        add("Team lunch", 6)

        NoteRepository(db: db).save("Ideas for the demo\n- ship v2\n- record a walkthrough\nCall the plumber", for: today)
    }
}

/// Developer checks (`--selftest-note`) that exercise UI logic without needing clicks. Throwaway DB only.
@MainActor
enum SelfTest {
    static func noteConversion() {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else { return }
        let store = TaskStore.shared
        let tv = NoteTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        var created: [String] = []
        tv.onConvertLine = { line in created.append(line); store.add(title: line, day: .today); return true }
        tv.string = "Buy milk\nCall dentist\n\n✓ already done\nLast line no newline"

        func cmdReturn(atLine marker: String) {
            let r = (tv.string as NSString).range(of: marker)
            tv.setSelectedRange(NSRange(location: r.location + 1, length: 0))
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                     isARepeat: false, keyCode: 36)!
            tv.keyDown(with: e)
        }
        cmdReturn(atLine: "Buy milk")
        cmdReturn(atLine: "Call dentist")
        cmdReturn(atLine: "Buy milk")          // already converted: must not duplicate
        cmdReturn(atLine: "✓ already done")    // pre-marked: must be ignored
        cmdReturn(atLine: "Last line")         // no trailing newline
        // blank line
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).range(of: "dentist\n\n").location + 9, length: 0))
        let blank = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        tv.keyDown(with: blank)

        print("created tasks: \(created)")
        print("text now: \(tv.string.debugDescription)")
        print("tasks in store: \(store.tasks.map(\.title))")
    }

    static func settings() {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else { return }
        let db = Database.shared
        let a = AppSettings(db: db)
        a.setEnabled(.notepad, false)
        a.setEnabled(.events, false)
        a.moveCard(.timer, by: -1)
        a.data.showWeekTab = false
        a.data.defaultFocusMinutes = 50
        print("after edits:      visible=\(a.visibleCards.map(\.rawValue)) order=\(a.data.cards.map(\.card.rawValue))")

        a.setEnabled(.timer, false)
        a.setEnabled(.tasks, false)   // would leave zero cards: must be refused
        print("zero-card guard:  visible=\(a.visibleCards.map(\.rawValue))")

        let b = AppSettings(db: db)  // simulates a relaunch
        print("after relaunch:   visible=\(b.visibleCards.map(\.rawValue)) week=\(b.data.showWeekTab) focus=\(b.data.defaultFocusMinutes) hover=\(b.data.hoverToOpen)")

        // An older/partial settings row must still load, with defaults for anything missing.
        _ = try? db.run("UPDATE settings SET value = ? WHERE key = 'app'", [.text("{\"showWeekTab\":false,\"cards\":[{\"card\":\"notepad\",\"enabled\":true}]}")])
        let c = AppSettings(db: db)
        print("partial row:      order=\(c.data.cards.map(\.card.rawValue)) enabled=\(c.visibleCards.map(\.rawValue)) week=\(c.data.showWeekTab) insights=\(c.data.showInsightsTab) snooze=\(c.data.snoozeMinutes)")

        _ = try? db.run("UPDATE settings SET value = 'not json at all' WHERE key = 'app'")
        let d = AppSettings(db: db)
        print("corrupt row:      falls back to defaults -> visible=\(d.visibleCards.map(\.rawValue)) focus=\(d.data.defaultFocusMinutes)")
    }
}
