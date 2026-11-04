import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var sync = SyncEngine.shared
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
                    accountSection
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
                        .labelsHidden().toggleStyle(AmberSwitch())
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
            toggleRow("Battery percentage in the tray", "battery.75percent", settings.binding(\.showBattery))
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
        Section(title: "Music", footer: "Turn on the Now playing card above.") {
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

    private var accountSection: some View {
        Section(title: "Cloud sync",
                footer: sync.isSignedIn ? nil : "Cloud access needs an access key from the NotchCat owner. Your tasks work fully offline without it.") {
            AccountForm(sync: sync, pillButton: { title, action in AnyView(pillButton(title, action: action)) })
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
            Toggle("", isOn: binding).labelsHidden().toggleStyle(AmberSwitch())
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

/// A switch that is always amber when on, regardless of the system accent color
/// (the stock `.switch` style falls back to the accent and can show up gray).
struct AmberSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Theme.amber : Color.white.opacity(0.18))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .padding(1.5)
                    .frame(width: 15, height: 15)
                    .offset(x: configuration.isOn ? 6 : -6)
            }
            .frame(width: 30, height: 18)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isOn)
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


// MARK: - Cloud account

/// Sign in, create an account with an access key, and see sync status.
private struct AccountForm: View {
    @ObservedObject var sync: SyncEngine
    let pillButton: (String, @escaping () -> Void) -> AnyView

    @State private var creating = false
    @State private var accessKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if let name = sync.username, sync.isSignedIn {
            signedIn(name)
        } else {
            signedOut
        }
    }

    // MARK: Signed in

    private func signedIn(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle").font(.system(size: 11, weight: .semibold)).frame(width: 16).opacity(0.7)
                Text(name).font(.system(size: 12.5, weight: .medium))
                Spacer()
                statusDot
            }
            Text(statusText).font(.system(size: 11)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if sync.phase != .revoked {
                    pillButton("Sync now") { Task { await sync.syncNow() } }
                }
                Button("Sign out") { Task { await sync.signOut() } }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).opacity(0.6)
            }
        }
    }

    private var statusDot: some View {
        Circle().fill(dotColor).frame(width: 7, height: 7)
    }

    private var dotColor: Color {
        switch sync.phase {
        case .idle: return Color(red: 0.4, green: 0.9, blue: 0.5)
        case .syncing: return Theme.amber
        case .offline: return .gray
        case .failed, .revoked: return Color(red: 1, green: 0.42, blue: 0.4)
        case .signedOut: return .gray
        }
    }

    private var statusText: String {
        switch sync.phase {
        case .syncing: return "Syncing…"
        case .offline: return "Offline. Changes are saved here and will sync when you reconnect."
        case .failed(let message): return message
        case .revoked: return "Cloud access for this account has been turned off. Your tasks are still here."
        case .idle:
            guard let last = sync.lastSync else { return "Signed in" }
            return "Synced " + last.formatted(.relative(presentation: .named))
        case .signedOut: return ""
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                modeButton("Sign in", selected: !creating) { creating = false; error = nil }
                modeButton("Use access key", selected: creating) { creating = true; error = nil }
            }
            .padding(2)
            .background(Capsule().fill(.white.opacity(0.08)))

            field("Server", text: $sync.serverText, prompt: "https://sync.example.com")
            if creating { field("Access key", text: $accessKey, prompt: "NC-XXXX-XXXX-XXXX-XXXX") }
            field("Username", text: $username, prompt: creating ? "Choose a username" : "Username")
            secureField

            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                pillButton(working ? "Please wait…" : (creating ? "Create account" : "Sign in")) { submit() }
                    .opacity(canSubmit ? 1 : 0.45).allowsHitTesting(canSubmit)
            }
        }
    }

    private var canSubmit: Bool {
        !working && !username.isEmpty && password.count >= (creating ? 8 : 1) && (!creating || !accessKey.isEmpty)
            && !sync.serverText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        working = true
        error = nil
        Task {
            do {
                if creating {
                    try await sync.signUp(accessKey: accessKey, username: username, password: password)
                } else {
                    try await sync.signIn(username: username, password: password)
                }
                password = ""
                accessKey = ""
            } catch let e as URLError {
                error = e.code == .notConnectedToInternet ? "You're offline." : "Couldn't reach the server."
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Theme.amber : .clear))
                .foregroundStyle(selected ? Theme.ink : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.3)))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
            .accessibilityLabel(label)
    }

    private var secureField: some View {
        SecureField("", text: $password, prompt: Text(creating ? "Password (8+ characters)" : "Password").foregroundStyle(.white.opacity(0.3)))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
            .onSubmit { submit() }
            .accessibilityLabel("Password")
    }
}
