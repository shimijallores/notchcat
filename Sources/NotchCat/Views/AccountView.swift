import SwiftUI

// Cloud sync: the card in Settings, and the full-card screens it opens.
//
// Signed out, the card is two buttons. Tapping one replaces the whole Settings list with a single form on a
// card of that button's colour: mint for signing in, lavender for signing up (the Tasks and Focus pastels).
// When it works, a short welcome plays and Settings comes back.

/// Which full-card screen the Settings tab is showing instead of the settings list.
enum AuthFlow: Equatable {
    case signIn
    case signUp
    case welcome(name: String, created: Bool)

    var tint: Color {
        switch self {
        case .signIn: return Theme.signInTint
        case .signUp: return Theme.signUpTint
        case .welcome(_, let created): return created ? Theme.signUpTint : Theme.signInTint
        }
    }

    /// Test-only: NOTCHCAT_ACCOUNT_VIEW opens a screen directly so each state can be photographed without clicking.
    static func fromTestEnvironment() -> AuthFlow? {
        switch ProcessInfo.processInfo.environment["NOTCHCAT_ACCOUNT_VIEW"] {
        case "signin": return .signIn
        case "key", "keyerror", "details": return .signUp
        case "welcome", "welcome-done": return .welcome(name: "alex", created: false)
        default: return nil
        }
    }
}

extension Theme {
    static let signInTint = mint
    static let signUpTint = lavender
    /// Readable on the pastels, where the app's bright red would wash out.
    static let errorInk = Color(red: 0.62, green: 0.13, blue: 0.13)
    static let okInk = Color(red: 0.12, green: 0.40, blue: 0.20)
}

// MARK: - The card in Settings

struct CloudSyncPanel: View {
    @ObservedObject var sync: SyncEngine
    @Binding var flow: AuthFlow?

    var body: some View {
        if let name = sync.username, sync.isSignedIn {
            SignedInSummary(sync: sync, name: name)
        } else {
            HStack(spacing: 8) {
                ChoiceButton(title: "Sign in", tint: Theme.signInTint) { flow = .signIn }
                ChoiceButton(title: "Sign up", tint: Theme.signUpTint) { flow = .signUp }
            }
        }
    }
}

private struct ChoiceButton: View {
    let title: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(tint))
                .brightness(hovering ? 0.05 : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

/// Presses in slightly. Transform only, so nothing reflows.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct SignedInSummary: View {
    @ObservedObject var sync: SyncEngine
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.signInTint))
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
                    Button { Task { await sync.syncNow() } } label: {
                        Text("Sync now")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.amber))
                    }
                    .buttonStyle(PressStyle())
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
}

// MARK: - The full-card screens

/// The pastel card that replaces the settings list. The card keeps its colour while its contents change, so the
/// step from form to welcome is a change of content, not a new screen.
struct AuthTakeover: View {
    @ObservedObject var sync: SyncEngine
    @Binding var flow: AuthFlow?

    var body: some View {
        let current = flow ?? .signIn
        ZStack {
            switch current {
            case .signIn:
                AuthScreen(sync: sync, mode: .signIn, close: close, succeeded: succeeded)
                    .transition(.opacity)
            case .signUp:
                AuthScreen(sync: sync, mode: .signUp, close: close, succeeded: succeeded)
                    .transition(.opacity)
            case .welcome(let name, let created):
                WelcomeScreen(name: name, created: created, tint: current.tint, finish: close)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(current.tint, radius: 22)
        .environment(\.colorScheme, .light)
        .animation(.easeInOut(duration: 0.3), value: current)
    }

    private func close() { flow = nil }

    private func succeeded(_ name: String, created: Bool) {
        flow = .welcome(name: name, created: created)
    }
}

private struct AuthScreen: View {
    enum Mode { case signIn, signUp }
    enum Step { case key, details }
    enum Field { case key, username, password }

    @ObservedObject var sync: SyncEngine
    let mode: Mode
    let close: () -> Void
    let succeeded: (String, Bool) -> Void

    @State private var step: Step = .key
    @State private var accessKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var working = false
    @State private var error: String?
    @FocusState private var focus: Field?

    init(sync: SyncEngine, mode: Mode, close: @escaping () -> Void, succeeded: @escaping (String, Bool) -> Void) {
        self.sync = sync
        self.mode = mode
        self.close = close
        self.succeeded = succeeded
        // Test-only starting states (see AuthFlow.fromTestEnvironment).
        switch ProcessInfo.processInfo.environment["NOTCHCAT_ACCOUNT_VIEW"] {
        case "keyerror": _error = State(initialValue: "That access key is not valid or has already been used.")
        case "details": _step = State(initialValue: .details)
        default: break
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            intro
                .frame(width: 270, alignment: .leading)
            form
                .frame(width: 330)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { backButton.padding(16) }
        .onAppear { focus = mode == .signIn ? .username : .key }
    }

    // MARK: Left: what this is

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            MascotView(size: 54)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 13.5, weight: .medium))
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch (mode, step) {
        case (.signIn, _): return "Welcome back"
        case (.signUp, .key): return "Join NotchCat"
        case (.signUp, .details): return "Almost there"
        }
    }

    private var subtitle: String {
        switch (mode, step) {
        case (.signIn, _): return "Sign in to keep your tasks, notes and focus time in step on every device."
        case (.signUp, .key): return "Cloud sync is invite only. Enter the access key you were given."
        case (.signUp, .details): return "Choose a username and a password for your account."
        }
    }

    private var backButton: some View {
        Button(action: close) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Settings").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.4)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Back to settings")
    }

    // MARK: Right: the form

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch (mode, step) {
            case (.signIn, _): signInFields
            case (.signUp, .key): keyFields
            case (.signUp, .details): detailFields
            }
        }
        .disabled(working)
    }

    private var signInFields: some View {
        Group {
            labeled("Username") {
                TextField("", text: $username, prompt: prompt("alex"))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                    .fieldBox(focused: focus == .username, invalid: error != nil)
            }
            labeled("Password") {
                passwordField(focus: .password, invalid: error != nil)
                    .onSubmit { submit() }
            }
            messageLine(helper: nil)
            primary("Sign in", busy: "Signing in…", enabled: !username.isEmpty && !password.isEmpty) { submit() }
        }
    }

    private var keyFields: some View {
        Group {
            labeled("Access key") {
                TextField("", text: $accessKey, prompt: prompt("NC-XXXX-XXXX-XXXX-XXXX"))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .focused($focus, equals: .key)
                    .onSubmit { verifyKey() }
                    .fieldBox(focused: focus == .key, invalid: error != nil)
            }
            messageLine(helper: "Contact owner for access key")
            primary("Continue", busy: "Checking…", enabled: !accessKey.trimmingCharacters(in: .whitespaces).isEmpty) { verifyKey() }
        }
    }

    private var detailFields: some View {
        Group {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.okInk)
                Text("Access key accepted").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button("Change") { step = .key; error = nil; focus = .key }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).opacity(0.65)
            }
            labeled("Username") {
                TextField("", text: $username, prompt: prompt("Choose a username"))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                    .fieldBox(focused: focus == .username, invalid: error != nil && focus != .password)
            }
            labeled("Password") {
                passwordField(focus: .password, invalid: false)
                    .onSubmit { submit() }
            }
            messageLine(helper: "At least 8 characters")
            primary("Create account", busy: "Creating…", enabled: !username.isEmpty && password.count >= 8) { submit() }
        }
    }

    // MARK: Actions

    private func verifyKey() {
        guard !working, !accessKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        perform {
            try await sync.checkAccessKey(accessKey)
            step = .details
            focus = .username
        }
    }

    private func submit() {
        guard !working else { return }
        switch mode {
        case .signIn:
            guard !username.isEmpty, !password.isEmpty else { return }
            perform {
                try await sync.signIn(username: username, password: password)
                succeeded(sync.username ?? username, false)
            }
        case .signUp:
            guard step == .details, !username.isEmpty, password.count >= 8 else { return }
            perform {
                do {
                    try await sync.signUp(accessKey: accessKey, username: username, password: password)
                } catch let e as APIError where e.status == 403 {
                    step = .key   // the key was used or turned off in the meantime
                    throw e
                }
                succeeded(sync.username ?? username, true)
            }
        }
    }

    /// Runs a network step with the shared busy and error handling.
    private func perform(_ work: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            do {
                try await work()
            } catch let e as URLError {
                error = e.code == .notConnectedToInternet ? "You're offline. Check your connection and try again." : "Couldn't reach the server. Try again in a moment."
            } catch {
                self.error = Self.sentence(error.localizedDescription)
            }
            working = false
        }
    }

    private static func sentence(_ text: String) -> String {
        text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") ? text : text + "."
    }

    // MARK: Pieces

    private func prompt(_ text: String) -> Text { Text(text).foregroundStyle(Theme.ink.opacity(0.32)) }

    /// A visible label above the field, never the placeholder.
    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).opacity(0.75)
            content()
        }
    }

    private func passwordField(focus field: Field, invalid: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if showPassword {
                    TextField("", text: $password, prompt: prompt("Password"))
                } else {
                    SecureField("", text: $password, prompt: prompt("Password"))
                }
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            Button {
                showPassword.toggle()
                focus = field
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .opacity(0.6)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showPassword ? "Hide password" : "Show password")
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
        .fieldBox(focused: focus == field, invalid: invalid)
    }

    /// One line that holds the helper text, and is replaced by the error rather than joined by it. Its height is
    /// reserved, so the form doesn't jump when an error appears.
    private func messageLine(helper: String?) -> some View {
        Group {
            if let error {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11.5))
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.errorInk)
            } else if let helper {
                Text(helper).opacity(0.6)
            } else {
                Text(" ")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
    }

    private func primary(_ title: String, busy: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small).tint(.white) }
                Text(working ? busy : title)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(Theme.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .opacity(enabled || working ? 1 : 0.45)
        .disabled(!enabled && !working)
        .keyboardShortcut(.defaultAction)
    }
}

/// The input look on a pastel card: a soft white field with a border that is always there (and only changes colour),
/// so focusing or an error never shifts the layout.
private extension View {
    func fieldBox(focused: Bool, invalid: Bool) -> some View {
        self
            .font(.system(size: 13.5, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.55)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(invalid ? Theme.errorInk : (focused ? Theme.ink.opacity(0.7) : Theme.ink.opacity(0.12)), lineWidth: 1.5)
            )
    }
}

// MARK: - The welcome

/// Plays once after signing in or signing up, then hands control back so Settings returns.
/// A ring draws around the cat, a check pops in, the greeting fades up. With Reduce Motion it just fades.
private struct WelcomeScreen: View {
    let name: String
    let created: Bool
    let tint: Color
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringDrawn = false
    @State private var markShown = false
    @State private var textShown = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: ringDrawn ? 1 : 0)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                MascotView(size: 66)
                    .scaleEffect(markShown ? 1 : 0.6)
                    .opacity(markShown ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.okInk))
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .offset(x: 38, y: 38)
                    .scaleEffect(markShown ? 1 : 0.01)
            }
            .frame(width: 112, height: 112)

            VStack(spacing: 6) {
                Text(created ? "You're in, \(name)" : "Welcome back, \(name)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Your tasks, notes and focus time now follow you everywhere.")
                    .font(.system(size: 13.5, weight: .medium))
                    .opacity(0.7)
            }
            .opacity(textShown ? 1 : 0)
            .offset(y: textShown || reduceMotion ? 0 : 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .task { await play() }
    }

    private func play() async {
        let holdForTests = ProcessInfo.processInfo.environment["NOTCHCAT_ACCOUNT_VIEW"] == "welcome-done"
        if reduceMotion || holdForTests {
            ringDrawn = true; markShown = true
            withAnimation(.easeOut(duration: 0.2)) { textShown = true }
            if holdForTests { return }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            finish()
            return
        }
        withAnimation(.easeOut(duration: 0.55)) { ringDrawn = true }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { markShown = true }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(.easeOut(duration: 0.4)) { textShown = true }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        finish()
    }
}
