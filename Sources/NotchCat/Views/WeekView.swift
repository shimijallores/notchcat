import SwiftUI

/// The week ahead: seven day-columns. Drag a task onto any column to re-plan it.
struct WeekView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: PanelUIState

    private var days: [Date] {
        let cal = Calendar.current
        let start = store.today
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private let palette: [Color] = [Theme.mint, Theme.lavender, Theme.sand, Theme.slate, Theme.mint, Theme.lavender, Theme.sand]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                WeekColumn(day: day, color: palette[index], store: store, ui: ui)
            }
        }
    }
}

private struct WeekColumn: View {
    let day: Date
    let color: Color
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: PanelUIState

    @State private var draft = ""
    @State private var targeted = false
    @FocusState private var adding: Bool

    private var tasks: [TaskItem] { store.tasks(on: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .opacity(0.6)
                HStack(spacing: 4) {
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if isToday {
                        Circle().fill(Theme.ink).frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                    if !tasks.isEmpty {
                        Text("\(tasks.filter(\.isDone).count)/\(tasks.count)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .opacity(0.55)
                    }
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(tasks) { task in chip(task) }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 8.5, weight: .bold)).opacity(0.5)
                TextField("Add", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .focused($adding)
                    .onSubmit {
                        store.add(title: draft, on: day)
                        draft = ""
                        adding = true
                    }
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.4)))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(color, radius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink.opacity(targeted ? 0.85 : 0), lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.12), value: targeted)
        .dropDestination(for: String.self) { items, _ in
            var moved = false
            for raw in items {
                if let id = UUID(uuidString: raw) { store.move(id, toDate: day); moved = true }
            }
            return moved
        } isTargeted: { targeted = $0 }
    }

    private func chip(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button { store.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .opacity(task.isDone ? 0.9 : 0.5)
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(.system(size: 11, weight: .medium))
                .strikethrough(task.isDone)
                .opacity(task.isDone ? 0.45 : 1)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.42)))
        .draggable(task.id.uuidString)
    }
}
