import SwiftUI

/// Compact "Dynamic Island" card shown when a focus session ends.
struct IslandView: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: ui.headerHeight)
            HStack(spacing: 12) {
                MascotView(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time's up")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.task(id: timer.linkedTaskID)?.title ?? "Session complete")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    timer.addTime(seconds: 300)
                    ui.close()
                } label: {
                    Text("+5 min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    timer.reset()
                    ui.close()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        Text("Done").font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.amber))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
    }
}
