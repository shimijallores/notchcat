import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()

        // Option-N toggles the panel from anywhere.
        hotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: optionKey) { [weak self] in
            DispatchQueue.main.async { self?.controller.toggle() }
        }

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
        if args.contains("--log-frames") { controller.logFrames() }
        if args.contains("--open-hover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.controller.show(pinned: false) }
        }
        if args.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.controller.show(pinned: true) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TaskStore.shared.save()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
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
