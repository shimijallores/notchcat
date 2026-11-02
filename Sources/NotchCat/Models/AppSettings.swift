import SwiftUI
import ServiceManagement

enum CardID: String, Codable, CaseIterable, Identifiable {
    case tasks, timer, notepad, events, music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .timer: return "Focus timer"
        case .notepad: return "Notepad"
        case .events: return "Events & reminders"
        case .music: return "Now playing"
        }
    }

    var icon: String {
        switch self {
        case .tasks: return "checklist"
        case .timer: return "timer"
        case .notepad: return "note.text"
        case .events: return "calendar"
        case .music: return "music.note"
        }
    }

    /// How wide the card would like to be; the tray grows to fit the cards that are switched on.
    var preferredWidth: CGFloat {
        switch self {
        case .tasks: return 330
        case .timer: return 236
        case .notepad: return 220
        case .events: return 224
        case .music: return 236
        }
    }

    /// Cards that need permission or touch other apps start switched off until the user opts in.
    var onByDefault: Bool { self != .music }
}

struct CardSetting: Codable, Equatable, Identifiable {
    var card: CardID
    var enabled: Bool
    var id: String { card.rawValue }
}

/// Everything the Settings tab controls. Decoding tolerates missing keys so new options can be added
/// without breaking saved settings.
struct SettingsData: Codable, Equatable {
    var cards: [CardSetting] = CardID.allCases.map { CardSetting(card: $0, enabled: $0.onByDefault) }

    // Tabs
    var showWeekTab = true
    var showInsightsTab = true

    // Timer
    var showPill = true
    var defaultFocusMinutes = 25
    var timerSound = true
    var timeUpIsland = true

    // Reminders & calendar
    var remindersEnabled = true
    var snoozeMinutes = 5
    var showRemindersInEvents = true

    // Opening
    var hoverToOpen = true
    var hotkeyEnabled = true

    // Music
    var showMusicChip = false

    // Appearance
    var paperGrain = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsData()
        cards = try c.decodeIfPresent([CardSetting].self, forKey: .cards) ?? d.cards
        showWeekTab = try c.decodeIfPresent(Bool.self, forKey: .showWeekTab) ?? d.showWeekTab
        showInsightsTab = try c.decodeIfPresent(Bool.self, forKey: .showInsightsTab) ?? d.showInsightsTab
        showPill = try c.decodeIfPresent(Bool.self, forKey: .showPill) ?? d.showPill
        defaultFocusMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultFocusMinutes) ?? d.defaultFocusMinutes
        timerSound = try c.decodeIfPresent(Bool.self, forKey: .timerSound) ?? d.timerSound
        timeUpIsland = try c.decodeIfPresent(Bool.self, forKey: .timeUpIsland) ?? d.timeUpIsland
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        showRemindersInEvents = try c.decodeIfPresent(Bool.self, forKey: .showRemindersInEvents) ?? d.showRemindersInEvents
        hoverToOpen = try c.decodeIfPresent(Bool.self, forKey: .hoverToOpen) ?? d.hoverToOpen
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        paperGrain = try c.decodeIfPresent(Bool.self, forKey: .paperGrain) ?? d.paperGrain
        showMusicChip = try c.decodeIfPresent(Bool.self, forKey: .showMusicChip) ?? d.showMusicChip
        normalizeCards()
    }

    /// Makes sure every card appears exactly once and at least one is on.
    mutating func normalizeCards() {
        var seen = Set<CardID>()
        cards = cards.filter { seen.insert($0.card).inserted }
        for card in CardID.allCases where !seen.contains(card) {
            cards.append(CardSetting(card: card, enabled: card.onByDefault))
        }
        if !cards.contains(where: \.enabled) { cards[0].enabled = true }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(db: .shared)

    @Published var data: SettingsData {
        didSet {
            guard data != oldValue else { return }
            repo.save(data, key: Self.key)
        }
    }

    private let repo: SettingsRepository
    private static let key = "app"

    init(db: Database) {
        repo = SettingsRepository(db: db)
        data = repo.load(Self.key, as: SettingsData.self) ?? SettingsData()
    }

    /// True when anything needs the music service running.
    var musicWanted: Bool { isEnabled(.music) || data.showMusicChip }

    /// Cards that are switched on, in the user's order.
    var visibleCards: [CardID] { data.cards.filter(\.enabled).map(\.card) }

    func isEnabled(_ card: CardID) -> Bool { data.cards.first { $0.card == card }?.enabled ?? false }

    func setEnabled(_ card: CardID, _ on: Bool) {
        guard let i = data.cards.firstIndex(where: { $0.card == card }) else { return }
        // Never allow zero cards.
        if !on, data.cards.filter(\.enabled).count == 1, data.cards[i].enabled { return }
        data.cards[i].enabled = on
    }

    func moveCard(_ card: CardID, by offset: Int) {
        guard let i = data.cards.firstIndex(where: { $0.card == card }) else { return }
        let j = i + offset
        guard data.cards.indices.contains(j) else { return }
        data.cards.swapAt(i, j)
    }

    func binding<T>(_ keyPath: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { self.data[keyPath: keyPath] }, set: { self.data[keyPath: keyPath] = $0 })
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message if the system refused (for example an unsigned build).
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
            return nil
        } catch {
            objectWillChange.send()
            return error.localizedDescription
        }
    }
}
