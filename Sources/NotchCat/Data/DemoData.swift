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
        @discardableResult
        func add(_ title: String, _ offset: Int, done: Bool = false, limit: Int? = nil,
                 remind: Date? = nil, planned: Int? = nil, completedHour: Int = 14) -> UUID {
            var t = TaskItem(title: title, day: day(offset), timeLimitMinutes: limit)
            t.plannedDay = day(planned ?? offset)
            t.isDone = done
            if done { t.completedAt = cal.date(bySettingHour: completedHour, minute: 10, second: 0, of: day(offset)) }
            t.remindAt = remind
            t.createdAt = day(min(offset, 0)).addingTimeInterval(-3600)
            tasks.upsert(t, position: position)
            position += 1
            return t.id
        }
        let titles = ["Review pull request", "Write release notes", "Reply to emails", "Plan the sprint", "Fix login bug",
                      "Update the docs", "Design landing page", "Call the dentist", "Buy groceries", "Refactor storage layer"]

        // The last fortnight: a varied number planned and completed each day.
        let history: [(Int, Int)] = [(-13, 3), (-12, 4), (-11, 2), (-10, 5), (-9, 3), (-8, 1), (-7, 4),
                                     (-6, 3), (-5, 5), (-4, 6), (-3, 4), (-2, 6), (-1, 7)]
        for (offset, count) in history {
            var firstDone: UUID?
            for i in 0..<count {
                let doneIt = i < count - (offset % 3 == 0 ? 1 : 0)
                let id = add(titles[(i + abs(offset)) % titles.count], offset, done: doneIt, completedHour: 9 + i)
                if doneIt, firstDone == nil { firstDone = id }
            }
            let minutes = [25, 50, 75, 100, 45, 125, 25, 90, 60, 150, 35, 105, 80][history.firstIndex { $0.0 == offset }!]
            sessions.insert(FocusSession(taskID: firstDone, startedAt: day(offset).addingTimeInterval(10 * 3600),
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

        NoteRepository(db: db).saveMain("Ideas for the demo\n- ship v2\n- record a walkthrough\nCall the plumber")
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
        cmdReturn(atLine: "✓ already done")    // pre-marked: must be ignored
        cmdReturn(atLine: "Last line")         // no trailing newline
        // blank line (the converted lines are gone, so the empty line is now first)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        let blank = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        tv.keyDown(with: blank)

        print("created tasks: \(created)")
        print("text now: \(tv.string.debugDescription)")
        print("tasks in store: \(store.tasks.map(\.title))")
    }

    /// `--selftest-focus`: a session on a task that runs to 00:00 completes that task; an abandoned one does not.
    static func focusCompletion() {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else { return }
        let store = TaskStore.shared
        let timer = FocusTimer.shared
        store.add(title: "Finishes", day: .today)
        store.add(title: "Abandoned", day: .today)
        store.add(title: "No task", day: .today)
        let finishes = store.tasks.first { $0.title == "Finishes" }!.id
        let abandoned = store.tasks.first { $0.title == "Abandoned" }!.id

        func status(_ title: String) -> String {
            guard let t = store.tasks.first(where: { $0.title == title }) else { return "missing" }
            return t.isDone ? "done(completedAt set: \(t.completedAt != nil))" : "open"
        }

        timer.startDemo(seconds: 60, taskID: abandoned)
        timer.reset()                                  // abandoned before the end
        print("abandoned session:  \(status("Abandoned"))")

        timer.startDemo(seconds: 1)                    // no task attached
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            print("no-task session:    task list unchanged -> \(store.tasks.filter(\.isDone).count) done")
            timer.reset()
            timer.startDemo(seconds: 1, taskID: finishes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                print("finished session:   \(status("Finishes"))")
                let before = store.tasks.first { $0.id == finishes }?.completedAt
                store.markDone(finishes)               // doing it again must not undo or re-stamp
                let after = store.tasks.first { $0.id == finishes }
                print("markDone twice:     isDone=\(after?.isDone ?? false) sameStamp=\(after?.completedAt == before)")
                exit(0)
            }
        }
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

    static func music() {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else { return }
        let m = MusicService.shared
        m.setActive(true)

        func post(_ name: String, _ info: [String: Any]) {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(name), object: nil,
                                                                         userInfo: info, deliverImmediately: true)
        }
        func show(_ label: String) {
            if let np = m.nowPlaying {
                print("\(label): \(np.source.displayName) | \(np.title) - \(np.artist) | playing=\(np.isPlaying) | dur=\(Int(np.duration))s pos=\(String(format: "%.1f", np.position()))s")
            } else {
                print("\(label): nothing")
            }
        }
        let spotify = "com.spotify.client.PlaybackStateChanged", music = "com.apple.Music.playerInfo"
        let steps: [(Double, () -> Void)] = [
            (0.0, { post(spotify, ["Player State": "Playing", "Name": "Blinding Lights", "Artist": "The Weeknd",
                                    "Album": "After Hours", "Duration": 200040, "Playback Position": 42.5]) }),
            (0.3, { show("1 spotify playing  ") }),
            (1.3, { show("2 +1s later        ") }),
            (1.4, { post(music, ["Player State": "Playing", "Name": "Heat Waves", "Artist": "Glass Animals",
                                  "Album": "Dreamland", "Total Time": 238000]) }),
            (1.7, { show("3 music started    ") }),
            (1.8, { post(music, ["Player State": "Paused", "Name": "Heat Waves", "Artist": "Glass Animals",
                                  "Album": "Dreamland", "Total Time": 238000]) }),
            (2.1, { show("4 music paused     ") }),
            (2.2, { post(spotify, ["Player State": "Stopped"]) }),
            (2.5, { show("5 spotify stopped  ") }),
            (2.6, { post(music, ["Player State": "Stopped"]) }),
            (2.9, { show("6 all stopped      ") }),
            (3.0, { post(spotify, ["Player State": "Playing", "Name": "", "Artist": "x"]) }),
            (3.3, { show("7 empty name ignored") }),
            (3.4, { m.runPlainScript("return \"script queue ok: \" & ((1 + 1) as text)") { print($0) } }),
        ]
        for (t, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t) { f() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { exit(0) }
    }

    /// Visual check: card + chip on, a fake "Playing" notification, and a generated cover image.
    static func fakeMusic() {
        guard ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil else { return }
        let settings = AppSettings.shared
        settings.setEnabled(.music, true)
        settings.data.showMusicChip = true
        // Put the card first so it's easy to see.
        while settings.data.cards.first?.card != .music { settings.moveCard(.music, by: -1) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil,
                userInfo: ["Player State": "Playing", "Name": "Blinding Lights", "Artist": "The Weeknd",
                           "Album": "After Hours", "Duration": 200040, "Playback Position": 77.0],
                deliverImmediately: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let size = NSSize(width: 300, height: 300)
            let cover = NSImage(size: size)
            cover.lockFocus()
            NSGradient(colors: [NSColor(calibratedRed: 0.85, green: 0.1, blue: 0.2, alpha: 1),
                                NSColor(calibratedRed: 0.15, green: 0.05, blue: 0.3, alpha: 1)])?
                .draw(in: NSRect(origin: .zero, size: size), angle: 60)
            cover.unlockFocus()
            if let key = MusicService.shared.nowPlaying?.trackKey {
                MusicService.shared.setArtwork(cover, forKey: key)
            }
        }
    }
}

// MARK: - Sync end-to-end (`--selftest-sync`)

extension SelfTest {
    /// Two devices (separate databases, separate engines) syncing through a real server.
    /// Needs NOTCHCAT_DB (so the Keychain item is a test one), NOTCHCAT_SERVER and NOTCHCAT_TEST_KEY.
    static func sync() async -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["NOTCHCAT_DB"] != nil, let server = env["NOTCHCAT_SERVER"], let key = env["NOTCHCAT_TEST_KEY"] else {
            print("needs NOTCHCAT_DB, NOTCHCAT_SERVER, NOTCHCAT_TEST_KEY")
            return false
        }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(ok ? "" : "  -> \(detail())")")
            if !ok { failures += 1 }
        }

        let dir = "/tmp/nc-sync-test"
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dbA = try! Database(path: "\(dir)/a.sqlite"), dbB = try! Database(path: "\(dir)/b.sqlite")
        let a = TaskStore(db: dbA), b = TaskStore(db: dbB)
        let noteA = NoteStore(db: dbA), noteB = NoteStore(db: dbB)
        let logA = SessionSync(db: dbA), logB = SessionSync(db: dbB)
        let prefsA = AppSettings(db: dbA), prefsB = AppSettings(db: dbB)
        let ea = SyncEngine(sources: [a, noteA, logA, SettingsSync(settings: prefsA, db: dbA)], db: dbA, keychainAccount: "test-a")
        let eb = SyncEngine(sources: [b, noteB, logB, SettingsSync(settings: prefsB, db: dbB)], db: dbB, keychainAccount: "test-b")
        func sessionCount(_ db: Database) -> Int { (try? db.scalarInt("SELECT COUNT(*) FROM focus_sessions")) ?? -1 }
        ea.serverText = server
        eb.serverText = server

        func titles(_ s: TaskStore) -> [String] { s.tasks.map(\.title) }
        func task(_ s: TaskStore, _ title: String) -> TaskItem? { s.tasks.first { $0.title == title } }
        func pause() async { try? await Task.sleep(nanoseconds: 15_000_000) }
        let user = "tester\(Int.random(in: 1000...9999))"

        // Accounts
        a.add(title: "Existing before signing in", day: .today)    // a task from before the account existed
        noteA.text = "A wrote this before signing in"             // so did both notes
        noteB.text = "B wrote this before signing in"
        logA.log(FocusSession(taskID: nil, startedAt: Date().addingTimeInterval(-7200), activeSeconds: 1500, plannedSeconds: 1500, completed: true))
        do { try await ea.signUp(accessKey: "NC-AAAA-AAAA-AAAA-AAAA", username: user, password: "correct horse"); check("bad key refused", false) }
        catch { check("bad key refused", (error as? APIError)?.status == 403, "\(error)") }
        do { try await ea.signUp(accessKey: key, username: user, password: "correct horse"); check("sign up with key", ea.username == user) }
        catch { check("sign up with key", false, "\(error)") }
        do { try await eb.signIn(username: user, password: "wrong password"); check("wrong password refused", false) }
        catch { check("wrong password refused", (error as? APIError)?.status == 401, "\(error)") }
        do { try await eb.signIn(username: user.uppercased(), password: "correct horse"); check("second device signs in", eb.username == user) }
        catch { check("second device signs in", false, "\(error)") }

        // Basic flow, including a task that existed before the account
        a.add(title: "Buy milk", day: .today)
        a.add(title: "Write docs", day: .today)
        await ea.syncNow(); await eb.syncNow()
        check("pre-existing task reaches device B", task(b, "Existing before signing in") != nil, "\(titles(b))")
        check("new tasks reach device B", task(b, "Buy milk") != nil && task(b, "Write docs") != nil, "\(titles(b))")
        check("same order on both", titles(a) == titles(b), "\(titles(a)) vs \(titles(b))")

        // Offline edits on both, then reconnect: different fields of one task, a delete, and a new task
        await pause(); a.rename(task(a, "Buy milk")!.id, to: "Buy oat milk")
        await pause(); b.toggleDone(task(b, "Buy milk")!.id)
        await pause(); a.delete(task(a, "Write docs")!.id)
        await pause(); b.add(title: "Call mom", day: .today)
        await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        let milkA = task(a, "Buy oat milk"), milkB = task(b, "Buy oat milk")
        check("rename and done-tick both survive", milkA?.isDone == true && milkB?.isDone == true, "A=\(String(describing: milkA)) B=\(String(describing: milkB))")
        check("delete reaches the other device", task(b, "Write docs") == nil && task(a, "Write docs") == nil, "\(titles(b))")
        check("task added offline reaches the other device", task(a, "Call mom") != nil, "\(titles(a))")
        check("both devices agree", Set(titles(a)) == Set(titles(b)), "\(titles(a)) vs \(titles(b))")

        // Same field edited on both: the later edit wins, whichever device syncs first
        let target = task(a, "Call mom")!.id
        await pause(); a.rename(target, to: "Call Mom (A)")
        await pause(); b.rename(target, to: "Call Mom (B)")
        await eb.syncNow(); await ea.syncNow(); await eb.syncNow()      // B's edit is newer but A syncs second
        check("newest edit wins a conflict", task(a, "Call Mom (B)") != nil && task(b, "Call Mom (B)") != nil, "A=\(titles(a)) B=\(titles(b))")

        // Reminders and time limits round-trip, including clearing them
        await pause(); a.setTimeLimit(target, minutes: 45); a.setReminder(target, at: Date().addingTimeInterval(3600))
        await ea.syncNow(); await eb.syncNow()
        let got = b.tasks.first { $0.id == target }
        check("time limit and reminder sync", got?.timeLimitMinutes == 45 && got?.remindAt != nil, "\(String(describing: got))")
        await pause(); b.setTimeLimit(target, minutes: nil)
        await eb.syncNow(); await ea.syncNow()
        check("clearing a field syncs", a.tasks.first { $0.id == target }?.timeLimitMinutes == nil)

        // Reordering
        a.add(title: "Third", day: .today); a.add(title: "Fourth", day: .today)
        await ea.syncNow(); await eb.syncNow()
        a.moveVisible(day: .today, from: IndexSet(integer: a.visibleTasks(for: .today).count - 1), to: 0)
        await ea.syncNow(); await eb.syncNow()
        check("reorder syncs", a.tasks.map(\.title) == b.tasks.map(\.title), "\(titles(a)) vs \(titles(b))")

        // Notes: both devices had text before the account existed; neither may be lost
        await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        check("both pre-existing notes survive", noteA.text.contains("A wrote this") && noteA.text.contains("B wrote this"), noteA.text)
        check("devices end on the same note", noteA.text == noteB.text, "A=\(noteA.text.debugDescription) B=\(noteB.text.debugDescription)")

        await pause(); noteA.text += "\nplain addition on A"
        await ea.syncNow(); await eb.syncNow()
        check("a note edit reaches the other device", noteB.text == noteA.text && noteB.text.hasSuffix("plain addition on A"))

        // Simultaneous edits to the same note: neither device's words are overwritten
        await pause(); noteA.text += "\nA offline line"
        await pause(); noteB.text += "\nB offline line"
        await eb.syncNow(); await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        check("simultaneous note edits keep both", noteA.text.contains("A offline line") && noteA.text.contains("B offline line"), noteA.text)
        check("and both devices agree", noteA.text == noteB.text, "A=\(noteA.text.debugDescription) B=\(noteB.text.debugDescription)")

        await pause(); noteB.text = ""
        await eb.syncNow(); await ea.syncNow()
        check("clearing the note syncs", noteA.text.isEmpty)

        // Focus sessions
        check("session logged before sign-in reached B", sessionCount(dbB) == 1, "B has \(sessionCount(dbB))")
        logB.log(FocusSession(taskID: task(b, "Third")?.id, startedAt: Date(), activeSeconds: 600, plannedSeconds: 1500, completed: false))
        await eb.syncNow(); await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        check("a session logged on B reaches A, once", sessionCount(dbA) == 2 && sessionCount(dbB) == 2, "A=\(sessionCount(dbA)) B=\(sessionCount(dbB))")

        // Settings: shared ones sync, per-device ones stay put
        await pause(); prefsA.data.snoozeMinutes = 12; prefsA.data.paperGrain = false; prefsA.data.hoverToOpen = false
        await pause(); prefsB.data.defaultFocusMinutes = 45; prefsB.setEnabled(.music, true)
        await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        check("shared settings sync both ways",
              prefsB.data.snoozeMinutes == 12 && prefsB.data.paperGrain == false && prefsA.data.defaultFocusMinutes == 45
                && prefsA.isEnabled(.music), "B snooze=\(prefsB.data.snoozeMinutes) A focus=\(prefsA.data.defaultFocusMinutes)")
        check("per-device settings stay local", prefsA.data.hoverToOpen == false && prefsB.data.hoverToOpen == true)
        await pause(); prefsA.data.snoozeMinutes = 20
        await pause(); prefsB.data.snoozeMinutes = 30
        await ea.syncNow(); await eb.syncNow(); await ea.syncNow()
        check("newest settings edit wins", prefsA.data.snoozeMinutes == 30 && prefsB.data.snoozeMinutes == 30, "A=\(prefsA.data.snoozeMinutes) B=\(prefsB.data.snoozeMinutes)")

        // Restart: a fresh store and engine reading the same database must not resend or lose anything
        let a2 = TaskStore(db: dbA)
        check("restart keeps tasks and bookkeeping", titles(a2) == titles(a) && a2.pendingChanges().isEmpty, "pending=\(a2.pendingChanges().count)")

        // Sign out keeps the tasks
        let before = titles(b)
        await eb.signOut()
        check("sign out keeps tasks", titles(b) == before && !eb.isSignedIn)
        check("sign out clears the stored login", KeychainStore(service: KeychainStore.defaultService, account: "test-b").read() == nil)

        await ea.signOut()   // leave no test login in the Keychain
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        return failures == 0
    }
}

// MARK: - Update check (`--selftest-update`)

extension SelfTest {
    static func update() async {
        let cases: [(String, String, Bool)] = [
            ("v1.0.4", "1.0.3", true), ("1.0.3", "1.0.3", false), ("v1.0.10", "1.0.9", true), ("1.1", "1.0.9", true),
            ("v2", "1.9.9", true), ("1.0.2", "1.0.3", false), ("garbage", "1.0.3", false), ("v1.0.4-beta", "1.0.3", true),
            ("", "1.0.3", false), ("1.0.3.1", "1.0.3", true),
        ]
        var bad = 0
        for (remote, local, want) in cases {
            let got = UpdateChecker.isNewer(remote, than: local)
            if got != want { bad += 1 }
            print("\(got == want ? "PASS" : "FAIL")  \(remote.isEmpty ? "(empty)" : remote) vs \(local) -> newer=\(got)")
        }
        let hostile = #"{"tag_name":"v9.9.9","html_url":"https://evil.example/phish","draft":false,"prerelease":false}"#
        let r1 = UpdateChecker.release(from: Data(hostile.utf8), newerThan: "1.0.3")
        print("\(r1?.url.host == "github.com" ? "PASS" : "FAIL")  foreign link in the response is ignored -> \(r1?.url.absoluteString ?? "nil")")
        let pre = #"{"tag_name":"v9.9.9","html_url":"https://github.com/shimijallores/notchcat/releases/tag/v9.9.9","prerelease":true}"#
        print("\(UpdateChecker.release(from: Data(pre.utf8), newerThan: "1.0.3") == nil ? "PASS" : "FAIL")  pre-releases are ignored")
        let ok = #"{"tag_name":"v1.0.4","html_url":"https://github.com/shimijallores/notchcat/releases/tag/v1.0.4"}"#
        print("\(UpdateChecker.release(from: Data(ok.utf8), newerThan: "1.0.3")?.url.lastPathComponent == "v1.0.4" ? "PASS" : "FAIL")  release link kept")
        await UpdateChecker.shared.check()
        print("check() with NOTCHCAT_UPDATE_URL=\(ProcessInfo.processInfo.environment["NOTCHCAT_UPDATE_URL"] ?? "-"), version=\(UpdateChecker.shared.currentVersion ?? "-") -> available=\(UpdateChecker.shared.available?.version ?? "none")")
        if bad > 0 { print("\(bad) FAILED") }
    }
}
