import Foundation
import Combine
import Network

/// Keeps this Mac's tasks in step with the account on the server.
///
/// Edits are saved locally first and always work offline. They queue as "dirty" fields on the store; this engine
/// sends them when it can, then pulls whatever other devices changed. Nothing here blocks the UI.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine(
        sources: [TaskStore.shared, NoteStore.shared, SessionSync.shared, SettingsSync.shared], db: .shared)

    enum Phase: Equatable {
        case signedOut
        case idle
        case syncing
        case offline
        case failed(String)
        /// The owner turned this account's access key off.
        case revoked
    }

    /// The NotchCat server. Sign-up there needs an access key from its owner, so a public default is harmless.
    static let defaultServer = "https://api.notchcat.cloud"

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var username: String?
    @Published private(set) var lastSync: Date?
    @Published var serverText: String

    private let sources: [SyncSource]
    private let meta: SyncMetaRepository
    private let keychain: KeychainStore
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var cursor: Int
    private var running = false
    private var again = false
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var wasOnline = true

    init(sources: [SyncSource], db: Database, keychainAccount: String = "refresh-token") {
        self.sources = sources
        meta = SyncMetaRepository(db: db)
        keychain = KeychainStore(service: KeychainStore.defaultService, account: keychainAccount)
        serverText = meta.get("server_url") ?? ProcessInfo.processInfo.environment["NOTCHCAT_SERVER"] ?? Self.defaultServer
        cursor = Int(meta.get("cursor") ?? "") ?? 0
        username = meta.get("username")
        if username != nil, keychain.read() != nil { phase = .idle }
    }

    var isSignedIn: Bool { phase != .signedOut }

    /// Call once at launch. Does nothing for people who never signed in.
    func start() {
        guard cancellables.isEmpty else { return }
        Publishers.MergeMany(sources.map(\.changes))
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] in Task { await self?.syncNow() } }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                // Coming back online is the moment queued edits should go out.
                if online, !self.wasOnline { await self.syncNow() }
                self.wasOnline = online
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
        Task { await syncNow() }
    }

    // MARK: - Accounts

    func signUp(accessKey: String, username: String, password: String) async throws {
        let api = try makeAPI()
        let tokens = try await api.signUp(accessKey: accessKey, username: username, password: password, device: Self.deviceName)
        accept(tokens)
        await syncNow()
    }

    func signIn(username: String, password: String) async throws {
        let api = try makeAPI()
        let tokens = try await api.login(username: username, password: password, device: Self.deviceName)
        accept(tokens)
        await syncNow()
    }

    /// Leaves the account. Tasks stay on this Mac; they are not removed from the server either.
    func signOut() async {
        if let api = try? makeAPI(), let refresh = keychain.read() { await api.logout(refreshToken: refresh) }
        clearSession()
        phase = .signedOut
    }

    private func accept(_ tokens: TokenPair) {
        // A different account than last time starts from scratch rather than mixing two people's data.
        if let previous = meta.get("user_id"), previous != tokens.user.id {
            sources.forEach { $0.resetSyncState() }
            cursor = 0
            meta.set("cursor", "0")
        }
        keychain.write(tokens.refreshToken)
        accessToken = tokens.accessToken
        accessExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 30))
        meta.set("server_url", serverText.trimmingCharacters(in: .whitespacesAndNewlines))
        meta.set("user_id", tokens.user.id)
        meta.set("username", tokens.user.username)
        username = tokens.user.username
        sources.forEach { $0.enroll() }
        phase = .idle
    }

    private func clearSession() {
        keychain.delete()
        accessToken = nil
        accessExpiry = .distantPast
        meta.set("user_id", nil)
        meta.set("username", nil)
        meta.set("cursor", nil)
        cursor = 0
        username = nil
        lastSync = nil
        sources.forEach { $0.resetSyncState() }
    }

    private func makeAPI() throws -> SyncAPI {
        guard let url = SyncAPI.normalizedURL(serverText) else {
            throw APIError(status: 0, message: "Enter a valid server address (https://…)")
        }
        return SyncAPI(baseURL: url)
    }

    private static var deviceName: String { Host.current().localizedName ?? "Mac" }

    // MARK: - Syncing

    /// Sends queued edits, then pulls everything new. Safe to call at any time; overlapping calls collapse into one more pass.
    func syncNow() async {
        guard isSignedIn else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            await runOnce()
        } while again && phase == .idle
    }

    private func runOnce() async {
        phase = .syncing
        do {
            let api = try makeAPI()
            var token = try await validToken(api)

            // Push in chunks the server accepts, handing each source the server's answer for its own items.
            var pending = totalPending
            var rounds = 0
            while pending > 0, rounds < 50 {
                rounds += 1
                var batch: [WireChange] = []
                for source in sources where batch.count < 200 { batch += source.pendingChanges(limit: 200 - batch.count) }
                if batch.isEmpty { break }
                let result: PushResult
                do { result = try await api.push(batch, accessToken: token) }
                catch let error as APIError where error.status == 401 {
                    token = try await refreshToken(api)
                    result = try await api.push(batch, accessToken: token)
                }
                route(result.records) { $0.apply($1) }
                route(result.conflicts) { $0.resolveConflicts($1) }
                for (collection, items) in Dictionary(grouping: result.rejected, by: \.collection) {
                    NSLog("NotchCat sync: server refused \(items.count) \(collection) change(s): \(items.first?.reason ?? "")")
                    source(for: collection)?.dropPending(ids: items.map(\.id))
                }
                // A pass that didn't shrink the queue (an item edited again mid-flight) is picked up next time,
                // unless it only turned up conflicts, which the next pass resolves.
                let remaining = totalPending
                if remaining >= pending && result.conflicts.isEmpty { break }
                pending = remaining
            }

            // Pull until caught up.
            while true {
                let page: PullResult
                do { page = try await api.pull(cursor: cursor, accessToken: token) }
                catch let error as APIError where error.status == 401 {
                    token = try await refreshToken(api)
                    page = try await api.pull(cursor: cursor, accessToken: token)
                }
                route(page.records) { $0.apply($1) }
                cursor = page.cursor
                meta.set("cursor", String(cursor))
                if !page.hasMore { break }
            }
            lastSync = Date()
            phase = .idle
        } catch let error as APIError {
            handle(error)
        } catch let error as URLError {
            _ = error
            phase = .offline
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private var totalPending: Int { sources.reduce(0) { $0 + $1.pendingCount } }

    private func source(for collection: String) -> SyncSource? { sources.first { $0.collection == collection } }

    /// Hands each source only the records of its own collection.
    private func route(_ records: [WireRecord], _ body: (SyncSource, [WireRecord]) -> Void) {
        for (collection, items) in Dictionary(grouping: records, by: \.collection) {
            if let source = source(for: collection) { body(source, items) }
        }
    }

    private func handle(_ error: APIError) {
        switch error.status {
        case 403: phase = .revoked
        case 401:
            // The session is gone (password changed, token expired after long absence). Ask for sign-in again.
            keychain.delete()
            accessToken = nil
            phase = .failed("Your session ended. Sign in again.")
        default: phase = .failed(error.message)
        }
    }

    private func validToken(_ api: SyncAPI) async throws -> String {
        if let accessToken, accessExpiry > Date() { return accessToken }
        return try await refreshToken(api)
    }

    private func refreshToken(_ api: SyncAPI) async throws -> String {
        guard let stored = keychain.read() else { throw APIError(status: 401, message: "Not signed in") }
        let tokens = try await api.refresh(stored)
        keychain.write(tokens.refreshToken)
        accessToken = tokens.accessToken
        accessExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 30))
        return tokens.accessToken
    }
}
