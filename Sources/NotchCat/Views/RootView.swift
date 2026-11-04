import SwiftUI

/// The expanded drop-down: one dark housing holding separate pastel cards.
/// Laid out once at full size; `DropContainerView` animates the silhouette around it.
struct RootView: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
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
            HeaderBar(ui: ui, settings: settings)
            tabBody
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .overlay(alignment: .top) {
            if let id = ui.banner {
                ReminderBanner(ui: ui, store: store, taskID: id)
                    .padding(.top, ui.headerHeight + 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let modal = ui.modal {
                ModalHost(ui: ui, store: store, timer: timer, modal: modal)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: ui.modal)
        .animation(.spring(duration: 0.3, bounce: 0.08), value: ui.banner)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var tabBody: some View {
        switch ui.tab {
        case .workspace: WorkspaceView(ui: ui, store: store, timer: timer, settings: settings)
        case .week: WeekView(store: store, ui: ui)
        case .insights: InsightsView(store: store)
        case .settings: SettingsView(settings: settings)
        }
    }
}

/// The cards the user has switched on, in the order they chose. Tasks get the most room.
struct WorkspaceView: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer
    @ObservedObject var settings: AppSettings

    private let gap: CGFloat = 10

    private func weight(_ card: CardID) -> CGFloat { card == .tasks ? 1.5 : 1 }

    var body: some View {
        let cards = settings.visibleCards
        let available = ui.size.width - 24 - gap * CGFloat(max(cards.count - 1, 0))
        let totalWeight = cards.reduce(0) { $0 + weight($1) }

        HStack(spacing: gap) {
            ForEach(cards) { card in
                let width = available * weight(card) / max(totalWeight, 1)
                view(for: card, width: width)
                    .frame(width: width)
            }
        }
    }

    @ViewBuilder
    private func view(for card: CardID, width: CGFloat) -> some View {
        switch card {
        case .tasks: TasksCard(ui: ui, store: store, timer: timer)
        case .timer: TimerCard(ui: ui, store: store, timer: timer, width: width)
        case .notepad: NotepadCard(notes: NoteStore.shared, store: store)
        case .events: EventsCard(calendar: CalendarStore.shared, store: store, settings: settings)
        case .music: MusicCard(music: MusicService.shared)
        }
    }
}

/// Brand on the left, tabs on the right, with the hardware notch left empty in the middle.
struct HeaderBar: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var settings: AppSettings
    @ObservedObject private var battery = BatteryMonitor.shared

    private var tabs: [PanelTab] {
        PanelTab.allCases.filter {
            switch $0 {
            case .week: return settings.data.showWeekTab
            case .insights: return settings.data.showInsightsTab
            default: return true
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                MascotView(size: 20)
                Text("NotchCat")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                if settings.data.showBattery, let status = battery.status {
                    BatteryView(status: status).padding(.leading, 12)
                }
            }

            Spacer(minLength: ui.notchWidth + 24)

            HStack(spacing: 3) {
                ForEach(tabs.filter { $0 != .settings }) { tab in tabButton(tab) }
                Button { ui.tab = .settings } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ui.tab == .settings ? Theme.ink : .white.opacity(0.6))
                        .frame(width: 26, height: 22)
                        .background(Capsule().fill(ui.tab == .settings ? Theme.amber : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 22)
        .frame(height: ui.headerHeight)
        .environment(\.colorScheme, .dark)
    }

    private func tabButton(_ tab: PanelTab) -> some View {
        let selected = ui.tab == tab
        return Button { ui.tab = tab } label: {
            Text(tab.rawValue)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.ink : .white.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? Theme.amber : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Battery icon and percentage, e.g. "82%". A bolt while charging; red when low and unplugged.
struct BatteryView: View {
    let status: BatteryMonitor.Status

    private var symbol: String {
        if status.isCharging { return "battery.100percent.bolt" }
        switch status.percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var tint: Color {
        if status.isLow { return Color(red: 1, green: 0.42, blue: 0.4) }
        return status.isCharging ? Color(red: 0.45, green: 0.9, blue: 0.55) : .white.opacity(0.7)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            Text("\(status.percent)%").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .help(status.isCharging ? "Charging" : (status.onACPower ? "Plugged in" : "On battery"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(status.percent) percent\(status.isCharging ? ", charging" : "")")
    }
}

/// A reminder that fired while the tray was open.
struct ReminderBanner: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    let taskID: UUID

    var body: some View {
        if let task = store.task(id: taskID) {
            HStack(spacing: 10) {
                MascotView(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("Reminder").font(.system(size: 10.5)).opacity(0.55)
                }
                Spacer(minLength: 8)
                ReminderButtons(taskID: taskID) { ui.banner = nil }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(width: min(ui.size.width - 80, 460))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.housingRaised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            .environment(\.colorScheme, .dark)
        }
    }
}

/// "zZ snooze" and "✓ Done", shared by the banner and the island.
struct ReminderButtons: View {
    let taskID: UUID
    let onFinished: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                TaskStore.shared.snooze(taskID, minutes: settings.data.snoozeMinutes)
                onFinished()
            } label: {
                HStack(spacing: 4) {
                    Text("zZ").font(.system(size: 11, weight: .heavy, design: .rounded))
                    Text("\(settings.data.snoozeMinutes) min").font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button {
                let store = TaskStore.shared
                if let t = store.task(id: taskID), !t.isDone { store.toggleDone(taskID) }
                onFinished()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    Text("Done").font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
    }
}

/// Dims the housing and shows a small popover.
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
            switch modal {
            case .customReminder(let id):
                CustomReminderModal(
                    existing: store.task(id: id)?.remindAt,
                    onSave: { store.setReminder(id, at: $0); ui.modal = nil },
                    onClear: { store.setReminder(id, at: nil); ui.modal = nil },
                    onCancel: { ui.modal = nil })
            default:
                FocusDurationModal(initialMinutes: initialMinutes,
                                   allowsClear: allowsClear,
                                   onSave: save,
                                   onClear: clear,
                                   onCancel: { ui.modal = nil })
            }
        }
    }

    private var initialMinutes: Int {
        switch modal {
        case .taskLimit(let id): return store.task(id: id)?.timeLimitMinutes ?? AppSettings.shared.data.defaultFocusMinutes
        default: return timer.sessionTotal / 60
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
        default:
            timer.setDuration(minutes: minutes)
            AppSettings.shared.data.defaultFocusMinutes = minutes
        }
        ui.modal = nil
    }

    private func clear() {
        if case .taskLimit(let id) = modal { store.setTimeLimit(id, minutes: nil) }
        ui.modal = nil
    }
}

/// Pick an exact date and time for a reminder.
struct CustomReminderModal: View {
    let existing: Date?
    let onSave: (Date) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var date = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remind me")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if existing != nil {
                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                Button { onSave(date) } label: {
                    Text("Set reminder")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.amber))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(18)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.housingRaised))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onAppear { if let existing, existing > Date() { date = existing } }
    }
}
