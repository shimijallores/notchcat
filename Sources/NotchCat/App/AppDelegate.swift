import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // v1 kept data in state.json; bring it into SQLite before anything reads the database.
        if let minutes = LegacyImporter.importIfNeeded(into: .shared) {
            AppSettings.shared.data.defaultFocusMinutes = minutes
        }
        if CommandLine.arguments.contains("--seed-demo") { DemoData.seed(into: .shared) }
        if CommandLine.arguments.contains("--selftest-note") { SelfTest.noteConversion(); exit(0) }
        if CommandLine.arguments.contains("--selftest-settings") { SelfTest.settings(); exit(0) }
        let timer = FocusTimer.shared
        let sessions = SessionRepository(db: .shared)
        timer.sessionLogger = { sessions.insert($0) }

        controller = NotchController()

        // Option-N toggles the panel from anywhere (can be switched off in Settings).
        AppSettings.shared.$data.map(\.hotkeyEnabled).removeDuplicates()
            .sink { [weak self] enabled in
                self?.hotKey = enabled
                    ? HotKey(keyCode: kVK_ANSI_N, modifiers: optionKey) { [weak self] in
                        DispatchQueue.main.async { self?.controller.toggle() }
                    }
                    : nil
            }
            .store(in: &cancellables)

        installStatusItem()

        // Developer conveniences: `--open` shows the panel, `--demo` starts a timer.
        let args = CommandLine.arguments
        if args.contains("--demo") {
            FocusTimer.shared.start(minutes: 25)
        }
        if let i = args.firstIndex(of: "--demo-secs"), i + 1 < args.count, let n = Int(args[i + 1]) {
            FocusTimer.shared.startDemo(seconds: n)
        }
        if let i = args.firstIndex(of: "--close-after"), i + 1 < args.count, let n = Double(args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + n) { self.controller.hide() }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            FocusTimer.shared.start(minutes: 25)
            controller.writeSnapshots(to: URL(fileURLWithPath: args[i + 1])) { NSApp.terminate(nil) }
        }
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count,
           let tab = PanelTab.allCases.first(where: { $0.rawValue.lowercased() == args[i + 1] }) {
            controller.ui.tab = tab
        }
        // Test-only: add a reminder N seconds out. Refuses to touch the real database.
        if let i = args.firstIndex(of: "--remind-in"), i + 1 < args.count, let n = Double(args[i + 1]),
           ProcessInfo.processInfo.environment["NOTCHCAT_DB"] != nil {
            let store = TaskStore.shared
            store.add(title: "Call mom", on: store.today)
            if let id = store.tasks.last?.id { store.setReminder(id, at: Date().addingTimeInterval(n)) }
        }
        if let i = args.firstIndex(of: "--tab-after"), i + 2 < args.count, let delay = Double(args[i + 1]),
           let tab = PanelTab.allCases.first(where: { $0.rawValue.lowercased() == args[i + 2] }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.controller.ui.tab = tab }
        }
        if args.contains("--log-frames") { controller.logFrames() }
        if args.contains("--open-hover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.controller.show(pinned: false) }
        }
        if args.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.controller.show(pinned: true) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusTimer.shared.flushForQuit()
        NoteStore.shared.flush()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = Mascot.image {
                let scaled = NSImage(size: NSSize(width: 18, height: 18))
                scaled.lockFocus()
                image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                scaled.unlockFocus()
                scaled.isTemplate = false
                button.image = scaled
            } else {
                button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "NotchCat")
            }
        }

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open NotchCat", action: #selector(openPanel), keyEquivalent: "n")
        open.keyEquivalentModifierMask = [.option]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NotchCat", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func openPanel() { controller.show(pinned: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}
