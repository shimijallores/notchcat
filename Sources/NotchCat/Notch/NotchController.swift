import AppKit
import SwiftUI
import Combine

/// Shared UI state for the expanded panel.
@MainActor
final class PanelUIState: ObservableObject {
    enum Modal: Equatable {
        case taskLimit(UUID)
        case timerDuration
    }

    enum Mode { case dashboard, island }

    @Published var expanded = false
    @Published var mode: Mode = .dashboard
    /// Size of the hardware notch: the shape the housing grows out of.
    @Published var notchSize = CGSize(width: 180, height: 32)
    @Published var modal: Modal?
    @Published var size = CGSize(width: 760, height: 340)
    /// Bumped to ask the task field to take focus.
    @Published var focusRequest = 0
    /// Height of the menu-bar strip the header row sits in.
    @Published var headerHeight: CGFloat = 32
    /// Width of the hardware notch, left empty in the header.
    @Published var notchWidth: CGFloat = 190

    var close: () -> Void = {}
}

/// Owns the expanded panel and the timer pill, and decides when each is shown.
@MainActor
final class NotchController {
    private let store = TaskStore.shared
    private let timer = FocusTimer.shared
    let ui = PanelUIState()

    private var geometry = NotchGeometry.current()
    private let panel: FloatingPanel
    private let container: DropContainerView
    private let pill: PillPanel

    private var pinned = false
    private var hoverArmed = true
    private var hoverWork: DispatchWorkItem?
    private var exitPoll: Timer?
    private var outsideTicks = 0

    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    private let pillUI = PillUIState()
    private var pillGeneration = 0

    init() {
        panel = FloatingPanel(contentRect: geometry.panelFrame)
        pill = PillPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 24))

        // All stored properties must exist before any closure captures `self`.
        let root = RootView(ui: ui, store: store, timer: timer)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        container = DropContainerView(host: host)
        panel.contentView = container

        ui.close = { [weak self] in self?.hide() }
        panel.onCancel = { [weak self] in self?.handleEscape() }

        let pillView = PillView(timer: timer, ui: pillUI, height: { [weak self] in self?.geometry.pillHeight ?? 24 }) { [weak self] in
            self?.show(pinned: true)
        }
        let pillHost = FirstMouseHostingView(rootView: pillView)
        pillHost.sizingOptions = []
        pill.contentView = pillHost

        applyGeometry()
        installMonitors()
        bindPill()
        prewarm()

        // When a session ends with the panel closed, the notch stretches into a compact island.
        timer.$state.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, state == .finished, !self.ui.expanded else { return }
                self.show(pinned: true, mode: .island)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyGeometry() }
        }
    }

    // MARK: - Showing and hiding

    func toggle() {
        ui.expanded ? hide() : show(pinned: true)
    }

    func show(pinned: Bool, mode: PanelUIState.Mode = .dashboard) {
        if ui.expanded {
            if ui.mode != mode {
                // Switch styles by retracting first, then growing the other one.
                hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
                    self?.show(pinned: pinned, mode: mode)
                }
            } else if pinned, mode == .dashboard {
                self.pinned = true
                focusPanel()
            }
            return
        }
        hoverWork?.cancel()
        panel.alphaValue = 1
        ui.mode = mode
        applyGeometry()
        self.pinned = pinned
        outsideTicks = 0

        panel.orderFrontRegardless()
        if pinned, mode == .dashboard { focusPanel() }

        // Start collapsed (notch-sized), then let Core Animation grow it on the next turn.
        panel.ignoresMouseEvents = false
        DispatchQueue.main.async {
            self.container.animate(expanded: true)
            self.ui.expanded = true
        }
        startExitPoll()
        if pinned, mode == .dashboard { ui.focusRequest += 1 }
    }

    func hide() {
        guard ui.expanded else { return }
        hoverArmed = false
        stopExitPoll()
        ui.expanded = false
        ui.modal = nil
        container.animate(expanded: false)
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self, !self.ui.expanded else { return }
            self.panel.orderOut(nil)
        }
    }

    private func focusPanel() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func handleEscape() {
        if ui.modal != nil {
            ui.modal = nil
        } else {
            hide()
        }
    }

    /// Builds the SwiftUI tree once, invisibly, so the first real open doesn't pay for it mid-animation.
    private func prewarm() {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        container.host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.panel.alphaValue = 1
            if !self.ui.expanded { self.panel.orderOut(nil) }
        }
    }

    /// Developer: logs the window frame and mask geometry every ~8ms for a second (`--log-frames`).
    func logFrames() {
        let start = CACurrentMediaTime()
        var last = ""
        Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let now = CACurrentMediaTime() - start
                if now > 6 { t.invalidate(); return }
                let f = self.panel.frame
                let m = self.container.debugMask()
                let line = "frame y=\(f.origin.y) h=\(f.height) top=\(f.maxY) screenTop=\(self.geometry.screen.frame.maxY) vis=\(self.panel.isVisible) key=\(self.panel.isKeyWindow) | mask \(m)"
                if line != last { print(String(format: "%.3f ", now) + line); last = line }
            }
        }
    }

    // MARK: - Developer snapshot (--snapshot <dir>)

    /// Renders the expanded panel and the pill to PNGs without needing screen-recording access.
    func writeSnapshots(to dir: URL, completion: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        show(pinned: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.snapshot(self.container.host, to: dir.appendingPathComponent("panel.png"))
            self.ui.modal = .timerDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.snapshot(self.container.host, to: dir.appendingPathComponent("modal.png"))
                self.ui.modal = nil
                self.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.snapshot(self.pill.contentView, to: dir.appendingPathComponent("pill.png"))
                    print("pill frame:", self.pill.frame, "visible:", self.pill.isVisible,
                          "notch:", self.geometry.notchRect, "hasNotch:", self.geometry.hasNotch)
                    completion()
                }
            }
        }
    }

    private func snapshot(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    // MARK: - Geometry

    private func applyGeometry() {
        geometry = .current()
        let frame = ui.mode == .island ? geometry.islandFrame : geometry.panelFrame
        ui.size = frame.size
        ui.notchSize = geometry.notchRect.size
        ui.headerHeight = geometry.menuBarHeight
        ui.notchWidth = geometry.notchRect.width
        panel.setFrame(frame, display: true)
        container.configure(notch: geometry.notchRect.size,
                            radius: ui.mode == .island ? 24 : 30,
                            expanded: ui.expanded)
        layoutPill()
    }

    private func layoutPill() {
        let h = geometry.pillHeight
        let w = PillMetrics.width(for: timer.remaining.clockString, height: h)
        let origin = geometry.pillOrigin(width: w)
        pill.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
    }

    // MARK: - Pill visibility

    private func bindPill() {
        Publishers.CombineLatest3(timer.$state, timer.$remaining, ui.$expanded)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, _, expanded in
                guard let self else { return }
                let shouldShow = state != .idle && !expanded
                if shouldShow {
                    self.layoutPill()
                    if !self.pill.isVisible {
                        // Peel off the notch's right shoulder once the tray has mostly retracted.
                        self.pillGeneration += 1
                        self.pillUI.shown = false
                        self.pill.orderFrontRegardless()
                        let gen = self.pillGeneration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                            guard let self, gen == self.pillGeneration else { return }
                            self.pillUI.shown = true
                        }
                    } else {
                        self.pillUI.shown = true
                    }
                } else if self.pill.isVisible {
                    self.pillGeneration += 1
                    let gen = self.pillGeneration
                    self.pillUI.shown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                        guard let self, gen == self.pillGeneration else { return }
                        self.pill.orderOut(nil)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Hover, click-away, exit polling

    private func installMonitors() {
        // Hovering the notch opens the panel. Mouse-moved needs no special permission.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(m) }

        // Clicking anywhere in another app closes the panel.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.ui.expanded else { return }
                self.hide()
            }
        }) { monitors.append(m) }

        // A click inside the panel keeps it open even if opened by hover.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window === self.panel { self.pinned = true }
            }
            return event
        }) { monitors.append(m) }
    }

    private func mouseMoved() {
        guard !ui.expanded else { return }
        let p = NSEvent.mouseLocation
        let inside = geometry.hoverRect.contains(p)
        if !inside {
            hoverArmed = true
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverArmed, hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            if self.geometry.hoverRect.contains(NSEvent.mouseLocation), !self.ui.expanded {
                self.show(pinned: false)
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func startExitPoll() {
        stopExitPoll()
        exitPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollExit() }
        }
    }

    private func stopExitPoll() {
        exitPoll?.invalidate()
        exitPoll = nil
    }

    private func pollExit() {
        guard ui.expanded, !pinned else { return }
        let p = NSEvent.mouseLocation
        let keepOpen = panel.frame.insetBy(dx: -14, dy: -14).contains(p) || geometry.hoverRect.contains(p)
        outsideTicks = keepOpen ? 0 : outsideTicks + 1
        if outsideTicks >= 4 { hide() }
    }
}
