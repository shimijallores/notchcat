import SwiftUI

/// Finished tasks grouped by the day they were completed.
struct HistoryList: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject var store: TaskStore

    var body: some View {
        if model.sections.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: model.search.isEmpty ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 24)).opacity(0.35)
                Text(model.search.isEmpty ? "Finished tasks will show up here." : "No finished tasks match.")
                    .font(.system(size: 12.5, weight: .medium)).opacity(0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                        ForEach(model.sections) { section in
                            sectionView(section)
                        }
                        if model.canLoadMore {
                            Button { model.loadMore() } label: {
                                Text("Show older")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity).frame(height: 28)
                                    .background(Capsule().fill(Theme.ink.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("\(model.total) finished \(model.total == 1 ? "task" : "tasks")")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.5)
            }
        }
    }

    private func sectionView(_ section: HistoryModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(HistoryModel.title(for: section.day))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                Text("\(section.items.count) done")
                    .font(.system(size: 10.5, weight: .medium))
                    .opacity(0.5)
                if section.focusSeconds > 0 {
                    Text("· \(InsightsModel.duration(section.focusSeconds)) focused")
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.5)
                }
                Spacer()
            }
            .padding(.leading, 2)

            ForEach(section.items) { row($0) }
        }
    }

    private func row(_ task: FinishedTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).opacity(0.8)
            Text(task.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            if task.focusSeconds > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 8.5, weight: .bold))
                    Text(InsightsModel.duration(task.focusSeconds)).font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Theme.ink.opacity(0.11)))
            }
            Text(task.completedAt, format: .dateTime.hour().minute())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .opacity(0.55)
            Menu {
                Button { store.restore(task.id) } label: { Label("Restore to Today", systemImage: "arrow.uturn.backward") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.5)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.35)))
    }
}

struct HistorySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .semibold)).opacity(0.5)
            TextField("Search finished tasks", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).opacity(0.45)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 190, height: 26)
        .background(Capsule().fill(Theme.ink.opacity(0.09)))
    }
}
