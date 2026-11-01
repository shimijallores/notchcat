import Foundation
import AppKit
import EventKit

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// Read-only view of today's Apple Calendar events. NotchCat never creates, edits or deletes events.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    enum Access {
        case unavailable     // this build has no Info.plist usage text, so macOS would kill the app on request
        case notDetermined
        case denied
        case authorized
    }

    @Published private(set) var access: Access = .unavailable
    @Published private(set) var events: [CalendarEvent] = []

    private lazy var store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        if access == .authorized { startObserving(); refresh() }
    }

    private static var hasUsageText: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    private static func currentAccess() -> Access {
        guard hasUsageText else { return .unavailable }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Shows the macOS permission prompt (only when it has not been answered yet).
    func requestAccess() {
        guard access == .notDetermined else {
            if access == .denied { openPrivacySettings() }
            return
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.access = granted ? .authorized : .denied
                if granted { self.startObserving(); self.refresh() }
            }
        }
    }

    func refresh() {
        let latest = Self.currentAccess()
        if latest != access { access = latest }
        guard access == .authorized else { events = []; return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                                 title: $0.title ?? "Untitled",
                                 start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) }
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
