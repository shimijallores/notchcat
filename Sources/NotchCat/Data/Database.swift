import Foundation
import SQLite3

/// A value that can be bound to a statement parameter.
enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    init(_ v: Int?) { self = v.map { .int(Int64($0)) } ?? .null }
    init(_ v: Double?) { self = v.map { .double($0) } ?? .null }
    init(_ v: String?) { self = v.map { .text($0) } ?? .null }
    init(_ v: Date?) { self = v.map { .double($0.timeIntervalSince1970) } ?? .null }
    init(_ v: Bool) { self = .int(v ? 1 : 0) }
}

struct DatabaseError: Error, CustomStringConvertible {
    let message: String
    let sql: String
    var description: String { "SQLite error: \(message) [\(sql)]" }
}

/// One row of a result set. Column indexes are zero-based.
struct Row {
    fileprivate let stmt: OpaquePointer

    func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    func bool(_ i: Int32) -> Bool { sqlite3_column_int64(stmt, i) != 0 }
    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }

    func text(_ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }

    func optionalInt(_ i: Int32) -> Int? { isNull(i) ? nil : int(i) }
    func optionalDouble(_ i: Int32) -> Double? { isNull(i) ? nil : double(i) }
    func optionalText(_ i: Int32) -> String? { isNull(i) ? nil : text(i) }
    func date(_ i: Int32) -> Date { Date(timeIntervalSince1970: double(i)) }
    func optionalDate(_ i: Int32) -> Date? { isNull(i) ? nil : date(i) }
}

/// Minimal SQLite wrapper. Everything runs on the main thread; the data set is small.
final class Database {
    private var handle: OpaquePointer?
    let path: String

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// The app's database: ~/Library/Application Support/NotchCat/notchcat.sqlite
    static let shared: Database = {
        // NOTCHCAT_DB points the app at a throwaway database (used for testing; never touches real data).
        if let override = ProcessInfo.processInfo.environment["NOTCHCAT_DB"], !override.isEmpty {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: override).deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let db = try? Database(path: override) { return db }
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchCat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("notchcat.sqlite").path
        do {
            return try Database(path: path)
        } catch {
            // Never crash the menu-bar app over storage; fall back to memory and say so.
            NSLog("NotchCat: could not open database (\(error)); using in-memory storage")
            return try! Database(path: ":memory:")
        }
    }()

    init(path: String) throws {
        self.path = path
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let db { sqlite3_close(db) }
            throw DatabaseError(message: message, sql: "open \(path)")
        }
        handle = db
        sqlite3_busy_timeout(db, 3000)
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA synchronous = NORMAL")
        try exec("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - Running statements

    /// Runs one or more statements that return no rows.
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            throw DatabaseError(message: message, sql: sql)
        }
    }

    /// Runs a single statement with bound parameters.
    @discardableResult
    func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(sql) }
        return Int(sqlite3_changes(handle))
    }

    /// Runs a query and maps every row.
    func query<T>(_ sql: String, _ params: [SQLValue] = [], _ map: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(map(Row(stmt: stmt))) }
            else if rc == SQLITE_DONE { break }
            else { throw error(sql) }
        }
        return out
    }

    /// First column of the first row, as an Int (for COUNT / SUM).
    func scalarInt(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        try query(sql, params) { $0.int(0) }.first ?? 0
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Wraps several writes in one atomic transaction.
    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Writes a consistent copy of the whole database to `url` (used for backups).
    func backup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let escaped = url.path.replacingOccurrences(of: "'", with: "''")
        try exec("VACUUM INTO '\(escaped)'")
    }

    // MARK: - Internals

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw error(sql)
        }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func error(_ sql: String) -> DatabaseError {
        DatabaseError(message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle", sql: sql)
    }

    // MARK: - Migrations

    private var userVersion: Int {
        (try? scalarInt("PRAGMA user_version")) ?? 0
    }

    /// Each entry runs once, in order. Never edit a shipped migration; append a new one.
    private static let migrations: [String] = [
        // 1: initial schema
        """
        CREATE TABLE tasks (
            id                 TEXT PRIMARY KEY,
            title              TEXT NOT NULL,
            is_done            INTEGER NOT NULL DEFAULT 0,
            day                REAL NOT NULL,
            planned_day        REAL NOT NULL,
            position           INTEGER NOT NULL DEFAULT 0,
            time_limit_minutes INTEGER,
            remind_at          REAL,
            reminded           INTEGER NOT NULL DEFAULT 0,
            created_at         REAL NOT NULL,
            completed_at       REAL
        );
        CREATE INDEX idx_tasks_day ON tasks(day);
        CREATE INDEX idx_tasks_planned ON tasks(planned_day);
        CREATE INDEX idx_tasks_completed ON tasks(completed_at);
        CREATE INDEX idx_tasks_due ON tasks(remind_at) WHERE reminded = 0 AND remind_at IS NOT NULL;

        CREATE TABLE focus_sessions (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id         TEXT,
            started_at      REAL NOT NULL,
            active_seconds  INTEGER NOT NULL,
            planned_seconds INTEGER NOT NULL,
            completed       INTEGER NOT NULL
        );
        CREATE INDEX idx_sessions_started ON focus_sessions(started_at);

        CREATE TABLE notes (
            day        REAL PRIMARY KEY,
            body       TEXT NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """,
        // 2: cloud sync bookkeeping, kept beside the tasks table so existing queries are untouched.
        // task_sync: when each field was last edited here (epoch ms), which fields still need pushing,
        // and a tombstone for deleted tasks so the deletion can reach the server.
        """
        CREATE TABLE task_sync (
            task_id  TEXT PRIMARY KEY,
            field_ts TEXT NOT NULL DEFAULT '{}',
            dirty    TEXT NOT NULL DEFAULT '[]',
            deleted  INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE sync_meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    ]

    private func migrate() throws {
        let current = userVersion
        guard current < Self.migrations.count else { return }
        for (index, sql) in Self.migrations.enumerated() where index >= current {
            try transaction {
                try exec(sql)
                try exec("PRAGMA user_version = \(index + 1)")   // same transaction: all or nothing
            }
        }
    }
}
