import AppKit
import SwiftUI
import CoreImage

enum MusicSource: String, CaseIterable {
    case spotify, appleMusic

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var displayName: String { self == .spotify ? "Spotify" : "Music" }
    /// The name used in `tell application "..."`.
    var scriptName: String { displayName }
    var notificationName: String {
        self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
    }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

struct NowPlaying: Equatable {
    var source: MusicSource
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var isPlaying: Bool
    /// Playback position at `positionDate`; use `position(at:)` for the live value.
    var basePosition: TimeInterval
    var positionDate: Date

    var trackKey: String { "\(source.rawValue)|\(title)|\(artist)|\(album)" }

    func position(at date: Date = Date()) -> TimeInterval {
        let p = isPlaying ? basePosition + date.timeIntervalSince(positionDate) : basePosition
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Now playing from Spotify and Apple Music.
///
/// State comes from the notifications both apps broadcast (no permission needed). Controls, seeking and
/// album art use AppleScript, which makes macOS ask for Automation permission the first time.
/// Nothing runs until `setActive(true)`, and a player is never launched just to ask it a question.
@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// A soft tint taken from the artwork, for the card background.
    @Published private(set) var tint: Color?
    @Published private(set) var automationDenied = false

    private var states: [MusicSource: NowPlaying] = [:]
    private var updatedAt: [MusicSource: Date] = [:]
    private var bridge: NotificationBridge?
    private var terminateObserver: NSObjectProtocol?
    private var active = false
    private var artworkKey: String?

    /// All AppleScript runs on one serial queue; NSAppleScript is not thread-safe.
    private let scriptQueue = DispatchQueue(label: "notchcat.applescript", qos: .userInitiated)
    private static let separator = "\u{1F}"

    // MARK: - Start / stop

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on { start() } else { stop() }
    }

    private func start() {
        let bridge = NotificationBridge { [weak self] source, info in
            MainActor.assumeIsolated { self?.handle(info, from: source) }
        }
        for source in MusicSource.allCases {
            DistributedNotificationCenter.default().addObserver(
                bridge, selector: #selector(NotificationBridge.received(_:)),
                name: NSNotification.Name(source.notificationName), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
        self.bridge = bridge

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let source = MusicSource.allCases.first(where: { $0.bundleID == id }) else { return }
                self.states[source] = nil
                self.publish()
            }
        }

        // Pick up whatever is already playing.
        for source in MusicSource.allCases where source.isRunning { query(source) }
    }

    private func stop() {
        if let bridge { DistributedNotificationCenter.default().removeObserver(bridge) }
        bridge = nil
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        terminateObserver = nil
        states = [:]
        updatedAt = [:]
        publish()
    }

    // MARK: - Notifications from the players

    /// Parses the userInfo Spotify and Music broadcast. Internal so it can be tested with a fake notification.
    func handle(_ info: [AnyHashable: Any], from source: MusicSource) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" || state.isEmpty {
            states[source] = nil
            publish()
            return
        }
        let title = info["Name"] as? String ?? ""
        guard !title.isEmpty else { return }

        let rawDuration = (info["Duration"] ?? info["Total Time"]) as? NSNumber
        let duration = (rawDuration?.doubleValue ?? 0) / 1000            // both report milliseconds
        let reported = (info["Playback Position"] as? NSNumber)?.doubleValue

        var next = NowPlaying(source: source, title: title,
                              artist: info["Artist"] as? String ?? "",
                              album: info["Album"] as? String ?? "",
                              duration: duration, isPlaying: state == "playing",
                              basePosition: reported ?? 0, positionDate: Date())

        // Same track and no new position: keep counting from where we were.
        if reported == nil, let old = states[source], old.trackKey == next.trackKey {
            next.basePosition = old.position()
        }
        states[source] = next
        updatedAt[source] = Date()
        publish()

        // Music doesn't include the position; ask once so the progress bar starts in the right place.
        if reported == nil, source == .appleMusic || next.basePosition == 0 { query(source) }
    }

    /// The player that is playing, otherwise the one that changed most recently.
    private func publish() {
        let playing = states.values.filter(\.isPlaying)
        let chosen = playing.max { (updatedAt[$0.source] ?? .distantPast) < (updatedAt[$1.source] ?? .distantPast) }
            ?? states.values.max { (updatedAt[$0.source] ?? .distantPast) < (updatedAt[$1.source] ?? .distantPast) }

        let trackChanged = chosen?.trackKey != nowPlaying?.trackKey
        if chosen != nowPlaying { nowPlaying = chosen }

        if let chosen {
            if trackChanged || artworkKey != chosen.trackKey { loadArtwork(for: chosen) }
        } else {
            artwork = nil
            tint = nil
            artworkKey = nil
        }
    }

    // MARK: - Controls

    func togglePlayPause() { control("playpause", optimistic: { $0.isPlaying.toggle() }) }
    func nextTrack() { control("next track", optimistic: nil) }
    func previousTrack() { control("previous track", optimistic: nil) }

    func seek(toFraction fraction: Double) {
        guard let np = nowPlaying, np.duration > 0 else { return }
        let seconds = Int((np.duration * min(max(fraction, 0), 1)).rounded())
        var updated = np
        updated.basePosition = TimeInterval(seconds)
        updated.positionDate = Date()
        states[np.source] = updated
        publish()
        run(np.source, "set player position to \(seconds)")
    }

    func open(_ source: MusicSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func control(_ command: String, optimistic: ((inout NowPlaying) -> Void)?) {
        guard let np = nowPlaying else { return }
        if let optimistic {
            var updated = np
            updated.basePosition = np.position()
            updated.positionDate = Date()
            optimistic(&updated)
            states[np.source] = updated
            publish()
        }
        run(np.source, command)
    }

    /// Sends one command to a player, but only if it is already running (never launches it).
    private func run(_ source: MusicSource, _ command: String) {
        guard source.isRunning else { return }
        let script = "with timeout of 3 seconds\ntell application \"\(source.scriptName)\" to \(command)\nend timeout"
        execute(script) { [weak self] result in
            if case .failure(let error) = result, error.code == -1743 { self?.automationDenied = true }
            else if case .success = result { self?.automationDenied = false }
        }
    }

    // MARK: - Reading state with AppleScript

    private func query(_ source: MusicSource) {
        guard source.isRunning else { return }
        let d = "ASCII character 31"
        let body: String
        switch source {
        case .spotify:
            body = """
            if player state is stopped then return "stopped"
            return (player state as text) & \(d) & (name of current track) & \(d) & (artist of current track) & \(d) & (album of current track) & \(d) & ((duration of current track) as text) & \(d) & ((player position) as text)
            """
        case .appleMusic:
            body = """
            if player state is stopped then return "stopped"
            return (player state as text) & \(d) & (name of current track) & \(d) & (artist of current track) & \(d) & (album of current track) & \(d) & (((duration of current track) * 1000) as text) & \(d) & ((player position) as text)
            """
        }
        let script = "with timeout of 3 seconds\ntell application \"\(source.scriptName)\"\n\(body)\nend tell\nend timeout"
        execute(script) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if error.code == -1743 { self.automationDenied = true }
            case .success(let descriptor):
                self.automationDenied = false
                self.apply(queryResult: descriptor.stringValue ?? "", from: source)
            }
        }
    }

    private func apply(queryResult text: String, from source: MusicSource) {
        if text == "stopped" { states[source] = nil; publish(); return }
        let parts = text.components(separatedBy: Self.separator)
        guard parts.count >= 6, !parts[1].isEmpty else { return }
        // AppleScript formats numbers with the user's decimal separator.
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

        let next = NowPlaying(source: source, title: parts[1], artist: parts[2], album: parts[3],
                              duration: number(parts[4]) / 1000, isPlaying: parts[0].lowercased() == "playing",
                              basePosition: number(parts[5]), positionDate: Date())
        states[source] = next
        updatedAt[source] = updatedAt[source] ?? Date()
        publish()
    }

    // MARK: - Artwork

    private func loadArtwork(for np: NowPlaying) {
        artworkKey = np.trackKey
        let key = np.trackKey
        switch np.source {
        case .spotify:
            guard np.source.isRunning else { return }
            execute("with timeout of 3 seconds\ntell application \"Spotify\" to return artwork url of current track\nend timeout") { [weak self] result in
                guard case .success(let d) = result, let s = d.stringValue, let url = URL(string: s) else { return }
                Task {
                    guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return }
                    await MainActor.run { self?.setArtwork(image, forKey: key) }
                }
            }
        case .appleMusic:
            guard np.source.isRunning else { return }
            let script = """
            with timeout of 3 seconds
            tell application "Music"
                try
                    return data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            end timeout
            """
            execute(script) { [weak self] result in
                guard case .success(let d) = result, d.data.count > 200, let image = NSImage(data: d.data) else { return }
                self?.setArtwork(image, forKey: key)
            }
        }
    }

    func setArtwork(_ image: NSImage, forKey key: String) {
        guard key == nowPlaying?.trackKey else { return }   // the track changed while it loaded
        artwork = image
        tint = Self.pastelTint(of: image)
    }

    private static let ciContext = CIContext()

    /// Average color of the image, softened toward white so dark ink stays readable on it.
    static func pastelTint(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let mix = 0.58
        func soften(_ v: UInt8) -> Double { Double(v) / 255 * (1 - mix) + mix }
        return Color(red: soften(px[0]), green: soften(px[1]), blue: soften(px[2]))
    }

    // MARK: - AppleScript runner

    struct ScriptError: Error {
        let code: Int
        let message: String
    }

    private func execute(_ source: String,
                         completion: @escaping @MainActor (Result<NSAppleEventDescriptor, ScriptError>) -> Void) {
        // Test-only: never send Apple events (so a test can't pop a permission prompt or touch a real player).
        if ProcessInfo.processInfo.environment["NOTCHCAT_NO_APPLESCRIPT"] != nil, source.contains("tell application") {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(.failure(ScriptError(code: -1, message: "disabled for tests"))) }
            }
            return
        }
        scriptQueue.async {
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            let outcome: Result<NSAppleEventDescriptor, ScriptError>
            if let result {
                outcome = .success(result)
            } else {
                let code = (errorInfo?[NSAppleScript.errorNumber] as? Int) ?? -1
                let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"
                outcome = .failure(ScriptError(code: code, message: message))
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(outcome) } }
        }
    }

    /// Runs a script with no target app. Used by the self-test to confirm the queue works.
    func runPlainScript(_ source: String, completion: @escaping @MainActor (String) -> Void) {
        execute(source) { result in
            switch result {
            case .success(let d): completion(d.stringValue ?? "(no string)")
            case .failure(let e): completion("error \(e.code): \(e.message)")
            }
        }
    }
}

/// Objective-C target for DistributedNotificationCenter, which needs a selector to set suspension behavior.
final class NotificationBridge: NSObject {
    private let handler: (MusicSource, [AnyHashable: Any]) -> Void

    init(handler: @escaping (MusicSource, [AnyHashable: Any]) -> Void) {
        self.handler = handler
    }

    @objc func received(_ note: Notification) {
        guard let source = MusicSource.allCases.first(where: { $0.notificationName == note.name.rawValue }) else { return }
        handler(source, note.userInfo ?? [:])
    }
}
