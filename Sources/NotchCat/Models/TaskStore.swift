import Foundation
import Combine

/// Which day the task list is showing.
enum TaskDay: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    var id: String { rawValue }
}

private struct PersistedState: Codable {
    var tasks: [TaskItem]
    var defaultFocusMinutes: Int
}

/// Local-first task storage, saved as JSON in Application Support.
@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var tasks: [TaskItem] = []
    @Published var defaultFocusMinutes: Int = 25 {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private var cal: Calendar { Calendar.current }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NotchCat", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("state.json")
        }
        load()
        rollOverIfNeeded()
        scheduleMidnightRollover()
    }

    // MARK: - Queries

    var today: Date { cal.startOfDay(for: Date()) }
    var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: today)! }

    func date(for day: TaskDay) -> Date { day == .today ? today : tomorrow }

    func visibleTasks(for day: TaskDay) -> [TaskItem] {
        let d = date(for: day)
        return tasks.filter { cal.isDate($0.day, inSameDayAs: d) }
    }

    func task(id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    // MARK: - Mutations

    func add(title: String, day: TaskDay, timeLimitMinutes: Int? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed, day: date(for: day), timeLimitMinutes: timeLimitMinutes))
        scheduleSave()
    }

    func toggleDone(_ id: UUID) {
        update(id) {
            $0.isDone.toggle()
            $0.completedAt = $0.isDone ? Date() : nil
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

    func move(_ id: UUID, to day: TaskDay) {
        update(id) { $0.day = date(for: day) }
    }

    func duplicate(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var copy = tasks[idx]
        copy.id = UUID()
        copy.isDone = false
        copy.completedAt = nil
        copy.createdAt = Date()
        tasks.insert(copy, at: idx + 1)
        scheduleSave()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Reorders within the visible subset while leaving other days' tasks in place.
    func moveVisible(day: TaskDay, from source: IndexSet, to destination: Int) {
        var visible = visibleTasks(for: day)
        let slots = tasks.indices.filter { cal.isDate(tasks[$0].day, inSameDayAs: date(for: day)) }
        visible.move(fromOffsets: source, toOffset: destination)
        for (slot, item) in zip(slots, visible) {
            tasks[slot] = item
        }
        scheduleSave()
    }

    private func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[idx])
        scheduleSave()
    }

    // MARK: - Day rollover

    /// Unfinished tasks from earlier days carry over to today.
    func rollOverIfNeeded() {
        var changed = false
        for i in tasks.indices where !tasks[i].isDone && tasks[i].day < today {
            tasks[i].day = today
            changed = true
        }
        if changed { scheduleSave() }
    }

    private func scheduleMidnightRollover() {
        let next = cal.date(byAdding: .day, value: 1, to: today)!
        let interval = max(1, next.timeIntervalSinceNow + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.rollOverIfNeeded()
            self.objectWillChange.send()
            self.scheduleMidnightRollover()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        tasks = state.tasks
        defaultFocusMinutes = state.defaultFocusMinutes
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func save() {
        let state = PersistedState(tasks: tasks, defaultFocusMinutes: defaultFocusMinutes)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
