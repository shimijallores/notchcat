import Foundation

struct TaskSyncRepository {
    let db: Database

    func loadAll() -> [UUID: TaskSyncMeta] {
        let rows = (try? db.query("SELECT task_id, field_ts, dirty, deleted FROM task_sync") { r in
            (r.text(0), r.text(1), r.text(2), r.bool(3))
        }) ?? []
        var out: [UUID: TaskSyncMeta] = [:]
        for (id, ts, dirty, deleted) in rows {
            guard let uuid = UUID(uuidString: id) else { continue }
            let stamps = (try? JSONDecoder().decode([String: Int64].self, from: Data(ts.utf8))) ?? [:]
            let fields = (try? JSONDecoder().decode([String].self, from: Data(dirty.utf8))) ?? []
            out[uuid] = TaskSyncMeta(fieldTs: stamps, dirty: Set(fields), deleted: deleted)
        }
        return out
    }

    func save(_ id: UUID, _ meta: TaskSyncMeta) {
        let ts = (try? JSONEncoder().encode(meta.fieldTs)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let dirty = (try? JSONEncoder().encode(meta.dirty.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        _ = try? db.run("""
            INSERT INTO task_sync (task_id, field_ts, dirty, deleted) VALUES (?, ?, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET field_ts = excluded.field_ts, dirty = excluded.dirty, deleted = excluded.deleted
            """, [.text(id.uuidString), .text(ts), .text(dirty), SQLValue(meta.deleted)])
    }

    func deleteAll() {
        _ = try? db.run("DELETE FROM task_sync")
    }
}

/// Small key-value store for sync state (server, account, cursor). Secrets do not go here; they go in the Keychain.
struct SyncMetaRepository {
    let db: Database

    func get(_ key: String) -> String? {
        (try? db.query("SELECT value FROM sync_meta WHERE key = ?", [.text(key)]) { $0.text(0) })?.first
    }

    func set(_ key: String, _ value: String?) {
        if let value {
            _ = try? db.run("""
                INSERT INTO sync_meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, [.text(key), .text(value)])
        } else {
            _ = try? db.run("DELETE FROM sync_meta WHERE key = ?", [.text(key)])
        }
    }
}
