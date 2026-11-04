import Foundation

// MARK: - Tasks

struct TaskRepository {
    let db: Database

    func loadAll() -> [TaskItem] {
        let sql = """
        SELECT id, title, is_done, day, planned_day, time_limit_minutes, remind_at, reminded, created_at, completed_at
        FROM tasks ORDER BY position, created_at
        """
        return (try? db.query(sql) { r in
            TaskItem(id: UUID(uuidString: r.text(0)) ?? UUID(),
                     title: r.text(1),
                     isDone: r.bool(2),
                     day: r.date(3),
                     plannedDay: r.date(4),
                     timeLimitMinutes: r.optionalInt(5),
                     remindAt: r.optionalDate(6),
                     reminded: r.bool(7),
                     createdAt: r.date(8),
                     completedAt: r.optionalDate(9))
        }) ?? []
    }

    /// Saved display order of every task, keyed by id.
    func loadPositions() -> [UUID: Int] {
        let rows = (try? db.query("SELECT id, position FROM tasks") { ($0.text(0), $0.int(1)) }) ?? []
        return Dictionary(uniqueKeysWithValues: rows.compactMap { id, pos in UUID(uuidString: id).map { ($0, pos) } })
    }

    func upsert(_ t: TaskItem, position: Int) {
        let sql = """
        INSERT INTO tasks (id, title, is_done, day, planned_day, position, time_limit_minutes, remind_at, reminded, created_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title, is_done = excluded.is_done, day = excluded.day,
            planned_day = excluded.planned_day, position = excluded.position,
            time_limit_minutes = excluded.time_limit_minutes, remind_at = excluded.remind_at,
            reminded = excluded.reminded, completed_at = excluded.completed_at
        """
        log(try? db.run(sql, [
            .text(t.id.uuidString), .text(t.title), SQLValue(t.isDone),
            SQLValue(t.day), SQLValue(t.plannedDay), .int(Int64(position)),
            SQLValue(t.timeLimitMinutes), SQLValue(t.remindAt), SQLValue(t.reminded),
            SQLValue(t.createdAt), SQLValue(t.completedAt)
        ]), "upsert task")
    }

    func delete(_ id: UUID) {
        log(try? db.run("DELETE FROM tasks WHERE id = ?", [.text(id.uuidString)]), "delete task")
    }

    /// Writes the display order for all tasks in one transaction.
    func savePositions(_ ids: [UUID]) {
        try? db.transaction {
            for (i, id) in ids.enumerated() {
                try db.run("UPDATE tasks SET position = ? WHERE id = ?", [.int(Int64(i)), .text(id.uuidString)])
            }
        }
    }

    func count() -> Int { (try? db.scalarInt("SELECT COUNT(*) FROM tasks")) ?? 0 }

    // MARK: History

    /// Escapes a user search string for use inside a LIKE pattern.
    private func likePattern(_ search: String) -> String {
        let escaped = search
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    /// Finished tasks, newest first, with the focus time that was spent on each.
    func finished(search: String, limit: Int, offset: Int = 0) -> [FinishedTask] {
        let sql = """
        SELECT t.id, t.title, t.completed_at, t.planned_day, t.time_limit_minutes,
               COALESCE((SELECT SUM(s.active_seconds) FROM focus_sessions s WHERE s.task_id = t.id), 0)
        FROM tasks t
        WHERE t.is_done = 1 AND t.completed_at IS NOT NULL AND t.title LIKE ? ESCAPE '\\'
        ORDER BY t.completed_at DESC
        LIMIT ? OFFSET ?
        """
        return (try? db.query(sql, [.text(likePattern(search)), .int(Int64(limit)), .int(Int64(offset))]) { r in
            FinishedTask(id: UUID(uuidString: r.text(0)) ?? UUID(), title: r.text(1), completedAt: r.date(2),
                         plannedDay: r.date(3), timeLimitMinutes: r.optionalInt(4), focusSeconds: r.int(5))
        }) ?? []
    }

    func finishedCount(search: String) -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM tasks WHERE is_done = 1 AND completed_at IS NOT NULL AND title LIKE ? ESCAPE '\\'",
                           [.text(likePattern(search))])) ?? 0
    }

    private func log(_ result: Int?, _ what: String) {
        if result == nil { NSLog("NotchCat: failed to \(what)") }
    }
}

// MARK: - Focus sessions & Insights queries

struct SessionRepository {
    let db: Database

    func insert(_ s: FocusSession) {
        _ = try? db.run("""
            INSERT INTO focus_sessions (task_id, started_at, active_seconds, planned_seconds, completed)
            VALUES (?, ?, ?, ?, ?)
            """, [SQLValue(s.taskID?.uuidString), SQLValue(s.startedAt), .int(Int64(s.activeSeconds)),
                  .int(Int64(s.plannedSeconds)), SQLValue(s.completed)])
    }

    /// Seconds of focus that started in [from, to).
    func focusSeconds(from: Date, to: Date) -> Int {
        (try? db.scalarInt("SELECT COALESCE(SUM(active_seconds), 0) FROM focus_sessions WHERE started_at >= ? AND started_at < ?",
                           [SQLValue(from), SQLValue(to)])) ?? 0
    }

    /// Tasks first planned for a day in [from, to).
    func plannedCount(from: Date, to: Date) -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM tasks WHERE planned_day >= ? AND planned_day < ?",
                           [SQLValue(from), SQLValue(to)])) ?? 0
    }

    /// Tasks completed in [from, to).
    func completedCount(from: Date, to: Date) -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM tasks WHERE is_done = 1 AND completed_at >= ? AND completed_at < ?",
                           [SQLValue(from), SQLValue(to)])) ?? 0
    }
}

// MARK: - Notes

struct NoteRepository {
    let db: Database

    /// The one long-lived note is stored under 1970-01-01. The old per-day notes (real dates) are kept as is.
    private static let mainKey = Date(timeIntervalSince1970: 0)

    /// The saved note, or nil if it has never been saved (a cleared note is saved as empty, not removed,
    /// so the old daily notes are only ever imported once).
    func loadMain() -> String? {
        (try? db.query("SELECT body FROM notes WHERE day = ?", [SQLValue(Self.mainKey)]) { $0.text(0) })?.first
    }

    func saveMain(_ body: String) {
        _ = try? db.run("""
            INSERT INTO notes (day, body, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at
            """, [SQLValue(Self.mainKey), .text(body), SQLValue(Date())])
    }

    /// Notes written back when the notepad was one-per-day, oldest first.
    func legacyDailyNotes() -> [(day: Date, body: String)] {
        let rows = try? db.query("SELECT day, body FROM notes WHERE day != ? ORDER BY day ASC",
                                 [SQLValue(Self.mainKey)]) { ($0.date(0), $0.text(1)) }
        return (rows ?? []).filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - Settings

struct SettingsRepository {
    let db: Database

    func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let json = (try? db.query("SELECT value FROM settings WHERE key = ?", [.text(key)]) { $0.text(0) })?.first,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
        _ = try? db.run("""
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, [.text(key), .text(json)])
    }
}

// MARK: - Import from v1's state.json

enum LegacyImporter {
    private struct LegacyTask: Decodable {
        var id: UUID
        var title: String
        var isDone: Bool
        var day: Date
        var timeLimitMinutes: Int?
        var createdAt: Date
        var completedAt: Date?
    }

    private struct LegacyState: Decodable {
        var tasks: [LegacyTask]
        var defaultFocusMinutes: Int
    }

    /// Moves v1 data into SQLite once. The old file is renamed, never deleted.
    /// Returns the imported default focus length, if any.
    @discardableResult
    static func importIfNeeded(into db: Database) -> Int? {
        let repo = TaskRepository(db: db)
        let dir = URL(fileURLWithPath: db.path).deletingLastPathComponent()
        let legacy = dir.appendingPathComponent("state.json")
        guard repo.count() == 0,
              FileManager.default.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let state = try? JSONDecoder().decode(LegacyState.self, from: data) else { return nil }

        try? db.transaction {
            for (i, t) in state.tasks.enumerated() {
                var item = TaskItem(id: t.id, title: t.title, isDone: t.isDone, day: t.day, plannedDay: t.day,
                                    timeLimitMinutes: t.timeLimitMinutes, remindAt: nil, reminded: false,
                                    createdAt: t.createdAt, completedAt: t.completedAt)
                if item.isDone, item.completedAt == nil { item.completedAt = t.day }
                repo.upsert(item, position: i)
            }
        }
        try? FileManager.default.moveItem(at: legacy, to: dir.appendingPathComponent("state.json.imported"))
        return state.defaultFocusMinutes
    }
}
