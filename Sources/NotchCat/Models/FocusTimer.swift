import Foundation
import AppKit
import Combine

/// The pomodoro / focus countdown. Single source of truth for the card and the notch pill.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer(defaultMinutes: AppSettings.shared.data.defaultFocusMinutes)

    enum State: Equatable {
        case idle        // ready, nothing started
        case running
        case paused
        case finished    // hit 00:00, waiting to be dismissed or extended
    }

    @Published private(set) var state: State = .idle
    /// Whole seconds left, rounded up so the display reads 25:00 on start.
    @Published private(set) var remaining: Int
    /// Length of the current/next session in seconds (used for progress).
    @Published private(set) var sessionTotal: Int
    /// Task this session is attached to, if started from a task.
    @Published private(set) var linkedTaskID: UUID?

    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private var pausedBySleep = false

    /// Called when a session ends (finished or abandoned) so Insights can count it.
    var sessionLogger: ((FocusSession) -> Void)?
    private var sessionStartedAt: Date?
    private var activeAccumulated: TimeInterval = 0
    private var lastResumeAt: Date?

    init(defaultMinutes: Int = 25) {
        let secs = defaultMinutes * 60
        remaining = secs
        sessionTotal = secs
        observeSleep()
    }

    var isActive: Bool { state != .idle }

    var progress: Double {
        guard sessionTotal > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remaining) / Double(sessionTotal)))
    }

    // MARK: - Controls

    /// Starts a fresh session. Pass `minutes` to override the prepared duration.
    func start(minutes: Int? = nil, taskID: UUID? = nil) {
        // Starting over a live session (e.g. Focus on another task) closes the old one first.
        if state == .running || state == .paused { endTracking(completed: false) }
        if let minutes {
            sessionTotal = max(1, minutes) * 60
            remaining = sessionTotal
        } else if state == .idle || state == .finished {
            remaining = sessionTotal
        }
        linkedTaskID = taskID
        pausedRemaining = TimeInterval(remaining)
        endDate = Date().addingTimeInterval(pausedRemaining)
        state = .running
        beginTracking()
        startTicker()
    }

    /// Developer helper: a session of arbitrary length in seconds.
    func startDemo(seconds: Int) {
        reset()
        sessionTotal = seconds
        remaining = seconds
        start()
    }

    func toggle() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: break
        }
    }

    func pause() {
        guard state == .running, let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        accumulateActive()
        state = .paused
        stopTicker()
    }

    func resume() {
        guard state == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        state = .running
        lastResumeAt = Date()
        startTicker()
    }

    /// Back to Ready with the current session length.
    func reset() {
        endTracking(completed: false)
        stopTicker()
        endDate = nil
        linkedTaskID = nil
        pausedBySleep = false
        remaining = sessionTotal
        pausedRemaining = TimeInterval(sessionTotal)
        state = .idle
    }

    /// Changes the prepared duration. Stops any session in progress.
    func setDuration(minutes: Int) {
        let clamped = min(max(minutes, 1), 240)
        reset()
        sessionTotal = clamped * 60
        remaining = sessionTotal
        pausedRemaining = TimeInterval(sessionTotal)
    }

    /// "+ Add 5 min". Works while running, paused, or after time is up.
    func addTime(seconds: Int) {
        switch state {
        case .running:
            endDate = endDate?.addingTimeInterval(TimeInterval(seconds))
            sessionTotal += seconds
            tick()
        case .paused:
            pausedRemaining += TimeInterval(seconds)
            sessionTotal += seconds
            remaining = Int(ceil(pausedRemaining))
        case .finished:
            sessionTotal = seconds
            remaining = seconds
            pausedRemaining = TimeInterval(seconds)
            endDate = Date().addingTimeInterval(pausedRemaining)
            state = .running
            beginTracking()
            startTicker()
        case .idle:
            sessionTotal += seconds
            remaining = sessionTotal
            pausedRemaining = TimeInterval(sessionTotal)
        }
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state == .running, let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        let whole = max(0, Int(ceil(left)))
        if whole != remaining { remaining = whole }
        if left <= 0 { finish() }
    }

    private func finish() {
        stopTicker()
        endDate = nil
        remaining = 0
        pausedRemaining = 0
        endTracking(completed: true)
        state = .finished
        if AppSettings.shared.data.timerSound { NSSound(named: NSSound.Name("Glass"))?.play() }
    }

    // MARK: - Session tracking (counts only time the timer was really running)

    private func beginTracking() {
        sessionStartedAt = Date()
        activeAccumulated = 0
        lastResumeAt = Date()
    }

    private func accumulateActive() {
        if let resumed = lastResumeAt { activeAccumulated += Date().timeIntervalSince(resumed) }
        lastResumeAt = nil
    }

    /// Logs the session if one is in progress. Very short abandoned sessions are ignored.
    private func endTracking(completed: Bool) {
        guard let started = sessionStartedAt else { return }
        accumulateActive()
        let seconds = Int(activeAccumulated.rounded())
        sessionStartedAt = nil
        activeAccumulated = 0
        guard completed || seconds >= 30 else { return }
        sessionLogger?(FocusSession(taskID: linkedTaskID, startedAt: started, activeSeconds: seconds,
                                    plannedSeconds: sessionTotal, completed: completed))
    }

    /// Call on quit so a running session is not lost.
    func flushForQuit() {
        if state == .running || state == .paused { endTracking(completed: false) }
    }

    // MARK: - Sleep handling (timers pause while the Mac sleeps)

    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                self.pause()
                self.pausedBySleep = true
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pausedBySleep else { return }
                self.pausedBySleep = false
                self.resume()
            }
        }
    }
}

extension Int {
    /// 1500 -> "25:00". Minutes keep growing past 99 rather than wrapping.
    var clockString: String {
        let m = self / 60, s = self % 60
        return String(format: "%02d:%02d", m, s)
    }
}
