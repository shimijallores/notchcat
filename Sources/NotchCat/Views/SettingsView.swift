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
                    accountSection
                    tabsSection
                    openingSection
                    appearanceSection
                }
                VStack(spacing: 10) {
                    timerSection
                    remindersSection
                    musicSection
                    cardsSection
                    generalSection
                }
            }
            .padding(.bottom, 4)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Sections

    private var cardsSection: some View {
        Section(title: "Workspace cards") {
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
        Section(title: "Opening") {
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
                footer: sync.isSignedIn ? nil : "Contact owner for access key") {
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
            if UpdateChecker.shared.currentVersion != nil {
                toggleRow("Tell me about new versions", "arrow.down.circle", Binding(
                    get: { settings.data.checkForUpdates },
                    set: { on in
                        settings.data.checkForUpdates = on
                        Task { await UpdateChecker.shared.check() }
                    }))
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

/// Sign in or sign up. Signed out it shows two buttons; the one you tap opens its form underneath. Signing up asks for
/// the access key first, checks it with the server, and only then asks for a username and password.
private struct AccountForm: View {
    @ObservedObject var sync: SyncEngine
    let pillButton: (String, @escaping () -> Void) -> AnyView

    enum Mode { case signIn, signUp }
    enum SignUpStep { case key, details }

    @State private var mode: Mode?
    @State private var step: SignUpStep = .key
    @State private var accessKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var working = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    init(sync: SyncEngine, pillButton: @escaping (String, @escaping () -> Void) -> AnyView) {
        self.sync = sync
        self.pillButton = pillButton
        // Test-only: open on a given state, so each one can be screenshotted without clicking.
        switch ProcessInfo.processInfo.environment["NOTCHCAT_ACCOUNT_VIEW"] {
        case "signin": _mode = State(initialValue: .signIn)
        case "key": _mode = State(initialValue: .signUp)
        case "keyerror":
            _mode = State(initialValue: .signUp)
            _error = State(initialValue: "That access key is not valid or has already been used")
        case "details":
            _mode = State(initialValue: .signUp)
            _step = State(initialValue: .details)
        default: break
        }
    }

    var body: some View {
        if let name = sync.username, sync.isSignedIn {
            signedIn(name)
        } else {
            signedOut
        }
    }

    // MARK: Signed in

    private func signedIn(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.amber))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13.5, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                        Text(statusText).font(.system(size: 11)).opacity(0.65).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                if sync.phase != .revoked {
                    pillButton("Sync now") { Task { await sync.syncNow() } }
                }
                Button("Sign out") { Task { await sync.signOut() } }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).opacity(0.6)
            }
        }
    }

    private var dotColor: Color {
        switch sync.phase {
        case .idle: return Color(red: 0.4, green: 0.9, blue: 0.5)
        case .syncing: return Theme.amber
        case .offline, .signedOut: return .gray
        case .failed, .revoked: return Color(red: 1, green: 0.42, blue: 0.4)
        }
    }

    private var statusText: String {
        switch sync.phase {
        case .syncing: return "Syncing…"
        case .offline: return "Offline. Changes sync when you reconnect."
        case .failed(let message): return message
        case .revoked: return "Cloud access was turned off. Your tasks are still here."
        case .idle:
            guard let last = sync.lastSync else { return "Signed in" }
            return "Synced " + last.formatted(.relative(presentation: .named))
        case .signedOut: return ""
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modeButton("Sign in", .signIn)
                modeButton("Sign up", .signUp)
            }
            if let mode {
                VStack(alignment: .leading, spacing: 8) {
                    switch mode {
                    case .signIn: signInFields
                    case .signUp: signUpFields
                    }
                    if let error {
                        Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: mode)
        .animation(.easeOut(duration: 0.18), value: step)
    }

    private func modeButton(_ title: String, _ target: Mode) -> some View {
        let selected = mode == target
        return Button {
            if selected { mode = nil } else { open(target) }
        } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(selected ? 180 : 0))
                    .opacity(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? Theme.amber : .white.opacity(0.1)))
            .foregroundStyle(selected ? Theme.ink : .white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func open(_ target: Mode) {
        mode = target
        step = .key
        error = nil
        password = ""
        showPassword = false
    }

    // MARK: Sign in

    private var signInFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            textField("Username", text: $username)
            passwordField("Password")
            primaryButton(working ? "Signing in…" : "Sign in", enabled: !username.isEmpty && !password.isEmpty && !working) {
                run { try await sync.signIn(username: username, password: password) }
            }
        }
    }

    // MARK: Sign up

    @ViewBuilder
    private var signUpFields: some View {
        switch step {
        case .key:
            VStack(alignment: .leading, spacing: 8) {
                textField("Access key", text: $accessKey, mono: true)
                    .onSubmit { verifyKey() }
                primaryButton(working ? "Checking…" : "Continue", enabled: !accessKey.trimmingCharacters(in: .whitespaces).isEmpty && !working) {
                    verifyKey()
                }
            }
        case .details:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.5))
                    Text("Access key accepted").font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Change") { step = .key; error = nil }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).opacity(0.6)
                }
                textField("Choose a username", text: $username)
                passwordField("Password (8+ characters)")
                primaryButton(working ? "Creating…" : "Create account",
                              enabled: !username.isEmpty && password.count >= 8 && !working) {
                    run {
                        do {
                            try await sync.signUp(accessKey: accessKey, username: username, password: password)
                        } catch let e as APIError where e.status == 403 {
                            // Someone used the key in the meantime, or the owner turned it off.
                            step = .key
                            throw e
                        }
                    }
                }
            }
        }
    }

    private func verifyKey() {
        guard !working, !accessKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        run(onSuccess: { step = .details }) { try await sync.checkAccessKey(accessKey) }
    }

    // MARK: Pieces

    /// Runs a network step with the shared "working" and error handling.
    private func run(onSuccess: (() -> Void)? = nil, _ work: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            do {
                try await work()
                password = ""
                onSuccess?()
            } catch let e as URLError {
                error = e.code == .notConnectedToInternet ? "You're offline." : "Couldn't reach the server."
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func fieldBackground() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08))
    }

    private func textField(_ prompt: String, text: Binding<String>, mono: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.3)))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .font(.system(size: 12.5, weight: .medium, design: mono ? .monospaced : .default))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(fieldBackground())
            .accessibilityLabel(prompt)
    }

    private func passwordField(_ prompt: String) -> some View {
        HStack(spacing: 6) {
            Group {
                if showPassword {
                    TextField("", text: $password, prompt: Text(prompt).foregroundStyle(.white.opacity(0.3)))
                } else {
                    SecureField("", text: $password, prompt: Text(prompt).foregroundStyle(.white.opacity(0.3)))
                }
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .font(.system(size: 12.5, weight: .medium))
            .focused($passwordFocused)
            .onSubmit { submitFromPassword() }
            Button {
                showPassword.toggle()
                passwordFocused = true
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 11.5))
                    .opacity(0.55)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showPassword ? "Hide password" : "Show password")
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(fieldBackground())
    }

    private func submitFromPassword() {
        guard !working else { return }
        if mode == .signIn, !username.isEmpty, !password.isEmpty {
            run { try await sync.signIn(username: username, password: password) }
        } else if mode == .signUp, step == .details, !username.isEmpty, password.count >= 8 {
            run {
                do { try await sync.signUp(accessKey: accessKey, username: username, password: password) }
                catch let e as APIError where e.status == 403 { step = .key; throw e }
            }
        }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.amber))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}
