import Foundation

/// Finished tasks for the Insights history list, loaded a page at a time.
@MainActor
final class HistoryModel: ObservableObject {
    struct Section: Identifiable {
        let day: Date
        let items: [FinishedTask]
        var id: Date { day }
        var focusSeconds: Int { items.reduce(0) { $0 + $1.focusSeconds } }
    }

    @Published private(set) var sections: [Section] = []
    @Published private(set) var total = 0
    @Published private(set) var canLoadMore = false
    @Published var search = "" {
        didSet { if search != oldValue { pageSize = Self.firstPage; reload() } }
    }

    private static let firstPage = 60
    private var pageSize = HistoryModel.firstPage
    private let repo: TaskRepository
    private var cal: Calendar { Calendar.current }

    init(db: Database = .shared) {
        repo = TaskRepository(db: db)
        reload()
    }

    func reload() {
        let query = search.trimmingCharacters(in: .whitespaces)
        let rows = repo.finished(search: query, limit: pageSize)
        total = repo.finishedCount(search: query)
        canLoadMore = rows.count < total

        let grouped = Dictionary(grouping: rows) { cal.startOfDay(for: $0.completedAt) }
        sections = grouped.keys.sorted(by: >).map { Section(day: $0, items: grouped[$0]!) }
    }

    func loadMore() {
        pageSize += Self.firstPage
        reload()
    }

    static func title(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        return day.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.abbreviated)
                                      : .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}
