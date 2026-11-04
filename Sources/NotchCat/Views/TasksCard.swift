import SwiftUI

struct TasksCard: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer
    @ObservedObject private var settings = AppSettings.shared

    @State private var day: TaskDay = .today
    @State private var draft = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var addFocused: Bool
    @FocusState private var renameFocused: Bool

    private var tasks: [TaskItem] { store.visibleTasks(for: day) }
    private var doneCount: Int { tasks.filter(\.isDone).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            addField
            list
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(Theme.mint)
        .tint(Theme.ink)
        .onChange(of: ui.focusRequest) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { addFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(TaskDay.allCases) { d in
                Button { day = d } label: {
                    Text(d.rawValue)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(day == d ? Theme.ink : Color.clear))
                        .foregroundStyle(day == d ? Color.white : Theme.ink.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(doneCount)/\(tasks.count)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Theme.ink.opacity(0.10)))
        }
    }

    // MARK: Add field

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.55)
            TextField("What needs doing?", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .focused($addFocused)
                .onSubmit {
                    store.add(title: draft, day: day)
                    draft = ""
                    addFocused = true
                }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.5)))
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if tasks.isEmpty {
            VStack(spacing: 8) {
                MascotView(size: 44).opacity(0.85)
                Text(day == .today ? "Nothing planned yet." : "Nothing queued for tomorrow.")
                    .font(.system(size: 12.5, weight: .medium))
                    .opacity(0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(tasks) { task in
                    row(task)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { store.moveVisible(day: day, from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 36)
            // List adds ~8pt of side inset on macOS; pull it back so rows line up with the field.
            .padding(.horizontal, -8)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.28)
                .frame(width: 12)

            Button { store.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.isDone ? Theme.ink : Theme.ink.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                if renamingID == task.id {
                    TextField("Task", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                        .focused($renameFocused)
                        .onSubmit { commitRename(task.id) }
                        .onExitCommand { renamingID = nil }
                } else {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(task.isDone)
                        .opacity(task.isDone ? 0.45 : 1)
                        .lineLimit(1)
                }
                badges(task)
            }

            Spacer(minLength: 4)

            Menu {
                Button { focus(task) } label: { Label("Focus", systemImage: "scope") }
                Button { store.toggleDone(task.id) } label: {
                    Label(task.isDone ? "Mark as Not Done" : "Mark as Done", systemImage: "checkmark.circle")
                }
                Button { beginRename(task) } label: { Label("Rename…", systemImage: "pencil") }
                Button { ui.modal = .taskLimit(task.id) } label: { Label("Set Time Limit…", systemImage: "clock") }
                if settings.data.remindersEnabled {
                    Menu {
                        ForEach(ReminderPreset.allCases, id: \.self) { preset in
                            if let when = preset.date() {
                                Button(preset.title) { store.setReminder(task.id, at: when) }
                            }
                        }
                        Button("Custom…") { ui.modal = .customReminder(task.id) }
                        if task.remindAt != nil {
                            Divider()
                            Button("Clear Reminder") { store.setReminder(task.id, at: nil) }
                        }
                    } label: { Label("Remind Me", systemImage: "bell") }
                }
                Divider()
                if day == .today {
                    Button { store.move(task.id, to: .tomorrow) } label: { Label("Move to Tomorrow", systemImage: "arrow.right.circle") }
                } else {
                    Button { store.move(task.id, to: .today) } label: { Label("Move to Today", systemImage: "arrow.left.circle") }
                }
                Button { store.duplicate(task.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Divider()
                Button(role: .destructive) { store.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.55)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.32)))
    }

    @ViewBuilder
    private func badges(_ task: TaskItem) -> some View {
        let linked = timer.linkedTaskID == task.id && timer.state != .idle
        if task.timeLimitMinutes != nil || task.remindAt != nil || linked {
            HStack(spacing: 5) {
                if let m = task.timeLimitMinutes {
                    Badge(icon: "clock", text: "\(m)m")
                }
                if let at = task.remindAt {
                    Badge(icon: task.reminded ? "bell.slash" : "bell", text: at.reminderLabel)
                        .opacity(task.reminded ? 0.55 : 1)
                }
                if linked {
                    ActiveBadge(state: timer.state)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let estimate = estimateLabel {
                Label(estimate, systemImage: "hourglass")
                    .labelStyle(.titleAndIcon)
                    .help("Estimated time to finish every unfinished task that has a time limit")
            }
            Spacer()
            Text(store.date(for: day), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        .font(.system(size: 10.5, weight: .medium))
        .opacity(0.5)
    }

    // MARK: Estimate

    /// Seconds of focus still needed across the unfinished tasks that have a time limit.
    /// A task whose session is running or paused counts only what is left on the timer.
    private var estimateSeconds: Int {
        tasks.filter { !$0.isDone }.reduce(0) { total, task in
            guard let minutes = task.timeLimitMinutes else { return total }
            let inSession = timer.linkedTaskID == task.id && (timer.state == .running || timer.state == .paused)
            return total + (inSession ? min(timer.remaining, minutes * 60) : minutes * 60)
        }
    }

    /// "1:05pm (5h 10m)": local finish time if you started now, then the total. Nil when no task has a limit.
    private var estimateLabel: String? {
        let seconds = estimateSeconds
        guard seconds > 0 else { return nil }
        let minutes = (seconds + 59) / 60
        let duration = Self.durationText(minutes: minutes)
        // The clock time only makes sense for today's list; tomorrow's tasks can't start now.
        guard day == .today else { return "\(duration) planned" }
        let finish = Date().addingTimeInterval(TimeInterval(minutes * 60))
        var clock = finish.formatted(.dateTime.hour().minute())
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if !Calendar.current.isDateInToday(finish) { clock = "tomorrow " + clock }
        return "\(clock) (\(duration))"
    }

    private static func durationText(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Actions

    private func focus(_ task: TaskItem) {
        timer.start(minutes: task.timeLimitMinutes ?? AppSettings.shared.data.defaultFocusMinutes, taskID: task.id)
    }

    private func beginRename(_ task: TaskItem) {
        renameText = task.title
        renamingID = task.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { renameFocused = true }
    }

    private func commitRename(_ id: UUID) {
        store.rename(id, to: renameText)
        renamingID = nil
    }
}

private struct Badge: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Theme.ink.opacity(0.11)))
    }
}

private struct ActiveBadge: View {
    let state: FocusTimer.State

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Theme.ink))
        .foregroundStyle(.white)
    }

    private var color: Color { state == .finished ? Theme.amber : (state == .paused ? .gray : Color(red: 0.4, green: 0.9, blue: 0.5)) }
    private var label: String {
        switch state {
        case .running: return "Active"
        case .paused: return "Paused"
        case .finished: return "Time's up"
        case .idle: return ""
        }
    }
}
