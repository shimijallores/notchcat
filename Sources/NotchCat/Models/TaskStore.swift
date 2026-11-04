import Foundation
import Combine
import Foundation

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
    private let syncRepo: TaskSyncRepository
    private var cal: Calendar { Calendar.current }

    /// What this Mac knows about each task's sync state (see Sync/).
    private(set) var syncMeta: [UUID: TaskSyncMeta]
    /// Display order as stored (and as the server has it). Can have gaps after a sync, so it is tracked, not derived.
    private var positions: [UUID: Int]
    /// Fires after an edit that needs pushing to the server.
    let localChange = PassthroughSubject<Void, Never>()

    init(db: Database) {
        repo = TaskRepository(db: db)
        syncRepo = TaskSyncRepository(db: db)
        syncMeta = syncRepo.loadAll()
        tasks = repo.loadAll()
        positions = repo.loadPositions()
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
        let task = TaskItem(title: trimmed, day: cal.startOfDay(for: date), timeLimitMinutes: timeLimitMinutes)
        tasks.append(task)
        positions[task.id] = (positions.values.max() ?? -1) + 1
        persist(tasks.count - 1)
        createSyncMeta(for: task)
    }

    func toggleDone(_ id: UUID) {
        update(id) {
            $0.isDone.toggle()
            $0.completedAt = $0.isDone ? Date() : nil
        }
    }

    /// Marks a task done. Unlike `toggleDone`, doing it twice leaves it done.
    func markDone(_ id: UUID) {
        guard let task = task(id: id), !task.isDone else { return }
        update(id) {
            $0.isDone = true
            $0.completedAt = Date()
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
        renumberPositions()
        createSyncMeta(for: copy)
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        repo.delete(id)
        positions[id] = nil
        // Keep a tombstone so the deletion reaches the server and other devices.
        var meta = syncMeta[id] ?? TaskSyncMeta()
        meta.deleted = true
        meta.fieldTs["deleted"] = nextTimestamp(after: meta)
        meta.dirty = ["deleted"]
        saveMeta(id, meta)
    }

    /// Reorders within the visible subset while leaving other days' tasks in place.
    func moveVisible(day: TaskDay, from source: IndexSet, to destination: Int) {
        let target = date(for: day)
        var visible = tasks(on: target)
        let slots = tasks.indices.filter { cal.isDate(tasks[$0].day, inSameDayAs: target) }
        visible.move(fromOffsets: source, toOffset: destination)
        for (slot, item) in zip(slots, visible) { tasks[slot] = item }
        renumberPositions()
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
        let before = tasks[idx]
        change(&tasks[idx])
        persist(idx)
        let changed = Self.changedFields(before, tasks[idx])
        if !changed.isEmpty { touch(before, changed, after: tasks[idx]) }
    }

    private func persist(_ index: Int) {
        guard tasks.indices.contains(index) else { return }
        let task = tasks[index]
        repo.upsert(task, position: positions[task.id] ?? index)
    }

    /// Writes the current order (index in the list) for every task and marks the ones that moved.
    private func renumberPositions() {
        repo.savePositions(tasks.map(\.id))
        for (index, task) in tasks.enumerated() where positions[task.id] != index {
            positions[task.id] = index
            touch(task, ["position"], after: task)
        }
    }

    // MARK: - Day rollover

    /// Unfinished tasks from earlier days carry over to today.
    func rollOverIfNeeded() {
        for i in tasks.indices where !tasks[i].isDone && tasks[i].day < today {
            let before = tasks[i]
            tasks[i].day = today
            persist(i)
            touch(before, ["day"], after: tasks[i])
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

// MARK: - Sync bookkeeping

/// The fields that sync, named as the server names them.
enum SyncField {
    static let all = ["title", "is_done", "day", "planned_day", "position", "time_limit_minutes",
                      "remind_at", "reminded", "created_at", "completed_at", "deleted"]
}

extension TaskStore {
    private static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// A strictly later timestamp than anything recorded for this task, so two quick edits keep their order.
    fileprivate func nextTimestamp(after meta: TaskSyncMeta) -> Int64 {
        max(Self.ms(Date()), (meta.fieldTs.values.max() ?? 0) + 1)
    }

    fileprivate func saveMeta(_ id: UUID, _ meta: TaskSyncMeta) {
        syncMeta[id] = meta
        syncRepo.save(id, meta)
        localChange.send()
    }

    /// A task that has never been tracked: everything about it is unsent, dated by when it was last known to change.
    fileprivate func baselineMeta(for task: TaskItem) -> TaskSyncMeta {
        let known = max(task.createdAt, task.completedAt ?? .distantPast)
        var meta = TaskSyncMeta()
        for field in SyncField.all {
            meta.fieldTs[field] = Self.ms(known)
            meta.dirty.insert(field)
        }
        meta.fieldTs["deleted"] = Self.ms(known)
        return meta
    }

    fileprivate func createSyncMeta(for task: TaskItem) {
        var meta = TaskSyncMeta()
        let now = Self.ms(Date())
        for field in SyncField.all {
            meta.fieldTs[field] = now
            meta.dirty.insert(field)
        }
        saveMeta(task.id, meta)
    }

    /// Records an edit. A task from before sync existed is first given a baseline from its state before the edit.
    fileprivate func touch(_ before: TaskItem, _ fields: [String], after: TaskItem) {
        var meta = syncMeta[before.id] ?? baselineMeta(for: before)
        let ts = nextTimestamp(after: meta)
        for field in fields {
            meta.fieldTs[field] = ts
            meta.dirty.insert(field)
        }
        meta.deleted = false
        saveMeta(before.id, meta)
    }

    fileprivate static func changedFields(_ a: TaskItem, _ b: TaskItem) -> [String] {
        var out: [String] = []
        if a.title != b.title { out.append("title") }
        if a.isDone != b.isDone { out.append("is_done") }
        if a.day != b.day { out.append("day") }
        if a.plannedDay != b.plannedDay { out.append("planned_day") }
        if a.timeLimitMinutes != b.timeLimitMinutes { out.append("time_limit_minutes") }
        if a.remindAt != b.remindAt { out.append("remind_at") }
        if a.reminded != b.reminded { out.append("reminded") }
        if a.createdAt != b.createdAt { out.append("created_at") }
        if a.completedAt != b.completedAt { out.append("completed_at") }
        return out
    }

    private func wireValue(_ field: String, of task: TaskItem) -> JSONValue {
        switch field {
        case "title": return .string(task.title)
        case "is_done": return .bool(task.isDone)
        case "day": return .double(task.day.timeIntervalSince1970)
        case "planned_day": return .double(task.plannedDay.timeIntervalSince1970)
        case "position": return .int(positions[task.id] ?? 0)
        case "time_limit_minutes": return .from(task.timeLimitMinutes)
        case "remind_at": return .from(task.remindAt)
        case "reminded": return .bool(task.reminded)
        case "created_at": return .double(task.createdAt.timeIntervalSince1970)
        case "completed_at": return .from(task.completedAt)
        default: return .null
        }
    }

    // MARK: Pushing

    /// Edits the server has not seen yet, as the server expects them.
    func pendingChanges() -> [WireChange] {
        var out: [WireChange] = []
        for (id, meta) in syncMeta where !meta.dirty.isEmpty {
            var fields: [String: JSONValue] = [:]
            var stamps: [String: Int64] = [:]
            if meta.deleted {
                fields["deleted"] = .bool(true)
                stamps["deleted"] = meta.fieldTs["deleted"] ?? Self.ms(Date())
            } else {
                guard let task = tasks.first(where: { $0.id == id }) else { continue }
                for field in meta.dirty {
                    fields[field] = field == "deleted" ? .bool(false) : wireValue(field, of: task)
                    stamps[field] = meta.fieldTs[field] ?? Self.ms(Date())
                }
            }
            out.append(WireChange(collection: "tasks", id: id.uuidString.lowercased(), fields: fields, fieldTs: stamps))
        }
        return out
    }

    /// The server refused these changes outright; stop resending them.
    func dropPending(ids: [String]) {
        for raw in ids {
            guard let id = UUID(uuidString: raw), var meta = syncMeta[id] else { continue }
            meta.dirty = []
            syncMeta[id] = meta
            syncRepo.save(id, meta)
        }
    }

    /// Makes every task count as unsent, e.g. after signing in. Tasks that were never tracked get a baseline.
    func enrollAllForSync() {
        for task in tasks where syncMeta[task.id] == nil {
            let meta = baselineMeta(for: task)
            syncMeta[task.id] = meta
            syncRepo.save(task.id, meta)
        }
    }

    /// Forgets all sync state (signing out). Tasks stay; they are treated as new if an account signs in later.
    fileprivate func resetSyncStateImpl() {
        syncMeta = [:]
        syncRepo.deleteAll()
    }

    // MARK: Pulling

    /// Merges what the server holds into the local tasks, field by field. A field edited here more recently
    /// than the server's version stays as it is (and stays queued to be sent).
    func applyRemote(_ records: [WireRecord]) {
        var working = tasks
        var touched = false

        for record in records {
            guard let id = UUID(uuidString: record.id) else { continue }
            let index = working.firstIndex { $0.id == id }
            var meta = syncMeta[id] ?? (index.map { baselineMeta(for: working[$0]) } ?? TaskSyncMeta())
            var task = index.map { working[$0] }
            var position = positions[id]
            var deleted = meta.deleted

            func takes(_ field: String) -> Bool {
                (record.fieldTs[field] ?? 0) >= (meta.fieldTs[field] ?? 0)
            }

            // Apply each field the server holds a newer (or equal) version of.
            for (field, value) in record.fields {
                guard takes(field) else { continue }
                meta.fieldTs[field] = record.fieldTs[field] ?? 0
                meta.dirty.remove(field)
                if field == "deleted" { deleted = value.bool ?? deleted; continue }
                if field == "position" { position = value.int ?? position; continue }
                if task == nil {
                    // A task seen for the first time needs its required fields before it can exist.
                    guard let title = record.fields["title"]?.string,
                          let day = record.fields["day"]?.double,
                          let planned = record.fields["planned_day"]?.double,
                          let created = record.fields["created_at"]?.double else { break }
                    task = TaskItem(id: id, title: title, isDone: false, day: Date(timeIntervalSince1970: day),
                                    plannedDay: Date(timeIntervalSince1970: planned), timeLimitMinutes: nil,
                                    remindAt: nil, reminded: false, createdAt: Date(timeIntervalSince1970: created),
                                    completedAt: nil)
                }
                guard var t = task else { continue }
                switch field {
                case "title": if let v = value.string, !v.isEmpty { t.title = v }
                case "is_done": t.isDone = value.bool ?? t.isDone
                case "day": if let v = value.double { t.day = Date(timeIntervalSince1970: v) }
                case "planned_day": if let v = value.double { t.plannedDay = Date(timeIntervalSince1970: v) }
                case "time_limit_minutes": t.timeLimitMinutes = value.int
                case "remind_at": t.remindAt = value.double.map { Date(timeIntervalSince1970: $0) }
                case "reminded": t.reminded = value.bool ?? t.reminded
                case "created_at": if let v = value.double { t.createdAt = Date(timeIntervalSince1970: v) }
                case "completed_at": t.completedAt = value.double.map { Date(timeIntervalSince1970: $0) }
                default: break
                }
                task = t
            }

            meta.deleted = deleted
            if deleted {
                if let index { working.remove(at: index); repo.delete(id); touched = true }
                positions[id] = nil
                meta.dirty.remove("deleted")
            } else if let task {
                positions[id] = position ?? positions[id] ?? (positions.values.max() ?? -1) + 1
                repo.upsert(task, position: positions[id] ?? 0)
                if let index { working[index] = task } else { working.append(task) }
                touched = true
            }
            syncMeta[id] = meta
            syncRepo.save(id, meta)
        }

        guard touched else { return }
        // The server's order is authoritative; ties (two devices adding at once) break by creation time.
        working.sort {
            let a = positions[$0.id] ?? Int.max, b = positions[$1.id] ?? Int.max
            return a != b ? a < b : $0.createdAt < $1.createdAt
        }
        tasks = working
    }
}

// MARK: - SyncSource

extension TaskStore: SyncSource {
    var collection: String { "tasks" }
    var changes: AnyPublisher<Void, Never> { localChange.eraseToAnyPublisher() }
    var pendingCount: Int { pendingChanges().count }
    func pendingChanges(limit: Int) -> [WireChange] { Array(pendingChanges().prefix(limit)) }
    func apply(_ records: [WireRecord]) { applyRemote(records.filter { $0.collection == "tasks" }) }
    func resolveConflicts(_ records: [WireRecord]) {}   // tasks merge field by field and never conflict
    func enroll() { enrollAllForSync() }
    func resetSyncState() { resetSyncStateImpl() }
}
