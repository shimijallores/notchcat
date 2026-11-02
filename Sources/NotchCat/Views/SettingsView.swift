import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var music = MusicService.shared
    @State private var loginError: String?
    @State private var backupMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    cardsSection
                    tabsSection
                    openingSection
                    appearanceSection
                }
                VStack(spacing: 10) {
                    timerSection
                    remindersSection
                    musicSection
                    generalSection
                }
            }
            .padding(.bottom, 4)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Sections

    private var cardsSection: some View {
        Section(title: "Workspace cards", footer: "Reorder with the arrows. At least one card stays on.") {
            ForEach(Array(settings.data.cards.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: item.card.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                        .opacity(0.7)
                    Text(item.card.title).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    arrow("chevron.up", disabled: index == 0) { settings.moveCard(item.card, by: -1) }
                    arrow("chevron.down", disabled: index == settings.data.cards.count - 1) { settings.moveCard(item.card, by: 1) }
                    Toggle("", isOn: Binding(get: { item.enabled }, set: { settings.setEnabled(item.card, $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.amber)
                }
            }
        }
    }

    private var tabsSection: some View {
        Section(title: "Tabs") {
            toggleRow("Week", "calendar.day.timeline.left", settings.binding(\.showWeekTab))
            toggleRow("Insights", "chart.bar.xaxis", settings.binding(\.showInsightsTab))
        }
    }

    private var openingSection: some View {
        Section(title: "Opening", footer: "Click the pill or the menu-bar cat to open it either way.") {
            toggleRow("Open when I hover the notch", "cursorarrow.motionlines", settings.binding(\.hoverToOpen))
            toggleRow("Option-N shortcut", "command", settings.binding(\.hotkeyEnabled))
        }
    }

    private var appearanceSection: some View {
        Section(title: "Appearance",
                footer: NotchGeometry.hasHardwareNotch ? nil
                    : "For Macs without a notch. Notch draws a black notch at the top of the screen; Island draws a floating pill. The tray opens from it either way.") {
            toggleRow("Paper grain on cards", "circle.grid.3x3", settings.binding(\.paperGrain))
            if !NotchGeometry.hasHardwareNotch {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 11, weight: .semibold)).frame(width: 16).opacity(0.7)
                    Text("Fake notch").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Picker("", selection: settings.binding(\.fakeNotch)) {
                        ForEach(FakeNotchStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
        }
    }

    private var timerSection: some View {
        Section(title: "Focus timer") {
            toggleRow("Show countdown beside the notch", "capsule", settings.binding(\.showPill))
            stepperRow("Default length", "clock", value: settings.binding(\.defaultFocusMinutes), range: 1...240, step: 5, unit: "min")
            toggleRow("Play sounds (timer and reminders)", "speaker.wave.2", settings.binding(\.timerSound))
            toggleRow("Drop a \"Time's up\" card from the notch", "rectangle.expand.vertical", settings.binding(\.timeUpIsland))
        }
    }

    private var remindersSection: some View {
        Section(title: "Reminders") {
            toggleRow("Remind me from the notch", "bell", settings.binding(\.remindersEnabled))
            toggleRow("Show reminders in Events", "list.bullet", settings.binding(\.showRemindersInEvents))
            stepperRow("Snooze for", "zzz", value: settings.binding(\.snoozeMinutes), range: 1...60, step: 1, unit: "min")
        }
    }

    private var musicSection: some View {
        Section(title: "Music",
                footer: "Works with Spotify and Apple Music. Turn on the Now playing card above. macOS asks permission the first time NotchCat controls a player.") {
            toggleRow("Album art beside the notch while playing", "music.note", settings.binding(\.showMusicChip))
            if music.automationDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.amber)
                    Text("Control is blocked").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    pillButton("Open Settings") { music.openAutomationSettings() }
                }
            }
        }
    }

    private var generalSection: some View {
        Section(title: "General") {
            toggleRow("Open at login", "power", Binding(
                get: { settings.launchAtLogin },
                set: { loginError = settings.setLaunchAtLogin($0) }))
            if let loginError {
                Text(loginError).font(.system(size: 10.5)).foregroundStyle(.red.opacity(0.85))
            }
            actionRow("Back up database", "externaldrive") { backup() }
            if let backupMessage {
                Text(backupMessage).font(.system(size: 10.5)).opacity(0.6)
            }
            actionRow("Show data folder", "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Database.shared.path)])
            }
            actionRow("Quit NotchCat", "xmark.circle") { NSApp.terminate(nil) }
        }
    }

    // MARK: - Actions

    private func backup() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = downloads.appendingPathComponent("NotchCat-backup-\(stamp).sqlite")
        do {
            try Database.shared.backup(to: url)
            backupMessage = "Saved to Downloads"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            backupMessage = "Backup failed"
        }
    }

    // MARK: - Row builders

    private func toggleRow(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 16).opacity(0.7)
            Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Theme.amber)
        }
    }

    private func stepperRow(_ title: String, _ icon: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 16).opacity(0.7)
            Text(title).font(.system(size: 12.5, weight: .medium))
            Spacer()
            HStack(spacing: 0) {
                arrow("minus", disabled: value.wrappedValue <= range.lowerBound) {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                Text("\(value.wrappedValue) \(unit)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 62)
                arrow("plus", disabled: value.wrappedValue >= range.upperBound) {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
            }
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }

    private func actionRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 16).opacity(0.7)
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).opacity(0.35)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func arrow(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.25 : 0.75)
        .disabled(disabled)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(Capsule().fill(Theme.amber))
        }
        .buttonStyle(.plain)
    }
}

/// A rounded dark group with a small title.
private struct Section<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .opacity(0.45)
            content
            if let footer {
                Text(footer).font(.system(size: 10.5)).opacity(0.4).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.housingRaised))
    }
}
