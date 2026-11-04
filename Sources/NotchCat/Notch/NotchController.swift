import AppKit
import SwiftUI
import Combine

/// What the compact island is showing.
enum IslandKind: Equatable {
    case timerFinished
    case reminder(UUID)
}

enum PanelTab: String, CaseIterable, Identifiable {
    case workspace = "Workspace", week = "Week", insights = "Insights", settings = "Settings"
    var id: String { rawValue }
}

/// Shared UI state for the expanded panel.
@MainActor
final class PanelUIState: ObservableObject {
    enum Modal: Equatable {
        case taskLimit(UUID)
        case timerDuration
        case customReminder(UUID)
    }

    enum Mode { case dashboard, island }

    @Published var expanded = false
    @Published var mode: Mode = .dashboard
    @Published var tab: PanelTab = .workspace
    @Published var islandKind: IslandKind = .timerFinished
    /// A reminder that fired while the tray was already open; shown as a banner instead of the island.
    @Published var banner: UUID?
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

    private var geometry = NotchGeometry.current(fake: AppSettings.shared.data.fakeNotch)
    private let panel: FloatingPanel
    private let container: DropContainerView
    private let pill: PillPanel
    private let chip: PillPanel
    /// Black notch / island drawn on screens without a hardware notch.
    private let fakeNotch: PillPanel
    private var fakeGeneration = 0

    private var pinned = false
    private var hoverArmed = true
    private var hoverWork: DispatchWorkItem?
    private var exitPoll: Timer?
    private var outsideTicks = 0

    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    private let pillUI = PillUIState()
    private var pillGeneration = 0
    private let chipUI = PillUIState()
    private var chipGeneration = 0
    /// Whether the album-art chip is (or is about to be) on screen, which moves the timer pill over.
    private var chipWanted = false

    private let settings = AppSettings.shared
    private var reminders: ReminderScheduler?
    /// Islands waiting for the current one to finish (a reminder landing during "Time's up", etc).
    private var islandQueue: [IslandKind] = []

    init() {
        panel = FloatingPanel(contentRect: geometry.panelFrame)
        pill = PillPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 24))
        chip = PillPanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 24))
        fakeNotch = PillPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 24))

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

        let chipView = MusicChipView(music: MusicService.shared, ui: chipUI,
                                     height: { [weak self] in self?.geometry.pillHeight ?? 24 }) { [weak self] in
            self?.show(pinned: true)
        }
        let chipHost = FirstMouseHostingView(rootView: chipView)
        chipHost.sizingOptions = []
        chip.contentView = chipHost

        let fakeView = FakeNotchView()
        fakeView.onClick = { [weak self] in self?.show(pinned: true) }
        fakeNotch.contentView = fakeView

        applyGeometry()
        installMonitors()
        bindPill()
        bindChip()
        bindFakeNotch()
        prewarm()

        // When a session ends, the notch stretches into a compact "Time's up" island.
        timer.$state.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, state == .finished, self.settings.data.timeUpIsland else { return }
                self.present(.timerFinished)
            }
            .store(in: &cancellables)

        // Reminders come due -> island (or a banner if the tray is already open).
        reminders = ReminderScheduler(store: store, settings: settings) { [weak self] task in
            self?.present(.reminder(task.id))
        }

        // The tray resizes to fit the visible cards and the current tab.
        ui.$tab.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanel() }
            .store(in: &cancellables)
        settings.$data.map(\.cards).removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanel() }
            .store(in: &cancellables)
        // Hiding a tab you are on sends you back to the workspace.
        settings.$data.receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let self else { return }
                if (self.ui.tab == .week && !data.showWeekTab) || (self.ui.tab == .insights && !data.showInsightsTab) {
                    self.ui.tab = .workspace
                }
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
        ui.banner = nil
        container.animate(expanded: false)
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self, !self.ui.expanded else { return }
            self.panel.orderOut(nil)
            // Show whatever was waiting behind the island that just closed.
            if !self.islandQueue.isEmpty {
                let next = self.islandQueue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.present(next) }
            }
        }
    }

    // MARK: - Islands and banners

    /// Shows a compact island for a finished timer or a reminder, without disturbing what the user is doing.
    func present(_ kind: IslandKind) {
        if settings.data.timerSound {
            switch kind {
            case .reminder: NSSound(named: NSSound.Name("Ping"))?.play()
            case .timerFinished: break   // the timer plays its own sound
            }
        }

        if ui.expanded && ui.mode == .dashboard {
            // The tray is open: a reminder becomes a banner inside it; the timer card already says "Time's up".
            if case .reminder(let id) = kind { ui.banner = id }
            return
        }
        if ui.expanded && ui.mode == .island {
            if ui.islandKind != kind, !islandQueue.contains(kind) { islandQueue.append(kind) }
            return
        }
        ui.islandKind = kind
        show(pinned: true, mode: .island)
    }

    // MARK: - Panel size

    private func desiredPanelWidth() -> CGFloat {
        switch ui.tab {
        case .workspace:
            let cards = settings.visibleCards
            return cards.reduce(0) { $0 + $1.preferredWidth } + 10 * CGFloat(max(cards.count - 1, 0)) + 24
        case .week: return 840
        case .insights, .settings: return 780
        }
    }

    /// Re-fits the tray after a tab or card change, easing the width when it is on screen.
    private func resizePanel() {
        guard ui.mode == .dashboard else { return }
        geometry = currentGeometry()
        let frame = geometry.panelFrame(width: desiredPanelWidth())
        guard frame != panel.frame else { return }
        ui.size = frame.size
        if ui.expanded, panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
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
                let line = "frame x=\(f.origin.x) w=\(f.width) y=\(f.origin.y) h=\(f.height) top=\(f.maxY) screenTop=\(self.geometry.screen.frame.maxY) vis=\(self.panel.isVisible) key=\(self.panel.isKeyWindow) | mask \(m)"
                if line != last { FileHandle.standardError.write(Data((String(format: "%.3f ", now) + line + "\n").utf8)); last = line }
            }
        }
    }

    // MARK: - Developer snapshot (--snapshot <dir>)

    /// Renders every tab, the duration modal and the pill to PNGs without needing screen-recording access.
    func writeSnapshots(to dir: URL, completion: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        show(pinned: true)

        let tabs: [PanelTab] = [.workspace, .week, .insights, .settings]
        func step(_ index: Int) {
            guard index < tabs.count else { return finish() }
            ui.tab = tabs[index]
            DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 1.0 : 0.7)) {
                self.snapshot(self.container.host, to: dir.appendingPathComponent("tab-\(tabs[index].rawValue.lowercased()).png"))
                step(index + 1)
            }
        }

        func finish() {
            // Settings scrolls, so also render it tall enough to see every section.
            let tall = NSHostingView(rootView: SettingsView(settings: settings)
                .padding(12).background(Color(DropContainerView.housing)).frame(width: 780, height: 1180))
            tall.frame = NSRect(x: 0, y: 0, width: 780, height: 1180)
            tall.layoutSubtreeIfNeeded()
            snapshot(tall, to: dir.appendingPathComponent("settings-full.png"))
            ui.tab = .workspace
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.ui.modal = .timerDuration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.snapshot(self.container.host, to: dir.appendingPathComponent("modal.png"))
                    self.ui.modal = nil
                    self.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.snapshot(self.pill.contentView, to: dir.appendingPathComponent("pill.png"))
                        completion()
                    }
                }
            }
        }
        step(0)
    }

    private func snapshot(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    // MARK: - Geometry

    private func applyGeometry() {
        geometry = currentGeometry()
        let frame = ui.mode == .island ? geometry.islandFrame : geometry.panelFrame(width: desiredPanelWidth())
        ui.size = frame.size
        ui.notchSize = geometry.notchRect.size
        ui.headerHeight = geometry.menuBarHeight
        ui.notchWidth = geometry.notchRect.width
        panel.setFrame(frame, display: true)
        container.configure(notch: geometry.notchRect.size,
                            radius: ui.mode == .island ? 24 : 30,
                            expanded: ui.expanded)
        layoutPill()
        layoutFakeNotch()
    }

    private func currentGeometry() -> NotchGeometry {
        NotchGeometry.current(fake: settings.data.fakeNotch)
    }

    private func layoutPill(animated: Bool = false) {
        let h = geometry.pillHeight
        let w = PillMetrics.width(for: timer.remaining.clockString, height: h)
        var origin = geometry.pillOrigin(width: w)

        // The album-art chip takes the spot next to the notch; the timer pill slides over.
        let chipWidth = MusicChipView.width(height: h)
        chip.setFrame(NSRect(x: origin.x, y: origin.y, width: chipWidth, height: h), display: true)
        if chipWanted { origin.x += chipWidth + 6 }

        let frame = NSRect(origin: origin, size: NSSize(width: w, height: h))
        if animated, pill.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                pill.animator().setFrame(frame, display: true)
            }
        } else {
            pill.setFrame(frame, display: true)
        }
    }

    // MARK: - Pill visibility

    private func bindPill() {
        let showPill = settings.$data.map(\.showPill).removeDuplicates()
        Publishers.CombineLatest4(timer.$state, timer.$remaining, ui.$expanded, showPill)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, _, expanded, showPill in
                guard let self else { return }
                let shouldShow = state != .idle && !expanded && showPill
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

    // MARK: - Fake notch / island

    private func layoutFakeNotch() {
        guard geometry.fakeStyle != .off else { return }
        var frame = geometry.fakeNotchFrame
        // Developer: shift sideways so it can be seen next to a real notch in screenshots.
        if let dx = ProcessInfo.processInfo.environment["NOTCHCAT_FAKE_OFFSET_X"].flatMap(Double.init) { frame.origin.x += dx }
        fakeNotch.setFrame(frame, display: true)
        (fakeNotch.contentView as? FakeNotchView)?.style = geometry.fakeStyle
    }

    private func bindFakeNotch() {
        let style = settings.$data.map(\.fakeNotch).removeDuplicates()
        // A style change re-lays everything out, because the pill and chip line up against the shape.
        style.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyGeometry() }
            .store(in: &cancellables)

        // The shape fades out as the tray's own silhouette takes over, and returns once it has retracted.
        Publishers.CombineLatest(style, ui.$expanded)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, expanded in self?.setFakeNotchVisible(!expanded) }
            .store(in: &cancellables)
    }

    private func setFakeNotchVisible(_ visible: Bool) {
        fakeGeneration += 1
        let gen = fakeGeneration
        guard geometry.fakeStyle != .off else {
            fakeNotch.orderOut(nil)
            return
        }
        if visible {
            layoutFakeNotch()
            fakeNotch.alphaValue = 0
            fakeNotch.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + (ui.expanded ? 0 : 0.28)) { [weak self] in
                guard let self, gen == self.fakeGeneration else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.16
                    self.fakeNotch.animator().alphaValue = 1
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                fakeNotch.animator().alphaValue = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, gen == self.fakeGeneration else { return }
                self.fakeNotch.orderOut(nil)
            }
        }
    }

    // MARK: - Music chip

    private func bindChip() {
        let music = MusicService.shared
        let playing = music.$nowPlaying.map { $0?.isPlaying ?? false }.removeDuplicates()
        let enabled = settings.$data.map(\.showMusicChip).removeDuplicates()
        Publishers.CombineLatest3(playing, ui.$expanded, enabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] playing, expanded, enabled in
                guard let self else { return }
                let shouldShow = playing && !expanded && enabled
                guard shouldShow != self.chipWanted || (shouldShow && !self.chip.isVisible) else { return }
                self.chipWanted = shouldShow
                self.chipGeneration += 1
                let gen = self.chipGeneration
                if shouldShow {
                    self.layoutPill(animated: true)
                    self.chipUI.shown = false
                    self.chip.orderFrontRegardless()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        guard let self, gen == self.chipGeneration else { return }
                        self.chipUI.shown = true
                    }
                } else {
                    self.chipUI.shown = false
                    self.layoutPill(animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                        guard let self, gen == self.chipGeneration else { return }
                        self.chip.orderOut(nil)
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
        guard !ui.expanded, settings.data.hoverToOpen else { return }
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
