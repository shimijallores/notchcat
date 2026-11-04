import Foundation
import Combine

/// One kind of data that syncs (tasks, the note, focus sessions, settings). The engine knows nothing about
/// what is inside; it asks each source for unsent changes and hands back what the server says.
@MainActor
protocol SyncSource: AnyObject {
    /// The server's name for this data ("tasks", "notes", "sessions", "settings").
    var collection: String { get }
    /// Fires after a local edit that needs sending.
    var changes: AnyPublisher<Void, Never> { get }
    /// How many items have unsent edits. Pure; safe to call as often as needed.
    var pendingCount: Int { get }
    /// Builds the unsent edits to send now (at most `limit`). Call once per push.
    func pendingChanges(limit: Int) -> [WireChange]
    /// The server's merged version of some items: confirmations of our own pushes, and changes from other devices.
    func apply(_ records: [WireRecord])
    /// Items the server did not accept because they were based on an old version. Each carries the current one.
    func resolveConflicts(_ records: [WireRecord])
    /// The server refused these outright; stop resending them.
    func dropPending(ids: [String])
    /// Signing in: everything that exists here must be offered to the server.
    func enroll()
    /// Signing out or switching accounts: forget what the server has seen. Local data stays.
    func resetSyncState()
}

extension SyncSource {
    func resolveConflicts(_ records: [WireRecord]) {}
}
