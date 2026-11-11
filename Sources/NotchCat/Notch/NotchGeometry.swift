import AppKit

/// Where the notch is on a screen, in global (bottom-left origin) coordinates.
struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    /// Hardware notch (or a virtual one on screens without a notch).
    let notchRect: NSRect
    /// What actually gets drawn at the top of the screen: the hardware notch, the fake notch, or the
    /// floating island. The timer pill and album chip line up against this.
    let shapeRect: NSRect
    /// The fake shape in use. Always `.off` on a screen with a hardware notch.
    let fakeStyle: FakeNotchStyle
    /// Height of the menu bar strip.
    let menuBarHeight: CGFloat

    /// The screen that has the notch, otherwise the primary screen.
    static func current(fake: FakeNotchStyle = .off) -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first
            ?? NSScreen.main!
        return NotchGeometry(screen: screen, fake: fake)
    }

    /// Developer: NOTCHCAT_FORCE_NO_NOTCH=1 treats a notched screen as if it had none, to test the fake notch.
    private static let forceNoNotch = ProcessInfo.processInfo.environment["NOTCHCAT_FORCE_NO_NOTCH"] != nil

    /// True when any connected screen has a real notch (so the fake one is never needed).
    static var hasHardwareNotch: Bool { !forceNoNotch && NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    /// Island size: a floating capsule inside the menu bar, with a small gap above and below.
    private static let islandWidth: CGFloat = 116
    private static let islandTopGap: CGFloat = 3

    init(screen: NSScreen, fake: FakeNotchStyle = .off) {
        self.screen = screen
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        hasNotch = inset > 0 && !Self.forceNoNotch

        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            menuBarHeight = inset
            notchRect = NSRect(x: frame.minX + left.width, y: frame.maxY - inset,
                               width: width, height: inset)
            shapeRect = notchRect
            fakeStyle = .off
        } else {
            // No notch: pretend there is a small one at top center, below the menu bar.
            let bar = max(24, frame.maxY - screen.visibleFrame.maxY)
            menuBarHeight = bar
            let width: CGFloat = 180
            notchRect = NSRect(x: frame.midX - width / 2, y: frame.maxY - bar,
                               width: width, height: bar)
            fakeStyle = fake
            if fake == .island {
                let h = max(18, bar - Self.islandTopGap * 2)
                let w = Self.islandWidth
                shapeRect = NSRect(x: (frame.midX - w / 2).rounded(), y: frame.maxY - Self.islandTopGap - h,
                                   width: w, height: h)
            } else {
                shapeRect = notchRect
            }
        }
    }

    /// Where the fake notch / island window goes, on whole points so the top edge is crisp.
    var fakeNotchFrame: NSRect {
        let r = shapeRect
        let w = (r.width / 2).rounded() * 2
        let h = r.height.rounded()
        return NSRect(x: (r.midX - w / 2).rounded(), y: (r.maxY - h).rounded(), width: w, height: h)
    }

    /// The area where hovering opens the panel.
    var hoverRect: NSRect {
        NSRect(x: notchRect.minX - 6, y: notchRect.minY - 2,
               width: notchRect.width + 12, height: notchRect.height + 40)
    }

    /// The notch itself: where a click opens the panel. Tighter than `hoverRect`, which reaches into other apps' windows.
    var clickRect: NSRect { notchRect.insetBy(dx: -6, dy: -2) }

    /// Widest the tray may get on this screen.
    var maxPanelWidth: CGFloat { min(screen.frame.width * 0.74, 1120) }

    /// Frame of the expanded panel: flush with the top of the screen, centered on the notch.
    func panelFrame(width requested: CGFloat) -> NSRect {
        let frame = screen.frame
        let width = min(max(requested, 780), maxPanelWidth)
        let height = min(max(frame.height * 0.36, 320), 400)
        return alignedFrame(width: width, height: height)
    }

    var panelFrame: NSRect { panelFrame(width: 780) }

    /// Compact "Dynamic Island" frame: just wider than the notch, a slim row below it.
    var islandFrame: NSRect {
        let frame = screen.frame
        let width = max(notchRect.width + 230, 440)
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
        return NSPoint(x: shapeRect.maxX + 8, y: y)
    }
}
