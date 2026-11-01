import Foundation

/// Seven days of numbers for the Insights tab, read straight from SQLite.
@MainActor
final class InsightsModel: ObservableObject {
    struct Day: Identifiable, Equatable {
        let date: Date
        let planned: Int
        let completed: Int
        let focusSeconds: Int
        var id: Date { date }
    }

    struct Summary: Equatable {
        var days: [Day] = []
        var completed = 0
        var planned = 0
        var focusSeconds = 0
        var activeDays = 0
        var previousCompleted = 0

        var rangeStart: Date? { days.first?.date }
        var rangeEnd: Date? { days.last?.date }
    }

    /// 0 = the 7 days ending today, -1 = the week before, and so on.
    @Published var weekOffset = 0 {
        didSet {
            if weekOffset > 0 { weekOffset = 0 }   // no future weeks; assigning here doesn't re-trigger didSet
            reload()
        }
    }
    @Published private(set) var summary = Summary()

    private let repo: SessionRepository
    private var cal: Calendar { Calendar.current }

    init(db: Database = .shared) {
        repo = SessionRepository(db: db)
        reload()
    }

    func reload() {
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: weekOffset * 7, to: today)!
        let start = cal.date(byAdding: .day, value: -6, to: end)!

        let days: [Day] = (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let next = cal.date(byAdding: .day, value: 1, to: d)!
            return Day(date: d,
                       planned: repo.plannedCount(from: d, to: next),
                       completed: repo.completedCount(from: d, to: next),
                       focusSeconds: repo.focusSeconds(from: d, to: next))
        }
        let prevStart = cal.date(byAdding: .day, value: -7, to: start)!
        let next = Summary(days: days,
                           completed: days.reduce(0) { $0 + $1.completed },
                           planned: days.reduce(0) { $0 + $1.planned },
                           focusSeconds: days.reduce(0) { $0 + $1.focusSeconds },
                           activeDays: days.filter { $0.completed > 0 || $0.focusSeconds > 0 }.count,
                           previousCompleted: repo.completedCount(from: prevStart, to: start))
        if next != summary { summary = next }
    }

    // MARK: - Wording

    var headline: String {
        let s = summary
        if s.completed == 0 && s.focusSeconds == 0 { return "A fresh start" }
        if s.completed > s.previousCompleted { return "Momentum is building" }
        if s.completed == s.previousCompleted { return "Holding steady" }
        return "A quieter stretch"
    }

    var sentence: String {
        let s = summary
        let noun = s.completed == 1 ? "task" : "tasks"
        var text = "\(s.completed) \(noun) done"
        if s.previousCompleted > 0 || s.completed > 0 {
            if s.completed > s.previousCompleted { text += ", up from \(s.previousCompleted) the week before" }
            else if s.completed < s.previousCompleted { text += ", down from \(s.previousCompleted) the week before" }
            else { text += ", the same as the week before" }
        }
        if s.focusSeconds > 0 { text += ", with \(Self.duration(s.focusSeconds)) focused" }
        return text + "."
    }

    /// 7h 50m, 45m, 0m
    static func duration(_ seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
}
