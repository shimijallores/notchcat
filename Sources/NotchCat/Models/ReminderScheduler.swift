import Foundation
import AppKit

/// Watches for reminders that have come due and hands them to the UI once each.
@MainActor
final class ReminderScheduler {
    private let store: TaskStore
    private let settings: AppSettings
    private let onFire: (TaskItem) -> Void
    private var timer: Timer?

    /// Reminders missed while the app was closed for longer than this are dropped silently.
    private let staleAfter: TimeInterval = 6 * 3600

    init(store: TaskStore, settings: AppSettings, onFire: @escaping (TaskItem) -> Void) {
        self.store = store
        self.settings = settings
        self.onFire = onFire

        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func check() {
        guard settings.data.remindersEnabled else { return }
        let now = Date()
        for task in store.dueReminders(at: now) {
            store.markReminded(task.id)
            if let at = task.remindAt, now.timeIntervalSince(at) > staleAfter { continue }
            onFire(task)
        }
    }
}

/// Quick choices for the "Remind Me" menu.
enum ReminderPreset: CaseIterable {
    case in30Minutes, in1Hour, thisEvening, tomorrowMorning

    var title: String {
        switch self {
        case .in30Minutes: return "In 30 Minutes"
        case .in1Hour: return "In 1 Hour"
        case .thisEvening: return "This Evening"
        case .tomorrowMorning: return "Tomorrow Morning"
        }
    }

    /// The moment this preset means right now, or nil if it no longer makes sense (e.g. "This Evening" at 9pm).
    func date(from now: Date = Date(), calendar cal: Calendar = .current) -> Date? {
        switch self {
        case .in30Minutes: return now.addingTimeInterval(30 * 60)
        case .in1Hour: return now.addingTimeInterval(60 * 60)
        case .thisEvening:
            guard let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now),
                  evening.timeIntervalSince(now) > 15 * 60 else { return nil }
            return evening
        case .tomorrowMorning:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}

extension Date {
    /// "5:23 PM" for today, "Tue 9:00 AM" for another day.
    var reminderLabel: String {
        let cal = Calendar.current
        let time = formatted(.dateTime.hour().minute())
        if cal.isDateInToday(self) { return time }
        if cal.isDateInTomorrow(self) { return "Tomorrow \(time)" }
        return formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }
}
