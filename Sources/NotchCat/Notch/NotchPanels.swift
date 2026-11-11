import AppKit

/// Borderless panel that floats over the menu bar and can take keyboard focus
/// (for the task field) without activating the app.
class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    // Keep the frame exactly where we put it, even over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    // The app has no menu bar, so ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z never reach the text fields. Send them down the responder chain.
    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
           var key = event.charactersIgnoringModifiers?.lowercased() {
            let shift = flags.contains(.shift)
            if key == "z", shift { key = "Z" }   // ⇧⌘Z is redo
            let action = key == "Z" ? Selector(("redo:")) : (shift ? nil : Self.editActions[key])
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The timer pill beside the notch. Never takes focus.
final class PillPanel: FloatingPanel {
    override var canBecomeKey: Bool { false }

    override init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
        // Sit just above the menu bar contents.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }
}
