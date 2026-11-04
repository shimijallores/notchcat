import Foundation
import Combine

/// Finished focus sessions. They never change once logged, so syncing is just "send the ones the server lacks,
/// store the ones other devices logged".
@MainActor
final class SessionSync: SyncSource {
    static let shared = SessionSync(db: .shared)

    private let repo: SessionRepository
    private let localChange = PassthroughSubject<Void, Never>()
    /// Fires when sessions arrive from another device, so Insights can refresh.
    let remoteChange = PassthroughSubject<Void, Never>()

    init(db: Database) {
        repo = SessionRepository(db: db)
    }

    /// Records a finished session and queues it for the server.
    func log(_ session: FocusSession) {
        repo.insert(session)
        localChange.send()
    }

    // MARK: SyncSource

    var collection: String { "sessions" }
    var changes: AnyPublisher<Void, Never> { localChange.eraseToAnyPublisher() }
    var pendingCount: Int { repo.unsentCount() }

    func pendingChanges(limit: Int) -> [WireChange] {
        repo.unsent(limit: limit).map { syncID, s in
            // Sessions are immutable, so every field shares one timestamp: when the session started.
            let ts = Int64((s.startedAt.timeIntervalSince1970 * 1000).rounded())
            let fields: [String: JSONValue] = [
                "task_id": s.taskID.map { .string($0.uuidString.lowercased()) } ?? .null,
                "started_at": .double(s.startedAt.timeIntervalSince1970),
                "active_seconds": .int(s.activeSeconds),
                "planned_seconds": .int(s.plannedSeconds),
                "completed": .bool(s.completed),
            ]
            return WireChange(collection: "sessions", id: syncID, fields: fields,
                              fieldTs: Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, ts) }))
        }
    }

    func apply(_ records: [WireRecord]) {
        var arrived = false
        for record in records where record.collection == "sessions" {
            let f = record.fields
            guard let started = f["started_at"]?.double, let active = f["active_seconds"]?.int,
                  let planned = f["planned_seconds"]?.int, let completed = f["completed"]?.bool else { continue }
            let session = FocusSession(taskID: f["task_id"]?.string.flatMap(UUID.init(uuidString:)),
                                       startedAt: Date(timeIntervalSince1970: started),
                                       activeSeconds: active, plannedSeconds: planned, completed: completed)
            // Our own sessions come back too; those are only marked as sent.
            if repo.insertRemote(syncID: record.id, session) { arrived = true } else { repo.markPushed([record.id]) }
        }
        if arrived { remoteChange.send() }
    }

    func dropPending(ids: [String]) { repo.markPushed(ids) }
    func enroll() {}
    func resetSyncState() { repo.resetPushed() }
}
