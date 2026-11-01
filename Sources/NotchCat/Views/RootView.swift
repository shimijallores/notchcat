import SwiftUI

/// The expanded drop-down: one dark housing holding separate pastel cards.
struct RootView: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer

    var body: some View {
        // Laid out once at full size; the container animates the silhouette around it.
        content
            .frame(width: ui.size.width, height: ui.size.height, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch ui.mode {
        case .dashboard: dashboard
        case .island: IslandView(ui: ui, store: store, timer: timer)
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            HeaderBar(ui: ui)
            HStack(spacing: 10) {
                TasksCard(ui: ui, store: store, timer: timer)
                TimerCard(ui: ui, store: store, timer: timer)
                    .frame(width: 252)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .overlay {
            if let modal = ui.modal {
                ModalHost(ui: ui, store: store, timer: timer, modal: modal)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: ui.modal)
        .environment(\.colorScheme, .light)
    }
}

/// Brand on the left, tabs on the right, with the hardware notch left empty in the middle.
struct HeaderBar: View {
    @ObservedObject var ui: PanelUIState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                MascotView(size: 20)
                Text("NotchCat")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer(minLength: ui.notchWidth + 24)

            HStack(spacing: 6) {
                Text("Workspace")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.amber))

                Menu {
                    Button("Quit NotchCat") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .frame(height: ui.headerHeight)
        .environment(\.colorScheme, .dark)
    }
}

/// Dims the housing and shows the "Focus duration" popover.
struct ModalHost: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer
    let modal: PanelUIState.Modal

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
                .onTapGesture { ui.modal = nil }
            FocusDurationModal(initialMinutes: initialMinutes,
                               allowsClear: allowsClear,
                               onSave: save,
                               onClear: clear,
                               onCancel: { ui.modal = nil })
        }
    }

    private var initialMinutes: Int {
        switch modal {
        case .taskLimit(let id): return store.task(id: id)?.timeLimitMinutes ?? store.defaultFocusMinutes
        case .timerDuration: return timer.sessionTotal / 60
        }
    }

    private var allowsClear: Bool {
        if case .taskLimit(let id) = modal { return store.task(id: id)?.timeLimitMinutes != nil }
        return false
    }

    private func save(_ minutes: Int) {
        switch modal {
        case .taskLimit(let id):
            store.setTimeLimit(id, minutes: minutes)
        case .timerDuration:
            timer.setDuration(minutes: minutes)
            store.defaultFocusMinutes = minutes
        }
        ui.modal = nil
    }

    private func clear() {
        if case .taskLimit(let id) = modal { store.setTimeLimit(id, minutes: nil) }
        ui.modal = nil
    }
}
