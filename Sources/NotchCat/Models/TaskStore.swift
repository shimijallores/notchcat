import Foundation
import Combine

/// Which day the task list is showing.
enum TaskDay: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    var id: String { rawValue }
}

/// Tasks, kept in memory for the UI and written through to SQLite on every change.
@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore(db: .shared)

    @Published private(set) var tasks: [TaskItem] = []
    /// Changes at local midnight so day-based views refresh.
    @Published private(set) var dayStamp = Date()

    private let repo: TaskRepository
    private var cal: Calendar { Calendar.current }

    init(db: Database) {
        repo = TaskRepository(db: db)
        tasks = repo.loadAll()
        rollOverIfNeeded()
        scheduleMidnightRollover()
    }

    // MARK: - Queries

    var today: Date { cal.startOfDay(for: Date()) }
    var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: today)! }

    func date(for day: TaskDay) -> Date { day == .today ? today : tomorrow }

    func tasks(on date: Date) -> [TaskItem] {
        tasks.filter { cal.isDate($0.day, inSameDayAs: date) }
    }

    func visibleTasks(for day: TaskDay) -> [TaskItem] { tasks(on: date(for: day)) }

    func task(id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Reminders that are due and not yet shown.
    func dueReminders(at now: Date = Date()) -> [TaskItem] {
        tasks.filter { !$0.isDone && !$0.reminded && ($0.remindAt ?? .distantFuture) <= now }
    }

    /// Reminders set for a given day (shown in the Events card).
    func reminders(on date: Date) -> [TaskItem] {
        tasks.filter { t in
            guard let r = t.remindAt, !t.isDone else { return false }
            return cal.isDate(r, inSameDayAs: date)
        }
        .sorted { $0.remindAt! < $1.remindAt! }
    }

    // MARK: - Mutations

    func add(title: String, day: TaskDay) { add(title: title, on: date(for: day)) }

    func add(title: String, on date: Date, timeLimitMinutes: Int? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed, day: cal.startOfDay(for: date), timeLimitMinutes: timeLimitMinutes))
        persist(tasks.count - 1)
    }

    func toggleDone(_ id: UUID) {
        update(id) {
            $0.isDone.toggle()
            $0.completedAt = $0.isDone ? Date() : nil
        }
    }

    /// Brings a finished task back onto today's list.
    func restore(_ id: UUID) {
        let today = self.today
        update(id) {
            $0.isDone = false
            $0.completedAt = nil
            $0.day = today
        }
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    func setTimeLimit(_ id: UUID, minutes: Int?) {
        update(id) { $0.timeLimitMinutes = minutes }
    }

    func move(_ id: UUID, to day: TaskDay) { move(id, toDate: date(for: day)) }

    /// Moves a task to another day. Moving counts as re-planning it for that day.
    func move(_ id: UUID, toDate date: Date) {
        let d = cal.startOfDay(for: date)
        update(id) {
            $0.day = d
            if !$0.isDone { $0.plannedDay = d }
        }
    }

    func duplicate(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var copy = tasks[idx]
        copy.id = UUID()
        copy.isDone = false
        copy.completedAt = nil
        copy.remindAt = nil
        copy.reminded = false
        copy.createdAt = Date()
        copy.plannedDay = copy.day
        tasks.insert(copy, at: idx + 1)
        persist(idx + 1)
        repo.savePositions(tasks.map(\.id))
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        repo.delete(id)
    }

    /// Reorders within the visible subset while leaving other days' tasks in place.
    func moveVisible(day: TaskDay, from source: IndexSet, to destination: Int) {
        let target = date(for: day)
        var visible = tasks(on: target)
        let slots = tasks.indices.filter { cal.isDate(tasks[$0].day, inSameDayAs: target) }
        visible.move(fromOffsets: source, toOffset: destination)
        for (slot, item) in zip(slots, visible) { tasks[slot] = item }
        repo.savePositions(tasks.map(\.id))
    }

    // MARK: - Reminders

    func setReminder(_ id: UUID, at date: Date?) {
        update(id) {
            $0.remindAt = date
            $0.reminded = false
        }
    }

    func markReminded(_ id: UUID) {
        update(id) { $0.reminded = true }
    }

    func snooze(_ id: UUID, minutes: Int) {
        setReminder(id, at: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    // MARK: - Internals

    private func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[idx])
        persist(idx)
    }

    private func persist(_ index: Int) {
        guard tasks.indices.contains(index) else { return }
        repo.upsert(tasks[index], position: index)
    }

    // MARK: - Day rollover

    /// Unfinished tasks from earlier days carry over to today.
    func rollOverIfNeeded() {
        for i in tasks.indices where !tasks[i].isDone && tasks[i].day < today {
            tasks[i].day = today
            persist(i)
        }
    }

    private func scheduleMidnightRollover() {
        let next = cal.date(byAdding: .day, value: 1, to: today)!
        let interval = max(1, next.timeIntervalSinceNow + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.rollOverIfNeeded()
            self.dayStamp = Date()
            self.scheduleMidnightRollover()
        }
    }
}
