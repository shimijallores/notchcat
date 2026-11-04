import Foundation
import Combine

/// The preferences that mean the same on every device. Each syncs on its own, newest edit winning.
///
/// Deliberately left out because they describe this Mac, not the person: the Option-N shortcut, hover-to-open,
/// the countdown and album art next to the notch, the fake notch, the battery readout and the update check.
@MainActor
final class SettingsSync: SyncSource {
    static let shared = SettingsSync(settings: .shared, db: .shared)

    private struct Field {
        let name: String
        let read: (SettingsData) -> JSONValue
        let write: (inout SettingsData, JSONValue) -> Void
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let fields: [Field] = [
        Field(name: "cards",
              read: { data in .string((try? encoder.encode(data.cards)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]") },
              write: { data, value in
                  if let text = value.string, let cards = try? JSONDecoder().decode([CardSetting].self, from: Data(text.utf8)) {
                      data.cards = cards
                      data.normalizeCards()
                  }
              }),
        flag("show_week_tab", \.showWeekTab),
        flag("show_insights_tab", \.showInsightsTab),
        number("default_focus_minutes", \.defaultFocusMinutes),
        flag("timer_sound", \.timerSound),
        flag("reminders_enabled", \.remindersEnabled),
        number("snooze_minutes", \.snoozeMinutes),
        flag("show_reminders_in_events", \.showRemindersInEvents),
        flag("paper_grain", \.paperGrain),
    ]

    private static func flag(_ name: String, _ path: WritableKeyPath<SettingsData, Bool>) -> Field {
        Field(name: name, read: { .bool($0[keyPath: path]) }, write: { data, v in if let b = v.bool { data[keyPath: path] = b } })
    }

    private static func number(_ name: String, _ path: WritableKeyPath<SettingsData, Int>) -> Field {
        Field(name: name, read: { .int($0[keyPath: path]) }, write: { data, v in if let n = v.int { data[keyPath: path] = n } })
    }

    struct State: Codable, Equatable {
        var fieldTs: [String: Int64] = [:]
        var dirty: Set<String> = []
    }

    private let settings: AppSettings
    private let meta: SyncMetaRepository
    private(set) var state: State
    private var snapshot: SettingsData
    private var applyingRemote = false
    private let localChange = PassthroughSubject<Void, Never>()
    private var cancellable: AnyCancellable?

    init(settings: AppSettings, db: Database) {
        self.settings = settings
        meta = SyncMetaRepository(db: db)
        state = meta.get("settings_sync").flatMap { try? JSONDecoder().decode(State.self, from: Data($0.utf8)) } ?? State()
        snapshot = settings.data
        // @Published emits before the value changes, so work from the value it hands over.
        cancellable = settings.$data.sink { [weak self] new in self?.edited(to: new) }
    }

    private func edited(to new: SettingsData) {
        defer { snapshot = new }
        guard !applyingRemote else { return }
        var any = false
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for field in Self.fields where field.read(new) != field.read(snapshot) {
            state.fieldTs[field.name] = max(now, (state.fieldTs[field.name] ?? 0) + 1)
            state.dirty.insert(field.name)
            any = true
        }
        if any { save(); localChange.send() }
    }

    private func save() {
        meta.set("settings_sync", (try? Self.encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) })
    }

    // MARK: SyncSource

    var collection: String { "settings" }
    var changes: AnyPublisher<Void, Never> { localChange.eraseToAnyPublisher() }
    var pendingCount: Int { state.dirty.isEmpty ? 0 : 1 }

    func pendingChanges(limit: Int) -> [WireChange] {
        guard !state.dirty.isEmpty else { return [] }
        let wanted = Self.fields.filter { state.dirty.contains($0.name) }
        return [WireChange(collection: "settings", id: "app",
                           fields: Dictionary(uniqueKeysWithValues: wanted.map { ($0.name, $0.read(settings.data)) }),
                           fieldTs: Dictionary(uniqueKeysWithValues: wanted.map { ($0.name, state.fieldTs[$0.name] ?? 0) }))]
    }

    func apply(_ records: [WireRecord]) {
        for record in records where record.id == "app" {
            var data = settings.data
            for field in Self.fields {
                guard let value = record.fields[field.name] else { continue }
                let serverTs = record.fieldTs[field.name] ?? 0
                // An edit made here after the server's version stays; otherwise the server's version wins.
                guard serverTs >= (state.fieldTs[field.name] ?? 0) else { continue }
                field.write(&data, value)
                state.fieldTs[field.name] = serverTs
                state.dirty.remove(field.name)
            }
            applyingRemote = true
            if data != settings.data { settings.data = data }
            applyingRemote = false
            snapshot = settings.data
            save()
        }
    }

    func dropPending(ids: [String]) {
        state.dirty = []
        save()
    }

    func enroll() {
        // Offer anything customised that was never tracked (set before this existed). Defaults stay quiet, so a
        // new device with untouched settings can't overwrite the ones you chose elsewhere.
        let defaults = SettingsData()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var any = false
        for field in Self.fields where state.fieldTs[field.name] == nil && field.read(settings.data) != field.read(defaults) {
            state.fieldTs[field.name] = now
            state.dirty.insert(field.name)
            any = true
        }
        if any { save(); localChange.send() }
    }

    func resetSyncState() {
        state = State()
        save()
    }
}
