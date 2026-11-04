import Foundation
import AppKit

/// Looks for a newer NotchCat on GitHub Releases and says so. It never downloads or installs anything:
/// the button just opens the releases page, where the DMG is.
///
/// The only request made is a GET to the public GitHub API for the latest release, at launch and then every
/// few hours. It can be switched off in Settings.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var available: Release?

    private static let repo = "shimijallores/notchcat"
    private static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    private var timer: Timer?

    /// The version this copy was built as. Unset when run from `swift run`, which turns the check off.
    var currentVersion: String? {
        let env = ProcessInfo.processInfo.environment
        return env["NOTCHCAT_VERSION"] ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func start() {
        guard timer == nil, currentVersion != nil else { return }
        let delay = ProcessInfo.processInfo.environment["NOTCHCAT_UPDATE_URL"] == nil ? 8.0 : 0.2   // tests do not wait
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in Task { await self?.check() } }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    /// Fetches the latest release and updates `available`. Failures are silent: no network just means no badge.
    func check() async {
        guard AppSettings.shared.data.checkForUpdates, let current = currentVersion else {
            available = nil
            return
        }
        // NOTCHCAT_UPDATE_URL lets tests point at a local file instead of GitHub.
        let source = ProcessInfo.processInfo.environment["NOTCHCAT_UPDATE_URL"]
            .flatMap(URL.init(string:)) ?? URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: source, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchCat/\(current)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return }
        available = Self.release(from: data, newerThan: current)
    }

    func openReleasePage() {
        NSWorkspace.shared.open(available?.url ?? Self.releasesPage)
    }

    // MARK: - Parsing

    /// The latest release if it is newer than `current`. Drafts and pre-releases never count.
    static func release(from data: Data, newerThan current: String) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              isNewer(tag, than: current) else { return nil }
        // Only ever open a page of this project, whatever the response says.
        var url = releasesPage
        if let text = object["html_url"] as? String, let candidate = URL(string: text),
           candidate.scheme == "https", candidate.host == "github.com",
           candidate.path.lowercased().hasPrefix("/\(repo)/releases") {
            url = candidate
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url)
    }

    /// Compares dotted version numbers ("v1.0.10" is newer than "1.0.9"). Anything unparseable is not newer.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let a = parts(remote), let b = parts(local) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // "1.0.4-beta" counts as 1.0.4
        text = String(text.prefix { $0.isNumber || $0 == "." })
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        return numbers.compactMap { $0 }
    }
}
