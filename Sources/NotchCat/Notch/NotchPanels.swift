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
