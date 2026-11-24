import AppKit
import Sparkle

/// Updates, TypeFire style: a quiet check once a day, the update downloads in the background, then
/// the app shows a notification, a banner and a red dot, and one click installs and relaunches.
/// This is the only code in the app that uses the network (the network test enforces that).
@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    struct Available: Equatable {
        let version: String
        let notes: [String]
        /// True once the update is downloaded and one click can install it.
        var ready: Bool
    }

    @Published private(set) var available: Available?
    @Published private(set) var lastChecked: Date?
    /// Called when an update is first found, so the app can post one notification per version.
    var onFound: ((Available) -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    private static let dayInSeconds: TimeInterval = 86_400

    /// The feed address can be pointed at a local test feed with AIUSAGEMENU_FEED_URL.
    nonisolated static var feedOverride: String? { ProcessInfo.processInfo.environment["AIUSAGEMENU_FEED_URL"] }

    private func updater() -> SPUUpdater {
        if let controller { return controller.updater }
        let made = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = made
        return made.updater
    }

    /// Turns the daily check on or off. On: checks now if the last check is over a day old.
    func setAutomatic(_ enabled: Bool) {
        let updater = updater()
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        updater.updateCheckInterval = Self.dayInSeconds
        lastChecked = updater.lastUpdateCheckDate
        if enabled, Date().timeIntervalSince(updater.lastUpdateCheckDate ?? .distantPast) > Self.dayInSeconds || Self.feedOverride != nil {
            updater.checkForUpdatesInBackground()
        }
    }

    /// "Check for Updates…": Sparkle's own window, which shows the release notes and installs.
    func check() { updater().checkForUpdates() }

    /// One click: install the downloaded update, quit, replace and relaunch.
    func install() {
        if let installNow {
            installNow()
        } else {
            // Not downloaded yet (or Sparkle needs permission): its window downloads and installs.
            updater().checkForUpdates()
        }
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? { Self.feedOverride }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let found = Available(version: item.displayVersionString, notes: Self.bullets(from: item.itemDescription), ready: false)
        Task { @MainActor in
            let isNew = self.available?.version != found.version
            if isNew { self.available = found; self.onFound?(found) }
            self.lastChecked = Date()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.lastChecked = Date() }
    }

    /// Sparkle has downloaded the update and would install it at quit; we take over and let one
    /// click install it right away.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        let notes = Self.bullets(from: item.itemDescription)
        let version = item.displayVersionString
        let block = InstallBlock(run: immediateInstallationBlock)
        Task { @MainActor in
            self.installNow = block.run
            let isNew = self.available?.version != version
            self.available = Available(version: version, notes: notes, ready: true)
            if isNew { self.onFound?(self.available!) }
        }
        return true
    }

    /// Release notes arrive as HTML in the appcast. Each <li> becomes one bullet.
    nonisolated static func bullets(from html: String?) -> [String] {
        guard let html, let regex = try? NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }.map { item in
            item.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }
}

/// Sparkle calls its delegate off the main thread; this carries its install action to the main actor.
private struct InstallBlock: @unchecked Sendable { let run: () -> Void }
