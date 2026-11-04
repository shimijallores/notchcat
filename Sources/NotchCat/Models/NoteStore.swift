import Foundation
import Combine

/// The notepad: one long-lived note, autosaved to SQLite and synced as a single piece of text.
@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore(db: .shared)

    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
            if !applyingRemote { markDirty() }
        }
    }

    private let repo: NoteRepository
    private let metaRepo: SyncMetaRepository
    private var saveWork: DispatchWorkItem?

    // MARK: Sync state

    /// What the server has seen of the note. Free text can't be merged by timestamp without losing words, so every
    /// edit records which server version it was written on top of (`baseSeq`).
    struct SyncState: Codable, Equatable {
        var baseSeq: Int?
        var dirty = false
        var ts: Int64 = 0
        /// The text of the push in flight, to recognise the server echoing it back.
        var lastSent: String?
    }

    private(set) var syncState: SyncState
    private var applyingRemote = false
    let localChange = PassthroughSubject<Void, Never>()

    init(db: Database) {
        let repo = NoteRepository(db: db)
        self.repo = repo
        metaRepo = SyncMetaRepository(db: db)
        syncState = metaRepo.get("note_sync").flatMap { try? JSONDecoder().decode(SyncState.self, from: Data($0.utf8)) } ?? SyncState()
        if let saved = repo.loadMain() {
            text = saved
        } else {
            // First run with the long-lived note: bring over anything written in the old per-day notepad.
            let merged = Self.merge(repo.legacyDailyNotes())
            repo.saveMain(merged)
            text = merged
        }
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        repo.saveMain(text)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// A single old note is used as is; several are stacked oldest first, each under its date.
    static func merge(_ notes: [(day: Date, body: String)]) -> String {
        guard notes.count > 1 else { return notes.first?.body ?? "" }
        return notes.map { note in
            "— \(note.day.formatted(.dateTime.month(.abbreviated).day().year())) —\n\(note.body)"
        }.joined(separator: "\n\n")
    }

    // MARK: Sync helpers

    private func saveSyncState() {
        metaRepo.set("note_sync", (try? JSONEncoder().encode(syncState)).flatMap { String(data: $0, encoding: .utf8) })
    }

    private func markDirty() {
        syncState.dirty = true
        syncState.ts = max(Int64(Date().timeIntervalSince1970 * 1000), syncState.ts + 1)
        saveSyncState()
        localChange.send()
    }

    /// Replaces the text with something that came from the server (not an edit made here).
    private func setFromServer(_ body: String) {
        applyingRemote = true
        text = body
        applyingRemote = false
        flush()
    }

    /// Two versions that both have words the other lacks: keep both, remote first, so nothing is lost.
    static func reconcile(remote: String, local: String) -> String {
        if remote == local || local.isEmpty { return remote }
        if remote.isEmpty { return local }
        // One already contains the other (for instance text appended while offline): the longer one loses nothing.
        if remote.contains(local) { return remote }
        if local.contains(remote) { return local }
        return remote + "\n\n— also written elsewhere at the same time —\n\n" + local
    }
}

// MARK: - SyncSource

extension NoteStore: SyncSource {
    var collection: String { "notes" }
    var changes: AnyPublisher<Void, Never> { localChange.eraseToAnyPublisher() }

    var pendingCount: Int { syncState.dirty ? 1 : 0 }

    func pendingChanges(limit: Int) -> [WireChange] {
        guard syncState.dirty, limit > 0 else { return [] }
        syncState.lastSent = text
        saveSyncState()
        return [WireChange(collection: "notes", id: "main", fields: ["body": .string(text)],
                           fieldTs: ["body": syncState.ts], baseSeq: syncState.baseSeq)]
    }

    func apply(_ records: [WireRecord]) {
        for record in records where record.id == "main" {
            let body = record.fields["body"]?.string ?? ""
            // Already seen (our own change coming back around in a pull).
            if let base = syncState.baseSeq, record.seq <= base { continue }

            if body == syncState.lastSent {
                // The server confirming what we just sent. If more was typed meanwhile, that part is still unsent.
                syncState.baseSeq = record.seq
                if text == body { syncState.dirty = false }
                saveSyncState()
            } else if !syncState.dirty {
                setFromServer(body)
                syncState.baseSeq = record.seq
                saveSyncState()
            } else {
                // Edited here and elsewhere. Keep both, then send the combined text on top of the server's version.
                let combined = Self.reconcile(remote: body, local: text)
                syncState.baseSeq = record.seq
                if combined == body {
                    setFromServer(body)
                    syncState.dirty = false
                    saveSyncState()
                } else {
                    if combined != text { setFromServer(combined) }
                    syncState.dirty = true
                    syncState.ts = max(Int64(Date().timeIntervalSince1970 * 1000), syncState.ts + 1)
                    saveSyncState()
                }
            }
        }
    }

    func resolveConflicts(_ records: [WireRecord]) {
        // The server's version has moved on from the one our edit was based on: same handling as a remote change.
        syncState.lastSent = nil
        apply(records)
    }

    func dropPending(ids: [String]) {
        syncState.dirty = false
        saveSyncState()
    }

    func enroll() {
        // Existing text must be offered to the server; if the server already has a note, the conflict path merges.
        if syncState.baseSeq == nil, !text.isEmpty, !syncState.dirty { markDirty() }
    }

    func resetSyncState() {
        syncState = SyncState()
        saveSyncState()
    }
}
