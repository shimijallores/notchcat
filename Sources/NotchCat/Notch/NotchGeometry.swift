import AppKit

/// Where the notch is on a screen, in global (bottom-left origin) coordinates.
struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    /// Hardware notch (or a virtual one on screens without a notch).
    let notchRect: NSRect
    /// Height of the menu bar strip.
    let menuBarHeight: CGFloat

    /// The screen that has the notch, otherwise the primary screen.
    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first
            ?? NSScreen.main!
        return NotchGeometry(screen: screen)
    }

    init(screen: NSScreen) {
        self.screen = screen
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        hasNotch = inset > 0

        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            menuBarHeight = inset
            notchRect = NSRect(x: frame.minX + left.width, y: frame.maxY - inset,
                               width: width, height: inset)
        } else {
            // No notch: pretend there is a small one at top center, below the menu bar.
            let bar = max(24, frame.maxY - screen.visibleFrame.maxY)
            menuBarHeight = bar
            let width: CGFloat = 180
            notchRect = NSRect(x: frame.midX - width / 2, y: frame.maxY - bar,
                               width: width, height: bar)
        }
    }

    /// The area where hovering opens the panel.
    var hoverRect: NSRect {
        NSRect(x: notchRect.minX - 6, y: notchRect.minY - 2,
               width: notchRect.width + 12, height: notchRect.height + 40)
    }

    /// Frame of the expanded panel: flush with the top of the screen, centered on the notch.
    var panelFrame: NSRect {
        let frame = screen.frame
        let width = min(max(frame.width * 0.52, 720), 860)
        let height = min(max(frame.height * 0.36, 320), 400)
        return alignedFrame(width: width, height: height)
    }

    /// Compact "Dynamic Island" frame: just wider than the notch, a slim row below it.
    var islandFrame: NSRect {
        let frame = screen.frame
        let width = max(notchRect.width + 170, 380)
        let height = menuBarHeight + 62
        return alignedFrame(width: width, height: height)
    }

    /// Whole-point, even-sized frame centered on the notch with its top exactly on the screen edge.
    /// Fractional sizes get snapped to the pixel grid by AppKit, which can leave a sliver of menu bar showing.
    private func alignedFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let w = (width / 2).rounded() * 2
        let h = (height / 2).rounded() * 2
        let x = (notchRect.midX - w / 2).rounded()
        return NSRect(x: x, y: screen.frame.maxY - h, width: w, height: h)
    }

    /// Height of the pill: a bit shorter than the menu bar so it floats inside it.
    var pillHeight: CGFloat { max(22, menuBarHeight - 8) }

    /// Right shoulder of the notch, inline with the menu bar.
    func pillOrigin(width: CGFloat) -> NSPoint {
        let y = notchRect.maxY - menuBarHeight + (menuBarHeight - pillHeight) / 2
        return NSPoint(x: notchRect.maxX + 8, y: y)
    }
}
